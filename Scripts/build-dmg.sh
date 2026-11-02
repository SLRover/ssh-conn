#!/bin/bash
# Собирает ssh-conn.app и установщик CLI, упаковывает их в образ build/ssh-conn-<версия>.dmg.
#
# Переменные окружения:
#   CODESIGN_IDENTITY — сертификат Developer ID Application для подписи приложения (иначе ad-hoc);
#   INSTALLER_IDENTITY — сертификат Developer ID Installer для подписи пакета CLI
#                        (обязателен при NOTARIZE=1);
#   NOTARIZE=1, APPLE_ID, TEAM_ID, NOTARY_PASSWORD — нотаризация через xcrun notarytool.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${1:-release}"
APP="build/ssh-conn.app"
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"

if [ "${NOTARIZE:-0}" = "1" ] && [ -z "${INSTALLER_IDENTITY:-}" ]; then
    echo "Для нотаризации укажите INSTALLER_IDENTITY (сертификат Developer ID Installer)." >&2
    exit 1
fi

./Scripts/build-app.sh "$CONFIGURATION"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="build/ssh-conn-$VERSION.dmg"
CLI_PKG="build/ssh-conn-cli-$VERSION.pkg"
CLI_PKG_NAME="Install CLI.pkg"

./Scripts/build-cli-pkg.sh "$CONFIGURATION" "$VERSION"

if [ -n "$SIGN_IDENTITY" ]; then
    echo "Подписываю приложение: $SIGN_IDENTITY"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

STAGE_DIR="$(mktemp -d)"
MOUNT_DIR=""
if diskutil image --help >/dev/null 2>&1; then
    HAS_DISKUTIL_IMAGE=1
else
    HAS_DISKUTIL_IMAGE=0
fi
cleanup() {
    if [ -n "$MOUNT_DIR" ]; then
        if [ "$HAS_DISKUTIL_IMAGE" = 1 ]; then
            diskutil eject "$MOUNT_DIR" >/dev/null 2>&1 || true
        else
            hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
        fi
    fi
    rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

# Прячет прогресс diskutil/hdiutil, но показывает вывод при ошибке.
run_quiet() {
    local log
    log="$(mktemp)"
    if ! "$@" >/dev/null 2>"$log"; then
        cat "$log" >&2
        rm -f "$log"
        return 1
    fi
    rm -f "$log"
}

ditto "$APP" "$STAGE_DIR/ssh-conn.app"
cp "$CLI_PKG" "$STAGE_DIR/$CLI_PKG_NAME"
ln -s /Applications "$STAGE_DIR/Applications"

rm -f "$DMG"
if [ "$HAS_DISKUTIL_IMAGE" = 1 ]; then
    run_quiet diskutil image create from \
        --format UDZO \
        --volumeName "ssh-conn $VERSION" \
        "$STAGE_DIR" "$DMG"
else
    run_quiet hdiutil create \
        -volname "ssh-conn $VERSION" \
        -srcfolder "$STAGE_DIR" \
        -format UDZO \
        -ov \
        "$DMG"
fi

if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

# Проверяем, что образ читается и содержит приложение, установщик CLI и ярлык Applications.
run_quiet hdiutil verify "$DMG"
MOUNT_DIR="$(mktemp -d)"
if [ "$HAS_DISKUTIL_IMAGE" = 1 ]; then
    run_quiet diskutil image attach --readOnly --nobrowse --mountPoint "$MOUNT_DIR" "$DMG"
else
    run_quiet hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT_DIR"
fi
test -d "$MOUNT_DIR/ssh-conn.app"
test -f "$MOUNT_DIR/$CLI_PKG_NAME"
test -L "$MOUNT_DIR/Applications"
pkgutil --payload-files "$MOUNT_DIR/$CLI_PKG_NAME" | grep -qx "./usr/local/bin/ssh-conn"
if [ "$HAS_DISKUTIL_IMAGE" = 1 ]; then
    run_quiet diskutil eject "$MOUNT_DIR"
else
    run_quiet hdiutil detach "$MOUNT_DIR"
fi
MOUNT_DIR=""
echo "Образ проверен: контрольная сумма и содержимое корректны."

if [ "${NOTARIZE:-0}" = "1" ]; then
    : "${APPLE_ID:?Укажите APPLE_ID для нотаризации}"
    : "${TEAM_ID:?Укажите TEAM_ID для нотаризации}"
    : "${NOTARY_PASSWORD:?Укажите NOTARY_PASSWORD (app-specific password)}"
    xcrun notarytool submit "$DMG" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$NOTARY_PASSWORD" \
        --wait
    xcrun stapler staple "$DMG"
fi

echo "Готово: $DMG ($(du -h "$DMG" | cut -f1))"
echo "Установка: перетащите ssh-conn в Applications, затем запустите \"$CLI_PKG_NAME\","
echo "чтобы установить консольную утилиту ssh-conn в /usr/local/bin."
