#!/bin/bash
# 코드 -> 더블클릭 가능한 JumpQuest.app 으로 묶어주는 스크립트.
set -e
cd "$(dirname "$0")"

APP="JumpQuest"          # 실행파일/SwiftPM 타깃 이름 (유지)
NAME="bamtistory"        # 앱 표시 이름
BUNDLE="$NAME.app"

echo "▶︎ 1/4 릴리즈 빌드 중..."
swift build -c release

echo "▶︎ 2/4 .app 폴더 구조 만드는 중..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

echo "▶︎ 3/4 실행파일 · 설정 · 아이콘 넣는 중..."
cp ".build/release/$APP" "$BUNDLE/Contents/MacOS/$APP"
cp Info.plist "$BUNDLE/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
# SwiftPM 리소스 번들 통째로 복사 (release 바이너리가 찾는 그대로 — frameTex 1순위 경로)
cp -R ".build/release/$APP"_"$APP.bundle" "$BUNDLE/Contents/Resources/" 2>/dev/null || true
# 게임 데이터(JSON)·캐릭터 이미지도 loose로도 넣기 (frameTex fallback)
cp Sources/JumpQuest/monsters.json "$BUNDLE/Contents/Resources/monsters.json"
cp Sources/JumpQuest/skills.json   "$BUNDLE/Contents/Resources/skills.json"
cp Sources/JumpQuest/items.json    "$BUNDLE/Contents/Resources/items.json"
cp -R Sources/JumpQuest/sprites "$BUNDLE/Contents/Resources/sprites"

echo "▶︎ 4/4 로컬용 서명 중..."
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || true

echo "✅ 완료: $(pwd)/$BUNDLE"
echo "   더블클릭하거나 'open $BUNDLE' 로 실행하세요."
