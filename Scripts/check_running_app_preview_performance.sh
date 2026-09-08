#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
bundle=${1:-"$project_root/.build/AdaptivePlotter.app"}
evidence=${2:-"$project_root/.build/evidence/preview-performance.json"}
scenario=${3:-preview}
case "$scenario" in
    preview) drawing_studio=NO ;;
    drawing-studio) drawing_studio=YES ;;
    *) echo "unknown preview performance scenario: $scenario" >&2; exit 1 ;;
esac
executable="$bundle/Contents/MacOS/AdaptivePlotter"
python="$project_root/.VE/bin/python"

cpu_median_limit=75
cpu_p95_limit=100
interaction_p95_milliseconds_limit=100
interaction_max_milliseconds_limit=250
minimum_preview_frames=60
minimum_cpu_samples=8
minimum_interaction_samples=80

if [ ! -x "$executable" ]; then
    echo "signed AdaptivePlotter app executable is missing: $executable" >&2
    exit 1
fi
if [ ! -x "$python" ]; then
    echo "repo-local Python is missing: $python" >&2
    exit 1
fi
sh "$project_root/Scripts/validate_local_app_bundle.sh" "$bundle" >/dev/null
bundle_configuration=$(/usr/libexec/PlistBuddy -c 'Print :AdaptivePlotterBuildConfiguration' \
    "$bundle/Contents/Info.plist")

if /usr/bin/pgrep -x AdaptivePlotter >/dev/null 2>&1; then
    echo "AdaptivePlotter is already running; quit it before measuring the signed app" >&2
    exit 1
fi

mkdir -p "$(dirname "$evidence")"
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/adaptiveplotter-preview-performance.XXXXXX")
runtime_report="$temporary_root/runtime.json"
measurement_ready="$temporary_root/measurement-ready"
cpu_samples="$temporary_root/cpu.txt"
application_log="$temporary_root/application.log"
application_pid=

cleanup() {
    if [ -n "$application_pid" ] && /bin/kill -0 "$application_pid" 2>/dev/null; then
        /bin/kill -TERM "$application_pid" 2>/dev/null || true
        wait "$application_pid" 2>/dev/null || true
    fi
    rm -rf "$temporary_root"
}
trap cleanup EXIT HUP INT TERM

"$executable" \
    -NSQuitAlwaysKeepsWindows NO \
    -AdaptivePlotterPreviewPerformanceGate YES \
    -AdaptivePlotterPreviewPerformanceReport "$runtime_report" \
    -AdaptivePlotterPreviewPerformanceReadyMarker "$measurement_ready" \
    -AdaptivePlotterPreviewPerformanceDrawingStudio "$drawing_studio" \
    >"$application_log" 2>&1 &
application_pid=$!

ready_polls=0
while [ ! -f "$measurement_ready" ] && [ "$ready_polls" -lt 100 ]; do
    if ! /bin/kill -0 "$application_pid" 2>/dev/null; then
        echo "AdaptivePlotter exited before the preview measurement began" >&2
        sed -n '1,200p' "$application_log" >&2
        exit 1
    fi
    sleep 0.25
    ready_polls=$((ready_polls + 1))
done
if [ ! -f "$measurement_ready" ]; then
    echo "AdaptivePlotter did not reach the preview measurement window within 25 seconds" >&2
    sed -n '1,200p' "$application_log" >&2
    exit 1
fi

sample_count=0
while /bin/kill -0 "$application_pid" 2>/dev/null && [ "$sample_count" -lt 12 ]; do
    sample=$(/bin/ps -p "$application_pid" -o %cpu= | /usr/bin/tr -d ' ' || true)
    case "$sample" in
        ''|*[!0-9.]*) ;;
        *) printf '%s\n' "$sample" >>"$cpu_samples" ;;
    esac
    sample_count=$((sample_count + 1))
    sleep 1
done

report_polls=0
while [ ! -f "$runtime_report" ] && /bin/kill -0 "$application_pid" 2>/dev/null \
    && [ "$report_polls" -lt 12 ]; do
    sleep 0.25
    report_polls=$((report_polls + 1))
done
if /bin/kill -0 "$application_pid" 2>/dev/null; then
    /bin/kill -TERM "$application_pid" 2>/dev/null || true
fi
termination_polls=0
while /bin/kill -0 "$application_pid" 2>/dev/null && [ "$termination_polls" -lt 20 ]; do
    sleep 0.25
    termination_polls=$((termination_polls + 1))
done
if /bin/kill -0 "$application_pid" 2>/dev/null; then
    /bin/kill -KILL "$application_pid" 2>/dev/null || true
fi
wait "$application_pid" 2>/dev/null || true
application_pid=
if [ ! -f "$runtime_report" ]; then
    echo "AdaptivePlotter exited without writing its preview performance report" >&2
    sed -n '1,200p' "$application_log" >&2
    exit 1
fi

"$python" - \
    "$runtime_report" "$cpu_samples" "$evidence" \
    "$cpu_median_limit" "$cpu_p95_limit" \
    "$interaction_p95_milliseconds_limit" "$interaction_max_milliseconds_limit" \
    "$minimum_preview_frames" "$minimum_cpu_samples" "$minimum_interaction_samples" "$scenario" "$bundle_configuration" <<'PY'
import json
import math
import pathlib
import statistics
import sys

(
    runtime_path,
    cpu_path,
    evidence_path,
    cpu_median_limit,
    cpu_p95_limit,
    interaction_p95_limit,
    interaction_max_limit,
    minimum_preview_frames,
    minimum_cpu_samples,
    minimum_interaction_samples,
    scenario,
    bundle_configuration,
) = sys.argv[1:]


def percentile(values, percentile_value):
    ordered = sorted(values)
    index = max(0, math.ceil(percentile_value * len(ordered)) - 1)
    return ordered[index]


runtime = json.loads(pathlib.Path(runtime_path).read_text(encoding="utf-8"))
cpu = [
    float(value)
    for value in pathlib.Path(cpu_path).read_text(encoding="utf-8").splitlines()
    if value.strip()
]
latencies = [float(value) for value in runtime["interactionLatencyMilliseconds"]]

thresholds = {
    "cpuMedianPercentMaximum": float(cpu_median_limit),
    "cpuP95PercentMaximum": float(cpu_p95_limit),
    "interactionP95MillisecondsMaximum": float(interaction_p95_limit),
    "interactionMaximumMillisecondsMaximum": float(interaction_max_limit),
    "minimumPreviewFramesAdvanced": int(minimum_preview_frames),
    "minimumCPUSampleCount": int(minimum_cpu_samples),
    "minimumInteractionSampleCount": int(minimum_interaction_samples),
}
measurements = {
    "buildConfiguration": runtime["buildConfiguration"],
    "cpuPercentSamples": cpu,
    "cpuMedianPercent": statistics.median(cpu) if cpu else None,
    "cpuP95Percent": percentile(cpu, 0.95) if cpu else None,
    "interactionLatencyMilliseconds": latencies,
    "interactionMedianMilliseconds": statistics.median(latencies) if latencies else None,
    "interactionP95Milliseconds": percentile(latencies, 0.95) if latencies else None,
    "interactionMaximumMilliseconds": max(latencies) if latencies else None,
    "previewFramesAdvanced": runtime["previewFramesAdvanced"],
    "previewStartSequence": runtime["previewStartSequence"],
    "previewEndSequence": runtime["previewEndSequence"],
    "previewSourceWasLive": runtime["previewSourceWasLive"],
    "previewConfigurationRemainedStable": runtime["previewConfigurationRemainedStable"],
    "semanticPresentationRevisionDelta": runtime["semanticPresentationRevisionDelta"],
    "rootProjectionBuildCountDelta": runtime["rootProjectionBuildCountDelta"],
    "drawingDraftSynchronizationCountDelta": runtime[
        "drawingDraftSynchronizationCountDelta"
    ],
    "measurementDurationSeconds": runtime["measurementDurationSeconds"],
    "overlayPresentationRevisionDelta": runtime["overlayPresentationRevisionDelta"],
    "overlayCanvasDrawCountDelta": runtime["overlayCanvasDrawCountDelta"],
    "overlayCanvasBuildCountDelta": runtime["overlayCanvasBuildCountDelta"],
    "drawingStudioWasOpen": runtime["drawingStudioWasOpen"],
    "drawingPlanWasAvailable": runtime["drawingPlanWasAvailable"],
    "automaticAnalysisWasRunning": runtime["automaticAnalysisWasRunning"],
}
checks = {
    "buildConfigurationMatchesBundle": runtime["buildConfiguration"] == bundle_configuration,
    "cpuSampleCount": len(cpu) >= thresholds["minimumCPUSampleCount"],
    "cpuMedian": bool(cpu)
    and measurements["cpuMedianPercent"] <= thresholds["cpuMedianPercentMaximum"],
    "cpuP95": bool(cpu)
    and measurements["cpuP95Percent"] <= thresholds["cpuP95PercentMaximum"],
    "interactionSampleCount": len(latencies)
    >= thresholds["minimumInteractionSampleCount"],
    "interactionP95": bool(latencies)
    and measurements["interactionP95Milliseconds"]
    <= thresholds["interactionP95MillisecondsMaximum"],
    "interactionMaximum": bool(latencies)
    and measurements["interactionMaximumMilliseconds"]
    <= thresholds["interactionMaximumMillisecondsMaximum"],
    "livePreferredCameraPreview": measurements["previewSourceWasLive"],
    "stableCameraConfiguration": measurements["previewConfigurationRemainedStable"],
    "previewAdvanced": measurements["previewFramesAdvanced"]
    >= thresholds["minimumPreviewFramesAdvanced"],
    "semanticPresentationUnchanged": measurements["semanticPresentationRevisionDelta"] == 0,
    "rootProjectionNotRebuilt": measurements["rootProjectionBuildCountDelta"] == 0,
    # Core Animation can repaint a retained Canvas without rebuilding its view.
    # Enforce application invalidation here; retain actual draws as raw evidence.
    "overlayRebuildsBoundedByPresentationChanges": measurements["overlayCanvasBuildCountDelta"]
    <= measurements["overlayPresentationRevisionDelta"],
    "drawingDraftNotSynchronized": measurements[
        "drawingDraftSynchronizationCountDelta"
    ]
    == 0,
    "requestedStudioIsOpen": scenario != "drawing-studio" or runtime["drawingStudioWasOpen"],
}
evidence = {
    "schema": "adaptiveplotter.preview-performance-gate.v1",
    "route": "signed-app-preferred-camera",
    "scenario": scenario,
    "thresholds": thresholds,
    "measurements": measurements,
    "checks": checks,
    "passed": all(checks.values()),
}
destination = pathlib.Path(evidence_path)
temporary = destination.with_suffix(destination.suffix + ".tmp")
temporary.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
temporary.replace(destination)
print(json.dumps(evidence, indent=2, sort_keys=True))
if not evidence["passed"]:
    raise SystemExit(1)
PY

echo "Preview performance evidence: $evidence" >&2
