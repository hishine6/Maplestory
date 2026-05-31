import SpriteKit
import AppKit
import Foundation

// 몬스터 종류·스킬·세이브는 GameData.swift, 표는 monsters.json / skills.json 에 있어요.

// 몬스터 한 마리 (화면 노드 + 종류 + 현재 상태)
@MainActor
final class Monster {
    let node: SKLabelNode
    let type: MonsterType
    var hp: Int
    var dir: CGFloat
    let minX: CGFloat
    let maxX: CGFloat
    let baseY: CGFloat
    var bobPhase: CGFloat = 0

    init(node: SKLabelNode, type: MonsterType, dir: CGFloat, minX: CGFloat, maxX: CGFloat, baseY: CGFloat) {
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
    var icon: SKLabelNode!
    var cdLabel: SKLabelNode!

    init(type: SkillType, keyCode: UInt16) { self.type = type; self.keyCode = keyCode }
}

// 게임의 "무대".
final class GameScene: SKScene {

    // ── 게임 느낌 조절 ────────────────────────────────────────
    let moveSpeed: CGFloat = 320
    let jumpSpeed: CGFloat = 620
    let gravity:   CGFloat = 1600
    let playerHalfH: CGFloat = 22
    let attackRange: CGFloat = 95

    // ── 플레이어 상태 ─────────────────────────────────────────
    var player: SKNode!
    var leftPressed = false
    var rightPressed = false
    var velocityY: CGFloat = 0
    var onGround = false
    var attackCooldown: CGFloat = 0

    let baseMaxHP = 100
    var maxHP: Int { baseMaxHP + bonusHP }   // 장비 HP 보너스 반영
    var hp = 100
    var invuln: CGFloat = 0

    let maxMP: CGFloat = 100
    var mp: CGFloat = 100
    let mpRegen: CGFloat = 12     // 초당 MP 회복량

    // ── 성장 상태 ─────────────────────────────────────────────
    var level = 1
    var xp = 0
    var kills = 0
    var xpToNext: Int { level * 3 }

    // ── 인벤토리 / 장비 ───────────────────────────────────────
    var inventory: [String] = []                 // 보유 아이템 id (중복 허용)
    var equipped: [EquipSlot: String] = [:]      // 부위 → 장착 아이템 id
    var inventoryOpen = false
    var inventoryPanel: SKNode?

    // ── 능력치 / AP (스탯 분배) ────────────────────────────────
    var statATK = 0          // ⚔️ 분배 (1 AP = +1 공격)
    var statDEF = 0          // 🛡️ 분배 (1 AP = +1 방어)
    var statHPpts = 0        // ❤️ 분배 (1 AP = +10 최대 HP)
    var unspentAP = 0        // 아직 안 쓴 능력치 포인트
    var statsOpen = false
    var statsPanel: SKNode?
    let apPerLevel = 3       // 레벨업마다 받는 AP
    let hpPerPoint = 10      // ❤️ 1포인트당 최대 HP
    var spentAP: Int { statATK + statDEF + statHPpts }

    // ── 골드 / 상점 ───────────────────────────────────────────
    var gold = 0
    let sellFraction: CGFloat = 0.5
    var shopOpen = false
    var shopPanel: SKNode?
    var anyModalOpen: Bool { inventoryOpen || statsOpen || shopOpen }

    // 장비에서 나오는 보너스
    var equippedItems: [ItemType] { equipped.values.compactMap { ItemCatalog.item($0) } }
    var equipATK: Int { equippedItems.reduce(0) { $0 + $1.attack } }
    var equipDEF: Int { equippedItems.reduce(0) { $0 + $1.defense } }
    var equipHP:  Int { equippedItems.reduce(0) { $0 + $1.hpBonus } }
    // 총 보너스 = 장비 + 분배 스탯 (전투 코드는 이걸 그대로 읽어요 → 수정 불필요)
    var bonusATK: Int { equipATK + statATK }
    var bonusDEF: Int { equipDEF + statDEF }
    var bonusHP:  Int { equipHP  + statHPpts * hpPerPoint }

    // ── 월드 크기 (뷰포트 720x480과 분리) ──────────────────────
    let worldW: CGFloat = 2400
    let worldH: CGFloat = 900
    var viewW: CGFloat { size.width }    // 720 — 뷰포트
    var viewH: CGFloat { size.height }   // 480

    // ── 카메라 & 화면 고정 오버레이 ──
    // 좌표 규칙: 월드=씬 좌표(0…2400 × 0…900). 카메라 position은 월드 좌표.
    // hudLayer는 cam의 자식 → 그 안은 화면중심(0,0) 기준 [-360..360]×[-240..240].
    // 옛 절대 HUD 좌표 (ax,ay) → camRel = (ax-360, ay-240).
    var cam: SKCameraNode!
    var hudLayer: SKNode!

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
    var skills: [SkillSlot] = []
    var respawnQueue: [(time: CGFloat, surface: Surface)] = []
    var lastTime: TimeInterval = 0
    var keyMonitor: Any?

    // ── HUD ───────────────────────────────────────────────────
    var levelLabel: SKLabelNode!
    var killsLabel: SKLabelNode!
    var expBarFill: SKSpriteNode!
    var hpBarFill: SKSpriteNode!
    var mpBarFill: SKSpriteNode!
    var goldLabel: SKLabelNode!
    let barWidth: CGFloat = 200

    override func didMove(to view: SKView) {
        anchorPoint = .zero
        backgroundColor = SKColor(red: 0.60, green: 0.85, blue: 1.0, alpha: 1.0)

        setupCamera()                                   // 먼저 (HUD/모달이 카메라에 붙음)
        addGround()                                     // 이제 worldW 너비
        // 점프(620)로 한 칸씩 오를 수 있는 지그재그 계단 (각 단 ~90px 차이)
        addPlatform(x: 320,  y: 129, width: 180)   // 윗면 140
        addPlatform(x: 580,  y: 219, width: 150)   // 230
        addPlatform(x: 840,  y: 309, width: 160)   // 320
        addPlatform(x: 1100, y: 219, width: 200)   // 230
        addPlatform(x: 1360, y: 309, width: 150)   // 320
        addPlatform(x: 1620, y: 219, width: 180)   // 230
        addPlatform(x: 1880, y: 129, width: 160)   // 140
        addPlatform(x: 2140, y: 219, width: 200)   // 230
        addClouds()
        addPlayer()
        buildSurfaces()
        addHUD()
        addSkills()
        addMiniMap()
        setupKeyboard()

        if let s = SaveStore.load() {
            level = s.level; xp = s.xp; kills = s.kills
            // 저장된 아이템 불러오기 (카탈로그에 있는 유효한 것만)
            inventory = (s.inventory ?? []).filter { ItemCatalog.item($0) != nil }
            equipped = [:]
            for (raw, id) in (s.equipped ?? [:]) {
                if let slot = EquipSlot(rawValue: raw),
                   let item = ItemCatalog.item(id), item.slot == slot {
                    equipped[slot] = id
                }
            }
            // 능력치 분배 불러오기
            statATK = max(0, s.statATK ?? 0)
            statDEF = max(0, s.statDEF ?? 0)
            statHPpts = max(0, s.statHP ?? 0)
            unspentAP = max(0, s.unspentAP ?? 0)
            gold = max(0, s.gold ?? 0)
            reconcileAP()                 // 구버전·고레벨 세이브에 AP 소급 지급
            if hp > maxHP { hp = maxHP }
            popText("이어하기! Lv \(level)", at: player.position,
                    color: SKColor(red: 0.15, green: 0.45, blue: 0.9, alpha: 1), size: 26)
        }

        for s in surfaces { spawnMonster(on: s) }
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
    }

    func updateCamera() {
        let halfW = viewW / 2, halfH = viewH / 2
        let cx = min(max(player.position.x, halfW), worldW - halfW)
        let cy = min(max(player.position.y, halfH), worldH - halfH)
        cam.position = CGPoint(x: cx, y: cy)
    }

    // ── 월드 만들기 ───────────────────────────────────────────
    func addGround() {
        let h: CGFloat = 50
        let ground = SKSpriteNode(color: SKColor(red: 0.36, green: 0.72, blue: 0.36, alpha: 1),
                                  size: CGSize(width: worldW, height: h))
        ground.position = CGPoint(x: worldW / 2, y: h / 2)
        addChild(ground)
        solids.append(CGRect(x: 0, y: 0, width: worldW, height: h))
    }

    func addPlatform(x: CGFloat, y: CGFloat, width: CGFloat) {
        let h: CGFloat = 22
        let p = SKSpriteNode(color: SKColor(red: 0.55, green: 0.40, blue: 0.28, alpha: 1),
                             size: CGSize(width: width, height: h))
        p.position = CGPoint(x: x, y: y)
        addChild(p)
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
            addChild(c)
        }
    }

    // 사람 형태 캐릭터 (도형 조합). 중심이 position, 발끝은 local y=-22 (playerHalfH)
    func addPlayer() {
        let body = SKNode()
        body.position = CGPoint(x: 360, y: 200)
        body.zPosition = 5
        let skin  = SKColor(red: 1.0,  green: 0.85, blue: 0.7,  alpha: 1)
        let shirt = SKColor(red: 0.25, green: 0.55, blue: 0.95, alpha: 1)
        let pants = SKColor(red: 0.22, green: 0.25, blue: 0.45, alpha: 1)

        for dx in [CGFloat(-5), 5] {   // 다리 (발끝 y=-22)
            let leg = SKShapeNode(rect: CGRect(x: dx - 2.5, y: -22, width: 5, height: 12), cornerRadius: 2)
            leg.fillColor = pants; leg.strokeColor = .clear; leg.zPosition = -1
            body.addChild(leg)
        }
        let armBack = SKShapeNode(rect: CGRect(x: -12, y: -6, width: 4, height: 14), cornerRadius: 2)
        armBack.fillColor = shirt; armBack.strokeColor = .clear; armBack.zPosition = -1
        body.addChild(armBack)
        let torso = SKShapeNode(rect: CGRect(x: -8, y: -10, width: 16, height: 20), cornerRadius: 4)
        torso.fillColor = shirt; torso.strokeColor = .clear
        body.addChild(torso)
        let head = SKShapeNode(circleOfRadius: 8)
        head.fillColor = skin; head.strokeColor = .clear
        head.position = CGPoint(x: 0, y: 18); head.zPosition = 1
        body.addChild(head)
        let eye = SKShapeNode(circleOfRadius: 1.6)
        eye.fillColor = .black; eye.strokeColor = .clear
        eye.position = CGPoint(x: 4, y: 19); eye.zPosition = 2
        body.addChild(eye)
        let arm = SKShapeNode(rect: CGRect(x: 8, y: -10, width: 4, height: 14), cornerRadius: 2)
        arm.fillColor = skin; arm.strokeColor = .clear
        arm.name = "arm"; arm.zPosition = 2     // 휘두를 앞팔
        body.addChild(arm)

        player = body
        addChild(player)
    }

    var playerFacing: CGFloat { player.xScale < 0 ? -1 : 1 }

    // 플랫폼/바닥을 순찰 구역(Surface)으로 변환 (스폰·미니맵이 재사용)
    func buildSurfaces() {
        surfaces.removeAll()
        // 바닥(맨 위 y=50): 넓은 맵에 순찰 구역 분산
        for cx in stride(from: 200, through: worldW - 200, by: 380) {
            surfaces.append(Surface(cx: cx, topY: 50, span: 150))
        }
        // 플랫폼들 (solids[0]은 바닥이므로 제외)
        for r in solids.dropFirst() {
            surfaces.append(Surface(cx: r.midX, topY: r.maxY, span: max(20, r.width/2 - 18)))
        }
    }

    func spawnMonster(on s: Surface) {
        let type = MonsterCatalog.all.randomElement()!
        let node = SKLabelNode(text: type.emoji)
        node.fontSize = 36
        node.position = CGPoint(x: s.cx, y: s.topY)
        node.verticalAlignmentMode = .bottom
        addChild(node)
        let mon = Monster(node: node, type: type, dir: Bool.random() ? 1 : -1,
                          minX: s.cx - s.span, maxX: s.cx + s.span, baseY: s.topY)
        monsters.append(mon)
    }

    // ── HUD ───────────────────────────────────────────────────
    // HUD는 hudLayer(카메라 자식)에 붙어 화면에 고정. 좌표는 화면중심(0,0) 기준.
    func addHUD() {
        let hint = SKLabelNode(text: "←→ 이동 · Space · A 공격 · S/D 스킬 · I 장비 · C 능력치 · B 상점")
        hint.fontSize = 13
        hint.fontColor = SKColor(white: 0.15, alpha: 0.9)
        hint.position = CGPoint(x: 0, y: viewH/2 - 22)
        hudLayer.addChild(hint)

        levelLabel = SKLabelNode(text: "Lv 1")
        levelLabel.fontSize = 18
        levelLabel.fontColor = SKColor(white: 0.1, alpha: 1)
        levelLabel.horizontalAlignmentMode = .left
        levelLabel.position = CGPoint(x: -viewW/2 + 14, y: viewH/2 - 30)
        hudLayer.addChild(levelLabel)

        killsLabel = SKLabelNode(text: "처치 0")
        killsLabel.fontSize = 16
        killsLabel.fontColor = SKColor(white: 0.1, alpha: 1)
        killsLabel.horizontalAlignmentMode = .right
        killsLabel.position = CGPoint(x: viewW/2 - 14, y: viewH/2 - 30)
        hudLayer.addChild(killsLabel)

        goldLabel = SKLabelNode(text: "💰 0")
        goldLabel.fontSize = 16
        goldLabel.fontColor = SKColor(red: 0.85, green: 0.6, blue: 0.05, alpha: 1)
        goldLabel.horizontalAlignmentMode = .right
        goldLabel.position = CGPoint(x: viewW/2 - 14, y: viewH/2 - 50)
        hudLayer.addChild(goldLabel)

        expBarFill = addBar(icon: "⭐️", y: viewH/2 - 54, color: SKColor(red: 1.0, green: 0.82, blue: 0.2, alpha: 1))
        hpBarFill  = addBar(icon: "❤️", y: viewH/2 - 74, color: SKColor(red: 0.95, green: 0.30, blue: 0.30, alpha: 1))
        mpBarFill  = addBar(icon: "💧", y: viewH/2 - 94, color: SKColor(red: 0.25, green: 0.55, blue: 1.0, alpha: 1))
    }

    func addBar(icon: String, y: CGFloat, color: SKColor) -> SKSpriteNode {
        let label = SKLabelNode(text: icon)
        label.fontSize = 16
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: -viewW/2 + 20, y: y)
        hudLayer.addChild(label)

        let bg = SKSpriteNode(color: SKColor(white: 0.3, alpha: 0.35), size: CGSize(width: barWidth, height: 12))
        bg.anchorPoint = CGPoint(x: 0, y: 0.5)
        bg.position = CGPoint(x: -viewW/2 + 38, y: y)
        hudLayer.addChild(bg)

        let fill = SKSpriteNode(color: color, size: CGSize(width: barWidth, height: 12))
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.position = bg.position
        fill.zPosition = 1
        hudLayer.addChild(fill)
        return fill
    }

    // 스킬 슬롯들을 만들어 화면 하단에 배치
    func addSkills() {
        var x: CGFloat = -viewW/2 + 40    // 화면 좌하단부터
        for type in SkillCatalog.all {
            guard let code = keyCode(forLetter: type.key) else { continue }
            let slot = SkillSlot(type: type, keyCode: code)

            let bg = SKSpriteNode(color: SKColor(white: 0.1, alpha: 0.35), size: CGSize(width: 52, height: 52))
            bg.position = CGPoint(x: x, y: -viewH/2 + 44)
            hudLayer.addChild(bg)

            let icon = SKLabelNode(text: type.emoji)
            icon.fontSize = 28
            icon.verticalAlignmentMode = .center
            icon.position = CGPoint(x: x, y: -viewH/2 + 46)
            hudLayer.addChild(icon)

            let keyLabel = SKLabelNode(text: type.key)
            keyLabel.fontSize = 11
            keyLabel.fontColor = .white
            keyLabel.position = CGPoint(x: x + 17, y: -viewH/2 + 24)
            hudLayer.addChild(keyLabel)

            let cd = SKLabelNode(text: "")
            cd.fontSize = 22
            cd.fontColor = .white
            cd.verticalAlignmentMode = .center
            cd.position = CGPoint(x: x, y: -viewH/2 + 46)
            cd.zPosition = 2
            cd.isHidden = true
            hudLayer.addChild(cd)

            slot.icon = icon
            slot.cdLabel = cd
            skills.append(slot)
            x += 64
        }
    }

    // ── 미니맵 (hudLayer 자식, 우상단) ─────────────────────────
    func addMiniMap() {
        miniMap = SKNode()
        miniMap.zPosition = 60
        miniMap.position = CGPoint(x: viewW/2 - miniW - 12, y: -viewH/2 + 12)   // 우하단 (HUD 라벨과 안 겹침)
        hudLayer.addChild(miniMap)

        let bg = SKShapeNode(rect: CGRect(x: 0, y: 0, width: miniW, height: miniH), cornerRadius: 4)
        bg.fillColor = SKColor(white: 0.05, alpha: 0.55)
        bg.strokeColor = SKColor(white: 1, alpha: 0.35)
        bg.zPosition = -1
        miniMap.addChild(bg)

        for r in solids {   // 정적 지형 윤곽
            let pr = SKShapeNode(rect: CGRect(x: r.minX*miniScale, y: r.minY*miniScale,
                                              width: r.width*miniScale, height: max(2, r.height*miniScale)))
            pr.fillColor = SKColor(red: 0.55, green: 0.40, blue: 0.28, alpha: 0.9)
            pr.strokeColor = .clear
            miniMap.addChild(pr)
        }

        miniPlayerDot = SKShapeNode(circleOfRadius: 3)
        miniPlayerDot.fillColor = SKColor(red: 0.2, green: 0.6, blue: 1, alpha: 1)
        miniPlayerDot.strokeColor = .white
        miniPlayerDot.zPosition = 2
        miniMap.addChild(miniPlayerDot)
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
        killsLabel.text = "처치 \(kills)"
        goldLabel.text = "💰 \(gold)"
        expBarFill.size = CGSize(width: barWidth * clamp01(CGFloat(xp) / CGFloat(xpToNext)), height: 12)
        hpBarFill.size  = CGSize(width: barWidth * clamp01(CGFloat(hp) / CGFloat(maxHP)), height: 12)
        mpBarFill.size  = CGSize(width: barWidth * clamp01(mp / maxMP), height: 12)
    }

    func clamp01(_ v: CGFloat) -> CGFloat { max(0, min(1, v)) }

    // 알파벳 키 → macOS 키코드
    func keyCode(forLetter s: String) -> UInt16? {
        let map: [String: UInt16] = ["A":0,"S":1,"D":2,"F":3,"H":4,"G":5,"Z":6,"X":7,
                                     "C":8,"V":9,"B":11,"Q":12,"W":13,"E":14,"R":15]
        return map[s.uppercased()]
    }

    // ── 매 프레임 ─────────────────────────────────────────────
    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 1.0/60.0 : min(CGFloat(currentTime - lastTime), 1.0/30.0)
        lastTime = currentTime

        // 플레이어 이동/중력 (창 열려있으면 멈춤 = 모달)
        if !anyModalOpen {
            // 좌우 이동
            let dir: CGFloat = (rightPressed ? 1 : 0) - (leftPressed ? 1 : 0)
            var newX = player.position.x + dir * moveSpeed * dt
            newX = min(max(newX, 20), worldW - 20)
            if dir < 0 { player.xScale = -1 } else if dir > 0 { player.xScale = 1 }

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
        }

        // 몬스터 순찰
        for mon in monsters {
            var x = mon.node.position.x + mon.dir * mon.type.speed * dt
            if x <= mon.minX { x = mon.minX; mon.dir = 1 }
            else if x >= mon.maxX { x = mon.maxX; mon.dir = -1 }
            mon.bobPhase += dt * 4
            let bob = CGFloat(sin(Double(mon.bobPhase))) * 4
            mon.node.position = CGPoint(x: x, y: mon.baseY + bob)
            mon.node.xScale = mon.dir < 0 ? -1 : 1
        }

        // 타이머들
        if attackCooldown > 0 { attackCooldown -= dt }
        if invuln > 0 { invuln -= dt }

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

        // 몬스터 충돌 피해 (창 열려있으면 잠시 무피해)
        if invuln <= 0 && !anyModalOpen {
            for mon in monsters where abs(mon.node.position.x - player.position.x) < 32
                                   && abs(mon.node.position.y - player.position.y) < 34 {
                takeDamage(mon.type.touchDamage); break
            }
        }

        // 몬스터 재등장
        if !respawnQueue.isEmpty {
            for i in respawnQueue.indices { respawnQueue[i].time -= dt }
            for r in respawnQueue where r.time <= 0 { spawnMonster(on: r.surface) }
            respawnQueue.removeAll { $0.time <= 0 }
        }

        updateCamera()
        updateMiniMap()
    }

    // ── 플레이어 행동 ─────────────────────────────────────────
    func jump() {
        guard onGround else { return }
        velocityY = jumpSpeed
        onGround = false
    }

    // 앞팔만 휘둘러요 (몸 컨테이너의 xScale=±1이 방향을 알아서 반전)
    func swingPlayer(_ facing: CGFloat, strong: Bool = false) {
        guard let arm = player.childNode(withName: "arm") else { return }
        let angle: CGFloat = strong ? 1.4 : 1.0
        arm.run(.sequence([
            .rotate(toAngle: -angle, duration: 0.07),
            .rotate(toAngle: 0, duration: 0.15)
        ]), withKey: "swing")
    }

    // ── MapleStory식 데미지 ───────────────────────────────────
    // 공격력 = 기본 + 레벨*2 + 분배공격 + 장비공격 (메이플의 주스탯·무기공격 항을 압축)
    var attackPower: Int {
        let p = BASE_ATTACK + Double(level)*LEVEL_FACTOR + Double(statATK) + Double(equipATK)
        return Int(p.rounded())
    }
    // 한 방 데미지 = [max*MASTERY, max] 사이 랜덤. skillPercent=1.0이 기본공격.
    func rollDamage(skillPercent: Double = 1.0) -> Int {
        let maxD = Double(attackPower) * skillPercent
        let minD = maxD * MASTERY
        return max(1, Int(Double.random(in: minD...maxD).rounded()))
    }

    func attack() {
        guard attackCooldown <= 0 else { return }
        attackCooldown = 0.35
        let facing: CGFloat = playerFacing
        swingPlayer(facing)

        let sword = SKLabelNode(text: "🗡️")
        sword.fontSize = 34
        sword.position = CGPoint(x: player.position.x + facing * 30, y: player.position.y + 8)
        sword.xScale = facing
        sword.zRotation = facing > 0 ? 0.9 : -0.9
        sword.zPosition = 8
        addChild(sword)
        sword.run(.sequence([
            .group([.rotate(byAngle: facing > 0 ? -1.6 : 1.6, duration: 0.18),
                    .moveBy(x: facing * 16, y: -8, duration: 0.18),
                    .fadeOut(withDuration: 0.2)]),
            .removeFromParent()
        ]))

        let hit = monsters.filter { mon in
            let ahead = facing * (mon.node.position.x - player.position.x)
            return ahead > -20 && ahead < attackRange && abs(mon.node.position.y - player.position.y) < 70
        }
        for mon in hit { damageMonster(mon, amount: rollDamage(skillPercent: 1.0)) }
    }

    // 스킬 사용
    func useSkill(_ slot: SkillSlot) {
        guard slot.cooldownLeft <= 0 else { return }
        if mp < CGFloat(slot.type.mpCost) {
            popText("MP 부족!", at: CGPoint(x: player.position.x, y: player.position.y + 40),
                    color: SKColor(red: 0.3, green: 0.5, blue: 1, alpha: 1))
            return
        }
        mp -= CGFloat(slot.type.mpCost)
        slot.cooldownLeft = slot.type.cooldown
        let facing = playerFacing
        swingPlayer(facing, strong: true)

        let px = player.position.x, py = player.position.y
        let footY = py - playerHalfH    // 발끝 기준 (몬스터 y도 바닥 기준 → 수직 정렬)
        let st = slot.type
        func inFront(_ mon: Monster) -> Bool {
            let ahead = facing * (mon.node.position.x - px)
            return ahead > -10 && ahead < st.range && abs(mon.node.position.y - footY) < st.hitHalfHeight
        }

        let targets: [Monster]
        switch st.shape {
        case .beam, .area:
            targets = monsters.filter(inFront)                    // 일직선/범위의 모든 적
        case .strike:
            targets = monsters.filter(inFront)
                .min(by: { abs($0.node.position.x - px) < abs($1.node.position.x - px) })
                .map { [$0] } ?? []                               // 가장 가까운 1마리만
        }

        spawnSkillFX(shape: st.shape, emoji: st.emoji, range: st.range, height: st.hitHalfHeight, facing: facing)
        popText(st.name, at: CGPoint(x: px, y: py + 62),
                color: SKColor(red: 1, green: 0.9, blue: 0.3, alpha: 1), size: 20)
        for mon in targets { damageMonster(mon, amount: rollDamage(skillPercent: st.skillPercent)) }
        updateHUD()
    }

    // 모양별 스킬 이펙트 (월드 좌표 → 월드와 함께 스크롤)
    func spawnSkillFX(shape: SkillShape, emoji: String, range: CGFloat, height: CGFloat, facing: CGFloat) {
        switch shape {
        case .beam:
            let beam = SKSpriteNode(color: SKColor(red: 1, green: 0.95, blue: 0.4, alpha: 0.85),
                                    size: CGSize(width: range, height: max(8, height*1.4)))
            beam.anchorPoint = CGPoint(x: facing > 0 ? 0 : 1, y: 0.5)   // 앞쪽으로 뻗음
            beam.position = CGPoint(x: player.position.x + facing*16, y: player.position.y + 6)
            beam.zPosition = 9
            addChild(beam)
            beam.run(.sequence([.group([.scaleY(to: 2.0, duration: 0.18), .fadeOut(withDuration: 0.25)]),
                                .removeFromParent()]))
        case .strike:
            let fx = SKLabelNode(text: emoji); fx.fontSize = 30
            fx.position = CGPoint(x: player.position.x + facing*range*0.7, y: player.position.y + 4)
            fx.zPosition = 9; addChild(fx)
            fx.run(.sequence([.group([.scale(to: 2.4, duration: 0.16), .fadeOut(withDuration: 0.22)]),
                              .removeFromParent()]))
        case .area:
            let fx = SKLabelNode(text: emoji); fx.fontSize = 32
            fx.position = CGPoint(x: player.position.x + facing*range*0.45, y: player.position.y + 6)
            fx.zPosition = 9; addChild(fx)
            fx.run(.sequence([.group([.scale(to: 3.0, duration: 0.25), .fadeOut(withDuration: 0.32)]),
                              .removeFromParent()]))
        }
    }

    func damageMonster(_ mon: Monster, amount: Int = 1) {
        mon.hp -= amount
        popText("\(amount)",
                at: CGPoint(x: mon.node.position.x + CGFloat.random(in: -8...8), y: mon.node.position.y + 36),
                color: SKColor(red: 1, green: 0.95, blue: 0.45, alpha: 1), size: 18)   // 부유 데미지 숫자
        if mon.hp <= 0 {
            defeat(mon)
        } else {
            mon.node.run(.sequence([.fadeAlpha(to: 0.4, duration: 0.06), .fadeAlpha(to: 1, duration: 0.06)]))
        }
    }

    func defeat(_ mon: Monster) {
        guard let idx = monsters.firstIndex(where: { $0 === mon }) else { return }
        monsters.remove(at: idx)
        let node = mon.node
        node.removeAllActions()
        node.run(.sequence([
            .group([.scale(to: 1.8, duration: 0.15), .fadeOut(withDuration: 0.2)]),
            .removeFromParent()
        ]))
        popText("+\(mon.type.xpReward)", at: CGPoint(x: node.position.x, y: node.position.y + 30),
                color: SKColor(red: 1.0, green: 0.82, blue: 0.2, alpha: 1))
        kills += 1
        gold += mon.type.gold
        popText("💰+\(mon.type.gold)", at: CGPoint(x: node.position.x + 24, y: node.position.y + 30),
                color: SKColor(red: 1.0, green: 0.84, blue: 0.2, alpha: 1))
        gainXP(mon.type.xpReward)
        maybeDrop(from: mon, at: node.position)   // 아이템 드롭 시도
        respawnQueue.append((3.0, surfaces.randomElement()!))
        saveProgress()
    }

    func saveProgress() {
        let eq = Dictionary(uniqueKeysWithValues: equipped.map { ($0.key.rawValue, $0.value) })
        SaveStore.save(SaveData(level: level, xp: xp, kills: kills, inventory: inventory, equipped: eq,
                                statATK: statATK, statDEF: statDEF, statHP: statHPpts, unspentAP: unspentAP,
                                gold: gold))
    }

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
        case "atk": statATK += 1
        case "def": statDEF += 1
        case "hp":  statHPpts += 1; hp += hpPerPoint   // 분배 즉시 현재 HP도 회복
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
        let w: CGFloat = 360, h: CGFloat = 340
        let cx: CGFloat = 0, cy: CGFloat = 0   // hudLayer 기준 화면 중심
        let rowW = w - 30

        let bg = SKSpriteNode(color: SKColor(white: 0.08, alpha: 0.93), size: CGSize(width: w, height: h))
        bg.position = CGPoint(x: cx, y: cy); bg.name = "statsBG"
        bg.zPosition = -1
        panel.addChild(bg)

        let title = SKLabelNode(text: "능력치"); title.fontSize = 18; title.fontColor = .white
        title.position = CGPoint(x: cx, y: cy + h/2 - 26); panel.addChild(title)

        let close = SKLabelNode(text: "✕"); close.name = "stats_close"
        close.fontSize = 20; close.fontColor = .white
        close.position = CGPoint(x: cx + w/2 - 22, y: cy + h/2 - 28); panel.addChild(close)

        var sy = cy + h/2 - 60
        for line in ["Lv \(level)        처치 \(kills)",
                     "EXP \(xp) / \(xpToNext)",
                     "HP \(hp) / \(maxHP)        MP \(Int(mp)) / \(Int(maxMP))"] {
            addRow(to: panel, text: line, color: .white, name: nil, cx: cx, y: sy, width: rowW)
            sy -= 26
        }

        addRow(to: panel, text: "남은 AP: \(unspentAP)",
               color: SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 1),
               name: nil, cx: cx, y: sy, width: rowW)
        sy -= 32

        statRow(panel, label: "⚔️ 공격",   key: "atk", total: 1 + bonusATK,
                detail: "분배 +\(statATK)  장비 +\(equipATK)", cx: cx, y: &sy, rowW: rowW)
        statRow(panel, label: "🛡️ 방어",   key: "def", total: bonusDEF,
                detail: "분배 +\(statDEF)  장비 +\(equipDEF)", cx: cx, y: &sy, rowW: rowW)
        statRow(panel, label: "❤️ 최대HP", key: "hp",  total: maxHP,
                detail: "기본 \(baseMaxHP)  분배 +\(statHPpts * hpPerPoint)  장비 +\(equipHP)", cx: cx, y: &sy, rowW: rowW)

        let hint = SKLabelNode(text: "[ + ] 눌러 분배 · C 닫기")
        hint.fontSize = 11; hint.fontColor = SKColor(white: 0.8, alpha: 1)
        hint.position = CGPoint(x: cx, y: cy - h/2 + 12); panel.addChild(hint)

        hudLayer.addChild(panel); statsPanel = panel
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

    func buildShopPanel() {
        let panel = SKNode(); panel.zPosition = 100; panel.name = "shopPanel"
        let w: CGFloat = 420, h: CGFloat = 380
        let cx: CGFloat = 0, cy: CGFloat = 0   // hudLayer 기준 화면 중심
        let rowW = w - 30

        let bg = SKSpriteNode(color: SKColor(white: 0.08, alpha: 0.93), size: CGSize(width: w, height: h))
        bg.position = CGPoint(x: cx, y: cy); bg.name = "shopBG"
        bg.zPosition = -1
        panel.addChild(bg)

        let title = SKLabelNode(text: "상점  💰 \(gold)"); title.fontSize = 18; title.fontColor = .white
        title.position = CGPoint(x: cx, y: cy + h/2 - 26); panel.addChild(title)

        let close = SKLabelNode(text: "✕"); close.name = "shop_close"
        close.fontSize = 20; close.fontColor = .white
        close.position = CGPoint(x: cx + w/2 - 22, y: cy + h/2 - 28); panel.addChild(close)

        var sy = cy + h/2 - 60

        // — 구매 — (전체 아이템, 싼 순)
        let buyTitle = SKLabelNode(text: "— 구매 —"); buyTitle.fontSize = 12
        buyTitle.fontColor = SKColor(white: 0.7, alpha: 1)
        buyTitle.position = CGPoint(x: cx, y: sy); panel.addChild(buyTitle); sy -= 22

        for item in ItemCatalog.all.sorted(by: { $0.price < $1.price }) {
            let afford = gold >= item.price
            let text = "\(item.emoji) \(item.name)  ⚔️\(item.attack) 🛡️\(item.defense) ❤️\(item.hpBonus)   💰\(item.price)"
            addRow(to: panel, text: text,
                   color: afford ? rarityColor(item.rarity) : SKColor(white: 0.45, alpha: 1),
                   name: afford ? "buy:\(item.id)" : nil,   // 못 사면 클릭 불가
                   cx: cx, y: sy, width: rowW)
            sy -= 24
            if sy < cy - h/2 + 70 { break }
        }

        // — 판매 — (가방 = 장착 안 한 보유분)
        sy -= 8
        let sellTitle = SKLabelNode(text: "— 판매 (\(Int(sellFraction*100))% 환급) —")
        sellTitle.fontSize = 12; sellTitle.fontColor = SKColor(white: 0.7, alpha: 1)
        sellTitle.position = CGPoint(x: cx, y: sy); panel.addChild(sellTitle); sy -= 22

        let counts = unequippedInventory().reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        if counts.isEmpty {
            let empty = SKLabelNode(text: "(팔 물건이 없어요)")
            empty.fontSize = 12; empty.fontColor = .gray
            empty.position = CGPoint(x: cx, y: sy); panel.addChild(empty)
        }
        for (id, n) in counts.sorted(by: { $0.key < $1.key }) {
            guard let item = ItemCatalog.item(id) else { continue }
            let text = "\(item.emoji) \(item.name)" + (n > 1 ? " ×\(n)" : "") + "   판매 💰\(sellPrice(item))"
            addRow(to: panel, text: text, color: rarityColor(item.rarity),
                   name: "sell:\(id)", cx: cx, y: sy, width: rowW)
            sy -= 24
            if sy < cy - h/2 + 30 { break }
        }

        let hint = SKLabelNode(text: "윗줄=구매 · 아랫줄=판매 · B 닫기")
        hint.fontSize = 11; hint.fontColor = SKColor(white: 0.8, alpha: 1)
        hint.position = CGPoint(x: cx, y: cy - h/2 + 12); panel.addChild(hint)

        hudLayer.addChild(panel); shopPanel = panel
    }

    // ── 인벤토리 / 장비 시스템 ────────────────────────────────
    func maybeDrop(from mon: Monster, at pos: CGPoint) {
        guard let id = mon.type.dropID,
              let item = ItemCatalog.item(id),
              CGFloat.random(in: 0...1) < mon.type.dropProbability else { return }
        inventory.append(id)
        spawnDropFX(item, at: pos)
        popText("\(item.emoji) \(item.name) 획득!", at: CGPoint(x: pos.x, y: pos.y + 52),
                color: rarityColor(item.rarity), size: 16)
        if inventoryOpen { refreshInventoryPanel() }
    }

    func spawnDropFX(_ item: ItemType, at pos: CGPoint) {
        let l = SKLabelNode(text: item.emoji)
        l.fontSize = 26; l.position = pos; l.zPosition = 9
        addChild(l)
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
        guard let item = ItemCatalog.item(itemID), inventory.contains(itemID) else { return }
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

    func toggleInventory() {
        if statsOpen { toggleStats() }   // 상호 배타: 다른 창 닫기
        if shopOpen { toggleShop() }
        inventoryOpen.toggle()
        if inventoryOpen {
            leftPressed = false; rightPressed = false   // 모달 열면 이동 멈춤
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

    func buildInventoryPanel() {
        let panel = SKNode(); panel.zPosition = 100; panel.name = "inventoryPanel"
        let w: CGFloat = 380, h: CGFloat = 320
        let cx: CGFloat = 0, cy: CGFloat = 0   // hudLayer 기준 화면 중심
        let rowW = w - 30

        let bg = SKSpriteNode(color: SKColor(white: 0.08, alpha: 0.93), size: CGSize(width: w, height: h))
        bg.position = CGPoint(x: cx, y: cy); bg.name = "invBG"
        bg.zPosition = -1            // 항상 패널 내용물 뒤에 (그리기 순서에 의존 안 함)
        panel.addChild(bg)

        let title = SKLabelNode(text: "장비 · 가방"); title.fontSize = 18; title.fontColor = .white
        title.position = CGPoint(x: cx, y: cy + h/2 - 26); panel.addChild(title)

        let close = SKLabelNode(text: "✕"); close.name = "inv_close"
        close.fontSize = 20; close.fontColor = .white
        close.position = CGPoint(x: cx + w/2 - 22, y: cy + h/2 - 28); panel.addChild(close)

        var sy = cy + h/2 - 62
        for slot in EquipSlot.allCases {
            let item = equipped[slot].flatMap { ItemCatalog.item($0) }
            let text = "[\(slot.label)] " + (item.map { "\($0.emoji) \($0.name)" } ?? "(빈 칸)")
            addRow(to: panel, text: text,
                   color: item == nil ? .gray : .yellow,
                   name: item == nil ? nil : "unequip:\(slot.rawValue)",
                   cx: cx, y: sy, width: rowW)
            sy -= 26
        }

        let stats = SKLabelNode(text: "⚔️+\(bonusATK)    🛡️+\(bonusDEF)    ❤️+\(bonusHP)")
        stats.fontSize = 14; stats.fontColor = .white
        stats.position = CGPoint(x: cx, y: sy - 2); panel.addChild(stats); sy -= 30

        let bagTitle = SKLabelNode(text: "— 가방 —"); bagTitle.fontSize = 12
        bagTitle.fontColor = SKColor(white: 0.7, alpha: 1)
        bagTitle.position = CGPoint(x: cx, y: sy); panel.addChild(bagTitle); sy -= 22

        let counts = unequippedInventory().reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        if counts.isEmpty {
            let empty = SKLabelNode(text: "(비어 있음 — 몬스터를 잡아 아이템을 모으세요)")
            empty.fontSize = 12; empty.fontColor = .gray
            empty.position = CGPoint(x: cx, y: sy); panel.addChild(empty)
        }
        for (id, n) in counts.sorted(by: { $0.key < $1.key }) {
            guard let item = ItemCatalog.item(id) else { continue }
            let text = "\(item.emoji) \(item.name)" + (n > 1 ? " ×\(n)" : "")
            addRow(to: panel, text: text, color: rarityColor(item.rarity),
                   name: "equip:\(id)", cx: cx, y: sy, width: rowW)
            sy -= 24
            if sy < cy - h/2 + 30 { break }   // 넘침 방지
        }

        let hint = SKLabelNode(text: "가방=장착 · 장착품=해제 · I 닫기")
        hint.fontSize = 11; hint.fontColor = SKColor(white: 0.8, alpha: 1)
        hint.position = CGPoint(x: cx, y: cy - h/2 + 12); panel.addChild(hint)

        hudLayer.addChild(panel); inventoryPanel = panel
    }

    // 마우스 클릭 (인벤토리 열렸을 때만 처리)
    override func mouseDown(with event: NSEvent) {
        guard anyModalOpen else { return }
        let p = event.location(in: self)
        // 클릭 지점 노드 중 '행동 가능한' 이름을 찾아 처리 (그리기 순서에 의존 안 함).
        for n in nodes(at: p) {
            guard let name = n.name else { continue }
            // 장비창
            if name == "inv_close" { toggleInventory(); return }
            if name.hasPrefix("equip:")   { equip(String(name.dropFirst(6)));  return }
            if name.hasPrefix("unequip:") {
                if let slot = EquipSlot(rawValue: String(name.dropFirst(8))) { unequip(slot) }
                return
            }
            // 능력치창
            if name == "stats_close" { toggleStats(); return }
            if name.hasPrefix("alloc:") { allocate(String(name.dropFirst(6))); return }
            // 상점창
            if name == "shop_close" { toggleShop(); return }
            if name.hasPrefix("buy:")  { buy(String(name.dropFirst(4)));  return }
            if name.hasPrefix("sell:") { sell(String(name.dropFirst(5))); return }
        }
    }

    func takeDamage(_ amount: Int) {
        let reduced = max(1, amount - bonusDEF)   // 장비 방어력 반영 (최소 1)
        hp -= reduced
        invuln = 1.0
        popText("-\(reduced)", at: CGPoint(x: player.position.x, y: player.position.y + 36),
                color: SKColor(red: 0.95, green: 0.3, blue: 0.3, alpha: 1))
        player.run(.sequence([
            .fadeAlpha(to: 0.3, duration: 0.08), .fadeAlpha(to: 1, duration: 0.08),
            .fadeAlpha(to: 0.3, duration: 0.08), .fadeAlpha(to: 1, duration: 0.08)
        ]))
        if hp <= 0 { die() }
        updateHUD()
    }

    func die() {
        popText("기절! 💫", at: CGPoint(x: player.position.x, y: player.position.y + 56),
                color: SKColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1), size: 26)
        hp = maxHP
        mp = maxMP
        player.position = CGPoint(x: 360, y: 200)
        velocityY = 0
        invuln = 1.5
    }

    func gainXP(_ n: Int) {
        xp += n
        while xp >= xpToNext {
            xp -= xpToNext
            level += 1
            unspentAP += apPerLevel       // 레벨업 시 능력치 포인트 지급
            popText("LEVEL UP! ⭐️ (+\(apPerLevel) AP)", at: CGPoint(x: player.position.x, y: player.position.y + 50),
                    color: SKColor(red: 1.0, green: 0.6, blue: 0.1, alpha: 1), size: 24)
        }
        updateHUD()
    }

    func popText(_ text: String, at pos: CGPoint, color: SKColor, size fontSize: CGFloat = 20) {
        let l = SKLabelNode(text: text)
        l.fontSize = fontSize
        l.fontColor = color
        l.position = pos
        l.zPosition = 10
        addChild(l)
        l.run(.sequence([
            .group([.moveBy(x: 0, y: 40, duration: 0.6), .fadeOut(withDuration: 0.6)]),
            .removeFromParent()
        ]))
    }

    // ── 키보드 입력 ───────────────────────────────────────────
    func setupKeyboard() {
        var keySet: Set<UInt16> = [123, 124, 49, 126, 0, 34, 8, 11]  // ← → Space ↑ A I C B
        for s in skills { keySet.insert(s.keyCode) }         // 스킬 키들도 가로채기
        let ourKeys = keySet                                 // 클로저엔 불변 복사본을 캡처

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            let keyCode = event.keyCode
            let isDown = event.type == .keyDown
            let isRepeat = event.isARepeat
            guard ourKeys.contains(keyCode) else { return event }
            MainActor.assumeIsolated {
                guard let self else { return }
                if isDown {
                    if self.statsOpen {
                        // 능력치창: C(닫기)만
                        if keyCode == 8, !isRepeat { self.toggleStats() }
                    } else if self.inventoryOpen {
                        // 장비창: I(닫기)만
                        if keyCode == 34, !isRepeat { self.toggleInventory() }
                    } else if self.shopOpen {
                        // 상점창: B(닫기)만
                        if keyCode == 11, !isRepeat { self.toggleShop() }
                    } else {
                        switch keyCode {
                        case 123:     self.leftPressed = true
                        case 124:     self.rightPressed = true
                        case 49, 126: if !isRepeat { self.jump() }
                        case 0:       if !isRepeat { self.attack() }
                        case 34:      if !isRepeat { self.toggleInventory() }   // I = 장비창
                        case 8:       if !isRepeat { self.toggleStats() }       // C = 능력치창
                        case 11:      if !isRepeat { self.toggleShop() }        // B = 상점
                        default:
                            if !isRepeat, let slot = self.skills.first(where: { $0.keyCode == keyCode }) {
                                self.useSkill(slot)
                            }
                        }
                    }
                } else {
                    switch keyCode {
                    case 123: self.leftPressed = false
                    case 124: self.rightPressed = false
                    default: break
                    }
                }
            }
            return nil
        }
    }
}
