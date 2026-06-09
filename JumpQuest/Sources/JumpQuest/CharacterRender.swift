import Foundation
import AppKit
import SpriteKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// 게임 내에서 장비를 바꾸면 maplestory.io 캐릭터 렌더 API로 조합을 받아와
// (build_char 파이프라인을 Swift로 포팅) 무게중심 정렬 → 캐릭터를 라이브 교체.
// 조합별로 Application Support에 캐싱 → 두 번째부터는 네트워크 없이 즉시.

struct EquipPiece: Sendable, Equatable {
    let id: Int
    var region = "GMS"
    var version = "217"
}

enum CharSlot: String, CaseIterable, Sendable {
    case hat, hair, face, cape, overall, weapon, shoes, gloves
    var label: String {
        switch self {
        case .hat: return "모자"; case .hair: return "머리"; case .face: return "얼굴"
        case .cape: return "망토"; case .overall: return "옷"; case .weapon: return "무기"
        case .shoes: return "신발"; case .gloves: return "장갑"
        }
    }
}

// 액션 매핑: 게임 애니키 ← maple stance, 프레임수(바디 스킨 2000 기준 고정)
struct CharAction: Sendable { let anim: String; let stance: String; let count: Int }

// 정렬 결과(메인 외부로 넘길 땐 Data만 — Sendable)
struct ComboResult: Sendable {
    let framesPNG: [String: [Data]]    // anim → [PNG data]
    let feetFrac: CGFloat
    let bodyCenterFrac: CGFloat
}

// 백그라운드에서 PNG를 SKTexture로 디코드해 메인에 넘기기 위한 래퍼.
// SKTexture는 Sendable이 아니라 @unchecked — 생성은 백그라운드 안전, 메인은 할당만(디코드 히치 제거).
struct DecodedCombo: @unchecked Sendable {
    let anims: [String: [SKTexture]]   // anim → [텍스처]
    let feet: CGFloat
    let center: CGFloat
}

final class CharacterRenderer: @unchecked Sendable {
    static let shared = CharacterRenderer()

    // 고정 베이스: 몸통(2000)·머리(12000). 얼굴은 슬롯(swappable)으로 분리됨.
    let base: [EquipPiece] = [EquipPiece(id: 2000), EquipPiece(id: 12000)]

    // 슬롯별 후보 카탈로그 (드랍/장착 가능 maple 아이템)
    let catalog: [CharSlot: [Int]] = [
        .hat:     [1001011, 1002357, 1002140, 1004073, 1003797],
        .hair:    [30030, 30000, 30020, 34870, 30150, 30406],
        .face:    [20003, 20000, 21002, 20015, 20100],
        .cape:    [1102000, 1102041, 1102085, 1102013, 1102222],
        .overall: [1052434, 1050018, 1051031, 1053000],
        .weapon:  [1402061, 1302000, 1302005, 1312004, 1322000, 1302063, 1432014, 1442139,
                   1302007, 1432000, 1402000, 1412000, 1312005, 1302020, 1432005, 1442005, 1312020, 1402005],   // 검·도끼·둔기 + 창·폴암(stand2). 뒤 10종=상점 판매
        .shoes:   [1072018, 1072064, 1070006, 1072246, 1070003],   // 신발(maplestory.io)
        .gloves:  [1082002, 1082149, 1080000, 1082145, 1082515],   // 장갑(maplestory.io)
    ]

    // 아이템 이름 (툴팁/표시용)
    static let itemNames: [Int: String] = [
        1001011:"딸기 모자",1002357:"자쿰 헬름",1002140:"위젯 무적 모자",1004073:"말띠 모자",1003797:"로얄 워리어 헬름",
        30030:"쉐이브드",30000:"토벤 헤어",30020:"블랙 레벨",34870:"블랙 웨이브",30150:"드레드락",30406:"퍼플 트라이벌",
        20003:"드라마틱 페이스",20000:"모티베이티드",21002:"인텔리전트",20015:"라이온의 눈",20100:"디파이언트",
        1102000:"그린 모험가 망토",1102041:"핑크 모험가 망토",1102085:"옐로우 가이아 망토",1102013:"화이트 저스티스 망토",1102222:"세라핌 망토",
        1052434:"핑크빈 슈트",1050018:"블루 사우나 로브",1051031:"화이트 칼라프",1053000:"소 코스튬",
        1402061:"클레이모어",1302000:"검",1302005:"사브르",1312004:"손도끼",1322000:"메이스",1302063:"화염 카타나",1432014:"장창",1442139:"드레고닉 모글레이",
        1302007:"롱 소드",1432000:"스피어",1402000:"투핸드 소드",1412000:"투핸드 액스",1312005:"소방 도끼",1302020:"메이플 소드",1432005:"제코",1442005:"나인 드래곤",1312020:"미카엘",1402005:"버서커",
        1072018:"블루 스니커즈",1072064:"레드 스니커즈",1070006:"로얄 코스튬 슈즈",1072246:"핑크 스니커즈",1070003:"죽음의 검은 신발",
        1082002:"작업 장갑",1082149:"브라운 작업 장갑",1080000:"화이트 닌자 장갑",1082145:"옐로우 작업 장갑",1082515:"요정 작업 장갑",
    ]
    func slotOf(_ id: Int) -> CharSlot? { catalog.first(where: { $0.value.contains(id) })?.key }
    static func name(_ id: Int) -> String { itemNames[id] ?? "아이템 \(id)" }

    // 현재 선택 (a.json 기본값: 딸기+드라마틱얼굴+핑크빈+클레이모어, 머리·망토 없음)
    var selection: [CharSlot: Int] = [.hat: 1001011, .face: 20003, .overall: 1052434, .weapon: 1402061, .shoes: 1072018, .gloves: 1082002]
    // 캐시(치장) 외형 오버레이 — 외형만 덮어씀(능력치·레벨은 selection 그대로). 비면 실제 장비 외형.
    var cashSelection: [CharSlot: Int] = [:]
    var displaySelection: [CharSlot: Int] { var d = selection; for (k, v) in cashSelection { d[k] = v }; return d }   // 렌더용 = 캐시 우선

    // 액션 세트는 **장착 무기 종류**에 따라 idle/walk/attack 스탠스가 달라짐.
    // (프레임 수는 무기 무관 고정: idle/walk 4, swing 3, jump/prone 1, rope 2 — animated GIF로 확정)
    var actions: [CharAction] { Self.actions(forWeapon: displaySelection[.weapon]) }
    static func actions(forWeapon wid: Int?) -> [CharAction] {
        let polearm = ((wid ?? 0) / 10000 == 143 || (wid ?? 0) / 10000 == 144)  // 창·폴암 → stand2/walk2
        let idle = polearm ? "stand2" : "stand1"
        let walk = polearm ? "walk2"  : "walk1"
        var acts: [CharAction] = [
            CharAction(anim: "idle",  stance: idle,   count: 4),
            CharAction(anim: "walk",  stance: walk,   count: 4),
            CharAction(anim: "jump",  stance: "jump", count: 1),
            CharAction(anim: "prone", stance: "prone",count: 1),
            CharAction(anim: "climb", stance: "rope", count: 2),
            CharAction(anim: "proneAttack", stance: "proneStab", count: 2),   // 숙여서 찌르기(모든 무기 보임)
        ]
        // 공격 모션은 무기별로 여러 개 → 게임에서 칠 때마다 랜덤 1개 재생(찌르기/휘두르기 등 다양)
        for (i, m) in attackMotions(forWeapon: wid).enumerated() {
            acts.append(CharAction(anim: "attack\(i)", stance: m.stance, count: m.count))
        }
        return acts
    }
    // 무기 종류별 "전 프레임에서 무기가 보이는" 공격 스탠스들(실측). itemId//10000 = 무기 카테고리.
    static func attackMotions(forWeapon wid: Int?) -> [(stance: String, count: Int)] {
        switch (wid ?? 0) / 10000 {
        case 143, 144:        // 창·폴암: 휘두르기2 + 찌르기2
            return [("swingP1", 3), ("swingP2", 3), ("stabT1", 3), ("stabT2", 3)]
        case 140, 141, 142:   // 두손 검/도끼/둔기: 머리위 휘두르기3 + 찌르기
            return [("swingT1", 3), ("swingT2", 3), ("swingT3", 3), ("stabO2", 2)]
        default:              // 1H 검·도끼·둔기 등: 가로 휘두르기2 + 찌르기 (swingT1은 가려짐)
            return [("swingO1", 3), ("swingO3", 3), ("stabO1", 2)]
        }
    }

    private(set) var regenerating = false

    func currentItems() -> [EquipPiece] {
        base + CharSlot.allCases.compactMap { displaySelection[$0].map { EquipPiece(id: $0) } }   // 캐시 외형 우선
    }
    static func comboKey(_ items: [EquipPiece]) -> String {
        items.map { String($0.id) }.sorted().joined(separator: "_")
    }

    // ── 캐시 디렉터리 ───────────────────────────────────────────
    static func cacheDir(_ key: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JumpQuest/chars/\(key)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    // ── URL ────────────────────────────────────────────────────
    static func charURL(_ items: [EquipPiece], stance: String, frame: Int) -> URL {
        let parts = items.map { p -> String in
            let json = "{\"itemId\":\(p.id),\"region\":\"\(p.region)\",\"version\":\"\(p.version)\"}"
            return json.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? json
        }.joined(separator: ",")
        let s = "https://maplestory.io/api/character/\(parts)/\(stance)/\(frame)?showears=false&resize=2&renderMode=Full"
        return URL(string: s)!
    }
    static func iconURL(_ id: Int) -> URL {
        URL(string: "https://maplestory.io/api/GMS/217/item/\(id)/icon")!
    }

    // ── 동기 fetch (백그라운드 큐 전용, 실패 시 재시도) ──────────
    static func fetchData(_ url: URL, timeout: TimeInterval = 30) -> Data? {
        for _ in 0..<3 {                              // 네트워크 플레이키 대비 최대 3회
            nonisolated(unsafe) var out: Data?
            let sem = DispatchSemaphore(value: 0)
            var req = URLRequest(url: url, timeoutInterval: timeout)
            req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: req) { d, resp, _ in
                if let d = d, let http = resp as? HTTPURLResponse, http.statusCode == 200 { out = d }
                sem.signal()
            }.resume()
            _ = sem.wait(timeout: .now() + timeout + 5)
            if let out = out { return out }
        }
        return nil
    }

    // ── 장비 교체 트리거: 백그라운드 fetch+align → completion(main) ──
    // completion: SKTexture로 디코드해서 GameScene이 swap
    func regenerate(items: [EquipPiece], completion: @escaping @MainActor (DecodedCombo?) -> Void) {
        if regenerating { return }
        regenerating = true
        let acts = actions
        DispatchQueue.global(qos: .userInitiated).async {
            // 서버 풀렌더 + base 무게중심 단일정렬(조합별 디스크 캐싱). 디코드까지 백그라운드에서 끝내
            // 메인은 텍스처 할당만 → 장착 시 프레임 끊김 제거.
            var decoded: DecodedCombo? = nil
            if let result = Self.buildComboServer(items: items, actions: acts) {
                decoded = DecodedCombo(anims: Self.decodeTextures(result.framesPNG),
                                       feet: result.feetFrac, center: result.bodyCenterFrac)
            }
            DispatchQueue.main.async {
                self.regenerating = false
                completion(decoded)
            }
        }
    }

    // PNG Data → SKTexture (백그라운드 스레드에서 호출). SKTexture 생성은 스레드 안전.
    nonisolated static func decodeTextures(_ framesPNG: [String: [Data]]) -> [String: [SKTexture]] {
        var out: [String: [SKTexture]] = [:]
        for (k, arr) in framesPNG {
            out[k] = arr.compactMap { d -> SKTexture? in
                guard let img = NSImage(data: d) else { return nil }
                let t = SKTexture(image: img); t.filteringMode = .nearest; return t
            }
        }
        return out
    }

    // ── 조합 생성: 캐시 있으면 로드, 없으면 fetch+align+저장 ──────
    static func buildCombo(items: [EquipPiece], actions: [CharAction]) -> ComboResult? {
        let key = comboKey(items)
        let dir = cacheDir(key)
        // 캐시 확인 (메타 + 모든 프레임)
        let metaURL = dir.appendingPathComponent("meta.json")
        if let meta = try? Data(contentsOf: metaURL),
           let m = try? JSONSerialization.jsonObject(with: meta) as? [String: Any],
           let feet = m["feetFrac"] as? Double, let bc = m["bodyCenterFrac"] as? Double {
            var cached: [String: [Data]] = [:]
            var ok = true
            for a in actions {
                var arr: [Data] = []
                for f in 0..<a.count {
                    let u = dir.appendingPathComponent("player_\(a.anim)\(f).png")
                    if let d = try? Data(contentsOf: u) { arr.append(d) } else { ok = false; break }
                }
                if !ok { break }
                cached[a.anim] = arr
            }
            if ok { return ComboResult(framesPNG: cached, feetFrac: CGFloat(feet), bodyCenterFrac: CGFloat(bc)) }
        }
        // fetch 원본 프레임
        var rawByAnim: [(anim: String, frames: [CGImage])] = []
        for a in actions {
            var imgs: [CGImage] = []
            for f in 0..<a.count {
                guard let d = fetchData(charURL(items, stance: a.stance, frame: f)),
                      let src = CGImageSourceCreateWithData(d as CFData, nil),
                      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
                imgs.append(img)
            }
            rawByAnim.append((a.anim, imgs))
        }
        guard let aligned = align(rawByAnim: rawByAnim, standAnim: "idle") else { return nil }
        // PNG 인코딩 + 캐시 저장
        var out: [String: [Data]] = [:]
        for (anim, imgs) in aligned.frames {
            var arr: [Data] = []
            for (f, img) in imgs.enumerated() {
                guard let d = pngData(img) else { continue }
                arr.append(d)
                try? d.write(to: dir.appendingPathComponent("player_\(anim)\(f).png"))
            }
            out[anim] = arr
        }
        let meta: [String: Any] = ["feetFrac": Double(aligned.feetFrac), "bodyCenterFrac": Double(aligned.bodyCenterFrac)]
        if let md = try? JSONSerialization.data(withJSONObject: meta) { try? md.write(to: metaURL) }
        return ComboResult(framesPNG: out, feetFrac: aligned.feetFrac, bodyCenterFrac: aligned.bodyCenterFrac)
    }

    // ── 무게중심 정렬 (build_char4 포팅) ────────────────────────
    private struct Buf { let w: Int; let h: Int; var p: [UInt8] }   // row0 = TOP
    private static func toBuf(_ img: CGImage) -> Buf {
        let w = img.width, h = img.height
        var d = [UInt8](repeating: 0, count: w * h * 4)
        d.withUnsafeMutableBytes { ptr in
            let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return Buf(w: w, h: h, p: d)
    }
    private static func alpha(_ b: Buf, _ x: Int, _ y: Int) -> Int { Int(b.p[(y * b.w + x) * 4 + 3]) }
    private static func feetRow(_ b: Buf) -> Int {
        var y = b.h - 1
        while y >= 0 { for x in 0..<b.w where alpha(b, x, y) > 25 { return y }; y -= 1 }
        return b.h - 1
    }
    private static func centroid(_ b: Buf) -> (Double, Double) {
        var sx = 0, sy = 0, c = 0
        for y in 0..<b.h { for x in 0..<b.w where alpha(b, x, y) > 60 { sx += x; sy += y; c += 1 } }
        return c > 0 ? (Double(sx) / Double(c), Double(sy) / Double(c)) : (Double(b.w) / 2, Double(b.h) / 2)
    }

    static func align(rawByAnim: [(anim: String, frames: [CGImage])], standAnim: String)
        -> (frames: [String: [CGImage]], feetFrac: CGFloat, bodyCenterFrac: CGFloat)? {
        let FW = 480, FH = 380
        let CX = Double(FW) / 2, CY = Double(FH) * 0.52
        var placed: [(anim: String, idx: Int, buf: [UInt8])] = []
        var standFeetFinal = 0
        for (anim, imgs) in rawByAnim {
            for (i, img) in imgs.enumerated() {
                let b = toBuf(img)
                let (cx, cy) = centroid(b)
                let offX = Int((CX - cx).rounded()), offY = Int((CY - cy).rounded())
                if anim == standAnim { standFeetFinal = max(standFeetFinal, feetRow(b) + offY) }
                var out = [UInt8](repeating: 0, count: FW * FH * 4)
                for y in 0..<b.h {
                    let oy = y + offY; if oy < 0 || oy >= FH { continue }
                    for x in 0..<b.w {
                        let ox = x + offX; if ox < 0 || ox >= FW { continue }
                        let si = (y * b.w + x) * 4; if b.p[si + 3] == 0 { continue }
                        let di = (oy * FW + ox) * 4
                        out[di] = b.p[si]; out[di+1] = b.p[si+1]; out[di+2] = b.p[si+2]; out[di+3] = b.p[si+3]
                    }
                }
                placed.append((anim, i, out))
            }
        }
        guard !placed.isEmpty else { return nil }
        // union bbox
        var uminX = FW, umaxX = 0, uminY = FH, umaxY = 0
        for p in placed {
            for y in 0..<FH { for x in 0..<FW where p.buf[(y * FW + x) * 4 + 3] > 15 {
                if x < uminX { uminX = x }; if x > umaxX { umaxX = x }
                if y < uminY { uminY = y }; if y > umaxY { umaxY = y }
            } }
        }
        let cw = umaxX - uminX + 1, ch = umaxY - uminY + 1
        guard cw > 0, ch > 0 else { return nil }
        let feetInCrop = standFeetFinal - uminY
        let feetFromBottom = ch - 1 - feetInCrop
        let centerXcrop = Int(CX) - uminX
        let feetFrac = CGFloat(max(0, feetFromBottom)) / CGFloat(ch)
        let bodyCenterFrac = CGFloat(cw - 1 - centerXcrop) / CGFloat(cw)
        // crop + 가로 flip → CGImage
        var result: [String: [CGImage]] = [:]
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        for p in placed {
            var crop = [UInt8](repeating: 0, count: cw * ch * 4)
            for y in 0..<ch { for x in 0..<cw {
                let sx = umaxX - x, sy = uminY + y
                let si = (sy * FW + sx) * 4, di = (y * cw + x) * 4
                crop[di] = p.buf[si]; crop[di+1] = p.buf[si+1]; crop[di+2] = p.buf[si+2]; crop[di+3] = p.buf[si+3]
            } }
            guard let prov = CGDataProvider(data: Data(crop) as CFData),
                  let img = CGImage(width: cw, height: ch, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: cw * 4, space: cs,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            else { continue }
            result[p.anim, default: []].append(img)
        }
        // 프레임 순서 보장 (idx 순)
        for (anim, imgs) in rawByAnim where result[anim] != nil {
            if result[anim]!.count != imgs.count { /* 일부 누락 허용 */ }
        }
        return (result, feetFrac, bodyCenterFrac)
    }

    private static func pngData(_ img: CGImage) -> Data? {
        let m = NSMutableData()
        guard let d = CGImageDestinationCreateWithData(m, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(d, img, nil)
        guard CGImageDestinationFinalize(d) else { return nil }
        return m as Data
    }


    // 헤드리스 검증: 현재 선택 조합을 fetch+정렬해서 /tmp/chargen_test/에 저장 (창 안 띄움)
    static func selfTest() {
        // CHARGEN_SEL="hat:1002357,weapon:1302000" 로 슬롯 override 가능
        if let sel = ProcessInfo.processInfo.environment["CHARGEN_SEL"] {
            for pair in sel.split(separator: ",") {
                let kv = pair.split(separator: ":")
                if kv.count == 2, let slot = CharSlot(rawValue: String(kv[0])), let id = Int(kv[1]) {
                    shared.selection[slot] = id
                }
            }
        }
        let items = shared.currentItems()
        FileHandle.standardError.write("CHARGEN_TEST items=\(items.map { $0.id })\n".data(using: .utf8)!)
        let r0 = buildComboServer(items: items, actions: shared.actions)
        guard let r = r0 else {
            FileHandle.standardError.write("CHARGEN_TEST FAIL\n".data(using: .utf8)!); return
        }
        let dir = URL(fileURLWithPath: "/tmp/chargen_test")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (anim, arr) in r.framesPNG {
            for (f, d) in arr.enumerated() { try? d.write(to: dir.appendingPathComponent("player_\(anim)\(f).png")) }
        }
        let counts = r.framesPNG.mapValues { $0.count }
        FileHandle.standardError.write("CHARGEN_TEST OK feetFrac=\(r.feetFrac) bodyCenterFrac=\(r.bodyCenterFrac) anims=\(counts)\n".data(using: .utf8)!)
    }
}

// ── Phase 2: 로컬 레이어링 (diff-overlay) ──────────────────────────────
// base(몸통+머리+얼굴, 고정)와 각 장비의 diff 레이어를 캐싱 →
// 조합은 로컬에서 즉시 합성(네트워크 없음). 서버는 base/base+단일아이템만 렌더.
extension CharacterRenderer {
    static let baseItems = [2000, 12000]

    static func layersBase() -> URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JumpQuest/layers/_base", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u
    }
    static func layersItem(_ id: Int) -> URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JumpQuest/layers/item_\(id)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u
    }
    static func fetchCG(_ url: URL) -> CGImage? {
        guard let d = fetchData(url), let s = CGImageSourceCreateWithData(d as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(s, 0, nil)
    }
    static func cgFromBuf(_ buf: [UInt8], _ w: Int, _ h: Int) -> CGImage {
        let csp = CGColorSpace(name: CGColorSpace.sRGB)!
        let prov = CGDataProvider(data: Data(buf) as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: csp, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    // base 렌더 (캐시)
    static func baseRender(_ stance: String, _ frame: Int) -> CGImage? {
        let f = layersBase().appendingPathComponent("\(stance)_\(frame).png")
        if let d = try? Data(contentsOf: f), let s = CGImageSourceCreateWithData(d as CFData, nil),
           let img = CGImageSourceCreateImageAtIndex(s, 0, nil) { return img }
        guard let img = fetchCG(charURL(baseItems.map { EquipPiece(id: $0) }, stance: stance, frame: frame)) else { return nil }
        if let d = pngData(img) { try? d.write(to: f, options: .atomic) }
        return img
    }

    // base가 g 안 어디에 위치하나. containment-penalty 스코어:
    // 색일치 +2, 가려짐(G불투명·색다름) 0, 삐져나옴(base불투명인데 G투명) -3.
    // → base가 G 안에 온전히 들어가는(올바른) offset만 높은 점수. 베어바디 좌우대칭 오정렬 방지.
    private static func bestOffset(_ base: Buf, _ g: Buf) -> (Int, Int)? {
        var samples: [(Int, Int, Int, Int, Int)] = []
        var n = 0
        for y in 0..<base.h { for x in 0..<base.w {
            let i = (y * base.w + x) * 4; if Int(base.p[i + 3]) > 180 { n += 1
                if n % 2 == 0 { samples.append((x, y, Int(base.p[i]), Int(base.p[i+1]), Int(base.p[i+2]))) } }
        } }
        if samples.count < 10 { return nil }
        var best = (0, 0); var bestScore = Int.min
        let maxOY = max(0, g.h - base.h), maxOX = max(0, g.w - base.w)
        for oy in 0...maxOY { for ox in 0...maxOX {
            var s = 0
            for (sx, sy, sr, sg, sb) in samples {
                let gi = ((sy + oy) * g.w + (sx + ox)) * 4
                if Int(g.p[gi+3]) > 120 {
                    if abs(Int(g.p[gi]) - sr) + abs(Int(g.p[gi+1]) - sg) + abs(Int(g.p[gi+2]) - sb) <= 40 { s += 2 }
                } else { s -= 3 }
            }
            if s > bestScore { bestScore = s; best = (ox, oy) }
        } }
        return best
    }

    // 아이템 diff 레이어 (캐시): base+item 렌더 → base와 다른 픽셀만 크롭 + base-relative offset
    private static func itemLayer(_ id: Int, _ stance: String, _ frame: Int, _ baseBuf: Buf) -> (Data, Int, Int)? {
        let imgF = layersItem(id).appendingPathComponent("\(stance)_\(frame).png")
        let metaF = layersItem(id).appendingPathComponent("\(stance)_\(frame).json")
        if let md = try? Data(contentsOf: metaF),
           let m = try? JSONSerialization.jsonObject(with: md) as? [String: Int],
           let rx = m["x"], let ry = m["y"], let d = try? Data(contentsOf: imgF) { return (d, rx, ry) }
        let items = baseItems.map { EquipPiece(id: $0) } + [EquipPiece(id: id)]
        guard let g = fetchCG(charURL(items, stance: stance, frame: frame)) else { return nil }
        let gb = toBuf(g)
        guard let (bx, by) = bestOffset(baseBuf, gb) else { return nil }
        var diff = [UInt8](repeating: 0, count: gb.w * gb.h * 4)
        var minX = gb.w, minY = gb.h, maxX = -1, maxY = -1
        for y in 0..<gb.h { for x in 0..<gb.w {
            let gi = (y * gb.w + x) * 4; if Int(gb.p[gi+3]) < 8 { continue }
            let bxp = x - bx, byp = y - by
            if bxp >= 0, bxp < baseBuf.w, byp >= 0, byp < baseBuf.h {
                let bi = (byp * baseBuf.w + bxp) * 4
                if baseBuf.p[bi+3] > 8 &&
                   abs(Int(gb.p[gi]) - Int(baseBuf.p[bi])) + abs(Int(gb.p[gi+1]) - Int(baseBuf.p[bi+1])) + abs(Int(gb.p[gi+2]) - Int(baseBuf.p[bi+2])) < 24 { continue }
            }
            diff[gi] = gb.p[gi]; diff[gi+1] = gb.p[gi+1]; diff[gi+2] = gb.p[gi+2]; diff[gi+3] = gb.p[gi+3]
            if x < minX { minX = x }; if x > maxX { maxX = x }; if y < minY { minY = y }; if y > maxY { maxY = y }
        } }
        if maxX < 0 {   // 변화 없음 (장비가 안 보임) → 1x1 투명
            let empty = cgFromBuf([0,0,0,0], 1, 1); let d = pngData(empty) ?? Data()
            try? d.write(to: imgF); try? JSONSerialization.data(withJSONObject: ["x": 0, "y": 0]).write(to: metaF)
            return (d, 0, 0)
        }
        let cw = maxX - minX + 1, ch = maxY - minY + 1
        var crop = [UInt8](repeating: 0, count: cw * ch * 4)
        for y in 0..<ch { for x in 0..<cw {
            let si = ((minY + y) * gb.w + (minX + x)) * 4, di = (y * cw + x) * 4
            crop[di] = diff[si]; crop[di+1] = diff[si+1]; crop[di+2] = diff[si+2]; crop[di+3] = diff[si+3]
        } }
        let cropImg = cgFromBuf(crop, cw, ch)
        let relX = minX - bx, relY = minY - by
        guard let d = pngData(cropImg) else { return nil }
        try? d.write(to: imgF)
        try? JSONSerialization.data(withJSONObject: ["x": relX, "y": relY]).write(to: metaF)
        return (d, relX, relY)
    }

    // 로컬 합성: base + overlay diff들(z순서) → 한 프레임
    static func composeLocal(_ overlayIds: [Int], _ stance: String, _ frame: Int) -> CGImage? {
        guard let base = baseRender(stance, frame) else { return nil }
        let baseBuf = toBuf(base)
        let CWc = 360, CHc = 360, BX = 130, BY = 110
        var canvas = [UInt8](repeating: 0, count: CWc * CHc * 4)
        func over(_ src: Buf, _ ox: Int, _ oy: Int) {
            for y in 0..<src.h { for x in 0..<src.w {
                let si = (y * src.w + x) * 4; let sa = Int(src.p[si+3]); if sa == 0 { continue }
                let cx = x + ox, cy = y + oy; if cx < 0 || cx >= CWc || cy < 0 || cy >= CHc { continue }
                let di = (cy * CWc + cx) * 4; let ia = 255 - sa
                canvas[di]   = UInt8(min(255, Int(src.p[si])   + Int(canvas[di])   * ia / 255))
                canvas[di+1] = UInt8(min(255, Int(src.p[si+1]) + Int(canvas[di+1]) * ia / 255))
                canvas[di+2] = UInt8(min(255, Int(src.p[si+2]) + Int(canvas[di+2]) * ia / 255))
                canvas[di+3] = UInt8(min(255, sa               + Int(canvas[di+3]) * ia / 255))
            } }
        }
        over(baseBuf, BX, BY)
        for id in overlayIds {
            guard let (d, rx, ry) = itemLayer(id, stance, frame, baseBuf),
                  let s = CGImageSourceCreateWithData(d as CFData, nil),
                  let dimg = CGImageSourceCreateImageAtIndex(s, 0, nil) else { continue }
            over(toBuf(dimg), BX + rx, BY + ry)
        }
        return cgFromBuf(canvas, CWc, CHc)
    }

    // Phase 2 진입점: 로컬 합성 → **base(몸통)만의 무게중심**으로 정렬.
    // 장비(무기/망토)가 움직여도 몸 무게중심은 고정 → 흔들림 없음. base는 모든 조합 공통 → 크기 일정.
    static func buildComboLocal(overlayOrdered: [Int], actions: [CharAction]) -> ComboResult? {
        let BX = 130, BY = 110, FW = 480, FH = 380
        let TX = Double(FW) / 2, TY = Double(FH) * 0.5      // base 무게중심 목표점
        var placed: [(anim: String, buf: [UInt8])] = []
        var standFeetFinal = 0
        for a in actions {
            for f in 0..<a.count {
                guard let comp = composeLocal(overlayOrdered, a.stance, f),
                      let baseR = baseRender(a.stance, f) else { return nil }
                let cb = toBuf(comp), bb = toBuf(baseR)
                let (bcx, bcy) = centroid(bb)                // base 무게중심(base render 좌표)
                let offX = Int((TX - (Double(BX) + bcx)).rounded())   // composite의 base무게중심 → (TX,TY)
                let offY = Int((TY - (Double(BY) + bcy)).rounded())
                if a.anim == "idle" { standFeetFinal = max(standFeetFinal, (BY + feetRow(bb)) + offY) }
                var out = [UInt8](repeating: 0, count: FW * FH * 4)
                for y in 0..<cb.h { let oy = y + offY; if oy < 0 || oy >= FH { continue }
                    for x in 0..<cb.w { let ox = x + offX; if ox < 0 || ox >= FW { continue }
                        let si = (y * cb.w + x) * 4; if cb.p[si + 3] == 0 { continue }
                        let di = (oy * FW + ox) * 4
                        out[di] = cb.p[si]; out[di+1] = cb.p[si+1]; out[di+2] = cb.p[si+2]; out[di+3] = cb.p[si+3] } }
                placed.append((a.anim, out))
            }
        }
        var uMinX = FW, uMaxX = 0, uMinY = FH, uMaxY = 0
        for p in placed { for y in 0..<FH { for x in 0..<FW where p.buf[(y * FW + x) * 4 + 3] > 15 {
            if x < uMinX { uMinX = x }; if x > uMaxX { uMaxX = x }; if y < uMinY { uMinY = y }; if y > uMaxY { uMaxY = y } } } }
        let cw = uMaxX - uMinX + 1, ch = uMaxY - uMinY + 1
        guard cw > 0, ch > 0 else { return nil }
        let feetFromBottom = ch - 1 - (standFeetFinal - uMinY)
        let centerXcrop = Int(TX) - uMinX
        let feetFrac = CGFloat(max(0, feetFromBottom)) / CGFloat(ch)
        let bodyCenterFrac = CGFloat(cw - 1 - centerXcrop) / CGFloat(cw)   // 가로 flip 후
        var out: [String: [Data]] = [:]
        for p in placed {
            var crop = [UInt8](repeating: 0, count: cw * ch * 4)
            for y in 0..<ch { for x in 0..<cw { let sx = uMaxX - x, sy = uMinY + y     // 가로 flip
                let si = (sy * FW + sx) * 4, di = (y * cw + x) * 4
                crop[di] = p.buf[si]; crop[di+1] = p.buf[si+1]; crop[di+2] = p.buf[si+2]; crop[di+3] = p.buf[si+3] } }
            if let d = pngData(cgFromBuf(crop, cw, ch)) { out[p.anim, default: []].append(d) }
        }
        return ComboResult(framesPNG: out, feetFrac: feetFrac, bodyCenterFrac: bodyCenterFrac)
    }

    // ── 권장 경로: 서버 풀렌더 + base 무게중심 단일정렬 ───────────────────
    // 서버가 합성/가림/z순서/안티에일리어싱을 정확히 처리한 풀조합 프레임을 받아,
    // 프레임마다 "base(몸통)가 풀렌더 안 어디 있는지"를 bestOffset로 한 번만 찾아
    // base 무게중심을 고정점(TX,TY)에 맞춘다. → 무기가 커도 몸 흔들림/겹침/구멍 없음.
    // (diff-overlay는 아이템별 정렬 누적오차·근살색 옷 구멍·가려진 무기 손실 문제로 폐기)
    static func buildComboServer(items: [EquipPiece], actions: [CharAction]) -> ComboResult? {
        let key = comboKey(items)
        let dir = cacheDir(key)
        let metaURL = dir.appendingPathComponent("meta.json")
        if let meta = try? Data(contentsOf: metaURL),
           let m = try? JSONSerialization.jsonObject(with: meta) as? [String: Any],
           let feet = m["feetFrac"] as? Double, let bc = m["bodyCenterFrac"] as? Double {
            var cached: [String: [Data]] = [:]; var ok = true
            for a in actions {
                var arr: [Data] = []
                for f in 0..<a.count {
                    if let d = try? Data(contentsOf: dir.appendingPathComponent("player_\(a.anim)\(f).png")) { arr.append(d) }
                    else { ok = false; break }
                }
                if !ok { break }; cached[a.anim] = arr
            }
            if ok { return ComboResult(framesPNG: cached, feetFrac: CGFloat(feet), bodyCenterFrac: CGFloat(bc)) }
        }
        let FW = 480, FH = 380
        let TX = Double(FW) / 2, FEET_Y = Double(FH) * 0.68   // 가로 중심점 / 발끝 고정선
        let standFeetFinal = Int(FEET_Y.rounded())            // 모든 포즈 발끝을 FEET_Y에 맞춤 → 항상 같은 높이
        // ── Phase A(병렬): 프레임별 fetch(네트워크) + 합성(toBuf/bestOffset/픽셀복사, CPU)을 동시에 (동시 8개) ──
        let jobs: [(anim: String, stance: String, f: Int)] =
            actions.flatMap { a in (0..<a.count).map { (a.anim, a.stance, $0) } }
        nonisolated(unsafe) var placedArr = [[UInt8]?](repeating: nil, count: jobs.count)  // 락으로 보호(인덱스별)
        let lock = NSLock()
        let sem = DispatchSemaphore(value: 8)
        let group = DispatchGroup()
        let fq = DispatchQueue(label: "combo.build", attributes: .concurrent)
        for (i, j) in jobs.enumerated() {
            sem.wait(); group.enter()
            fq.async {
                defer { sem.signal(); group.leave() }
                guard let g = fetchCG(charURL(items, stance: j.stance, frame: j.f)),   // 네트워크(캐시 없을 때)
                      let baseR = baseRender(j.stance, j.f) else { return }              // 실패→placedArr[i]=nil→아래서 전체 실패
                let gb = toBuf(g), bb = toBuf(baseR)
                let (bcx, bcy) = centroid(bb)
                let off = bestOffset(bb, gb)                       // base가 풀렌더 안 어디 있나 (프레임당 1회)
                let bx = off?.0 ?? Int((centroid(gb).0 - bcx).rounded())
                let by = off?.1 ?? Int((centroid(gb).1 - bcy).rounded())
                // 가로=몸 중심, 세로=base(몸) 발끝을 FEET_Y에 고정 → 공격/포즈 바뀌어도 발이 안 뜸
                let offX = Int((TX - (Double(bx) + bcx)).rounded())
                let offY = Int((FEET_Y - Double(by + feetRow(bb))).rounded())
                var out = [UInt8](repeating: 0, count: FW * FH * 4)
                for y in 0..<gb.h { let oy = y + offY; if oy < 0 || oy >= FH { continue }
                    for x in 0..<gb.w { let ox = x + offX; if ox < 0 || ox >= FW { continue }
                        let si = (y * gb.w + x) * 4; if gb.p[si + 3] == 0 { continue }
                        let di = (oy * FW + ox) * 4
                        out[di] = gb.p[si]; out[di+1] = gb.p[si+1]; out[di+2] = gb.p[si+2]; out[di+3] = gb.p[si+3] } }
                lock.lock(); placedArr[i] = out; lock.unlock()
            }
        }
        group.wait()
        var placed: [(anim: String, buf: [UInt8])] = []
        for (i, j) in jobs.enumerated() {
            guard let b = placedArr[i] else { return nil }    // 한 프레임이라도 실패 → 전체 실패(기존 동작 유지)
            placed.append((j.anim, b))
        }
        guard !placed.isEmpty else { return nil }
        var uMinX = FW, uMaxX = 0, uMinY = FH, uMaxY = 0
        for p in placed { for y in 0..<FH { for x in 0..<FW where p.buf[(y * FW + x) * 4 + 3] > 15 {
            if x < uMinX { uMinX = x }; if x > uMaxX { uMaxX = x }; if y < uMinY { uMinY = y }; if y > uMaxY { uMaxY = y } } } }
        let cw = uMaxX - uMinX + 1, ch = uMaxY - uMinY + 1
        guard cw > 0, ch > 0 else { return nil }
        let feetFromBottom = ch - 1 - (standFeetFinal - uMinY)
        let centerXcrop = Int(TX) - uMinX
        let feetFrac = CGFloat(max(0, feetFromBottom)) / CGFloat(ch)
        let bodyCenterFrac = CGFloat(cw - 1 - centerXcrop) / CGFloat(cw)   // 가로 flip 후
        // ── Phase C(병렬): 프레임별 crop+가로flip+PNG인코딩 동시에 → 이후 순차 조립/저장(빠름) ──
        let flipMaxX = uMaxX, cropMinY = uMinY    // 불변 복사(동시 클로저 캡처용)
        nonisolated(unsafe) var dataArr = [Data?](repeating: nil, count: placed.count)
        let lock2 = NSLock()
        let sem2 = DispatchSemaphore(value: 8)
        let group2 = DispatchGroup()
        let eq = DispatchQueue(label: "combo.encode", attributes: .concurrent)
        for (i, p) in placed.enumerated() {
            sem2.wait(); group2.enter()
            eq.async {
                defer { sem2.signal(); group2.leave() }
                var crop = [UInt8](repeating: 0, count: cw * ch * 4)
                for y in 0..<ch { for x in 0..<cw { let sx = flipMaxX - x, sy = cropMinY + y     // 가로 flip
                    let si = (sy * FW + sx) * 4, di = (y * cw + x) * 4
                    crop[di] = p.buf[si]; crop[di+1] = p.buf[si+1]; crop[di+2] = p.buf[si+2]; crop[di+3] = p.buf[si+3] } }
                let d = pngData(cgFromBuf(crop, cw, ch))
                lock2.lock(); dataArr[i] = d; lock2.unlock()
            }
        }
        group2.wait()
        var out: [String: [Data]] = [:]
        for (i, p) in placed.enumerated() {     // 조립·디스크 저장은 순차(빠름, 원자적 쓰기)
            guard let d = dataArr[i] else { return nil }   // 인코딩 실패 → 전체 실패(프레임 번호 밀림 방지, meta 미기록→다음에 재빌드)
            out[p.anim, default: []].append(d)
            try? d.write(to: dir.appendingPathComponent("player_\(p.anim)\(out[p.anim]!.count - 1).png"), options: .atomic)
        }
        let metaOut: [String: Any] = ["feetFrac": Double(feetFrac), "bodyCenterFrac": Double(bodyCenterFrac)]
        if let md = try? JSONSerialization.data(withJSONObject: metaOut) { try? md.write(to: metaURL, options: .atomic) }
        return ComboResult(framesPNG: out, feetFrac: feetFrac, bodyCenterFrac: bodyCenterFrac)
    }

    // 선택 → z순서 overlay id (망토 뒤 → 옷 → 무기(검은 옷보다 앞) → 머리 → 얼굴 → 모자 앞)
    func overlayOrder() -> [Int] {
        var ids: [Int] = []
        for s in [CharSlot.cape, .overall, .weapon, .hair, .face, .hat] {
            if let id = selection[s] { ids.append(id) }
        }
        return ids
    }

    // ── 프리페치: 브라우징 중 백그라운드로 레이어 캐싱 → 확인 시 즉시 합성 ──
    private static let prefetchQueue = DispatchQueue(label: "chargen.prefetch", qos: .utility)
    // 한 (id, stance, frame) 캐싱 (디스크에 base/item 레이어 저장)
    static func cacheItemFrame(_ id: Int, _ stance: String, _ frame: Int) {
        guard let base = baseRender(stance, frame) else { return }
        _ = itemLayer(id, stance, frame, toBuf(base))
    }
    func prefetchBase() {
        Self.prefetchQueue.async { for a in self.actions { for f in 0..<a.count { _ = Self.baseRender(a.stance, f) } } }
    }
    func prefetchItem(_ id: Int) {
        Self.prefetchQueue.async { for a in self.actions { for f in 0..<a.count { Self.cacheItemFrame(id, a.stance, f) } } }
    }

}
