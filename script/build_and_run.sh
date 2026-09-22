#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Kagami"
BUNDLE_ID="com.kagami.app"
MIN_SYSTEM_VERSION="14.0"
VERSION="${KAGAMI_VERSION:-0.2.1}"
CONFIGURATION="${KAGAMI_CONFIGURATION:-debug}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
UPDATE_FEED_URL="https://github.com/Azdmjiny/kagami/releases/latest/download/appcast.xml"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_FILE="$ROOT_DIR/Resources/Kagami.icns"

cd "$ROOT_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
swift build -c "$CONFIGURATION"
BUILD_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_CONTENTS/Resources"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$ICON_FILE" "$APP_CONTENTS/Resources/Kagami.icns"
# Bundle.module must resolve inside the app even after it leaves this checkout.
cp -R "$BUILD_DIR/Kagami_Kagami.bundle" "$APP_CONTENTS/Resources/"
mkdir -p "$APP_CONTENTS/Frameworks"
SPARKLE_FRAMEWORK="$BUILD_DIR/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  SPARKLE_FRAMEWORK="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
fi
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  echo "Sparkle.framework is missing; cannot package the app." >&2
  exit 1
fi
cp -R "$SPARKLE_FRAMEWORK" "$APP_CONTENTS/Frameworks/"
install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP_BINARY"
chmod +x "$APP_BINARY"
cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>CFBundleIconFile</key><string>Kagami</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>SUFeedURL</key><string>$UPDATE_FEED_URL</string>
<key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
<key>SUEnableAutomaticChecks</key><false/>
<key>SUAutomaticallyUpdate</key><false/>
</dict></plist>
PLIST

# The executable is adjusted to load bundled frameworks, which invalidates its
# build signature. Re-sign the complete development bundle after all copies.
codesign --force --deep --sign - "$APP_BUNDLE"

case "$MODE" in
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --package|package) ;;
  --debug|debug) lldb -- "$APP_BINARY" ;;
  --logs|logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  --telemetry|telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
  --verify|verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  *) echo "usage: $0 [run|--package|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
