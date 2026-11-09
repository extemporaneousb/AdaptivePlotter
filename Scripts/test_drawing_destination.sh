#!/bin/bash
set -euo pipefail
# Invoked by the sole validation executor against a frozen source tree.
project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$project_root"
build_args=(--configuration debug)
test_args=(--configuration debug)
evidence_directory=""
while (($#)); do
  case "$1" in
    --scratch-path)
      [[ $# -ge 2 && "$2" = /* ]] || { echo '--scratch-path requires an absolute directory' >&2; exit 2; }
      build_args+=(--scratch-path "$2"); test_args+=(--scratch-path "$2"); shift 2 ;;
    --xunit-output)
      [[ $# -ge 2 && "$2" = /* ]] || { echo '--xunit-output requires an absolute file' >&2; exit 2; }
      test_args+=(--xunit-output "$2"); shift 2 ;;
    --evidence-directory)
      [[ $# -ge 2 && "$2" = /* ]] || { echo '--evidence-directory requires an absolute directory' >&2; exit 2; }
      evidence_directory="$2"; shift 2 ;;
    --jobs)
      [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || { echo '--jobs requires a positive integer' >&2; exit 2; }
      build_args+=(--jobs "$2"); test_args+=(--jobs "$2"); shift 2 ;;
    *) echo "unsupported option: $1" >&2; exit 2 ;;
  esac
done
if [[ -n "$evidence_directory" ]]; then export DRAWING_DESTINATION_EVIDENCE_DIRECTORY="$evidence_directory"; fi
swift build "${build_args[@]}" --product DrawingDestinationHarness
binary_directory=$(swift build "${build_args[@]}" --show-bin-path)
DRAWING_DESTINATION_HARNESS="$binary_directory/DrawingDestinationHarness" swift test "${test_args[@]}" --no-parallel --filter 'DrawingDestinationTests|DrawingDestinationCompositionTests'
