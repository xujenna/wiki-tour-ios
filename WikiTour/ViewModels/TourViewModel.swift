import Foundation
import CoreLocation
import Observation

@Observable
final class TourViewModel: NSObject, CLLocationManagerDelegate {

    // MARK: - Published state

    var landmarks: [Landmark] = []
    var userLocation: CLLocationCoordinate2D?
    var isLoading = false
    var error: String?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var searchRadius: Int = 1000

    // MARK: - Private

    private let locationManager = CLLocationManager()
    private var lastFetchLocation: CLLocation?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Public API

    func start() {
        authorizationStatus = locationManager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        default:
            error = "Location access denied. Please enable in Settings > WikiTour."
        }
    }

    func refresh() {
        guard let location = locationManager.location else { return }
        lastFetchLocation = nil
        Task { await loadLandmarks(from: location) }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            error = "Location access denied. Please enable in Settings > WikiTour."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLocation = location.coordinate

        // Re-fetch only after moving more than 200 m from the last fetch point.
        if let last = lastFetchLocation, location.distance(from: last) < 200 { return }
        lastFetchLocation = location

        Task { await loadLandmarks(from: location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.error = "Location error: \(error.localizedDescription)"
    }

    // MARK: - Data loading

    @MainActor
    private func loadLandmarks(from location: CLLocation) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            var results = try await WikipediaService.shared.nearbyLandmarks(
                at: location.coordinate,
                radius: searchRadius
            )
            // Attach walking distances and sort nearest-first.
            for i in results.indices {
                let dest = CLLocation(latitude: results[i].lat, longitude: results[i].lon)
                results[i].distance = location.distance(from: dest)
            }
            results.sort { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
            landmarks = results
        } catch {
            self.error = error.localizedDescription
        }
    }
}
