#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

repo="${1:-}"
version="${2:-}"
if [[ ! "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ || ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: bash scripts/generate-appcast.sh OWNER/REPO X.Y.Z" >&2
    exit 1
fi

archive="$PWD/dist/$version/DockStay-$version-arm64.zip"
tool="$PWD/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
[[ -f "$archive" ]] || { echo "Missing final signed, stapled archive: $archive" >&2; exit 1; }
[[ -x "$tool" ]] || { echo "Run swift package resolve first." >&2; exit 1; }

# Sparkle applies the new URL prefix to every archive it scans. Give it the old
# feed and only the new archive so existing entries keep their download URLs.
updates="$PWD/dist/appcast"
mkdir -p "$updates"
staging="$(mktemp -d "$updates/.generate.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
if [[ -f "$updates/appcast.xml" ]]; then
    cp "$updates/appcast.xml" "$staging/"
fi
cp "$archive" "$staging/"
"$tool" \
    --account DockStay \
    --download-url-prefix "https://github.com/$repo/releases/download/v$version/" \
    --link "https://github.com/$repo" \
    --maximum-deltas 0 \
    "$staging"
cp "$staging/appcast.xml" "$updates/appcast.xml"
cp "$updates/appcast.xml" "$PWD/dist/$version/appcast.xml"
printf '\nUpload dist/%s/appcast.xml alongside the ZIP to the same GitHub release.\n' "$version"
