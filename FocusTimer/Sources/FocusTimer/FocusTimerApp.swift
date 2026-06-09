import SwiftUI
import AppKit

// ============================================================
//  앱의 출발점.
//  이 앱은 '메뉴바 전용 앱'이에요 — Dock에 큰 창으로 뜨지 않고,
//  화면 맨 위 메뉴바에 시간이 항상 보여요. 거기를 누르면 패널이 열려요.
// ============================================================
@main
struct FocusTimerApp: App {

    // 맥 앱의 기본 동작(메뉴바 전용으로 만들기)을 담당하는 연결고리
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // 앱 전체가 함께 보는 '두뇌'. @StateObject로 앱이 살아있는 동안 유지돼요.
    @StateObject private var tracker = TimeTracker.shared

    var body: some Scene {
        // MenuBarExtra = 메뉴바에 들어가는 항목.
        //  label : 메뉴바에 '보이는' 부분 (실시간으로 흐르는 시간 글자)
        //  내용  : 그걸 눌렀을 때 아래로 펼쳐지는 패널(MenuBarView)
        MenuBarExtra {
            MenuBarView()
                .environmentObject(tracker)
        } label: {
            // 작은 목표 링 + 시간. tracker가 매초 갱신되므로 링/시간도 매초 갱신돼요.
            MenuBarLabel(tracker: tracker)
        }
        // .window = 패널을 '작은 창'처럼 넓게 보여줘요 (메모 입력 등 가능).
        .menuBarExtraStyle(.window)
    }
}


// ── 앱 기본 동작 설정 ───────────────────────────────────────
// .accessory = Dock 아이콘 없이 메뉴바에서만 사는 앱.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    // '자리 비움'이 이만큼 이어지면 자동 종료 (5분)
    // 화면보호기 / 화면 잠금 / 디스플레이 꺼짐 — 셋 다 같은 규칙으로 처리해요.
    static let awayAutoStopDelay: TimeInterval = 300

    private var awayReasons: Set<String> = []        // 지금 '자리 비움' 상태인 이유들
    private var awayStart: Date?                      // 처음 자리 비운 시각
    private var autoStopItem: DispatchWorkItem?       // 5분 뒤 자동종료 예약

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // macOS 기본 알림을 보내도 되는지 권한을 한 번 물어봐요.
        Notifier.requestAuthorization()

        // '자리 비움' 신호 구독: 화면보호기 / 화면 잠금은 시스템 전역 알림(DistributedNotificationCenter),
        // 디스플레이 꺼짐은 NSWorkspace 알림으로 와요.
        let dnc = DistributedNotificationCenter.default()
        func observeDNC(_ name: String, away: Bool, reason: String) {
            dnc.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { away ? self?.goAway(reason) : self?.comeBack(reason) }
            }
        }
        observeDNC("com.apple.screensaver.didstart", away: true,  reason: "screensaver")
        observeDNC("com.apple.screensaver.didstop",  away: false, reason: "screensaver")
        observeDNC("com.apple.screenIsLocked",       away: true,  reason: "lock")
        observeDNC("com.apple.screenIsUnlocked",     away: false, reason: "lock")

        let wnc = NSWorkspace.shared.notificationCenter
        wnc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.goAway("display") }
        }
        wnc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.comeBack("display") }
        }

        // '오늘 누적 N시간 달성' 순간마다 귀여운 알림을 띄우도록 연결해요.
        TimeTracker.shared.onMilestone = { hours in
            Celebration.fire(hours: hours)
        }
        // 하루 목표를 달성하면 화면 전체 컨페티!
        TimeTracker.shared.onGoalReached = {
            Celebration.goalReached()
        }
        // 이번 주 목표를 달성하면 컨페티!
        TimeTracker.shared.onWeeklyGoalReached = {
            Celebration.weeklyGoalReached()
        }
        // 이번 달 목표를 달성하면 더 큰 컨페티!
        TimeTracker.shared.onMonthlyGoalReached = {
            Celebration.monthlyGoalReached()
        }
        // 새 업적을 달성하면 배지 토스트.
        TimeTracker.shared.onAchievement = { achievement in
            Celebration.achievement(achievement)
        }
    }

    // 앱이 꺼지기 직전에 항상 불려요(종료 버튼·Cmd+Q·로그아웃 등 모든 경로).
    // 측정 중이었다면 지금까지의 구간을 저장하고 끝내요. (멈춤 상태면 아무 일 없음)
    func applicationWillTerminate(_ notification: Notification) {
        TimeTracker.shared.stop()
    }

    // ── 자리 비움 → 5분 → 자동 종료 ────────────────────────
    // 화면보호기/잠금/디스플레이 꺼짐 중 하나라도 켜지면 '자리 비움' 시작.
    // 5분 안에 (모든 이유가) 풀리면 취소, 5분 넘게 이어지면 측정을 자동 종료해요.
    private func goAway(_ reason: String) {
        let wasHome = awayReasons.isEmpty
        awayReasons.insert(reason)
        guard wasHome else { return }          // 이미 비운 상태면 타이머 유지(처음 비운 시각 기준)
        awayStart = Date()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.autoStopIfStillAway() }
        }
        autoStopItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.awayAutoStopDelay, execute: item)
    }

    private func comeBack(_ reason: String) {
        awayReasons.remove(reason)
        guard awayReasons.isEmpty else { return }   // 다른 이유가 남아 있으면 계속 비운 상태
        autoStopItem?.cancel()                      // 다 돌아왔으면 자동종료 취소
        autoStopItem = nil
        awayStart = nil
    }

    private func autoStopIfStillAway() {
        autoStopItem = nil
        // 측정 중일 때만, 끝 시각은 '처음 자리 비운 순간'으로 되돌려요(그 5분은 작업 아님).
        if TimeTracker.shared.isRunning {
            TimeTracker.shared.stop(at: awayStart)
        }
        awayReasons.removeAll()
        awayStart = nil
    }
}


// ============================================================
//  DashboardWindow = '대시보드 열기'를 누르면 뜨는 큰 창을 관리해요.
//  메뉴바 전용 앱이라 SwiftUI의 일반 창 대신, 필요할 때만 직접 창을
//  만들어 띄우는 방식을 써요(시작할 때 빈 창이 뜨는 걸 막으려고).
// ============================================================
@MainActor
final class DashboardWindow: NSObject, NSWindowDelegate {
    static let shared = DashboardWindow()
    private var window: NSWindow?

    func show() {
        // 메뉴바 팝오버(지금 떠 있는 그 작은 창 = 현재 keyWindow)를 먼저 닫아요.
        // → 대시보드를 열면 위젯 화면은 사라지고 대시보드만 남아요.
        NSApp.keyWindow?.close()

        // 창이 아직 없으면 한 번 만들어요. (다음부터는 재사용)
        if window == nil {
            let hosting = NSHostingController(
                rootView: DashboardView().environmentObject(TimeTracker.shared)
            )
            let w = NSWindow(contentViewController: hosting)
            w.title = "작업 기록"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.setContentSize(NSSize(width: 880, height: 640))
            w.isReleasedWhenClosed = false   // 닫아도 메모리에서 사라지지 않게 (재사용)
            w.center()
            w.delegate = self
            window = w
        }

        // 창을 띄우는 동안만 잠깐 '일반 앱'처럼 굴어 창이 앞으로 잘 나오게 해요.
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // 창을 닫으면 다시 메뉴바 전용(.accessory)으로 돌아가요.
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
