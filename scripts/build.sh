#!/bin/bash
# Builds YUCE ZIP.app and a distributable DMG locally.
#   ./scripts/build.sh            -> build/YUCE ZIP.app + dist/YUCE-ZIP-<version>.dmg
# Requirements: Xcode command line tools, 7-Zip (brew install sevenzip)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP_NAME="YUCE ZIP"
BUNDLE_ID="com.bariscagriyuce.yucezip"
VERSION="$(cat VERSION | tr -d '[:space:]')"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
APP="$BUILD_DIR/$APP_NAME.app"
DMG="$DIST_DIR/YUCE-ZIP-$VERSION.dmg"

# Locate the 7-Zip engine (7zz)
SEVENZIP="${SEVENZIP:-}"
if [[ -z "$SEVENZIP" ]]; then
  for c in "$(brew --prefix sevenzip 2>/dev/null)/bin/7zz" /opt/homebrew/bin/7zz /usr/local/bin/7zz; do
    [[ -x "$c" ]] && SEVENZIP="$c" && break
  done
fi
[[ -x "$SEVENZIP" ]] || { echo "7zz not found. Install with: brew install sevenzip"; exit 1; }
echo "==> Using 7-Zip engine: $SEVENZIP"

echo "==> Compiling (release)"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/YuceZip"

echo "==> Creating app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/YuceZip"
cp "$SEVENZIP" "$APP/Contents/Resources/7zz"
chmod 755 "$APP/Contents/Resources/7zz"
cp "$ROOT/Resources/7-Zip-License.txt" "$APP/Contents/Resources/" 2>/dev/null || true

echo "==> Generating icon"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
swift "$ROOT/scripts/make_icon.swift" "$BUILD_DIR/icon_1024.png" >/dev/null
for s in 16 32 128 256 512; do
  sips -z $s $s "$BUILD_DIR/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s*2))
  sips -z $d $d "$BUILD_DIR/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Writing Info.plist"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD_NUMBER/g" -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" \
  "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --options runtime "$APP/Contents/Resources/7zz"
codesign --force --sign - --options runtime "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Building DMG"
mkdir -p "$DIST_DIR"
STAGE="$BUILD_DIR/dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
rm -rf "$STAGE"

echo ""
echo "App: $APP"
echo "DMG: $DMG"
