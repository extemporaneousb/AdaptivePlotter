#!/usr/bin/env python3
"""Run the exact EA-01 zero-match scan set for one cutover package."""

from __future__ import annotations

import re
import sys
from pathlib import Path

from check_episode_inventory import CUTOVER_PACKAGES, ROOT, ContractError, validate_manifest


LEARNING_RAW_DECISION_INPUTS = re.compile(
    r"\b(?:activeOwnerID|activeAttemptOwner|restartableOwnerID|restartableItem|"
    r"stopDispositionIsLatched|stopDispositionLatched|stickyAmbiguityReason|"
    r"discoveryStageHasFailure|drawingStageHasFailure|savedTrainingCandidateIsPresent|"
    r"startUnavailableReasons|boundaryIsComplete|boundaryHasCenterArrival|"
    r"boundaryCenterArrivalRetryIsRequired|boundaryHasEstimatedCenter|"
    r"acceptedBoundaryDirections|allowedBoundaryDirections|selectedBoundaryDirection|"
    r"sparseState|sparseCollectedClickCount|sparseSavedCheckpointMatchesPaper|"
    r"drawingState|selectedResetPlanIsPresent|resetAllPlanIsPresent|"
    r"resetUnavailableReason|isComplete)\b"
)

LEARNING_SEMANTIC_OUTPUTS = {
    "action": re.compile(
        r"ExerciseActionDescriptor|ExerciseActionStripPresentation|"
        r"PlotterUIActionCandidate|PlotterUILearningActionDecision"
    ),
    "status": re.compile(r"LearningPathStageStatus"),
    "retained-candidate": re.compile(
        r"intent\s*:\s*\.retainedLearning(?:Action|Reset)"
    ),
    "reachability": re.compile(r"\.learningOwner\s*\(|PlotterUIActionReachability"),
}

CANONICAL_LEARNING_INPUTS = (
    "PlotterUILearningActionabilityProjection",
    "PlotterUILearningActionStripDecision",
    "PlotterUILearningActionDecision",
    "PlotterUILearningItemDecision",
    "PlotterUILearningItemStatus",
    "PlotterUILearningSemanticAction",
)


def braced_functions(text: str) -> list[tuple[str, str, str]]:
    """Return computed vars/functions as (name, declaration header, body)."""
    declarations: list[tuple[str, str, str]] = []
    pattern = re.compile(
        r"^\s*(?:(?:public|private|fileprivate|internal|package|static|class|"
        r"mutating|nonmutating|nonisolated|override)\s+)*(?:func|var)\s+"
        r"([A-Za-z_][A-Za-z0-9_]*)\b",
        re.MULTILINE,
    )
    for match in pattern.finditer(text):
        brace = text.find("{", match.end())
        if brace < 0:
            continue
        header = text[match.start():brace]
        # Do not consume a later declaration when this is a stored property.
        signature_tail = text[match.end():brace]
        if re.search(
            r"\n\s*(?:func|var|struct|class|enum|extension)\b",
            signature_tail,
        ):
            continue
        depth = 1
        index = brace + 1
        while index < len(text) and depth:
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
            index += 1
        if depth:
            raise ContractError(f"unterminated App Learning declaration: {match.group(1)}")
        declarations.append((match.group(1), header, text[brace + 1:index - 1]))
    return declarations


def returned_type(header: str) -> str | None:
    function_return = re.search(r"->\s*([A-Za-z_][A-Za-z0-9_<>?.\[\]]*)", header)
    if function_return:
        return re.sub(r"[?\[\]]", "", function_return.group(1)).split("<", 1)[0]
    property_type = re.search(r"\bvar\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*([A-Za-z_][A-Za-z0-9_]*)", header)
    return property_type.group(1) if property_type else None


def validate_ea09_learning_authority(
    plotter_ui_text: str,
    app_sources: dict[str, str],
) -> None:
    for token in (
        "public struct PlotterUILearningActionabilityCompiler",
        "maximumItemVisitCount",
        "public let currentOwnerID: String?",
        "public let strips: [PlotterUILearningActionStripDecision]",
        "public let selectedResetPlanIsReachable: Bool",
        "case learningOwner(String)",
        "case .learningOwner(let owner)",
    ):
        if token not in plotter_ui_text:
            raise ContractError(f"EA-09 canonical PlotterUI Learning authority missing: {token}")

    app_text = "\n".join(app_sources.values())
    for token in (
        "struct PlotterLearningActionabilityFactAdapter",
        "PlotterUILearningActionabilityCompiler().compile",
        "struct PlotterLearningDetailedPresentationNormalizer",
        "actionability: PlotterUILearningActionabilityProjection",
    ):
        if token not in app_text:
            raise ContractError(f"EA-09 App Learning adapter topology missing: {token}")

    declarations: list[tuple[str, str, str, str]] = []
    for path, text in app_sources.items():
        declarations.extend((path, name, header, body) for name, header, body in braced_functions(text))

    tainted_types: set[str] = set()
    primitive_types = {"Bool", "String", "Int", "Double", "UUID", "Void"}
    for _path, _name, header, body in declarations:
        combined = f"{header}\n{body}"
        if not LEARNING_RAW_DECISION_INPUTS.search(combined):
            continue
        output = returned_type(header)
        if output and output not in primitive_types and output != "PlotterUILearningActionabilityFacts":
            tainted_types.add(output)

    for path, name, header, body in declarations:
        combined = f"{header}\n{body}"
        outputs = sorted(
            category
            for category, pattern in LEARNING_SEMANTIC_OUTPUTS.items()
            if pattern.search(combined)
        )
        if (
            re.search(r"(?:availability|unavailable)", name, re.IGNORECASE)
            and returned_type(header) in {"String", "IntentAvailability"}
        ):
            outputs.append("availability")
            outputs.sort()
        if not outputs:
            continue
        has_raw_input = LEARNING_RAW_DECISION_INPUTS.search(combined) is not None
        consumes_tainted_split = any(
            re.search(rf"\b{re.escape(type_name)}\b", header)
            for type_name in tainted_types
        )
        consumes_canonical_decision = any(token in header for token in CANONICAL_LEARNING_INPUTS)
        returns_canonical_facts = returned_type(header) == "PlotterUILearningActionabilityFacts"
        if (has_raw_input or consumes_tainted_split) and not (
            consumes_canonical_decision or returns_canonical_facts
        ):
            reason = "raw Learning decision inputs" if has_raw_input else "split App decision mapping"
            raise ContractError(
                f"EA-09 App Learning authority bypass in {path}:{name}: "
                f"{reason} -> {','.join(outputs)}"
            )


def matching_paths(specification: str) -> list[Path]:
    paths: set[Path] = set()
    for part in specification.split(","):
        part = part.strip()
        if not part:
            continue
        paths.update(path for path in ROOT.glob(part) if path.is_file())
    return sorted(paths)


CONSUMER_SCAN_CLASSES = {
    "direct-port",
    "duplicate-ingress",
    "forbidden-import",
    "forbidden-conformance",
    "environment-branch",
}


def main(argv: list[str]) -> int:
    try:
        _rows, scans = validate_manifest()
    except (OSError, ContractError) as error:
        print(f"episode cutover: invalid EA-01 manifest: {error}", file=sys.stderr)
        return 1
    if argv == ["--validate-manifest"]:
        print("episode cutover manifest passed")
        return 0
    consumer_only = len(argv) == 2 and argv[1] == "--consumer-only"
    if (len(argv) not in {1, 2} or not argv or argv[0] not in CUTOVER_PACKAGES or (len(argv) == 2 and not consumer_only)):
        allowed = ", ".join(sorted(CUTOVER_PACKAGES))
        print(f"usage: check_episode_cutover.py <PACKAGE-ID> [--consumer-only]; allowed: {allowed}", file=sys.stderr)
        return 2
    package = argv[0]
    failures: list[str] = []
    package_scans = [row for row in scans if row["package"] == package]
    if consumer_only:
        package_scans = [row for row in package_scans if row["class"] in CONSUMER_SCAN_CLASSES]
    for scan in package_scans:
        literal = scan["literal"]
        for path in matching_paths(scan["paths"]):
            for line_number, line in enumerate(
                path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1
            ):
                if literal in line:
                    failures.append(
                        f"{scan['class']} {path.relative_to(ROOT)}:{line_number}: {literal}"
                    )
    if failures:
        print(f"episode cutover {package}: superseded paths remain", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1
    if package == "EA-09":
        try:
            validate_ea09_learning_authority(
                (ROOT / "Sources/PlotterUI/PlotterUI.swift").read_text(encoding="utf-8"),
                {
                    str(path.relative_to(ROOT)): path.read_text(
                        encoding="utf-8", errors="replace"
                    )
                    for path in sorted((ROOT / "Sources/PlotterApp").glob("*.swift"))
                },
            )
        except (OSError, ContractError) as error:
            print(f"episode cutover EA-09: {error}", file=sys.stderr)
            return 1
    scope = "consumer" if consumer_only else "zero-match"
    print(f"episode cutover {package} passed: {len(package_scans)} {scope} scans")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
