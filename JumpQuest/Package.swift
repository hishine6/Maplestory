// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "JumpQuest",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "JumpQuest",
            path: "Sources/JumpQuest",
            resources: [.copy("monsters.json"), .copy("skills.json"), .copy("items.json"),
                        .copy("sprites"), .copy("fonts")]   // JSON · 스프라이트 · 폰트(Galmuri 한글 픽셀)
        )
    ]
)
