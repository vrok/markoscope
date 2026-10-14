# AGENTS.md

Markoscope: a native macOS Markdown viewer (AppKit + a `WKWebView` page). Swift package, built
with the Xcode Command Line Tools — there is no Xcode project, and no `xcodebuild`/`actool`.

## Building

- `./run.sh [file.md]` builds `build/Markoscope.app` and opens it; `./run.sh --build-only` just builds.
- `./make-dmg.sh` builds a universal (arm64 + x86_64) app and `build/Markoscope-<version>.dmg`.
  Architectures are compiled one at a time and merged with `lipo` (multi-arch `swift build` needs Xcode).
- The app bundle is assembled by `run.sh` (Info.plist, web resources, icon, ad-hoc signature);
  don't add build steps elsewhere.
- `Resources/web/vendor/` (marked, DOMPurify, highlight.js, Mermaid) is downloaded by `run.sh`
  at pinned versions and is not committed. Change versions there, in `run.sh`.
- The app icon is generated from `icon.png` by `scripts/app-icon.swift` (fitted to Apple's icon
  shape so macOS 26 doesn't put it on a grey plate).

## Testing

- `./test.sh` runs the tests (also run by `release.sh`); run it after changing anything in
  `Resources/web/`.
- Syntax highlighting has golden-file tests: each `tests/highlighting/NAME.LANG` is highlighted
  as LANG by the app's own highlight.js and grammars (in JavaScriptCore) and compared with
  `NAME.LANG.tokens`. When changing a grammar, add or extend a sample, run `./test.sh --update`,
  and check the `.tokens` diff is what you intended before committing it.
- XCTest and Swift Testing don't work with only the Command Line Tools, so tests are Swift
  scripts run by `test.sh`.

## Versioning

- Versions come only from git tags `vMAJOR.MINOR.PATCH` on `main` (semantic versioning).
  Never put the app's version in code or `Resources/Info.plist` (it holds placeholders); the only
  place versions are written by hand is `CHANGELOG.md`.
- `run.sh` sets `CFBundleShortVersionString` to the latest tag, `CFBundleVersion` to the commit
  count, and `MarkoscopeVersion` to the `git describe` label (e.g. `0.1.0-3-g1a2b3c4-dirty`),
  which the About window and welcome window show.
- Every release has a `## X.Y.Z — YYYY-MM-DD` entry in `CHANGELOG.md`: succinct bullet points of
  user-visible changes, newest version first. Add a bullet under `## Unreleased` with each
  user-visible change; before releasing, rename that heading to the version and date and commit.
- Release with `./release.sh X.Y.Z`: it requires a clean `main` in sync with `origin/main` and the
  changelog entry, tags, builds the DMG, pushes the tag and creates the GitHub release (DMG,
  checksum, the changelog entry as notes). Don't tag or create releases by hand.

## Commits

- One commit per change, with a descriptive message.
- Push to `main` on GitHub; `git fetch` and rebase first, since the README is sometimes edited there.
- Never commit `build/`, `.build/`, `Resources/web/vendor/`, test files, or temporary debug code.
