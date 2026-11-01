#!/bin/bash
# Собирает GUI и упаковывает его в build/ssh-conn.app.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${1:-release}"
APP_NAME="ssh-conn"
BUNDLE="build/$APP_NAME.app"
ICON_SOURCE="Assets/ssh-conn-brand/icons/png/icon-light-1024.png"

if ! swift build -c "$CONFIGURATION" --product ssh-conn-gui; then
    echo "" >&2
    echo "Сборка GUI не удалась. Для SwiftUI в SDK macOS 26+ нужен Xcode:" >&2
    echo "его плагины макросов отсутствуют в Command Line Tools." >&2
    exit 1
fi

BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_PATH/ssh-conn-gui" "$BUNDLE/Contents/MacOS/ssh-conn-gui"

if [ -f "$ICON_SOURCE" ] && command -v iconutil >/dev/null 2>&1; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ru</string>
    <key>CFBundleDisplayName</key>
    <string>ssh-conn</string>
    <key>CFBundleExecutable</key>
    <string>ssh-conn-gui</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>dev.sshconn.gui</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ssh-conn</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - "$BUNDLE" >/dev/null 2>&1 || true
fi

echo "Готово: $BUNDLE"
echo "Запуск: open \"$BUNDLE\""
