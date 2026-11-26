// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenTap",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ScreenTap",
            path: "Sources/ScreenTap",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
