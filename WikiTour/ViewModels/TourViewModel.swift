import Foundation
import CoreLocation
import Observation

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
    var routeCoordinates: [CLLocationCoordinate2D] = []
    var userLocation: CLLocationCoordinate2D?
    var locationName: String = ""
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

    // MARK: - Tour building

    @MainActor
    private func buildTour(from location: CLLocation) async {
        phase = .geocoding
        statusMessage = "Finding your location…"
        error = nil

        // Reverse-geocode to get city / county / state.
        // county + state are optional — NRHP source requires them (US only);
        // geosearch works without them everywhere.
        var county: String?
        var state: String?

        if let placemark = try? await reverseGeocode(location: location) {
            county = placemark.subAdministrativeArea
            state  = placemark.administrativeArea

            // Build the display name: prefer "City, State", fall back to "County, State"
            // or just "State", or just coordinates.
            if let city = placemark.locality, let st = state {
                locationName = "\(city), \(st)"
            } else if let co = county, let st = state {
                locationName = "\(co), \(st)"
            } else if let st = state {
                locationName = st
            } else if let country = placemark.country {
                locationName = country
            }
        }

        phase = .loading
        statusMessage = county != nil
            ? "Finding historic landmarks in \(county!)…"
            : "Finding historic and cultural sites nearby…"

        do {
            let results = try await WikipediaService.shared.findLandmarks(
                near: location.coordinate,
                county: county,
                state: state,
                progress: { [weak self] msg in
                    Task { @MainActor [weak self] in self?.statusMessage = msg }
                }
            )

            landmarks = results
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
