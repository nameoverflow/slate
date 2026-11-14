#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-auto}"
CERT_NAME="${CERT_NAME:-Slate Local Code Signing}"

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

LOCAL_ID="$(sh "$ROOT_DIR/Scripts/resolve-codesign-identity.sh" "$CODESIGN_IDENTITY" "$CERT_NAME")"
echo "Signing $APP_DIR with identity: $LOCAL_ID"
codesign --force --deep --sign "$LOCAL_ID" "$APP_DIR"

DIST_ID="$(sh "$ROOT_DIR/Scripts/resolve-codesign-identity.sh" dist "$CERT_NAME")"
if [ "$DIST_ID" = "$LOCAL_ID" ]; then
    (cd "$DIST_DIR" && ditto -c -k --sequesterRsrc --keepParent "Slate.app" "Slate.zip")
else
    TMP_DIST="$DIST_DIR/dist-pkg"
    mkdir -p "$TMP_DIST"
    ditto "$APP_DIR" "$TMP_DIST/Slate.app"
    codesign --force --deep --sign "$DIST_ID" "$TMP_DIST/Slate.app"
    (cd "$TMP_DIST" && ditto -c -k --sequesterRsrc --keepParent "Slate.app" "$DIST_DIR/Slate.zip")
    rm -rf "$TMP_DIST"
fi

echo "Built: $APP_DIR"
echo "Zipped: $DIST_DIR/Slate.zip"
