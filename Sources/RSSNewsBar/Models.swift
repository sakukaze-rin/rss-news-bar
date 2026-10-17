import Foundation

struct RSSFeed: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var url: String
    var enabled: Bool = true
    var refreshMinutes: Int = 30
    var timeRangeDays: Int = 3
    var customBadge: String = ""

    var displayName: String {
        if !customBadge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return customBadge }
        if !name.isEmpty { return name }
        return URL(string: url)?.host ?? "RSS"
    }

    var normalizedURL: String {
        url.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "，,。；;")))
    }
}

struct RSSHeadline: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let link: String?
    let publishedAt: Date?
    let sourceName: String
    let sourceID: UUID?

    init(id: UUID = UUID(), title: String, link: String? = nil, publishedAt: Date? = nil, sourceName: String, sourceID: UUID? = nil) {
        self.id = id
        self.title = title
        self.link = link
        self.publishedAt = publishedAt
        self.sourceName = sourceName
        self.sourceID = sourceID
    }

    var playbackKey: String {
        if let link, !link.isEmpty { return link }
        return "\(sourceName)|\(title)"
    }
}

struct AppSettings: Codable {
    var speed: Double = 0.55
    var randomOrder: Bool = false
    var easingPause: Bool = true
    var tickerFontSize: Double = 13
    var tickerColorHex: String = "#F4F4F4"
    var tickerWidth: Double = 190
    var fadeEdgesEnabled: Bool = true

    private enum CodingKeys: String, CodingKey {
        case speed, randomOrder, easingPause, tickerFontSize, tickerColorHex, tickerWidth, fadeEdgesEnabled
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        speed = try values.decodeIfPresent(Double.self, forKey: .speed) ?? 0.55
        randomOrder = try values.decodeIfPresent(Bool.self, forKey: .randomOrder) ?? false
        easingPause = try values.decodeIfPresent(Bool.self, forKey: .easingPause) ?? true
        tickerFontSize = try values.decodeIfPresent(Double.self, forKey: .tickerFontSize) ?? 13
        tickerColorHex = try values.decodeIfPresent(String.self, forKey: .tickerColorHex) ?? "#F4F4F4"
        tickerWidth = try values.decodeIfPresent(Double.self, forKey: .tickerWidth) ?? 190
        fadeEdgesEnabled = try values.decodeIfPresent(Bool.self, forKey: .fadeEdgesEnabled) ?? true
    }
}

enum CacheStore {
    static let feedsKey = "RSSNewsBar.feeds"
    static let settingsKey = "RSSNewsBar.settings"
    static let headlinesKey = "RSSNewsBar.headlines"
}
