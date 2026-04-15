import Foundation
import CoreLocation

@MainActor
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authContinuation: CheckedContinuation<Void, Never>?

    func requestOneShotLocation() async throws -> CLLocation {
        if CLLocationManager.locationServicesEnabled() == false {
            throw CLError(.locationUnknown)
        }

        manager.delegate = self

        // Wait for authorization if not yet determined. requestLocation()
        // fails immediately when called before the user responds to the
        // permission prompt — this was the root cause of weather never loading.
        let status = manager.authorizationStatus
        if status == .notDetermined {
            await withCheckedContinuation { continuation in
                self.authContinuation = continuation
                self.manager.requestWhenInUseAuthorization()
            }
        }

        let currentStatus = manager.authorizationStatus
        guard currentStatus == .authorizedWhenInUse || currentStatus == .authorizedAlways else {
            throw CLError(.denied)
        }

        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            self.manager.requestLocation()

            // 10-second timeout — prevents indefinite hang when location
            // services are slow or silently failing (e.g. poor GPS indoors).
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                if let pending = self?.locationContinuation {
                    self?.locationContinuation = nil
                    pending.resume(throwing: CLError(.locationUnknown))
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            locationContinuation?.resume(throwing: CLError(.locationUnknown))
            locationContinuation = nil
            return
        }
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Fires after the user responds to the permission prompt (or if
        // status was already determined). Resume the auth waiter if one exists.
        if manager.authorizationStatus != .notDetermined {
            authContinuation?.resume()
            authContinuation = nil
        }
    }
}
