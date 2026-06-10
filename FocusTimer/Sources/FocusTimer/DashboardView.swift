import SwiftUI
import Charts
import MapKit
import CoreLocation
import Combine

// ============================================================
//  DashboardView = 큰 창에 뜨는 '기록 모아보기' 화면.
//  - 위: 일 / 주 / 월 전환 + 날짜 앞뒤 이동
//  - 요약 카드 3개 (총 시간 / 세션 수 / 가장 많이 한 일)
//  - 가운데: 막대 차트 (시간대/요일/날짜별로, 카테고리 색으로 쌓아서)
//  - 아래: 그 기간의 세션 목록 (메모 고치고, 카테고리 바꾸고, 지우기)
// ============================================================



struct DashboardView: View {
    @EnvironmentObject var tracker: TimeTracker

    enum Page: String, CaseIterable, Identifiable {
        case dashboard = "대시보드", tags = "태그", map = "지도",
             achievements = "업적", trash = "휴지통", settings = "설정"
        var id: String { rawValue }
    }

    @State private var page: Page = .dashboard  // 상단 탭 선택
    @State private var mapFocused = false        // 대시보드 지도 카드: 조작(줌/이동) 허용 여부
    @State private var mapCamera: MapCameraPosition = .automatic   // 날짜 바뀌면 그 날 위치로 재조정
    @State private var anchor: Date = Date()    // 지금 보고 있는 날짜
    @State private var showAchievements = true  // 업적 페이지 펼침/접힘(페이지라 기본 펼침)
    @State private var showDatePicker = false   // 달력 점프 팝오버 표시 여부

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            pageSwitcher
            Divider().opacity(0.3)
            switch page {
            case .dashboard:    dashboardContent
            case .tags:         TagSearchView()
            case .map:          MapPageView()
            case .achievements: achievementsPage
            case .trash:        trashPage
            case .settings:     settingsPage
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(backgroundGradient)
        // 대시보드 창을 열 때마다 '오늘 + 대시보드 탭'으로 리셋 (이전에 다른 날로 옮겨놨어도).
        .onReceive(NotificationCenter.default.publisher(for: .dashboardDidOpen)) { _ in
            anchor = Date()
            page = .dashboard
        }
    }

    // 맨 위: 대시보드 / 태그 페이지 전환
    private var pageSwitcher: some View {
        HStack {
            Picker("", selection: $page) {
                ForEach(Page.allCases) { p in Text(p.rawValue).tag(p) }
            }
            .pickerStyle(.segmented)
            .frame(width: 540)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var dashboardContent: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(spacing: 18) {
                    goalCard
                    clockCard
                    mapCard
                    summaryCards
                    heatmapCard
                    sessionListCard
                }
                .padding(20)
            }
        }
    }

    // ── 업적 탭 (전체 기간 기준, 날짜 내비 없음) ──
    private var achievementsPage: some View {
        ScrollView {
            VStack(spacing: 18) { achievementsCard }
                .padding(20)
        }
    }

    // ── 휴지통 탭 (비어 있으면 안내) ──
    private var trashPage: some View {
        ScrollView {
            VStack(spacing: 18) {
                if tracker.trash.isEmpty {
                    Card {
                        VStack(spacing: 8) {
                            Image(systemName: "trash")
                                .font(.largeTitle).foregroundStyle(.secondary)
                            Text("휴지통이 비어 있어요").font(.headline)
                            Text("삭제한 기록은 7일 동안 여기 보관되고, 그 안에 복구할 수 있어요.")
                                .font(.caption).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                } else {
                    trashCard
                }
            }
            .padding(20)
        }
    }

    // ── 설정 탭 (알림·축하 효과 등 전역 설정) ──
    private var settingsPage: some View {
        ScrollView {
            VStack(spacing: 18) { settingsCard }
                .padding(20)
        }
    }

    // 부드러운 배경 그라데이션 (fancy)
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(nsColor: .windowBackgroundColor),
                     Color(nsColor: .windowBackgroundColor).opacity(0.85)],
            startPoint: .top, endPoint: .bottom
        ).ignoresSafeArea()
    }

    // ── 지금 보고 있는 하루 ────────────────────────────────
    private var interval: DateInterval { tracker.dayInterval(of: anchor) }
    private var isToday: Bool { cal.isDateInToday(anchor) }
    private var dayWord: String { isToday ? "오늘" : Fmt.shortDate(anchor) }

    // 보고 있는 날/주/달의 합계·진행률 (liveTotal은 '오늘이 포함된 기간'이면 측정 중인 것도 자동 포함)
    private var dayTotal: TimeInterval { tracker.liveTotal(in: interval) }
    private var dayProgress: Double { min(1, dayTotal / tracker.goalSeconds) }

    private var weekIntervalA: DateInterval { tracker.weekInterval(of: anchor) }
    private var monthIntervalA: DateInterval { tracker.monthInterval(of: anchor) }
    private var weekTotalA: TimeInterval { tracker.liveTotal(in: weekIntervalA) }
    private var monthTotalA: TimeInterval { tracker.liveTotal(in: monthIntervalA) }
    private var weekProgressA: Double { min(1, weekTotalA / tracker.weekGoalSeconds) }
    private var monthProgressA: Double { min(1, monthTotalA / tracker.monthGoalSeconds) }
    private var isCurrentWeek: Bool { weekIntervalA.contains(tracker.now) }
    private var isCurrentMonth: Bool { monthIntervalA.contains(tracker.now) }

    // ====================================================
    //  맨 위 막대: 제목 + 날짜 이동(하루 단위) + 날짜 라벨
    // ====================================================
    private var topBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                Text("작업 기록")
                    .font(.title2).fontWeight(.bold)
                Spacer()
                // 날짜 앞뒤 이동 (하루 단위) + 달력으로 원하는 날짜 점프
                HStack(spacing: 4) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Button("오늘") { anchor = Date() }.font(.caption)
                    // 달력 아이콘 → 그래프형 달력으로 아무 날짜나 한 번에 점프
                    Button { showDatePicker = true } label: { Image(systemName: "calendar") }
                        .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                            VStack(spacing: 10) {
                                DatePicker("", selection: $anchor, displayedComponents: .date)
                                    .datePickerStyle(.graphical)
                                    .labelsHidden()
                                    .environment(\.locale, Locale(identifier: "ko_KR"))
                                    .frame(width: 300)
                                Button("오늘로 이동") { anchor = Date(); showDatePicker = false }
                                    .buttonStyle(.borderedProminent)
                            }
                            .padding(14)
                        }
                        // 날짜를 고르면(=anchor 변경) 팝오버는 자동으로 닫혀요.
                        .onChange(of: anchor) { _, _ in showDatePicker = false }
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.bordered)
            }
            // 보고 있는 날짜
            Text(rangeLabel)
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 14)          // 날짜 밑 여백
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    // 앞/뒤 날짜로 이동 (하루씩)
    private func shift(_ direction: Int) {
        if let moved = cal.date(byAdding: .day, value: direction, to: anchor) {
            anchor = moved
        }
    }

    // 보고 있는 날짜 라벨
    private var rangeLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월 d일 (E)"
        return f.string(from: interval.start)
    }

    // ====================================================
    //  요약 카드 3개
    // ====================================================
    private var summaryCards: some View {
        let totalSec = dayTotal   // 보고 있는 날의 합계(오늘이면 측정 중인 것도 포함)
        let list = tracker.sessions(in: interval)
        let topTag = topTag(in: list)
        return HStack(spacing: 14) {
            SummaryCard(title: "총 작업 시간",
                        value: Fmt.human(totalSec),
                        icon: "clock.fill",
                        tint: Color(red: 0.30, green: 0.55, blue: 0.98))
            SummaryCard(title: "기록한 구간",
                        value: "\(list.count)개",
                        icon: "square.stack.3d.up.fill",
                        tint: Color(red: 0.61, green: 0.40, blue: 0.94))
            SummaryCard(title: "가장 많이 한 태그",
                        value: topTag.map { "#\($0)" } ?? "–",
                        icon: "number",
                        tint: topTag.map { TagStyle.color(forTag: $0) } ?? .gray)
        }
    }

    // 기간 안에서 가장 시간을 많이 쓴 태그
    private func topTag(in list: [WorkSession]) -> String? {
        var sums: [String: TimeInterval] = [:]
        for s in list {
            for tag in s.tags { sums[tag, default: 0] += s.duration }
        }
        return sums.max(by: { $0.value < $1.value })?.key
    }

    // ====================================================
    //  세션 목록 카드
    // ====================================================
    private var sessionListCard: some View {
        let list = tracker.sessions(in: interval)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("구간별 기록").font(.headline)
                    Spacer()
                    // 방금 합친 게 있으면 '되돌리기' 버튼이 나타나요.
                    if tracker.canUndoMerge {
                        Button {
                            tracker.undoMerge()
                        } label: {
                            Label("합치기 되돌리기", systemImage: "arrow.uturn.backward")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if list.isEmpty {
                    Text("아직 이 기간에 저장된 기록이 없어요.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    // 목록은 최신순. 인접한 두 줄 '사이'에 합치기 버튼을 둬요.
                    // 단, 둘 다 '오늘' 기록이고 시간상 '연속'일 때만 (사이에 쉬는 시간이 있으면 못 합쳐요).
                    ForEach(Array(list.enumerated()), id: \.element.id) { idx, session in
                        SessionRow(session: session)
                        if idx < list.count - 1,
                           tracker.isEditable(session),
                           tracker.isEditable(list[idx + 1]),
                           tracker.areConsecutive(session, list[idx + 1]) {
                            MergeDivider {
                                tracker.merge(session.id, with: list[idx + 1].id)
                            }
                        } else if idx < list.count - 1 {
                            Divider().opacity(0.4)   // 합치기 불가 구간은 그냥 구분선
                        }
                    }
                }
            }
        }
    }

    // ====================================================
    //  목표 링 카드 (오늘 목표 진행률 + 스트릭 + 목표 조절)
    // ====================================================
    private var goalCard: some View {
        let streak = tracker.currentStreak()
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                // 윗부분: 그 날 목표(원형 링)
                HStack(spacing: 22) {
                    ZStack {
                        Circle().stroke(.quaternary, lineWidth: 12)
                        Circle()
                            .trim(from: 0, to: dayProgress)
                            .stroke(goalGradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 3) {
                            Text("\(Int(dayProgress * 100))%")
                                .font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                            Text(Fmt.human(dayTotal))
                                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .frame(width: 108, height: 108)
                    .animation(.easeOut(duration: 0.4), value: dayProgress)

                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 8) {
                            Text("\(dayWord) 목표").font(.headline)
                            if isToday, streak > 0 {
                                Text("🔥 \(streak)일 연속")
                                    .font(.subheadline).fontWeight(.bold).foregroundStyle(.orange)
                            }
                        }

                        Stepper(value: $tracker.dailyGoalHours, in: 1...16) {
                            Text("하루 \(tracker.dailyGoalHours)시간")
                                .font(.callout).monospacedDigit()
                        }
                        .frame(width: 190)

                        Text(dayProgress >= 1
                             ? "\(dayWord) 목표를 달성했어요! 🎉"
                             : "목표까지 \(Fmt.human(max(0, tracker.goalSeconds - dayTotal))) 남았어요")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider().opacity(0.5)

                // 아랫부분: (보고 있는 날이 속한) 주간 / 월간 목표
                periodGoalBar(title: isCurrentWeek ? "이번 주 목표" : "그 주 목표", total: weekTotalA,
                              goalHours: $tracker.weeklyGoalHours, progress: weekProgressA,
                              range: 5...200, step: 5, unit: "주", reached: "주 목표 달성! 🎖️")
                periodGoalBar(title: isCurrentMonth ? "이번 달 목표" : "그 달 목표", total: monthTotalA,
                              goalHours: $tracker.monthlyGoalHours, progress: monthProgressA,
                              range: 10...500, step: 5, unit: "월", reached: "달 목표 달성! 🏆")
            }
        }
    }

    // 기간(주/월) 목표 진행 바 + 조절 — 같은 모양을 둘 다에 재사용해요.
    private func periodGoalBar(title: String, total: TimeInterval, goalHours: Binding<Int>,
                               progress: Double, range: ClosedRange<Int>, step: Int,
                               unit: String, reached: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Stepper(value: goalHours, in: range, step: step) {
                    Text("\(unit) \(goalHours.wrappedValue)시간").font(.callout).monospacedDigit()
                }
                .frame(width: 180)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary.opacity(0.6))
                    Capsule().fill(goalGradient)
                        .frame(width: max(6, geo.size.width * progress))
                }
            }
            .frame(height: 12)
            HStack {
                Text("\(Fmt.human(total)) / \(goalHours.wrappedValue)시간")
                    .font(.caption).fontWeight(.semibold).monospacedDigit()
                Spacer()
                Text(progress >= 1 ? reached : "\(Int(progress * 100))%")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private var goalGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 0.30, green: 0.55, blue: 0.98),
                                Color(red: 0.61, green: 0.40, blue: 0.94)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // ====================================================
    //  그 날의 24시간 시계 (하루를 한 바퀴로, 일한 시간대를 색칠)
    // ====================================================
    private var clockCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(dayWord)의 24시간").font(.headline)
                Text("자정(0시)이 맨 위, 시계방향으로 하루가 흘러요")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    DayClockView(segments: dayClockSegments(),
                                 centerText: Fmt.human(dayTotal),
                                 centerSub: dayWord)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }

    // 보고 있는 날의 기록(+오늘이면 측정 중)을 시계의 호 조각으로 변환 (0~1 = 0~24시)
    private func dayClockSegments() -> [ClockSeg] {
        let day = interval                 // 보고 있는 날
        let dayStart = day.start
        let span: Double = 24 * 3600
        var segs: [ClockSeg] = []

        func add(_ start: Date, _ end: Date, _ color: Color) {
            let lo = max(start, day.start), hi = min(end, day.end)
            guard hi > lo else { return }
            segs.append(ClockSeg(start: lo.timeIntervalSince(dayStart) / span,
                                 end: hi.timeIntervalSince(dayStart) / span,
                                 color: color))
        }

        for s in tracker.sessions {
            add(s.start, s.end, s.primaryTag.map { TagStyle.color(forTag: $0) } ?? Color.gray.opacity(0.55))
        }
        if let begin = tracker.runningStart {   // 측정 중인 구간 (오늘 볼 때만 이 날과 겹쳐요)
            let c = tracker.draftTags.first.map { TagStyle.color(forTag: $0) } ?? Color.green
            add(begin, tracker.now, c)
        }
        return segs
    }

    // ====================================================
    //  그 날 공부한 곳 (지도)
    // ====================================================
    private var mapCard: some View {
        let spots = daySpots()
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(dayWord) 공부한 곳").font(.headline)
                if spots.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 30)).foregroundStyle(.tertiary)
                        Text("\(dayWord) 위치를 찍은 기록이 없어요")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("메뉴바에서 ‘현재 위치 찍기’로 남길 수 있어요")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity).frame(height: 180)
                } else {
                    // 평소엔 고정(스크롤·줌 안 됨), '지도 조작'을 켜야 줌/이동 가능.
                    Map(position: $mapCamera, interactionModes: mapFocused ? .all : []) {
                        ForEach(spots) { spot in
                            Annotation(spot.title, coordinate: spot.coord) {
                                ZStack {
                                    Circle().fill(spot.color).frame(width: 22, height: 22)
                                        .overlay(Circle().stroke(.white, lineWidth: 2))
                                        .shadow(radius: 2)
                                    Image(systemName: "mappin")
                                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                }
                            }
                        }
                    }
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    // '지도 조작'을 켜지 않은 동안엔 지도가 스크롤을 가로채지 않게 해서,
                    // 지도 위에서도 대시보드가 그대로 스크롤되게 해요.
                    // (조작 토글은 overlay라 위에 떠서 항상 눌려요.)
                    .allowsHitTesting(mapFocused)
                    .overlay(alignment: .topTrailing) { MapFocusToggle(focused: $mapFocused) }
                    // 날짜를 넘기면 그 날 위치들로 지도를 다시 맞춰요.
                    .onChange(of: anchor) { _, _ in mapCamera = .automatic }
                }
            }
        }
    }

    private func daySpots() -> [DaySpot] {
        tracker.sessions(in: interval).compactMap { s in   // 보고 있는 날
            guard let loc = s.location else { return nil }
            return DaySpot(
                id: s.id,
                coord: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude),
                color: s.primaryTag.map { TagStyle.color(forTag: $0) } ?? .gray,
                title: Fmt.shortDate(s.start))   // 핀 라벨 = 날짜
        }
    }

    // ====================================================
    //  휴지통 (삭제 후 7일간 복구)
    // ====================================================
    @ViewBuilder
    private var trashCard: some View {
        if !tracker.trash.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("휴지통", systemImage: "trash").font(.headline)
                        Text("\(tracker.trash.count)개 · 7일 보관")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("전체 비우기") { tracker.emptyTrash() }
                            .font(.caption).buttonStyle(.borderless)
                    }
                    ForEach(tracker.trash) { item in
                        trashRow(item)
                        if item.id != tracker.trash.last?.id { Divider().opacity(0.3) }
                    }
                }
            }
        }
    }

    private func trashRow(_ item: TrashedSession) -> some View {
        let s = item.session
        let remain = max(0, TimeTracker.trashRetention - tracker.now.timeIntervalSince(item.deletedAt))
        let days = max(1, Int(ceil(remain / 86400)))
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Fmt.shortDate(s.start)) · \(Fmt.hm(s.start))–\(Fmt.hm(s.end))")
                    .font(.callout).monospacedDigit()
                if !s.note.isEmpty {
                    Text(s.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text("\(days)일 후 삭제").font(.caption2).foregroundStyle(.tertiary)
            Button { tracker.restore(s.id) } label: {
                Label("복구", systemImage: "arrow.uturn.backward").font(.caption)
            }
            .controlSize(.small)
            Button(role: .destructive) { tracker.purgeTrash(s.id) } label: {
                Image(systemName: "trash")
            }
            .controlSize(.small)
        }
        .buttonStyle(.bordered)
        .padding(.vertical, 3)
    }

    // ====================================================
    //  설정 (알림 방식)
    // ====================================================
    private var settingsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("설정").font(.headline)

                // ── 모든 알림·축하 효과 마스터 스위치 (끄면 측정은 계속, 알림만 조용) ──
                Toggle(isOn: $tracker.alertsEnabled) {
                    Label("알림·축하 효과",
                          systemImage: tracker.alertsEnabled ? "bell.fill" : "bell.slash.fill")
                        .font(.callout)
                }
                .toggleStyle(.switch)
                Text(tracker.alertsEnabled
                     ? "1시간 알림·목표 축하 효과·업적 알림을 모두 보여줘요."
                     : "모든 알림·축하 효과가 꺼져 있어요 — 시간 측정(⏱️)은 그대로 계속돼요.")
                    .font(.caption2).foregroundStyle(.secondary)

                Divider().padding(.vertical, 2)

                // ── 알림 방식 (알림이 켜져 있을 때만 의미 있어요) ──
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("알림 방식", systemImage: "bell.badge").font(.callout)
                        Spacer()
                        Picker("", selection: $tracker.notifyStyle) {
                            ForEach(NotifyStyle.allCases) { s in Text(s.rawValue).tag(s) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                    Text("축하·1시간 알림을 ‘시스템 알림센터’ 또는 ‘앱 안 팝업’ 중 하나로만 보여줘요.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .disabled(!tracker.alertsEnabled)
                .opacity(tracker.alertsEnabled ? 1 : 0.4)

                Divider().padding(.vertical, 2)

                HStack {
                    Label("축하 효과 미리보기", systemImage: "sparkles").font(.callout)
                    Spacer()
                    Button("하루") { Celebration.preview(tier: 1) }
                    Button("주간") { Celebration.preview(tier: 2) }
                    Button("월간") { Celebration.preview(tier: 3) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Text("목표를 달성하지 않아도 단계별 축하 효과를 바로 볼 수 있어요 — 하루 < 주간 < 월간 순으로 점점 화려해져요.")
                    .font(.caption2).foregroundStyle(.secondary)

                Divider().padding(.vertical, 2)

                // ── 친구와 공유 (Discord 웹훅) ──
                VStack(alignment: .leading, spacing: 8) {
                    Label("친구와 공유 (Discord)", systemImage: "person.2.fill").font(.callout)

                    HStack {
                        Text("내 이름").font(.caption).foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)
                        TextField("채널에 보일 이름 (예: Tony)", text: $tracker.shareName)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Text("웹훅 URL").font(.caption).foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)
                        TextField("https://discord.com/api/webhooks/…", text: $tracker.shareWebhookURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                    }

                    Toggle(isOn: $tracker.autoShareOnGoal) {
                        Text("하루 목표 달성하면 자동으로 공유").font(.caption)
                    }
                    .toggleStyle(.switch)
                    .disabled(!Sharer.isConfigured)

                    HStack {
                        Button { Sharer.sendTest() } label: {
                            Label("테스트 전송", systemImage: "paperplane")
                        }
                        Button { Sharer.shareToday() } label: {
                            Label("지금 오늘 기록 공유", systemImage: "square.and.arrow.up")
                        }
                        Spacer()
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(!Sharer.isConfigured)

                    Text("Discord 채널 설정 → 연동 → 웹훅 → ‘웹훅 URL 복사’ 해서 붙여넣으면, 그 채널 친구들이 푸시로 받아요. 친구도 같은 채널 웹훅을 자기 앱에 넣으면 서로 보여요. (URL은 비밀!)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // ====================================================
    //  히트맵 카드 (GitHub 잔디처럼 날짜별 작업량)
    // ====================================================
    private var heatmapCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("최근 기록 히트맵").font(.headline)
                HeatmapView(totals: tracker.dailyTotals(), goalSeconds: tracker.goalSeconds)
                HStack(spacing: 6) {
                    Text("적음").font(.caption2).foregroundStyle(.secondary)
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(HeatmapView.color(intensity: Double(i) / 4))
                            .frame(width: 11, height: 11)
                    }
                    Text("많음").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // ====================================================
    //  업적 카드 (배지 그리드)
    // ====================================================
    private var achievementsCard: some View {
        let unlocked = tracker.unlocked
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                // 헤더를 누르면 펼침/접힘 (▶︎가 ▼로 회전)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showAchievements.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Text("업적").font(.headline)
                        Text("\(unlocked.count) / \(Achievement.all.count)")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        Spacer()
                        Text(showAchievements ? "접기" : "펼치기")
                            .font(.caption).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showAchievements ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showAchievements {
                    // 달성한 업적을 위로(원래 순서 유지), 못한 건 아래로.
                    let ordered = Achievement.all.enumerated().sorted { a, b in
                        let ua = unlocked.contains(a.element.id), ub = unlocked.contains(b.element.id)
                        if ua != ub { return ua }
                        return a.offset < b.offset
                    }.map(\.element)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
                        ForEach(ordered) { a in
                            AchievementBadge(achievement: a, unlocked: unlocked.contains(a.id))
                        }
                    }
                }
            }
        }
    }
}


// ── 요약 카드 한 칸 ─────────────────────────────────────────
private struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10).fill(tint.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(value).font(.title3).fontWeight(.bold)
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer()
            }
        }
    }
}


// ── 세션 목록의 한 줄 ───────────────────────────────────────
// 설명은 '오늘 것'만 수정 가능(박제). 태그는 분류용이라 아무 날이나 붙이고 뗄 수 있어요.
private struct SessionRow: View {
    @EnvironmentObject var tracker: TimeTracker
    let session: WorkSession
    @State private var note: String = ""
    @State private var addingTag = false
    @State private var newTag = ""

    // 시작 시각/설명은 '오늘 것'만 수정 가능. 지난 날은 잠금.
    private var editable: Bool { tracker.isEditable(session) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 왼쪽: 대표 태그 색 점 + 시간 범위
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(session.primaryTag.map { TagStyle.color(forTag: $0) } ?? Color.gray.opacity(0.5))
                        .frame(width: 9, height: 9)
                    Text("\(Fmt.hm(session.start)) – \(Fmt.hm(session.end))")
                        .font(.callout).fontWeight(.medium).monospacedDigit()
                    if !editable {
                        Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(.tertiary)
                            .help("지난 날의 설명·시간은 수정할 수 없어요 (태그는 가능)")
                    }
                }
                Text(Fmt.human(session.duration))
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 130, alignment: .leading)

            // 가운데: 설명 (오늘이면 수정, 지난 날이면 읽기 전용)
            if editable {
                TextField("설명", text: $note)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                    .onSubmit { tracker.updateNote(session.id, note: note) }
            } else {
                Text(session.note.isEmpty ? "—" : session.note)
                    .font(.callout)
                    .foregroundStyle(session.note.isEmpty ? .tertiary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 7)
            }

            // 오른쪽: 태그 (아무 날이나 추가/제거)
            FlowLayout(spacing: 4) {
                ForEach(session.tags, id: \.self) { tag in
                    RemovableTagChip(tag: tag) { tracker.removeTag(session.id, tag) }
                }
                if addingTag {
                    TextField("태그", text: $newTag)
                        .textFieldStyle(.plain)
                        .frame(width: 64)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(.quaternary.opacity(0.6)))
                        .onSubmit {
                            tracker.addTag(session.id, newTag)
                            newTag = ""; addingTag = false
                        }
                } else {
                    Button { addingTag = true } label: {
                        Image(systemName: "plus.circle").font(.callout).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("태그 추가")
                }
            }
            .frame(width: 200, alignment: .leading)

            // 위치 (아무 날이나 붙이거나 뗄 수 있어요)
            Menu {
                Button("현재 위치로 설정", systemImage: "location.fill") {
                    tracker.captureLocation(for: session.id)
                }
                if session.location != nil {
                    Button("위치 지우기", systemImage: "trash", role: .destructive) {
                        tracker.clearLocation(for: session.id)
                    }
                }
            } label: {
                Image(systemName: session.location != nil ? "mappin.circle.fill" : "mappin.circle")
                    .foregroundStyle(session.location != nil
                                     ? AnyShapeStyle(Color.red) : AnyShapeStyle(.tertiary))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
            .help(session.location?.name ?? "위치 없음")

            // 맨 오른쪽: 오늘이면 삭제 버튼 (지난 날은 비활성)
            if editable {
                Button { tracker.delete(session.id) } label: {
                    Image(systemName: "trash").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "trash").foregroundStyle(.clear)   // 자리 맞춤
            }
        }
        .padding(.vertical, 5)
        .onAppear { note = session.note }
        .onChange(of: session.note) { _, newValue in note = newValue }
    }
}


// ── 두 구간 '사이'에 놓이는 합치기 버튼 ─────────────────────
// 평소엔 옅은 구분선만 보이고, 이 줄 사이에 마우스를 올리면(hover)
// 가운데 '합치기' 버튼이 스르륵 나타나요.
private struct MergeDivider: View {
    let action: () -> Void
    @State private var hovering = false        // 마우스가 이 영역 위에 있나?

    var body: some View {
        ZStack {
            Divider().opacity(0.4)
            Button(action: action) {
                Label("합치기", systemImage: "arrow.triangle.merge")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("위·아래 두 구간을 하나로 합쳐요 (이른 시작 ~ 늦은 끝)")
            .opacity(hovering ? 1 : 0)         // hover 안 하면 숨김
            .scaleEffect(hovering ? 1 : 0.9)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 18)                     // 얇은 선보다 마우스로 올리기 쉽게 영역 확보
        .contentShape(Rectangle())             // 투명한 빈 곳도 hover로 인식되게
        .onHover { hovering = $0 }             // 마우스가 들어오면 true, 나가면 false
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }
}


// ── 카드(둥근 모서리 + 옅은 그림자) 공통 껍데기 ─────────────
struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
            )
    }
}


// ── 히트맵(GitHub 잔디) ─────────────────────────────────────
// 가로 = 주(週), 세로 = 요일. 칸 색이 진할수록 그날 많이 일한 거예요.
private struct HeatmapView: View {
    let totals: [Date: TimeInterval]   // 하루 시작시각 -> 그날 총 초
    let goalSeconds: Double

    private let weeks = 18             // 약 4개월치 (가로 = 주)
    private let cell: CGFloat = 12
    private let gap: CGFloat = 3
    private let leftLabel: CGFloat = 20   // 왼쪽 요일 라벨 칸 너비
    private let labelGap: CGFloat = 6     // 요일 라벨과 격자 사이 간격
    private var colStride: CGFloat { cell + gap }          // 열/행 하나가 차지하는 폭
    private var gridHeight: CGFloat { 7 * cell + 6 * gap } // 7행(요일) 높이
    private var gridWidth: CGFloat { CGFloat(weeks) * colStride - gap }

    // 격자 안의 좌표 도우미 (칸 사이 틈의 한가운데)
    private func colGapX(_ c: Int) -> CGFloat { CGFloat(c) * colStride - gap / 2 }
    private func rowGapY(_ r: Int) -> CGFloat { CGFloat(r) * colStride - gap / 2 }

    // 월 경계: '1일'이 떨어지는 (열, 행) / 위쪽 월 라벨
    private struct MonthBoundary { let col: Int; let row: Int; let label: String }
    private struct MonthLabel: Identifiable { let id = UUID(); let col: Int; let label: String }

    var body: some View {
        let weekStarts = computeWeekStarts()
        let boundaries = computeBoundaries(weekStarts)
        let labels = monthLabelMarks(weekStarts, boundaries)
        let today = Calendar.current.startOfDay(for: Date())

        VStack(alignment: .leading, spacing: 4) {
            monthLabels(labels)                      // 위: 월 라벨
            HStack(alignment: .top, spacing: labelGap) {
                weekdayLabels(firstCol: weekStarts.first ?? today)   // 왼쪽: 요일(7행)
                ZStack(alignment: .topLeading) {
                    grid(weekStarts: weekStarts, today: today)       // 격자(열=주, 행=요일)
                    separators(boundaries)                           // 월 경계 '계단식' 점선
                }
            }
        }
    }

    // ── 위쪽 월 라벨 ──
    private func monthLabels(_ labels: [MonthLabel]) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: 12)
            ForEach(labels) { m in
                Text(m.label)
                    .font(.caption2).foregroundStyle(.secondary)
                    .offset(x: leftLabel + labelGap + CGFloat(m.col) * colStride)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ── 왼쪽 요일 라벨 (보기 깔끔하게 홀수 행만 표시) ──
    private func weekdayLabels(firstCol: Date) -> some View {
        VStack(spacing: gap) {
            ForEach(0..<7, id: \.self) { d in
                Text(weekdayText(d, firstCol: firstCol))
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                    .frame(width: leftLabel, height: cell, alignment: .trailing)
            }
        }
    }

    private func weekdayText(_ d: Int, firstCol: Date) -> String {
        guard d % 2 == 1 else { return "" }   // 1,3,5행만 (월/수/금 식)
        let date = Calendar.current.date(byAdding: .day, value: d, to: firstCol) ?? firstCol
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "E"
        return f.string(from: date)
    }

    // ── 격자 (열 = 주, 행 = 요일) ──
    private func grid(weekStarts: [Date], today: Date) -> some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(Array(weekStarts.enumerated()), id: \.offset) { _, ws in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { d in
                        cellView(Calendar.current.date(byAdding: .day, value: d, to: ws) ?? ws,
                                 today: today)
                    }
                }
            }
        }
    }

    // ── 월 경계 '계단식' 점선 ──
    // 월 1일이 주(열) 중간에 떨어지므로, 경계가 직선이 아니라 계단처럼 꺾여요.
    // (윗칸=지난 달의 끝, 그 아래=새 달의 시작)
    private func separators(_ boundaries: [MonthBoundary]) -> some View {
        ForEach(boundaries, id: \.col) { b in
            Staircase(xRight: colGapX(b.col + 1), xLeft: colGapX(b.col),
                      yStep: rowGapY(b.row), bottom: gridHeight)
                .stroke(Color.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .frame(width: gridWidth, height: gridHeight, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func cellView(_ date: Date, today: Date) -> some View {
        if date > today {
            RoundedRectangle(cornerRadius: 2).fill(.clear)
                .frame(width: cell, height: cell)
        } else {
            let day = Calendar.current.startOfDay(for: date)
            let secs = totals[day] ?? 0
            let intensity = (secs <= 0) ? -1 : (goalSeconds > 0 ? min(1, secs / goalSeconds) : 0)
            RoundedRectangle(cornerRadius: 2)
                .fill(Self.color(intensity: intensity))
                .frame(width: cell, height: cell)
                .help("\(Fmt.dayLabel(date)) · \(Fmt.human(secs))")
        }
    }

    // 매주 시작일들
    private func computeWeekStarts() -> [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let firstCol = cal.date(byAdding: .day, value: -7 * (weeks - 1), to: thisWeekStart) ?? today
        return (0..<weeks).map { cal.date(byAdding: .day, value: 7 * $0, to: firstCol) ?? firstCol }
    }

    // 격자 안에서 '1일'이 떨어지는 (열, 행) 찾기
    private func computeBoundaries(_ weekStarts: [Date]) -> [MonthBoundary] {
        let cal = Calendar.current
        var out: [MonthBoundary] = []
        for col in 0..<weeks {
            for row in 0..<7 {
                guard let date = cal.date(byAdding: .day, value: row, to: weekStarts[col]) else { continue }
                if cal.component(.day, from: date) == 1 {
                    if col == 0 && row == 0 { continue }   // 맨 첫 칸은 경계 표시 안 함
                    out.append(MonthBoundary(col: col, row: row,
                                             label: "\(cal.component(.month, from: date))월"))
                }
            }
        }
        return out
    }

    // 위쪽 라벨: 맨 앞 달 + 각 경계 달 (늦게 시작하면 다음 열 위에)
    private func monthLabelMarks(_ weekStarts: [Date], _ boundaries: [MonthBoundary]) -> [MonthLabel] {
        let cal = Calendar.current
        var labels: [MonthLabel] = []
        if let first = weekStarts.first {
            labels.append(MonthLabel(col: 0, label: "\(cal.component(.month, from: first))월"))
        }
        for b in boundaries {
            let lc = b.row >= 4 ? b.col + 1 : b.col
            labels.append(MonthLabel(col: min(lc, weeks - 1), label: b.label))
        }
        return labels
    }

    // intensity: 0~1이면 초록 농도, 음수(-1)면 '기록 없음' 회색.
    static func color(intensity: Double) -> Color {
        if intensity < 0 { return Color.gray.opacity(0.15) }
        let green = Color(red: 0.20, green: 0.74, blue: 0.45)
        return green.opacity(0.25 + 0.75 * intensity)
    }
}


// 지도 핀 하나
private struct DaySpot: Identifiable {
    let id: UUID
    let coord: CLLocationCoordinate2D
    let color: Color
    let title: String
}


// 지도 조작(줌/이동) 켜고 끄는 작은 버튼 — 평소엔 고정해서 실수로 안 움직이게.
private struct MapFocusToggle: View {
    @Binding var focused: Bool
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { focused.toggle() }
        } label: {
            Label(focused ? "조작 중 · 탭해서 고정" : "지도 조작",
                  systemImage: focused ? "hand.draw.fill" : "hand.tap.fill")
                .font(.caption2).fontWeight(.semibold)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(focused ? Color.accentColor : .clear, lineWidth: 1.5))
                .foregroundStyle(focused ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .padding(8)
    }
}


// 월 경계 계단선: 오른쪽 위 → 아래로 → 왼쪽으로 → 다시 아래로 (절대 좌표로 그림)
private struct Staircase: Shape {
    let xRight: CGFloat
    let xLeft: CGFloat
    let yStep: CGFloat
    let bottom: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: xRight, y: 0))
        p.addLine(to: CGPoint(x: xRight, y: yStep))
        p.addLine(to: CGPoint(x: xLeft, y: yStep))
        p.addLine(to: CGPoint(x: xLeft, y: bottom))
        return p
    }
}


// ── 24시간 시계 ─────────────────────────────────────────────
// 하루(24h)를 원 한 바퀴로 보고, 일한 시간대를 태그 색으로 칠해요.
// 0시=맨 위(12시 방향), 시계방향으로 6시=오른쪽 · 12시=아래 · 18시=왼쪽.
struct ClockSeg: Identifiable {
    let id = UUID()
    let start: Double   // 0~1 (0=0시, 1=24시)
    let end: Double
    let color: Color
}

private struct DayClockView: View {
    let segments: [ClockSeg]
    let centerText: String
    let centerSub: String

    private let size: CGFloat = 250
    private let ring: CGFloat = 24
    private let inset: CGFloat = 18
    private var tickR: CGFloat { size / 2 - inset - ring - 6 }
    private var labelR: CGFloat { size / 2 - inset - ring - 20 }

    var body: some View {
        ZStack {
            // 배경 다이얼
            Circle().stroke(.quaternary.opacity(0.4), lineWidth: ring).padding(inset)

            // 일한 시간대 호 (자정=위, 시계방향)
            ForEach(segments) { seg in
                Circle()
                    .trim(from: seg.start, to: seg.end)
                    .stroke(seg.color, style: StrokeStyle(lineWidth: ring, lineCap: .butt))
                    .padding(inset)
                    .rotationEffect(.degrees(-90))
            }

            // 시간 눈금 점 (6시간마다 진하게)
            ForEach(0..<24, id: \.self) { h in
                let a = Double(h) / 24 * 2 * .pi - .pi / 2
                Circle()
                    .fill(.secondary.opacity(h % 6 == 0 ? 0.55 : 0.22))
                    .frame(width: h % 6 == 0 ? 3 : 2, height: h % 6 == 0 ? 3 : 2)
                    .position(x: size / 2 + CGFloat(cos(a)) * tickR,
                              y: size / 2 + CGFloat(sin(a)) * tickR)
            }

            // 0 / 6 / 12 / 18 라벨
            ForEach([0, 6, 12, 18], id: \.self) { h in
                let a = Double(h) / 24 * 2 * .pi - .pi / 2
                Text("\(h)")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .position(x: size / 2 + CGFloat(cos(a)) * labelR,
                              y: size / 2 + CGFloat(sin(a)) * labelR)
            }

            // 중앙: 오늘 누적 (라벨과 안 겹치게 폭 제한 + 자동 축소)
            VStack(spacing: 2) {
                Text(centerText)
                    .font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(centerSub).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 2 * labelR - 14)
        }
        .frame(width: size, height: size)
    }
}


// ── 업적 배지 한 칸 ─────────────────────────────────────────
// 달성하면 색이 켜지고, 아직이면 흑백으로 흐릿하게.
private struct AchievementBadge: View {
    let achievement: Achievement
    let unlocked: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(achievement.emoji)
                .font(.title2)
                .grayscale(unlocked ? 0 : 1)
                .opacity(unlocked ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.title).font(.callout).fontWeight(.semibold)
                Text(achievement.detail).font(.caption2)
                    .foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(unlocked ? AnyShapeStyle(Color.accentColor.opacity(0.12))
                               : AnyShapeStyle(.quaternary.opacity(0.4)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(unlocked ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .opacity(unlocked ? 1 : 0.75)
    }
}


// ============================================================
//  태그 검색 페이지 — #태그별로 모아보고 검색해요.
// ============================================================
private struct TagSearchView: View {
    @EnvironmentObject var tracker: TimeTracker
    @State private var search = ""
    @State private var selected: String? = nil

    var body: some View {
        let summaries = tracker.tagSummaries()
        let filtered = filter(summaries)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 검색창
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("태그 검색 (예: 개발)", text: $search)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))

                if summaries.isEmpty {
                    emptyState
                } else {
                    // 태그 목록
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("태그 \(summaries.count)종").font(.headline)
                            if filtered.isEmpty {
                                Text("검색 결과가 없어요")
                                    .font(.callout).foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(filtered) { row in
                                    tagRow(row)
                                    if row.id != filtered.last?.id { Divider().opacity(0.3) }
                                }
                            }
                        }
                    }

                    // 선택된 태그의 기록
                    if let sel = selected {
                        selectedDetail(sel)
                    }
                }
            }
            .padding(20)
        }
    }

    // 검색어로 태그 목록 거르기 (# 떼고, 대소문자 무시)
    private func filter(_ list: [TagSummary]) -> [TagSummary] {
        let q = search.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "").lowercased()
        guard !q.isEmpty else { return list }
        return list.filter { $0.tag.contains(q) }
    }

    // 태그 한 줄 (누르면 아래에 그 태그의 기록이 펼쳐져요)
    private func tagRow(_ row: TagSummary) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selected = (selected == row.tag) ? nil : row.tag
            }
        } label: {
            HStack(spacing: 10) {
                TagChip(tag: row.tag)
                Spacer()
                Text(Fmt.human(row.seconds))
                    .font(.callout).fontWeight(.semibold).monospacedDigit()
                Text("· \(row.count)회")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Image(systemName: selected == row.tag ? "chevron.down" : "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }

    // 선택된 태그의 모든 기록 (날짜 무관, 최근 순)
    private func selectedDetail(_ tag: String) -> some View {
        let list = tracker.sessions(withTag: tag)
        let total = list.reduce(0) { $0 + $1.duration }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TagChip(tag: tag)
                    Text("기록").font(.headline)
                    Spacer()
                    Text("총 \(Fmt.human(total)) · \(list.count)회")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                ForEach(list) { s in
                    detailRow(s)
                    if s.id != list.last?.id { Divider().opacity(0.3) }
                }
            }
        }
    }

    private func detailRow(_ s: WorkSession) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.dayLabel(s.start)).font(.callout).fontWeight(.medium)
                Text("\(Fmt.hm(s.start)) – \(Fmt.hm(s.end)) · \(Fmt.human(s.duration))")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 180, alignment: .leading)
            Text(s.note.isEmpty ? "—" : s.note)
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "number")
                .font(.system(size: 34)).foregroundStyle(.tertiary)
            Text("아직 태그가 없어요").font(.headline)
            Text("메모에 #개발 처럼 적으면 여기서 태그별로 모아볼 수 있어요")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 50)
    }
}


// ============================================================
//  지도 페이지 — 위치 찍은 모든 기록을 점으로, 누르면 그 날 기록을 봐요.
// ============================================================
private struct MapPageView: View {
    @EnvironmentObject var tracker: TimeTracker
    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: UUID? = nil
    @State private var mapFocused = false        // 조작(줌/이동) 허용 여부

    var body: some View {
        let spots = allSpots()
        Group {
            if spots.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    // 평소엔 고정, '지도 조작'을 켜야 줌/이동. 핀 탭(선택)은 항상 됨.
                    Map(position: $camera,
                        interactionModes: mapFocused ? .all : [],
                        selection: $selected) {
                        ForEach(spots) { spot in
                            Marker(spot.title, coordinate: spot.coord)   // 라벨 = 날짜
                                .tint(spot.color)
                                .tag(spot.id)
                        }
                    }
                    .overlay(alignment: .topTrailing) { MapFocusToggle(focused: $mapFocused) }

                    // 선택한 점의 '그 날 기록' 패널
                    if let sel = selected,
                       let session = tracker.sessions.first(where: { $0.id == sel }) {
                        dayPanel(for: session)
                            .frame(width: 300)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 위치가 있는 모든 기록을 점으로
    private func allSpots() -> [DaySpot] {
        tracker.sessions
            .filter { $0.location != nil }
            .sorted { $0.start > $1.start }
            .map { s in
                let loc = s.location!
                return DaySpot(
                    id: s.id,
                    coord: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude),
                    color: s.primaryTag.map { TagStyle.color(forTag: $0) } ?? .gray,
                    title: Fmt.shortDate(s.start))   // 핀 라벨 = 날짜
            }
    }

    // 오른쪽 패널: 선택한 기록이 있는 '그 날'의 모든 구간
    private func dayPanel(for session: WorkSession) -> some View {
        let day = tracker.dayInterval(of: session.start)
        let list = tracker.sessions(in: day)
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(Fmt.dayLabel(session.start)).font(.headline)
                    Spacer()
                    Button { selected = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                if let name = session.location?.name {
                    Label(name, systemImage: "mappin.circle.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                ForEach(list) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(s.primaryTag.map { TagStyle.color(forTag: $0) } ?? Color.gray.opacity(0.5))
                                .frame(width: 8, height: 8)
                            Text("\(Fmt.hm(s.start)) – \(Fmt.hm(s.end))")
                                .font(.callout).monospacedDigit()
                            Spacer()
                            Text(Fmt.human(s.duration))
                                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        }
                        if !s.note.isEmpty {
                            Text(s.note).font(.caption).foregroundStyle(.secondary)
                        }
                        if !s.tags.isEmpty {
                            FlowLayout(spacing: 4) { ForEach(s.tags, id: \.self) { TagChip(tag: $0) } }
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(s.id == session.id ? Color.accentColor.opacity(0.12) : Color.clear))
                }
            }
            .padding(16)
        }
        .background(.ultraThinMaterial)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "map").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("위치를 찍은 기록이 아직 없어요").font(.headline)
            Text("메뉴바의 ‘현재 위치 찍기’나, 기록 줄의 📍 버튼으로 위치를 붙여보세요")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
