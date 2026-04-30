import AppKit

enum AppIconVariant: String, CaseIterable, Identifiable {
    case graphite
    case blueprint
    case light
    case copper

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .graphite:
            "Graphite"
        case .blueprint:
            "Blueprint"
        case .light:
            "Light"
        case .copper:
            "Copper"
        }
    }

    var iconName: String {
        switch self {
        case .graphite:
            "Graphite"
        case .blueprint:
            "Blueprint"
        case .light:
            "Light"
        case .copper:
            "Copper"
        }
    }

    static func resolved(rawValue: String) -> AppIconVariant {
        AppIconVariant(rawValue: rawValue) ?? .graphite
    }
}

enum AppIconSettings {
    static let selectedIconKey = "roost.appearance.selectedAppIcon"
    static let defaultVariant = AppIconVariant.graphite
}

@MainActor
enum AppIconService {
    static func applySelectedIcon(defaults: UserDefaults = .standard) {
        let rawValue = defaults.string(forKey: AppIconSettings.selectedIconKey) ?? AppIconSettings.defaultVariant.rawValue
        apply(AppIconVariant.resolved(rawValue: rawValue))
    }

    static func apply(_ variant: AppIconVariant) {
        guard let image = image(for: variant) else { return }
        NSApp.applicationIconImage = image
    }

    static func image(for variant: AppIconVariant) -> NSImage? {
        guard let url = previewURL(for: variant) else { return nil }
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 512, height: 512)
        return image
    }

    private static func previewURL(for variant: AppIconVariant) -> URL? {
        guard let resourceURL = Bundle.appResources.resourceURL else { return nil }

        let candidates = [
            resourceURL.appendingPathComponent("AppIcons").appendingPathComponent("Previews")
                .appendingPathComponent("\(variant.iconName).png"),
            resourceURL.appendingPathComponent("Previews").appendingPathComponent("\(variant.iconName).png"),
        ]

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        return nil
    }
}
