import Foundation
import CoreLocation

/// Mirrors the logic in the original wiki-tour web app:
///   1. Reverse-geocode the user's position to county + state.
///   2. Build the Wikipedia "National Register of Historic Places listings in …" page name.
///   3. Inspect the page's section structure to find the right links.
///   4. Concurrently fetch Wikipedia REST summaries for every linked article.
///   5. Keep only articles that have coordinates and aren't state/NPS overview pages.
///   6. Return the 10 closest landmarks in nearest-neighbour walk order.
struct WikipediaService {
    static let shared = WikipediaService()

    private let apiBase  = "https://en.wikipedia.org/w/api.php"
    private let restBase = "https://en.wikipedia.org/api/rest_v1/page/summary"

    // MARK: - Public entry point

    func findLandmarks(
        near coordinate: CLLocationCoordinate2D,
        county: String,
        state: String,
        progress: @escaping (String) -> Void
    ) async throws -> [Landmark] {
        let pageName = nrhpPageName(county: county, state: state)
        progress("Looking up National Register listings for \(county)…")

        let links = try await resolveLinks(pageName: pageName)
        progress("Found \(links.count) historic sites — fetching details…")

        let userLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let landmarks = await fetchLandmarks(from: links, state: state, userLocation: userLocation)

        progress("Optimising your walking route…")
        let top10 = Array(landmarks
            .sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
            .prefix(10))
        return nearestNeighbourRoute(from: coordinate, landmarks: top10)
    }

    // MARK: - NRHP page name

    /// Matches the county→page-name mapping from the original JS `getWikiPage()`.
    func nrhpPageName(county: String, state: String) -> String {
        switch county {
        case "Kings County":    return "National_Register_of_Historic_Places_listings_in_Brooklyn"
        case "New York County": return "National_Register_of_Historic_Places_listings_in_Manhattan"
        case "Bronx County":    return "National_Register_of_Historic_Places_listings_in_the_Bronx"
        case "Queens County":   return "National_Register_of_Historic_Places_listings_in_Queens,_New_York"
        case "Richmond County": return "National_Register_of_Historic_Places_listings_in_Staten_Island"
        default:
            let c = county.replacingOccurrences(of: " ", with: "_")
            let s = state.replacingOccurrences(of: " ", with: "_")
            return "National_Register_of_Historic_Places_listings_in_\(c),_\(s)"
        }
    }

    // MARK: - Link resolution (mirrors the branching logic in getWikiPage())

    private func resolveLinks(pageName: String) async throws -> [String] {
        let sections = try await fetchSections(pageName: pageName)

        guard let firstLine = sections.first else {
            // Sections array is empty — page was probably renamed.
            // Fall back to following any NRHP listing link on the page.
            let allLinks = try await fetchLinks(pageName: pageName, section: nil)
            var collected: [String] = []
            for link in allLinks where link.contains("National Register of Historic Places listings") {
                let sub = try await fetchLinks(
                    pageName: link.replacingOccurrences(of: " ", with: "_"),
                    section: "1"
                )
                collected.append(contentsOf: sub)
            }
            return collected
        }

        switch firstLine {
        case "Current listings", "Listings county-wide":
            // Listings live directly in section 1 of this page.
            return try await fetchLinks(pageName: pageName, section: "1")

        case "Listings by town", "Lists by area":
            // Section 1 links to per-town sub-pages; collect from all of them.
            let subPageNames = try await fetchLinks(pageName: pageName, section: "1")
            var collected: [String] = []
            for sub in subPageNames {
                let subLinks = try await fetchLinks(
                    pageName: sub.replacingOccurrences(of: " ", with: "_"),
                    section: "1"
                )
                collected.append(contentsOf: subLinks)
            }
            return collected

        default:
            return try await fetchLinks(pageName: pageName, section: "1")
        }
    }

    // MARK: - Wikipedia parse API helpers

    private func fetchSections(pageName: String) async throws -> [String] {
        var c = URLComponents(string: apiBase)!
        c.queryItems = [
            URLQueryItem(name: "action", value: "parse"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "page",   value: pageName),
            URLQueryItem(name: "prop",   value: "sections"),
        ]
        guard let url = c.url else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response  = try JSONDecoder().decode(ParseSectionsResponse.self, from: data)
        return response.parse.sections.map(\.line)
    }

    /// `section` == nil fetches all page links (for the renamed-page fallback).
    private func fetchLinks(pageName: String, section: String?) async throws -> [String] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "action", value: "parse"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "page",   value: pageName),
            URLQueryItem(name: "prop",   value: "links"),
        ]
        if let section { items.append(URLQueryItem(name: "section", value: section)) }
        var c = URLComponents(string: apiBase)!
        c.queryItems = items
        guard let url = c.url else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response  = try JSONDecoder().decode(ParseLinksResponse.self, from: data)
        // Only namespace-0 links are actual articles.
        return response.parse.links.filter { $0.ns == 0 }.map(\.title)
    }

    // MARK: - Landmark fetching (concurrent, mirrors getLandmarksList cloud function)

    private func fetchLandmarks(
        from titles: [String],
        state: String,
        userLocation: CLLocation
    ) async -> [Landmark] {
        var results: [Landmark] = []
        await withTaskGroup(of: Landmark?.self) { group in
            for title in titles {
                group.addTask {
                    await self.fetchOneLandmark(title: title, state: state, userLocation: userLocation)
                }
            }
            for await landmark in group {
                if let landmark { results.append(landmark) }
            }
        }
        return results
    }

    private func fetchOneLandmark(
        title: String,
        state: String,
        userLocation: CLLocation
    ) async -> Landmark? {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        guard let url = URL(string: "\(restBase)/\(encoded)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let summary = try? JSONDecoder().decode(WikiSummaryResponse.self, from: data),
              let coords = summary.coordinates
        else { return nil }

        // Mirror the sortData() filter from the original:
        //   !landmark.name.includes(', ' + userLocation.state)
        //   !landmark.name.includes('National Park Service')
        let displayTitle = summary.displaytitle ?? title
        guard !displayTitle.contains(", \(state)"),
              !displayTitle.contains("National Park Service")
        else { return nil }

        let coordinate    = CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lon)
        let landmarkLoc   = CLLocation(latitude: coords.lat, longitude: coords.lon)
        let wikiURL       = summary.contentUrls?.desktop?.page.flatMap(URL.init)

        return Landmark(
            title: displayTitle,
            coordinate: coordinate,
            description: summary.extract ?? "",
            imageURL: summary.thumbnail.flatMap { URL(string: $0.source) },
            wikipediaURL: wikiURL,
            distance: landmarkLoc.distance(from: userLocation)
        )
    }

    // MARK: - Route optimisation (nearest-neighbour greedy TSP)
    //
    // The original uses Google Maps `optimizeWaypoints: true`.
    // This greedy algorithm produces a comparable result without an API call.

    private func nearestNeighbourRoute(
        from origin: CLLocationCoordinate2D,
        landmarks: [Landmark]
    ) -> [Landmark] {
        var remaining = landmarks
        var route: [Landmark] = []
        var current = origin

        while !remaining.isEmpty {
            let nearest = remaining.min {
                CLLocation(latitude: current.latitude, longitude: current.longitude)
                    .distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude))
                < CLLocation(latitude: current.latitude, longitude: current.longitude)
                    .distance(from: CLLocation(latitude: $1.coordinate.latitude, longitude: $1.coordinate.longitude))
            }!
            route.append(nearest)
            current = nearest.coordinate
            remaining.removeAll { $0.id == nearest.id }
        }

        return route.enumerated().map { i, l in
            var copy = l; copy.stopNumber = i + 1; return copy
        }
    }
}
