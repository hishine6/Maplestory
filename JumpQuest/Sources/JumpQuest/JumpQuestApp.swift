import SwiftUI
import AppKit

@main
struct JumpQuestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("bamtistory") {
            ContentView()
        }
        .windowResizability(.contentMinSize)   // 창 크기 조절 허용(최소 크기 이상으로 자유 확대)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 헤드리스 엔진 검증 모드 (창 안 띄우고 종료) — 작업 방해 없이 fetch+정렬 확인용
        if ProcessInfo.processInfo.environment["CHARGEN_TEST"] != nil {
            CharacterRenderer.selfTest()
            exit(0)
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
