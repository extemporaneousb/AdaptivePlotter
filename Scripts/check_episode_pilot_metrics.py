#!/usr/bin/env python3
"""Fail-closed, source-derived EA-01 to current Pilot metric manifests."""

from __future__ import annotations

import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Mapping


ROOT = Path(__file__).resolve().parent.parent
BASELINE_COMMIT = "96253197a42dc6052ef76ad53c4c94c1c5f745a1"

OPERATOR = "Sources/PlotterApp/OperatorWorkspace.swift"
DRAWING_ACTIONS = "Sources/PlotterApp/DrawingStudioPresentation.swift"
COMPARISON_ACTIONS = "Sources/PlotterApp/CompletedComparisonReviewPresentation.swift"
LEARNING_ACTIONS = "Sources/PlotterEpisodeModel/PlotterIntent.swift"
UI_SINK = "Sources/PlotterUI/PlotterUI.swift"


class MetricError(ValueError):
    pass


def fail(message: str) -> None:
    raise MetricError(message)


@dataclass(frozen=True, order=True)
class Symbol:
    path: str
    container: str
    kind: str
    member: str

    @property
    def identity(self) -> str:
        return f"{self.path}:{self.container}.{self.member}"


@dataclass(frozen=True)
class Family:
    identity: str
    members: tuple[Symbol, ...]


@dataclass(frozen=True)
class MetricResult:
    baseline: tuple[str, ...]
    current: tuple[str, ...]


def function(path: str, container: str, member: str) -> Symbol:
    return Symbol(path, container, "func", member)


def enum_case(path: str, container: str, member: str) -> Symbol:
    return Symbol(path, container, "case", member)


def prop(path: str, container: str, member: str) -> Symbol:
    return Symbol(path, container, "property", member)


def closure(path: str, container: str, member: str) -> Symbol:
    return Symbol(path, container, "closure", member)


def ow_func(member: str) -> Symbol:
    return function(OPERATOR, "OperatorWorkspace", member)


def exercise(member: str) -> Symbol:
    return enum_case(LEARNING_ACTIONS, "PlotterLearningAction", member)


def drawing(member: str) -> Symbol:
    return enum_case(DRAWING_ACTIONS, "DrawingStudioAction", member)


def comparison(member: str) -> Symbol:
    return enum_case(COMPARISON_ACTIONS, "CompletedComparisonReviewAction", member)


# Inclusion rule: the independent-admission unit is one immutable EA-01 INT
# family, not each enum case or each later typed runtime. INT-019 is excluded
# because it is window-local visibility with no application admission. The
# current units are the application lifecycle family and the one public
# projection-bound PlotterUIIntentSink family; forwarding into typed feature
# runtimes is excluded because those runtimes retain their own admission.
BASELINE_ADMISSION_FAMILIES = (
    Family("INT-001", (ow_func("performApplicationStartup"), ow_func("shutdown"))),
    Family("INT-002", tuple(ow_func(name) for name in (
        "selectSerialDevice", "performControllerConnectionAction",
        "connectSelectedController", "disconnectMachineSession",
    ))),
    Family("INT-003", tuple(ow_func(name) for name in (
        "requestPassiveProbe", "clearControllerAlarm", "performMotionAuthorizationAction",
    ))),
    Family("INT-004", (ow_func("requestJog"), ow_func("stopManualMotion"))),
    Family("INT-005", (ow_func("requestPenActuation"),)),
    Family("INT-006", (ow_func("selectToolContactPoint"),)),
    Family("INT-007", (ow_func("toggleLearningMode"),)),
    Family("INT-008", tuple(drawing(name) for name in (
        "selectCatalogItem", "setParameter", "placeAtCameraPoint", "setUniformScale",
        "setRotationDegrees", "centerInDrawableRegion",
    )) + (comparison("openDrawingStudio"),)),
    Family("INT-009", tuple(drawing(name) for name in (
        "run", "stop", "reviewRun", "resumeLivePreview", "newRun",
    )) + tuple(comparison(name) for name in ("reviewComparison", "resumeLivePreview"))),
    Family("INT-010", (exercise("setPenSetpoint"), ow_func("beginPenInteraction"))),
    Family("INT-011", tuple(exercise(name) for name in (
        "redoBoundary", "recordAnotherBoundaryAttempt", "selectDirection",
        "moveToEstimatedCenter",
    )) + (ow_func("beginPairedBoundarySide"),)),
    Family("INT-012", tuple(exercise(name) for name in (
        "runCameraCalibrationAndBuildProposal", "acceptCameraCalibrationProposal",
        "rejectCameraCalibrationProposal",
    ))),
    Family("INT-013", tuple(exercise(name) for name in (
        "drawFourCornerTipCircles", "undoLastSparseTipClick", "clearSparseTipClicks",
        "revalidateTipCalibrationCheckpoint", "acceptTipCalibrationProposal",
        "rejectTipCalibrationProposal", "retryTipCalibrationCommit",
    ))),
    Family("INT-014", (ow_func("runObservedDrawingTrial"),)),
    Family("INT-015", tuple(exercise(name) for name in (
        "useSavedTraining", "startNewLearning", "restart", "redoThisStep",
        "recordAnotherAttempt", "paperReplaced",
    )) + (ow_func("performResetAllLearning"),)),
    Family("INT-016", (ow_func("announceAdvisory"),)),
    Family("INT-017", tuple(ow_func(name) for name in (
        "switchFrameMode", "selectAndStartCamera", "setVisionAnalysisCadence",
        "setVideoAnalysisRegion", "setOverlay",
    ))),
    Family("INT-018", tuple(exercise(name) for name in (
        "start", "choice", "cancel", "stop",
    )) + (ow_func("performExerciseAction"),)),
)

CURRENT_ADMISSION_FAMILIES = (
    Family("APPLICATION-LIFECYCLE", (
        function(OPERATOR, "PlotterApplicationRuntime", "performApplicationStartup"),
        function(OPERATOR, "PlotterApplicationRuntime", "shutdown"),
    )),
    Family("PLOTTER-UI-SINK", (
        function(UI_SINK, "PlotterUIIntentSink", "submitPlotterUIRequest"),
        function(OPERATOR, "PlotterApplicationRuntime", "submitPlotterUIRequest"),
    )),
)


# Inclusion rule: direct stored Swift.Task properties on the legacy
# OperatorWorkspace only. Tasks retained by typed runtimes, lower device owners,
# and the application delegate are deliberately outside this literal metric.
BASELINE_TASKS = tuple(prop(OPERATOR, "OperatorWorkspace", name) for name in (
    "penSetpointActuationTask",
    "activeLearningActionTask",
    "frameTask",
    "visionUpdateTask",
    "savedTrainingComparisonTask",
    "penCapAcceptedClickContinuationTask",
    "penCapVisionReconfigurationTask",
    "boundaryMotionTask",
    "currentCameraCalibrationTask",
))


# Inclusion rule: the two application-owned EA-01 environment/effect-owner
# families MOD-001 and MOD-002. MOD-003 is explicitly excluded because the
# causal simulator is a retained typed environment owner, not a duplicate root
# branch. A scalar current projection selector is not an effect-owner family.
BASELINE_ENVIRONMENT_FAMILIES = (
    Family("MOD-001", (
        prop(OPERATOR, "OperatorWorkspace", "frameMode"),
        ow_func("requestSimulatedRelativeJog"),
        ow_func("executeSimulatedBoundaryMotion"),
    )),
    Family("MOD-002", tuple(prop(OPERATOR, "OperatorWorkspace", name) for name in (
        "liveLearningSession", "simulatedLearningSession", "activeLearningSession",
    ))),
)


# Inclusion rule: the exact stored effect capabilities in EA-01's
# PRT-001...PRT-007 closure facades: 39 inline @Sendable fields plus
# CameraActions.captureStableWorkflowCap, whose StableWorkflowCapCaptureRunner
# stores the fortieth closure. Initializer parameters, nominal protocol
# requirements, pure callbacks, persistence preference closures classified by
# PER rows, and retained lower-owner methods are excluded. The candidate scan
# rejects every stored @Sendable member in this application-root source file,
# so a replacement closure bag cannot escape by changing its type name.
PRT_MEMBERS = {
    "MachineActions": (
        "select", "snapshot", "requestPassiveProbe", "requestControllerAlarmClear",
        "activateMotionGuard", "deactivateMotionGuard", "beginRelativeJog",
        "beginDrawingStroke", "beginDrawingPlan", "requestPenActuation",
        "beginBoundaryMotion", "requestJogCancel", "disconnect",
    ),
    "CameraActions": (
        "discover", "select", "start", "stop", "restart", "snapshot", "frames",
        "inspectWorkflowScene", "captureFrame", "captureStableWorkflowCap",
        "setSceneAnalysisRegion", "setPenCapColor", "setAutomaticInspection",
        "analysisUpdates", "visionDiagnostics", "observePlannedDrawingInk",
    ),
    "AnnouncementActions": ("announce", "cancelForShutdown"),
    "WorkflowTelemetryActions": ("record",),
    "AcceptedLearningPathCheckpointActions": ("load", "save", "clear"),
    "DrawingEvidenceActions": ("load", "append"),
    "PaperCoverageActions": ("load", "save", "clear"),
}
BASELINE_DIRECT_EFFECTS = tuple(
    closure(OPERATOR, container, member)
    for container, members in PRT_MEMBERS.items()
    for member in members
)


# Inclusion rule: the exact six failed EA-01 application-root policy/state
# identities recorded by the Pilot inspection. Lifecycle latch/generation
# bookkeeping and typed feature-runtime state are excluded. After EA-11C the
# only qualifying root aggregate is PlotterApplicationState; the current
# frameMode scalar selects a projection and does not own a parallel workflow.
BASELINE_POLICY_STATE = tuple(prop(OPERATOR, "OperatorWorkspace", name) for name in (
    "frameMode",
    "liveLearningSession",
    "simulatedLearningSession",
    "activeStoppableOperation",
    "activeHardwareIntentCount",
    "intentDrainWaiters",
))
CURRENT_POLICY_STATE = (
    prop(OPERATOR, "PlotterApplicationRuntime", "applicationState"),
)


# Inclusion rule: top-level stored application-root cross-owner properties whose
# name denotes an Actions facade, Adapter, Port, FactSource, Session, or a
# wrapper-like Facade/Capabilities/Bundle/Bridge/Relay. observationPreferences
# is the one historical non-suffix port name and is included explicitly.
# Typed feature runtimes are excluded; nominality does not exempt a qualifying
# root property. This makes wrapper aggregation an addition, not a reduction.
BASELINE_ADAPTERS = tuple(prop(OPERATOR, "OperatorWorkspace", name) for name in (
    "machineActions",
    "cameraActions",
    "announcementActions",
    "workflowTelemetryActions",
    "liveAcceptedLearningPathCheckpointActions",
    "liveDrawingEvidenceActions",
    "livePaperCoverageActions",
))
CURRENT_ADAPTERS = tuple(prop(OPERATOR, "PlotterApplicationRuntime", name) for name in (
    "residualOperationAdapter",
    "machineSession",
    "observationPreferences",
    "statePersistencePort",
    "drawingEvidencePort",
    "residualEffectPort",
    "causalSimulatorEffectAdapter",
))


EXPECTED_COUNTS = {
    "independent-admission-sites": (18, 2, "decreased"),
    "workspace-task-owners": (9, 0, "decreased"),
    "environment-mode-branches": (2, 0, "decreased"),
    "direct-effect-calls": (40, 0, "decreased"),
    "operator-workspace-policy-state": (6, 1, "decreased"),
    "operator-workspace-adapters": (7, 7, "not-increased"),
}


def mask_comments_and_literals(text: str) -> str:
    result = list(text)
    index = 0
    block_depth = 0
    line_comment = False
    string = False
    multiline = False
    escaped = False
    while index < len(text):
        pair = text[index:index + 2]
        triple = text[index:index + 3]
        char = text[index]
        if line_comment:
            if char == "\n":
                line_comment = False
            else:
                result[index] = " "
            index += 1
            continue
        if block_depth:
            if pair == "/*":
                result[index:index + 2] = [" ", " "]
                block_depth += 1
                index += 2
            elif pair == "*/":
                result[index:index + 2] = [" ", " "]
                block_depth -= 1
                index += 2
            else:
                if char != "\n":
                    result[index] = " "
                index += 1
            continue
        if string:
            if multiline and triple == '"""':
                result[index:index + 3] = [" ", " ", " "]
                string = False
                multiline = False
                index += 3
            elif not multiline and char == '"' and not escaped:
                result[index] = " "
                string = False
                index += 1
            else:
                if char != "\n":
                    result[index] = " "
                escaped = char == "\\" and not escaped
                if char != "\\":
                    escaped = False
                index += 1
            continue
        if pair == "//":
            result[index:index + 2] = [" ", " "]
            line_comment = True
            index += 2
        elif pair == "/*":
            result[index:index + 2] = [" ", " "]
            block_depth = 1
            index += 2
        elif triple == '"""':
            result[index:index + 3] = [" ", " ", " "]
            string = True
            multiline = True
            index += 3
        elif char == '"':
            result[index] = " "
            string = True
            escaped = False
            index += 1
        else:
            index += 1
    if block_depth or string:
        fail("unterminated comment or string in Swift source")
    return "".join(result)


TYPE_DECLARATION = re.compile(
    r"\b(?:final\s+)?(?:class|struct|actor|enum|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)\b[^\{]*\{"
)
MODIFIERS = (
    r"(?:(?:private|fileprivate|internal|package|public|open|static|class|final|"
    r"nonisolated|lazy|weak|unowned|private\(set\)|public\(set\))\s+)*"
)
ATTRIBUTES = r"(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s+)*"
PROPERTY_LINE = re.compile(
    rf"^\s*{ATTRIBUTES}{MODIFIERS}(let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\b"
)
FUNCTION_LINE = re.compile(
    rf"^\s*{ATTRIBUTES}{MODIFIERS}func\s+([A-Za-z_][A-Za-z0-9_]*)\b"
)
CASE_LINE = re.compile(r"^\s*case\s+([A-Za-z_][A-Za-z0-9_]*)\b")


def container_body(source: str, container: str, *, allow_absent: bool = False) -> str | None:
    masked = mask_comments_and_literals(source)
    declaration = re.search(
        rf"\b(?:final\s+)?(?:class|struct|actor|enum|protocol)\s+{re.escape(container)}\b[^\{{]*\{{",
        masked,
    )
    if declaration is None:
        if allow_absent:
            return None
        fail(f"missing Swift container {container}")
    start = declaration.end()
    depth = 1
    index = start
    while index < len(masked) and depth:
        if masked[index] == "{":
            depth += 1
        elif masked[index] == "}":
            depth -= 1
        index += 1
    if depth:
        fail(f"unbalanced Swift container {container}")
    return masked[start:index - 1]


@dataclass(frozen=True)
class DirectProperty:
    name: str
    declaration: str
    stored: bool


def direct_inventory(source: str, container: str, *, allow_absent: bool = False) -> tuple[
    set[str], set[str], dict[str, DirectProperty]
]:
    body = container_body(source, container, allow_absent=allow_absent)
    if body is None:
        return set(), set(), {}
    lines = body.splitlines()
    functions: set[str] = set()
    cases: set[str] = set()
    properties: dict[str, DirectProperty] = {}
    depth = 0
    index = 0
    while index < len(lines):
        line = lines[index]
        if depth == 0:
            function_match = FUNCTION_LINE.match(line)
            case_match = CASE_LINE.match(line)
            property_match = PROPERTY_LINE.match(line)
            if function_match:
                functions.add(function_match.group(1))
            if case_match:
                cases.add(case_match.group(1))
            if property_match:
                name = property_match.group(2)
                declaration_lines = [line]
                lookahead = index + 1
                while lookahead < len(lines) and len(declaration_lines) < 8:
                    candidate = lines[lookahead]
                    if PROPERTY_LINE.match(candidate) or FUNCTION_LINE.match(candidate) or CASE_LINE.match(candidate):
                        break
                    declaration_lines.append(candidate)
                    if "=" in candidate or "{" in candidate:
                        break
                    lookahead += 1
                declaration = "\n".join(declaration_lines)
                stored = "=" in declaration or "{" not in declaration
                if name in properties:
                    fail(f"duplicate direct property {container}.{name}")
                properties[name] = DirectProperty(name, declaration, stored)
        depth += line.count("{") - line.count("}")
        if depth < 0:
            fail(f"negative brace depth in {container}")
        index += 1
    if depth:
        fail(f"nested declarations are unbalanced in {container}")
    return functions, cases, properties


def source_for(files: Mapping[str, str], path: str) -> str:
    try:
        return files[path]
    except KeyError:
        fail(f"manifest source path is absent: {path}")


def verify_symbol(files: Mapping[str, str], symbol: Symbol) -> None:
    source = source_for(files, symbol.path)
    functions, cases, properties = direct_inventory(source, symbol.container)
    if symbol.kind == "func":
        present = symbol.member in functions
    elif symbol.kind == "case":
        present = symbol.member in cases
    elif symbol.kind == "property":
        # Some stable EA-01 families intentionally name a direct computed
        # selector (notably activeLearningSession). Metrics that require
        # storage additionally compare the extracted stored-property set.
        present = symbol.member in properties
    elif symbol.kind == "closure":
        item = properties.get(symbol.member)
        present = bool(
            item and item.stored
            and (
                re.search(
                    rf"\b(?:let|var)\s+{re.escape(symbol.member)}\s*:\s*\(?\s*@Sendable\b",
                    item.declaration,
                )
                or (
                    symbol.member == "captureStableWorkflowCap"
                    and re.search(r"\bStableWorkflowCapCaptureRunner\b", item.declaration)
                )
            )
        )
    else:
        fail(f"unknown symbol kind: {symbol.kind}")
    if not present:
        fail(f"source identity is absent or changed: {symbol.identity} ({symbol.kind})")


def verify_symbols(files: Mapping[str, str], symbols: Iterable[Symbol]) -> tuple[str, ...]:
    identities: list[str] = []
    for symbol in symbols:
        verify_symbol(files, symbol)
        identities.append(symbol.identity)
    if len(identities) != len(set(identities)):
        fail(f"duplicate source identities in manifest: {identities}")
    return tuple(sorted(identities))


def verify_families(files: Mapping[str, str], families: Iterable[Family]) -> tuple[str, ...]:
    identities: list[str] = []
    for family in families:
        if not family.members:
            fail(f"empty identity family: {family.identity}")
        verify_symbols(files, family.members)
        identities.append(family.identity)
    if len(identities) != len(set(identities)):
        fail(f"duplicate family identities: {identities}")
    return tuple(sorted(identities))


def all_type_names(source: str) -> set[str]:
    return {match.group(1) for match in TYPE_DECLARATION.finditer(mask_comments_and_literals(source))}


def stored_sendable_members(files: Mapping[str, str], paths: Iterable[str]) -> tuple[str, ...]:
    found: set[str] = set()
    for path in paths:
        source = source_for(files, path)
        for container in all_type_names(source):
            _functions, _cases, properties = direct_inventory(source, container)
            for item in properties.values():
                if item.stored and (
                    re.search(r"\(?\s*@Sendable\b", item.declaration)
                    or re.search(r":\s*[A-Za-z_][A-Za-z0-9_]*(?:Effect)?Runner\b", item.declaration)
                ):
                    found.add(f"{path}:{container}.{item.name}")
    return tuple(sorted(found))


ADAPTER_SUFFIX = re.compile(
    r"(?:Actions|Adapter|Port|FactSource|Session|Facade|Capabilities|Bundle|Bridge|Relay)$"
)


def qualifying_adapter_properties(files: Mapping[str, str], container: str) -> tuple[str, ...]:
    _functions, _cases, properties = direct_inventory(source_for(files, OPERATOR), container)
    # LearningSession properties are root policy/state (the separate metric),
    # not cross-owner session adapters. machineSession is the lower-owner
    # capability and remains included by the Session suffix.
    policy_sessions = {
        "liveLearningSession", "simulatedLearningSession", "activeLearningSession"
    }
    projection_only = {"currentApplicationActions"}
    operation_state = {"pendingBoundaryStopCapabilities"}
    names = {
        name for name, item in properties.items()
        if item.stored and name not in policy_sessions | projection_only | operation_state and (
            ADAPTER_SUFFIX.search(name) is not None or name == "observationPreferences"
        )
    }
    return tuple(sorted(f"{OPERATOR}:{container}.{name}" for name in names))


def qualifying_current_policy(files: Mapping[str, str]) -> tuple[str, ...]:
    _functions, _cases, properties = direct_inventory(
        source_for(files, OPERATOR), "PlotterApplicationRuntime"
    )
    names = {
        name for name, item in properties.items()
        if item.stored and (
            name == "applicationState"
            or name.endswith("ApplicationState")
            or name in {
                "liveLearningSession", "simulatedLearningSession", "activeLearningSession",
                "activeStoppableOperation", "activeHardwareIntentCount", "intentDrainWaiters",
            }
        )
    }
    return tuple(sorted(
        f"{OPERATOR}:PlotterApplicationRuntime.{name}" for name in names
    ))


def current_environment_families(files: Mapping[str, str]) -> tuple[str, ...]:
    functions, _cases, properties = direct_inventory(
        source_for(files, OPERATOR), "PlotterApplicationRuntime"
    )
    found: set[str] = set()
    if {"requestSimulatedRelativeJog", "executeSimulatedBoundaryMotion"} & functions:
        found.add("MOD-001")
    if {"liveLearningSession", "simulatedLearningSession", "activeLearningSession"} & set(properties):
        found.add("MOD-002")
    return tuple(sorted(found))


def current_workspace_tasks(files: Mapping[str, str]) -> tuple[str, ...]:
    found: set[str] = set()
    for path, source in files.items():
        if not path.startswith("Sources/") or not path.endswith(".swift"):
            continue
        if "OperatorWorkspace" not in all_type_names(source):
            continue
        _functions, _cases, properties = direct_inventory(source, "OperatorWorkspace")
        for item in properties.values():
            if item.stored and re.search(r"\b(?:Swift\s*\.\s*)?Task\s*<", item.declaration):
                found.add(f"{path}:OperatorWorkspace.{item.name}")
    return tuple(sorted(found))


def current_admission(files: Mapping[str, str]) -> tuple[str, ...]:
    expected = verify_families(files, CURRENT_ADMISSION_FAMILIES)
    protocol_functions, _cases, _properties = direct_inventory(
        source_for(files, UI_SINK), "PlotterUIIntentSink"
    )
    if protocol_functions != {"submitPlotterUIRequest"}:
        fail(
            "PlotterUIIntentSink capability set changed; reconcile the admission manifest: "
            f"{sorted(protocol_functions)}"
        )
    return expected


def evaluate_bundles(
    baseline_files: Mapping[str, str], current_files: Mapping[str, str]
) -> dict[str, MetricResult]:
    baseline_admission = verify_families(baseline_files, BASELINE_ADMISSION_FAMILIES)
    current_admission_identities = current_admission(current_files)

    baseline_tasks = verify_symbols(baseline_files, BASELINE_TASKS)
    _functions, _cases, baseline_root_properties = direct_inventory(
        source_for(baseline_files, OPERATOR), "OperatorWorkspace"
    )
    extracted_baseline_tasks = tuple(sorted(
        f"{OPERATOR}:OperatorWorkspace.{name}"
        for name, item in baseline_root_properties.items()
        if item.stored and re.search(r"\b(?:Swift\s*\.\s*)?Task\s*<", item.declaration)
    ))
    if extracted_baseline_tasks != baseline_tasks:
        fail(
            "pinned OperatorWorkspace Task manifest mismatch: "
            f"expected={baseline_tasks}, extracted={extracted_baseline_tasks}"
        )

    baseline_environment = verify_families(baseline_files, BASELINE_ENVIRONMENT_FAMILIES)
    baseline_effects = verify_symbols(baseline_files, BASELINE_DIRECT_EFFECTS)
    baseline_policy = verify_symbols(baseline_files, BASELINE_POLICY_STATE)
    expected_baseline_adapters = verify_symbols(baseline_files, BASELINE_ADAPTERS)
    extracted_baseline_adapters = qualifying_adapter_properties(
        baseline_files, "OperatorWorkspace"
    )
    if extracted_baseline_adapters != expected_baseline_adapters:
        fail(
            "pinned OperatorWorkspace adapter manifest mismatch: "
            f"expected={expected_baseline_adapters}, extracted={extracted_baseline_adapters}"
        )

    expected_current_policy = verify_symbols(current_files, CURRENT_POLICY_STATE)
    extracted_current_policy = qualifying_current_policy(current_files)
    if extracted_current_policy != expected_current_policy:
        fail(
            "current application policy-state manifest mismatch: "
            f"expected={expected_current_policy}, extracted={extracted_current_policy}"
        )

    expected_current_adapters = verify_symbols(current_files, CURRENT_ADAPTERS)
    extracted_current_adapters = qualifying_adapter_properties(
        current_files, "PlotterApplicationRuntime"
    )
    if extracted_current_adapters != expected_current_adapters:
        fail(
            "current application adapter manifest mismatch: "
            f"expected={expected_current_adapters}, extracted={extracted_current_adapters}"
        )

    current_effects = stored_sendable_members(current_files, (OPERATOR,))
    results = {
        "independent-admission-sites": MetricResult(
            baseline_admission, current_admission_identities
        ),
        "workspace-task-owners": MetricResult(
            baseline_tasks, current_workspace_tasks(current_files)
        ),
        "environment-mode-branches": MetricResult(
            baseline_environment, current_environment_families(current_files)
        ),
        "direct-effect-calls": MetricResult(baseline_effects, current_effects),
        "operator-workspace-policy-state": MetricResult(
            baseline_policy, extracted_current_policy
        ),
        "operator-workspace-adapters": MetricResult(
            expected_baseline_adapters, extracted_current_adapters
        ),
    }
    enforce_thresholds(results)
    return results


def enforce_thresholds(
    results: Mapping[str, MetricResult],
    expected: Mapping[str, tuple[int, int, str]] = EXPECTED_COUNTS,
) -> None:
    if set(results) != set(expected):
        fail(
            f"metric name drift: expected={sorted(expected)}, actual={sorted(results)}"
        )
    for name, (baseline_expected, current_expected, requirement) in expected.items():
        result = results[name]
        counts = (len(result.baseline), len(result.current))
        if counts != (baseline_expected, current_expected):
            fail(
                f"{name} identity/count drift: expected={baseline_expected}->{current_expected}, "
                f"actual={counts[0]}->{counts[1]}, baseline={result.baseline}, current={result.current}"
            )
        if requirement == "decreased" and not counts[1] < counts[0]:
            fail(f"{name} did not decrease: {counts[0]}->{counts[1]}")
        if requirement == "not-increased" and not counts[1] <= counts[0]:
            fail(f"{name} increased: {counts[0]}->{counts[1]}")
        if requirement not in {"decreased", "not-increased"}:
            fail(f"unknown metric requirement for {name}: {requirement}")


def git_text(root: Path, commit: str, path: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), "show", f"{commit}:{path}"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        fail(f"cannot read pinned source {commit}:{path}: {result.stderr.strip()}")
    return result.stdout


def baseline_paths() -> tuple[str, ...]:
    symbols = [
        *(symbol for family in BASELINE_ADMISSION_FAMILIES for symbol in family.members),
        *BASELINE_TASKS,
        *(symbol for family in BASELINE_ENVIRONMENT_FAMILIES for symbol in family.members),
        *BASELINE_DIRECT_EFFECTS,
        *BASELINE_POLICY_STATE,
        *BASELINE_ADAPTERS,
    ]
    return tuple(sorted({symbol.path for symbol in symbols}))


def load_baseline(root: Path) -> dict[str, str]:
    return {path: git_text(root, BASELINE_COMMIT, path) for path in baseline_paths()}


def load_current(root: Path) -> dict[str, str]:
    files = {
        path.relative_to(root).as_posix(): path.read_text(encoding="utf-8")
        for path in (root / "Sources").rglob("*.swift")
    }
    for required in (OPERATOR, UI_SINK):
        if required not in files:
            fail(f"current source path is absent: {required}")
    return files


def evaluate(root: Path = ROOT) -> dict[str, MetricResult]:
    return evaluate_bundles(load_baseline(root), load_current(root))


def main() -> int:
    try:
        results = evaluate(ROOT)
    except (OSError, MetricError) as error:
        print(f"episode Pilot metrics failed: {error}", file=sys.stderr)
        return 1
    rendered = ", ".join(
        f"{name}={len(result.baseline)}->{len(result.current)}"
        for name, result in results.items()
    )
    print(f"episode Pilot metrics passed: baseline={BASELINE_COMMIT}; {rendered}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
