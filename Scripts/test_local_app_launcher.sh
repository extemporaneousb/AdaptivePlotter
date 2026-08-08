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

logic_tests="$test_root/AdaptivePlotterLauncherLogicTests"
xcrun swiftc \
    -parse-as-library \
    -DADAPTIVEPLOTTER_LAUNCHER_TESTING \
    -framework AppKit \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -o "$logic_tests" \
    "$project_root/Scripts/launch_local_app.swift" \
    "$project_root/Scripts/test_local_app_launcher_logic.swift"
"$logic_tests"

if grep -Eq 'createsNewApplicationInstance[[:space:]]*=[[:space:]]*true' \
    "$project_root/Scripts/launch_local_app.swift"
then
    echo "launcher still forces a new AdaptivePlotter application instance" >&2
    exit 1
fi

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

raw_directory="$test_root/other-worktree/.build/x86_64-apple-macosx/debug"
raw_executable="$raw_directory/AdaptivePlotter"
refusal_bundle="$test_root/RefusalFixture.app"
mkdir -p "$raw_directory"
mkdir -p "$refusal_bundle/Contents/MacOS"
install -m 755 /usr/bin/true "$refusal_bundle/Contents/MacOS/AdaptivePlotter"
install -m 644 \
    "$project_root/Resources/AdaptivePlotter-Info.plist" \
    "$refusal_bundle/Contents/Info.plist"
/usr/bin/codesign \
    --force \
    --deep \
    --sign - \
    --identifier com.bullard.AdaptivePlotter \
    --timestamp=none \
    "$refusal_bundle" >/dev/null 2>&1
xcrun swiftc \
    -parse-as-library \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -o "$raw_executable" \
    "$project_root/Scripts/test_raw_adaptiveplotter_process.swift"
"$raw_executable" 3 &
raw_pid=$!

set +e
raw_refusal=$(
    "$launcher" "$refusal_bundle" 2>&1
)
raw_status=$?
set -e

if [ "$raw_status" -eq 0 ]; then
    echo "launcher accepted a competing raw AdaptivePlotter executable" >&2
    wait "$raw_pid"
    exit 1
fi
if ! printf '%s\n' "$raw_refusal" \
    | grep -Fq "raw pid=$raw_pid executable=$raw_executable"
then
    printf '%s\n' "$raw_refusal" >&2
    echo "raw-process refusal did not report its PID and executable path" >&2
    wait "$raw_pid"
    exit 1
fi
if ! ps -p "$raw_pid" >/dev/null 2>&1; then
    printf '%s\n' "$raw_refusal" >&2
    echo "launcher terminated the user-owned raw-process fixture" >&2
    exit 1
fi
wait "$raw_pid"

echo "AdaptivePlotter local launcher validation passed"
