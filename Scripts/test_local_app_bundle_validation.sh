#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
source_bundle=${1:-"$project_root/.build/AdaptivePlotter.app"}
validator="$project_root/Scripts/validate_local_app_bundle.sh"

if [ ! -d "$source_bundle" ]; then
    echo "AdaptivePlotter app bundle is missing: $source_bundle" >&2
    exit 1
fi

test_root=$(mktemp -d "$project_root/.build/.AdaptivePlotter-validation.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

unsigned_bundle="$test_root/Unsigned.app"
mkdir -p "$unsigned_bundle/Contents/MacOS"
install -m 755 \
    "$source_bundle/Contents/MacOS/AdaptivePlotter" \
    "$unsigned_bundle/Contents/MacOS/AdaptivePlotter"
install -m 644 \
    "$source_bundle/Contents/Info.plist" \
    "$unsigned_bundle/Contents/Info.plist"
/usr/bin/codesign --remove-signature "$unsigned_bundle"

if sh "$validator" "$unsigned_bundle" >/dev/null 2>&1; then
    echo "bundle validation accepted an unsigned bundle" >&2
    exit 1
fi

tampered_bundle="$test_root/Tampered.app"
cp -R "$source_bundle" "$tampered_bundle"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 2' \
    "$tampered_bundle/Contents/Info.plist"

if sh "$validator" "$tampered_bundle" >/dev/null 2>&1; then
    echo "bundle validation accepted a bundle with a tampered Info.plist" >&2
    exit 1
fi

echo "AdaptivePlotter app-bundle negative validation passed"
