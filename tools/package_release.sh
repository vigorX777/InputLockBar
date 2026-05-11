#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="InputLockBar"
VERSION="${1:-v0.1.0}"
RELEASE_DIR="$ROOT_DIR/release"
ARCHIVE_PATH="$RELEASE_DIR/${APP_NAME}-${VERSION}-macOS.zip"

cd "$ROOT_DIR"

./tools/package_app.sh

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

ditto -c -k --sequesterRsrc --keepParent "dist/${APP_NAME}.app" "$ARCHIVE_PATH"

echo "Packaged release archive $ARCHIVE_PATH"
