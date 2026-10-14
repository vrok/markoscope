#!/usr/bin/env bash
# Downloads the JavaScript libraries the page uses into Resources/web/vendor (once; they're
# bundled into the app so it works offline, and not committed). Used by run.sh and test.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/Resources/web/vendor"

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
