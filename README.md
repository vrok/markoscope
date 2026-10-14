<p align="center">
  <img src="icon.png" width="160" alt="Markoscope icon">
</p>

<h1 align="center">Markoscope</h1>

<p align="center">A small, native macOS app for reading Markdown.</p>

<p align="center">Vibe-coded for personal use, but published for everyone who wants to save some time &amp; tokens.</p>

## Features

- **Nice themes**: Reader, Clean, Sepia and Night
- **Mermaid diagrams** from ` ```mermaid ` code blocks
- **Live reload**: save the file in any editor and the window updates in place
- **Change history**: every version of the file, with what changed highlighted in red and green
- **Folders**: open a folder to browse its Markdown files in a sidebar, each opening in a tab

## Installing

Download the DMG from [Releases](https://github.com/vrok/markoscope/releases), open it and drag Markoscope to Applications.

The app isn't notarized by Apple, so macOS blocks it the first time: open it, click **Done**, then go to **System Settings ▸ Privacy & Security** and click **Open Anyway** next to the Markoscope message. After that it opens normally.

## Build & run

Requires macOS 13+ and the Xcode Command Line Tools.

```bash
./run.sh                  # build, then open examples/sample.md
./run.sh notes/todo.md    # build, then open a file
./run.sh --build-only     # just build build/Markoscope.app
./make-dmg.sh             # build/Markoscope-<version>.dmg, for Apple silicon and Intel
```

The first build downloads the JavaScript libraries (marked, DOMPurify, highlight.js, Mermaid) into `Resources/web/vendor`. After that, the app works offline.

Releases are tagged `vX.Y.Z` and published on GitHub with a DMG by `./release.sh X.Y.Z`; the app's version comes from those tags.

## Settings

Settings are kept in `~/.markoscope/config.toml`, and recently opened files in `~/.markoscope/history`:

```toml
theme = "reader"      # reader, clean, sepia, night
font_size = 18        # 12–32
outline_pane = false
history_pane = true
show_changes = false
merge_window = 5      # seconds; changes this close together count as one version
recent_files = 5      # files listed in the welcome window and File ▸ Open Recent
```

You can edit the file by hand. The app rewrites it whenever you change a setting, so comments you add won't be kept.

## How it works

The app is AppKit with one `WKWebView` per document window. The Swift side ([Sources/markoscope](Sources/markoscope)) handles files, windows, menus, version history and settings. The page in [Resources/web](Resources/web) turns Markdown into HTML, draws the diagrams, and highlights changes between versions ([diff.js](Resources/web/diff.js)). All theme styling lives in [style.css](Resources/web/style.css).
