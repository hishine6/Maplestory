import Foundation

// ============================================================
//  업적(배지) 시스템.
//
//  설계: 매번 세션 전체를 훑는 대신, 통계 스냅샷(TrackerStats)을
//  '한 번' 계산하고(아래 TimeTracker.makeStats), 각 업적은 그 숫자만
//  보고 달성 여부를 판단해요. → 100개여도 빠르고 단순해요.
//
//  Duolingo의 업적(연속 기록·누적·하루 집중·시간대 등)을 참고해
//  작업시간 트래커에 맞게 옮겼어요.
// ============================================================

// 업적 판단에 쓰는 '오늘까지의 요약 숫자들' (값 타입이라 안전하게 넘길 수 있어요)
struct TrackerStats: Sendable {
    var cumulativeSeconds: Double = 0          // 누적 총 시간(초)
    var sessionCount: Int = 0                  // 기록한 구간 수
    var streak: Int = 0                        // 연속 목표 달성 일수
    var longestSession: Double = 0             // 가장 긴 단일 구간(초)
    var daysTracked: Int = 0                   // 기록이 있는 날의 수
    var daysGoalMet: Int = 0                   // 목표를 달성한 날의 수
    var maxDayTotal: Double = 0                // 하루 최대 누적(초)
    var maxSessionsInDay: Int = 0              // 하루 최대 구간 수
    var tagSeconds: [String: Double] = [:]     // 태그별 누적(초)
    var notesCount: Int = 0                    // 메모를 남긴 구간 수
    var startHours: Set<Int> = []             // 구간을 시작한 '시각(0~23)'들
    var weekdays: Set<Int> = []               // 일한 요일들(1=일 … 7=토)
    var crossedMidnight: Bool = false         // 자정을 넘긴 구간이 있나
    var distinctTags: Int = 0                 // 사용한 태그 종류 수
    var maxTagSeconds: Double = 0             // 한 태그에 쏟은 최대 시간(초)
}


struct Achievement: Identifiable, Sendable {
    let id: String
    let title: String
    let emoji: String
    let detail: String
    let check: @Sendable (TrackerStats) -> Bool   // 통계를 보고 달성 여부 판단

    static let all: [Achievement] = makeAll()
    static func find(_ id: String) -> Achievement? { all.first { $0.id == id } }
}


// ── 업적 목록을 만드는 곳 ───────────────────────────────────
// 비슷한 업적(누적시간, 스트릭 등)은 '단계(tier)'로 한꺼번에 만들어요.
private func makeAll() -> [Achievement] {
    var list: [Achievement] = []

    // 1) 누적 총 시간
    let cum: [(Int, String, String)] = [
        (1,"첫 한 시간","⏱️"), (3,"세 시간의 벽","🧱"), (5,"다섯 시간","✋"),
        (10,"두 자릿수","🔟"), (20,"스무 시간","💼"), (30,"서른 시간","📈"),
        (50,"반백 시간","🎖️"), (75,"75시간","🏅"), (100,"100시간 클럽","👑"),
        (150,"150시간","🌟"), (200,"200시간","💎"), (300,"300시간","🛡️"),
        (500,"500시간","🏆"), (750,"750시간","🚀"), (1000,"1000시간 마스터","🌌"),
    ]
    for (h, t, e) in cum {
        list.append(Achievement(id: "cum\(h)", title: t, emoji: e,
                                detail: "누적 \(h)시간 집중") { s in
            s.cumulativeSeconds >= Double(h) * 3600
        })
    }

    // 2) 연속 목표 달성(스트릭)
    let strk: [(Int, String, String)] = [
        (2,"이틀 연속","🔥"), (3,"사흘 연속","🔥"), (5,"닷새 연속","🔥"),
        (7,"일주일 연속","🌟"), (10,"열흘 연속","⚡"), (14,"2주 연속","💪"),
        (21,"3주 연속","🏃"), (30,"한 달 연속","📅"), (50,"50일 연속","🎯"),
        (75,"75일 연속","🥇"), (100,"100일 연속","💯"), (150,"150일 연속","🦾"),
        (200,"200일 연속","🛡️"), (365,"1년 연속","🏆"),
    ]
    for (d, t, e) in strk {
        list.append(Achievement(id: "strk\(d)", title: t, emoji: e,
                                detail: "\(d)일 연속 목표 달성") { s in
            s.streak >= d
        })
    }

    // 3) 목표를 달성한 '날'의 수
    let gday: [(Int, String, String)] = [
        (1,"첫 목표 달성","🎯"), (3,"목표 3일","✅"), (5,"목표 5일","✅"),
        (10,"목표 10일","🎯"), (20,"목표 20일","📗"), (30,"목표 30일","📅"),
        (50,"목표 50일","🏅"), (75,"목표 75일","🥈"), (100,"목표 100일","💯"),
        (150,"목표 150일","💎"), (200,"목표 200일","👑"), (300,"목표 300일","🏆"),
        (365,"목표 365일","🌈"),
    ]
    for (n, t, e) in gday {
        list.append(Achievement(id: "gday\(n)", title: t, emoji: e,
                                detail: "목표를 \(n)일 달성") { s in
            s.daysGoalMet >= n
        })
    }

    // 4) 기록한 날의 수
    let trk: [(Int, String, String)] = [
        (1,"첫 기록 날","📝"), (3,"사흘 기록","🗓️"), (7,"일주일 기록","📆"),
        (14,"2주 기록","📋"), (30,"한 달 기록","📚"), (60,"두 달 기록","🗂️"),
        (100,"100일 기록","💯"), (200,"200일 기록","📖"), (365,"1년 기록","🎂"),
    ]
    for (n, t, e) in trk {
        list.append(Achievement(id: "trk\(n)", title: t, emoji: e,
                                detail: "\(n)일 기록을 남김") { s in
            s.daysTracked >= n
        })
    }

    // 5) 기록한 구간(세션) 수
    let ses: [(Int, String, String)] = [
        (1,"첫 걸음","🐣"), (10,"10구간","🌱"), (25,"25구간","🌿"),
        (50,"50구간","🌳"), (100,"100구간","🌲"), (250,"250구간","🏔️"),
        (500,"500구간","🗻"), (1000,"1000구간","🌋"),
    ]
    for (n, t, e) in ses {
        list.append(Achievement(id: "ses\(n)", title: t, emoji: e,
                                detail: "\(n)개 구간 기록") { s in
            s.sessionCount >= n
        })
    }

    // 6) 단일 구간 최장 길이
    let long: [(Int, String, String)] = [
        (1,"1시간 집중","🎯"), (2,"2시간 몰입","🌊"), (3,"3시간 마라톤","🏃"),
        (4,"4시간 딥워크","🧠"), (5,"5시간 무아지경","🌀"), (6,"6시간 철인","🦾"),
        (8,"8시간 전설","🐉"),
    ]
    for (h, t, e) in long {
        list.append(Achievement(id: "long\(h)", title: t, emoji: e,
                                detail: "한 번에 \(h)시간 이상 집중") { s in
            s.longestSession >= Double(h) * 3600
        })
    }

    // 7) 하루 최대 누적 시간
    let dayh: [(Int, String, String)] = [
        (4,"하루 4시간","🌤️"), (6,"하루 6시간","☀️"), (8,"풀타임","💪"),
        (10,"하루 10시간","🔥"), (12,"하루 12시간","😤"),
    ]
    for (h, t, e) in dayh {
        list.append(Achievement(id: "dayh\(h)", title: t, emoji: e,
                                detail: "하루에 \(h)시간 집중") { s in
            s.maxDayTotal >= Double(h) * 3600
        })
    }

    // 8) 하루 최대 구간 수
    let dayn: [(Int, String, String)] = [
        (3,"하루 3구간","🧩"), (5,"하루 5구간","🎰"),
        (8,"하루 8구간","🎲"), (12,"하루 12구간","🃏"),
    ]
    for (n, t, e) in dayn {
        list.append(Achievement(id: "dayn\(n)", title: t, emoji: e,
                                detail: "하루에 \(n)개 구간 기록") { s in
            s.maxSessionsInDay >= n
        })
    }

    // 9) 태그 다양성 (서로 다른 #태그를 몇 종이나 썼나)
    let tagVariety: [(Int, String, String)] = [
        (2,"멀티태스커","🔀"), (3,"태그 3종","🏷️"), (5,"태그 수집가","🗂️"),
        (8,"태그 8종","🎨"), (12,"태그 12종","🌈"), (20,"태그 마스터","🧩"),
    ]
    for (n, t, e) in tagVariety {
        list.append(Achievement(id: "tagv\(n)", title: t, emoji: e,
                                detail: "서로 다른 태그 \(n)종 사용") { s in
            s.distinctTags >= n
        })
    }

    // 10) 한 태그 깊이 (한 #태그에 쏟은 시간)
    let tagDepth: [(Int, String, String)] = [
        (5,"한 우물 5시간","⛏️"), (10,"한 우물 10시간","🪏"), (25,"한 우물 25시간","🛠️"),
        (50,"한 우물 50시간","🏗️"), (100,"한 우물 100시간","🏆"),
    ]
    for (h, t, e) in tagDepth {
        list.append(Achievement(id: "tagd\(h)", title: t, emoji: e,
                                detail: "한 태그에 \(h)시간 집중") { s in
            s.maxTagSeconds >= Double(h) * 3600
        })
    }

    // 10) 시간대
    list.append(Achievement(id: "tod_am7", title: "아침형 인간", emoji: "🌅",
                            detail: "오전 7시 전에 시작") { s in s.startHours.contains { $0 < 7 } })
    list.append(Achievement(id: "tod_am6", title: "새벽반", emoji: "🌄",
                            detail: "오전 6시 전에 시작") { s in s.startHours.contains { $0 < 6 } })
    list.append(Achievement(id: "tod_am5", title: "동트기 전", emoji: "🐓",
                            detail: "오전 5시 전에 시작") { s in s.startHours.contains { $0 < 5 } })
    list.append(Achievement(id: "tod_pm10", title: "올빼미", emoji: "🦉",
                            detail: "밤 10시 이후에 집중") { s in s.startHours.contains { $0 >= 22 } })
    list.append(Achievement(id: "tod_mid", title: "자정의 집중", emoji: "🌙",
                            detail: "자정~새벽 2시에 집중") { s in s.startHours.contains { $0 <= 2 } })
    list.append(Achievement(id: "tod_lunch", title: "점심 집중", emoji: "🍱",
                            detail: "낮 12시에 집중") { s in s.startHours.contains(12) })

    // 11) 요일
    list.append(Achievement(id: "wd_weekend", title: "주말 전사", emoji: "⚔️",
                            detail: "주말에도 기록") { s in s.weekdays.contains(1) || s.weekdays.contains(7) })
    list.append(Achievement(id: "wd_monday", title: "월요일 워리어", emoji: "💼",
                            detail: "월요일에 기록") { s in s.weekdays.contains(2) })
    list.append(Achievement(id: "wd_allweek", title: "7일 개근", emoji: "🗓️",
                            detail: "모든 요일에 한 번씩 기록") { s in s.weekdays.count >= 7 })

    // 12) 메모
    let note: [(Int, String, String)] = [
        (1,"첫 메모","✍️"), (10,"메모왕","📝"), (50,"기록광","📚"), (100,"기록 마스터","🖊️"),
    ]
    for (n, t, e) in note {
        list.append(Achievement(id: "note\(n)", title: t, emoji: e,
                                detail: "메모를 \(n)번 남김") { s in
            s.notesCount >= n
        })
    }

    // 13) 특수/재미
    list.append(Achievement(id: "fun_midnight", title: "자정을 넘어", emoji: "🌃",
                            detail: "한 구간이 자정을 넘김") { s in s.crossedMidnight })

    return list
}
