import SwiftUI

// ============================================================
//  🏆 TrophyZoom 축하 효과
//  - 중앙에 큰 트로피 이모지가 스프링으로 "통" 튀어나와요
//    (scale 이 살짝 1을 넘었다가 → 작은 반동 후 → 1로 안정 = 오버슈트).
//  - 등장과 거의 동시에 방사형 반짝임 링(빛줄기 + 작은 반짝이)을
//    한 번 바깥으로 뿜고 사라져요.
//  - 마지막엔 전체가 부드럽게 페이드아웃.
//  외부 의존성 없이 SwiftUI Canvas + TimelineView 로만 그려요.
// ============================================================
struct TrophyZoomEffectView: View {
    let birth: Date          // 효과가 시작된 시각(경과시간 t 계산 기준)
    let duration: Double     // 전체 지속 시간(초)
    let emoji: String        // 가운데에 띄울 이모지(기본 🏆)

    // 방사형으로 뻗는 "빛줄기" 한 개의 정보.
    private struct Ray {
        let angle: Double     // 뻗어나가는 방향(라디안)
        let length: CGFloat   // 최대 길이(반지름 비율)
        let width: CGFloat    // 줄기 두께
        let hue: Double       // 색상(0~1)
        let delay: Double     // 살짝씩 다른 타이밍에 터지도록
    }

    // 빛줄기 사이에 흩뿌려지는 작은 "반짝이" 한 개의 정보.
    private struct Spark {
        let angle: Double     // 날아가는 방향
        let dist: CGFloat     // 최종 도달 거리(반지름 비율)
        let size: CGFloat     // 반짝이 크기
        let hue: Double       // 색상(0~1)
        let twinkle: Double   // 깜빡임 위상
    }

    // 이 뷰는 NSHostingView 에 한 번만 올라가므로(재생성 X),
    // 난수 기반 입자들을 init 에서 1회만 만들어 저장해 둬요.
    private let rays: [Ray]
    private let sparks: [Spark]

    init(birth: Date, duration: Double, emoji: String = "🏆") {
        self.birth = birth
        self.duration = duration
        self.emoji = emoji

        // ── 빛줄기: 원 둘레에 고르게 배치(+약간의 흔들림)해 방사형 링을 만들어요.
        let rayCount = 18
        self.rays = (0..<rayCount).map { i in
            let base = Double(i) / Double(rayCount) * 2 * .pi
            return Ray(
                angle: base + Double.random(in: -0.06...0.06),
                length: CGFloat.random(in: 0.78...1.0),
                width: CGFloat.random(in: 3...6),
                hue: Double.random(in: 0.10...0.16),   // 금빛~노랑 계열
                delay: Double.random(in: 0...0.05)
            )
        }

        // ── 반짝이: 사방으로 흩뿌려요(채도 높은 다양한 색).
        self.sparks = (0..<70).map { _ in
            Spark(
                angle: Double.random(in: 0...(2 * .pi)),
                dist: CGFloat.random(in: 0.45...1.05),
                size: CGFloat.random(in: 2.5...6),
                hue: Double.random(in: 0...1),
                twinkle: Double.random(in: 0...(2 * .pi))
            )
        }
    }

    var body: some View {
        // TimelineView(.animation) = 화면 주사율에 맞춰 매 프레임 다시 그려달라는 뜻.
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(birth)
                if t < 0 { return }

                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height)  // 효과 크기의 기준 반지름

                // ── 전체 페이드: 마지막 0.4초 동안 1 → 0 으로 사라져요.
                let fade: Double
                if t > duration - 0.4 {
                    fade = max(0, (duration - t) / 0.4)
                } else {
                    fade = 1
                }
                if fade <= 0 { return }  // 다 사라졌으면 그릴 필요 없음

                // ── 방사형 반짝임 링: 시작 직후 한 번 "확" 퍼졌다가 잦아들어요.
                drawRays(context, center: center, radius: radius, t: t, fade: fade)
                drawSparks(context, center: center, radius: radius, t: t, fade: fade)

                // ── 중앙 트로피: 스프링 오버슈트 스케일로 통 튀어나와요.
                drawTrophy(context, center: center, radius: radius, t: t, fade: fade)
            }
        }
        .allowsHitTesting(false)   // 클릭은 데스크톱으로 통과
        .ignoresSafeArea()
    }

    // ── 스프링 오버슈트 스케일 ─────────────────────────────────
    //  감쇠 사인파로 0 → (1.25 부근으로 오버슈트) → 1 로 안정시켜요.
    private func springScale(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        let omega = 13.0          // 진동 빠르기
        let zeta = 0.42           // 감쇠(클수록 빨리 안정)
        let decay = exp(-zeta * omega * t)
        // 1 을 중심으로 진동하다가 decay 로 잦아들어 1 로 수렴.
        let value = 1 - decay * cos(omega * t)
        return max(0, value)
    }

    // ── 중앙 트로피 그리기 ─────────────────────────────────────
    private func drawTrophy(_ context: GraphicsContext, center: CGPoint,
                            radius: CGFloat, t: Double, fade: Double) {
        let scale = springScale(t)
        if scale <= 0.001 { return }

        let baseSize = radius * 0.34          // 기본 글자 크기(화면에 비례)
        let fontSize = baseSize * CGFloat(scale)

        var c = context
        c.opacity = fade

        // 트로피 뒤에 은은한 금빛 후광(부드러운 원)을 한 겹 깔아 떠 보이게.
        let glowR = fontSize * 0.95
        let glow = Path(ellipseIn: CGRect(x: center.x - glowR, y: center.y - glowR,
                                          width: glowR * 2, height: glowR * 2))
        c.fill(glow, with: .radialGradient(
            Gradient(colors: [Color(hue: 0.13, saturation: 0.9, brightness: 1.0).opacity(0.55),
                              .clear]),
            center: center, startRadius: 0, endRadius: glowR))

        // 이모지를 중앙에 배치. Text 자체엔 그림자를 못 붙이므로(=Text.shadow 는
        // some View 를 돌려줘 컴파일 불가), 컨텍스트 필터로 그림자를 줘서
        // 밝은/어두운 배경 모두에서 잘 보이게 해요.
        let text = Text(emoji).font(.system(size: max(1, fontSize)))
        c.addFilter(.shadow(color: .black.opacity(0.45), radius: fontSize * 0.06,
                            x: 0, y: fontSize * 0.03))
        let resolved = c.resolve(text)
        c.draw(resolved, at: center, anchor: .center)
    }

    // ── 방사형 빛줄기 ──────────────────────────────────────────
    private func drawRays(_ context: GraphicsContext, center: CGPoint,
                          radius: CGFloat, t: Double, fade: Double) {
        for r in rays {
            let lt = t - r.delay
            if lt <= 0 { continue }
            // 빛줄기 수명: 0.9초 동안 퍼졌다가 사라짐.
            let life = 0.9
            if lt > life { continue }
            let prog = lt / life                       // 0 → 1

            // 줄기는 안쪽 가장자리에서 시작해 바깥으로 뻗어나가요(아래쪽으로 살짝 가속).
            let ease = 1 - (1 - prog) * (1 - prog)     // easeOut
            let inner = radius * (0.16 + 0.34 * ease)
            let outer = inner + radius * r.length * 0.30 * (0.4 + 0.6 * ease)

            // 길이/투명도는 중간에 최고였다가 끝으로 갈수록 사라져요.
            let alpha = sin(prog * .pi) * 0.9 * fade
            if alpha <= 0.01 { continue }

            let dir = CGPoint(x: cos(r.angle), y: sin(r.angle))
            let p0 = CGPoint(x: center.x + dir.x * inner, y: center.y + dir.y * inner)
            let p1 = CGPoint(x: center.x + dir.x * outer, y: center.y + dir.y * outer)

            var path = Path()
            path.move(to: p0)
            path.addLine(to: p1)

            var c = context
            c.opacity = alpha
            let color = Color(hue: r.hue, saturation: 0.85, brightness: 1.0)
            c.stroke(path, with: .color(color),
                     style: StrokeStyle(lineWidth: r.width * (1 - prog * 0.4), lineCap: .round))
        }
    }

    // ── 작은 반짝이들 ──────────────────────────────────────────
    private func drawSparks(_ context: GraphicsContext, center: CGPoint,
                            radius: CGFloat, t: Double, fade: Double) {
        let life = 1.1
        if t > life { return }                         // 반짝이는 초반에만
        let prog = t / life                            // 0 → 1
        let ease = 1 - (1 - prog) * (1 - prog)         // easeOut: 빠르게 퍼졌다가 느려짐

        for s in sparks {
            let dist = radius * s.dist * 0.55 * ease
            let x = center.x + cos(s.angle) * dist
            let y = center.y + sin(s.angle) * dist

            // 깜빡임 + 전체 수명 페이드.
            let twinkle = 0.55 + 0.45 * sin(t * 18 + s.twinkle)
            let alpha = sin(prog * .pi) * twinkle * fade
            if alpha <= 0.02 { continue }

            let sz = s.size * (1 - prog * 0.5)
            let rect = CGRect(x: x - sz / 2, y: y - sz / 2, width: sz, height: sz)

            var c = context
            c.opacity = alpha
            let color = Color(hue: s.hue, saturation: 0.9, brightness: 1.0)
            // 살짝 어둡게 테두리를 깐 뒤 채운 점 → 밝은 배경에서도 보이게.
            c.fill(Path(ellipseIn: rect.insetBy(dx: -0.6, dy: -0.6)),
                   with: .color(.black.opacity(0.25)))
            c.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }
}
