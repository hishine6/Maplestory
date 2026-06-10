import SwiftUI

// ============================================================
//  🎈 Balloons 축하 효과
//  - 화면 아래에서 색색 풍선이 위로 둥둥 떠오르며
//    사인파로 좌우로 살랑살랑 흔들려요.
//  - 풍선 한 개 = 타원(몸통) + 작은 매듭 삼각형 + 짧은 곡선 끈.
//  - 이 뷰는 NSHostingView에 '한 번만' 올라가므로(재생성 안 됨),
//    랜덤 값은 init에서 1회만 만들어 저장해 두고 매 프레임 재사용해요.
//  - 마지막 0.4초에 전체 opacity를 0으로 페이드아웃.
// ============================================================
struct BalloonsEffectView: View {
    let birth: Date
    let duration: Double

    // 풍선 한 개분의 '변하지 않는' 정보(처음에 한 번 정해두는 값들)
    private struct Balloon {
        let x: CGFloat        // 시작 가로 위치(화면 폭에 대한 0~1 비율)
        let color: Color      // 풍선 색
        let size: CGFloat     // 풍선 폭(px). 높이는 폭의 약 1.2배
        let riseDur: Double   // 화면 아래 → 위로 떠오르는 데 걸리는 시간(초)
        let delay: Double     // 시작 지연(다 같이 안 올라오게 흩뿌림)
        let swayAmp: CGFloat  // 좌우로 흔들리는 폭(px)
        let swayFreq: Double  // 흔들리는 빠르기
        let swayPhase: Double // 흔들림 시작 위상(서로 어긋나게)
        let shine: CGFloat    // 하이라이트(반짝) 위치 살짝 변주용 0~1
    }

    // init에서 1회 생성해 저장하는 풍선 배열
    private let balloons: [Balloon]

    init(birth: Date, duration: Double) {
        self.birth = birth
        self.duration = duration

        // 채도 높고 잘 보이는 풍선 팔레트(밝은/어두운 배경 둘 다 대비 OK)
        let palette: [Color] = [
            Color(red: 0.95, green: 0.26, blue: 0.31),  // 빨강
            Color(red: 0.98, green: 0.55, blue: 0.16),  // 주황
            Color(red: 0.98, green: 0.80, blue: 0.18),  // 노랑
            Color(red: 0.30, green: 0.78, blue: 0.42),  // 초록
            Color(red: 0.18, green: 0.62, blue: 0.96),  // 파랑
            Color(red: 0.55, green: 0.40, blue: 0.95),  // 보라
            Color(red: 0.96, green: 0.40, blue: 0.70),  // 분홍
            Color(red: 0.20, green: 0.78, blue: 0.78),  // 청록
        ]

        // 풍선 개수: 성능 위해 충분히 적게(~28개). 입자 수 제한(<200) 만족.
        let count = 28
        self.balloons = (0..<count).map { _ in
            Balloon(
                x: CGFloat.random(in: 0.04...0.96),
                color: palette.randomElement()!,
                size: CGFloat.random(in: 34...64),
                riseDur: Double.random(in: 3.4...5.6),
                delay: Double.random(in: 0...1.6),
                swayAmp: CGFloat.random(in: 14...42),
                swayFreq: Double.random(in: 0.7...1.6),
                swayPhase: Double.random(in: 0...(2 * .pi)),
                shine: CGFloat.random(in: 0.0...1.0)
            )
        }
    }

    var body: some View {
        // TimelineView(.animation) = 주사율에 맞춰 매 프레임 다시 그려요.
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(birth)

                // 마지막 0.4초 동안 전체를 서서히 투명하게(페이드아웃).
                let fadeStart = duration - 0.4
                let globalOpacity: Double = {
                    if t <= fadeStart { return 1 }
                    if t >= duration { return 0 }
                    return max(0, 1 - (t - fadeStart) / 0.4)
                }()
                // 다 끝났으면 그릴 필요 없음.
                if globalOpacity <= 0 { return }

                for b in balloons {
                    let lt = t - b.delay          // 이 풍선의 '개인 경과시간'
                    if lt <= 0 { continue }        // 아직 출발 전

                    let prog = lt / b.riseDur      // 0(아래) → 1(위)
                    if prog > 1.1 { continue }      // 화면 위로 다 빠져나감

                    let h = b.size * 1.2            // 풍선 몸통 높이

                    // 세로: 화면 아래(살짝 밖)에서 위(밖)로.
                    //  prog=0 → 화면 바닥 아래, prog=1 → 화면 천장 위.
                    let startY = size.height + h
                    let endY = -h * 2.2             // 끈까지 충분히 빠져나가게
                    let cy = startY + (endY - startY) * CGFloat(prog)

                    // 가로: 시작 위치 + 사인파 좌우 흔들림.
                    let sway = sin(lt * b.swayFreq + b.swayPhase) * b.swayAmp
                    let cx = b.x * size.width + sway

                    // 살짝 기울임(흔들리는 방향으로 기우뚱).
                    let tilt = cos(lt * b.swayFreq + b.swayPhase) * 0.12

                    // 조각마다 따로 변환/투명도 주려고 컨텍스트 복사본 사용.
                    var c = context
                    c.opacity = globalOpacity
                    c.translateBy(x: cx, y: cy)
                    c.rotate(by: .radians(tilt))

                    drawBalloon(in: &c, size: b.size, height: h,
                                color: b.color, shine: b.shine)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    // 풍선 한 개를 (0,0) 기준으로 그려요(몸통 중심이 원점).
    // 호출 전에 c는 이미 풍선 위치로 translate/rotate 된 상태입니다.
    private func drawBalloon(in c: inout GraphicsContext,
                             size w: CGFloat, height h: CGFloat,
                             color: Color, shine: CGFloat) {
        // 매듭 끝(풍선 바닥 중앙). 여기서 끈이 내려가요.
        let bottomY = h / 2

        // ── 끈(짧은 곡선) ─────────────────────────────────
        // 매듭에서 아래로 흐르는 부드러운 곡선.
        var string = Path()
        string.move(to: CGPoint(x: 0, y: bottomY + h * 0.10))
        string.addCurve(
            to: CGPoint(x: w * 0.10, y: bottomY + h * 0.85),
            control1: CGPoint(x: -w * 0.22, y: bottomY + h * 0.35),
            control2: CGPoint(x: w * 0.26, y: bottomY + h * 0.60)
        )
        c.stroke(string, with: .color(.black.opacity(0.45)),
                 style: StrokeStyle(lineWidth: max(1, w * 0.03),
                                    lineCap: .round))

        // ── 매듭(작은 삼각형) ─────────────────────────────
        let knotW = w * 0.16
        let knotH = h * 0.09
        var knot = Path()
        knot.move(to: CGPoint(x: -knotW / 2, y: bottomY))
        knot.addLine(to: CGPoint(x: knotW / 2, y: bottomY))
        knot.addLine(to: CGPoint(x: 0, y: bottomY + knotH))
        knot.closeSubpath()
        c.fill(knot, with: .color(color))

        // ── 몸통(타원) ────────────────────────────────────
        let body = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        let bodyPath = Path(ellipseIn: body)

        // 살짝 그림자/테두리로 투명 배경 위에서도 또렷하게.
        c.fill(bodyPath, with: .color(.black.opacity(0.18)))  // 바깥 살짝 어둡게(그림자 느낌)
        c.fill(Path(ellipseIn: body.insetBy(dx: w * 0.015, dy: h * 0.015)),
               with: .color(color))
        c.stroke(bodyPath, with: .color(.black.opacity(0.22)),
                 lineWidth: max(0.8, w * 0.02))

        // ── 하이라이트(반짝) ──────────────────────────────
        // 좌상단에 흰색 타원으로 광택 한 점.
        let hx = -w * 0.18 + (shine - 0.5) * w * 0.06
        let hy = -h * 0.22
        let hw = w * 0.26
        let hh = h * 0.18
        let highlight = CGRect(x: hx - hw / 2, y: hy - hh / 2, width: hw, height: hh)
        c.fill(Path(ellipseIn: highlight), with: .color(.white.opacity(0.55)))
    }
}