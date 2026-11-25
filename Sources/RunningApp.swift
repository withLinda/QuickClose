import AppKit

// Equality describes the snapshot; Identifiable describes the row.
struct RunningApp: Identifiable, Equatable {
    let id: pid_t
    let name: String
    let bundleIdentifier: String?
    let bundlePath: String?
    let isBackground: Bool
    let launchDate: Date
    let application: NSRunningApplication?
}

extension RunningApp {
    func isSameProcess(as other: Self) -> Bool {
        guard id == other.id else { return false }
        if let application, let previous = other.application { return application == previous }
        return launchDate == other.launchDate
    }

    init?(application: NSRunningApplication) {
        guard application.processIdentifier > 0, !application.isTerminated,
              let name = application.localizedName, !name.isEmpty else { return nil }
        self.init(id: application.processIdentifier, name: name,
                  bundleIdentifier: application.bundleIdentifier, bundlePath: application.bundleURL?.path,
                  isBackground: application.activationPolicy != .regular,
                  launchDate: application.launchDate ?? .distantPast, application: application)
    }
}

struct AppGroup: Identifiable {
    let id: String
    let apps: [RunningApp]
    let latestLaunch: Date

    init(id: String, members: [RunningApp]) {
        self.id = id
        apps = members.sorted { $0.id < $1.id }
        latestLaunch = members.lazy.map(\.launchDate).max() ?? .distantPast
    }

    var name: String { apps.first?.name ?? "App" }
    var title: String { apps.count > 1 ? "\(name) (\(apps.count))" : name }
    var icon: NSImage? { apps.first?.application?.icon }
}

struct AppSelection {
    let ids: Set<pid_t>
    let selectedCount: Int
    var allSelected: Bool { !ids.isEmpty && selectedCount == ids.count }
    var isMixed: Bool { selectedCount > 0 && !allSelected }
}

struct BulkQuitFollowUp {
    let apps: [RunningApp]
    let status: String
    let buttonTitle: String

    init?(apps: [RunningApp]) {
        guard let first = apps.first else { return nil }
        self.apps = apps
        status = apps.count == 1 ? "\(first.name) is still open" : "\(apps.count) apps are still open"
        buttonTitle = apps.count == 1 ? "Force Quit \(first.name)" : "Force Quit \(apps.count) Remaining Apps"
    }
}
