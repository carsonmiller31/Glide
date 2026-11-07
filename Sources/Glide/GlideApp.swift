import AppKit
import SwiftUI

@main
struct GlideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var settings = Settings.shared
    @StateObject private var engine = ScrollEngine.shared
    @StateObject private var apps = FrontmostAppTracker.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(settings)
                .environmentObject(engine)
                .environmentObject(apps)
        } label: {
            Image(systemName: settings.enabled && engine.isRunning ? "computermouse.fill" : "computermouse")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = FrontmostAppTracker.shared
        ScrollEngine.shared.start()
    }
}

/// Remembers the last app the user was in, so the menu can offer to turn
/// Glide off for it (opening our menu does not count).
final class FrontmostAppTracker: ObservableObject {
    static let shared = FrontmostAppTracker()
    @Published private(set) var lastApp: ExcludedApp?

    private init() {
        update(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.update(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
    }

    private func update(_ app: NSRunningApplication?) {
        guard let app, let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
        lastApp = ExcludedApp(bundleID: id, name: app.localizedName ?? id)
    }
}
