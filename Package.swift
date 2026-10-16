// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RSSNewsBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "RSSNewsBar", targets: ["RSSNewsBar"])
    ],
    targets: [
        .executableTarget(
            name: "RSSNewsBar",
            path: "Sources/RSSNewsBar"
        )
    ]
)
