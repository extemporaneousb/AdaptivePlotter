#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
source_file="$project_root/Scripts/launch_local_app.swift"
output="$project_root/.build/AdaptivePlotterLauncher"

if [ ! -f "$source_file" ]; then
    echo "local app launcher source is missing: $source_file" >&2
    exit 1
fi

staging_root=$(mktemp -d "$project_root/.build/.AdaptivePlotter-launcher.XXXXXX")
staging_executable="$staging_root/AdaptivePlotterLauncher"
trap 'rm -rf "$staging_root"' EXIT HUP INT TERM

xcrun swiftc \
    -parse-as-library \
    -framework AppKit \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -o "$staging_executable" \
    "$source_file"

if [ ! -x "$staging_executable" ]; then
    echo "Swift compiler did not produce an executable launcher" >&2
    exit 1
fi
mv "$staging_executable" "$output"
echo "$output"
