import SwiftUI
import Combine

// ============================================================
//  TimeTracker = 이 앱의 '두뇌'예요.
//  - 지금 측정 중인지(시작/멈춤) 기억하고
//  - 끝나면 작업 구간(WorkSession)을 목록에 추가하고
//  - 그 목록을 파일에 저장/불러오고
//  - 일/주/월 합계를 계산해줘요.
//
//  @MainActor = "이 클래스의 일은 전부 메인(화면) 스레드에서 한다"는 표시.
//               화면과 직접 연결된 데이터라 안전을 위해 이렇게 둬요.
//  ObservableObject + @Published = "값이 바뀌면 화면을 자동으로 다시 그려라".
// ============================================================
@MainActor
final class TimeTracker: ObservableObject {

    // 앱 전체에서 하나만 쓰는 공용 인스턴스. (메뉴바 화면과 대시보드 창이 같은 데이터를 봐야 해서)
    static let shared = TimeTracker()

    // ── 화면이 지켜보는 상태들 ──────────────────────────────
    @Published private(set) var sessions: [WorkSession] = []   // 저장된 작업 구간들
    @Published private(set) var runningStart: Date? = nil      // 측정 중이면 '시작 시각', 아니면 nil
    @Published var draftNote: String = ""                      // 지금 입력 중인 설명(태그 미포함)
    @Published var draftTags: [String] = []                    // 지금 붙일 태그들
    @Published var draftLocation: LocationStamp? = nil         // 지금 찍은 위치(있으면)
    @Published private(set) var now: Date = Date()             // 1초마다 갱신 → 시간이 '살아 움직임'

    // 알림 방식(시스템 알림 / 앱 안 토스트 중 하나만). 바뀌면 자동 저장.
    @Published var notifyStyle: NotifyStyle = .inApp {
        didSet { UserDefaults.standard.set(notifyStyle.rawValue, forKey: "notifyStyle") }
    }

    // 모든 자동 알림·축하 효과 on/off 마스터 스위치. false면 1시간 토스트·목표
    // 컨페티/불꽃·업적 알림이 전부 조용해져요. **측정(시간 기록)은 그대로 계속**되고,
    // 마일스톤 기록도 내부적으로는 진행돼서, 다시 켜도 밀린 알림이 한꺼번에 안 터져요.
    // (설정 카드의 '미리보기' 버튼은 직접 누르는 거라 꺼도 동작해요.)
    @Published var alertsEnabled: Bool = true {
        didSet { UserDefaults.standard.set(alertsEnabled, forKey: "alertsEnabled") }
    }

    // ── 친구와 공유 (Discord 웹훅) ─────────────────────────
    // 웹훅 URL로 '오늘 N시간' 같은 한 줄을 보내면, 그 채널에 있는 친구들이
    // 푸시로 봐요. 각자 자기 이름을 적어두면 채널에서 누가 누군지 구분돼요.
    @Published var shareWebhookURL: String = "" {
        didSet { UserDefaults.standard.set(shareWebhookURL, forKey: "shareWebhookURL") }
    }
    @Published var shareName: String = "" {            // 채널에 표시될 내 이름
        didSet { UserDefaults.standard.set(shareName, forKey: "shareName") }
    }
    @Published var autoShareOnGoal: Bool = false {     // 하루 목표 달성 시 자동 공유
        didSet { UserDefaults.standard.set(autoShareOnGoal, forKey: "autoShareOnGoal") }
    }

    // ── 집중 확인(졸음 방지) ───────────────────────────────
    // 켜면 측정 중 가끔 화면 테두리에 버튼이 떠요. 30초 안에 안 누르면 실패,
    // 3번 연속 실패하면 '졸기 시작한 첫 실패 시각'으로 측정을 자동 종료해요.
    @Published var focusCheckEnabled: Bool = false {
        didSet { UserDefaults.standard.set(focusCheckEnabled, forKey: "focusCheckEnabled") }
    }
    @Published var focusCheckIntervalMinutes: Int = 15 {   // 확인이 뜨는 주기(분)
        didSet { UserDefaults.standard.set(focusCheckIntervalMinutes, forKey: "focusCheckInterval") }
    }

    // 1초마다 신호를 주는 타이머 (메뉴바 시간을 실시간으로 흐르게 함)
    private var ticker: AnyCancellable?

    // ── 1시간 누적 알림용 ──────────────────────────────────
    // firedMilestone = 오늘 '몇 시간째'까지 이미 축하했는지(중복 방지)
    // milestoneDay   = 그 '오늘'이 며칠인지(자정 지나면 리셋하려고)
    private var firedMilestone = 0
    private var milestoneDay: Date? = nil
    // 새 1시간 고지(1·2·3시간…)에 막 도달하면 이 클로저가 불려요.
    // (모델은 '도달했다'고 알리기만 하고, 귀여운 알림을 띄우는 건 앱이 맡아요)
    var onMilestone: ((Int) -> Void)? = nil

    // ── 하루 목표 / 스트릭 / 업적 ──────────────────────────
    // 하루 목표 시간(설정값). 바뀌면 자동 저장돼요.
    @Published var dailyGoalHours: Int = 6 {
        didSet { UserDefaults.standard.set(dailyGoalHours, forKey: "dailyGoalHours") }
    }
    var goalSeconds: Double { Double(max(1, dailyGoalHours)) * 3600 }

    // 오늘 목표를 이미 축하했는지(하루에 컨페티 한 번만)
    private var goalReachedForDay = false
    var onGoalReached: (() -> Void)? = nil

    // 이번 주 목표 시간(설정값). 바뀌면 자동 저장돼요.
    @Published var weeklyGoalHours: Int = 30 {
        didSet { UserDefaults.standard.set(weeklyGoalHours, forKey: "weeklyGoalHours") }
    }
    var weekGoalSeconds: Double { Double(max(1, weeklyGoalHours)) * 3600 }
    private var weeklyGoalWeek: String? = nil     // 예: "2026-24"
    private var weeklyGoalReached = false
    var onWeeklyGoalReached: (() -> Void)? = nil

    // 이번 달 목표 시간(설정값). 바뀌면 자동 저장돼요.
    @Published var monthlyGoalHours: Int = 80 {
        didSet { UserDefaults.standard.set(monthlyGoalHours, forKey: "monthlyGoalHours") }
    }
    var monthGoalSeconds: Double { Double(max(1, monthlyGoalHours)) * 3600 }

    // 이번 달 목표를 이미 축하했는지(한 달에 한 번)
    private var monthlyGoalMonth: String? = nil   // 예: "2026-6"
    private var monthlyGoalReached = false
    var onMonthlyGoalReached: (() -> Void)? = nil

    // 지금까지 달성한 업적 id 모음(저장됨)
    @Published private(set) var unlocked: Set<String> = []
    var onAchievement: ((Achievement) -> Void)? = nil

    // 측정 중인지 여부 (runningStart가 있으면 측정 중)
    var isRunning: Bool { runningStart != nil }

    private init() {
        // 저장된 설정/업적 먼저 불러오기
        if let g = UserDefaults.standard.object(forKey: "dailyGoalHours") as? Int {
            dailyGoalHours = g
        }
        if let wg = UserDefaults.standard.object(forKey: "weeklyGoalHours") as? Int {
            weeklyGoalHours = wg
        }
        if let mg = UserDefaults.standard.object(forKey: "monthlyGoalHours") as? Int {
            monthlyGoalHours = mg
        }
        if let raw = UserDefaults.standard.string(forKey: "notifyStyle"),
           let style = NotifyStyle(rawValue: raw) {
            notifyStyle = style
        }
        if let on = UserDefaults.standard.object(forKey: "alertsEnabled") as? Bool {
            alertsEnabled = on
        }
        shareWebhookURL = UserDefaults.standard.string(forKey: "shareWebhookURL") ?? ""
        shareName = UserDefaults.standard.string(forKey: "shareName") ?? ""
        autoShareOnGoal = UserDefaults.standard.bool(forKey: "autoShareOnGoal")
        focusCheckEnabled = UserDefaults.standard.bool(forKey: "focusCheckEnabled")
        if let iv = UserDefaults.standard.object(forKey: "focusCheckInterval") as? Int {
            focusCheckIntervalMinutes = iv
        }
        unlocked = Set(UserDefaults.standard.array(forKey: "unlockedAchievements") as? [String] ?? [])

        load()  // 앱 켜질 때 저장돼 있던 기록 불러오기
        loadTrash()
        pruneExpiredTrash()   // 7일 지난 휴지통 항목 정리

        // 시작 시엔 알림 없이 현재 업적 상태만 맞춰둬요(과거 걸 소급해 축하하지 않도록).
        refreshAchievements(notify: false)

        // 매초 now를 현재 시각으로 갱신. 타이머는 메인 런루프에서 울리므로
        // assumeIsolated로 "지금 메인에 있다"고 알려주고 안전하게 값을 바꿔요.
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.now = date
                    self.splitRunningAtMidnightIfNeeded()   // 자정 넘기면 끊고 이어가기
                    self.checkMilestone()   // 매초 '오늘 누적이 1시간 넘었나?' 확인
                }
            }
    }

    // 측정 중에 자정을 넘기면, 자정에서 끊어 '그 날 기록'으로 저장하고
    // 자정부터 새 구간으로 이어서 측정해요. (메모·태그·위치는 그대로 이어감)
    private func splitRunningAtMidnightIfNeeded() {
        guard let begin = runningStart else { return }
        let cal = Calendar.current
        guard !cal.isDate(begin, inSameDayAs: now),
              let boundary = cal.dateInterval(of: .day, for: begin)?.end,
              boundary <= now else { return }

        // 1) 시작~자정 을 그 날의 한 구간으로 저장 (1초 이상일 때만)
        let part = WorkSession(
            start: begin, end: boundary,
            note: draftNote.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: draftTags, location: draftLocation)
        if part.duration >= 1 {
            sessions.append(part)
            clearMergeUndo()
            save()
            refreshAchievements()
        }
        // 2) 자정부터 이어서 계속 측정 (draft는 그대로 둬서 다음 날 기록도 같은 메모/태그)
        runningStart = boundary
    }

    // ── 시작 / 멈춤 ────────────────────────────────────────

    // 측정 시작: 지금 시각을 기록해둬요.
    func start() {
        guard runningStart == nil else { return }
        runningStart = Date()
        FocusCheck.shared.measurementDidStart()   // 졸음 방지 확인 스케줄 시작
    }

    // 측정 멈춤: 시작~(지정 시각 또는 지금)을 한 구간으로 저장하고 초기화해요.
    // endDate를 주면 그 시각으로 끝을 잡아요(화면보호기 자동 종료 때 '자리 비운 순간'으로 되돌리기 위함).
    func stop(at endDate: Date? = nil) {
        guard let begin = runningStart else { return }
        var end = endDate ?? Date()
        if end <= begin { end = Date() }       // 끝이 시작보다 빠르면 안전하게 지금으로
        end = min(end, Date())                 // 미래 시각 방지(과거로 되돌리기만 허용)
        let session = WorkSession(
            start: begin,
            end: end,
            note: draftNote.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: draftTags,
            location: draftLocation
        )
        // 1초도 안 되는 건 실수 클릭으로 보고 버려요.
        if session.duration >= 1 {
            sessions.append(session)
            clearMergeUndo()        // 새 기록이 생기면 직전 합치기 되돌리기는 무효
            save()
            refreshAchievements()
        }
        runningStart = nil
        draftNote = ""
        draftTags = []
        draftLocation = nil
        FocusCheck.shared.measurementDidStop()    // 졸음 방지 확인 예약/창 정리
    }

    // ── 입력 중(draft)인 태그 다루기 ────────────────────────
    func addDraftTagsFromText(_ text: String) {
        for t in WorkSession.parseTagInput(text) where !draftTags.contains(t) { draftTags.append(t) }
    }
    func removeDraftTag(_ tag: String) { draftTags.removeAll { $0 == tag } }
    func toggleDraftTag(_ tag: String) {
        guard let t = WorkSession.normalizeTag(tag) else { return }
        if draftTags.contains(t) { draftTags.removeAll { $0 == t } } else { draftTags.append(t) }
    }

    // ── 위치 찍기 (수동) ────────────────────────────────────
    func captureDraftLocation() {
        LocationManager.shared.requestStamp { stamp in
            // 콜백은 메인 스레드에서 와요 → assumeIsolated로 안전하게 값 반영
            MainActor.assumeIsolated {
                if let stamp { self.draftLocation = stamp }
            }
        }
    }
    func clearDraftLocation() { draftLocation = nil }

    // 시작/멈춤을 한 버튼으로 토글
    func toggle() { isRunning ? stop() : start() }

    // 지금 측정 중인 구간이 몇 초 흘렀는지 (멈춰 있으면 0)
    var currentElapsed: TimeInterval {
        guard let begin = runningStart else { return 0 }
        return now.timeIntervalSince(begin)
    }

    // ── 메뉴바에 보일 글자 ─────────────────────────────────
    // 측정 중이면 🟢 + 흐르는 시간, 멈춰 있으면 ⚪️ + 오늘 누적 시간.
    var menuBarTitle: String {
        if isRunning {
            return "🟢 " + Fmt.clock(currentElapsed)
        } else {
            return "⚪️ " + Fmt.clock(liveTodayTotal)
        }
    }

    // ── 집계(합계) 계산 ────────────────────────────────────

    // 주어진 기간(interval)과 겹치는 모든 세션의 시간을 더해줘요.
    // 한 세션이 기간 경계를 걸치면 '겹친 부분'만 더해요.
    func total(in interval: DateInterval) -> TimeInterval {
        sessions.reduce(0) { sum, s in
            let lo = max(s.start, interval.start)
            let hi = min(s.end, interval.end)
            return sum + max(0, hi.timeIntervalSince(lo))
        }
    }

    // 위 total은 '저장된' 세션만 더해요. 측정 중인(아직 저장 안 된) 구간까지
    // 합쳐서 '지금 이 순간의 진짜 누적'을 주는 버전. 1시간 알림은 이걸로 판단해요.
    func liveTotal(in interval: DateInterval) -> TimeInterval {
        var sum = total(in: interval)
        if let begin = runningStart {                 // 측정 중이면 그 구간도 더함
            let lo = max(begin, interval.start)
            let hi = min(now, interval.end)
            sum += max(0, hi.timeIntervalSince(lo))
        }
        return sum
    }

    // 오늘의 살아있는 누적 (측정 중인 시간까지 포함)
    var liveTodayTotal: TimeInterval { liveTotal(in: dayInterval(of: now)) }

    // 오늘 목표 달성률(0~1)
    var goalProgressToday: Double { min(1, liveTodayTotal / goalSeconds) }

    // 이번 주 기간 / 누적 / 달성률
    func weekInterval(of date: Date) -> DateInterval {
        Calendar.current.dateInterval(of: .weekOfYear, for: date) ?? dayInterval(of: date)
    }
    var liveWeekTotal: TimeInterval { liveTotal(in: weekInterval(of: now)) }
    var weekProgress: Double { min(1, liveWeekTotal / weekGoalSeconds) }

    // "2026-24" 같은 '연-주' 열쇠 (주가 바뀌었는지 비교용)
    private func weekKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(c.yearForWeekOfYear ?? 0)-\(c.weekOfYear ?? 0)"
    }

    // 이번 달 기간 / 누적 / 달성률
    func monthInterval(of date: Date) -> DateInterval {
        Calendar.current.dateInterval(of: .month, for: date) ?? dayInterval(of: date)
    }
    var liveMonthTotal: TimeInterval { liveTotal(in: monthInterval(of: now)) }
    var monthProgress: Double { min(1, liveMonthTotal / monthGoalSeconds) }

    // "2026-6" 같은 '연-월' 열쇠 (달이 바뀌었는지 비교용)
    private func monthKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)"
    }

    // 하루(자정~자정)별 총 시간 표. (히트맵·업적·스트릭 계산에 사용)
    func dailyTotals() -> [Date: TimeInterval] {
        var map: [Date: TimeInterval] = [:]
        let cal = Calendar.current
        for s in sessions {
            let day = cal.startOfDay(for: s.start)
            map[day, default: 0] += s.duration
        }
        return map
    }

    // 특정 하루의 총 시간(오늘이면 측정 중인 것도 포함)
    func dayTotal(_ dayStart: Date) -> TimeInterval {
        let interval = dayInterval(of: dayStart)
        return Calendar.current.isDateInToday(dayStart)
            ? liveTotal(in: interval)
            : total(in: interval)
    }

    // 연속 목표 달성 일수(스트릭). 오늘이 아직 미달이면 끊지 않고 어제부터 세요.
    func currentStreak() -> Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: now)
        if dayTotal(day) < goalSeconds {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        var guardN = 0
        while dayTotal(day) >= goalSeconds, guardN < 2000 {
            streak += 1
            guardN += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    func anyDayMeetsGoal() -> Bool { dailyTotals().values.contains { $0 >= goalSeconds } }
    func anyDayTotalAtLeast(_ secs: TimeInterval) -> Bool { dailyTotals().values.contains { $0 >= secs } }

    // 시작 시각이 기간 안에 드는 세션들 (목록 표시용), 최근 순으로.
    func sessions(in interval: DateInterval) -> [WorkSession] {
        sessions
            .filter { interval.contains($0.start) }
            .sorted { $0.start > $1.start }
    }

    // 오늘 하루 기간
    func dayInterval(of date: Date) -> DateInterval {
        Calendar.current.dateInterval(of: .day, for: date)
            ?? DateInterval(start: date, duration: 0)
    }

    // ── 1시간 누적 알림 판단 (매초 호출됨) ──────────────────
    // 오늘 누적이 1·2·3…시간을 '막 넘는' 순간에만 onMilestone을 한 번 불러요.
    private func checkMilestone() {
        let today = dayInterval(of: now)
        let live = liveTotal(in: today)

        // 날짜가 바뀌었거나(자정) 앱을 막 켰으면: 기준만 잡고 알림은 울리지 않아요.
        // (예: 켰을 때 이미 2시간 쌓여 있으면, 과거 걸 소급해 울리지 않도록)
        if milestoneDay != today.start {
            milestoneDay = today.start
            firedMilestone = Int(live / 3600)
            goalReachedForDay = live >= goalSeconds   // 시작/자정 시점 이미 달성한 건 소급 축하 X
            pruneExpiredTrash()                       // 자정마다 휴지통 정리
            return
        }

        // 1) 1시간 누적 고지
        let reached = Int(live / 3600)
        if reached > firedMilestone {
            firedMilestone = reached
            onMilestone?(reached)
        }

        // 2) 하루 목표 달성(하루에 한 번 컨페티)
        if !goalReachedForDay && live >= goalSeconds {
            goalReachedForDay = true
            onGoalReached?()
            refreshAchievements()
        }

        // 3) 이번 주 목표 달성(한 주에 한 번 컨페티)
        let wKey = weekKey(now)
        let weekLive = liveTotal(in: weekInterval(of: now))
        if weeklyGoalWeek != wKey {
            weeklyGoalWeek = wKey
            weeklyGoalReached = weekLive >= weekGoalSeconds
        } else if !weeklyGoalReached && weekLive >= weekGoalSeconds {
            weeklyGoalReached = true
            onWeeklyGoalReached?()
        }

        // 4) 이번 달 목표 달성(한 달에 한 번 컨페티)
        let mKey = monthKey(now)
        let monthLive = liveTotal(in: monthInterval(of: now))
        if monthlyGoalMonth != mKey {
            monthlyGoalMonth = mKey
            monthlyGoalReached = monthLive >= monthGoalSeconds   // 시작/월초 시점 이미 달성한 건 소급 X
        } else if !monthlyGoalReached && monthLive >= monthGoalSeconds {
            monthlyGoalReached = true
            onMonthlyGoalReached?()
        }
    }

    // 업적 판단에 쓸 '요약 숫자들'을 한 번에 계산해요.
    func makeStats() -> TrackerStats {
        let cal = Calendar.current
        var s = TrackerStats()
        s.sessionCount = sessions.count

        var dayTotals: [Date: Double] = [:]      // 날짜 -> 그날 총 초
        var daySessions: [Date: Int] = [:]       // 날짜 -> 그날 구간 수

        var allTags = Set<String>()
        for sess in sessions {
            let dur = sess.duration
            s.cumulativeSeconds += dur
            s.longestSession = max(s.longestSession, dur)
            for tag in sess.tags {                 // 한 구간이 여러 태그면 각 태그에 시간을 더해요
                s.tagSeconds[tag, default: 0] += dur
                allTags.insert(tag)
            }
            if !sess.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { s.notesCount += 1 }
            s.startHours.insert(cal.component(.hour, from: sess.start))
            s.weekdays.insert(cal.component(.weekday, from: sess.start))
            if !cal.isDate(sess.start, inSameDayAs: sess.end) { s.crossedMidnight = true }
            let day = cal.startOfDay(for: sess.start)
            dayTotals[day, default: 0] += dur
            daySessions[day, default: 0] += 1
        }

        // 오늘은 측정 중인 시간까지 반영(목표 달성을 그 순간 인정하려고)
        let today = cal.startOfDay(for: now)
        dayTotals[today] = max(dayTotals[today] ?? 0, liveTodayTotal)

        s.daysTracked = dayTotals.count
        s.daysGoalMet = dayTotals.values.filter { $0 >= goalSeconds }.count
        s.maxDayTotal = dayTotals.values.max() ?? 0
        s.maxSessionsInDay = daySessions.values.max() ?? 0
        s.distinctTags = allTags.count
        s.maxTagSeconds = s.tagSeconds.values.max() ?? 0
        s.streak = currentStreak()
        return s
    }

    // ── 태그 모아보기(태그 검색 페이지에서 사용) ───────────
    // 모든 태그를 (태그, 총 시간, 횟수)로, 시간 많은 순으로 정리해요.
    func tagSummaries() -> [TagSummary] {
        var secs: [String: TimeInterval] = [:]
        var cnt: [String: Int] = [:]
        for sess in sessions {
            for tag in sess.tags {
                secs[tag, default: 0] += sess.duration
                cnt[tag, default: 0] += 1
            }
        }
        return secs.keys
            .map { TagSummary(tag: $0, seconds: secs[$0] ?? 0, count: cnt[$0] ?? 0) }
            .sorted { $0.seconds > $1.seconds }
    }

    // 특정 태그가 들어간 구간들(최근 순)
    func sessions(withTag tag: String) -> [WorkSession] {
        let t = tag.lowercased()
        return sessions.filter { $0.tags.contains(t) }.sorted { $0.start > $1.start }
    }

    // 최근 쓴 태그(가장 최근에 사용한 순) 상위 몇 개 — 메뉴바 단축칩용
    func recentTags(limit: Int = 8) -> [String] {
        var latest: [String: Date] = [:]   // 태그 -> 마지막으로 쓴 시각
        for sess in sessions {
            for tag in sess.tags {
                if let prev = latest[tag] {
                    if sess.start > prev { latest[tag] = sess.start }
                } else {
                    latest[tag] = sess.start
                }
            }
        }
        return latest.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
    }

    // 현재 업적 달성 상태를 다시 계산하고, '새로' 달성한 게 있으면 알려줘요.
    func refreshAchievements(notify: Bool = true) {
        let stats = makeStats()
        let nowSet = Set(Achievement.all.filter { $0.check(stats) }.map(\.id))
        let newly = nowSet.subtracting(unlocked)
        unlocked = nowSet
        UserDefaults.standard.set(Array(nowSet), forKey: "unlockedAchievements")
        if notify {
            // 정의된 순서대로 토스트 (한 번에 여러 개면 마지막 게 보여요)
            for a in Achievement.all where newly.contains(a.id) { onAchievement?(a) }
        }
    }

    // ── 세션 편집/삭제 (대시보드에서 사용) ──────────────────

    // 오늘 시작한 기록만 수정할 수 있어요. 지난 날의 기록은 '박제'(읽기 전용).
    // → 정말로 남기는 기록이라는 느낌, 그리고 '오늘'에 집중하게 하려는 규칙이에요.
    func isEditable(_ session: WorkSession) -> Bool {
        Calendar.current.isDate(session.start, inSameDayAs: now)
    }

    func updateNote(_ id: UUID, note: String) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        guard isEditable(sessions[i]) else { return }   // 설명은 지난 날엔 수정 불가
        sessions[i].note = note
        save()
    }

    // 태그는 '메타데이터'라 지난 날 기록이라도 나중에 붙이거나 뗄 수 있어요.
    // (시간·설명 같은 진짜 기록은 그대로 박제, 분류용 태그만 자유롭게)
    func addTag(_ id: UUID, _ rawTag: String) {
        guard let t = WorkSession.normalizeTag(rawTag),
              let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        guard !sessions[i].tags.contains(t) else { return }
        sessions[i].tags.append(t)
        save()
        refreshAchievements()
    }

    func removeTag(_ id: UUID, _ tag: String) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].tags.removeAll { $0 == tag }
        save()
        refreshAchievements()
    }

    // 위치도 메타데이터라 지난 기록에 나중에 붙이거나 뗄 수 있어요.
    func captureLocation(for id: UUID) {
        LocationManager.shared.requestStamp { stamp in
            MainActor.assumeIsolated {
                guard let stamp, let i = self.sessions.firstIndex(where: { $0.id == id }) else { return }
                self.sessions[i].location = stamp
                self.save()
            }
        }
    }

    func clearLocation(for id: UUID) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].location = nil
        save()
    }

    func delete(_ id: UUID) {
        guard let s = sessions.first(where: { $0.id == id }) else { return }
        guard isEditable(s) else { return }   // 지난 날의 기록은 지울 수 없어요(오늘 것만)
        // 바로 지우지 않고 휴지통으로 — 7일간 복구 가능.
        trash.insert(TrashedSession(session: s, deletedAt: Date()), at: 0)
        saveTrash()
        sessions.removeAll { $0.id == id }
        clearMergeUndo()
        save()
        refreshAchievements()
    }

    // ── 휴지통 (삭제 후 7일간 복구) ─────────────────────────
    @Published private(set) var trash: [TrashedSession] = []
    static let trashRetention: TimeInterval = 7 * 24 * 3600   // 7일

    // 복구: 휴지통에서 빼서 기록으로 되돌려요.
    func restore(_ id: UUID) {
        guard let i = trash.firstIndex(where: { $0.id == id }) else { return }
        let s = trash.remove(at: i).session
        if !sessions.contains(where: { $0.id == s.id }) { sessions.append(s) }
        saveTrash(); save(); refreshAchievements()
    }

    // 영구 삭제: 휴지통에서 완전히 지워요(복구 불가).
    func purgeTrash(_ id: UUID) {
        trash.removeAll { $0.id == id }
        saveTrash()
    }

    func emptyTrash() {
        trash.removeAll()
        saveTrash()
    }

    // 보관 기간(7일) 지난 항목 자동 영구삭제.
    func pruneExpiredTrash() {
        let cutoff = now.addingTimeInterval(-Self.trashRetention)
        let before = trash.count
        trash.removeAll { $0.deletedAt < cutoff }
        if trash.count != before { saveTrash() }
    }

    // ── 구간 합치기 + 되돌리기 ─────────────────────────────
    // 직전 합치기를 되돌릴 수 있게, 합치기 전 원본 두 개를 잠깐 기억해둬요.
    private var lastMergeOriginals: [WorkSession]? = nil
    private var lastMergeResultID: UUID? = nil
    @Published private(set) var canUndoMerge = false   // 화면의 '되돌리기' 버튼 표시용

    // '연속된 구간'으로 볼 사이 간격 한계(초). 이만큼 안쪽으로 붙어 있어야 합칠 수 있어요.
    // (멈춤→시작 사이의 클릭 텀 정도만 허용. 진짜 쉬는 시간은 합쳐지지 않게)
    static let mergeGapTolerance: TimeInterval = 120

    // 두 구간이 시간상 '연속'인가? (사이 간격이 아주 짧거나 겹치면 연속)
    func areConsecutive(_ a: WorkSession, _ b: WorkSession) -> Bool {
        let earlier = a.start <= b.start ? a : b
        let later   = a.start <= b.start ? b : a
        let gap = later.start.timeIntervalSince(earlier.end)
        return gap <= Self.mergeGapTolerance
    }

    // 이웃한 두 구간을 하나로 합쳐요.
    //  - 합친 구간의 시간 = 더 이른 시작 ~ 더 늦은 끝
    //  - 메모(=태그 포함) = 두 메모를 시간순으로 이어붙임(빈 메모는 건너뜀)
    func merge(_ idA: UUID, with idB: UUID) {
        guard let a = sessions.first(where: { $0.id == idA }),
              let b = sessions.first(where: { $0.id == idB }) else { return }
        guard isEditable(a), isEditable(b) else { return }   // 오늘 것끼리만 합칠 수 있어요
        guard areConsecutive(a, b) else { return }           // 연속된 구간끼리만

        let earlier = a.start <= b.start ? a : b
        let later   = a.start <= b.start ? b : a

        let notes = [earlier.note, later.note].filter { !$0.isEmpty }
        var merged = WorkSession(
            start: min(a.start, b.start),
            end:   max(a.end, b.end),
            note:  notes.joined(separator: " / ")
        )
        merged.id = earlier.id   // 더 이른 구간의 id를 이어받아요

        // 되돌리기용으로 원본을 기억
        lastMergeOriginals = [a, b]
        lastMergeResultID = merged.id
        canUndoMerge = true

        sessions.removeAll { $0.id == idA || $0.id == idB }
        sessions.append(merged)
        save()
        refreshAchievements()
    }

    // 방금 한 합치기를 되돌려요(합친 것 지우고 원본 둘을 복원).
    func undoMerge() {
        guard let originals = lastMergeOriginals, let resultID = lastMergeResultID else { return }
        // 자정을 넘겨 어제 기록이 됐으면 되돌리기도 막아요.
        if let result = sessions.first(where: { $0.id == resultID }), !isEditable(result) {
            clearMergeUndo(); return
        }
        sessions.removeAll { $0.id == resultID }
        sessions.append(contentsOf: originals)
        clearMergeUndo()
        save()
        refreshAchievements()
    }

    private func clearMergeUndo() {
        lastMergeOriginals = nil
        lastMergeResultID = nil
        canUndoMerge = false
    }

    // ── 파일 저장/불러오기 ─────────────────────────────────
    // ~/Library/Application Support/FocusTimer/sessions.json 에 보관해요.

    private var supportDir: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusTimer", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    private var fileURL: URL { supportDir.appendingPathComponent("sessions.json") }
    private var trashFileURL: URL { supportDir.appendingPathComponent("trash.json") }

    private func save() {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("저장 실패:", error)
        }
    }

    private func saveTrash() {
        do {
            let data = try JSONEncoder().encode(trash)
            try data.write(to: trashFileURL, options: .atomic)
        } catch {
            print("휴지통 저장 실패:", error)
        }
    }

    private func loadTrash() {
        guard let data = try? Data(contentsOf: trashFileURL),
              let decoded = try? JSONDecoder().decode([TrashedSession].self, from: data)
        else { return }
        trash = decoded
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([WorkSession].self, from: data)
        else { return }

        // 구버전 데이터를 새 구조(태그 분리)로 옮겨요.
        //  - 아주 옛날: categoryID("dev"…) → 태그
        //  - 직전 버전: 설명(note) 안의 #태그 → tags 배열로 옮기고 설명에서 제거
        let legacyNames = ["dev": "개발", "study": "공부", "meeting": "회의",
                           "writing": "글쓰기", "etc": "기타"]
        var changed = false
        sessions = decoded.map { s in
            var fixed = s
            if let cid = s.categoryID, !cid.isEmpty {
                let name = (legacyNames[cid] ?? cid).lowercased()
                if !fixed.tags.contains(name) { fixed.tags.append(name) }
                fixed.categoryID = nil
                changed = true
            }
            let inNote = WorkSession.extractTags(from: s.note)
            if !inNote.isEmpty {
                for t in inNote where !fixed.tags.contains(t) { fixed.tags.append(t) }
                fixed.note = WorkSession.stripHashtags(from: s.note)
                changed = true
            }
            return fixed
        }
        if changed { save() }
    }
}
