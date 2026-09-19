#!/usr/bin/env python3
"""Exercise the exact inline shell validator without launching an application."""

from __future__ import annotations

import contextlib
import copy
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).with_name("check_running_app_preview_performance.sh")
VALIDATOR = compile(SCRIPT.read_text().split("<<'NATIVE_PY'\n", 1)[1].split("\nNATIVE_PY", 1)[0], str(SCRIPT), "exec")
PANELS = ["guidedLearning", "videoSettings", "motion", "activeLearning", "drawing"]
SLOTS = ["right", "left", "rightBottom", "leftBottom"]
CONTEXTS = [f"{slot}.{width}" for slot in SLOTS for width in (1000, 1600)]
BODY_IDS = ["learning.exerciseActions", "workbench.video.cameraRole", "motion.penDown",
            "learning.coverage.prepare", "drawing.draw"]


def rect(x=0, y=0, width=300, height=200):
    return [[x, y], [width, height]]


def control(identifier, panel, clips=1):
    return dict(identifier=identifier, panelIdentifier=f"workbench.panel.{panel}", frame=rect(20, 60, 150, 30),
                containingClipCount=clips, scrolledClipCount=0, fitsEveryContainingClip=True)


class NativeWorkbenchReportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.report = dict(schema="adaptiveplotter.native-workbench.v3", failures=[], placements=[],
                           portraitWorkspaces=[], bitmaps=[], inputs=[], nativeCounts={}, fittingDrawingBodies=[],
                           learningStates=[False, True], applicationWasActive=True, stopWasVisible=True,
                           acceptedArtifactsUnchanged=True, windowPreferencesUnchanged=True,
                           canvasOnlyWidths=[1000, 1600], viewMenuWasPresent=True)
        for panel, identifier in zip(PANELS, BODY_IDS):
            for slot in SLOTS:
                for width in (1000, 1600):
                    self.report["placements"].append(dict(panel=panel, slot=slot, width=width,
                        header=control(f"workbench.hide.{panel}", panel), body=control(identifier, panel)))
        for width in (1000, 1600):
            self.report["portraitWorkspaces"].append(dict(width=width,
                header=control("workbench.hide.portraitStudio", "portraitStudio", 0),
                capture=control("portrait.capture", "portraitStudio", 0)))
        for index in range(10):
            image = self.root / f"layout-{index}.png"
            image.write_bytes(b"fixture-artifact")
            self.report["bitmaps"].append(str(image))
        identifiers = ["learning.mode", "workbench.scroll.inner", "workbench.resize"]
        identifiers += [f"workbench.{action}.{panel}" for action in ("hide", "toggle") for panel in PANELS + ["portraitStudio"]]
        for identifier in identifiers:
            count = 2 if identifier == "learning.mode" or identifier.endswith(".portraitStudio") else 8
            self.report["nativeCounts"][identifier] = dict(posted=count, dispatched=count, handled=count, acknowledged=count)
            for index in range(count):
                identity = len(self.report["inputs"]) + 1
                sample = dict(targetIdentifier=identifier, postedEventIdentity=identity,
                              dispatchedEventIdentity=identity, handledEventIdentity=identity,
                              postedUptimeSeconds=10, eventUptimeSeconds=10, dispatchEntryUptimeSeconds=10.01,
                              handlerUptimeSeconds=10.02, handlerLatencyMilliseconds=20,
                              visibleAcknowledgmentLatencyMilliseconds=30)
                if identifier == "workbench.scroll.inner":
                    sample["scrollEvidence"] = dict(context=CONTEXTS[index], controlIdentifier="drawing.draw",
                        clipIdentity=f"inner-{index}", outerClipIdentities=[], beforeBounds=rect(y=400),
                        afterBounds=rect(y=280), documentBounds=rect(height=600))
                self.report["inputs"].append(sample)

    def tearDown(self):
        self.temporary.cleanup()

    def accepts(self, report):
        path = self.root / "report.json"
        path.write_text(json.dumps(report), encoding="utf-8")
        with patch("sys.argv", [str(SCRIPT), str(path)]), contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(SystemExit) as result:
                exec(VALIDATOR, {})
        return result.exception.code == 0

    def fitting_report(self, count=8):
        report = copy.deepcopy(self.report)
        wheels = [sample for sample in report["inputs"] if sample["targetIdentifier"] == "workbench.scroll.inner"]
        for sample in wheels[:count]:
            evidence = sample["scrollEvidence"]
            report["fittingDrawingBodies"].append(dict(context=evidence["context"],
                control=control("drawing.draw", "drawing"), clipIdentity=evidence["clipIdentity"],
                clipBounds=rect(height=700), documentFrameInClip=rect(height=572)))
            report["inputs"].remove(sample)
        report["nativeCounts"]["workbench.scroll.inner"] = {key: 8 - count for key in ("posted", "dispatched", "handled", "acknowledged")}
        return report

    def test_complete_wheel_fitting_and_mixed_reports(self):
        for report in (self.report, self.fitting_report(), self.fitting_report(4)):
            with self.subTest(fitting=len(report["fittingDrawingBodies"])):
                self.assertTrue(self.accepts(report))

    def test_rejects_incomplete_layout_and_event_evidence(self):
        mutations = [
            lambda r: r.update(schema="adaptiveplotter.native-workbench.v2"),
            lambda r: r["placements"].append(r["placements"][0]),
            lambda r: r["portraitWorkspaces"].pop(),
            lambda r: r["portraitWorkspaces"][0]["capture"].update(containingClipCount=1),
            lambda r: r["portraitWorkspaces"][0]["capture"].update(fitsEveryContainingClip=False),
            lambda r: r["bitmaps"].__setitem__(0, str(self.root / "missing.png")),
            lambda r: r["inputs"][0].update(handledEventIdentity=9999),
            lambda r: r["inputs"][0].update(handlerUptimeSeconds=9),
            lambda r: r["inputs"].pop(),
            lambda r: r["nativeCounts"]["workbench.hide.drawing"].update(handled=7),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(mutation=index):
                report = copy.deepcopy(self.report)
                mutate(report)
                self.assertFalse(self.accepts(report))

    def test_rejects_zero_wheel_movement(self):
        sample = next(s for s in self.report["inputs"] if "scrollEvidence" in s)
        sample["scrollEvidence"]["afterBounds"] = sample["scrollEvidence"]["beforeBounds"]
        self.assertFalse(self.accepts(self.report))

    def test_rejects_false_fitting_claims(self):
        mutations = [
            lambda r: r["fittingDrawingBodies"][0].update(documentFrameInClip=rect(height=750)),
            lambda r: r["fittingDrawingBodies"][0]["control"].update(panelIdentifier="workbench.panel.motion"),
            lambda r: r["fittingDrawingBodies"][0]["control"].update(fitsEveryContainingClip=False),
            lambda r: r["fittingDrawingBodies"][0]["control"].update(scrolledClipCount=1),
            lambda r: r["fittingDrawingBodies"][0].update(clipIdentity=""),
            lambda r: r["fittingDrawingBodies"].append(r["fittingDrawingBodies"][0]),
            lambda r: r["fittingDrawingBodies"].pop(),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(mutation=index):
                report = self.fitting_report()
                mutate(report)
                self.assertFalse(self.accepts(report))


if __name__ == "__main__":
    unittest.main()
