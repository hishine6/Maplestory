import SwiftUI
import AppKit

// ============================================================
//  EffectOverlay — 범용 축하 효과 오버레이.
//
//  기존 ConfettiOverlay 를 일반화한 것이에요. 차이점:
//   - 컨페티 하나만 띄우던 것에서 → '여러 효과 View 를 ZStack 으로
//     겹쳐' 한 번에 띄울 수 있게 바뀌었어요.
//   - 효과 View 들은 타입이 제각각이지만(불꽃/풍선/이모지/트로피/글로우)
//     모두 init(birth:duration:) 만 공유하므로, 호출부에서 AnyView 로
//     '타입을 지워' 배열에 담아 넘기면 여기서 ZStack 으로 합쳐 그려요.
//   - 화면 전체를 덮는 투명 borderless 창을 모든 모니터에 하나씩 띄우고,
//     클릭은 통과(ignoresMouseEvents)시켜 일하던 걸 막지 않아요.
//   - duration 뒤 부드럽게 페이드아웃하고 창을 제거해요.
//   - 손쉬운 사용(모션 줄이기)이 켜져 있으면 효과를 통째로 생략해요.
//
//  쓰는 법:
//      EffectOverlay.shared.fire(duration: 4.0) { birth, dur in
//          [
//              AnyView(ConfettiView(pieces: ConfettiFactory.make(160), birth: birth)),
//              AnyView(FireworksEffectView(birth: birth, duration: dur)),
//          ]
//      }
//  → 클로저는 (birth, duration) 을 받아 'AnyView 로 감싼 효과 View 배열'을
//    돌려주면 돼요. 모든 효과가 같은 birth/duration 을 공유해 박자가 맞아요.
// ============================================================
@MainActor
final class EffectOverlay {
    static let shared = EffectOverlay()

    private var windows: [NSWindow] = []
    private var clearItem: DispatchWorkItem?

    /// 효과 View 들을 모아 화면 전체에 띄워요.
    /// - Parameters:
    ///   - duration: 효과가 살아있는 시간(초). 마지막 0.4초쯤 페이드아웃은
    ///               각 효과 View 가 스스로 처리하지만, 창 자체도 끝에서
    ///               부드럽게 사라지게 한 번 더 페이드아웃해요.
    ///   - respectsReduceMotion: 모션 줄이기 설정을 존중할지(기본 true).
    ///   - layers: (birth, duration) 을 받아 AnyView 배열을 돌려주는 빌더.
    ///             배열의 앞쪽이 뒤(아래 레이어), 뒤쪽이 위(앞 레이어)예요.
    func fire(duration: Double,
              respectsReduceMotion: Bool = true,
              layers: (_ birth: Date, _ duration: Double) -> [AnyView]) {

        // 모션 줄이기가 켜져 있으면 화려한 효과는 생략(접근성 존중).
        if respectsReduceMotion,
           NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return
        }

        dismiss()   // 이전 효과가 남아 있으면 먼저 정리

        let birth = Date()
        let built = layers(birth, duration)
        guard !built.isEmpty else { return }

        // 여러 효과를 하나의 ZStack 으로 겹쳐요. 타입이 지워진 AnyView 라
        // 서로 다른 효과를 한 배열에 담아도 문제없어요.
        let root = ZStack {
            ForEach(Array(built.enumerated()), id: \.offset) { _, layer in
                layer
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()

        // 연결된 모니터마다 하나씩 창을 띄워요(멀티모니터 지원).
        for screen in NSScreen.screens {
            let hosting = NSHostingView(rootView: root)

            let w = NSWindow(contentRect: screen.frame,
                             styleMask: [.borderless], backing: .buffered, defer: false)
            w.contentView = hosting
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true                    // 클릭 통과(작업 방해 없음)
            w.level = .screenSaver                          // 거의 모든 것 위에
            w.collectionBehavior = [.canJoinAllSpaces,      // 모든 Space 에서 보임
                                    .fullScreenAuxiliary,   // 풀스크린 앱 위에도 보임
                                    .stationary]            // Space 전환 시 따라다니지 않음
            w.setFrame(screen.frame, display: true)
            w.alphaValue = 1
            w.orderFrontRegardless()                        // 앱이 비활성이어도 보여줌
            windows.append(w)
        }

        // duration 뒤 창을 부드럽게 페이드아웃하고 제거해요.
        let item = DispatchWorkItem { [weak self] in self?.fadeOutAndDismiss() }
        clearItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    /// 창 자체를 0.45초에 걸쳐 페이드아웃한 뒤 제거.
    /// (효과 View 의 내부 페이드아웃과 더해져 자연스럽게 사라져요.)
    private func fadeOutAndDismiss() {
        clearItem = nil
        guard !windows.isEmpty else { return }
        let toClose = windows
        windows.removeAll()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            for w in toClose { w.animator().alphaValue = 0 }
        } completionHandler: {
            // 완료 핸들러는 메인 스레드에서 불려요 → assumeIsolated 로 안전 정리.
            MainActor.assumeIsolated {
                for w in toClose { w.orderOut(nil) }
            }
        }
    }

    /// 즉시 제거(다음 효과를 띄우기 전 정리용).
    func dismiss() {
        clearItem?.cancel()
        clearItem = nil
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
    }
}