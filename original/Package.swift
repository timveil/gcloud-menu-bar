// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GCloudMenuBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "GCloudMenuBar",
            path: "Sources/GCloudMenuBar",
            resources: [.process("Resources")]
        )
    ]
)
