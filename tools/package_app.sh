#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="InputLockBar"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ICON_BASE="$ROOT_DIR/Support/AppIcon-base.png"
ICONSET_DIR="$ROOT_DIR/Support/AppIcon.iconset"
ICNS_PATH="$ROOT_DIR/Support/AppIcon.icns"
CODE_SIGN_REQUIREMENT='=designated => identifier "local.vigor.InputLockBar"'

cd "$ROOT_DIR"

swift "$ROOT_DIR/tools/generate_app_icon.swift" "$ICON_BASE"

rm -rf "$ICONSET_DIR" "$ICNS_PATH"
mkdir -p "$ICONSET_DIR"

sips -z 16 16 "$ICON_BASE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_BASE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_BASE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_BASE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_BASE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_BASE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_BASE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_BASE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_BASE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_BASE" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

swift build -c release --product "$APP_NAME"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/Support/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$BUILD_DIR/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ICNS_PATH" "$APP_DIR/Contents/Resources/AppIcon.icns"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

codesign --force --deep --sign - --requirements "$CODE_SIGN_REQUIREMENT" "$APP_DIR" >/dev/null

echo "Packaged $APP_DIR"
