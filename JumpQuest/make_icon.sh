#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "▶︎ 1/3 아이콘 그리는 중 (CoreGraphics)..."
swift make_icon.swift AppIcon1024.png

echo "▶︎ 2/3 여러 크기로 변환 중..."
ICONSET="AppIcon.iconset"
rm -rf "$ICONSET"; mkdir "$ICONSET"
sips -z 16 16   AppIcon1024.png --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32   AppIcon1024.png --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32   AppIcon1024.png --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64   AppIcon1024.png --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128 AppIcon1024.png --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256 AppIcon1024.png --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 AppIcon1024.png --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512 AppIcon1024.png --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 AppIcon1024.png --out "$ICONSET/icon_512x512.png"    >/dev/null
cp AppIcon1024.png "$ICONSET/icon_512x512@2x.png"

echo "▶︎ 3/3 .icns로 합치는 중..."
iconutil -c icns "$ICONSET" -o AppIcon.icns
echo "✅ AppIcon.icns 생성 완료"
