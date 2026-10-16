import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: FeedStore
    @State private var newName = ""
    @State private var newURL = ""
    @State private var selectedFeedIDs = Set<UUID>()

    var body: some View {
        TabView {
            feedsTab.tabItem { Label("RSS 源", systemImage: "dot.radiowaves.left.and.right") }
            playbackTab.tabItem { Label("播放", systemImage: "play.circle") }
            appearanceTab.tabItem { Label("外观", systemImage: "textformat") }
        }
        .padding(20)
        .frame(minWidth: 580, minHeight: 500)
    }

    private var feedsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RSS 源列表").font(.title2.bold())
            Text("拖动可以调整顺序；标题滚动只读取标题，不下载正文。下载失败时会保留缓存。").foregroundStyle(.secondary)
            List(selection: $selectedFeedIDs) {
                ForEach($store.feeds) { $feed in
                    HStack {
                        Toggle("", isOn: $feed.enabled).labelsHidden()
                        VStack(alignment: .leading, spacing: 3) {
                            Text(feed.displayName).font(.headline)
                            Text(feed.url).font(.caption).foregroundStyle(.secondary)
                            if let status = store.feedStatuses[feed.id] {
                                Text(status).font(.caption2).foregroundStyle(status.hasPrefix("失败") ? .red : .secondary)
                            }
                        }
                        Spacer()
                        Stepper("\(feed.refreshMinutes) 分钟", value: $feed.refreshMinutes, in: 1...1440, step: 5)
                        Picker("范围", selection: $feed.timeRangeDays) { Text("1 天").tag(1); Text("3 天").tag(3); Text("7 天").tag(7) }.frame(width: 80)
                    }
                }.onDelete(perform: store.deleteFeed).onMove(perform: store.moveFeed)
            }.listStyle(.inset)
            HStack {
                TextField("名称（可选）", text: $newName)
                TextField("https://…", text: $newURL)
                Button("添加") { guard !newURL.isEmpty else { return }; store.addFeed(name: newName, url: newURL); newName = ""; newURL = "" }
            }
            HStack {
                Button("删除选中") { store.deleteFeeds(ids: selectedFeedIDs); selectedFeedIDs.removeAll() }.disabled(selectedFeedIDs.isEmpty)
                Button("立即刷新") { store.refresh() }
                if store.isRefreshing { ProgressView().controlSize(.small) }
                Spacer()
                Button("清理缓存") { store.clearCache() }
            }
            if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
        }
    }

    private var playbackTab: some View {
        Form {
            Section("滚动") {
                HStack { Text("速度"); Slider(value: $store.settings.speed, in: 0.15...1.0); Text(String(format: "%.2fx", store.settings.speed)).monospacedDigit() }
                Toggle("随机（乱序）播放", isOn: $store.settings.randomOrder)
                Toggle("鼠标悬停时使用缓动暂停", isOn: $store.settings.easingPause)
            }
            Section("状态") {
                Text(store.lastRefresh.map { "上次刷新：\($0.formatted(date: .abbreviated, time: .shortened))" } ?? "尚未刷新")
                Text("当前缓存：\(store.headlines.count) 条标题").foregroundStyle(.secondary)
            }
        }
    }

    private var appearanceTab: some View {
        Form {
            Section("菜单栏") {
                HStack {
                    Text("滚动栏宽度")
                    Slider(value: $store.settings.tickerWidth, in: 120...480, step: 10)
                    Text("\(Int(store.settings.tickerWidth)) pt").monospacedDigit().frame(width: 58, alignment: .trailing)
                }
                Toggle("两端渐隐", isOn: $store.settings.fadeEdgesEnabled)
                HStack { Text("字号"); Slider(value: $store.settings.tickerFontSize, in: 10...18, step: 1); Text("\(Int(store.settings.tickerFontSize)) pt") }
                TextField("颜色（例如 #F4F4F4）", text: $store.settings.tickerColorHex)
            }
            Section("来源标识") { Text("每条消息前会显示 RSS 源名称；后续可扩展为自动抓取 favicon，并允许为每个源指定自定义名称。") }
        }
    }
}
