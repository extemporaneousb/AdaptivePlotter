"""Batch admission tests; no model, worker or native image preparation is invoked."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import face_pilot


class FrozenFacePilotTests(unittest.TestCase):
    def setup_pilot(self, root):
        selection = root / "source-selection.json"
        selection.write_bytes(b'{"fixture":"selection"}\n')
        parameters = root / "preparation-parameters.json"
        parameters.write_bytes(b'{"fixture":"parameters"}\n')
        worker = root / "worker.py"
        worker.write_bytes(b'# Never executed\n')
        model = root / "model.json"
        model.write_bytes(b'{  "fixture": "unloaded asset" }\n')
        photos = []
        for index in range(10):
            name = "request-%02d.json" % index
            (root / name).write_bytes(json.dumps({"fixture": index}).encode())
            photos.append({"capture_id": "capture-%d" % index,
                "preparation_status": "unsupported", "preparation_error": "Synthetic missing face refusal",
                "attempt": {"request_id": "request-%d" % index, "request_relative_path": name,
                            "request_sha256": face_pilot.sha(root / name), "output_relative_path": "output-%d" % index}})
        manifest = {"schema_version": 1, "pilot_revision": face_pilot.REVISION, "photos": photos,
                    "maximum_model_jobs_including_failures": 10, "seed": 42,
                    "source_selection_sha256": face_pilot.sha(selection),
                    "preparation_parameters_sha256": face_pilot.sha(parameters)}
        (root / "pilot-manifest.json").write_text(json.dumps(manifest))
        return model, worker, face_pilot.sha(root / "pilot-manifest.json")

    def test_unsupported_jobs_count_and_exact_manifest_then_refuse_repetition(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            model, worker, accepted = self.setup_pilot(root)
            with patch("face_pilot.subprocess.run") as launch:
                face_pilot.run(root, model, worker, "/unused/python", accepted)
                launch.assert_not_called()
                receipt = json.loads((root / "pilot-run.json").read_text())
                self.assertEqual(len(receipt["attempts"]), 10)
                self.assertTrue(all(a["status"] == "unsupported_preparation" for a in receipt["attempts"]))
                self.assertTrue(all(a["supervisor_admitted_at_unix"] is None for a in receipt["attempts"]))
                self.assertEqual((root / "model-manifest-exact.json").read_bytes(), model.read_bytes())
                retained = (root / "pilot-run.json").read_bytes()
                with self.assertRaisesRegex(ValueError, "already attempted"):
                    face_pilot.run(root, model, worker, "/unused/python", accepted)
                self.assertEqual((root / "pilot-run.json").read_bytes(), retained)
                launch.assert_not_called()

    def test_supervisor_admission_clock_is_durable_before_fake_launch(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            model, worker, _ = self.setup_pilot(root)
            manifest_path = root / "pilot-manifest.json"
            manifest = json.loads(manifest_path.read_text())
            photo = manifest["photos"][0]
            photo["preparation_status"] = "succeeded"
            photo["folder"] = "prepared"
            (root / "prepared").mkdir()
            for name, key in [("fixed-input.png", "input_sha256"), ("preparation.json", "preparation_sha256"),
                              ("foreground-mask.png", "foreground_mask_sha256"), ("framed-source.png", "framed_source_sha256")]:
                (root / "prepared" / name).write_bytes(b"test-only input; never decoded")
                photo[key] = face_pilot.sha(root / "prepared" / name)
            manifest_path.write_text(json.dumps(manifest))
            def fake_launch(argv):
                receipt = json.loads((root / "pilot-run.json").read_text())
                first = receipt["attempts"][0]
                self.assertEqual(first["status"], "started")
                self.assertIsInstance(first["supervisor_admitted_at_unix"], float)
                self.assertTrue(first["supervisor_admitted_at_utc"].endswith("+00:00"))
                self.assertIsNone(first["worker_started_at_unix"])
                self.assertEqual(first["argv"], argv)
                class Completed:
                    returncode = 0
                return Completed()
            with patch("face_pilot.subprocess.run", side_effect=fake_launch) as launch:
                face_pilot.run(root, model, worker, "/unused/python", face_pilot.sha(manifest_path))
                launch.assert_called_once()
            final = json.loads((root / "pilot-run.json").read_text())
            self.assertEqual(final["attempts"][0]["status"], "completed")
            self.assertTrue(all(a["supervisor_admitted_at_unix"] is None for a in final["attempts"][1:]))

    def test_changed_independently_accepted_freeze_admits_no_process_or_intent(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            model, worker, accepted = self.setup_pilot(root)
            with (root / "pilot-manifest.json").open("ab") as stream:
                stream.write(b" ")
            with patch("face_pilot.subprocess.run") as launch:
                with self.assertRaisesRegex(ValueError, "independently accepted freeze"):
                    face_pilot.run(root, model, worker, "/unused/python", accepted)
                self.assertFalse((root / "pilot-run.json").exists())
                launch.assert_not_called()

    def test_request_tamper_blocks_before_process_and_retains_batch_intent(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            model, worker, accepted = self.setup_pilot(root)
            (root / "request-00.json").write_bytes(b'{"changed":true}')
            with patch("face_pilot.subprocess.run") as launch:
                with self.assertRaisesRegex(ValueError, "frozen request changed"):
                    face_pilot.run(root, model, worker, "/unused/python", accepted)
                self.assertTrue((root / "pilot-run.json").exists())
                launch.assert_not_called()

    def test_first_pilot_changed_inventory_is_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            original = root / "old-pilot"
            original.mkdir()
            (original / "ratings.json").write_bytes(b'{"real_labels":[]}')
            face_pilot.write_new(root / "first-pilot-preservation-before.json", face_pilot.inventory([original]))
            (original / "ratings.json").write_bytes(b'{"real_labels":["modified"]}')
            with self.assertRaisesRegex(ValueError, "inventory changed"):
                face_pilot.preserve(root)
            self.assertFalse((root / "first-pilot-preservation-after.json").exists())


if __name__ == "__main__":
    unittest.main()
