#!/bin/bash
# SwiftPM の実行ファイルを macOS のアプリバンドルに包む。
# バンドルにしないと Dock に出ず、アプリとして扱われない。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="IrodoriStudio"
APP="$ROOT/build/$APP_NAME.app"

cd "$ROOT"
swift build -c release --product IrodoriStudio
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/IrodoriStudio" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>Irodori Studio</string>
    <key>CFBundleIdentifier</key><string>dev.kohey.irodoristudio</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Phase 1 はモックなので、ダミー音声をバンドルに入れる
cp -R "$ROOT/Resources/DummyAudio" "$APP/Contents/Resources/"

# Phase 2: Python ワーカースクリプトもバンドルに入れる（配布時は AppPaths.workerScript がこちらを見つける）
cp "$ROOT/python/irodori_worker.py" "$APP/Contents/Resources/"

# 署名なしだと Gatekeeper に弾かれるので ad-hoc 署名する。
codesign --force --sign - "$APP" || echo "警告: ad-hoc 署名に失敗しました"

echo "作成しました: $APP"
echo "起動: open \"$APP\""
