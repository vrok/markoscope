#!/usr/bin/env bash
# Builds "Markoscope.app" into ./build and launches it.
#
#   ./run.sh                 build, then open examples/sample.md
#   ./run.sh path/to/file.md build, then open that file
#   ./run.sh --build-only    just build
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Markoscope"
EXECUTABLE="markoscope"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
VENDOR="$ROOT/Resources/web/vendor"
ICON="$ROOT/Resources/AppIcon.icns"

# JavaScript libraries are downloaded once and bundled, so the app works offline.
fetch() {
  local url="$1" dest="$VENDOR/$2"
  [[ -s "$dest" ]] && return
  echo "→ Downloading $2"
  curl -fsSL "$url" -o "$dest.tmp"
  mv "$dest.tmp" "$dest"
}
mkdir -p "$VENDOR"
fetch "https://cdn.jsdelivr.net/npm/marked@12.0.2/marked.min.js" marked.min.js
fetch "https://cdn.jsdelivr.net/npm/dompurify@3.1.6/dist/purify.min.js" purify.min.js
fetch "https://cdn.jsdelivr.net/npm/@highlightjs/cdn-assets@11.9.0/highlight.min.js" highlight.min.js
fetch "https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js" mermaid.min.js

if [[ ! -f "$ICON" ]]; then
  echo "→ Generating app icon"
  ICONSET="$BUILD_DIR/AppIcon.iconset"
  rm -rf "$ICONSET"
  swift "$ROOT/scripts/make-icon.swift" "$ICONSET"
  iconutil -c icns "$ICONSET" -o "$ICON"
fi

echo "→ Compiling"
swift build -c release --package-path "$ROOT"
BIN_DIR="$(swift build -c release --package-path "$ROOT" --show-bin-path)"

echo "→ Assembling $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/"
cp "$ICON" "$APP/Contents/Resources/"
cp -R "$ROOT/Resources/web" "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "✓ Built $APP"

[[ "${1:-}" == "--build-only" ]] && exit 0

# Quit a previous instance so the freshly built binary is the one that runs.
if pgrep -x "$EXECUTABLE" >/dev/null; then
  pkill -x "$EXECUTABLE" || true
  for _ in {1..50}; do pgrep -x "$EXECUTABLE" >/dev/null || break; sleep 0.1; done
fi

FILE="${1:-$ROOT/examples/sample.md}"
echo "→ Opening $FILE"
open -a "$APP" "$FILE"
