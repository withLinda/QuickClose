import AppKit
import SwiftUI

struct QuickClosePanel: View {
    @Bindable var model: QuickCloseModel
    @State private var search = ""
    @State private var confirmsEmptyTrash = false

    private var groups: [AppGroup] { model.groups(matching: search) }
    private var selectedApps: [RunningApp] { model.selectedApps(in: groups) }
    private var rowCount: Int {
        groups.count + (model.preferences.includeFinderWindows ? 1 : 0) + (model.preferences.includeEmptyTrash ? 1 : 0)
    }
    private var panelHeight: CGFloat {
        let maxListHeight = max(84, min(820, (NSScreen.main?.visibleFrame.height ?? 900) - 170))
        let listHeight = min(max(CGFloat(max(rowCount, 1)) * 30, 60), maxListHeight)
        return 96 + listHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            appList
            footer
        }
        .frame(width: 280, height: panelHeight)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
        .task { model.refresh() }
        .alert("Empty Trash?", isPresented: $confirmsEmptyTrash) {
            Button("Cancel", role: .cancel) {}
            Button("Empty Trash", role: .destructive) { Task { await model.runExtra(.emptyTrash) } }
        } message: {
            Text("The items in the Trash will be permanently deleted.")
        }
    }

    private var header: some View {
        Button { model.quit(selectedApps) } label: {
            Text(model.isQuitting ? "Quitting…" : "\(model.quitMode.title) All")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(QuitButtonStyle())
        .tint(Theme.accent)
        .foregroundStyle(Theme.onAccent)
        .disabled(selectedApps.isEmpty || model.isQuitting)
        .keyboardShortcut("q", modifiers: [.command, .option])
        .accessibilityLabel("\(model.quitMode.title) all selected apps")
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 5)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Toggle("Select all visible apps", isOn: Binding(
                get: { !groups.isEmpty && groups.filter { !$0.apps.allSatisfy(model.isProtected) }.allSatisfy(model.isSelected) },
                set: { _ in model.toggleSelection(groups) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .tint(Theme.accent)
            .disabled(groups.isEmpty)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
                TextField("Search running apps", text: $search, prompt: Text("Search apps").foregroundStyle(Theme.secondaryText))
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.primaryText)
                    .accessibilityLabel("Search running apps")
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if groups.isEmpty && !model.preferences.includeFinderWindows && !model.preferences.includeEmptyTrash {
                    VStack(spacing: 4) {
                        Text(search.isEmpty ? "No running apps" : "No matching apps").foregroundStyle(Theme.primaryText)
                        Text(search.isEmpty ? "Your workspace is clear." : "Try a different search.").font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                }
                ForEach(groups) { group in
                    AppRow(
                        group: group,
                        isSelected: model.isSelected(group),
                        isProtected: group.apps.allSatisfy(model.isProtected),
                        isPending: group.apps.contains { model.pendingQuitIDs.contains($0.id) },
                        onToggleSelection: { model.toggleSelection([group]) },
                        onQuit: { model.quit(group.apps) }
                    )
                }
                if model.preferences.includeFinderWindows {
                    ExtraRow(action: .closeWindows) { Task { await model.runExtra(.closeWindows) } }.disabled(model.isRunningExtra)
                }
                if model.preferences.includeEmptyTrash {
                    ExtraRow(action: .emptyTrash) { confirmsEmptyTrash = true }.disabled(model.isRunningExtra)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(model.lastResult ?? (model.preferences.disableQuitTips ? "\(selectedApps.count) selected" : "Ready when you are"))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .help(model.lastResult ?? "Select apps above, or quit one using its row button.")
            Spacer(minLength: 4)
            Menu {
                Toggle("Show background apps", isOn: $model.preferences.showBackgroundApps)
                    .keyboardShortcut("b", modifiers: .command)
                Button("Refresh apps", systemImage: "arrow.clockwise") { model.refresh() }
                Divider()
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                Button("Help") {
                    if let url = URL(string: "https://github.com/withLinda/QuickClose#behavior") { NSWorkspace.shared.open(url) }
                }
                Divider()
                Button("Quit", systemImage: "power") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.secondaryText)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("QuickClose menu")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider().overlay(Theme.border) }
    }
}

private struct QuitButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Theme.onAccent : Theme.secondaryText)
            .frame(height: 24)
            .background(isEnabled ? Theme.accent : Theme.field, in: RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct AppRow: View {
    let group: AppGroup
    let isSelected: Bool
    let isProtected: Bool
    let isPending: Bool
    let onToggleSelection: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Button(action: onToggleSelection) {
                Image(systemName: isProtected ? "lock.fill" : (isSelected ? "checkmark.square.fill" : "square"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isProtected ? Theme.secondaryText : (isSelected ? Theme.accent : Theme.secondaryText))
                    .frame(width: 18, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isProtected)
            .accessibilityLabel(isProtected ? "Protected app, \(group.name)" : (isSelected ? "Exclude \(group.title) from quit" : "Include \(group.title) in quit"))

            Image(nsImage: group.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!)
                .resizable().aspectRatio(contentMode: .fit).frame(width: 18, height: 18)
            Text(group.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 3)
            if isPending { ProgressView().controlSize(.mini) }
            Button(action: onQuit) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(isProtected ? Theme.field : Theme.secondaryText)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isProtected || isPending)
            .accessibilityLabel("Quit \(group.title)")
            .help(isProtected ? "Music app protected in Settings" : "Quit \(group.title) using the default quit action")
        }
        .frame(height: 30)
        .padding(.horizontal, 12)
    }
}

private struct ExtraRow: View {
    let action: FinderAction
    let run: () -> Void
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: action.symbol).frame(width: 18).foregroundStyle(Theme.secondaryText)
            Text(action.title).font(.system(size: 13)).foregroundStyle(Theme.primaryText)
            Spacer()
            Button("Run", action: run).buttonStyle(.borderless).foregroundStyle(Theme.accent)
        }
        .frame(height: 30)
        .padding(.horizontal, 12)
    }
}

struct QuickCloseSettings: View {
    @Bindable var model: QuickCloseModel
    var body: some View {
        TabView {
            GeneralSettings(model: model).tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsSettings().tabItem { Label("Shortcuts", systemImage: "command") }
            SupportSettings().tabItem { Label("Support", systemImage: "bubble.left.and.bubble.right") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 400, height: 466)
        .tint(Theme.accent)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
    }
}

private struct GeneralSettings: View {
    @Bindable var model: QuickCloseModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                SettingsLine(label: "Startup:") {
                    Toggle("Open QuickClose at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })).toggleStyle(.checkbox)
                }
                if let loginMessage = model.loginMessage { Text(loginMessage).font(.caption).foregroundStyle(Theme.secondaryText).padding(.leading, 78) }
                SettingsLine(label: "Sounds:") { Toggle("Play cool sounds", isOn: $model.preferences.playSounds).toggleStyle(.checkbox) }
                SettingsLine(label: "Advanced:") { Toggle("View background apps", isOn: $model.preferences.showBackgroundApps).toggleStyle(.checkbox) }
                SettingsLine(label: "") { Toggle("Group background instances", isOn: $model.preferences.groupBackgroundInstances).toggleStyle(.checkbox) }
                SettingsLine(label: "") { Toggle("Never quit music apps", isOn: $model.preferences.neverQuitMusicApps).toggleStyle(.checkbox) }
                SettingsLine(label: "") { Toggle("Deselect apps by default", isOn: $model.preferences.deselectAppsByDefault).toggleStyle(.checkbox) }
                SettingsLine(label: "") { Toggle("Disable quit tips", isOn: $model.preferences.disableQuitTips).toggleStyle(.checkbox) }
                SettingsLine(label: "Extras:") { Toggle("Include Finder Windows in list", isOn: $model.preferences.includeFinderWindows).toggleStyle(.checkbox) }
                SettingsLine(label: "") { Toggle("Include Empty Trash in list", isOn: $model.preferences.includeEmptyTrash).toggleStyle(.checkbox) }
                SettingsLine(label: "Auto Quit:") { Toggle("Quit inactive apps after", isOn: $model.preferences.autoQuitEnabled).toggleStyle(.checkbox) }
                SettingsLine(label: "") {
                    HStack(spacing: 4) {
                        Stepper(value: $model.preferences.autoQuitInterval, in: 1...24) { Text("\(model.preferences.autoQuitInterval)") }.frame(width: 90)
                        Picker("Unit", selection: $model.preferences.autoQuitUnit) { ForEach(IdleUnit.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 92)
                    }
                    .disabled(!model.preferences.autoQuitEnabled)
                }
                SettingsLine(label: "Sort:") { Picker("Sort", selection: $model.preferences.sortOrder) { ForEach(AppSortOrder.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 185) }
                SettingsLine(label: "Default:") {
                    Picker("Default", selection: $model.preferences.quitMode) {
                        ForEach(QuitMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 185)
                    .help(model.quitMode.explanation)
                }
                SettingsLine(label: "Reset:") { Button("Reset all") { model.resetPreferences() }.controlSize(.small) }
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(Theme.panel)
        .foregroundStyle(Theme.primaryText)
        .controlSize(.small)
    }
}

private struct SettingsLine<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primaryText).frame(width: 68, alignment: .trailing)
            content()
            Spacer(minLength: 0)
        }.frame(minHeight: 26)
    }
}

private struct ShortcutsSettings: View {
    var body: some View {
        Form {
            Section("Quick actions") {
                LabeledContent("Quit selected apps") { Text("⌘⌥Q").foregroundStyle(Theme.secondaryText) }
                LabeledContent("Quit QuickClose") { Text("⌘Q").foregroundStyle(Theme.secondaryText) }
            }
        }.formStyle(.grouped).scrollContentBackground(.hidden).background(Theme.panel)
    }
}

private struct SupportSettings: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "questionmark.circle").font(.system(size: 34)).foregroundStyle(Theme.accent)
            Text("Need help?").font(.title3.weight(.semibold)).foregroundStyle(Theme.primaryText)
            Text("Normal Quit lets apps save work; Force Close ends them immediately.").multilineTextAlignment(.center).foregroundStyle(Theme.secondaryText).frame(maxWidth: 300)
            Button("Open help") { if let url = URL(string: "https://github.com/withLinda/QuickClose#behavior") { NSWorkspace.shared.open(url) } }.buttonStyle(.borderedProminent).tint(Theme.accent)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding().background(Theme.panel)
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "power.circle.fill").font(.system(size: 42)).foregroundStyle(Theme.accent)
            Text("QuickClose").font(.title2.weight(.semibold)).foregroundStyle(Theme.primaryText)
            Text("A quiet menu-bar utility for clearing your workspace.").multilineTextAlignment(.center).foregroundStyle(Theme.secondaryText)
            Text("Version 1.0").font(.caption).foregroundStyle(Theme.secondaryText)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding().background(Theme.panel)
    }
}

enum Theme {
    static let panelHex: UInt32 = 0x1E2326
    static let fieldHex: UInt32 = 0x272E33
    static let primaryTextHex: UInt32 = 0xD3C6AA
    static let secondaryTextHex: UInt32 = 0x9DA9A0
    static let accentHex: UInt32 = 0xE69875
    static let panel = color(panelHex)
    static let field = color(fieldHex)
    static let border = Color(red: 0x7A / 255.0, green: 0x84 / 255.0, blue: 0x78 / 255.0).opacity(0.45)
    static let primaryText = color(primaryTextHex)
    static let secondaryText = color(secondaryTextHex)
    static let accent = color(accentHex)
    static let onAccent = panel

    private static func color(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

#Preview { QuickClosePanel(model: QuickCloseModel(monitorWorkspace: false)) }
