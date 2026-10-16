import Foundation

enum RSSFeedService {
    static func fetch(feed: RSSFeed) async throws -> [RSSHeadline] {
        guard let url = URL(string: feed.normalizedURL) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("RSSNewsBar/0.2-beta", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try RSSParser(data: data, feed: feed).parse()
    }
}

final class RSSParser: NSObject, XMLParserDelegate {
    private let data: Data
    private let feed: RSSFeed
    private var parser: XMLParser!
    private var currentElement = ""
    private var buffer = ""
    private var title = ""
    private var link: String?
    private var date: Date?
    private var inItem = false
    private var items: [RSSHeadline] = []
    private var linkAttribute: String?

    init(data: Data, feed: RSSFeed) { self.data = data; self.feed = feed }

    func parse() throws -> [RSSHeadline] {
        parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { throw parser.parserError ?? URLError(.cannotParseResponse) }
        let cutoff = Calendar.current.date(byAdding: .day, value: -feed.timeRangeDays, to: Date()) ?? .distantPast
        return items.filter { ($0.publishedAt ?? Date()) >= cutoff }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName.lowercased()
        if currentElement == "item" || currentElement == "entry" {
            inItem = true; title = ""; link = nil; date = nil
        }
        if currentElement == "link" { linkAttribute = attributeDict["href"] }
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = elementName.lowercased()
        guard inItem else { return }
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch element {
        case "title": title = value
        case "link": link = value.isEmpty ? linkAttribute : value; linkAttribute = nil
        case "pubdate", "published", "updated", "dc:date": date = RSSParser.parseDate(value)
        case "item", "entry":
            if !title.isEmpty { items.append(RSSHeadline(title: title, link: link, publishedAt: date, sourceName: feed.displayName)) }
            inItem = false
        default: break
        }
        buffer = ""
    }

    private static func parseDate(_ value: String) -> Date? {
        let formats = ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm Z", "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"]
        for format in formats {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return ISO8601DateFormatter().date(from: value)
    }
}
