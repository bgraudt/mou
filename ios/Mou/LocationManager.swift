import SwiftUI
import CoreLocation

/// Обёртка над CLLocationManager: разрешение + текущая позиция.
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var authorized = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Запросить разрешение и обновить позицию.
    func requestAndLocate() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: authorized = false
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            let s = m.authorizationStatus
            authorized = (s == .authorizedWhenInUse || s == .authorizedAlways)
            if authorized { m.requestLocation() }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let c = locs.last?.coordinate else { return }
        Task { @MainActor in self.coordinate = c }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}
}
