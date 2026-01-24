// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "agentmonitor",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/ibrahimcetin/SwiftGitX.git", from: "0.4.0"),
    ],
    targets: [
        // System library target for libghostty C headers
        .systemLibrary(
            name: "GhosttyKit",
            path: "Vendor/ghostty/include"
        ),
        .executableTarget(
            name: "agentmonitor",
            dependencies: [
                .product(name: "SwiftGitX", package: "SwiftGitX"),
                "GhosttyKit",
            ],
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5),  // Use Swift 5 mode to avoid strict concurrency errors
            ],
            linkerSettings: [
                // Link libghostty static library
                .unsafeFlags(["-L", "Vendor/libghostty/lib"]),
                .unsafeFlags(["-lghostty"]),
                // Required frameworks for Ghostty
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Carbon"),
                // Required libraries
                .linkedLibrary("z"),
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
