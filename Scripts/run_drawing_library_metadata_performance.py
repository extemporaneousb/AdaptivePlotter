#!/usr/bin/env python3
"""Run the opt-in current metadata test on an already-built normal test binary.

Never builds, opens user libraries, or reads historical benchmark fixtures.
The test generates and removes its own temporary current-schema metadata stores.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def inputs(root):
    names = subprocess.check_output(["git", "ls-files", "-c", "-o", "--exclude-standard", "-z"], cwd=root).split(b"\0")
    prefixes = ("Sources/", "Tests/", "Scripts/", "Tools/", "docs/", "Resources/")
    return {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
            for raw in sorted(set(names)) if raw
            for name in [os.fsdecode(raw)]
            if (name == "Package.swift" or name.startswith(prefixes)) and (root / name).is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch-path", type=Path, required=True, help="Existing normal SwiftPM test build scratch")
    parser.add_argument("--output-directory", type=Path, help="New observation directory under the system temporary directory")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.output_directory:
        output = args.output_directory.resolve()
        if not output.is_relative_to(Path(tempfile.gettempdir()).resolve()):
            parser.error("Observation directory must be under the system temporary directory")
        output.mkdir(mode=0o700)  # Never overwrite an earlier observation.
    else:
        output = Path(tempfile.mkdtemp(prefix="drawing-library-current-metadata-perf-"))
    scratch = args.scratch_path.resolve(strict=True)
    environment = os.environ.copy()
    prefixes = ("FLOW_", "PORTRAIT_", "DX", "DRAW_", "DRAWING_", "PLOTTER_", "ADAPTIVEPLOTTER_", "RUNNING_APP_", "PREVIEW_PERFORMANCE_", "ACTION_SURFACE_", "ACTIVE_LEARNING_", "HOLDER_REFERENCE_", "MARKER_", "PEN_CAP_", "WORKBENCH_")
    declared = set()
    for source in (root / "Tests").rglob("*.swift"):
        declared.update(re.findall(r'environment\["([A-Z][A-Z0-9_]*)"\]', source.read_text()))
    cleared = []
    for key in list(environment):
        if key in declared or key.startswith(prefixes):
            cleared.append(key)
            del environment[key]
    report = output / "measurements.json"
    environment["DRAWING_LIBRARY_METADATA_PERF"] = "1"
    environment["DRAWING_LIBRARY_METADATA_PERF_OUTPUT"] = str(report)
    argv = ["swift", "test", "--skip-build", "--no-parallel", "--scratch-path", str(scratch),
            "--xunit-output", str(output / "results.xml"), "--filter", "DrawingLibraryMetadataPerformanceTests"]
    before = inputs(root)
    write_json(output / "inputs-before.json", before)
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    write_json(output / "start.json", {"argv": argv, "cwd": str(root), "start_utc": started,
                                      "cleared_environment_keys": sorted(cleared), "build": "skip-build; existing normal package binary"})
    print(f"EVIDENCE={output}", flush=True)
    timer = time.monotonic()
    with (output / "stdout-stderr.log").open("wb") as log:
        result = subprocess.run(argv, cwd=root, env=environment, stdout=log, stderr=subprocess.STDOUT)
    after = inputs(root)
    write_json(output / "inputs-after.json", after)
    receipt = {"argv": argv, "start_utc": started, "stop_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "elapsed_seconds": time.monotonic() - timer, "exit_code": result.returncode,
               "input_count": len(before), "changed_inputs": sorted(key for key in before.keys() | after.keys() if before.get(key) != after.get(key)),
               "log_sha256": hashlib.sha256((output / "stdout-stderr.log").read_bytes()).hexdigest(),
               "measurement_report_written": report.exists()}
    xml = output / "results.xml"
    if xml.exists():
        cases = list(ET.parse(xml).getroot().iter("testcase"))
        receipt["xml_counts"] = {"testcase_elements": len(cases), "skips": sum(case.find("skipped") is not None for case in cases),
                                 "failures": sum(case.find("failure") is not None for case in cases), "errors": sum(case.find("error") is not None for case in cases)}
        receipt["xml_sha256"] = hashlib.sha256(xml.read_bytes()).hexdigest()
    if report.exists():
        receipt["report_sha256"] = hashlib.sha256(report.read_bytes()).hexdigest()
    write_json(output / "process.json", receipt)
    print(json.dumps(receipt, sort_keys=True))
    if result.returncode:
        return result.returncode
    return 2 if receipt["changed_inputs"] or not report.exists() else 0


if __name__ == "__main__":
    raise SystemExit(main())
