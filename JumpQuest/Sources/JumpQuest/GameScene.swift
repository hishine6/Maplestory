import SpriteKit
import AppKit
import Foundation
import CoreText

// 몬스터 종류·스킬·세이브는 GameData.swift, 표는 monsters.json / skills.json 에 있어요.

// 몬스터 한 마리 (화면 노드 + 종류 + 현재 상태)
@MainActor
final class Monster {
    let node: SKNode              // 이모지(SKLabelNode) 또는 스프라이트(SKSpriteNode)
    let type: MonsterType
    var hp: Int
    var dir: CGFloat
    let minX: CGFloat
    let maxX: CGFloat
    let baseY: CGFloat
    var bobPhase: CGFloat = 0
    var dying = false             // 죽는 애니 재생 중(중복 방지)
    var hpFill: SKSpriteNode?     // 머리 위 HP 바(채워지는 부분)
    var hpBarW: CGFloat = 40      // HP 바 최대 폭

    init(node: SKNode, type: MonsterType, dir: CGFloat, minX: CGFloat, maxX: CGFloat, baseY: CGFloat) {
        self.node = node; self.type = type; self.hp = type.maxHP
        self.dir = dir; self.minX = minX; self.maxX = maxX; self.baseY = baseY
    }
}

// 스킬 슬롯 (스킬 종류 + 발동 키 + 현재 쿨타임 + HUD 노드)
@MainActor
final class SkillSlot {
    let type: SkillType
    let keyCode: UInt16
    var cooldownLeft: CGFloat = 0
    var icon: SKNode!          // 스킬 아이콘(이미지 SKSpriteNode 또는 이모지 SKLabelNode)
    var cdLabel: SKLabelNode!
    var keyLabel: SKLabelNode!

    init(type: SkillType, keyCode: UInt16) { self.type = type; self.keyCode = keyCode }
}

// 바닥에 떨어진 전리품 (주워야 획득, 20초 후 소멸)
enum DropKind { case item(String); case gold(Int) }
// 데미지 스킨 (메이플식 데미지 숫자 스타일: 색 + 외곽선 + 글로우)
struct DmgSkin { let name: String; let normal: SKColor; let crit: SKColor; let outline: SKColor; let glow: Bool }

// 강화 주문서 종류 (성공률/증가량/실패하락/가격)
struct ScrollType { let name: String; let emoji: String; let rate: Double; let gain: Int; let failDrop: Int; let price: Int }

// 직업 — 1차 주스탯이 다름 (메이플 수식)
enum Job: String, Codable, CaseIterable {
    case warrior, thief, magician, archer
    var label: String { switch self { case .warrior: return "전사"; case .thief: return "도적"; case .magician: return "마법사"; case .archer: return "궁수" } }
    var primaryLabel: String { switch self { case .warrior: return "STR"; case .thief: return "LUK"; case .magician: return "INT"; case .archer: return "DEX" } }
    var hpPerLevel: Int { switch self { case .warrior: return 24; case .thief: return 16; case .archer: return 16; case .magician: return 10 } }
    var mpPerLevel: Int { switch self { case .magician: return 22; case .archer: return 14; case .thief: return 14; case .warrior: return 6 } }
}
enum PotKind { case str, int, dex, luk, atk, def, hp, mp, allstat, crit, dmg }   // 잠재옵션/스탯 종류
enum CubeKind { case red, black, additional }   // 큐브 종류(레드=즉시·낮은확률 / 블랙=before·after·높은확률 / 에디셔널=에디셔널 잠재)
struct PotOption { let kind: PotKind; let value: Int; let weight: Int; var pct: Bool = false }   // 큐브 줄별 확률표 항목(가중치, pct=퍼센트옵션)

@MainActor
final class GroundDrop {
    let node: SKNode            // 라벨(아이템) 또는 스프라이트(메소 코인)
    let kind: DropKind
    var life: CGFloat
    init(node: SKNode, kind: DropKind, life: CGFloat) {
        self.node = node; self.kind = kind; self.life = life
    }
}

// 게임의 "무대".
final class GameScene: SKScene {

    // ── 게임 느낌 조절 ────────────────────────────────────────
    let moveSpeed: CGFloat = 270
    let airAccel:  CGFloat = 340   // 공중에서 방향키가 주는 약한 가속(끌림)
    let jumpSpeed: CGFloat = 630   // 체공시간 줄이려 중력↑ 보정해 살짝 올림
    let gravity:   CGFloat = 2200  // ↑ = 더 빨리 떨어짐(체공 짧게)
    let playerHalfH: CGFloat = 22
    let playerHalfW: CGFloat = 12   // 옆벽(지면 블록) 충돌용 반폭
    // 캐릭터 표시: 텍스처를 **고정 배율**로 그림 → 장비(무기/망토)가 커져도 몸 크기 일정
    static let bodyScale: CGFloat = 0.5
    static let defaultFeetFrac: CGFloat = 0.2057        // 기본(베이크) 캐릭터 발끝/중심 (base-발끝 정렬)
    static let defaultBodyCenterFrac: CGFloat = 0.4879
    let attackRange: CGFloat = 95

    // ── 플레이어 상태 ─────────────────────────────────────────
    var player: SKNode!
    // 펫 (따라다니며 자동으로 주변 아이템 줍기) — maplestory.io 펫 아이콘
    static let petItemID = 5000001          // Brown Puppy
    var petNode: SKSpriteNode?
    // 비홀더 소환수 (다크나이트 G 스킬) — 따라다니며 주변 적 자동 공격
    var beholderNode: SKNode?
    var beholderCD: CGFloat = 0
    var beholderSkill: SkillType?
    var beholderBob: CGFloat = 0
    // 지속 스킬 존: 비홀더 임팩트(정지 2초 지속 광역) / 피어스 사이클론(채널, 키 떼거나 3초까지·플레이어 추적)
    struct SkillZone {
        let node: SKNode
        var x: CGFloat; var footY: CGFloat       // 데미지 판정 중심(x, 발높이)
        let range: CGFloat; let hh: CGFloat
        var remain: CGFloat; var tick: CGFloat
        let st: SkillType; let follows: Bool; var held: Bool
    }
    var skillZones: [SkillZone] = []
    var channelKey: UInt16? = nil               // 채널 중인 스킬 키(떼면 종료)
    // 버프창 (우상단) — 활성 버프 + 남은 시간(초). permanent=무제한(시간 표시 안 함)
    var buffs: [(key: String, icon: String, name: String, remain: CGFloat, permanent: Bool, dmgPct: Double, defPct: Double)] = []
    var buffHUD: SKNode?
    var buffDmgPct: Double { buffs.reduce(0) { $0 + $1.dmgPct } }   // 버프로 인한 데미지 +%
    var buffDefPct: Double { buffs.reduce(0) { $0 + $1.defPct } }   // 버프로 인한 방어 +%
    var leftPressed = false
    var rightPressed = false
    var pickupPressed = false   // Z(줍기) 1회 소비 플래그
    var pickupHeld = false      // Z 꾹 누름 → 일정 간격마다 자동 줍기
    var pickupCD: CGFloat = 0   // 자동 줍기 간격 타이머
    var velocityX: CGFloat = 0  // 수평 속도(공중 관성 + 약한 에어컨트롤)
    var dashTimer: CGFloat = 0  // 러시(돌진) 남은 시간
    var dashDir: CGFloat = 1    // 돌진 방향
    var velocityY: CGFloat = 0
    var onGround = false
    var transitioning = false      // 포탈/월드맵 이동 중 = 캐릭터 조작 잠금
    var attackCooldown: CGFloat = 0
    var attackHeld = false         // 공격키 꾹 누름 → 쿨다운마다 자동 반복
    var attackSpeedMult: CGFloat = 1.0   // 공격 속도 배수(>1=빠름) — 나중에 스킬/버프로 올림
    var attackDur: CGFloat = 0.45  // 현재 공격 모션 길이(애니 tpf 계산용)
    var attackInterval: CGFloat { max(0.18, 0.66 / attackSpeedMult) }   // 공격 간격(기본 0.66s, 하한 0.18)
    var jumpsUsed = 0              // 0=땅, 1=1단 점프중, 2=더블점프 사용 → 착지 시 0
    static let hudBarH: CGFloat = 84   // 하단 UI 영역 높이(게임화면과 겹치지 않는 전용 바)

    // 최대HP/MP = 기본 + 레벨×직업계수 + 주스탯(STR→HP, INT→MP) + 잠재
    var maxHP: Int { Int(Double(100 + (level - 1) * job.hpPerLevel + totalSTR * 2 + potStat(.hp)) * (1 + potPct(.hp) / 100.0)) }
    var hp = 100
    var invuln: CGFloat = 0
    var maxMP: CGFloat { CGFloat(Int(Double(600 + (level - 1) * (job.mpPerLevel + 10) + totalINT * 3 + potStat(.mp)) * (1 + potPct(.mp) / 100.0))) }
    var mp: CGFloat = 600
    let mpRegen: CGFloat = 60     // 초당 MP 회복량(넉넉히 — 마나 부족으로 못 쓰는 일 거의 없게)

    // ── 성장 상태 ─────────────────────────────────────────────
    var level = 1
    var xp = 0
    var kills = 0
    var xpToNext: Int { LevelTable.toNext(level) }

    // ── 인벤토리 / 장비 ───────────────────────────────────────
    var inventory: [String] = []                 // 보유 아이템 id (중복 허용)
    var equipped: [EquipSlot: String] = [:]      // (구) items.json 장비 — 미사용, maplestory 장비로 통일
    var inventoryOpen = false
    var inventoryPanel: SKNode?

    // ── 직업 / 주스탯(STR·INT·DEX·LUK) / AP ────────────────────────
    var job: Job = .warrior  // 전사(STR)/도적(LUK)/마법사(INT)/궁수(DEX)
    var statSTR = 0, statINT = 0, statDEX = 0, statLUK = 0   // AP 분배 (기본 4 + 분배)
    var unspentAP = 0        // 아직 안 쓴 능력치 포인트
    var statsOpen = false
    var statsPanel: SKNode?
    let apPerLevel = 3       // 레벨업마다 받는 AP
    var spentAP: Int { statSTR + statINT + statDEX + statLUK }
    // 총 스탯 = 기본 4 + 분배 + 잠재옵션(큐브)
    // 주스탯 = (기본4 + 분배 + 고정잠재 + 올스탯고정) × (1 + (스탯% + 올스탯%)/100)
    func statTotal(_ base: Int, _ k: PotKind) -> Int {
        let flat = Double(base + potStat(k) + potStat(.allstat))
        let pct = potPct(k) + potPct(.allstat)
        return Int(flat * (1 + pct / 100.0))
    }
    var totalSTR: Int { statTotal(4 + statSTR, .str) }
    var totalINT: Int { statTotal(4 + statINT, .int) }
    var totalDEX: Int { statTotal(4 + statDEX, .dex) }
    var totalLUK: Int { statTotal(4 + statLUK, .luk) }
    // 무기 공격력 = 무기/장갑 (기본 + 강화 + 잠재)
    var weaponATK: Int {
        let flat = [CharSlot.weapon, .gloves].reduce(0) { a, s in CharacterRenderer.shared.selection[s].map { a + itemATK(s, $0) } ?? a }
        return Int(Double(flat) * (1 + potPct(.atk) / 100.0))   // 공격력% 적용
    }
    // 직업별 1차스탯×배수 + 2차스탯 (메이플 클래식 수식)
    var statFactor: Double {
        let str = Double(totalSTR), it = Double(totalINT), dex = Double(totalDEX), luk = Double(totalLUK)
        switch job {
        case .warrior:  return str*4.0 + dex
        case .magician: return it*4.0 + luk
        case .archer:   return dex*3.4 + str
        case .thief:    return luk*3.6 + dex + str
        }
    }
    var maxDamage: Int { max(1, Int(statFactor * Double(weaponATK) / 100.0 * (1 + (potPct(.dmg) + buffDmgPct) / 100.0))) }   // ×(1+데미지%+버프%)

    // ── 스킬 SP 시스템 ──
    var unspentSP = 0                       // 안 쓴 스킬 포인트
    var skillLevels: [String: Int] = [:]    // 스킬 key → 레벨(기본 1)
    var skillWindowOpen = false
    var skillPanel: SKNode?
    let spPerLevel = 1       // 레벨업마다 받는 SP
    let maxSkillLevel = 20
    func skillLevel(_ key: String) -> Int { max(1, skillLevels[key] ?? 1) }
    // 스킬 레벨 보너스: 레벨당 +15% 데미지
    func skillPercentScaled(_ st: SkillType) -> Double { st.skillPercent * (1 + 0.15 * Double(skillLevel(st.key) - 1)) }

    // ── 골드 / 상점 ───────────────────────────────────────────
    var gold = 0
    let sellFraction: CGFloat = 0.5
    var shopOpen = false
    var shopScroll = 0                           // 상점 리스트 스크롤(행 오프셋)
    var shopPanel: SKNode?
    // 창 드래그 이동 (상점·인벤)
    var panelPos: [String: CGPoint] = [:]    // 창별 드래그 위치(키별)
    var panelHalf: [String: CGSize] = [:]    // 창별 절반 크기(클램프용)
    var dragNode: SKNode?
    var dragName = ""
    var dragLast: CGPoint = .zero
    var cubeWindowOpen = false
    var cubePanel: SKNode?
    var cubeItemID: Int = 0   // 강화/잠재 창이 다루는 아이템(장착 안 해도 됨)
    var cubeMode = 0          // 강화 창 탭: 0=주문서강화 1=별강화 2=잠재(큐브)
    var invSelectedID: Int = 0   // 인벤 장비탭에서 한번클릭으로 선택한 아이템(강화/잠재 대상)
    var cashWindowOpen = false   // 치장(캐시 외형) 창
    var cashPanel: SKNode?
    // ── 외형/장비 꾸미기 (maplestory.io 동적 합성) ──
    var equipBrowserOpen = false
    var equipPanel: SKNode?
    var equipPending: [CharSlot: Int] = [:]      // 브라우징 중 임시 선택 (확인 전)
    var iconCache: [Int: SKTexture] = [:]        // 아이템 아이콘 캐시
    var iconRefreshScheduled = false             // 아이콘 로드 후 패널 갱신 합치기(틱당 1회)
    // ── 착용창(E) + 탭 인벤토리(I) ──
    var equippedWindowOpen = false
    var equippedPanel: SKNode?
    var selEquipSlot: CharSlot = .weapon   // 장착창에서 선택된 부위(강화/큐브 대상)
    var invTab = 0                               // 0=장비 1=소비 2=기타
    var invScroll = 0                            // 인벤 그리드 스크롤(행 오프셋)
    var ownedAppearance: Set<Int> = []           // 보유 외형(maple) 아이템
    var hoverTooltip: SKNode?
    var hoverKey = ""                            // 호버 중 아이템 키(중복 갱신 방지)
    var pendingRegen = false                     // 재생성 중 또 바꾸면 끝나고 한번 더
    var anyModalOpen: Bool { inventoryOpen || statsOpen || shopOpen || worldMapOpen || keybindsOpen || skillWindowOpen || equipBrowserOpen || equippedWindowOpen || cubeWindowOpen || cashWindowOpen }
    // 세계 시뮬레이션을 멈추는 모달 (인벤·스탯·착용창은 제외 → 배경이 안 멈춤)
    var worldPaused: Bool { worldMapOpen || keybindsOpen }   // 전체화면 창만 정지 — 상점·장비·인벤·스탯은 이동 가능

    // ── 외형 장비 스탯 + 강화(주문서, 업그레이드 횟수) + 잠재(큐브) ──────────
    var enhanceStat: [Int: Int] = [:]   // maple id → 강화로 누적된 스탯(무기/장갑=ATK, 방어구=DEF)
    var upgradeUsed: [Int: Int] = [:]   // maple id → 사용한 업그레이드 횟수(성공·실패 모두 차감)
    var starForce: [Int: Int] = [:]     // maple id → 별 강화(스타포스) ★ 개수
    // 주문서 3종: 일반(안전·흔함) / 고급(확정) / 혼돈(고위험 고보상·실패 시 하락)
    static let scrollTypes: [ScrollType] = [
        ScrollType(name: "일반 주문서", emoji: "🔵", rate: 0.60, gain: 2, failDrop: 0, price: 40),
        ScrollType(name: "고급 주문서", emoji: "🟡", rate: 1.00, gain: 1, failDrop: 0, price: 100),
        ScrollType(name: "혼돈 주문서", emoji: "🔴", rate: 0.15, gain: 5, failDrop: 2, price: 80),
    ]
    var scrollCounts: [Int] = [0, 0, 0]   // 종류별 보유 수
    var selectedScroll = 0                // 현재 선택한 주문서 종류
    // 부위별 업그레이드 가능 횟수(슬롯)
    func maxSlots(_ s: CharSlot) -> Int { switch s { case .weapon: return 7; case .overall: return 6; case .hat, .cape: return 5; case .shoes, .gloves: return 4; default: return 0 } }
    func slotBaseDEF(_ s: CharSlot) -> Int { switch s { case .hat: return 8; case .overall: return 14; case .cape: return 6; case .shoes: return 5; default: return 0 } }
    func slotEnhanceable(_ s: CharSlot) -> Bool { maxSlots(s) > 0 }
    // 한 아이템의 공격력/방어력 = 부위 기본 + 강화누적 + 잠재
    // 무기별 실제 메이플 공격력(incPAD). 표에 없으면 30.
    static let weaponBaseATK: [Int: Int] = [
        1402061:110, 1302000:17, 1302005:32, 1312004:17, 1322000:34, 1302063:65, 1432014:40, 1442139:103,
        1302007:27, 1432000:32, 1402000:40, 1412000:47, 1312005:47, 1302020:48, 1432005:62, 1442005:72, 1312020:93, 1402005:95,
    ]
    func itemATK(_ s: CharSlot, _ id: Int) -> Int {
        if GameScene.isCash(id) { return 0 }   // 캐시(외형 전용) = 능력치 없음
        let base = (s == .weapon ? (GameScene.weaponBaseATK[id] ?? 30) : (s == .gloves ? 6 : 0))
        let enh = (s == .weapon || s == .gloves) ? (enhanceStat[id] ?? 0) : 0
        let star = (s == .weapon || s == .gloves) ? (starForce[id] ?? 0) * 2 : 0   // ★당 +2 공격력
        return base + enh + star + potBonus(id, .atk)
    }
    func itemDEF(_ s: CharSlot, _ id: Int) -> Int {
        if GameScene.isCash(id) { return 0 }   // 캐시(외형 전용) = 능력치 없음
        let base = slotBaseDEF(s)
        let enh = base > 0 ? (enhanceStat[id] ?? 0) : 0
        let star = base > 0 ? (starForce[id] ?? 0) * 2 : 0   // ★당 +2 방어력
        return base + enh + star + potBonus(id, .def)
    }
    // 외형(maple) 장착 합산
    var appearanceDEF: Int { CharSlot.allCases.reduce(0) { a, s in CharacterRenderer.shared.selection[s].map { a + itemDEF(s, $0) } ?? a } }
    var equippedIDs: [Int] { CharSlot.allCases.compactMap { CharacterRenderer.shared.selection[$0] } }
    var bonusDEF: Int { Int(Double(appearanceDEF) * (1 + (potPct(.def) + buffDefPct) / 100.0)) }   // 받는 피해 감소 (방어력%+버프%)
    // 주스탯 파생: 크리티컬 확률(LUK), 회피(LUK+DEX) — 메이플 느낌
    var critChance: Double { min(0.95, 0.05 + Double(totalLUK) * 0.0025 + potPct(.crit) / 100.0) }   // LUK + 잠재 크리%
    var avoidChance: Double { min(0.4, Double(totalLUK + totalDEX) * 0.0008) }
    // 잠재옵션(큐브) — 다음 단계에서 채움. 지금은 0.
    func potStat(_ k: PotKind) -> Int { equippedIDs.reduce(0) { $0 + potBonus($1, k) } }   // 장착 전체의 고정(+) 합
    func potBonus(_ id: Int, _ k: PotKind) -> Int {   // 고정(+) 옵션만 (메인 + 에디셔널 합산)
        ((potentialLines[id] ?? []) + (additionalLines[id] ?? [])).reduce(0) { $0 + ($1.kind == k && !$1.pct ? $1.value : 0) }
    }
    func potPct(_ k: PotKind) -> Double {   // 장착 전체의 퍼센트(%) 합
        Double(equippedIDs.reduce(0) { $0 + potPctBonus($1, k) })
    }
    func potPctBonus(_ id: Int, _ k: PotKind) -> Int {   // 메인 + 에디셔널 합산
        ((potentialLines[id] ?? []) + (additionalLines[id] ?? [])).reduce(0) { $0 + ($1.kind == k && $1.pct ? $1.value : 0) }
    }
    var potentialLines: [Int: [(kind: PotKind, value: Int, pct: Bool)]] = [:]   // id → 잠재옵션 줄들(큐브가 채움, pct=%)
    var potentialGrade: [Int: Int] = [:]                              // id → 등급(0레어 1에픽 2유니크 3레전)
    var additionalLines: [Int: [(kind: PotKind, value: Int, pct: Bool)]] = [:]  // id → 에디셔널 잠재 줄들
    var additionalGrade: [Int: Int] = [:]                             // id → 에디셔널 등급
    var redCubes: Int = 0                                             // 레드 큐브
    var blackCubes: Int = 0                                           // 블랙 큐브
    var addCubes: Int = 0                                             // 에디셔널 큐브
    var cubes: Int = 0                                                // (구) 큐브 — 로드 시 레드로 이관
    // 블랙 큐브 before/after 보류 상태(아직 확정 안 한 새 잠재). additional=에디셔널 대상 여부
    var pendingCube: (id: Int, grade: Int, lines: [(kind: PotKind, value: Int, pct: Bool)], additional: Bool)? = nil

    // ── 월드 크기 (뷰포트 720x480과 분리) ──────────────────────
    var worldW: CGFloat = 2400   // 영역별로 loadArea가 갱신
    var worldH: CGFloat = 900
    var viewW: CGFloat { size.width }    // 720 — 뷰포트
    var viewH: CGFloat { size.height }   // 480

    // ── 카메라 & 화면 고정 오버레이 ──
    // 좌표 규칙: 월드=씬 좌표(0…2400 × 0…900). 카메라 position은 월드 좌표.
    // hudLayer는 cam의 자식 → 그 안은 화면중심(0,0) 기준 [-360..360]×[-240..240].
    // 옛 절대 HUD 좌표 (ax,ay) → camRel = (ax-360, ay-240).
    var cam: SKCameraNode!
    var hudLayer: SKNode!
    var fadeOverlay: SKSpriteNode!

    // ── MapleStory식 데미지 상수 ──
    let BASE_ATTACK:  Double = 8
    let LEVEL_FACTOR: Double = 2
    let MASTERY:      Double = 0.65

    // ── 지형/스폰 ──
    struct Surface { let cx: CGFloat; let topY: CGFloat; let span: CGFloat }
    var surfaces: [Surface] = []

    // ── 미니맵 ──
    var miniMap: SKNode!
    var miniPlayerDot: SKShapeNode!
    var miniMonsterDots: [SKShapeNode] = []
    let miniW: CGFloat = 200
    var miniH: CGFloat { miniW * (worldH / worldW) }
    var miniScale: CGFloat { miniW / worldW }

    // ── 월드 ──────────────────────────────────────────────────
    var solids: [CGRect] = []
    var monsters: [Monster] = []
    var drops: [GroundDrop] = []
    var skills: [SkillSlot] = []
    var respawnQueue: [(time: CGFloat, surface: Surface)] = []
    var lastTime: TimeInterval = 0
    var keyMonitor: Any?

    // ── 영역(Area) / 포털 / NPC ──
    var worldLayer: SKNode!                    // 모든 영역 노드의 부모. loadArea가 비움.
    var currentArea: Area = .field(0)
    struct Portal { let node: SKNode; let rect: CGRect; let target: Area }
    var portals: [Portal] = []
    var shopNPC: (node: SKNode, rect: CGRect)?
    var townNPCList: [(rect: CGRect, name: String, line: String, shop: Bool)] = []   // 마을 NPC 상호작용
    var dialogueBox: SKNode?                                                          // NPC 말풍선(화면 고정)
    var interactPressed = false
    var interactCooldown: CGFloat = 0

    // ── 밧줄/등반 ──
    struct Rope { let x: CGFloat; let bottomY: CGFloat; let topY: CGFloat }
    var ropes: [Rope] = []
    var climbing = false
    var climbRope: Rope?
    var upHeld = false
    var downHeld = false
    let climbSpeed: CGFloat = 165

    // ── 월드맵 / 키설정 모달 ──
    var worldMapOpen = false
    var worldMapPanel: SKNode?
    var keybindsOpen = false
    var keybindsScroll = 0
    var keybindsPanel: SKNode?
    var capturingAction: GameAction? = nil     // non-nil = 다음 키 입력을 이 액션에 바인딩

    // ── 키 바인딩 / 캐릭터 ID ──
    static let defaultCharID = "용사"
    var charID: String = GameScene.defaultCharID
    var binds: [GameAction: UInt16] = GameScene.defaultBinds

    // ── HUD ───────────────────────────────────────────────────
    var levelLabel: SKLabelNode!
    var killsLabel: SKLabelNode!
    var charLabel: SKLabelNode!
    var expBarFill: SKSpriteNode!
    var hpBarFill: SKSpriteNode!
    var mpBarFill: SKSpriteNode!
    var goldLabel: SKLabelNode!
    let barWidth: CGFloat = 200

    override func didMove(to view: SKView) {
        GameScene.registerFonts()        // Galmuri 한글 픽셀 폰트 등록(최초 1회)
        anchorPoint = .zero
        backgroundColor = SKColor(red: 0.60, green: 0.85, blue: 1.0, alpha: 1.0)
        view.window?.acceptsMouseMovedEvents = true   // 인벤토리 호버 툴팁용
        DispatchQueue.main.async { [weak view] in view?.window?.makeFirstResponder(view) }

        setupCamera()        // cam + hudLayer + worldLayer
        addPlayer()          // 씬 자식 → 영역 전환에도 유지
        addHUD()             // 하단 상태바 (한 번만)
        addSkills()          // 스킬 아이콘 (한 번만)
        styleLabels(hudLayer)   // HUD 라벨(레벨·골드·처치수 등) = Galmuri
        setupKeyboard()      // 라이브 binds 모니터

        binds = GameScene.defaultBinds                  // 기본값 먼저
        let save = SaveStore.load()
        if let s = save {
            level = s.level; xp = s.xp; kills = s.kills
            // 소비·기타 아이템 보관 — 옛 items.json 장비(나무검 등)는 maplestory 장비로 통일하며 제거
            inventory = (s.inventory ?? []).filter { let it = ItemCatalog.item($0); return it?.isConsumable == true || it?.slot == .etc }
            equipped = [:]   // (구) items.json 장비 시스템 미사용
            job = .warrior   // 직업 전사 고정 (전직 비활성화)
            statSTR = max(0, s.statSTR ?? 0); statINT = max(0, s.statINT ?? 0)
            statDEX = max(0, s.statDEX ?? 0); statLUK = max(0, s.statLUK ?? 0)
            unspentAP = max(0, s.unspentAP ?? 0)
            gold = max(0, s.gold ?? 0)
            reconcileAP()    // 구버전(STR 등 없는) 세이브는 spentAP=0 → 레벨당 AP 환급되어 재분배
            if hp > maxHP { hp = maxHP }
            if let b = s.binds {                        // 저장된 키만 덮어쓰기
                for (k, v) in b { if let a = GameAction(rawValue: k) { binds[a] = UInt16(v) } }
            }
            charID = (s.charID?.isEmpty == false) ? s.charID! : GameScene.defaultCharID
            skillLevels = s.skillLevels ?? [:]; unspentSP = max(0, s.unspentSP ?? 0)
            if let cs = s.charSlots {                    // 외형 선택 복원
                for (raw, id) in cs { if let slot = CharSlot(rawValue: raw) { CharacterRenderer.shared.selection[slot] = id } }
            }
            CharacterRenderer.shared.cashSelection = [:]
            for (raw, id) in (s.cashSlots ?? [:]) { if let slot = CharSlot(rawValue: raw) { CharacterRenderer.shared.cashSelection[slot] = id } }   // 치장 복원
            ownedAppearance = Set(s.charOwned ?? [])     // 보유 외형 아이템 복원
            dmgSkinIdx = min(max(0, s.damageSkin ?? 0), GameScene.dmgSkins.count - 1)   // 데미지 스킨 복원(클램프: 손상 세이브 방어)
            let parseIntMap: ([String:Int]?) -> [Int:Int] = { m in
                Dictionary((m ?? [:]).compactMap { k, v in Int(k).map { ($0, v) } }, uniquingKeysWith: { a, _ in a })   // 중복키 손상세이브 방어
            }
            enhanceStat = parseIntMap(s.enhanceStat).mapValues { max(0, $0) }
            upgradeUsed = parseIntMap(s.upgradeUsed).mapValues { max(0, $0) }
            starForce = parseIntMap(s.starForce).mapValues { max(0, min(GameScene.maxStar, $0)) }
            scrollCounts = (s.scrollCounts.map { Array($0.prefix(3)) + Array(repeating: 0, count: max(0, 3 - $0.count)) }) ?? [0,0,0]
            selectedScroll = min(max(0, s.selectedScroll ?? 0), GameScene.scrollTypes.count - 1)
            redCubes = max(0, s.redCubes ?? 0) + max(0, s.cubes ?? 0)   // 구버전 cubes → 레드로 이관
            blackCubes = max(0, s.blackCubes ?? 0)
            addCubes = max(0, s.addCubes ?? 0)
            // 잠재옵션 복원 (id → "kind:value:pct;...")
            func deserLines(_ src: [String: String]?) -> [Int: [(kind: PotKind, value: Int, pct: Bool)]] {
                var out: [Int: [(kind: PotKind, value: Int, pct: Bool)]] = [:]
                for (k, str) in (src ?? [:]) {
                    guard let id = Int(k) else { continue }
                    out[id] = str.split(separator: ";").compactMap { seg in
                        let p = seg.split(separator: ":"); guard p.count >= 2, let v = Int(p[1]), let kind = GameScene.potKind(String(p[0])) else { return nil }
                        return (kind, v, p.count >= 3 && p[2] == "1")
                    }
                }
                return out
            }
            potentialLines = deserLines(s.potentialLines)
            additionalLines = deserLines(s.additionalLines)
            for (k, g) in (s.potentialGrade ?? [:]) { if let id = Int(k) { potentialGrade[id] = max(0, min(3, g)) } }
            for (k, g) in (s.additionalGrade ?? [:]) { if let id = Int(k) { additionalGrade[id] = max(0, min(3, g)) } }
            if let lbl = hudLayer?.childNode(withName: "dmgskin_label") as? SKLabelNode {   // 로드 후 HUD 라벨 동기화
                lbl.text = "🎨 \(GameScene.dmgSkins[dmgSkinIdx].name)"
            }
        }
        // 테스트용: 큐브 최소 보유량 보장(부족하면 채워줌). 정식화 시 이 줄 제거.
        redCubes = max(redCubes, 50); blackCubes = max(blackCubes, 50); addCubes = max(addCubes, 50)
        mp = maxMP                                  // 시작 시 마나 가득(부족으로 못 쓰는 일 없게)
        binds[.openKeybinds] = nil                       // 키설정=버튼 전용, 옛 저장의 E(14) 충돌 제거
        binds[.equipBrowser] = nil                       // R 제거 — 옛 저장의 R 바인딩도 무효화
        ensureStartingOwnedItems()                       // 장착중인 것 + 신규면 기본 인벤 보장
        prefetchAppearanceIcons()                        // 외형 아이콘 미리 받아둠 → 인벤 열자마자 표시
        refreshSkillKeyLabels()                         // 스킬 아이콘 키 라벨을 binds로 맞춤

        let startArea = Area.migrated(save?.area ?? "")
        loadArea(startArea, spawnAt: nil)               // 지형/몬스터/미니맵 빌드 + 플레이어 배치
        loadSavedCharacterIfNeeded()                    // 저장된 외형이 기본과 다르면 백그라운드 합성·교체

        if save != nil {
            popText("이어하기! Lv \(level)", at: player.position,
                    color: SKColor(red: 0.15, green: 0.45, blue: 0.9, alpha: 1), size: 26)
        }
        updateHUD()
    }

    // ── 카메라 ────────────────────────────────────────────────
    func setupCamera() {
        cam = SKCameraNode()
        addChild(cam)
        camera = cam
        hudLayer = SKNode()
        hudLayer.zPosition = 1000     // 모든 월드 노드 위
        cam.addChild(hudLayer)

        // 영역 전환용 페이드 오버레이 (화면 전체 덮는 검정, 평소 투명)
        fadeOverlay = SKSpriteNode(color: .black, size: CGSize(width: 4000, height: 3000))
        fadeOverlay.zPosition = 5000   // HUD·모달보다 위
        fadeOverlay.alpha = 0
        fadeOverlay.position = .zero
        hudLayer.addChild(fadeOverlay)

        worldLayer = SKNode()         // 영역 콘텐츠 부모 (loadArea가 비움)
        worldLayer.zPosition = 0
        addChild(worldLayer)
    }

    func updateCamera() {
        let halfW = viewW / 2, halfH = viewH / 2
        let bar = GameScene.hudBarH
        let cx = min(max(player.position.x, halfW), worldW - halfW)
        // 하단 UI바 만큼 화면을 위로 양보: 플레이어를 "바 위 플레이영역" 중앙에 두고(중심보다 bar/2 위),
        // 카메라가 bar만큼 더 내려갈 수 있게 해 월드 바닥이 바 위에 오게 함(캐릭터가 바에 가리지 않음).
        let upper = max(halfH - bar, worldH - halfH)   // 아주 작은 맵(worldH<viewH-bar)에서도 클램프 역전 방지
        let cy = min(max(player.position.y - bar/2, halfH - bar), upper)
        cam.position = CGPoint(x: cx, y: cy)
    }

    // ── 영역(Area) 전환 ───────────────────────────────────────
    func areaSize(_ a: Area) -> (w: CGFloat, h: CGFloat) {
        if a.isTown { return (GameScene.townW, GameScene.townH) }   // maplestory map 1000000 (Amherst)
        let g = GameScene.fieldGeo[min(GameScene.fieldGeo.count - 1, max(0, a.fieldIndex ?? 0))]
        return (g.w, g.h)
    }

    func buildAreaContent(_ a: Area) {
        if a.isTown { buildTown(); return }
        buildField(min(GameScene.fieldGeo.count - 1, max(0, a.fieldIndex ?? 0)))
    }

    // ── 레벨대 필드(실제 메이플 맵 레이아웃 + 테마색 지형) ──
    // 지형 = FieldMaps.swift의 fieldGeo[i](실제 footholds/ropes 변환). 포털은 이전/다음 필드로 자동 연결.
    func buildField(_ i: Int) {
        let g = GameScene.fieldGeo[i]
        let d = FieldCatalog.fields[i]
        func col(_ c: (r: Double, g: Double, b: Double), _ a: CGFloat = 1) -> SKColor {
            SKColor(red: c.r, green: c.g, blue: c.b, alpha: a)
        }
        // 하늘(원경 그라데이션 느낌: 위는 약간 어둡게)
        let sky = SKSpriteNode(color: col(d.sky), size: CGSize(width: worldW, height: worldH))
        sky.position = CGPoint(x: worldW/2, y: worldH/2); sky.zPosition = -11; worldLayer.addChild(sky)
        // 바닥 지면 = 키 큰 솔리드 블록(y0~top): 윗면 착지 + 옆벽 막힘
        for b in g.ground {
            let w = max(2, b.x2 - b.x1)
            solids.append(CGRect(x: b.x1, y: 0, width: w, height: b.top))
            let node = SKSpriteNode(color: col(d.ground), size: CGSize(width: w, height: b.top))
            node.position = CGPoint(x: (b.x1 + b.x2)/2, y: b.top/2); node.zPosition = -5
            let cap = SKSpriteNode(color: col(d.plat), size: CGSize(width: w, height: 6))   // 윗면 강조선
            cap.position = CGPoint(x: 0, y: b.top/2 - 3); node.addChild(cap)
            worldLayer.addChild(node)
        }
        // 공중 발판 = 얇은 1방향 발판(밑에서 뚫고 올라감, 위에 착지)
        for p in g.platforms {
            let w = max(2, p.x2 - p.x1)
            solids.append(CGRect(x: p.x1, y: p.top - 8, width: w, height: 8))
            let node = SKSpriteNode(color: col(d.plat), size: CGSize(width: w, height: 8))
            node.position = CGPoint(x: (p.x1 + p.x2)/2, y: p.top - 4); node.zPosition = -4
            worldLayer.addChild(node)
        }
        for r in g.ropes { makeRope(x: r.x, bottomY: r.bottomY, topY: r.topY) }   // 보이는 밧줄
        // ── 포털 자동 연결: 왼쪽=이전 필드(또는 마을), 오른쪽=다음 필드 ──
        if let lg = g.ground.min(by: { $0.x1 < $1.x1 }) {
            let leftTarget: Area = (i == 0) ? .town : .field(i - 1)
            makePortal(at: CGPoint(x: lg.x1 + 50, y: lg.top + 20), target: leftTarget,
                       label: "◀ \(leftTarget.title)")
        }
        if i < FieldCatalog.fields.count - 1, let rg = g.ground.max(by: { $0.x2 < $1.x2 }) {
            makePortal(at: CGPoint(x: rg.x2 - 50, y: rg.top + 20), target: .field(i + 1),
                       label: "\(Area.field(i + 1).title) ▶")
        }
    }

    // ── maplestory.io map 1000000 "애머스트(메이플 아일랜드 마을)" ──
    // 배경=서버 렌더 PNG(투명 하늘), 바닥/뒤발판/밧줄=맵 footholds, NPC=맵 npc 데이터(스프라이트+이름+대사).
    func buildTown() {
        let sky = SKSpriteNode(color: SKColor(red: 0.53, green: 0.78, blue: 0.92, alpha: 1),
                               size: CGSize(width: worldW, height: worldH))
        sky.position = CGPoint(x: worldW/2, y: worldH/2); sky.zPosition = -11
        worldLayer.addChild(sky)
        addAreaBackground("town_bg")                         // 마을 렌더(버섯집/돌바닥)
        for g in GameScene.townGround {                      // 앞 바닥 = 키 큰 솔리드 블록
            solids.append(CGRect(x: g.x1, y: 0, width: max(2, g.x2 - g.x1), height: g.top))
        }
        for p in GameScene.townPlatforms {                   // 뒤 단상 = 얇은 1방향 발판
            solids.append(CGRect(x: p.x1, y: p.top - 8, width: max(2, p.x2 - p.x1), height: 8))
        }
        for r in GameScene.townRopes { makeRope(x: r.x, bottomY: r.bottomY, topY: r.topY) }   // 밧줄(보이는 사다리)
        for npc in GameScene.townNPCs {                      // NPC 스프라이트 + 이름표 + 상호작용
            let tex = GameScene.frameTex("npc/\(npc.sprite)")
            let node: SKNode
            if tex.size().width > 1 {
                let sp = SKSpriteNode(texture: tex)
                sp.anchorPoint = CGPoint(x: 0.5, y: 0)        // 발끝을 지면에
                if npc.flip { sp.xScale = -1 }
                node = sp
            } else { let l = SKLabelNode(text: "🧍"); l.fontSize = 36; l.verticalAlignmentMode = .bottom; node = l }
            node.position = CGPoint(x: npc.x, y: npc.y); node.zPosition = 4
            worldLayer.addChild(node)
            let tag = SKLabelNode(text: npc.shop ? "\(npc.name) 🛒" : npc.name)
            tag.fontSize = 13; tag.fontColor = npc.shop ? .yellow : .white
            tag.verticalAlignmentMode = .bottom
            tag.position = CGPoint(x: npc.x, y: npc.y + node.frame.height + 4); tag.zPosition = 4
            // 이름표 배경(가독성)
            let pad: CGFloat = 4
            let bgw = tag.frame.width + pad*2
            let lblBG = SKShapeNode(rect: CGRect(x: npc.x - bgw/2, y: tag.position.y - 2, width: bgw, height: 18), cornerRadius: 4)
            lblBG.fillColor = SKColor(white: 0, alpha: 0.5); lblBG.strokeColor = .clear; lblBG.zPosition = 3.9
            worldLayer.addChild(lblBG); worldLayer.addChild(tag)
            townNPCList.append((rect: CGRect(x: npc.x - 30, y: npc.y, width: 60, height: 70),
                                name: npc.name, line: npc.line, shop: npc.shop))
        }
        makePortal(at: CGPoint(x: 2680, y: 280), target: .field(0), label: "\(Area.field(0).title) ▶")  // 오른쪽 끝 → 첫 필드
    }

    // 현재 영역을 비우고 target을 다시 짓는다.
    func loadArea(_ target: Area, spawnAt: CGPoint?) {
        worldLayer.removeAllChildren()     // 지형/몬스터/포털/NPC/FX/드롭 (player는 씬 자식이라 안전)
        solids.removeAll(); surfaces.removeAll(); monsters.removeAll()
        respawnQueue.removeAll(); portals.removeAll(); shopNPC = nil; drops.removeAll()
        townNPCList.removeAll(); dialogueBox?.removeFromParent(); dialogueBox = nil
        ropes.removeAll(); climbing = false; climbRope = nil; upHeld = false; downHeld = false
        skillZones.removeAll(); channelKey = nil   // 지속 스킬 존 정리(worldLayer가 비워짐)

        currentArea = target
        let sz = areaSize(target); worldW = sz.w; worldH = sz.h

        if target == .town { addAreaBackground("town_bg") }   // 마을.png 배경
        buildAreaContent(target)
        styleLabels(worldLayer)        // NPC 이름표·포탈 라벨 = Galmuri
        buildSurfaces()
        rebuildMiniMap()

        if let fi = target.fieldIndex {                                 // 필드 = 레벨대 몬스터 스폰
            var spots = surfaces.shuffled()
            if spots.count > 16 { spots = Array(spots.prefix(16)) }      // 과밀 방지
            for surf in spots { spawnMonster(on: surf, fieldIndex: fi) }
        }

        player.position = spawnAt ?? defaultSpawn(for: target)
        velocityY = 0; onGround = false; dashTimer = 0; velocityX = 0   // 잔여 돌진/속도 정리(도착 지점 밀림 방지)
        leftPressed = false; rightPressed = false
        updateCamera()
        updateHUD()
        saveProgress()
    }

    // 영역 배경 이미지(예: 마을.png) — 월드 전체를 덮고 맨 뒤(z=-10)에 깔림.
    func addAreaBackground(_ name: String) {
        let tex = GameScene.frameTex(name)
        guard tex.size().width > 1 else { return }
        tex.filteringMode = .linear                 // 스크린샷이라 부드럽게
        let bg = SKSpriteNode(texture: tex)
        bg.size = CGSize(width: worldW, height: worldH)
        bg.position = CGPoint(x: worldW/2, y: worldH/2)
        bg.zPosition = -10
        worldLayer.addChild(bg)
    }

    func defaultSpawn(for a: Area) -> CGPoint {
        if a.isTown { return CGPoint(x: 500, y: 330) }   // gy219 왼쪽 바닥 위에서 낙하 착지
        let g = GameScene.fieldGeo[min(GameScene.fieldGeo.count - 1, max(0, a.fieldIndex ?? 0))]
        guard let lg = g.ground.min(by: { $0.x1 < $1.x1 }) else { return CGPoint(x: 120, y: 120) }
        let sx = lg.x1 + 50                              // 왼쪽 포털과 같은 x (좌측 포털 근처)
        // 그 x를 덮는 가장 높은 지면 위에 착지(겹친 높은 블록에 박히지 않게)
        let top = g.ground.filter { $0.x1 <= sx && sx <= $0.x2 }.map { $0.top }.max() ?? lg.top
        return CGPoint(x: sx, y: top + 40)
    }

    // 포털로 입장했을 때 돌아가는 포털 옆에 세움 (즉시 되돌아가지 않게)
    func arrivalSpawn(in target: Area, cameFrom: Area) -> CGPoint? {
        if let back = portals.first(where: { $0.target == cameFrom }) {
            return CGPoint(x: back.node.position.x, y: back.node.position.y + 30)   // 포탈 바로 위에 등장(낙하 착지)
        }
        return nil
    }

    func makePortal(at p: CGPoint, target: Area, label: String) {
        let n = SKNode(); n.position = p; n.zPosition = 4
        let glow = SKShapeNode(rect: CGRect(x: -22, y: -40, width: 44, height: 84), cornerRadius: 10)
        glow.fillColor = SKColor(red: 0.5, green: 0.3, blue: 0.9, alpha: 0.4)
        glow.strokeColor = SKColor(white: 1, alpha: 0.7); glow.lineWidth = 2
        n.addChild(glow)
        glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.2, duration: 0.7),
                                           .fadeAlpha(to: 0.55, duration: 0.7)])))
        let swirl = SKLabelNode(text: "🌀"); swirl.fontSize = 30
        swirl.verticalAlignmentMode = .center; swirl.position = CGPoint(x: 0, y: 6)
        n.addChild(swirl)
        let tag = SKLabelNode(text: label); tag.fontSize = 12; tag.fontColor = .white
        tag.position = CGPoint(x: 0, y: 52); n.addChild(tag)
        worldLayer.addChild(n)
        portals.append(Portal(node: n, rect: CGRect(x: p.x - 22, y: p.y - 40, width: 44, height: 84),
                              target: target))
    }

    func makeShopNPC(at p: CGPoint) {
        let n = SKNode(); n.position = p; n.zPosition = 4
        let body = SKLabelNode(text: "🧙"); body.fontSize = 40; body.verticalAlignmentMode = .bottom
        n.addChild(body)
        let tag = SKLabelNode(text: "상점 (↑)"); tag.fontSize = 12; tag.fontColor = .yellow
        tag.position = CGPoint(x: 0, y: 54); n.addChild(tag)
        worldLayer.addChild(n)
        shopNPC = (n, CGRect(x: p.x - 28, y: p.y, width: 56, height: 56))
    }

    // ── 밧줄(사다리) ──────────────────────────────────────────
    func makeRope(x: CGFloat, bottomY: CGFloat, topY: CGFloat) {
        let h = topY - bottomY
        let rail = SKSpriteNode(color: SKColor(red: 0.74, green: 0.58, blue: 0.34, alpha: 1),
                                size: CGSize(width: 5, height: h))
        rail.position = CGPoint(x: x, y: (bottomY + topY)/2); rail.zPosition = 3
        worldLayer.addChild(rail)
        var ry = bottomY + 14                       // 가로대
        while ry < topY - 4 {
            let rung = SKSpriteNode(color: SKColor(red: 0.58, green: 0.43, blue: 0.24, alpha: 1),
                                    size: CGSize(width: 15, height: 3))
            rung.position = CGPoint(x: x, y: ry); rung.zPosition = 3
            worldLayer.addChild(rung)
            ry += 22
        }
        ropes.append(Rope(x: x, bottomY: bottomY, topY: topY))
    }

    // 잡을 수 있는 밧줄: ↑은 밧줄 몸통에서, ↓은 꼭대기 발판에서
    func ropeNear(_ pos: CGPoint) -> Rope? {
        let feet = pos.y - playerHalfH
        for r in ropes where abs(pos.x - r.x) < 18 {
            if upHeld   && feet >= r.bottomY - 6 && feet <= r.topY - 10 { return r }   // 위로 잡기
            if downHeld && feet >= r.topY - 6   && feet <= r.topY + 10 { return r }    // 꼭대기에서 아래로
        }
        return nil
    }

    func startClimb(_ rope: Rope) {
        climbing = true; climbRope = rope
        player.position.x = rope.x
        velocityY = 0; dashTimer = 0; velocityX = 0   // 줄 잡으면 남은 돌진 취소(이탈 시 갑자기 돌진 방지)
        player.xScale = 1                 // 줄에서는 정면(반전 없음)
        currentAnimKey = ""               // climb 애니가 즉시 걸리도록
    }

    func releaseClimb() {
        climbing = false; climbRope = nil
        player.removeAction(forKey: "climb")
        player.zRotation = 0
        currentAnimKey = ""
    }

    func rebuildMiniMap() {
        miniMap?.removeFromParent(); miniMap = nil
        miniMonsterDots.removeAll()
        addMiniMap()
    }

    func tryInteract() {
        guard !anyModalOpen, !climbing, interactCooldown <= 0 else { return }
        if dialogueBox != nil { dialogueBox?.removeFromParent(); dialogueBox = nil; interactCooldown = 0.25; return }  // ↑ 다시 → 닫기
        let pp = player.position
        for portal in portals where portal.rect.contains(pp) {
            interactCooldown = 0.8
            fadeToArea(portal.target, from: currentArea)
            return
        }
        for npc in townNPCList where npc.rect.contains(pp) {
            interactCooldown = 0.3
            if npc.shop { openShop() } else { showDialogue(name: npc.name, line: npc.line) }
            return
        }
        if let npc = shopNPC, npc.rect.contains(pp) { openShop(); return }
    }

    // NPC 말풍선 (화면 하단 고정, ↑ 다시 누르거나 멀어지면 닫힘)
    func showDialogue(name: String, line: String) {
        dialogueBox?.removeFromParent()
        let box = SKNode(); box.zPosition = 95
        box.position = CGPoint(x: 0, y: -viewH/2 + 92)
        let w: CGFloat = min(560, viewW - 60), h: CGFloat = 76
        let bg = SKShapeNode(rect: CGRect(x: -w/2, y: -h/2, width: w, height: h), cornerRadius: 10)
        bg.fillColor = SKColor(white: 0.06, alpha: 0.92); bg.strokeColor = SKColor(white: 0.8, alpha: 0.7); bg.lineWidth = 2
        box.addChild(bg)
        let nm = SKLabelNode(text: "💬 \(name)"); nm.fontSize = 15; nm.fontColor = .yellow
        nm.horizontalAlignmentMode = .left; nm.verticalAlignmentMode = .top
        nm.position = CGPoint(x: -w/2 + 18, y: h/2 - 12); box.addChild(nm)
        let tx = SKLabelNode(text: line); tx.fontSize = 16; tx.fontColor = .white
        tx.horizontalAlignmentMode = .left; tx.verticalAlignmentMode = .center
        tx.position = CGPoint(x: -w/2 + 18, y: -6); box.addChild(tx)
        let hint = SKLabelNode(text: "↑ 닫기"); hint.fontSize = 11; hint.fontColor = SKColor(white: 0.6, alpha: 1)
        hint.horizontalAlignmentMode = .right; hint.verticalAlignmentMode = .bottom
        hint.position = CGPoint(x: w/2 - 14, y: -h/2 + 8); box.addChild(hint)
        styleLabels(box); hudLayer.addChild(box); dialogueBox = box
    }

    // 전리품 줍기 (Z) — 사거리 내 가장 가까운 1개만
    // 펫 x 아래의 지면 윗면(플레이어 발 높이 근처) — 펫이 바닥을 걷도록
    func groundTopBelow(x: CGFloat, near y: CGFloat) -> CGFloat? {
        var best: CGFloat? = nil
        for r in solids where x >= r.minX && x <= r.maxX {
            let top = r.maxY
            if top <= y + 40 {                               // 발 높이 또는 그 아래
                if best == nil || top > best! { best = top }
            }
        }
        return best
    }

    // 펫: 바닥을 걸어 플레이어를 따라다니다, 근처에 드롭이 있으면 그쪽으로 걸어가 주워줌
    func updatePet(_ dt: CGFloat) {
        if petNode == nil {                                  // 아이콘 도착하면 생성
            guard let tex = iconCache[GameScene.petItemID], tex.size().width > 1 else { ensureIcon(GameScene.petItemID); return }
            tex.filteringMode = .nearest
            let s = tex.size(); let mx = max(s.width, s.height, 1)
            let sp = SKSpriteNode(texture: tex)
            sp.size = CGSize(width: s.width / mx * 30, height: s.height / mx * 30)
            sp.anchorPoint = CGPoint(x: 0.5, y: 0)           // 발끝을 지면에
            sp.zPosition = 4; sp.position = CGPoint(x: player.position.x, y: player.position.y - playerHalfH)
            addChild(sp); petNode = sp
        }
        guard let pet = petNode else { return }
        let footY = player.position.y - playerHalfH

        // 목표 x: 플레이어 주변(가로260·세로150) 드롭이 있으면 가장 가까운 그 드롭, 없으면 플레이어 뒤
        var fetchIdx = -1; var bestDX: CGFloat = .greatestFiniteMagnitude
        for (i, d) in drops.enumerated() {
            let dp = d.node.position
            if abs(dp.x - player.position.x) < 260, abs(dp.y - footY) < 150 {
                let dd = abs(dp.x - pet.position.x)
                if dd < bestDX { bestDX = dd; fetchIdx = i }
            }
        }
        let behind: CGFloat = player.xScale < 0 ? 1 : -1
        let targetX = fetchIdx >= 0 ? drops[fetchIdx].node.position.x : player.position.x + behind * 40

        // 걸어서 이동(속도 제한). 너무 멀어지면(점프/포털) 가까이 당김
        let petSpeed: CGFloat = 230
        var nx = pet.position.x + max(-petSpeed * dt, min(petSpeed * dt, targetX - pet.position.x))
        if abs(nx - player.position.x) > 640 { nx = player.position.x + behind * 40 }
        // y: 펫 아래 지면에 접지(없으면 발 높이로)
        let gy = groundTopBelow(x: nx, near: footY) ?? footY
        let ny = pet.position.y + (gy - pet.position.y) * min(1, dt * 12)
        pet.position = CGPoint(x: nx, y: ny)
        let dx = targetX - pet.position.x
        if dx < -1 { pet.xScale = abs(pet.xScale) } else if dx > 1 { pet.xScale = -abs(pet.xScale) }

        // 줍기: 펫이 드롭에 충분히 가까이 갔을 때만 (영역 전환 중엔 금지 → 빨려오던 노드 유실 방지)
        if fetchIdx >= 0, !anyModalOpen, !transitioning {
            let dp = drops[fetchIdx].node.position
            if abs(dp.x - pet.position.x) < 30, abs(dp.y - pet.position.y) < 72 {
                let d = drops[fetchIdx]; drops.remove(at: fetchIdx); collectDropAnimated(d)   // 나한테 빨려옴
            }
        }
    }

    // 비홀더 소환 — 무제한(영구) 버프. 머리 위에 떠서 주변 적을 자동 공격(어둠/헥스)
    func summonBeholder(skill: SkillType) {
        beholderSkill = skill
        if beholderNode == nil {
            children.filter { $0.name == "beholder_summon" }.forEach { $0.removeFromParent() }   // 잔여 제거
            let frames = GameScene.monsterFrames("beholder", "move")    // 비홀더 전용 스프라이트(있으면)
            let node: SKNode
            if let first = frames.first, frames.count > 1 {             // 적 몹(curse_eye)로는 폴백 안 함 — 혼동 방지
                let sp = SKSpriteNode(texture: first); let s = first.size(); let mx = max(s.width, s.height, 1)
                sp.size = CGSize(width: s.width/mx*62, height: s.height/mx*62)   // 최대변 62px(잘 보이게)
                sp.run(.repeatForever(.animate(with: frames, timePerFrame: 0.12, resize: false, restore: false)))
                node = sp
            } else { let l = SKLabelNode(text: "👁️"); l.fontSize = 34; l.verticalAlignmentMode = .center; node = l }   // 눈 이모지 소환수
            node.name = "beholder_summon"; node.zPosition = 6
            node.position = CGPoint(x: player.position.x, y: player.position.y + 44)
            addChild(node); beholderNode = node
            node.alpha = 0; node.run(.fadeIn(withDuration: 0.3))
        }
        addBuff(key: "beholder", icon: "👁️", name: "비홀더", duration: 0)   // 0=무제한
        beholderCD = 0.6
    }
    // 버프 추가/갱신 (duration<=0 = 무제한)
    func addBuff(key: String, icon: String, name: String, duration: CGFloat, dmgPct: Double = 0, defPct: Double = 0) {
        if let i = buffs.firstIndex(where: { $0.key == key }) { buffs[i].remain = duration; buffs[i].permanent = duration <= 0 }
        else { buffs.append((key, icon, name, duration, duration <= 0, dmgPct, defPct)) }
    }
    // 우상단 버프창: 타이머 감소·만료 정리 후 표시 (남은 초, 무제한은 시간 없음)
    func updateBuffHUD(_ dt: CGFloat) {
        for i in buffs.indices where !buffs[i].permanent { buffs[i].remain -= dt }
        buffs.removeAll { !$0.permanent && $0.remain <= 0 }
        if beholderNode == nil { buffs.removeAll { $0.key == "beholder" } }   // 소환수 없으면 비홀더 버프 제거
        buffHUD?.removeFromParent()
        guard !buffs.isEmpty else { buffHUD = nil; return }
        let node = SKNode(); node.zPosition = 52
        var yy = viewH/2 - 26
        for b in buffs {
            let txt = b.permanent ? "\(b.icon) \(b.name)" : "\(b.icon) \(b.name)  \(Int(ceil(b.remain)))s"
            let bg = SKSpriteNode(color: SKColor(white:0.05,alpha:0.66), size: CGSize(width: 122, height: 22))
            bg.position = CGPoint(x: viewW/2 - 67, y: yy); bg.name = "buffkill:\(b.key)"; node.addChild(bg)
            let l = SKLabelNode(text: txt); l.fontSize = 12; l.fontColor = SKColor(red:0.8,green:0.95,blue:0.7,alpha:1)
            l.horizontalAlignmentMode = .left; l.verticalAlignmentMode = .center; l.position = CGPoint(x: viewW/2 - 122, y: yy)
            l.name = "buffkill:\(b.key)"; node.addChild(l)
            yy -= 25
        }
        styleLabels(node); hudLayer.addChild(node); buffHUD = node
    }
    // 버프 즉시 해제 (우클릭). 비홀더는 소환수도 함께 제거.
    func removeBuff(key: String) {
        guard buffs.contains(where: { $0.key == key }) else { return }
        buffs.removeAll { $0.key == key }
        if key == "beholder" {
            beholderNode?.removeAllActions(); beholderNode?.removeFromParent(); beholderNode = nil; beholderSkill = nil
        }
        updateBuffHUD(0)
    }
    func updateBeholder(_ dt: CGFloat) {
        guard let eye = beholderNode else { return }
        // 무제한 — 만료 없음
        // 머리 위 둥실 추적
        beholderBob += dt * 3
        let tx = player.position.x - playerFacing * 26, ty = player.position.y + 46 + sin(beholderBob) * 6
        eye.position = CGPoint(x: eye.position.x + (tx - eye.position.x) * min(1, dt*7),
                               y: eye.position.y + (ty - eye.position.y) * min(1, dt*7))
        // 자동 공격
        if beholderCD > 0 { beholderCD -= dt; return }
        guard !worldPaused, let sk = beholderSkill else { return }
        let bp = eye.position
        if let target = monsters.filter({ abs($0.node.position.x - bp.x) < sk.range && abs($0.node.position.y - bp.y) < 200 })
            .min(by: { abs($0.node.position.x - bp.x) < abs($1.node.position.x - bp.x) }) {
            beholderCD = 1.4
            spawnSkillSprite("hex", at: target.node.position, scale: 1.3, dur: 0.5)
            dealDamage(to: target, skillPercent: skillPercentScaled(sk), missScale: 0.5)
        }
    }

    // 지속 스킬 존 시작. channel=true면 플레이어 추적·키 떼면 종료(최대 3초), false면 정지 2초.
    static let channelOffset: CGFloat = 95     // 채널 스킬이 캐릭터 앞쪽으로 떨어진 거리
    func startSkillZone(_ st: SkillType, channel: Bool) {
        let set = skillSet(st.emoji)
        let facing = playerFacing
        let footY = player.position.y - playerHalfH
        let cx = channel ? player.position.x + facing * GameScene.channelOffset : player.position.x + facing * st.range * 0.5
        let nodeY = channel ? player.position.y - playerHalfH + 12 : player.position.y + 44   // 채널=발에서 나가듯 낮게
        let node = SKNode(); node.position = CGPoint(x: cx, y: nodeY); node.zPosition = 11
        if channel { node.xScale = facing > 0 ? -1 : 1 }     // 보는 방향으로(원본 art 왼쪽향)
        let frames = GameScene.skillFXFrames(set)
        if frames.count > 1 {
            let sp = SKSpriteNode(texture: frames[0]); sp.setScale(channel ? 3.5 : 2.4)   // 채널은 훨씬 크게
            sp.run(.repeatForever(.animate(with: frames, timePerFrame: 0.07, resize: false, restore: false)))
            node.addChild(sp)
        }
        node.alpha = 0; node.run(.fadeIn(withDuration: 0.15))
        worldLayer.addChild(node)
        skillZones.append(SkillZone(node: node, x: cx, footY: footY, range: st.range, hh: st.hitHalfHeight,
                                    remain: channel ? 3.0 : 2.0, tick: 0, st: st, follows: channel, held: channel))
    }
    func updateSkillZones(_ dt: CGFloat) {
        guard !worldPaused, !skillZones.isEmpty else { return }
        let footY = player.position.y - playerHalfH
        var i = 0
        while i < skillZones.count {
            if skillZones[i].follows {                       // 채널: 플레이어 앞쪽 추적 + 방향 따라 뒤집힘
                let f = playerFacing
                let nx = player.position.x + f * GameScene.channelOffset
                skillZones[i].x = nx; skillZones[i].footY = footY
                skillZones[i].node.position = CGPoint(x: nx, y: player.position.y - playerHalfH + 12)   // 발 높이
                skillZones[i].node.xScale = f > 0 ? -1 : 1   // 방향 바꾸면 이펙트도 같이 뒤집힘
                if !skillZones[i].held { skillZones[i].remain = -1 }   // 키 뗌 → 종료
            }
            skillZones[i].remain -= dt
            skillZones[i].tick -= dt
            if skillZones[i].tick <= 0 && skillZones[i].remain > 0 {
                skillZones[i].tick = 0.3                      // 0.3초마다 지속 타격
                let z = skillZones[i]
                if z.follows {                               // 채널은 MP 지속 소모
                    if mp < 5 { skillZones[i].remain = -1 } else { mp -= 5; updateHUD() }
                }
                let lv = skillLevel(z.st.key)
                let cap = max(1, Int(ceil(Double(z.st.maxTargets ?? 8) * (0.6 + 0.4 * Double(lv) / Double(maxSkillLevel)))))
                let hit = monsters.filter { abs($0.node.position.x - z.x) < z.range && abs($0.node.position.y - z.footY) < z.hh }
                    .sorted { abs($0.node.position.x - z.x) < abs($1.node.position.x - z.x) }.prefix(cap)
                for m in hit { dealDamage(to: m, skillPercent: skillPercentScaled(z.st), missScale: 0.5) }
            }
            if skillZones[i].remain <= 0 {
                let n = skillZones[i].node
                n.removeAllActions(); n.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
                skillZones.remove(at: i)
            } else { i += 1 }
        }
    }

    func pickupNearestDrop() {
        guard !anyModalOpen, !climbing, !transitioning else { return }
        let pp = player.position
        var bestI = -1; var bestD: CGFloat = .greatestFiniteMagnitude
        for (i, d) in drops.enumerated() {
            let dp = d.node.position
            let dx = abs(dp.x - pp.x), dy = abs(dp.y - pp.y)
            if dx < 46, dy < 58, dx + dy < bestD { bestD = dx + dy; bestI = i }
        }
        if bestI >= 0 {
            let d = drops[bestI]; drops.remove(at: bestI); collectDropAnimated(d)   // 나한테 빨려옴
        }
    }

    // 영역 전환: 천천히 어두워졌다 → (이동) → 천천히 밝아짐
    func fadeToArea(_ target: Area, from: Area) {
        transitioning = true                       // 이동 시작 → 조작 잠금
        leftPressed = false; rightPressed = false; upHeld = false; downHeld = false
        guard let overlay = fadeOverlay else {
            loadArea(target, spawnAt: nil); transitioning = false; return
        }
        overlay.removeAllActions()
        overlay.run(.sequence([
            .fadeAlpha(to: 1, duration: 0.45),
            .run { [weak self] in
                guard let self = self else { return }
                self.loadArea(target, spawnAt: nil)
                if let sp = self.arrivalSpawn(in: target, cameFrom: from) {
                    self.player.position = sp; self.updateCamera()
                }
                self.popText("\(target.title) 입장!", at: self.player.position,
                             color: SKColor(red: 0.7, green: 0.5, blue: 1, alpha: 1), size: 22)
            },
            .fadeAlpha(to: 0, duration: 0.55),
            .run { [weak self] in self?.transitioning = false }    // 도착 → 조작 해제
        ]))
    }

    func openShop() {
        guard !anyModalOpen else { return }
        shopOpen = true
        leftPressed = false; rightPressed = false
        shopScroll = 0; panelPos["shop"] = .zero            // NPC로 열어도 중앙·스크롤 초기화
        for id in GameScene.scrollIcons { ensureIcon(id) }
        for id in [GameScene.cubeIconRed, GameScene.cubeIconBlack, GameScene.cubeIconAdd] { ensureIcon(id) }
        for id in GameScene.shopWeaponIDs { ensureIcon(id) }
        buildShopPanel()
    }

    // ── 월드 만들기 ───────────────────────────────────────────
    func addGround() {
        let h: CGFloat = 50
        let ground = SKSpriteNode(color: SKColor(red: 0.36, green: 0.72, blue: 0.36, alpha: 1),
                                  size: CGSize(width: worldW, height: h))
        ground.position = CGPoint(x: worldW / 2, y: h / 2)
        worldLayer.addChild(ground)
        solids.append(CGRect(x: 0, y: 0, width: worldW, height: h))
    }

    func addPlatform(x: CGFloat, y: CGFloat, width: CGFloat) {
        let h: CGFloat = 22
        let p = SKSpriteNode(color: SKColor(red: 0.55, green: 0.40, blue: 0.28, alpha: 1),
                             size: CGSize(width: width, height: h))
        p.position = CGPoint(x: x, y: y)
        worldLayer.addChild(p)
        solids.append(CGRect(x: x - width/2, y: y - h/2, width: width, height: h))
    }

    func addClouds() {
        let clouds: [(CGFloat, CGFloat, CGFloat)] = [
            (120, 450, 46), (560, 560, 40), (1000, 480, 50), (1450, 600, 44),
            (1850, 500, 48), (2200, 540, 42)
        ]
        for (x, y, fs) in clouds {
            let c = SKLabelNode(text: "☁️")
            c.fontSize = fs
            c.position = CGPoint(x: x, y: y)
            c.verticalAlignmentMode = .center
            worldLayer.addChild(c)
        }
    }

    // 캐릭터 = maple_body_pale 부위를 조립한 클래식 도트 프레임(sprites/).
    // 모든 프레임 동일 캔버스·발끝 하단정렬 → 앵커로 발끝을 중심 아래 -playerHalfH(=-22)에 둠(물리/충돌 그대로).
    func addPlayer() {
        loadPlayerFrames()
        let tex = animIdle.first ?? SKTexture()
        let s = tex.size()
        let nodeH = s.height * GameScene.bodyScale     // 고정 배율 → 몸 크기 일정
        let body = SKSpriteNode(texture: tex, size: CGSize(width: s.width * GameScene.bodyScale, height: nodeH))
        body.anchorPoint = CGPoint(x: GameScene.defaultBodyCenterFrac,
                                   y: GameScene.defaultFeetFrac + playerHalfH / nodeH)   // 발끝을 중심 아래 22로
        body.position = CGPoint(x: 360, y: 200)
        body.zPosition = 5
        player = body
        addChild(player)
        currentAnimKey = ""
        playAnim("idle", animIdle, tpf: 0.22, loop: true)   // idle = 상시 숨쉬기 루프
    }

    // ── 프레임 애니메이션 ────────────────────────────────────────
    var animIdle: [SKTexture] = []
    var animWalk: [SKTexture] = []
    var animClimb: [SKTexture] = []
    var animAttack: [SKTexture] = []
    var animAttackVariants: [[SKTexture]] = []   // 무기별 공격 모션 변형들(찌르기/휘두르기) — 칠 때 랜덤
    var currentAtkVariant = 0
    var animJump: [SKTexture] = []
    var animProne: [SKTexture] = []
    var animProneAttack: [SKTexture] = []   // 숙여서 공격(proneStab)
    var proneAttacking = false              // 현재 공격이 숙인 자세 공격인가
    var animStill: [SKTexture] = []
    // 조합별 디코드 텍스처 메모리 캐시 → 같은 외형 재장착 시 네트워크/디스크/디코드 없이 즉시 적용
    struct ComboTex { let idle:[SKTexture]; let walk:[SKTexture]; let climb:[SKTexture]; let jump:[SKTexture]; let prone:[SKTexture]; let proneAttack:[SKTexture]; let attack:[[SKTexture]]; let feet:CGFloat; let center:CGFloat }
    var comboTexCache: [String: ComboTex] = [:]
    var prefetchingKeys: Set<String> = []      // 프리페치 진행 중인 조합(중복 방지)
    let equipPrefetchQueue = DispatchQueue(label: "equip.prefetch", qos: .utility)
    var currentAnimKey = ""
    var attackAnimTimer: CGFloat = 0      // >0이면 공격 모션 재생 중
    var climbMoving = false               // 줄에서 위아래로 움직이는 중인가
    var combatTimer: CGFloat = 0          // >0이면 전투 중(숨쉬기), 0이면 비전투(완전 정지)

    var currentWeaponArt: String? = nil      // 현재 장착 무기의 아트 폴더(없으면 nil)

    // 캐릭터 = a.json(maplestory.io 디자이너 export)을 캐릭터 렌더 API로 서버합성 → 무게중심 정렬한 프레임.
    // 딸기 코스튬 + 클레이모어. 장비 바꾸려면 a.json 수정 후 tools/fetch_char.py + build_char 재실행.
    func loadPlayerFrames() {
        animIdle   = ["player_stand0","player_stand1","player_stand2","player_stand3"].map(GameScene.frameTex)
        animWalk   = ["player_walk0","player_walk1","player_walk2","player_walk3"].map(GameScene.frameTex)
        animClimb  = ["player_climb0","player_climb1"].map(GameScene.frameTex)              // rope 등반 2프레임
        animAttack = ["player_attack0","player_attack1","player_attack2"].map(GameScene.frameTex)  // swingT1 3프레임
        animJump   = ["player_jump0"].map(GameScene.frameTex)
        animProne  = ["player_prone0"].map(GameScene.frameTex)
        animStill  = ["player_stand0"].map(GameScene.frameTex)
    }

    // 장비 조합으로 캐릭터 프레임 합성 — 장착/해제 시마다 호출(레이어 페이퍼돌)
    func rebuildPlayerFrames() {
        let armed = equipped[.weapon] != nil
        currentWeaponArt = armed ? "sword_basic" : nil    // PoC: 모든 무기 → 기본검 아트
        func seq(_ ns: [String]) -> [SKTexture] { ns.map { composedTex($0, armed: armed) } }
        animIdle   = seq(["stand0","stand1","stand2","stand3"])
        animWalk   = seq(["walk0","walk1","walk2","walk3","walk4"])
        animClimb  = seq(["climb0","climb1","climb2"])
        animAttack = seq(["attack0","attack1","attack2","attack3"])
        animJump   = seq(["jump0"])
        animProne  = seq(["prone0"])
        animStill  = seq(["stand0"])
        currentAnimKey = ""                               // 다음 프레임에 재적용
    }

    // base_below + (무기) + base_above 를 z-order로 합쳐 한 프레임 텍스처
    func composedTex(_ frame: String, armed: Bool) -> SKTexture {
        let below = GameScene.charImg("base/\(frame)_below")
        let above = GameScene.charImg("base/\(frame)_above")
        let w = below?.width ?? above?.width ?? 1
        let h = below?.height ?? above?.height ?? 1
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return SKTexture() }
        let r = CGRect(x: 0, y: 0, width: w, height: h)
        if let b = below { ctx.draw(b, in: r) }
        if armed, let art = currentWeaponArt, let wp = GameScene.charImg("items/\(art)/\(frame)") { ctx.draw(wp, in: r) }
        if let a = above { ctx.draw(a, in: r) }
        guard let img = ctx.makeImage() else { return SKTexture() }
        let t = SKTexture(image: NSImage(cgImage: img, size: NSSize(width: w, height: h)))
        t.filteringMode = .nearest
        return t
    }

    // 캐릭터 레이어 PNG 로드 (sprites/char/<rel>.png → CGImage). rel 예: "base/stand0_below", "items/sword_basic/attack2"
    static func charImg(_ rel: String) -> CGImage? {
        let comps = rel.split(separator: "/").map(String.init)
        guard let name = comps.last else { return nil }
        let sub = (["sprites", "char"] + comps.dropLast()).joined(separator: "/")
        var cands: [URL?] = [Bundle.main.url(forResource: name, withExtension: "png", subdirectory: sub)]
        let bn = "JumpQuest_JumpQuest.bundle"
        for base in [Bundle.main.resourceURL, Bundle.main.bundleURL] {
            if let bu = base?.appendingPathComponent(bn), let b = Bundle(url: bu) {
                cands.append(b.url(forResource: name, withExtension: "png", subdirectory: sub))
            }
        }
        cands.append(Bundle.main.resourceURL?.appendingPathComponent("\(sub)/\(name).png"))
        for case let u? in cands where FileManager.default.fileExists(atPath: u.path) {
            if let img = NSImage(contentsOf: u), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) { return cg }
        }
        return nil
    }

    // ── Galmuri 한글 픽셀 폰트 (OFL 1.1, 배포 가능) ─────────────────
    static let uiFont = "Galmuri11-Regular"        // SKLabelNode fontName (PostScript명)
    static var fontsRegistered = false
    static func registerFonts() {
        guard !fontsRegistered else { return }
        fontsRegistered = true
        for name in ["Galmuri11", "Galmuri11-Bold"] {
            if let url = fontURL(name) { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
    }
    // fonts/ 서브폴더에서 .ttf 찾기 (리소스 번들 / .app 둘 다 — frameTex와 동일 패턴)
    static func fontURL(_ name: String) -> URL? {
        let bn = "JumpQuest_JumpQuest.bundle"
        var cands: [URL?] = [Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "fonts")]
        for base in [Bundle.main.resourceURL, Bundle.main.bundleURL] {
            if let bu = base?.appendingPathComponent(bn), let b = Bundle(url: bu) {
                cands.append(b.url(forResource: name, withExtension: "ttf", subdirectory: "fonts"))
            }
        }
        cands.append(Bundle.main.resourceURL?.appendingPathComponent("fonts/\(name).ttf"))
        cands.append(Bundle.main.resourceURL?.appendingPathComponent("\(bn)/fonts/\(name).ttf"))   // .app: 번들 안 fonts/
        cands.append(Bundle.main.bundleURL.appendingPathComponent("\(bn)/fonts/\(name).ttf"))
        for case let u? in cands where FileManager.default.fileExists(atPath: u.path) { return u }
        return nil
    }
    // 노드 트리의 모든 SKLabelNode에 Galmuri 적용 (이모지는 CoreText가 AppleColorEmoji로 자동 대체 — 검증됨)
    func styleLabels(_ node: SKNode) {
        if let l = node as? SKLabelNode, GameScene.fontsRegistered { l.fontName = GameScene.uiFont }
        for c in node.children { styleLabels(c) }
    }

    // 한 프레임 텍스처 로드 (sprites/ 서브폴더; 리소스 번들 / .app 둘 다 대응). 픽셀아트라 nearest.
    static func frameTex(_ name: String) -> SKTexture {
        var cands: [URL?] = [Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "sprites")]
        let bn = "JumpQuest_JumpQuest.bundle"
        for base in [Bundle.main.resourceURL, Bundle.main.bundleURL] {
            if let bu = base?.appendingPathComponent(bn), let b = Bundle(url: bu) {
                cands.append(b.url(forResource: name, withExtension: "png", subdirectory: "sprites"))
            }
        }
        cands.append(Bundle.main.resourceURL?.appendingPathComponent("sprites/\(name).png"))
        for case let u? in cands where FileManager.default.fileExists(atPath: u.path) {
            if let img = NSImage(contentsOf: u) {
                let t = SKTexture(image: img); t.filteringMode = .nearest; return t
            }
        }
        return SKTexture()
    }

    // 몬스터 프레임 한 장. rel = "snail/move0" (몬스터별 디렉터리). 구버전 flat(snail_move0)도 폴백.
    static func monsterTexOpt(_ rel: String) -> SKTexture? {
        let comps = rel.split(separator: "/", maxSplits: 1).map(String.init)
        let sub = comps.count == 2 ? "sprites/monsters/\(comps[0])" : "sprites/monsters"
        let file = comps.count == 2 ? comps[1] : rel
        let bn = "JumpQuest_JumpQuest.bundle"
        var cands: [URL?] = [Bundle.main.url(forResource: file, withExtension: "png", subdirectory: sub)]
        for base in [Bundle.main.resourceURL, Bundle.main.bundleURL] {
            if let bu = base?.appendingPathComponent(bn), let b = Bundle(url: bu) {
                cands.append(b.url(forResource: file, withExtension: "png", subdirectory: sub))
            }
        }
        cands.append(Bundle.main.resourceURL?.appendingPathComponent("\(sub)/\(file).png"))
        if comps.count == 2 {                          // 구버전 flat 폴백: sprites/monsters/snail_move0.png
            let flat = "\(comps[0])_\(file)"
            cands.append(Bundle.main.resourceURL?.appendingPathComponent("sprites/monsters/\(flat).png"))
            for base in [Bundle.main.resourceURL, Bundle.main.bundleURL] {
                if let bu = base?.appendingPathComponent(bn), let b = Bundle(url: bu) {
                    cands.append(b.url(forResource: flat, withExtension: "png", subdirectory: "sprites/monsters"))
                }
            }
        }
        for case let u? in cands where FileManager.default.fileExists(atPath: u.path) {
            if let img = NSImage(contentsOf: u) { let t = SKTexture(image: img); t.filteringMode = .nearest; return t }
        }
        return nil
    }
    // 몬스터 액션 프레임 시퀀스 (sprites/monsters/<set>/<action>0,1,… 존재하는 만큼)
    static func monsterFrames(_ set: String, _ action: String) -> [SKTexture] {
        var out: [SKTexture] = []; var i = 0
        while let t = monsterTexOpt("\(set)/\(action)\(i)") { out.append(t); i += 1; if i > 14 { break } }
        return out
    }

    // 현재와 다른 애니로 전환할 때만 교체(같은 애니 재시작 방지).
    func playAnim(_ key: String, _ frames: [SKTexture], tpf: Double, loop: Bool) {
        guard key != currentAnimKey, let sp = player as? SKSpriteNode, !frames.isEmpty else { return }
        currentAnimKey = key
        sp.removeAction(forKey: "anim")
        if frames.count <= 1 { sp.texture = frames[0]; return }
        let a = SKAction.animate(with: frames, timePerFrame: tpf, resize: false, restore: false)
        sp.run(loop ? .repeatForever(a) : a, withKey: "anim")
    }

    // 한 프레임 정지(애니 멈추고 텍스처 고정) — key로 중복 방지
    func holdFrame(_ key: String, _ tex: SKTexture?) {
        guard currentAnimKey != key, let sp = player as? SKSpriteNode else { return }
        currentAnimKey = key; sp.removeAction(forKey: "anim"); sp.texture = tex
    }

    // 상태 우선순위: 등반 > 공격 > 점프 > 숙이기 > 걷기 > (전투중 숨쉬기 / 비전투 정지)
    func decidePlayerAnim(dt: CGFloat) {
        if attackAnimTimer > 0 { attackAnimTimer -= dt }
        if combatTimer > 0 { combatTimer -= dt }
        if climbing {
            if climbMoving {                       // 위아래 움직일 때만 씰룩
                playAnim("climb", animClimb, tpf: 0.14, loop: true)
            } else {
                holdFrame("climbStill", animClimb.last)   // 정지=마지막 프레임(재이동 시 첫 프레임과 달라 즉시 반응)
            }
        } else if attackAnimTimer > 0 {
            if proneAttacking && !animProneAttack.isEmpty {   // 숙여서 공격(proneStab)
                let tpf = Double(attackDur) / Double(max(1, animProneAttack.count))
                playAnim("pattack", animProneAttack, tpf: tpf, loop: false)
            } else {
                let v = animAttackVariants.indices.contains(currentAtkVariant) ? animAttackVariants[currentAtkVariant] : animAttack
                let tpf = Double(attackDur) / Double(max(1, v.count))   // 모션이 공격 간격을 꽉 채우게(공격속도↑면 자동으로 빨라짐)
                playAnim("attack\(currentAtkVariant)", v, tpf: tpf, loop: false)   // 무기별 랜덤 공격모션
            }
        } else if !onGround {
            playAnim("jump", animJump, tpf: 0.12, loop: false)
        } else if downHeld && rightPressed == leftPressed {
            playAnim("prone", animProne, tpf: 0.2, loop: false)      // ↓ 숙이기
        } else if rightPressed != leftPressed {
            playAnim("walk", animWalk, tpf: 0.1, loop: true)
        } else if combatTimer > 0 {
            playAnim("idle", animIdle, tpf: 0.22, loop: true)        // 전투 중: 숨쉬기
        } else {
            holdFrame("still", animStill.first)                      // 비전투: 완전 정지(차렷, 다리 모음)
        }
    }

    var playerFacing: CGFloat { player.xScale < 0 ? -1 : 1 }

    // 플랫폼/바닥을 순찰 구역(Surface)으로 변환 (스폰·미니맵이 재사용)
    func buildSurfaces() {
        surfaces.removeAll()
        // 실제 솔리드(지면·발판)의 윗면에서만 스폰 — 같은 높이 인접 솔리드는 병합해 자연스러운 발판으로
        let sorted = solids.sorted { $0.maxY != $1.maxY ? $0.maxY < $1.maxY : $0.minX < $1.minX }
        var merged: [(top: CGFloat, x1: CGFloat, x2: CGFloat)] = []
        for r in sorted {
            if var last = merged.last, abs(last.top - r.maxY) < 1, r.minX <= last.x2 + 8 {
                last.x2 = max(last.x2, r.maxX); merged[merged.count - 1] = last     // 인접 → 확장
            } else {
                merged.append((r.maxY, r.minX, r.maxX))
            }
        }
        for m in merged {
            let w = m.x2 - m.x1
            if w < 56 { continue }                                  // 너무 좁은 발판엔 스폰 안 함
            if w > 760 {                                            // 넓은 지면 → 순찰 구역 분할
                for cx in stride(from: m.x1 + 200, through: m.x2 - 200, by: 400) {
                    surfaces.append(Surface(cx: cx, topY: m.top, span: 160))
                }
            } else {
                surfaces.append(Surface(cx: (m.x1 + m.x2) / 2, topY: m.top, span: max(34, w/2 - 18)))
            }
        }
    }

    // 필드 레벨대(20레벨 밴드)에 속한 몬스터만 스폰. 약한(저HP) 몬스터는 흔하게, 강한 건 드물게(1/maxHP 가중).
    func pickMonsterType(fieldIndex: Int) -> MonsterType {
        let lo = FieldCatalog.bandMin(fieldIndex), hi = FieldCatalog.bandMax(fieldIndex)
        let pool = MonsterCatalog.all.filter { let l = $0.level ?? 0; return l >= lo && l <= hi }
        let all = pool.isEmpty ? MonsterCatalog.all : pool
        guard all.count > 1 else { return all.first ?? MonsterCatalog.fallback[0] }
        let weights = all.map { 1.0 / Double(max(1, $0.maxHP)) }
        var r = Double.random(in: 0..<weights.reduce(0, +))
        for (i, w) in weights.enumerated() { r -= w; if r < 0 { return all[i] } }
        return all[0]
    }

    func spawnMonster(on s: Surface, fieldIndex: Int = 0) {
        let type = pickMonsterType(fieldIndex: fieldIndex)
        let node: SKNode
        if let sp = type.sprite {                       // 스프라이트 몬스터(애니)
            let moves = GameScene.monsterFrames(sp, "move")
            let sprite = SKSpriteNode(texture: moves.first ?? GameScene.monsterTexOpt("\(sp)/stand0"))
            // 몹마다 원본 픽셀 크기가 제각각(달팽이~30 vs 드래곤~120) → 높이를 일정 밴드(50~68)로 정규화해
            // 필드별 크기 차이를 줄임. 종횡비는 유지(가로도 같은 배율). 큰 몹은 약간만 더 크게.
            let baseH = max(1, sprite.size.height)
            let targetH = min(68, max(50, baseH * 0.4 + 34))
            let scale = targetH / baseH
            sprite.size = CGSize(width: sprite.size.width * scale, height: sprite.size.height * scale)
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0)   // 발(아래)을 표면에
            if moves.count > 1 {
                sprite.run(.repeatForever(.animate(with: moves, timePerFrame: 0.22, resize: false, restore: false)), withKey: "move")
            }
            node = sprite
        } else {                                         // 이모지 몬스터(기존)
            let label = SKLabelNode(text: type.emoji)
            label.fontSize = 36; label.verticalAlignmentMode = .bottom
            node = label
        }
        node.position = CGPoint(x: s.cx, y: s.topY)
        worldLayer.addChild(node)
        let headY = (node as? SKSpriteNode)?.size.height ?? 36   // 머리 높이(스프라이트 윗변)
        // ── 머리 위 HP 바 (몹 뒤집혀도 좌→우 그대로: 컨테이너를 "lvl"로 역보정) ──
        let barW: CGFloat = max(30, min(54, (node as? SKSpriteNode)?.size.width ?? 40))
        let barC = SKNode(); barC.name = "lvl"; barC.position = CGPoint(x: 0, y: headY + 5); barC.zPosition = 1
        let barBg = SKSpriteNode(color: SKColor(white: 0, alpha: 0.6), size: CGSize(width: barW + 2, height: 7))
        let fill = SKSpriteNode(color: SKColor(red: 0.3, green: 0.92, blue: 0.4, alpha: 1), size: CGSize(width: barW, height: 5))
        fill.anchorPoint = CGPoint(x: 0, y: 0.5); fill.position = CGPoint(x: -barW/2, y: 0)
        barC.addChild(barBg); barC.addChild(fill); node.addChild(barC)
        // ── 이름 + Lv.N (HP 바 위) ──
        if let lv = type.level {
            let labelText = type.name.map { "\($0) Lv.\(lv)" } ?? "Lv.\(lv)"
            let tag = SKLabelNode(text: labelText); tag.fontSize = 10; tag.fontColor = SKColor(white:0.95,alpha:1)
            tag.verticalAlignmentMode = .bottom; tag.horizontalAlignmentMode = .center
            tag.position = CGPoint(x: 0, y: headY + 14); tag.zPosition = 1; tag.name = "lvl"
            styleLabels(tag)                                  // 폰트 먼저 적용 후 실제 글자폭 측정
            let tw = tag.frame.width + 6
            let bg = SKSpriteNode(color: SKColor(white:0,alpha:0.45), size: CGSize(width: tw, height: 13))
            bg.position = CGPoint(x: 0, y: headY + 20); bg.zPosition = 0.9; bg.name = "lvl"
            node.addChild(bg); node.addChild(tag)
        }
        let mon = Monster(node: node, type: type, dir: Bool.random() ? 1 : -1,
                          minX: s.cx - s.span, maxX: s.cx + s.span, baseY: s.topY)
        mon.hpFill = fill; mon.hpBarW = barW
        monsters.append(mon)
    }

    // ── HUD ───────────────────────────────────────────────────
    // HUD는 hudLayer(카메라 자식)에 붙어 화면에 고정. 좌표는 화면중심(0,0) 기준.
    // 하단 상태바 (메이플식): HP/MP/EXP + 레벨 + 아이디. 단축키 안내는 없앰.
    func addHUD() {
        let bottomY = -viewH/2 + 12
        let leftX   = -viewW/2 + 90

        // 하단 UI 전용 바: 불투명이라 게임화면을 완전히 가림(여기엔 게임이 안 보이고 HP/EXP/스킬 UI만).
        // 카메라(updateCamera)가 이 바 높이만큼 위로 양보해 캐릭터가 바에 가리지 않음.
        let bar = SKSpriteNode(color: SKColor(white: 0.07, alpha: 1.0),
                               size: CGSize(width: viewW, height: GameScene.hudBarH))
        bar.position = CGPoint(x: 0, y: -viewH/2 + GameScene.hudBarH/2); bar.zPosition = 44
        hudLayer.addChild(bar)
        let edge = SKSpriteNode(color: SKColor(white: 0.32, alpha: 1), size: CGSize(width: viewW, height: 2))  // 윗 경계선
        edge.position = CGPoint(x: 0, y: -viewH/2 + GameScene.hudBarH); edge.zPosition = 44.1
        hudLayer.addChild(edge)

        levelLabel = SKLabelNode(text: "Lv 1")
        levelLabel.fontSize = 15; levelLabel.fontColor = .white
        levelLabel.horizontalAlignmentMode = .left; levelLabel.zPosition = 51
        levelLabel.position = CGPoint(x: leftX, y: bottomY + 50)
        hudLayer.addChild(levelLabel)

        charLabel = SKLabelNode(text: charID)
        charLabel.fontSize = 14; charLabel.fontColor = SKColor(red: 1, green: 0.95, blue: 0.7, alpha: 1)
        charLabel.horizontalAlignmentMode = .left; charLabel.zPosition = 51
        charLabel.position = CGPoint(x: leftX + 48, y: bottomY + 50)
        hudLayer.addChild(charLabel)

        // 처치/골드는 하단 바 우측으로 (우상단은 버프창 자리)
        goldLabel = SKLabelNode(text: "💰 0"); goldLabel.fontSize = 16; goldLabel.zPosition = 51
        goldLabel.fontColor = SKColor(red: 1, green: 0.82, blue: 0.2, alpha: 1)
        goldLabel.horizontalAlignmentMode = .right
        goldLabel.position = CGPoint(x: viewW/2 - 14, y: bottomY + 50); hudLayer.addChild(goldLabel)
        killsLabel = SKLabelNode(text: "처치 0"); killsLabel.fontSize = 13; killsLabel.zPosition = 51
        killsLabel.fontColor = SKColor(white: 0.7, alpha: 1)
        killsLabel.horizontalAlignmentMode = .right
        killsLabel.position = CGPoint(x: viewW/2 - 14, y: bottomY + 30); hudLayer.addChild(killsLabel)

        hpBarFill  = addBar(icon: "❤️", x: leftX, y: bottomY + 34, color: SKColor(red: 0.95, green: 0.30, blue: 0.30, alpha: 1))
        mpBarFill  = addBar(icon: "💧", x: leftX, y: bottomY + 18, color: SKColor(red: 0.25, green: 0.55, blue: 1.0, alpha: 1))
        expBarFill = addBar(icon: "⭐️", x: leftX, y: bottomY + 2,  color: SKColor(red: 1.0, green: 0.82, blue: 0.2, alpha: 1))

        // 하단 우측: 키설정 버튼 (키 대신 클릭으로 — E와 충돌 방지)
        let kb = SKSpriteNode(color: SKColor(white: 0.15, alpha: 0.85), size: CGSize(width: 96, height: 26))
        kb.position = CGPoint(x: viewW/2 - 58, y: -viewH/2 + 20); kb.zPosition = 50; kb.name = "open_keybinds"
        hudLayer.addChild(kb)
        let kbl = SKLabelNode(text: "⌨️ 키설정"); kbl.fontSize = 13; kbl.fontColor = .white
        kbl.verticalAlignmentMode = .center; kbl.position = kb.position; kbl.zPosition = 51; kbl.name = "open_keybinds"
        hudLayer.addChild(kbl)

        // 데미지 스킨 교체 버튼 (클릭 시 다음 스킨 + 미리보기)
        let ds = SKSpriteNode(color: SKColor(white: 0.15, alpha: 0.85), size: CGSize(width: 96, height: 26))
        ds.position = CGPoint(x: viewW/2 - 158, y: -viewH/2 + 20); ds.zPosition = 50; ds.name = "cycle_dmgskin"
        hudLayer.addChild(ds)
        let dsl = SKLabelNode(text: "🎨 \(GameScene.dmgSkins[dmgSkinIdx % GameScene.dmgSkins.count].name)")
        dsl.fontSize = 13; dsl.fontColor = .white; dsl.verticalAlignmentMode = .center
        dsl.position = ds.position; dsl.zPosition = 51; dsl.name = "dmgskin_label"
        hudLayer.addChild(dsl)
    }

    func addBar(icon: String, x: CGFloat, y: CGFloat, color: SKColor) -> SKSpriteNode {
        let label = SKLabelNode(text: icon); label.fontSize = 14
        label.verticalAlignmentMode = .center; label.zPosition = 51
        label.position = CGPoint(x: x, y: y); hudLayer.addChild(label)
        let bg = SKSpriteNode(color: SKColor(white: 0.3, alpha: 0.35), size: CGSize(width: barWidth, height: 12))
        bg.anchorPoint = CGPoint(x: 0, y: 0.5); bg.position = CGPoint(x: x + 18, y: y)
        bg.zPosition = 51; hudLayer.addChild(bg)
        let fill = SKSpriteNode(color: color, size: CGSize(width: barWidth, height: 12))
        fill.anchorPoint = CGPoint(x: 0, y: 0.5); fill.position = bg.position
        fill.zPosition = 52; hudLayer.addChild(fill); return fill
    }

    // 스킬 슬롯들을 만들어 화면 하단에 배치
    // 스킬 슬롯↔액션 매핑(10칸). skillSlot/skillAction/refreshSkillKeyLabels/addSkills 공용.
    static let skillActions: [GameAction] = [.skill1, .skill2, .skill3, .skill4, .skill5,
                                             .skill6, .skill7, .skill8, .skill9, .skill10]
    static var skillCooldownsEnabled = false   // 임시: 모든 스킬 쿨타임 제거(테스트용 — true로 되돌리면 복구)
    func addSkills() {
        let count = SkillCatalog.all.count
        // 6칸까지는 넉넉히, 그 이상은 압축해 한 줄에(좌측 HP바 끝 ~-52, 우측 골드 ~290 사이)
        let step: CGFloat   = count <= 6 ? 60 : 33
        let isz: CGFloat    = count <= 6 ? 50 : 30
        let iconFS: CGFloat = count <= 6 ? 28 : 16
        let keyFS: CGFloat  = count <= 6 ? 11 : 9
        let rowCenter: CGFloat = count <= 6 ? 110 : 125
        let baseY = -viewH/2 + 44
        var x = rowCenter - CGFloat(max(0, count - 1)) * step / 2
        for type in SkillCatalog.all {
            guard let code = keyCode(forLetter: type.key) else { continue }
            let slot = SkillSlot(type: type, keyCode: code)
            let action: GameAction = GameScene.skillActions.indices.contains(skills.count) ? GameScene.skillActions[skills.count] : .skill1

            let bg = SKSpriteNode(color: SKColor(white: 0.1, alpha: 0.35), size: CGSize(width: isz, height: isz))
            bg.position = CGPoint(x: x, y: baseY); bg.zPosition = 50
            hudLayer.addChild(bg)

            // 나무위키 공식 스킬 아이콘. 비홀더(소환)는 비홀더 아이콘.
            let icon: SKNode
            let iconTex = type.shape == .summon ? GameScene.frameTex("fx/skills/icons/beholder")
                                                : GameScene.frameTex("fx/skills/icons/\(skillSet(type.emoji))")
            if iconTex.size().width > 1 {
                let sp = SKSpriteNode(texture: iconTex); sp.size = CGSize(width: isz - 6, height: isz - 6)
                icon = sp
            } else {
                let l = SKLabelNode(text: type.emoji); l.fontSize = iconFS; l.verticalAlignmentMode = .center
                icon = l
            }
            icon.position = CGPoint(x: x, y: baseY + 2); icon.zPosition = 51
            hudLayer.addChild(icon)

            let keyLabel = SKLabelNode(text: keyName(binds[action] ?? 0))
            keyLabel.fontSize = keyFS; keyLabel.fontColor = .white; keyLabel.zPosition = 51
            keyLabel.horizontalAlignmentMode = .center
            keyLabel.position = CGPoint(x: x, y: baseY - isz/2 - 7)
            hudLayer.addChild(keyLabel)

            let cd = SKLabelNode(text: "")
            cd.fontSize = iconFS * 0.8; cd.fontColor = .white; cd.verticalAlignmentMode = .center
            cd.position = CGPoint(x: x, y: baseY + 2); cd.zPosition = 52; cd.isHidden = true
            hudLayer.addChild(cd)

            slot.icon = icon; slot.cdLabel = cd; slot.keyLabel = keyLabel
            skills.append(slot)
            x += step
        }
    }

    // ── 미니맵 (hudLayer 자식, 우상단) ─────────────────────────
    func addMiniMap() {
        miniMap = SKNode()
        miniMap.zPosition = 60
        miniMap.position = CGPoint(x: -viewW/2 + 12, y: viewH/2 - miniH - 30)   // 좌상단(이름 자리 위로 확보)
        hudLayer.addChild(miniMap)

        let bg = SKShapeNode(rect: CGRect(x: 0, y: 0, width: miniW, height: miniH), cornerRadius: 4)
        bg.fillColor = SKColor(white: 0.05, alpha: 0.55)
        bg.strokeColor = SKColor(white: 1, alpha: 0.35)
        bg.zPosition = -1
        miniMap.addChild(bg)

        let nameLbl = SKLabelNode(text: currentArea.title)   // 미니맵 위 맵 이름
        nameLbl.fontSize = 13; nameLbl.fontColor = .white
        nameLbl.horizontalAlignmentMode = .center; nameLbl.verticalAlignmentMode = .bottom
        nameLbl.position = CGPoint(x: miniW/2, y: miniH + 5); nameLbl.zPosition = 2
        miniMap.addChild(nameLbl)

        for r in solids {   // 정적 지형 윤곽
            let pr = SKShapeNode(rect: CGRect(x: r.minX*miniScale, y: r.minY*miniScale,
                                              width: r.width*miniScale, height: max(2, r.height*miniScale)))
            pr.fillColor = SKColor(red: 0.55, green: 0.40, blue: 0.28, alpha: 0.9)
            pr.strokeColor = .clear
            miniMap.addChild(pr)
        }

        for rope in ropes {   // 밧줄(세로선)
            let h = max(2, (rope.topY - rope.bottomY) * miniScale)
            let rl = SKShapeNode(rect: CGRect(x: rope.x*miniScale - 1, y: rope.bottomY*miniScale, width: 2, height: h))
            rl.fillColor = SKColor(red: 0.92, green: 0.78, blue: 0.35, alpha: 0.95)
            rl.strokeColor = .clear; rl.zPosition = 0.5
            miniMap.addChild(rl)
        }

        miniPlayerDot = SKShapeNode(circleOfRadius: 3)
        miniPlayerDot.fillColor = SKColor(red: 0.2, green: 0.6, blue: 1, alpha: 1)
        miniPlayerDot.strokeColor = .white
        miniPlayerDot.zPosition = 2
        miniMap.addChild(miniPlayerDot)
        styleLabels(miniMap)        // 미니맵 맵 이름 라벨 = Galmuri
    }

    func updateMiniMap() {
        miniPlayerDot.position = CGPoint(x: player.position.x * miniScale, y: player.position.y * miniScale)
        while miniMonsterDots.count < monsters.count {
            let d = SKShapeNode(circleOfRadius: 2)
            d.fillColor = SKColor(red: 1, green: 0.35, blue: 0.35, alpha: 1)
            d.strokeColor = .clear; d.zPosition = 1
            miniMap.addChild(d); miniMonsterDots.append(d)
        }
        for (i, dot) in miniMonsterDots.enumerated() {
            if i < monsters.count {
                let p = monsters[i].node.position
                dot.position = CGPoint(x: p.x*miniScale, y: p.y*miniScale)
                dot.isHidden = false
            } else { dot.isHidden = true }
        }
    }

    func updateHUD() {
        levelLabel.text = "Lv \(level)"
        charLabel.text = charID
        killsLabel.text = "처치 \(kills)"
        goldLabel.text = "💰 \(gold)"
        let expRatio: CGFloat = (level >= LevelTable.maxLevel) ? 1 : clamp01(CGFloat(xp) / CGFloat(xpToNext))
        expBarFill.size = CGSize(width: barWidth * expRatio, height: 12)
        hpBarFill.size  = CGSize(width: barWidth * clamp01(CGFloat(hp) / CGFloat(maxHP)), height: 12)
        mpBarFill.size  = CGSize(width: barWidth * clamp01(mp / maxMP), height: 12)
    }

    func clamp01(_ v: CGFloat) -> CGFloat { max(0, min(1, v)) }

    // 알파벳 키 → macOS 키코드
    func keyCode(forLetter s: String) -> UInt16? {
        let map: [String: UInt16] = ["A":0,"S":1,"D":2,"F":3,"H":4,"G":5,"Z":6,"X":7,
                                     "C":8,"V":9,"B":11,"Q":12,"W":13,"E":14,"R":15,
                                     "Y":16,"T":17]
        return map[s.uppercased()]
    }

    // ── 매 프레임 ─────────────────────────────────────────────
    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 1.0/60.0 : min(CGFloat(currentTime - lastTime), 1.0/30.0)
        lastTime = currentTime
        updateHoverTooltip()      // 인벤/착용창 열려있으면 마우스 올린 아이템 정보 툴팁
        if transitioning { leftPressed = false; rightPressed = false; upHeld = false; downHeld = false }  // 이동 중 조작 잠금

        // 플레이어 이동/중력 (전체화면 모달만 멈춤; 인벤·스탯은 안 멈춤)
        if !worldPaused {
            if climbing, let rope = climbRope {
                // 줄에선 좌우 키로 보는 방향만 바꿈(이동은 X) → 그 방향으로 점프 이탈 가능
                if leftPressed { player.xScale = -1 } else if rightPressed { player.xScale = 1 }
                // 등반 중: 중력 없음, ↑↓로 상하 이동
                let vy: CGFloat = (upHeld ? 1 : 0) - (downHeld ? 1 : 0)
                climbMoving = (vy != 0)            // 움직일 때만 애니
                let minC = rope.bottomY + playerHalfH
                let maxC = rope.topY + playerHalfH
                var newY = player.position.y + vy * climbSpeed * dt
                newY = min(max(newY, minC), maxC)
                player.position = CGPoint(x: rope.x, y: newY)
                velocityY = 0; onGround = false
                if newY >= maxC - 0.5 && upHeld {           // 꼭대기 → 위 발판에 자연스럽게 올라섬
                    releaseClimb()
                    if let plat = solids.filter({ rope.x > $0.minX - 4 && rope.x < $0.maxX + 4 && $0.maxY >= rope.topY - 14 && $0.maxY <= rope.topY + 72 })
                                        .min(by: { abs($0.maxY - rope.topY) < abs($1.maxY - rope.topY) }) {
                        player.position = CGPoint(x: rope.x, y: plat.maxY + playerHalfH)   // 발판 위로 끌어올림
                    } else { player.position.y = maxC }
                    onGround = true; velocityX = 0; velocityY = 0
                } else if newY <= minC + 0.5 && downHeld { releaseClimb(); onGround = true } // 바닥 → 내려섬
            } else {
                // 좌우 이동 — 땅에선 즉시 제어, 공중에선 관성 + 약한 끌림(방향 전환은 X)
                let inputDir: CGFloat = (rightPressed ? 1 : 0) - (leftPressed ? 1 : 0)
                let attacking = attackAnimTimer > 0                      // 공격·스킬 모션 중 → 이동 정지
                if dashTimer > 0 {                                       // 러시(돌진): 공격모션 무시하고 앞으로 밀고 나감
                    dashTimer -= dt
                    velocityX = dashDir * 880
                    player.xScale = dashDir < 0 ? -1 : 1
                } else if onGround {
                    if attacking {
                        velocityX = 0                                    // 땅: 공격 중엔 그 자리에 멈춤(보는 방향 유지)
                    } else {
                        velocityX = inputDir * moveSpeed                 // 즉시 전체 제어
                        if inputDir < 0 { player.xScale = -1 } else if inputDir > 0 { player.xScale = 1 }
                    }
                } else {
                    if !attacking { velocityX += inputDir * airAccel * dt }   // 공중: 공격 중엔 입력 끌림 X(관성만)
                    velocityX = max(-moveSpeed, min(moveSpeed, velocityX))
                }
                var newX = player.position.x + velocityX * dt
                newX = min(max(newX, 20), worldW - 20)

                // 지면 블록 옆벽: 발이 블록 윗면보다 아래면 = 벽 → 통과 불가. 단 낮은 턱(≤stepUp)은 막지 않고 타고 오름.
                // 윗면보다 위(=블록 위에 서있음)면 벽 아님 → 가장자리에선 그냥 떨어짐(발판 끝 추락 정상).
                if newX != player.position.x {     // 모든 영역이 실제 지면블록 사용 → 옆벽 충돌 적용
                    let oldX = player.position.x
                    let feetY = player.position.y - playerHalfH
                    let stepUp: CGFloat = 38                          // 이만큼 낮은 턱은 걸어서 올라감(2*playerHalfH 미만)
                    var stepTop: CGFloat? = nil
                    for b in solids where b.size.height > 40 {        // 키 큰 블록 = 지면
                        guard feetY < b.maxY - 6 else { continue }    // 발이 윗면 위/같음 = 위에 서있음(벽 아님)
                        let hitR = velocityX > 0 && oldX + playerHalfW <= b.minX + 1 && newX + playerHalfW > b.minX
                        let hitL = velocityX < 0 && oldX - playerHalfW >= b.maxX - 1 && newX - playerHalfW < b.maxX
                        guard hitR || hitL else { continue }
                        if onGround && b.maxY - feetY <= stepUp {     // 낮은 턱 → 막지 말고 위로 올림
                            stepTop = max(stepTop ?? b.maxY, b.maxY)
                        } else if hitR {
                            newX = b.minX - playerHalfW; velocityX = 0          // 오른쪽 이동 → 블록 왼면에서 막힘
                        } else {
                            newX = b.maxX + playerHalfW; velocityX = 0          // 왼쪽 이동 → 블록 오른면에서 막힘
                        }
                    }
                    if let st = stepTop { player.position.y = max(player.position.y, st + playerHalfH) }   // 턱 위로 올라섬
                }

                // 중력 + 착지
                velocityY -= gravity * dt
                var newY = player.position.y + velocityY * dt
                let feetOld = player.position.y - playerHalfH
                let feetNew = newY - playerHalfH
                onGround = false
                if velocityY <= 0 {
                    for r in solids where newX > r.minX && newX < r.maxX {
                        let top = r.maxY
                        if feetOld >= top - 1 && feetNew <= top {
                            newY = top + playerHalfH; velocityY = 0; onGround = true; break
                        }
                    }
                }
                player.position = CGPoint(x: newX, y: newY)

                // 밧줄 잡기 (↑ 또는 ↓ 누르고 밧줄과 겹치면)
                if (upHeld || downHeld), let rope = ropeNear(player.position) { startClimb(rope) }
                // 틈으로 추락 시(최하단 발판보다 아래) 스폰으로 리스폰 (안전바닥 대신)
                if player.position.y < 30 {
                    player.position = defaultSpawn(for: currentArea); velocityX = 0; velocityY = 0; onGround = false
                }
            }
            decidePlayerAnim(dt: dt)
        }

        // 몬스터 순찰 (전체화면 모달만 정지)
        if !worldPaused {
            for mon in monsters {
                var x = mon.node.position.x + mon.dir * mon.type.speed * dt
                if x <= mon.minX { x = mon.minX; mon.dir = 1 }
                else if x >= mon.maxX { x = mon.maxX; mon.dir = -1 }
                // 둥둥(bob)은 이모지 몬스터만 — 스프라이트 몬스터는 자기 애니로 표현
                var y = mon.baseY
                if mon.type.sprite == nil {
                    mon.bobPhase += dt * 4
                    y += CGFloat(sin(Double(mon.bobPhase))) * 4
                }
                mon.node.position = CGPoint(x: x, y: y)
                mon.node.xScale = mon.dir < 0 ? 1 : -1   // 메이플 몹 스프라이트는 기본 왼쪽 바라봄 → 가는 방향으로 뒤집기
                mon.node.enumerateChildNodes(withName: "lvl") { n, _ in n.xScale = mon.node.xScale }   // Lv 라벨은 글자 안 뒤집히게 역보정(배열 할당 없이)
            }
        }

        // 타이머들
        if attackCooldown > 0 { attackCooldown -= dt }
        if invuln > 0 { invuln -= dt }

        // 공격키 꾹 누름 → 쿨다운마다 자동 반복 (모달/일시정지/등반 중 제외)
        if attackHeld && !anyModalOpen && !worldPaused && !transitioning { attack() }
        // 착지하면 더블 점프 사용 횟수 리셋
        if onGround { jumpsUsed = 0 }

        // MP 회복
        if mp < maxMP { mp = min(maxMP, mp + mpRegen * dt) }
        mpBarFill.size = CGSize(width: barWidth * clamp01(mp / maxMP), height: 12)

        // 스킬 쿨타임 표시
        for s in skills {
            if s.cooldownLeft > 0 {
                s.cooldownLeft -= dt
                s.icon.alpha = 0.3
                s.cdLabel.isHidden = false
                s.cdLabel.text = String(Int(ceil(s.cooldownLeft)))
            } else {
                s.icon.alpha = 1.0
                s.cdLabel.isHidden = true
            }
        }

        // 몬스터 충돌 피해 (전체화면 모달만 무피해)
        if invuln <= 0 && !worldPaused {
            for mon in monsters where abs(mon.node.position.x - player.position.x) < 32
                                   && abs(mon.node.position.y - player.position.y) < 34 {
                takeDamage(mon.type.touchDamage); break
            }
        }

        // 몬스터 재등장
        if !respawnQueue.isEmpty {
            for i in respawnQueue.indices { respawnQueue[i].time -= dt }
            let regenField = currentArea.fieldIndex ?? 0
            for r in respawnQueue where r.time <= 0 { spawnMonster(on: r.surface, fieldIndex: regenField) }
            respawnQueue.removeAll { $0.time <= 0 }
        }

        // 상호작용 (포털/NPC) — 모니터가 세운 플래그를 1회 소비
        if interactCooldown > 0 { interactCooldown -= dt }
        if dialogueBox != nil && !townNPCList.contains(where: { $0.rect.contains(player.position) }) {
            dialogueBox?.removeFromParent(); dialogueBox = nil   // NPC에서 멀어지면 말풍선 닫기
        }
        if interactPressed { interactPressed = false; tryInteract() }
        if pickupCD > 0 { pickupCD -= dt }
        if (pickupPressed || pickupHeld), pickupCD <= 0 {        // 누른 즉시 + 꾹 누르면 0.1초마다 자동 줍기
            pickupPressed = false; pickupCD = 0.1; pickupNearestDrop()
        }

        // 바닥 전리품: 수명만 깎음(60초). 줍기는 ↑(상호작용) 키로 — 자동 줍기 X.
        if !drops.isEmpty {
            var i = drops.count - 1
            while i >= 0 {
                let d = drops[i]
                if !worldPaused { d.life -= dt }
                if d.life <= 0 {
                    d.node.removeFromParent(); drops.remove(at: i)
                } else if d.life <= 4 {
                    d.node.alpha = sin(d.life * 14) > 0 ? 1.0 : 0.35   // 사라지기 직전 깜빡
                }
                i -= 1
            }
        }

        updatePet(dt)
        updateBeholder(dt)
        updateSkillZones(dt)
        updateBuffHUD(dt)
        updateCamera()
        updateMiniMap()
    }

    // ── 플레이어 행동 ─────────────────────────────────────────
    func jump() {
        if climbing {     // 밧줄에서 점프 이탈: 누른 방향(보던 방향)으로 튀어나감
            releaseClimb()
            velocityY = jumpSpeed; onGround = false
            let d: CGFloat = (rightPressed ? 1 : 0) - (leftPressed ? 1 : 0)
            velocityX = d * moveSpeed
            if d < 0 { player.xScale = -1 } else if d > 0 { player.xScale = 1 }
            jumpsUsed = 1
            return
        }
        // 아래점프: 숙이고(↓) 점프 → 딛고 선 얇은 1방향 발판 아래로 떨어짐. (솔리드 지면 위에선 안 뚫림 → 점프 무효)
        if onGround && downHeld {
            let feetY = player.position.y - playerHalfH
            if let plat = solids.first(where: { $0.size.height <= 40 && abs($0.maxY - feetY) < 8 &&
                                                player.position.x > $0.minX && player.position.x < $0.maxX }) {
                player.position.y = plat.maxY + playerHalfH - 14   // 발판 윗면 아래로 내려 통과
                velocityY = -50; onGround = false; jumpsUsed = 1
            }
            return
        }
        if onGround {
            velocityY = jumpSpeed; onGround = false; jumpsUsed = 1
        } else if jumpsUsed < 2 {          // 공중에서 한 번 더 → 더블 점프(위로 살짝 + 앞으로 도약)
            velocityY = jumpSpeed * 0.82
            let d: CGFloat = (rightPressed ? 1 : 0) - (leftPressed ? 1 : 0)
            let dir: CGFloat = d != 0 ? d : playerFacing      // 누른 방향, 없으면 보던 방향
            velocityX = dir * moveSpeed * 1.15                // 앞으로 살짝 더 도약
            if dir < 0 { player.xScale = -1 } else if dir > 0 { player.xScale = 1 }
            jumpsUsed = 2
        }
    }

    // 공격 모션(준비→스윙 프레임)을 재생시킴. decidePlayerAnim이 attackAnimTimer를 보고 attack 애니를 틈.
    func swingPlayer(_ facing: CGFloat, dur: CGFloat) {
        attackAnimTimer = dur      // 공격 모션 길이 = 공격 간격(애니가 간격을 꽉 채워 끊김 없이 재생)
        attackDur = dur
        combatTimer = 3.5                          // 공격/스킬 → 전투 상태 진입
        if !animAttackVariants.isEmpty {           // 칠 때마다 공격 모션 랜덤(찌르기/휘두르기 등)
            currentAtkVariant = Int.random(in: 0..<animAttackVariants.count)
        }
        currentAnimKey = ""        // 즉시 attack으로 전환·처음부터 재생
    }

    // ── MapleStory 클래식 데미지 수식 ───────────────────────────
    // MAX = (1차스탯×배수 + 2차스탯) × 무기공격 / 100  (직업별 statFactor)
    var attackPower: Int { maxDamage }
    // 한 방 데미지 = [max*MASTERY, max] 사이 랜덤. skillPercent=1.0이 기본공격.
    func rollDamage(skillPercent: Double = 1.0) -> Int {
        let maxD = Double(attackPower) * skillPercent
        let minD = maxD * MASTERY
        return max(1, Int(Double.random(in: minD...maxD).rounded()))
    }

    func attack() {
        guard attackCooldown <= 0, !climbing else { return }   // 줄에 매달려선 공격 불가
        attackCooldown = attackInterval                        // 공격 속도 = 간격(스킬로 빨라질 수 있음)
        let facing: CGFloat = playerFacing
        proneAttacking = downHeld && onGround                  // 숙인 채 공격 → proneStab 모션
        swingPlayer(facing, dur: attackInterval)   // 캐릭터 공격 모션
        spawnSlashFX(facing: facing, at: player.position)   // 슬래시 잔상(오리지널)

        let hit = monsters.filter { mon in
            let ahead = facing * (mon.node.position.x - player.position.x)
            return ahead > -20 && ahead < attackRange && abs(mon.node.position.y - player.position.y) < 70
        }
        for mon in hit { dealDamage(to: mon) }
    }

    // 스킬 사용
    func useSkill(_ slot: SkillSlot) {
        guard slot.cooldownLeft <= 0, !climbing, !transitioning else { return }   // 줄·영역전환 중엔 스킬 불가
        let setName = skillSet(slot.type.emoji)
        if setName == "beholderimpact", beholderNode == nil {        // 비홀더 임팩트 = 비홀더(G) 소환 중에만
            floatText("비홀더(G) 필요!", at: CGPoint(x: player.position.x, y: player.position.y + 40),
                      color: SKColor(red: 1, green: 0.6, blue: 0.6, alpha: 1), size: 16)
            return
        }
        if setName == "cyclone", channelKey != nil { return }        // 피어스 사이클론 채널 중복 방지
        if mp < CGFloat(slot.type.mpCost) {
            popText("MP 부족!", at: CGPoint(x: player.position.x, y: player.position.y + 40),
                    color: SKColor(red: 0.3, green: 0.5, blue: 1, alpha: 1))
            return
        }
        mp -= CGFloat(slot.type.mpCost)
        slot.cooldownLeft = GameScene.skillCooldownsEnabled ? slot.type.cooldown : 0   // 임시: 쿨타임 끔
        let facing = playerFacing
        proneAttacking = false          // 스킬은 일반 모션
        swingPlayer(facing, dur: 0.6)   // 스킬은 좀 더 긴 모션
        if slot.type.name == "러시" { dashTimer = 0.36; dashDir = facing }   // 돌진: 앞으로 더 멀리 밀고 나감
        // ── 지속 스킬: 비홀더 임팩트(정지 2초) / 피어스 사이클론(채널) ──
        if setName == "beholderimpact" {
            startSkillZone(slot.type, channel: false)
            popText(slot.type.name, at: CGPoint(x: player.position.x, y: player.position.y + 62), color: GameScene.potGradeColor(2), size: 20)
            updateHUD(); return
        }
        if setName == "cyclone" {
            channelKey = slot.keyCode
            startSkillZone(slot.type, channel: true)
            popText(slot.type.name + " (채널)", at: CGPoint(x: player.position.x, y: player.position.y + 62), color: SKColor(red:0.7,green:0.6,blue:1,alpha:1), size: 18)
            updateHUD(); return
        }

        let px = player.position.x, py = player.position.y
        let footY = py - playerHalfH    // 발끝 기준 (몬스터 y도 바닥 기준 → 수직 정렬)
        let st = slot.type
        func inFront(_ mon: Monster) -> Bool {
            let ahead = facing * (mon.node.position.x - px)
            return ahead > -10 && ahead < st.range && abs(mon.node.position.y - footY) < st.hitHalfHeight
        }
        func inRadius(_ mon: Monster) -> Bool {      // 플레이어 중심 원형(좌우 양쪽)
            abs(mon.node.position.x - px) < st.range && abs(mon.node.position.y - footY) < st.hitHalfHeight
        }

        var targets: [Monster]
        switch st.shape {
        case .beam, .area: targets = monsters.filter(inFront)     // 일직선/범위의 앞쪽 모든 적
        case .nova:        targets = monsters.filter(inRadius)    // 주위 원형 모든 적
        case .strike:
            targets = monsters.filter(inFront)
                .min(by: { abs($0.node.position.x - px) < abs($1.node.position.x - px) })
                .map { [$0] } ?? []                               // 가장 가까운 1마리만
        case .summon:
            summonBeholder(skill: st)                             // 비홀더 소환 (즉시 타격 없음)
            popText(st.name, at: CGPoint(x: px, y: py + 62), color: SKColor(red:0.5,green:1,blue:0.6,alpha:1), size: 20)
            updateHUD(); return
        case .buff:                                              // 자기 버프 — 능력치↑
            addBuff(key: st.key, icon: st.emoji, name: st.name, duration: CGFloat(st.buffDur ?? 60), dmgPct: st.buffDmg ?? 0, defPct: st.buffDef ?? 0)
            spawnSkillSprite(skillSet(st.emoji), at: CGPoint(x: px, y: py + 22), scale: 1.5, dur: 0.7)   // 실제 메이플 버프 이펙트(오라 웨폰/아이언 월)
            spawnHitSpark(at: CGPoint(x: px, y: py + 10), crit: true)
            floatText(st.name + " 버프!", at: CGPoint(x: px, y: py + 70), color: SKColor(red:1,green:0.85,blue:0.4,alpha:1), size: 18)
            updateHUD(); return
        }
        // 최대 타격 수 = 스킬별 실제값 × 스킬레벨 스케일(레벨1=60% → 만렙=100%)
        if let baseCap = st.maxTargets {
            let lv = skillLevel(st.key)
            let cap = max(1, Int(ceil(Double(baseCap) * (0.6 + 0.4 * Double(lv) / Double(maxSkillLevel)))))
            if targets.count > cap {
                targets = Array(targets.sorted { abs($0.node.position.x - px) < abs($1.node.position.x - px) }.prefix(cap))
            }
        }
        // 적중한 몬스터들의 중심(이펙트를 몹 위에 꽂기 위해)
        let tc: CGPoint? = targets.isEmpty ? nil :
            CGPoint(x: targets.reduce(0) { $0 + $1.node.position.x } / CGFloat(targets.count),
                    y: targets.reduce(0) { $0 + $1.node.position.y } / CGFloat(targets.count))
        spawnSkillFX(shape: st.shape, emoji: st.emoji, range: st.range, height: st.hitHalfHeight, facing: facing, targetCenter: tc)
        popText(st.name, at: CGPoint(x: px, y: py + 62),
                color: SKColor(red: 1, green: 0.9, blue: 0.3, alpha: 1), size: 20)
        for mon in targets { dealDamage(to: mon, skillPercent: skillPercentScaled(st), missScale: 0.5) }
        updateHUD()
    }

    // 모양별 스킬 이펙트 (월드 좌표 → 월드와 함께 스크롤)
    func spawnSkillFX(shape: SkillShape, emoji: String, range: CGFloat, height: CGFloat, facing: CGFloat, targetCenter: CGPoint? = nil) {
        let p = player.position
        // 나무위키 실제 이펙트 스프라이트만 사용(절차적 글로우/링/스파크 제거)
        let set = skillSet(emoji)
        switch shape {
        case .beam:
            if set == "darkspear" {               // 다크 스피어 = 머리 위에서 생겨 앞으로 더 길게·크게 날아감
                spawnSkillSprite(set, at: CGPoint(x: p.x + facing*14, y: p.y + playerHalfH + 6), scale: 2.4, dur: 0.5,
                                 flipX: facing > 0, fly: CGVector(dx: facing*range*1.6, dy: -28))
            } else {
                spawnSkillSprite(set, at: CGPoint(x: p.x + facing*range*0.55, y: p.y + 10), scale: 1.5, dur: 0.5, flipX: facing > 0)
            }
        case .strike: spawnSkillSprite(set, at: CGPoint(x: p.x + facing*range*0.6,  y: p.y + 14), scale: 2.5, dur: 0.5, flipX: facing > 0)
        case .area:   spawnSkillSprite(set, at: CGPoint(x: p.x + facing*range*0.4,  y: p.y + 10), scale: 1.9, dur: 0.5, flipX: facing > 0)
        case .nova:                                       // 적중한 몬스터 위에 하나의 큰 이펙트(흩뿌리지 않음)
            let c = targetCenter ?? CGPoint(x: p.x + facing*range*0.4, y: p.y - playerHalfH + 18)
            if set == "roar" {                            // 궁니르 디센트 = 몬스터 위로 내리꽂힘(임팩트가 몹에)
                spawnSkillSprite(set, at: CGPoint(x: c.x, y: c.y), scale: 2.0, dur: 0.5, anchorBottom: true)
            } else {                                       // 매직/사이클론 = 몬스터 중심에 큰 폭발
                spawnSkillSprite(set, at: CGPoint(x: c.x, y: c.y + 18), scale: 2.0, dur: 0.5)
            }
        case .summon, .buff: break
        }
    }

    // 스킬 → 픽셀 이펙트 세트(이모지 원소로 매핑). 변형선택자(U+FE0F) 무시 위해 스칼라 값으로 비교.
    func skillSet(_ emoji: String) -> String {
        let v = Set(emoji.unicodeScalars.map { $0.value })
        if v.contains(0x1F531) { return "impale" }   // 🔱 다크 임페일(어둠)
        if v.contains(0x1F4A8) { return "rush" }      // 💨 러시(슬래시)
        if v.contains(0x1F432) { return "roar" }      // 🐲 드래곤 로어(소용돌이)
        if v.contains(0x1F441) { return "hex" }       // 👁 비홀더(헥스)
        if v.contains(0x2694)  { return "rage" }       // ⚔️ 레이지(오라 웨폰)
        if v.contains(0x1F6E1) { return "ironwall" }   // 🛡️ 아이언 윌(아이언 월)
        if v.contains(0x1F52E) { return "darkspear" }      // 🔮 다크 스피어
        if v.contains(0x1F4A0) { return "magiccrash" }     // 💠 매직 크래쉬
        if v.contains(0x1F4A2) { return "beholderimpact" } // 💢 비홀더 임팩트
        if v.contains(0x1F300) { return "cyclone" }        // 🌀 피어스 사이클론
        if v.contains(0x26A1) || v.contains(0x1F329) { return "lightning" }   // ⚡ 🌩
        if v.contains(0x1F4A5) { return "darkbolt" }                          // 💥
        if v.contains(0x1F31F) || v.contains(0x2728) || v.contains(0x1F525) { return "firebomb" }   // 🌟 ✨ 🔥
        return "spark"
    }
    static var skillFXCache: [String: [SKTexture]] = [:]
    static func skillFXFrames(_ set: String) -> [SKTexture] {
        if let c = skillFXCache[set] { return c }
        var out: [SKTexture] = []; var i = 0
        while i <= 40 { let t = frameTex("fx/skills/\(set)/\(i)"); if t.size().width <= 1 { break }; out.append(t); i += 1 }
        skillFXCache[set] = out
        return out
    }
    func spawnSkillSprite(_ set: String, at pos: CGPoint, scale: CGFloat, dur: Double, flipX: Bool = false, anchorBottom: Bool = false, fly: CGVector? = nil) {
        let frames = GameScene.skillFXFrames(set)
        guard frames.count > 1 else { return }     // 프레임 없으면 절차적만(폴백)
        let sp = SKSpriteNode(texture: frames[0]); sp.setScale(scale)
        if flipX { sp.xScale = -scale }            // 바라보는 방향으로(가로형 이펙트 좌우 뒤집기)
        if anchorBottom { sp.anchorPoint = CGPoint(x: 0.5, y: 0) }   // 내리꽂힘: 임팩트(아래)가 spawn 지점에
        sp.position = pos; sp.zPosition = 11
        worldLayer.addChild(sp)
        if let v = fly {                           // 투사체: 프레임 반복 재생하며 앞으로 날아감
            sp.run(.group([.repeatForever(.animate(with: frames, timePerFrame: 0.06, resize: false, restore: false)),
                           .sequence([.moveBy(x: v.dx, y: v.dy, duration: dur), .removeFromParent()])]))
        } else {
            sp.run(.sequence([.animate(with: frames, timePerFrame: dur/Double(frames.count), resize: false, restore: false),
                              .removeFromParent()]))
        }
    }

    // ── 절차적 전투 이펙트 (SpriteKit 도형/파티클, 100% 오리지널·배포 가능) ──
    // 기본 공격 슬래시 잔상 (검 휘두르는 호)
    func spawnSlashFX(facing: CGFloat, at pos: CGPoint) {
        let arc = CGMutablePath()
        arc.addArc(center: .zero, radius: 38, startAngle: -0.95, endAngle: 0.95, clockwise: false)
        let slash = SKShapeNode(path: arc)
        slash.strokeColor = SKColor(red: 0.82, green: 0.96, blue: 1.0, alpha: 0.95)
        slash.lineWidth = 7; slash.lineCap = .round; slash.glowWidth = 4
        slash.fillColor = .clear; slash.blendMode = .add
        let c = SKNode()
        c.position = CGPoint(x: pos.x + facing*26, y: pos.y + 6)
        c.zRotation = facing > 0 ? -0.7 : (CGFloat.pi + 0.7)
        c.zPosition = 9; c.addChild(slash)
        worldLayer.addChild(c)
        c.run(.sequence([.group([SKAction.rotate(byAngle: facing > 0 ? 1.5 : -1.5, duration: 0.14),
                                 SKAction.scale(by: 1.5, duration: 0.14)]),
                         .fadeOut(withDuration: 0.08), .removeFromParent()]))
    }

    // 피격 스파크 (번쩍임 + 사방으로 튀는 입자) — 기본공격·스킬 공용 타격감
    func spawnHitSpark(at pos: CGPoint, crit: Bool) {
        let col = crit ? SKColor(red: 1, green: 0.6, blue: 0.15, alpha: 1)
                       : SKColor(red: 1, green: 0.95, blue: 0.5, alpha: 1)
        let flash = SKShapeNode(circleOfRadius: crit ? 11 : 8)
        flash.fillColor = col; flash.strokeColor = .clear; flash.blendMode = .add
        flash.position = pos; flash.zPosition = 11
        worldLayer.addChild(flash)
        flash.run(.sequence([.group([.scale(to: 2.4, duration: 0.16), .fadeOut(withDuration: 0.18)]), .removeFromParent()]))
        let n = crit ? 9 : 6
        for i in 0..<n {
            let ang = CGFloat(i)/CGFloat(n) * .pi*2 + CGFloat.random(in: -0.3...0.3)
            let dot = SKShapeNode(circleOfRadius: crit ? 3 : 2.2)
            dot.fillColor = col; dot.strokeColor = .clear; dot.blendMode = .add
            dot.position = pos; dot.zPosition = 11
            worldLayer.addChild(dot)
            let dist = CGFloat.random(in: 20...38)
            dot.run(.sequence([.group([.moveBy(x: cos(ang)*dist, y: sin(ang)*dist, duration: 0.22),
                                       .fadeOut(withDuration: 0.24)]), .removeFromParent()]))
        }
    }

    // 메소 코인 회전 프레임 (rzuf, OpenGameArt CC0 — sprites/fx/coin0..7)
    static let coinFrames: [SKTexture] = {
        var out: [SKTexture] = []; var i = 0
        while i <= 16 {
            let t = GameScene.frameTex("fx/coin\(i)")
            if t.size().width <= 1 { break }
            t.filteringMode = .linear; out.append(t); i += 1
        }
        return out
    }()

    // ── 데미지 스킨 (메이플식: 외곽선+팝 애니메이션, 교체 가능) ──
    var dmgSkinIdx = 0
    static let dmgSkins: [DmgSkin] = [
        DmgSkin(name: "클래식", normal: SKColor(red:1,green:0.95,blue:0.45,alpha:1), crit: SKColor(red:1,green:0.55,blue:0.12,alpha:1), outline: SKColor(red:0.22,green:0.10,blue:0.0,alpha:1), glow: false),
        DmgSkin(name: "네온",   normal: SKColor(red:0.4,green:1.0,blue:0.95,alpha:1), crit: SKColor(red:1,green:0.35,blue:0.95,alpha:1), outline: SKColor(red:0.04,green:0.08,blue:0.22,alpha:1), glow: true),
        DmgSkin(name: "캔디",   normal: SKColor(red:1,green:0.78,blue:0.92,alpha:1), crit: SKColor(red:0.72,green:0.4,blue:1.0,alpha:1), outline: SKColor(red:0.45,green:0.10,blue:0.35,alpha:1), glow: false),
        DmgSkin(name: "용암",   normal: SKColor(red:1,green:0.8,blue:0.2,alpha:1),  crit: SKColor(red:1,green:0.28,blue:0.1,alpha:1), outline: SKColor(red:0.28,green:0.0,blue:0.0,alpha:1), glow: true),
    ]
    // 메이플식 데미지 숫자 = 자릿수별 그림자+(글로우)+본체(굵은 픽셀폰트), 좌→우 스태거 바운스 → 전체 상승+페이드
    func popDamage(_ amount: Int, crit: Bool, at pos: CGPoint) {
        let skin = GameScene.dmgSkins[dmgSkinIdx % GameScene.dmgSkins.count]
        let chars = Array("\(amount)") + (crit ? ["!"] : [])
        let size: CGFloat = crit ? 42 : 28       // 더 크게
        let color = crit ? skin.crit : skin.normal
        let dw = size * 0.6
        let total = dw * CGFloat(chars.count)
        func digit(_ s: String, _ c: SKColor) -> SKLabelNode {
            let l = SKLabelNode(text: s)
            if GameScene.fontsRegistered { l.fontName = "Galmuri11-Bold" }
            l.fontSize = size; l.fontColor = c; l.verticalAlignmentMode = .center; l.horizontalAlignmentMode = .center
            return l
        }
        let cont = SKNode()
        cont.position = CGPoint(x: pos.x + CGFloat.random(in: -6...6), y: pos.y + 30)
        cont.zPosition = 12
        func makeDigitGroup(_ s: String) -> SKNode {        // 그림자 + (글로우) + 본체
            let grp = SKNode()
            let sh = digit(s, skin.outline); sh.position = CGPoint(x: 2, y: -2.5); sh.zPosition = -1; grp.addChild(sh)
            if skin.glow { let g = digit(s, color); g.setScale(1.4); g.alpha = 0.4; g.blendMode = .add; g.zPosition = -2; grp.addChild(g) }
            grp.addChild(digit(s, color))
            return grp
        }
        var settle = 0.18
        if crit {                                            // 크리: 자릿수별 좌→우 스태거 바운스(화려함)
            for (i, ch) in chars.enumerated() {
                let grp = makeDigitGroup(String(ch))
                grp.position = CGPoint(x: -total/2 + dw*(CGFloat(i)+0.5), y: 0); cont.addChild(grp)
                grp.setScale(0.1)
                grp.run(.sequence([.wait(forDuration: Double(i) * 0.05),
                                   .scale(to: 1.45, duration: 0.07), .scale(to: 1.0, duration: 0.08)]))
            }
            settle = 0.15 + Double(chars.count) * 0.05
        } else {                                             // 일반: 숫자 한 덩어리 팝 바운스(노드 적게 — AoE 다수타격 대비)
            let grp = makeDigitGroup("\(amount)"); cont.addChild(grp)
            grp.setScale(0.4)
            grp.run(.sequence([.scale(to: 1.25, duration: 0.08), .scale(to: 1.0, duration: 0.09)]))
        }
        worldLayer.addChild(cont)
        cont.run(.sequence([.wait(forDuration: settle),
                            .group([.moveBy(x: 0, y: crit ? 44 : 32, duration: 0.6),
                                    .sequence([.wait(forDuration: 0.28), .fadeOut(withDuration: 0.4)])]),
                            .removeFromParent()]))
    }
    func cycleDamageSkin() {
        dmgSkinIdx = (dmgSkinIdx + 1) % GameScene.dmgSkins.count
        let skin = GameScene.dmgSkins[dmgSkinIdx]
        popDamage(Int.random(in: 1000...9999), crit: true, at: CGPoint(x: player.position.x, y: player.position.y + 24))   // 미리보기
        if let lbl = hudLayer.childNode(withName: "dmgskin_label") as? SKLabelNode { lbl.text = "🎨 \(skin.name)" }
        popText("데미지 스킨: \(skin.name)", at: CGPoint(x: player.position.x, y: player.position.y + 64),
                color: SKColor(white: 1, alpha: 1), size: 14)
        saveProgress()
    }
    // 스킬 이펙트 색(원소) = 이모지에서 추론 (변형선택자 무시 위해 스칼라 값 비교)
    func skillColor(_ emoji: String) -> SKColor {
        let v = Set(emoji.unicodeScalars.map { $0.value })
        if v.contains(0x1F531) { return SKColor(red:0.62,green:0.35,blue:1,alpha:1) }   // 🔱 어둠 보라
        if v.contains(0x1F4A8) { return SKColor(red:0.82,green:0.9,blue:1,alpha:1) }    // 💨 러시 백색
        if v.contains(0x1F432) { return SKColor(red:1,green:0.4,blue:0.3,alpha:1) }     // 🐲 로어 적색
        if v.contains(0x1F441) { return SKColor(red:0.5,green:1,blue:0.6,alpha:1) }     // 👁 비홀더 녹색
        if v.contains(0x26A1) || v.contains(0x1F329) { return SKColor(red:1,green:0.96,blue:0.5,alpha:1) }    // ⚡ 🌩
        if v.contains(0x1F4A5) || v.contains(0x1F525) { return SKColor(red:1,green:0.55,blue:0.2,alpha:1) }   // 💥 🔥
        if v.contains(0x1F31F) || v.contains(0x2728) { return SKColor(red:1,green:0.92,blue:0.6,alpha:1) }    // 🌟 ✨
        if v.contains(0x2744) || v.contains(0x1F30A) { return SKColor(red:0.5,green:0.85,blue:1,alpha:1) }    // ❄ 🌊
        return SKColor(red:1,green:0.9,blue:0.45,alpha:1)
    }

    let critMult: Double = 1.6       // 크리티컬 배율

    // ── 레벨차 보정 ─────────────────────────────────────────────
    // 몹이 나보다 높으면: 데미지↓ + 미스↑.  내가 몹보다 높으면(과렙): 경험치↓.  몹이 높으면 경험치 약간↑(리스크 보상).
    func levelDamageFactor(_ monLevel: Int?) -> Double {
        guard let ml = monLevel else { return 1.0 }
        let gap = ml - level                       // 몹이 높을수록 +
        return gap <= 0 ? 1.0 : max(0.2, 1.0 - Double(gap) * 0.04)   // 레벨당 -4%, 최저 20%
    }
    func levelMissChance(_ monLevel: Int?) -> Double {
        guard let ml = monLevel else { return 0 }
        let gap = ml - level
        return gap <= 0 ? 0 : min(0.55, Double(gap) * 0.025)         // 레벨당 +2.5% 미스, 최대 55%(스킬은 호출부에서 ×0.5)
    }
    func levelExpFactor(_ monLevel: Int?) -> Double {
        guard let ml = monLevel else { return 1.0 }
        let over = level - ml                       // 내가 높을수록(과렙) +
        if over <= 0 { return min(1.3, 1.0 + Double(-over) * 0.02) }     // 몹이 높음 → 최대 +30%
        if over <= 5 { return 1.0 }                                      // 5렙 차까지는 그대로
        return max(0.1, 1.0 - Double(over - 5) * 0.06)                   // 그 이상 과렙 → 6%씩 감소, 최저 10%
    }

    // 데미지 굴리기 → 미스/크리 판정 → 적용 (attack/skill 공용). missScale: 스킬·비홀더는 0.5(미스 절반)
    func dealDamage(to mon: Monster, skillPercent: Double = 1.0, missScale: Double = 1.0) {
        guard !mon.dying else { return }                                  // 이미 죽는 중인 몹엔 작용 안 함
        if Double.random(in: 0..<1) < levelMissChance(mon.type.level) * missScale {   // 고렙 몹 회피 → MISS
            popText("MISS", at: CGPoint(x: mon.node.position.x, y: mon.node.position.y + 36),
                    color: SKColor(white: 0.85, alpha: 1), size: 15)
            mon.node.run(.sequence([.fadeAlpha(to: 0.7, duration: 0.04), .fadeAlpha(to: 1, duration: 0.04)]), withKey: "flinch")
            return
        }
        let factor = levelDamageFactor(mon.type.level)
        let base = max(1, Int((Double(rollDamage(skillPercent: skillPercent)) * factor).rounded()))
        let crit = Double.random(in: 0..<1) < critChance
        damageMonster(mon, amount: crit ? Int(Double(base) * critMult) : base, crit: crit)
    }

    func updateMonsterHPBar(_ mon: Monster) {
        guard let f = mon.hpFill else { return }
        let ratio = max(0, min(1, CGFloat(mon.hp) / CGFloat(max(1, mon.type.maxHP))))
        f.size.width = mon.hpBarW * ratio
        f.color = ratio > 0.5 ? SKColor(red: 0.3, green: 0.92, blue: 0.4, alpha: 1)     // 초록
                : ratio > 0.25 ? SKColor(red: 1.0, green: 0.82, blue: 0.2, alpha: 1)     // 노랑
                : SKColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1)                     // 빨강
    }

    func damageMonster(_ mon: Monster, amount: Int = 1, crit: Bool = false) {
        mon.hp -= amount
        updateMonsterHPBar(mon)                                                  // 머리 위 HP 바 갱신
        spawnHitSpark(at: CGPoint(x: mon.node.position.x, y: mon.node.position.y + 18), crit: crit)   // 타격 스파크
        popDamage(amount, crit: crit, at: CGPoint(x: mon.node.position.x, y: mon.node.position.y + 36))   // 데미지 스킨
        if mon.hp <= 0 {
            defeat(mon)
        } else {
            mon.node.run(.sequence([.fadeAlpha(to: 0.4, duration: 0.06), .fadeAlpha(to: 1, duration: 0.06)]), withKey: "flinch")
            if let sp = mon.type.sprite, let sprite = mon.node as? SKSpriteNode {   // 피격 프레임 잠깐
                sprite.removeAction(forKey: "move")
                sprite.texture = GameScene.monsterTexOpt("\(sp)/hit0")
                let moves = GameScene.monsterFrames(sp, "move")
                if moves.count > 1 {
                    sprite.run(.sequence([.wait(forDuration: 0.18),
                                          .repeatForever(.animate(with: moves, timePerFrame: 0.22, resize: false, restore: false))]),
                               withKey: "move")
                }
            }
        }
    }

    func defeat(_ mon: Monster) {
        guard let idx = monsters.firstIndex(where: { $0 === mon }) else { return }
        monsters.remove(at: idx)
        mon.dying = true                       // 이후 들어오는 타격/미스 무시(dealDamage 가드)
        let node = mon.node
        node.removeAllActions(); node.alpha = 1   // flinch 잔여 제거 후 죽는 애니 시작

        if let sp = mon.type.sprite, let sprite = node as? SKSpriteNode {   // 죽는 애니(가변 프레임)
            let dies = GameScene.monsterFrames(sp, "die")
            let anim: SKAction = dies.count > 1 ? .animate(with: dies, timePerFrame: 0.12, resize: false, restore: false)
                                                : .wait(forDuration: 0.1)
            sprite.run(.sequence([anim, .fadeOut(withDuration: 0.15), .removeFromParent()]))
        } else {
            node.run(.sequence([
                .group([.scale(to: 1.8, duration: 0.15), .fadeOut(withDuration: 0.2)]),
                .removeFromParent()
            ]))
        }
        let ef = levelExpFactor(mon.type.level)                              // 레벨차 경험치 보정
        let xpGain = max(1, Int((Double(mon.type.xpReward) * ef).rounded()))
        let expColor: SKColor = ef < 0.95 ? SKColor(red: 0.72, green: 0.72, blue: 0.55, alpha: 1)   // 과렙 감소 → 칙칙
                              : ef > 1.05 ? SKColor(red: 0.55, green: 1.0, blue: 0.35, alpha: 1)     // 리스크 보너스 → 선명
                              : SKColor(red: 0.5, green: 1.0, blue: 0.6, alpha: 1)
        let mark = ef < 0.95 ? " ▼" : ef > 1.05 ? " ▲" : ""
        popText("+\(xpGain) EXP\(mark)", at: CGPoint(x: node.position.x, y: node.position.y + 30),
                color: expColor)
        kills += 1
        gainXP(xpGain)
        spawnDrop(.gold(mon.type.gold), at: node.position)   // 골드는 바닥에 떨어짐
        maybeDrop(from: mon, at: node.position)               // 아이템도 (확률) 바닥에
        maybeDropAppearance(at: node.position)                 // 외형(maple) 장비 확률 드랍
        if let s = surfaces.randomElement() { respawnQueue.append((4.5, s)) }  // 리젠 살짝 느리게(표면 없으면 스킵)
        saveProgress()
    }

    func saveProgress() {
        let eq = Dictionary(uniqueKeysWithValues: equipped.map { ($0.key.rawValue, $0.value) })
        let bindsOut = Dictionary(uniqueKeysWithValues: binds.map { ($0.key.rawValue, Int($0.value)) })
        let slotsOut = Dictionary(uniqueKeysWithValues: CharacterRenderer.shared.selection.map { ($0.key.rawValue, $0.value) })
        let cashOut = Dictionary(uniqueKeysWithValues: CharacterRenderer.shared.cashSelection.map { ($0.key.rawValue, $0.value) })
        func serLines(_ d: [Int: [(kind: PotKind, value: Int, pct: Bool)]]) -> [String: String] {
            Dictionary(uniqueKeysWithValues: d.map { (id, lines) in
                (String(id), lines.map { "\(GameScene.potKindName($0.kind)):\($0.value):\($0.pct ? 1 : 0)" }.joined(separator: ";")) })
        }
        let potOut = serLines(potentialLines)
        let addOut = serLines(additionalLines)
        SaveStore.save(SaveData(level: level, xp: xp, kills: kills, inventory: inventory, equipped: eq,
                                unspentAP: unspentAP, gold: gold, binds: bindsOut, area: currentArea.raw, charID: charID,
                                skillLevels: skillLevels, unspentSP: unspentSP, charSlots: slotsOut, cashSlots: cashOut,
                                charOwned: Array(ownedAppearance), damageSkin: dmgSkinIdx,
                                job: job.rawValue, statSTR: statSTR, statINT: statINT, statDEX: statDEX, statLUK: statLUK,
                                enhanceStat: Dictionary(uniqueKeysWithValues: enhanceStat.map { (String($0.key), $0.value) }),
                                upgradeUsed: Dictionary(uniqueKeysWithValues: upgradeUsed.map { (String($0.key), $0.value) }),
                                starForce: Dictionary(uniqueKeysWithValues: starForce.map { (String($0.key), $0.value) }),
                                scrollCounts: scrollCounts, selectedScroll: selectedScroll, cubes: cubes,
                                potentialLines: potOut,
                                potentialGrade: Dictionary(uniqueKeysWithValues: potentialGrade.map { (String($0.key), $0.value) }),
                                redCubes: redCubes, blackCubes: blackCubes, addCubes: addCubes,
                                additionalLines: addOut,
                                additionalGrade: Dictionary(uniqueKeysWithValues: additionalGrade.map { (String($0.key), $0.value) })))
    }
    // PotKind ↔ 문자열/표시
    static func potKindName(_ k: PotKind) -> String { switch k { case .str: return "STR"; case .int: return "INT"; case .dex: return "DEX"; case .luk: return "LUK"; case .atk: return "ATK"; case .def: return "DEF"; case .hp: return "HP"; case .mp: return "MP"; case .allstat: return "ALLSTAT"; case .crit: return "CRIT"; case .dmg: return "DMG" } }   // 저장용(영문 키, 호환성 위해 고정)
    static func potKind(_ s: String) -> PotKind? { switch s { case "STR": return .str; case "INT": return .int; case "DEX": return .dex; case "LUK": return .luk; case "ATK": return .atk; case "DEF": return .def; case "HP": return .hp; case "MP": return .mp; case "ALLSTAT": return .allstat; case "CRIT": return .crit; case "DMG": return .dmg; default: return nil } }
    static func potKindLabel(_ k: PotKind) -> String { switch k { case .str: return "STR"; case .int: return "INT"; case .dex: return "DEX"; case .luk: return "LUK"; case .atk: return "공격력"; case .def: return "방어력"; case .hp: return "HP"; case .mp: return "MP"; case .allstat: return "올스탯"; case .crit: return "크리티컬 확률"; case .dmg: return "데미지" } }   // 화면 표시용(한글)

    // ── 능력치(AP) 시스템 ─────────────────────────────────────
    func totalAPforLevel(_ lv: Int) -> Int { max(0, lv - 1) * apPerLevel }

    // 레벨에 비해 AP가 모자라면 보충 (구버전/고레벨 세이브 대응). 절대 줄이지 않음.
    func reconcileAP() {
        let owed = totalAPforLevel(level) - spentAP
        if owed > unspentAP { unspentAP = owed }
        if unspentAP < 0 { unspentAP = 0 }
    }

    func allocate(_ stat: String) {
        guard unspentAP > 0 else { return }
        switch stat {
        case "str": statSTR += 1
        case "int": statINT += 1
        case "dex": statDEX += 1
        case "luk": statLUK += 1
        default: return
        }
        unspentAP -= 1
        if hp > maxHP { hp = maxHP }
        updateHUD()
        saveProgress()
        refreshStatsPanel()
    }

    func toggleStats() {
        if inventoryOpen { toggleInventory() }   // 상호 배타: 다른 창 닫기
        if shopOpen { toggleShop() }
        statsOpen.toggle()
        if statsOpen {
            leftPressed = false; rightPressed = false
            buildStatsPanel()
        } else {
            statsPanel?.removeFromParent(); statsPanel = nil
        }
    }

    func refreshStatsPanel() {
        guard statsOpen else { return }
        statsPanel?.removeFromParent(); statsPanel = nil
        buildStatsPanel()
    }

    func buildStatsPanel() {
        let panel = SKNode(); panel.zPosition = 100; panel.name = "statsPanel"
        let w: CGFloat = 480, h: CGFloat = 540
        let cx: CGFloat = 0, cy: CGFloat = 0   // hudLayer 기준 화면 중심
        let rowW = w - 30

        panel.position = panelPos["stats"] ?? .zero
        let bg = SKSpriteNode(color: SKColor(white: 0.08, alpha: 0.93), size: CGSize(width: w, height: h))
        bg.position = CGPoint(x: cx, y: cy); bg.name = "statsBG"
        bg.zPosition = -1
        panel.addChild(bg)
        addDragBar(panel, "stats", w: w, h: h, topY: cy + h/2 - 26)

        let title = SKLabelNode(text: "능력치"); title.fontSize = 18; title.fontColor = .white
        title.position = CGPoint(x: cx, y: cy + h/2 - 26); panel.addChild(title)

        let close = SKLabelNode(text: "✕"); close.name = "stats_close"
        close.fontSize = 20; close.fontColor = .white
        close.position = CGPoint(x: cx + w/2 - 22, y: cy + h/2 - 28); panel.addChild(close)

        var sy = cy + h/2 - 56
        let expPct = level >= LevelTable.maxLevel ? "MAX" : "\(Int(Double(xp) / Double(max(1, xpToNext)) * 100))%"
        // 이름 · 직업 · 레벨
        addRow(to: panel, text: "👤 밤티      ⚔️ \(job.label)      Lv.\(level)   처치 \(kills)",
               color: SKColor(red:0.7,green:0.85,blue:1,alpha:1), name: nil, cx: cx, y: sy, width: rowW); sy -= 24
        addRow(to: panel, text: "❤️ HP \(hp) / \(maxHP)        💧 MP \(Int(mp)) / \(Int(maxMP))",
               color: .white, name: nil, cx: cx, y: sy, width: rowW); sy -= 24
        addRow(to: panel, text: "✨ 경험치 \(expPct)",
               color: SKColor(red:0.6,green:1,blue:0.7,alpha:1), name: nil, cx: cx, y: sy, width: rowW); sy -= 26

        addRow(to: panel, text: "남은 AP: \(unspentAP)  (1차 \(job.primaryLabel))",
               color: SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 1), name: nil, cx: cx, y: sy, width: rowW); sy -= 30
        statRow(panel, label: "💪 STR", key: "str", total: totalSTR, detail: "분배 +\(statSTR)", cx: cx, y: &sy, rowW: rowW)
        statRow(panel, label: "🔮 INT", key: "int", total: totalINT, detail: "분배 +\(statINT)", cx: cx, y: &sy, rowW: rowW)
        statRow(panel, label: "🎯 DEX", key: "dex", total: totalDEX, detail: "분배 +\(statDEX)", cx: cx, y: &sy, rowW: rowW)
        statRow(panel, label: "🍀 LUK", key: "luk", total: totalLUK, detail: "분배 +\(statLUK)", cx: cx, y: &sy, rowW: rowW)

        sy -= 4
        let dvTitle = SKLabelNode(text: "— 세부 능력치 —"); dvTitle.fontSize = 12; dvTitle.fontColor = SKColor(white: 0.7, alpha: 1)
        dvTitle.position = CGPoint(x: cx, y: sy); panel.addChild(dvTitle); sy -= 24
        // 2열 세부 능력치
        let derived: [(String, String)] = [
            ("⚔️ 공격력", "\(weaponATK)"),                 ("🔮 마력", "\(weaponATK)"),
            ("⚔️ 데미지", "~\(maxDamage)"),                 ("🎯 크리 확률", "\(Int(critChance*100))%"),
            ("💥 크리 데미지", "135%"),                      ("📈 총 데미지", "+\(Int(potPct(.dmg) + buffDmgPct))%"),
            ("👹 보스 데미지", "+0%"),                       ("🪓 방어력 무시", "+0%"),
            ("🛡️ 물리 방어", "\(bonusDEF)"),               ("🔰 마법 방어", "\(bonusDEF)"),
            ("💨 회피율", "\(Int(avoidChance*100))%"),       ("🏃 이동속도", "100%"),
            ("🦘 점프력", "100%"),
        ]
        let colX = [cx - rowW/2 + 10, cx + 14]
        for (i, d) in derived.enumerated() {
            let l = SKLabelNode(text: "\(d.0)  \(d.1)"); l.fontSize = 12; l.fontColor = .white
            l.horizontalAlignmentMode = .left; l.verticalAlignmentMode = .center
            l.position = CGPoint(x: colX[i % 2], y: sy); panel.addChild(l)
            if i % 2 == 1 { sy -= 22 }
        }
        if derived.count % 2 == 1 { sy -= 22 }

        let hint = SKLabelNode(text: "[ + ] 분배 · C 닫기")
        hint.fontSize = 11; hint.fontColor = SKColor(white: 0.8, alpha: 1)
        hint.position = CGPoint(x: cx, y: cy - h/2 + 12); panel.addChild(hint)

        styleLabels(panel); hudLayer.addChild(panel); statsPanel = panel
    }

    // 능력치 한 줄: 설명 + [+] 버튼 (AP 남아있을 때만 클릭 가능)
    func statRow(_ panel: SKNode, label: String, key: String,
                 total: Int, detail: String, cx: CGFloat, y: inout CGFloat, rowW: CGFloat) {
        let l = SKLabelNode(text: "\(label):  \(total)   (\(detail))")
        l.fontSize = 13; l.fontColor = .white
        l.horizontalAlignmentMode = .left; l.verticalAlignmentMode = .center
        l.position = CGPoint(x: cx - rowW/2 + 10, y: y)
        panel.addChild(l)

        let canSpend = unspentAP > 0
        let plusBG = SKSpriteNode(color: canSpend ? SKColor(red: 0.2, green: 0.55, blue: 0.25, alpha: 1)
                                                  : SKColor(white: 0.3, alpha: 0.4),
                                  size: CGSize(width: 26, height: 22))
        plusBG.position = CGPoint(x: cx + rowW/2 - 16, y: y)
        plusBG.zPosition = -0.5
        if canSpend { plusBG.name = "alloc:\(key)" }
        panel.addChild(plusBG)

        let plus = SKLabelNode(text: "+"); plus.fontSize = 16
        plus.fontColor = canSpend ? .white : SKColor(white: 0.6, alpha: 1)
        plus.verticalAlignmentMode = .center
        plus.position = plusBG.position
        panel.addChild(plus)

        y -= 30
    }

    // ── 스킬창 (SP 분배) ───────────────────────────────────────
    func toggleSkillWindow() {
        if inventoryOpen { toggleInventory() }
        if statsOpen { toggleStats() }
        if shopOpen { toggleShop() }
        skillWindowOpen.toggle()
        if skillWindowOpen {
            leftPressed = false; rightPressed = false
            buildSkillPanel()
        } else {
            skillPanel?.removeFromParent(); skillPanel = nil
        }
    }

    func refreshSkillPanel() {
        guard skillWindowOpen else { return }
        skillPanel?.removeFromParent(); skillPanel = nil
        buildSkillPanel()
    }

    func levelUpSkill(_ key: String) {
        guard unspentSP > 0, skillLevel(key) < maxSkillLevel else { return }
        skillLevels[key] = skillLevel(key) + 1
        unspentSP -= 1
        saveProgress()
        refreshSkillPanel()
    }

    // 스킬 key → 매핑된 액션 (키 라벨용)
    func skillAction(forKey key: String) -> GameAction {
        if let idx = SkillCatalog.all.firstIndex(where: { $0.key == key }), GameScene.skillActions.indices.contains(idx) { return GameScene.skillActions[idx] }
        return .skill1
    }

    func buildSkillPanel() {
        let panel = SKNode(); panel.zPosition = 100; panel.name = "skillPanel"
        let rowStep: CGFloat = 36
        let w: CGFloat = 460, h: CGFloat = CGFloat(SkillCatalog.all.count) * rowStep + 100   // 스킬 수에 맞춰 높이(화면 480 내)
        let cx: CGFloat = 0, cy: CGFloat = 0
        let rowW = w - 30

        let bg = SKSpriteNode(color: SKColor(white: 0.08, alpha: 0.93), size: CGSize(width: w, height: h))
        bg.position = CGPoint(x: cx, y: cy); bg.zPosition = -1; panel.addChild(bg)

        let title = SKLabelNode(text: "스킬"); title.fontSize = 18; title.fontColor = .white
        title.position = CGPoint(x: cx, y: cy + h/2 - 26); panel.addChild(title)

        let close = SKLabelNode(text: "✕"); close.name = "skills_close"
        close.fontSize = 20; close.fontColor = .white
        close.position = CGPoint(x: cx + w/2 - 22, y: cy + h/2 - 28); panel.addChild(close)

        var sy = cy + h/2 - 56
        addRow(to: panel, text: "남은 SP: \(unspentSP)",
               color: SKColor(red: 0.5, green: 0.9, blue: 1, alpha: 1), name: nil, cx: cx, y: sy, width: rowW)
        sy -= 30

        let iconX = cx - rowW/2 + 16
        let textX = cx - rowW/2 + 36
        for st in SkillCatalog.all {
            let lv = skillLevel(st.key)
            let pct = Int((skillPercentScaled(st) * 100).rounded())
            let keyTag = keyName(binds[skillAction(forKey: st.key)] ?? 0)
            // 나무위키 공식 스킬 아이콘. 비홀더(소환)는 비홀더 아이콘.
            let iconTex = st.shape == .summon ? GameScene.frameTex("fx/skills/icons/beholder")
                                              : GameScene.frameTex("fx/skills/icons/\(skillSet(st.emoji))")
            if iconTex.size().width > 1 {
                let sp = SKSpriteNode(texture: iconTex); sp.size = CGSize(width: 26, height: 26)
                sp.position = CGPoint(x: iconX, y: sy); sp.zPosition = 0.5; panel.addChild(sp)
            } else {
                let e = SKLabelNode(text: st.emoji); e.fontSize = 20; e.verticalAlignmentMode = .center
                e.position = CGPoint(x: iconX, y: sy); panel.addChild(e)
            }
            // 1행: 이름 [키]  Lv  피해%
            let title = st.shape == .buff ? "\(st.name) [\(keyTag)]   Lv.\(lv)/\(maxSkillLevel)"
                                          : "\(st.name) [\(keyTag)]   Lv.\(lv)/\(maxSkillLevel)   피해 \(pct)%"
            let l = SKLabelNode(text: title); l.fontSize = 13; l.fontColor = .white
            l.horizontalAlignmentMode = .left; l.verticalAlignmentMode = .center
            l.position = CGPoint(x: textX, y: sy + 7); panel.addChild(l)
            // 2행: 설명(회색)
            if let d = st.desc {
                let dl = SKLabelNode(text: d); dl.fontSize = 9.5; dl.fontColor = SKColor(white: 0.62, alpha: 1)
                dl.horizontalAlignmentMode = .left; dl.verticalAlignmentMode = .center
                dl.position = CGPoint(x: textX, y: sy - 8); panel.addChild(dl)
            }

            let canUp = unspentSP > 0 && lv < maxSkillLevel
            let plusBG = SKSpriteNode(color: canUp ? SKColor(red: 0.2, green: 0.45, blue: 0.7, alpha: 1)
                                                   : SKColor(white: 0.3, alpha: 0.4),
                                      size: CGSize(width: 26, height: 22))
            plusBG.position = CGPoint(x: cx + rowW/2 - 16, y: sy); plusBG.zPosition = -0.5
            if canUp { plusBG.name = "sklv:\(st.key)" }
            panel.addChild(plusBG)
            let plus = SKLabelNode(text: "+"); plus.fontSize = 16
            plus.fontColor = canUp ? .white : SKColor(white: 0.6, alpha: 1)
            plus.verticalAlignmentMode = .center; plus.position = plusBG.position; panel.addChild(plus)
            sy -= rowStep
        }

        let hint = SKLabelNode(text: "[ + ] 눌러 스킬 레벨업 · 레벨업마다 SP 획득 · K 닫기")
        hint.fontSize = 11; hint.fontColor = SKColor(white: 0.8, alpha: 1)
        hint.position = CGPoint(x: cx, y: cy - h/2 + 12); panel.addChild(hint)

        styleLabels(panel); hudLayer.addChild(panel); skillPanel = panel
    }

    // ── 상점 / 골드 ───────────────────────────────────────────
    func sellPrice(_ item: ItemType) -> Int {
        max(1, Int((CGFloat(item.price) * sellFraction).rounded(.down)))
    }

    func toggleShop() {
        if inventoryOpen { toggleInventory() }   // 상호 배타
        if statsOpen     { toggleStats() }
        shopOpen.toggle()
        if shopOpen {
            leftPressed = false; rightPressed = false
            shopScroll = 0; panelPos["shop"] = .zero
            for id in GameScene.scrollIcons { ensureIcon(id) }   // 아이콘 미리 로드
            ensureIcon(GameScene.cubeIconID)
            for id in GameScene.shopWeaponIDs { ensureIcon(id) }  // 무기 아이콘 미리 로드
            buildShopPanel()
        } else {
            shopPanel?.removeFromParent(); shopPanel = nil
        }
    }

    func refreshShopPanel() {
        guard shopOpen else { return }
        shopPanel?.removeFromParent(); shopPanel = nil
        buildShopPanel()
    }

    func buy(_ itemID: String) {
        guard let item = ItemCatalog.item(itemID) else { return }
        guard gold >= item.price else {
            popText("골드 부족!", at: CGPoint(x: player.position.x, y: player.position.y + 40),
                    color: SKColor(red: 1, green: 0.5, blue: 0.2, alpha: 1))
            return
        }
        gold -= item.price
        inventory.append(itemID)              // 가방으로 (자동 장착 안 함)
        popText("\(item.emoji) 구매!", at: CGPoint(x: player.position.x, y: player.position.y + 44),
                color: rarityColor(item.rarity), size: 16)
        updateHUD()
        saveProgress()
        refreshShopPanel()
    }

    func sell(_ itemID: String) {
        guard let item = ItemCatalog.item(itemID) else { return }
        let bag = unequippedInventory()                  // 장착품 보호
        guard bag.contains(itemID), let idx = inventory.firstIndex(of: itemID) else { return }
        inventory.remove(at: idx)
        gold += sellPrice(item)
        popText("💰+\(sellPrice(item))", at: CGPoint(x: player.position.x, y: player.position.y + 44),
                color: SKColor(red: 1, green: 0.84, blue: 0.2, alpha: 1), size: 16)
        updateHUD()
        saveProgress()
        refreshShopPanel()
    }

    // 상점/창에서 아이콘(또는 이모지) + 텍스트 한 줄. 아이콘은 maplestory.io 캐시 사용.
    func addIconRow(to panel: SKNode, iconID: Int?, fallback: String, text: String,
                    color: SKColor, name: String?, cx: CGFloat, y: CGFloat, width: CGFloat) {
        if let name {
            let hit = SKSpriteNode(color: SKColor(white: 1, alpha: 0.06),
                                   size: CGSize(width: width, height: 24))
            hit.position = CGPoint(x: cx, y: y); hit.name = name; hit.zPosition = -0.5
            panel.addChild(hit)
        }
        let iconX = cx - width/2 + 16
        if let id = iconID, let tex = iconCache[id], tex.size().width > 1 {
            let ic = SKSpriteNode(texture: tex); let s = tex.size(); let mx = max(s.width, s.height, 1)
            ic.size = CGSize(width: s.width / mx * 22, height: s.height / mx * 22)
            ic.position = CGPoint(x: iconX, y: y); ic.zPosition = 0.2; panel.addChild(ic)
        } else {
            if let id = iconID { ensureIcon(id) }
            let em = SKLabelNode(text: fallback); em.fontSize = 18
            em.verticalAlignmentMode = .center; em.horizontalAlignmentMode = .center
            em.position = CGPoint(x: iconX, y: y); em.zPosition = 0.2; panel.addChild(em)
        }
        let label = SKLabelNode(text: text); label.fontSize = 13; label.fontColor = color
        label.horizontalAlignmentMode = .left; label.verticalAlignmentMode = .center
        label.position = CGPoint(x: cx - width/2 + 34, y: y); panel.addChild(label)
    }

    func buildShopPanel() {
        let panel = SKNode(); panel.zPosition = 100; panel.name = "shopPanel"
        let w: CGFloat = 470, h: CGFloat = 470
        let rowW = w - 60

        panel.position = panelPos["shop"] ?? .zero          // 드래그 위치 유지
        let bg = SKSpriteNode(color: SKColor(white: 0.08, alpha: 0.93), size: CGSize(width: w, height: h))
        bg.name = "shopBG"; bg.zPosition = -1; panel.addChild(bg)
        addDragBar(panel, "shop", w: w, h: h, topY: h/2 - 26)
        let title = SKLabelNode(text: "상점  💰 \(gold)"); title.fontSize = 18; title.fontColor = .white
        title.position = CGPoint(x: 0, y: h/2 - 26); panel.addChild(title)
        let close = SKLabelNode(text: "✕"); close.name = "shop_close"; close.fontSize = 20; close.fontColor = .white
        close.position = CGPoint(x: w/2 - 22, y: h/2 - 28); panel.addChild(close)

        // ── 행 리스트 구성 (header=섹션제목) ──
        typealias Row = (icon: Int?, fallback: String, text: String, color: SKColor, name: String?, header: Bool)
        var rows: [Row] = []
        func header(_ t: String) { rows.append((nil, "", t, SKColor(white:0.7,alpha:1), nil, true)) }

        header("— 강화 아이템 (주문서·큐브) —")
        for (i, sc) in GameScene.scrollTypes.enumerated() {
            let afford = gold >= sc.price
            let effect = "+\(sc.gain) (\(Int(sc.rate*100))%)" + (sc.failDrop > 0 ? " 실패-\(sc.failDrop)" : "")
            rows.append((GameScene.scrollIcons[i], sc.emoji, "\(sc.name)  \(effect)  보유×\(scrollCounts[i])   💰\(sc.price)",
                         afford ? .white : SKColor(white:0.45,alpha:1), afford ? "shopscroll:\(i)" : nil, false))
        }
        // 큐브 3종 (레드/블랙/에디셔널) — 각각 실제 아이콘
        let cubeRows: [(String, Int, Int, Int, String)] = [   // (이름, 아이콘, 가격, 보유, 액션)
            ("레드 큐브 (메인 잠재)",        GameScene.cubeIconRed,   GameScene.cubePriceRed,   redCubes,   "shopcube:red"),
            ("블랙 큐브 (메인·유지/교체)",   GameScene.cubeIconBlack, GameScene.cubePriceBlack, blackCubes, "shopcube:black"),
            ("에디셔널 큐브 (에디셔널 잠재)", GameScene.cubeIconAdd,   GameScene.cubePriceAdd,   addCubes,   "shopcube:add"),
        ]
        for (nm, icon, price, owned, act) in cubeRows {
            let afford = gold >= price
            rows.append((icon, "🧊", "\(nm)  보유×\(owned)   💰\(price)",
                         afford ? SKColor(red:0.6,green:0.85,blue:1,alpha:1) : SKColor(white:0.45,alpha:1),
                         afford ? act : nil, false))
        }

        header("— 무기 구매 (전사) —")
        for id in GameScene.shopWeaponIDs {
            let price = GameScene.weaponPrice(id), req = GameScene.weaponLevel(id)
            let owned = ownedAppearance.contains(id), afford = gold >= price
            let txt = "\(CharacterRenderer.name(id)) [\(GameScene.weaponTypeName(id))]  Lv.\(req)   💰\(price)" + (owned ? "  ✓보유" : "")
            let color: SKColor = owned ? SKColor(white:0.5,alpha:1) : (afford ? .white : SKColor(white:0.45,alpha:1))
            rows.append((id, "🗡️", txt, color, (!owned && afford) ? "buyweapon:\(id)" : nil, false))
        }

        header("— 물약 구매 —")
        for item in ItemCatalog.all.filter({ $0.isConsumable }).sorted(by: { $0.price < $1.price }) {
            let afford = gold >= item.price
            var heal = [String]()
            if item.healHPamount > 0 { heal.append("HP+\(item.healHPamount)") }
            if item.healMPamount > 0 { heal.append("MP+\(item.healMPamount)") }
            rows.append((item.iconID, item.emoji, "\(item.name)  \(heal.joined(separator: " "))   💰\(item.price)",
                         afford ? rarityColor(item.rarity) : SKColor(white:0.45,alpha:1), afford ? "buy:\(item.id)" : nil, false))
        }

        header("— 판매 (\(Int(sellFraction*100))% 환급) —")
        // 보유 장비(미착용) 판매
        let equippedSet = Set(CharacterRenderer.shared.selection.values)
        let sellableGear = ownedAppearance.subtracting(equippedSet).sorted()
        for id in sellableGear {
            let price = appearanceSellPrice(id)
            let t = GameScene.weaponJob(id) != nil ? GameScene.weaponTypeName(id) : (CharacterRenderer.shared.slotOf(id)?.label ?? "장비")
            rows.append((id, "🗡️", "\(CharacterRenderer.name(id)) [\(t)]  판매 💰\(price)", .white, "sellapp:\(id)", false))
        }
        // 소비/기타 판매
        let counts = unequippedInventory().reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        if sellableGear.isEmpty && counts.isEmpty { rows.append((nil, "", "(팔 물건이 없어요)", .gray, nil, false)) }
        for (id, n) in counts.sorted(by: { $0.key < $1.key }) {
            guard let item = ItemCatalog.item(id) else { continue }
            rows.append((item.iconID, item.emoji, "\(item.name)" + (n > 1 ? " ×\(n)" : "") + "  판매 💰\(sellPrice(item))",
                         rarityColor(item.rarity), "sell:\(id)", false))
        }

        // ── 윈도잉 렌더 (보이는 행만) ──
        let rowH: CGFloat = 26, topY = h/2 - 60, visible = 13
        let maxScroll = max(0, rows.count - visible)
        if shopScroll > maxScroll { shopScroll = maxScroll }; if shopScroll < 0 { shopScroll = 0 }
        for vi in 0..<min(visible, rows.count - shopScroll) {
            let r = rows[shopScroll + vi]; let y = topY - CGFloat(vi) * rowH
            if r.header {
                let lbl = SKLabelNode(text: r.text); lbl.fontSize = 12; lbl.fontColor = r.color
                lbl.position = CGPoint(x: 0, y: y); panel.addChild(lbl)
            } else {
                addIconRow(to: panel, iconID: r.icon, fallback: r.fallback, text: r.text, color: r.color, name: r.name, cx: 0, y: y, width: rowW)
            }
        }
        if maxScroll > 0 {
            let ax = w/2 - 16
            let up = SKLabelNode(text: "▲"); up.name = "shop_scrollup"; up.fontSize = 15
            up.fontColor = shopScroll > 0 ? .white : SKColor(white:0.35,alpha:1)
            up.position = CGPoint(x: ax, y: topY); up.zPosition = 0.3; panel.addChild(up)
            let dn = SKLabelNode(text: "▼"); dn.name = "shop_scrolldn"; dn.fontSize = 15
            dn.fontColor = shopScroll < maxScroll ? .white : SKColor(white:0.35,alpha:1)
            dn.position = CGPoint(x: ax, y: topY - CGFloat(visible - 1) * rowH); dn.zPosition = 0.3; panel.addChild(dn)
            let pos = SKLabelNode(text: "\(shopScroll+1)–\(min(rows.count, shopScroll+visible))/\(rows.count)")
            pos.fontSize = 10; pos.fontColor = SKColor(white:0.7,alpha:1)
            pos.position = CGPoint(x: ax, y: topY - CGFloat(visible) * rowH + 6); pos.zPosition = 0.3; panel.addChild(pos)
        }

        let hint = SKLabelNode(text: "클릭=구매/판매 · 휠·▲▼ 스크롤 · ↑ 닫기")
        hint.fontSize = 11; hint.fontColor = SKColor(white: 0.8, alpha: 1)
        hint.position = CGPoint(x: 0, y: -h/2 + 12); panel.addChild(hint)

        styleLabels(panel); hudLayer.addChild(panel); shopPanel = panel
    }

    // ── 인벤토리 / 장비 시스템 ────────────────────────────────
    func maybeDrop(from mon: Monster, at pos: CGPoint) {
        // 드롭 테이블의 각 항목을 독립 확률로 굴림 (여러 개 동시 드롭 가능)
        var offset: CGFloat = 0
        for entry in mon.type.dropTable {
            guard ItemCatalog.item(entry.id) != nil,
                  CGFloat.random(in: 0...1) < entry.chance else { continue }
            spawnDrop(.item(entry.id), at: CGPoint(x: pos.x + offset, y: pos.y))
            offset += 14   // 여러 개면 살짝 흩어지게
        }
    }

    // 바닥에 전리품을 떨어뜨림 (톡 튀어나와 자리잡고, 줍기 전까지 둥실)
    func spawnDrop(_ kind: DropKind, at pos: CGPoint) {
        let node: SKNode
        switch kind {
        case .gold(let amount):                       // 메소 = 큰 금액이면 돈 주머니(💰), 적으면 회전 코인(CC0)
            let frames = GameScene.coinFrames
            if amount >= 80 {                          // 큰 메소 → 돈 주머니(메이플식 메소 주머니)
                let l = SKLabelNode(text: "💰"); l.fontSize = amount >= 300 ? 30 : 24; l.verticalAlignmentMode = .center
                node = l
            } else if let first = frames.first {       // 적은 메소 → 회전 동전
                let sp = SKSpriteNode(texture: first)
                sp.size = CGSize(width: 24, height: 24)
                if frames.count > 1 {
                    sp.run(.repeatForever(.animate(with: frames, timePerFrame: 0.08, resize: false, restore: false)), withKey: "spin")
                }
                node = sp
            } else {
                let l = SKLabelNode(text: "🪙"); l.fontSize = 20; l.verticalAlignmentMode = .center
                node = l
            }
        case .item(let id):                           // 아이템 = 실제 아이콘(있으면) 아니면 이모지
            if let iid = ItemCatalog.item(id)?.iconID, let tex = iconCache[iid], tex.size().width > 1 {
                let sp = SKSpriteNode(texture: tex); let s = tex.size(); let mx = max(s.width, s.height, 1)
                sp.size = CGSize(width: s.width / mx * 26, height: s.height / mx * 26); node = sp
            } else {
                if let iid = ItemCatalog.item(id)?.iconID { ensureIcon(iid) }
                let l = SKLabelNode(text: ItemCatalog.item(id)?.emoji ?? "❓")
                l.fontSize = 22; l.verticalAlignmentMode = .center; node = l
            }
        }
        node.position = pos; node.zPosition = 6
        worldLayer.addChild(node)
        let dx = CGFloat.random(in: -34...34)
        node.run(.sequence([
            .group([.moveBy(x: dx, y: 22, duration: 0.18), .scale(to: 1.15, duration: 0.18)]),
            .moveBy(x: 0, y: -22, duration: 0.16),
            .repeatForever(.sequence([.moveBy(x: 0, y: 3, duration: 0.5), .moveBy(x: 0, y: -3, duration: 0.5)]))
        ]))
        drops.append(GroundDrop(node: node, kind: kind, life: 60))   // 줍기 전까지 60초 유지
    }

    // 줍기: 아이템이 플레이어에게 빨려오는 모션 후 효과 적용 (호출 전에 drops 배열에서 제거해 둘 것)
    func collectDropAnimated(_ d: GroundDrop) {
        let target = CGPoint(x: player.position.x, y: player.position.y + 4)
        d.node.removeAllActions()
        d.node.zPosition = 7
        d.node.run(.sequence([
            .wait(forDuration: 0.04),
            .group([.move(to: target, duration: 0.2),                       // 나한테 쏙 빨려옴
                    .scale(to: 0.45, duration: 0.2),
                    .fadeAlpha(to: 0.85, duration: 0.2)]),
            .run { [weak self] in self?.collectDrop(d) },                    // 도착하면 효과(골드·아이템·EXP)
            .removeFromParent()
        ]))
    }

    func collectDrop(_ d: GroundDrop) {
        switch d.kind {
        case .gold(let g):
            gold += g
            popText("💰 메소 +\(g)", at: CGPoint(x: player.position.x, y: player.position.y + 44),
                    color: SKColor(red: 1, green: 0.84, blue: 0.2, alpha: 1), size: 15)
        case .item(let id):
            inventory.append(id)
            if let item = ItemCatalog.item(id) {
                popText("\(item.emoji) \(item.name) 획득!", at: CGPoint(x: player.position.x, y: player.position.y + 50),
                        color: rarityColor(item.rarity), size: 15)
            }
            if inventoryOpen { refreshInventoryPanel() }
        }
        updateHUD()
        saveProgress()
    }

    func spawnDropFX(_ item: ItemType, at pos: CGPoint) {
        let l = SKLabelNode(text: item.emoji)
        l.fontSize = 26; l.position = pos; l.zPosition = 9
        worldLayer.addChild(l)
        l.run(.sequence([
            .group([.moveBy(x: 0, y: 24, duration: 0.3), .scale(to: 1.4, duration: 0.3)]),
            .group([.moveBy(x: 0, y: -8, duration: 0.25), .fadeOut(withDuration: 0.5)]),
            .removeFromParent()
        ]))
    }

    // 가방 = 보유 아이템 중 장착 안 된 것 (장착품은 슬롯으로 옮겨감)
    func unequippedInventory() -> [String] {
        var bag = inventory
        for id in equipped.values { if let i = bag.firstIndex(of: id) { bag.remove(at: i) } }
        return bag
    }

    func equip(_ itemID: String) {
        guard let item = ItemCatalog.item(itemID), !item.isConsumable,
              inventory.contains(itemID) else { return }
        equipped[item.slot] = itemID          // 같은 부위 기존 장비는 자동 가방행
        afterEquipChange()
    }

    func unequip(_ slot: EquipSlot) {
        guard equipped[slot] != nil else { return }
        equipped[slot] = nil
        afterEquipChange()
    }

    func afterEquipChange() {
        if hp > maxHP { hp = maxHP }   // HP 보너스 빠지면 클램프
        updateHUD()
        saveProgress()
        refreshInventoryPanel()
    }

    func rarityColor(_ r: Rarity) -> SKColor {
        switch r {
        case .common:    return SKColor(white: 0.92, alpha: 1)
        case .rare:      return SKColor(red: 0.40, green: 0.70, blue: 1.0, alpha: 1)
        case .epic:      return SKColor(red: 0.80, green: 0.50, blue: 1.0, alpha: 1)
        case .legendary: return SKColor(red: 1.0,  green: 0.70, blue: 0.2, alpha: 1)
        }
    }

    // 아이템 한 줄 스탯(인벤 인라인 툴팁)
    func itemShortStat(_ it: ItemType) -> String {
        var s = [String]()
        if it.isConsumable {
            if it.healHPamount > 0 { s.append("❤️+\(it.healHPamount)") }
            if it.healMPamount > 0 { s.append("💧+\(it.healMPamount)") }
        } else {
            if it.attack  != 0 { s.append("⚔️+\(it.attack)") }
            if it.defense != 0 { s.append("🛡️+\(it.defense)") }
            if it.hpBonus != 0 { s.append("❤️+\(it.hpBonus)") }
        }
        return s.joined(separator: " ")
    }

    // 소비아이템(물약) 사용 — HP/MP 회복 후 1개 소모
    func useItem(_ id: String) {
        guard let item = ItemCatalog.item(id), item.isConsumable,
              let idx = inventory.firstIndex(of: id) else { return }
        hp = min(maxHP, hp + item.healHPamount)
        mp = min(maxMP, mp + CGFloat(item.healMPamount))
        inventory.remove(at: idx)
        var msg = "\(item.emoji) "
        if item.healHPamount > 0 { msg += "+\(item.healHPamount)HP " }
        if item.healMPamount > 0 { msg += "+\(item.healMPamount)MP" }
        popText(msg, at: CGPoint(x: player.position.x, y: player.position.y + 44),
                color: SKColor(red: 0.5, green: 1, blue: 0.6, alpha: 1))
        updateHUD(); saveProgress(); refreshInventoryPanel()
    }

    func toggleInventory() {
        if statsOpen { toggleStats() }   // 상호 배타: 다른 창 닫기
        if shopOpen { toggleShop() }
        inventoryOpen.toggle()
        if inventoryOpen {
            leftPressed = false; rightPressed = false   // 모달 열면 이동 멈춤
            invScroll = 0; panelPos["inv"] = .zero
            buildInventoryPanel()
        } else {
            inventoryPanel?.removeFromParent(); inventoryPanel = nil
        }
    }

    func refreshInventoryPanel() {
        guard inventoryOpen else { return }
        inventoryPanel?.removeFromParent(); inventoryPanel = nil
        buildInventoryPanel()
    }

    // 클릭 가능한 한 줄 (배경 스프라이트에 name → 줄 전체가 클릭 영역)
    func addRow(to panel: SKNode, text: String, color: SKColor, name: String?,
                cx: CGFloat, y: CGFloat, width: CGFloat) {
        if let name {
            let hit = SKSpriteNode(color: SKColor(white: 1, alpha: 0.06),
                                   size: CGSize(width: width, height: 22))
            hit.position = CGPoint(x: cx, y: y)
            hit.name = name
            hit.zPosition = -0.5            // 배경(-1)보다 위, 글자(0)보다 아래로 명시
            panel.addChild(hit)
        }
        let label = SKLabelNode(text: text)
        label.fontSize = 14
        label.fontColor = color
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: cx - width/2 + 10, y: y)
        panel.addChild(label)
    }

    // 현재 탭의 아이템 목록 (id, 외형여부, 갯수)
    func inventoryTabItems() -> [(id: String, isAppearance: Bool, count: Int)] {
        switch invTab {
        case 0:   // 장비: 보유 외형 중 **착용 안 한 것만**(착용중인 건 E창에만 — I에서 숨김)
            let equipped = Set(CharacterRenderer.shared.selection.values)
            let order: (Int) -> Int = { id in
                CharacterRenderer.shared.slotOf(id).flatMap { CharSlot.allCases.firstIndex(of: $0) } ?? 99
            }
            return ownedAppearance.subtracting(equipped).sorted { a, b in order(a) != order(b) ? order(a) < order(b) : a < b }
                                   .map { (String($0), true, 1) }
        case 1:   // 소비 (갯수 표시)
            let counts = inventory.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            return counts.filter { ItemCatalog.item($0.key)?.isConsumable == true }
                         .sorted { $0.key < $1.key }.map { (id: $0.key, isAppearance: false, count: $0.value) }
        default:  // 기타 (비소비 — 갯수 표시)
            let counts = inventory.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            return counts.filter { ItemCatalog.item($0.key)?.isConsumable == false }
                         .sorted { $0.key < $1.key }.map { (id: $0.key, isAppearance: false, count: $0.value) }
        }
    }

    func buildInventoryPanel() {
        let panel = SKNode(); panel.zPosition = 100; panel.name = "inventoryPanel"
        let w: CGFloat = 460, h: CGFloat = 420
        panel.position = panelPos["inv"] ?? .zero           // 드래그 위치 유지
        let bg = SKSpriteNode(color: SKColor(white: 0.08, alpha: 0.95), size: CGSize(width: w, height: h))
        bg.zPosition = -1; bg.name = "invBG"; panel.addChild(bg)
        addDragBar(panel, "inv", w: w, h: h, topY: h/2 - 24)
        let title = SKLabelNode(text: "인벤토리"); title.fontSize = 18; title.fontColor = .white
        title.position = CGPoint(x: 0, y: h/2 - 24); panel.addChild(title)
        let close = SKLabelNode(text: "✕"); close.name = "inv_close"; close.fontSize = 20; close.fontColor = .white
        close.position = CGPoint(x: w/2 - 22, y: h/2 - 26); panel.addChild(close)

        // 탭
        for (i, tn) in ["장비", "소비", "기타"].enumerated() {
            let active = invTab == i
            let tb = SKSpriteNode(color: active ? SKColor(red: 0.25, green: 0.5, blue: 0.72, alpha: 1) : SKColor(white: 0.2, alpha: 1),
                                  size: CGSize(width: 84, height: 26))
            tb.position = CGPoint(x: -w/2 + 64 + CGFloat(i) * 92, y: h/2 - 56); tb.name = "invtab:\(i)"; tb.zPosition = 0.1
            panel.addChild(tb)
            let tl = SKLabelNode(text: tn); tl.fontSize = 14; tl.fontColor = active ? .white : SKColor(white: 0.7, alpha: 1)
            tl.verticalAlignmentMode = .center; tl.position = tb.position; tl.zPosition = 0.2; panel.addChild(tl)
        }

        // 아이템 그리드
        let items = inventoryTabItems()
        let cols = 8, cell = 52
        let gridX = -w/2 + 40, gridY = h/2 - 102
        let visibleRows = 5                                   // 한 번에 보이는 행 수
        if items.isEmpty {
            let e = SKLabelNode(text: invTab == 0 ? "(보유 장비 없음 — 몬스터를 잡으세요)" : "(비어 있음)")
            e.fontSize = 13; e.fontColor = .gray; e.position = CGPoint(x: 0, y: 20); panel.addChild(e)
        }
        let totalRows = (items.count + cols - 1) / cols
        let maxScroll = max(0, totalRows - visibleRows)
        if invScroll > maxScroll { invScroll = maxScroll }; if invScroll < 0 { invScroll = 0 }
        for (k, entry) in items.enumerated() {
            let col = k % cols, row = k / cols
            let vrow = row - invScroll
            if vrow < 0 || vrow >= visibleRows { continue }    // 보이는 행만 그림(스크롤 윈도잉)
            let x = gridX + CGFloat(col) * CGFloat(cell), y = gridY - CGFloat(vrow) * CGFloat(cell)
            let isSel = entry.isAppearance && entry.id == String(invSelectedID)
            let box = SKSpriteNode(color: isSel ? SKColor(red:0.32,green:0.5,blue:0.72,alpha:1) : SKColor(white: 0.16, alpha: 1), size: CGSize(width: 44, height: 44))
            box.position = CGPoint(x: x, y: y); box.zPosition = 0.1
            box.name = (entry.isAppearance ? "appitem:" : (invTab == 1 ? "useitem:" : "etcitem:")) + entry.id
            panel.addChild(box)
            // 잠재 등급별 테두리 색(메인/에디셔널 중 높은 등급) — 레어/에픽/유니크/레전더리
            if entry.isAppearance, let id = Int(entry.id) {
                let g = max(potentialGrade[id] ?? -1, additionalGrade[id] ?? -1)
                if g >= 0 {
                    let border = SKShapeNode(rect: CGRect(x: -22, y: -22, width: 44, height: 44), cornerRadius: 5)
                    border.position = box.position; border.strokeColor = GameScene.potGradeColor(g)
                    border.lineWidth = 3; border.fillColor = .clear; border.glowWidth = g >= 2 ? 2.5 : 0
                    border.zPosition = 0.15; panel.addChild(border)
                }
            }
            if entry.isAppearance, let id = Int(entry.id) {
                if let tex = iconCache[id], tex.size().width > 1 {
                    let ic = SKSpriteNode(texture: tex); let s = tex.size(); let mx = max(s.width, s.height, 1)
                    ic.size = CGSize(width: s.width / mx * 36, height: s.height / mx * 36)
                    ic.position = box.position; ic.zPosition = 0.2; panel.addChild(ic)
                } else { ensureIcon(id) }
            } else if let item = ItemCatalog.item(entry.id) {
                if let iid = item.iconID, let tex = iconCache[iid], tex.size().width > 1 {   // 실제 아이템 아이콘
                    let ic = SKSpriteNode(texture: tex); let s = tex.size(); let mx = max(s.width, s.height, 1)
                    ic.size = CGSize(width: s.width / mx * 34, height: s.height / mx * 34)
                    ic.position = box.position; ic.zPosition = 0.2; panel.addChild(ic)
                } else {
                    if let iid = item.iconID { ensureIcon(iid) }
                    let em = SKLabelNode(text: item.emoji); em.fontSize = 26; em.verticalAlignmentMode = .center
                    em.position = box.position; em.zPosition = 0.2; panel.addChild(em)
                }
                let cnt = SKLabelNode(text: "x\(entry.count)")   // 소비/기타: 밑에 갯수 표시(복수 소지)
                cnt.fontSize = 11; cnt.fontColor = .white; cnt.horizontalAlignmentMode = .right; cnt.verticalAlignmentMode = .bottom
                cnt.position = CGPoint(x: x + 21, y: y - 22); cnt.zPosition = 0.3; panel.addChild(cnt)
            }
        }
        // 스크롤 표시(▲▼ 화살표 + 위치)
        if maxScroll > 0 {
            let arrowX = w/2 - 24
            let up = SKLabelNode(text: "▲"); up.name = "inv_scrollup"; up.fontSize = 16
            up.fontColor = invScroll > 0 ? .white : SKColor(white: 0.35, alpha: 1)
            up.position = CGPoint(x: arrowX, y: gridY - 4); up.zPosition = 0.3; panel.addChild(up)
            let dn = SKLabelNode(text: "▼"); dn.name = "inv_scrolldn"; dn.fontSize = 16
            dn.fontColor = invScroll < maxScroll ? .white : SKColor(white: 0.35, alpha: 1)
            dn.position = CGPoint(x: arrowX, y: gridY - CGFloat(visibleRows - 1) * CGFloat(cell) - 4); dn.zPosition = 0.3; panel.addChild(dn)
            let pos = SKLabelNode(text: "\(invScroll + 1)–\(min(totalRows, invScroll + visibleRows))/\(totalRows)줄")
            pos.fontSize = 10; pos.fontColor = SKColor(white: 0.7, alpha: 1)
            pos.position = CGPoint(x: arrowX, y: gridY - CGFloat(visibleRows) * CGFloat(cell) + 14); pos.zPosition = 0.3; panel.addChild(pos)
        }

        // 소비 탭: 큐브·주문서 보유를 아이콘+개수로 표시(아래 줄)
        if invTab == 1 {
            var ix = -w/2 + 40; let iy = -h/2 + 42
            func chip(_ icon: Int, _ fb: String, _ n: Int) {
                let box = SKSpriteNode(color: SKColor(white:0.16,alpha:1), size: CGSize(width: 34, height: 34))
                box.position = CGPoint(x: ix, y: iy); box.zPosition = 0.1; panel.addChild(box)
                if let tex = iconCache[icon], tex.size().width > 1 {
                    let s = tex.size(); let mx = max(s.width,s.height,1); let sp = SKSpriteNode(texture: tex)
                    sp.size = CGSize(width: s.width/mx*28, height: s.height/mx*28); sp.position = box.position; sp.zPosition = 0.2; panel.addChild(sp)
                } else { ensureIcon(icon); let l = SKLabelNode(text: fb); l.fontSize = 20; l.verticalAlignmentMode = .center; l.position = box.position; l.zPosition = 0.2; panel.addChild(l) }
                let c = SKLabelNode(text: "×\(n)"); c.fontSize = 11; c.fontColor = .white; c.horizontalAlignmentMode = .left; c.verticalAlignmentMode = .center
                c.position = CGPoint(x: ix + 20, y: iy); c.zPosition = 0.3; panel.addChild(c)
                ix += 64
            }
            chip(GameScene.cubeIconRed, "🔴", redCubes)       // 레드 큐브(실제 아이콘)
            chip(GameScene.cubeIconBlack, "⬛", blackCubes)   // 블랙 큐브
            chip(GameScene.cubeIconAdd, "🟢", addCubes)       // 에디셔널 큐브(보너스 잠재)
            for (i, sc) in GameScene.scrollTypes.enumerated() { chip(GameScene.scrollIcons[i], sc.emoji, scrollCounts[i]) }
        }
        // 장비탭: 선택한 아이템 + 강화/잠재 버튼 (한번클릭 선택 → 버튼으로 강화. 장착은 더블클릭)
        if invTab == 0, invSelectedID != 0, ownedAppearance.contains(invSelectedID) {
            let nm = CharacterRenderer.name(invSelectedID)
            let sel = SKLabelNode(text: "선택: \(nm)"); sel.fontSize = 12; sel.fontColor = SKColor(red:0.7,green:0.85,blue:1,alpha:1)
            sel.horizontalAlignmentMode = .left; sel.position = CGPoint(x: -w/2 + 20, y: -h/2 + 40); panel.addChild(sel)
            let canEnh = (CharacterRenderer.shared.slotOf(invSelectedID).map { slotEnhanceable($0) } ?? false) && !GameScene.isCash(invSelectedID)
            let bw: CGFloat = 150
            let b = SKSpriteNode(color: canEnh ? SKColor(red:0.2,green:0.5,blue:0.32,alpha:1) : SKColor(white:0.3,alpha:0.5), size: CGSize(width: bw, height: 24))
            b.position = CGPoint(x: w/2 - bw/2 - 16, y: -h/2 + 40); b.zPosition = 0.1; b.name = "inv_enhance"; panel.addChild(b)
            let bl = SKLabelNode(text: "🔼 강화 / 🧊 잠재"); bl.fontSize = 12; bl.fontColor = .white; bl.verticalAlignmentMode = .center
            bl.position = b.position; bl.zPosition = 0.2; bl.name = "inv_enhance"; panel.addChild(bl)
        }
        let hint = SKLabelNode(text: invTab == 0 ? "한번클릭=선택 · 더블클릭=장착 · 선택 후 강화 버튼 · I 닫기"
                                                 : (invTab == 1 ? "클릭 → 사용 · 큐브·주문서는 강화창에서 사용 · I 닫기" : "기타 아이템 · I 닫기"))
        hint.fontSize = 11; hint.fontColor = SKColor(white: 0.8, alpha: 1)
        hint.position = CGPoint(x: 0, y: -h/2 + 12); panel.addChild(hint)
        styleLabels(panel); hudLayer.addChild(panel); inventoryPanel = panel
    }

    // 마우스 휠 → 열린 패널 스크롤
    override func scrollWheel(with event: NSEvent) {
        let step = event.deltaY > 0 ? -1 : (event.deltaY < 0 ? 1 : 0)   // 위로=이전 행, 아래로=다음 행
        if step == 0 { return }
        if inventoryOpen { invScroll += step; refreshInventoryPanel() }        // 내부에서 클램프
        else if shopOpen { shopScroll += step; refreshShopPanel() }
        else if keybindsOpen { keybindsScroll += step; refreshKeybindsPanel() }
    }

    // 창 드래그 이동 (상점·인벤 — 제목 영역 잡고 끌기)
    // 창 드래그 핸들(제목 영역) 추가 — 모든 창 공용
    func addDragBar(_ panel: SKNode, _ key: String, w: CGFloat, h: CGFloat, topY: CGFloat) {
        panelHalf[key] = CGSize(width: w/2, height: h/2)
        let bar = SKSpriteNode(color: .clear, size: CGSize(width: w - 60, height: 32))
        bar.position = CGPoint(x: 0, y: topY); bar.name = "pdrag:\(key)"; bar.zPosition = 0.05; panel.addChild(bar)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let node = dragNode, !dragName.isEmpty else { return }
        let p = hudLayer.convert(event.location(in: self), from: self)
        var pos = CGPoint(x: node.position.x + (p.x - dragLast.x), y: node.position.y + (p.y - dragLast.y))
        // 창 전체(제목·닫기 포함)가 화면 안에 머물게 클램프. 창이 화면보다 크면 그 축은 중앙 고정.
        let half = panelHalf[dragName] ?? CGSize(width: 230, height: 210)
        let mx = max(0, viewW/2 - half.width), my = max(0, viewH/2 - half.height)
        pos.x = min(max(pos.x, -mx), mx); pos.y = min(max(pos.y, -my), my)
        node.position = pos; dragLast = p; panelPos[dragName] = pos
    }
    override func mouseUp(with event: NSEvent) { dragNode = nil; dragName = "" }

    // 마우스 클릭 (인벤토리 열렸을 때만 처리)
    // 우클릭: 버프 아이콘 클릭 시 즉시 해제
    override func rightMouseDown(with event: NSEvent) {
        let p = event.location(in: self)
        for n in nodes(at: p) where (n.name ?? "").hasPrefix("buffkill:") {
            removeBuff(key: String(n.name!.dropFirst(9))); return
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = event.location(in: self)
        if nodes(at: p).contains(where: { $0.name == "open_keybinds" }) { toggleKeybinds(); return }  // HUD 버튼(모달 없어도)
        if nodes(at: p).contains(where: { $0.name == "cycle_dmgskin" }) { cycleDamageSkin(); return }  // 데미지 스킨 교체
        guard anyModalOpen else { return }
        let dbl = event.clickCount >= 2   // 장착/해제는 더블클릭
        // 클릭 지점 노드 중 '행동 가능한' 이름을 찾아 처리 (그리기 순서에 의존 안 함).
        for n in nodes(at: p) {
            guard let name = n.name else { continue }
            if name.hasPrefix("pdrag:") { dragName = String(name.dropFirst(6)); dragNode = n.parent; dragLast = hudLayer.convert(p, from: self); return }   // 창 드래그 시작
            // 인벤토리(탭) / 착용창
            if name == "inv_close" { toggleInventory(); return }
            if name.hasPrefix("invtab:")  { invTab = Int(name.dropFirst(7)) ?? 0; invScroll = 0; refreshInventoryPanel(); hideTooltip(); return }
            if name == "inv_scrollup"     { invScroll -= 1; refreshInventoryPanel(); return }
            if name == "inv_scrolldn"     { invScroll += 1; refreshInventoryPanel(); return }
            if name.hasPrefix("appitem:"), let id = Int(name.dropFirst(8)) {   // 더블=장착 / 한번=선택(아래 강화 버튼)
                if dbl { equipAppearanceItem(id) } else { invSelectedID = id; refreshInventoryPanel() }; return
            }
            if name == "inv_enhance", invSelectedID != 0, let slot = CharacterRenderer.shared.slotOf(invSelectedID), slotEnhanceable(slot), !GameScene.isCash(invSelectedID) { openCubeWindow(forID: invSelectedID); return }   // 강화 가능 부위 + 진짜템만
            if name.hasPrefix("useitem:") { useItem(String(name.dropFirst(8))); return }   // 소비는 클릭 즉시 사용
            if name.hasPrefix("etcitem:") { return }
            if name == "equipped_close"   { toggleEquippedWindow(); return }
            if name == "cyclescroll"      { cycleScroll(); return }
            if name == "cube_close"       { closeCubeWindow(); return }
            if name == "cube_reroll"      { useCubeKind(cubeItemID, .red); return }   // (구 버튼 호환)
            if name == "cube_red"         { useCubeKind(cubeItemID, .red); return }
            if name == "cube_black"       { useCubeKind(cubeItemID, .black); return }
            if name == "cube_add"         { useCubeKind(cubeItemID, .additional); return }
            if name == "cube_apply"       { resolvePending(apply: true); return }    // 블랙 큐브 교체(after)
            if name == "cube_keep"        { resolvePending(apply: false); return }   // 블랙 큐브 유지(before)
            if name == "cube_enh"         { enhanceItem(cubeItemID); return }
            if name == "cube_star"        { starUp(cubeItemID); return }   // ⭐ 별 강화
            if name.hasPrefix("cube_tab:"), let m = Int(name.dropFirst(9)) { cubeMode = m; refreshCubePanel(); return }
            if name == "openCash"         { toggleCash(); return }                                          // 🎀 치장 창 열기
            if name == "cash_close"       { closeCashWindow(); return }
            if name.hasPrefix("cashcyc:") { let p = name.dropFirst(8).split(separator: ":"); if p.count == 2, let slot = CharSlot(rawValue: String(p[0])), let d = Int(p[1]) { cycleCash(slot, d) }; return }
            if name.hasPrefix("cashclr:"), let slot = CharSlot(rawValue: String(name.dropFirst(8))) { clearCash(slot); return }
            if name.hasPrefix("setcash:") { let p = name.dropFirst(8).split(separator: ":"); if p.count == 2, let slot = CharSlot(rawValue: String(p[0])), let cid = Int(p[1]) { setCash(slot, cid) }; return }
            if name.hasPrefix("shopscroll:"), let i = Int(name.dropFirst(11)) { buyScrollAt(i); return }   // 상점 주문서 구매
            if name.hasPrefix("shopcube:") { buyCube(String(name.dropFirst(9))); return }                   // 상점 큐브 구매(레드/블랙/에디셔널)
            if name.hasPrefix("buyweapon:"), let id = Int(name.dropFirst(10)) { buyWeapon(id); return }     // 상점 무기 구매
            if name.hasPrefix("sellapp:"),   let id = Int(name.dropFirst(8))  { sellAppearance(id); return }  // 장비 판매
            if name == "shop_scrollup"    { shopScroll -= 1; refreshShopPanel(); return }
            if name == "shop_scrolldn"    { shopScroll += 1; refreshShopPanel(); return }
            if name.hasPrefix("enh:"),     let slot = CharSlot(rawValue: String(name.dropFirst(4))), let id = CharacterRenderer.shared.selection[slot] { enhanceItem(id); return }   // 🔼강화(착용중)
            if name.hasPrefix("cubewin:"), let slot = CharSlot(rawValue: String(name.dropFirst(8))), let id = CharacterRenderer.shared.selection[slot] { openCubeWindow(forID: id); return }    // 🧊 강화/잠재 창
            if name.hasPrefix("selslot:"), let slot = CharSlot(rawValue: String(name.dropFirst(8))) {   // 부위 클릭=선택, 더블=벗기
                if dbl { unequipAppearanceSlot(slot) } else { selEquipSlot = slot; refreshEquippedPanel() }; return
            }
            // (구) 장비창
            if name.hasPrefix("equip:")   { equip(String(name.dropFirst(6)));  return }
            if name.hasPrefix("use:")     { useItem(String(name.dropFirst(4))); return }
            if name.hasPrefix("unequip:") {
                if let slot = EquipSlot(rawValue: String(name.dropFirst(8))) { unequip(slot) }
                return
            }
            // 능력치창
            if name == "stats_close" { toggleStats(); return }
            if name.hasPrefix("alloc:") { allocate(String(name.dropFirst(6))); return }
            // 스킬창
            if name == "skills_close" { toggleSkillWindow(); return }
            if name.hasPrefix("sklv:") { levelUpSkill(String(name.dropFirst(5))); return }
            // 외형 꾸미기
            if name == "equip_close" { toggleEquipBrowser(); return }
            if name == "equip_confirm" { confirmEquipSelection(); return }
            if name.hasPrefix("eqsel:") {
                let parts = name.dropFirst(6).split(separator: ":")
                if parts.count == 2, let slot = CharSlot(rawValue: String(parts[0])), let id = Int(parts[1]) {
                    equipPending[slot] = id
                    CharacterRenderer.shared.prefetchItem(id)               // 고른 아이템 레이어 미리 받기
                    refreshEquipPanel()
                }
                return
            }
            // 상점창
            if name == "shop_close" { toggleShop(); return }
            if name.hasPrefix("buy:")  { buy(String(name.dropFirst(4)));  return }
            if name.hasPrefix("sell:") { sell(String(name.dropFirst(5))); return }
            // 월드맵
            if name == "worldmap_close" { toggleWorldMap(); return }
            if name.hasPrefix("travel:") {
                let a = Area(raw: String(name.dropFirst(7)))
                if a != currentArea {
                    let from = currentArea
                    toggleWorldMap(); fadeToArea(a, from: from)   // 포탈처럼 페이드 전환
                }
                return
            }
            // 키 설정
            if name == "keybinds_close" { toggleKeybinds(); return }
            if name == "kb_scrollup"    { keybindsScroll -= 1; refreshKeybindsPanel(); return }
            if name == "kb_scrolldn"    { keybindsScroll += 1; refreshKeybindsPanel(); return }
            if name.hasPrefix("rebind:") {
                if let a = GameAction(rawValue: String(name.dropFirst(7))) {
                    capturingAction = a; refreshKeybindsPanel()
                }
                return
            }
        }
    }

    func takeDamage(_ amount: Int) {
        if Double.random(in: 0..<1) < avoidChance {   // 회피(LUK+DEX) → 0 피해
            floatText("MISS", at: CGPoint(x: player.position.x, y: player.position.y + 40),
                      color: SKColor(white: 0.95, alpha: 1), size: 18); invuln = 0.5; return
        }
        let reduced = max(1, amount - bonusDEF)   // 장비 방어력 반영 (최소 1)
        hp -= reduced
        invuln = 1.0
        combatTimer = 3.5                          // 피격 → 전투 상태
        floatText("-\(reduced)", at: CGPoint(x: player.position.x, y: player.position.y + 40),
                  color: SKColor(red: 0.72, green: 0.42, blue: 1.0, alpha: 1), size: 22)   // 캐릭터 위 보라색
        // 깜빡임 (무적 동안 또렷하게)
        player.run(.repeat(.sequence([.fadeAlpha(to: 0.2, duration: 0.07),
                                      .fadeAlpha(to: 1, duration: 0.07)]), count: 6), withKey: "hurt")
        // 빨강 피격 플래시 (캐릭터에 붙어 따라다님)
        let flash = SKShapeNode(circleOfRadius: 24)
        flash.fillColor = SKColor(red: 1, green: 0.15, blue: 0.15, alpha: 0.55)
        flash.strokeColor = .clear; flash.zPosition = 3
        player.addChild(flash)
        flash.run(.sequence([.group([.scale(to: 1.7, duration: 0.2), .fadeOut(withDuration: 0.25)]),
                             .removeFromParent()]))
        if hp <= 0 { die() }
        updateHUD()
    }

    func die() {
        if climbing { releaseClimb() }      // 등반 중 사망 시 로프로 다시 끌려가지 않게
        upHeld = false; downHeld = false
        popText("기절! 💫", at: CGPoint(x: player.position.x, y: player.position.y + 56),
                color: SKColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1), size: 26)
        hp = maxHP
        mp = maxMP
        player.position = defaultSpawn(for: currentArea)
        velocityY = 0
        invuln = 1.5
    }

    func gainXP(_ n: Int) {
        xp += n
        var leveled = false
        while xp >= xpToNext {
            xp -= xpToNext
            level += 1
            unspentAP += apPerLevel       // 레벨업 시 능력치 포인트 지급
            unspentSP += spPerLevel       // + 스킬 포인트
            leveled = true
        }
        if leveled { levelUpEffect() }
        updateHUD()
    }

    // 레벨업 큰 연출: 화면 번쩍 + "LEVEL N" + 반짝이
    func levelUpEffect() {
        let flash = SKSpriteNode(color: SKColor(red: 1, green: 1, blue: 0.6, alpha: 0.55),
                                 size: CGSize(width: viewW, height: viewH))
        flash.zPosition = 300; flash.position = .zero
        hudLayer.addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.5), .removeFromParent()]))

        let big = SKLabelNode(text: "LEVEL \(level)")
        big.fontName = "AvenirNext-Heavy"; big.fontSize = 16
        big.fontColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        big.zPosition = 301; big.position = CGPoint(x: 0, y: 30); big.setScale(0.3)
        hudLayer.addChild(big)
        big.run(.sequence([.scale(to: 3.0, duration: 0.35), .wait(forDuration: 0.6),
                           .fadeOut(withDuration: 0.4), .removeFromParent()]))

        popText("능력치 포인트 +\(apPerLevel)", at: CGPoint(x: player.position.x, y: player.position.y + 56),
                color: SKColor(red: 1.0, green: 0.6, blue: 0.1, alpha: 1), size: 16)

        for i in 0..<12 {
            let ang = CGFloat(i) / 12 * .pi * 2
            let s = SKLabelNode(text: "✨"); s.fontSize = 18
            s.position = player.position; s.zPosition = 11
            worldLayer.addChild(s)
            s.run(.sequence([.group([.moveBy(x: cos(ang)*70, y: sin(ang)*70, duration: 0.55),
                                     .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
        }
    }

    // 모든 이벤트/획득 텍스트는 화면 우측 하단 알림으로 (월드엔 몬스터 위 데미지만 뜨도록).
    // 'at' 좌표는 무시 — 기존 popText 호출부가 자동으로 우측 하단 알림이 됨.
    func popText(_ text: String, at pos: CGPoint, color: SKColor, size fontSize: CGFloat = 20) {
        notify(text, color: color)
    }
    // 월드 공간에 떠오르는 텍스트(지정 위치에서 위로 떠오르며 사라짐) — 하단 토스트(notify)와 별개로 캐릭터/몹 위에 표시.
    func floatText(_ text: String, at worldPos: CGPoint, color: SKColor, size: CGFloat = 20) {
        let l = SKLabelNode(text: text)
        if GameScene.fontsRegistered { l.fontName = GameScene.uiFont }
        l.fontSize = size; l.fontColor = color
        l.verticalAlignmentMode = .center; l.horizontalAlignmentMode = .center
        l.position = worldPos; l.zPosition = 55; l.setScale(0.5)
        worldLayer.addChild(l)
        l.run(.sequence([.group([.scale(to: 1.0, duration: 0.12),
                                 .moveBy(x: 0, y: 42, duration: 0.75)]),
                         .fadeOut(withDuration: 0.25), .removeFromParent()]))
    }
    var notifyToasts: [SKLabelNode] = []
    func notify(_ text: String, color: SKColor) {
        let l = SKLabelNode(text: text)
        if GameScene.fontsRegistered { l.fontName = GameScene.uiFont }
        l.fontSize = 14; l.fontColor = color
        l.horizontalAlignmentMode = .right; l.verticalAlignmentMode = .center
        l.position = CGPoint(x: viewW/2 - 14, y: -viewH/2 + GameScene.hudBarH + 16)
        l.zPosition = 60; l.alpha = 0
        hudLayer.addChild(l)
        for t in notifyToasts { t.run(.moveBy(x: 0, y: 19, duration: 0.12)) }   // 기존 알림 위로
        notifyToasts.append(l)
        while notifyToasts.count > 6 {                                          // 오래된 건 정리
            let old = notifyToasts.removeFirst()
            old.removeAllActions(); old.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
        }
        l.run(.sequence([.fadeIn(withDuration: 0.12), .wait(forDuration: 3.2), .fadeOut(withDuration: 0.5),
                         .run { [weak self, weak l] in guard let self, let l else { return }; self.notifyToasts.removeAll { $0 === l } },
                         .removeFromParent()]))
    }

    // ── 키보드 입력 (라이브 binds 디스패치 + 리바인드 캡처) ─────
    func setupKeyboard() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            let keyCode = event.keyCode
            let isDown = event.type == .keyDown
            let isRepeat = event.isARepeat
            let consumed: Bool = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handleKey(keyCode: keyCode, isDown: isDown, isRepeat: isRepeat)
            }
            return consumed ? nil : event   // 우리가 처리했을 때만 소비
        }
    }

    // true = 이벤트 소비, false = 통과
    func handleKey(keyCode: UInt16, isDown: Bool, isRepeat: Bool) -> Bool {
        // 1) 리바인드 캡처: 어떤 키든 잡아 액션에 할당 (Esc=취소)
        if let action = capturingAction, isDown, !isRepeat {
            if keyCode == 53 { capturingAction = nil; refreshKeybindsPanel(); return true }
            rebind(action, to: keyCode)
            return true
        }
        // 2) keyUp: 좌/우/위/아래 해제
        if !isDown {
            if let ck = channelKey, keyCode == ck {   // 채널 스킬 키 뗌 → 종료
                channelKey = nil
                for j in skillZones.indices where skillZones[j].follows { skillZones[j].held = false }
                return true
            }
            if keyCode == binds[.left]     { leftPressed = false;  return true }
            if keyCode == binds[.right]    { rightPressed = false; return true }
            if keyCode == binds[.interact] { upHeld = false; return true }
            if keyCode == binds[.down]     { downHeld = false; return true }
            if keyCode == binds[.attack]   { attackHeld = false; return true }   // 공격키 떼면 자동반복 중지
            if keyCode == binds[.pickup]   { pickupHeld = false; return true }   // 줍기키 떼면 자동반복 중지
            return false
        }
        // 3) 모달 열림: Esc는 항상 닫기 (안전장치) + 해당 토글 키만, 나머지 바운드 키는 흡수
        if keyCode == 53, !isRepeat {   // Esc — 어떤 키 설정이어도 모달 탈출 가능
            if inventoryOpen { toggleInventory(); return true }
            if statsOpen { toggleStats(); return true }
            if worldMapOpen { toggleWorldMap(); return true }
            if keybindsOpen { toggleKeybinds(); return true }
            if shopOpen { toggleShop(); return true }
            if skillWindowOpen { toggleSkillWindow(); return true }
            if equipBrowserOpen { toggleEquipBrowser(); return true }
            if equippedWindowOpen { toggleEquippedWindow(); return true }
            if cubeWindowOpen { closeCubeWindow(); return true }
            if cashWindowOpen { closeCashWindow(); return true }
        }
        // 전체화면(이동 차단) 창: 바운드 키 흡수
        if cubeWindowOpen { return binds.values.contains(keyCode) }   // 큐브 창: 닫기는 Esc/취소버튼만
        if cashWindowOpen { return binds.values.contains(keyCode) }   // 치장 창: 닫기는 Esc/✕만
        if worldMapOpen  { if !isRepeat, keyCode == binds[.worldmap]     { toggleWorldMap() };  return binds.values.contains(keyCode) }
        if keybindsOpen  { if !isRepeat, keyCode == binds[.openKeybinds] { toggleKeybinds() };  return binds.values.contains(keyCode) }
        // 사이드 창(상점·인벤·스탯·장비·스킬): 닫기 키만 처리하고 이동·공격 키는 4)로 통과 → 창 열고도 플레이
        if shopOpen, !isRepeat, keyCode == binds[.interact] { toggleShop(); return true }
        // (인벤/스탯/스킬/착용창의 토글 키는 아래 4) switch가 처리 — 그대로 통과시켜 이동 허용)
        // 4) 일반 플레이 (라이브 binds 역조회)
        guard let action = binds.first(where: { $0.value == keyCode })?.key else { return false }
        switch action {
        case .left:  leftPressed = true
        case .right: rightPressed = true
        case .jump:  if !isRepeat { jump() }
        case .attack: attackHeld = true; if !isRepeat { attack() }   // 꾹 누르면 update에서 쿨다운마다 자동반복
        case .skill1, .skill2, .skill3, .skill4, .skill5, .skill6, .skill7, .skill8, .skill9, .skill10: if !isRepeat, let s = skillSlot(for: action) { useSkill(s) }
        case .inventory:    if !isRepeat { toggleInventory() }
        case .stats:        if !isRepeat { toggleStats() }
        case .worldmap:     if !isRepeat { toggleWorldMap() }
        case .openKeybinds: if !isRepeat { toggleKeybinds() }
        case .skills:       if !isRepeat { toggleSkillWindow() }                     // K: 스킬창
        case .equipBrowser: break                                                    // R 제거 — 장비는 E(착용)·I(인벤)로
        case .equippedWindow: if !isRepeat { toggleEquippedWindow() }                // E: 착용 장비창
        case .interact:     upHeld = true; if !isRepeat { interactPressed = true }   // ↑: 등반/포털
        case .down:         downHeld = true                                          // ↓: 등반 하강
        case .pickup:       pickupHeld = true; if !isRepeat { pickupPressed = true }   // Z: 줍기(꾹 누르면 자동반복)
        }
        return true
    }

    static var defaultBinds: [GameAction: UInt16] {
        func code(_ letter: String, _ fallback: UInt16) -> UInt16 {
            let m: [String: UInt16] = ["A":0,"S":1,"D":2,"F":3,"G":5,"C":8,"V":9,"B":11,
                                       "Q":12,"W":13,"E":14,"R":15,"I":34,"Y":16,"T":17,"X":7]
            return m[letter.uppercased()] ?? fallback
        }
        func skKey(_ i: Int, _ fb: String) -> String { SkillCatalog.all.indices.contains(i) ? SkillCatalog.all[i].key : fb }
        return [
            .left: 123, .right: 124, .jump: 49, .attack: 0,
            .skill1: code(skKey(0,"S"), 1), .skill2: code(skKey(1,"D"), 2),
            .skill3: code(skKey(2,"F"), 3), .skill4: code(skKey(3,"G"), 5),
            .skill5: code(skKey(4,"V"), 9), .skill6: code(skKey(5,"Q"), 12),
            .skill7: code(skKey(6,"R"), 15), .skill8: code(skKey(7,"T"), 17),
            .skill9: code(skKey(8,"V"), 9), .skill10: code(skKey(9,"Q"), 12),   // 스킬<9면 슬롯없음 — 빈 V/Q로 폴백(B/X 충돌 방지)
            .inventory: 34, .stats: 8, .worldmap: 13, .interact: 126, .down: 125,
            // openKeybinds는 키 없음 — 화면 하단 "키설정" 버튼으로만 염 (E와 충돌 방지)
            .pickup: 6,  // Z
            .skills: 40, // K
            .equippedWindow: 14   // E: 착용 장비창 (장비는 E·I로 통일, R 제거)
        ]
    }

    func keyName(_ code: UInt16) -> String {
        let special: [UInt16: String] = [123:"←",124:"→",125:"↓",126:"↑",49:"Space",
                                         36:"Enter",48:"Tab",53:"Esc",51:"⌫"]
        if let s = special[code] { return s }
        let letters: [UInt16: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",
                                         8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",
                                         16:"Y",17:"T",31:"O",32:"U",34:"I",35:"P",37:"L",
                                         38:"J",40:"K",45:"N",46:"M"]
        return letters[code] ?? "#\(code)"
    }

    func bindName(_ a: GameAction) -> String { binds[a].map { keyName($0) } ?? "—" }

    func skillSlot(for action: GameAction) -> SkillSlot? {
        guard let idx = GameScene.skillActions.firstIndex(of: action), skills.indices.contains(idx) else { return nil }
        return skills[idx]
    }

    func refreshSkillKeyLabels() {
        for (i, a) in GameScene.skillActions.enumerated() where skills.indices.contains(i) {
            skills[i].keyLabel?.text = bindName(a)
        }
    }

    func rebind(_ action: GameAction, to code: UInt16) {
        capturingAction = nil
        let old = binds[action]                          // 이 액션의 기존 키
        for (a, c) in binds where c == code && a != action {
            binds[a] = old                               // 충돌 액션에 기존 키를 넘겨줌 (스왑 → 미바인딩 방지)
        }
        binds[action] = code
        refreshSkillKeyLabels()
        saveProgress()
        refreshKeybindsPanel()
    }

    // ── 월드맵 모달 ───────────────────────────────────────────
    func toggleWorldMap() {
        if inventoryOpen { toggleInventory() }; if statsOpen { toggleStats() }
        if shopOpen { toggleShop() }; if keybindsOpen { toggleKeybinds() }
        worldMapOpen.toggle()
        if worldMapOpen { leftPressed = false; rightPressed = false; buildWorldMapPanel() }
        else { worldMapPanel?.removeFromParent(); worldMapPanel = nil }
    }

    func buildWorldMapPanel() {
        let panel = SKNode(); panel.zPosition = 100; panel.name = "worldMapPanel"
        let areas: [Area] = [.town] + (0..<FieldCatalog.fields.count).map { .field($0) }
        let w: CGFloat = 420, rowStep: CGFloat = 30
        let h: CGFloat = CGFloat(areas.count) * rowStep + 96, cx: CGFloat = 0, cy: CGFloat = 0
        let rowW = w - 30
        let bg = SKSpriteNode(color: SKColor(white: 0.08, alpha: 0.94), size: CGSize(width: w, height: h))
        bg.position = CGPoint(x: cx, y: cy); bg.zPosition = -1; panel.addChild(bg)
        let title = SKLabelNode(text: "월드 맵 (레벨 1~200)"); title.fontSize = 17; title.fontColor = .white
        title.position = CGPoint(x: cx, y: cy + h/2 - 26); panel.addChild(title)
        let close = SKLabelNode(text: "✕"); close.name = "worldmap_close"
        close.fontSize = 20; close.fontColor = .white
        close.position = CGPoint(x: cx + w/2 - 22, y: cy + h/2 - 28); panel.addChild(close)
        var sy = cy + h/2 - 58
        for a in areas {
            let here = (a == currentArea)
            // 현재 레벨에 맞는 추천 필드는 ▶로 강조
            let rec = a.fieldIndex.map { level >= FieldCatalog.bandMin($0) && level <= FieldCatalog.bandMax($0) } ?? false
            let text = (here ? "📍 " : rec ? "⭐ " : "🗺️ ") + a.title + (here ? "  (현재 위치)" : "")
            addRow(to: panel, text: text,
                   color: here ? SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
                        : rec ? SKColor(red: 0.6, green: 1, blue: 0.7, alpha: 1) : .white,
                   name: here ? nil : "travel:\(a.raw)", cx: cx, y: sy, width: rowW)
            sy -= rowStep
        }
        let hint = SKLabelNode(text: "영역 클릭 = 이동 · ⭐ = 내 레벨 추천 · \(bindName(.worldmap)) 닫기")
        hint.fontSize = 11; hint.fontColor = SKColor(white: 0.8, alpha: 1)
        hint.position = CGPoint(x: cx, y: cy - h/2 + 14); panel.addChild(hint)
        styleLabels(panel); hudLayer.addChild(panel); worldMapPanel = panel
    }

    // ── 키 설정 모달 ──────────────────────────────────────────
    func toggleKeybinds() {
        if inventoryOpen { toggleInventory() }; if statsOpen { toggleStats() }
        if shopOpen { toggleShop() }; if worldMapOpen { toggleWorldMap() }
        keybindsOpen.toggle(); capturingAction = nil
        if keybindsOpen { leftPressed = false; rightPressed = false; keybindsScroll = 0; buildKeybindsPanel() }
        else { keybindsPanel?.removeFromParent(); keybindsPanel = nil }
    }

    func refreshKeybindsPanel() {
        guard keybindsOpen else { return }
        keybindsPanel?.removeFromParent(); keybindsPanel = nil; buildKeybindsPanel()
    }

    func buildKeybindsPanel() {
        let panel = SKNode(); panel.zPosition = 100; panel.name = "keybindsPanel"
        let w: CGFloat = 400, h: CGFloat = 400, cx: CGFloat = 0, cy: CGFloat = 0
        let rowW = w - 60
        let bg = SKSpriteNode(color: SKColor(white: 0.08, alpha: 0.93), size: CGSize(width: w, height: h))
        bg.position = CGPoint(x: cx, y: cy); bg.zPosition = -1; panel.addChild(bg)
        let title = SKLabelNode(text: "키 설정"); title.fontSize = 18; title.fontColor = .white
        title.position = CGPoint(x: cx, y: cy + h/2 - 26); panel.addChild(title)
        let close = SKLabelNode(text: "✕"); close.name = "keybinds_close"
        close.fontSize = 20; close.fontColor = .white
        close.position = CGPoint(x: cx + w/2 - 22, y: cy + h/2 - 28); panel.addChild(close)
        // 윈도잉 스크롤
        let actions = GameAction.allCases.filter { $0 != .openKeybinds && $0 != .equipBrowser }
        let rowH: CGFloat = 28, topY = cy + h/2 - 58, visible = 10
        let maxScroll = max(0, actions.count - visible)
        if keybindsScroll > maxScroll { keybindsScroll = maxScroll }; if keybindsScroll < 0 { keybindsScroll = 0 }
        for vi in 0..<min(visible, actions.count - keybindsScroll) {
            let a = actions[keybindsScroll + vi]; let y = topY - CGFloat(vi) * rowH
            let waiting = (capturingAction == a)
            let key = waiting ? "[ 키를 누르세요… ]" : bindName(a)
            addRow(to: panel, text: "\(a.title):  \(key)",
                   color: waiting ? SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 1) : .white,
                   name: "rebind:\(a.rawValue)", cx: cx, y: y, width: rowW)
        }
        if maxScroll > 0 {
            let ax = cx + w/2 - 16
            let up = SKLabelNode(text: "▲"); up.name = "kb_scrollup"; up.fontSize = 15
            up.fontColor = keybindsScroll > 0 ? .white : SKColor(white:0.35,alpha:1)
            up.position = CGPoint(x: ax, y: topY); up.zPosition = 0.3; panel.addChild(up)
            let dn = SKLabelNode(text: "▼"); dn.name = "kb_scrolldn"; dn.fontSize = 15
            dn.fontColor = keybindsScroll < maxScroll ? .white : SKColor(white:0.35,alpha:1)
            dn.position = CGPoint(x: ax, y: topY - CGFloat(visible - 1) * rowH); dn.zPosition = 0.3; panel.addChild(dn)
        }
        let hint = SKLabelNode(text: "행 클릭 → 새 키 입력 · 휠 스크롤 · Esc 취소 · ✕ 닫기")
        hint.fontSize = 11; hint.fontColor = SKColor(white: 0.8, alpha: 1)
        hint.position = CGPoint(x: cx, y: cy - h/2 + 14); panel.addChild(hint)
        styleLabels(panel); hudLayer.addChild(panel); keybindsPanel = panel
    }
}

// ── 외형 꾸미기: maplestory.io 동적 합성으로 장비 교체 ──────────────
extension GameScene {
    func toggleEquipBrowser() {
        if inventoryOpen { toggleInventory() }
        if statsOpen { toggleStats() }
        if shopOpen { toggleShop() }
        if skillWindowOpen { toggleSkillWindow() }
        equipBrowserOpen.toggle()
        if equipBrowserOpen {
            leftPressed = false; rightPressed = false
            equipPending = CharacterRenderer.shared.selection
            CharacterRenderer.shared.prefetchBase()                          // 베이스 미리 캐싱
            for id in equipPending.values { CharacterRenderer.shared.prefetchItem(id) }
            buildEquipPanel()
        } else {
            equipPanel?.removeFromParent(); equipPanel = nil
        }
    }

    func refreshEquipPanel() {
        guard equipBrowserOpen else { return }
        equipPanel?.removeFromParent(); equipPanel = nil
        buildEquipPanel()
    }

    func buildEquipPanel() {
        let panel = SKNode(); panel.zPosition = 100; panel.name = "equipPanel"
        let w: CGFloat = 480, h: CGFloat = 480
        let bg = SKSpriteNode(color: SKColor(white: 0.08, alpha: 0.95), size: CGSize(width: w, height: h))
        bg.zPosition = -1; panel.addChild(bg)

        let title = SKLabelNode(text: "장비 고르기"); title.fontSize = 18; title.fontColor = .white
        title.position = CGPoint(x: 0, y: h/2 - 26); panel.addChild(title)
        let close = SKLabelNode(text: "✕"); close.name = "equip_close"
        close.fontSize = 20; close.fontColor = .white
        close.position = CGPoint(x: w/2 - 22, y: h/2 - 28); panel.addChild(close)

        let r = CharacterRenderer.shared
        var rowY = h/2 - 54
        for slot in CharSlot.allCases {
            let lbl = SKLabelNode(text: slot.label); lbl.fontSize = 14; lbl.fontColor = SKColor(white: 0.85, alpha: 1)
            lbl.horizontalAlignmentMode = .left; lbl.verticalAlignmentMode = .center
            lbl.position = CGPoint(x: -w/2 + 18, y: rowY); panel.addChild(lbl)

            var x: CGFloat = -w/2 + 90
            for id in r.catalog[slot] ?? [] {
                let selected = equipPending[slot] == id
                let box = SKSpriteNode(color: selected ? SKColor(red: 0.95, green: 0.8, blue: 0.2, alpha: 1)
                                                       : SKColor(white: 0.22, alpha: 1),
                                       size: CGSize(width: 46, height: 46))
                box.position = CGPoint(x: x, y: rowY); box.name = "eqsel:\(slot.rawValue):\(id)"
                panel.addChild(box)
                let inner = SKSpriteNode(color: SKColor(white: 0.12, alpha: 1), size: CGSize(width: 40, height: 40))
                inner.position = box.position; inner.zPosition = 0.1; panel.addChild(inner)
                if let tex = iconCache[id] {
                    let icon = SKSpriteNode(texture: tex)
                    let s = tex.size(); let mx = max(s.width, s.height, 1)
                    icon.size = CGSize(width: s.width/mx*36, height: s.height/mx*36)
                    icon.position = box.position; icon.zPosition = 0.2; panel.addChild(icon)
                } else {
                    ensureIcon(id)
                }
                x += 54
            }
            rowY -= 52
        }

        // 확인 버튼
        let busy = CharacterRenderer.shared.regenerating
        let confBG = SKSpriteNode(color: busy ? SKColor(white: 0.3, alpha: 0.5) : SKColor(red: 0.2, green: 0.55, blue: 0.3, alpha: 1),
                                  size: CGSize(width: 150, height: 34))
        confBG.position = CGPoint(x: 0, y: -h/2 + 38); confBG.zPosition = 0.1
        if !busy { confBG.name = "equip_confirm" }
        panel.addChild(confBG)
        let conf = SKLabelNode(text: busy ? "불러오는 중…" : "✅ 확인 (적용)")
        conf.fontSize = 15; conf.fontColor = .white; conf.verticalAlignmentMode = .center
        conf.position = confBG.position; conf.zPosition = 0.2; panel.addChild(conf)

        let hint = SKLabelNode(text: "아이콘 클릭 → 선택 · 확인 누르면 maplestory.io에서 합성 · \(bindName(.equipBrowser)) 닫기")
        hint.fontSize = 10; hint.fontColor = SKColor(white: 0.75, alpha: 1)
        hint.position = CGPoint(x: 0, y: -h/2 + 14); panel.addChild(hint)

        styleLabels(panel); hudLayer.addChild(panel); equipPanel = panel
    }

    // 아이템 아이콘 비동기 로드 → 캐시 후 패널 갱신
    func ensureIcon(_ id: Int) {
        if iconCache[id] != nil { return }
        iconCache[id] = SKTexture()   // 중복 요청 방지 placeholder
        DispatchQueue.global(qos: .userInitiated).async {
            guard let d = CharacterRenderer.fetchData(CharacterRenderer.iconURL(id)),
                  let img = NSImage(data: d) else {
                DispatchQueue.main.async { self.iconCache[id] = nil }   // 실패 시 재시도 가능하게
                return
            }
            DispatchQueue.main.async {
                let t = SKTexture(image: img); t.filteringMode = .nearest
                self.iconCache[id] = t
                self.refreshOpenItemPanels()      // 인벤/착용/브라우저 중 열린 것 갱신
            }
        }
    }
    // 아이콘이 도착하면 열려있는 아이템 패널을 갱신(여러 아이콘이 같은 틱에 와도 1회만 rebuild)
    func refreshOpenItemPanels() {
        if iconRefreshScheduled { return }
        iconRefreshScheduled = true
        DispatchQueue.main.async {
            self.iconRefreshScheduled = false
            if self.equipBrowserOpen   { self.refreshEquipPanel() }
            if self.inventoryOpen      { self.refreshInventoryPanel() }
            if self.equippedWindowOpen { self.refreshEquippedPanel() }
            if self.shopOpen           { self.refreshShopPanel() }
            if self.cubeWindowOpen     { self.refreshCubePanel() }
        }
    }
    // 보유 외형 아이콘을 백그라운드로 미리 받아둠 → 인벤 처음 열 때 바로 보이게
    func prefetchAppearanceIcons() {
        for id in ownedAppearance { ensureIcon(id) }
        for it in ItemCatalog.all { if let iid = it.iconID { ensureIcon(iid) } }   // 물약·기타템 실제 아이콘
        ensureIcon(GameScene.petItemID)                                            // 펫 아이콘
        for id in GameScene.scrollIcons { ensureIcon(id) }
        for id in [GameScene.cubeIconRed, GameScene.cubeIconBlack, GameScene.cubeIconAdd] { ensureIcon(id) }  // 주문서·큐브 아이콘
    }

    // 확인 → 조합 fetch+정렬(백그라운드) → 캐릭터 라이브 교체
    func confirmEquipSelection() {
        let r = CharacterRenderer.shared
        if r.regenerating { return }
        r.selection = equipPending
        let items = r.currentItems()
        let key = CharacterRenderer.comboKey(items)
        if let c = comboTexCache[key] { applyComboTex(c); saveProgress(); refreshEquipPanel(); return }   // 메모리 캐시 즉시
        refreshEquipPanel()          // "불러오는 중…" 표시
        r.regenerate(items: items) { [weak self] result in
            guard let self else { return }
            if let result { self.reloadCharacter(result, cacheKey: key); self.saveProgress() }
            self.refreshEquipPanel()
        }
    }

    // ComboResult → 애니 텍스처 교체 + 앵커/크기 갱신
    // 백그라운드에서 디코드된 텍스처를 받아 즉시 적용(메인 디코드 없음 → 끊김 제거).
    func reloadCharacter(_ d: DecodedCombo, cacheKey: String? = nil) {
        let ct = makeComboTex(d.anims, feet: d.feet, center: d.center)
        applyComboTex(ct)
        if let key = cacheKey { comboTexCache[key] = ct }   // 메모리 캐시 → 다음 재장착 즉시
    }
    // 디코드된 anim 텍스처 dict → ComboTex (attack0,1,… 변형 수집)
    func makeComboTex(_ anims: [String: [SKTexture]], feet: CGFloat, center: CGFloat) -> ComboTex {
        var variants: [[SKTexture]] = []; var i = 0
        while let t = anims["attack\(i)"], !t.isEmpty { variants.append(t); i += 1 }
        return ComboTex(idle: anims["idle"] ?? [], walk: anims["walk"] ?? [], climb: anims["climb"] ?? [],
                        jump: anims["jump"] ?? [], prone: anims["prone"] ?? [], proneAttack: anims["proneAttack"] ?? [],
                        attack: variants, feet: feet, center: center)
    }
    // 플레이어 스프라이트 크기/앵커 갱신(고정 배율, 발끝 정렬)
    func applyPlayerSizeAnchor(feet: CGFloat, center: CGFloat) {
        guard let sp = player as? SKSpriteNode, let first = animIdle.first else { return }
        let s = first.size()
        let nodeH = s.height * GameScene.bodyScale
        sp.size = CGSize(width: s.width * GameScene.bodyScale, height: nodeH)
        sp.anchorPoint = CGPoint(x: center, y: feet + playerHalfH / nodeH)
        sp.texture = first
    }
    // 메모리 캐시된 조합 즉시 적용 (재생성 없음)
    func applyComboTex(_ c: ComboTex) {
        if !c.attack.isEmpty { animAttackVariants = c.attack; animAttack = c.attack[0]; currentAtkVariant = 0 }
        if !c.idle.isEmpty  { animIdle = c.idle; animStill = [c.idle[0]] }
        if !c.walk.isEmpty  { animWalk = c.walk }
        if !c.climb.isEmpty { animClimb = c.climb }
        if !c.jump.isEmpty  { animJump = c.jump }
        if !c.prone.isEmpty { animProne = c.prone }
        if !c.proneAttack.isEmpty { animProneAttack = c.proneAttack }
        applyPlayerSizeAnchor(feet: c.feet, center: c.center)
        currentAnimKey = ""
    }

    // 시작 시: 저장된 외형이 기본(베이크된 스프라이트)과 다르면 백그라운드로 합성해 교체
    func loadSavedCharacterIfNeeded() {
        // 항상 백그라운드 재생성 → 공격 모션 변형(찌르기/휘두르기)까지 로드(캐시 있으면 즉시).
        // 베이크 스프라이트는 그 사이 즉시 표시되는 초기 모습(공격 모션 1종).
        let r = CharacterRenderer.shared
        let key = CharacterRenderer.comboKey(r.currentItems())
        r.regenerate(items: r.currentItems()) { [weak self] result in
            if let self, let result { self.reloadCharacter(result, cacheKey: key) }
        }
    }
}

// ── 착용 장비창(E) · 외형 장착/해제 · 드랍 · 호버 툴팁 ────────────────
extension GameScene {
    func ensureStartingOwnedItems() {
        let r = CharacterRenderer.shared
        // stand1/walk1에서 몸 뒤로 가려져 안 보이는 무기(창·완드·가방 등 — 폴암류는 stand2 필요)는
        // 카탈로그에 없으므로 보유 목록에서 정리하고, 장착 중이면 보이는 기본 무기로 교체.
        let valid = Set(r.catalog.values.flatMap { $0 })
        ownedAppearance = ownedAppearance.filter { valid.contains($0) }
        if let w = r.selection[.weapon], r.catalog[.weapon]?.contains(w) != true {
            r.selection[.weapon] = r.catalog[.weapon]?.first             // 안 보이는 무기 → 보이는 기본 무기
        }
        for id in r.selection.values { ownedAppearance.insert(id) }       // 장착중인 건 항상 보유
        if ownedAppearance.count < 9 {                                    // 신규: 슬롯별 앞 2개 기본 지급
            for (_, ids) in r.catalog { for id in ids.prefix(2) { ownedAppearance.insert(id) } }
        }
        for slot in [CharSlot.shoes, .gloves] {                            // 신발·장갑 미보유 세이브엔 기본 지급(신규 슬롯)
            if let ids = r.catalog[slot], !ids.contains(where: { ownedAppearance.contains($0) }) {
                ids.prefix(2).forEach { ownedAppearance.insert($0) }
            }
        }
    }

    // ── E: 착용 장비창 (6 외형 슬롯) ──
    func toggleEquippedWindow() {
        if inventoryOpen { toggleInventory() }
        if statsOpen { toggleStats() }
        if shopOpen { toggleShop() }
        if skillWindowOpen { toggleSkillWindow() }
        equippedWindowOpen.toggle()
        if equippedWindowOpen {
            leftPressed = false; rightPressed = false
            for id in CharacterRenderer.shared.catalog.values.flatMap({ $0 }) { ensureIcon(id) }   // 치장 카탈로그 아이콘 미리
            buildEquippedPanel()
        }
        else { equippedPanel?.removeFromParent(); equippedPanel = nil; hideTooltip() }
    }
    func refreshEquippedPanel() {
        guard equippedWindowOpen else { return }
        equippedPanel?.removeFromParent(); equippedPanel = nil; buildEquippedPanel()
    }
    // ── 큐브 전용 창 (한번 더 사용하기 / 취소) ──
    func openCubeWindow(forID id: Int) {   // 장착 안 해도 아이템 id로 강화/잠재
        if equippedWindowOpen { equippedPanel?.removeFromParent(); equippedPanel = nil; equippedWindowOpen = false }
        if pendingCube?.id != id { pendingCube = nil }     // 다른 아이템 열면 보류중인 블랙큐브 결과 폐기
        cubeItemID = id; cubeWindowOpen = true; leftPressed = false; rightPressed = false; buildCubePanel()
    }
    func closeCubeWindow() { pendingCube = nil; cubePanel?.removeFromParent(); cubePanel = nil; cubeWindowOpen = false; hideTooltip() }
    func refreshCubePanel() { guard cubeWindowOpen else { return }; cubePanel?.removeFromParent(); cubePanel = nil; buildCubePanel() }

    // ── 치장(캐시 외형) 창 — 외형만 바꿈(능력치·레벨 무관), 무료 적용 ──
    func toggleCash() {
        cashWindowOpen.toggle()
        if cashWindowOpen { leftPressed = false; rightPressed = false; for id in CharacterRenderer.shared.catalog.values.flatMap({ $0 }) { ensureIcon(id) }; buildCashPanel() }
        else { cashPanel?.removeFromParent(); cashPanel = nil }
    }
    func closeCashWindow() { cashPanel?.removeFromParent(); cashPanel = nil; cashWindowOpen = false; hideTooltip() }
    func refreshCashPanel() { guard cashWindowOpen else { return }; cashPanel?.removeFromParent(); cashPanel = nil; buildCashPanel() }
    func applyCash() { regenerateAppearance(); refreshCashPanel(); saveProgress() }
    func cycleCash(_ slot: CharSlot, _ dir: Int) {
        let cat = CharacterRenderer.shared.catalog[slot] ?? []
        guard !cat.isEmpty else { return }
        let idx = CharacterRenderer.shared.cashSelection[slot].flatMap { cat.firstIndex(of: $0) } ?? (dir > 0 ? -1 : 0)
        CharacterRenderer.shared.cashSelection[slot] = cat[((idx + dir) % cat.count + cat.count) % cat.count]
        applyCash()
    }
    func clearCash(_ slot: CharSlot) { CharacterRenderer.shared.cashSelection[slot] = nil; applyCash(); refreshEquippedPanel() }
    func setCash(_ slot: CharSlot, _ id: Int) {   // 외형(치장) 적용 — 능력치 무관
        if CharacterRenderer.shared.selection[slot] == id { CharacterRenderer.shared.cashSelection[slot] = nil }   // 원래 장비와 같으면 해제
        else { CharacterRenderer.shared.cashSelection[slot] = id }
        applyCash(); refreshEquippedPanel()
    }
    func buildCashPanel() {
        let panel = SKNode(); panel.zPosition = 110; panel.name = "cashPanel"
        let w: CGFloat = 460, h: CGFloat = 430
        panel.position = panelPos["cash"] ?? .zero
        let bg = SKSpriteNode(color: SKColor(white: 0.07, alpha: 0.97), size: CGSize(width: w, height: h)); bg.zPosition = -1; panel.addChild(bg)
        addDragBar(panel, "cash", w: w, h: h, topY: h/2 - 22)
        let title = SKLabelNode(text: "🎀 치장 (외형만 · 능력치 영향 없음)"); title.fontSize = 16; title.fontColor = .white
        title.position = CGPoint(x: 0, y: h/2 - 24); panel.addChild(title)
        let close = SKLabelNode(text: "✕"); close.name = "cash_close"; close.fontSize = 20; close.fontColor = .white
        close.position = CGPoint(x: w/2 - 20, y: h/2 - 24); panel.addChild(close)
        let r = CharacterRenderer.shared
        var y = h/2 - 56
        for slot in CharSlot.allCases {
            let cashID = r.cashSelection[slot]
            let shownID = r.displaySelection[slot]
            let nm = shownID.map { CharacterRenderer.name($0) } ?? "없음"
            let mark = cashID != nil ? "🎀" : "  "
            let lbl = SKLabelNode(text: "\(mark) \(slot.label): \(nm)"); lbl.fontSize = 13
            lbl.fontColor = cashID != nil ? SKColor(red:1,green:0.7,blue:0.85,alpha:1) : .white
            lbl.horizontalAlignmentMode = .left; lbl.verticalAlignmentMode = .center
            lbl.position = CGPoint(x: -w/2 + 14, y: y); panel.addChild(lbl)
            func btn(_ t: String, _ x: CGFloat, _ name: String, _ wdt: CGFloat = 28) {
                let b = SKSpriteNode(color: SKColor(white:0.28,alpha:1), size: CGSize(width: wdt, height: 22))
                b.position = CGPoint(x: x, y: y); b.zPosition = 0.1; b.name = name; panel.addChild(b)
                let l = SKLabelNode(text: t); l.fontSize = 12; l.fontColor = .white; l.verticalAlignmentMode = .center
                l.position = b.position; l.zPosition = 0.2; l.name = name; panel.addChild(l)
            }
            btn("◀", w/2 - 116, "cashcyc:\(slot.rawValue):-1")
            btn("▶", w/2 - 84,  "cashcyc:\(slot.rawValue):1")
            btn("해제", w/2 - 36, "cashclr:\(slot.rawValue)", 48)
            y -= 30
        }
        let hint = SKLabelNode(text: "◀▶ 외형 바꾸기 · 해제=원래 장비 외형 · 무료")
        hint.fontSize = 11; hint.fontColor = SKColor(white: 0.8, alpha: 1)
        hint.position = CGPoint(x: 0, y: -h/2 + 14); panel.addChild(hint)
        styleLabels(panel); hudLayer.addChild(panel); cashPanel = panel
    }
    func buildCubePanel() {
        let panel = SKNode(); panel.zPosition = 110; panel.name = "cubePanel"
        let w: CGFloat = 380, h: CGFloat = cubeMode == 2 ? 470 : 400   // 잠재 탭은 메인+에디셔널 표시로 더 큼
        panel.position = panelPos["cube"] ?? .zero
        let bg = SKSpriteNode(color: SKColor(white: 0.06, alpha: 0.97), size: CGSize(width: w, height: h)); bg.zPosition = -1; panel.addChild(bg)
        addDragBar(panel, "cube", w: w, h: h, topY: h/2 - 18)
        let id = cubeItemID
        let slot = CharacterRenderer.shared.slotOf(id)
        let close = SKLabelNode(text: "✕"); close.name = "cube_close"; close.fontSize = 20; close.fontColor = .white
        close.position = CGPoint(x: w/2 - 20, y: h/2 - 20); panel.addChild(close)
        // ── 탭 (강화/별/잠재 전환) ──
        let tabs = ["🔼 강화", "⭐ 별", "🧊 잠재"]
        for (i, t) in tabs.enumerated() {
            let active = cubeMode == i
            let tb = SKSpriteNode(color: active ? SKColor(red:0.28,green:0.42,blue:0.6,alpha:1) : SKColor(white:0.18,alpha:1), size: CGSize(width: 110, height: 26))
            tb.position = CGPoint(x: -114 + CGFloat(i)*114, y: h/2 - 24); tb.zPosition = 0.1; tb.name = "cube_tab:\(i)"; panel.addChild(tb)
            let tl = SKLabelNode(text: t); tl.fontSize = 13; tl.fontColor = active ? .white : SKColor(white:0.65,alpha:1)
            tl.verticalAlignmentMode = .center; tl.position = tb.position; tl.zPosition = 0.2; tl.name = "cube_tab:\(i)"; panel.addChild(tl)
        }
        var y = h/2 - 58
        func line(_ s: String, _ c: SKColor, _ sz: CGFloat = 13) {
            let l = SKLabelNode(text: s); l.fontSize = sz; l.fontColor = c; l.verticalAlignmentMode = .center; l.position = CGPoint(x: 0, y: y); l.zPosition = 0.2; panel.addChild(l)
        }
        // ── 공통: 아이템 정보 ──
        guard id != 0, let slot else {
            line("강화/잠재할 아이템을 인벤에서 선택하세요", SKColor(white:0.6,alpha:1), 12)
            styleLabels(panel); hudLayer.addChild(panel); cubePanel = panel; return
        }
        if let tex = iconCache[id], tex.size().width > 1 {
            let ic = SKSpriteNode(texture: tex); let s = tex.size(); let mx = max(s.width, s.height, 1)
            ic.size = CGSize(width: s.width/mx*32, height: s.height/mx*32); ic.position = CGPoint(x: -w/2 + 32, y: y); ic.zPosition = 0.2; panel.addChild(ic)
        } else { ensureIcon(id) }
        line("\(slot.label): \(CharacterRenderer.name(id))  ⭐\(starForce[id] ?? 0)", .yellow); y -= 22
        line("⚔️ \(itemATK(slot, id))    🛡️ \(itemDEF(slot, id))", .white, 12); y -= 28
        let enhanceable = slotEnhanceable(slot) && !GameScene.isCash(id)
        func btn(_ text: String, _ yy: CGFloat, _ name: String, _ color: SKColor) {
            let b = SKSpriteNode(color: color, size: CGSize(width: 300, height: 30))
            b.position = CGPoint(x: 0, y: yy); b.zPosition = 0.1; b.name = name; panel.addChild(b)
            let l = SKLabelNode(text: text); l.fontSize = 13; l.fontColor = .white; l.verticalAlignmentMode = .center
            l.position = b.position; l.zPosition = 0.2; l.name = name; panel.addChild(l)
        }
        if !enhanceable {
            line("이 부위는 강화/별/잠재를 할 수 없어요", SKColor(white:0.6,alpha:1), 12)
        } else if cubeMode == 0 {            // ── 주문서 강화 ──
            let used = upgradeUsed[id] ?? 0, maxS = maxSlots(slot), enh = enhanceStat[id] ?? 0
            line("📜 강화 \(used)/\(maxS)" + (enh > 0 ? "   누적 +\(enh)" : ""), .white); y -= 26
            let scT = GameScene.scrollTypes[selectedScroll]
            line("\(scT.emoji) \(scT.name)  +\(scT.gain) 성공 \(Int(scT.rate*100))%\(scT.failDrop>0 ? " 실패-\(scT.failDrop)" : "")  ×\(scrollCounts[selectedScroll])", SKColor(white:0.88,alpha:1), 12)
            let cyc = SKSpriteNode(color: SKColor(white:0.3,alpha:1), size: CGSize(width: 36, height: 20)); cyc.position = CGPoint(x: w/2 - 28, y: y); cyc.zPosition = 0.1; cyc.name = "cyclescroll"; panel.addChild(cyc)
            let cycL = SKLabelNode(text: "◀▶"); cycL.fontSize = 11; cycL.verticalAlignmentMode = .center; cycL.position = cyc.position; cycL.zPosition = 0.2; cycL.name = "cyclescroll"; panel.addChild(cycL); y -= 30
            let can = used < maxS && scrollCounts[selectedScroll] > 0
            btn(can ? "🔼 주문서로 강화하기" : "🔼 강화 불가(횟수/주문서 부족)", -h/2 + 24, "cube_enh", can ? SKColor(red:0.2,green:0.5,blue:0.32,alpha:1) : SKColor(white:0.3,alpha:0.5))
        } else if cubeMode == 1 {            // ── 별 강화(스타포스) ──
            let star = starForce[id] ?? 0
            line("⭐ 현재 ★\(star) / 최대 ★\(GameScene.maxStar)  (★당 능력치 +2)", SKColor(red:1,green:0.85,blue:0.3,alpha:1)); y -= 26
            if star < GameScene.maxStar {
                line("성공 \(Int(GameScene.starRates[min(star,GameScene.starRates.count-1)]*100))%  비용 \(GameScene.starCost(star))메소" + (star>=13 ? "  ⚠파괴 위험" : star>=11 ? "  ⚠실패 시 하락" : ""), SKColor(white:0.85,alpha:1), 12); y -= 28
            } else { y -= 2 }
            let can = star < GameScene.maxStar && gold >= GameScene.starCost(star)
            btn(star >= GameScene.maxStar ? "⭐ 최대 ★\(star) 도달" : (can ? "⭐ 별 강화하기 ★\(star)→\(star+1)" : "⭐ 메소 부족"), -h/2 + 24, "cube_star", can ? SKColor(red:0.7,green:0.5,blue:0.15,alpha:1) : SKColor(white:0.3,alpha:0.5))
        } else {                              // ── 잠재능력(큐브: 레드/블랙/에디셔널) ──
            func potBlock(_ title: String, _ grade: Int?, _ lns: [(kind: PotKind, value: Int, pct: Bool)]) {
                if let g = grade {
                    line("\(title) [\(GameScene.potGradeNames[g])]", GameScene.potGradeColor(g), 13); y -= 17
                    for ln in lns { line("· \(GameScene.potKindLabel(ln.kind)) +\(ln.value)\(ln.pct ? "%" : "")", GameScene.potGradeColor(g), 11); y -= 15 }
                } else { line("\(title) 없음", SKColor(white:0.55,alpha:1), 12); y -= 17 }
            }
            potBlock("메인 잠재", potentialGrade[id], potentialLines[id] ?? []); y -= 4
            potBlock("에디셔널 잠재", additionalGrade[id], additionalLines[id] ?? []); y -= 6
            if let p = pendingCube, p.id == id {        // ── 블랙 큐브 before/after ──
                line("⬛ 블랙 큐브 결과 (\(p.additional ? "에디셔널" : "메인")) — 선택하세요", SKColor(red:1,green:0.8,blue:0.4,alpha:1), 12); y -= 18
                line("새 잠재 [\(GameScene.potGradeNames[p.grade])]", GameScene.potGradeColor(p.grade), 12); y -= 16
                for ln in p.lines { line("· \(GameScene.potKindLabel(ln.kind)) +\(ln.value)\(ln.pct ? "%" : "")", GameScene.potGradeColor(p.grade), 11); y -= 15 }
                btn("✅ 교체(새 잠재로)", -h/2 + 58, "cube_apply", SKColor(red:0.2,green:0.55,blue:0.32,alpha:1))
                btn("↩︎ 유지(기존 잠재)", -h/2 + 24, "cube_keep",  SKColor(white:0.32,alpha:1))
            } else {                                    // ── 큐브 3종 버튼 ──
                line("레드 6/1.8/0.3% · 블랙 15/3.5/1.4%(유지·교체)", SKColor(white:0.7,alpha:1), 10); y -= 4
                btn("🔴 레드 큐브 ×\(redCubes) — 메인 재설정", -h/2 + 92, "cube_red",
                    redCubes > 0 ? SKColor(red:0.6,green:0.2,blue:0.2,alpha:1) : SKColor(white:0.3,alpha:0.5))
                btn("⬛ 블랙 큐브 ×\(blackCubes) — 메인 (유지/교체)", -h/2 + 58, "cube_black",
                    blackCubes > 0 ? SKColor(red:0.25,green:0.25,blue:0.32,alpha:1) : SKColor(white:0.3,alpha:0.5))
                btn("🟢 에디셔널 큐브 ×\(addCubes) — 에디셔널", -h/2 + 24, "cube_add",
                    addCubes > 0 ? SKColor(red:0.2,green:0.5,blue:0.35,alpha:1) : SKColor(white:0.3,alpha:0.5))
            }
        }
        styleLabels(panel); hudLayer.addChild(panel); cubePanel = panel
    }
    func buildEquippedPanel() {
        let panel = SKNode(); panel.zPosition = 100; panel.name = "equippedPanel"
        let w: CGFloat = 620, h: CGFloat = 432
        panel.position = panelPos["equipped"] ?? .zero
        let bg = SKSpriteNode(color: SKColor(white: 0.08, alpha: 0.96), size: CGSize(width: w, height: h)); bg.zPosition = -1; panel.addChild(bg)
        addDragBar(panel, "equipped", w: w, h: h, topY: h/2 - 22)
        let title = SKLabelNode(text: "착용 장비 · 🎀 치장(외형)"); title.fontSize = 17; title.fontColor = .white
        title.position = CGPoint(x: 0, y: h/2 - 22); panel.addChild(title)
        let close = SKLabelNode(text: "✕"); close.name = "equipped_close"; close.fontSize = 20; close.fontColor = .white
        close.position = CGPoint(x: w/2 - 20, y: h/2 - 24); panel.addChild(close)
        let r = CharacterRenderer.shared
        // ── 좌측: 부위 목록(클릭=선택) ──
        var sy = h/2 - 54
        for slot in CharSlot.allCases {
            let selected = slot == selEquipSlot
            let row = SKSpriteNode(color: selected ? SKColor(red:0.2,green:0.32,blue:0.5,alpha:1) : SKColor(white:0.14,alpha:1), size: CGSize(width: 300, height: 30))
            row.position = CGPoint(x: -w/2 + 158, y: sy); row.zPosition = 0; row.name = "selslot:\(slot.rawValue)"; panel.addChild(row)
            let lbl = SKLabelNode(text: slot.label); lbl.fontSize = 11; lbl.fontColor = SKColor(white:0.7,alpha:1)
            lbl.horizontalAlignmentMode = .left; lbl.verticalAlignmentMode = .center; lbl.position = CGPoint(x: -w/2 + 14, y: sy); lbl.zPosition = 0.2; panel.addChild(lbl)
            if let id = r.selection[slot] {
                if let tex = iconCache[id] {
                    let ic = SKSpriteNode(texture: tex); let s = tex.size(); let mx = max(s.width, s.height, 1)
                    ic.size = CGSize(width: s.width/mx*26, height: s.height/mx*26); ic.position = CGPoint(x: -w/2 + 62, y: sy); ic.zPosition = 0.2; panel.addChild(ic)
                } else { ensureIcon(id) }
                let st = enhanceStat[id] ?? 0, g = potentialGrade[id] ?? -1
                let nm = SKLabelNode(text: (st > 0 ? "+\(st) " : "") + CharacterRenderer.name(id))
                nm.fontSize = 11; nm.fontColor = st > 0 ? SKColor(red:0.55,green:1,blue:0.65,alpha:1) : .yellow
                nm.horizontalAlignmentMode = .left; nm.verticalAlignmentMode = .center; nm.position = CGPoint(x: -w/2 + 82, y: sy); nm.zPosition = 0.2; panel.addChild(nm)
                if g >= 0 {
                    let gl = SKLabelNode(text: "●"); gl.fontSize = 11; gl.fontColor = GameScene.potGradeColor(g)
                    gl.verticalAlignmentMode = .center; gl.position = CGPoint(x: -w/2 + 296, y: sy); gl.zPosition = 0.2; panel.addChild(gl)
                }
            } else {
                let nm = SKLabelNode(text: "(빈 칸)"); nm.fontSize = 11; nm.fontColor = .gray
                nm.horizontalAlignmentMode = .left; nm.verticalAlignmentMode = .center; nm.position = CGPoint(x: -w/2 + 82, y: sy); nm.zPosition = 0.2; panel.addChild(nm)
            }
            sy -= 33
        }
        // ── 우측: 선택 부위 컨트롤 ──
        let cx0: CGFloat = w/2 - 250   // 우측 영역 좌단
        func line(_ s: String, _ y: CGFloat, _ c: SKColor = .white, _ size: CGFloat = 12) {
            let l = SKLabelNode(text: s); l.fontSize = size; l.fontColor = c
            l.horizontalAlignmentMode = .left; l.verticalAlignmentMode = .center; l.position = CGPoint(x: cx0, y: y); l.zPosition = 0.2; panel.addChild(l)
        }
        func btn(_ s: String, _ x: CGFloat, _ y: CGFloat, _ wd: CGFloat, _ name: String, _ col: SKColor) {
            let b = SKSpriteNode(color: col, size: CGSize(width: wd, height: 22)); b.position = CGPoint(x: x, y: y); b.zPosition = 0.1; b.name = name; panel.addChild(b)
            let l = SKLabelNode(text: s); l.fontSize = 11; l.fontColor = .white; l.verticalAlignmentMode = .center; l.position = b.position; l.zPosition = 0.2; l.name = name; panel.addChild(l)
        }
        var ry = h/2 - 50
        let slot = selEquipSlot, selId = r.selection[slot]
        line("◆ \(slot.label)", ry, SKColor(red:0.7,green:0.85,blue:1,alpha:1), 13); ry -= 24
        if let id = selId {
            let st = enhanceStat[id] ?? 0
            line((st>0 ? "+\(st) " : "") + CharacterRenderer.name(id) + "  ⭐\(starForce[id] ?? 0)", ry, st>0 ? SKColor(red:0.55,green:1,blue:0.65,alpha:1) : .yellow); ry -= 20
            let a = itemATK(slot, id), d = itemDEF(slot, id)
            line("⚔️ \(a)   🛡️ \(d)", ry, SKColor(white:0.85,alpha:1)); ry -= 22
            // 잠재옵션 (메인 + 에디셔널)
            if let g = potentialGrade[id] {
                line("잠재 [\(GameScene.potGradeNames[g])]", ry, GameScene.potGradeColor(g)); ry -= 18
                for ln in (potentialLines[id] ?? []) { line("· \(GameScene.potKindLabel(ln.kind)) +\(ln.value)\(ln.pct ? "%" : "")", ry, GameScene.potGradeColor(g), 11); ry -= 16 }
            } else { line("잠재: 없음 (큐브로 부여)", ry, SKColor(white:0.6,alpha:1), 11); ry -= 18 }
            if let ag = additionalGrade[id] {
                line("에디셔널 [\(GameScene.potGradeNames[ag])]", ry, GameScene.potGradeColor(ag), 11); ry -= 16
                for ln in (additionalLines[id] ?? []) { line("· \(GameScene.potKindLabel(ln.kind)) +\(ln.value)\(ln.pct ? "%" : "")", ry, GameScene.potGradeColor(ag), 11); ry -= 15 }
            }
            line("강화·별·잠재는 I(인벤)에서 아이템 선택 → 강화 버튼", ry, SKColor(white:0.55,alpha:1), 10); ry -= 20
        } else {
            line("비어 있음 — I(인벤)에서 장착", ry, SKColor(white:0.6,alpha:1)); ry -= 20
        }
        // ── 우측 하단: 치장(외형) — 이 부위에 입힐 수 있는 외형 나열(클릭=적용, 무료) ──
        ry -= 4
        line("🎀 치장(외형) — 능력치·레벨 영향 없음", ry, SKColor(red:1,green:0.7,blue:0.85,alpha:1), 11); ry -= 18
        let curCash = r.cashSelection[slot]
        line("현재 외형: " + (curCash.map { CharacterRenderer.name($0) } ?? "원래 장비"), ry, SKColor(white:0.85,alpha:1), 11)
        btn("해제", cx0 + 210, ry, 40, "cashclr:\(slot.rawValue)", SKColor(white:0.3,alpha:1)); ry -= 24
        let cat = r.catalog[slot] ?? []
        let cols = 6, cell = 36
        for (k, cid) in cat.enumerated() {
            let col = k % cols, rw = k / cols
            let bx = cx0 + CGFloat(col)*CGFloat(cell) + 16, byy = ry - CGFloat(rw)*CGFloat(cell)
            let sel2 = (curCash ?? r.selection[slot]) == cid
            let cbx = SKSpriteNode(color: sel2 ? SKColor(red:0.55,green:0.32,blue:0.48,alpha:1) : SKColor(white:0.16,alpha:1), size: CGSize(width:31,height:31))
            cbx.position = CGPoint(x: bx, y: byy); cbx.zPosition = 0.1; cbx.name = "setcash:\(slot.rawValue):\(cid)"; panel.addChild(cbx)
            if let tex = iconCache[cid], tex.size().width > 1 {
                let ic = SKSpriteNode(texture: tex); let s = tex.size(); let mx = max(s.width,s.height,1)
                ic.size = CGSize(width: s.width/mx*26, height: s.height/mx*26); ic.position = cbx.position; ic.zPosition = 0.2; panel.addChild(ic)
            } else { ensureIcon(cid) }
        }
        // 합계 + 힌트
        let tot = SKLabelNode(text: "직업 \(job.label) · 데미지 ~\(maxDamage)  🛡️방어 \(bonusDEF)"); tot.fontSize = 12; tot.fontColor = .white
        tot.position = CGPoint(x: 0, y: -h/2 + 30); panel.addChild(tot)
        let hint = SKLabelNode(text: "부위 클릭=선택 · 더블클릭=벗기 · 우측 치장 클릭=외형 적용 · E 닫기"); hint.fontSize = 10; hint.fontColor = SKColor(white:0.7,alpha:1)
        hint.position = CGPoint(x: 0, y: -h/2 + 12); panel.addChild(hint)
        styleLabels(panel); hudLayer.addChild(panel); equippedPanel = panel
    }

    // ── 무기 종류·직업 판정 (maplestory 아이템 ID 앞자리로) ──
    // 무기 ID = 1 + 3자리 분류 + 일련번호. 분류 = (id/10000)%1000.
    static func weaponCategory(_ id: Int) -> Int { (id / 10000) % 1000 }
    static func weaponTypeName(_ id: Int) -> String {
        switch weaponCategory(id) {
        case 130: return "한손검"; case 131: return "한손도끼"; case 132: return "한손둔기"
        case 133: return "단검";   case 134: return "아대";     case 137: return "완드"
        case 138: return "스태프"; case 140: return "두손검";   case 141: return "두손도끼"
        case 142: return "두손둔기"; case 143: return "창";      case 144: return "폴암"
        case 145: return "활";     case 146: return "석궁";     case 147: return "아대"
        case 148: return "너클";   case 149: return "건";       default: return "무기"
        }
    }
    // 무기 종류 → 착용 가능 직업. nil = 공용/무기 아님(제한 없음).
    static func weaponJob(_ id: Int) -> Job? {
        switch weaponCategory(id) {
        case 130,131,132,140,141,142,143,144: return .warrior   // 검·도끼·둔기·창·폴암
        case 137,138:                         return .magician  // 완드·스태프
        case 145,146:                         return .archer    // 활·석궁
        case 133,134,147:                     return .thief     // 단검·아대(클로)
        default:                              return nil
        }
    }
    // 무기 레벨 제한 (maplestory.io reqLevel, 로컬 저장). 표에 없으면 0(제한 없음).
    static let weaponReqLevel: [Int: Int] = [
        1402061:120, 1302000:0, 1302005:15, 1312004:0, 1322000:15, 1302063:38, 1432014:20, 1442139:110,
        1302007:10, 1432000:10, 1402000:20, 1412000:25, 1312005:30, 1302020:35, 1432005:40, 1442005:50, 1312020:60, 1402005:90,
    ]
    static func weaponLevel(_ id: Int) -> Int { weaponReqLevel[id] ?? 0 }
    // 방어구·장신구 레벨 제한 (maplestory.io reqLevel). 모자/망토/옷/신발/장갑.
    static let armorReqLevel: [Int: Int] = [
        1001011:0, 1002357:50, 1002140:0, 1004073:0, 1003797:150, 1102000:50, 1102041:50, 1102085:65, 1102013:0, 1102222:0,
        1052434:13, 1050018:30, 1051031:48, 1053000:0, 1072018:31, 1072064:31, 1070006:0, 1072246:0, 1070003:0,
        1082002:0, 1082149:10, 1080000:0, 1082145:10, 1082515:10,
    ]
    // 캐시(외형 전용) 아이템 — maplestory.io metaInfo.cash=true. 능력치·레벨제한·강화 없음(치장 전용).
    static let cashItemIDs: Set<Int> = [20000, 20003, 20015, 20100, 21002, 30000, 30406, 34870, 1001011, 1004073, 1053000, 1070003, 1070006, 1072246, 1102222]
    static func isCash(_ id: Int) -> Bool { cashItemIDs.contains(id) }
    // 모든 장비 레벨 제한 (무기+방어구). 캐시·머리·얼굴 등은 0(제한 없음).
    static func equipLevel(_ id: Int) -> Int { isCash(id) ? 0 : (weaponReqLevel[id] ?? armorReqLevel[id] ?? 0) }
    // 상점 판매 무기(전사용, 레벨순) + 가격(레벨 기반)
    static let shopWeaponIDs: [Int] = [1302007, 1432000, 1402000, 1412000, 1312005, 1302020, 1432005, 1442005, 1312020, 1402005]
    static func weaponPrice(_ id: Int) -> Int { weaponLevel(id) * 30 + 150 }
    // 장착 불가 사유(nil=가능). 무기=직업+레벨, 그 외 장비=레벨 제한.
    func equipBlockReason(_ id: Int) -> String? {
        guard let slot = CharacterRenderer.shared.slotOf(id) else { return nil }
        if slot == .weapon, let j = GameScene.weaponJob(id), j != job { return "\(GameScene.weaponTypeName(id))은(는) \(j.label) 전용" }
        let req = GameScene.equipLevel(id)
        if level < req { return "\(slot.label) 착용 Lv.\(req) 필요 (현재 \(level))" }
        return nil
    }

    // ── 장착/해제 → 로컬 합성 재생성 ──
    func equipAppearanceItem(_ id: Int) {
        guard let slot = CharacterRenderer.shared.slotOf(id) else { return }
        if let reason = equipBlockReason(id) {   // 무기 직업·레벨 제한
            notify("\(reason) — 착용 불가", color: SKColor(red:1,green:0.5,blue:0.5,alpha:1))
            return
        }
        CharacterRenderer.shared.selection[slot] = id
        invSelectedID = 0                        // 장착되면 그리드에서 사라지므로 선택 해제
        regenerateAppearance()
        refreshInventoryPanel(); refreshEquippedPanel(); updateHUD()
    }
    func unequipAppearanceSlot(_ slot: CharSlot) {
        CharacterRenderer.shared.selection[slot] = nil
        regenerateAppearance()
        refreshInventoryPanel(); refreshEquippedPanel(); updateHUD()
    }
    // ── 장비 강화 (메이플 주문서, 선택한 종류로) ──
    // 강화: 장비별 업그레이드 횟수(슬롯) 안에서, 성공·실패 모두 1회 차감
    func enhanceItem(_ id: Int) {
        let red = SKColor(red:1,green:0.5,blue:0.5,alpha:1)
        guard id != 0, let slot = CharacterRenderer.shared.slotOf(id) else { notify("강화할 수 없는 아이템", color: .gray); return }
        guard slotEnhanceable(slot) else { notify("\(slot.label)은(는) 강화할 수 없어", color: .gray); return }
        guard !GameScene.isCash(id) else { notify("캐시(치장) 아이템은 강화할 수 없어", color: .gray); return }
        let used = upgradeUsed[id] ?? 0, maxS = maxSlots(slot)
        guard used < maxS else { notify("업그레이드 가능 횟수 소진 (\(used)/\(maxS))", color: SKColor(red:1,green:0.85,blue:0.3,alpha:1)); return }
        let sc = GameScene.scrollTypes[selectedScroll]
        guard scrollCounts[selectedScroll] > 0 else { notify("\(sc.emoji) \(sc.name)가 없어 — 구매 필요", color: red); return }
        scrollCounts[selectedScroll] -= 1
        upgradeUsed[id] = used + 1                                  // 성공·실패 모두 횟수 차감
        let cur = enhanceStat[id] ?? 0
        if Double.random(in: 0..<1) < sc.rate {
            enhanceStat[id] = cur + sc.gain
            notify("✨ 강화 성공! \(CharacterRenderer.name(id)) +\(cur + sc.gain) (\(used+1)/\(maxS))", color: SKColor(red:0.5,green:1,blue:0.6,alpha:1))
            spawnHitSpark(at: CGPoint(x: player.position.x, y: player.position.y + 10), crit: true)
        } else if sc.failDrop > 0 && cur > 0 {
            enhanceStat[id] = max(0, cur - sc.failDrop)
            notify("💢 강화 실패! 스탯 하락 (\(used+1)/\(maxS))", color: red)
        } else {
            notify("💢 강화 실패… 횟수만 소모 (\(used+1)/\(maxS))", color: red)
        }
        refreshEquippedPanel(); refreshCubePanel(); updateHUD(); saveProgress()
    }
    func cycleScroll() { selectedScroll = (selectedScroll + 1) % GameScene.scrollTypes.count; refreshEquippedPanel(); refreshCubePanel() }

    // ── 큐브: 잠재옵션 리롤 ──
    static let potGradeNames = ["레어", "에픽", "유니크", "레전더리"]
    // 등급업 확률 (메이플 공식): 블랙 큐브 = 레어→에픽 15% · 에픽→유니크 3.5% · 유니크→레전 1.4%
    static let cubeTierUp: [Double] = [0.15, 0.035, 0.014]            // 블랙 큐브
    static let cubeTierUpRed: [Double] = [0.06, 0.018, 0.003]         // 레드 큐브(블랙보다 낮음)
    static let cubeTierUpAdd: [Double] = [0.045, 0.012, 0.0025]       // 에디셔널 큐브
    static func cubeTierRates(_ kind: CubeKind) -> [Double] {
        switch kind { case .red: return cubeTierUpRed; case .black: return cubeTierUp; case .additional: return cubeTierUpAdd }
    }
    static func potGradeColor(_ g: Int) -> SKColor {
        switch g { case 1: return SKColor(red:0.6,green:0.4,blue:1,alpha:1); case 2: return SKColor(red:1,green:0.8,blue:0.2,alpha:1); case 3: return SKColor(red:0.4,green:1,blue:0.5,alpha:1); default: return SKColor(red:0.4,green:0.7,blue:1,alpha:1) }
    }
    // 공식 줄별 등급 규칙(블랙 큐브): 1번째 줄 100% 동급, 2번째 동급 20%, 3번째 동급 5% (아니면 한 단계 아래).
    static let lineSameByPosition: [Double] = [1.0, 0.20, 0.05]   // index = 줄 위치(0/1/2)
    // 잠재 옵션 스펙 (부위공통/전용 + 고정/% + 등급·아이템레벨별 수치). scope: 0=부위공통, 1=무기·장갑전용, 2=방어구전용
    struct PotSpec { let kind: PotKind; let pct: Bool; let scope: Int; let unit: Double; let levelScaled: Bool; let weight: Int; let minGrade: Int }
    static let potSpecs: [PotSpec] = [
        // ── 부위공통 (모든 장비) ──
        PotSpec(kind:.str, pct:false, scope:0, unit:2,  levelScaled:true,  weight:13, minGrade:0),
        PotSpec(kind:.dex, pct:false, scope:0, unit:2,  levelScaled:true,  weight:13, minGrade:0),
        PotSpec(kind:.int, pct:false, scope:0, unit:2,  levelScaled:true,  weight:13, minGrade:0),
        PotSpec(kind:.luk, pct:false, scope:0, unit:2,  levelScaled:true,  weight:13, minGrade:0),
        PotSpec(kind:.hp,  pct:false, scope:0, unit:25, levelScaled:true,  weight:9,  minGrade:0),
        PotSpec(kind:.mp,  pct:false, scope:0, unit:20, levelScaled:true,  weight:7,  minGrade:0),
        PotSpec(kind:.str, pct:true,  scope:0, unit:1,  levelScaled:false, weight:6,  minGrade:1),
        PotSpec(kind:.dex, pct:true,  scope:0, unit:1,  levelScaled:false, weight:6,  minGrade:1),
        PotSpec(kind:.int, pct:true,  scope:0, unit:1,  levelScaled:false, weight:6,  minGrade:1),
        PotSpec(kind:.luk, pct:true,  scope:0, unit:1,  levelScaled:false, weight:6,  minGrade:1),
        PotSpec(kind:.allstat, pct:true, scope:0, unit:1, levelScaled:false, weight:4, minGrade:2),  // 올스탯% (유니크+)
        PotSpec(kind:.hp,  pct:true,  scope:0, unit:1,  levelScaled:false, weight:6,  minGrade:1),
        PotSpec(kind:.mp,  pct:true,  scope:0, unit:1,  levelScaled:false, weight:4,  minGrade:1),
        // ── 무기·장갑 전용 ──
        PotSpec(kind:.atk, pct:false, scope:1, unit:2,  levelScaled:true,  weight:16, minGrade:0),
        PotSpec(kind:.atk, pct:true,  scope:1, unit:2,  levelScaled:false, weight:8,  minGrade:1),  // 공격력%
        PotSpec(kind:.dmg, pct:true,  scope:1, unit:2,  levelScaled:false, weight:6,  minGrade:1),  // 데미지%
        PotSpec(kind:.crit,pct:true,  scope:1, unit:2,  levelScaled:false, weight:6,  minGrade:1),  // 크리티컬 확률%
        // ── 방어구 전용 ──
        PotSpec(kind:.def, pct:false, scope:2, unit:2,  levelScaled:true,  weight:16, minGrade:0),
        PotSpec(kind:.def, pct:true,  scope:2, unit:1,  levelScaled:false, weight:8,  minGrade:1),  // 방어력%
    ]
    // 아이템 레벨 → 수치 배율 구간 (0~9 / 10~39 / 40~79 / 80~119 / 120+)
    static func levelTier(_ lv: Int) -> Int {
        switch lv { case ..<10: return 0; case 10..<40: return 1; case 40..<80: return 2; case 80..<120: return 3; default: return 4 } }
    // 한 줄 추첨: 부위(무기/방어구) + 등급 + 아이템레벨 → (종류, 수치, %여부)
    static func rollPotLine(weapon: Bool, grade g: Int, itemLevel lv: Int) -> (kind: PotKind, value: Int, pct: Bool) {
        let lt = levelTier(lv)
        let pool = potSpecs.filter { ($0.scope == 0 || $0.scope == (weapon ? 1 : 2)) && g >= $0.minGrade }
        guard !pool.isEmpty else { return (.str, g + 1, false) }
        let total = pool.reduce(0) { $0 + $1.weight }
        var r = Int.random(in: 0..<max(1, total)); var pick = pool[0]
        for s in pool { if r < s.weight { pick = s; break }; r -= s.weight }
        let val: Int = pick.pct
            ? max(1, Int((pick.unit * Double(g + 1)).rounded()))                              // % = 등급 비례(레벨 무관)
            : max(1, Int((pick.unit * Double(g + 1) * (1 + Double(lt) * 0.5)).rounded()))      // 고정 = 등급 × 아이템레벨 구간
        return (pick.kind, val, pick.pct)
    }
    // ── 별 강화(스타포스) — ★마다 능력치↑, 성공/실패/파괴 ──
    static let maxStar = 15
    static let starRates: [Double] = [0.95,0.90,0.85,0.85,0.80,0.75,0.70,0.65,0.60,0.55,0.50,0.45,0.40,0.35,0.30]  // ★0..14 성공률
    static func starCost(_ star: Int) -> Int { 100 + (star+1)*(star+1)*50 }   // ★ 올릴수록 메소 급증
    func starUp(_ id: Int) {
        let red = SKColor(red:1,green:0.5,blue:0.5,alpha:1)
        guard id != 0, let slot = CharacterRenderer.shared.slotOf(id) else { notify("별 강화할 수 없는 아이템", color:.gray); return }
        guard slotEnhanceable(slot) else { notify("\(slot.label)은(는) 별 강화 불가", color:.gray); return }
        guard !GameScene.isCash(id) else { notify("캐시(치장) 아이템은 별 강화 불가", color: .gray); return }
        let star = starForce[id] ?? 0
        guard star < GameScene.maxStar else { notify("⭐ 이미 최대 \(GameScene.maxStar)성", color: SKColor(red:1,green:0.85,blue:0.3,alpha:1)); return }
        let cost = GameScene.starCost(star)
        guard gold >= cost else { notify("메소 부족 (★강화 \(cost))", color: red); return }
        gold -= cost
        var success = false, failed = false
        if Double.random(in:0..<1) < GameScene.starRates[min(star, GameScene.starRates.count-1)] {
            starForce[id] = star + 1; success = true
            notify("⭐ 별 강화 성공! ★\(star+1)  \(CharacterRenderer.name(id))", color: SKColor(red:1,green:0.9,blue:0.3,alpha:1))
            spawnHitSpark(at: CGPoint(x: player.position.x, y: player.position.y + 10), crit: true)
        } else if star >= 13 && Double.random(in:0..<1) < 0.05 {       // 13성+ 5% 파괴
            notify("💥 펑! \(CharacterRenderer.name(id)) 파괴됨…", color: red)
            for _ in 0..<8 { popText("💥", at: CGPoint(x: player.position.x + .random(in: -30...30), y: player.position.y + .random(in: 0...50)), color: red, size: 22) }
            destroyItem(id); return
        } else if star >= 11 {                                          // 11성+ 실패 시 한 단계 하락
            starForce[id] = max(0, star - 1); failed = true
            notify("💢 별 강화 실패 — ★\(max(0,star-1))로 하락", color: red)
        } else {
            failed = true
            notify("💢 별 강화 실패 — ★\(star) 유지", color: red)
        }
        clampHP(); refreshEquippedPanel(); refreshCubePanel(); refreshInventoryPanel(); updateHUD(); saveProgress()
        if success { flashCubePanel(tierUp: true, grade: 2, banner: "⭐ ★\(starForce[id] ?? 0) 강화 성공! ⭐") }   // 새 패널 위에 연출
        else if failed { failFlashCubePanel(destroyed: false) }
    }
    func destroyItem(_ id: Int) {   // 파괴: 장착 해제 + 보유/강화/별/잠재 데이터 정리
        for (slot, sid) in CharacterRenderer.shared.selection where sid == id { CharacterRenderer.shared.selection[slot] = nil }
        ownedAppearance.remove(id)
        starForce[id] = nil; enhanceStat[id] = nil; upgradeUsed[id] = nil; potentialGrade[id] = nil; potentialLines[id] = nil
        additionalGrade[id] = nil; additionalLines[id] = nil
        if pendingCube?.id == id { pendingCube = nil }
        if invSelectedID == id { invSelectedID = 0 }
        if cubeItemID == id { closeCubeWindow() }
        regenerateAppearance(); refreshEquippedPanel(); refreshInventoryPanel(); updateHUD(); saveProgress()
    }
    // 큐브 1개 사용 → 등급업 시도 + 3줄 재설정. (장비창 아닌 큐브 전용 창에서 호출)
    // 큐브 보유 수 접근
    func cubeCount(_ kind: CubeKind) -> Int { switch kind { case .red: return redCubes; case .black: return blackCubes; case .additional: return addCubes } }
    func consumeCube(_ kind: CubeKind) { switch kind { case .red: redCubes -= 1; case .black: blackCubes -= 1; case .additional: addCubes -= 1 } }

    // 새 잠재(등급+3줄) 굴리기. additional=에디셔널 대상. tier-up 확률은 큐브별.
    func rollNewPotential(_ id: Int, kind: CubeKind) -> (grade: Int, lines: [(kind: PotKind, value: Int, pct: Bool)], leveledUp: Bool) {
        guard let slot = CharacterRenderer.shared.slotOf(id) else { return (0, [], false) }
        let additional = (kind == .additional)
        let gradeMap = additional ? additionalGrade : potentialGrade
        let first = gradeMap[id] == nil
        let oldG = gradeMap[id] ?? 0
        var g = oldG
        let rates = GameScene.cubeTierRates(kind)
        if !first && g < 3 && Double.random(in:0..<1) < rates[g] { g += 1 }      // 등급업(큐브별 공식 확률)
        let weapon = (slot == .weapon || slot == .gloves)
        let itemLevel = max(GameScene.weaponLevel(id), level)
        var lines: [(kind: PotKind, value: Int, pct: Bool)] = []
        for i in 0..<3 {                                                          // 1줄=동급확정, 2줄 20%, 3줄 5%
            let tier = (Double.random(in:0..<1) < GameScene.lineSameByPosition[i]) ? g : max(0, g - 1)
            lines.append(GameScene.rollPotLine(weapon: weapon, grade: tier, itemLevel: itemLevel))
        }
        return (g, lines, !first && g > oldG)
    }

    func useCubeKind(_ id: Int, _ kind: CubeKind) {
        guard id != 0, let slot = CharacterRenderer.shared.slotOf(id) else { notify("잠재 설정 불가 아이템", color: .gray); return }
        guard slotEnhanceable(slot) else { notify("\(slot.label)은(는) 잠재 설정 불가", color: .gray); return }
        guard !GameScene.isCash(id) else { notify("캐시(치장) 아이템은 잠재 설정 불가", color: .gray); return }
        guard pendingCube == nil else { notify("먼저 블랙 큐브 결과를 선택하세요(유지/교체)", color: SKColor(red:1,green:0.8,blue:0.4,alpha:1)); return }
        let names: [CubeKind:String] = [.red:"레드 큐브", .black:"블랙 큐브", .additional:"에디셔널 큐브"]
        guard cubeCount(kind) > 0 else { notify("\(names[kind]!)가 없어 — 상점에서 구매", color: SKColor(red:1,green:0.5,blue:0.5,alpha:1)); return }
        consumeCube(kind)
        let roll = rollNewPotential(id, kind: kind)
        let additional = (kind == .additional)
        if kind == .black {                                  // 블랙 = 결과 보여주고 유지/교체 선택
            pendingCube = (id, roll.grade, roll.lines, additional)
            notify("⬛ 블랙 큐브 — 새 잠재를 확인하고 유지/교체를 선택하세요", color: GameScene.potGradeColor(roll.grade))
            refreshCubePanel()
        } else {                                             // 레드/에디셔널 = 즉시 적용
            if additional { additionalGrade[id] = roll.grade; additionalLines[id] = roll.lines }
            else          { potentialGrade[id]  = roll.grade; potentialLines[id]  = roll.lines }
            notify("🧊 \(CharacterRenderer.name(id)) [\(GameScene.potGradeNames[roll.grade])] \(additional ? "에디셔널 " : "")잠재 재설정!", color: GameScene.potGradeColor(roll.grade))
            clampHP(); refreshEquippedPanel(); refreshCubePanel(); updateHUD(); saveProgress()
            flashCubePanel(tierUp: roll.leveledUp, grade: roll.grade)
        }
    }
    // 블랙 큐브 결과 선택: apply=true면 새 잠재로 교체(after), false면 기존 유지(before)
    func resolvePending(apply: Bool) {
        guard let p = pendingCube else { return }
        pendingCube = nil
        if apply {
            if p.additional { additionalGrade[p.id] = p.grade; additionalLines[p.id] = p.lines }
            else            { potentialGrade[p.id]  = p.grade; potentialLines[p.id]  = p.lines }
            notify("⬛ 교체 완료 — [\(GameScene.potGradeNames[p.grade])]\(p.additional ? " 에디셔널" : "") 잠재", color: GameScene.potGradeColor(p.grade))
            clampHP(); refreshEquippedPanel(); updateHUD()
        } else {
            notify("⬛ 기존 잠재 유지", color: SKColor(white:0.85,alpha:1))
        }
        refreshCubePanel(); saveProgress()
    }
    // (구 호환) 단일 큐브 진입점 → 레드로
    func useCube(_ id: Int) { useCubeKind(id, .red) }
    // 큐브 사용 연출: 패널 살짝 어두워졌다 밝아짐 + 등급업이면 반짝이
    func flashCubePanel(tierUp: Bool, grade: Int, banner bannerText: String? = nil) {
        guard let panel = cubePanel else { return }
        panel.removeAction(forKey: "flash")
        panel.alpha = 0.45
        panel.run(.fadeAlpha(to: 1, duration: 0.22), withKey: "flash")   // 어두워졌다 → 밝아짐
        guard tierUp else { return }
        let color = GameScene.potGradeColor(grade)
        for i in 0..<14 {                                                // 등급업 반짝이 파티클
            let star = SKLabelNode(text: "✨"); star.fontSize = CGFloat.random(in: 14...26)
            star.fontColor = color; star.zPosition = 5
            star.position = CGPoint(x: CGFloat.random(in: -120...120), y: CGFloat.random(in: -60...90))
            star.alpha = 0; star.setScale(0.2); panel.addChild(star)
            let delay = Double(i) * 0.018
            star.run(.sequence([
                .wait(forDuration: delay),
                .group([.fadeAlpha(to: 1, duration: 0.12), .scale(to: 1, duration: 0.18),
                        .moveBy(x: 0, y: 22, duration: 0.6)]),
                .fadeOut(withDuration: 0.35), .removeFromParent()]))
        }
        for d in [0.0, 0.12] {                                          // 확장하는 빛 고리 2겹
            let ring = SKShapeNode(circleOfRadius: 20); ring.strokeColor = color; ring.lineWidth = 6
            ring.glowWidth = 5; ring.fillColor = .clear; ring.blendMode = .add; ring.zPosition = 4; ring.alpha = 0; ring.position = CGPoint(x: 0, y: 10)
            panel.addChild(ring)
            ring.run(.sequence([.wait(forDuration: d), .fadeAlpha(to: 0.9, duration: 0.02),
                                .group([.scale(to: 9, duration: 0.4), .fadeOut(withDuration: 0.45)]), .removeFromParent()]))
        }
        let banner = SKLabelNode(text: bannerText ?? "⭐ \(GameScene.potGradeNames[grade]) 등급 업! ⭐")
        banner.fontSize = 18; banner.fontColor = color; banner.zPosition = 6
        banner.position = CGPoint(x: 0, y: 8); banner.setScale(0.5); banner.alpha = 0
        styleLabels(banner); panel.addChild(banner)
        banner.run(.sequence([.group([.fadeAlpha(to: 1, duration: 0.15), .scale(to: 1.15, duration: 0.22)]),
                              .scale(to: 1.0, duration: 0.12), .wait(forDuration: 0.7), .fadeOut(withDuration: 0.4), .removeFromParent()]))
    }
    // 강화 실패/파괴 연출: 패널 붉게 떨림 + 문구
    func failFlashCubePanel(destroyed: Bool) {
        guard let panel = cubePanel else { return }
        let red = SKColor(red:1,green:0.25,blue:0.2,alpha:1)
        let flash = SKSpriteNode(color: red, size: CGSize(width: 380, height: 410)); flash.zPosition = 3; flash.alpha = 0; flash.blendMode = .add
        panel.addChild(flash); flash.run(.sequence([.fadeAlpha(to: destroyed ? 0.6 : 0.35, duration: 0.05), .fadeOut(withDuration: 0.3), .removeFromParent()]))
        // 좌우 흔들림
        panel.removeAction(forKey: "shake")
        let amp: CGFloat = destroyed ? 14 : 8; let base = panel.position
        panel.run(.sequence([.moveBy(x: amp, y: 0, duration: 0.04), .moveBy(x: -amp*2, y: 0, duration: 0.07),
                             .moveBy(x: amp*2, y: 0, duration: 0.07), .moveBy(x: -amp*1.5, y: 0, duration: 0.06),
                             .moveBy(x: amp, y: 0, duration: 0.05), .move(to: base, duration: 0.04)]), withKey: "shake")
        let n = destroyed ? 16 : 8
        for i in 0..<n {                                                 // 💢/💥 파편
            let p = SKLabelNode(text: destroyed ? "💥" : "💢"); p.fontSize = CGFloat.random(in: 14...24); p.zPosition = 5
            p.position = CGPoint(x: CGFloat.random(in: -110...110), y: CGFloat.random(in: -50...80)); p.alpha = 0
            panel.addChild(p)
            p.run(.sequence([.wait(forDuration: Double(i)*0.015), .fadeAlpha(to: 1, duration: 0.1),
                             .group([.moveBy(x: CGFloat.random(in: -20...20), y: -24, duration: 0.5), .fadeOut(withDuration: 0.4)]), .removeFromParent()]))
        }
    }
    // 상점 구매(주문서/큐브) — 구매는 상점에서만
    static let scrollIcons = [2043021, 2040727, 2049000]   // maplestory.io 아이콘 id (일반/고급/혼돈)
    static let cubeIconID = 5062010                          // 블랙 큐브 아이콘
    static let cubeIconRed = 5062009                         // 레드 큐브(Red Cube)
    static let cubeIconBlack = 5062010                       // 블랙 큐브(Black Cube)
    static let cubeIconAdd = 5062500                         // 에디셔널 큐브(Bonus Potential Cube)
    static let cubePrice = 70
    static let cubePriceRed = 70       // 레드 큐브(낮은 승급)
    static let cubePriceBlack = 220    // 블랙 큐브(높은 승급 + 유지/교체)
    static let cubePriceAdd = 150      // 에디셔널 큐브
    func buyScrollAt(_ idx: Int) {
        let sc = GameScene.scrollTypes[idx]
        guard gold >= sc.price else { notify("메소 부족 (\(sc.name) \(sc.price)메소)", color: SKColor(red:1,green:0.5,blue:0.5,alpha:1)); return }
        gold -= sc.price; scrollCounts[idx] += 1
        notify("\(sc.emoji) \(sc.name) 구매! (×\(scrollCounts[idx]))", color: SKColor(red:1,green:0.85,blue:0.3,alpha:1))
        refreshShopPanel(); updateHUD(); saveProgress()
    }
    func buyCube(_ kindStr: String) {
        let red = SKColor(red:1,green:0.5,blue:0.5,alpha:1)
        let (price, name): (Int, String)
        switch kindStr {
        case "black": price = GameScene.cubePriceBlack; name = "블랙 큐브"
        case "add":   price = GameScene.cubePriceAdd;   name = "에디셔널 큐브"
        default:      price = GameScene.cubePriceRed;   name = "레드 큐브"
        }
        guard gold >= price else { notify("메소 부족 (\(name) \(price)메소)", color: red); return }
        gold -= price
        switch kindStr { case "black": blackCubes += 1; case "add": addCubes += 1; default: redCubes += 1 }
        notify("🧊 \(name) 구매!", color: SKColor(red:0.6,green:0.85,blue:1,alpha:1))
        refreshShopPanel(); updateHUD(); saveProgress()
    }
    func buyWeapon(_ id: Int) {
        let price = GameScene.weaponPrice(id)
        if ownedAppearance.contains(id) { notify("이미 보유한 무기예요 — I에서 장착", color: .gray); return }
        guard gold >= price else { notify("메소 부족 (\(CharacterRenderer.name(id)) \(price))", color: SKColor(red:1,green:0.5,blue:0.5,alpha:1)); return }
        gold -= price; ownedAppearance.insert(id); ensureIcon(id)
        notify("🗡️ \(CharacterRenderer.name(id)) 구매! (I 인벤에서 장착)", color: SKColor(red:1,green:0.85,blue:0.3,alpha:1))
        refreshShopPanel(); updateHUD(); saveProgress()
    }
    func appearanceSellPrice(_ id: Int) -> Int { max(1, Int(Double(GameScene.weaponPrice(id)) * sellFraction)) }
    func sellAppearance(_ id: Int) {
        guard ownedAppearance.contains(id) else { return }
        if CharacterRenderer.shared.selection.values.contains(id) { notify("착용 중인 장비는 못 팔아 — 먼저 해제(E)", color: .gray); return }
        let price = appearanceSellPrice(id)
        ownedAppearance.remove(id); gold += price
        notify("💰 \(CharacterRenderer.name(id)) 판매 (+\(price))", color: SKColor(red:1,green:0.84,blue:0.2,alpha:1))
        refreshShopPanel(); refreshInventoryPanel(); updateHUD(); saveProgress()
    }
    func clampHP() { if hp > maxHP { hp = maxHP } }   // 장비/잠재 변경으로 maxHP 줄면 현재 HP도 맞춤
    func regenerateAppearance() {
        clampHP()                                     // 장착/해제로 HP 잠재 줄었을 때
        let r = CharacterRenderer.shared
        let key = CharacterRenderer.comboKey(r.currentItems())
        if let c = comboTexCache[key] {                       // 메모리 캐시 → 즉시 적용(딜레이 없음)
            applyComboTex(c); saveProgress(); refreshEquippedPanel(); return
        }
        if r.regenerating { pendingRegen = true; return }     // 진행 중이면 끝나고 재시도
        r.regenerate(items: r.currentItems()) { [weak self] result in
            guard let self else { return }
            if let result {
                self.reloadCharacter(result, cacheKey: key); self.saveProgress()
                self.refreshEquippedPanel(); self.refreshInventoryPanel()   // 합성 완료 후 아바타·아이콘 갱신
            }
            if self.pendingRegen { self.pendingRegen = false; self.regenerateAppearance() }
        }
    }

    // ── 드랍: 처치 시 18% 확률로 외형 아이템 획득 ──
    func maybeDropAppearance(at pos: CGPoint) {
        guard Double.random(in: 0..<1) < 0.18 else { return }
        let r = CharacterRenderer.shared
        let pool = r.catalog.values.flatMap { $0 }.filter { !ownedAppearance.contains($0) }
        guard let id = pool.randomElement() else { return }
        ownedAppearance.insert(id)
        r.prefetchItem(id)
        popText("🎁 \(CharacterRenderer.name(id)) 획득!", at: CGPoint(x: pos.x, y: pos.y + 46),
                color: SKColor(red: 0.6, green: 0.9, blue: 1, alpha: 1), size: 15)
        if inventoryOpen, invTab == 0 { refreshInventoryPanel() }
        saveProgress()
    }

    // ── 호버 툴팁 ──
    // 장비 한 점의 능력치 툴팁(기본 + 강화누적 + 잠재). equipped면 ✓장착중 표시.
    func equipTooltip(id: Int, slot: CharSlot, equipped: Bool, footer: String) -> String {
        var s = "\(CharacterRenderer.name(id))\n[\(slot.label)]" + (equipped ? "  ✓장착중" : "")
        if GameScene.isCash(id) { s += "\n🎀 캐시(치장) — 외형 전용, 능력치·레벨 없음" }
        if slot == .weapon {   // 무기: 종류 + 착용 직업 + 레벨 제한
            let t = GameScene.weaponTypeName(id)
            if let j = GameScene.weaponJob(id) {
                s += "\n🗡️ \(t) · 착용: \(j.label)" + (j == job ? "" : " (현재 직업 불가)")
            } else { s += "\n🗡️ \(t)" }
        }
        let req = GameScene.equipLevel(id)   // 모든 장비 레벨 제한
        if req > 0 { s += "\n⭐ 착용 Lv.\(req)" + (level < req ? " (현재 \(level) 부족)" : "") }
        let atk = itemATK(slot, id), def = itemDEF(slot, id)
        var stat: [String] = []
        if atk > 0 { stat.append("⚔️ \(atk)") }
        if def > 0 { stat.append("🛡️ \(def)") }
        if !stat.isEmpty { s += "\n" + stat.joined(separator: "   ") }
        if slotEnhanceable(slot) {
            let used = upgradeUsed[id] ?? 0, mx = maxSlots(slot), enh = enhanceStat[id] ?? 0
            s += "\n📜 강화 \(used)/\(mx)" + (enh > 0 ? " (+\(enh))" : "")
            let star = starForce[id] ?? 0
            if star > 0 { s += "   ⭐\(star)" }
        }
        if let g = potentialGrade[id] {
            s += "\n🧊 [\(GameScene.potGradeNames[g])]"
            for ln in (potentialLines[id] ?? []) { s += "\n· \(GameScene.potKindLabel(ln.kind)) +\(ln.value)\(ln.pct ? "%" : "")" }
        }
        if let ag = additionalGrade[id] {
            s += "\n🧊 에디셔널 [\(GameScene.potGradeNames[ag])]"
            for ln in (additionalLines[id] ?? []) { s += "\n· \(GameScene.potKindLabel(ln.kind)) +\(ln.value)\(ln.pct ? "%" : "")" }
        }
        if !footer.isEmpty { s += "\n\(footer)" }
        return s
    }
    func tooltipText(forNode name: String) -> String? {
        if name.hasPrefix("appitem:"), let id = Int(name.dropFirst(8)) {
            let slot = CharacterRenderer.shared.slotOf(id) ?? .weapon
            let equipped = CharacterRenderer.shared.selection.values.contains(id)
            return equipTooltip(id: id, slot: slot, equipped: equipped, footer: "더블클릭 → 장착")
        }
        if name.hasPrefix("useitem:") || name.hasPrefix("etcitem:"), let item = ItemCatalog.item(String(name.dropFirst(8))) {
            var s = "\(item.emoji) \(item.name)"
            let info = itemShortStat(item); if !info.isEmpty { s += "\n\(info)" }
            if item.healHPamount > 0 { s += "\nHP +\(item.healHPamount)" }
            if item.healMPamount > 0 { s += (item.healHPamount > 0 ? "   " : "\n") + "MP +\(item.healMPamount)" }
            return s
        }
        if name.hasPrefix("selslot:"), let slot = CharSlot(rawValue: String(name.dropFirst(8))), let id = CharacterRenderer.shared.selection[slot] {
            return equipTooltip(id: id, slot: slot, equipped: true, footer: "클릭=선택 · 더블클릭=해제")
        }
        return nil
    }
    override func mouseMoved(with event: NSEvent) {
        guard inventoryOpen || equippedWindowOpen else { if hoverTooltip != nil { hideTooltip() }; return }
        let p = event.location(in: self)
        var found: String? = nil
        for n in nodes(at: p) {
            if let nm = n.name, nm.hasPrefix("appitem:") || nm.hasPrefix("useitem:") || nm.hasPrefix("etcitem:") || nm.hasPrefix("selslot:") { found = nm; break }
        }
        if let nm = found {
            if nm == hoverKey { return }
            hoverKey = nm; showTooltip(nm, at: p)
        } else if hoverTooltip != nil { hideTooltip() }
    }
    func showTooltip(_ name: String, at scenePoint: CGPoint) {
        hideTooltip()
        guard let text = tooltipText(forNode: name) else { return }
        let hudP = hudLayer.convert(scenePoint, from: self)
        let node = SKNode(); node.zPosition = 2000; node.name = "tooltip"
        let lines = text.components(separatedBy: "\n")
        let lh: CGFloat = 17, pad: CGFloat = 9
        var maxW: CGFloat = 0; var labels: [SKLabelNode] = []
        for (i, line) in lines.enumerated() {
            let l = SKLabelNode(text: line); l.fontSize = 13; l.fontColor = i == 0 ? .white : SKColor(white: 0.85, alpha: 1)
            l.horizontalAlignmentMode = .left; l.verticalAlignmentMode = .center
            labels.append(l); maxW = max(maxW, l.frame.width)
        }
        let bw = maxW + pad * 2, bh = CGFloat(lines.count) * lh + pad * 2
        let bgr = SKShapeNode(rectOf: CGSize(width: bw, height: bh), cornerRadius: 5)
        bgr.fillColor = SKColor(white: 0.05, alpha: 0.96); bgr.strokeColor = SKColor(white: 0.5, alpha: 1); bgr.lineWidth = 1; bgr.zPosition = 0
        node.addChild(bgr)
        for (i, l) in labels.enumerated() { l.position = CGPoint(x: -bw/2 + pad, y: bh/2 - pad - lh/2 - CGFloat(i) * lh); l.zPosition = 1; node.addChild(l) }
        // 화면 경계 보정
        var px = hudP.x, py = hudP.y + bh/2 + 28
        px = min(max(px, -viewW/2 + bw/2 + 4), viewW/2 - bw/2 - 4)
        py = min(py, viewH/2 - bh/2 - 4)
        node.position = CGPoint(x: px, y: py)
        hudLayer.addChild(node); hoverTooltip = node
    }
    func hideTooltip() { hoverTooltip?.removeFromParent(); hoverTooltip = nil; hoverKey = "" }

    // mouseMoved 이벤트는 first-responder/창 상태에 따라 안 올 수 있어 → 매 프레임 마우스 위치 직접 폴링(확실).
    func updateHoverTooltip() {
        guard inventoryOpen || equippedWindowOpen else { if hoverTooltip != nil { hideTooltip() }; return }
        guard let view = self.view, let win = view.window else { return }
        let vp = view.convert(win.mouseLocationOutsideOfEventStream, from: nil)   // window→view
        let p = convertPoint(fromView: vp)                                        // view→scene
        var found: String? = nil
        for n in nodes(at: p) {
            if let nm = n.name, nm.hasPrefix("appitem:") || nm.hasPrefix("useitem:") || nm.hasPrefix("etcitem:") || nm.hasPrefix("selslot:") { found = nm; break }
        }
        if let nm = found {
            if nm != hoverKey {
                hoverKey = nm; showTooltip(nm, at: p)
                if nm.hasPrefix("appitem:"), let id = Int(nm.dropFirst(8)) { prefetchEquipPreview(id) }   // 미리 받아둠
            }
        } else if hoverTooltip != nil { hideTooltip() }
    }
    // 마우스 올린 외형 아이템의 "장착 후 조합"을 백그라운드에서 합성+디코드해 **메모리 캐시까지** 채움.
    // → 클릭 시 디스크/디코드/네트워크 없이 메모리 히트로 즉시 교체.
    func prefetchEquipPreview(_ id: Int) {
        let r = CharacterRenderer.shared
        guard let slot = r.slotOf(id) else { return }
        var sel = r.selection; sel[slot] = id
        let items = CharacterRenderer.baseItems.map { EquipPiece(id: $0) }
                  + CharSlot.allCases.compactMap { sel[$0].map { EquipPiece(id: $0) } }
        let key = CharacterRenderer.comboKey(items)
        if comboTexCache[key] != nil || prefetchingKeys.contains(key) { return }   // 이미 캐시됨/진행중
        prefetchingKeys.insert(key)
        let acts = CharacterRenderer.actions(forWeapon: sel[.weapon])
        equipPrefetchQueue.async { [weak self] in
            let result = CharacterRenderer.buildComboServer(items: items, actions: acts)
            let anims = result.map { CharacterRenderer.decodeTextures($0.framesPNG) }   // 디코드도 백그라운드
            DispatchQueue.main.async {
                guard let self else { return }
                self.prefetchingKeys.remove(key)
                if let result, let anims {
                    self.comboTexCache[key] = self.makeComboTex(anims, feet: result.feetFrac, center: result.bodyCenterFrac)
                }
            }
        }
    }
}
