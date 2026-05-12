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
    @Published var authorizationStatus: CLAuthorizationStatus?
    @Published var path: [CLLocation] = []
    @Published var pois: [PointOfInterest] = []
    @Published var isRecording: Bool = false
    @Published var totalDistance: Double = 0 // in meters
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
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
        
        self.location = location
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
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        self.authorizationStatus = status
    }
    
    func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
    }
}
