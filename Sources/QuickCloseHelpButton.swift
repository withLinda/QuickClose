import SwiftUI

struct QuickCloseHelpButton: View {
    @Environment(\.openURL) private var openURL
    private let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Button(title) {
            if let url = URL(string: "https://github.com/withLinda/QuickClose#behavior") { openURL(url) }
        }
    }
}
