import XCTest
import MapKit
@testable import WikiTour

@MainActor
final class WikiTourTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "WikiTourTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testEmojiClassificationUsesNameThenDescription() {
        let cases = [("Park Slope Armory", "", "🏰"),
                     ("Park Slope Jewish Center", "", "🕍"),
                     ("Public School 39", "", "🏫"),
                     ("Prospect Park", "", "🌲"),
                     ("Green-Wood Cemetery", "", "🪦"),
                     ("Grand Prospect Hall", "", "💒"),
                     ("Al-Aqsa", "Mosque in Jerusalem", "🕌"),
                     ("The Met", "Art museum in New York City", "🏛️"),
                     ("Park Slope Food Coop", "Food cooperative in Brooklyn", "🛒"),
                     ("Community Bookstore", "Bookstore in Park Slope, Brooklyn", "📚"),
                     ("Park Slope Co-op", "Food co-op in New York City", "🛒"),
                     ("Community", "Bookstore in Park Slope", "📚"),
                     ("Park Slope", "", "🏛️"),
                     ("Park Avenue", "Street in New York City", "🏙️"),
                     ("Forest Hills Association", "Organization in Forest Hills", "🏛️"),
                     ("Community Center", "Community organization in Park Slope", "🏛️"),
                     ("Spark Center", "", "🏛️"),
                     ("Unknown", "", "🏛️")]
        for (title, category, emoji) in cases {
            let place = Landmark(title: title, coordinate: .init(), description: "", categoryDescription: category)
            XCTAssertEqual(place.emoji, emoji, title)
        }
        // Wikidata types classify places whose descriptions only say where they are.
        let typed = [("Saint-Sulpice, Paris", "building in Paris, France (1646-)", ["church building"], "⛪️"),
                     ("Mibu-dera", "building in Nakagyo-ku, Kyoto Prefecture, Japan", ["Buddhist temple"], "🛕"),
                     ("Hôtel de Vendôme", "hôtel particulier", ["private mansion"], "🏠"),
                     ("Fontaine Saint-Michel", "fountain in Paris, France", ["fountain"], "⛲"),
                     ("Palacio de Bellas Artes", "cultural centre in Mexico City", ["arts center", "concert hall", "opera house"], "🎭"),
                     ("Terazije", "square in Belgrade, Serbia", ["square"], "🏙️"),
                     ("Hotel Moskva", "building in Belgrade", ["hotel"], "🏨"),
                     ("Maruyama Park", "park in Kyoto city, Japan", ["urban park"], "🌲"),
                     ("BIGZ building", "protected cultural monuments in Serbia", ["building"], "🏛️"),
                     ("Customs Office", "", ["office building"], "🏢")]
        for (title, category, types, emoji) in typed {
            let place = Landmark(title: title, coordinate: .init(), description: "", categoryDescription: category, placeTypes: types)
            XCTAssertEqual(place.emoji, emoji, title)
        }
        // Generic words in names are not place types.
        XCTAssertEqual(Landmark(title: "Market Street Bank", coordinate: .init(), description: "").emoji, "🏛️")
        // Every emoji the rules can return has a bundled image.
        for emoji in ["⛲", "🗿", "🏨", "🍽️", "🛍️", "🏢", "🏺", "🏙️", "🏥", "🏠", "🌲", "🏛️"] {
            let name = "Emoji-" + emoji.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-")
            XCTAssertNotNil(UIImage(named: name, in: Bundle(for: TourViewModel.self), with: nil), name)
        }
    }

    func testStationsAreExcludedByWikidataTypeInAnyLanguage() {
        XCTAssertTrue(WikipediaService.isExcludedDesignatedPlace(description: "Paris Métro station", types: ["underground station"]))
        XCTAssertTrue(WikipediaService.isExcludedDesignatedPlace(description: "station of the Paris Métro", types: ["metro station"]))
        XCTAssertTrue(WikipediaService.isExcludedDesignatedPlace(description: "railway station", types: ["S-Bahn station"]))
        XCTAssertTrue(WikipediaService.isExcludedDesignatedPlace(description: "", types: ["neighborhood"]))
        XCTAssertFalse(WikipediaService.isExcludedDesignatedPlace(description: "fire station in Brooklyn", types: ["fire station"]))
        XCTAssertFalse(WikipediaService.isExcludedDesignatedPlace(description: "building in Paris, France", types: ["church building"]))
    }

    func testSavedPlacesSurviveRelaunchAndRefreshIdentity() throws {
        let model = TourViewModel(defaults: defaults)
        let place = Landmark.previews[0]
        model.toggleSaved(place)
        let restored = TourViewModel(defaults: defaults)
        let refreshed = Landmark(title: place.title, coordinate: place.coordinate, description: "Updated summary")
        XCTAssertTrue(restored.isSaved(refreshed))
        XCTAssertEqual(restored.savedLandmarks.first?.latitude, place.latitude)
        XCTAssertEqual(restored.savedLandmarks.first?.description, place.description)
        restored.toggleSaved(refreshed)
        XCTAssertTrue(TourViewModel(defaults: defaults).savedLandmarks.isEmpty)
        model.toggleSaved(place) // Cancel the pending directions request.
    }

    func testNearestNeighbourVisitsEveryStopExactlyOnce() {
        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let stops = [3.0, 1, 2].map { longitude in
            Landmark(title: "Stop \(longitude)", coordinate: .init(latitude: 0, longitude: longitude), description: "")
        }
        let ordered = TourViewModel.orderedStops(stops, from: origin)
        XCTAssertEqual(ordered.map(\.longitude), [1, 2, 3])
        // Nearest-neighbour alone would go east to 1, then west to -2, then back east to 3.
        let zigzag = [1.0, -2, 3].map { Landmark(title: "Zig \($0)", coordinate: .init(latitude: 0, longitude: $0), description: "") }
        XCTAssertEqual(TourViewModel.orderedStops(zigzag, from: origin).map(\.longitude), [-2, 1, 3])
        let shuffled = (0..<8).map { Landmark(title: "Line \($0)", coordinate: .init(latitude: 0, longitude: Double([5, 2, 7, 1, 8, 3, 6, 4][$0])), description: "") }
        XCTAssertEqual(TourViewModel.orderedStops(shuffled, from: origin).map(\.longitude), [1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(Set(ordered.map(\.id)).count, stops.count)
        XCTAssertTrue(TourViewModel.orderedStops([], from: origin).isEmpty)
    }

    /// Places due east of the origin, `meters` apart, so walking estimates are easy to reason about.
    private func placesEast(_ count: Int, spacing meters: Double, designated: Set<Int> = [], prefix: String = "Place") -> [Landmark] {
        (0..<count).map { index in
            Landmark(title: "\(prefix) \(index)", coordinate: .init(latitude: 0, longitude: Double(index + 1) * meters / 111_320),
                     description: "", designation: designated.contains(index) ? "National Register of Historic Places" : nil)
        }
    }

    func testSuggestedWalkUsesUpToTenNearbyPlacesAndYieldsToUserEdits() async throws {
        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let candidates = placesEast(15, spacing: 111)
            + [Landmark(title: "Place 0", coordinate: .init(latitude: 0, longitude: 0.5), description: "duplicate")]
        let suggested = try XCTUnwrap(TourViewModel.walkingStops(from: candidates, near: origin))
        XCTAssertEqual(suggested.map(\.title), (0..<10).map { "Place \($0)" })
        XCTAssertEqual(Set(suggested.map(\.id)).count, suggested.count)
        XCTAssertNil(TourViewModel.walkingStops(from: [], near: origin))

        let model = TourViewModel(defaults: defaults) { from, to in
            WalkingLeg(polyline: MKPolyline(coordinates: [from, to], count: 2), distance: 100, duration: 120)
        }
        model.userLocation = origin
        XCTAssertTrue(model.suggestWalk(from: candidates, near: origin))
        XCTAssertTrue(model.draftIsSuggested)
        XCTAssertEqual(model.travelMode, .walking)
        XCTAssertEqual(model.savedLandmarks.map(\.id), suggested.map(\.id))
        XCTAssertTrue(model.isRouting, "Directions must start without waiting for a tap")
        try await waitForRoute(model)
        XCTAssertEqual(model.routeStops.count, 10)
        XCTAssertEqual(model.routeLines.count, 10)
        XCTAssertTrue(model.routeSummary.hasPrefix("10 stops"))
        XCTAssertFalse(model.routeSummary.contains("drive"))
        XCTAssertTrue(TourViewModel(defaults: defaults).draftIsSuggested, "The suggestion flag survives relaunch")

        // Searching another area keeps the current walk; a new location replaces an untouched suggestion.
        let fewer = Array(candidates.prefix(3))
        model.suggestWalk(from: fewer, near: origin)
        XCTAssertEqual(model.savedLandmarks.count, 10, "Search this area must not swap out the walk")
        model.suggestWalk(from: candidates, near: origin, replacingSuggestion: true)
        XCTAssertFalse(model.isRouting, "An identical suggestion must not reload directions")
        model.suggestWalk(from: fewer, near: origin, replacingSuggestion: true)
        XCTAssertEqual(model.savedLandmarks.count, 3)
        model.toggleSaved(candidates[0])
        XCTAssertFalse(model.draftIsSuggested)
        XCTAssertEqual(model.savedLandmarks.count, 2)
        model.suggestWalk(from: candidates, near: origin, replacingSuggestion: true)
        XCTAssertEqual(model.savedLandmarks.count, 2, "User edits win over new suggestions")
        XCTAssertFalse(TourViewModel(defaults: defaults).draftIsSuggested)
        try await waitForRoute(model)

        // An open saved walk is left alone; clearing lets the next search suggest again.
        let walk = try XCTUnwrap(model.saveCurrentWalk(named: "Mine"))
        model.suggestWalk(from: candidates, near: origin)
        XCTAssertEqual(model.activeSavedWalk?.id, walk.id)
        XCTAssertEqual(model.savedLandmarks.count, 2)
        model.clearCurrentRoute()
        XCTAssertFalse(model.draftIsSuggested)
        model.suggestWalk(from: candidates, near: origin)
        XCTAssertEqual(model.savedLandmarks.count, 10)
        try await waitForRoute(model)
        XCTAssertEqual(model.suggestedWalkName, "Place 0")
    }

    func testSuggestionsFollowDistanceWithoutDoublingBack() {
        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        // Great Bend, Kansas: after two stops west of the user, continue to the next place west
        // rather than crossing back past the user, whatever each place's listing status.
        let west1 = Landmark(title: "Town 1", coordinate: .init(latitude: 0, longitude: -3000 / 111_320), description: "", designation: "NRHP")
        let west2 = Landmark(title: "Town 2", coordinate: .init(latitude: 0, longitude: -3500 / 111_320), description: "", designation: "NRHP")
        let westHouse = Landmark(title: "Town house", coordinate: .init(latitude: 0, longitude: -4500 / 111_320), description: "")
        let behind = Landmark(title: "Behind", coordinate: .init(latitude: 0, longitude: 4000 / 111_320), description: "", designation: "NRHP")
        let drive = TourViewModel.plannedStops([behind, west1, west2, westHouse], from: origin, mode: .driving,
                                               budget: .infinity, limit: 3)
        XCTAssertEqual(drive.map(\.title), ["Town 1", "Town 2", "Town house"])
        // A designated place gets no head start over a nearer ordinary one.
        let walk = TourViewModel.plannedStops([behind, westHouse], from: origin, mode: .walking, budget: .infinity, limit: 1)
        XCTAssertEqual(walk.map(\.title), ["Behind"])
    }

    func testWalkStaysWithinSeventyFiveMinutesAndFallsBackToDriving() {
        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        // Each 600 m hop is estimated at nearly 10 minutes on foot, so only seven fit in 75 minutes.
        let spread = TourViewModel.walkingStops(from: placesEast(10, spacing: 600), near: origin)
        XCTAssertEqual(spread?.count, 7)
        let estimate = zip([origin] + (spread ?? []).map(\.coordinate), (spread ?? []).map(\.coordinate))
            .reduce(0) { $0 + TourViewModel.estimatedTime($1.0, $1.1, .walking) }
        XCTAssertLessThanOrEqual(estimate, TourViewModel.walkingTimeLimit)

        // Only one place within a 20-minute walk: no walk, so the caller searches farther and drives.
        let sparse = [placesEast(1, spacing: 500)[0]] + placesEast(4, spacing: 1500, prefix: "Far")
        XCTAssertNil(TourViewModel.walkingStops(from: sparse, near: origin))
        let drive = TourViewModel.drivingStops(from: sparse + placesEast(1, spacing: 12_000, prefix: "Too far"), near: origin)
        XCTAssertEqual(drive.map(\.title), ["Place 0", "Far 0", "Far 1", "Far 2", "Far 3"],
                       "Driving keeps places within 6 miles and drops the rest")
    }

    func testDrivingSuggestionPersistsModeAndClearingReturnsToWalking() async throws {
        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let model = TourViewModel(defaults: defaults) { from, to in
            WalkingLeg(polyline: MKPolyline(coordinates: [from, to], count: 2), distance: 3000, duration: 300)
        }
        model.userLocation = origin
        let far = placesEast(3, spacing: 2000)
        XCTAssertFalse(model.suggestWalk(from: far, near: origin), "Too few walkable places must ask for a drive")
        XCTAssertTrue(model.savedLandmarks.isEmpty)
        let fit = model.routeFitRevision
        model.suggestDrive(from: far, near: origin)
        XCTAssertEqual(model.travelMode, .driving)
        XCTAssertEqual(model.routeFitRevision, fit + 1, "The map zooms to show the tour")
        try await waitForRoute(model)
        XCTAssertEqual(model.routeSummary, "3 stops • 5.6 mi • 15 min drive")
        XCTAssertEqual(TourViewModel(defaults: defaults).travelMode, .driving)
        let walk = try XCTUnwrap(model.saveCurrentWalk(named: "Drive"))
        XCTAssertEqual(walk.mode, .driving)
        model.clearCurrentRoute()
        XCTAssertEqual(model.travelMode, .walking)
        model.openSavedWalk(walk)
        XCTAssertEqual(model.travelMode, .driving)
        model.returnToDraft()
        XCTAssertEqual(model.travelMode, .walking)
        model.toggleSaved(far[0])
        XCTAssertEqual(model.travelMode, .walking, "A hand-built tour is a walk")
        model.toggleSaved(far[0])
    }

    func testKeepGoingAddsStopsAfterTheLastOneAndKeepsTheirOrder() async throws {
        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let counter = RequestCounter()
        let provider: (CLLocationCoordinate2D, CLLocationCoordinate2D) async throws -> WalkingLeg = { from, to in
            _ = await counter.next()
            return WalkingLeg(polyline: MKPolyline(coordinates: [from, to], count: 2), distance: 100, duration: 60)
        }
        let model = TourViewModel(defaults: defaults, routeProvider: provider)
        model.userLocation = origin
        let places = placesEast(8, spacing: 120)
        model.suggestWalk(from: Array(places.prefix(3)), near: origin)
        try await waitForRoute(model)
        model.landmarks = places
        model.currentStopIndex = 2
        XCTAssertTrue(model.canKeepGoing)
        let before = await counter.count
        model.keepGoing()
        for _ in 0..<40 where model.isExtending || model.routeStops.count == 3 { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(model.routeStops.map(\.title), (0..<8).map { "Place \($0)" })
        XCTAssertEqual(model.currentStopIndex, 3, "The walk moves on to the first new stop")
        XCTAssertEqual(model.routeLines.count, 8)
        XCTAssertEqual(model.routeDuration, 8 * 60)
        let after = await counter.count
        XCTAssertEqual(after - before, 5, "Only the five new legs need directions")
        XCTAssertFalse(model.draftIsSuggested, "An extended tour is the user's own and is never trimmed or replaced")
        XCTAssertEqual(model.savedLandmarks.map(\.id), model.routeStops.map(\.id))
        XCTAssertTrue(model.routeSummary.hasPrefix("8 stops"))

        // After a relaunch the extended tour keeps the order it was walked in.
        let restored = TourViewModel(defaults: defaults, routeProvider: provider)
        restored.userLocation = origin
        restored.prepareRoute()
        try await waitForRoute(restored)
        XCTAssertEqual(restored.routeStops.map(\.id), model.routeStops.map(\.id))

        // A saved walk is a fixed snapshot, so it still ends with Finish.
        let walk = try XCTUnwrap(model.saveCurrentWalk(named: "Long"))
        model.openSavedWalk(walk)
        XCTAssertFalse(model.canKeepGoing)
    }

    func testSuggestedWalkDropsFinalStopsWhenRealDirectionsRunLong() async throws {
        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        // Real directions report 20 minutes a leg, far more than the estimate for these short hops.
        let model = TourViewModel(defaults: defaults) { from, to in
            WalkingLeg(polyline: MKPolyline(coordinates: [from, to], count: 2), distance: 1000, duration: 1200)
        }
        model.userLocation = origin
        model.suggestWalk(from: placesEast(6, spacing: 150), near: origin)
        try await waitForRoute(model)
        XCTAssertEqual(model.routeStops.map(\.title), ["Place 0", "Place 1", "Place 2"])
        XCTAssertEqual(model.routeDuration, 3600)
        XCTAssertEqual(model.savedLandmarks.count, 3)
        // A walk the user built is never shortened.
        model.toggleSaved(placesEast(6, spacing: 150)[3])
        try await waitForRoute(model)
        XCTAssertEqual(model.routeStops.count, 4)
        XCTAssertEqual(model.routeDuration, 4800)
    }

    func testWalkHeadingMath() {
        let origin = CLLocationCoordinate2D(latitude: 40.66, longitude: -73.98)
        XCTAssertEqual(TourMapView.bearing(from: origin, to: .init(latitude: 40.67, longitude: -73.98)), 0, accuracy: 0.01)
        XCTAssertEqual(TourMapView.bearing(from: origin, to: .init(latitude: 40.66, longitude: -73.97)), 90, accuracy: 0.1)
        XCTAssertEqual(TourMapView.bearing(from: origin, to: .init(latitude: 40.65, longitude: -73.98)), 180, accuracy: 0.01)
        XCTAssertEqual(TourMapView.bearing(from: origin, to: .init(latitude: 40.66, longitude: -73.99)), 270, accuracy: 0.1)
        // Facing east, a place 150 m east appears straight above the center of the screen.
        let ahead = Landmark(title: "Ahead", coordinate: TourMapView.coordinate(from: origin, bearing: 90, meters: 150), description: "")
        let layout = LandmarkMapLayout.place([ahead], savedIDs: [ahead.id], selectedID: nil,
                                             region: .init(center: origin, span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02)),
                                             viewport: .init(width: 400, height: 800), camera: (90, 1))
        // The marker (and its label beside it) sits on the point directly above the screen center.
        XCTAssertEqual(layout.first?.bounds.midY ?? 0, 400 - 150, accuracy: 1)
        XCTAssertTrue(layout.first?.bounds.contains(CGPoint(x: 200, y: 250)) == true)
        XCTAssertFalse(layout.first?.bounds.contains(CGPoint(x: 150, y: 250)) == true)
        let east = TourMapView.coordinate(from: origin, bearing: 90, meters: 500)
        XCTAssertEqual(TourViewModel.distance(origin, east), 500, accuracy: 2)
        XCTAssertEqual(TourMapView.bearing(from: origin, to: east), 90, accuracy: 0.1)
    }

    func testSignificanceMatchesWholeWordsAndSkipsOrdinarySchools() {
        XCTAssertTrue(WikipediaService.isSignificant(title: "Old Stone House", description: "house museum in Brooklyn"))
        XCTAssertTrue(WikipediaService.isSignificant(title: "Brooklyn Museums", description: ""))
        XCTAssertFalse(WikipediaService.isSignificant(title: "P.S. 321", description: "public elementary school in Brooklyn"))
        XCTAssertFalse(WikipediaService.isSignificant(title: "Park Slope Food Coop", description: "food cooperative in Brooklyn"))
        XCTAssertFalse(WikipediaService.isSignificant(title: "Marshall Tower", description: "office building in Manhattan"))
        XCTAssertFalse(WikipediaService.isSignificant(title: "Parkside", description: "apartment complex"))
        XCTAssertFalse(WikipediaService.isSignificant(title: "7th Avenue", description: "historic subway station"))
        XCTAssertTrue(WikipediaService.isSignificant(title: "Prospect Park", description: "urban park in Brooklyn"))
    }

    func testRouteUsesWalkingMetricsAndRemovingAllStopsClearsRoute() async throws {
        let model = TourViewModel(defaults: defaults) { from, to in
            let line = MKPolyline(coordinates: [from, to], count: 2)
            return WalkingLeg(polyline: line, distance: 800, duration: 600)
        }
        model.userLocation = Landmark.previewOrigin
        model.toggleSaved(Landmark.previews[0])
        model.toggleSaved(Landmark.previews[1])
        try await waitForRoute(model)
        XCTAssertEqual(model.routeStops.count, 2)
        XCTAssertEqual(model.routeDistance, 1600)
        XCTAssertEqual(model.routeDuration, 1200)
        XCTAssertEqual(model.routeLines.count, 2)
        XCTAssertTrue(model.routeSummary.contains("20 min"))
        model.toggleSaved(Landmark.previews[0])
        model.toggleSaved(Landmark.previews[1])
        XCTAssertTrue(model.routeStops.isEmpty)
        XCTAssertTrue(model.routeLines.isEmpty)
        XCTAssertFalse(model.isRouting)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertTrue(model.routeStops.isEmpty, "Cancelled work must not restore a stale route")
    }

    func testEditsReuseDirectionsAndThrottlingWaitsInsteadOfFailing() async throws {
        let counter = RequestCounter()
        let model = TourViewModel(defaults: defaults) { from, to in
            // Apple refuses the third request once, as when its per-minute allowance runs out.
            if await counter.next() == 3 {
                throw NSError(domain: MKErrorDomain, code: Int(MKError.Code.loadingThrottled.rawValue),
                              userInfo: ["MKErrorGEOErrorUserInfo": ["timeUntilReset": NSNumber(value: -1)]])
            }
            return WalkingLeg(polyline: MKPolyline(coordinates: [from, to], count: 2), distance: 100, duration: 60)
        }
        model.userLocation = Landmark.previewOrigin
        model.toggleSaved(Landmark.previews[0])
        model.toggleSaved(Landmark.previews[1])
        model.toggleSaved(Landmark.previews[2])
        try await waitForRoute(model)
        XCTAssertNil(model.routeError, "Throttling waits for the reset instead of failing")
        XCTAssertEqual(model.routeStops.count, 3)
        let afterFirstRoute = await counter.count
        XCTAssertEqual(afterFirstRoute, 4, "Three legs plus one retry")
        // Removing the last stop needs no new directions; every remaining leg is cached.
        let last = try XCTUnwrap(model.routeStops.last)
        model.toggleSaved(last)
        try await waitForRoute(model)
        XCTAssertEqual(model.routeStops.count, 2)
        let afterRemoval = await counter.count
        XCTAssertEqual(afterRemoval, afterFirstRoute)
        XCTAssertEqual(TourViewModel.throttleDelay(for: NSError(domain: MKErrorDomain, code: 3, userInfo: [
            "MKErrorGEOErrorUserInfo": ["timeUntilReset": NSNumber(value: 33)]])), 34)
    }

    func testRouteFailureDoesNotInventStraightLineDirections() async throws {
        let model = TourViewModel(defaults: defaults) { _, _ in throw URLError(.notConnectedToInternet) }
        model.userLocation = Landmark.previewOrigin
        model.toggleSaved(Landmark.previews[0])
        try await waitForRoute(model)
        XCTAssertNotNil(model.routeError)
        XCTAssertTrue(model.routeStops.isEmpty)
        XCTAssertTrue(model.routeLines.isEmpty)
        XCTAssertEqual(model.savedLandmarks.count, 1)
    }

    func testDiscoveryFiltersTransitAndUsesPlainTitlesAndCategories() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WikiStub.self]
        WikiStub.mode = .success
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = WikipediaService(session: session)
        let results = try await service.findLandmarks(near: .init(latitude: 40.66, longitude: -73.98))
        XCTAssertEqual(results.map(\.title), ["Old Stone House (Brooklyn)", "The Met"], "Stations are excluded from both sources")
        let listed = results[0]
        XCTAssertEqual(listed.designation, "National Register of Historic Places listed place")
        XCTAssertEqual(listed.distance, 50)
        XCTAssertEqual(listed.latitude, 40.6731)
        XCTAssertEqual(listed.categoryDescription, "house museum in Brooklyn")
        XCTAssertEqual(listed.placeTypes, ["house museum", "building"])
        XCTAssertEqual(listed.imageURL?.absoluteString, "https://commons.wikimedia.org/wiki/Special:FilePath/Old%20Stone%20House.jpg?width=1280")
        XCTAssertEqual(listed.wikipediaURL?.absoluteString, "https://en.wikipedia.org/wiki/Old_Stone_House_(Brooklyn)")
        XCTAssertTrue(listed.description.isEmpty, "The introduction loads when the card opens")
        XCTAssertEqual(WikiStub.sparqlQuery?.contains(#"wikibase:radius "3.0""#), true)
        let museum = results[1]
        XCTAssertFalse(museum.isDesignated)
        XCTAssertEqual(museum.emoji, "🏛️")
        XCTAssertEqual(museum.description, "Museum summary")
        XCTAssertEqual(museum.distance, 100)

        // Either source alone is enough; only a total outage is an error.
        WikiStub.mode = .wikidataOutage
        let articlesOnly = try await service.findLandmarks(near: .init(latitude: 40.66, longitude: -73.98), radius: 10_000)
        XCTAssertEqual(articlesOnly.map(\.title), ["The Met"])
        XCTAssertEqual(WikiStub.geosearchRadius, "10000")
    }

    func testIntroductionIncludesMultipleParagraphsAndHandlesMissingArticles() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WikiStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = WikipediaService(session: session)
        WikiStub.mode = .success
        let text = try await service.introduction(for: "House & Garden")
        XCTAssertEqual(text, "The first introduction paragraph.\n\nA second introduction paragraph with more context.")
        XCTAssertEqual(WikiStub.extractQuery?["titles"], "House & Garden")
        XCTAssertEqual(WikiStub.extractQuery?["redirects"], "1")
        XCTAssertEqual(WikiStub.extractQuery?["explaintext"], "1")
        XCTAssertEqual(WikiStub.extractQuery?["exintro"], "1", "Stop before the article sections")
        WikiStub.mode = .missingArticle
        do {
            _ = try await service.introduction(for: "Missing")
            XCTFail("A missing article should leave the existing summary available")
        } catch { XCTAssertEqual((error as? URLError)?.code, .resourceUnavailable) }
        WikiStub.mode = .summaryOutage
        do {
            _ = try await service.introduction(for: "Offline")
            XCTFail("An HTTP error should be reported for retry")
        } catch { XCTAssertEqual((error as? URLError)?.code, .badServerResponse) }
    }

    func testSummaryOutageThrowsInsteadOfReportingNoPlaces() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WikiStub.self]
        WikiStub.mode = .summaryOutage
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await WikipediaService(session: session).findLandmarks(near: .init(latitude: 40.66, longitude: -73.98))
            XCTFail("All summaries failed; this must be an error, not an empty area")
        } catch { XCTAssertEqual((error as? URLError)?.code, .badServerResponse) }
    }

    func testDenseMapLabelsDoNotOverlapAndSelectedPlaceWins() {
        let center = CLLocationCoordinate2D(latitude: 40.66, longitude: -73.98)
        let crowded = (0..<15).map { index in
            Landmark(title: "Place \(index)", coordinate: .init(latitude: 40.66 + Double(index) * 0.0002, longitude: -73.98), description: "")
        }
        let layout = LandmarkMapLayout.place(crowded, savedIDs: [], selectedID: crowded[8].id,
                                             region: .init(center: center, span: .init(latitudeDelta: 0.024, longitudeDelta: 0.018)),
                                             viewport: .init(width: 402, height: 874))
        XCTAssertEqual(layout.first?.id, crowded[8].id)
        XCTAssertEqual(layout.first?.showsTitle, true)
        XCTAssertEqual(layout.first?.anchor, .init(x: 30.0 / 188.0, y: 72.0 / 77.0))
        XCTAssertEqual(layout.first?.bounds.height, 77)
        XCTAssertEqual(Set(layout.map(\.id)), Set(crowded.map(\.id)))
        XCTAssertTrue(layout.contains(where: \.isDot))
        let fullMarkers = layout.filter { !$0.isDot }
        for (index, item) in fullMarkers.enumerated() {
            XCTAssertFalse(fullMarkers.dropFirst(index + 1).contains { item.bounds.intersects($0.bounds) })
        }
        let dot = layout.first(where: \.isDot)!
        XCTAssertEqual(dot.bounds.width, 10)
        XCTAssertEqual(dot.anchor, .center)
        let selected = LandmarkMapLayout.place(crowded, savedIDs: [], selectedID: dot.id,
                                               region: .init(center: center, span: .init(latitudeDelta: 0.024, longitudeDelta: 0.018)),
                                               viewport: .init(width: 402, height: 874))
        XCTAssertEqual(selected.first?.id, dot.id)
        XCTAssertEqual(selected.first?.markerSize, 60)
    }

    func testCrowdedSavedMarkersCannotBeHiddenByCollisionFiltering() {
        let center = CLLocationCoordinate2D(latitude: 40.66, longitude: -73.98)
        let saved = (0..<4).map { index in
            Landmark(title: "Saved \(index)", coordinate: .init(latitude: center.latitude + Double(index) * 0.00001,
                                                               longitude: center.longitude), description: "")
        }
        let unsaved = Landmark(title: "Unsaved competing place", coordinate: center, description: "")
        let layout = LandmarkMapLayout.place([unsaved] + saved, savedIDs: Set(saved.map(\.id)), selectedID: nil,
                                             region: .init(center: center, span: .init(latitudeDelta: 0.024, longitudeDelta: 0.018)),
                                             viewport: .init(width: 402, height: 874))
        XCTAssertEqual(Set(layout.filter { !$0.isDot }.map(\.id)), Set(saved.map(\.id)))
        XCTAssertEqual(layout.first(where: { $0.id == unsaved.id })?.isDot, true)
        XCTAssertTrue(layout.allSatisfy { !$0.showsTitle }, "Hide competing labels, never saved markers")
    }

    func testSavedWalkSnapshotSurvivesRelaunchAndDoesNotReplaceDraft() async throws {
        let provider: (CLLocationCoordinate2D, CLLocationCoordinate2D) async throws -> WalkingLeg = { from, to in
            WalkingLeg(polyline: MKPolyline(coordinates: [from, to], count: 2), distance: 800, duration: 600)
        }
        let model = TourViewModel(defaults: defaults, routeProvider: provider)
        XCTAssertNil(model.saveCurrentWalk(named: "Empty"))
        model.userLocation = Landmark.previewOrigin
        model.toggleSaved(Landmark.previews[1])
        model.toggleSaved(Landmark.previews[0])
        try await waitForRoute(model)
        let order = model.routeStops.map(\.id)
        let walk = try XCTUnwrap(model.saveCurrentWalk(named: "  Park Slope  "))
        XCTAssertEqual(walk.name, "Park Slope")
        XCTAssertEqual(model.saveCurrentWalk(named: "Duplicate")?.id, walk.id)
        XCTAssertEqual(model.savedWalks.count, 1)
        model.toggleSaved(Landmark.previews[1])
        try await waitForRoute(model)
        let restored = TourViewModel(defaults: defaults, routeProvider: provider)
        XCTAssertEqual(restored.savedWalks.count, 1)
        restored.openSavedWalk(restored.savedWalks[0])
        XCTAssertEqual(restored.routeStops.map(\.id), order)
        XCTAssertEqual(restored.routeDistance, 1600)
        XCTAssertEqual(restored.routeLines.count, 2)
        XCTAssertEqual(restored.routeLines[0].pointCount, 2)
        XCTAssertEqual(restored.currentStop?.description, walk.stops[0].description)
        restored.prepareRoute() // A location update cannot reorder an opened walk.
        XCTAssertEqual(restored.routeStops.map(\.id), order)
        XCTAssertEqual(restored.savedLandmarks.count, 1)
        XCTAssertTrue(Set(walk.stops.map(\.id)).isSubset(of: restored.mapSavedIDs))
        XCTAssertTrue(Set(walk.stops.map(\.id)).isSubset(of: Set(restored.mapLandmarks.map(\.id))))
        XCTAssertEqual(Set(restored.mapLandmarks.map(\.id)).count, restored.mapLandmarks.count)
        restored.deleteSavedWalk(walk.id)
        try await waitForRoute(restored)
        XCTAssertNil(restored.activeSavedWalkID)
        XCTAssertEqual(restored.routeStops.count, 1)
        XCTAssertTrue(TourViewModel(defaults: defaults).savedWalks.isEmpty)
    }

    func testClearRouteRemovesDraftAndPreservesSavedWalks() async throws {
        let model = TourViewModel(defaults: defaults) { from, to in
            WalkingLeg(polyline: MKPolyline(coordinates: [from, to], count: 2), distance: 800, duration: 600)
        }
        model.userLocation = Landmark.previewOrigin
        model.toggleSaved(Landmark.previews[0])
        try await waitForRoute(model)
        let walk = try XCTUnwrap(model.saveCurrentWalk(named: "Keep this walk"))
        model.clearCurrentRoute()
        XCTAssertNil(model.activeSavedWalkID)
        XCTAssertTrue(model.savedLandmarks.isEmpty)
        XCTAssertTrue(model.routeStops.isEmpty)
        XCTAssertTrue(model.routeLines.isEmpty)
        XCTAssertEqual(model.routeDistance, 0)
        XCTAssertEqual(model.routeDuration, 0)
        XCTAssertEqual(model.currentStopIndex, 0)
        XCTAssertFalse(model.isRouting)
        let restored = TourViewModel(defaults: defaults)
        XCTAssertTrue(restored.savedLandmarks.isEmpty)
        XCTAssertEqual(restored.savedWalks.map(\.id), [walk.id])
        // Clearing while the next route is pending must not let it return later.
        model.toggleSaved(Landmark.previews[1])
        model.clearCurrentRoute()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(model.routeStops.isEmpty)
        XCTAssertTrue(model.routeLines.isEmpty)
    }

    func testUnsaveKeepsOpenRouteAndCanBeSavedAgain() async throws {
        let model = TourViewModel(defaults: defaults) { from, to in
            WalkingLeg(polyline: MKPolyline(coordinates: [from, to], count: 2), distance: 800, duration: 600)
        }
        model.userLocation = Landmark.previewOrigin
        model.toggleSaved(Landmark.previews[0])
        model.toggleSaved(Landmark.previews[1])
        try await waitForRoute(model)
        let walk = try XCTUnwrap(model.saveCurrentWalk(named: "Weekend walk"))
        model.toggleSaved(Landmark.previews[1]) // The draft differs from the opened saved walk.
        try await waitForRoute(model)
        model.openSavedWalk(walk)
        model.currentStopIndex = 1
        model.toggleCurrentWalkSaved()
        XCTAssertNil(model.activeSavedWalkID)
        XCTAssertTrue(TourViewModel(defaults: defaults).savedWalks.isEmpty)
        XCTAssertEqual(model.savedLandmarks.count, 1)
        model.prepareRoute() // Location updates must not replace the still-open route.
        XCTAssertEqual(model.routeStops.map(\.id), walk.stops.map(\.id))
        XCTAssertEqual(model.currentStopIndex, 1)
        XCTAssertEqual(model.routeDistance, walk.distance)
        XCTAssertEqual(model.routeLines.count, walk.lines.count)
        XCTAssertTrue(model.routeSummary.hasPrefix("2 stops"))
        model.toggleCurrentWalkSaved()
        XCTAssertEqual(model.savedWalks.count, 1)
        XCTAssertEqual(model.activeSavedWalk?.name, "Weekend walk")
        XCTAssertEqual(model.activeSavedWalk?.stops.map(\.id), walk.stops.map(\.id))
        model.toggleCurrentWalkSaved()
        model.returnToDraft()
        try await waitForRoute(model)
        XCTAssertEqual(model.routeStops.count, 1)
    }

    private func waitForRoute(_ model: TourViewModel) async throws {
        for _ in 0..<40 {
            if !model.isRouting { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Route never finished")
    }
}

private final class WikiStub: URLProtocol {
    enum Mode { case success, summaryOutage, missingArticle, wikidataOutage }
    static var extractQuery: [String: String]?
    static var sparqlQuery: String?
    static var geosearchRadius: String?
    static var mode: Mode = .success
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        var status = 200
        let json: String
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        if url.host == "query.wikidata.org" {
            Self.sparqlQuery = query["query"]
            if Self.mode == .summaryOutage || Self.mode == .wikidataOutage {
                status = 503
                json = "{}"
            } else {
                json = #"""
                {"results":{"bindings":[
                  {"name":{"value":"Old Stone House (Brooklyn)"},"summary":{"value":"house museum in Brooklyn"},"distance":{"value":"0.05"},
                   "photo":{"value":"http://commons.wikimedia.org/wiki/Special:FilePath/Old%20Stone%20House.jpg"},
                   "listing":{"value":"National Register of Historic Places listed place"},"lat":{"value":"40.6731"},"lon":{"value":"-73.9842"},
                   "types":{"value":"house museum|building"}},
                  {"name":{"value":"Cluny – La Sorbonne"},"summary":{"value":"Paris Métro station"},"distance":{"value":"0.06"},
                   "listing":{"value":"monument historique"},"lat":{"value":"40.67"},"lon":{"value":"-73.98"},
                   "types":{"value":"underground station"}},
                  {"name":{"value":"Ninth Street station"},"summary":{"value":"subway station in Brooklyn"},"distance":{"value":"0.07"},
                   "listing":{"value":"National Register of Historic Places listed place"},"lat":{"value":"40.67"},"lon":{"value":"-73.98"}}
                ]}}
                """#
            }
        } else if query["prop"] == "extracts" {
            Self.extractQuery = query
            if Self.mode == .summaryOutage {
                status = 503
                json = "{}"
            } else if Self.mode == .missingArticle {
                json = #"{"query":{"pages":[{"title":"Missing","missing":true}]}}"#
            } else {
                json = #"{"query":{"pages":[{"title":"House & Garden","extract":"The first introduction paragraph.\n\nA second introduction paragraph with more context."}]}}"#
            }
        } else if url.path == "/w/api.php" {
            Self.geosearchRadius = query["gsradius"]
            json = #"{"query":{"geosearch":[{"pageid":1,"title":"The Met","lat":40.66,"lon":-73.98,"dist":100},{"pageid":2,"title":"Station","lat":40.67,"lon":-73.98,"dist":200}]}}"#
        } else if Self.mode == .summaryOutage {
            status = 503
            json = "{}"
        } else if url.path.hasSuffix("Station") {
            json = #"{"title":"Station","description":"Historic subway station","extract":"Transit"}"#
        } else {
            json = #"{"title":"The Met","displaytitle":"<i>The Met</i>","description":"Art museum in New York City","extract":"Museum summary"}"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor RequestCounter {
    private(set) var count = 0
    func next() -> Int { count += 1; return count }
}
