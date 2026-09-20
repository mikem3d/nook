// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nook",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Nook",
            path: "Sources/Nook",
            resources: [.copy("Assets")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
