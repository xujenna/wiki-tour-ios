import Foundation
import CoreLocation

struct Landmark: Identifiable, Hashable {
    var id = UUID()
    let title: String
    let coordinate: CLLocationCoordinate2D
    let description: String
    let imageURL: URL?
    let wikipediaURL: URL?
    var distance: CLLocationDistance?
    var stopNumber: Int?        // assigned after route optimization

    var formattedDistance: String {
        guard let distance else { return "" }
        let miles = distance / 1609.34
        return miles < 0.1
            ? String(format: "%.0f ft", distance * 3.28084)
            : String(format: "%.1f mi", miles)
    }

    static func == (lhs: Landmark, rhs: Landmark) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Wikipedia parse API response models

struct ParseSectionsResponse: Codable {
    let parse: ParseSections
}
struct ParseSections: Codable {
    let sections: [WikiSection]
}
struct WikiSection: Codable {
    let line: String
}

struct ParseLinksResponse: Codable {
    let parse: ParseLinks
}
struct ParseLinks: Codable {
    let links: [WikiLink]
}
struct WikiLink: Codable {
    let ns: Int
    let title: String
    enum CodingKeys: String, CodingKey {
        case ns
        case title = "*"
    }
}

// MARK: - Wikipedia geosearch API response

struct GeoSearchResponse: Codable {
    let query: GeoQuery
}
struct GeoQuery: Codable {
    let geosearch: [GeoArticle]
}
struct GeoArticle: Codable {
    let pageid: Int
    let title: String
    let lat: Double
    let lon: Double
    let dist: Double
}

// MARK: - Wikipedia REST summary response

struct WikiSummaryResponse: Codable {
    let displaytitle: String?
    /// Short Wikidata description, e.g. "historic district in Manhattan" — used for
    /// significance filtering in the geosearch path.
    let description: String?
    let extract: String?
    let coordinates: WikiCoordinates?
    let thumbnail: ThumbnailInfo?
    let contentUrls: ContentURLs?

    enum CodingKeys: String, CodingKey {
        case displaytitle, description, extract, coordinates, thumbnail
        case contentUrls = "content_urls"
    }
}
struct WikiCoordinates: Codable {
    let lat: Double
    let lon: Double
}
struct ThumbnailInfo: Codable {
    let source: String
}
struct ContentURLs: Codable {
    let desktop: DesktopURL?
    let mobile: MobileURL?
}
struct DesktopURL: Codable {
    let page: String?
}
struct MobileURL: Codable {
    let page: String?
}
