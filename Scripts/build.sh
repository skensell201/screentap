#!/usr/bin/env bash
#
# Builds ScreenTap.app from the Swift sources.
#
#   Scripts/build.sh [--debug]
#
# Environment variables:
#   SCREENTAP_CODESIGN_IDENTITY — identity passed to codesign (defaults to ad-hoc: "-").
#                              With a stable self-signed identity the screen recording
#                              permission survives rebuilding the app.
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

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"

echo "==> Assembling $APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Scripts/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "    ! Resources/AppIcon.icns is missing — the app will be built without an icon"
fi

chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

IDENTITY=""
if [[ -n "${SCREENTAP_CODESIGN_IDENTITY:-}" ]]; then
    IDENTITY="$SCREENTAP_CODESIGN_IDENTITY"
elif [[ -f "$ROOT/.signing-identity" ]]; then
    # Local, git ignored file with the identity to sign with.
    IDENTITY="$(head -n 1 "$ROOT/.signing-identity" | tr -d '\r')"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "ScreenTap SelfSigned"; then
    IDENTITY="ScreenTap SelfSigned"
else
    IDENTITY="-"
fi

echo "==> Signing ($IDENTITY)"
codesign --force --deep --sign "$IDENTITY" --options runtime "$APP_BUNDLE" 2>/dev/null \
    || codesign --force --deep --sign "$IDENTITY" "$APP_BUNDLE"

codesign --verify --verbose=1 "$APP_BUNDLE" 2>&1 | sed 's/^/    /' || true

echo
echo "Done: $APP_BUNDLE"
echo "Run:     open '$APP_BUNDLE'"
echo "Install: cp -R '$APP_BUNDLE' /Applications/"
