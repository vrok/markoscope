# Markoscope

A small, native macOS app for reading Markdown.

## Features

- **Nice themes**: Reader, Clean, Sepia and Night
- **Mermaid diagrams** from ` ```mermaid ` code blocks
- **Live reload**: save the file in any editor and the window updates in place

## Build & run

Requires macOS 13+ and the Xcode Command Line Tools.

```bash
./run.sh                  # build, then open examples/sample.md
./run.sh notes/todo.md    # build, then open a file
./run.sh --build-only     # just build build/Markoscope.app
```

The first build downloads the JavaScript libraries (marked, DOMPurify, highlight.js, Mermaid) into `Resources/web/vendor`. After that, the app works offline.

## Settings

The last-used theme and text size are kept in `~/.markoscope.toml`:

```toml
theme = "reader"   # reader, clean, sepia, night
font_size = 18     # 12–32
```

You can edit the file by hand. The app rewrites it whenever you change a setting, so comments you add won't be kept.

## How it works

The app is AppKit with one `WKWebView` per document window. The Swift side ([Sources/markoscope](Sources/markoscope)) handles files, windows, menus and settings. The page in [Resources/web](Resources/web) turns Markdown into HTML and draws the diagrams. All theme styling lives in [style.css](Resources/web/style.css).
