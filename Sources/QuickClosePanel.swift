import AppKit
import SwiftUI

struct QuickClosePanel: View {
    @Bindable var model: QuickCloseModel
    @State private var search = ""
    @State private var confirmsEmptyTrash = false

    private func panelHeight(rowCount: Int, hasFollowUp: Bool) -> CGFloat {
        let extraHeight: CGFloat = hasFollowUp ? PanelLayout.followUpHeight : 0
        let maxListHeight = max(84, min(820, (NSScreen.main?.visibleFrame.height ?? 900) - 170) - extraHeight)
        let listHeight = min(max(CGFloat(rowCount) * PanelLayout.rowHeight, 60), maxListHeight)
        return 96 + listHeight + extraHeight
    }

    var body: some View {
        let groups = model.groups(matching: search)
        let selectedApps = model.selectedApps(in: groups)
        let followUp = model.bulkFollowUp(in: groups)
        let rowCount = groups.count + (model.preferences.includeFinderWindows ? 1 : 0) + (model.preferences.includeEmptyTrash ? 1 : 0)
        VStack(spacing: 0) {
            header(hasTargets: !selectedApps.isEmpty)
            searchField(selection: model.selection(in: groups))
            appList(groups: groups)
            footer(selectedCount: selectedApps.count, followUp: followUp)
        }
        .frame(width: 280, height: panelHeight(rowCount: rowCount, hasFollowUp: followUp != nil))
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

    private func header(hasTargets: Bool) -> some View {
        Button { model.quitSelected(matching: search) } label: {
            Text(model.isQuitting ? "Quitting…" : "Quit All")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(QuitButtonStyle())
        .tint(Theme.accent)
        .foregroundStyle(Theme.onAccent)
        .disabled(!hasTargets || model.isQuitting)
        .keyboardShortcut("q", modifiers: [.command, .option])
        .accessibilityLabel("Quit All")
        .accessibilityHint("Asks the selected apps to quit.")
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 5)
    }

    private func searchField(selection: AppSelection) -> some View {
        HStack(spacing: 7) {
            Toggle("Select all visible apps", isOn: Binding(
                get: { selection.allSelected },
                set: { model.setSelected($0, in: model.selection(in: model.groups(matching: search))) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .tint(Theme.accent)
            .disabled(selection.ids.isEmpty)
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

    private func appList(groups: [AppGroup]) -> some View {
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
                    let selection = model.selection(in: [group])
                    AppRow(
                        group: group,
                        selection: selection,
                        quitMode: model.quitMode,
                        isPending: group.apps.contains { model.pendingQuitIDs.contains($0.id) },
                        onToggleSelection: { model.setSelected(!selection.allSelected, in: selection) },
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

    @ViewBuilder
    private func footer(selectedCount: Int, followUp: BulkQuitFollowUp?) -> some View {
        let status = followUp?.status ?? model.lastResult
        HStack(spacing: 8) {
            Text(status ?? (model.preferences.disableQuitTips ? "\(selectedCount) selected" : "Ready when you are"))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .help(status ?? "Select apps above, or quit one using its row button.")
            Spacer(minLength: 4)
            Menu {
                Toggle("Show background apps", isOn: $model.preferences.showBackgroundApps)
                    .keyboardShortcut("b", modifiers: .command)
                Button("Refresh apps", systemImage: "arrow.clockwise") { model.refresh() }
                Divider()
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                QuickCloseHelpButton("Help")
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
        if let followUp {
            Button(role: .destructive) { model.forceQuit(followUp, matching: search) } label: {
                Text(followUp.buttonTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .help("\(followUp.buttonTitle). Unsaved changes may be lost.")
            .accessibilityHint("Unsaved changes may be lost.")
            .padding(.horizontal, 12)
            .frame(height: PanelLayout.followUpHeight, alignment: .top)
        }
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
    let selection: AppSelection
    let quitMode: QuitMode
    let isPending: Bool
    let onToggleSelection: () -> Void
    let onQuit: () -> Void
    private var isProtected: Bool { selection.ids.isEmpty }
    private var selectionSymbol: String {
        if isProtected { return "lock.fill" }
        if selection.isMixed { return "minus.square.fill" }
        return selection.allSelected ? "checkmark.square.fill" : "square"
    }

    var body: some View {
        HStack(spacing: 7) {
            Button(action: onToggleSelection) {
                Image(systemName: selectionSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selection.selectedCount > 0 ? Theme.accent : Theme.secondaryText)
                    .frame(width: 18, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isProtected)
            .accessibilityLabel(isProtected ? "Protected app, \(group.name)" : (selection.allSelected ? "Exclude \(group.title) from quit" : "Include \(group.title) in quit"))

            (group.icon.map(Image.init(nsImage:)) ?? Image(systemName: "app"))
                .resizable().aspectRatio(contentMode: .fit).frame(width: 18, height: 18)
            Text(group.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 3)
            if isPending { ProgressView().controlSize(.mini) }
            Button(action: onQuit) {
                Image(systemName: quitMode == .forceClose ? "bolt.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(isProtected ? Theme.field : Theme.secondaryText)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isProtected || isPending)
            .accessibilityLabel("\(quitMode.title) \(group.title)")
            .help(isProtected ? "Music app protected in Settings" : "\(quitMode.title) \(group.title). \(quitMode.explanation)")
        }
        .frame(height: PanelLayout.rowHeight)
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
        .frame(height: PanelLayout.rowHeight)
        .padding(.horizontal, 12)
    }
}

private enum PanelLayout {
    static let rowHeight: CGFloat = 30
    static let followUpHeight: CGFloat = 32
}

#Preview { QuickClosePanel(model: QuickCloseModel(monitorWorkspace: false)) }
