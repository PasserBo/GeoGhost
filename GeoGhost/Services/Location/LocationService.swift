import CoreLocation
import Foundation
import Observation

/// Single-shot-ish location + heading for tagging captures. Only runs while the capture screen is visible.
@Observable
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var latest: CLLocation?
    private(set) var heading: CLHeading?

    private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 5
    }

    var isAuthorized: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    func requestIfNeeded() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    func start() {
        requestIfNeeded()
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    /// A fix good enough to attach to a photo: fresh (≤ 15 s) and reasonably accurate.
    var usableFix: CLLocation? {
        guard let latest, latest.horizontalAccuracy >= 0, latest.horizontalAccuracy <= 100,
              Date().timeIntervalSince(latest.timestamp) < 15 else { return nil }
        return latest
    }

    func metadataSnapshot(at date: Date = Date()) -> CaptureMetadata {
        var m = CaptureMetadata()
        m.capturedAt = date
        if let fix = usableFix {
            m.latitude = fix.coordinate.latitude
            m.longitude = fix.coordinate.longitude
            m.horizontalAccuracy = fix.horizontalAccuracy
            m.altitude = fix.verticalAccuracy >= 0 ? fix.altitude : nil
            m.locationSource = .device
        }
        if let heading, heading.headingAccuracy >= 0 { m.heading = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading }
        return m
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.isAuthorized { self.start() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        nonisolated(unsafe) let fix = last
        Task { @MainActor in self.latest = fix }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        nonisolated(unsafe) let h = newHeading
        Task { @MainActor in self.heading = h }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
