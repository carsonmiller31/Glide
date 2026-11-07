import AppKit
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var engine: ScrollEngine
    @EnvironmentObject private var apps: FrontmostAppTracker

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if !engine.hasPermission { permissionCard }
            Divider()
            feel
            Divider()
            appsSection
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Glide").font(.headline)
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Smooth scrolling", isOn: $settings.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var status: String {
        if !engine.hasPermission { return "Waiting for Accessibility permission" }
        if !engine.isRunning { return "Starting…" }
        return settings.enabled ? "Smooth scrolling is on" : "Off"
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Glide needs Accessibility access to smooth your mouse wheel.", systemImage: "hand.raised")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text("Turn on Glide in System Settings, Privacy & Security, Accessibility. It starts working as soon as you do.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Accessibility Settings") { engine.openAccessibilitySettings() }
                .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var feel: some View {
        VStack(alignment: .leading, spacing: 12) {
            slider("Distance per notch", value: $settings.stepSize, in: 40...400, step: 10,
                   label: "\(Int(settings.stepSize)) px")
            slider("Smoothness", value: $settings.duration, in: 0.1...0.8, step: 0.05,
                   label: "\(Int(settings.duration * 1000)) ms")
            slider("Acceleration", value: $settings.acceleration, in: 0...1, step: 0.05,
                   label: settings.acceleration == 0 ? "Off" : "\(Int(settings.acceleration * 100))%")
            Toggle("Reverse wheel direction", isOn: $settings.reverseDirection)
            Toggle("Elastic page edges", isOn: $settings.elasticEdges)
                .help("Sends trackpad-style gestures so pages bounce at the top and bottom.")
        }
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>,
                        step: Double, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(label).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            Slider(value: value, in: range, step: step)
                .controlSize(.small)
        }
    }

    @ViewBuilder private var appsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let app = apps.lastApp {
                Toggle("Turn off in \(app.name)", isOn: Binding(
                    get: { settings.isExcluded(app.bundleID) },
                    set: { settings.setExcluded(app, $0) }
                ))
            }
            if !settings.excludedApps.isEmpty {
                Text("Off in these apps").font(.caption).foregroundStyle(.secondary)
                ForEach(settings.excludedApps) { app in
                    HStack {
                        Text(app.name).font(.callout)
                        Spacer()
                        Button {
                            settings.setExcluded(app, false)
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Smooth scroll in \(app.name) again")
                    }
                }
            }
            Toggle("Open at login", isOn: Binding(
                get: { settings.launchAtLogin },
                set: { settings.launchAtLogin = $0 }
            ))
        }
    }

    private var footer: some View {
        HStack {
            Button("Reset to defaults") { settings.resetFeel() }
            Spacer()
            Button("Quit Glide") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .controlSize(.small)
    }
}
