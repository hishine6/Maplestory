import SwiftUI
import AppKit

// ============================================================
//  FocusCheck — '정말 집중하고 있나?' 졸음 방지 확인.
//
//  켜면(설정 탭) 측정 중 가끔 화면 '테두리'에 클릭 버튼이 통 떠요.
//   - 30초 안에 누르면 통과 → 다음 확인은 한 주기 뒤.
//   - 30초 안에 못 누르면 실패 → 잠시(1분) 뒤 다시 확인.
//   - 3번 '연속' 실패하면 = 자리 비우고 졸고 있을 가능성 → 측정을 자동 종료.
//     이때 끝 시각은 '첫 실패가 뜬 순간'으로 되돌려, 졸던 시간은 빼요.
//
//  창은 nonactivating 패널이라, 클릭해도 지금 하던 작업의 포커스를 안 뺏어요.
// ============================================================
@MainActor
final class FocusCheck {
    static let shared = FocusCheck()
    private init() {}

    // 튜닝 값
    static let answerWindow: TimeInterval = 30    // 눌러야 하는 제한 시간(초)
    static let retryAfterMiss: TimeInterval = 60  // 한 번 놓친 뒤 다음 확인까지(초)
    static let failsToStop = 3                    // 연속 실패 몇 번이면 자동 종료

    private var nextItem: DispatchWorkItem?        // 다음 확인 예약
    private var timeoutItem: DispatchWorkItem?     // 현재 확인의 30초 제한
    private var panel: NSPanel?
    private var failCount = 0
    private var firstFailAt: Date?                 // 연속 실패의 '첫' 시각
    private var away = false                        // 화면보호기/잠금/디스플레이 꺼짐 = 자리 비움

    private var isEnabled: Bool { TimeTracker.shared.focusCheckEnabled }
    private var interval: TimeInterval {
        Double(max(1, TimeTracker.shared.focusCheckIntervalMinutes)) * 60
    }

    // ── 측정 시작/종료/설정변경에 따른 진입점 ────────────────
    func measurementDidStart() {
        guard isEnabled else { return }
        failCount = 0; firstFailAt = nil
        scheduleNext(after: interval)             // 첫 확인은 한 주기 뒤(바로 안 귀찮게)
    }

    func measurementDidStop() {
        nextItem?.cancel(); nextItem = nil
        timeoutItem?.cancel(); timeoutItem = nil
        dismissPanel()
        failCount = 0; firstFailAt = nil
    }

    // 설정 탭에서 켜고/끄거나 주기를 바꿨을 때 호출(.onChange).
    func settingsChanged() {
        guard TimeTracker.shared.isRunning else { measurementDidStop(); return }
        if isEnabled {
            if panel == nil, !away { scheduleNext(after: interval) }   // 창 떠 있으면 그대로 두고, 아니면 새 주기로 재예약
        } else {
            measurementDidStop()
        }
    }

    // ── '자리 비움'(화면보호기/잠금/디스플레이 꺼짐) 동안엔 확인을 멈춰요. ──
    //  내가 'working 중'(자리에 있고 화면이 켜진 상태)일 때만 확인이 뜨도록.
    //  자리 비운 사이엔 안 띄우고, 떠 있던 확인은 실패로 치지 않고 닫아요.
    //  (자리 비움 자체는 AppDelegate의 5분 자동종료가 따로 처리해요.)
    func setAway(_ on: Bool) {
        away = on
        if on {
            nextItem?.cancel(); nextItem = nil
            timeoutItem?.cancel(); timeoutItem = nil
            dismissPanel()
            failCount = 0; firstFailAt = nil
        } else {
            if TimeTracker.shared.isRunning, isEnabled, panel == nil { scheduleNext(after: interval) }
        }
    }

    // ── 다음 확인 예약 ──────────────────────────────────────
    private func scheduleNext(after seconds: TimeInterval) {
        nextItem?.cancel()
        // 칼같은 주기가 아니라 '언저리에 랜덤'하게 — ±30% 흔들어요.
        // (예: 15분이면 약 10.5~19.5분 사이 무작위로 떠요.)
        let jitter = Double.random(in: -0.30...0.30) * seconds
        let delay = max(5, seconds + jitter)
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.present() }
        }
        nextItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // ── 확인 버튼 띄우기 (실제 확인) ─────────────────────────
    private func present() {
        nextItem = nil
        guard TimeTracker.shared.isRunning, isEnabled, !away, panel == nil else { return }
        let appearedAt = Date()
        showPanel { [weak self] in self?.passed() }
        // 30초 제한 → 못 누르면 실패 처리
        let timeout = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.missed(appearedAt: appearedAt) }
        }
        timeoutItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.answerWindow, execute: timeout)
    }

    // ── 설정의 '지금 테스트' — 실패 카운트/스케줄과 무관하게 버튼만 한 번 띄워요. ──
    func testNow() {
        guard panel == nil else { return }
        showPanel { [weak self] in
            self?.timeoutItem?.cancel(); self?.timeoutItem = nil
            self?.dismissPanel()
            NSSound(named: NSSound.Name("Pop"))?.play()
        }
        let timeout = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.timeoutItem = nil; self?.dismissPanel() }
        }
        timeoutItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.answerWindow, execute: timeout)
    }

    // 패널을 만들어 화면 테두리에 띄우고 주의 사운드를 울려요. onHit = 버튼 클릭 동작.
    private func showPanel(onHit: @escaping () -> Void) {
        let size = NSSize(width: 150, height: 150)
        let hosting = NSHostingView(rootView: FocusCheckView(seconds: Self.answerWindow, onHit: onHit))
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.contentView = hosting
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = false                 // 클릭돼야 하니까!
        p.level = .floating                          // 일반 창들 위에
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        positionAtRandomEdge(p, size: size)
        p.orderFrontRegardless()
        panel = p
        NSSound(named: NSSound.Name("Ping"))?.play() // 주의를 끌어요
    }

    // ── 통과(눌렀음) ────────────────────────────────────────
    private func passed() {
        timeoutItem?.cancel(); timeoutItem = nil
        dismissPanel()
        failCount = 0; firstFailAt = nil
        NSSound(named: NSSound.Name("Pop"))?.play()
        if TimeTracker.shared.isRunning, isEnabled { scheduleNext(after: interval) }
    }

    // ── 실패(30초 안에 못 누름) ──────────────────────────────
    private func missed(appearedAt: Date) {
        timeoutItem = nil
        dismissPanel()
        failCount += 1
        if firstFailAt == nil { firstFailAt = appearedAt }

        if failCount >= Self.failsToStop {
            let endAt = firstFailAt                  // 졸기 시작한 첫 실패 순간으로 되돌림
            failCount = 0; firstFailAt = nil
            if TimeTracker.shared.isRunning {
                TimeTracker.shared.stop(at: endAt)   // (이 stop이 measurementDidStop도 호출)
            }
            NSSound(named: NSSound.Name("Basso"))?.play()
            CelebrationToast.shared.show(
                emoji: "😴",
                title: "집중 확인 \(Self.failsToStop)회 실패",
                subtitle: "졸고 있던 것 같아 측정을 멈췄어요. 다시 시작하려면 ▶︎를 눌러요.")
        } else {
            // 곧 다시 확인(빨리 연속 실패를 판정).
            let left = Self.failsToStop - failCount
            CelebrationToast.shared.show(
                emoji: "⏰",
                title: "집중 확인을 놓쳤어요 (\(failCount)/\(Self.failsToStop))",
                subtitle: "\(left)번 더 놓치면 측정이 멈춰요.")
            if TimeTracker.shared.isRunning, isEnabled { scheduleNext(after: Self.retryAfterMiss) }
        }
    }

    private func dismissPanel() {
        panel?.orderOut(nil)
        panel = nil
    }

    // 화면 테두리(상/하/좌/우) 중 무작위 위치에 놓아 '진짜 찾아서' 누르게 해요.
    private func positionAtRandomEdge(_ w: NSWindow, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let m: CGFloat = 12
        let xLo = vf.minX + m, xHi = max(vf.minX + m, vf.maxX - size.width - m)
        let yLo = vf.minY + m, yHi = max(vf.minY + m, vf.maxY - size.height - m)
        var x = (xLo + xHi) / 2
        var y = (yLo + yHi) / 2
        switch Int.random(in: 0..<4) {
        case 0: y = yHi; x = CGFloat.random(in: xLo...xHi)   // 위
        case 1: y = yLo; x = CGFloat.random(in: xLo...xHi)   // 아래
        case 2: x = xLo; y = CGFloat.random(in: yLo...yHi)   // 왼쪽
        default: x = xHi; y = CGFloat.random(in: yLo...yHi)  // 오른쪽
        }
        w.setFrameOrigin(NSPoint(x: x, y: y))
    }
}


// ── 클릭해야 하는 확인 버튼(맥동 + 30초 카운트다운 링) ──────────
struct FocusCheckView: View {
    let seconds: Double
    let onHit: () -> Void

    private let birth = Date()
    @State private var pulse = false

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(birth)
            let remain = max(0, seconds - elapsed)
            let frac = seconds > 0 ? remain / seconds : 0

            Button(action: onHit) {
                ZStack {
                    Circle()
                        .fill(Color.orange.gradient)
                        .shadow(color: .orange.opacity(0.6), radius: 14)
                    // 남은 시간 링(점점 줄어듦)
                    Circle()
                        .trim(from: 0, to: frac)
                        .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(7)
                    VStack(spacing: 1) {
                        Image(systemName: "hand.tap.fill").font(.system(size: 26))
                        Text("집중 확인").font(.system(size: 11, weight: .bold))
                        Text("\(Int(ceil(remain)))초")
                            .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: 112, height: 112)
                .scaleEffect(pulse ? 1.06 : 0.92)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
