#!/usr/bin/env bash
#
# Готовит иконку приложения: масштабирует исходный PNG до 1024x1024 с полями,
# раскладывает по размерам и собирает Resources/AppIcon.icns.
#
#   Scripts/make-icon.sh [исходный.png]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SOURCE="${1:-$ROOT/Resources/icon-source.png}"
if [[ ! -f "$SOURCE" ]]; then
    echo "Не найден исходник иконки: $SOURCE" >&2
    exit 1
fi

WORK="$ROOT/.build/icon"
rm -rf "$WORK"
mkdir -p "$WORK/AppIcon.iconset"

echo "==> Подготовка полотна 1024x1024"
swift "$ROOT/Scripts/pad-icon.swift" "$SOURCE" "$WORK/icon-1024.png"

echo "==> Генерация размеров"
make_size() {
    local size="$1" name="$2"
    sips -z "$size" "$size" "$WORK/icon-1024.png" --out "$WORK/AppIcon.iconset/$name" >/dev/null
}

make_size 16   "icon_16x16.png"
make_size 32   "icon_16x16@2x.png"
make_size 32   "icon_32x32.png"
make_size 64   "icon_32x32@2x.png"
make_size 128  "icon_128x128.png"
make_size 256  "icon_128x128@2x.png"
make_size 256  "icon_256x256.png"
make_size 512  "icon_256x256@2x.png"
make_size 512  "icon_512x512.png"
make_size 1024 "icon_512x512@2x.png"
cp "$WORK/icon-1024.png" "$WORK/AppIcon.iconset/icon_1024x1024.png"

echo "==> Сборка .icns"
iconutil -c icns "$WORK/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
cp "$WORK/icon-1024.png" "$ROOT/Resources/icon-1024.png"

echo "Готово: $ROOT/Resources/AppIcon.icns"
