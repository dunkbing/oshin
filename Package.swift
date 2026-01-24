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
        .executableTarget(
            name: "agentmonitor",
            dependencies: [
                .product(name: "SwiftGitX", package: "SwiftGitX"),
            ],
            path: "Sources"
        ),
    ]
)
