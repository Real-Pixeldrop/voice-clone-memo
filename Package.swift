// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceCloneMemo",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VoiceCloneMemo",
            path: "Sources/VoiceCloneMemo"
        )
    ]
)
