#!/usr/bin/env bash
# Runs the tests: syntax highlighting is checked against the expected tokens in
# tests/highlighting/*.tokens.
#
#   ./test.sh            run the tests
#   ./test.sh --update   rewrite the expected tokens from the current output (review the diff!)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$ROOT/scripts/fetch-vendor.sh"
swift "$ROOT/tests/highlighting-tests.swift" "$ROOT" "$@"
