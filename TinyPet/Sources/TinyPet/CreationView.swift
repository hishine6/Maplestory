import SwiftUI

// 캐릭터를 "만드는" 화면: 이름 짓기 + 종류 고르기.
struct CreationView: View {
    // 다 만들면 이 함수로 새 캐릭터를 부모(ContentView)에게 전달해요.
    var onCreate: (Pet) -> Void

    @State private var name = ""
    @State private var selectedType: PetType = .chick

    var body: some View {
        VStack(spacing: 22) {
            Text("나만의 캐릭터 만들기")
                .font(.title.bold())

            // 지금 고른 종류 미리보기
            Text(selectedType.previewEmoji)
                .font(.system(size: 90))

            // 이름 입력칸
            TextField("이름을 지어주세요", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)

            Text("종류 선택")
                .font(.headline)

            // 종류 버튼들 (가로로 나열)
            HStack(spacing: 10) {
                // ForEach = 목록을 돌면서 버튼을 자동으로 만들어줘요.
                ForEach(PetType.allCases) { type in
                    Button {
                        selectedType = type     // 누르면 이 종류로 선택
                    } label: {
                        VStack(spacing: 4) {
                            Text(type.previewEmoji).font(.largeTitle)
                            Text(type.displayName).font(.caption)
                        }
                        .padding(8)
                        .background(
                            selectedType == type     // 고른 것만 배경색 강조
                            ? Color.accentColor.opacity(0.25)
                            : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }

            // 시작 버튼
            Button("키우기 시작! 🚀") {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                let pet = Pet(name: trimmed.isEmpty ? "이름없음" : trimmed,
                              type: selectedType)
                onCreate(pet)               // 부모에게 "이 캐릭터로 시작!" 알림
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(30)
    }
}
