import SwiftUI

// ContentView = 우리가 실제로 보는 화면 한 장이에요.
// SwiftUI에서는 화면을 이렇게 'struct'로 만들고 그 안 body에 무엇을 그릴지 적어요.
struct ContentView: View {

    // ── 상태(State) ──────────────────────────────────────────
    // @State = "값이 바뀌면 화면을 자동으로 다시 그려라"라는 표시예요.
    // 이게 SwiftUI의 핵심! 변수만 바꾸면 화면이 알아서 갱신돼요.

    @State private var remainingSeconds = 25 * 60   // 남은 시간(초). 처음엔 25분.
    @State private var isRunning = false            // 타이머가 도는 중인지

    // 1초마다 신호를 보내주는 타이머. 아래 onReceive에서 이 신호를 받아요.
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // ── 화면(body) ──────────────────────────────────────────
    var body: some View {
        VStack(spacing: 24) {                       // 세로로 차곡차곡 쌓기

            Text("집중 타이머")
                .font(.headline)
                .foregroundStyle(.secondary)

            // 남은 시간을 "25:00" 형태로 크게 표시
            Text(timeString)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()                  // 숫자 폭 고정 → 깜빡임 없이 안정적

            // 버튼 두 개를 가로로 나란히
            HStack(spacing: 16) {

                // 시작/일시정지 버튼: 누르면 isRunning을 뒤집어요.
                Button(isRunning ? "일시정지" : "시작") {
                    isRunning.toggle()
                }
                .keyboardShortcut(.space, modifiers: [])  // 스페이스바로도 가능

                // 리셋 버튼: 25분으로 되돌리고 멈춤.
                Button("리셋") {
                    isRunning = false
                    remainingSeconds = 25 * 60
                }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(width: 320)
        // ── 매 초 호출되는 부분 ──
        // 타이머가 보낸 신호를 받을 때마다 실행돼요.
        .onReceive(ticker) { _ in
            // 돌고 있고, 0보다 클 때만 1초 줄임
            guard isRunning, remainingSeconds > 0 else { return }
            remainingSeconds -= 1
            if remainingSeconds == 0 {
                isRunning = false                   // 0이 되면 자동 정지
            }
        }
    }

    // 남은 초(예: 1500)를 "25:00" 문자열로 바꿔주는 도우미.
    private var timeString: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// 아래는 Xcode의 'Preview'(코드 옆 실시간 미리보기)에서 쓰는 부분이에요.
#Preview {
    ContentView()
}
