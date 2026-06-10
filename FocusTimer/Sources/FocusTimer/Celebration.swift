import SwiftUI
import AppKit
import UserNotifications

// ============================================================
//  '오늘 누적 N시간 / 주간 / 월간 목표 달성!' 순간에 보여줄 축하 모음.
//
//  목표 달성 축하는 '3단계 점층(tier)' 으로 설계했어요 — 더 어려운 목표일수록
//  효과가 풍성하고, 길고, 소리가 웅장하고, 햅틱도 강해져요.
//
//    tier1 (하루):  컨페티 + 가벼운 트로피 줌            ~4.0초
//    tier2 (주간):  불꽃놀이 + 컨페티 + 가장자리 글로우   ~5.5초
//    tier3 (월간):  불꽃 + 풍선 + 이모지비 + 글로우 + 트로피  ~7.0초
//
//  매시간 마일스톤(fire(hours:)) 은 효과 없이 토스트만 유지해요(요구사항).
//  알림은 기존과 동일하게 '시스템 알림' 과 '인앱 토스트' 중 설정된 하나만!
// ============================================================
@MainActor
enum Celebration {

    // 모든 자동 알림·축하 효과 마스터 스위치. 꺼져 있으면 아래 자동 경로는
    // 전부 조용히 넘어가요(측정·마일스톤 기록은 호출부에서 계속 진행됨).
    private static var alertsOn: Bool { TimeTracker.shared.alertsEnabled }

    // ── 매시간 마일스톤: 화려한 효과 없이 토스트(또는 시스템 알림)만. ──
    static func fire(hours: Int) {
        guard alertsOn else { return }
        let m = message(hours: hours)
        notify(emoji: m.emoji, title: m.title, subtitle: m.subtitle)
    }

    // ── 하루 목표 달성! (tier1: 적당히) ───────────────────────
    static func goalReached() {
        autoShareGoalIfEnabled()        // 친구 공유는 로컬 알림 on/off 와 무관하게 처리
        guard alertsOn else { return }
        let hours = TimeTracker.shared.dailyGoalHours
        celebrate(tier: 1)
        notify(emoji: "🎊", title: "오늘 목표 달성! 🎯",
               subtitle: "오늘 \(hours)시간을 채웠어요. 멋져요! 🎉")
    }

    // 자동 공유가 켜져 있고 채널이 설정돼 있으면, 목표 달성을 친구 채널에 알려요.
    private static func autoShareGoalIfEnabled() {
        let t = TimeTracker.shared
        guard t.autoShareOnGoal, Sharer.isConfigured else { return }
        Sharer.post("🎯 오늘 목표(\(t.dailyGoalHours)시간) 달성! 지금까지 \(Fmt.human(t.liveTodayTotal)) 집중!",
                    showToast: false)
    }

    // ── 이번 주 목표 달성! (tier2: 더) ────────────────────────
    static func weeklyGoalReached() {
        guard alertsOn else { return }
        let hours = TimeTracker.shared.weeklyGoalHours
        celebrate(tier: 2)
        notify(emoji: "🎖️", title: "이번 주 목표 달성! 🎖️",
               subtitle: "이번 주 \(hours)시간을 채웠어요. 잘했어요!")
    }

    // ── 이번 달 목표 달성! (tier3: 풀세트) ────────────────────
    static func monthlyGoalReached() {
        guard alertsOn else { return }
        let hours = TimeTracker.shared.monthlyGoalHours
        celebrate(tier: 3)
        notify(emoji: "🏆", title: "이번 달 목표 달성! 🏆",
               subtitle: "이번 달 \(hours)시간을 채웠어요. 대단해요!")
    }

    // 새 업적 달성! (효과 없이 배지 토스트만)
    static func achievement(_ a: Achievement) {
        guard alertsOn else { return }
        notify(emoji: a.emoji, title: "업적 달성: \(a.title)", subtitle: a.detail)
    }

    // ── (미리보기용) 알림은 띄우지 않고 화면 효과만 — 단계별 모습 확인용. ──
    //  실제 목표 달성과 달리 '오늘 목표 달성' 알림/기록을 남기지 않아요.
    static func preview(tier: Int) {
        celebrate(tier: max(1, min(3, tier)))
    }

    // ──────────────────────────────────────────────────────────
    //  점층 축하의 핵심: tier 에 맞춰 (효과 조합 + 지속시간 + 사운드 + 햅틱)
    //  을 한곳에서 결정해요. 효과 View 의 표시/제거는 EffectOverlay 가 담당.
    // ──────────────────────────────────────────────────────────
    private static func celebrate(tier: Int) {
        // tier 별 지속시간 — 어려운 목표일수록 더 길게 즐겨요.
        let duration: Double
        switch tier {
        case 1:  duration = 4.0
        case 2:  duration = 5.5
        default: duration = 7.0
        }

        // 화면 효과: (birth, duration) 을 공유해 모든 효과의 박자를 맞춰요.
        // 모션 줄이기가 켜져 있으면 fire 내부에서 통째로 생략돼요(접근성).
        EffectOverlay.shared.fire(duration: duration) { birth, dur in
            switch tier {
            // tier1: 컨페티 + 가벼운 트로피 줌
            case 1:
                return [
                    AnyView(ConfettiView(pieces: ConfettiFactory.make(150), birth: birth)),
                    AnyView(TrophyZoomEffectView(birth: birth, duration: dur, emoji: "🏅")),
                ]

            // tier2: 불꽃놀이 + 컨페티 + 가장자리 글로우 (더 화려, 더 길게)
            case 2:
                return [
                    AnyView(EdgeGlowEffectView(birth: birth, duration: dur,
                                               color: Color(red: 1.0, green: 0.84, blue: 0.30))),
                    AnyView(FireworksEffectView(birth: birth, duration: dur)),
                    AnyView(ConfettiView(pieces: ConfettiFactory.make(160), birth: birth)),
                ]

            // tier3: 풀세트 — 불꽃 + 풍선 + 이모지비 + 글로우 + 트로피
            default:
                return [
                    AnyView(EdgeGlowEffectView(birth: birth, duration: dur,
                                               color: Color(red: 1.0, green: 0.78, blue: 0.25))),
                    AnyView(FireworksEffectView(birth: birth, duration: dur)),
                    AnyView(BalloonsEffectView(birth: birth, duration: dur)),
                    AnyView(EmojiRainEffectView(birth: birth, duration: dur)),
                    AnyView(TrophyZoomEffectView(birth: birth, duration: dur, emoji: "🏆")),
                ]
            }
        }

        // 사운드 + 햅틱은 화면 효과와 별개로 항상(모션 줄이기와 무관하게) 울려요.
        playSound(tier: tier)
        playHaptic(tier: tier)
    }

    // ── tier 별 사운드: 점점 웅장하게 (macOS 기본 시스템 사운드 사용) ──
    //  Glass(맑은 종)  → Hero(영웅적)  → Hero+Submarine(저음 보강)
    private static func playSound(tier: Int) {
        switch tier {
        case 1:
            NSSound(named: NSSound.Name("Glass"))?.play()
        case 2:
            NSSound(named: NSSound.Name("Hero"))?.play()
        default:
            // 월간: 영웅적 사운드 + 살짝 늦게 저음(Submarine)을 겹쳐 웅장하게.
            NSSound(named: NSSound.Name("Hero"))?.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                NSSound(named: NSSound.Name("Submarine"))?.play()
            }
        }
    }

    // ── tier 별 트랙패드 햅틱: 단계가 오를수록 더 또렷하게 ──
    //  햅틱은 Force Touch 트랙패드에서만 체감돼요(없는 기기에선 조용히 무시).
    private static func playHaptic(tier: Int) {
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch tier {
        case 1:
            performer.perform(.alignment, performanceTime: .now)
        case 2:
            performer.perform(.levelChange, performanceTime: .now)
        default:
            // 월간: 묵직한 '쿵쿵' 느낌을 위해 두 번 톡톡 겹쳐요.
            // (지연 클로저에선 캡처 대신 그 자리에서 다시 가져와 동시성 안전하게)
            performer.perform(.generic, performanceTime: .now)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
        }
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
