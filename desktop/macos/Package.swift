// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mox",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Mox", targets: ["Mox"])
    ],
    targets: [
        // Logic with no UI: configuration, hotkey parsing, the Supabase
        // client and its models. Unit-tested.
        .target(
            name: "MoxCore",
            path: "Sources/MoxCore"
        ),
        // The menu-bar app: AppKit UI, Finder, pasteboard, notifications.
        .executableTarget(
            name: "Mox",
            dependencies: ["MoxCore"],
            path: "Sources/Mox"
        ),
        .testTarget(
            name: "MoxCoreTests",
            dependencies: ["MoxCore"],
            path: "Tests/MoxCoreTests"
        )
    ]
)
