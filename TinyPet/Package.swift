// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TinyPet",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TinyPet",
            path: "Sources/TinyPet"
        )
    ]
)
