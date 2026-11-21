#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Feed location and public key are release configuration, never credentials.
if [[ -n "${UPDATE_FEED_URL:-}" || -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
    python3 - <<'PY'
import base64
import os
from urllib.parse import urlsplit

try:
    feed = urlsplit(os.environ.get("UPDATE_FEED_URL", ""))
    key = base64.b64decode(os.environ.get("SPARKLE_PUBLIC_ED_KEY", ""), validate=True)
    valid = (feed.scheme == "https" and feed.hostname and not feed.username
             and not feed.password and not feed.fragment and len(key) == 32)
except ValueError:
    valid = False
if not valid:
    raise SystemExit("Set both UPDATE_FEED_URL (HTTPS) and SPARKLE_PUBLIC_ED_KEY (base64 Ed25519 public key).")
PY
fi

# Default to an Apple Silicon executable and matching framework slices.
build_args=(-c release)
framework_copy=(ditto)
case "${ARCH:-arm64}" in
    arm64)
        build_args+=(--arch arm64)
        framework_copy+=(--arch arm64)
        ;;
    universal) build_args+=(--arch arm64 --arch x86_64) ;;
esac
swift build "${build_args[@]}"
bin_dir="$(swift build "${build_args[@]}" --show-bin-path)"
app="${BUILD_OUTPUT_DIR:-$PWD/build}/DockStay.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/DockStay" "$app/Contents/MacOS/DockStay"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp -R Resources/en.lproj Resources/ru.lproj "$app/Contents/Resources/"
if [[ -n "${UPDATE_FEED_URL:-}" ]]; then
    plutil -replace SUFeedURL -string "$UPDATE_FEED_URL" "$app/Contents/Info.plist"
    plutil -replace SUPublicEDKey -string "$SPARKLE_PUBLIC_ED_KEY" "$app/Contents/Info.plist"
fi

# ditto preserves the versioned framework's symlinks and executable permissions.
framework="$app/Contents/Frameworks/Sparkle.framework"
mkdir -p "$app/Contents/Frameworks"
"${framework_copy[@]}" "$bin_dir/Sparkle.framework" "$framework"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$app/Contents/Resources/Sparkle-LICENSE.txt"
plutil -lint "$app/Contents/Info.plist"

# Prefer a stable development identity for Accessibility grants across rebuilds.
# A local ad-hoc build remains possible without an Apple Developer membership.
identity="${CODE_SIGN_IDENTITY:--}"
sign_args=(--force --sign "$identity")
if [[ "$identity" != - ]]; then
    sign_args+=(--options runtime --timestamp)
fi
# Sign nested code from the inside out, using the same team as the host app.
for component in \
    "$framework/Versions/B/XPCServices/Downloader.xpc" \
    "$framework/Versions/B/XPCServices/Installer.xpc" \
    "$framework/Versions/B/Autoupdate" \
    "$framework/Versions/B/Updater.app" \
    "$framework"; do
    codesign "${sign_args[@]}" --preserve-metadata=entitlements "$component"
done
codesign "${sign_args[@]}" --identifier com.liquorice.DockStay "$app"
codesign --verify --deep --strict "$app"
printf '\nBuilt %s\n' "$app"
