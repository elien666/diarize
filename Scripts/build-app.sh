#!/usr/bin/env bash
# Builds Diarize.app — a proper macOS app bundle so macOS can persist mic /
# screen-recording permissions and so the app shows up in
# System Settings → Privacy & Security.
#
# Usage:
#   ./Scripts/build-app.sh                # builds to ./build/Diarize.app
#   ./Scripts/build-app.sh --install      # also copies to /Applications
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/Diarize.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
BUNDLE_ID="de.tty7.diarize"
EXECUTABLE_NAME="Diarize"

echo "→ Build icon"
"$ROOT_DIR/Scripts/build-icon.sh"

echo "→ swift build (release)"
cd "$ROOT_DIR"
swift build -c release --product diarize-app

BIN="$ROOT_DIR/.build/release/diarize-app"
if [[ ! -x "$BIN" ]]; then
    echo "✗ Built binary not found at $BIN" >&2
    exit 1
fi

echo "→ Assembling app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RES"
cp "$BIN" "$MACOS/$EXECUTABLE_NAME"
chmod +x "$MACOS/$EXECUTABLE_NAME"

ICON_SRC="$ROOT_DIR/Resources/icon/Diarize.icns"
if [[ -f "$ICON_SRC" ]]; then
    cp "$ICON_SRC" "$RES/Diarize.icns"
fi

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>de</string>
    <key>CFBundleDisplayName</key><string>Diarize</string>
    <key>CFBundleName</key><string>Diarize</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleIconFile</key><string>Diarize</string>
    <key>CFBundleIconName</key><string>Diarize</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Diarize records your microphone for meeting recordings that are transcribed and archived locally.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Diarize records system audio (e.g. from online meetings) for local transcription. Screen contents are not saved.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Diarize does not require AppleScript interaction.</string>
</dict>
</plist>
EOF


# ── Code signing ───────────────────────────────────────────────────────────────
# TCC (Privacy permissions) tracks apps by their "designated requirement" (DR).
# Ad-hoc signing without an explicit DR defaults to the binary hash, which
# changes on every build → permissions reset every time.
#
# Fix: pin the DR to the bundle identifier. This is stable across rebuilds
# regardless of whether a named identity exists in the keychain.
DR="identifier \"$BUNDLE_ID\""

SIGN_IDENTITY="Diarize Local Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$SIGN_IDENTITY\""; then
    echo "→ Code signing with '$SIGN_IDENTITY'"
    codesign --force --sign "$SIGN_IDENTITY" \
        --requirements "=designated => $DR" \
        --deep --timestamp=none "$APP_DIR"
else
    echo "→ Code signing (ad-hoc with stable bundle-ID designated requirement)"
    codesign --force --sign - \
        --requirements "=designated => $DR" \
        --deep --timestamp=none "$APP_DIR"
fi

echo "✓ Built $APP_DIR"

if [[ "${1:-}" == "--install" ]]; then
    DEST="/Applications/Diarize.app"
    echo "→ Installing to $DEST"
    rm -rf "$DEST"
    cp -R "$APP_DIR" "$DEST"
    echo "✓ Installed. Start with: open '$DEST'"
else
    echo ""
    echo "Start with:  open '$APP_DIR'"
    echo "Install:     $0 --install"
fi
