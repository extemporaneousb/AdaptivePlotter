#!/usr/bin/env python3
"""Bounded native inspection. Never launches/restarts the app or sends plotter commands."""
import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import stat
import subprocess
import time
import math
from datetime import datetime, timezone


def save_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def read_regular(path, limit):
    """Read one bounded, non-symlink file; verification and copying use these bytes."""
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
            raise ValueError(f"Inspection file is not regular or exceeds its bound: {path.name}")
        data = stream.read(limit + 1)
        if len(data) > limit:
            raise ValueError(f"Inspection file exceeds its bound: {path.name}")
        return data


def export_inventory(source):
    return {path.name for path in source.glob("diagnostics-*.json")}


def export_time(content):
    value = datetime.fromisoformat(content["capturedAt"].replace("Z", "+00:00"))
    if value.tzinfo is None:
        raise ValueError("Diagnostic capture time has no timezone")
    return value.timestamp()


def collect_export(source, target, newer_than, timeout=10, *, known_names=(), expected_pid=None):
    """Copy only a new matching export; export freshness never implies a fresh camera frame."""
    deadline = time.monotonic() + timeout
    known_names = set(known_names)
    while True:
        matches = sorted((p for p in source.glob("diagnostics-*.json")
                          if p.name not in known_names and p.lstat().st_mtime >= newer_than),
                         key=lambda p: p.lstat().st_mtime, reverse=True)
        for manifest in matches:
            manifest_bytes = read_regular(manifest, 16 * 1024 * 1024)
            content = json.loads(manifest_bytes)
            schema = content.get("format")
            if schema not in ("adaptiveplotter.debug-snapshot.v1", "adaptiveplotter.debug-snapshot.v2"):
                raise ValueError("Unsupported diagnostic manifest format")
            # The app's ISO8601 writer has one-second resolution. Baseline filename
            # exclusion closes the same-second stale-export ambiguity.
            captured = export_time(content)
            if captured < math.floor(newer_than) or captured > time.time() + 1:
                continue
            if schema.endswith(".v2") and expected_pid is not None and content.get("processID") != expected_pid:
                continue
            camera = content.get("camera") if schema.endswith(".v2") else None
            assets = []
            if camera is not None:
                width, height, row_bytes = (camera[key] for key in ("width", "height", "rowBytes"))
                bytes_per_pixel = {"gray8": 1, "rgba8": 4, "bgra8": 4}.get(camera.get("pixelFormat"))
                if (any(type(value) is not int or value <= 0 for value in (width, height, row_bytes))
                    or bytes_per_pixel is None or row_bytes < width * bytes_per_pixel
                    or row_bytes * height > 128 * 1024 * 1024):
                    raise ValueError("Invalid raw camera pixel layout or inspection size")
                for key, suffix in (("pixelsFile", ".pixels"), ("imageFile", ".png")):
                    name = camera[key]
                    if name != manifest.stem + suffix:
                        raise ValueError("Diagnostic asset is not the manifest's local sidecar filename")
                    data = read_regular(source / name, 128 * 1024 * 1024)
                    digest = hashlib.sha256(data).hexdigest()
                    if key == "pixelsFile" and (len(data) != row_bytes * height or digest != camera["contentSHA256"]):
                        raise ValueError("Raw camera pixel length or hash does not match manifest")
                    if key == "imageFile" and not data.startswith(b"\x89PNG\r\n\x1a\n"):
                        raise ValueError("Diagnostic image is not a PNG sidecar")
                    assets.append((name, data, digest))
            # Validate every sidecar before publishing any collected file. The
            # exact bytes hashed above are those retained, never a second read.
            for name, data, _ in assets:
                with (target / name).open("xb") as stream:
                    stream.write(data)
            with (target / manifest.name).open("xb") as stream:
                stream.write(manifest_bytes)
            return {"manifest": manifest.name, "manifestSHA256": hashlib.sha256(manifest_bytes).hexdigest(),
                    "assets": [name for name, _, _ in assets],
                    "assetSHA256": {name: digest for name, _, digest in assets}, "format": schema,
                    "processAttribution": "matched" if expected_pid is not None and schema.endswith(".v2") else "unavailable",
                    "exportCapturedAt": content["capturedAt"], "rawCameraPixelsAvailable": camera is not None,
                    "cameraCaptureNanoseconds": camera.get("captureNanoseconds") if camera else None,
                    "cameraFrameID": camera.get("frameID") if camera else None,
                    "cameraFreshness": "Displayed frame may be frozen or stale; export time is not capture time."}
        if time.monotonic() >= deadline:
            raise TimeoutError("No new matching diagnostic manifest; app may be busy or export unavailable. Existing or other-process exports were not mislabeled current.")
        time.sleep(0.1)


def collect_persisted_state(support, target):
    facts = {}
    archive = support / "DrawingEvidence/drawing-run-evidence-v1.json"
    if archive.exists():
        data = read_regular(archive, 64 * 1024 * 1024)
        (target / "drawing-archive.json").write_bytes(data)
        facts["drawingArchive"] = {"source": str(archive), "modifiedAtUnix": archive.stat().st_mtime,
                                   "contentSHA256": hashlib.sha256(data).hexdigest()}
    def modification_time(path):
        wal = Path(str(path) + "-wal")
        return max(path.stat().st_mtime, wal.stat().st_mtime if wal.exists() else 0)
    sessions = sorted((p for p in (support / "MachineSessions").glob("session-*.sqlite")
                       if p.is_file() and not p.is_symlink()), key=modification_time)
    if sessions:
        selected = sessions[-1]
        facts["machineSessionSelection"] = "Most recently modified SQLite database or WAL; verify run timestamps against native process launch."
        facts["machineSessionSource"] = str(selected)
        started = time.monotonic()
        temporary = target / ".machine-session.sqlite.tmp"
        try:
            with closing(sqlite3.connect(selected.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)) as source:
                page_size = source.execute("PRAGMA page_size").fetchone()[0]
                if source.execute("PRAGMA page_count").fetchone()[0] * page_size > 256 * 1024 * 1024:
                    facts["machineSessionOmitted"] = "Database including WAL exceeds 256 MiB inspection bound."
                    return facts
                def progress(_status, _remaining, total):
                    if time.monotonic() - started > 10 or total * page_size > 256 * 1024 * 1024:
                        raise TimeoutError("SQLite snapshot exceeded its 10-second or 256 MiB bound")
                with closing(sqlite3.connect(temporary)) as destination:
                    source.backup(destination, pages=256, progress=progress)
                    rows = destination.execute("SELECT sequence, wall_time, kind, CASE WHEN length(payload) <= 65536 THEN payload END FROM event ORDER BY sequence DESC LIMIT 120").fetchall()
                    events = []
                    for sequence, wall, kind, payload in reversed(rows):
                        if payload is None:
                            payload = {"omitted": "payload absent or exceeds 64 KiB; original retained in SQLite snapshot"}
                        else:
                            try: payload = json.loads(payload)
                            except (ValueError, TypeError): payload = {"unparsed": repr(payload)}
                        events.append({"sequence": sequence, "wallTime": wall, "kind": kind, "payload": payload})
            snapshot = target / "machine-session.sqlite"
            temporary.replace(snapshot)
            save_json(target / "machine-events-tail.json", events)
            facts["machineSessionSnapshot"] = {"contentSHA256": hashlib.sha256(snapshot.read_bytes()).hexdigest(),
                                              "capturedAt": datetime.now(timezone.utc).isoformat()}
        finally:
            temporary.unlink(missing_ok=True)
    return facts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, help="Select one running AdaptivePlotter when multiple copies exist")
    parser.add_argument("--output", type=Path, required=True, help="New output directory")
    parser.add_argument("--export-diagnostics", action="store_true", help="Press only the existing Export Diagnostics button to copy current displayed raw pixels and plan")
    parser.add_argument("--samples", type=int, default=1, choices=range(1, 121), metavar="1..120")
    parser.add_argument("--interval", type=float, default=5, help="Seconds between samples (minimum 1)")
    args = parser.parse_args()
    if not math.isfinite(args.interval) or args.interval < 1: parser.error("--interval must be finite and at least 1 second")
    if args.pid is not None and args.pid <= 0: parser.error("--pid must identify a positive process ID")
    os.umask(0o077)
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=False)
    root = Path(__file__).resolve().parent.parent
    helper = root / "Scripts/inspect_running_app.swift"
    cache = root / ".build/inspection-tools"
    cache.mkdir(parents=True, exist_ok=True)
    binary = cache / ("inspect-" + hashlib.sha256(helper.read_bytes()).hexdigest()[:16])
    if not binary.exists():
        subprocess.run(["swiftc", str(helper), "-o", str(binary)], check=True, timeout=60)
    diagnostics = Path.home() / "Library/Logs/AdaptivePlotter/Diagnostics"
    support = Path.home() / "Library/Application Support/AdaptivePlotter"
    manifest = {"format": "adaptiveplotter.native-inspection.v1", "samples": [], "errors": [],
                "startedAt": datetime.now(timezone.utc).isoformat(),
                "requestedSamples": args.samples, "exportRequested": args.export_diagnostics,
                "inspectionComplete": False,
                "limitations": ["No app restart, camera reconfiguration, controller command, or calibration change.",
                                "Repeated snapshots are sampled observations, not continuous video or verified ink coverage.",
                                "Native, exported camera, and persisted controller state are independently timestamped."]}
    for index in range(args.samples):
        sample = output / f"sample-{index + 1:03d}"
        sample.mkdir()
        started = time.time()
        known_exports = export_inventory(diagnostics) if args.export_diagnostics else set()
        command = [str(binary), "--output", str(sample)]
        if args.pid: command += ["--pid", str(args.pid)]
        if args.export_diagnostics: command += ["--export-diagnostics"]
        try:
            subprocess.run(command, check=True, timeout=30)
            native = json.loads((sample / "native.json").read_text())
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            native = {"errors": [f"Native helper unavailable: {error}"]}
        complete = (type(native.get("pid")) is int and native["pid"] > 0
                    and native.get("windowCaptureExitCode") == 0 and (sample / "window.png").is_file()
                    and native.get("accessibilityScope") == "capturedWindow"
                    and bool(native.get("accessibility")) and not native.get("accessibilityTruncated", False))
        receipt = {"directory": sample.name, "nativeErrors": native.get("errors", []),
                   "nativeCaptureComplete": complete, "pid": native.get("pid"),
                   "screenLockState": native.get("screenLockState", "unknown")}
        executable = native.get("executable")
        if executable and Path(executable).is_file():
            receipt["executableSHA256"] = hashlib.sha256(Path(executable).read_bytes()).hexdigest()
        if args.export_diagnostics:
            receipt["exportComplete"] = False
            if type(native.get("diagnosticExportRequest")) is int and native["diagnosticExportRequest"] == 0:
                try:
                    receipt["export"] = collect_export(diagnostics, sample,
                        native.get("diagnosticExportRequestedAtUnix", started), known_names=known_exports,
                        expected_pid=native.get("pid"))
                    receipt["exportComplete"] = (receipt["export"]["format"] == "adaptiveplotter.debug-snapshot.v2"
                        and receipt["export"]["processAttribution"] == "matched")
                    if not receipt["exportComplete"]:
                        receipt["exportError"] = "Collected diagnostic export cannot verify the inspected process; a matching v2 export is required."
                except (OSError, ValueError, KeyError, TypeError, TimeoutError) as error:
                    receipt["exportError"] = str(error)
            else:
                receipt["exportError"] = ("Diagnostic export was skipped because the macOS console session is locked; unlock the existing desktop and rerun inspection."
                    if native.get("screenLockState") == "locked" else
                    "Requested diagnostic export was unavailable or its Accessibility action failed.")
        receipt["requestedInspectionComplete"] = complete and (not args.export_diagnostics or receipt["exportComplete"])
        manifest["samples"].append(receipt)
        save_json(output / "inspection.json", manifest)
        print(f"{'Captured' if receipt['requestedInspectionComplete'] else 'Inspection incomplete:'} {sample}", flush=True)
        if index + 1 < args.samples: time.sleep(max(0, args.interval - (time.time() - started)))
    try: manifest["persistedState"] = collect_persisted_state(support, output)
    except (OSError, ValueError, sqlite3.Error, TimeoutError) as error: manifest["errors"].append(str(error))
    manifest["inspectionComplete"] = (all(sample["requestedInspectionComplete"] for sample in manifest["samples"])
                                      and not manifest["errors"])
    save_json(output / "inspection.json", manifest)
    print(output / "inspection.json", flush=True)
    if not any(sample["nativeCaptureComplete"] for sample in manifest["samples"]):
        return 2
    return 0 if manifest["inspectionComplete"] else 3


if __name__ == "__main__":
    raise SystemExit(main())
