import Foundation
import SwiftUI

@MainActor
final class FeedStore: ObservableObject {
    @Published var feeds: [RSSFeed] {
        didSet { save(feeds, key: CacheStore.feedsKey) }
    }
    @Published var settings: AppSettings {
        didSet { save(settings, key: CacheStore.settingsKey) }
    }
    @Published private(set) var headlines: [RSSHeadline] = []
    @Published private(set) var newHeadlineKeys: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var feedStatuses: [UUID: String] = [:]
    @Published var lastRefresh: Date?
    @Published var errorMessage: String?

    private var refreshTask: Task<Void, Never>?

    init() {
        feeds = Self.load([RSSFeed(name: "CNBeta", url: "https://rss.cnbeta.com.tw/"),], key: CacheStore.feedsKey)
        settings = Self.load(AppSettings(), key: CacheStore.settingsKey)
        headlines = Self.load([], key: CacheStore.headlinesKey)
        feeds = feeds.map { feed in
            var normalized = feed
            normalized.url = feed.normalizedURL
            return normalized
        }
    }

    func refresh() {
        refreshTask?.cancel()
        let activeFeeds = feeds.filter(\.enabled)
        guard !activeFeeds.isEmpty else { return }
        let previousKeys = Set(headlines.map(\.playbackKey))
        isRefreshing = true
        errorMessage = nil
        refreshTask = Task { [weak self] in
            guard let self else { return }
            var all: [RSSHeadline] = []
            var failures = 0
            for feed in activeFeeds {
                if Task.isCancelled { return }
                self.feedStatuses[feed.id] = "刷新中…"
                do {
                    let newItems = try await RSSFeedService.fetch(feed: feed)
                    all.append(contentsOf: newItems)
                    self.feedStatuses[feed.id] = "成功 · \(newItems.count) 条"
                } catch {
                    failures += 1
                    self.feedStatuses[feed.id] = "失败 · \(Self.describe(error))"
                }
            }
            let sorted = all.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            let refreshedKeys = Set(sorted.map(\.playbackKey))
            self.newHeadlineKeys.formIntersection(refreshedKeys)
            self.newHeadlineKeys.formUnion(refreshedKeys.subtracting(previousKeys))
            self.headlines = sorted
            self.lastRefresh = Date()
            self.isRefreshing = false
            self.save(sorted, key: CacheStore.headlinesKey)
            if failures == activeFeeds.count { self.errorMessage = "暂时无法获取 RSS，请检查网络或源地址。" }
        }
    }

    func clearCache() {
        headlines = []
        newHeadlineKeys = []
        UserDefaults.standard.removeObject(forKey: CacheStore.headlinesKey)
    }

    func moveFeed(from offsets: IndexSet, to destination: Int) { feeds.move(fromOffsets: offsets, toOffset: destination) }
    func deleteFeed(at offsets: IndexSet) { feeds.remove(atOffsets: offsets) }
    func deleteFeeds(ids: Set<UUID>) {
        feeds.removeAll { ids.contains($0.id) }
        ids.forEach { feedStatuses.removeValue(forKey: $0) }
    }
    func addFeed(name: String, url: String) {
        let normalizedURL = url.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "，,。；;")))
        feeds.append(RSSFeed(name: name.isEmpty ? (URL(string: normalizedURL)?.host ?? "RSS") : name, url: normalizedURL))
    }

    func isNew(_ headline: RSSHeadline) -> Bool { newHeadlineKeys.contains(headline.playbackKey) }

    func markPlayed(key: String) { newHeadlineKeys.remove(key) }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T, key: String) -> T {
        guard let data = UserDefaults.standard.data(forKey: key), let value = try? JSONDecoder().decode(T.self, from: data) else { return type }
        return value
    }

    private static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "请求超时"
            case .cannotFindHost, .dnsLookupFailed: return "找不到主机"
            case .notConnectedToInternet: return "无网络"
            case .badServerResponse: return "服务器响应异常"
            default: return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
