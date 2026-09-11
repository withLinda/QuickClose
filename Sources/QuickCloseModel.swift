import AppKit
import Combine
import Observation
import ServiceManagement

struct RunningApp: Identifiable, Hashable {
    let id: pid_t
    let name: String
    let bundleIdentifier: String?
    let bundlePath: String?
    let isBackground: Bool
    let launchDate: Date
    let application: NSRunningApplication?

    init?(application: NSRunningApplication) {
        guard !application.isTerminated, let name = application.localizedName, !name.isEmpty else { return nil }
        id = application.processIdentifier
        self.name = name
        bundleIdentifier = application.bundleIdentifier
        bundlePath = application.bundleURL?.path
        isBackground = application.activationPolicy != .regular
        launchDate = application.launchDate ?? .distantPast
        self.application = application
    }

    // Descriptors without process handles let tests exercise targeting without closing real apps.
    init(id: pid_t, name: String, bundleIdentifier: String? = nil, isBackground: Bool = false, launchDate: Date = .distantPast) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        bundlePath = bundleIdentifier
        self.isBackground = isBackground
        self.launchDate = launchDate
        application = nil
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.name == rhs.name && lhs.isBackground == rhs.isBackground }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct AppGroup: Identifiable {
    let id: String
    let apps: [RunningApp]
    var name: String { apps.first?.name ?? "App" }
    var title: String { apps.count > 1 ? "\(name) (\(apps.count))" : name }
    var icon: NSImage? { apps.first?.application?.icon }
}

@MainActor
@Observable
final class QuickCloseModel {
    private(set) var applications: [RunningApp] = []
    private(set) var excludedAppIDs: Set<pid_t> = []
    private(set) var pendingQuitIDs: Set<pid_t> = []
    private(set) var lastResult: String?
    private(set) var launchAtLogin = false
    private(set) var loginMessage: String?
    private(set) var isRunningExtra = false

    var preferences: Preferences {
        didSet {
            preferences.save(to: defaults)
            if oldValue.deselectAppsByDefault != preferences.deselectAppsByDefault {
                excludedAppIDs = preferences.deselectAppsByDefault ? Set(applications.map(\.id)) : []
            }
            if oldValue.autoQuitEnabled != preferences.autoQuitEnabled || oldValue.idleTimeout != preferences.idleTimeout {
                lastActiveAt = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, clock()) })
                autoQuitAttemptedIDs.removeAll()
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let enumerate: () -> [RunningApp]
    @ObservationIgnored private let sendRequest: (RunningApp, QuitMode) -> Bool
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let playSound: () -> Void
    @ObservationIgnored private var subscriptions: Set<AnyCancellable> = []
    @ObservationIgnored private var lastActiveAt: [pid_t: Date] = [:]
    @ObservationIgnored private var autoQuitAttemptedIDs: Set<pid_t> = []
    @ObservationIgnored private var requestedAt: [pid_t: Date] = [:]

    init(
        defaults: UserDefaults = .standard,
        monitorWorkspace: Bool = true,
        enumerate: @escaping () -> [RunningApp] = { NSWorkspace.shared.runningApplications.compactMap(RunningApp.init) },
        sendRequest: @escaping (RunningApp, QuitMode) -> Bool = { app, mode in
            guard let handle = app.application, !handle.isTerminated else { return false }
            return mode == .forceClose ? handle.forceTerminate() : handle.terminate()
        },
        clock: @escaping () -> Date = Date.init,
        playSound: @escaping () -> Void = { NSSound(named: "Glass")?.play() }
    ) {
        self.defaults = defaults
        self.enumerate = enumerate
        self.sendRequest = sendRequest
        self.clock = clock
        self.playSound = playSound
        preferences = Preferences.load(from: defaults)
        refresh()
        if monitorWorkspace {
            syncLoginStatus()
            observeWorkspace()
        }
    }

    var quitMode: QuitMode { preferences.quitMode }
    var isQuitting: Bool { !pendingQuitIDs.isEmpty }

    func refresh() {
        let previousIDs = Set(applications.map(\.id))
        let current = enumerate().filter {
            $0.id != ProcessInfo.processInfo.processIdentifier &&
            $0.bundleIdentifier != "app.quickclose.mac" && $0.bundleIdentifier != "com.apple.finder"
        }
        let currentIDs = Set(current.map(\.id))
        for id in currentIDs.subtracting(previousIDs) {
            lastActiveAt[id] = clock()
            if preferences.deselectAppsByDefault { excludedAppIDs.insert(id) }
        }
        excludedAppIDs.formIntersection(currentIDs)
        lastActiveAt = lastActiveAt.filter { currentIDs.contains($0.key) }
        autoQuitAttemptedIDs.formIntersection(currentIDs)
        if applications != current { applications = current }

        let closed = pendingQuitIDs.subtracting(currentIDs)
        if !closed.isEmpty {
            pendingQuitIDs.subtract(closed)
            closed.forEach { requestedAt.removeValue(forKey: $0) }
            lastResult = "Closed \(closed.count) \(closed.count == 1 ? "app" : "apps")"
            if preferences.playSounds { playSound() }
        }
        let waitingTooLong = pendingQuitIDs.filter { clock().timeIntervalSince(requestedAt[$0] ?? clock()) >= 8 }
        if !waitingTooLong.isEmpty {
            pendingQuitIDs.subtract(waitingTooLong)
            waitingTooLong.forEach { requestedAt.removeValue(forKey: $0) }
            lastResult = "\(waitingTooLong.count) still open — check the app"
        }
    }

    var visibleApplications: [RunningApp] {
        applications.filter { preferences.showBackgroundApps || !$0.isBackground }
    }

    func groups(matching search: String = "") -> [AppGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = visibleApplications.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        let grouped = Dictionary(grouping: matches) { app in
            if preferences.groupBackgroundInstances && app.isBackground, let path = app.bundlePath {
                return "background:\(path)"
            }
            return "pid:\(app.id)"
        }
        return grouped.map { AppGroup(id: $0.key, apps: $0.value.sorted { $0.id < $1.id }) }.sorted { lhs, rhs in
            if preferences.sortOrder == .newestFirst {
                let left = lhs.apps.map(\.launchDate).max() ?? .distantPast
                let right = rhs.apps.map(\.launchDate).max() ?? .distantPast
                if left != right { return left > right }
            }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            if order == .orderedSame { return lhs.id < rhs.id }
            return order == (preferences.sortOrder == .reverseAlphabetical ? .orderedDescending : .orderedAscending)
        }
    }

    func isProtected(_ app: RunningApp) -> Bool {
        guard preferences.neverQuitMusicApps, let identifier = app.bundleIdentifier else { return false }
        return Self.musicAppIDs.contains(identifier)
    }

    static let musicAppIDs: Set<String> = [
        "com.apple.Music", "com.apple.iTunes", "com.spotify.client", "com.tidal.desktop",
        "com.deezer.Deezer", "com.amazon.music", "com.coppertino.Vox", "com.ronorm.riimusic"
    ]

    func isSelected(_ group: AppGroup) -> Bool {
        group.apps.contains { !isProtected($0) && !excludedAppIDs.contains($0.id) }
    }

    func toggleSelection(_ groups: [AppGroup]) {
        let targets = groups.flatMap(\.apps).filter { !isProtected($0) }
        let allSelected = !targets.isEmpty && targets.allSatisfy { !excludedAppIDs.contains($0.id) }
        if allSelected { excludedAppIDs.formUnion(targets.map(\.id)) }
        else { excludedAppIDs.subtract(targets.map(\.id)) }
    }

    func selectedApps(in groups: [AppGroup]) -> [RunningApp] {
        groups.flatMap(\.apps).filter { !excludedAppIDs.contains($0.id) && !isProtected($0) && !pendingQuitIDs.contains($0.id) }
    }

    func quit(_ apps: [RunningApp]) {
        let currentIDs = Set(applications.map(\.id))
        var rejected = 0
        var sent = 0
        for app in apps where currentIDs.contains(app.id) && !isProtected(app) && !pendingQuitIDs.contains(app.id) {
            if sendRequest(app, quitMode) {
                pendingQuitIDs.insert(app.id)
                requestedAt[app.id] = clock()
                sent += 1
            } else { rejected += 1 }
        }
        if sent > 0 { lastResult = "Asked \(sent) \(sent == 1 ? "app" : "apps") to quit" }
        if rejected > 0 { lastResult = "\(rejected) quit \(rejected == 1 ? "request" : "requests") refused" }
        refresh()
    }

    func noteActivity(_ id: pid_t) {
        lastActiveAt[id] = clock()
        autoQuitAttemptedIDs.remove(id)
    }

    func quitInactiveApps(frontmostID: pid_t?) {
        guard preferences.autoQuitEnabled else { return }
        if let frontmostID { noteActivity(frontmostID) }
        let targets = visibleApplications.filter {
            !$0.isBackground && $0.id != frontmostID && !isProtected($0) &&
            !excludedAppIDs.contains($0.id) && !autoQuitAttemptedIDs.contains($0.id) &&
            clock().timeIntervalSince(lastActiveAt[$0.id] ?? clock()) >= preferences.idleTimeout
        }
        autoQuitAttemptedIDs.formUnion(targets.map(\.id))
        quit(targets)
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.publisher(for: name).receive(on: DispatchQueue.main).sink { [weak self] _ in
                // receive(on:) guarantees the main queue; all model state is MainActor-owned.
                MainActor.assumeIsolated { self?.refresh() }
            }.store(in: &subscriptions)
        }
        center.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] notification in
                MainActor.assumeIsolated {
                    if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                        self?.noteActivity(app.processIdentifier)
                    }
                }
            }.store(in: &subscriptions)
        Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refresh()
                self.quitInactiveApps(frontmostID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
            }
        }.store(in: &subscriptions)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            syncLoginStatus()
        } catch {
            syncLoginStatus()
            loginMessage = error.localizedDescription
        }
    }

    func syncLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        loginMessage = status == .requiresApproval ? "Allow QuickClose in System Settings → Login Items." : nil
    }

    func resetPreferences() {
        preferences = Preferences()
        setLaunchAtLogin(false)
    }

    func runExtra(_ action: FinderAction) async {
        guard !isRunningExtra else { return }
        isRunningExtra = true
        let error = await FinderActions.execute(action)
        lastResult = error ?? action.completedMessage
        isRunningExtra = false
    }
}

enum FinderAction: String, Sendable {
    case closeWindows, emptyTrash
    var title: String { self == .closeWindows ? "Close Finder Windows" : "Empty Trash…" }
    var symbol: String { self == .closeWindows ? "macwindow" : "trash" }
    var completedMessage: String { self == .closeWindows ? "Closed Finder windows" : "Trash emptied" }
}

private actor FinderActions {
    static let shared = FinderActions()

    static func execute(_ action: FinderAction) async -> String? { await shared.run(action) }

    // AppleScript is created and used on this serial actor, away from the UI actor.
    private func run(_ action: FinderAction) -> String? {
        let command = action == .closeWindows ? "close every Finder window" : "empty trash"
        let source = "tell application \"Finder\"\n\(command)\nend tell"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            if error[NSAppleScript.errorNumber] as? Int == -1743 { return "Allow Finder access in Privacy → Automation" }
            if error[NSAppleScript.errorNumber] as? Int == -128 { return "Cancelled" }
            return error[NSAppleScript.errorMessage] as? String ?? "Finder action failed"
        }
        return nil
    }
}
