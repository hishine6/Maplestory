#!/bin/bash
# 코드 -> 더블클릭 가능한 'Daily Punchclock' 앱으로 묶어주는 스크립트.
# 코드를 바꿀 때마다 이 스크립트만 다시 돌리면 .app이 갱신돼요.
set -e
cd "$(dirname "$0")"

APP="FocusTimer"               # SwiftPM 타깃/빌드 산출 바이너리 이름(내부)
BUNDLE="DailyPunchclock.app"   # 만들 앱 번들 이름(보이는 이름은 Info.plist의 Daily Punchclock)

echo "▶︎ 1/4 릴리즈 빌드 중 (최적화된 버전)..."
swift build -c release

echo "▶︎ 2/4 .app 폴더 구조 만드는 중..."
rm -rf "$BUNDLE" "FocusTimer.app"   # 옛 이름 번들도 정리
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

echo "▶︎ 3/4 실행파일 · 설정 · 아이콘 넣는 중..."
cp ".build/release/$APP" "$BUNDLE/Contents/MacOS/$APP"
cp Info.plist "$BUNDLE/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"

echo "▶︎ 4/4 로컬용 서명 중..."
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || true

echo "✅ 완료: $(pwd)/$BUNDLE"
echo "   더블클릭하거나 'open $BUNDLE' 로 실행하세요."
