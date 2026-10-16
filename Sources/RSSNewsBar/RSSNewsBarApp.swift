import AppKit
import SwiftUI

@main
struct RSSNewsBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: FeedStore!
    private var menuBar: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = FeedStore()
        menuBar = MenuBarController(store: store)
    }
}
