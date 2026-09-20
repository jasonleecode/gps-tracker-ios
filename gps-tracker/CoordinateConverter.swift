import Foundation
import CoreLocation

// Converts between WGS-84 (raw GPS / Mapbox) and GCJ-02 ("Mars coordinates",
// used by the map tiles Apple Maps serves in mainland China). The transform is
// only valid inside China; coordinates elsewhere are returned unchanged.
enum CoordinateConverter {
    private static let earthRadius = 6378245.0
    private static let eccentricitySquared = 0.00669342162296594323

    static func isInChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        (72.004...137.8347).contains(coordinate.longitude)
            && (0.8293...55.8271).contains(coordinate.latitude)
    }

    static func wgs84ToGcj02(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInChina(coordinate) else { return coordinate }
        let offset = self.offset(for: coordinate)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + offset.latitude,
            longitude: coordinate.longitude + offset.longitude
        )
    }

    // No closed-form inverse exists; one fixed-point iteration of the forward
    // transform gets back within ~1 m, which is far below GPS noise.
    static func gcj02ToWgs84(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInChina(coordinate) else { return coordinate }
        let shifted = wgs84ToGcj02(coordinate)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude * 2 - shifted.latitude,
            longitude: coordinate.longitude * 2 - shifted.longitude
        )
    }

    private static func offset(for coordinate: CLLocationCoordinate2D) -> (latitude: Double, longitude: Double) {
        let dLat = transformLat(x: coordinate.longitude - 105.0, y: coordinate.latitude - 35.0)
        let dLon = transformLon(x: coordinate.longitude - 105.0, y: coordinate.latitude - 35.0)
        let radLat = coordinate.latitude / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - eccentricitySquared * magic * magic
        let sqrtMagic = sqrt(magic)
        let latOffset = (dLat * 180.0) / ((earthRadius * (1 - eccentricitySquared)) / (magic * sqrtMagic) * .pi)
        let lonOffset = (dLon * 180.0) / (earthRadius / sqrtMagic * cos(radLat) * .pi)
        return (latOffset, lonOffset)
    }

    private static func transformLat(x: Double, y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * .pi) + 320.0 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLon(x: Double, y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }
}
