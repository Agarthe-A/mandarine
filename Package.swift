// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mandarine",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Mandarine", path: "Sources")
    ]
)
