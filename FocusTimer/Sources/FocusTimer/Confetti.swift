import SwiftUI
import AppKit

// ============================================================
//  화면 전체에 쏟아지는 '컨페티(색종이)' 효과 View.
//  - 예전엔 이 파일이 창 띄우는 일까지 했지만, 이제 창 관리는 범용
//    EffectOverlay 가 맡고(여기 EffectOverlay.swift), 이 파일은 '색종이를
//    그리는 View(ConfettiView)' 와 입자 데이터(ConfettiPiece/Factory)만 담아요.
//  - 그래서 불꽃놀이·풍선 같은 다른 효과와 ZStack 으로 겹쳐 쓸 수 있어요.
// ============================================================


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
