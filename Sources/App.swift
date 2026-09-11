import AppKit
import SwiftUI

@main
struct QuickClose: App {
    @State private var model = QuickCloseModel()

    var body: some Scene {
        MenuBarExtra("QuickClose", systemImage: "power.circle") {
            QuickClosePanel(model: model)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit QuickClose") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }

        Settings {
            QuickCloseSettings(model: model)
        }
    }
}
