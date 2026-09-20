// swift-tools-version: 6.0
import PackageDescription

// The app is one executable target. SwiftPM lets a test target `@testable import` an executable
// on macOS, so the tests reach internal types without splitting the sources into a library
// (which would move every file while other branches are editing them).
let package = Package(
    name: "Nook",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Nook",
            path: "Sources/Nook",
            resources: [.copy("Assets")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Every file under Tests/NookTests is picked up; add new test files there.
        .testTarget(
            name: "NookTests",
            dependencies: ["Nook"],
            path: "Tests/NookTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
