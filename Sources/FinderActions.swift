import AppKit

enum FinderAction: Sendable {
    case closeWindows, emptyTrash
    var title: String { self == .closeWindows ? "Close Finder Windows" : "Empty Trash…" }
    var symbol: String { self == .closeWindows ? "macwindow" : "trash" }
    var completedMessage: String { self == .closeWindows ? "Closed Finder windows" : "Trash emptied" }
}

// Keep the script and its reply on one serial executor, away from the UI actor.
actor FinderActions {
    static let shared = FinderActions()

    func run(_ action: FinderAction) -> String? {
        let command = action == .closeWindows ? "close every Finder window" : "empty trash"
        let source = "tell application \"Finder\"\n\(command)\nend tell"
        guard let script = NSAppleScript(source: source) else { return "Finder action failed" }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        guard let error else { return nil }
        switch error[NSAppleScript.errorNumber] as? Int {
        case -1743: return "Allow Finder access in Privacy → Automation"
        case -128: return "Cancelled"
        default: return error[NSAppleScript.errorMessage] as? String ?? "Finder action failed"
        }
    }
}
