// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GrokMenu",
    platforms: [.macOS("14.4")],
    targets: [
        .executableTarget(name: "GrokMenu", path: "Sources/GrokMenu")
    ]
)
