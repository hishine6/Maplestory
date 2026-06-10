import SwiftUI

// ============================================================
//  EdgeGlow — 화면 가장자리에서 안쪽으로 번지는 부드러운 글로우(비네트) 효과.
//  핵심 아이디어:
//   - 테두리(상/하/좌/우)에서 안쪽으로 색이 스며들도록 '바깥은 진하고 안쪽은 투명'한
//     선형 그라데이션을 네 변에 깔아요. (비네트처럼 화면을 액자로 감싸는 느낌)
//   - 네 모서리에는 방사형 그라데이션을 살짝 얹어 코너가 어색하게 끊기지 않게 해요.
//   - 전체 밝기를 사인파로 1~2회 은은하게 '맥동(pulse)'시켜 우아하게 숨 쉬듯 보여요.
//   - 마지막 0.4초엔 전체 opacity 를 0 으로 페이드아웃.
//  (NSWindow/표시/제거는 오버레이 컨트롤러 담당. 여기선 SwiftUI View 한 개만.)
// ============================================================
struct EdgeGlowEffectView: View {
    let birth: Date
    let duration: Double
    let color: Color

    // 맥동 횟수: duration 동안 글로우가 몇 번 차오를지. (1~2회 사이로 은은하게)
    // init 에서 1회만 난수로 정해 둬요. 이 뷰는 재생성되지 않아 안정적이에요.
    private let pulses: Double
    // 가장자리에서 안쪽으로 글로우가 파고드는 깊이(화면 짧은 변 대비 비율).
    private let inset: CGFloat

    init(birth: Date,
         duration: Double,
         color: Color = Color(red: 0.95, green: 0.72, blue: 0.20)) {
        self.birth = birth
        self.duration = duration
        self.color = color
        // 1.0 또는 2.0 회 — 가끔은 한 번, 가끔은 두 번 맥동하도록 살짝 변주.
        self.pulses = Bool.random() ? 2.0 : 1.0
        self.inset = CGFloat.random(in: 0.16...0.22)
    }

    var body: some View {
        // TimelineView(.animation) = 화면 주사율에 맞춰 매 프레임 다시 그려요.
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(birth)

                // ── 전체 페이드(등장 + 퇴장) ──────────────────────────
                // 처음 0.5초: 0 → 1 로 부드럽게 등장(살짝 스며들 듯).
                let fadeIn = min(1.0, t / 0.5)
                // 마지막 0.4초: 1 → 0 으로 사라짐.
                let fadeOut = max(0.0, min(1.0, (duration - t) / 0.4))
                let envelope = max(0.0, fadeIn * fadeOut)
                if envelope <= 0.001 { return }  // 끝났으면 거의 안 그려요.

                // ── 맥동(pulse) ─────────────────────────────────────
                // 0 → 1 → 0 모양의 부드러운 사인 곡선을 pulses 번 반복.
                // (1 - cos) / 2 는 0에서 시작해 0으로 끝나는 자연스러운 봉우리예요.
                let phase = (t / max(duration, 0.001)) * pulses * 2.0 * .pi
                let pulse = (1.0 - cos(phase)) / 2.0
                // 완전히 0이 되면 깜빡 꺼지므로 바닥(0.35)을 깔아 은은하게 유지.
                let intensity = (0.35 + 0.65 * pulse) * envelope

                // 글로우가 파고드는 픽셀 깊이(짧은 변 기준).
                let depth = min(size.width, size.height) * inset

                // 색을 단계별로 옅게 — 바깥(진함) → 안쪽(투명).
                let strong = color.opacity(0.85 * intensity)
                let mid = color.opacity(0.35 * intensity)
                let clear = color.opacity(0.0)

                // ── 네 변(상/하/좌/우) 선형 글로우 ────────────────────
                // 위 가장자리: 위(진함) → 아래(투명)
                context.fill(
                    Path(CGRect(x: 0, y: 0, width: size.width, height: depth)),
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: strong, location: 0.0),
                            .init(color: mid, location: 0.45),
                            .init(color: clear, location: 1.0),
                        ]),
                        startPoint: CGPoint(x: size.width / 2, y: 0),
                        endPoint: CGPoint(x: size.width / 2, y: depth)
                    )
                )
                // 아래 가장자리: 아래(진함) → 위(투명)
                context.fill(
                    Path(CGRect(x: 0, y: size.height - depth, width: size.width, height: depth)),
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: clear, location: 0.0),
                            .init(color: mid, location: 0.55),
                            .init(color: strong, location: 1.0),
                        ]),
                        startPoint: CGPoint(x: size.width / 2, y: size.height - depth),
                        endPoint: CGPoint(x: size.width / 2, y: size.height)
                    )
                )
                // 왼쪽 가장자리: 왼쪽(진함) → 오른쪽(투명)
                context.fill(
                    Path(CGRect(x: 0, y: 0, width: depth, height: size.height)),
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: strong, location: 0.0),
                            .init(color: mid, location: 0.45),
                            .init(color: clear, location: 1.0),
                        ]),
                        startPoint: CGPoint(x: 0, y: size.height / 2),
                        endPoint: CGPoint(x: depth, y: size.height / 2)
                    )
                )
                // 오른쪽 가장자리: 오른쪽(진함) → 왼쪽(투명)
                context.fill(
                    Path(CGRect(x: size.width - depth, y: 0, width: depth, height: size.height)),
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: clear, location: 0.0),
                            .init(color: mid, location: 0.55),
                            .init(color: strong, location: 1.0),
                        ]),
                        startPoint: CGPoint(x: size.width - depth, y: size.height / 2),
                        endPoint: CGPoint(x: size.width, y: size.height / 2)
                    )
                )

                // ── 네 모서리 방사형 보강 ────────────────────────────
                // 변끼리 만나는 코너는 살짝 덜 채워지므로, 모서리에서 퍼지는
                // 방사형 글로우를 얹어 액자처럼 둥글게 이어 줘요.
                let cornerR = depth * 1.25
                let cornerStrong = color.opacity(0.55 * intensity)
                let corners: [CGPoint] = [
                    CGPoint(x: 0, y: 0),
                    CGPoint(x: size.width, y: 0),
                    CGPoint(x: 0, y: size.height),
                    CGPoint(x: size.width, y: size.height),
                ]
                for ctr in corners {
                    context.fill(
                        Path(CGRect(x: ctr.x - cornerR, y: ctr.y - cornerR,
                                    width: cornerR * 2, height: cornerR * 2)),
                        with: .radialGradient(
                            Gradient(stops: [
                                .init(color: cornerStrong, location: 0.0),
                                .init(color: color.opacity(0.18 * intensity), location: 0.5),
                                .init(color: clear, location: 1.0),
                            ]),
                            center: ctr,
                            startRadius: 0,
                            endRadius: cornerR
                        )
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}