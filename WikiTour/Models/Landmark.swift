import Foundation
import CoreLocation

struct Landmark: Identifiable, Hashable, Codable {
    // Article titles stay stable across refreshes, unlike a newly generated UUID.
    var id: String { title.replacingOccurrences(of: "_", with: " ").lowercased() }
    let title: String
    let latitude: Double
    let longitude: Double
    let description: String
    let categoryDescription: String
    let imageURL: URL?
    let wikipediaURL: URL?
    var distance: CLLocationDistance?
    var previewImage: String?
    /// The official heritage listing, such as the National Register of Historic Places.
    /// Optional so places saved by earlier builds still decode.
    var designation: String?
    /// Wikidata "instance of" labels, such as "church building" or "private mansion".
    /// These classify places whose short description only says "building in Paris".
    var placeTypes: [String]?

    var isDesignated: Bool { designation != nil }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(title: String, coordinate: CLLocationCoordinate2D, description: String, categoryDescription: String = "",
         imageURL: URL? = nil, wikipediaURL: URL? = nil, distance: CLLocationDistance? = nil,
         previewImage: String? = nil, designation: String? = nil, placeTypes: [String]? = nil) {
        self.title = title
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        self.description = description
        self.categoryDescription = categoryDescription
        self.imageURL = imageURL
        self.wikipediaURL = wikipediaURL
        self.distance = distance
        self.previewImage = previewImage
        self.designation = designation
        self.placeTypes = placeTypes
    }

    var formattedDistance: String {
        guard let distance else { return "" }
        return distance < 161 ? String(format: "%.0f feet", distance * 3.28084)
            : String(format: "%.1f miles", distance / 1609.34)
    }

    var emoji: String {
        // Wikipedia categories often read “Bookstore in Park Slope, Brooklyn”.
        // Only the place-type clause is classification evidence; location is not.
        let category = categoryDescription.lowercased()
            .components(separatedBy: " in ").first ?? ""
        let types = (placeTypes ?? []).joined(separator: " ; ")
        // Descriptions and Wikidata types name place types, so they may use generic words like
        // "house" or "street". Titles may not: “Park Avenue” and “Customs House” are names.
        return Self.emoji(for: category, rules: Self.typeRules) ?? Self.emoji(for: types, rules: Self.typeRules)
            ?? Self.emoji(for: title, rules: Self.specificRules)
            ?? Self.emoji(for: category, rules: Self.broadRules) ?? Self.natureEmoji(forName: title) ?? "🏛️"
    }

    private static func natureEmoji(forName name: String) -> String? {
        let name = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // A terminal place type is useful for articles without category metadata.
        // “Park Slope …”, “Forest Hills …”, and “Park Avenue …” are not park types.
        if name.hasSuffix(" park") || name.hasSuffix(" forest") || name.hasSuffix(" nature reserve") { return "🌲" }
        if name.hasSuffix(" house") || name.hasSuffix(" residence") { return "🏠" }
        return nil
    }

    var emojiAssetName: String {
        "Emoji-" + emoji.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-")
    }

    /// Distinctive place types, safe to find even in a place's name. Earlier rules win.
    private static let specificRules: [([String], String)] = [
        (["bookstore", "bookshop", "book store", "book shop", "bookseller"], "📚"),
        (["food coop", "food co op", "food cooperative", "grocery", "supermarket", "grocery store"], "🛒"),
        (["cemetery", "burial", "graveyard", "mausoleum"], "🪦"),
        (["armory", "armoury", "castle", "fortress", "palace"], "🏰"),
        (["synagogue", "jewish center", "jewish centre"], "🕍"),
        (["church", "cathedral", "chapel", "basilica", "abbey", "monastery", "convent"], "⛪️"),
        (["mosque", "masjid"], "🕌"),
        (["temple", "shrine"], "🛕"),
        (["school", "college", "university", "lycée", "academy"], "🏫"),
        (["library", "archive"], "📚"),
        (["theater", "theatre", "opera", "cinema", "concert hall", "music venue", "arts center", "arts centre",
          "cultural center", "cultural centre"], "🎭"),
        (["hospital"], "🏥"),
        (["hotel"], "🏨"),
        (["restaurant", "brasserie", "café", "cafe", "tavern"], "🍽️"),
        (["department store", "shopping", "covered passages", "arcade"], "🛍️"),
        (["skyscraper", "office building", "commercial building"], "🏢"),
        (["fountain"], "⛲"),
        (["statue", "sculpture", "bust", "obelisk"], "🗿"),
        (["archaeological", "ruins", "amphitheatre", "amphitheater", "tomb"], "🏺"),
        (["hall"], "💒"),
        (["museum", "memorial", "monument", "historic building", "historic district", "historic site"], "🏛️"),
        (["bridge"], "🌉"),
        (["garden", "botanical"], "🌷"),
        (["lighthouse", "tower"], "🗼")
    ]

    /// Generic words that identify a place type only in a description or Wikidata type.
    private static let typeRules: [([String], String)] = specificRules + [
        (["mansion", "hôtel particulier", "villa", "manor", "house", "home", "residence", "residential building",
          "apartment building", "rowhouse", "townhouse"], "🏠"),
        (["park", "forest", "nature reserve"], "🌲"),
        (["store", "shop", "market", "passageway", "passage"], "🛍️"),
        (["bank", "bank building", "office"], "🏢"),
        (["bar", "pub"], "🍽️"),
        (["square", "plaza", "street", "boulevard", "avenue"], "🏙️")
    ]

    private static let broadRules: [([String], String)] = [
        (["park", "forest", "nature reserve"], "🌲"),
        (["house", "residence"], "🏠")
    ]

    private static func emoji(for value: String, rules: [([String], String)]) -> String? {
        let text = value.lowercased().replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
        let padded = " " + text + " "
        return rules.first { keywords, _ in keywords.contains { padded.contains(" " + $0 + " ") } }?.1
    }

    static func == (lhs: Landmark, rhs: Landmark) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct GeoSearchResponse: Decodable { let query: GeoQuery }
struct GeoQuery: Decodable { let geosearch: [GeoArticle] }
struct GeoArticle: Decodable {
    let pageid: Int
    let title: String
    let lat: Double
    let lon: Double
    let dist: Double
}
struct WikiSummaryResponse: Decodable {
    let title: String?
    let description: String?
    let extract: String?
    let coordinates: WikiCoordinates?
    let thumbnail: ThumbnailInfo?
    let originalimage: ThumbnailInfo?
    let contentUrls: ContentURLs?
    enum CodingKeys: String, CodingKey {
        case title, description, extract, coordinates, thumbnail, originalimage
        case contentUrls = "content_urls"
    }
}
struct WikiCoordinates: Decodable { let lat: Double; let lon: Double }
struct ThumbnailInfo: Decodable { let source: String }
struct ContentURLs: Decodable { let desktop: DesktopURL? }
struct DesktopURL: Decodable { let page: String? }

#if DEBUG
extension Landmark {
    static let previewOrigin = CLLocationCoordinate2D(latitude: 40.6575, longitude: -73.9865)
    static let previews: [Landmark] = [
        Landmark(title: "14th Regiment Armory", coordinate: .init(latitude: 40.6632, longitude: -73.9846),
                 description: "The 14th Regiment Armory, also known as the Eighth Avenue Armory and the Park Slope Armory, is a historic National Guard armory building located on Eighth Avenue between 14th and 15th Streets in the South Slope neighborhood of Brooklyn, New York City, United States. The building is a brick and stone castle-like structure, and designed to be reminiscent of medieval military structures in Europe. It was built in 1891–95 and was designed in the Late Victorian style by William A. Mundell.\n\nThe structure was originally built for the 14th Regiment of the New York State Militia. Since the 1980s, it has been in use as a women's homeless shelter. A veterans' museum and a YMCA sports facility are also located in the armory.\n\nThe armory was listed on the National Register of Historic Places in 1994, and was designated a New York City landmark in 1998.",
                 wikipediaURL: URL(string: "https://en.wikipedia.org/wiki/14th_Regiment_Armory"), distance: 1931, previewImage: "ArmoryPreview"),
        Landmark(title: "Grand Prospect Hall", coordinate: .init(latitude: 40.6663, longitude: -73.9875), description: "Grand Prospect Hall was a historic banquet hall in Park Slope, Brooklyn.", wikipediaURL: URL(string: "https://en.wikipedia.org/wiki/Grand_Prospect_Hall")),
        Landmark(title: "Park Slope Jewish Center", coordinate: .init(latitude: 40.6625, longitude: -73.9859), description: "A historic synagogue in South Slope, Brooklyn."),
        Landmark(title: "Prospect Park", coordinate: .init(latitude: 40.6602, longitude: -73.9797), description: "A public park in Brooklyn, New York City."),
        Landmark(title: "Green-Wood Cemetery", coordinate: .init(latitude: 40.6537, longitude: -73.9899), description: "A historic cemetery in Brooklyn, New York City."),
        Landmark(title: "Public School 39", coordinate: .init(latitude: 40.6703, longitude: -73.9834), description: "A historic school in Park Slope, Brooklyn."),
        Landmark(title: "Old First Reformed Church", coordinate: .init(latitude: 40.6726, longitude: -73.9789), description: "A historic church in Park Slope, Brooklyn.")
    ]
}
#endif
