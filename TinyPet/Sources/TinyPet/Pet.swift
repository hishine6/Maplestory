import Foundation
import Observation

// ───────────────────────────────────────────────────────────
// 캐릭터 "종류". 알/씨앗에서 시작해 레벨이 오르면 진화해요.
// ───────────────────────────────────────────────────────────
enum PetType: String, CaseIterable, Identifiable {
    case chick, dragon, cat, sprout
    var id: String { rawValue }

    // 선택 화면에 보일 한글 이름
    var displayName: String {
        switch self {
        case .chick:  return "병아리"
        case .dragon: return "드래곤"
        case .cat:    return "고양이"
        case .sprout: return "새싹"
        }
    }

    // 레벨에 따라 달라지는 진화 이모지 (1~2: 아기 / 3~4: 청소년 / 5+: 어른)
    func emoji(forLevel level: Int) -> String {
        switch self {
        case .chick:  return level < 3 ? "🥚" : (level < 5 ? "🐣" : "🐔")
        case .dragon: return level < 3 ? "🥚" : (level < 5 ? "🐲" : "🐉")
        case .cat:    return level < 3 ? "🐱" : (level < 5 ? "😺" : "🦁")
        case .sprout: return level < 3 ? "🌱" : (level < 5 ? "🌿" : "🌳")
        }
    }

    // 선택 화면 미리보기용 (레벨 4 모습)
    var previewEmoji: String { emoji(forLevel: 4) }
}

// ───────────────────────────────────────────────────────────
// 캐릭터의 "데이터 모델".
// @Observable = 이 안의 값이 바뀌면 화면이 자동으로 다시 그려져요.
// (FocusTimer의 @State 변수 하나를, 여러 값 묶음으로 키운 버전이에요.)
// @MainActor = 항상 화면(메인) 쪽에서만 다뤄서 안전하게.
// ───────────────────────────────────────────────────────────
@MainActor
@Observable
class Pet {
    var name: String
    var type: PetType

    var level = 1
    var xp = 0

    // 모든 능력치는 0~100
    var fullness = 80.0     // 포만감 (배고픔의 반대)
    var happiness = 80.0    // 행복
    var energy = 80.0       // 에너지

    var lastMessage = "안녕하세요! 잘 부탁해요 😊"

    init(name: String, type: PetType) {
        self.name = name
        self.type = type
    }

    // 다음 레벨까지 필요한 경험치 (레벨이 오를수록 많이 필요)
    var xpToNext: Int { level * 20 }

    // 지금 보여줄 캐릭터 이모지
    var emoji: String { type.emoji(forLevel: level) }

    // 현재 기분 (가장 부족한 능력치가 기분을 결정해요)
    var mood: String {
        if energy < 20 { return "너무 졸려요... 😴" }
        if fullness < 20 { return "배고파요! 🍽️" }
        if happiness < 20 { return "심심하고 우울해요... 😢" }
        if fullness > 70 && happiness > 70 && energy > 50 { return "정말 행복해요! 🥰" }
        return "그럭저럭 지내요 🙂"
    }

    // ── 행동들 (버튼이 호출) ─────────────────────────────
    func feed() {
        fullness += 25
        gainXP(2)
        lastMessage = "냠냠! 잘 먹었어요 🍚"
        clamp()
    }

    func play() {
        guard energy > 10 else { lastMessage = "너무 피곤해서 못 놀겠어요 😵"; return }
        happiness += 20
        energy -= 12
        fullness -= 6
        gainXP(5)
        lastMessage = "신난다! 또 놀아요 🎾"
        clamp()
    }

    func sleep() {
        energy += 35
        fullness -= 5
        lastMessage = "쿨쿨... 잘 잤어요 💤"
        clamp()
    }

    func train() {
        guard energy > 15 && fullness > 15 else { lastMessage = "기운이 없어서 훈련은 무리예요 💦"; return }
        energy -= 18
        fullness -= 12
        happiness -= 5
        gainXP(12)
        lastMessage = "열심히 훈련했어요! 💪"
        clamp()
    }

    // 시간이 흐르면 능력치가 조금씩 줄어요 (타이머가 호출)
    func tick() {
        fullness -= 2
        happiness -= 1.5
        energy -= 1
        clamp()
    }

    // 경험치 획득 + 레벨업 처리
    private func gainXP(_ amount: Int) {
        xp += amount
        while xp >= xpToNext {
            xp -= xpToNext
            level += 1
            lastMessage = "🎉 레벨 \(level) 달성! 쑥쑥 자라요!"
        }
    }

    // 능력치를 항상 0~100 사이로 가둬요
    private func clamp() {
        fullness  = min(100, max(0, fullness))
        happiness = min(100, max(0, happiness))
        energy    = min(100, max(0, energy))
    }
}
