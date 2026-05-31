import Foundation
import CoreGraphics

// ───────────────────────────────────────────────────────────
// JSON 파일을 찾아서 불러오는 재사용 도구.
// (.app 안 / swift run 시 리소스 번들 / 둘 다 대응)
// ───────────────────────────────────────────────────────────
enum GameJSON {
    static func load<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        for url in resourceURLs(name) {
            if let data = try? Data(contentsOf: url),
               let value = try? JSONDecoder().decode(T.self, from: data) {
                return value
            }
        }
        return nil
    }

    private static func resourceURLs(_ name: String) -> [URL] {
        var urls: [URL] = []
        if let u = Bundle.main.url(forResource: name, withExtension: "json") {
            urls.append(u)
        }
        let bundleName = "JumpQuest_JumpQuest.bundle"
        let bases = [Bundle.main.resourceURL, Bundle.main.bundleURL,
                     Bundle(for: Token.self).resourceURL, Bundle(for: Token.self).bundleURL]
        for base in bases {
            if let u = base?.appendingPathComponent(bundleName),
               let b = Bundle(url: u),
               let j = b.url(forResource: name, withExtension: "json") {
                urls.append(j)
            }
        }
        return urls
    }
    private final class Token {}
}

// ── 몬스터 종류 (monsters.json) ────────────────────────────
struct MonsterType: Codable {
    let emoji: String
    let maxHP: Int
    let speed: CGFloat
    let xpReward: Int
    let touchDamage: Int
    let dropID: String?        // 떨어뜨릴 아이템 id (없으면 드롭 없음)
    let dropChance: CGFloat?   // 0.0~1.0
    let goldReward: Int?       // 처치 시 골드 (없으면 xpReward*2)
    var dropProbability: CGFloat { dropChance ?? 0 }
    var gold: Int { goldReward ?? max(1, xpReward * 2) }
}

enum MonsterCatalog {
    static let all: [MonsterType] = GameJSON.load("monsters", as: [MonsterType].self) ?? fallback
    static let fallback = [MonsterType(emoji: "🍄", maxHP: 1, speed: 55, xpReward: 1,
                                       touchDamage: 8, dropID: nil, dropChance: nil, goldReward: nil)]
}

// ── 장비/아이템 (items.json) ───────────────────────────────
enum EquipSlot: String, Codable, CaseIterable {
    case weapon, hat, top
    var label: String {
        switch self {
        case .weapon: return "무기"
        case .hat:    return "모자"
        case .top:    return "상의"
        }
    }
}

enum Rarity: String, Codable {
    case common, rare, epic, legendary
}

struct ItemType: Codable {
    let id: String          // 고유 키 ("wood_sword") — 인벤토리/세이브/드롭에 사용
    let name: String
    let emoji: String
    let slot: EquipSlot
    let rarity: Rarity
    let attack: Int         // 공격력 보너스 (주는 피해 +)
    let defense: Int        // 방어력 보너스 (받는 피해 -)
    let hpBonus: Int        // 최대 HP 보너스
    let price: Int          // 상점 구매가 (gold) — items.json 모든 행에 존재
}

enum ItemCatalog {
    static let all: [ItemType] = GameJSON.load("items", as: [ItemType].self) ?? fallback
    static let fallback: [ItemType] = [
        ItemType(id: "wood_sword", name: "나무 검", emoji: "🗡️",
                 slot: .weapon, rarity: .common, attack: 1, defense: 0, hpBonus: 0, price: 30)
    ]
    static let byID: [String: ItemType] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    static func item(_ id: String) -> ItemType? { byID[id] }
}

// ── 스킬 종류 (skills.json) ────────────────────────────────
enum SkillShape: String, Codable {
    case beam     // 길고 얇은 수평 빔: 긴 사거리, 앞 일직선의 모든 적
    case strike   // 단일 타격: 짧은 사거리, 바로 앞 가장 가까운 1마리만
    case area     // (기존) 앞쪽 범위 — 기본값/하위호환
}

struct SkillType: Codable {
    let key: String         // 발동 키 ("S", "D" …)
    let name: String        // 스킬 이름
    let emoji: String       // 이펙트 이모지
    let damage: CGFloat     // 스킬 배율 (3.0 = 기본공격의 300%)
    let range: CGFloat      // 앞쪽 적중 범위
    let cooldown: CGFloat   // 재사용 대기시간(초)
    let mpCost: Int         // 소모 MP
    let shapeRaw: String?   // "beam" | "strike" | "area" (누락 시 area)
    let height: CGFloat?    // 적중 세로 반경 (누락 시 모양별 기본값)

    enum CodingKeys: String, CodingKey {
        case key, name, emoji, damage, range, cooldown, mpCost
        case shapeRaw = "shape", height
    }
    var shape: SkillShape { SkillShape(rawValue: shapeRaw ?? "area") ?? .area }
    var hitHalfHeight: CGFloat {
        if let h = height { return h }
        switch shape { case .beam: return 24; case .strike: return 70; case .area: return 90 }
    }
    var skillPercent: Double { Double(damage) }
}

enum SkillCatalog {
    static let all: [SkillType] = GameJSON.load("skills", as: [SkillType].self) ?? []
}

// ── 세이브 데이터 (내 진행 상황) ───────────────────────────
struct SaveData: Codable {
    var level: Int
    var xp: Int
    var kills: Int
    var inventory: [String]?          // 보유 아이템 id (구버전 호환 위해 옵셔널)
    var equipped: [String: String]?   // 슬롯 rawValue → 아이템 id
    // ── 능력치 분배 (구버전 호환: 모두 옵셔널) ──
    var statATK: Int?
    var statDEF: Int?
    var statHP: Int?
    var unspentAP: Int?
    var gold: Int?            // 구버전 호환: 옵셔널 → 없으면 0
}

enum SaveStore {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JumpQuest", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("save.json")
    }
    static func load() -> SaveData? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SaveData.self, from: data)
    }
    static func save(_ s: SaveData) {
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: fileURL) }
    }
}
