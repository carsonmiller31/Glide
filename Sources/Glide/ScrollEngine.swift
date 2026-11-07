import AppKit
import ApplicationServices
import GlideCore
import QuartzCore

/// Intercepts mouse-wheel events and replaces them with a stream of small,
/// pixel-precise, continuous scroll events, one per display frame.
///
/// - Trackpads and Magic Mouse already send continuous events: passed through.
/// - Our own synthetic events carry `marker` in `eventSourceUserData`: passed through.
/// - ⌘ / ⌃ / ⌥ + wheel is left alone so zoom shortcuts keep working.
final class ScrollEngine: ObservableObject {
    static let shared = ScrollEngine()

    /// "GLID" — tags events we post so the tap lets them through.
    private static let marker: Int64 = 0x474C_4944

    @Published fileprivate(set) var hasPermission = AXIsProcessTrusted()
    @Published fileprivate(set) var isRunning = false

    /// For README screenshots only: show the menu as if the tap were running.
    func showAsRunningForSnapshot() {
        hasPermission = true
        isRunning = true
    }

    private let settings = Settings.shared
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?

    private var animator = ScrollAnimator()
    private var displayLink: CADisplayLink?
    private var lastFrame: CFTimeInterval?
    private var gestureActive = false
    private var gestureHasPhases = false
    /// Modifier flags from the last real wheel event, reapplied to what we post.
    private var flags: CGEventFlags = []

    private init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // MARK: Lifecycle

    func start() {
        if AXIsProcessTrusted() {
            hasPermission = true
            installTap()
        } else {
            hasPermission = false
            requestPermission()
        }
    }

    func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted() else { return }
            timer.invalidate()
            self.permissionTimer = nil
            self.hasPermission = true
            self.installTap()
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func installTap() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let engine = Unmanaged<ScrollEngine>.fromOpaque(refcon!).takeUnretainedValue()
            return engine.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("Glide: could not create event tap (Accessibility permission missing?)")
            hasPermission = false
            requestPermission()
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        NSLog("Glide: event tap installed")
    }

    // MARK: Event handling (main thread)

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // macOS turns slow taps off; turn it straight back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }

        if event.getIntegerValueField(.eventSourceUserData) == Self.marker
            || event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            || !settings.enabled
            || settings.isExcluded(NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
            return Unmanaged.passUnretained(event)
        }

        let mods = event.flags
        if !mods.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            animator.stop()
            return Unmanaged.passUnretained(event)
        }

        var vertical = Self.direction(event, lines: .scrollWheelEventDeltaAxis1, points: .scrollWheelEventPointDeltaAxis1)
        var horizontal = Self.direction(event, lines: .scrollWheelEventDeltaAxis2, points: .scrollWheelEventPointDeltaAxis2)
        guard vertical != 0 || horizontal != 0 else { return Unmanaged.passUnretained(event) }

        // Shift + wheel scrolls sideways (AppKit only does this for line events).
        if mods.contains(.maskShift), horizontal == 0 {
            horizontal = vertical
            vertical = 0
        }
        if settings.reverseDirection {
            vertical = -vertical
            horizontal = -horizontal
        }
        flags = mods.subtracting(.maskShift)

        let now = CACurrentMediaTime()
        let config = settings.config
        if vertical != 0 { animator.notch(axis: .vertical, direction: vertical, at: now, config: config) }
        if horizontal != 0 { animator.notch(axis: .horizontal, direction: horizontal, at: now, config: config) }
        startFrames()
        return nil // swallow the original notch
    }

    private static func direction(_ event: CGEvent, lines: CGEventField, points: CGEventField) -> Int {
        let l = event.getIntegerValueField(lines)
        if l != 0 { return l > 0 ? 1 : -1 }
        let p = event.getIntegerValueField(points)
        if p != 0 { return p > 0 ? 1 : -1 }
        return 0
    }

    // MARK: Frame loop

    private func startFrames() {
        if displayLink == nil { makeDisplayLink() }
        guard let link = displayLink else { return }
        if link.isPaused {
            lastFrame = nil
            link.isPaused = false
        }
    }

    private func makeDisplayLink() {
        displayLink?.invalidate()
        // Drive frames from the fastest screen so ProMotion gets 120 Hz.
        let screen = NSScreen.screens.max { $0.maximumFramesPerSecond < $1.maximumFramesPerSecond }
        guard let screen else { return }
        let link = screen.displayLink(target: self, selector: #selector(frame(_:)))
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func screensChanged() {
        let wasRunning = displayLink.map { !$0.isPaused } ?? false
        displayLink?.invalidate()
        displayLink = nil
        if wasRunning { startFrames() }
    }

    @objc private func frame(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt: Double
        if let lastFrame { dt = now - lastFrame } else { dt = link.targetTimestamp - link.timestamp }
        lastFrame = now

        let delta = animator.frame(dt: min(max(dt, 1.0 / 240), 1.0 / 30), config: settings.config)

        if delta.dx != 0 || delta.dy != 0 {
            let phase: Int64
            if !gestureActive {
                gestureActive = true
                // Sideways phases can trigger "swipe between pages"; keep them off.
                gestureHasPhases = settings.elasticEdges && delta.dx == 0
                phase = 1 // kCGScrollPhaseBegan
            } else {
                phase = 2 // kCGScrollPhaseChanged
            }
            post(dx: delta.dx, dy: delta.dy, phase: gestureHasPhases ? phase : 0)
        }

        if animator.isIdle {
            if gestureActive {
                if gestureHasPhases { post(dx: 0, dy: 0, phase: 4) } // kCGScrollPhaseEnded
                gestureActive = false
            }
            link.isPaused = true
        }
    }

    private func post(dx: Int, dy: Int, phase: Int64) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
            wheel1: Int32(clamping: dy), wheel2: Int32(clamping: dx), wheel3: 0
        ) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        if phase != 0 { event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase) }
        event.flags = flags
        if let location = CGEvent(source: nil)?.location { event.location = location }
        event.post(tap: .cgSessionEventTap)
    }
}
