// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalVoice",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LocalVoice",
            path: "Sources/LocalVoice"
        )
    ]
)
