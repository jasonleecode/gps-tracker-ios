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

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    @Published var location: CLLocation?
    @Published var heading: CLHeading?
    @Published var authorizationStatus: CLAuthorizationStatus?
    @Published var path: [CLLocation] = []
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

    // Writes the GPX to a temp file named with the current date and time.
    // Memoized on the data signature so view re-renders don't rewrite the file.
    func exportAsGPXFile() -> URL? {
        if let lastExportURL, let sig = lastExportSignature,
           sig.pathCount == path.count, sig.poiCount == pois.count,
           FileManager.default.fileExists(atPath: lastExportURL.path) {
            return lastExportURL
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let url = URL.temporaryDirectory.appendingPathComponent("Track_\(formatter.string(from: Date())).gpx")

        do {
            try exportAsGPX().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        lastExportSignature = (path.count, pois.count)
        lastExportURL = url
        return url
    }

    func exportAsGPX() -> String {
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="GPS Tracker iOS" xmlns="http://www.topografix.com/GPX/1/1">
        """
        
        let dateFormatter = ISO8601DateFormatter()
        
        // Export Waypoints (POIs)
        for poi in pois {
            gpx += """
          <wpt lat="\(poi.coordinate.latitude)" lon="\(poi.coordinate.longitude)">
            <ele>\(poi.altitude)</ele>
            <time>\(dateFormatter.string(from: poi.timestamp))</time>
            <name>\(poi.name)</name>
          </wpt>
        """
        }
        
        // Export Track
        gpx += """
          <trk>
            <name>Tracked Path</name>
            <trkseg>
        """
        
        for loc in path {
            let lat = loc.coordinate.latitude
            let lon = loc.coordinate.longitude
            let ele = loc.altitude
            let time = dateFormatter.string(from: loc.timestamp)
            let speed = loc.speed > 0 ? loc.speed : 0
            
            gpx += """
              <trkpt lat="\(lat)" lon="\(lon)">
                <ele>\(ele)</ele>
                <time>\(time)</time>
                <extensions>
                  <speed>\(speed)</speed>
                </extensions>
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
