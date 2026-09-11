import Foundation
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
            #expect(model.pendingQuitIDs == [10])
            #expect(!model.visibleApplications.contains { [13, 14].contains($0.id) })
            model.quit(model.applications.filter { $0.id == 11 })
            #expect(fixture.requests.count == 1)
        }
    }

    @Test @MainActor func individualQuitDoesNotDependOnBulkSelection() {
        let fixture = Fixture(apps: [.init(id: 21, name: "Notes")])
        let model = fixture.model()
        model.toggleSelection(model.groups())
        #expect(model.selectedApps(in: model.groups()).isEmpty)
        model.quit(model.groups()[0].apps)
        #expect(fixture.requests.map(\.0) == [21])
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
}

@MainActor
private final class Fixture {
    let suite = "QuickCloseTests.\(UUID().uuidString)"
    var defaults: UserDefaults
    var apps: [RunningApp]
    var requests: [(pid_t, QuitMode)] = []
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
            enumerate: { self.apps },
            sendRequest: { app, mode in self.requests.append((app.id, mode)); return self.acceptsRequest },
            clock: { Date(timeIntervalSince1970: self.now) },
            playSound: { self.sounds += 1 }
        )
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
