// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "JumpQuest",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "JumpQuest",
            path: "Sources/JumpQuest",
            resources: [.copy("monsters.json"), .copy("skills.json"), .copy("items.json")]   // JSON을 앱에 포함
        )
    ]
)
