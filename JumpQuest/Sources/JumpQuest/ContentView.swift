import SwiftUI
import SpriteKit

// SpriteKit 게임 화면(SKView)을 SwiftUI 안에 끼워넣는 "다리".
struct GameContainer: NSViewRepresentable {
    func makeNSView(context: Context) -> SKView {
        let skView = KeyableSKView()
        let scene = GameScene(size: CGSize(width: 720, height: 480))
        scene.scaleMode = .aspectFit           // 무대 크기를 720x480으로 "고정" (바닥이 항상 제대로 깔림)
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
    override func mouseDown(with event: NSEvent) { scene?.mouseDown(with: event) }
}

struct ContentView: View {
    var body: some View {
        GameContainer()
            .frame(width: 720, height: 480)
    }
}
