#!/usr/bin/env python3
"""Focused fixtures for EA-01 live inventory and EA-10G deletion authority."""

from __future__ import annotations

import unittest

from check_episode_inventory import PLAN, PORT_STRUCTS, scan_rows, validate_manifest


class EpisodeInventoryTests(unittest.TestCase):
    def test_live_port_inventory_excludes_retired_announcement_actions(self) -> None:
        self.assertNotIn("AnnouncementActions", PORT_STRUCTS)
        rows, _scans = validate_manifest()
        ports = {row["id"]: row["seams"] for row in rows if row["category"] == "direct-port"}
        self.assertEqual({"PlotterSpeechEffectRuntime.shutdown"}, ports["PRT-003"])

    def test_ea10g_keeps_announcement_actions_as_a_deleted_symbol_scan(self) -> None:
        scans = scan_rows(PLAN.read_text(encoding="utf-8"))
        self.assertIn(
            {
                "package": "EA-10G",
                "class": "deleted-symbol",
                "paths": "Sources/PlotterApp/*.swift",
                "literal": "AnnouncementActions",
            },
            scans,
        )

    def test_ea10c_current_typed_action_and_task_replace_retired_workspace_paths(self) -> None:
        rows, scans = validate_manifest()
        seams = {row["id"]: row["seams"] for row in rows}
        self.assertEqual({"ExerciseActionKind.cameraCalibration"}, seams["INT-012"])
        self.assertEqual({"PlotterCameraCalibrationRuntime.activeTask"}, seams["TSK-005"])
        self.assertEqual(
            {
                "UI.executeCameraCalibrationEffect",
                "UI.isShutdown",
            },
            seams["UI-011"],
        )

        action_source = (
            PLAN.parent.parent / "Sources/PlotterApp/LearningPathPresentation.swift"
        ).read_text(encoding="utf-8")
        for retired_case in (
            "case runCameraCalibrationAndBuildProposal",
            "case acceptCameraCalibrationProposal",
            "case rejectCameraCalibrationProposal",
        ):
            self.assertNotIn(retired_case, action_source)

        composition_source = (
            PLAN.parent.parent / "Sources/PlotterApp/PlotterCameraCalibrationComposition.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("return await workspace.executeCameraCalibrationEffect(request)", composition_source)

        self.assertIn(
            {
                "package": "EA-10C",
                "class": "duplicate-ingress",
                "paths": "Sources/PlotterApp/*.swift",
                "literal": "runCameraCalibrationAndBuildProposal",
            },
            scans,
        )
        self.assertIn(
            {
                "package": "EA-10C",
                "class": "task-owner",
                "paths": "Sources/PlotterApp/*.swift",
                "literal": "currentCameraCalibrationTask",
            },
            scans,
        )

    def test_ea10d_typed_actions_and_runtime_replace_sparse_coordinator(self) -> None:
        rows, scans = validate_manifest()
        seams = {row["id"]: row["seams"] for row in rows}
        self.assertEqual(
            {
                "ExerciseActionKind.tipCalibration",
                "ExerciseActionKind.pointSelectionCorrection",
            },
            seams["INT-013"],
        )
        self.assertEqual({"PlotterTipCalibrationRuntime"}, seams["OWN-012"])
        self.assertEqual(
            {
                "TipCalibrationAuthority",
                "TipCameraRegistration",
                "AcceptedTipCalibrationCheckpoint",
            },
            seams["OWN-014"],
        )
        self.assertEqual({"PlotterTipCalibrationRuntime.activeTask"}, seams["TSK-015"])
        self.assertEqual(
            {"PlotterTipCalibrationEpisodeTests", "TipPortFixture"}, seams["FIX-006"]
        )

        action_source = (
            PLAN.parent.parent / "Sources/PlotterApp/LearningPathPresentation.swift"
        ).read_text(encoding="utf-8")
        for retired_case in (
            "case drawFourCornerTipCircles",
            "case undoLastSparseTipClick",
            "case clearSparseTipClicks",
            "case revalidateTipCalibrationCheckpoint",
            "case acceptTipCalibrationProposal",
            "case rejectTipCalibrationProposal",
            "case retryTipCalibrationCommit",
        ):
            self.assertNotIn(retired_case, action_source)

        expected_scans = {
            ("deleted-symbol", "Sources/PlotterApp/*.swift", "SparseTipCalibrationCoordinator"),
            ("duplicate-ingress", "Sources/PlotterApp/*.swift", "drawFourCornerTipCircles"),
            ("duplicate-ingress", "Sources/PlotterApp/*.swift", "undoLastSparseTipClick"),
            ("fixture", "Tests/PlotterAppTests/*.swift", "completeSimulatedSparseTipCalibration"),
        }
        actual_scans = {
            (scan["class"], scan["paths"], scan["literal"])
            for scan in scans
            if scan["package"] == "EA-10D"
        }
        self.assertEqual(expected_scans, actual_scans)

    def test_ea10e_border_runtime_replaces_every_old_label(self) -> None:
        rows, scans = validate_manifest()
        seams = {row["id"]: row["seams"] for row in rows}
        self.assertEqual(
            {
                "ExerciseActionKind.borderValidation",
                "PlotterBorderValidationIntent.begin",
                "PlotterBorderValidationIntent.acceptObservedPrediction",
                "PlotterBorderValidationIntent.reject",
                "PlotterBorderValidationIntent.retryFrom",
                "LearningPathStage.borderValidations",
                "LearningPathItemID.borderValidation",
                "BorderValidationStep",
                "PlotterBorderValidationPhase",
            },
            seams["INT-014"],
        )
        self.assertEqual(
            {"OperatorWorkspace.borderValidationActionUnavailableReason"}, seams["GRD-009"]
        )
        self.assertEqual(
            {"PlotterBorderValidationRuntime.activeTask"}, seams["TSK-016"]
        )
        self.assertEqual(
            {"PlotterBorderValidationEpisodeTests", "BorderValidationPortFixture"},
            seams["FIX-007"],
        )

        root = PLAN.parent.parent
        presentation_source = (root / "Sources/PlotterApp/LearningPathPresentation.swift").read_text(
            encoding="utf-8"
        )
        runtime_source = (root / "Sources/PlotterEpisodeRuntime/PlotterBorderValidationRuntime.swift").read_text(
            encoding="utf-8"
        )
        workspace_source = (root / "Sources/PlotterApp/OperatorWorkspace.swift").read_text(
            encoding="utf-8"
        )
        for token in (
            "case borderValidation(PlotterBorderValidationIntent)",
            "case borderValidations",
            "case borderValidation(BorderValidationStep)",
        ):
            self.assertIn(token, presentation_source)
        for token in (
            "case begin",
            "case acceptObservedPrediction",
            "case reject(String)",
            "case retryFrom(BorderValidationStep)",
        ):
            self.assertIn(token, runtime_source)
        for token in (
            "case .borderValidation(let intent):",
            "case .runStep(_, let step):",
            "case .acceptComparison(_, let assessment):",
            "case .rejectComparison(_, let reason):",
        ):
            self.assertIn(token, workspace_source)

        retired_literals = {
            "DrawingTrialState",
            "ObservedDrawingTrialStep",
            "runObservedDrawingTrial",
            "activeExplorationOperation",
            "completeSimulatedStageFour",
            "completeSimulatedBorderValidation",
            ".drawingTrial",
            ".observedDrawingTrial",
            "drawingTrial",
            "observedDrawingTrial",
        }
        source_and_test_text = "\n".join(
            path.read_text(encoding="utf-8", errors="replace")
            for directory in (root / "Sources", root / "Tests")
            for path in directory.rglob("*.swift")
        )
        for literal in retired_literals:
            self.assertNotIn(literal, source_and_test_text)

        expected_scans = {
            ("deleted-symbol", "Sources/PlotterApp/*.swift", "DrawingTrialState"),
            ("deleted-symbol", "Sources/PlotterApp/*.swift", "ObservedDrawingTrialStep"),
            ("duplicate-ingress", "Sources/PlotterApp/*.swift", "runObservedDrawingTrial"),
            ("task-owner", "Sources/PlotterApp/*.swift", "activeExplorationOperation"),
            ("fixture", "Tests/PlotterAppTests/*.swift", "completeSimulatedStageFour"),
            ("fixture", "Tests/PlotterAppTests/*.swift", "completeSimulatedBorderValidation"),
            ("deleted-symbol", "Sources/**/*.swift,Tests/**/*.swift", ".drawingTrial"),
            ("deleted-symbol", "Sources/**/*.swift,Tests/**/*.swift", ".observedDrawingTrial"),
            ("deleted-symbol", "Sources/**/*.swift,Tests/**/*.swift", "drawingTrial"),
            ("deleted-symbol", "Sources/**/*.swift,Tests/**/*.swift", "observedDrawingTrial"),
        }
        actual_scans = {
            (scan["class"], scan["paths"], scan["literal"])
            for scan in scans
            if scan["package"] == "EA-10E"
        }
        self.assertEqual(expected_scans, actual_scans)

    def test_ea10f_runtime_composition_replaces_workspace_lifecycle_and_legacy_stores(self) -> None:
        rows, scans = validate_manifest()
        seams = {row["id"]: row["seams"] for row in rows}
        self.assertEqual(
            {
                "ExerciseActionKind.applySavedLearning",
                "ExerciseActionKind.startNewLearning",
                "ExerciseActionKind.restart",
                "ExerciseActionKind.redoThisStep",
                "ExerciseActionKind.recordAnotherAttempt",
                "ExerciseActionKind.paperReplaced",
                "PlotterArtifactResetIntent.compareSavedLearning",
                "PlotterArtifactResetIntent.applySavedLearning",
                "PlotterArtifactResetIntent.retainSavedLearning",
                "PlotterArtifactResetIntent.rejectSavedLearning",
                "PlotterArtifactResetIntent.redoStep",
                "PlotterArtifactResetIntent.recordAnotherAttempt",
                "PlotterArtifactResetIntent.paperReplaced",
                "PlotterArtifactResetIntent.reset",
            },
            seams["INT-015"],
        )
        self.assertEqual(
            {"OperatorWorkspace.artifactResetUnavailableReason"}, seams["GRD-010"]
        )
        self.assertEqual({"AcceptedLearningPathCheckpoint"}, seams["OWN-022"])
        self.assertEqual({"PlotterArtifactResetRuntime"}, seams["OWN-023"])
        self.assertEqual(
            {
                "AcceptedLearningPathCheckpointActions.load",
                "AcceptedLearningPathCheckpointActions.save",
                "AcceptedLearningPathCheckpointActions.clear",
                "PlotterArtifactResetEffectPort.execute",
                "PlotterArtifactResetPersistencePort.persist",
                "OperatorWorkspaceArtifactResetRelay",
            },
            seams["PRT-005"],
        )
        self.assertEqual({"PlotterArtifactResetRuntime.activeTask"}, seams["TSK-006"])
        self.assertEqual(
            {"AcceptedArtifactCheckpointComposition", "AcceptedLearningPathCheckpointStore"},
            seams["PER-003"],
        )
        self.assertEqual(
            {"AcceptedLearningPathLegacyMigrationAdapter"}, seams["PER-004"]
        )
        self.assertEqual(
            {"UI.executeArtifactResetEffect", "UI.persistArtifactReset"}, seams["UI-012"]
        )
        self.assertEqual(
            {
                "PlotterArtifactResetEpisodeTests",
                "ArtifactResetPortFixture",
                "AcceptedLearningPathLegacyMigrationTests",
                "OperatorWorkspaceTests",
            },
            seams["FIX-015"],
        )

        root = PLAN.parent.parent
        app_source = (root / "Sources/PlotterApp/AdaptivePlotterApp.swift").read_text(
            encoding="utf-8"
        )
        workspace_source = (root / "Sources/PlotterApp/OperatorWorkspace.swift").read_text(
            encoding="utf-8"
        )
        composition_source = (root / "Sources/PlotterApp/PlotterArtifactResetComposition.swift").read_text(
            encoding="utf-8"
        )
        migration_source = (root / "Sources/PlotterApp/AcceptedLearningPathLegacyMigration.swift").read_text(
            encoding="utf-8"
        )
        for token in (
            "PlotterArtifactResetComposition.make()",
            "artifactResetComposition.install(on: workspace)",
        ):
            self.assertIn(token, app_source)
        for token in (
            "PlotterArtifactResetEffectPort",
            "PlotterArtifactResetPersistencePort",
            "artifactResetRuntime.shutdown()",
            "artifactResetUnavailableReason",
        ):
            self.assertIn(token, workspace_source)
        self.assertIn("PlotterArtifactResetRuntime(effectPort: relay, persistencePort: relay)", composition_source)
        for token in (
            "case .loaded(let checkpoint):",
            "case .rejected(let reason):",
            "try canonicalPersistence.save(checkpoint)",
            "if let failure = stageAndClear(artifacts)",
            "return .failed(.legacyClear",
        ):
            self.assertIn(token, migration_source)

        source_and_test_text = "\n".join(
            path.read_text(encoding="utf-8", errors="replace")
            for directory in (root / "Sources", root / "Tests")
            for path in directory.rglob("*.swift")
        )
        for retired_literal in (
            "SavedLearningPackageState",
            "useSavedTraining",
            "performResetAllLearning",
            "savedTrainingComparisonTask",
            "LearningPathCheckpointBox",
            "AcceptedArtifactCheckpointStore",
            "AcceptedTipCalibrationCheckpointStore",
        ):
            self.assertNotIn(retired_literal, source_and_test_text)

        expected_scans = {
            ("deleted-symbol", "Sources/PlotterApp/*.swift", "SavedLearningPackageState"),
            ("duplicate-ingress", "Sources/PlotterApp/*.swift", "useSavedTraining"),
            ("duplicate-ingress", "Sources/PlotterApp/*.swift", "performResetAllLearning"),
            ("task-owner", "Sources/PlotterApp/*.swift", "savedTrainingComparisonTask"),
            ("fixture", "Tests/PlotterAppTests/*.swift", "LearningPathCheckpointBox"),
            ("deleted-symbol", "Sources/**/*.swift,Tests/**/*.swift", "AcceptedArtifactCheckpointStore"),
            ("deleted-symbol", "Sources/**/*.swift,Tests/**/*.swift", "AcceptedTipCalibrationCheckpointStore"),
        }
        actual_scans = {
            (scan["class"], scan["paths"], scan["literal"])
            for scan in scans
            if scan["package"] == "EA-10F"
        }
        self.assertEqual(expected_scans, actual_scans)


if __name__ == "__main__":
    unittest.main()
