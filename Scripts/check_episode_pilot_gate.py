#!/usr/bin/env python3
"""Fail-closed evaluator for the canonical GATE-01 Pilot predicates."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PLAN = Path("docs/EPISODE_ARCHITECTURE_EXECUTION_PLAN.md")
EVIDENCE = Path("docs/CURRENT_EVIDENCE.md")

LEDGER_HEADER = ["ID", "Status", "Dependencies", "Class", "Atomic package outcome", "Required gates"]
INVENTORY_HEADER = [
    "Inventory ID", "Category", "Current source seams", "Current owner and behavior",
    "Disposition", "Cutover", "Focused command",
]
SCAN_HEADER = ["Package", "Scan class", "Paths", "Zero-match literal"]
COMPLETION_HEADER = ["Package", "Blackdog task", "Gate results", "Evidence section"]
CANDIDATE_HEADER = ["Candidate package", "Blackdog task", "Current gate state", "Landing boundary"]
PILOT_HEADER = ["Pilot predicate", "Result", "Evidence"]
METRIC_HEADER = ["Reduction metric", "Baseline", "Current", "Requirement"]

REQUIRED_PACKAGES = (
    "DOC-00", "DOC-01", "EA-01", "FIX-00", "FIX-01", "DOC-02", "EA-02A",
    "EA-02B", "EA-03A", "EA-03B", "EA-05A", "EA-05B", "EA-05C", "EA-04",
    "FIX-02", "EA-06", "EA-07", "EA-08A", "EA-08B", "EA-09",
)
MIGRATED_CUTOVERS = ("EA-04", "EA-06", "EA-07", "EA-08A", "EA-08B", "EA-09")
PREDICATES = {
    "GENERICITY": ("EA-02A/CORE", "EA-02B/PLOTTER-MODEL"),
    "REPLAY": ("EA-05B/REPLAY",),
    "DEVICE-OWNERS": ("EA-05A/RECORDING", "FIX-02/LINK-OBS", "FIX-02/LINK-SAFETY"),
    "ENVIRONMENT-GRAMMAR": ("EA-07/SIM", "EA-09/UI"),
    "SAME-SLICE-DELETION": tuple(f"{package}/DELETE" for package in MIGRATED_CUTOVERS),
    "AUTHORITY-REDUCTION": ("EA-01/INVENTORY", "METRICS/AUTHORITY-REDUCTION"),
    "OBSERVABILITY": ("EA-05C/INCIDENT", "EA-06/MOTION", "EA-09/UI"),
    "WORKSPACE-REDUCTION": ("METRICS/WORKSPACE-REDUCTION",),
    "SAFETY-EVIDENCE": ("FIX-02/LINK-SAFETY", "EA-07/SIM", "EA-09/UI"),
}
METRICS = {
    "independent-admission-sites": "decreased",
    "workspace-task-owners": "decreased",
    "environment-mode-branches": "decreased",
    "direct-effect-calls": "decreased",
    "operator-workspace-policy-state": "decreased",
    "operator-workspace-adapters": "not-increased",
}


class GateError(ValueError):
    pass


def fail(message: str) -> None:
    raise GateError(message)


def cells(line: str) -> list[str]:
    return [value.strip() for value in line.strip().strip("|").split("|")]


def table(text: str, header: list[str], *, required: bool = True) -> list[list[str]]:
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if cells(line) != header:
            continue
        rows: list[list[str]] = []
        for candidate in lines[index + 2:]:
            if not candidate.startswith("|"):
                break
            row = cells(candidate)
            if len(row) != len(header):
                fail(f"malformed table row for {' / '.join(header)}: {candidate}")
            rows.append(row)
        return rows
    if required:
        fail(f"missing table: {' / '.join(header)}")
    return []


def uncode(value: str) -> str:
    value = value.strip()
    return value[1:-1] if value.startswith("`") and value.endswith("`") else value


def code_list(value: str) -> list[str]:
    matches = re.findall(r"`([^`]+)`", value)
    if value != ", ".join(f"`{item}`" for item in matches):
        fail(f"malformed exact token list: {value}")
    return matches


def parse_ledger(plan: str) -> dict[str, dict[str, object]]:
    result: dict[str, dict[str, object]] = {}
    for package, status, dependencies, execution_class, _outcome, gates in table(plan, LEDGER_HEADER):
        if package in result:
            fail(f"duplicate ledger row: {package}")
        result[package] = {
            "status": status,
            "dependencies": [] if dependencies == "none" else [item.strip() for item in dependencies.split(",")],
            "class": execution_class,
            "gates": code_list(gates),
        }
    missing = [package for package in REQUIRED_PACKAGES if package not in result]
    if missing:
        fail(f"required landed ledger rows are absent: {missing}")
    for package in REQUIRED_PACKAGES:
        if result[package]["status"] != "complete":
            fail(f"required landed package is not complete: {package}={result[package]['status']}")
    gate = result.get("GATE-01")
    if gate is None:
        fail("required GATE-01 ledger row is absent")
    if gate["dependencies"] != ["EA-09"] or gate["class"] != "gate" or gate["gates"] != ["DOC", "DIFF", "PILOT"]:
        fail(f"GATE-01 contract mismatch: {gate}")
    if gate["status"] not in {"pending", "complete"}:
        fail(f"GATE-01 has invalid status: {gate['status']}")
    return result


def final_result(package: str, gate: str, result: str) -> None:
    if not result.startswith("passed — "):
        fail(f"{package}/{gate} is not final passed evidence: {result}")
    normalized = re.sub(r"\s+", " ", result).casefold().replace("re-run", "rerun")
    normalized = re.sub(r"\b0 failed\b", "", normalized)
    if re.search(r"\b(failed|skipped|pending|candidate|rerun|unverified|incomplete|blocked)\b", normalized):
        fail(f"{package}/{gate} contains nonpass evidence: {result}")


def section(text: str, title: str) -> str:
    match = re.search(rf"^## {re.escape(title)}$(.*?)(?=^## |\Z)", text, re.MULTILINE | re.DOTALL)
    if match is None:
        fail(f"linked Current Evidence section is absent: {title}")
    return match.group(1)


def validate_completion_evidence(
    evidence: str, ledger: dict[str, dict[str, object]]
) -> dict[str, set[str]]:
    candidates = {row[0] for row in table(evidence, CANDIDATE_HEADER, required=False)}
    unfinished = sorted(candidates.intersection(REQUIRED_PACKAGES))
    if unfinished:
        fail(f"required packages remain task-local candidates: {unfinished}")
    rows: dict[str, list[str]] = {}
    for package, _task, results, title in table(evidence, COMPLETION_HEADER):
        if package in rows:
            fail(f"duplicate completion evidence row: {package}")
        pairs = re.findall(r"`([A-Z][A-Z0-9-]*)=([a-z-]+)`", results)
        if results != ", ".join(f"`{gate}={state}`" for gate, state in pairs):
            fail(f"malformed completion evidence for {package}: {results}")
        if any(state != "passed" for _gate, state in pairs):
            fail(f"completion evidence is not passed for {package}: {results}")
        gates = [gate for gate, _state in pairs]
        if package in ledger and gates != ledger[package]["gates"]:
            fail(f"completion gate mismatch for {package}: {gates}")
        details = table(section(evidence, title), ["Validation", "Result", "Scope"])
        detailed: dict[str, str] = {}
        for validation, result, _scope in details:
            gate = uncode(validation)
            if gate in gates:
                if gate in detailed:
                    fail(f"duplicate detailed evidence for {package}/{gate}")
                final_result(package, gate, result)
                detailed[gate] = result
        if list(detailed) != gates:
            fail(f"missing or reordered detailed evidence for {package}: {list(detailed)}")
        rows[package] = gates
    missing = [package for package in REQUIRED_PACKAGES if package not in rows]
    if missing:
        fail(f"required landed Current Evidence rows are absent: {missing}")
    return {package: set(gates) for package, gates in rows.items()}


def validate_metrics(evidence: str) -> None:
    found: dict[str, tuple[int, int, str]] = {}
    for name, baseline, current, requirement in table(evidence, METRIC_HEADER):
        if name in found or not baseline.isdecimal() or not current.isdecimal():
            fail(f"invalid reduction metric row: {name}")
        found[name] = (int(baseline), int(current), requirement)
    if set(found) != set(METRICS):
        fail(f"reduction metric mismatch; expected={sorted(METRICS)}, found={sorted(found)}")
    for name, expected in METRICS.items():
        baseline, current, requirement = found[name]
        if requirement != expected:
            fail(f"reduction requirement mismatch for {name}: {requirement}")
        if expected == "decreased" and not current < baseline:
            fail(f"reduction did not decrease for {name}: {baseline}->{current}")
        if expected == "not-increased" and not current <= baseline:
            fail(f"adapter count increased for {name}: {baseline}->{current}")


def validate_predicates(evidence: str, completed: dict[str, set[str]]) -> None:
    rows = table(evidence, PILOT_HEADER)
    if [row[0] for row in rows] != list(PREDICATES):
        fail(f"Pilot predicate rows mismatch: {[row[0] for row in rows]}")
    for predicate, result, evidence_cell in rows:
        if result != "passed":
            fail(f"Pilot predicate is not passed: {predicate}={result}")
        tokens = code_list(evidence_cell)
        if tokens != list(PREDICATES[predicate]):
            fail(f"Pilot predicate evidence mismatch for {predicate}: {tokens}")
        for token in tokens:
            if token.startswith("METRICS/"):
                continue
            package, gate = token.split("/", 1)
            if gate not in completed.get(package, set()):
                fail(f"Pilot predicate references unpassed evidence: {token}")


def matching_paths(root: Path, specification: str) -> list[Path]:
    paths: set[Path] = set()
    for part in specification.split(","):
        part = part.strip()
        if not part or part.startswith("/") or ".." in Path(part).parts:
            fail(f"unsafe or empty scan path: {part!r}")
        matched = [path for path in root.glob(part) if path.is_file()]
        if not matched:
            fail(f"scan path matches no files: {part}")
        paths.update(matched)
    return sorted(paths)


def validate_inventory_and_scans(root: Path, plan: str) -> None:
    inventory_packages = [uncode(row[5]) for row in table(plan, INVENTORY_HEADER)]
    missing_inventory = [package for package in MIGRATED_CUTOVERS if package not in inventory_packages]
    if missing_inventory:
        fail(f"migrated packages lack inventory rows: {missing_inventory}")
    scans: dict[str, list[tuple[str, str]]] = {package: [] for package in MIGRATED_CUTOVERS}
    for package_cell, _scan_class, paths, literal_cell in table(plan, SCAN_HEADER):
        package = uncode(package_cell)
        if package in scans:
            scans[package].append((uncode(paths), uncode(literal_cell)))
    missing_scans = [package for package, rows in scans.items() if not rows]
    if missing_scans:
        fail(f"migrated packages lack cutover scans: {missing_scans}")
    failures: list[str] = []
    for package, rows in scans.items():
        for paths, literal in rows:
            if not literal:
                fail(f"empty scan literal for {package}")
            for path in matching_paths(root, paths):
                for line_number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
                    if literal in line:
                        failures.append(f"{package} {path.relative_to(root)}:{line_number}: {literal}")
    if failures:
        fail("dual-authority cutover scans are dirty: " + "; ".join(failures))


def validate_structural_boundaries(root: Path) -> None:
    core_files = list((root / "Sources/EpisodeCore").glob("*.swift"))
    model_files = list((root / "Sources/PlotterEpisodeModel").glob("*.swift"))
    if not core_files or not model_files:
        fail("EpisodeCore or PlotterEpisodeModel source rows are absent")
    core = "\n".join(path.read_text(encoding="utf-8") for path in core_files)
    if re.search(r"\bPlotter[A-Za-z0-9_]*\b|\bAny(Object)?\b|@unchecked\s+Sendable|unsafeBitCast|nonisolated\(unsafe\)", core):
        fail("EpisodeCore contains forbidden Plotter/type-erasure/concurrency escape syntax")
    model = "\n".join(path.read_text(encoding="utf-8") for path in model_files)
    for token in ("PlotterIntent", "case live", "case simulated", "livePhysical", "simulatedCausal"):
        if token not in model:
            fail(f"PlotterEpisodeModel lacks required typed boundary: {token}")
    required_owners = {
        root / "Sources/PlotterRuntime/MachineController.swift": "public actor MachineController",
        root / "Sources/PlotterRuntime/CameraCapture.swift": "public actor CameraCapture",
    }
    for path, declaration in required_owners.items():
        if not path.is_file() or declaration not in path.read_text(encoding="utf-8"):
            fail(f"production device owner is absent: {declaration}")


def evaluate(root: Path) -> None:
    plan = (root / PLAN).read_text(encoding="utf-8")
    evidence = (root / EVIDENCE).read_text(encoding="utf-8")
    ledger = parse_ledger(plan)
    completed = validate_completion_evidence(evidence, ledger)
    validate_metrics(evidence)
    validate_predicates(evidence, completed)
    validate_inventory_and_scans(root, plan)
    validate_structural_boundaries(root)


def main() -> int:
    try:
        evaluate(ROOT)
    except (OSError, GateError) as error:
        print(f"episode Pilot gate failed: {error}", file=sys.stderr)
        return 1
    print("episode Pilot gate passed: 9 predicates, 6 reduction metrics, 6 cutover scan sets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
