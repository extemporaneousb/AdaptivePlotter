#!/usr/bin/env python3
"""Create and consume the hash-bound episode-wave launch capsule."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from types import ModuleType
from typing import Callable


SCHEMA = "adaptiveplotter.episode-wave-launch.v1"
DEFAULT_CAPSULE = Path(".VE/run-multi-agent-wave/launch-capsule.json")
MAX_CAPSULE_BYTES = 262_144
MAX_CONSUMPTION_BYTES = 65_536
MAX_UNFINISHED_CLAIMS = 32
MAX_CLAIM_FIELD_CHARACTERS = 1_024
AUTHORITY_PATHS = (
    ".gitignore",
    "AGENTS.md",
    "blackdog.toml",
    "docs/INDEX.md",
    "docs/EPISODE_ARCHITECTURE_EXECUTION_PLAN.md",
    "docs/EPISODE_ARCHITECTURE_VOCABULARY.md",
    "docs/PRODUCT_CONTRACT.md",
    "docs/SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md",
    "docs/CURRENT_EVIDENCE.md",
    ".codex/skills/adaptiveplotter/SKILL.md",
    ".codex/skills/adaptiveplotter/references/episode-migration.md",
    ".codex/skills/run-multi-agent-wave/SKILL.md",
    ".codex/skills/run-multi-agent-wave/references/wave-coordination.md",
    "Scripts/check_episode_contract.py",
    "Scripts/episode_wave_capsule.py",
)


class CapsuleError(ValueError):
    pass


def canonical_bytes(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def run(command: list[str], root: Path, *, allow_failure: bool = False) -> str:
    result = subprocess.run(command, cwd=root, check=False, capture_output=True, text=True)
    if result.returncode != 0 and not allow_failure:
        detail = result.stderr.strip() or result.stdout.strip() or f"exit {result.returncode}"
        raise CapsuleError(f"command failed: {' '.join(command)}: {detail}")
    return result.stdout.strip() if result.returncode == 0 else ""


def repository_state(root: Path) -> dict[str, object]:
    root = root.resolve()
    if not (root / ".git").is_dir():
        raise CapsuleError("wave capsule requires the normal primary Git workspace")
    branch = run(["git", "branch", "--show-current"], root)
    head = run(["git", "rev-parse", "HEAD"], root)
    status_text = run(["git", "status", "--short"], root)
    if branch != "main":
        raise CapsuleError(f"wave capsule requires branch main; found {branch or 'detached HEAD'}")
    if status_text:
        raise CapsuleError("wave capsule requires an empty git status --short")
    origin_counts = run(
        ["git", "rev-list", "--left-right", "--count", "main...origin/main"],
        root,
    )
    if not re.fullmatch(r"\d+\s+\d+", origin_counts):
        raise CapsuleError(f"invalid main...origin/main relation: {origin_counts!r}")
    if not re.fullmatch(r"[0-9a-f]{40}", head):
        raise CapsuleError(f"invalid Git HEAD identity: {head!r}")
    return {
        "root": str(root),
        "branch": branch,
        "head": head,
        "status_short": "",
        "origin_main_counts": origin_counts or None,
    }


def import_contract(root: Path) -> ModuleType:
    contract_path = root / "Scripts/check_episode_contract.py"
    spec = importlib.util.spec_from_file_location("adaptiveplotter_episode_contract", contract_path)
    if spec is None or spec.loader is None:
        raise CapsuleError(f"cannot load contract checker: {contract_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def validated_contract(
    root: Path,
    *,
    validate_live_gates: bool = True,
) -> tuple[
    ModuleType,
    dict[str, dict[str, object]],
    dict[str, tuple[str, str]],
    dict[str, dict[str, str]],
]:
    contract = import_contract(root)
    plan = (root / "docs/EPISODE_ARCHITECTURE_EXECUTION_PLAN.md").read_text(encoding="utf-8")
    vocabulary = (root / "docs/EPISODE_ARCHITECTURE_VOCABULARY.md").read_text(encoding="utf-8")
    evidence = (root / "docs/CURRENT_EVIDENCE.md").read_text(encoding="utf-8")
    protocol = (root / ".codex/skills/adaptiveplotter/references/episode-migration.md").read_text(encoding="utf-8")
    skill = (root / ".codex/skills/adaptiveplotter/SKILL.md").read_text(encoding="utf-8")
    wave_skill = (root / ".codex/skills/run-multi-agent-wave/SKILL.md").read_text(encoding="utf-8")
    wave_protocol = (root / ".codex/skills/run-multi-agent-wave/references/wave-coordination.md").read_text(encoding="utf-8")
    contract.validate_vocabulary(vocabulary)
    rows = contract.validate_plan(plan)
    contract.validate_evidence(evidence, rows)
    contract.validate_wave_frontier(rows, evidence)
    contract.validate_protocol(protocol, skill, wave_skill, wave_protocol)
    blockers = contract.parse_wave_admission_blockers(evidence, rows)
    if validate_live_gates:
        contract.validate_live_repository_gates(rows)
    gate_rows = contract.markdown_table(
        plan,
        ["Gate", "Exact command or evidence procedure", "Created or owned by"],
    )
    gates: dict[str, tuple[str, str]] = {}
    for gate_cell, procedure, owner in gate_rows:
        gate = gate_cell.strip("`")
        gates[gate] = (procedure, owner)
    return contract, rows, gates, blockers


def ledger_sha256(plan: str) -> str:
    lines = plan.splitlines()
    start = next((index for index, line in enumerate(lines) if line.startswith("| ID | Status | Dependencies |")), None)
    if start is None:
        raise CapsuleError("canonical work ledger is missing")
    material: list[str] = []
    for line in lines[start:]:
        if not line.startswith("|"):
            break
        material.append(line.rstrip())
    return sha256_bytes(("\n".join(material) + "\n").encode("utf-8"))


def unfinished_claims(summary: dict[str, object]) -> list[dict[str, object]]:
    tasks = summary.get("tasks")
    if not isinstance(tasks, list):
        raise CapsuleError("Blackdog summary lacks a tasks array")
    claims: list[dict[str, object]] = []
    for task in tasks:
        if not isinstance(task, dict) or task.get("readiness") == "done":
            continue
        claim = {
            "task_id": task.get("task_id"),
            "task_ref": task.get("task_ref"),
            "readiness": task.get("readiness"),
            "runtime_status": task.get("runtime_status"),
            "latest_attempt_status": task.get("latest_attempt_status"),
            "claim_actor": task.get("claim_actor"),
        }
        if any(
            value is not None and (not isinstance(value, str) or len(value) > MAX_CLAIM_FIELD_CHARACTERS)
            for value in claim.values()
        ):
            raise CapsuleError("Blackdog claim contains an invalid or unbounded field")
        claims.append(claim)
    if len(claims) > MAX_UNFINISHED_CLAIMS:
        raise CapsuleError("Blackdog reports more unfinished claims than the capsule bound permits")
    return sorted(claims, key=lambda item: str(item.get("task_id")))


def read_blackdog_summary(root: Path) -> dict[str, object]:
    blackdog = root / ".VE/bin/blackdog"
    output = run([str(blackdog), "summary", "--project-root", str(root), "--json"], root)
    try:
        value = json.loads(output)
    except json.JSONDecodeError as error:
        raise CapsuleError(f"Blackdog summary is not valid JSON: {error}") from error
    if not isinstance(value, dict):
        raise CapsuleError("Blackdog summary must be a JSON object")
    return value


def line_range(text: str, heading: str) -> tuple[int, int]:
    lines = text.splitlines()
    start = next((index for index, line in enumerate(lines) if line == heading), None)
    if start is None:
        raise CapsuleError(f"missing section heading: {heading}")
    level = len(heading) - len(heading.lstrip("#"))
    end = len(lines)
    for index in range(start + 1, len(lines)):
        candidate = lines[index]
        if candidate.startswith("#"):
            candidate_level = len(candidate) - len(candidate.lstrip("#"))
            if candidate_level <= level:
                end = index
                break
    return start + 1, end


def pointer(path: str, text: str, start: int, end: int, purpose: str) -> dict[str, object]:
    lines = text.splitlines()
    material = "\n".join(lines[start - 1 : end]) + "\n"
    return {
        "path": path,
        "start_line": start,
        "end_line": end,
        "purpose": purpose,
        "content_sha256": sha256_bytes(material.encode("utf-8")),
    }


def matching_line_pointers(path: str, text: str, token: str, purpose: str) -> list[dict[str, object]]:
    matches = [index for index, line in enumerate(text.splitlines(), start=1) if token in line]
    return [pointer(path, text, line, line, purpose) for line in matches[:64]]


def exact_table_cell_pointers(
    contract: ModuleType,
    path: str,
    text: str,
    column: int,
    token: str,
    purpose: str,
) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        if not line.startswith("|"):
            continue
        row = contract.cells(line)
        if len(row) <= column or row[column].strip("`") != token:
            continue
        result.append(pointer(path, text, line_number, line_number, purpose))
    return result


def package_pointers(
    root: Path,
    contract: ModuleType,
    package_id: str | None,
    rows: dict[str, dict[str, object]],
) -> list[dict[str, object]]:
    plan_path = "docs/EPISODE_ARCHITECTURE_EXECUTION_PLAN.md"
    vocabulary_path = "docs/EPISODE_ARCHITECTURE_VOCABULARY.md"
    product_path = "docs/PRODUCT_CONTRACT.md"
    architecture_path = "docs/SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md"
    evidence_path = "docs/CURRENT_EVIDENCE.md"
    protocol_path = ".codex/skills/adaptiveplotter/references/episode-migration.md"
    wave_path = ".codex/skills/run-multi-agent-wave/references/wave-coordination.md"
    plan = (root / plan_path).read_text(encoding="utf-8")
    vocabulary = (root / vocabulary_path).read_text(encoding="utf-8")
    product = (root / product_path).read_text(encoding="utf-8")
    architecture = (root / architecture_path).read_text(encoding="utf-8")
    evidence = (root / evidence_path).read_text(encoding="utf-8")
    protocol = (root / protocol_path).read_text(encoding="utf-8")
    wave = (root / wave_path).read_text(encoding="utf-8")
    result: list[dict[str, object]] = []
    if package_id is not None:
        result.extend(
            exact_table_cell_pointers(
                contract,
                plan_path,
                plan,
                0,
                package_id,
                "selected package contract row",
            )
        )
        result.extend(matching_line_pointers(evidence_path, evidence, f"`{package_id}`", "selected package evidence reference"))
        result.extend(
            exact_table_cell_pointers(
                contract,
                plan_path,
                plan,
                5,
                package_id,
                "selected package current-source inventory row",
            )
        )
        for dependency in rows[package_id]["dependencies"]:
            result.extend(exact_table_cell_pointers(contract, plan_path, plan, 0, dependency, "dependency ledger row"))
            result.extend(exact_table_cell_pointers(contract, evidence_path, evidence, 0, dependency, "dependency evidence row"))
        for gate in rows[package_id]["gates"]:
            result.extend(exact_table_cell_pointers(contract, plan_path, plan, 0, gate, "required gate catalog row"))

        outcome = str(rows[package_id]["outcome"]).lower()
        vocabulary_sections = {"## Specifications and state", "## Canonical target seams"}
        if any(token in outcome for token in ("intent", "decision", "availability", "receipt")):
            vocabulary_sections.add("## Semantic request and decision")
        if any(token in outcome for token in ("event", "effect", "capabil", "result", "operation")):
            vocabulary_sections.add("## Events, effects, and capabilities")
        if any(token in outcome for token in ("observation", "evidence", "assessment", "measurement", "outcome")):
            vocabulary_sections.add("## Observation, evidence, and assessment")
        if any(token in outcome for token in ("journal", "store", "replay", "incident", "trace", "workpackage")):
            vocabulary_sections.add("## Memory and repository execution")
        if any(token in outcome for token in ("runner", "provider", "projection", "environment", "composition")):
            vocabulary_sections.add("## Supporting roles and field correspondence")
        for heading in sorted(vocabulary_sections):
            start, end = line_range(vocabulary, heading)
            result.append(pointer(vocabulary_path, vocabulary, start, end, "package vocabulary authority"))

    for path, text, heading, purpose in (
        (plan_path, plan, "## Target packages", "target package topology"),
        (plan_path, plan, "## Central semantic ingress", "semantic ingress authority"),
        (plan_path, plan, "## Operation ownership and safety priority", "operation ownership authority"),
        (plan_path, plan, "## Guard ownership", "guard ownership authority"),
        (plan_path, plan, "## Non-negotiable observability", "observability authority"),
        (plan_path, plan, "## Replay and simulation", "replay and simulation authority"),
        (plan_path, plan, "## Same-landing deletion rule", "same-landing deletion authority"),
        (plan_path, plan, "## Known prerequisite corrections", "prerequisite correction authority"),
        (plan_path, plan, "## Package completion contract", "package completion authority"),
        (product_path, product, "## Product boundary", "preserved product boundary"),
        (product_path, product, "## Runtime authority", "preserved runtime authority"),
        (architecture_path, architecture, "## Package topology", "current package topology"),
        (architecture_path, architecture, "## Runtime owners", "current runtime owners"),
        (evidence_path, evidence, "## Wave admission blockers", "wave admission blocker authority"),
        (protocol_path, protocol, "## Compile the exact execution prompt", "prompt compilation protocol"),
        (protocol_path, protocol, "## Execute from authority outward", "package execution protocol"),
        (protocol_path, protocol, "## Validate, assess, and land", "validation and landing protocol"),
        (wave_path, wave, "## 3. Compose the coordinator prompt", "coordination overlay"),
        (wave_path, wave, "## 4. Worker assignment and status contract", "worker status contract"),
        (wave_path, wave, "## 5. Completion", "wave completion protocol"),
    ):
        start, end = line_range(text, heading)
        result.append(pointer(path, text, start, end, purpose))
    unique: dict[tuple[str, int, int, str], dict[str, object]] = {}
    for item in result:
        key = (str(item["path"]), int(item["start_line"]), int(item["end_line"]), str(item["purpose"]))
        unique[key] = item
    return list(unique.values())


def contract_frontier(
    rows: dict[str, dict[str, object]],
    selected: str | None,
    blockers: dict[str, dict[str, str]] | None = None,
) -> dict[str, object]:
    if selected is not None:
        return {"state": "selected", "package_id": selected}
    eligible = [
        package_id
        for package_id, row in rows.items()
        if row["status"] == "pending"
        and row["class"] in {"repository", "software", "gate"}
        and all(rows[dependency]["status"] == "complete" for dependency in row["dependencies"])
    ]
    if eligible and eligible[0] in (blockers or {}):
        package_id = eligible[0]
        return {
            "state": "evidence_blocked",
            "package_id": package_id,
            "blocker": blockers[package_id],
        }
    incomplete = [package_id for package_id, row in rows.items() if row["status"] != "complete"]
    if not incomplete:
        return {"state": "complete", "package_id": None}
    package_id = incomplete[0]
    row = rows[package_id]
    missing = [dependency for dependency in row["dependencies"] if rows[dependency]["status"] != "complete"]
    if row["class"] in {"attended-physical", "remote-git"} and not missing:
        state = "authorization_boundary"
    else:
        state = "dependency_blocked"
    return {"state": state, "package_id": package_id, "incomplete_dependencies": missing}


def build_capsule(
    root: Path,
    summary: dict[str, object] | None = None,
    *,
    validate_live_gates: bool = True,
) -> dict[str, object]:
    root = root.resolve()
    state = repository_state(root)
    contract, rows, gates, blockers = validated_contract(root, validate_live_gates=validate_live_gates)
    selected = contract.ordinary_wave_frontier(rows, set(blockers))
    frontier = contract_frontier(rows, selected, blockers)
    package_id = frontier.get("package_id")
    package: dict[str, object] | None = None
    dependencies: list[dict[str, object]] = []
    expanded_gates: list[dict[str, object]] = []
    if isinstance(package_id, str):
        row = rows[package_id]
        package = {
            "id": package_id,
            "status": row["status"],
            "class": row["class"],
            "dependencies": row["dependencies"],
            "outcome": row["outcome"],
        }
        dependencies = [
            {"id": dependency, "status": rows[dependency]["status"]}
            for dependency in row["dependencies"]
        ]
        expanded_gates = [
            {"id": gate, "procedure": gates[gate][0], "owner": gates[gate][1]}
            for gate in row["gates"]
        ]
    live_summary = summary if summary is not None else read_blackdog_summary(root)
    claims = unfinished_claims(live_summary)
    launch_state = "claim_resolution" if claims else frontier["state"]
    bindings = {path: sha256_file(root / path) for path in AUTHORITY_PATHS}
    plan = (root / "docs/EPISODE_ARCHITECTURE_EXECUTION_PLAN.md").read_text(encoding="utf-8")
    capsule: dict[str, object] = {
        "schema": SCHEMA,
        "repository": state,
        "bindings": bindings,
        "blackdog": {
            "unfinished_claims_sha256": sha256_bytes(canonical_bytes(claims)),
            "unfinished_claims": claims,
        },
        "launch": {"state": launch_state},
        "contract": {
            "ledger_sha256": ledger_sha256(plan),
            "complete_packages": [package_id for package_id, row in rows.items() if row["status"] == "complete"],
            "frontier": frontier,
            "package": package,
            "dependency_rows": dependencies,
            "expanded_gates": expanded_gates,
            "wave_admission_blockers": blockers,
        },
        "pointers": package_pointers(
            root,
            contract,
            package_id if isinstance(package_id, str) else None,
            rows,
        ),
    }
    capsule["payload_sha256"] = sha256_bytes(canonical_bytes(capsule))
    return capsule


def atomic_write_capsule(path: Path, capsule: dict[str, object]) -> None:
    encoded = canonical_bytes(capsule) + b"\n"
    if len(encoded) > MAX_CAPSULE_BYTES:
        raise CapsuleError("generated capsule exceeds the bounded size limit")
    if len(canonical_bytes(consumption_view(capsule))) > MAX_CONSUMPTION_BYTES:
        raise CapsuleError("generated capsule exceeds the bounded consumption-output limit")
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def read_capsule(path: Path) -> dict[str, object]:
    metadata = path.lstat()
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink():
        raise CapsuleError("capsule must be a regular non-symlink file")
    if metadata.st_uid != os.getuid():
        raise CapsuleError("capsule must be owned by the current user")
    if stat.S_IMODE(metadata.st_mode) != 0o600:
        raise CapsuleError("capsule must have mode 0600")
    if metadata.st_size > MAX_CAPSULE_BYTES:
        raise CapsuleError("capsule exceeds the bounded size limit")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CapsuleError(f"cannot read capsule: {error}") from error
    if not isinstance(value, dict):
        raise CapsuleError("capsule must be a JSON object")
    return value


def consume_capsule(
    root: Path,
    path: Path,
    summary_loader: Callable[[Path], dict[str, object]] = read_blackdog_summary,
    *,
    validate_live_gates: bool = True,
) -> dict[str, object]:
    stored = read_capsule(path)
    if stored.get("schema") != SCHEMA:
        raise CapsuleError("capsule schema mismatch")
    recorded_digest = stored.get("payload_sha256")
    unsigned = dict(stored)
    unsigned.pop("payload_sha256", None)
    if recorded_digest != sha256_bytes(canonical_bytes(unsigned)):
        raise CapsuleError("capsule payload digest mismatch")
    current = build_capsule(
        root,
        summary_loader(root),
        validate_live_gates=validate_live_gates,
    )
    if stored != current:
        raise CapsuleError("capsule is stale relative to canonical Git, documents, contract, or Blackdog claims")
    return stored


def consumption_view(capsule: dict[str, object]) -> dict[str, object]:
    repository = capsule["repository"]
    contract = capsule["contract"]
    return {
        "schema": capsule["schema"],
        "payload_sha256": capsule["payload_sha256"],
        "repository": {
            "root": repository["root"],
            "branch": repository["branch"],
            "head": repository["head"],
            "origin_main_counts": repository["origin_main_counts"],
        },
        "launch": capsule["launch"],
        "unfinished_claims": capsule["blackdog"]["unfinished_claims"],
        "contract": contract,
        "pointers": capsule["pointers"],
    }


def parse_arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("create", "consume"))
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--capsule", type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = parse_arguments(sys.argv[1:] if argv is None else argv)
    root = arguments.project_root.resolve()
    path = arguments.capsule or root / DEFAULT_CAPSULE
    if not path.is_absolute():
        path = root / path
    try:
        if arguments.command == "create":
            capsule = build_capsule(root)
            atomic_write_capsule(path, capsule)
        else:
            capsule = consume_capsule(root, path)
    except (OSError, CapsuleError, ValueError) as error:
        print(f"wave launch capsule: {error}", file=sys.stderr)
        return 2
    encoded_view = canonical_bytes(consumption_view(capsule))
    if len(encoded_view) > MAX_CONSUMPTION_BYTES:
        print("wave launch capsule: consumption output exceeds its bounded size limit", file=sys.stderr)
        return 2
    print(encoded_view.decode("utf-8"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
