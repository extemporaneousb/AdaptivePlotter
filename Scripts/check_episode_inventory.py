#!/usr/bin/env python3
"""Validate EA-01's canonical current-source inventory and cutover scans."""

from __future__ import annotations

import re
import sys
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PLAN = ROOT / "docs" / "EPISODE_ARCHITECTURE_EXECUTION_PLAN.md"

INVENTORY_HEADER = [
    "Inventory ID",
    "Category",
    "Current source seams",
    "Current owner and behavior",
    "Disposition",
    "Cutover",
    "Focused command",
]
SCAN_HEADER = ["Package", "Scan class", "Paths", "Zero-match literal"]
LEDGER_HEADER = [
    "ID",
    "Status",
    "Dependencies",
    "Class",
    "Atomic package outcome",
    "Required gates",
]

CATEGORIES = {
    "semantic-intent",
    "guard",
    "authority-owner",
    "direct-port",
    "environment-branch",
    "task-cancel-owner",
    "persistence-path",
    "ui-consumer",
    "high-level-fixture",
}
DISPOSITIONS = {"retain", "adapt", "delete"}
CUTOVER_PACKAGES = {
    "EA-04",
    "EA-06",
    "EA-07",
    "EA-08A",
    "EA-08B",
    "EA-09",
    "FIX-03",
    "EA-10A",
    "EA-10B",
    "EA-10C",
    "EA-10D",
    "EA-10E",
    "EA-10F",
    "EA-10G",
    "EA-11A",
    "EA-11B",
    "EA-11C",
}
ASSIGNABLE_PACKAGES = CUTOVER_PACKAGES | {
    "FIX-00",
    "FIX-01",
    "EA-05A",
    "EA-05B",
    "EA-05C",
}
FOCUSED_COMMANDS = {
    "FIX-00": "swift test --filter CoordinateAcceptancePolicyTests",
    "FIX-01": "swift test --filter TipApplicabilityEvidencePolicyTests",
    "EA-05A": "swift test --filter PlotterRecordingStoreTests",
    "EA-05B": "swift test --filter PlotterRecordingReplayTests",
    "EA-05C": "swift test --filter PlotterIncidentPackageTests",
    "EA-04": "swift test --filter PlotterPointSelectionEpisodeTests",
    "EA-06": "swift test --filter PlotterManualMotionEpisodeTests",
    "EA-07": "swift test --filter PlotterCausalEpisodeEnvironmentTests",
    "EA-08A": "swift test --filter PlotterDrawingDraftEpisodeTests",
    "EA-08B": "swift test --filter PlotterDrawingRunEpisodeTests",
    "EA-09": "swift test --filter PlotterEpisodeUIActionabilityTests",
    "FIX-03": "swift test --filter PlotterDrawingRunEpisodeTests",
    "EA-10A": "swift test --filter PlotterPenInteractionEpisodeTests",
    "EA-10B": "swift test --filter PlotterBoundaryEpisodeTests",
    "EA-10C": "swift test --filter PlotterCameraCalibrationEpisodeTests",
    "EA-10D": "swift test --filter PlotterTipCalibrationEpisodeTests",
    "EA-10E": "swift test --filter PlotterBorderValidationEpisodeTests",
    "EA-10F": "swift test --filter PlotterArtifactResetEpisodeTests",
    "EA-10G": "swift test --filter PlotterSpeechEffectEpisodeTests",
    "EA-11A": "swift test --filter PlotterControllerSessionEpisodeTests",
    "EA-11B": "swift test --filter PlotterObservationConfigurationEpisodeTests",
    "EA-11C": "swift test --filter PlotterEpisodeCompositionTests",
}
SCAN_CLASSES = {
    "deleted-symbol",
    "forbidden-import",
    "forbidden-conformance",
    "direct-port",
    "duplicate-ingress",
    "task-owner",
    "fixture",
    "environment-branch",
}

ACTION_ENUMS = {
    "ExerciseActionKind": ROOT / "Sources/PlotterApp/LearningPathPresentation.swift",
    "PlotterArtifactResetIntent": ROOT / "Sources/PlotterEpisodeRuntime/PlotterArtifactResetRuntime.swift",
    "PlotterBorderValidationIntent": ROOT / "Sources/PlotterEpisodeRuntime/PlotterBorderValidationRuntime.swift",
    "PlotterDrawingDraftIntent":
        ROOT / "Sources/PlotterEpisodeModel/PlotterDrawingDraft.swift",
    "VideoSettingsVisibilityAction": ROOT / "Sources/PlotterApp/WorkbenchLayout.swift",
}
PORT_STRUCTS = {
    "WorkflowTelemetryActions",
    "AcceptedLearningPathCheckpointActions",
}
TASK_FILES = {
    "OperatorWorkspace": ROOT / "Sources/PlotterApp/OperatorWorkspace.swift",
    "CameraSourceSession": ROOT / "Sources/PlotterApp/CameraComposition.swift",
    "PlotterObservationConfigurationRuntime": ROOT / "Sources/PlotterApp/PlotterObservationConfigurationRuntime.swift",
    "AdaptivePlotterApplicationDelegate": ROOT / "Sources/PlotterApp/AdaptivePlotterApp.swift",
    "CameraCapture": ROOT / "Sources/PlotterRuntime/CameraCapture.swift",
    "PlotterSceneAnalysisPipeline": ROOT / "Sources/PlotterRuntime/PlotterSceneAnalysisPipeline.swift",
    "PlotterCameraCalibrationRuntime": ROOT / "Sources/PlotterEpisodeRuntime/PlotterCameraCalibrationRuntime.swift",
    "PlotterTipCalibrationRuntime": ROOT / "Sources/PlotterEpisodeRuntime/PlotterTipCalibrationRuntime.swift",
    "PlotterBorderValidationRuntime": ROOT / "Sources/PlotterEpisodeRuntime/PlotterBorderValidationRuntime.swift",
    "PlotterArtifactResetRuntime": ROOT / "Sources/PlotterEpisodeRuntime/PlotterArtifactResetRuntime.swift",
    "MachineController": ROOT / "Sources/PlotterRuntime/MachineController.swift",
    "NativeSpeechAnnouncer": ROOT / "Sources/PlotterRuntime/SpeechAnnouncements.swift",
    "RunInterpreter": ROOT / "Sources/PlotterRuntime/RunInterpreter.swift",
}


class ContractError(ValueError):
    pass


def fail(message: str) -> None:
    raise ContractError(message)


def cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def table(text: str, header: list[str]) -> list[list[str]]:
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if cells(line) != header:
            continue
        rows: list[list[str]] = []
        for candidate in lines[index + 2 :]:
            if not candidate.startswith("|"):
                break
            row = cells(candidate)
            if len(row) != len(header):
                fail(f"malformed {' / '.join(header)} row: {candidate}")
            rows.append(row)
        return rows
    fail(f"missing table: {' / '.join(header)}")


def uncode(value: str) -> str:
    value = value.strip()
    if value.startswith("`") and value.endswith("`"):
        return value[1:-1]
    return value


def seams(cell: str) -> set[str]:
    return {uncode(value) for value in cell.split("<br>") if value.strip()}


def braced_block(text: str, declaration: str) -> str:
    match = re.search(rf"\b(?:enum|struct)\s+{re.escape(declaration)}\b[^{{]*{{", text)
    if match is None:
        fail(f"source declaration missing: {declaration}")
    depth = 1
    index = match.end()
    while index < len(text) and depth:
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
        index += 1
    if depth:
        fail(f"unterminated source declaration: {declaration}")
    return text[match.end() : index - 1]


def enum_cases(path: Path, name: str) -> set[str]:
    block = braced_block(path.read_text(encoding="utf-8"), name)
    return set(re.findall(r"^\s*case\s+([A-Za-z_][A-Za-z0-9_]*)", block, re.MULTILINE))


def port_fields(name: str, workspace_text: str) -> set[str]:
    block = braced_block(workspace_text, name)
    return set(re.findall(r"^\s*let\s+([A-Za-z_][A-Za-z0-9_]*)\s*:", block, re.MULTILINE))


def inventory_rows(plan: str) -> tuple[list[dict[str, object]], set[str]]:
    raw_rows = table(plan, INVENTORY_HEADER)
    if not raw_rows:
        fail("current-source inventory is empty")
    result: list[dict[str, object]] = []
    all_seams: set[str] = set()
    seen_ids: set[str] = set()
    for row in raw_rows:
        inventory_id, category, seam_cell, owner, disposition, package_cell, command_cell = row
        package = uncode(package_cell)
        command = uncode(command_cell)
        row_seams = seams(seam_cell)
        if not re.fullmatch(r"(?:INT|GRD|OWN|PRT|MOD|TSK|PER|UI|FIX)-[0-9]{3}", inventory_id):
            fail(f"invalid inventory ID: {inventory_id}")
        if inventory_id in seen_ids:
            fail(f"duplicate inventory ID: {inventory_id}")
        seen_ids.add(inventory_id)
        if category not in CATEGORIES:
            fail(f"{inventory_id} has invalid category {category}")
        if not row_seams:
            fail(f"{inventory_id} has no exact current source seam")
        if not owner or owner in {"TBD", "multiple"}:
            fail(f"{inventory_id} lacks one current owner")
        if disposition not in DISPOSITIONS:
            fail(f"{inventory_id} has invalid disposition {disposition}")
        if package not in ASSIGNABLE_PACKAGES:
            fail(f"{inventory_id} has invalid cutover package {package}")
        if command != FOCUSED_COMMANDS[package]:
            fail(
                f"{inventory_id} focused command for {package} must be "
                f"{FOCUSED_COMMANDS[package]!r}; found {command!r}"
            )
        duplicate_seams = all_seams.intersection(row_seams)
        if duplicate_seams:
            fail(f"source seams assigned more than once: {sorted(duplicate_seams)}")
        all_seams.update(row_seams)
        result.append(
            {
                "id": inventory_id,
                "category": category,
                "seams": row_seams,
                "owner": owner,
                "disposition": disposition,
                "package": package,
                "command": command,
            }
        )
    counts = Counter(str(row["category"]) for row in result)
    missing_categories = sorted(CATEGORIES.difference(counts))
    if missing_categories:
        fail(f"inventory categories are empty: {missing_categories}")
    return result, all_seams


def require_exact_family(
    label: str,
    actual: set[str],
    assigned: set[str],
) -> None:
    missing = sorted(actual.difference(assigned))
    extra = sorted(assigned.difference(actual))
    if missing or extra:
        fail(f"{label} coverage mismatch; missing={missing}, extra={extra}")


def validate_action_cases(rows: list[dict[str, object]]) -> None:
    intent_seams = set().union(
        *(row["seams"] for row in rows if row["category"] == "semantic-intent")
    )
    for name, path in ACTION_ENUMS.items():
        actual = {f"{name}.{case}" for case in enum_cases(path, name)}
        assigned = {seam for seam in intent_seams if seam.startswith(f"{name}.")}
        require_exact_family(f"{name} cases", actual, assigned)


def validate_guards(rows: list[dict[str, object]]) -> None:
    text = (ROOT / "Sources/PlotterApp/OperatorWorkspace.swift").read_text(encoding="utf-8")
    actual_names = set(
        re.findall(
            r"^\s*(?:private\s+)?(?:var|func)\s+([A-Za-z_][A-Za-z0-9_]*UnavailableReason)\b",
            text,
            re.MULTILINE,
        )
    )
    actual = {f"OperatorWorkspace.{name}" for name in actual_names}
    guard_seams = set().union(*(row["seams"] for row in rows if row["category"] == "guard"))
    assigned = {seam for seam in guard_seams if seam.startswith("OperatorWorkspace.") and seam.endswith("UnavailableReason")}
    require_exact_family("OperatorWorkspace named guards", actual, assigned)


def validate_ports(rows: list[dict[str, object]]) -> None:
    text = (ROOT / "Sources/PlotterApp/OperatorWorkspace.swift").read_text(encoding="utf-8")
    actual: set[str] = set()
    for name in PORT_STRUCTS:
        actual.update(f"{name}.{field}" for field in port_fields(name, text))
    port_seams = set().union(*(row["seams"] for row in rows if row["category"] == "direct-port"))
    assigned = {seam for seam in port_seams if seam.split(".", 1)[0] in PORT_STRUCTS}
    require_exact_family("injected direct ports", actual, assigned)


def task_names(owner: str, path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8")
    visibility = r"(?:private\s+)?" if owner == "RunInterpreter" else r"private\s+"
    names = set(
        re.findall(
            rf"^\s*(?:@ObservationIgnored\s+)?{visibility}var\s+"
            r"([A-Za-z_][A-Za-z0-9_]*)\s*:\s*Task<",
            text,
            re.MULTILINE,
        )
    )
    return {f"{owner}.{name}" for name in names}


def validate_tasks(rows: list[dict[str, object]]) -> None:
    actual = set().union(*(task_names(owner, path) for owner, path in TASK_FILES.items()))
    task_seams = set().union(
        *(row["seams"] for row in rows if row["category"] == "task-cancel-owner")
    )
    assigned = actual.intersection(task_seams)
    require_exact_family("declared Task owners", actual, assigned)


def validate_ui_consumers(rows: list[dict[str, object]]) -> None:
    actual: set[str] = set()
    for path in (ROOT / "Sources/PlotterApp").glob("*.swift"):
        if path.name == "OperatorWorkspace.swift":
            continue
        text = path.read_text(encoding="utf-8")
        actual.update(
            f"UI.{name}"
            for name in re.findall(r"\b(?:workspace|actionWorkspace)\.([A-Za-z_][A-Za-z0-9_]*)", text)
        )
    ui_seams = set().union(*(row["seams"] for row in rows if row["category"] == "ui-consumer"))
    assigned = {seam for seam in ui_seams if seam.startswith("UI.")}
    require_exact_family("direct SwiftUI OperatorWorkspace consumers", actual, assigned)


def validate_source_seams(rows: list[dict[str, object]]) -> None:
    corpus = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for root in (ROOT / "Sources", ROOT / "Tests")
        for path in root.rglob("*.swift")
    )
    for row in rows:
        for seam in row["seams"]:
            token = seam.rsplit(".", 1)[-1]
            if token not in corpus:
                fail(f"{row['id']} source seam is not present in current Swift source: {seam}")


def scan_rows(plan: str) -> list[dict[str, str]]:
    result: list[dict[str, str]] = []
    identities: set[tuple[str, str, str, str]] = set()
    for package_cell, scan_class, paths_cell, literal_cell in table(plan, SCAN_HEADER):
        package = uncode(package_cell)
        paths = uncode(paths_cell)
        literal = uncode(literal_cell)
        identity = (package, scan_class, paths, literal)
        if identity in identities:
            fail(f"duplicate cutover scan: {identity}")
        identities.add(identity)
        if package not in CUTOVER_PACKAGES:
            fail(f"cutover scan references non-cutover package {package}")
        if scan_class not in SCAN_CLASSES:
            fail(f"{package} has invalid scan class {scan_class}")
        if not paths or paths.startswith("/") or ".." in Path(paths).parts:
            fail(f"{package} has unsafe scan paths {paths!r}")
        if not literal or literal in {"TBD", "TODO"}:
            fail(f"{package} has an empty or deferred zero-match literal")
        result.append(
            {"package": package, "class": scan_class, "paths": paths, "literal": literal}
        )
    missing_packages = sorted(CUTOVER_PACKAGES.difference(row["package"] for row in result))
    if missing_packages:
        fail(f"cutover packages lack exact scans: {missing_packages}")
    missing_classes = sorted(SCAN_CLASSES.difference(row["class"] for row in result))
    if missing_classes:
        fail(f"cutover scan classes are unused: {missing_classes}")
    return result


def completed_assignable_packages(plan: str) -> set[str]:
    completed: set[str] = set()
    for package_id, status, _dependencies, _execution_class, _outcome, _gates in table(
        plan, LEDGER_HEADER
    ):
        if package_id in ASSIGNABLE_PACKAGES and status == "complete":
            completed.add(package_id)
    return completed


def validate_manifest() -> tuple[list[dict[str, object]], list[dict[str, str]]]:
    plan = PLAN.read_text(encoding="utf-8")
    rows, _ = inventory_rows(plan)
    completed_packages = completed_assignable_packages(plan)
    live_rows = [
        row
        for row in rows
        if not (
            row["disposition"] == "delete"
            and row["package"] in completed_packages
        )
    ]
    validate_action_cases(live_rows)
    validate_guards(live_rows)
    validate_ports(live_rows)
    validate_tasks(live_rows)
    validate_ui_consumers(live_rows)
    validate_source_seams(live_rows)
    scans = scan_rows(plan)
    return rows, scans


def main() -> int:
    try:
        rows, scans = validate_manifest()
    except (OSError, ContractError) as error:
        print(f"episode inventory: {error}", file=sys.stderr)
        return 1
    print(
        "episode inventory passed: "
        f"{len(rows)} stable entries, {len(scans)} exact cutover scans"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
