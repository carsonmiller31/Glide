// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Glide",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "GlideCore"),
        .executableTarget(name: "Glide", dependencies: ["GlideCore"]),
        .testTarget(name: "GlideCoreTests", dependencies: ["GlideCore"]),
    ],
    swiftLanguageModes: [.v5]
)
