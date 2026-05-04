import AppKit
import GhosttyKit

enum TerminalResolvedColorScheme: Equatable {
    case light
    case dark

    var ghosttyValue: ghostty_color_scheme_e {
        switch self {
        case .light:
            GHOSTTY_COLOR_SCHEME_LIGHT
        case .dark:
            GHOSTTY_COLOR_SCHEME_DARK
        }
    }
}

enum TerminalColorSchemeResolver {
    static func resolve(backgroundColor: NSColor) -> TerminalResolvedColorScheme {
        guard let srgb = backgroundColor.usingColorSpace(.sRGB) else { return .dark }
        let luminance = 0.2126 * srgb.redComponent + 0.7152 * srgb.greenComponent + 0.0722 * srgb.blueComponent
        return luminance > 0.5 ? .light : .dark
    }
}
