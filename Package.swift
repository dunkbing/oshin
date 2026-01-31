// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "oshin",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "Vendor/SwiftGitX"),
    ],
    targets: [
        .systemLibrary(
            name: "GhosttyKit",
            path: "Vendor/ghostty/include"
        ),
        .executableTarget(
            name: "oshin",
            dependencies: [
                .product(name: "SwiftGitX", package: "SwiftGitX"),
                "GhosttyKit",
            ],
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5)
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
