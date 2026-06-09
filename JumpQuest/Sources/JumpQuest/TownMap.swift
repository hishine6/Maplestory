// 자동생성+정리: maplestory.io GMS map 1000000 (Amherst / 메이플 아일랜드 마을).
// world->game: gx=worldX+260. gy 보정: vrBounds.top(-506)는 ~96px 어긋나 실제 오프셋 -410 사용
//   → gy = 493 - worldY (= 잔디 표면에 발판이 얹힘, 잔디띠 검출로 보정함).
// townGround=앞 바닥(솔리드 블록,연속 테라스) / townPlatforms=뒤 얇은 1방향 발판 / townRopes=밧줄.
import SpriteKit

extension GameScene {
    static let townW: CGFloat = 2799
    static let townH: CGFloat = 903
    // 메인 3단 바닥(연속): 왼쪽 낮은 지면 → 가운데 높은 지면 → 오른쪽 낮은 지면 (+96 보정 적용)
    static let townGround: [(x1: CGFloat, x2: CGFloat, top: CGFloat)] = [
        (0, 1060, 219),
        (1060, 1120, 279),     // 중간 단(60px씩 두 번 오르게)
        (1120, 1990, 339),
        (1990, 2055, 279),
        (2055, 2799, 219),
    ]
    // 뒤쪽 높은 발판(버섯집 단상=Sid, 오른쪽 계단)
    static let townPlatforms: [(x1: CGFloat, x2: CGFloat, top: CGFloat)] = [
        (447, 1243, 549),
        (2022, 2188, 399),
        (2112, 2278, 579),
        (2112, 2278, 639),
    ]
    static let townRopes: [(x: CGFloat, bottomY: CGFloat, topY: CGFloat)] = [
        (1178, 341, 547),
        (2149, 401, 577),
    ]
    // NPC: (스프라이트, 표시이름, gx, gy=발끝, 좌우반전, 상점여부, 대사)  (+96 보정)
    static let townNPCs: [(sprite: String, name: String, x: CGFloat, y: CGFloat, flip: Bool, shop: Bool, line: String)] = [
        ("rain",  "레인",   363,  219, true,  false, "메이플 아일랜드에 온 걸 환영해!"),
        ("pio",   "피오",   807,  219, false, true,  "물약 필요하면 나한테 와!"),    // 잡화상점
        ("lucy",  "루시",   1513, 339, false, false, "위험한 숲엔 몬스터가 많으니 조심해."),
        ("lucas", "루카스", 1870, 339, false, false, "나는 이 마을의 촌장 루카스란다."),
        ("sid",   "시드",   974,  549, false, false, "밧줄을 타고 올라왔구나! 멋진걸."),    // 뒤 단상(밧줄로)
    ]
}
