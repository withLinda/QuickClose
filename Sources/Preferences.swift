import Foundation

struct Preferences: Codable, Equatable {
    private static let storageKey = "preferences.v1"
    var showBackgroundApps = false
    var groupBackgroundInstances = true
    var neverQuitMusicApps = true
    var playSounds = true
    var deselectAppsByDefault = false
    var disableQuitTips = false
    var includeFinderWindows = false
    var includeEmptyTrash = false
    var autoQuitEnabled = false
    var autoQuitInterval = 1
    var autoQuitUnit = IdleUnit.hours
    var sortOrder = AppSortOrder.alphabetical
    // Stored under the original key for compatibility; applies only to individual rows.
    var quitMode = QuitMode.normalQuit

    var idleTimeout: TimeInterval { Double(autoQuitInterval) * autoQuitUnit.seconds }

    static func load(from defaults: UserDefaults) -> Self {
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(Self.self, from: data) {
            return saved
        }
        // Preserve preferences from the first version of QuickClose.
        var result = Self()
        result.showBackgroundApps = defaults.bool(forKey: "showBackgroundApps")
        result.playSounds = defaults.object(forKey: "playSounds") as? Bool ?? true
        result.deselectAppsByDefault = defaults.bool(forKey: "deselectAppsByDefault")
        result.disableQuitTips = defaults.bool(forKey: "disableQuitTips")
        if let savedMode = defaults.string(forKey: "quitMode").flatMap(QuitMode.init(rawValue:)) {
            result.quitMode = savedMode
        }
        return result
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

enum QuitMode: String, CaseIterable, Identifiable, Codable {
    case forceClose, normalQuit
    var id: Self { self }
    var title: String { self == .forceClose ? "Force Quit" : "Quit" }
    var symbol: String { self == .forceClose ? "bolt.fill" : "power" }
    var explanation: String {
        self == .forceClose
            ? "Force Quit ends the app immediately; unsaved changes may be lost."
            : "Quit lets the app save work or ask before closing."
    }
}

enum AppSortOrder: String, CaseIterable, Identifiable, Codable {
    case alphabetical, reverseAlphabetical, newestFirst
    var id: Self { self }
    var title: String {
        switch self {
        case .alphabetical: "A–Z Alphabetical"
        case .reverseAlphabetical: "Z–A Alphabetical"
        case .newestFirst: "Recently launched"
        }
    }
}

enum IdleUnit: String, CaseIterable, Identifiable, Codable {
    case minutes, hours
    var id: Self { self }
    var seconds: TimeInterval { self == .hours ? 3_600 : 60 }
}
