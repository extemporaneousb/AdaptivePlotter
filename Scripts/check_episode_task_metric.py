#!/usr/bin/env python3
"""Prove the direct stored OperatorWorkspace Task-owner metric from source."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCE_PATH = Path("Sources/PlotterApp/OperatorWorkspace.swift")
EVIDENCE_PATH = Path("docs/CURRENT_EVIDENCE.md")
BASELINE_COMMIT = "96253197a42dc6052ef76ad53c4c94c1c5f745a1"
PRE_FIX03_COMMIT = "03d8279603c39ad19b49d980fc39aa0144b96148"
EXPECTED_BASELINE_COUNT = 9
EXPECTED_CURRENT_COUNT = 8
METRIC_NAME = "workspace-task-owners"
METRIC_HEADER = ["Reduction metric", "Baseline", "Current", "Requirement"]


class MetricError(ValueError):
    pass


def fail(message: str) -> None:
    raise MetricError(message)


def mask_comments_and_literals(text: str) -> str:
    """Replace comments and string contents while preserving braces and newlines."""
    result = list(text)
    index = 0
    block_depth = 0
    in_line_comment = False
    in_string = False
    multiline_string = False
    escaped = False
    while index < len(text):
        pair = text[index:index + 2]
        triple = text[index:index + 3]
        character = text[index]
        if in_line_comment:
            if character == "\n":
                in_line_comment = False
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
                if character != "\n":
                    result[index] = " "
                index += 1
            continue
        if in_string:
            if multiline_string and triple == '\"\"\"':
                result[index:index + 3] = [" ", " ", " "]
                in_string = False
                multiline_string = False
                index += 3
            elif not multiline_string and character == '"' and not escaped:
                result[index] = " "
                in_string = False
                index += 1
            else:
                if character != "\n":
                    result[index] = " "
                escaped = character == "\\" and not escaped
                if character != "\\":
                    escaped = False
                index += 1
            continue
        if pair == "//":
            result[index:index + 2] = [" ", " "]
            in_line_comment = True
            index += 2
        elif pair == "/*":
            result[index:index + 2] = [" ", " "]
            block_depth = 1
            index += 2
        elif triple == '\"\"\"':
            result[index:index + 3] = [" ", " ", " "]
            in_string = True
            multiline_string = True
            index += 3
        elif character == '"':
            result[index] = " "
            in_string = True
            escaped = False
            index += 1
        else:
            index += 1
    if block_depth or in_string:
        fail("unterminated comment or string while scanning OperatorWorkspace")
    return "".join(result)


def operator_workspace_body(source: str) -> str:
    masked = mask_comments_and_literals(source)
    declaration = re.search(r"\bfinal\s+class\s+OperatorWorkspace\b[^\{]*\{", masked)
    if declaration is None:
        fail("final class OperatorWorkspace declaration is absent")
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
        fail("OperatorWorkspace declaration is unbalanced")
    return masked[start:index - 1]


DIRECT_TASK_DECLARATION = re.compile(
    r"(?:^|\n)\s*"
    r"(?:(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?)\s+)*"
    r"(?:(?:private|fileprivate|internal|public|package|nonisolated|static|class)\s+)*"
    r"(?:var|let)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*"
    r"(?:Swift\s*\.\s*)?Task\s*<[^\n\{]+?(?:\?|!)?\s*(?=$|=)",
    re.MULTILINE,
)


def direct_stored_task_names(source: str) -> list[str]:
    masked = mask_comments_and_literals(source)
    if re.search(r"\btypealias\s+\w+\s*=\s*(?:Swift\s*\.\s*)?Task\s*<", masked):
        fail("Task typealiases are unsupported because they could hide metric owners")
    body = operator_workspace_body(source)
    names: list[str] = []
    depth = 0
    offset = 0
    for line in body.splitlines(keepends=True):
        if depth == 0:
            match = DIRECT_TASK_DECLARATION.search("\n" + line)
            if match is not None:
                names.append(match.group(1))
        depth += line.count("{") - line.count("}")
        if depth < 0:
            fail(f"unexpected brace depth near OperatorWorkspace offset {offset}")
        offset += len(line)
    if depth:
        fail("nested OperatorWorkspace declarations are unbalanced")
    if len(names) != len(set(names)):
        fail(f"duplicate direct stored Task property names: {names}")
    return sorted(names)


def evidence_metric(evidence: str) -> tuple[int, int, str]:
    lines = evidence.splitlines()
    for index, line in enumerate(lines):
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if cells != METRIC_HEADER:
            continue
        for candidate in lines[index + 2:]:
            if not candidate.startswith("|"):
                break
            row = [cell.strip() for cell in candidate.strip().strip("|").split("|")]
            if len(row) == 4 and row[0] == METRIC_NAME:
                if not row[1].isdecimal() or not row[2].isdecimal():
                    fail(f"{METRIC_NAME} evidence must contain decimal counts: {row}")
                return int(row[1]), int(row[2]), row[3]
        fail(f"{METRIC_NAME} row is absent from Current Evidence")
    fail("Current Evidence reduction metric table is absent")


def git_text(root: Path, commit: str, path: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), "show", f"{commit}:{path.as_posix()}"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        fail(f"cannot read pinned baseline {commit}:{path}: {result.stderr.strip()}")
    return result.stdout


def validate_scanner_fixtures() -> None:
    fixture = """
@MainActor
final class OperatorWorkspace {
  private var first: Task<Void, Never>?
  let second: Swift.Task<Int, Never> = Task { 1 }
  var computed: Task<Void, Never> { Task {} }
  struct Nested { var hidden: Task<Void, Never>? }
  let text = "var fake: Task<Void, Never>?"
  // var commented: Task<Void, Never>?
}
"""
    if direct_stored_task_names(fixture) != ["first", "second"]:
        fail("internal scanner fixture did not isolate direct stored Task owners")
    alias = "final class OperatorWorkspace { typealias Hidden = Task<Void, Never>\nvar value: Hidden? }"
    try:
        direct_stored_task_names(alias)
    except MetricError:
        pass
    else:
        fail("internal scanner fixture admitted a Task typealias")


def evaluate(root: Path) -> tuple[list[str], list[str], list[str]]:
    validate_scanner_fixtures()
    baseline_source = git_text(root, BASELINE_COMMIT, SOURCE_PATH)
    pre_fix03_source = git_text(root, PRE_FIX03_COMMIT, SOURCE_PATH)
    current_source = (root / SOURCE_PATH).read_text(encoding="utf-8")
    evidence = (root / EVIDENCE_PATH).read_text(encoding="utf-8")
    baseline_names = direct_stored_task_names(baseline_source)
    pre_fix03_names = direct_stored_task_names(pre_fix03_source)
    current_names = direct_stored_task_names(current_source)
    recorded_baseline, recorded_current, requirement = evidence_metric(evidence)
    if len(baseline_names) != EXPECTED_BASELINE_COUNT:
        fail(f"pinned baseline count changed: {len(baseline_names)} {baseline_names}")
    if len(pre_fix03_names) != EXPECTED_BASELINE_COUNT:
        fail(f"pre-FIX-03 count changed: {len(pre_fix03_names)} {pre_fix03_names}")
    if "drawingRunTask" not in pre_fix03_names:
        fail("pre-FIX-03 source does not contain drawingRunTask")
    if "drawingRunTask" in current_names:
        fail("candidate still contains drawingRunTask")
    if len(current_names) != EXPECTED_CURRENT_COUNT:
        fail(f"candidate count is not {EXPECTED_CURRENT_COUNT}: {len(current_names)} {current_names}")
    if not len(current_names) < len(baseline_names):
        fail(f"workspace Task owners did not decrease: {len(baseline_names)}->{len(current_names)}")
    if requirement != "decreased":
        fail(f"Current Evidence requirement mismatch: {requirement}")
    if (recorded_baseline, recorded_current) != (len(baseline_names), len(current_names)):
        fail(
            "Current Evidence metric does not match source: "
            f"recorded={recorded_baseline}->{recorded_current}, "
            f"computed={len(baseline_names)}->{len(current_names)}"
        )
    if sorted(set(pre_fix03_names) - set(current_names)) != ["drawingRunTask"]:
        fail(
            "FIX-03 must remove exactly drawingRunTask from the pre-correction owner set: "
            f"before={pre_fix03_names}, current={current_names}"
        )
    if sorted(set(current_names) - set(pre_fix03_names)):
        fail(
            "FIX-03 must not add a replacement workspace Task owner: "
            f"before={pre_fix03_names}, current={current_names}"
        )
    return baseline_names, pre_fix03_names, current_names


def main() -> int:
    try:
        baseline_names, pre_fix03_names, current_names = evaluate(ROOT)
    except (OSError, MetricError) as error:
        print(f"episode Task metric failed: {error}", file=sys.stderr)
        return 1
    removed = sorted(set(pre_fix03_names) - set(current_names))
    added = sorted(set(current_names) - set(pre_fix03_names))
    print(
        "episode Task metric passed: "
        f"{BASELINE_COMMIT} {len(baseline_names)} -> working tree {len(current_names)}; "
        f"FIX-03 {PRE_FIX03_COMMIT} {len(pre_fix03_names)} -> working tree {len(current_names)}; "
        f"removed={removed}; added={added}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
