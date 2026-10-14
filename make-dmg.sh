#!/usr/bin/env bash
# Builds a universal (Apple silicon + Intel) Markoscope.app and packages it as
# build/Markoscope-<version>.dmg (version from git, see run.sh), with a shortcut to
# Applications to drag it onto.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/build/Markoscope.app"

ARCHS="arm64 x86_64" "$ROOT/run.sh" --build-only

VERSION="$(/usr/libexec/PlistBuddy -c "Print :MarkoscopeVersion" "$APP/Contents/Info.plist")"
DMG="$ROOT/build/Markoscope-$VERSION.dmg"
STAGING="$ROOT/build/dmg"

echo "→ Packaging $(basename "$DMG")"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
# The mounted disk shows the app's icon.
cp "$ROOT/build/AppIcon.icns" "$STAGING/.VolumeIcon.icns"
if command -v SetFile >/dev/null; then SetFile -a C "$STAGING"; fi

hdiutil create -volname "Markoscope" -srcfolder "$STAGING" -fs HFS+ -format UDZO \
  -imagekey zlib-level=9 -ov "$DMG" >/dev/null
rm -rf "$STAGING"
echo "✓ Built $DMG"
