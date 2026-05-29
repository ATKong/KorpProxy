#!/usr/bin/env bash
#
# package-app.sh — build, sign, notarize, and package KorpProxy.app for Sparkle.
#
# Produces:
#   app/dist/KorpProxy-<VERSION>.zip      signed + notarized, ready to upload
#   app/dist/appcast.xml                  updated feed (a new <item> prepended)
#
# Works locally (uses your login keychain for both the Developer ID cert and the
# Sparkle EdDSA key) and in CI (pass creds via the env vars below).
#
# Required:
#   VERSION                 marketing version, e.g. 0.2.0 (defaults from git tag app-vX.Y.Z)
#   DEVELOPER_ID_APP        signing identity, e.g. "Developer ID Application: Foo (TEAMID)"
#
# Notarization (pick ONE; skipped with a warning if none provided):
#   NOTARY_PROFILE                          notarytool keychain profile name, OR
#   NOTARY_KEY / NOTARY_KEY_ID / NOTARY_ISSUER   App Store Connect API key (.p8 path), OR
#   APPLE_ID / APPLE_TEAM_ID / APPLE_APP_PASSWORD  Apple ID + app-specific password
#
# Sparkle signing:
#   SPARKLE_PRIVATE_KEY     EdDSA private key string (CI). Omit locally to use the keychain.
#   SPARKLE_BIN             dir with sign_update (default: auto-download to /tmp)
#
# Optional:
#   BUILD                   CFBundleVersion integer (default: git commit count)
#   DOWNLOAD_URL_PREFIX     base URL for the enclosure (default: the public releases repo)
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # repo/app
cd "$APP_DIR"

# ---- version + build number ------------------------------------------------
TAG="${GITHUB_REF_NAME:-$(git describe --tags --match 'app-v*' --abbrev=0 2>/dev/null || true)}"
if [ -z "${VERSION:-}" ]; then
  VERSION="${TAG#app-v}"
fi
[ -z "${VERSION:-}" ] && { echo "error: set VERSION (or tag app-vX.Y.Z)" >&2; exit 1; }
BUILD="${BUILD:-$(git rev-list --count HEAD)}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/ATKong/KorpProxy-releases/releases/download/app-v${VERSION}}"
DEVELOPER_ID_APP="${DEVELOPER_ID_APP:-}"
[ -z "$DEVELOPER_ID_APP" ] && { echo "error: set DEVELOPER_ID_APP" >&2; exit 1; }

echo "▸ Packaging KorpProxy ${VERSION} (build ${BUILD})"

DIST="$APP_DIR/dist"
DERIVED="$APP_DIR/build"
rm -rf "$DIST"; mkdir -p "$DIST"

# ---- build (Release, Developer ID, hardened runtime) -----------------------
command -v xcodegen >/dev/null 2>&1 && xcodegen generate >/dev/null

xcodebuild \
  -project KorpProxy.xcodeproj \
  -scheme KorpProxy \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination 'generic/platform=macOS' \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APP" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  ENABLE_DEBUG_DYLIB=NO \
  clean build

APP="$DERIVED/Build/Products/Release/KorpProxy.app"
[ -d "$APP" ] || { echo "error: app not found at $APP" >&2; exit 1; }

# ---- re-sign nested code (inside-out) --------------------------------------
# Xcode/SPM leaves Sparkle's helpers (Updater.app, XPC services) without a
# secure timestamp, which notarization rejects. Re-sign everything deepest-first
# with Developer ID + hardened runtime + timestamp, then re-sign the app with
# our clean entitlements (also drops any injected get-task-allow).
echo "▸ Re-signing nested code (Developer ID + runtime + timestamp)…"
FW="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$FW" ]; then
  V="$FW/Versions/B"; [ -d "$V" ] || V="$FW/Versions/Current"
  for c in "$V/XPCServices/Downloader.xpc" "$V/XPCServices/Installer.xpc" "$V/Autoupdate" "$V/Updater.app"; do
    [ -e "$c" ] && codesign --force --options runtime --timestamp \
      --preserve-metadata=entitlements --sign "$DEVELOPER_ID_APP" "$c"
  done
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$FW"
fi
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" \
  "$APP/Contents/Resources/korpproxy-server"
codesign --force --options runtime --timestamp \
  --entitlements "$APP_DIR/KorpProxy.entitlements" --sign "$DEVELOPER_ID_APP" "$APP"

# ---- verify signing --------------------------------------------------------
echo "▸ Verifying code signature…"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|Runtime" || true
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "get-task-allow"; then
  echo "error: get-task-allow still present on app (would fail notarization)" >&2; exit 1
fi

# ---- notarize --------------------------------------------------------------
NOTARIZE_ZIP="$DIST/KorpProxy-notarize.zip"
ditto -c -k --keepParent "$APP" "$NOTARIZE_ZIP"

notarize() {
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  elif [ -n "${NOTARY_KEY:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER:-}" ]; then
    xcrun notarytool submit "$NOTARIZE_ZIP" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
  elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
    xcrun notarytool submit "$NOTARIZE_ZIP" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
  else
    return 2
  fi
}

if notarize; then
  echo "▸ Stapling notarization ticket…"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
else
  echo "warning: no notarization credentials provided — skipping notarize+staple (Gatekeeper will warn on other Macs)" >&2
fi
rm -f "$NOTARIZE_ZIP"

# ---- package for distribution ----------------------------------------------
ZIP="$DIST/KorpProxy-${VERSION}.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
LENGTH="$(stat -f%z "$ZIP")"
echo "▸ Archive: $ZIP ($LENGTH bytes)"

# ---- Sparkle EdDSA signature -----------------------------------------------
SPARKLE_BIN="${SPARKLE_BIN:-}"
if [ -z "$SPARKLE_BIN" ] || [ ! -x "$SPARKLE_BIN/sign_update" ]; then
  echo "▸ Fetching Sparkle tools…"
  STAG="$(gh api repos/sparkle-project/Sparkle/releases/latest --jq .tag_name 2>/dev/null || echo 2.9.2)"
  curl -sL -o /tmp/sparkle.tar.xz "https://github.com/sparkle-project/Sparkle/releases/download/${STAG}/Sparkle-${STAG}.tar.xz"
  mkdir -p /tmp/sparkle-tools && tar -xJf /tmp/sparkle.tar.xz -C /tmp/sparkle-tools
  SPARKLE_BIN="/tmp/sparkle-tools/bin"
fi

if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  SIGOUT="$("$SPARKLE_BIN/sign_update" -s "$SPARKLE_PRIVATE_KEY" "$ZIP")"
else
  SIGOUT="$("$SPARKLE_BIN/sign_update" "$ZIP")"   # uses login keychain
fi
echo "▸ Sparkle signature: $SIGOUT"
# sign_update prints e.g.:  sparkle:edSignature="…" length="…"
ED_SIG="$(printf '%s' "$SIGOUT" | sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p')"
[ -z "$ED_SIG" ] && { echo "error: could not parse EdDSA signature" >&2; exit 1; }

# ---- update appcast --------------------------------------------------------
APPCAST="$DIST/appcast.xml"
# Seed from an existing feed if present (keeps release history).
if [ -f "$APP_DIR/appcast.xml" ]; then cp "$APP_DIR/appcast.xml" "$APPCAST"; fi
python3 "$APP_DIR/scripts/update_appcast.py" \
  --appcast "$APPCAST" \
  --version "$VERSION" \
  --build "$BUILD" \
  --url "${DOWNLOAD_URL_PREFIX}/KorpProxy-${VERSION}.zip" \
  --length "$LENGTH" \
  --ed-signature "$ED_SIG" \
  --min-system "14.0"

echo "✓ Done."
echo "  Artifact: $ZIP"
echo "  Appcast:  $APPCAST"
