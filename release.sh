#!/usr/bin/env bash
# Publishes a Markoscope release: tags vX.Y.Z on main, builds the DMG for that tag and
# creates a GitHub release with it, a SHA-256 checksum, and the version's CHANGELOG.md entry
# as notes (the entry must exist and be committed first).
#
#   ./release.sh 0.2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

die() { echo "✗ $*" >&2; exit 1; }

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: ./release.sh X.Y.Z (e.g. 0.2.0)"
TAG="v$VERSION"

command -v gh >/dev/null || die "needs the GitHub CLI: brew install gh"
gh auth status >/dev/null 2>&1 || die "log in to GitHub first: gh auth login"
[[ "$(git branch --show-current)" == "main" ]] || die "releases are made from main"
[[ -z "$(git status --porcelain)" ]] || die "commit or stash your changes first"
git fetch -q origin main --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die "main differs from origin/main; pull or push first"
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || die "$TAG already exists"

# The "## X.Y.Z — date" section of CHANGELOG.md, without its heading.
CHANGES="$(awk -v version="$VERSION" '
  /^## / { if (found) exit; found = ($2 == version) ; next }
  found' CHANGELOG.md | sed -e '/./,$!d')"
[[ -n "$CHANGES" ]] || die "add a \"## $VERSION — $(date +%Y-%m-%d)\" entry to CHANGELOG.md and commit it first"

PREVIOUS="$(git tag --list 'v[0-9]*' --sort=-v:refname | head -1)"
if [[ -n "$PREVIOUS" ]]; then
  NEWEST="$(printf '%s\n%s\n' "${PREVIOUS#v}" "$VERSION" | sort -V | tail -1)"
  [[ "$NEWEST" == "$VERSION" && "$PREVIOUS" != "$TAG" ]] || die "$TAG must be newer than $PREVIOUS"
fi

echo "→ Tagging $TAG"
git tag -a "$TAG" -m "Markoscope $VERSION"
# Until the tag is pushed, a failed build leaves nothing behind.
trap 'git tag -d "$TAG" >/dev/null 2>&1; echo "✗ Release failed; tag $TAG removed" >&2' ERR

"$ROOT/make-dmg.sh"
DMG="$ROOT/build/Markoscope-$VERSION.dmg"
[[ -f "$DMG" ]] || die "expected $DMG"
(cd "$ROOT/build" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")

NOTES="$ROOT/build/release-notes.md"
{
  echo "$CHANGES"
  echo
  echo "## Installing"
  echo
  echo "Open the DMG and drag Markoscope to Applications. Runs on Apple silicon and Intel Macs (macOS 13 or later)."
  echo
  echo "The app isn't notarized by Apple, so macOS will refuse to open it at first: open it once,"
  echo "then choose **Open Anyway** in System Settings ▸ Privacy & Security. Or run:"
  echo
  echo '```'
  echo "xattr -dr com.apple.quarantine /Applications/Markoscope.app"
  echo '```'
} > "$NOTES"

echo "→ Pushing $TAG"
git push -q origin "$TAG"
trap - ERR

echo "→ Creating the GitHub release"
gh release create "$TAG" "$DMG" "$DMG.sha256" --title "Markoscope $VERSION" --notes-file "$NOTES" --verify-tag
echo "✓ Released $TAG"
