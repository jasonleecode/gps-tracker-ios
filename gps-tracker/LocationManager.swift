import Foundation
import CoreLocation
import Combine

struct PointOfInterest: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let name: String
    let timestamp: Date
    let altitude: Double
}

// A run of consecutive track points with similar speed, drawn as one
// polyline. speedFraction is 0 for the slowest and 1 for the fastest
// speed in the current track. Coordinates are pre-converted to GCJ-02
// (the tile system Apple Maps uses in China), ready for display.
struct TrackSegment {
    var coordinates: [CLLocationCoordinate2D]
    var speedFraction: Double
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    @Published var location: CLLocation?
    @Published var heading: CLHeading?
    @Published var authorizationStatus: CLAuthorizationStatus?
    @Published var path: [CLLocation] = [] {
        didSet { rebuildTrackSegments() }
    }
    @Published var trackSegments: [TrackSegment] = []
    @Published var pois: [PointOfInterest] = []
    @Published var isRecording: Bool = false
    @Published var totalDistance: Double = 0 // in meters
    @Published var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy

    // Direction of travel in degrees from north: GPS course while moving, compass heading when stationary
    var movementDirection: Double? {
        if let location, location.speed > 1, location.course >= 0 {
            return location.course
        }
        if let heading {
            if heading.trueHeading >= 0 { return heading.trueHeading }
            if heading.magneticHeading >= 0 { return heading.magneticHeading }
        }
        return nil
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    func toggleRecording() {
        isRecording.toggle()
    }
    
    func addPOI() {
        guard let currentLoc = location else { return }
        let newPOI = PointOfInterest(
            coordinate: currentLoc.coordinate,
            name: "POI \(pois.count + 1)",
            timestamp: Date(),
            altitude: currentLoc.altitude
        )
        pois.append(newPOI)
    }
    
    func clearAll() {
        path = []
        pois = []
        totalDistance = 0
        isRecording = false
    }

    // Rebuilds the speed-colored segments shown on the map. Consecutive points
    // with similar speed are merged into one polyline to keep the polyline
    // count (and map rendering cost) low. Speed is normalized against the
    // current track's own min/max so the full red→blue range is always used.
    private func rebuildTrackSegments() {
        guard path.count > 1 else {
            trackSegments = []
            return
        }
        let speeds = path.map { max($0.speed, 0) }
        let minSpeed = speeds.min() ?? 0
        let maxSpeed = speeds.max() ?? 0
        let range = maxSpeed - minSpeed

        let bucketCount = 20.0
        var segments: [TrackSegment] = []
        var lastBucket = -1.0

        for i in 0..<(path.count - 1) {
            let speed = (speeds[i] + speeds[i + 1]) / 2
            let fraction = range > 0.1 ? (speed - minSpeed) / range : 0.5
            let bucket = (fraction * bucketCount).rounded() / bucketCount

            let next = CoordinateConverter.wgs84ToGcj02(path[i + 1].coordinate)
            if bucket == lastBucket, !segments.isEmpty {
                segments[segments.count - 1].coordinates.append(next)
            } else {
                let start = CoordinateConverter.wgs84ToGcj02(path[i].coordinate)
                segments.append(TrackSegment(coordinates: [start, next], speedFraction: bucket))
                lastBucket = bucket
            }
        }
        trackSegments = segments
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Reject stale cached fixes — CoreLocation delivers a cached location
        // immediately on start, which can be minutes old and kilometers off.
        let age = -location.timestamp.timeIntervalSinceNow
        guard age < 5 else { return }

        // Always show the freshest valid fix so the map never looks dead,
        // even while GPS is still warming up (indoors, cold start).
        guard location.horizontalAccuracy >= 0 else { return }
        self.location = location

        // Recording is stricter: skip very coarse fixes (cell tower / Wi-Fi
        // triangulation can be hundreds of meters off while GPS warms up),
        // otherwise the track starts with a long jump from a wrong point.
        guard location.horizontalAccuracy <= 50 else { return }

        if isRecording {
            if let lastLocation = path.last {
                let distance = location.distance(from: lastLocation)
                // Filter out small jitters/noise
                if distance > 2 {
                    totalDistance += distance
                    self.path.append(location)
                }
            } else {
                self.path.append(location)
            }
        }
    }
    
    private var lastExportSignature: (pathCount: Int, poiCount: Int)?
    private var lastExportURL: URL?

    // Writes the GPX to a temp file named like "track 2025-08-17 104411.gpx".
    // Memoized on the data signature so view re-renders don't rewrite the file.
    func exportAsGPXFile() -> URL? {
        if let lastExportURL, let sig = lastExportSignature,
           sig.pathCount == path.count, sig.poiCount == pois.count,
           FileManager.default.fileExists(atPath: lastExportURL.path) {
            return lastExportURL
        }

        let url = URL.temporaryDirectory.appendingPathComponent("\(trackName()).gpx")

        do {
            try exportAsGPX().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        lastExportSignature = (path.count, pois.count)
        lastExportURL = url
        return url
    }

    private func trackName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return "track \(formatter.string(from: Date()))"
    }

    // GPX 1.1 in the shape produced by Open GPX Tracker / gpx.studio:
    // metadata with the track name, waypoints with ele/time/name/desc,
    // and a track whose points carry only ele and time.
    func exportAsGPX() -> String {
        let name = trackName()

        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="GPS Tracker iOS" xmlns="http://www.topografix.com/GPX/1/1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
          <metadata>
            <name>\(name)</name>
          </metadata>

        """

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Export Waypoints (POIs)
        for poi in pois {
            gpx += """
          <wpt lat="\(poi.coordinate.latitude)" lon="\(poi.coordinate.longitude)">
            <ele>\(poi.altitude)</ele>
            <time>\(dateFormatter.string(from: poi.timestamp))</time>
            <name>\(poi.name)</name>
            <desc>\(poi.name)</desc>
          </wpt>

        """
        }

        // Export Track
        gpx += """
          <trk>
            <name>\(name)</name>
            <trkseg>

        """

        for loc in path {
            let lat = loc.coordinate.latitude
            let lon = loc.coordinate.longitude
            let ele = loc.altitude
            let time = dateFormatter.string(from: loc.timestamp)

            gpx += """
              <trkpt lat="\(lat)" lon="\(lon)">
                <ele>\(ele)</ele>
                <time>\(time)</time>
              </trkpt>

            """
        }

        gpx += """
            </trkseg>
          </trk>
        </gpx>
        """
        return gpx
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        self.authorizationStatus = status
        self.accuracyAuthorization = manager.accuracyAuthorization
        if status == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        }
    }

    // Asks the user to turn on Precise Location if they granted only reduced
    // accuracy (reduced accuracy is ~1–2 km, which looks "定位不准").
    func requestTemporaryFullAccuracy() {
        guard locationManager.accuracyAuthorization == .reducedAccuracy else { return }
        locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "Tracking") { [weak self] _ in
            DispatchQueue.main.async {
                self?.accuracyAuthorization = self?.locationManager.accuracyAuthorization ?? .reducedAccuracy
            }
        }
    }
    
    func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
    }
}
