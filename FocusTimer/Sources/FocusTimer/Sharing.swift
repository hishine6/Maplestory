import SwiftUI
import AppKit

// ============================================================
//  Sharer — 친구들과 '오늘 몇 시간 했는지'를 Discord 채널로 공유.
//
//  원리: Discord 채널에 만든 '웹훅(Webhook) URL' 로 JSON 한 줄을 POST 하면
//        그 메시지가 채널에 뜨고, 채널에 있는 친구들이 푸시로 받아요.
//        서버를 따로 세울 필요가 없어요(웹훅 URL = 비밀 주소).
//
//  - 웹훅 URL/내 이름/자동공유 설정은 TimeTracker 에 저장돼요(설정 탭에서 입력).
//  - 전송은 fire-and-forget: 실패해도 앱 동작엔 영향 없고, 수동 공유일 땐
//    성공/실패를 작은 토스트로 알려줘요.
// ============================================================
@MainActor
enum Sharer {

    // 웹훅 URL이 채워져 있고 Discord 주소처럼 보이면 '설정됨'.
    static var isConfigured: Bool {
        let u = TimeTracker.shared.shareWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return !u.isEmpty && u.hasPrefix("https://") && u.contains("discord")
    }

    // 임의의 한 줄을 채널로 보냄. showToast=true 면 결과를 토스트로 알려줘요.
    static func post(_ content: String, showToast: Bool) {
        let raw = TimeTracker.shared.shareWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), isConfigured else {
            if showToast {
                CelebrationToast.shared.show(emoji: "⚠️", title: "공유 채널이 없어요",
                    subtitle: "설정 탭에서 Discord 웹훅 URL을 먼저 넣어 주세요.")
            }
            return
        }

        // 채널에 표시될 이름(비어 있으면 기본값). content 에 이름이 안 들어가도
        // username 으로 누가 보냈는지 보이게 해요.
        let name = TimeTracker.shared.shareName.trimmingCharacters(in: .whitespacesAndNewlines)
        var payload: [String: Any] = ["content": content]
        payload["username"] = name.isEmpty ? "Daily Punchclock" : name

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = httpBody
        let request = req                      // Sendable 값으로 캡처

        // @MainActor Task 안에서 await — 네트워크는 백그라운드에서 돌고
        // 끝나면 다시 메인으로 돌아와 토스트를 안전하게 띄워요(Swift6 동시성 OK).
        Task { @MainActor in
            var ok = false
            do {
                let (_, resp) = try await URLSession.shared.data(for: request)
                ok = (resp as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            } catch {
                ok = false
            }
            guard showToast else { return }
            CelebrationToast.shared.show(
                emoji: ok ? "📤" : "⚠️",
                title: ok ? "친구에게 공유했어요" : "공유 실패",
                subtitle: ok ? content : "웹훅 URL을 다시 확인해 주세요.")
        }
    }

    // 오늘 누적(측정 중이면 그것도 포함)을 보기 좋게 만들어 공유.
    static func shareToday(showToast: Bool = true) {
        let secs = TimeTracker.shared.liveTodayTotal
        post("오늘 \(Fmt.human(secs)) 집중했어요 ⏱️", showToast: showToast)
    }

    // 연결 확인용 테스트 메시지.
    static func sendTest() {
        post("👋 연결 테스트 — 여기로 기록이 올라가요!", showToast: true)
    }
}
