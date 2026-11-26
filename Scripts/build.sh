#!/usr/bin/env bash
#
# Собирает ScreenTap.app из исходников Swift.
#
#   Scripts/build.sh [--debug]
#
# Переменные окружения:
#   SCREENTAP_CODESIGN_IDENTITY — идентичность для codesign (по умолчанию ad-hoc: "-").
#                              С постоянной self-signed подписью разрешение «Запись экрана»
#                              переживает пересборку приложения.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="release"
if [[ "${1:-}" == "--debug" ]]; then
    CONFIG="debug"
fi

APP_NAME="ScreenTap"
BUILD_DIR="$ROOT/.build/$CONFIG"
APP_BUNDLE="$ROOT/build/$APP_NAME.app"

echo "==> Сборка ($CONFIG)"
swift build -c "$CONFIG"

echo "==> Сборка бандла $APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Scripts/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "    ! Resources/AppIcon.icns не найден — приложение соберётся без иконки"
fi

# Права на исполняемый файл
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

IDENTITY="${SCREENTAP_CODESIGN_IDENTITY:--}"
echo "==> Подпись ($IDENTITY)"
codesign --force --deep --sign "$IDENTITY" --options runtime "$APP_BUNDLE" 2>/dev/null \
    || codesign --force --deep --sign "$IDENTITY" "$APP_BUNDLE"

# Проверка, что бандл валиден
codesign --verify --verbose=1 "$APP_BUNDLE" 2>&1 | sed 's/^/    /' || true

echo
echo "Готово: $APP_BUNDLE"
echo "Запуск:  open '$APP_BUNDLE'"
echo "Перенос в /Applications:  cp -R '$APP_BUNDLE' /Applications/"
