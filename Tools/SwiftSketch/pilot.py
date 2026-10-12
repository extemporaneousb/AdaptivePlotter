#!/usr/bin/env python3
"""Freeze six originals before outputs;18 paired attempts maximum, no replacement."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import time
import uuid
from prepare import prepare, POLICY


def plan(library, destination, exclude_hashes):
    library = Path(library).resolve()
    output = Path(destination).resolve()
    if output.exists():
        raise ValueError("pilot directory exists")
    database = sqlite3.connect((library/"library-v1.sqlite").as_uri()+"?mode=ro", uri=True)
    rows = database.execute("SELECT id,source_hash,reference,captured_at FROM photo WHERE deleted=0 ORDER BY captured_at,id").fetchall()
    database.close()
    distinct = []
    seen = set(exclude_hashes)
    for row in rows:
        if row[1] not in seen:
            distinct.append(row)
            seen.add(row[1])
    if len(distinct) < 6:
        raise ValueError("fewer than six distinct unused originals")
    indices = [i*(len(distinct)-1)//5 for i in range(6)]
    output.mkdir(parents=True)
    selections = []
    for index, position in enumerate(indices):
        capture_id, source_hash, reference, timestamp = distinct[position]
        reference = json.loads(reference)
        source = library/"assets"/source_hash
        if hashlib.sha256(source.read_bytes()).hexdigest() != source_hash:
            raise ValueError("retained source hash mismatch")
        folder = output/("photo-%02d" % index)
        folder.mkdir()
        original = folder/"original.asset"
        shutil.copyfile(source, original)
        prepared = folder/"fixed-input.png"
        receipt = prepare(original, prepared)
        metadata = {"capture_id": capture_id, "source_sha256": source_hash,
            "reference": reference, "ordered_retained_timestamp": timestamp,
            "acquisition_id": reference.get("captureSessionID"),
            "human_subject_group": None, "human_photo_session_group": None,
            "subject_session_assignment_status": "unassigned-requires-human",
            "selected_distinct_position": position, "preparation": receipt}
        (folder/"source-receipt.json").write_text(json.dumps(metadata, sort_keys=True))
        attempts = []
        for variant in ("unchanged", "gamma08", "contrast115"):
            request_id = str(uuid.uuid5(uuid.NAMESPACE_URL, "swiftsketch-pilot-v1:"+source_hash+":"+variant))
            request = {"schema_version": 1, "request_id": request_id,
                "input_path": str(prepared), "input_sha256": receipt["input_sha256"],
                "preprocessing": variant, "seed": 42, "mask_policy": "fixed-input-no-segmentation-v1",
                "source_receipt_sha256": hashlib.sha256((folder/"source-receipt.json").read_bytes()).hexdigest()}
            request_path = folder/(variant+"-request.json")
            request_path.write_text(json.dumps(request, sort_keys=True))
            attempts.append({"variant": variant, "request_path": str(request_path),
                "request_sha256": hashlib.sha256(request_path.read_bytes()).hexdigest(),
                "output_path": str(folder/(variant+"-attempt"))})
        selections.append(dict(metadata, attempts=attempts))
    manifest = {"schema_version": 1, "pilot_revision": "portrait-swiftsketch-preprocessing-v1",
        "selection_rule": "Distinct source hashes, excluding declared smoke hashes; ordered retained captured_at,id metadata; positions floor(i*(N-1)/5),i=0..5. Timestamps are not asserted actual capture times.",
        "eligible_distinct_count": len(distinct), "excluded_smoke_hashes": exclude_hashes,
        "fixed_input_policy": POLICY, "seed": 42, "maximum_attempts_including_failures": 18,
        "variants": ["unchanged", "gamma08", "contrast115"],
        "gamma_equation": "u**0.8 in encoded-sRGB,round-to-8bit", "contrast_equation": "clamp((u-0.5)*1.15+0.5,0,1) in encoded-sRGB,round-to-8bit",
        "photos": selections, "human_labels": "unassigned; no inferred quality,identity or session labels"}
    path = output/"pilot-manifest.json"
    path.write_text(json.dumps(manifest, sort_keys=True))
    print(json.dumps({"manifest_path": str(path), "manifest_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}, sort_keys=True))


def run(manifest_path, model_manifest, worker, python):
    path = Path(manifest_path)
    manifest = json.loads(path.read_text())
    if manifest.get("schema_version") != 1 or len(manifest.get("photos", [])) != 6 or manifest["maximum_attempts_including_failures"] != 18:
        raise ValueError("unsupported frozen pilot")
    run_receipt = path.with_name("pilot-run.json")
    if run_receipt.exists():
        raise ValueError("pilot was already attempted; no replacement/retry")
    receipt = {"schema_version": 1, "manifest_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
               "model_manifest_sha256": hashlib.sha256(Path(model_manifest).read_bytes()).hexdigest(), "attempts": []}
    started = time.monotonic()
    run_receipt.write_text(json.dumps(receipt, sort_keys=True))
    for photo in manifest["photos"]:
        for attempt in photo["attempts"]:
            request_path = Path(attempt["request_path"])
            if hashlib.sha256(request_path.read_bytes()).hexdigest() != attempt["request_sha256"]:
                raise ValueError("frozen pilot request changed")
            remaining = 600-(time.monotonic()-started)
            argv = [sys.executable, str(Path(__file__).with_name("run_bounded.py")), "--python", python,
                "--worker", worker, "--request", str(request_path), "--manifest", model_manifest,
                "--output", attempt["output_path"], "--timeout", str(max(0.01, remaining))]
            # Record intent before launch; interrupted attempts count toward the18attempt cap.
            record = {"capture_id": photo["capture_id"], "variant": attempt["variant"], "argv": argv, "status": "started"}
            receipt["attempts"].append(record)
            if remaining <= 0:
                record["status"] = "skipped_wall_time_limit"
                run_receipt.write_text(json.dumps(receipt, sort_keys=True))
                continue
            run_receipt.write_text(json.dumps(receipt, sort_keys=True))
            result = subprocess.run(argv, timeout=remaining+3)
            record["returncode"] = result.returncode
            record["status"] = "completed" if result.returncode == 0 else "failed"
            run_receipt.write_text(json.dumps(receipt, sort_keys=True))
    receipt["elapsed_seconds"] = time.monotonic()-started
    run_receipt.write_text(json.dumps(receipt, sort_keys=True))
    print(json.dumps({"run_receipt": str(run_receipt), "attempts": len(receipt["attempts"])}, sort_keys=True))


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="operation", required=True)
    planner = sub.add_parser("plan")
    planner.add_argument("--library", required=True)
    planner.add_argument("--output", required=True)
    planner.add_argument("--exclude-source-hash", action="append", default=[])
    runner = sub.add_parser("run")
    runner.add_argument("--pilot-manifest", required=True)
    runner.add_argument("--model-manifest", required=True)
    runner.add_argument("--worker", required=True)
    runner.add_argument("--python", required=True)
    args = parser.parse_args()
    if args.operation == "plan":
        plan(args.library, args.output, args.exclude_source_hash)
    else:
        run(args.pilot_manifest, args.model_manifest, args.worker, args.python)


if __name__ == "__main__":
    main()
