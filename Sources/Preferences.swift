import Foundation

struct Preferences: Codable, Equatable {
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
    var quitMode = QuitMode.forceClose

    var idleTimeout: TimeInterval { Double(autoQuitInterval) * autoQuitUnit.seconds }

    static func load(from defaults: UserDefaults) -> Self {
        if let data = defaults.data(forKey: "preferences.v1"),
           let saved = try? JSONDecoder().decode(Self.self, from: data) {
            return saved
        }
        // Preserve preferences from the first version of QuickClose.
        var result = Self()
        result.showBackgroundApps = defaults.bool(forKey: "showBackgroundApps")
        result.playSounds = defaults.object(forKey: "playSounds") as? Bool ?? true
        result.deselectAppsByDefault = defaults.bool(forKey: "deselectAppsByDefault")
        result.disableQuitTips = defaults.bool(forKey: "disableQuitTips")
        result.quitMode = defaults.string(forKey: "quitMode").flatMap(QuitMode.init(rawValue:)) ?? .forceClose
        return result
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "preferences.v1") }
    }
}

enum QuitMode: String, CaseIterable, Identifiable, Codable {
    case forceClose, normalQuit
    var id: Self { self }
    var title: String { self == .forceClose ? "Force Close" : "Normal Quit" }
    var symbol: String { self == .forceClose ? "bolt.fill" : "power" }
    var explanation: String {
        self == .forceClose
            ? "Force Close ends apps immediately; unsaved changes may be lost."
            : "Normal Quit lets apps save work or ask before closing."
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
