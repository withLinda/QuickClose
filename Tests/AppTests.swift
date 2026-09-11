import Testing
import Foundation
@testable import QuickClose

struct QuickCloseTests {
    @Test func everforestPrimaryTextMeetsContrastAndLightnessDelta() {
        let ratio = ContrastAudit.ratio(foreground: 0xD3C6AA, background: 0x2D353B)
        let delta = ContrastAudit.deltaL(foreground: 0xD3C6AA, background: 0x2D353B)
        #expect(ratio >= 4.5)
        #expect(delta >= 40)
    }

    @Test func accentIsReservedForTheQuitAction() {
        #expect(Theme.danger != Theme.navigation)
    }
}

private enum ContrastAudit {
    static func ratio(foreground: UInt32, background: UInt32) -> Double {
        let a = luminance(foreground), b = luminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static func deltaL(foreground: UInt32, background: UInt32) -> Double {
        abs(lStar(foreground) - lStar(background))
    }

    private static func luminance(_ value: UInt32) -> Double {
        let channels = [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)].map { channel -> Double in
            let normalized = channel / 255
            return normalized <= 0.04045 ? normalized / 12.92 : pow((normalized + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    private static func lStar(_ value: UInt32) -> Double {
        let y = luminance(value)
        let fy = y > 216.0 / 24389.0 ? pow(y, 1.0 / 3.0) : ((24389.0 / 27.0 * y) + 16) / 116
        return 116 * fy - 16
    }
}
