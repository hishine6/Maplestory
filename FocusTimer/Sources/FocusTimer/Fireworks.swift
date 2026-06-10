import SwiftUI

// ============================================================
//  🎆 불꽃놀이(Fireworks) 축하 효과
//  - 화면 아래에서 로켓 여러 발이 시차를 두고 솟아올라요.
//  - 각 로켓은 정점(목표 높이)에서 방사형으로 폭발해요.
//  - 폭발한 불꽃 입자들은 중력을 받아 흩어지며 떨어지고 페이드돼요.
//  - duration 동안 색색의 폭발이 연달아 터지도록 발사 시각을 분산했어요.
//
//  주의: 이 뷰는 NSHostingView 에 한 번만 올라가 재생성되지 않으므로,
//        모든 난수는 init 에서 1회만 만들어 저장 프로퍼티에 보관해요.
//        (그래야 매 프레임 모양이 흔들리지 않아요.)
// ============================================================

// ── 로켓 한 발(=폭발 한 번)의 정보 ───────────────────────────
private struct Rocket {
    let launchT: Double      // 발사 시각(초, birth 기준)
    let riseDur: Double      // 솟아오르는 데 걸리는 시간(초)
    let startX: CGFloat      // 발사 가로 위치(0~1 비율)
    let apexX: CGFloat       // 정점 가로 위치(0~1 비율) — 살짝 휘며 올라가요
    let apexY: CGFloat       // 정점 세로 위치(0~1 비율, 위쪽일수록 작음)
    let color: Color         // 이 폭발의 기본 색
    let secondColor: Color   // 일부 입자에 섞을 보조 색
    let sparks: [Spark]      // 폭발 시 사방으로 퍼지는 불꽃 입자들
    let burstDur: Double     // 폭발 입자가 살아있는 시간(초)
}

// ── 폭발 불꽃 입자 하나 ──────────────────────────────────────
private struct Spark {
    let angle: Double        // 퍼져나가는 방향(라디안)
    let speed: CGFloat       // 초기 속도(px/초 스케일)
    let size: CGFloat        // 점 크기
    let useSecond: Bool      // 보조 색을 쓸지
    let flicker: Double      // 반짝임 위상(랜덤)
}

// ── 색/난수 생성을 담당하는 팩토리 ──────────────────────────
private enum FireworksFactory {
    static let palette: [Color] = [
        .red, .orange, .yellow, .green, .mint, .cyan, .blue, .purple, .pink,
        Color(red: 1.0, green: 0.85, blue: 0.30),   // 금빛
        Color(red: 0.40, green: 0.95, blue: 0.80),  // 청록
        Color(red: 0.95, green: 0.45, blue: 0.85),  // 자홍
    ]

    // duration 동안 연달아 터질 로켓들을 만들어요.
    static func makeRockets(duration: Double) -> [Rocket] {
        // duration 길이에 맞춰 발사 횟수를 정해요(너무 많지 않게).
        let count = max(5, min(12, Int(duration / 0.42)))
        var rockets: [Rocket] = []
        rockets.reserveCapacity(count)

        // 발사 구간: 마지막 폭발도 '끝-0.4초 페이드' 전에 충분히 터지도록
        // 상승시간(~1.15s)+폭발 일부(~0.8s)+페이드(0.4s) 만큼 앞쪽으로 당겨 분산해요.
        let span = max(0.1, duration - 2.35)

        for i in 0..<count {
            // 발사 시각을 0 ~ span 구간에 고르게 흩뿌리고 약간의 흔들림을 줘요.
            let base = Double(i) / Double(count) * span
            let jitter = Double.random(in: -0.12...0.12)
            let launchT = max(0, base + jitter)

            let color = palette.randomElement()!
            var second = palette.randomElement()!
            if second == color { second = palette.randomElement()! }

            // 폭발 입자 수(성능 위해 발당 22~34개 → 전체 ~200 이하 유지).
            let n = Int.random(in: 22...34)
            var sparks: [Spark] = []
            sparks.reserveCapacity(n)
            for _ in 0..<n {
                sparks.append(
                    Spark(
                        angle: Double.random(in: 0..<(2 * .pi)),
                        speed: CGFloat.random(in: 90...210),
                        size: CGFloat.random(in: 2.0...4.2),
                        useSecond: Double.random(in: 0...1) < 0.35,
                        flicker: Double.random(in: 0..<(2 * .pi))
                    )
                )
            }

            rockets.append(
                Rocket(
                    launchT: launchT,
                    riseDur: Double.random(in: 0.8...1.15),
                    startX: CGFloat.random(in: 0.15...0.85),
                    apexX: CGFloat.random(in: 0.15...0.85),
                    apexY: CGFloat.random(in: 0.16...0.42),  // 화면 위쪽 16~42% 지점에서 터짐
                    color: color,
                    secondColor: second,
                    sparks: sparks,
                    burstDur: Double.random(in: 1.1...1.6)
                )
            )
        }
        return rockets
    }
}

// ── 본체: 공통 인터페이스 시그니처를 지키는 효과 뷰 ─────────────
struct FireworksEffectView: View {
    let birth: Date
    let duration: Double
    private let rockets: [Rocket]

    init(birth: Date, duration: Double) {
        self.birth = birth
        self.duration = duration
        // 난수는 여기서 1회 생성 (이 뷰는 재생성되지 않음).
        self.rockets = FireworksFactory.makeRockets(duration: duration)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(birth)

                // 마지막 0.4초 동안 전체를 서서히 사라지게 해요.
                let fade = t > duration - 0.4
                    ? max(0, (duration - t) / 0.4)
                    : 1.0
                if fade <= 0 { return }   // 다 끝났으면 그릴 것 없음

                // 위로 갈수록 작아지는 '중력 가속도'(px/초^2 스케일).
                let gravity: CGFloat = 220

                for r in rockets {
                    let lt = t - r.launchT          // 이 로켓의 경과시간
                    if lt <= 0 { continue }         // 아직 발사 전

                    let apexPx = CGPoint(x: r.apexX * size.width, y: r.apexY * size.height)

                    if lt < r.riseDur {
                        // ── 1단계: 로켓이 솟아오르는 중 ──
                        drawRising(context, size: size, rocket: r, lt: lt,
                                   apexPx: apexPx, globalFade: fade)
                    } else {
                        // ── 2단계: 정점에서 폭발 후 흩어짐 ──
                        let bt = lt - r.riseDur     // 폭발 후 경과시간
                        if bt > r.burstDur + 0.2 { continue }   // 다 사라졌으면 건너뜀
                        drawBurst(context, rocket: r, bt: bt,
                                  apexPx: apexPx, gravity: gravity, globalFade: fade)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    // 로켓이 발사 위치에서 정점으로 휘어 올라가는 동안의 그림(꼬리 포함).
    private func drawRising(_ context: GraphicsContext, size: CGSize,
                            rocket r: Rocket, lt: Double,
                            apexPx: CGPoint, globalFade: Double) {
        let prog = CGFloat(lt / r.riseDur)         // 0(발사) → 1(정점)
        // 시작점에서 정점까지 직선 보간하되, y 는 ease-out(빨랐다 느려짐)으로 자연스럽게.
        let startPx = CGPoint(x: r.startX * size.width, y: size.height + 10)
        let eased = 1 - (1 - prog) * (1 - prog)    // ease-out
        let cx = startPx.x + (apexPx.x - startPx.x) * prog
        let cy = startPx.y + (apexPx.y - startPx.y) * eased

        var c = context
        c.opacity = globalFade

        // 짧은 불꼬리: 머리 뒤로 몇 점을 흐릿하게 남겨요.
        let tailN = 6
        for k in 0..<tailN {
            let back = CGFloat(k) * 5
            let ty = cy + back
            let fadeK = (1 - CGFloat(k) / CGFloat(tailN))
            let dot = CGRect(x: cx - 1.4, y: ty - 1.4, width: 2.8, height: 2.8)
            c.fill(Path(ellipseIn: dot), with: .color(r.color.opacity(0.5 * Double(fadeK))))
        }
        // 머리: 살짝 밝게, 테두리 느낌의 발광.
        let head = CGRect(x: cx - 2.4, y: cy - 2.4, width: 4.8, height: 4.8)
        c.addFilter(.shadow(color: r.color.opacity(0.9), radius: 6))
        c.fill(Path(ellipseIn: head), with: .color(.white.opacity(0.95)))
    }

    // 정점에서 방사형으로 터진 입자들이 중력 받아 흩어지며 페이드.
    private func drawBurst(_ context: GraphicsContext, rocket r: Rocket, bt: Double,
                           apexPx: CGPoint, gravity: CGFloat, globalFade: Double) {
        let life = CGFloat(min(bt / r.burstDur, 1))     // 0 → 1
        // 입자 수명에 따른 자체 페이드(끝에서 빠르게 사라지게 제곱 적용).
        let lifeFade = Double(max(0, 1 - life * life))
        let opacity = lifeFade * globalFade
        if opacity <= 0.01 { return }

        // 폭발 직후 0.12초는 가운데 흰 섬광(플래시)을 보여줘요.
        if bt < 0.14 {
            var f = context
            let fl = max(0, 1 - bt / 0.14)
            f.opacity = fl * globalFade
            let rad = 10 + CGFloat(bt) * 120
            let flash = CGRect(x: apexPx.x - rad, y: apexPx.y - rad,
                               width: rad * 2, height: rad * 2)
            f.addFilter(.shadow(color: r.color.opacity(0.9), radius: 14))
            f.fill(Path(ellipseIn: flash), with: .color(.white.opacity(0.85)))
        }

        var c = context
        c.opacity = opacity
        // 발광 느낌을 주는 그림자(투명 배경에서 밝게 보이도록).
        c.addFilter(.shadow(color: r.color.opacity(0.7), radius: 4))

        let bts = CGFloat(bt)
        for s in r.sparks {
            // 등속 퍼짐 + 약간의 감속(공기저항 느낌) + 중력 낙하.
            let drag = 1 - 0.35 * life               // 시간이 지날수록 퍼지는 속도 둔화
            let dist = s.speed * bts * drag
            let px = apexPx.x + cos(CGFloat(s.angle)) * dist
            let py = apexPx.y + sin(CGFloat(s.angle)) * dist + 0.5 * gravity * bts * bts

            // 반짝임: 사인파로 크기를 미세하게 흔들어 살아있는 느낌.
            let twk = 0.8 + 0.2 * sin(bt * 14 + s.flicker)
            let sz = s.size * CGFloat(twk) * (1 - 0.3 * life)
            let col = s.useSecond ? r.secondColor : r.color

            let dot = CGRect(x: px - sz / 2, y: py - sz / 2, width: sz, height: sz)
            c.fill(Path(ellipseIn: dot), with: .color(col))
        }
    }
}
