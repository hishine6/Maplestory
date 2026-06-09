import SwiftUI

// ============================================================
//  이 파일은 "데이터의 모양"을 정의해요.
//  - WorkSession : 작업 한 구간(언제~언제 무엇을 했나)
//  - TagStyle    : 해시태그(#개발 같은)별 색을 정해주는 도우미
//  - Fmt         : 초(seconds)를 사람이 읽기 좋은 글자로 바꿔주는 도우미
//  화면 그리는 코드는 다른 파일에 있고, 여기는 순수한 '재료'만 둬요.
// ============================================================


// ── 작업 한 구간 ────────────────────────────────────────────
// "오후 2시 30분 ~ 4시 5분 동안 무엇을 했나" 한 기록.
// 설명(note)과 태그(tags)를 '따로' 저장해요. 한 기록에 태그를 여러 개 달 수 있어요.
struct WorkSession: Identifiable, Codable, Hashable {
    var id: UUID
    var start: Date                    // 시작 시각
    var end: Date                      // 끝난 시각
    var note: String                   // 설명 (태그 미포함)
    var tags: [String]                 // 태그들 (소문자, 중복 없음) — 따로 저장
    var location: LocationStamp?       // 이 기록을 남긴 곳(선택)
    var categoryID: String?            // (아주 옛 버전 호환용. 불러올 때 tags로 옮기고 비워요)

    init(id: UUID = UUID(), start: Date, end: Date,
         note: String = "", tags: [String] = [],
         location: LocationStamp? = nil, categoryID: String? = nil) {
        self.id = id; self.start = start; self.end = end
        self.note = note; self.tags = tags
        self.location = location; self.categoryID = categoryID
    }

    // 이 구간이 몇 초였는지 = 끝 - 시작
    var duration: TimeInterval { end.timeIntervalSince(start) }
    // 대표 태그(색/차트 분류에 쓰임) = 첫 번째 태그
    var primaryTag: String? { tags.first }

    // ── 안전한 불러오기 ──
    // 예전 JSON엔 tags/location 키가 없어요. decodeIfPresent로 없으면 기본값을 써서
    // 옛 데이터도 깨지지 않게 불러와요.
    enum CodingKeys: String, CodingKey { case id, start, end, note, tags, location, categoryID }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        location = try c.decodeIfPresent(LocationStamp.self, forKey: .location)
        categoryID = try c.decodeIfPresent(String.self, forKey: .categoryID)
    }

    // ── 태그 글자 다루기 도우미 ──
    // "#개발" / "개발" → "개발" (소문자, 글자·숫자·_만). 비면 nil.
    static func normalizeTag(_ raw: String) -> String? {
        let body = raw.drop(while: { $0 == "#" }).prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        let t = body.lowercased()
        return t.isEmpty ? nil : t
    }

    // 입력칸 문자열을 여러 태그로 (공백/쉼표로 나눠서)
    static func parseTagInput(_ text: String) -> [String] {
        var out: [String] = []
        for token in text.split(whereSeparator: { $0.isWhitespace || $0 == "," }) {
            if let t = normalizeTag(String(token)), !out.contains(t) { out.append(t) }
        }
        return out
    }

    // 메모 안의 #태그를 뽑아내요 (구버전 마이그레이션용)
    static func extractTags(from text: String) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for token in text.split(whereSeparator: { $0.isWhitespace }) where token.hasPrefix("#") {
            let body = token.dropFirst().prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            let tag = body.lowercased()
            if !tag.isEmpty, !seen.contains(tag) { seen.insert(tag); result.append(tag) }
        }
        return result
    }

    // 메모에서 #태그 토큰을 빼고 설명만 남겨요 (구버전 마이그레이션용)
    static func stripHashtags(from text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace })
            .filter { !$0.hasPrefix("#") }
            .joined(separator: " ")
    }
}


// ── 해시태그 색 ─────────────────────────────────────────────
// 태그 글자를 보고 '항상 같은 색'을 골라줘요(차트/점 색깔용).
// (Swift의 hashValue는 실행마다 달라져서, 직접 안정적인 해시를 계산해요)
enum TagStyle {
    static let untaggedLabel = "태그 없음"

    static let palette: [Color] = [
        Color(red: 0.30, green: 0.55, blue: 0.98),   // 파랑
        Color(red: 0.61, green: 0.40, blue: 0.94),   // 보라
        Color(red: 0.98, green: 0.60, blue: 0.25),   // 주황
        Color(red: 0.20, green: 0.74, blue: 0.55),   // 초록
        Color(red: 0.95, green: 0.40, blue: 0.55),   // 분홍
        Color(red: 0.35, green: 0.78, blue: 0.92),   // 하늘
        Color(red: 0.85, green: 0.70, blue: 0.20),   // 노랑
        Color(red: 0.55, green: 0.55, blue: 0.95),   // 남보라
        Color(red: 0.40, green: 0.80, blue: 0.40),   // 연두
        Color(red: 0.90, green: 0.45, blue: 0.35),   // 다홍
    ]

    // 태그(# 없이)에 해당하는 안정적인 색
    static func color(forTag tag: String) -> Color {
        var h: UInt64 = 5381
        for b in tag.lowercased().utf8 { h = (h &* 33) &+ UInt64(b) }
        return palette[Int(h % UInt64(palette.count))]
    }

    // 차트 라벨("#개발" 또는 "태그 없음")에 해당하는 색
    static func color(forLabel label: String) -> Color {
        if label == untaggedLabel { return Color.gray.opacity(0.55) }
        let tag = label.hasPrefix("#") ? String(label.dropFirst()) : label
        return color(forTag: tag)
    }

    // 대표 태그를 화면 라벨("#개발" / "태그 없음")로
    static func label(for tag: String?) -> String {
        guard let tag, !tag.isEmpty else { return untaggedLabel }
        return "#\(tag)"
    }
}


// ── 태그 요약(태그 검색 페이지에서 사용) ────────────────────
// 한 태그가 '총 몇 초, 몇 번' 쓰였는지.
struct TagSummary: Identifiable, Hashable {
    let tag: String
    let seconds: TimeInterval
    let count: Int
    var id: String { tag }
}


// ── 위치 도장(어디서 기록했나) ──────────────────────────────
struct LocationStamp: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var name: String?      // 역지오코딩으로 얻은 장소 이름(있으면)
}


// ── 알림 방식 (시스템 알림 / 앱 안 토스트 중 하나만) ─────────
enum NotifyStyle: String, CaseIterable, Identifiable {
    case inApp = "앱 안 알림"
    case system = "시스템 알림"
    var id: String { rawValue }
}


// ── 휴지통에 담긴 기록 (삭제 후 일정 기간 복구 가능) ─────────
struct TrashedSession: Identifiable, Codable, Hashable {
    var session: WorkSession
    var deletedAt: Date          // 삭제한 시각 (이 시점부터 보관기간 카운트)
    var id: UUID { session.id }
}


// ── 시간 표시 도우미 ────────────────────────────────────────
// 초 단위 숫자를 사람이 읽기 좋은 글자로 바꿔주는 작은 함수 모음.
enum Fmt {

    // 1) 시계 모양: 3725초 → "1:02:05" (1시간 미만이면 "02:05")
    static func clock(_ t: TimeInterval) -> String {
        let total = max(0, Int(t))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    // 2) 한글 요약: 3725초 → "1시간 2분" (0분이면 "0분")
    static func human(_ t: TimeInterval) -> String {
        let total = max(0, Int(t))
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 && m > 0 { return "\(h)시간 \(m)분" }
        if h > 0 { return "\(h)시간" }
        return "\(m)분"
    }

    // 3) "14:30" 같은 시:분 (세션 목록의 시작/끝 표시용)
    static func hm(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // 4) "6월 9일 (월)" (히트맵 칸 툴팁용)
    static func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 (E)"
        return f.string(from: date)
    }

    // 5) "6월 9일" (지도 핀 라벨용 — 요일 없이 짧게)
    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일"
        return f.string(from: date)
    }
}
