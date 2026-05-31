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

// ── 영역(맵) ───────────────────────────────────────────────
enum Area: String, Codable, CaseIterable {
    case town, field
    var title: String { self == .town ? "마을" : "사냥터" }
}

// ── 조작 액션 (키 리바인드 대상) ───────────────────────────
enum GameAction: String, Codable, CaseIterable {
    case left, right, jump, attack
    case skill1, skill2
    case inventory, stats, worldmap, interact, openKeybinds
    var title: String {
        switch self {
        case .left: return "왼쪽";   case .right: return "오른쪽"
        case .jump: return "점프";   case .attack: return "공격"
        case .skill1: return "스킬 1"; case .skill2: return "스킬 2"
        case .inventory: return "장비창"; case .stats: return "능력치창"
        case .worldmap: return "월드맵"; case .interact: return "상호작용/포털"
        case .openKeybinds: return "키 설정"
        }
    }
}

// ── 레벨별 필요 경험치 (메이플스토리 곡선 참고, index=레벨) ──
enum LevelTable {
    static let maxLevel = 200
    // tnl[L] = 레벨 L → L+1 에 필요한 경험치. [0]은 미사용.
    static let tnl: [Int] = [
        0,
        15, 34, 57, 92, 135, 372, 560, 840, 1242, 1242,
        1242, 1242, 1242, 1242, 1490, 1788, 2145, 2574, 3088, 3705,
        4446, 5335, 6402, 7682, 9218, 11061, 13273, 15927, 19112, 19112,
        19112, 19112, 19112, 19112, 22934, 27520, 33024, 39628, 47553, 51357,
        55465, 59902, 64694, 69869, 75458, 81494, 88013, 95054, 102658, 110870,
        119739, 129318, 139663, 150836, 162902, 175934, 190008, 205208, 221624, 221624,
        221624, 221624, 221624, 221624, 238245, 256113, 275321, 295970, 318167, 342029,
        367681, 395257, 424901, 456768, 488741, 522952, 559558, 598727, 640637, 685481,
        733464, 784806, 839742, 898523, 961419, 1028718, 1100728, 1177778, 1260222, 1342136,
        1429374, 1522283, 1621231, 1726611, 1838840, 1958364, 2085657, 2221224, 2365603, 2365603,
        2365603, 2365603, 2365603, 2365603, 2519367, 2683125, 2857528, 3043267, 3241079, 3451749,
        3676112, 3915059, 4169537, 4440556, 4729192, 5036589, 5363967, 5712624, 6083944, 6479400,
        6900561, 7349097, 7826788, 8335529, 8877338, 9454364, 10068897, 10723375, 11420394, 12162719,
        12953295, 13795259, 14691950, 15646926, 16663976, 17747134, 18900697, 20129242, 21437642, 22777494,
        24201087, 25713654, 27320757, 29028304, 30842573, 32770233, 34818372, 36994520, 39306677, 41763344,
        44373553, 47146900, 50093581, 53224429, 56550955, 60085389, 63840725, 67830770, 72070193, 76574580,
        81360491, 86445521, 91848366, 97588888, 103688193, 110168705, 117054249, 124370139, 132143272, 138750435,
        145687956, 152972353, 160620970, 168652018, 177084618, 185938848, 195235790, 204997579, 215247457, 226009829,
        237310320, 249175836, 261634627, 274716358, 288452175, 302874783, 318018522, 333919448, 350615420, 368146191,
        386553500, 405881175, 426175233, 447483994, 469858193, 493351102, 518018657, 543919589, 571115568, 2207026470
    ]
    static func toNext(_ level: Int) -> Int {
        if level < 1 { return tnl[1] }
        if level >= maxLevel { return Int.max }   // 200 = 만렙
        return tnl[level]
    }
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
    // ── NEW (모두 옵셔널) ──
    var binds: [String: Int]?     // GameAction.rawValue → keyCode
    var area: String?             // 마지막 영역 (Area.rawValue)
    var charID: String?           // 캐릭터 이름/ID
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
