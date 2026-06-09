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

    /// JSON 외 리소스(예: png) 한 개의 URL을 찾아줘요. (swift run / .app 둘 다 대응)
    static func url(_ name: String, ext: String) -> URL? {
        if let u = Bundle.main.url(forResource: name, withExtension: ext) { return u }
        let bundleName = "JumpQuest_JumpQuest.bundle"
        let bases = [Bundle.main.resourceURL, Bundle.main.bundleURL,
                     Bundle(for: Token.self).resourceURL, Bundle(for: Token.self).bundleURL]
        for base in bases {
            if let u = base?.appendingPathComponent(bundleName),
               let b = Bundle(url: u),
               let j = b.url(forResource: name, withExtension: ext) {
                return j
            }
        }
        return nil
    }
    private final class Token {}
}

// ── 몬스터 종류 (monsters.json) ────────────────────────────
struct DropEntry: Codable { let id: String; let chance: CGFloat }   // 드롭 테이블 한 줄

struct MonsterType: Codable {
    let emoji: String
    let maxHP: Int
    let speed: CGFloat
    let xpReward: Int
    let touchDamage: Int
    let dropID: String?        // (구) 단일 드롭 — drops 없을 때만 사용
    let dropChance: CGFloat?   // 0.0~1.0
    let goldReward: Int?       // 처치 시 골드 (없으면 xpReward*2)
    let drops: [DropEntry]?    // 드롭 테이블(여러 종류). 있으면 우선.
    let sprite: String?        // 스프라이트 세트 이름(예: "snail") — 있으면 이모지 대신 애니 스프라이트
    let tier: Int?             // 0=사냥터(저렙) 1=위험한 숲(고렙). 없으면 0
    let level: Int?            // 표시용 몬스터 레벨
    let name: String?          // 표시용 몬스터 이름(한글)
    var spawnTier: Int { tier ?? 0 }
    var dropProbability: CGFloat { dropChance ?? 0 }
    var gold: Int { goldReward ?? max(1, xpReward * 2) }
    // 처치 시 굴릴 드롭 목록 (각 항목 독립 확률)
    var dropTable: [DropEntry] {
        if let d = drops, !d.isEmpty { return d }
        if let id = dropID { return [DropEntry(id: id, chance: dropProbability)] }
        return []
    }
}

enum MonsterCatalog {
    static let all: [MonsterType] = GameJSON.load("monsters", as: [MonsterType].self) ?? fallback
    static let fallback = [MonsterType(emoji: "🍄", maxHP: 1, speed: 55, xpReward: 1,
                                       touchDamage: 8, dropID: nil, dropChance: nil, goldReward: nil,
                                       drops: nil, sprite: nil, tier: nil, level: nil, name: nil)]
}

// ── 장비/아이템 (items.json) ───────────────────────────────
enum EquipSlot: String, Codable, CaseIterable {
    case weapon, hat, top, potion, etc
    var label: String {
        switch self {
        case .weapon: return "무기"
        case .hat:    return "모자"
        case .top:    return "상의"
        case .potion: return "물약"
        case .etc:    return "기타"
        }
    }
    static var wearable: [EquipSlot] { [.weapon, .hat, .top] }   // 장착 가능 부위(물약 제외)
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
    let healHP: Int?        // 소비아이템(물약) HP 회복량 (없으면 nil)
    let healMP: Int?        // 소비아이템 MP 회복량
    let iconID: Int?        // maplestory.io 아이템 id (있으면 이모지 대신 실제 아이콘)
    var isConsumable: Bool { slot == .potion }
    var healHPamount: Int { healHP ?? 0 }
    var healMPamount: Int { healMP ?? 0 }
}

enum ItemCatalog {
    static let all: [ItemType] = GameJSON.load("items", as: [ItemType].self) ?? fallback
    static let fallback: [ItemType] = [
        ItemType(id: "wood_sword", name: "나무 검", emoji: "🗡️",
                 slot: .weapon, rarity: .common, attack: 1, defense: 0, hpBonus: 0, price: 30,
                 healHP: nil, healMP: nil, iconID: nil)
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
    case nova     // 플레이어 중심 원형 광역: 좌우 양쪽 반경 내 적 (maxTargets로 제한)
    case summon   // 소환수(비홀더) — 즉시 타격 없이 따라다니며 자동 공격
    case buff     // 자기 버프 — 일정 시간 능력치↑ (버프창에 표시)
}

struct SkillType: Codable {
    let key: String         // 발동 키 ("S", "D" …)
    let name: String        // 스킬 이름
    let emoji: String       // 이펙트 이모지
    let damage: CGFloat     // 스킬 배율 (3.0 = 기본공격의 300%)
    let range: CGFloat      // 앞쪽 적중 범위
    let cooldown: CGFloat   // 재사용 대기시간(초)
    let mpCost: Int         // 소모 MP
    let shapeRaw: String?   // "beam" | "strike" | "area" | "nova" (누락 시 area)
    let height: CGFloat?    // 적중 세로 반경 (누락 시 모양별 기본값)
    let maxTargets: Int?    // 광역 최대 타격 수 (누락 시 무제한)
    let buffDmg: Double?    // buff: 데미지 +%
    let buffDef: Double?    // buff: 방어력 +%
    let buffDur: Double?    // buff: 지속(초)
    let desc: String?       // 스킬 설명(한글)

    enum CodingKeys: String, CodingKey {
        case key, name, emoji, damage, range, cooldown, mpCost
        case shapeRaw = "shape", height, maxTargets, buffDmg, buffDef, buffDur, desc
    }
    var shape: SkillShape { SkillShape(rawValue: shapeRaw ?? "area") ?? .area }
    var hitHalfHeight: CGFloat {
        if let h = height { return h }
        switch shape { case .beam: return 24; case .strike: return 70; case .area: return 90; case .nova: return 90; case .summon: return 90; case .buff: return 90 }
    }
    var skillPercent: Double { Double(damage) }
}

enum SkillCatalog {
    static let all: [SkillType] = GameJSON.load("skills", as: [SkillType].self) ?? []
}

// ── 영역(맵) ───────────────────────────────────────────────
// 영역 = 마을 또는 번호 필드(0..9). 레벨 1~200을 20레벨 단위 10개 필드로.
struct Area: Hashable, Codable {
    let raw: String
    init(raw: String) { self.raw = raw }
    static let town = Area(raw: "town")
    static func field(_ i: Int) -> Area { Area(raw: "f\(i)") }
    var isTown: Bool { raw == "town" }
    // "f<N>" → 0..<필드수 범위인 경우에만 유효(음수·초과·손상값은 nil → 호출부가 안전하게 폴백)
    var fieldIndex: Int? {
        guard raw.hasPrefix("f"), let i = Int(raw.dropFirst()),
              (0..<FieldCatalog.fields.count).contains(i) else { return nil }
        return i
    }
    var title: String {
        if isTown { return "마을" }
        let i = fieldIndex ?? 0
        return FieldCatalog.fields[i].name
    }
    // 구버전 저장값(field/forest/cave) → 새 인덱스로 이관
    static func migrated(_ raw: String) -> Area {
        switch raw {
        case "town": return .town
        case "field", "": return .field(0)
        case "forest": return .field(1)
        case "cave": return .field(2)
        default: return Area(raw: raw)
        }
    }
    // 단일 String으로 Codable
    init(from decoder: Decoder) throws { raw = try decoder.singleValueContainer().decode(String.self) }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(raw) }
}

// 필드 메타데이터(이름 + 테마색). 지형(footholds)은 FieldMaps.swift의 GameScene.fieldGeo[i].
struct FieldDef {
    let name: String
    let sky: (r: Double, g: Double, b: Double)
    let ground: (r: Double, g: Double, b: Double)
    let plat: (r: Double, g: Double, b: Double)
}
enum FieldCatalog {
    // 방어적 클램프(어떤 호출부도 오버플로우 못 하게)
    static func bandMin(_ i: Int) -> Int { min(fields.count - 1, max(0, i)) * 20 + 1 }
    static func bandMax(_ i: Int) -> Int { min(fields.count - 1, max(0, i)) * 20 + 20 }
    static let fields: [FieldDef] = [
        FieldDef(name: "리스항구 해안길 (Lv.1~20)",   sky: (0.53,0.78,0.92), ground: (0.62,0.50,0.34), plat: (0.40,0.70,0.35)),
        FieldDef(name: "버섯 포자 언덕 (Lv.21~40)",   sky: (0.60,0.82,0.70), ground: (0.34,0.44,0.28), plat: (0.45,0.60,0.32)),
        FieldDef(name: "야생 멧돼지의 땅 (Lv.41~60)", sky: (0.85,0.60,0.40), ground: (0.40,0.28,0.20), plat: (0.55,0.35,0.22)),
        FieldDef(name: "세 빛깔 정원 (Lv.61~80)",     sky: (0.70,0.80,0.95), ground: (0.78,0.80,0.92), plat: (0.88,0.80,0.90)),
        FieldDef(name: "아리언트 북문 사막 (Lv.81~100)", sky: (0.95,0.85,0.55), ground: (0.78,0.62,0.38), plat: (0.70,0.55,0.30)),
        FieldDef(name: "서부 리프레 숲 (Lv.101~120)", sky: (0.40,0.60,0.45), ground: (0.24,0.34,0.22), plat: (0.30,0.50,0.28)),
        FieldDef(name: "죽은 나무 설원 (Lv.121~140)", sky: (0.70,0.78,0.85), ground: (0.58,0.63,0.70), plat: (0.80,0.85,0.90)),
        FieldDef(name: "망각의 길 (Lv.141~160)",      sky: (0.35,0.30,0.50), ground: (0.30,0.25,0.40), plat: (0.50,0.42,0.62)),
        FieldDef(name: "헤네시스 폐허 시장 (Lv.161~180)", sky: (0.50,0.42,0.40), ground: (0.35,0.30,0.28), plat: (0.52,0.42,0.38)),
        FieldDef(name: "기사단 구역 (Lv.181~200)",    sky: (0.20,0.20,0.28), ground: (0.22,0.22,0.30), plat: (0.36,0.36,0.46)),
    ]
}

// ── 조작 액션 (키 리바인드 대상) ───────────────────────────
enum GameAction: String, Codable, CaseIterable {
    case left, right, jump, attack
    case skill1, skill2, skill3, skill4, skill5, skill6, skill7, skill8, skill9, skill10
    case inventory, stats, worldmap, interact, down, openKeybinds
    case pickup, skills, equipBrowser, equippedWindow
    var title: String {
        switch self {
        case .left: return "왼쪽";   case .right: return "오른쪽"
        case .jump: return "점프";   case .attack: return "공격"
        case .skill1: return "스킬 1"; case .skill2: return "스킬 2"
        case .skill3: return "스킬 3"; case .skill4: return "스킬 4"
        case .skill5: return "스킬 5"; case .skill6: return "스킬 6"
        case .skill7: return "스킬 7"; case .skill8: return "스킬 8"
        case .skill9: return "스킬 9"; case .skill10: return "스킬 10"
        case .inventory: return "장비창"; case .stats: return "능력치창"
        case .worldmap: return "월드맵"; case .interact: return "위/포털/등반"
        case .down: return "아래/내려가기"
        case .openKeybinds: return "키 설정"
        case .pickup: return "아이템 줍기"
        case .skills: return "스킬창"
        case .equipBrowser: return "장비 고르기"
        case .equippedWindow: return "착용 장비창"
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
    var skillLevels: [String: Int]?  // 스킬 key → 레벨
    var unspentSP: Int?              // 안 쓴 스킬 포인트
    var charSlots: [String: Int]?    // 외형 슬롯(CharSlot.rawValue → 아이템 id)
    var cashSlots: [String: Int]?    // 캐시(치장) 외형 오버레이
    var charOwned: [Int]?            // 보유 외형(maple) 아이템 id
    var damageSkin: Int?             // 데미지 스킨 인덱스
    var enhanceLevels: [String: Int]?  // (구) 외형 장비 강화 레벨 — 미사용(하위호환)
    var enhanceScrolls: Int?           // (구) 단일 주문서 수 — 미사용(하위호환)
    // ── 직업/주스탯 ──
    var job: String?                 // Job.rawValue
    var statSTR: Int?; var statINT: Int?; var statDEX: Int?; var statLUK: Int?
    // ── 장비 강화/잠재 ──
    var enhanceStat: [String: Int]?  // maple id → 강화 누적 스탯
    var upgradeUsed: [String: Int]?  // maple id → 사용한 업그레이드 횟수
    var starForce: [String: Int]?    // maple id → 별 강화 ★
    var scrollCounts: [Int]?         // 주문서 종류별 보유 수
    var selectedScroll: Int?         // 선택한 주문서 종류
    var cubes: Int?                  // (구) 보유 큐브 — 로드 시 레드로 이관
    var potentialLines: [String: String]?  // maple id → "kind:value;kind:value"
    var potentialGrade: [String: Int]?     // maple id → 등급(0~3)
    var redCubes: Int?               // 레드 큐브
    var blackCubes: Int?             // 블랙 큐브
    var addCubes: Int?               // 에디셔널 큐브
    var additionalLines: [String: String]? // maple id → 에디셔널 잠재 줄
    var additionalGrade: [String: Int]?    // maple id → 에디셔널 등급
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
