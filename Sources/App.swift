import SwiftUI

@main
struct QuickClose: App {
    @State private var model = QuickCloseModel()

    var body: some Scene {
        MenuBarExtra("QuickClose", systemImage: "power.circle") {
            QuickClosePanel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            QuickCloseSettings(model: model)
        }
    }
}
