import CoreLocation
import Foundation

final class NativeLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var requests: [Int: Bool] = [:]
    var reply: ((Int, [String: Any]) -> Void)?
    private var deadline: DispatchWorkItem?
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters }
    func request(id: Int, watch: Bool) {
        guard requests.count < 16 else { respond(id, error: "Too many location requests.", code: 2); return }
        requests[id] = watch
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: start()
        default: stop(message: "Location permission was denied.", code: 1)
        }
    }
    func clear(_ id: Int) { requests.removeValue(forKey: id); if requests.isEmpty { manager.stopUpdatingLocation(); deadline?.cancel() } }
    private func start() {
        guard !requests.isEmpty else { return }
        manager.startUpdatingLocation()
        deadline?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stop(message: "Location request timed out.", code: 3) }
        deadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }
    func stop(message: String = "Location is unavailable while this screen is inactive.", code: Int = 2) {
        manager.stopUpdatingLocation(); deadline?.cancel()
        let ids = Array(requests.keys); requests.removeAll()
        ids.forEach { respond($0, error: message, code: code) }
    }
    private func respond(_ id: Int, error: String, code: Int) { reply?(id, ["error": ["code": code, "message": error]]) }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { start() }
        else if manager.authorizationStatus != .notDetermined { stop(message: "Location permission was denied.", code: 1) }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0, abs(location.timestamp.timeIntervalSinceNow) < 30 else { return }
        deadline?.cancel()
        var coordinates: [String: Any] = ["latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude,
                                          "accuracy": location.horizontalAccuracy]
        if location.verticalAccuracy >= 0 { coordinates["altitude"] = location.altitude; coordinates["altitudeAccuracy"] = location.verticalAccuracy }
        if location.speed >= 0 { coordinates["speed"] = location.speed }
        if location.course >= 0 { coordinates["heading"] = location.course }
        for (id, watch) in Array(requests) {
            reply?(id, ["coords": coordinates, "timestamp": location.timestamp.timeIntervalSince1970 * 1000])
            if !watch { requests.removeValue(forKey: id) }
        }
        if requests.isEmpty { manager.stopUpdatingLocation() }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { stop(message: "Location could not be determined.", code: 2) }
    deinit { deadline?.cancel(); manager.stopUpdatingLocation() }
}
