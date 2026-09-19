#!/usr/bin/env python3
"""Bounded fixture checks; no native app, camera, controller, or compiler invoked."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import time
import unittest
from datetime import datetime, timezone
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("inspect_running_app", Path(__file__).with_name("inspect_running_app.py"))
inspect = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(inspect)


class InspectionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.target = self.root / "target"
        self.source.mkdir(); self.target.mkdir()
        self.started = time.time() - 0.1
        self.manifest = self.source / "diagnostics-test.json"
        self.pixels = bytes([0, 10, 20, 255])
        self.content = {"format": "adaptiveplotter.debug-snapshot.v2", "processID": 123,
            "capturedAt": datetime.now(timezone.utc).isoformat(),
            "camera": {"width": 1, "height": 1, "rowBytes": 4, "pixelFormat": "bgra8",
                       "pixelsFile": "diagnostics-test.pixels", "imageFile": "diagnostics-test.png",
                       "contentSHA256": hashlib.sha256(self.pixels).hexdigest(),
                       "captureNanoseconds": 10, "frameID": "retained-frame"}}
        self.write_fixture()

    def tearDown(self):
        self.temporary.cleanup()

    def write_fixture(self):
        self.manifest.write_text(json.dumps(self.content))
        (self.source / "diagnostics-test.pixels").write_bytes(self.pixels)
        (self.source / "diagnostics-test.png").write_bytes(b"\x89PNG\r\n\x1a\nfixture")

    def collect(self, **kwargs):
        return inspect.collect_export(self.source, self.target, self.started, timeout=0, expected_pid=123, **kwargs)

    def test_fresh_export_retains_verified_bytes_and_stale_frame_caveat(self):
        result = self.collect()
        self.assertTrue(result["rawCameraPixelsAvailable"])
        self.assertEqual(result["processAttribution"], "matched")
        self.assertEqual(result["cameraCaptureNanoseconds"], 10)
        self.assertIn("stale", result["cameraFreshness"])
        self.assertEqual((self.target / "diagnostics-test.pixels").read_bytes(), self.pixels)
        self.assertEqual(result["manifestSHA256"], hashlib.sha256(self.manifest.read_bytes()).hexdigest())

    def test_baseline_export_is_not_reused_even_with_fresh_mtime(self):
        with self.assertRaises(TimeoutError):
            self.collect(known_names={self.manifest.name})
        self.assertEqual(list(self.target.iterdir()), [])

    def test_old_capture_or_other_process_is_not_current(self):
        for key, value in (("capturedAt", "2001-01-01T00:00:00Z"), ("processID", 456)):
            with self.subTest(key=key):
                original = self.content[key]
                self.content[key] = value
                self.write_fixture()
                with self.assertRaises(TimeoutError): self.collect()
                self.content[key] = original
        self.assertEqual(list(self.target.iterdir()), [])

    def test_old_schema_is_explicitly_no_raw_or_process_attribution(self):
        self.content["format"] = "adaptiveplotter.debug-snapshot.v1"
        self.write_fixture()
        result = self.collect()
        self.assertFalse(result["rawCameraPixelsAvailable"])
        self.assertEqual(result["processAttribution"], "unavailable")
        self.assertEqual(result["assets"], [])

    def test_v2_no_displayed_frame_is_not_an_export_failure(self):
        del self.content["camera"]
        self.write_fixture()
        self.assertFalse(self.collect()["rawCameraPixelsAvailable"])

    def test_path_traversal_and_reserved_output_names_are_rejected(self):
        for name in ("../outside.pixels", "/tmp/outside.pixels", "native.json", "diagnostics-test.json"):
            with self.subTest(name=name):
                self.content["camera"]["pixelsFile"] = name
                self.write_fixture()
                with self.assertRaises(ValueError): self.collect()
        self.assertEqual(list(self.target.iterdir()), [])

    def test_symlink_sidecar_and_manifest_are_rejected(self):
        outside = self.root / "outside"
        outside.write_bytes(self.pixels)
        asset = self.source / "diagnostics-test.pixels"
        asset.unlink(); asset.symlink_to(outside)
        with self.assertRaises(OSError): self.collect()
        asset.unlink(); asset.write_bytes(self.pixels)
        outside.write_bytes(self.manifest.read_bytes())
        self.manifest.unlink(); self.manifest.symlink_to(outside)
        with self.assertRaises(OSError): self.collect()
        self.assertEqual(list(self.target.iterdir()), [])

    def test_hash_and_pixel_layout_mismatch_publish_no_artifacts(self):
        for mutate in (
            lambda: (self.source / "diagnostics-test.pixels").write_bytes(b"evil"),
            lambda: self.content["camera"].update(rowBytes=8),
            lambda: self.content["camera"].update(pixelFormat="unknown"),
        ):
            with self.subTest(mutation=mutate):
                self.content["camera"].update(rowBytes=4, pixelFormat="bgra8")
                self.write_fixture(); mutate()
                self.manifest.write_text(json.dumps(self.content))
                with self.assertRaises(ValueError): self.collect()
        self.assertEqual(list(self.target.iterdir()), [])

    def test_verified_file_is_not_reread_for_copy(self):
        real_read = inspect.read_regular
        def raced_read(path, limit):
            data = real_read(path, limit)
            if path.suffix == ".pixels": path.write_bytes(b"changed-after-verification")
            return data
        with patch.object(inspect, "read_regular", side_effect=raced_read):
            self.collect()
        self.assertEqual((self.target / "diagnostics-test.pixels").read_bytes(), self.pixels)

    def test_sqlite_backup_includes_wal_and_bounded_tail(self):
        sessions = self.source / "MachineSessions"
        sessions.mkdir()
        database = sessions / "session-live.sqlite"
        with contextlib.closing(sqlite3.connect(database)) as connection:
            connection.execute("PRAGMA journal_mode=WAL")
            connection.execute("CREATE TABLE event (sequence INTEGER PRIMARY KEY, wall_time TEXT, kind TEXT, payload BLOB)")
            connection.executemany("INSERT INTO event VALUES (?, ?, ?, ?)",
                [(index, "now", "fixture", json.dumps({"value": index})) for index in range(1, 124)])
            connection.execute("INSERT INTO event VALUES (124, 'now', 'large', ?)", ("x" * 70_000,))
            connection.commit()
            self.assertTrue(Path(str(database) + "-wal").is_file())
            result = inspect.collect_persisted_state(self.source, self.target)
            with contextlib.closing(sqlite3.connect(self.target / "machine-session.sqlite")) as copied:
                self.assertEqual(copied.execute("SELECT COUNT(*) FROM event").fetchone()[0], 124)
            tail = json.loads((self.target / "machine-events-tail.json").read_text())
            self.assertEqual(len(tail), 120)
            self.assertEqual(tail[0]["sequence"], 5)
            self.assertIn("omitted", tail[-1]["payload"])
            self.assertIn("WAL", result["machineSessionSelection"])
            self.assertEqual(result["machineSessionSnapshot"]["contentSHA256"],
                             hashlib.sha256((self.target / "machine-session.sqlite").read_bytes()).hexdigest())

    def run_main(self, natives, *, export_results=None, persisted_error=None):
        project = self.root / "project"
        (project / "Scripts").mkdir(parents=True, exist_ok=True)
        fake_source = project / "Scripts/inspect_running_app.py"
        (project / "Scripts/inspect_running_app.swift").write_text("// not compiled")
        output = self.root / f"inspection-{len(list(self.root.glob('inspection-*')))}"
        native_samples = iter(natives)
        def run(arguments, **_kwargs):
            if arguments[0] == "swiftc": return
            sample = Path(arguments[arguments.index("--output") + 1])
            native = next(native_samples)
            (sample / "native.json").write_text(json.dumps(native))
            if native.get("windowCaptureExitCode") == 0:
                (sample / "window.png").write_bytes(b"native fixture")
        argv = ["inspect", "--output", str(output), "--samples", str(len(natives))]
        if export_results is not None: argv.append("--export-diagnostics")
        previous_umask = os.umask(0o077)
        try:
            with patch.object(inspect, "__file__", str(fake_source)), patch.object(inspect.subprocess, "run", side_effect=run), \
                 patch.object(Path, "home", return_value=self.root), patch.object(inspect.time, "sleep"), \
                 patch.object(inspect, "collect_export", side_effect=export_results) as collect, \
                 patch.object(inspect, "collect_persisted_state", return_value={}, side_effect=persisted_error), \
                 patch("sys.argv", argv), contextlib.redirect_stdout(io.StringIO()) as stdout:
                status = inspect.main()
        finally:
            os.umask(previous_umask)
        result = json.loads((output / "inspection.json").read_text())
        return status, result, stdout.getvalue(), output, collect

    @staticmethod
    def complete_native(**changes):
        return {"pid": 123, "windowCaptureExitCode": 0, "accessibilityScope": "capturedWindow",
                "accessibility": [{"role": "AXWindow"}], "diagnosticExportRequest": 0, **changes}

    @staticmethod
    def matched_export(**changes):
        return {"format": "adaptiveplotter.debug-snapshot.v2", "processAttribution": "matched",
                "rawCameraPixelsAvailable": True, **changes}

    def test_no_running_app_retains_error_artifacts_and_returns_two(self):
        status, result, stdout, output, _ = self.run_main([{"errors": ["No running AdaptivePlotter"]}])
        self.assertEqual(status, 2)
        self.assertNotIn("Captured ", stdout)
        self.assertFalse(result["inspectionComplete"])
        self.assertFalse(result["samples"][0]["nativeCaptureComplete"])
        self.assertFalse(result["samples"][0]["requestedInspectionComplete"])
        self.assertIn("No running", result["samples"][0]["nativeErrors"][0])
        self.assertTrue((output / "sample-001/native.json").is_file())

    def test_locked_desktop_preserves_identity_and_reports_unlock_without_export(self):
        native = {"pid": 123, "screenLockState": "locked", "nativeCaptureSkippedReason": "lockedSession",
                  "screenRecordingAuthorized": True, "accessibilityAuthorized": True,
                  "accessibilityScope": "unavailableLockedSession",
                  "errors": ["Console session is locked. Unlock the existing desktop and rerun inspection."]}
        status, result, stdout, output, collect = self.run_main([native], export_results=[])
        self.assertEqual(status, 2)
        self.assertFalse(result["inspectionComplete"])
        sample = result["samples"][0]
        self.assertEqual(sample["pid"], 123)
        self.assertEqual(sample["screenLockState"], "locked")
        self.assertFalse(sample["nativeCaptureComplete"])
        self.assertFalse(sample["exportComplete"])
        self.assertIn("unlock the existing desktop", sample["exportError"])
        self.assertNotIn("Captured ", stdout)
        self.assertFalse((output / "sample-001/window.png").exists())
        self.assertEqual(json.loads((output / "sample-001/native.json").read_text()), native)
        collect.assert_not_called()

    def test_native_only_complete_samples_succeed_without_export(self):
        status, result, stdout, _, collect = self.run_main([self.complete_native(), self.complete_native()])
        self.assertEqual(status, 0)
        self.assertTrue(result["inspectionComplete"])
        self.assertEqual(result["requestedSamples"], 2)
        self.assertFalse(result["exportRequested"])
        self.assertEqual(stdout.count("Captured "), 2)
        collect.assert_not_called()

    def test_requested_export_timeout_preserves_native_evidence_and_returns_partial(self):
        status, result, stdout, output, _ = self.run_main([self.complete_native()],
            export_results=[TimeoutError("No matching fresh export")])
        self.assertEqual(status, 3)
        self.assertFalse(result["inspectionComplete"])
        self.assertNotIn("Captured ", stdout)
        sample = result["samples"][0]
        self.assertTrue(sample["nativeCaptureComplete"])
        self.assertFalse(sample["exportComplete"])
        self.assertFalse(sample["requestedInspectionComplete"])
        self.assertIn("No matching", sample["exportError"])
        self.assertTrue((output / "sample-001/window.png").is_file())
        self.assertTrue((output / "sample-001/native.json").is_file())

    def test_requested_export_missing_or_failed_ax_action_returns_partial(self):
        for action in (None, -25200):
            with self.subTest(action=action):
                native = self.complete_native()
                if action is None: del native["diagnosticExportRequest"]
                else: native["diagnosticExportRequest"] = action
                status, result, stdout, _, collect = self.run_main([native], export_results=[])
                self.assertEqual(status, 3)
                self.assertFalse(result["samples"][0]["exportComplete"])
                self.assertIn("Accessibility action failed", result["samples"][0]["exportError"])
                self.assertNotIn("Captured ", stdout)
                collect.assert_not_called()

    def test_legacy_or_unattributed_export_does_not_fulfill_request(self):
        for schema, attribution in (("adaptiveplotter.debug-snapshot.v1", "unavailable"),
                                    ("adaptiveplotter.debug-snapshot.v2", "unavailable")):
            with self.subTest(schema=schema):
                export = self.matched_export(format=schema, processAttribution=attribution)
                status, result, _, _, _ = self.run_main([self.complete_native()], export_results=[export])
                self.assertEqual(status, 3)
                self.assertFalse(result["inspectionComplete"])
                self.assertEqual(result["samples"][0]["export"], export)
                self.assertIn("matching v2 export is required", result["samples"][0]["exportError"])

    def test_native_and_matched_export_succeed_with_or_without_displayed_camera(self):
        for camera_available in (True, False):
            with self.subTest(camera_available=camera_available):
                status, result, stdout, _, collect = self.run_main([self.complete_native()],
                    export_results=[self.matched_export(rawCameraPixelsAvailable=camera_available)])
                self.assertEqual(status, 0)
                self.assertTrue(result["inspectionComplete"])
                self.assertTrue(result["exportRequested"])
                sample = result["samples"][0]
                self.assertTrue(sample["exportComplete"])
                self.assertTrue(sample["requestedInspectionComplete"])
                self.assertEqual(sample["export"]["rawCameraPixelsAvailable"], camera_available)
                self.assertIn("Captured ", stdout)
                self.assertEqual(collect.call_args.kwargs["expected_pid"], 123)

    def test_partial_native_sample_sequence_returns_partial(self):
        status, result, stdout, _, _ = self.run_main([
            self.complete_native(), self.complete_native(accessibilityTruncated=True)])
        self.assertEqual(status, 3)
        self.assertFalse(result["inspectionComplete"])
        self.assertEqual([sample["requestedInspectionComplete"] for sample in result["samples"]], [True, False])
        self.assertEqual(stdout.count("Captured "), 1)

    def test_partial_export_sample_sequence_returns_partial(self):
        status, result, stdout, _, _ = self.run_main([self.complete_native(), self.complete_native()],
            export_results=[self.matched_export(), TimeoutError("second sample export missing")])
        self.assertEqual(status, 3)
        self.assertFalse(result["inspectionComplete"])
        self.assertEqual([sample["exportComplete"] for sample in result["samples"]], [True, False])
        self.assertEqual(stdout.count("Captured "), 1)

    def test_persisted_state_failure_retains_samples_and_returns_partial(self):
        status, result, _, _, _ = self.run_main([self.complete_native()], persisted_error=OSError("archive unreadable"))
        self.assertEqual(status, 3)
        self.assertTrue(result["samples"][0]["requestedInspectionComplete"])
        self.assertFalse(result["inspectionComplete"])
        self.assertEqual(result["errors"], ["archive unreadable"])


if __name__ == "__main__":
    unittest.main()
