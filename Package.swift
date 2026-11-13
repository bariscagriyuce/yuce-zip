// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "YuceZip",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "YuceZip",
            path: "Sources/YuceZip"
        )
    ]
)
