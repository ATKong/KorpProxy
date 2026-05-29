#!/usr/bin/env bash
#
# build-engine.sh — build the KorpProxy engine (Go) and stage it for the app.
#
#   ./app/scripts/build-engine.sh                 # dev: writes app/.engine-bin/korpproxy-server
#   ./app/scripts/build-engine.sh --bundle <APP>  # also embed into <APP>/Contents/Resources
#
# The dev path is what ProxyManager.binaryURL() falls back to when the binary
# isn't bundled, so a plain run is enough to drive the app from Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" # repo root
cd "$ROOT"

OUT="$ROOT/app/.engine-bin/korpproxy-server"
mkdir -p "$(dirname "$OUT")"

# Are we running inside an Xcode build phase? (Xcode sets these.)
UNDER_XCODE="${BUILT_PRODUCTS_DIR:-}"

# Xcode build phases run with a minimal PATH, so locate `go` explicitly.
find_go() {
  if command -v go >/dev/null 2>&1; then command -v go; return 0; fi
  for c in /opt/homebrew/bin/go /usr/local/bin/go /usr/local/go/bin/go "$HOME/go/bin/go"; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

BUNDLE_APP=""
if [ "${1:-}" = "--bundle" ] && [ -n "${2:-}" ]; then BUNDLE_APP="$2"; fi

if GO_BIN="$(find_go)"; then
  echo "▸ $GO_BIN build ./cmd/server → $OUT"
  "$GO_BIN" build -o "$OUT" ./cmd/server
  echo "✓ engine built"
elif [ -x "$OUT" ]; then
  echo "warning: 'go' not found; bundling existing $OUT" >&2
else
  echo "warning: 'go' not found and no prebuilt engine at $OUT" >&2
  # Don't fail the Xcode build — the app falls back to the dev binary path.
  [ -n "$UNDER_XCODE" ] && { echo "warning: skipping engine bundling" >&2; exit 0; }
  echo "error: install Go (brew install go) or prebuild the engine first" >&2
  exit 1
fi

if [ -n "$BUNDLE_APP" ]; then
  resources="$BUNDLE_APP/Contents/Resources"
  mkdir -p "$resources"
  cp "$OUT" "$resources/korpproxy-server"
  chmod +x "$resources/korpproxy-server"
  echo "✓ embedded into $resources/korpproxy-server"
fi
