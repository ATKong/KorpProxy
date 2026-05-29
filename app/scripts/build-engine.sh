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

echo "▸ go build ./cmd/server → $OUT"
go build -o "$OUT" ./cmd/server
echo "✓ engine built"

if [ "${1:-}" = "--bundle" ] && [ -n "${2:-}" ]; then
  resources="$2/Contents/Resources"
  mkdir -p "$resources"
  cp "$OUT" "$resources/korpproxy-server"
  echo "✓ embedded into $resources/korpproxy-server"
fi
