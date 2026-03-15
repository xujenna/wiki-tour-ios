import Foundation
import CoreLocation

enum WikipediaError: LocalizedError {
    case invalidURL
    case network(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:       return "Invalid URL"
        case .network(let e):   return "Network error: \(e.localizedDescription)"
        case .decoding(let e):  return "Data error: \(e.localizedDescription)"
        }
    }
}

struct WikipediaService {
    static let shared = WikipediaService()

    private let apiBase    = "https://en.wikipedia.org/w/api.php"
    private let restBase   = "https://en.wikipedia.org/api/rest_v1/page/summary"

    // Returns articles within `radius` metres of the given coordinate, sorted by distance.
    func nearbyLandmarks(
        at coordinate: CLLocationCoordinate2D,
        radius: Int = 1000
    ) async throws -> [Landmark] {
        var components = URLComponents(string: apiBase)!
        components.queryItems = [
            URLQueryItem(name: "action",      value: "query"),
            URLQueryItem(name: "list",        value: "geosearch"),
            URLQueryItem(name: "gscoord",     value: "\(coordinate.latitude)|\(coordinate.longitude)"),
            URLQueryItem(name: "gsradius",    value: "\(radius)"),
            URLQueryItem(name: "gslimit",     value: "20"),
            URLQueryItem(name: "gsnamespace", value: "0"),
            URLQueryItem(name: "format",      value: "json"),
        ]
        guard let url = components.url else { throw WikipediaError.invalidURL }

        let data: Data
        do { (data, _) = try await URLSession.shared.data(from: url) }
        catch { throw WikipediaError.network(error) }

        do { return try JSONDecoder().decode(GeoSearchResponse.self, from: data).query.geosearch }
        catch { throw WikipediaError.decoding(error) }
    }

    // Returns the Wikipedia summary for a given article title.
    func summary(for title: String) async throws -> SummaryResponse {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        guard let url = URL(string: "\(restBase)/\(encoded)") else {
            throw WikipediaError.invalidURL
        }

        let data: Data
        do { (data, _) = try await URLSession.shared.data(from: url) }
        catch { throw WikipediaError.network(error) }

        do { return try JSONDecoder().decode(SummaryResponse.self, from: data) }
        catch { throw WikipediaError.decoding(error) }
    }
}
