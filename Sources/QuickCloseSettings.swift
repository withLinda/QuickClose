import SwiftUI

struct QuickCloseSettings: View {
    let model: QuickCloseModel

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
                checkbox("Open QuickClose at login", label: "Startup:",
                         isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                if let loginMessage = model.loginMessage {
                    Text(loginMessage).font(.caption).foregroundStyle(Theme.secondaryText).padding(.leading, 78)
                }
                checkbox("Play cool sounds", label: "Sounds:", isOn: $model.preferences.playSounds)
                checkbox("View background apps", label: "Advanced:", isOn: $model.preferences.showBackgroundApps)
                checkbox("Group background instances", isOn: $model.preferences.groupBackgroundInstances)
                checkbox("Never quit music apps", isOn: $model.preferences.neverQuitMusicApps)
                checkbox("Deselect apps by default", isOn: $model.preferences.deselectAppsByDefault)
                checkbox("Disable quit tips", isOn: $model.preferences.disableQuitTips)
                checkbox("Include Finder Windows in list", label: "Extras:", isOn: $model.preferences.includeFinderWindows)
                checkbox("Include Empty Trash in list", isOn: $model.preferences.includeEmptyTrash)
                checkbox("Quit inactive apps after", label: "Auto Quit:", isOn: $model.preferences.autoQuitEnabled)
                SettingsLine(label: "") {
                    HStack(spacing: 4) {
                        Stepper(value: $model.preferences.autoQuitInterval, in: 1...24) {
                            Text("\(model.preferences.autoQuitInterval)")
                        }.frame(width: 90)
                        Picker("Unit", selection: $model.preferences.autoQuitUnit) {
                            ForEach(IdleUnit.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().frame(width: 92)
                    }
                    .disabled(!model.preferences.autoQuitEnabled)
                }
                SettingsLine(label: "Sort:") {
                    Picker("Sort", selection: $model.preferences.sortOrder) {
                        ForEach(AppSortOrder.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 185)
                }
                SettingsLine(label: "Row action:") {
                    Picker("Individual app action", selection: $model.preferences.quitMode) {
                        ForEach(QuitMode.allCases) { mode in Label(mode.title, systemImage: mode.symbol).tag(mode) }
                    }.labelsHidden().frame(width: 185).help(model.quitMode.explanation)
                }
                SettingsLine(label: "Reset:") { Button("Reset all", action: model.resetPreferences) }
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(Theme.panel)
        .foregroundStyle(Theme.primaryText)
        .controlSize(.small)
    }

    private func checkbox(_ title: LocalizedStringKey, label: String = "", isOn: Binding<Bool>) -> some View {
        SettingsLine(label: label) { Toggle(title, isOn: isOn).toggleStyle(.checkbox) }
    }
}

private struct SettingsLine<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primaryText)
                .frame(width: 68, alignment: .trailing)
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
            Text("Quit All lets apps save their work. If an app stays open, check for a save prompt before choosing Force Quit.").multilineTextAlignment(.center).foregroundStyle(Theme.secondaryText).frame(maxWidth: 300)
            QuickCloseHelpButton("Open help").buttonStyle(.borderedProminent).tint(Theme.accent)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding().background(Theme.panel)
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "power.circle.fill").font(.system(size: 42)).foregroundStyle(Theme.accent)
            Text("QuickClose").font(.title2.weight(.semibold)).foregroundStyle(Theme.primaryText)
            Text("A quiet menu-bar utility for clearing your workspace.").multilineTextAlignment(.center).foregroundStyle(Theme.secondaryText)
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text("Version \(version)").font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding().background(Theme.panel)
    }
}
