// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Rumkapsel",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Rumkapsel",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Rumkapsel",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ],
    swiftLanguageVersions: [.v5]
)
