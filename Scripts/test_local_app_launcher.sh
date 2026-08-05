#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
bundle=${1:-"$project_root/.build/AdaptivePlotter.app"}
launcher=${2:-"$project_root/.build/AdaptivePlotterLauncher"}

if [ ! -x "$launcher" ]; then
    echo "AdaptivePlotter launcher is missing or not executable: $launcher" >&2
    exit 1
fi

"$launcher" --validate-only "$bundle" >/dev/null

if "$launcher" --validate-only "$project_root/.build/Missing.app" >/dev/null 2>&1; then
    echo "launcher validation accepted a missing app bundle" >&2
    exit 1
fi

test_root=$(mktemp -d "$project_root/.build/.AdaptivePlotter-launcher-validation.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

wrong_bundle="$test_root/Wrong.app"
mkdir -p "$wrong_bundle/Contents/MacOS"
install -m 755 \
    "$bundle/Contents/MacOS/AdaptivePlotter" \
    "$wrong_bundle/Contents/MacOS/AdaptivePlotter"
install -m 644 \
    "$bundle/Contents/Info.plist" \
    "$wrong_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c \
    'Set :CFBundleIdentifier com.bullard.NotAdaptivePlotter' \
    "$wrong_bundle/Contents/Info.plist"

if "$launcher" --validate-only "$wrong_bundle" >/dev/null 2>&1; then
    echo "launcher validation accepted an unexpected bundle identifier" >&2
    exit 1
fi

echo "AdaptivePlotter local launcher validation passed"
