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
        .executable(name: "roost-hostd-daemon", targets: ["RoostHostdDaemon"]),
        .executable(name: "RoostHostdXPCService", targets: ["RoostHostdXPCService"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.1"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
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
                .product(name: "SwiftTerm", package: "SwiftTerm"),
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
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Muxy",
            exclude: ["Info.plist", "Muxy.entitlements", "Resources/ghostty", "Resources/terminfo", "Resources/rg"],
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Resources/AppIcons"),
                .process("Resources/ProviderIcons"),
                .process("Resources/markdown-assets"),
                .process("Resources/scripts"),
                .process("Resources/themes"),
                .copy("Resources/ghostty"),
                .copy("Resources/terminfo"),
                .copy("Resources/rg"),
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
            name: "RoostHostdDaemon",
            dependencies: [
                "RoostHostdCore",
            ],
            path: "RoostHostdDaemon"
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
                .product(name: "Yams", package: "Yams"),
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
