import SwiftUI
import SpriteKit

// SpriteKit 게임 화면(SKView)을 SwiftUI 안에 끼워넣는 "다리".
struct GameContainer: NSViewRepresentable {
    func makeNSView(context: Context) -> SKView {
        let skView = KeyableSKView()
        let scene = GameScene(size: CGSize(width: 1280, height: 720))   // 더 크게(+더 넓은 시야)
        scene.scaleMode = .aspectFit           // 창 키우면 깨끗하게 확대(HUD/월드 같이 스케일). HUD는 viewW/viewH 자동
        skView.presentScene(scene)
        skView.ignoresSiblingOrder = true
        return skView
    }
    func updateNSView(_ nsView: SKView, context: Context) {
        // 키보드 입력을 받으려면 이 뷰가 "첫 응답자"여야 해요.
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

// 키보드 입력을 받아서 게임 무대(scene)로 전달하는 SKView.
final class KeyableSKView: SKView {
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { scene?.keyDown(with: event) }
    override func keyUp(with event: NSEvent)   { scene?.keyUp(with: event) }
    override func mouseDown(with event: NSEvent)    { scene?.mouseDown(with: event) }
    override func rightMouseDown(with event: NSEvent) { scene?.rightMouseDown(with: event) }   // 버프 우클릭 해제
    override func mouseDragged(with event: NSEvent) { scene?.mouseDragged(with: event) }   // 창 드래그
    override func mouseUp(with event: NSEvent)      { scene?.mouseUp(with: event) }
    override func scrollWheel(with event: NSEvent)  { scene?.scrollWheel(with: event) }     // 휠 스크롤
}

struct ContentView: View {
    var body: some View {
        GameContainer()
            .frame(minWidth: 960, idealWidth: 1280, maxWidth: .infinity,
                   minHeight: 540, idealHeight: 720, maxHeight: .infinity)   // 리사이즈 가능(동적)
    }
}
