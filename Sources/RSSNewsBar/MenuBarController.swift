import AppKit
import SwiftUI

final class TickerView: NSView {
    private let fadeMask = CAGradientLayer()

    var text = "RSS NewsBar"
    var textColor: NSColor = .labelColor
    var font: NSFont = .systemFont(ofSize: 13)
    var isIconOnly = false { didSet { updateFadeMask(); needsDisplay = true } }
    var fadeEdgesEnabled = true { didSet { updateFadeMask() } }
    var isHovered = false { didSet { if oldValue != isHovered { onHover?(isHovered) } } }
    var onHover: ((Bool) -> Void)?
    var onLeftClick: ((CGFloat) -> Void)?
    var onRightClick: (() -> Void)?
    var onScroll: ((CGFloat) -> Void)?
    var scrollOffset: CGFloat = 0 { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        fadeMask.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        updateFadeMask()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        fadeMask.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        updateFadeMask()
    }

    override func layout() {
        super.layout()
        updateFadeMask()
    }

    private func updateFadeMask() {
        guard fadeEdgesEnabled, !isIconOnly else {
            layer?.mask = nil
            return
        }
        let fadeDistance = min(28, max(14, bounds.width * 0.10))
        let fadeFraction = fadeDistance / max(bounds.width, 1)
        fadeMask.frame = bounds
        fadeMask.locations = [0, NSNumber(value: fadeFraction), NSNumber(value: 1 - fadeFraction), 1]
        layer?.mask = fadeMask
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onRightClick?()
            return
        }
        onLeftClick?(convert(event.locationInWindow, from: nil).x)
    }
    override func rightMouseDown(with event: NSEvent) { onRightClick?() }
    override func scrollWheel(with event: NSEvent) {
        let primaryDelta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : event.scrollingDeltaY
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1.5 : 8
        onScroll?(-primaryDelta * scale)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isIconOnly {
            let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let icon = NSImage(systemSymbolName: "dot.radiowaves.left.and.right", accessibilityDescription: "RSS NewsBar")?
                .withSymbolConfiguration(configuration)
            let iconSize = icon?.size ?? NSSize(width: 14, height: 14)
            icon?.draw(
                in: NSRect(
                    x: (bounds.width - iconSize.width) / 2,
                    y: (bounds.height - iconSize.height) / 2,
                    width: iconSize.width,
                    height: iconSize.height
                )
            )
            return
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph]
        let size = (text as NSString).size(withAttributes: attributes)
        let point = NSPoint(x: 8 - scrollOffset, y: (bounds.height - size.height) / 2)
        (text as NSString).draw(at: point, withAttributes: attributes)
    }
}

@MainActor
final class MenuBarController: NSObject, NSWindowDelegate {
    private static let headlineSeparator = "     ◆     "
    private static let versionLabel = "RSS NewsBar · v0.2.1 beta"

    private struct TickerQueueItem {
        let key: String
        let text: String
        let link: String?
    }

    private let store: FeedStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let ticker = TickerView(frame: NSRect(x: 0, y: 0, width: 190, height: 22))
    private var timer: Timer?
    private var refreshTimer: Timer?
    private var headlineIndex = 0
    private var settingsWindow: NSWindow?
    private var velocityScale: CGFloat = 1
    private var targetVelocityScale: CGFloat = 1
    private var tickerQueue: [TickerQueueItem] = []
    private var tickerHistory: [TickerQueueItem] = []
    private var recentHeadlineKeys: [String] = []
    private var lastRandomSource: String?
    private var fadeMenuItem: NSMenuItem?
    private var minimizeMenuItem: NSMenuItem?
    private var contextMenu: NSMenu?
    private var isMinimized = false

    init(store: FeedStore) {
        self.store = store
        super.init()
        NSApp.setActivationPolicy(.accessory)
        statusItem.view = ticker
        contextMenu = makeMenu()
        ticker.onHover = { [weak self] hovered in self?.setHovered(hovered) }
        ticker.onLeftClick = { [weak self] x in self?.openHeadline(at: x) }
        ticker.onRightClick = { [weak self] in self?.showMenu() }
        ticker.onScroll = { [weak self] delta in self?.scrollTicker(by: delta) }
        store.$settings.sink { [weak self] settings in self?.applyAppearance(settings) }.store(in: &cancellables)
        startTicker()
        scheduleRefresh()
        store.refresh()
    }

    private var cancellables: Set<AnyCancellable> = []

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let version = NSMenuItem(title: Self.versionLabel, action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(.separator())
        let refresh = NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r"); refresh.target = self; menu.addItem(refresh)
        let settings = NSMenuItem(title: "管理 RSS…", action: #selector(openSettings), keyEquivalent: ","); settings.target = self; menu.addItem(settings)
        let fade = NSMenuItem(title: "两端渐隐", action: #selector(toggleEdgeFade), keyEquivalent: "")
        fade.target = self
        fade.state = store.settings.fadeEdgesEnabled ? .on : .off
        fadeMenuItem = fade
        menu.addItem(fade)
        let minimize = NSMenuItem(title: "最小化为图标", action: #selector(toggleMinimized), keyEquivalent: "")
        minimize.target = self
        minimizeMenuItem = minimize
        menu.addItem(minimize)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 RSS NewsBar", action: #selector(quit), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
        return menu
    }

    private func startTicker() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.advanceTicker() }
        }
    }

    private func advanceTicker() {
        guard !store.headlines.isEmpty else {
            tickerQueue.removeAll()
            ticker.text = store.isRefreshing ? "正在刷新 RSS…" : "RSS NewsBar · 暂无新闻"
            ticker.scrollOffset = 0
            return
        }

        if tickerQueue.isEmpty {
            fillTickerQueue()
            ticker.scrollOffset = -ticker.bounds.width
        }

        let easing: CGFloat = store.settings.easingPause ? 0.12 : 1
        velocityScale += (targetVelocityScale - velocityScale) * easing
        ticker.scrollOffset += CGFloat(0.7 + store.settings.speed * 2.2) * velocityScale

        normalizeTickerPosition()
    }

    private func fillTickerQueue() {
        while tickerQueue.count < 4 {
            let headline = nextHeadline()
            let newBadge = store.isNew(headline) ? "🆕 " : ""
            tickerQueue.append(TickerQueueItem(
                key: headline.playbackKey,
                text: "\(headline.sourceName)  ·  \(newBadge)\(headline.title)",
                link: headline.link
            ))
        }
        ticker.text = tickerQueue.map(\.text).joined(separator: Self.headlineSeparator) + Self.headlineSeparator
    }

    private func nextHeadline() -> RSSHeadline {
        guard store.settings.randomOrder else {
            let headline = store.headlines[headlineIndex % store.headlines.count]
            headlineIndex += 1
            return headline
        }

        let queuedKeys = Set(tickerQueue.map(\.key))
        let recentKeys = Set(recentHeadlineKeys)
        let groups = Dictionary(grouping: store.headlines, by: \.sourceName)
        var sources = Array(groups.keys)
        if sources.count > 1, let lastRandomSource {
            sources.removeAll { $0 == lastRandomSource }
        }
        sources.shuffle()

        for source in sources {
            guard let sourceHeadlines = groups[source] else { continue }
            let freshCandidates = sourceHeadlines.filter {
                !queuedKeys.contains($0.playbackKey) && !recentKeys.contains($0.playbackKey)
            }
            let candidates = freshCandidates.isEmpty
                ? sourceHeadlines.filter { !queuedKeys.contains($0.playbackKey) }
                : freshCandidates
            if let headline = candidates.randomElement() {
                lastRandomSource = source
                return headline
            }
        }

        let fallback = store.headlines.filter { !queuedKeys.contains($0.playbackKey) }.randomElement()
            ?? store.headlines.randomElement()!
        lastRandomSource = fallback.sourceName
        return fallback
    }

    private func rememberRecentlyPlayed(_ key: String) {
        recentHeadlineKeys.removeAll { $0 == key }
        recentHeadlineKeys.append(key)
        if recentHeadlineKeys.count > 20 { recentHeadlineKeys.removeFirst() }
    }

    private func segmentWidth(for item: TickerQueueItem) -> CGFloat {
        ((item.text + Self.headlineSeparator) as NSString).size(withAttributes: [.font: ticker.font]).width
    }

    private func normalizeTickerPosition() {
        while let first = tickerQueue.first, ticker.scrollOffset >= segmentWidth(for: first) {
            ticker.scrollOffset -= segmentWidth(for: first)
            let played = tickerQueue.removeFirst()
            tickerHistory.append(played)
            if tickerHistory.count > 30 { tickerHistory.removeFirst() }
            store.markPlayed(key: played.key)
            rememberRecentlyPlayed(played.key)
            fillTickerQueue()
        }

        while ticker.scrollOffset < 0, let previous = tickerHistory.popLast() {
            tickerQueue.insert(previous, at: 0)
            ticker.scrollOffset += segmentWidth(for: previous)
            ticker.text = tickerQueue.map(\.text).joined(separator: Self.headlineSeparator) + Self.headlineSeparator
        }
    }

    private func scrollTicker(by delta: CGFloat) {
        guard !isMinimized, !tickerQueue.isEmpty else { return }
        ticker.scrollOffset += delta
        normalizeTickerPosition()
    }

    private func openHeadline(at viewX: CGFloat) {
        guard !isMinimized, !tickerQueue.isEmpty else { return }
        var contentX = viewX - 8 + ticker.scrollOffset
        guard contentX >= 0 else { return }
        let separatorWidth = (Self.headlineSeparator as NSString).size(withAttributes: [.font: ticker.font]).width

        for item in tickerQueue {
            let textWidth = (item.text as NSString).size(withAttributes: [.font: ticker.font]).width
            if contentX <= textWidth {
                guard let link = item.link,
                      let url = URL(string: link),
                      ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
                NSWorkspace.shared.open(url)
                return
            }
            contentX -= textWidth + separatorWidth
            if contentX < 0 { return }
        }
    }

    private func setHovered(_ hovered: Bool) {
        targetVelocityScale = hovered ? 0 : 1
        if !store.settings.easingPause { velocityScale = targetVelocityScale }
    }

    private func showMenu() {
        guard let menu = contextMenu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: ticker.bounds.minY), in: ticker)
    }

    private func scheduleRefresh() {
        refreshTimer?.invalidate()
        let minutes = max(1, store.feeds.map(\.refreshMinutes).min() ?? 30)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.store.refresh() }
        }
    }

    private func applyAppearance(_ settings: AppSettings) {
        ticker.font = .systemFont(ofSize: settings.tickerFontSize)
        ticker.textColor = NSColor(hex: settings.tickerColorHex) ?? .labelColor
        ticker.fadeEdgesEnabled = settings.fadeEdgesEnabled
        fadeMenuItem?.state = settings.fadeEdgesEnabled ? .on : .off
        ticker.isIconOnly = isMinimized
        minimizeMenuItem?.title = isMinimized ? "恢复滚动条" : "最小化为图标"
        let width = isMinimized ? 28 : min(max(settings.tickerWidth, 120), 480)
        statusItem.length = width
        ticker.frame.size.width = width
        ticker.toolTip = isMinimized
            ? "RSS NewsBar · 右键恢复滚动条"
            : "点击标题打开链接 · 右键打开菜单 · 滚轮回看或跳过"
        ticker.needsDisplay = true
    }

    @objc private func refreshNow() { store.refresh() }
    @objc private func toggleEdgeFade() { store.settings.fadeEdgesEnabled.toggle() }
    @objc private func toggleMinimized() {
        isMinimized.toggle()
        applyAppearance(store.settings)
    }
    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(store: store)
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.title = "RSS NewsBar v0.2.1 beta 设置"; window.styleMask = [.titled, .closable, .resizable]; window.setContentSize(NSSize(width: 620, height: 560)); window.center(); window.delegate = self
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func windowWillClose(_ notification: Notification) { settingsWindow = nil }
}

import Combine
extension NSColor {
    convenience init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if value.count == 6 { value += "FF" }
        guard value.count == 8, let number = UInt64(value, radix: 16) else { return nil }
        self.init(red: CGFloat((number >> 24) & 255) / 255, green: CGFloat((number >> 16) & 255) / 255, blue: CGFloat((number >> 8) & 255) / 255, alpha: CGFloat(number & 255) / 255)
    }
}
