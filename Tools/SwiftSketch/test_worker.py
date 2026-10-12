"""Protocol-only tests. These do not claim model inference or portrait quality."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import uuid
from unittest import mock
import worker


class WorkerContractTests(unittest.TestCase):
    def request(self, path):
        return {"schema_version": 1, "request_id": str(uuid.uuid4()), "input_path": str(path),
                "input_sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "preprocessing": "unchanged",
                "seed": 42, "mask_policy": "fixed-input-no-segmentation-v1"}

    def test_rejects_input_hash_mismatch_and_unsupported_variants(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/"input.png"
            path.write_bytes(b"bounded fixture")
            request = self.request(path)
            worker.validate_request(request)
            request["input_sha256"] = "0"*64
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                worker.validate_request(request)
            request = self.request(path)
            request["preprocessing"] = "tuned-gamma"
            with self.assertRaisesRegex(ValueError, "preprocessing"):
                worker.validate_request(request)

    def test_unavailable_model_is_a_retained_terminal_receipt(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            image = base/"input.png"; image.write_bytes(b"bounded fixture")
            request = base/"request.json"; request.write_text(json.dumps(self.request(image)))
            manifest = base/"missing-manifest.json"
            output = base/"attempt"
            result = subprocess.run([sys.executable, str(Path(worker.__file__)), "--request", str(request),
                "--manifest", str(manifest), "--output", str(output)], capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 2)
            terminal = json.loads((output/"response.json").read_text())
            self.assertEqual(terminal["status"], "unavailable")
            self.assertEqual(terminal["request_id"], json.loads(request.read_text())["request_id"])
            self.assertEqual(set(terminal["files"]), {"provenance.json"})
            provenance = json.loads((output/"provenance.json").read_text())
            self.assertEqual(provenance["failure"]["phase"], "manifest-read")
            self.assertEqual(provenance["model_manifest_observation"], "unknown")
            self.assertEqual(provenance["environment"]["runtime_import_versions"]["observation"], "unknown")

    def test_all_official_pins_reject_altered_bytes_even_with_matching_manifest(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            paths = {}
            for key in worker.OFFICIAL_ASSET_SHA256:
                paths[key] = base/key
                paths[key].write_bytes(b"original test stand-in")
            for target in worker.OFFICIAL_ASSET_SHA256:
                with self.subTest(asset=target):
                    paths[target].write_bytes(b"altered bytes with a caller-updated manifest")
                    changed = hashlib.sha256(paths[target].read_bytes()).hexdigest()
                    manifest = {"schema_version":1,"upstream_commit":worker.UPSTREAM_COMMIT,"upstream_root":str(base),
                        "assets": {key:{"path":str(path),"sha256":changed if key==target else worker.OFFICIAL_ASSET_SHA256[key]}
                                   for key,path in paths.items()}}
                    provenance = worker.initial_provenance()
                    # Only unaffected hashes are stand-ins; the changed asset has actual bytes+hash.
                    def observed(path):
                        path = Path(path)
                        return hashlib.sha256(path.read_bytes()).hexdigest() if path.name==target else worker.OFFICIAL_ASSET_SHA256[path.name]
                    with mock.patch.object(worker,"digest",side_effect=observed):
                        with self.assertRaisesRegex(ValueError,"official pretrained pin mismatch: "+target):
                            worker.validate_manifest(manifest,provenance)
                    result = provenance["model_assets"][target]
                    self.assertEqual(result["declared_sha256"],changed)
                    self.assertEqual(result["observed_sha256"],changed)
                    self.assertEqual(result["expected_sha256"],worker.OFFICIAL_ASSET_SHA256[target])
                    self.assertEqual(result["observation"],"declared-pin-mismatch")

    def test_runtime_version_mismatch_records_observed_versions(self):
        context = worker.initial_provenance()
        versions = dict(worker.RUNTIME_VERSIONS,torch="9.9.9")
        with self.assertRaisesRegex(ValueError,"runtime versions"):
            worker.validate_runtime_versions(versions,context)
        self.assertEqual(context["environment"]["runtime_import_versions"],
                         {"observation":"observed","versions":versions})

    def test_official_declaration_does_not_accept_changed_actual_bytes(self):
        with tempfile.TemporaryDirectory() as folder:
            base=Path(folder)
            assets={}
            for key,expected in worker.OFFICIAL_ASSET_SHA256.items():
                path=base/key;path.write_bytes(b"changed bytes")
                assets[key]={"path":str(path),"sha256":expected}
            manifest={"schema_version":1,"upstream_commit":worker.UPSTREAM_COMMIT,"upstream_root":str(base),"assets":assets}
            context=worker.initial_provenance()
            with self.assertRaisesRegex(ValueError,"official pretrained bytes mismatch"):
                worker.validate_manifest(manifest,context)
            self.assertTrue(all(value["observation"]=="actual-byte-mismatch"for value in context["model_assets"].values()))

    def test_failure_after_input_keeps_partial_provenance_and_exact_input(self):
        try:
            from PIL import Image
        except ImportError:
            self.skipTest("Pillow unavailable; post-input fixture requires real preparation")
        with tempfile.TemporaryDirectory() as folder:
            base=Path(folder);image=base/"input.png"
            Image.new("RGB",(2,2),(80,120,160)).save(image)
            request=base/"request.json";request.write_text(json.dumps(self.request(image)))
            manifest=base/"manifest.json";manifest.write_text(json.dumps({"schema_version":1,"upstream_commit":worker.UPSTREAM_COMMIT}))
            output=base/"attempt"
            def fail_after_input(manifest,image,provenance):
                worker.checkpoint_context(provenance,"runtime-import")
                worker.validate_runtime_versions(dict(worker.RUNTIME_VERSIONS,torch="9.9.9"),provenance)
            with mock.patch.object(sys,"argv",["worker.py","--request",str(request),"--manifest",str(manifest),"--output",str(output)]), \
                 mock.patch.object(worker,"validate_manifest",return_value=base), \
                 mock.patch.object(worker,"run_inference",side_effect=fail_after_input):
                self.assertEqual(worker.main(),2)
            terminal=json.loads((output/"response.json").read_text())
            context=json.loads((output/"provenance.json").read_text())
            self.assertEqual(terminal["status"],"failed")
            self.assertEqual(set(terminal["files"]),{"artist-input.png","provenance.json"})
            self.assertEqual(context["failure"]["phase"],"runtime-import")
            self.assertEqual(context["request_validation"],"verified")
            self.assertEqual(context["model_manifest_observation"],"observed")
            self.assertEqual(context["environment"]["runtime_import_versions"]["versions"]["torch"],"9.9.9")
            self.assertEqual(context["outputs"]["artist-input.png"],hashlib.sha256((output/"artist-input.png").read_bytes()).hexdigest())
            self.assertFalse((output/"raw-curves.json").exists())
            self.assertFalse((output/"provenance.json.pending").exists())

    def test_preprocess_paired_encoded_srgb_and_alpha(self):
        try:
            from PIL import Image
        except ImportError:
            self.skipTest("Pillow unavailable; stdlib protocol tests remain runnable")
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder); path = base/"input.png"
            im = Image.new("RGBA", (2, 2), (0, 0, 0, 0)); im.putpixel((1, 1), (64, 128, 192, 255)); im.save(path)
            request = self.request(path)
            request["preprocessing"] = "gamma08"
            prepared = worker.prepare_input(request, base/"out.png")
            self.assertEqual(prepared.getpixel((0, 0)), (255, 255, 255))
            self.assertEqual(prepared.getpixel((1, 1)), tuple(round(255*(c/255)**.8) for c in (64, 128, 192)))


if __name__ == "__main__":
    unittest.main()
