#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
bundle=${1:-"$project_root/.build/AdaptivePlotter.app"}
evidence=${2:-"$project_root/.build/evidence/preview-performance.json"}
scenario=${3:-preview}
case "$scenario" in
    preview) default_duration=12 ;;
    learned-portrait) default_duration=60 ;;
    physical-portrait) default_duration=600 ;;
    native-workbench) default_duration=180 ;;
    *) echo "unknown preview performance scenario: $scenario" >&2; exit 1 ;;
esac
measurement_seconds=${PREVIEW_PERFORMANCE_DURATION_SECONDS:-$default_duration}
executable="$bundle/Contents/MacOS/AdaptivePlotter"
launcher="$project_root/.build/AdaptivePlotterLauncher"
python="$project_root/.VE/bin/python"

cpu_median_limit=75
cpu_p95_limit=100
interaction_p95_milliseconds_limit=100
interaction_max_milliseconds_limit=250
minimum_preview_frames=60
minimum_cpu_samples=8
minimum_interaction_samples=10

if [ ! -x "$executable" ]; then
    echo "signed AdaptivePlotter app executable is missing: $executable" >&2
    exit 1
fi
if [ ! -x "$python" ]; then
    echo "repo-local Python is missing: $python" >&2
    exit 1
fi
if [ ! -x "$launcher" ]; then
    echo "existing AdaptivePlotter launcher is missing: $launcher; build the launcher before the native input gate" >&2
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
if [ "$scenario" = native-workbench ]; then
    temporary_root=$(mktemp -d "${evidence%.json}.native.XXXXXX")
elif [ "$scenario" = physical-portrait ]; then
    : "${PORTRAIT_REFERENCE_PHOTO:?physical-portrait requires an explicit portrait photo}"
    : "${PHYSICAL_CONTROLLER:?physical-portrait requires an exact controller identifier or BSD path}"
    temporary_root=$(mktemp -d "${evidence%.json}.physical.XXXXXX")
else
    temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/adaptiveplotter-preview-performance.XXXXXX")
fi
runtime_report="$temporary_root/runtime.json"
measurement_ready="$temporary_root/measurement-ready"
cpu_samples="$temporary_root/cpu.txt"
application_log="$temporary_root/application.log"
latency_failure="$measurement_ready.latency-failure"
process_sample="${evidence%.json}.sample.txt"
sample_taken=NO
application_pid=

cleanup() {
    if [ "$scenario" = physical-portrait ]; then
        echo "Physical scenario app PID ${application_pid:-not launched} and artifacts retained: $temporary_root" >&2
        return
    fi
    if [ -n "$application_pid" ] && /bin/kill -0 "$application_pid" 2>/dev/null; then
        /bin/kill -TERM "$application_pid" 2>/dev/null || true
        wait "$application_pid" 2>/dev/null || true
    fi
    if [ "$scenario" = native-workbench ]; then
        echo "Native workbench artifacts retained: $temporary_root" >&2
    else
        rm -rf "$temporary_root"
    fi
}
trap cleanup EXIT HUP INT TERM

set -- "$executable" \
    -NSQuitAlwaysKeepsWindows NO \
    -AdaptivePlotterPreviewPerformanceGate YES \
    -AdaptivePlotterPreviewPerformanceReport "$runtime_report" \
    -AdaptivePlotterPreviewPerformanceReadyMarker "$measurement_ready" \
    -AdaptivePlotterPreviewPerformanceScenario "$scenario" \
    -AdaptivePlotterPreviewPerformanceDuration "$measurement_seconds"
if [ -n "${PORTRAIT_REFERENCE_PHOTO:-}" ]; then
    set -- "$@" -AdaptivePlotterPreviewPerformancePortraitPhoto "$PORTRAIT_REFERENCE_PHOTO"
fi
if [ "$scenario" = physical-portrait ]; then
    set -- "$@" -AdaptivePlotterPhysicalController "$PHYSICAL_CONTROLLER"
fi
if [ "$scenario" = physical-portrait ]; then
    /usr/bin/nohup "$@" >"$application_log" 2>&1 </dev/null &
else
    "$@" >"$application_log" 2>&1 &
fi
application_pid=$!

# Every declared scenario drives native controls (preview includes Hide Motion).
# Registration/activation uses the existing launcher and exact spawned PID. Do
# not wait for measurement/review markers: physical preparation clicks Connect
# before its first review marker, so such a wait would create a cycle.
case "$scenario" in
    preview|learned-portrait|physical-portrait|native-workbench)
        if ! "$launcher" --activate-existing-pid "$application_pid" "$bundle" >"$temporary_root/activation.log" 2>&1; then
            cat "$temporary_root/activation.log" >&2
            echo "The exact gate process could not be activated; no fallback application was launched" >&2
            exit 1
        fi
        ;;
esac

if [ "$scenario" = native-workbench ]; then
    native_limit=$("$python" -c 'import math,sys; print(math.ceil(float(sys.argv[1])))' "$measurement_seconds")
    native_polls=0
    while [ ! -f "$runtime_report" ] && [ "$native_polls" -lt "$native_limit" ]; do
        if ! /bin/kill -0 "$application_pid" 2>/dev/null; then
            echo "Native workbench app exited without a report; artifacts retained: $temporary_root" >&2
            exit 1
        fi
        sleep 1
        native_polls=$((native_polls + 1))
    done
    if [ ! -f "$runtime_report" ]; then
        /usr/bin/sample "$application_pid" 2 -file "$process_sample" >/dev/null 2>&1 || true
        echo "Native workbench did not complete; report/log/captures retained: $temporary_root" >&2
        exit 1
    fi
    cp "$runtime_report" "$evidence"
    "$python" - "$evidence" <<'NATIVE_PY'
import json, pathlib, sys
report = json.loads(pathlib.Path(sys.argv[1]).read_text())
panels = ['guidedLearning', 'videoSettings', 'motion', 'activeLearning', 'portraitStudio']
slots = ['right', 'left', 'rightBottom', 'leftBottom']
expected = {(panel, slot, width) for panel in panels for slot in slots for width in (1000, 1600)}
actual = {(item.get('panel'), item.get('slot'), item.get('width')) for item in report.get('placements', [])}
images = report.get('bitmaps', [])
required = ['learning.mode', 'workbench.scroll.inner', 'workbench.resize']
required += ['workbench.hide.' + panel for panel in panels]
required += ['workbench.toggle.' + panel for panel in panels]
counts = report.get('nativeCounts', {})
def required_count(key):
    return 2 if key == 'learning.mode' else 8
valid_counts = all(counts.get(key, {}).get('posted', 0) >= required_count(key) and
                   len({counts[key].get(field, -1) for field in ('posted', 'dispatched', 'handled', 'acknowledged')}) == 1
                   for key in required)
body_ids = {'guidedLearning': 'learning.exerciseActions', 'videoSettings': 'workbench.video.cameraRole',
            'motion': 'motion.penDown', 'activeLearning': 'learning.coverage.prepare', 'portraitStudio': 'drawing.draw'}
valid_bodies = all(item.get('body', {}).get('identifier') == body_ids.get(item.get('panel'))
                   and item['body'].get('panelIdentifier') == 'workbench.panel.' + item.get('panel', '')
                   and item['body'].get('fitsEveryContainingClip') is True
                   and item.get('header', {}).get('fitsEveryContainingClip') is True
                   for item in report.get('placements', []))
scroll_contexts = {sample['scrollEvidence'].get('context') for sample in report.get('inputs', [])
                  if sample.get('targetIdentifier') == 'workbench.scroll.inner'
                  and sample.get('scrollEvidence', {}).get('controlIdentifier') == 'drawing.draw'
                  and sample['scrollEvidence'].get('clipIdentity')
                  and sample['scrollEvidence'].get('beforeBounds') != sample['scrollEvidence'].get('afterBounds')}
passed = (report.get('schema') == 'adaptiveplotter.native-workbench.v2'
          and not report.get('failures') and actual == expected and valid_counts and valid_bodies
          and scroll_contexts == {slot + '.' + str(width) for slot in slots for width in (1000, 1600)}
          and len(images) == 8 and len(set(images)) == 8 and all(pathlib.Path(path).is_file() for path in images)
          and report.get('applicationWasActive') is True
          and report.get('stopWasVisible') is True
          and report.get('acceptedArtifactsUnchanged') is True
          and report.get('windowPreferencesUnchanged') is True
          and report.get('viewMenuWasPresent') is True
          and set(report.get('canvasOnlyWidths', [])) == {1000, 1600}
          and set(report.get('learningStates', [])) == {False, True})
print('Native workbench ' + ('passed' if passed else 'failed')
      + '; actual application input with simulated startup, no physical or native-held-Draw Stop claim.')
for failure in report.get('failures', []):
    print(failure)
raise SystemExit(0 if passed else 1)
NATIVE_PY
    exit $?
fi

if [ "$scenario" = physical-portrait ]; then
    printf '%s\n' "$application_pid" >"$temporary_root/application.pid"
    printf 'Physical scenario running; no automatic continuation.\nPID: %s\nReport: %s\nReview: %s\nLog: %s\n' \
        "$application_pid" "$runtime_report" "$measurement_ready" "$application_log"
    # Three review stages and two draws each have their own bounded runtime
    # deadline. A shell timeout never kills a controller-owning process.
    physical_limit=$("$python" -c 'import math,sys; print(math.ceil(float(sys.argv[1])) * 5 + 180)' "$measurement_seconds")
    physical_polls=0
    while [ ! -f "$measurement_ready.finished" ] && [ "$physical_polls" -lt "$physical_limit" ]; do
        if ! /bin/kill -0 "$application_pid" 2>/dev/null; then
            echo "Physical app exited unexpectedly; retained artifacts require review; do not repeat Draw" >&2
            exit 1
        fi
        sleep 1
        physical_polls=$((physical_polls + 1))
    done
    if [ ! -f "$measurement_ready.finished" ] || [ ! -f "$runtime_report" ]; then
        echo "Physical scenario did not finish; app, active owners, and artifacts retained for Stop/review" >&2
        exit 1
    fi
    cp "$runtime_report" "$evidence"
    "$python" - "$evidence" <<'PHYSICAL_PY'
import json, pathlib, sys
report = json.loads(pathlib.Path(sys.argv[1]).read_text())
passed = (report.get("schema") == "adaptiveplotter.physical-portrait.v1"
          and report.get("state") == "completed"
          and not report.get("failures")
          and report.get("manualStopSettled") is True
          and len(set(report.get("planHashes", []))) == 2
          and len(set(report.get("recordIDs", []))) == 2
          and len(report.get("drawingStopCapabilities", [])) == 2)
print("Physical native/controller/archive scenario " + ("completed" if passed else "failed")
      + "; human attendance and independent ink inspection are separate. App retained.")
raise SystemExit(0 if passed else 1)
PHYSICAL_PY
    exit $?
fi

ready_polls=0
while [ ! -f "$measurement_ready" ] && [ "$ready_polls" -lt 720 ]; do
    if ! /bin/kill -0 "$application_pid" 2>/dev/null; then
        echo "AdaptivePlotter exited before the preview measurement began" >&2
        sed -n '1,200p' "$application_log" >&2
        exit 1
    fi
    sleep 0.25
    ready_polls=$((ready_polls + 1))
done
if [ ! -f "$measurement_ready" ]; then
    /usr/bin/sample "$application_pid" 2 -file "$process_sample" >/dev/null 2>&1 || true
    echo "AdaptivePlotter did not reach the workload measurement window within 180 seconds" >&2
    sed -n '1,200p' "$application_log" >&2
    exit 1
fi

sample_count=0
: >"$cpu_samples"
sample_limit=$("$python" -c 'import math,sys; print(math.ceil(float(sys.argv[1])) + 15)' "$measurement_seconds")
while /bin/kill -0 "$application_pid" 2>/dev/null && [ ! -f "$runtime_report" ] \
    && [ "$sample_count" -lt "$sample_limit" ]; do
    sample=$(/bin/ps -p "$application_pid" -o %cpu= | /usr/bin/tr -d ' ' || true)
    case "$sample" in
        ''|*[!0-9.]*) ;;
        *) printf '%s\n' "$sample" >>"$cpu_samples" ;;
    esac
    if [ "$sample_taken" = NO ] && [ -f "$latency_failure" ]; then
        /usr/bin/sample "$application_pid" 2 -file "$process_sample" >/dev/null 2>&1 || true
        sample_taken=YES
    fi
    sample_count=$((sample_count + 1))
    sleep 1
done
if [ ! -f "$runtime_report" ] && /bin/kill -0 "$application_pid" 2>/dev/null \
    && [ "$sample_taken" = NO ]; then
    /usr/bin/sample "$application_pid" 2 -file "$process_sample" >/dev/null 2>&1 || true
fi

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
latencies = [float(value["visibleAcknowledgmentLatencyMilliseconds"]) for value in runtime["nativeInputSamples"]]

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
    "nativeInputProvenance": runtime["nativeInputProvenance"],
    "nativeInputSamples": runtime["nativeInputSamples"],
    "nativeInputCounts": runtime["nativeInputCounts"],
    "mainActorSchedulingLatencyMilliseconds": runtime["mainActorSchedulingLatencyMilliseconds"],
    "submittedNativeInputCount": runtime["submittedNativeInputCount"],
    "deliveredNativeInputCount": runtime["deliveredNativeInputCount"],
    "acknowledgedNativeInputCount": runtime["acknowledgedNativeInputCount"],
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
    "targetWasVisible": runtime["targetWasVisible"],
    "drawingPlanWasAvailable": runtime["drawingPlanWasAvailable"],
    "automaticAnalysisWasRunning": runtime["automaticAnalysisWasRunning"],
    "appliedCheckpointID": runtime.get("appliedCheckpointID"),
    "completeAcceptedLearningWasRetained": runtime["completeAcceptedLearningWasRetained"],
    "acceptedBorderRecordID": runtime.get("acceptedBorderRecordID"),
    "quietAnalysisWindows": runtime["quietAnalysisWindows"],
    "retrospectiveRecordIDs": runtime["retrospectiveRecordIDs"],
    "retrospectiveConstraintCount": runtime["retrospectiveConstraintCount"],
    "portraitMaximumConcurrentExpensiveJobs": runtime["portraitMaximumConcurrentExpensiveJobs"],
    "passivePanelObservationProvenance": runtime["passivePanelObservationProvenance"],
    "portraitProgramHash": runtime.get("portraitProgramHash"),
    "portraitStrokeCount": runtime["portraitStrokeCount"],
    "portraitInputSource": runtime.get("portraitInputSource"),
    "completedCameraSwitchCount": runtime["completedCameraSwitchCount"],
    "cameraSwitchDurationsMilliseconds": runtime["cameraSwitchDurationsMilliseconds"],
    "cameraSwitchReceipts": runtime["cameraSwitchReceipts"],
    "suspendedPlotterAnalyzedFrameDelta": runtime["suspendedPlotterAnalyzedFrameDelta"],
    "measuredAnalysisFrameDelta": runtime["measuredAnalysisFrameDelta"],
    "portraitMaximumConcurrentWorkers": runtime["portraitMaximumConcurrentWorkers"],
    "portraitSettledWorkers": runtime["portraitSettledWorkers"],
    "passivePanelTextChanged": runtime["passivePanelTextChanged"],
    "passivePanelsObserved": runtime["passivePanelsObserved"],
    "stopWasPresent": runtime["stopWasPresent"],
    "workloadFailures": runtime["failures"],
}
checks = {
    "runtimeSchema": runtime["schema"] == "adaptiveplotter.running-app-preview-runtime.v2",
    "requestedScenario": runtime["scenario"] == scenario,
    "completeRequiredWorkload": not runtime["failures"],
    "nativeInputsDeliveredAndAcknowledged": runtime["submittedNativeInputCount"]
    == runtime["deliveredNativeInputCount"] == runtime["acknowledgedNativeInputCount"] == len(latencies),
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
}
evidence = {
    "schema": "adaptiveplotter.preview-performance-gate.v2",
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
