// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CursorUsageWidget",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CursorUsageWidget", targets: ["CursorUsageWidget"])
    ],
    targets: [
        .target(
            name: "CursorUsageLib",
            path: "Sources/CursorUsageWidget"
        ),
        .executableTarget(
            name: "CursorUsageWidget",
            dependencies: ["CursorUsageLib"],
            path: "Sources/CursorUsageWidgetMain"
        ),
        .testTarget(
            name: "CursorUsageWidgetTests",
            dependencies: ["CursorUsageLib"]
        ),
    ]
)
