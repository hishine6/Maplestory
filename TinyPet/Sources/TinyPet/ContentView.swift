import SwiftUI

// 앱의 "뿌리" 화면. 캐릭터가 있느냐 없느냐에 따라 화면을 바꿔요.
struct ContentView: View {
    // 아직 캐릭터가 없으면 nil → 생성 화면을 보여줘요.
    @State private var pet: Pet? = nil

    var body: some View {
        Group {
            if let pet {
                GameView(pet: pet)          // 캐릭터가 있으면 → 키우기 화면
            } else {
                CreationView { newPet in    // 없으면 → 만들기 화면
                    pet = newPet            // 다 만들면 여기로 새 캐릭터가 들어와요
                }
            }
        }
        .frame(width: 380, height: 600)
    }
}

#Preview {
    ContentView()
}
