#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

echo "Building Slate (release)..."
swift build -c release --product Slate

BIN_PATH="$(swift build -c release --product Slate --show-bin-path)/Slate"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Slate.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$DIST_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/Slate"
chmod +x "$MACOS_DIR/Slate"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
swift "$ROOT_DIR/Resources/make_icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

codesign --force --deep --sign - "$APP_DIR"

(cd "$DIST_DIR" && ditto -c -k --sequesterRsrc --keepParent "Slate.app" "Slate.zip")

echo "Built: $APP_DIR"
echo "Zipped: $DIST_DIR/Slate.zip"
