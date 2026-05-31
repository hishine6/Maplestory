// swift-tools-version: 6.1
// 위 줄은 "이 패키지는 Swift 6.1 도구로 만든다"는 선언이에요. 꼭 첫 줄에 있어야 해요.

import PackageDescription

// Package = 이 프로젝트가 무엇인지 설명하는 설정 파일이에요.
// Xcode의 프로젝트 설정 화면을 글로 적어둔 것이라고 보면 돼요.
let package = Package(
    name: "FocusTimer",                 // 앱(패키지) 이름
    platforms: [.macOS(.v14)],          // macOS 14 이상에서 돌아간다는 뜻 (SwiftUI 최신 기능 사용 위해)
    targets: [
        // executableTarget = "실행 가능한 앱"을 만든다는 의미.
        // path 안의 .swift 파일들이 이 앱의 코드예요.
        .executableTarget(
            name: "FocusTimer",
            path: "Sources/FocusTimer"
        )
    ]
)
