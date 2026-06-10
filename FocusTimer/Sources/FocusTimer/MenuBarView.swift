import SwiftUI
import AppKit

// ============================================================
//  MenuBarView = 메뉴바 아이콘을 눌렀을 때 아래로 펼쳐지는 작은 패널.
//  여기서 시작/멈춤 하고, 지금 뭘 하는지 메모/카테고리를 고르고,
//  오늘 누적 시간을 보고, 대시보드 창을 열 수 있어요.
// ============================================================
struct MenuBarView: View {
    // 공용 두뇌(TimeTracker)를 받아와요. 값이 바뀌면 이 화면도 자동 갱신.
    @EnvironmentObject var tracker: TimeTracker
    @State private var tagInput = ""   // 태그 입력칸 글자

    var body: some View {
        VStack(spacing: 0) {
            header        // 위: 큰 타이머
            goalBar       // 오늘 목표 진행바 + 스트릭
            controls      // 가운데: 카테고리/메모/시작버튼
            Divider().opacity(0.4)
            footer        // 아래: 오늘 누적 + 대시보드/종료
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)   // 반투명 유리 느낌 (fancy)
    }

    // ── 위쪽: 큰 시계 ──────────────────────────────────────
    private var header: some View {
        VStack(spacing: 6) {
            // 상태 글자: 측정 중 / 멈춤
            HStack(spacing: 6) {
                Circle()
                    .fill(tracker.isRunning ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(tracker.isRunning ? "측정 중" : "멈춤")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            // 큰 시간: 측정 중이면 흐르는 시간, 멈춰 있으면 오늘 누적
            Text(tracker.isRunning
                 ? Fmt.clock(tracker.currentElapsed)
                 : Fmt.clock(tracker.total(in: tracker.dayInterval(of: tracker.now))))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()                       // 숫자 폭 고정 → 안 떨림
                .contentTransition(.numericText())       // 숫자 바뀔 때 부드럽게
                .foregroundStyle(tracker.isRunning ? AnyShapeStyle(headerGradient) : AnyShapeStyle(.primary))

            Text(tracker.isRunning ? "지금 측정 중" : "오늘 누적")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var headerGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 0.30, green: 0.55, blue: 0.98),
                                Color(red: 0.61, green: 0.40, blue: 0.94)],
                       startPoint: .leading, endPoint: .trailing)
    }

    // ── 오늘 목표 진행바 + 스트릭 🔥 ───────────────────────
    private var goalBar: some View {
        let streak = tracker.currentStreak()
        return VStack(spacing: 6) {
            HStack {
                Text("오늘 목표")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if streak > 0 {
                    Text("🔥 \(streak)일 연속")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundStyle(.orange)
                }
            }
            // 진행 바 (목표 대비 오늘 누적)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary.opacity(0.6))
                    Capsule().fill(headerGradient)
                        .frame(width: max(6, geo.size.width * tracker.goalProgressToday))
                }
            }
            .frame(height: 8)
            HStack(spacing: 4) {
                Text(Fmt.human(tracker.liveTodayTotal))
                    .font(.caption2).fontWeight(.semibold).monospacedDigit()
                Text("/ \(tracker.dailyGoalHours)시간")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(tracker.goalProgressToday * 100))%")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // ── 가운데: 설명 + 태그 + 시작/멈춤 ────────────────────
    private var controls: some View {
        VStack(spacing: 10) {
            // 1) 설명 입력칸 (태그와 분리)
            TextField("무엇을 하고 있나요?", text: $tracker.draftNote)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.6)))

            // 2) 태그 입력칸 (Enter로 추가, 공백/쉼표로 여러 개)
            HStack(spacing: 6) {
                Image(systemName: "number").font(.caption).foregroundStyle(.secondary)
                TextField("태그 입력 후 Enter", text: $tagInput)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        tracker.addDraftTagsFromText(tagInput)
                        tagInput = ""
                    }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.6)))

            // 3) 지금 붙인 태그들 (x로 제거)
            if !tracker.draftTags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tracker.draftTags, id: \.self) { tag in
                        RemovableTagChip(tag: tag) { tracker.removeDraftTag(tag) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 4) 최근 쓴 태그 (탭하면 추가) — 이미 붙인 건 빼고 보여줘요
            let recent = tracker.recentTags().filter { !tracker.draftTags.contains($0) }
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("최근 쓴 태그").font(.caption2).foregroundStyle(.tertiary)
                    FlowLayout(spacing: 6) {
                        ForEach(recent, id: \.self) { tag in
                            QuickTagChip(tag: tag, active: false) {
                                tracker.toggleDraftTag(tag)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 5) 위치 찍기 (수동) — 지금 있는 곳을 이 기록에 붙여요
            HStack(spacing: 8) {
                Button {
                    tracker.captureDraftLocation()
                } label: {
                    Label(tracker.draftLocation == nil ? "현재 위치 찍기" : "위치 다시 찍기",
                          systemImage: "location.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered).controlSize(.small)

                if let loc = tracker.draftLocation {
                    Text("📍 " + (loc.name ?? "위치 기록됨"))
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button { tracker.clearDraftLocation() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }

            // 큰 시작/멈춤 버튼
            // 배경을 '라벨 안'에 넣고 contentShape로 전체를 클릭 영역으로 만들어요.
            // (이렇게 안 하면 가운데 글자/아이콘 부분만 눌리고 가장자리는 안 눌려요)
            Button(action: { tracker.toggle() }) {
                HStack {
                    Image(systemName: tracker.isRunning ? "stop.fill" : "play.fill")
                    Text(tracker.isRunning ? "멈추고 기록 저장" : "측정 시작")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(tracker.isRunning
                              ? AnyShapeStyle(Color.red.gradient)
                              : AnyShapeStyle(headerGradient))
                )
                .foregroundStyle(.white)
                .contentShape(Rectangle())   // 빈 여백까지 전부 클릭 가능하게
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    // ── 아래쪽: 오늘 누적 + 버튼들 ─────────────────────────
    private var footer: some View {
        VStack(spacing: 10) {
            HStack {
                Label("오늘", systemImage: "calendar")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(Fmt.human(tracker.liveTodayTotal))
                    .font(.caption).fontWeight(.semibold).monospacedDigit()
                // 공유 채널이 설정돼 있으면, 오늘 기록을 한 번에 친구에게 보내는 버튼
                if Sharer.isConfigured {
                    Button { Sharer.shareToday() } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .help("오늘 기록을 친구 채널(Discord)에 공유")
                }
            }

            HStack(spacing: 8) {
                Button {
                    DashboardWindow.shared.show()
                } label: {
                    Label("대시보드 열기", systemImage: "chart.bar.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                Button {
                    tracker.stop()          // 측정 중이었다면 먼저 저장하고 종료
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .controlSize(.large)
                .help("앱 종료 (측정 중이면 저장 후 종료)")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }
}


// ── 메뉴바에 '떠 있는' 라벨 ─────────────────────────────────
// 작은 링이 '오늘 목표'만큼 차오르고, 옆에 시간이 떠요.
//  · 측정 중  → 초록 링 + 흐르는 시간
//  · 멈춤     → 파란 링 + 오늘 누적 시간
//  · 목표 달성 → 금색 링 ✨
//
//  ⚠️ 메뉴바 라벨은 SwiftUI 도형(Circle 등)을 직접 못 그려서 비어 보여요.
//     그래서 링을 NSImage로 '구워서' 이미지로 넣어요. (텍스트·이미지는 잘 보임)
struct MenuBarLabel: View {
    @ObservedObject var tracker: TimeTracker

    private var progress: Double { min(1, max(0, tracker.goalProgressToday)) }
    private var reached: Bool { progress >= 1 }

    private var ringColor: Color {
        if reached { return Color(red: 0.95, green: 0.72, blue: 0.20) }   // 금색
        if tracker.isRunning { return .green }
        return Color(red: 0.30, green: 0.55, blue: 0.98)                  // 멈춤 = 파랑
    }
    private var timeText: String {
        tracker.isRunning ? Fmt.clock(tracker.currentElapsed)
                          : Fmt.clock(tracker.liveTodayTotal)
    }

    var body: some View {
        // ⚠️ 메뉴바는 HStack 간격을 무시해서, 링-시간 간격은 아래 이미지의
        //    오른쪽 여백(trailing)으로 조절해요. (spacing은 효과 없음)
        HStack(spacing: 0) {
            Image(nsImage: ringImage)        // 오른쪽 여백이 이미지에 구워져 있음
            Text(timeText).monospacedDigit() // 시간은 진짜 텍스트(메뉴바 색에 자동 적응)
        }
    }

    // 작은 링을 NSImage로 렌더링. 바탕은 회색(밝음/어둠 메뉴바 둘 다 보임), 채움은 상태 색.
    private var ringImage: NSImage {
        let ring = ZStack {
            Circle().stroke(Color.gray.opacity(0.55), lineWidth: 2.4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(-90))   // 12시 방향에서 시계방향으로 차오름
        }
        .frame(width: 14, height: 14)
        // 오른쪽 여백(trailing)이 곧 '링↔시간' 간격이에요. 이 숫자를 키우면 더 벌어져요.
        .padding(EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 8))

        let renderer = ImageRenderer(content: ring)
        renderer.scale = 2                        // 레티나 선명하게
        return renderer.nsImage ?? NSImage()
    }
}


// ── 해시태그 칩 ─────────────────────────────────────────────
// "#개발" 처럼 태그를 색칩으로 보여줘요. 색은 태그 글자에 따라 자동.
struct TagChip: View {
    let tag: String
    var body: some View {
        Text("#\(tag)")
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(TagStyle.color(forTag: tag).opacity(0.85)))
            .foregroundStyle(.white)
    }
}


// ── 제거 가능한 태그 칩 (x 눌러 빼기) ───────────────────────
struct RemovableTagChip: View {
    let tag: String
    let onRemove: () -> Void
    var body: some View {
        HStack(spacing: 4) {
            Text("#\(tag)").font(.caption2).fontWeight(.semibold)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 8).padding(.trailing, 5).padding(.vertical, 4)
        .background(Capsule().fill(TagStyle.color(forTag: tag).opacity(0.85)))
        .foregroundStyle(.white)
    }
}


// ── 자주 쓰는 태그 단축칩 ───────────────────────────────────
// 지금 메모에 들어 있으면 색이 꽉 차고(active), 아니면 옅은 테두리만.
struct QuickTagChip: View {
    let tag: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("#\(tag)")
                .font(.caption2).fontWeight(.semibold)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(
                    Capsule().fill(active ? AnyShapeStyle(TagStyle.color(forTag: tag))
                                          : AnyShapeStyle(.quaternary.opacity(0.4)))
                )
                .overlay(
                    Capsule().stroke(TagStyle.color(forTag: tag).opacity(active ? 0 : 0.5), lineWidth: 1)
                )
                .foregroundStyle(active ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }
}


// ── 칩들이 줄을 넘어가면 자동으로 다음 줄로 흐르는 배치 ──────
// (SwiftUI엔 기본 '흐름 배치'가 없어서 Layout으로 직접 만들었어요)
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            sub.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                      anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
