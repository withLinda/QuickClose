import AppKit
import Combine
import Observation
import ServiceManagement

@MainActor
@Observable
final class QuickCloseModel {
    private(set) var applications: [RunningApp] = []
    private var excludedAppIDs: Set<pid_t> = []
    private var requestedAt: [pid_t: Date] = [:]
    // Members of the last manual Quit All attempt. Refresh drops exited or replaced processes.
    private var bulkIDs: Set<pid_t> = []
    private(set) var lastResult: String?
    private(set) var launchAtLogin = false
    private(set) var loginMessage: String?
    private(set) var isRunningExtra = false

    var preferences: Preferences {
        didSet {
            preferences.save(to: defaults)
            if oldValue.deselectAppsByDefault != preferences.deselectAppsByDefault {
                excludedAppIDs = preferences.deselectAppsByDefault ? Set(applications.map(\.id)) : []
                if preferences.deselectAppsByDefault { bulkIDs.removeAll() }
            }
            if oldValue.autoQuitEnabled != preferences.autoQuitEnabled || oldValue.idleTimeout != preferences.idleTimeout {
                let now = clock()
                lastActiveAt = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, now) })
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
    var pendingQuitIDs: Dictionary<pid_t, Date>.Keys { requestedAt.keys }
    var isQuitting: Bool { !requestedAt.isEmpty }

    func refresh() {
        let current = enumerate().filter {
            $0.id != ProcessInfo.processInfo.processIdentifier &&
            $0.bundleIdentifier != "app.quickclose.mac" && $0.bundleIdentifier != "com.apple.finder"
        }
        let now = clock()
        if current != applications {
            let previous = Dictionary(uniqueKeysWithValues: applications.lazy.map { ($0.id, $0) })
            let continuing = Set(current.compactMap { app -> pid_t? in
                guard let old = previous[app.id], app.isSameProcess(as: old) else { return nil }
                return app.id
            })
            excludedAppIDs.formIntersection(continuing)
            lastActiveAt = lastActiveAt.filter { continuing.contains($0.key) }
            autoQuitAttemptedIDs.formIntersection(continuing)
            for app in current where !continuing.contains(app.id) {
                lastActiveAt[app.id] = now
                if preferences.deselectAppsByDefault { excludedAppIDs.insert(app.id) }
            }
            applications = current

            let closed = bulkIDs.union(pendingQuitIDs).subtracting(continuing)
            bulkIDs.formIntersection(continuing)
            if !closed.isEmpty {
                for id in closed { requestedAt.removeValue(forKey: id) }
                lastResult = "Closed \(closed.count) \(closed.count == 1 ? "app" : "apps")"
                if preferences.playSounds { playSound() }
            }
        }
        let expired = requestedAt.compactMap { now.timeIntervalSince($0.value) >= 8 ? $0.key : nil }
        if !expired.isEmpty {
            for id in expired { requestedAt.removeValue(forKey: id) }
            lastResult = "\(expired.count) still open — check the app"
        }
    }

    func groups(matching search: String = "") -> [AppGroup] {
        let preferences = self.preferences
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = applications.lazy.filter { app in
            (preferences.showBackgroundApps || !app.isBackground)
                && (query.isEmpty || app.name.localizedCaseInsensitiveContains(query))
        }
        let grouped = Dictionary(grouping: matches) { app in
            if preferences.groupBackgroundInstances && app.isBackground, let path = app.bundlePath {
                return "background:\(path)"
            }
            return "pid:\(app.id)"
        }
        return grouped.map { AppGroup(id: $0.key, members: $0.value) }.sorted { lhs, rhs in
            if preferences.sortOrder == .newestFirst, lhs.latestLaunch != rhs.latestLaunch {
                return lhs.latestLaunch > rhs.latestLaunch
            }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            if order == .orderedSame { return lhs.id < rhs.id }
            return order == (preferences.sortOrder == .reverseAlphabetical ? .orderedDescending : .orderedAscending)
        }
    }

    private func isProtected(_ app: RunningApp) -> Bool {
        guard preferences.neverQuitMusicApps, let identifier = app.bundleIdentifier else { return false }
        return Self.musicAppIDs.contains(identifier)
    }

    private static let musicAppIDs: Set<String> = [
        "com.apple.Music", "com.apple.iTunes", "com.spotify.client", "com.tidal.desktop",
        "com.deezer.Deezer", "com.amazon.music", "com.coppertino.Vox", "com.ronorm.riimusic"
    ]

    func selection(in groups: [AppGroup]) -> AppSelection {
        let ids = Set(groups.lazy.flatMap(\.apps).filter { !self.isProtected($0) }.map(\.id))
        return AppSelection(ids: ids, selectedCount: ids.count { !excludedAppIDs.contains($0) })
    }

    func setSelected(_ selected: Bool, in selection: AppSelection) {
        if selected { excludedAppIDs.subtract(selection.ids) }
        else {
            excludedAppIDs.formUnion(selection.ids)
            bulkIDs.subtract(selection.ids)
        }
    }

    private func isSelected(_ app: RunningApp) -> Bool {
        !excludedAppIDs.contains(app.id) && !isProtected(app)
    }

    func selectedApps(in groups: [AppGroup]) -> [RunningApp] {
        groups.lazy.flatMap(\.apps).filter { isSelected($0) && !pendingQuitIDs.contains($0.id) }
    }

    func quitSelected(matching search: String) {
        guard !isQuitting else { return }
        let targets = selectedApps(in: groups(matching: search))
        bulkIDs = Set(targets.map(\.id))
        quit(targets, mode: .normalQuit)
    }

    func bulkFollowUp(in groups: [AppGroup]) -> BulkQuitFollowUp? {
        guard !bulkIDs.isEmpty, bulkIDs.isDisjoint(with: pendingQuitIDs) else { return nil }
        return BulkQuitFollowUp(apps: selectedApps(in: groups).filter { bulkIDs.contains($0.id) })
    }

    func forceQuit(_ offer: BulkQuitFollowUp, matching search: String) {
        // A process can exit, relaunch or become protected between rendering and clicking.
        refresh()
        guard let current = bulkFollowUp(in: groups(matching: search)) else { return }
        let offered = Dictionary(uniqueKeysWithValues: offer.apps.map { ($0.id, $0) })
        let targets = current.apps.filter { app in
            offered[app.id].map { app.isSameProcess(as: $0) } == true
        }
        bulkIDs.subtract(targets.map(\.id))
        quit(targets, mode: .forceClose)
    }

    func quit(_ apps: [RunningApp]) {
        quit(apps, mode: quitMode)
    }

    private func quit(_ apps: [RunningApp], mode: QuitMode) {
        guard !apps.isEmpty else { return }
        let currentApps = Dictionary(uniqueKeysWithValues: applications.lazy.map { ($0.id, $0) })
        var rejected = 0
        var sent = 0
        for app in apps {
            // A panel row can outlive the snapshot it displays. Never target a replacement.
            guard currentApps[app.id] == app, !isProtected(app), !pendingQuitIDs.contains(app.id) else { continue }
            if sendRequest(app, mode) {
                requestedAt[app.id] = clock()
                sent += 1
            } else { rejected += 1 }
        }
        if sent > 0 { lastResult = "Asked \(sent) \(sent == 1 ? "app" : "apps") to quit" }
        if rejected > 0 { lastResult = "\(rejected) quit \(rejected == 1 ? "request" : "requests") refused" }
        refresh()
    }

    private func noteActivity(_ id: pid_t) {
        guard lastActiveAt[id] != nil else { return }
        lastActiveAt[id] = clock()
        autoQuitAttemptedIDs.remove(id)
    }

    func quitInactiveApps(frontmostID: pid_t?) {
        guard preferences.autoQuitEnabled else { return }
        if let frontmostID { noteActivity(frontmostID) }
        let now = clock()
        let targets = applications.filter {
            !$0.isBackground && $0.id != frontmostID && isSelected($0) && !autoQuitAttemptedIDs.contains($0.id) &&
            now.timeIntervalSince(lastActiveAt[$0.id] ?? now) >= preferences.idleTimeout
        }
        guard !targets.isEmpty else { return }
        autoQuitAttemptedIDs.formUnion(targets.lazy.map(\.id))
        quit(targets, mode: .normalQuit)
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

    private func syncLoginStatus() {
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
        let error = await FinderActions.shared.run(action)
        lastResult = error ?? action.completedMessage
        isRunningExtra = false
    }
}
