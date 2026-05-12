#!/usr/bin/env bash
# Builds Diarize.app — a proper macOS app bundle so macOS can persist mic /
# screen-recording permissions and so the app shows up in
# Systemeinstellungen → Datenschutz & Sicherheit.
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
BUNDLE_ID="eu.tty7.diarize"
EXECUTABLE_NAME="Diarize"

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
    <key>NSMicrophoneUsageDescription</key>
    <string>Diarize nimmt dein Mikrofon für Meeting-Aufnahmen auf, die lokal transkribiert und archiviert werden.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Diarize nimmt System-Audio (z.B. aus Online-Meetings) zur lokalen Transkription auf. Bildschirminhalte werden nicht gespeichert.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Diarize benötigt keine AppleScript-Interaktion.</string>
</dict>
</plist>
EOF

echo "→ Ad-hoc code signing (so macOS can track permissions for this binary)"
codesign --force --sign - --deep --options runtime --timestamp=none "$APP_DIR" 2>/dev/null || \
    codesign --force --sign - --deep "$APP_DIR"

echo "✓ Built $APP_DIR"

if [[ "${1:-}" == "--install" ]]; then
    DEST="/Applications/Diarize.app"
    echo "→ Installing to $DEST"
    rm -rf "$DEST"
    cp -R "$APP_DIR" "$DEST"
    echo "✓ Installed. Start with: open '$DEST'"
else
    echo ""
    echo "Start mit:  open '$APP_DIR'"
    echo "Installieren: $0 --install"
fi
