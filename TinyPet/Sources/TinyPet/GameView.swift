import SwiftUI

// 캐릭터를 "키우는" 메인 화면.
struct GameView: View {
    // 부모가 만든 캐릭터를 받아요.
    // @Observable 덕분에 pet의 값이 바뀌면 이 화면이 자동으로 갱신돼요.
    let pet: Pet

    // 2초마다 신호를 보내는 타이머 (시간 흐름 = 능력치 감소용)
    private let ticker = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    // 버튼 누를 때 캐릭터가 살짝 통통 튀는 효과용
    @State private var bounce = false

    var body: some View {
        VStack(spacing: 14) {

            // ── 이름 + 레벨 ──
            HStack {
                Text(pet.name).font(.title2.bold())
                Spacer()
                Text("Lv. \(pet.level)")
                    .font(.headline)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.2))
                    .clipShape(Capsule())
            }

            // ── 캐릭터 ──
            Text(pet.emoji)
                .font(.system(size: 110))
                .scaleEffect(bounce ? 1.12 : 1.0)
                .animation(.spring(duration: 0.3), value: bounce)
                .padding(.vertical, 4)

            // ── 기분 + 말풍선 ──
            Text(pet.mood).font(.headline)
            Text(pet.lastMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(height: 18)

            // ── 능력치 막대들 ──
            StatBar(icon: "⭐️", label: "경험치", value: Double(pet.xp), maxValue: Double(pet.xpToNext), color: .yellow)
            StatBar(icon: "🍚", label: "포만감", value: pet.fullness,  maxValue: 100, color: .orange)
            StatBar(icon: "💖", label: "행복",   value: pet.happiness, maxValue: 100, color: .pink)
            StatBar(icon: "⚡️", label: "에너지", value: pet.energy,    maxValue: 100, color: .green)

            // ── 행동 버튼 (2 x 2) ──
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    actionButton("🍔 밥주기")  { pet.feed() }
                    actionButton("🎾 놀아주기") { pet.play() }
                }
                GridRow {
                    actionButton("😴 재우기")  { pet.sleep() }
                    actionButton("💪 훈련하기") { pet.train() }
                }
            }
            .padding(.top, 4)
        }
        .padding(24)
        // 타이머 신호가 올 때마다 시간이 흐른 것으로 처리
        .onReceive(ticker) { _ in
            pet.tick()
        }
    }

    // 행동 버튼 하나를 만드는 도우미 (누르면 통통 효과 + 행동 실행)
    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            bounce = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { bounce = false }
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
    }
}

// 능력치 막대 하나 = 재사용 가능한 작은 화면 조각.
// (포만감·행복·에너지·경험치 4곳에서 똑같이 재사용해요!)
struct StatBar: View {
    let icon: String
    let label: String
    let value: Double
    let maxValue: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(icon)
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value)) / \(Int(maxValue))")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            // 막대: 회색 바탕 위에 색깔 막대를 비율만큼 덮어요.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.2))
                    Capsule().fill(color)
                        .frame(width: geo.size.width * min(1, max(0, value / maxValue)))
                }
            }
            .frame(height: 10)
        }
    }
}
