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
ICON="$BUILD_DIR/AppIcon.icns"

"$ROOT/scripts/fetch-vendor.sh"

# The app icon is built from icon.png, fitted to Apple's icon shape (rebuilt when either changes).
if [[ ! -f "$ICON" || "$ROOT/icon.png" -nt "$ICON" || "$ROOT/scripts/app-icon.swift" -nt "$ICON" ]]; then
  echo "→ Building app icon"
  ICONSET="$BUILD_DIR/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  swift "$ROOT/scripts/app-icon.swift" "$ROOT/icon.png" "$BUILD_DIR/AppIcon-1024.png"
  for size in 16 32 128 256 512; do
    sips -z $size $size "$BUILD_DIR/AppIcon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$BUILD_DIR/AppIcon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$ICON"
fi

# ARCHS="arm64 x86_64" builds a universal app (make-dmg.sh does); by default, just this Mac's.
# Each architecture is compiled on its own and the results merged with lipo.
echo "→ Compiling"
if [[ -n "${ARCHS:-}" ]]; then
  SLICES=()
  for arch in $ARCHS; do
    swift build -c release --package-path "$ROOT" --arch "$arch"
    SLICES+=("$(swift build -c release --package-path "$ROOT" --arch "$arch" --show-bin-path)/$EXECUTABLE")
  done
  BINARY="$BUILD_DIR/$EXECUTABLE"
  mkdir -p "$BUILD_DIR"
  lipo -create "${SLICES[@]}" -output "$BINARY"
else
  swift build -c release --package-path "$ROOT"
  BINARY="$(swift build -c release --package-path "$ROOT" --show-bin-path)/$EXECUTABLE"
fi

# The version comes from git tags (vX.Y.Z, see release.sh): the latest tag is the version,
# the commit count the build number, and builds after a tag are labelled like git describe
# (e.g. 0.1.0-3-g1a2b3c4, plus -dirty for uncommitted changes).
TAG="$(git -C "$ROOT" describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null || echo v0.0.0)"
VERSION="${TAG#v}"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 0)"
VERSION_LABEL="$(git -C "$ROOT" describe --tags --match 'v[0-9]*' --dirty 2>/dev/null || true)"
if [[ -z "$VERSION_LABEL" ]]; then
  VERSION_LABEL="$VERSION-g$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  git -C "$ROOT" diff --quiet HEAD 2>/dev/null || VERSION_LABEL+="-dirty"
fi
VERSION_LABEL="${VERSION_LABEL#v}"

echo "→ Assembling $APP_NAME.app ($VERSION_LABEL)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD_NUMBER" \
  -c "Add :MarkoscopeVersion string $VERSION_LABEL" "$PLIST"
cp "$ICON" "$APP/Contents/Resources/"
cp -R "$ROOT/Resources/web" "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null 2>&1
touch "$APP" # so Finder and the Dock pick up a changed icon
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
