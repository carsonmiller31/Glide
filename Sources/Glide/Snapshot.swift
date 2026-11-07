import AppKit
import SwiftUI

/// Renders the menu to a PNG for the README:
/// `GLIDE_SNAPSHOT=docs/menu.png build/Glide.app/Contents/MacOS/Glide`
/// Never starts the event tap or asks for permission.
enum Snapshot {
    static func render(to path: String) {
        ScrollEngine.shared.showAsRunningForSnapshot()
        FrontmostAppTracker.shared.showForSnapshot(ExcludedApp(bundleID: "com.apple.Safari", name: "Safari"))

        let content = MenuView()
            .environmentObject(Settings.shared)
            .environmentObject(ScrollEngine.shared)
            .environmentObject(FrontmostAppTracker.shared)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))

        let host = NSHostingView(rootView: content)
        host.frame.size = host.fittingSize
        // Controls only draw in colour in the key window, so make this one key, off screen.
        let window = KeyWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        host.display()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
