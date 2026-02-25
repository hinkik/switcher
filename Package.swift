// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Switcher",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Switcher",
            path: "Switcher",
            linkerSettings: [
                .unsafeFlags(["-framework", "Carbon"])
            ]
        )
    ]
)
