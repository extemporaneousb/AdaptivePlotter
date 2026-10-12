#!/usr/bin/env python3
"""Disposable repository-contract cases; no Swift compilation or worker execution."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
GUARD = ROOT / "Scripts/check_repository_contract.sh"
CLIENT = Path("Sources/PortraitArtists/SwiftSketchClient.swift")
REVIEWED_CLIENT = (ROOT / CLIENT).read_bytes()


class RepositoryContractTests(unittest.TestCase):
    def run_guard(self, files):
        with tempfile.TemporaryDirectory(prefix="portrait-contract-") as folder:
            root = Path(folder)
            (root / "Sources").mkdir()
            for name, data in files.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data if isinstance(data, bytes) else data.encode())
            return subprocess.run(["sh", str(GUARD)], cwd=root, capture_output=True, text=True, timeout=5)

    def test_accepts_reviewed_two_local_invocations(self):
        result = self.run_guard({CLIENT: REVIEWED_CLIENT})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_network_remains_forbidden_inside_reviewed_client_path(self):
        for capability in ("URLSession", "URLRequest", "NWConnection", "NWListener"):
            with self.subTest(capability=capability):
                result = self.run_guard({CLIENT: REVIEWED_CLIENT + ("\nlet denied = " + capability + "()\n").encode()})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("network capability", result.stderr)

    def test_third_process_in_allowed_client_is_rejected(self):
        result = self.run_guard({CLIENT: REVIEWED_CLIENT + b"\nlet third = Process()\n"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("subprocess seams changed", result.stderr)

    def test_changed_python_or_rss_target_is_rejected(self):
        changes = [
            (b"process.executableURL = config.pythonExecutable", b'process.executableURL = URL(fileURLWithPath: "/bin/sh")'),
            (b'fileURLWithPath: "/bin/ps"', b'fileURLWithPath: "/usr/bin/ssh"'),
            (b'"--request", requestFile.path', b'"--unapproved", requestFile.path'),
        ]
        for old, new in changes:
            with self.subTest(change=old):
                self.assertIn(old, REVIEWED_CLIENT)
                result = self.run_guard({CLIENT: REVIEWED_CLIENT.replace(old, new)})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("subprocess seams changed", result.stderr)

    def test_unapproved_paths_and_same_basename_remain_forbidden(self):
        for path in ("Sources/PlotterApp/Unexpected.swift", "Sources/Other/SwiftSketchClient.swift"):
            with self.subTest(path=path):
                result = self.run_guard({CLIENT: REVIEWED_CLIENT, path: "let denied = Process()\n"})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("unapproved child-process", result.stderr)

    def test_non_swift_product_source_remains_forbidden(self):
        for suffix in ("py", "js", "ts"):
            with self.subTest(suffix=suffix):
                result = self.run_guard({CLIENT: REVIEWED_CLIENT, "Sources/Unexpected." + suffix: "fixture\n"})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("non-Swift live product source", result.stderr)


if __name__ == "__main__":
    unittest.main()
