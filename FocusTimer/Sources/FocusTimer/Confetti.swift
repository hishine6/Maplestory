import SwiftUI
import AppKit

// ============================================================
//  화면 전체에 컨페티(색종이)가 쏟아지는 축하 효과.
//  핵심 아이디어:
//   - 화면을 꽉 채우는 '투명한 borderless 창'을 모든 것 위에 띄우고
//   - 클릭은 통과(ignoresMouseEvents)시켜 일하던 걸 막지 않고
//   - SwiftUI Canvas로 색종이 입자를 매 프레임 그려서 떨어뜨리고
//   - 몇 초 뒤 자동으로 닫아요.
//  (1시간 토스트 창과 같은 기술을 '화면 전체 + 클릭통과'로 키운 거예요)
// ============================================================
@MainActor
final class ConfettiOverlay {
    static let shared = ConfettiOverlay()
    private var windows: [NSWindow] = []
    private var clearItem: DispatchWorkItem?

    func fire(duration: Double = 3.6) {
        // 손쉬운 사용(모션 줄이기) 설정이 켜져 있으면 컨페티는 생략해요.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return }

        dismiss()  // 이전 게 남아 있으면 정리

        // 연결된 모니터마다 하나씩 띄워요.
        for screen in NSScreen.screens {
            let view = ConfettiView(pieces: ConfettiFactory.make(180), birth: Date())
            let hosting = NSHostingView(rootView: view)

            let w = NSWindow(contentRect: screen.frame,
                             styleMask: [.borderless], backing: .buffered, defer: false)
            w.contentView = hosting
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true                       // 클릭 통과
            w.level = .screenSaver                             // 거의 모든 것 위에
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()                           // 앱이 비활성이어도 보여줌
            windows.append(w)
        }

        // duration 뒤 자동으로 닫기
        let item = DispatchWorkItem { [weak self] in self?.dismiss() }
        clearItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    func dismiss() {
        clearItem?.cancel()
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
    }
}


// ── 색종이 한 조각의 정보 ───────────────────────────────────
struct ConfettiPiece {
    let x: CGFloat        // 시작 가로 위치(0~1 비율)
    let color: Color
    let size: CGFloat
    let vx: CGFloat       // 가로로 흘러가는 속도(px/초)
    let fallDur: Double   // 위→아래로 떨어지는 데 걸리는 시간(초)
    let delay: Double     // 시작 지연(다 같이 안 떨어지게)
    let spin: Double      // 회전 속도(라디안/초)
    let swayAmp: CGFloat  // 좌우로 살랑이는 폭
    let swayFreq: Double  // 살랑이는 빠르기
    let wide: Bool        // 납작한 모양인지
}

enum ConfettiFactory {
    static let palette: [Color] = [
        .red, .orange, .yellow, .green, .mint, .blue, .purple, .pink,
        Color(red: 0.30, green: 0.55, blue: 0.98),
        Color(red: 0.61, green: 0.40, blue: 0.94),
    ]
    static func make(_ n: Int) -> [ConfettiPiece] {
        (0..<n).map { _ in
            ConfettiPiece(
                x: CGFloat.random(in: 0...1),
                color: palette.randomElement()!,
                size: CGFloat.random(in: 7...13),
                vx: CGFloat.random(in: -45...45),
                fallDur: Double.random(in: 2.2...3.6),
                delay: Double.random(in: 0...0.9),
                spin: Double.random(in: -6...6),
                swayAmp: CGFloat.random(in: 8...30),
                swayFreq: Double.random(in: 1.4...3.4),
                wide: Bool.random()
            )
        }
    }
}


// ── 색종이를 매 프레임 그리는 화면 ──────────────────────────
struct ConfettiView: View {
    let pieces: [ConfettiPiece]
    let birth: Date

    var body: some View {
        // TimelineView(.animation) = 화면 주사율에 맞춰 계속 다시 그려달라는 뜻.
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(birth)
                for p in pieces {
                    let lt = t - p.delay
                    if lt <= 0 { continue }
                    let prog = lt / p.fallDur          // 0(위) → 1(아래)
                    if prog > 1.15 { continue }        // 다 떨어졌으면 건너뜀

                    let y = -30 + CGFloat(min(prog, 1.15)) * (size.height + 60)
                    let x = p.x * size.width + p.vx * CGFloat(lt) + sin(lt * p.swayFreq) * p.swayAmp

                    var c = context                    // 조각마다 따로 회전시키려고 복사본 사용
                    c.opacity = prog > 1 ? max(0, 1 - (prog - 1) / 0.15) : 1   // 끝에서 서서히 사라짐
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.spin * lt))
                    let w = p.size
                    let h = p.wide ? p.size * 0.5 : p.size
                    let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
                    c.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
