#!/bin/bash
# Собирает CLI ssh-conn и упаковывает его в установщик build/ssh-conn-cli-<версия>.pkg.
# Пакет устанавливает бинарник в /usr/local/bin/ssh-conn.
#
# Использование: Scripts/build-cli-pkg.sh [debug|release] [версия]
# Переменные окружения:
#   INSTALLER_IDENTITY — сертификат Developer ID Installer для подписи пакета (иначе без подписи).
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${1:-release}"
VERSION="${2:-1.0}"
PKG="build/ssh-conn-cli-$VERSION.pkg"

swift build -c "$CONFIGURATION" --product ssh-conn
BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

mkdir -p "$STAGE_DIR/root/usr/local/bin"
ditto --noextattr --noqtn "$BIN_PATH/ssh-conn" "$STAGE_DIR/root/usr/local/bin/ssh-conn"
chmod 755 "$STAGE_DIR/root/usr/local/bin/ssh-conn"

rm -f "$PKG"
pkgbuild \
    --root "$STAGE_DIR/root" \
    --identifier dev.sshconn.cli \
    --version "$VERSION" \
    --install-location / \
    "$PKG"

# pkgbuild превращает расширенные атрибуты com.apple.provenance, которые macOS
# вешает на новые файлы, в AppleDouble-файлы ._*. Они установились бы рядом с
# утилитой, поэтому убираем их из payload и BOM и собираем пакет заново.
if pkgutil --payload-files "$PKG" | grep -q '^\./\._'; then
    WORK_DIR="$(mktemp -d)"
    pkgutil --expand "$PKG" "$WORK_DIR/pkg"
    mkdir "$WORK_DIR/payload"
    (cd "$WORK_DIR/payload" && gzip -dc "$WORK_DIR/pkg/Payload" | cpio -id --quiet)
    find "$WORK_DIR/payload" -name '._*' -delete

    (cd "$WORK_DIR/payload" \
        && find . -print | cpio -o -H odc -R root:wheel 2>/dev/null | gzip -c > "$WORK_DIR/pkg/Payload")

    lsbom "$WORK_DIR/pkg/Bom" | grep -v '/\._' > "$WORK_DIR/bomlist"
    mkbom -i "$WORK_DIR/bomlist" "$WORK_DIR/pkg/Bom"

    PAYLOAD_FILES="$(find "$WORK_DIR/payload" | wc -l | tr -d ' ')"
    PAYLOAD_KBYTES="$(du -sk "$WORK_DIR/payload" | cut -f1 | tr -d ' ')"
    sed -i '' -E \
        -e "s/numberOfFiles=\"[0-9]+\"/numberOfFiles=\"$PAYLOAD_FILES\"/" \
        -e "s/installKBytes=\"[0-9]+\"/installKBytes=\"$PAYLOAD_KBYTES\"/" \
        "$WORK_DIR/pkg/PackageInfo"

    pkgutil --flatten "$WORK_DIR/pkg" "$PKG"
    rm -rf "$WORK_DIR"
fi

# Проверяем, что в пакет попал именно бинарник CLI.
if ! pkgutil --payload-files "$PKG" | grep -qx "./usr/local/bin/ssh-conn"; then
    echo "Ошибка: в пакет не попал usr/local/bin/ssh-conn" >&2
    exit 1
fi

# Пакет подписывается после пересборки: flatten сбрасывает подпись.
if [ -n "${INSTALLER_IDENTITY:-}" ]; then
    productsign --sign "$INSTALLER_IDENTITY" "$PKG" "$PKG.signed" >/dev/null
    mv "$PKG.signed" "$PKG"
    pkgutil --check-signature "$PKG" >/dev/null
fi

echo "Готово: $PKG ($(du -h "$PKG" | cut -f1))"
