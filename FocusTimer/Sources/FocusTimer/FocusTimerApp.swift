import SwiftUI
import AppKit

// @main = "앱이 여기서 시작된다"는 표시. 프로그램의 출발점이에요.
@main
struct FocusTimerApp: App {

    // 아래 한 줄은 맥 앱이 창을 제대로 띄우고 앞으로 나오게 해주는 연결고리예요.
    // (SPM으로 만든 앱은 이게 없으면 창이 뒤에 숨는 경우가 있어서 넣어둬요.)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // body = 이 앱이 화면에 무엇을 보여줄지 정하는 부분.
    var body: some Scene {
        // WindowGroup = 앱의 창 하나. 그 안에 ContentView(우리가 만든 화면)를 띄워요.
        WindowGroup("Focus Timer") {
            ContentView()
        }
        // 창 크기를 내용에 딱 맞게 고정 (리사이즈 핸들 숨김)
        .windowResizability(.contentSize)
    }
}

// 앱이 켜질 때 "창을 일반 앱처럼 보여주고 앞으로 가져와라"라고 시키는 코드예요.
// 지금은 그냥 '이런 게 필요하구나' 정도만 알면 돼요.
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)        // Dock에 보이는 정상 앱으로 동작
        NSApp.activate(ignoringOtherApps: true)    // 실행하면 창을 앞으로
    }
}
