#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "usage: sh Scripts/check_episode_cutover.sh <PACKAGE-ID> [--consumer-only]" >&2
    exit 2
fi

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if [ "$1" = "EA-12A" ]; then
    consumer_only=false
    if [ "$#" -eq 2 ]; then
        if [ "$2" != "--consumer-only" ]; then
            echo "usage: sh Scripts/check_episode_cutover.sh EA-12A [--consumer-only]" >&2
            exit 2
        fi
        consumer_only=true
    fi

    if ! command -v rg >/dev/null 2>&1; then
        echo "episode cutover EA-12A failed: rg is required" >&2
        exit 2
    fi
    for required_directory in "$project_root/Sources" "$project_root/Tests"; do
        if [ ! -d "$required_directory" ]; then
            echo "episode cutover EA-12A failed: missing scan root $required_directory" >&2
            exit 2
        fi
    done

    failures=0
    scan_count=0
    scan_zero_match() {
        scan_class=$1
        literal=$2
        shift 2
        scan_count=$((scan_count + 1))
        if rg --line-number --fixed-strings -- "$literal" "$@"; then
            echo "episode cutover EA-12A: $scan_class remains: $literal" >&2
            failures=$((failures + 1))
        else
            scan_status=$?
            if [ "$scan_status" -ne 1 ]; then
                echo "episode cutover EA-12A: scan error ($scan_status): $literal" >&2
                failures=$((failures + 1))
            fi
        fi
    }

    scan_zero_match duplicate-ingress "currentEnvironmentState.borderValidation" \
        "$project_root/Sources/PlotterApp" "$project_root/Tests"
    scan_zero_match duplicate-ingress "applicationState.environmentStates[source]?.borderValidation" \
        "$project_root/Sources/PlotterApp" "$project_root/Tests"
    scan_zero_match duplicate-ingress "borderValidationRuntime.replaceSnapshot" \
        "$project_root/Sources" "$project_root/Tests"
    scan_zero_match duplicate-ingress "activeBorderValidationOperation" \
        "$project_root/Sources/PlotterApp" "$project_root/Tests"
    scan_zero_match duplicate-ingress "workspace.borderValidationStep" \
        "$project_root/Tests"
    scan_zero_match duplicate-ingress "workspace.borderValidationAssessment" \
        "$project_root/Tests"
    scan_zero_match duplicate-ingress "workspace.drawingBorderPlan" \
        "$project_root/Tests"

    if [ "$consumer_only" = false ]; then
        scan_zero_match deleted-symbol "var borderValidation: PlotterBorderValidationSnapshot" \
            "$project_root/Sources" "$project_root/Tests"
        scan_zero_match deleted-symbol "func replaceSnapshot(" \
            "$project_root/Sources/PlotterEpisodeRuntime" "$project_root/Tests"
        scan_zero_match deleted-symbol "public func advanceAfterSuccess(" \
            "$project_root/Sources/PlotterEpisodeRuntime"
        scan_zero_match deleted-symbol "public func markExecutionState(" \
            "$project_root/Sources/PlotterEpisodeRuntime"
        scan_zero_match deleted-symbol "public func submitStep(" \
            "$project_root/Sources/PlotterEpisodeRuntime"
        scan_zero_match deleted-symbol "public func submitAcceptComparison(" \
            "$project_root/Sources/PlotterEpisodeRuntime"
        scan_zero_match deleted-symbol "public func submitReject(" \
            "$project_root/Sources/PlotterEpisodeRuntime"
        scan_zero_match deleted-symbol "case retryFrom(" \
            "$project_root/Sources" "$project_root/Tests"
        scan_zero_match deleted-symbol "ContextualStopActionPresentation" \
            "$project_root/Sources" "$project_root/Tests"
        scan_zero_match deleted-symbol "StableWorkflowCapCaptureRunner" \
            "$project_root/Sources" "$project_root/Tests"
        scan_zero_match deleted-symbol "PlotterSystemSerialDeviceDiscoveryAdapter" \
            "$project_root/Sources" "$project_root/Tests"
        scan_zero_match deleted-symbol "borderValidationPayloadSnapshot" \
            "$project_root/Sources" "$project_root/Tests"
        scan_zero_match deleted-symbol "restoreBorderValidationPayload" \
            "$project_root/Sources" "$project_root/Tests"
        for required in 'public func closeAdmissionAndCancel() async' \
            'await liveBorderValidationRuntime.closeAdmissionAndCancel()' \
            'await simulatedBorderValidationRuntime.closeAdmissionAndCancel()'; do
            scan_count=$((scan_count + 1))
            if ! rg --line-number --fixed-strings -- "$required" \
                "$project_root/Sources" "$project_root/Tests" >/dev/null; then
                echo "episode cutover EA-12A: required shutdown join missing: $required" >&2
                failures=$((failures + 1))
            fi
        done
    fi

    if [ "$failures" -ne 0 ]; then
        echo "episode cutover EA-12A failed: $failures superseded paths remain" >&2
        exit 1
    fi
    scope=zero-match
    if [ "$consumer_only" = true ]; then scope=consumer; fi
    echo "episode cutover EA-12A passed: $scan_count $scope scans"
    exit 0
fi

if [ "$1" = "EA-12B" ]; then
    consumer_only=false
    if [ "$#" -eq 2 ]; then
        if [ "$2" != "--consumer-only" ]; then
            echo "usage: sh Scripts/check_episode_cutover.sh EA-12B [--consumer-only]" >&2
            exit 2
        fi
        consumer_only=true
    fi
    if ! command -v rg >/dev/null 2>&1; then
        echo "episode cutover EA-12B failed: rg is required" >&2
        exit 2
    fi
    for required_directory in "$project_root/Sources" "$project_root/Tests"; do
        if [ ! -d "$required_directory" ]; then
            echo "episode cutover EA-12B failed: missing scan root $required_directory" >&2
            exit 2
        fi
    done

    failures=0
    scan_count=0
    scan_zero_match() {
        scan_class=$1
        literal=$2
        shift 2
        scan_count=$((scan_count + 1))
        if rg --line-number --fixed-strings -- "$literal" "$@"; then
            echo "episode cutover EA-12B: $scan_class remains: $literal" >&2
            failures=$((failures + 1))
        else
            scan_status=$?
            if [ "$scan_status" -ne 1 ]; then
                echo "episode cutover EA-12B: scan error ($scan_status): $literal" >&2
                failures=$((failures + 1))
            fi
        fi
    }

    for literal in PlotterApplicationBoundAction currentApplicationActions \
        currentPlotterUIResetPlans applicationAction retainedLearningAction \
        retainedLearningReset ExerciseActionKind PlotterUILearningSemanticAction \
        'static let controllerProbe' 'static let observationStop' 'static let observationRestart' \
        ActionSurfaceOverlayStyleToken 'styleToken(for:' '.discardCameraSamples' \
        'Discard Camera Samples' 'String(describing: action' 'String(describing: kind' \
        submitDynamicLearningAction submitPenInteractionSetpoint 'actionDecisions()' \
        'candidate(ownerID:'; do
        scan_zero_match deleted-symbol "$literal" "$project_root/Sources" "$project_root/Tests"
    done
    scan_zero_match silent-dispatch \
        'guard let request = plotterUIProjection.request(matching: .drawingDraft(intent)) else { return }' \
        "$project_root/Sources/PlotterApp" "$project_root/Tests"

    if [ "$consumer_only" = false ]; then
        for required in PlotterLearningItemIdentity PlotterLearningActionRequest \
            PlotterLearningResetRequest 'case learningAction(' 'case learningReset(' \
            'PlotterLearningUIAuthorityTests'; do
            scan_count=$((scan_count + 1))
            if ! rg --line-number --fixed-strings -- "$required" \
                "$project_root/Sources" "$project_root/Tests" >/dev/null; then
                echo "episode cutover EA-12B: required typed route missing: $required" >&2
                failures=$((failures + 1))
            fi
        done
        scan_count=$((scan_count + 1))
        sink_count=$(rg --no-heading --fixed-strings \
            'public protocol PlotterUIIntentSink' "$project_root/Sources" | wc -l | tr -d ' ')
        if [ "$sink_count" -ne 1 ]; then
            echo "episode cutover EA-12B: expected exactly one public PlotterUIIntentSink; found $sink_count" >&2
            failures=$((failures + 1))
        fi
    fi

    if [ "$failures" -ne 0 ]; then
        echo "episode cutover EA-12B failed: $failures contract violations remain" >&2
        exit 1
    fi
    scope=zero-match
    if [ "$consumer_only" = true ]; then scope=consumer; fi
    echo "episode cutover EA-12B passed: $scan_count $scope scans"
    exit 0
fi

if [ "$1" = "EA-12C" ]; then
    consumer_only=false
    if [ "$#" -eq 2 ]; then
        if [ "$2" != "--consumer-only" ]; then
            echo "usage: sh Scripts/check_episode_cutover.sh EA-12C [--consumer-only]" >&2
            exit 2
        fi
        consumer_only=true
    fi
    if ! command -v rg >/dev/null 2>&1; then
        echo "episode cutover EA-12C failed: rg is required" >&2
        exit 2
    fi
    for required_directory in "$project_root/Sources" "$project_root/Tests"; do
        if [ ! -d "$required_directory" ]; then
            echo "episode cutover EA-12C failed: missing scan root $required_directory" >&2
            exit 2
        fi
    done

    failures=0
    scan_count=0
    scan_zero_match() {
        scan_class=$1
        literal=$2
        shift 2
        scan_count=$((scan_count + 1))
        if rg --line-number --fixed-strings -- "$literal" "$@"; then
            echo "episode cutover EA-12C: $scan_class remains: $literal" >&2
            failures=$((failures + 1))
        else
            scan_status=$?
            if [ "$scan_status" -ne 1 ]; then
                echo "episode cutover EA-12C: scan error ($scan_status): $literal" >&2
                failures=$((failures + 1))
            fi
        fi
    }

    for literal in residualLearningAdmissionID PlotterApplicationResidualIntent \
        PlotterApplicationResidualOperationAdapter runResidualLearningAction \
        PlotterUIController PlotterUIObservation plotterUIControllerRequest \
        plotterUIObservationRequest observationSubmission identityComponent \
        'ownerID.id):' 'application-residual-'; do
        scan_zero_match deleted-symbol "$literal" "$project_root/Sources" "$project_root/Tests"
    done

    if [ "$consumer_only" = false ]; then
        for required in 'public struct PlotterLearningEpisodeID' \
            'public init(rawValue: UUID = UUID())' \
            'public struct PlotterLearningTransitionID' \
            'public let episodeID: PlotterLearningEpisodeID; public let sequence: UInt64' \
            'public enum PlotterLearningRecordRequest' \
            'case reset(PlotterLearningResetRequest)' \
            'public let postTransitionProjection: PlotterLearningPostTransitionProjection' \
            'public func closeAdmissionAndCancel() async' \
            PlotterLearningEpisodeRecord PlotterApplicationLearningTask \
            'learningEpisodeRecord.reserve(' 'learningEpisodeRecord.publish('; do
            scan_count=$((scan_count + 1))
            if ! rg --line-number --fixed-strings -- "$required" \
                "$project_root/Sources" "$project_root/Tests" >/dev/null; then
                echo "episode cutover EA-12C: required typed episode route missing: $required" >&2
                failures=$((failures + 1))
            fi
        done
        scan_count=$((scan_count + 1))
        sink_count=$(rg --no-heading --fixed-strings \
            'public protocol PlotterUIIntentSink' "$project_root/Sources" | wc -l | tr -d ' ')
        if [ "$sink_count" -ne 1 ]; then
            echo "episode cutover EA-12C: expected exactly one public PlotterUIIntentSink; found $sink_count" >&2
            failures=$((failures + 1))
        fi
        scan_count=$((scan_count + 1))
        if ! command -v git >/dev/null 2>&1; then
            echo "episode cutover EA-12C: git is required for Sources deletion evidence" >&2
            failures=$((failures + 1))
        else
            source_numstat=$(git -C "$project_root" diff --numstat -- Sources)
            source_additions=$(printf '%s\n' "$source_numstat" | awk '{ additions += $1 } END { print additions + 0 }')
            source_deletions=$(printf '%s\n' "$source_numstat" | awk '{ deletions += $2 } END { print deletions + 0 }')
            if [ "$source_additions" -ne 1631 ] || [ "$source_deletions" -ne 1600 ]; then
                echo "episode cutover EA-12C: expected reviewed Sources +1631/-1600 safety exception; additions=$source_additions deletions=$source_deletions" >&2
                failures=$((failures + 1))
            fi
        fi
    fi

    if [ "$failures" -ne 0 ]; then
        echo "episode cutover EA-12C failed: $failures contract violations remain" >&2
        exit 1
    fi
    scope=zero-match
    if [ "$consumer_only" = true ]; then scope=consumer; fi
    echo "episode cutover EA-12C passed: $scan_count $scope scans"
    exit 0
fi

PYTHONDONTWRITEBYTECODE=1 exec "$project_root/.VE/bin/python" "$project_root/Scripts/check_episode_cutover.py" "$@"
