import Foundation
import CoreLocation

/// Two complementary sources feed the tour:
///
///  1. **NRHP** (US only) — parses county-level "National Register of Historic Places
///     listings in …" pages, exactly as the original web app does.
///
///  2. **Geosearch** (global) — queries Wikipedia's geosearch API for nearby articles,
///     then keeps only those whose Wikidata short `description` contains a keyword
///     indicating historic or cultural significance (museum, landmark, cathedral, etc.).
///
/// Results from both sources are merged, deduplicated, trimmed to 10, and ordered
/// using a nearest-neighbour greedy algorithm.
struct WikipediaService {
    static let shared = WikipediaService()

    private let apiBase  = "https://en.wikipedia.org/w/api.php"
    private let restBase = "https://en.wikipedia.org/api/rest_v1/page/summary"

    // MARK: - Public entry point

    /// `county` and `state` are optional — pass them when available (US) to unlock
    /// the NRHP source; omit them (international) to use geosearch only.
    func findLandmarks(
        near coordinate: CLLocationCoordinate2D,
        county: String?,
        state: String?,
        progress: @escaping (String) -> Void
    ) async throws -> [Landmark] {
        let userLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var accumulated: [Landmark] = []

        // ── Source 1: NRHP ────────────────────────────────────────────────────────
        if let county, let state {
            let pageName = nrhpPageName(county: county, state: state)
            progress("Looking up National Register listings for \(county)…")
            if let nrhp = try? await fetchNRHPLandmarks(
                pageName: pageName, state: state, userLocation: userLocation
            ) {
                accumulated.append(contentsOf: nrhp)
                progress("Found \(nrhp.count) NRHP sites. Searching for more…")
            }
        }

        // ── Source 2: Geosearch (historic/cultural significance filter) ────────────
        progress("Searching for nearby cultural and historic sites…")
        let geo = await fetchGeoSearchLandmarks(near: coordinate, userLocation: userLocation)
        // Deduplicate by title (case-insensitive) before merging.
        let existingTitles = Set(accumulated.map { $0.title.lowercased() })
        for lm in geo where !existingTitles.contains(lm.title.lowercased()) {
            accumulated.append(lm)
        }

        // ── Select top 10 by distance, then optimise walk order ──────────────────
        progress("Optimising your walking route…")
        let top10 = Array(accumulated
            .sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
            .prefix(10))
        return nearestNeighbourRoute(from: coordinate, landmarks: top10)
    }

    // MARK: - Source 1: NRHP

    private func fetchNRHPLandmarks(
        pageName: String,
        state: String,
        userLocation: CLLocation
    ) async throws -> [Landmark] {
        let links = try await resolveLinks(pageName: pageName)
        return await fetchLandmarks(from: links, state: state, userLocation: userLocation)
    }

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

    private func resolveLinks(pageName: String) async throws -> [String] {
        let sections = try await fetchSections(pageName: pageName)

        guard let firstLine = sections.first else {
            let allLinks = try await fetchLinks(pageName: pageName, section: nil)
            var collected: [String] = []
            for link in allLinks where link.contains("National Register of Historic Places listings") {
                let sub = try await fetchLinks(
                    pageName: link.replacingOccurrences(of: " ", with: "_"), section: "1"
                )
                collected.append(contentsOf: sub)
            }
            return collected
        }

        switch firstLine {
        case "Current listings", "Listings county-wide":
            return try await fetchLinks(pageName: pageName, section: "1")

        case "Listings by town", "Lists by area":
            let subPages = try await fetchLinks(pageName: pageName, section: "1")
            var collected: [String] = []
            for sub in subPages {
                let subLinks = try await fetchLinks(
                    pageName: sub.replacingOccurrences(of: " ", with: "_"), section: "1"
                )
                collected.append(contentsOf: subLinks)
            }
            return collected

        default:
            return try await fetchLinks(pageName: pageName, section: "1")
        }
    }

    private func fetchSections(pageName: String) async throws -> [String] {
        var c = URLComponents(string: apiBase)!
        c.queryItems = [
            URLQueryItem(name: "action", value: "parse"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "page",   value: pageName),
            URLQueryItem(name: "prop",   value: "sections"),
        ]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        let response  = try JSONDecoder().decode(ParseSectionsResponse.self, from: data)
        return response.parse.sections.map(\.line)
    }

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
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        let response  = try JSONDecoder().decode(ParseLinksResponse.self, from: data)
        return response.parse.links.filter { $0.ns == 0 }.map(\.title)
    }

    // MARK: - Source 2: Geosearch with significance filter

    /// Keywords matched against the Wikidata short `description` field returned by the
    /// Wikipedia REST summary API. This field is terse and reliable, e.g.:
    ///   "historic district in the Lower East Side of Manhattan"
    ///   "art museum in Paris"
    ///   "medieval cathedral in England"
    ///   "Roman-era archaeological site in Greece"
    private let significanceKeywords: [String] = [
        "historic",        // historic district, historic building, historic site …
        "heritage",        // world heritage, cultural heritage …
        "landmark",        // architectural landmark, historical landmark …
        "monument",        // national monument, war monument …
        "museum",          // art museum, history museum, children's museum …
        "memorial",        // war memorial, national memorial …
        "archaeological",  // archaeological site, dig …
        "cultural",        // cultural center, cultural site …
        "cathedral",       // nearly always architecturally/historically significant
        "castle",          // ditto
        "palace",          // ditto
        "listed building", // Historic England / Cadw / HES grade listings
        "national park",   // US National Parks, international equivalents
        "state park",
        "national register",
        "national historic",
        "world heritage",
        "shrine",          // religious/cultural significance
        "cemetery",        // historic cemeteries (Arlington, Pere Lachaise …)
        "mausoleum",
        "ancient",         // ancient site, ancient ruins …
        "ruins",
    ]

    private func fetchGeoSearchLandmarks(
        near coordinate: CLLocationCoordinate2D,
        userLocation: CLLocation,
        radius: Int = 2000
    ) async -> [Landmark] {
        guard let articles = try? await fetchNearbyArticles(coordinate: coordinate, radius: radius)
        else { return [] }

        var results: [Landmark] = []
        await withTaskGroup(of: Landmark?.self) { group in
            for article in articles {
                group.addTask {
                    await self.fetchSignificantLandmark(title: article.title, userLocation: userLocation)
                }
            }
            for await lm in group {
                if let lm { results.append(lm) }
            }
        }
        return results
    }

    private func fetchNearbyArticles(
        coordinate: CLLocationCoordinate2D,
        radius: Int
    ) async throws -> [GeoArticle] {
        var c = URLComponents(string: apiBase)!
        c.queryItems = [
            URLQueryItem(name: "action",      value: "query"),
            URLQueryItem(name: "list",        value: "geosearch"),
            URLQueryItem(name: "gscoord",     value: "\(coordinate.latitude)|\(coordinate.longitude)"),
            URLQueryItem(name: "gsradius",    value: "\(radius)"),
            URLQueryItem(name: "gslimit",     value: "50"),
            URLQueryItem(name: "gsnamespace", value: "0"),
            URLQueryItem(name: "format",      value: "json"),
        ]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        return try JSONDecoder().decode(GeoSearchResponse.self, from: data).query.geosearch
    }

    /// Fetches the summary for a nearby article and returns a Landmark only if its
    /// Wikidata description suggests historic or cultural significance.
    private func fetchSignificantLandmark(title: String, userLocation: CLLocation) async -> Landmark? {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        guard let url = URL(string: "\(restBase)/\(encoded)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let summary = try? JSONDecoder().decode(WikiSummaryResponse.self, from: data),
              let coords  = summary.coordinates
        else { return nil }

        // Require a Wikidata description that matches at least one significance keyword.
        let desc = (summary.description ?? "").lowercased()
        guard !desc.isEmpty,
              significanceKeywords.contains(where: { desc.contains($0) })
        else { return nil }

        let coordinate   = CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lon)
        let landmarkLoc  = CLLocation(latitude: coords.lat, longitude: coords.lon)
        let wikiURL      = summary.contentUrls?.desktop?.page.flatMap(URL.init)

        return Landmark(
            title: summary.displaytitle ?? title,
            coordinate: coordinate,
            description: summary.extract ?? "",
            imageURL: summary.thumbnail.flatMap { URL(string: $0.source) },
            wikipediaURL: wikiURL,
            distance: landmarkLoc.distance(from: userLocation)
        )
    }

    // MARK: - Shared: concurrent NRHP landmark fetching

    private func fetchLandmarks(
        from titles: [String],
        state: String,
        userLocation: CLLocation
    ) async -> [Landmark] {
        var results: [Landmark] = []
        await withTaskGroup(of: Landmark?.self) { group in
            for title in titles {
                group.addTask {
                    await self.fetchNRHPLandmark(title: title, state: state, userLocation: userLocation)
                }
            }
            for await lm in group { if let lm { results.append(lm) } }
        }
        return results
    }

    private func fetchNRHPLandmark(title: String, state: String, userLocation: CLLocation) async -> Landmark? {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        guard let url = URL(string: "\(restBase)/\(encoded)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let summary  = try? JSONDecoder().decode(WikiSummaryResponse.self, from: data),
              let coords   = summary.coordinates
        else { return nil }

        let displayTitle = summary.displaytitle ?? title
        guard !displayTitle.contains(", \(state)"),
              !displayTitle.contains("National Park Service")
        else { return nil }

        let coordinate  = CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lon)
        let landmarkLoc = CLLocation(latitude: coords.lat, longitude: coords.lon)
        let wikiURL     = summary.contentUrls?.desktop?.page.flatMap(URL.init)

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
                <
                CLLocation(latitude: current.latitude, longitude: current.longitude)
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
