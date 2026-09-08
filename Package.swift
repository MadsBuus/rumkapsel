// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Rymdkapsel",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Rymdkapsel",
            path: "Sources/Rymdkapsel",
            swiftSettings: [.unsafeFlags(["-Onone"], .when(configuration: .debug))]
        )
    ],
    swiftLanguageVersions: [.v5]
)
