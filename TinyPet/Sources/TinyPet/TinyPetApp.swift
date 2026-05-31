import SwiftUI
import AppKit

// 앱의 시작점.
@main
struct TinyPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Tiny Pet") {
            ContentView()
        }
        .windowResizability(.contentSize)   // 창 크기를 내용에 맞게 고정
    }
}

// 창을 정상 앱처럼 띄우고 앞으로 가져오는 코드 (FocusTimer와 동일)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
