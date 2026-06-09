import SwiftUI
import AppKit
import UserNotifications

// ============================================================
//  '오늘 누적 N시간 달성!' 순간에 보여줄 축하 모음.
//   1) 인앱 귀여운 팝업(화면 오른쪽 위에 통통 떴다 사라짐) + 부드러운 효과음
//   2) macOS 기본 알림(알림센터에 기록으로 남음) — 소리는 무음(인앱과 중복 방지)
//
//  쓰는 법: Celebration.fire(hours: 3)  → 알아서 셋 다 처리해요.
// ============================================================
@MainActor
enum Celebration {

    static func fire(hours: Int) {
        let m = message(hours: hours)
        notify(emoji: m.emoji, title: m.title, subtitle: m.subtitle)
    }

    // 하루 목표 달성! 화면 전체 컨페티 + 알림(택일).
    static func goalReached() {
        let hours = TimeTracker.shared.dailyGoalHours
        ConfettiOverlay.shared.fire()                            // 🎊 전체 화면 컨페티
        notify(emoji: "🎊", title: "오늘 목표 달성! 🎯",
               subtitle: "오늘 \(hours)시간을 채웠어요. 멋져요! 🎉")
    }

    // 이번 주 목표 달성!
    static func weeklyGoalReached() {
        let hours = TimeTracker.shared.weeklyGoalHours
        ConfettiOverlay.shared.fire(duration: 4.0)
        notify(emoji: "🎖️", title: "이번 주 목표 달성! 🎖️",
               subtitle: "이번 주 \(hours)시간을 채웠어요. 잘했어요!")
    }

    // 이번 달 목표 달성! (컨페티 더 길게)
    static func monthlyGoalReached() {
        let hours = TimeTracker.shared.monthlyGoalHours
        ConfettiOverlay.shared.fire(duration: 4.5)
        notify(emoji: "🏆", title: "이번 달 목표 달성! 🏆",
               subtitle: "이번 달 \(hours)시간을 채웠어요. 대단해요!")
    }

    // 새 업적 달성!
    static func achievement(_ a: Achievement) {
        notify(emoji: a.emoji, title: "업적 달성: \(a.title)", subtitle: a.detail)
    }

    // ── 알림은 '시스템'과 '앱 안 토스트' 중 설정된 하나만! ──
    private static func notify(emoji: String, title: String, subtitle: String) {
        switch TimeTracker.shared.notifyStyle {
        case .inApp:
            NSSound(named: NSSound.Name("Glass"))?.play()
            CelebrationToast.shared.show(emoji: emoji, title: title, subtitle: subtitle)
        case .system:
            Notifier.post(title: "\(emoji) \(title)", body: subtitle, sound: true)
        }
    }

    // 달성 시간에 맞춰 이모지/문구를 골라줘요.
    static func message(hours: Int) -> (emoji: String, title: String, subtitle: String) {
        let emoji: String
        switch hours {
        case 1: emoji = "🎉"
        case 2: emoji = "🔥"
        case 3: emoji = "💪"
        case 4: emoji = "🌟"
        case 5: emoji = "🚀"
        default: emoji = "👑"
        }
        let subs = [
            "잠깐 스트레칭 어때요? 🧘",
            "물 한 잔 마시고 가요 💧",
            "정말 잘하고 있어요 ✨",
            "이 페이스 좋아요, 계속 가봐요!",
            "눈도 잠깐 쉬어주세요 👀",
        ]
        let subtitle = subs[max(0, hours - 1) % subs.count]
        return (emoji, "오늘 \(hours)시간 집중 완료!", subtitle)
    }
}


// ── 인앱 귀여운 팝업 창 ─────────────────────────────────────
// 테두리 없는 투명 창을 화면 오른쪽 위(메뉴바 아래)에 잠깐 띄워요.
// 클릭은 통과(ignoresMouseEvents)되고, 몇 초 뒤 스르륵 사라져요.
@MainActor
final class CelebrationToast {
    static let shared = CelebrationToast()
    private var window: NSWindow?
    private var dismissItem: DispatchWorkItem?

    func show(emoji: String, title: String, subtitle: String) {
        // 이미 떠 있던 게 있으면 정리하고 새로 띄움
        dismissItem?.cancel()
        window?.orderOut(nil)

        let hosting = NSHostingView(
            rootView: ToastView(emoji: emoji, title: title, subtitle: subtitle)
        )
        hosting.layout()
        let size = hosting.fittingSize

        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        w.contentView = hosting
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false                 // 그림자는 SwiftUI가 직접 그려요
        w.level = .statusBar                // 메뉴바 근처에서도 위로 보이게
        w.ignoresMouseEvents = true         // 클릭이 통과돼 방해 안 됨
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        position(w, size: size)
        w.orderFrontRegardless()            // 앱이 비활성(메뉴바 전용)이어도 보여줌
        window = w

        // 3.4초 뒤 자동으로 사라짐
        let item = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4, execute: item)
    }

    // 화면 오른쪽 위(메뉴바 바로 아래)에 위치시켜요.
    private func position(_ w: NSWindow, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let x = vf.maxX - size.width - 8
        let y = vf.maxY - size.height - 4
        w.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func dismiss() {
        guard let w = window else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            w.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // 완료 핸들러는 메인 스레드에서 불려요 → assumeIsolated로 안전하게 정리.
            MainActor.assumeIsolated {
                self?.window?.orderOut(nil)
                self?.window = nil
            }
        }
    }
}


// ── 팝업 안에 그려지는 카드(통통 튀고 이모지가 살랑살랑) ─────
private struct ToastView: View {
    let emoji: String
    let title: String
    let subtitle: String

    @State private var shown = false     // 통통 튀어 들어오는 효과용
    @State private var wiggle = false     // 이모지 살랑살랑

    var body: some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.system(size: 34))
                .rotationEffect(.degrees(wiggle ? 9 : -9))
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: wiggle)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .bold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(width: 250, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        )
        .scaleEffect(shown ? 1 : 0.85)
        .opacity(shown ? 1 : 0)
        .padding(12)                      // 그림자가 창 밖으로 잘리지 않게 여백
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { shown = true }
            wiggle = true
        }
    }
}


// ── macOS 기본 알림 ────────────────────────────────────────
// 알림센터에 기록을 남겨요. 소리는 인앱 팝업에서 한 번만 울리도록 무음.
@MainActor
enum Notifier {

    // 앱 켤 때 한 번: 알림을 보내도 되는지 사용자에게 권한을 물어봐요.
    static func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }  // .app 번들로 실행될 때만
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String, sound: Bool = false) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound ? .default : nil
        let req = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}
