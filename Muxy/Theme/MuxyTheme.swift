import SwiftUI
import AppKit

enum MuxyTheme {
    static let bg = Color(nsColor: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.14, alpha: 1))
    static let surfaceDim = Color(nsColor: NSColor(srgbRed: 0.13, green: 0.13, blue: 0.16, alpha: 1))
    static let surface = Color(nsColor: NSColor(srgbRed: 0.15, green: 0.15, blue: 0.19, alpha: 1))
    static let border = Color.white.opacity(0.06)

    static let accent = Color(nsColor: NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 1))

    static let text = Color.white
    static let textMuted = Color.white.opacity(0.45)
    static let textDim = Color.white.opacity(0.25)

    static let hover = Color.white.opacity(0.04)
    static let pressed = Color.white.opacity(0.07)

    static let nsBg = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.14, alpha: 1)
}
