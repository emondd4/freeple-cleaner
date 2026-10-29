#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-1.0.0}"
APP_NAME="Freeple Cleaner"
DERIVED="${DERIVED:-/tmp/FreepleCleanerRelease}"
STAGE="/tmp/FreepleDMGStage-$$"
DIST="$ROOT/dist"
DMG_RW="/tmp/FreepleCleaner-rw-$$.dmg"
DMG_OUT="$DIST/FreepleCleaner-${VERSION}.dmg"

echo "==> Building Release (universal)"
rm -rf "$DERIVED"
xcodebuild \
  -project "$ROOT/MacCleaner.xcodeproj" \
  -scheme MacCleaner \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination 'generic/platform=macOS' \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS='arm64 x86_64' \
  PRODUCT_NAME="$APP_NAME" \
  INFOPLIST_KEY_CFBundleDisplayName="$APP_NAME" \
  build

APP_SRC="$DERIVED/Build/Products/Release/${APP_NAME}.app"
test -d "$APP_SRC"

echo "==> Signing (ad-hoc)"
codesign --force --deep --options runtime --sign - "$APP_SRC"

echo "==> Staging DMG contents"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"
ditto "$APP_SRC" "$STAGE/${APP_NAME}.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Install Instructions.txt" << EOF
${APP_NAME} — Install
=====================

1. Drag "${APP_NAME}" onto the Applications folder.
2. Open Applications → ${APP_NAME}.
3. If macOS blocks the app: System Settings → Privacy & Security → Open Anyway.
4. For best remapping results, grant Full Disk Access.

Source: https://github.com/emondd4/freeple-cleaner
EOF

echo "==> Creating DMG"
rm -f "$DMG_RW" "$DMG_OUT"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDRW "$DMG_RW"
hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUT"
rm -f "$DMG_RW"
rm -rf "$STAGE"

echo "==> Done: $DMG_OUT"
ls -lh "$DMG_OUT"
