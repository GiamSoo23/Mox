// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mox",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Mox", targets: ["Mox"])
    ],
    targets: [
        .executableTarget(
            name: "Mox",
            path: "Sources/Mox"
        )
    ]
)
