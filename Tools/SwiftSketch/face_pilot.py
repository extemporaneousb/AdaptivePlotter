#!/usr/bin/env python3
"""Freeze sources, then consume native-prepared inputs for one bounded face pilot.

This tool does not crop, mask, resample or otherwise prepare an image. The Swift
opt-in harness uses PortraitStudioArtistInput.prepare, exactly as the native app.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import time
import uuid

REVISION = "portrait-native-face-mask-v1"
COUNT = 10


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_new(path, value):
    with Path(path).open("x", encoding="utf-8") as stream:
        json.dump(value, stream, sort_keys=True, indent=2)
        stream.write("\n")


def inventory(roots):
    files = []
    for root in roots:
        root = Path(root).resolve(strict=True)
        for path in sorted(root.rglob("*")):
            if path.is_symlink():
                raise ValueError("preservation root contains a symlink")
            if path.is_file():
                files.append({"root": str(root), "relative_path": str(path.relative_to(root)),
                              "bytes": path.stat().st_size, "sha256": sha(path)})
    return {"schema_version": 1, "files": files}


def plan(library, output, first_pilot, excluded):
    library = Path(library).resolve(strict=True)
    output = Path(output).resolve()
    first = Path(first_pilot).resolve(strict=True)
    if output.exists():
        raise ValueError("face pilot root exists; preserve it")
    database = sqlite3.connect((library / "library-v1.sqlite").as_uri() + "?mode=ro", uri=True)
    try:
        rows = database.execute("SELECT id,source_hash,reference,captured_at FROM photo WHERE deleted=0 ORDER BY captured_at,id").fetchall()
    finally:
        database.close()
    seen = set(excluded)
    distinct = []
    for row in rows:
        if row[1] not in seen:
            distinct.append(row)
            seen.add(row[1])
    if len(distinct) < COUNT:
        raise ValueError("fewer than ten distinct eligible originals")
    positions = [i * (len(distinct) - 1) // (COUNT - 1) for i in range(COUNT)]
    preservation = inventory([first / "PilotLibrary", first / "pilot-v1"])
    output.mkdir(parents=True)
    write_new(output / "first-pilot-preservation-before.json", preservation)
    photos = []
    for index, position in enumerate(positions):
        capture_id, source_hash, reference, timestamp = distinct[position]
        reference = json.loads(reference)
        source = library / "assets" / source_hash
        if sha(source) != source_hash:
            raise ValueError("selected original asset changed")
        folder = output / ("photo-%02d" % index)
        folder.mkdir()
        shutil.copyfile(source, folder / "original.asset")
        metadata = {"index": index, "capture_id": capture_id, "source_sha256": source_hash,
                    "acquisition_id": reference.get("captureSessionID"), "reference": reference,
                    "ordered_retained_timestamp": timestamp, "selected_distinct_position": position,
                    "human_subject_group": None, "human_photo_session_group": None,
                    "groups_status": "unassigned-requires-human"}
        write_new(folder / "source-receipt.json", metadata)
        metadata["source_receipt_sha256"] = sha(folder / "source-receipt.json")
        photos.append(metadata)
    selection = {"schema_version": 1, "pilot_revision": REVISION, "created_at_unix": time.time(),
                 "selection_rule": "Distinct source hashes excluding declared smoke sources; ordered retained captured_at,id; positions floor(i*(N-1)/9), i=0..9. Retained timestamps are not asserted capture chronology; no output-dependent replacement.",
                 "eligible_distinct_count": len(distinct), "excluded_smoke_hashes": excluded,
                 "photos": photos, "maximum_model_jobs_including_failures": COUNT,
                 "maximum_native_jobs_including_failures": 3 * COUNT,
                 "maximum_comparisons": 3 * COUNT, "total_model_wall_seconds": 600,
                 "model_preprocessing": "unchanged", "seed": 42,
                 "material": {"width_mm": 100, "height_mm": 100, "nominal_pen_mm": 0.4},
                 "human_groups_and_labels": "unknown-unassigned; no inferred identity or preferences"}
    write_new(output / "source-selection.json", selection)
    write_new(output / "preparation-parameters.json", {"schema_version": 1, "face_overrides": {},
                "override_coordinates": "EXIF-oriented pixels, top-left origin; explicit visual framing declarations only",
                "native_preparation": "PortraitStudioArtistInput.prepare; foreground mask and framed source retained separately",
                "native_styles": ["Flow Edge", "Contour", "Sketch"],
                "native_crop_to_face": False, "native_remove_background": False,
                "native_head_transform": "disabled; same exact prepared square input for all four artists"})
    print(json.dumps({"source_selection": str(output / "source-selection.json"),
                      "sha256": sha(output / "source-selection.json"), "positions": positions,
                      "sources": len(photos), "first_pilot_files_preserved": len(preservation["files"])}, sort_keys=True))


def run(root, model_manifest, worker, python, expected_manifest_sha256):
    root = Path(root).resolve(strict=True)
    path = root / "pilot-manifest.json"
    if sha(path) != expected_manifest_sha256:
        raise ValueError("pilot manifest differs from the independently accepted freeze")
    manifest = json.loads(path.read_text())
    if manifest.get("schema_version") != 1 or manifest.get("pilot_revision") != REVISION or len(manifest.get("photos", [])) != COUNT:
        raise ValueError("unsupported frozen face pilot")
    if manifest["maximum_model_jobs_including_failures"] != COUNT or manifest["seed"] != 42:
        raise ValueError("frozen inference cap or seed changed")
    receipt_path = root / "pilot-run.json"
    if receipt_path.exists():
        raise ValueError("pilot already attempted; no automatic retry or replacement")
    for file_name, hash_key in [("source-selection.json", "source_selection_sha256"),
                                ("preparation-parameters.json", "preparation_parameters_sha256")]:
        if sha(root / file_name) != manifest[hash_key]:
            raise ValueError("selection or preparation parameters changed after freeze")
    receipt = {"schema_version": 1, "manifest_sha256": sha(path), "worker_sha256": sha(worker),
               "model_manifest_sha256": sha(model_manifest), "attempts": []}
    with (root / "model-manifest-exact.json").open("xb") as stream:
        stream.write(Path(model_manifest).read_bytes())
    write_new(receipt_path, receipt)  # Durable batch intent precedes the first process.
    started = time.monotonic()
    for photo in manifest["photos"]:
        attempt = photo["attempt"]
        request_path = root / attempt["request_relative_path"]
        if sha(request_path) != attempt["request_sha256"]:
            raise ValueError("frozen request changed")
        remaining = 600 - (time.monotonic() - started)
        record = {"capture_id": photo["capture_id"], "request_id": attempt["request_id"],
                  "status": "planned", "output_relative_path": attempt["output_relative_path"],
                  "supervisor_admitted_at_unix": None, "supervisor_admitted_at_utc": None,
                  "worker_started_at_unix": None, "worker_start_clock_status": "unknown-not-observed-by-batch-runner"}
        receipt["attempts"].append(record)
        if photo["preparation_status"] != "succeeded":
            record.update(status="unsupported_preparation", reason=photo["preparation_error"])
        elif remaining <= 0:
            record.update(status="skipped_wall_time_limit", reason="Frozen 600-second batch budget exhausted.")
        else:
            for file_name, hash_key in [("fixed-input.png", "input_sha256"),
                                        ("preparation.json", "preparation_sha256"),
                                        ("foreground-mask.png", "foreground_mask_sha256"),
                                        ("framed-source.png", "framed_source_sha256")]:
                if sha(root / photo["folder"] / file_name) != photo[hash_key]:
                    raise ValueError("frozen native preparation changed")
            argv = [sys.executable, str(Path(__file__).with_name("run_bounded.py")), "--python", str(python),
                    "--worker", str(worker), "--request", str(request_path), "--manifest", str(model_manifest),
                    "--output", str(root / attempt["output_relative_path"]), "--timeout", str(max(0.01, remaining))]
            record["argv"] = argv
            admitted = time.time()
            record.update(status="started", supervisor_admitted_at_unix=admitted,
                supervisor_admitted_at_utc=datetime.datetime.fromtimestamp(admitted, datetime.timezone.utc).isoformat())
            receipt_path.write_text(json.dumps(receipt, sort_keys=True, indent=2) + "\n")
            try:
                result = subprocess.run(argv)  # The one-request supervisor owns timeout/termination/reaping.
                record.update(returncode=result.returncode, status="completed" if result.returncode == 0 else "failed")
            except subprocess.TimeoutExpired:
                record.update(status="supervisor_timeout", reason="Supervisor exceeded remaining batch budget plus cleanup margin.")
        receipt_path.write_text(json.dumps(receipt, sort_keys=True, indent=2) + "\n")
    receipt["elapsed_seconds"] = time.monotonic() - started
    receipt_path.write_text(json.dumps(receipt, sort_keys=True, indent=2) + "\n")
    print(json.dumps({"run_receipt": str(receipt_path), "scheduled": len(receipt["attempts"]),
                      "elapsed_seconds": receipt["elapsed_seconds"]}, sort_keys=True))


def preserve(root):
    root = Path(root).resolve(strict=True)
    before = json.loads((root / "first-pilot-preservation-before.json").read_text())
    roots = sorted({entry["root"] for entry in before["files"]})
    after = inventory(roots)
    if after != before:
        raise ValueError("first-pilot inventory changed; inspect evidence before continuing")
    write_new(root / "first-pilot-preservation-after.json", after)
    print(json.dumps({"unchanged": True, "files": len(after["files"]),
                      "before_sha256": sha(root / "first-pilot-preservation-before.json"),
                      "after_sha256": sha(root / "first-pilot-preservation-after.json")}, sort_keys=True))


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="operation", required=True)
    planner = sub.add_parser("plan")
    planner.add_argument("--library", required=True)
    planner.add_argument("--output", required=True)
    planner.add_argument("--first-pilot", required=True)
    planner.add_argument("--exclude-source-hash", action="append", default=[])
    runner = sub.add_parser("run")
    runner.add_argument("--root", required=True)
    runner.add_argument("--model-manifest", required=True)
    runner.add_argument("--worker", required=True)
    runner.add_argument("--python", required=True)
    runner.add_argument("--expected-manifest-sha256", required=True)
    checker = sub.add_parser("preserve")
    checker.add_argument("--root", required=True)
    args = parser.parse_args()
    if args.operation == "plan":
        plan(args.library, args.output, args.first_pilot, args.exclude_source_hash)
    elif args.operation == "run":
        run(args.root, args.model_manifest, args.worker, args.python, args.expected_manifest_sha256)
    else:
        preserve(args.root)


if __name__ == "__main__":
    main()
