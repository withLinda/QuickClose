import SwiftUI
import Testing
@testable import QuickClose

struct QuickCloseTests {
    @Test func productionDarkHardTextPairsMeetWCAG() {
        for background in [Theme.panelHex, Theme.fieldHex] {
            for foreground in [Theme.primaryTextHex, Theme.secondaryTextHex] {
                #expect(ContrastAudit.ratio(foreground: foreground, background: background) >= 4.5)
            }
        }
        #expect(ContrastAudit.ratio(foreground: Theme.panelHex, background: Theme.accentHex) >= 4.5)
        #expect(ContrastAudit.luminance(Theme.panelHex) < ContrastAudit.luminance(0x2D353B))
    }

    @Test @MainActor func preferenceRoundTripAndLegacyMigration() {
        let fixture = Fixture()
        fixture.defaults.set(false, forKey: "playSounds")
        fixture.defaults.set("normalQuit", forKey: "quitMode")
        let migrated = Preferences.load(from: fixture.defaults)
        #expect(!migrated.playSounds)
        #expect(migrated.quitMode == .normalQuit)

        var preferences = migrated
        preferences.includeFinderWindows = true
        preferences.includeEmptyTrash = true
        preferences.autoQuitEnabled = true
        preferences.autoQuitInterval = 2
        preferences.autoQuitUnit = .minutes
        preferences.sortOrder = .newestFirst
        preferences.save(to: fixture.defaults)
        #expect(Preferences.load(from: fixture.defaults) == preferences)
        #expect(preferences.idleTimeout == 120)
    }

    @Test @MainActor func bothModesRouteOnlyEligibleFilteredSelectedApps() {
        for mode in QuitMode.allCases {
            let fixture = Fixture(apps: [
                .init(id: 10, name: "Editor"),
                .init(id: 11, name: "Music", bundleIdentifier: "com.apple.Music"),
                .init(id: 12, name: "Browser"),
                .init(id: 13, name: "QuickClose", bundleIdentifier: "app.quickclose.mac"),
                .init(id: 14, name: "Finder", bundleIdentifier: "com.apple.finder")
            ])
            let model = fixture.model()
            model.preferences.quitMode = mode
            model.quit(model.selectedApps(in: model.groups(matching: "Editor")))
            #expect(fixture.requests.map(\.0) == [10])
            #expect(fixture.requests.map(\.1) == [mode])
            #expect(Set(model.pendingQuitIDs) == [10])
            #expect(!model.applications.contains { [13, 14].contains($0.id) })
            model.quit(model.applications.filter { $0.id == 11 })
            #expect(fixture.requests.count == 1)
        }
    }

    @Test @MainActor func individualQuitDoesNotDependOnBulkSelection() {
        let fixture = Fixture(apps: [.init(id: 21, name: "Notes")])
        let model = fixture.model()
        model.setSelected(false, in: model.selection(in: model.groups()))
        #expect(model.selectedApps(in: model.groups()).isEmpty)
        model.quit(model.groups()[0].apps)
        #expect(fixture.requests.map(\.0) == [21])
        #expect(fixture.requests.map(\.1) == [.normalQuit])
    }

    @Test @MainActor func savedForceModeCannotForceBulkOrIdleQuit() {
        let fixture = Fixture(apps: [.init(id: 25, name: "Editor"), .init(id: 26, name: "Browser")])
        fixture.defaults.set("forceClose", forKey: "quitMode")
        let model = fixture.model()
        model.preferences.autoQuitEnabled = true
        model.preferences.autoQuitUnit = .minutes
        model.quitSelected(matching: "Editor")
        fixture.now += 61
        model.quitInactiveApps(frontmostID: 25)
        #expect(fixture.requests.map(\.0) == [25, 26])
        #expect(fixture.requests.map(\.1) == [.normalQuit, .normalQuit])
    }

    @Test @MainActor func panelMakesRoomForFollowUpOnlyWhileBulkTargetsRemain() {
        let fixture = Fixture(apps: [.init(id: 27, name: "Editor"), .init(id: 28, name: "Notes")])
        let model = fixture.model()
        let panel = NSHostingView(rootView: QuickClosePanel(model: model))
        let original = panel.fittingSize
        model.quitSelected(matching: "")
        fixture.apps.removeLast()
        model.refresh()
        #expect(panel.fittingSize == original)
        fixture.now += 9
        model.refresh()
        panel.layoutSubtreeIfNeeded()
        #expect(panel.fittingSize.height > original.height)
        #expect(panel.fittingSize.width == original.width)
        #expect(fixture.requests.map(\.1) == [.normalQuit, .normalQuit])
        fixture.apps.removeAll()
        model.refresh()
        panel.layoutSubtreeIfNeeded()
        #expect(panel.fittingSize == original)
    }

    @Test @MainActor func partialQuitOffersOnlyTheOriginalSurvivors() throws {
        let fixture = Fixture(apps: [
            .init(id: 101, name: "Work Board"), .init(id: 102, name: "Work Editor"),
            .init(id: 103, name: "Work Notes"), .init(id: 104, name: "Work Chat"),
            .init(id: 105, name: "Browser")
        ])
        let model = fixture.model()
        model.setSelected(false, in: model.selection(in: model.groups(matching: "Chat")))
        model.quitSelected(matching: "Work")
        #expect(fixture.requests.map(\.0) == [101, 102, 103])
        fixture.apps.removeAll { $0.id == 101 }
        fixture.apps.append(.init(id: 106, name: "Work Preview"))
        fixture.now += 7
        model.refresh()
        #expect(model.bulkFollowUp(in: model.groups()) == nil)
        fixture.now += 1
        model.refresh()
        let multiple = try #require(model.bulkFollowUp(in: model.groups()))
        #expect(multiple.buttonTitle == "Force Quit 2 Remaining Apps")
        #expect(multiple.apps.map(\.id) == [102, 103])
        #expect(fixture.requests.allSatisfy { $0.1 == .normalQuit })

        // One user finishes saving after the offer appears.
        fixture.apps.removeAll { $0.id == 102 }
        model.refresh()
        let single = try #require(model.bulkFollowUp(in: model.groups()))
        #expect(single.status == "Work Notes is still open")
        #expect(single.buttonTitle == "Force Quit Work Notes")
        model.forceQuit(multiple, matching: "")
        model.forceQuit(multiple, matching: "")
        #expect(fixture.requests.filter { $0.1 == .forceClose }.map(\.0) == [103])
        #expect(model.bulkFollowUp(in: model.groups()) == nil)
    }

    @Test @MainActor func forceClickRechecksIdentityProtectionSelectionAndVisibility() throws {
        let fixture = Fixture(apps: [
            .init(id: 111, name: "Work Editor"), .init(id: 112, name: "Work Player", bundleIdentifier: "com.apple.Music"),
            .init(id: 113, name: "Work Notes"), .init(id: 114, name: "Work Helper", isBackground: true),
            .init(id: 115, name: "Browser"), .init(id: 116, name: "Work Board")
        ])
        let model = fixture.model()
        model.preferences.showBackgroundApps = true
        model.preferences.neverQuitMusicApps = false
        fixture.acceptsRequest = false
        model.quitSelected(matching: "")
        let offered = try #require(model.bulkFollowUp(in: model.groups()))
        #expect(offered.apps.count == 6)
        model.preferences.showBackgroundApps = false
        model.preferences.neverQuitMusicApps = true
        model.setSelected(false, in: model.selection(in: model.groups(matching: "Notes")))
        fixture.apps[0] = .init(id: 111, name: "Work Editor", launchDate: Date(timeIntervalSince1970: 1234))
        // No refresh here: the click itself must detect the replacement.
        fixture.acceptsRequest = true
        model.forceQuit(offered, matching: "Work")
        #expect(fixture.requests.filter { $0.1 == .forceClose }.map(\.0) == [116])
    }

    @Test @MainActor func rowAndIdleRefusalsDoNotBecomeBulkFollowUps() {
        let fixture = Fixture(apps: [.init(id: 121, name: "Notes"), .init(id: 122, name: "Editor")])
        let model = fixture.model()
        fixture.acceptsRequest = false
        model.quit(model.applications)
        model.preferences.autoQuitEnabled = true
        model.preferences.autoQuitUnit = .minutes
        fixture.now += 61
        model.quitInactiveApps(frontmostID: 121)
        #expect(model.bulkFollowUp(in: model.groups()) == nil)
        #expect(fixture.requests.map(\.1) == [.normalQuit, .normalQuit, .normalQuit])
    }

    @Test @MainActor func completionWaitsForActualExitAndPreventsDuplicateRequests() {
        let fixture = Fixture(apps: [.init(id: 31, name: "Editor")])
        let model = fixture.model()
        model.quit(model.applications)
        model.quit(model.applications)
        #expect(fixture.requests.count == 1)
        #expect(model.isQuitting)
        #expect(fixture.sounds == 0)
        fixture.apps = []
        model.refresh()
        #expect(!model.isQuitting)
        #expect(fixture.sounds == 1)
        #expect(model.lastResult == "Closed 1 app")
    }

    @Test @MainActor func refusedAndDelayedRequestsDoNotClaimCompletionOrForceFallback() {
        let fixture = Fixture(apps: [.init(id: 40, name: "Editor")])
        let model = fixture.model()
        model.preferences.quitMode = .normalQuit
        fixture.acceptsRequest = false
        model.quit(model.applications)
        #expect(!model.isQuitting)
        #expect(model.lastResult == "1 quit request refused")
        fixture.acceptsRequest = true
        model.quit(model.applications)
        fixture.now += 9
        model.refresh()
        #expect(!model.isQuitting)
        #expect(model.lastResult == "1 still open — check the app")
        #expect(fixture.requests.allSatisfy { $0.1 == .normalQuit })
        #expect(fixture.sounds == 0)
    }

    @Test @MainActor func backgroundGroupingSortingAndSearchStayConsistent() {
        let fixture = Fixture(apps: [
            .init(id: 50, name: "Helper", bundleIdentifier: "example.helper", isBackground: true),
            .init(id: 51, name: "Helper", bundleIdentifier: "example.helper", isBackground: true),
            .init(id: 52, name: "Alpha"),
            .init(id: 53, name: "Zulu", launchDate: Date())
        ])
        let model = fixture.model()
        #expect(model.groups().map(\.name) == ["Alpha", "Zulu"])
        model.preferences.showBackgroundApps = true
        #expect(model.groups().map(\.title) == ["Alpha", "Helper (2)", "Zulu"])
        #expect(model.groups(matching: " help ").flatMap(\.apps).map(\.id) == [50, 51])
        model.preferences.groupBackgroundInstances = false
        #expect(model.groups().count == 4)
        model.preferences.sortOrder = .reverseAlphabetical
        #expect(model.groups().first?.name == "Zulu")
        model.preferences.sortOrder = .newestFirst
        #expect(model.groups().first?.name == "Zulu")
    }

    @Test @MainActor func deselectionDefaultAppliesToNewAppsAndCanBeReversed() {
        let fixture = Fixture(apps: [.init(id: 61, name: "Editor")])
        let model = fixture.model()
        model.preferences.deselectAppsByDefault = true
        fixture.apps.append(.init(id: 62, name: "Browser"))
        model.refresh()
        #expect(model.selectedApps(in: model.groups()).isEmpty)
        model.preferences.deselectAppsByDefault = false
        #expect(model.selectedApps(in: model.groups()).count == 2)
    }

    @Test @MainActor func idleQuitTracksActivityProtectsFrontmostAndDoesNotRepeat() {
        let fixture = Fixture(apps: [
            .init(id: 71, name: "Editor"),
            .init(id: 72, name: "Music", bundleIdentifier: "com.spotify.client"),
            .init(id: 73, name: "Browser")
        ])
        let model = fixture.model()
        model.preferences.autoQuitUnit = .minutes
        model.preferences.autoQuitEnabled = true
        fixture.now += 61
        model.quitInactiveApps(frontmostID: 71)
        #expect(fixture.requests.map(\.0) == [73])
        fixture.now += 30
        model.quitInactiveApps(frontmostID: nil)
        #expect(fixture.requests.map(\.0) == [73])
        fixture.now += 31
        model.quitInactiveApps(frontmostID: nil)
        #expect(fixture.requests.map(\.0) == [73, 71])
    }

    @Test @MainActor func idleCheckWithNoTargetsDoesNotRescanWorkspace() {
        let fixture = Fixture(apps: [.init(id: 81, name: "Editor")])
        let model = fixture.model()
        model.preferences.autoQuitEnabled = true
        let scans = fixture.workspaceScans
        model.quitInactiveApps(frontmostID: 81)
        #expect(fixture.workspaceScans == scans)
        #expect(fixture.requests.isEmpty)
    }

    @Test @MainActor func refreshUsesNewMetadataForProtectionAndSorting() {
        let fixture = Fixture(apps: [
            .init(id: 82, name: "Player"),
            .init(id: 83, name: "Editor", launchDate: Date(timeIntervalSince1970: 10))
        ])
        let model = fixture.model()
        model.preferences.sortOrder = .newestFirst
        let oldTargets = model.selectedApps(in: model.groups())
        fixture.apps[0] = .init(id: 82, name: "Player", bundleIdentifier: "com.apple.Music",
                                launchDate: Date(timeIntervalSince1970: 20))
        model.refresh()
        #expect(model.groups().map(\.name) == ["Player", "Editor"])
        model.quit(oldTargets)
        #expect(fixture.requests.map(\.0) == [83])
    }

    @Test @MainActor func partiallySelectedGroupIsNotFullySelected() throws {
        let fixture = Fixture(apps: [
            .init(id: 84, name: "Helper", bundleIdentifier: "example.helper", isBackground: true),
            .init(id: 85, name: "Helper", bundleIdentifier: "example.helper", isBackground: true)
        ])
        let model = fixture.model()
        model.preferences.showBackgroundApps = true
        model.preferences.groupBackgroundInstances = false
        let first = try #require(model.groups().first)
        model.setSelected(false, in: model.selection(in: [first]))
        model.preferences.groupBackgroundInstances = true
        let group = try #require(model.groups().first)
        let selection = model.selection(in: [group])
        #expect(selection.isMixed)
        #expect(!selection.allSelected)
        #expect(model.selectedApps(in: [group]).count == 1)
        model.setSelected(true, in: selection)
        #expect(model.selectedApps(in: [group]).count == 2)
    }

    @Test @MainActor func hostedPanelResizesWhenVisibleRowsChange() {
        let fixture = Fixture(apps: [
            .init(id: 86, name: "Notes"),
            .init(id: 87, name: "Editor"),
            .init(id: 88, name: "Helper", isBackground: true)
        ])
        let model = fixture.model()
        let panel = NSHostingView(rootView: QuickClosePanel(model: model))
        #expect(panel.fittingSize == CGSize(width: 280, height: 156))
        model.preferences.showBackgroundApps = true
        model.preferences.includeFinderWindows = true
        panel.layoutSubtreeIfNeeded()
        #expect(panel.fittingSize == CGSize(width: 280, height: 216))
    }

    @Test @MainActor func bulkActionHonorsCurrentVisibilityAndSearch() {
        let fixture = Fixture(apps: [
            .init(id: 91, name: "Editor"),
            .init(id: 92, name: "Editor Helper", isBackground: true),
            .init(id: 93, name: "Notes")
        ])
        let model = fixture.model()
        model.preferences.showBackgroundApps = true
        #expect(model.groups(matching: "Editor").count == 2)
        model.preferences.showBackgroundApps = false
        model.quitSelected(matching: "Editor")
        #expect(fixture.requests.map(\.0) == [91])
    }

    @Test @MainActor func reusedPIDGetsItsOwnIdleDeadline() {
        let fixture = Fixture(apps: [.init(id: 94, name: "Editor", launchDate: Date(timeIntervalSince1970: 950))])
        let model = fixture.model()
        model.preferences.autoQuitUnit = .minutes
        model.preferences.autoQuitEnabled = true
        fixture.now += 61
        fixture.apps[0] = .init(id: 94, name: "Editor", launchDate: Date(timeIntervalSince1970: fixture.now))
        model.refresh()
        model.quitInactiveApps(frontmostID: nil)
        #expect(fixture.requests.isEmpty)
        fixture.now += 60
        model.quitInactiveApps(frontmostID: nil)
        #expect(fixture.requests.map(\.0) == [94])
    }
}

@MainActor
private final class Fixture {
    let suite = "QuickCloseTests.\(UUID().uuidString)"
    var defaults: UserDefaults
    var apps: [RunningApp]
    var requests: [(pid_t, QuitMode)] = []
    var workspaceScans = 0
    var acceptsRequest = true
    var sounds = 0
    var now: TimeInterval = 1_000

    init(apps: [RunningApp] = []) {
        self.apps = apps
        defaults = UserDefaults(suiteName: suite)!
    }

    deinit { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

    func model() -> QuickCloseModel {
        QuickCloseModel(
            defaults: defaults,
            monitorWorkspace: false,
            enumerate: { self.workspaceScans += 1; return self.apps },
            sendRequest: { app, mode in self.requests.append((app.id, mode)); return self.acceptsRequest },
            clock: { Date(timeIntervalSince1970: self.now) },
            playSound: { self.sounds += 1 }
        )
    }
}

private extension RunningApp {
    init(id: pid_t, name: String, bundleIdentifier: String? = nil, isBackground: Bool = false, launchDate: Date = .distantPast) {
        self.init(id: id, name: name, bundleIdentifier: bundleIdentifier, bundlePath: bundleIdentifier,
                  isBackground: isBackground, launchDate: launchDate, application: nil)
    }
}

private enum ContrastAudit {
    static func ratio(foreground: UInt32, background: UInt32) -> Double {
        let a = luminance(foreground), b = luminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static func luminance(_ value: UInt32) -> Double {
        let channels = [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)].map { channel -> Double in
            let normalized = channel / 255
            return normalized <= 0.04045 ? normalized / 12.92 : pow((normalized + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
}
