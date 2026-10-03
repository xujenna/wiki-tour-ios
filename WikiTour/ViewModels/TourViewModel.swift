import Foundation
import CoreLocation
import MapKit
import Observation

@MainActor
@Observable
final class TourViewModel: NSObject, @preconcurrency CLLocationManagerDelegate {
    enum Phase { case idle, locating, loading, done }
    enum TravelMode: String, Codable { case walking, driving }
    var phase: Phase = .idle
    var landmarks: [Landmark] = []
    private(set) var savedLandmarks: [Landmark] = []
    /// True while the draft is still the untouched suggestion built from discovery results.
    private(set) var draftIsSuggested = false
    /// Suggested tours drive between stops when too few places are within walking distance.
    private(set) var draftMode: TravelMode = .walking
    /// After "Keep going", the stops stay in the order walked instead of being re-optimized.
    private var startsInRouteOrder = false
    private var openWalkMode: TravelMode?
    var travelMode: TravelMode { openWalkMode ?? draftMode }
    /// Incremented when the map should zoom to show a whole suggested tour.
    private(set) var routeFitRevision = 0
    private(set) var savedWalks: [SavedWalk] = []
    private(set) var activeSavedWalkID: UUID?
    private var unsavedWalkName: String?
    var activeSavedWalk: SavedWalk? { savedWalks.first { $0.id == activeSavedWalkID } }
    var userLocation: CLLocationCoordinate2D?
    var searchCenter = CLLocationCoordinate2D(latitude: 40.666, longitude: -73.984)
    var locationName = "Explore nearby"
    var statusMessage = "Finding your location…"
    var error: String?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var routeStops: [Landmark] = []
    private(set) var routeLines: [MKPolyline] = []
    private(set) var routeDistance: CLLocationDistance = 0
    private(set) var routeDuration: TimeInterval = 0
    private(set) var isRouting = false
    /// True while "Keep going" finds and routes more stops.
    private(set) var isExtending = false
    /// Set when "Keep going" finds nothing more to add.
    private(set) var extendMessage: String?
    private(set) var routeError: String?
    var currentStopIndex = 0
    var cameraRevision = 0
    private(set) var articleDescriptions: [String: String] = [:]

    private let locationManager = CLLocationManager()
    private let defaults: UserDefaults
    private let routeProvider: ((CLLocationCoordinate2D, CLLocationCoordinate2D) async throws -> WalkingLeg)?
    private var discoveryTask: Task<Void, Never>?
    private var routeTask: Task<Void, Never>?
    private var activeDirections: MKDirections?
    /// Directions already fetched, by mode and endpoints. Apple allows an app about 50 directions
    /// requests a minute, so editing a long tour must only request the legs that changed.
    private var legCache: [String: WalkingLeg] = [:]
    private var discoveryID = UUID()
    private var routeID = UUID()
    private var started = false
    private var usesPreviewData = false
    private let savedKey = "savedLandmarks.v1"
    private let suggestedKey = "savedLandmarksSuggested.v1"
    private let modeKey = "routeMode.v1"
    private let routeOrderKey = "routeOrderFixed.v1"
    nonisolated static let suggestedStopLimit = 10
    /// A suggested walk stays within this much walking time, measured from the user to the last stop.
    nonisolated static let walkingTimeLimit: TimeInterval = 75 * 60
    /// At least `minimumWalkableStops` places must be this close on foot, or the tour drives instead.
    nonisolated static let walkableReach: TimeInterval = 20 * 60
    nonisolated static let minimumWalkableStops = 2

    init(defaults: UserDefaults = .standard,
         routeProvider: ((CLLocationCoordinate2D, CLLocationCoordinate2D) async throws -> WalkingLeg)? = nil) {
        self.routeProvider = routeProvider
        self.defaults = defaults
        super.init()
        if let data = defaults.data(forKey: savedKey),
           let saved = try? JSONDecoder().decode([Landmark].self, from: data) {
            savedLandmarks = saved
            draftIsSuggested = defaults.bool(forKey: suggestedKey)
            draftMode = defaults.string(forKey: modeKey).flatMap(TravelMode.init) ?? .walking
            startsInRouteOrder = defaults.bool(forKey: routeOrderKey)
        }
        if let data = defaults.data(forKey: "savedWalks.v1"),
           let walks = try? JSONDecoder().decode([SavedWalk].self, from: data) { savedWalks = walks }
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isBusy: Bool { phase == .locating || phase == .loading }
    var currentStop: Landmark? {
        routeStops.indices.contains(currentStopIndex) ? routeStops[currentStopIndex] : nil
    }
    var mapSavedIDs: Set<String> {
        Set((savedLandmarks + routeStops + (activeSavedWalk?.stops ?? [])).map(\.id))
    }
    var mapLandmarks: [Landmark] {
        var seen = Set<String>()
        return (landmarks + savedLandmarks + routeStops + (activeSavedWalk?.stops ?? []))
            .filter { seen.insert($0.id).inserted }
    }
    var routeSummary: String {
        let count = unsavedWalkName != nil ? routeStops.count : (activeSavedWalk?.stops.count ?? savedLandmarks.count)
        let stops = "\(count) \(count == 1 ? "stop" : "stops")"
        if isRouting { return "\(stops) • Finding a walk…" }
        if routeError != nil { return "\(stops) • Route unavailable" }
        if routeStops.isEmpty { return "\(stops) saved" }
        if routeLines.isEmpty { return "\(stops) • Start here" }
        let distance = String(format: "%.1f mi", routeDistance / 1609.34)
        let minutes = "\(max(1, Int(ceil(routeDuration / 60)))) min" + (travelMode == .driving ? " drive" : "")
        return "\(stops) • \(distance) • \(minutes)"
    }

    func start() {
        guard !started else { return }
        started = true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview"),
           ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            usesPreviewData = true
            landmarks = Landmark.previews
            userLocation = Landmark.previewOrigin
            searchCenter = .init(latitude: 40.6655, longitude: -73.984)
            locationName = "Park Slope, Brooklyn"
            phase = .done
            cameraRevision += 1
            if ProcessInfo.processInfo.arguments.contains("--saved-preview") {
                for landmark in Landmark.previews.prefix(2) where !isSaved(landmark) { toggleSaved(landmark) }
            }
            if !savedLandmarks.isEmpty { prepareRoute() }
            return
        }
        #endif
        locate()
        if !savedLandmarks.isEmpty { prepareRoute() }
    }

    func locate() {
        authorizationStatus = locationManager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            phase = .locating
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            phase = .locating
            statusMessage = "Finding your location…"
            error = nil
            locationManager.requestLocation()
        default:
            phase = .done
            error = "Location is off. Move the map and search this area, or enable location in Settings."
        }
    }

    /// `refreshesSuggestion` is true only for searches driven by a new device location, so panning and
    /// tapping "Search this area" never swap out the walk the user is looking at.
    func search(near coordinate: CLLocationCoordinate2D, refreshesSuggestion: Bool = false) {
        discoveryTask?.cancel()
        let requestID = UUID()
        discoveryID = requestID
        searchCenter = coordinate
        phase = .loading
        error = nil
        statusMessage = "Finding historic and cultural places…"
        discoveryTask = Task {
            do {
                let results = try await WikipediaService.shared.findLandmarks(near: coordinate)
                guard !Task.isCancelled, discoveryID == requestID else { return }
                landmarks = withUserDistances(results)
                let origin = userLocation ?? coordinate
                if !suggestWalk(from: landmarks, near: origin, replacingSuggestion: refreshesSuggestion) {
                    // Too little within walking distance: look across the full 6-mile range and drive.
                    statusMessage = "Few places within walking distance. Looking farther away…"
                    let wider = try await WikipediaService.shared.findLandmarks(near: coordinate, radius: WikipediaService.maximumRadius)
                    guard !Task.isCancelled, discoveryID == requestID else { return }
                    landmarks = withUserDistances(wider)
                    suggestDrive(from: landmarks, near: origin, replacingSuggestion: refreshesSuggestion)
                }
                phase = .done
                statusMessage = landmarks.isEmpty ? "No places found here. Try a different area." : "Tap a place to discover its story."
                let geocoder = CLGeocoder()
                let placemark = try? await geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)).first
                guard !Task.isCancelled, discoveryID == requestID else { return }
                locationName = placemark?.subLocality ?? placemark?.locality ?? "Around this area"
            } catch {
                guard !Task.isCancelled, discoveryID == requestID else { return }
                self.error = "Couldn't load nearby places. Check your connection and try again."
                phase = .done
            }
        }
    }

    private func withUserDistances(_ results: [Landmark]) -> [Landmark] {
        results.map { landmark in
            var copy = landmark
            copy.distance = userLocation.map { Self.distance($0, landmark.coordinate) }
            return copy
        }
    }

    func loadDescription(for landmark: Landmark) async throws {
        guard articleDescriptions[landmark.id] == nil else { return }
        if usesPreviewData {
            articleDescriptions[landmark.id] = landmark.description
            return
        }
        let text = try await WikipediaService.shared.introduction(for: landmark.title)
        try Task.checkCancellation()
        // Never replace an existing summary with a shorter or empty extract.
        articleDescriptions[landmark.id] = text.count > landmark.description.count ? text : landmark.description
    }

    func isSaved(_ landmark: Landmark) -> Bool { savedLandmarks.contains { $0.id == landmark.id } }

    /// Matches the web app: nearby places become a tour as soon as they load, without any taps.
    /// An existing tour is kept unless it is an untouched suggestion and the user's location changed.
    /// A draft the user has edited, or an open saved walk, is never replaced.
    private func canSuggest(replacingSuggestion: Bool) -> Bool {
        guard activeSavedWalkID == nil, unsavedWalkName == nil else { return false }
        return savedLandmarks.isEmpty || (draftIsSuggested && replacingSuggestion)
    }

    /// Suggests a walk. Returns false only when a suggestion is allowed but too few places are within
    /// walking distance, so the caller should search farther and call `suggestDrive`.
    @discardableResult
    func suggestWalk(from candidates: [Landmark], near origin: CLLocationCoordinate2D,
                     replacingSuggestion: Bool = false) -> Bool {
        guard canSuggest(replacingSuggestion: replacingSuggestion) else { return true }
        guard let stops = Self.walkingStops(from: candidates, near: origin) else { return false }
        applySuggestion(stops, mode: .walking)
        return true
    }

    func suggestDrive(from candidates: [Landmark], near origin: CLLocationCoordinate2D, replacingSuggestion: Bool = false) {
        guard canSuggest(replacingSuggestion: replacingSuggestion) else { return }
        applySuggestion(Self.drivingStops(from: candidates, near: origin), mode: .driving)
    }

    private func applySuggestion(_ stops: [Landmark], mode: TravelMode) {
        guard !stops.isEmpty, stops.map(\.id) != savedLandmarks.map(\.id) || mode != draftMode else { return }
        savedLandmarks = stops
        draftIsSuggested = true
        draftMode = mode
        startsInRouteOrder = false
        persistSaved()
        prepareRoute()
        routeFitRevision += 1
    }

    /// Up to ten stops within a 75-minute walk, or nil when fewer than two places are within a 20-minute walk.
    static func walkingStops(from candidates: [Landmark], near origin: CLLocationCoordinate2D) -> [Landmark]? {
        let unique = deduplicated(candidates)
        let walkable = unique.filter { estimatedTime(origin, $0.coordinate, .walking) <= walkableReach }
        guard walkable.count >= minimumWalkableStops else { return nil }
        return plannedStops(unique, from: origin, mode: .walking, budget: walkingTimeLimit)
    }

    /// Up to ten stops within 6 miles of the user, the widest area Wikipedia's nearby search covers.
    static func drivingStops(from candidates: [Landmark], near origin: CLLocationCoordinate2D) -> [Landmark] {
        let reachable = deduplicated(candidates).filter { distance(origin, $0.coordinate) <= WikipediaService.maximumRadius }
        return plannedStops(reachable, from: origin, mode: .driving, budget: .infinity)
    }

    /// Greedy tour: from the current point, go to the nearest next stop that keeps the estimated total
    /// within budget. All places are treated alike. The chosen stops are then put in a route order
    /// that does not double back.
    static func plannedStops(_ candidates: [Landmark], from origin: CLLocationCoordinate2D, mode: TravelMode,
                             budget: TimeInterval, limit: Int = suggestedStopLimit) -> [Landmark] {
        var remaining = candidates
        var stops: [Landmark] = []
        var current = origin
        var total: TimeInterval = 0
        while stops.count < limit {
            let feasible = remaining.filter { total + estimatedTime(current, $0.coordinate, mode) <= budget }
            let here = current
            guard let next = feasible.min(by: { distance(here, $0.coordinate) < distance(here, $1.coordinate) }) else { break }
            total += estimatedTime(current, next.coordinate, mode)
            stops.append(next)
            current = next.coordinate
            remaining.removeAll { $0.id == next.id }
        }
        return orderedStops(stops, from: origin)
    }

    /// Straight-line estimate with a street-grid detour factor. Real directions replace it once loaded.
    static func estimatedTime(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ mode: TravelMode) -> TimeInterval {
        let metersPerSecond = mode == .walking ? 1.35 : 8.0 // About 3 mph on foot, 18 mph in town.
        return distance(a, b) * 1.3 / metersPerSecond
    }

    private static func deduplicated(_ landmarks: [Landmark]) -> [Landmark] {
        var seen = Set<String>()
        return landmarks.filter { seen.insert($0.id).inserted }
    }

    func toggleSaved(_ landmark: Landmark) {
        unsavedWalkName = nil
        activeSavedWalkID = nil
        openWalkMode = nil
        draftIsSuggested = false
        startsInRouteOrder = false
        if savedLandmarks.isEmpty { draftMode = .walking } // A tour built by hand starts as a walk.
        if isSaved(landmark) { savedLandmarks.removeAll { $0.id == landmark.id } }
        else { savedLandmarks.append(landmark) }
        persistSaved()
        prepareRoute()
    }

    private func persistSaved() {
        if let data = try? JSONEncoder().encode(savedLandmarks) { defaults.set(data, forKey: savedKey) }
        defaults.set(draftIsSuggested, forKey: suggestedKey)
        defaults.set(draftMode.rawValue, forKey: modeKey)
        defaults.set(startsInRouteOrder, forKey: routeOrderKey)
    }

    func clearCurrentRoute() {
        unsavedWalkName = nil
        activeSavedWalkID = nil
        openWalkMode = nil
        savedLandmarks = []
        draftIsSuggested = false
        draftMode = .walking
        startsInRouteOrder = false
        defaults.removeObject(forKey: savedKey)
        defaults.removeObject(forKey: suggestedKey)
        defaults.removeObject(forKey: modeKey)
        defaults.removeObject(forKey: routeOrderKey)
        // Reuse the route reset to cancel pending directions and invalidate stale results.
        prepareRoute()
    }

    func prepareRoute() {
        guard activeSavedWalkID == nil, unsavedWalkName == nil else { return }
        routeTask?.cancel()
        activeDirections?.cancel()
        let requestID = UUID()
        routeID = requestID
        routeStops = []
        routeLines = []
        routeError = nil
        extendMessage = nil
        routeDistance = 0
        routeDuration = 0
        currentStopIndex = 0
        isRouting = !savedLandmarks.isEmpty
        guard !savedLandmarks.isEmpty else { return }
        let origin = userLocation ?? savedLandmarks[0].coordinate
        let ordered = startsInRouteOrder ? savedLandmarks : Self.orderedStops(savedLandmarks, from: origin)
        let mode = draftMode
        // Only a suggested walk is shortened; places the user picked are always kept.
        let trimsToLimit = draftIsSuggested && mode == .walking
        routeTask = Task {
            // A short debounce avoids sending a directions request for every rapid bookmark tap.
            do {
                try await Task.sleep(for: .milliseconds(350))
                var source = origin
                var legs: [WalkingLeg?] = []
                for stop in ordered {
                    try Task.checkCancellation()
                    legs.append(Self.distance(source, stop.coordinate) > 5
                                ? try await cachedLeg(from: source, to: stop.coordinate, mode: mode) : nil)
                    source = stop.coordinate
                }
                guard !Task.isCancelled, routeID == requestID else { return }
                var kept = ordered.count
                // Estimates can undercount real streets; drop final stops until the walk fits.
                while trimsToLimit, kept > 1,
                      legs.prefix(kept).compactMap({ $0 }).reduce(0, { $0 + $1.duration }) > Self.walkingTimeLimit {
                    kept -= 1
                }
                let keptLegs = legs.prefix(kept).compactMap { $0 }
                routeStops = Array(ordered.prefix(kept))
                routeLines = keptLegs.map(\.polyline)
                routeDistance = keptLegs.reduce(0) { $0 + $1.distance }
                routeDuration = keptLegs.reduce(0) { $0 + $1.duration }
                // Refit once the real roads are known; they can swing wider than the stops.
                if draftIsSuggested { routeFitRevision += 1 }
                if kept < ordered.count {
                    let keptIDs = Set(routeStops.map(\.id))
                    savedLandmarks.removeAll { !keptIDs.contains($0.id) }
                    persistSaved()
                }
                isRouting = false
                activeDirections = nil
            } catch {
                guard !Task.isCancelled, routeID == requestID else { return }
                isRouting = false
                activeDirections = nil
                routeError = "Directions couldn't be loaded. Try again when you're connected."
            }
        }
    }

    /// "Keep going" is offered on the last stop of the current draft. A saved walk is a fixed
    /// snapshot, so it still ends with Finish.
    var canKeepGoing: Bool {
        activeSavedWalkID == nil && unsavedWalkName == nil && !routeStops.isEmpty && !isRouting
    }

    /// Adds more stops after the last one, using the same rules as a new tour started from there,
    /// then moves to the first new stop. Places already on the map are used first; if fewer than
    /// three fit, the area around the last stop is searched. Only the new legs need directions.
    func keepGoing() {
        guard canKeepGoing, !isExtending, let last = routeStops.last else { return }
        let requestID = routeID
        let mode = travelMode
        isExtending = true
        extendMessage = nil
        Task {
            defer { isExtending = false }
            do {
                var additions = moreStops(after: last, mode: mode)
                if additions.count < 3 && !usesPreviewData {
                    let radius = mode == .walking ? WikipediaService.walkingRadius : WikipediaService.maximumRadius
                    let nearby = try await WikipediaService.shared.findLandmarks(near: last.coordinate, radius: radius)
                    guard routeID == requestID else { return }
                    let known = Set(landmarks.map(\.id))
                    landmarks += withUserDistances(nearby).filter { !known.contains($0.id) }
                    additions = moreStops(after: last, mode: mode)
                }
                guard !additions.isEmpty else {
                    extendMessage = "That's everything nearby."
                    return
                }
                var source = last.coordinate
                var legs: [WalkingLeg] = []
                for stop in additions {
                    if Self.distance(source, stop.coordinate) > 5 {
                        legs.append(try await cachedLeg(from: source, to: stop.coordinate, mode: mode))
                    }
                    source = stop.coordinate
                }
                guard routeID == requestID else { return }
                let nextIndex = routeStops.count
                routeStops += additions
                routeLines += legs.map(\.polyline)
                routeDistance += legs.reduce(0) { $0 + $1.distance }
                routeDuration += legs.reduce(0) { $0 + $1.duration }
                // Keep the route order the user is walking: save the stops in route order, and make
                // the tour the user's own so it is never trimmed or replaced by a new suggestion.
                savedLandmarks = routeStops
                draftIsSuggested = false
                startsInRouteOrder = true
                persistSaved()
                currentStopIndex = nextIndex
            } catch {
                guard routeID == requestID else { return }
                extendMessage = "Couldn't find more places. Check your connection and try again."
            }
        }
    }

    private func moreStops(after last: Landmark, mode: TravelMode) -> [Landmark] {
        let visited = Set(routeStops.map(\.id))
        let candidates = landmarks.filter { !visited.contains($0.id) }
        if mode == .walking {
            return Self.plannedStops(candidates, from: last.coordinate, mode: .walking, budget: Self.walkingTimeLimit)
        }
        return Self.drivingStops(from: candidates, near: last.coordinate)
    }

    var suggestedWalkName: String {
        if let unsavedWalkName { return unsavedWalkName }
        return ["Explore nearby", "Around this area"].contains(locationName)
            ? (routeStops.first?.title ?? "My walk") : locationName
    }

    @discardableResult
    func saveCurrentWalk(named name: String) -> SavedWalk? {
        guard !isRouting, routeError == nil, !routeStops.isEmpty else { return nil }
        if let activeSavedWalk { return activeSavedWalk }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let walk = SavedWalk(id: UUID(), name: trimmed.isEmpty ? suggestedWalkName : trimmed,
                             createdAt: Date(), stops: routeStops,
                             lines: routeLines.map { line in
                                 (0..<line.pointCount).map { index in
                                     let point = line.points()[index].coordinate
                                     return SavedWalk.Point(latitude: point.latitude, longitude: point.longitude)
                                 }
                             }, distance: routeDistance, duration: routeDuration, mode: travelMode)
        savedWalks.insert(walk, at: 0)
        activeSavedWalkID = walk.id
        unsavedWalkName = nil
        persistWalks()
        return walk
    }

    func toggleCurrentWalkSaved() {
        if let walk = activeSavedWalk {
            // Keep this route and stop index open; do not restore or overwrite the draft.
            unsavedWalkName = walk.name
            savedWalks.removeAll { $0.id == walk.id }
            activeSavedWalkID = nil
            persistWalks()
        } else {
            saveCurrentWalk(named: suggestedWalkName)
        }
    }

    func openSavedWalk(_ walk: SavedWalk) {
        guard savedWalks.contains(where: { $0.id == walk.id }) else { return }
        routeTask?.cancel()
        activeDirections?.cancel()
        routeID = UUID()
        unsavedWalkName = nil
        activeSavedWalkID = walk.id
        openWalkMode = walk.mode ?? .walking
        routeStops = walk.stops
        routeLines = walk.lines.map { points in
            let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            return MKPolyline(coordinates: coordinates, count: coordinates.count)
        }
        routeDistance = walk.distance
        routeDuration = walk.duration
        routeError = nil
        isRouting = false
        currentStopIndex = 0
    }

    func returnToDraft() {
        guard activeSavedWalkID != nil || unsavedWalkName != nil else { return }
        unsavedWalkName = nil
        activeSavedWalkID = nil
        openWalkMode = nil
        prepareRoute()
    }

    func deleteSavedWalk(_ id: UUID) {
        savedWalks.removeAll { $0.id == id }
        persistWalks()
        if activeSavedWalkID == id { returnToDraft() }
    }

    private func persistWalks() {
        if let data = try? JSONEncoder().encode(savedWalks) { defaults.set(data, forKey: "savedWalks.v1") }
    }

    /// A cached leg, or a new request. When Apple throttles requests, waits for its stated reset
    /// time and tries again instead of reporting the route as unavailable.
    private func cachedLeg(from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D,
                           mode: TravelMode) async throws -> WalkingLeg {
        let key = String(format: "%@|%.6f,%.6f|%.6f,%.6f", mode.rawValue, source.latitude, source.longitude,
                         destination.latitude, destination.longitude)
        if let leg = legCache[key] { return leg }
        while true {
            do {
                let leg = try await routeLeg(from: source, to: destination, mode: mode)
                legCache[key] = leg
                return leg
            } catch let error as NSError where error.domain == MKErrorDomain && error.code == MKError.Code.loadingThrottled.rawValue {
                try await Task.sleep(for: .seconds(Self.throttleDelay(for: error)))
            }
        }
    }

    /// Apple's error says how many seconds remain until the request window resets.
    static func throttleDelay(for error: NSError) -> Double {
        let details = error.userInfo["MKErrorGEOErrorUserInfo"] as? [String: Any]
        let seconds = (details?["timeUntilReset"] as? NSNumber)?.doubleValue ?? 10
        return max(0.2, seconds + 1)
    }

    private func routeLeg(from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D,
                          mode: TravelMode) async throws -> WalkingLeg {
        if let routeProvider { return try await routeProvider(source, destination) }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = mode == .driving ? .automobile : .walking
        let directions = MKDirections(request: request)
        activeDirections = directions
        let response = try await directions.calculate()
        guard let route = response.routes.first else { throw URLError(.badServerResponse) }
        return WalkingLeg(polyline: route.polyline, distance: route.distance, duration: route.expectedTravelTime)
    }

    /// Nearest-neighbour order, then local improvements until none helps: reverse any stretch that
    /// crosses itself (2-opt), or move a run of up to three stops elsewhere (or-opt). The route starts
    /// at `origin` and ends at the last stop.
    static func orderedStops(_ landmarks: [Landmark], from origin: CLLocationCoordinate2D) -> [Landmark] {
        var remaining = landmarks
        var route: [Landmark] = []
        var current = origin
        while let nearest = remaining.min(by: { distance(current, $0.coordinate) < distance(current, $1.coordinate) }) {
            route.append(nearest)
            current = nearest.coordinate
            remaining.removeAll { $0.id == nearest.id }
        }
        guard route.count > 2 else { return route }
        func length(_ stops: [Landmark]) -> Double {
            zip([origin] + stops.dropLast().map(\.coordinate), stops.map(\.coordinate)).reduce(0) { $0 + distance($1.0, $1.1) }
        }
        var best = length(route)
        var improved = true
        while improved {
            improved = false
            var candidates: [[Landmark]] = []
            for i in 0..<(route.count - 1) {
                for k in (i + 1)..<route.count {
                    var reversed = route
                    reversed[i...k].reverse()
                    candidates.append(reversed)
                }
            }
            for run in 1...min(3, route.count - 1) {
                for i in 0...(route.count - run) {
                    let segment = Array(route[i..<(i + run)])
                    var rest = route
                    rest.removeSubrange(i..<(i + run))
                    for j in 0...rest.count where j != i {
                        for piece in [segment, segment.reversed()] {
                            var moved = rest
                            moved.insert(contentsOf: piece, at: j)
                            candidates.append(moved)
                        }
                    }
                }
            }
            if let shorter = candidates.min(by: { length($0) < length($1) }), length(shorter) + 0.5 < best {
                route = shorter
                best = length(shorter)
                improved = true
            }
        }
        return route
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        guard started, !usesPreviewData else { return }
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            locate()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            phase = .done
            error = "Location is off. You can still move the map and search this area."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLocation = location.coordinate
        searchCenter = location.coordinate
        cameraRevision += 1
        search(near: location.coordinate, refreshesSuggestion: true)
        if !savedLandmarks.isEmpty { prepareRoute() }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        phase = .done
        self.error = "Couldn't find your location. Try again, or move the map and search this area."
    }
}

struct WalkingLeg {
    let polyline: MKPolyline
    let distance: CLLocationDistance
    let duration: TimeInterval
}

/// A walk is a snapshot: its ordered stops and walking route survive draft edits and relaunches.
struct SavedWalk: Codable, Identifiable {
    struct Point: Codable { let latitude: Double; let longitude: Double }
    let id: UUID
    let name: String
    let createdAt: Date
    let stops: [Landmark]
    let lines: [[Point]]
    let distance: Double
    let duration: TimeInterval
    /// Missing on walks saved before driving tours existed, which were all walks.
    var mode: TourViewModel.TravelMode? = nil

    var cover: Landmark? { stops.first { $0.imageURL != nil || $0.previewImage != nil } ?? stops.first }
}
