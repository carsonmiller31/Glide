import Foundation
import GlideCore
import ServiceManagement

struct ExcludedApp: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

/// User preferences, persisted to UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    @Published var stepSize: Double { didSet { defaults.set(stepSize, forKey: "stepSize") } }
    /// Seconds.
    @Published var duration: Double { didSet { defaults.set(duration, forKey: "duration") } }
    /// 0...1
    @Published var acceleration: Double { didSet { defaults.set(acceleration, forKey: "acceleration") } }
    /// Flip the wheel direction for mice only (trackpad stays as macOS sets it).
    @Published var reverseDirection: Bool { didSet { defaults.set(reverseDirection, forKey: "reverseDirection") } }
    /// Send trackpad-style gesture phases so pages rubber-band at their edges.
    @Published var elasticEdges: Bool { didSet { defaults.set(elasticEdges, forKey: "elasticEdges") } }
    @Published var excludedApps: [ExcludedApp] {
        didSet {
            excludedIDs = Set(excludedApps.map(\.bundleID))
            defaults.set(try? JSONEncoder().encode(excludedApps), forKey: "excludedApps")
        }
    }
    private(set) var excludedIDs: Set<String> = []

    static let defaultConfig = ScrollConfig(stepSize: 120, duration: 0.35, acceleration: 0.5)

    private init() {
        defaults.register(defaults: [
            "enabled": true,
            "stepSize": Self.defaultConfig.stepSize,
            "duration": Self.defaultConfig.duration,
            "acceleration": Self.defaultConfig.acceleration,
            "reverseDirection": false,
            "elasticEdges": false,
        ])
        enabled = defaults.bool(forKey: "enabled")
        stepSize = defaults.double(forKey: "stepSize")
        duration = defaults.double(forKey: "duration")
        acceleration = defaults.double(forKey: "acceleration")
        reverseDirection = defaults.bool(forKey: "reverseDirection")
        elasticEdges = defaults.bool(forKey: "elasticEdges")
        let apps = defaults.data(forKey: "excludedApps")
            .flatMap { try? JSONDecoder().decode([ExcludedApp].self, from: $0) } ?? []
        excludedApps = apps
        excludedIDs = Set(apps.map(\.bundleID))
    }

    var config: ScrollConfig {
        ScrollConfig(stepSize: stepSize, duration: duration, acceleration: acceleration)
    }

    func resetFeel() {
        stepSize = Self.defaultConfig.stepSize
        duration = Self.defaultConfig.duration
        acceleration = Self.defaultConfig.acceleration
        reverseDirection = false
        elasticEdges = false
    }

    func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedIDs.contains(bundleID)
    }

    func setExcluded(_ app: ExcludedApp, _ excluded: Bool) {
        if excluded {
            if !excludedIDs.contains(app.bundleID) { excludedApps.append(app) }
        } else {
            excludedApps.removeAll { $0.bundleID == app.bundleID }
        }
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Glide: launch at login change failed: \(error)")
            }
        }
    }
}
