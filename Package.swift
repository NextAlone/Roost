// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Roost",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "MuxyShared", targets: ["MuxyShared"]),
        .executable(name: "RoostHostdXPCService", targets: ["RoostHostdXPCService"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.1"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "MuxyShared",
            path: "MuxyShared"
        ),
        .target(
            name: "RoostHostdCore",
            dependencies: [
                "MuxyShared",
            ],
            path: "RoostHostdCore"
        ),
        .target(
            name: "GhosttyKit",
            path: "GhosttyKit",
            publicHeadersPath: "."
        ),
        .target(
            name: "MuxyServer",
            dependencies: [
                "MuxyShared",
            ],
            path: "MuxyServer"
        ),
        .executableTarget(
            name: "Roost",
            dependencies: [
                "GhosttyKit",
                "MuxyShared",
                "MuxyServer",
                "RoostHostdCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Muxy",
            exclude: ["Info.plist", "Muxy.entitlements", "Resources/ghostty", "Resources/terminfo"],
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Resources/AppIcons"),
                .process("Resources/ProviderIcons"),
                .process("Resources/markdown-assets"),
                .process("Resources/scripts"),
                .process("Resources/themes"),
                .copy("Resources/ghostty"),
                .copy("Resources/terminfo"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "GhosttyKit.xcframework/macos-arm64_x86_64/ghostty-internal.a",
                ]),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("Foundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedLibrary("c++"),
            ]
        ),
        .executableTarget(
            name: "RoostHostdXPCService",
            dependencies: [
                "MuxyShared",
                "RoostHostdCore",
            ],
            path: "RoostHostdXPCService",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "RoostTests",
            dependencies: [
                "Roost",
                "RoostHostdXPCService",
                "MuxyShared",
                "MuxyServer",
                "RoostHostdCore",
            ],
            path: "Tests/MuxyTests",
            linkerSettings: [
                .unsafeFlags([
                    "GhosttyKit.xcframework/macos-arm64_x86_64/ghostty-internal.a",
                ]),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("Foundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
