import AppKit
import Observation
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class QuickCloseModel {
    var applications: [RunningApp] = []
    var isQuitting = false
    var lastResult = "Ready"

    @ObservationIgnored @AppStorage("showBackgroundApps") var showBackgroundApps = false
    @ObservationIgnored @AppStorage("playSounds") var playSounds = true
    @ObservationIgnored @AppStorage("launchAtLogin") var launchAtLogin = false

    init() {
        refresh()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func refresh() {
        applications = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0 != NSRunningApplication.current }
            .compactMap(RunningApp.init)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func quitAll() {
        guard !visibleApplications.isEmpty else { return }
        isQuitting = true
        let targets = visibleApplications
        var sent = 0
        for app in targets where app.application.terminate() { sent += 1 }
        if playSounds { QuitSound.play() }
        lastResult = sent == 1 ? "Asked 1 app to quit" : "Asked \(sent) apps to quit"
        isQuitting = false
        refresh()
    }

    func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    var visibleApplications: [RunningApp] {
        showBackgroundApps ? applications + backgroundApplications : applications
    }

    private var backgroundApplications: [RunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .regular && $0 != NSRunningApplication.current }
            .compactMap(RunningApp.init)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct RunningApp: Identifiable, Hashable {
    let id: pid_t
    let name: String
    let application: NSRunningApplication

    init?(application: NSRunningApplication) {
        guard let name = application.localizedName, !name.isEmpty else { return nil }
        id = application.processIdentifier
        self.name = name
        self.application = application
    }

    static func == (lhs: RunningApp, rhs: RunningApp) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum QuitSound {
    static func play() {
        if let sound = NSSound(named: "Glass") ?? NSSound(named: "Pop") ?? NSSound(named: "Ping") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}

struct QuickClosePanel: View {
    @Bindable var model: QuickCloseModel
    @State private var search = ""

    private var filteredApps: [RunningApp] {
        let source = model.visibleApplications
        guard !search.isEmpty else { return source }
        return source.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            searchField
            appList
            footer
        }
        .frame(width: 340, height: model.showBackgroundApps ? 520 : 410)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
        .task { model.refresh() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("QuickClose").font(.headline).foregroundStyle(Theme.primaryText)
                Text(model.lastResult).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button { model.refresh() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondaryText)
            .accessibilityLabel("Refresh app list")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
            TextField("Search apps", text: $search)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.primaryText)
                .accessibilityLabel("Search running apps")
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var appList: some View {
        Group {
            if filteredApps.isEmpty {
                ContentUnavailableView("No apps found", systemImage: "checkmark.circle", description: Text("Your Mac is clear."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredApps) { app in
                            AppRow(app: app)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button(role: .destructive) { model.quitAll() } label: {
                Label(model.isQuitting ? "Quitting…" : "Quit All Apps", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.danger)
            .disabled(model.visibleApplications.isEmpty || model.isQuitting)
            .keyboardShortcut("q", modifiers: [.command, .option])

            HStack {
                Toggle("Background apps", isOn: $model.showBackgroundApps)
                    .toggleStyle(.switch)
                    .tint(Theme.navigation)
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .accessibilityLabel("Open QuickClose settings")
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(12)
    }
}

private struct AppRow: View {
    let app: RunningApp

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: app.application.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!)
                .resizable().aspectRatio(contentMode: .fit).frame(width: 20, height: 20)
            Text(app.name).font(.body).lineLimit(1).foregroundStyle(Theme.primaryText)
            Spacer()
            Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Theme.active)
        }
        .frame(height: 34)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Running app, \(app.name)")
    }
}

struct QuickCloseSettings: View {
    @Bindable var model: QuickCloseModel

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open QuickClose at login", isOn: $model.launchAtLogin)
                    .onChange(of: model.launchAtLogin) { model.updateLoginItem() }
            }
            Section("Feedback") {
                Toggle("Play a sound after quitting", isOn: $model.playSounds)
            }
            Section("List") {
                Toggle("Show background apps", isOn: $model.showBackgroundApps)
            }
            Section {
                Text("QuickClose asks apps to quit normally so they can save work. Apps may choose not to quit.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .padding()
        .preferredColorScheme(.dark)
    }
}

enum Theme {
    static let panel = Color(red: 0x2D / 255.0, green: 0x35 / 255.0, blue: 0x3B / 255.0)
    static let field = Color(red: 0x3D / 255.0, green: 0x48 / 255.0, blue: 0x4D / 255.0)
    static let border = Color(red: 0x7A / 255.0, green: 0x84 / 255.0, blue: 0x78 / 255.0).opacity(0.35)
    static let primaryText = Color(red: 0xD3 / 255.0, green: 0xC6 / 255.0, blue: 0xAA / 255.0)
    static let secondaryText = Color(red: 0x9D / 255.0, green: 0xA9 / 255.0, blue: 0xA0 / 255.0)
    static let danger = Color(red: 0xE6 / 255.0, green: 0x7E / 255.0, blue: 0x80 / 255.0)
    static let navigation = Color(red: 0x7F / 255.0, green: 0xBB / 255.0, blue: 0xB3 / 255.0)
    static let active = Color(red: 0x83 / 255.0, green: 0xC0 / 255.0, blue: 0x92 / 255.0)
}

#Preview { QuickClosePanel(model: QuickCloseModel()) }
