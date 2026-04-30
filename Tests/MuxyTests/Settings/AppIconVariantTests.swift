import AppKit
import Testing

@testable import Roost

@Suite("AppIconVariant")
struct AppIconVariantTests {
    @Test("loads known variants in settings order")
    func knownVariants() {
        #expect(AppIconVariant.allCases.map(\.rawValue) == [
            "graphite",
            "blueprint",
            "light",
            "copper",
        ])
        #expect(AppIconVariant.allCases.map(\.displayName) == [
            "Graphite",
            "Blueprint",
            "Light",
            "Copper",
        ])
    }

    @Test("maps variants to bundled Icon Composer resources")
    func iconNames() {
        #expect(AppIconVariant.graphite.iconName == "Graphite")
        #expect(AppIconVariant.blueprint.iconName == "Blueprint")
        #expect(AppIconVariant.light.iconName == "Light")
        #expect(AppIconVariant.copper.iconName == "Copper")
    }

    @Test("unknown persisted value falls back to graphite")
    func fallback() {
        #expect(AppIconVariant.resolved(rawValue: "future") == .graphite)
        #expect(AppIconVariant.resolved(rawValue: "") == .graphite)
        #expect(AppIconVariant.resolved(rawValue: "blueprint") == .blueprint)
    }

    @MainActor
    @Test("loads bundled icon images")
    func bundledImagesLoad() {
        for variant in AppIconVariant.allCases {
            let image = AppIconService.image(for: variant)
            #expect(image != nil)
            #expect(image?.size == NSSize(width: 512, height: 512))
        }
    }

    @MainActor
    @Test("rendered icon images hide package canvas corners")
    func renderedImagesMaskCanvasCorners() throws {
        for variant in AppIconVariant.allCases {
            let image = try #require(AppIconService.image(for: variant))
            let imageData = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: imageData))
            let cornerAlpha = try #require(bitmap.colorAt(x: 0, y: 0)?.alphaComponent)
            let centerAlpha = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.alphaComponent)

            #expect(cornerAlpha < 0.1)
            #expect(centerAlpha > 0.9)
        }
    }
}
