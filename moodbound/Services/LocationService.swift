import Foundation
import CoreLocation

@MainActor
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    func requestOneShotLocation() async throws -> CLLocation {
        if CLLocationManager.locationServicesEnabled() == false {
            throw CLError(.locationUnknown)
        }

        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.manager.requestLocation()

            // 10-second timeout — prevents indefinite hang when location
            // services are slow or silently failing (e.g. poor GPS indoors).
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                if let pending = self?.continuation {
                    self?.continuation = nil
                    pending.resume(throwing: CLError(.locationUnknown))
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            continuation?.resume(throwing: CLError(.locationUnknown))
            continuation = nil
            return
        }
        continuation?.resume(returning: location)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
