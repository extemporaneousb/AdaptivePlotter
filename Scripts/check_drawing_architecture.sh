#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
manifest_directory=$(mktemp -d "${TMPDIR:-/tmp}/drawing-architecture.XXXXXX")
trap 'rm -rf "$manifest_directory"' EXIT HUP INT TERM
swift package --package-path "$project_root" --scratch-path "$manifest_directory/scratch" dump-package > "$manifest_directory/manifest.json"
DRAWING_PACKAGE_MANIFEST="$manifest_directory/manifest.json" swift test --package-path "$project_root" --no-parallel --filter DrawingDependencyContractTests "$@"
