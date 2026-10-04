import Foundation
import CoreLocation

/// Discovery merges two sources, with officially designated places preferred:
///
///  1. **Heritage designations** from Wikidata: places listed on the National Register of
///     Historic Places, National Historic Landmarks, city landmarks, and equivalent registers
///     worldwide (UK listed buildings, French monuments historiques, UNESCO sites, …).
///  2. **Nearby Wikipedia articles** whose short description names a cultural place type
///     (museum, memorial, church, park, …). These only top up the designated places.
///
/// Summaries are fetched in small batches to avoid overwhelming Wikimedia.
struct WikipediaService {
    static let shared = WikipediaService()
    /// Walking discovery radius. Driving uses `maximumRadius`, Wikipedia geosearch's 10 km limit.
    static let walkingRadius: CLLocationDistance = 3000
    static let maximumRadius: CLLocationDistance = 10000
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func findLandmarks(near coordinate: CLLocationCoordinate2D,
                       radius: CLLocationDistance = walkingRadius) async throws -> [Landmark] {
        async let designatedResult = Self.capture { try await designatedPlaces(near: coordinate, radius: radius) }
        async let articleResult = Self.capture { try await significantArticles(near: coordinate, radius: radius) }
        let (designated, articles) = await (designatedResult, articleResult)
        try Task.checkCancellation()
        // An outage must not masquerade as an area with no landmarks.
        if case .failure = designated, case .failure(let error) = articles { throw error }
        var seen = Set<String>()
        // Designated places come first so their richer metadata wins when both sources match.
        let merged = ((try? designated.get()) ?? []) + ((try? articles.get()) ?? [])
        return merged.filter { seen.insert($0.id).inserted }
            .sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
    }

    private static func capture<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }

    // MARK: Designated places

    /// Descriptions or Wikidata types of designated items that are not a single place a visitor can
    /// stop at. Types catch what descriptions miss, such as Paris's “Métro station” with an accent.
    static let excludedDesignatedTypes = ["subway station", "railway station", "metro station", "métro station",
                                          "train station", "underground station", "elevated station", "s bahn station",
                                          "station complex", "historic district", "neighborhood", "neighbourhood",
                                          "borough of", "census-designated", "prefecture", "railway tunnel"]

    static func isExcludedDesignatedPlace(description: String, types: [String]) -> Bool {
        let text = ([description] + types).joined(separator: " ; ").lowercased().replacingOccurrences(of: "-", with: " ")
        return excludedDesignatedTypes.contains(where: text.contains)
    }

    private func designatedPlaces(near coordinate: CLLocationCoordinate2D,
                                  radius: CLLocationDistance) async throws -> [Landmark] {
        let query = """
        SELECT ?item (SAMPLE(?title) AS ?name) (SAMPLE(?description) AS ?summary) (MIN(?km) AS ?distance)
               (SAMPLE(?image) AS ?photo) (SAMPLE(?designationLabel) AS ?listing)
               (GROUP_CONCAT(DISTINCT ?typeLabel; separator="|") AS ?types)
               (SAMPLE(?latitude) AS ?lat) (SAMPLE(?longitude) AS ?lon) WHERE {
          SERVICE wikibase:around {
            ?item wdt:P625 ?location .
            bd:serviceParam wikibase:center "Point(\(coordinate.longitude) \(coordinate.latitude))"^^geo:wktLiteral .
            bd:serviceParam wikibase:radius "\(radius / 1000)" .
            bd:serviceParam wikibase:distance ?km .
          }
          ?item wdt:P1435 ?designation .
          ?article schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> ; schema:name ?title .
          OPTIONAL { ?item schema:description ?description . FILTER(LANG(?description) = "en") }
          OPTIONAL { ?item wdt:P18 ?image }
          OPTIONAL { ?designation rdfs:label ?designationLabel . FILTER(LANG(?designationLabel) = "en") }
          OPTIONAL { ?item wdt:P31 ?type . ?type rdfs:label ?typeLabel . FILTER(LANG(?typeLabel) = "en") }
          BIND(geof:latitude(?location) AS ?latitude)
          BIND(geof:longitude(?location) AS ?longitude)
        } GROUP BY ?item ORDER BY ?distance LIMIT 300
        """
        var url = URLComponents(string: "https://query.wikidata.org/sparql")!
        url.queryItems = [.init(name: "query", value: query), .init(name: "format", value: "json")]
        let data = try await fetch(url.url!)
        let rows = try JSONDecoder().decode(SPARQLResponse.self, from: data).results.bindings
        return rows.compactMap { row in
            guard let title = row["name"]?.value, let lat = row["lat"].flatMap({ Double($0.value) }),
                  let lon = row["lon"].flatMap({ Double($0.value) }) else { return nil }
            let summary = row["summary"]?.value ?? ""
            let types = (row["types"]?.value ?? "").split(separator: "|").map(String.init)
            guard !Self.isExcludedDesignatedPlace(description: summary, types: types) else { return nil }
            // Commons file URLs accept a width, which keeps photos small enough for a phone.
            let photo = row["photo"].flatMap { URL(string: $0.value.replacingOccurrences(of: "http://", with: "https://") + "?width=1280") }
            let article = title.replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
            return Landmark(title: title, coordinate: .init(latitude: lat, longitude: lon),
                            description: "", categoryDescription: summary, imageURL: photo,
                            wikipediaURL: URL(string: "https://en.wikipedia.org/wiki/\(article)"),
                            distance: row["distance"].flatMap { Double($0.value) }.map { $0 * 1000 },
                            designation: row["listing"]?.value ?? "Heritage designation",
                            placeTypes: types.isEmpty ? nil : types)
        }
    }

    // MARK: Significant nearby articles

    /// Whole-word place types. Ordinary schools, office buildings, and halls are deliberately absent:
    /// historic examples still qualify through their heritage designation.
    static let significantTypes: Set<String> = [
        "archive", "square", "plaza", "zoo", "historic", "heritage", "landmark", "monument", "museum", "memorial",
        "archaeological", "cultural", "cathedral", "castle", "palace", "park", "garden", "shrine", "cemetery",
        "mausoleum", "ruins", "church", "synagogue", "mosque", "temple", "armory", "armoury", "library",
        "theater", "theatre", "sculpture", "statue", "bridge"]
    static let excludedArticleTypes = ["subway station", "railway station", "metro station", "neighborhood",
                                       "neighbourhood", "borough of", "census-designated", "electoral district",
                                       "historic district"]

    /// Matches whole words in Wikipedia's short description, falling back to the title only when
    /// there is no description, so “Park Slope Food Coop” is not mistaken for a park.
    static func isSignificant(title: String, description: String) -> Bool {
        let text = (description.isEmpty ? title : description).lowercased()
        guard !excludedArticleTypes.contains(where: text.contains) else { return false }
        let words = text.split { !$0.isLetter }.map(String.init)
        return words.contains { significantTypes.contains($0) || ($0.hasSuffix("s") && significantTypes.contains(String($0.dropLast()))) }
    }

    private func significantArticles(near coordinate: CLLocationCoordinate2D,
                                     radius: CLLocationDistance) async throws -> [Landmark] {
        var url = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        url.queryItems = [
            .init(name: "action", value: "query"), .init(name: "list", value: "geosearch"),
            .init(name: "gscoord", value: "\(coordinate.latitude)|\(coordinate.longitude)"),
            .init(name: "gsradius", value: "\(Int(min(radius, Self.maximumRadius)))"), .init(name: "gslimit", value: "50"),
            .init(name: "gsnamespace", value: "0"), .init(name: "format", value: "json")
        ]
        let data = try await fetch(url.url!)
        let articles = try JSONDecoder().decode(GeoSearchResponse.self, from: data).query.geosearch
        var landmarks: [Landmark] = []
        var successfulSummaries = 0
        for start in stride(from: 0, to: articles.count, by: 6) {
            try Task.checkCancellation()
            let batch = articles[start..<min(start + 6, articles.count)]
            let results = await withTaskGroup(of: (Bool, Landmark?).self) { group in
                for article in batch {
                    group.addTask {
                        do { return (true, try await summary(for: article)) }
                        catch { return (false, nil) }
                    }
                }
                var results: [(Bool, Landmark?)] = []
                for await result in group { results.append(result) }
                return results
            }
            successfulSummaries += results.filter(\.0).count
            landmarks.append(contentsOf: results.compactMap(\.1))
        }
        if !articles.isEmpty && successfulSummaries == 0 { throw URLError(.badServerResponse) }
        return landmarks
    }

    /// Load all introduction paragraphs, stopping before the first article section.
    func introduction(for title: String) async throws -> String {
        var url = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        url.queryItems = [
            .init(name: "action", value: "query"), .init(name: "prop", value: "extracts"),
            .init(name: "titles", value: title), .init(name: "redirects", value: "1"),
            .init(name: "exintro", value: "1"), .init(name: "explaintext", value: "1"), .init(name: "exsectionformat", value: "plain"),
            .init(name: "format", value: "json"), .init(name: "formatversion", value: "2")
        ]
        let data = try await fetch(url.url!)
        let response = try JSONDecoder().decode(ArticleExtractResponse.self, from: data)
        guard let page = response.query?.pages.first, page.missing != true,
              let text = page.extract?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw URLError(.resourceUnavailable)
        }
        return text
    }

    private func summary(for article: GeoArticle) async throws -> Landmark? {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        guard let title = article.title.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(title)") else { return nil }
        let data = try await fetch(url)
        let summary = try JSONDecoder().decode(WikiSummaryResponse.self, from: data)
        guard Self.isSignificant(title: summary.title ?? article.title, description: summary.description ?? "") else { return nil }
        return Landmark(title: summary.title ?? article.title,
                        coordinate: .init(latitude: article.lat, longitude: article.lon),
                        description: summary.extract ?? "", categoryDescription: summary.description ?? "",
                        imageURL: (summary.originalimage ?? summary.thumbnail).flatMap { URL(string: $0.source) },
                        wikipediaURL: summary.contentUrls?.desktop?.page.flatMap(URL.init), distance: article.dist)
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("WikiTour-iOS/1.0 (https://github.com/xujenna/wiki-tour)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

private struct ArticleExtractResponse: Decodable {
    let query: Query?
    struct Query: Decodable { let pages: [Page] }
    struct Page: Decodable {
        let extract: String?
        let missing: Bool?
    }
}

/// The Wikidata Query Service's JSON results format.
private struct SPARQLResponse: Decodable {
    struct Value: Decodable { let value: String }
    struct Results: Decodable { let bindings: [[String: Value]] }
    let results: Results
}

/// Postcard place names from OpenStreetMap's reverse geocoder, which knows neighborhoods that
/// Apple's geocoder does not (Apple calls all of Park Slope just "Brooklyn"). One request per search,
/// within Nominatim's usage policy of at most one request a second with an identifying User-Agent.
struct PlaceNames: Equatable {
    let title: String
    let subtitle: String?

    static func lookup(_ coordinate: CLLocationCoordinate2D, session: URLSession = .shared) async throws -> PlaceNames? {
        var url = URLComponents(string: "https://nominatim.openstreetmap.org/reverse")!
        url.queryItems = [.init(name: "format", value: "jsonv2"), .init(name: "zoom", value: "16"),
                          .init(name: "addressdetails", value: "1"), .init(name: "accept-language", value: "en"),
                          .init(name: "lat", value: "\(coordinate.latitude)"), .init(name: "lon", value: "\(coordinate.longitude)")]
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 15
        request.setValue("WikiTour-iOS/1.0 (https://github.com/xujenna/wiki-tour)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(NominatimResponse.self, from: data)
        return names(from: response.address ?? [:])
    }

    /// The neighborhood leads, with its city (or New York City borough) below; with no neighborhood,
    /// the city leads, with its US state or country below.
    static func names(from address: [String: String]) -> PlaceNames? {
        let city = address["city"] ?? address["town"] ?? address["village"] ?? address["municipality"]
        let isNewYorkCity = city == "New York" || city == "City of New York"
        let borough = isNewYorkCity ? address["suburb"] ?? address["borough"] : nil
        let place = borough ?? city
        let region = address["country_code"] == "us" ? address["state"] : address["country"]
        if let neighborhood = address["neighbourhood"] ?? address["quarter"], neighborhood != place {
            return PlaceNames(title: neighborhood, subtitle: place ?? region)
        }
        if let place { return PlaceNames(title: place, subtitle: region) }
        return nil
    }

    private struct NominatimResponse: Decodable { let address: [String: String]? }
}
