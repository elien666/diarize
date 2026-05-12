#!/usr/bin/env bash
# Renders Resources/icon/diarize-icon.svg into a macOS .icns at
# Resources/icon/Diarize.icns. Idempotent.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT_DIR/Resources/icon/diarize-icon.svg"
ICONSET="$ROOT_DIR/Resources/icon/Diarize.iconset"
OUT="$ROOT_DIR/Resources/icon/Diarize.icns"

if [[ ! -f "$SRC" ]]; then
    echo "✗ Source SVG missing: $SRC" >&2
    exit 1
fi

# Skip rebuild if icns is newer than the SVG.
if [[ -f "$OUT" && "$OUT" -nt "$SRC" ]]; then
    echo "✓ Icon up-to-date: $OUT"
    exit 0
fi

echo "→ Rendering icon variants from $SRC"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

render() {
    local size=$1 name=$2
    sips -s format png -z "$size" "$size" "$SRC" --out "$ICONSET/$name" >/dev/null
}

render 16    icon_16x16.png
render 32    icon_16x16@2x.png
render 32    icon_32x32.png
render 64    icon_32x32@2x.png
render 128   icon_128x128.png
render 256   icon_128x128@2x.png
render 256   icon_256x256.png
render 512   icon_256x256@2x.png
render 512   icon_512x512.png
render 1024  icon_512x512@2x.png

echo "→ Packing iconset → $OUT"
iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$ICONSET"
echo "✓ Built $OUT"
