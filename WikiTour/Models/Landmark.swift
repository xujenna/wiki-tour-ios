import Foundation
import CoreLocation

struct Landmark: Identifiable, Codable, Hashable {
    let id: Int
    let title: String
    let lat: Double
    let lon: Double
    var distance: CLLocationDistance?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var formattedDistance: String {
        guard let distance else { return "" }
        return distance < 1000
            ? String(format: "%.0f m", distance)
            : String(format: "%.1f km", distance / 1000)
    }

    // CLLocationDistance is a Double, which is not Codable by default in structs,
    // so we exclude it from coding and compute it at runtime.
    enum CodingKeys: String, CodingKey {
        case id = "pageid"
        case title, lat, lon
    }

    static func == (lhs: Landmark, rhs: Landmark) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Wikipedia API response shapes

struct GeoSearchResponse: Codable {
    let query: GeoSearchQuery
}

struct GeoSearchQuery: Codable {
    let geosearch: [Landmark]
}

struct SummaryResponse: Codable {
    let extract: String?
    let thumbnail: ThumbnailInfo?
    let contentUrls: ContentURLs?

    enum CodingKeys: String, CodingKey {
        case extract, thumbnail
        case contentUrls = "content_urls"
    }
}

struct ThumbnailInfo: Codable {
    let source: String
}

struct ContentURLs: Codable {
    let mobile: MobileURL?
}

struct MobileURL: Codable {
    let page: String?
}
