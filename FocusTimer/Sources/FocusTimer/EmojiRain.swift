import SwiftUI

// ============================================================
//  EmojiRain — 축하 이모지(🎉🌟💪🔥✨🏆 …)가 위에서
//  회전·살랑이며 떨어지는 '컨페티의 이모지 버전' 효과.
//   - SwiftUI Canvas 에 이모지를 '텍스트'로 그려서 떨어뜨려요.
//   - TimelineView(.animation) 으로 매 프레임 다시 그려요.
//   - 화면/표시/제거는 오버레이 컨트롤러가 하므로 여기선 'View 하나'만.
//  (Confetti.swift 의 ConfettiView 관용구를 이모지에 맞게 옮긴 거예요)
//
//  성능 메모: 이모지 글리프는 매 프레임 새로 resolve 하면 비싸요(글자 레이아웃).
//  그래서 글리프 종류(~10개)마다 '기준 크기 40pt 로 1회만' resolve 해 캐시하고,
//  방울마다 크기는 컨텍스트 scaleBy 로 맞춰 그려 재사용해요.
// ============================================================

// ── 떨어지는 이모지 한 방울의 정보 ──────────────────────────
private struct EmojiDrop {
    let glyph: String     // 그릴 이모지
    let x: CGFloat         // 시작 가로 위치(0~1 비율)
    let size: CGFloat      // 폰트 크기(px)
    let vx: CGFloat        // 가로로 흘러가는 속도(px/초)
    let fallDur: Double    // 위→아래로 떨어지는 데 걸리는 시간(초)
    let delay: Double      // 시작 지연(다 같이 안 떨어지게)
    let spin: Double       // 회전 속도(라디안/초) — 살랑이며 회전
    let spinPhase: Double  // 회전 시작 위상(제각각 흔들리게)
    let swayAmp: CGFloat   // 좌우로 살랑이는 폭(px)
    let swayFreq: Double   // 살랑이는 빠르기
}

private enum EmojiRainFactory {
    // 축하 느낌의 이모지들. 밝은 데스크톱/어두운 데스크톱 둘 다에서 잘 보여요.
    static let glyphs: [String] = ["🎉", "🌟", "💪", "🔥", "✨", "🏆", "🎊", "⭐️", "💯", "🥳"]

    // 모든 글리프는 이 크기로 1회 resolve 한 뒤, 방울 크기에 맞춰 scale 해서 그려요.
    static let baseSize: CGFloat = 40

    static func make(_ n: Int) -> [EmojiDrop] {
        (0..<n).map { _ in
            EmojiDrop(
                glyph: glyphs.randomElement()!,
                x: CGFloat.random(in: 0...1),
                size: CGFloat.random(in: 22...40),   // baseSize(40) 이하 → 확대 없이 선명
                vx: CGFloat.random(in: -40...40),
                fallDur: Double.random(in: 2.4...4.0),
                delay: Double.random(in: 0...1.0),
                spin: Double.random(in: -2.2...2.2),
                spinPhase: Double.random(in: 0...(2 * .pi)),
                swayAmp: CGFloat.random(in: 10...34),
                swayFreq: Double.random(in: 1.2...3.0)
            )
        }
    }
}

// ── 이모지 비를 매 프레임 그리는 화면(공통 인터페이스 준수) ──
struct EmojiRainEffectView: View {
    let birth: Date
    let duration: Double
    // 난수는 init 에서 1회만 생성 — 이 뷰는 NSHostingView 에 한 번만 올라가요.
    private let drops: [EmojiDrop]

    init(birth: Date, duration: Double) {
        self.birth = birth
        self.duration = duration
        // 입자 수는 성능을 위해 ~200 이하로.
        self.drops = EmojiRainFactory.make(150)
    }

    // 마지막 0.4초 동안 전체 화면을 서서히 투명하게(페이드아웃).
    private let fadeOut: Double = 0.4

    var body: some View {
        // TimelineView(.animation) = 화면 주사율에 맞춰 계속 다시 그려달라는 뜻.
        TimelineView(.animation) { timeline in
            // 경과시간 t (초). 화면 크기는 Canvas 클로저의 size 를 사용.
            let t = timeline.date.timeIntervalSince(birth)

            // 끝에서 전체 opacity 를 0 으로 페이드아웃.
            let remain = duration - t
            let globalOpacity: Double = remain < fadeOut ? max(0, remain / fadeOut) : 1

            Canvas { context, size in
                // t > duration 이후엔 거의 안 그려도 되므로 일찍 빠져나가요.
                if t > duration + 0.1 { return }

                // 이 프레임에서 글리프별 resolve 결과를 캐시(같은 이모지는 한 번만 레이아웃).
                let base = EmojiRainFactory.baseSize
                var cache: [String: GraphicsContext.ResolvedText] = [:]

                for d in drops {
                    let lt = t - d.delay         // 이 방울의 '개인' 경과시간
                    if lt <= 0 { continue }      // 아직 시작 안 함
                    let prog = lt / d.fallDur    // 0(위) → 1(아래)
                    if prog > 1.15 { continue }  // 화면 아래로 다 떨어졌으면 건너뜀

                    // 위(-size 밖)에서 아래(화면 밖)까지 선형으로 낙하.
                    let y = -40 + CGFloat(min(prog, 1.15)) * (size.height + 80)
                    // 가로: 시작위치 + 흐름속도 + 사인 살랑임.
                    let x = d.x * size.width
                        + d.vx * CGFloat(lt)
                        + sin(lt * d.swayFreq + d.spinPhase) * d.swayAmp

                    // 방울마다 따로 회전/스케일시키려고 context 복사본을 사용.
                    var c = context
                    // 떨어진 끝부분(prog>1)에서 개별적으로도 서서히 사라지게,
                    // 전체 페이드아웃과 곱해서 적용.
                    let tailFade = prog > 1 ? max(0, 1 - (prog - 1) / 0.15) : 1
                    c.opacity = globalOpacity * tailFade
                    if c.opacity <= 0.01 { continue }

                    c.translateBy(x: x, y: y)
                    // 좌우 살랑임에 살짝 맞춰 회전(spin) — 이모지가 흔들리며 떨어져요.
                    c.rotate(by: .radians(d.spin * lt + d.spinPhase))
                    // 기준 크기(40)로 그린 글리프를 방울 크기에 맞춰 축소.
                    let scale = d.size / base
                    c.scaleBy(x: scale, y: scale)

                    // 밝은/어두운 배경 모두에서 보이도록 옅은 그림자를 깔아줘요.
                    // (Text 에는 그림자가 안 붙으니, 컨텍스트 필터로 그림자를 줘요.)
                    c.addFilter(.shadow(color: .black.opacity(0.35), radius: 1.5, x: 0, y: 1))

                    // 같은 글리프는 프레임당 한 번만 resolve 해 캐시에서 재사용.
                    let resolved: GraphicsContext.ResolvedText
                    if let hit = cache[d.glyph] {
                        resolved = hit
                    } else {
                        let r = context.resolve(Text(verbatim: d.glyph).font(.system(size: base)))
                        cache[d.glyph] = r
                        resolved = r
                    }
                    // (0,0) 을 중심으로 회전/스케일된 좌표계에 배치.
                    c.draw(resolved, at: .zero, anchor: .center)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
