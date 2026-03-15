import Foundation
import CoreLocation
import Observation

/// Mirrors the end-to-end flow of the original wiki-tour web app:
///   getLocation() → geocodeLatLng() → getWikiPage() → sortData() → getWayPts() → initMap()
@Observable
final class TourViewModel: NSObject, CLLocationManagerDelegate {

    // MARK: - State

    enum Phase: Equatable {
        case idle
        case locating
        case geocoding
        case loading
        case done
    }

    var phase: Phase = .idle
    var landmarks: [Landmark] = []
    var routeCoordinates: [CLLocationCoordinate2D] = []   // straight-line path for map polyline
    var userLocation: CLLocationCoordinate2D?
    var locationName: String = ""                          // "City, State" for the UI header
    var statusMessage: String = ""
    var error: String?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    // MARK: - Private

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Public API

    /// Called on app appear — requests permission then fires a one-shot location fix.
    func start() {
        authorizationStatus = locationManager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            beginTour()
        default:
            error = "Location access denied. Please enable in Settings > WikiTour."
        }
    }

    func refresh() {
        landmarks = []
        routeCoordinates = []
        locationName = ""
        error = nil
        beginTour()
    }

    // MARK: - Private tour flow

    private func beginTour() {
        phase = .locating
        statusMessage = "Getting your location…"
        // One-shot fix, same as navigator.geolocation.getCurrentPosition() in the original.
        locationManager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if phase == .idle { beginTour() }
        case .denied, .restricted:
            phase = .done
            error = "Location access denied. Please enable in Settings > WikiTour."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLocation = location.coordinate
        Task { await buildTour(from: location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.error = "Couldn't get your location: \(error.localizedDescription)"
        phase = .done
    }

    // MARK: - Tour building (geocodeLatLng → getWikiPage → sortData → getWayPts)

    @MainActor
    private func buildTour(from location: CLLocation) async {
        phase = .geocoding
        statusMessage = "Finding your county…"
        error = nil

        do {
            let placemark = try await reverseGeocode(location: location)

            guard let county = placemark.subAdministrativeArea,
                  let state  = placemark.administrativeArea
            else {
                error = "Couldn't determine your county. Try moving to a different spot and refreshing."
                phase = .done
                return
            }

            // Mirror grandReveal() — show the city/county name immediately.
            locationName = placemark.locality.map { "\($0), \(state)" }
                        ?? "\(county), \(state)"

            phase = .loading
            statusMessage = "Finding historical landmarks in \(county)…"

            let results = try await WikipediaService.shared.findLandmarks(
                near: location.coordinate,
                county: county,
                state: state,
                progress: { [weak self] msg in
                    Task { @MainActor [weak self] in self?.statusMessage = msg }
                }
            )

            landmarks = results
            // Build a straight-line polyline: user → stop 1 → stop 2 → … → stop 10
            if let userLoc = userLocation {
                routeCoordinates = [userLoc] + results.map(\.coordinate)
            }
            phase = .done
            statusMessage = results.isEmpty ? "No landmarks found nearby." : "Have fun!"

        } catch {
            self.error = "Couldn't load landmarks: \(error.localizedDescription)"
            phase = .done
        }
    }

    // MARK: - CLGeocoder wrapper (mirrors Google Maps Geocoder in the original)

    private func reverseGeocode(location: CLLocation) async throws -> CLPlacemark {
        try await withCheckedThrowingContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let placemark = placemarks?.first {
                    continuation.resume(returning: placemark)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "WikiTour", code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "No placemark returned"]))
                }
            }
        }
    }
}
