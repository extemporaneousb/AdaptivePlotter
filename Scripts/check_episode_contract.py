#!/usr/bin/env python3
"""Validate the canonical episode vocabulary and executable work ledger."""

from __future__ import annotations

import hashlib
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PLAN_PATH = ROOT / "docs" / "EPISODE_ARCHITECTURE_EXECUTION_PLAN.md"
VOCAB_PATH = ROOT / "docs" / "EPISODE_ARCHITECTURE_VOCABULARY.md"
PROTOCOL_PATH = ROOT / ".codex" / "skills" / "adaptiveplotter" / "references" / "episode-migration.md"
SKILL_PATH = ROOT / ".codex" / "skills" / "adaptiveplotter" / "SKILL.md"
WAVE_SKILL_PATH = ROOT / ".codex" / "skills" / "run-multi-agent-wave" / "SKILL.md"
WAVE_PROTOCOL_PATH = (
    ROOT
    / ".codex"
    / "skills"
    / "run-multi-agent-wave"
    / "references"
    / "wave-coordination.md"
)
EVIDENCE_PATH = ROOT / "docs" / "CURRENT_EVIDENCE.md"
ARCHITECTURE_PATH = ROOT / "docs" / "SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md"
PRODUCT_PATH = ROOT / "docs" / "PRODUCT_CONTRACT.md"
# Updated in the same package whenever a canonical ledger row changes.
EXPECTED_LEDGER_SHA256 = "caad889aba1cff6f17b68adca57ddad5ab4ba1a85c4038cb3f1c771a4031f96c"


EXPECTED_GATES = {
    "ARCHIVED": (
        "`git merge-base --is-ancestor d33d4ff HEAD` and the `TASK-C86132F1` Current Evidence entry identifies `d33d4ff`",
        "DOC-00",
    ),
    "DOC": ("`make docs-check`", "repository"),
    "DIFF": ("`git diff --check`", "repository"),
    "CRITIC": (
        "A fresh-context read-only critic inspects the actual candidate tree, runs `make docs-check` and `git diff --check`, gives PASS on all ten readiness dimensions in the execution prompt, and ends exactly `UNANIMOUS PASS — no material disagreement`; Current Evidence records that verdict while the full transient report is not checked in",
        "DOC-01",
    ),
    "QUICK": ("`make quick-test`", "repository"),
    "JOURNEY": ("`make journey-test`", "repository"),
    "STRICT": ("`make strict-check`", "repository"),
    "INVENTORY": (
        "`sh Scripts/check_episode_inventory.sh` proves every semantic intent, guard, owner, direct device/evidence port, environment branch, task/cancel owner, persistence path, UI consumer, and high-level fixture has one stable inventory ID, one current owner, one disposition, and one cutover package",
        "EA-01",
    ),
    "FIX-CONTAINMENT": ("`swift test --filter CoordinateAcceptancePolicyTests`", "FIX-00"),
    "FIX-APPLICABILITY": ("`swift test --filter TipApplicabilityEvidencePolicyTests`", "FIX-01"),
    "CORE": ("`swift test --filter EpisodeCoreTests`", "EA-02A"),
    "PLOTTER-MODEL": (
        "`swift test --filter PlotterEpisodeModelContractTests`",
        "EA-02B",
    ),
    "STORE": ("`swift test --filter EpisodeStoreTests`", "EA-03A"),
    "RUNTIME": ("`swift test --filter EpisodeRuntimeTests`", "EA-03B"),
    "RECORDING": ("`swift test --filter PlotterRecordingStoreTests`", "EA-05A"),
    "REPLAY": ("`swift test --filter PlotterRecordingReplayTests`", "EA-05B"),
    "INCIDENT": ("`swift test --filter PlotterIncidentPackageTests`", "EA-05C"),
    "POINT": ("`swift test --filter PlotterPointSelectionEpisodeTests`", "EA-04"),
    "MOTION": ("`swift test --filter PlotterManualMotionEpisodeTests`", "EA-06"),
    "SIM": ("`swift test --filter PlotterCausalEpisodeEnvironmentTests`", "EA-07"),
    "DRAW-DRAFT": ("`swift test --filter PlotterDrawingDraftEpisodeTests`", "EA-08A"),
    "DRAW-RUN": ("`swift test --filter PlotterDrawingRunEpisodeTests`", "EA-08B"),
    "UI": ("`swift test --filter PlotterEpisodeUIActionabilityTests`", "EA-09"),
    "PILOT": (
        "`sh Scripts/check_episode_pilot_gate.sh` proves the exact Pilot continuation gate predicates below against landed rows and Current Evidence",
        "EA-09",
    ),
    "PEN": ("`swift test --filter PlotterPenInteractionEpisodeTests`", "EA-10A"),
    "BOUNDARY": ("`swift test --filter PlotterBoundaryEpisodeTests`", "EA-10B"),
    "CAMERA-CAL": ("`swift test --filter PlotterCameraCalibrationEpisodeTests`", "EA-10C"),
    "TIP-CAL": ("`swift test --filter PlotterTipCalibrationEpisodeTests`", "EA-10D"),
    "BORDER-VALIDATION": ("`swift test --filter PlotterBorderValidationEpisodeTests`", "EA-10E"),
    "ARTIFACT-RESET": ("`swift test --filter PlotterArtifactResetEpisodeTests`", "EA-10F"),
    "SPEECH": ("`swift test --filter PlotterSpeechEffectEpisodeTests`", "EA-10G"),
    "SESSION": ("`swift test --filter PlotterControllerSessionEpisodeTests`", "EA-11A"),
    "OBSERVATION-CONFIG": (
        "`swift test --filter PlotterObservationConfigurationEpisodeTests`",
        "EA-11B",
    ),
    "COMPOSITION": ("`swift test --filter PlotterEpisodeCompositionTests`", "EA-11C"),
    "DELETE": (
        "`sh Scripts/check_episode_cutover.sh <PACKAGE-ID>` executes the exact zero-match deleted-symbol, forbidden-import, forbidden-conformance, direct-port, duplicate-ingress, task-owner, fixture, and environment-branch scans recorded by EA-01 for that package; any unassigned remaining consumer fails",
        "EA-01",
    ),
    "PHYSICAL-FINAL": (
        "On the exact signed landed EA-11C commit, one continuously attending operator executes Attended Hardware Runbook sections 1 through 6 and completes its Evidence record; the record must additionally capture one visible typed refusal/remedy, active owner/progress/Stop, runtime/UI revisions, one bounded incident export, controller transcript completeness, camera artifact presence or declared absence, and observed-ink/ambiguity outcomes",
        "VAL-01",
    ),
    "FINAL-GATE": (
        "`sh Scripts/check_episode_final_gate.sh` proves every ledger row through VAL-01 complete, all final-matrix software/replay/simulation/UI evidence linked from Current Evidence, one globally exclusive gateway and registry by structural scan, zero superseded paths, and a passed PHYSICAL-FINAL record for the exact EA-11C commit",
        "EA-11C",
    ),
}


# This inspectable map explains the dependency/class/gate grammar. The full
# ledger fingerprint separately pins status and every atomic-outcome sentence.
EXPECTED_PACKAGE_SHAPES = {
    "DOC-00": ([], "repository", ["ARCHIVED"]),
    "DOC-01": (["DOC-00"], "repository", ["DOC", "DIFF", "CRITIC"]),
    "EA-01": (["DOC-01"], "repository", ["DOC", "DIFF", "INVENTORY"]),
    "FIX-00": (["EA-01"], "software", ["DOC", "DIFF", "QUICK", "STRICT", "FIX-CONTAINMENT"]),
    "FIX-01": (["FIX-00"], "software", ["DOC", "DIFF", "QUICK", "STRICT", "FIX-APPLICABILITY"]),
    "DOC-02": (["FIX-01"], "repository", ["DOC", "DIFF"]),
    "EA-02A": (["DOC-02"], "software", ["DOC", "DIFF", "QUICK", "CORE"]),
    "EA-02B": (["EA-02A"], "software", ["DOC", "DIFF", "QUICK", "PLOTTER-MODEL"]),
    "EA-03A": (["EA-02B"], "software", ["DOC", "DIFF", "QUICK", "STRICT", "STORE"]),
    "EA-03B": (["EA-03A"], "software", ["DOC", "DIFF", "QUICK", "STRICT", "RUNTIME"]),
    "EA-05A": (["EA-03A"], "software", ["DOC", "DIFF", "QUICK", "STRICT", "RECORDING"]),
    "EA-05B": (["EA-03A", "EA-05A"], "software", ["DOC", "DIFF", "QUICK", "STRICT", "REPLAY"]),
    "EA-05C": (["EA-05B"], "software", ["DOC", "DIFF", "QUICK", "STRICT", "INCIDENT"]),
    "EA-04": (["EA-03B", "EA-05B"], "software", ["DOC", "DIFF", "QUICK", "STRICT", "POINT", "DELETE"]),
    "EA-06": (["EA-04", "EA-05C"], "software", ["DOC", "DIFF", "QUICK", "JOURNEY", "STRICT", "MOTION", "DELETE"]),
    "EA-07": (["EA-06"], "software", ["DOC", "DIFF", "QUICK", "JOURNEY", "STRICT", "SIM", "DELETE"]),
    "EA-08A": (["EA-05C", "EA-07"], "software", ["DOC", "DIFF", "QUICK", "STRICT", "DRAW-DRAFT", "DELETE"]),
    "EA-08B": (["EA-08A"], "software", ["DOC", "DIFF", "QUICK", "JOURNEY", "STRICT", "DRAW-RUN", "DELETE"]),
    "EA-09": (["EA-04", "EA-06", "EA-08B"], "software", ["DOC", "DIFF", "QUICK", "JOURNEY", "STRICT", "UI", "DELETE"]),
    "GATE-01": (["EA-09"], "gate", ["DOC", "DIFF", "PILOT"]),
    "EA-10A": (["GATE-01"], "software", ["DOC", "DIFF", "QUICK", "STRICT", "PEN", "DELETE"]),
    "EA-10B": (["EA-10A"], "software", ["DOC", "DIFF", "QUICK", "JOURNEY", "STRICT", "BOUNDARY", "DELETE"]),
    "EA-10C": (["EA-10B"], "software", ["DOC", "DIFF", "QUICK", "STRICT", "CAMERA-CAL", "DELETE"]),
    "EA-10D": (["EA-10C"], "software", ["DOC", "DIFF", "QUICK", "JOURNEY", "STRICT", "TIP-CAL", "DELETE"]),
    "EA-10E": (["EA-10D"], "software", ["DOC", "DIFF", "QUICK", "JOURNEY", "STRICT", "BORDER-VALIDATION", "DELETE"]),
    "EA-10F": (["EA-10E"], "software", ["DOC", "DIFF", "QUICK", "JOURNEY", "STRICT", "ARTIFACT-RESET", "DELETE"]),
    "EA-10G": (["EA-10F"], "software", ["DOC", "DIFF", "QUICK", "STRICT", "SPEECH", "DELETE"]),
    "EA-11A": (["EA-10G"], "software", ["DOC", "DIFF", "QUICK", "JOURNEY", "STRICT", "SESSION", "DELETE"]),
    "EA-11B": (["EA-10G"], "software", ["DOC", "DIFF", "QUICK", "JOURNEY", "STRICT", "OBSERVATION-CONFIG", "DELETE"]),
    "EA-11C": (["EA-11A", "EA-11B"], "software", ["DOC", "DIFF", "QUICK", "JOURNEY", "STRICT", "COMPOSITION", "DELETE"]),
    "VAL-01": (["EA-11C"], "attended-physical", ["DOC", "DIFF", "STRICT", "PHYSICAL-FINAL"]),
    "GATE-02": (["VAL-01"], "gate", ["DOC", "DIFF", "FINAL-GATE"]),
}


EXPECTED_SOFTWARE_OUTCOME_KIND = {
    "FIX-00": "Correction",
    "FIX-01": "Correction",
    "EA-02A": "Foundation",
    "EA-02B": "Foundation",
    "EA-03A": "Foundation",
    "EA-03B": "Foundation",
    "EA-04": "Cutover",
    "EA-05A": "Foundation",
    "EA-05B": "Foundation",
    "EA-05C": "Foundation",
    "EA-06": "Cutover",
    "EA-07": "Cutover",
    "EA-08A": "Cutover",
    "EA-08B": "Cutover",
    "EA-09": "Cutover",
    "EA-10A": "Cutover",
    "EA-10B": "Cutover",
    "EA-10C": "Cutover",
    "EA-10D": "Cutover",
    "EA-10E": "Cutover",
    "EA-10F": "Cutover",
    "EA-10G": "Cutover",
    "EA-11A": "Cutover",
    "EA-11B": "Cutover",
    "EA-11C": "Cutover",
}


EXPECTED_COMPLETE_PACKAGES = {
    "DOC-00",
    "DOC-01",
    "DOC-02",
    "EA-01",
    "FIX-00",
    "FIX-01",
    "EA-02A",
    "EA-02B",
    "EA-03A",
    "EA-03B",
    "EA-04",
    "EA-05A",
    "EA-05B",
    "EA-05C",
}


def fail(message: str) -> None:
    raise ValueError(message)


def cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def markdown_table(text: str, header: list[str]) -> list[list[str]]:
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if cells(line) != header:
            continue
        rows: list[list[str]] = []
        for candidate in lines[index + 2 :]:
            if not candidate.startswith("|"):
                break
            row = cells(candidate)
            if len(row) != len(header):
                fail(f"malformed table row after {' / '.join(header)}: {candidate}")
            rows.append(row)
        return rows
    fail(f"missing table: {' / '.join(header)}")


def validate_vocabulary(text: str) -> None:
    required = [
        "EpisodeGoal",
        "EpisodeDefinition",
        "EpisodeManifest",
        "EpisodeState",
        "PlotterIntent",
        "IntentDecision",
        "IntentAvailability",
        "IntentReceipt",
        "EpisodeEvent",
        "PlotterEffect",
        "EffectPermit",
        "EffectResult",
        "CapabilityFact",
        "StopCapability",
        "Observation",
        "Measurement",
        "Evidence",
        "EpisodeOutcome",
        "Assessment",
        "EpisodeJournal",
        "EpisodeTrace",
        "WorkPackage",
        "BlackdogTask",
        "PlotterIntentGateway",
        "PlotterOperationRegistry",
    ]
    definition_pattern = re.compile(r"^- `([^`]+)` [A-Za-z]", re.MULTILINE)
    definitions = definition_pattern.findall(text)
    for term in required:
        count = definitions.count(term)
        if count != 1:
            fail(f"{term} must have exactly one canonical definition bullet; found {count}")
    forbidden = {
        "ActionDecision",
        "ActionAvailability",
        "ActionReceipt",
        "SemanticActionAuthority",
        "SemanticActionGateway",
    }
    defined_forbidden = sorted(forbidden.intersection(definitions))
    if defined_forbidden:
        fail(f"forbidden synonym definitions remain: {', '.join(defined_forbidden)}")
    combined = re.sub(r"\s+", " ", text + "\n" + PLAN_PATH.read_text(encoding="utf-8"))
    for required_phrase in (
        "EpisodeDefinition<Intent>",
        "EpisodeManifest<DomainManifest>",
        "Foundation only; no Plotter, device, persistence, or UI imports",
        "Current `RunLedger` is retained as low-level device diagnostic history",
        "Current `ActiveStoppableOperation` remains the sole owner for unmigrated operations",
        "then its declaration and final consumers are deleted in `EA-11C`",
        "Current `LearningSessionState` is decomposed by the feature cutovers",
        "`EA-11C` deletes its declaration and any residue",
        "Current `SpeechAnnouncing`, `NativeSpeechAnnouncer`, and its identity-bound queue",
        "speech failure never becomes physical permission",
        "`EA-11C` makes the gateway the globally exclusive public mutation ingress",
    ):
        if required_phrase not in combined:
            fail(f"missing generic-core invariant: {required_phrase}")


def parse_gate_tokens(cell: str, package_id: str) -> list[str]:
    if not re.fullmatch(r"`[A-Z][A-Z0-9-]*`(?:, `[A-Z][A-Z0-9-]*`)*", cell):
        fail(f"{package_id} required gates are not an exact token list: {cell}")
    return re.findall(r"`([A-Z][A-Z0-9-]*)`", cell)


def validate_product_contract(text: str) -> None:
    normalized = re.sub(r"\s+", " ", text)
    for required_phrase in (
        "The sole active-work exception is EA-04 point selection",
        "Learning Off may itself typed-cancel only the exact point-selection/pen-cap continuation owner bound by both its selection ID and exercise-attempt token",
        "It awaits that same owner to settlement and re-evaluates the exact owner after suspension before committing Off",
        "A successor attempt token, another selection, or unrelated Learning, calibration, exploration, motion, or attempt work typed-refuses with the existing Cancel/Stop remedy",
        "This exception does not authorize Learning Off to cancel physical motion or any other owner and does not weaken operator or safety authority",
        "Every other active Learning attempt must finish or use its existing Cancel/Stop contract before Learning can be turned off",
    ):
        if required_phrase not in normalized:
            fail(f"Product Contract is missing the exact Learning-Off exception: {required_phrase}")


def validate_architecture(text: str) -> None:
    normalized = re.sub(r"\s+", " ", text)
    for required_phrase in (
        "PlotterEpisodeRuntime -> EpisodeCore + EpisodeRuntime + PlotterEpisodeModel + PlotterRuntime",
        "`PlotterEpisodeRuntime` depends inward only on `EpisodeCore`, `EpisodeRuntime`, `PlotterEpisodeModel`, and `PlotterRuntime`",
        "`PlotterIntentGateway` evaluates each typed point-selection or Learning-mode intent",
        "`PlotterLearningIntentRules.modeAvailability` is the one pure Learning-mode availability rule",
        "`submitLearningModeChange` has no local guard or early return",
        "every operator click reaches the runtime, which commits the typed acceptance or refusal event",
        "there is no silent no-op or second semantic owner",
        "`PlotterPointSelectionRuntime` is the single actor owner for the point-selection `EpisodeStore`",
        "Its FIFO mutation/publication boundary covers mutations and projection reads",
        "a concurrent mutation re-evaluates the state serialized by the one ahead of it",
        "`PointSelectionJournalPersistence` uses a macOS-14-compatible `OSAllocatedUnfairLock` compare-and-swap commit",
        "the episode model/runtime contain no `@unchecked Sendable` escape hatch",
        "Production point ingress uses `ExactFramePointSubmissionBuilder.submission`",
        "point geometry from the current viewport",
        "identity from the staged request's exact `request.presentationTransformRevision`",
        "owns no admission authority",
        "The current request admits and a replaced request receives a typed runtime refusal",
        "Submission refuses stale identity, source, camera configuration, frame hash/layout, presentation revision/bounds, or capacity",
        "An accepted selection becomes publicly visible only after the select event, point observation, and accepted operator-assertion evidence have all committed",
        "the FIFO projection boundary exposes no partial accepted state",
        "Runtime `PlotterPenCapPointSampler` owns exact-frame color sampling",
        "an accepted pen-cap result carries that exact `DisplayedFrame` to the app adapter",
        "Learning Off is one typed accepted intent only when the active work is the EA-04-owned exact selection/pen-cap continuation",
        "Unrelated calibration, exploration, motion, or exercise-attempt work receives the typed refusal from `PlotterLearningIntentRules.modeAvailability`",
        "`PlotterPointSelectionRuntime.setLearningEnabled` accepts a typed `PlotterLearningActivityFactProviding` and obtains a fresh fact inside the FIFO boundary for initial evaluation",
        "It reacquires a fresh fact after exact continuation cancellation before reevaluation",
        "`OperatorWorkspace` passes the provider through the Task hop rather than capturing a fact before it",
        "`PlotterPointSelectionActivityOwner(selectionID: PlotterPointSelectionID, exerciseAttemptID: UUID)` binds the exact selection and attempt identity across those initial and post-suspension evaluations",
        "The same item and selection with a successor attempt token typed-refuses",
        "`OperatorWorkspace` rechecks the exact attempt identity before post-runtime attempt cancellation",
        "For a latched continuation, the FIFO remains held while `setLearningEnabled` latches that owner, awaits `registry.stop`, and privately clears the runtime continuation handle without publishing episode-state mutation",
        "reevaluates the bound exact owner against the still-private `.continuing` plus `continuationIsActive` state",
        "An admitted Off event clears selection; a successor or unrelated refusal publishes continuation inactive and then its final typed refusal behind the same boundary",
        "preserving transaction-complete public state and nonrevival",
        "For that continuation path, `setLearningEnabled` returns only after registry settlement and final publication",
        "no replacement settlement helper, poll, sleep, or state exists",
        "Tests use the immutable returned/current projection and observable continuation-port state",
        "The model exception independently requires `.collecting` or `.continuing` with `continuationIsActive`",
        "`OperatorWorkspace` emits the owner only in those phases",
        "Retained `.accepted` Pen first-question/discovery and sparse batch/calibration attempts typed-refuse even with a matching supplied owner",
        "Recording failure remains a visible nonblocking diagnostic and never promotes evidence",
        "`PlotterPointSelectionIntentSink`",
        "`PlotterLearningModeIntentSink`",
        "`UI.learningModePresentation` consumer is inventory item UI-008, scheduled for the EA-09 presentation cutover",
        "The deleted `PointSelectionPresentationContext` cannot copy a request or re-decide admission",
        "`frozenPointSelectionFrame` holds pixels for UI presentation only",
        "`pendingToolContactEvidence` remains adapter data for the retained sparse-tip calibration fit",
        "The app cancellation helper is async and awaits the runtime owner",
        "Application Support `AdaptivePlotter/EpisodeRecordings/<recording UUID>`",
        "64-unique-frame, 512 MiB bound",
        "eleven focused PlotterPointSelectionEpisodeTests",
        "The deleted `submitCurrentPenCapPoint` and `OperatorWorkspace.awaitPenCapAcceptedClickTransition` helpers",
        "focused tests use generic submissions and bounded observable-state waits",
        "The deleted `awaitContinuationSettlement` task-owner/polling helper has no replacement helper, poll, sleep, or state",
        "`ActionSurface` sends only its inverse-transformed click submission through the click-only `PlotterPointSelectionIntentSink`",
        "Retained `OperatorWorkspace` action adapters invoke the same runtime/store authority for undo, clear, and cancel",
        "those actions do not originate in `ActionSurface` or the click-only sink protocol",
        "`SparseTipCalibrationCoordinator` retains the machine-position association, fit, calibration acceptance, and artifact graph",
        "Its sealed `PlotterEpisodeReplayExecutableDescriptor` is instantiated only by the private `PlotterEpisodeReplayExecutableAdapter`",
        "`PlotterEpisodeCanonicalDigestV1.revision` before any prefix reduction",
        "Effect-lifecycle-invalid prefixes fail closed and are not published",
        "Start attribution requires exactly one complete available operation-bound provenance tuple",
        "The service validates the complete source schedule before applying any transform",
        "completion delay retimes the completion and causal suffix",
        "Terminal replacement preserves its exact boundary and retimes that causal suffix and chunks with checked underflow",
        "After every candidate transformation, `controllerReplayScheduleViolation` validates the complete schedule across all outstanding invocations",
        "`invalidTransformedSchedule` refuses the complete scenario and returns the unchanged source schedule",
        "The same internal target now also owns one pure, unbound `PlotterIncidentPackageAssembler`",
        "Assembly validates cross-source episode/manifest/revision identity",
        "embeds the snapshot as `sourceReportedRecording`",
        "always emits `sourceSnapshotNotRevalidated` in `recordingSourceFacts`",
        "missing optional episode or environment provenance as diagnostic facts",
        "refuses an explicit foreign episode ID in any recording entry",
        "Assessment evidence is restricted to evidence accepted by its referenced outcome",
        "Accepted observation evidence requires an `inputEnvironment` equal to its referenced observation environment",
        "accepted measurement evidence requires that environment to equal every source observation environment",
        "preserves LIVE/SIMULATED evidence truth without moving evidence-acceptance authority",
        "Every `possibleInk` or `unclear` measurement requires one exact typed linked unresolved possible-ink ambiguity",
        "missing, duplicate, foreign, and spurious links are refused",
        "never certifies or revalidates recording format, controller, camera, lifecycle, frame descriptors, frame layout, frame hashes, frame paths, duplicate store records, `RunLedger`, or store completeness truth",
        "`maximumReferencedFrameByteCount` independently bounds checked referenced-frame bytes",
        "Frame bytes are never embedded",
        "checks only incident-package sensitive-ID linkage, checked referenced-byte accounting, and the independent limit",
        "remain source-reported rather than frame-store validation",
        "Canonical envelope verification returns `envelopeIntegrityConfirmed`",
        "proves only deterministic versioned byte integrity and canonical reassembly",
        "owns no artifact store, export destination, filesystem adapter, redaction workflow, UI, application ingress, device port, effect execution",
        "The focused incident suite contains 23 tests",
        "EA-09 still owns later UI request/progress/result presentation for this service",
    ):
        if required_phrase not in normalized:
            fail(f"current Swift architecture is missing: {required_phrase}")


def validate_plan(text: str) -> dict[str, dict[str, object]]:
    validate_architecture(ARCHITECTURE_PATH.read_text(encoding="utf-8"))
    normalized = re.sub(r"\s+", " ", text)
    ledger_lines: list[str] = []
    collecting_ledger = False
    for line in text.splitlines():
        if line.startswith("| ID | Status | Dependencies |"):
            collecting_ledger = True
        if collecting_ledger and line.startswith("|"):
            ledger_lines.append(line.rstrip())
        elif collecting_ledger:
            break
    ledger_material = ("\n".join(ledger_lines) + "\n").encode("utf-8")
    actual_ledger_sha256 = hashlib.sha256(ledger_material).hexdigest()
    if actual_ledger_sha256 != EXPECTED_LEDGER_SHA256:
      fail(
            "complete ledger content drifted; update the canonical plan and "
            "EXPECTED_LEDGER_SHA256 in the same reviewed package "
            f"(expected {EXPECTED_LEDGER_SHA256}, actual {actual_ledger_sha256})"
        )
    ledger_rows = markdown_table(
        text,
        ["ID", "Status", "Dependencies", "Class", "Atomic package outcome", "Required gates"],
    )
    if not ledger_rows:
        fail("work ledger is empty")

    rows: dict[str, dict[str, object]] = {}
    allowed_status = {"complete", "pending", "blocked"}
    allowed_classes = {"repository", "software", "attended-physical", "remote-git", "gate"}
    for package_id, status, dependency_cell, execution_class, outcome, gate_cell in ledger_rows:
        if package_id in rows:
            fail(f"duplicate ledger package ID: {package_id}")
        if not re.fullmatch(r"(?:DOC|FIX|BASE|EA|VAL|GATE)-[0-9]{2}[A-Z]?", package_id):
            fail(f"invalid ledger package ID: {package_id}")
        if status not in allowed_status:
            fail(f"{package_id} has invalid status {status}")
        if execution_class not in allowed_classes:
            fail(f"{package_id} has invalid execution class {execution_class}")
        if not outcome:
            fail(f"{package_id} has no atomic outcome")
        dependencies = [] if dependency_cell == "none" else [item.strip() for item in dependency_cell.split(",")]
        if len(dependencies) != len(set(dependencies)):
            fail(f"{package_id} repeats a dependency")
        rows[package_id] = {
            "status": status,
            "dependencies": dependencies,
            "class": execution_class,
            "gates": parse_gate_tokens(gate_cell, package_id),
            "outcome": outcome,
        }

    actual_ids = set(rows)
    expected_ids = set(EXPECTED_PACKAGE_SHAPES)
    if actual_ids != expected_ids:
        missing = sorted(expected_ids.difference(actual_ids))
        extra = sorted(actual_ids.difference(expected_ids))
        fail(f"ledger package mismatch; missing={missing}, extra={extra}")
    forbidden_broad_ids = {"BASE-00", "EA-10", "EA-11"}
    present_broad_ids = sorted(forbidden_broad_ids.intersection(rows))
    if present_broad_ids:
        fail(f"superseded broad package IDs remain: {', '.join(present_broad_ids)}")

    actual_complete_packages = {
        package_id for package_id, row in rows.items() if row["status"] == "complete"
    }
    if actual_complete_packages != EXPECTED_COMPLETE_PACKAGES:
        fail(
            "complete package statuses drifted; expected "
            f"{sorted(EXPECTED_COMPLETE_PACKAGES)}, found {sorted(actual_complete_packages)}"
        )

    for package_id, row in rows.items():
        for dependency in row["dependencies"]:
            if dependency not in rows:
                fail(f"{package_id} has undefined dependency {dependency}")
            if row["status"] == "complete" and rows[dependency]["status"] != "complete":
                fail(f"complete {package_id} depends on non-complete {dependency}")

    for package_id, (dependencies, execution_class, gates) in EXPECTED_PACKAGE_SHAPES.items():
        actual_shape = (
            rows[package_id]["dependencies"],
            rows[package_id]["class"],
            rows[package_id]["gates"],
        )
        expected_shape = (dependencies, execution_class, gates)
        if actual_shape != expected_shape:
            fail(f"{package_id} dependencies/class/gates drifted; expected {expected_shape}, found {actual_shape}")

    actual_software_ids = {package_id for package_id, row in rows.items() if row["class"] == "software"}
    if actual_software_ids != set(EXPECTED_SOFTWARE_OUTCOME_KIND):
        fail("software package classification does not cover the exact software ledger set")
    for package_id, kind in EXPECTED_SOFTWARE_OUTCOME_KIND.items():
        if not rows[package_id]["outcome"].startswith(f"{kind}:"):
            fail(f"{package_id} must declare a {kind} software outcome")
        if kind == "Foundation" and not rows[package_id]["outcome"].startswith("Foundation: add one "):
            fail(f"{package_id} Foundation must add exactly one isolated contract or service")
        if kind == "Cutover" and "DELETE" not in rows[package_id]["gates"]:
            fail(f"{package_id} is a Cutover without the required DELETE gate")

    outcome_requirements = {
        "EA-02A": (
            "one compile-only domain-generic `EpisodeCore` contract module",
            "add no Plotter, device, persistence, UI, effect port, or app caller",
        ),
        "EA-02B": (
            "one compile-only `PlotterEpisodeModel` contract module",
            "add no runtime, device port, persistence, UI, or app caller",
        ),
        "FIX-00": (
            "separate Euclidean controller-pose settlement from drawing-region containment",
            "delete the shared 0.5 mm policy assumption",
        ),
        "FIX-01": (
            "prevent projection outside `TipCameraRegistration.applicabilityRectangle` from becoming attributable evidence",
            "retaining typed diagnostic-only projection",
        ),
        "DOC-02": (
            "Operator acceptance of clean `main` commit `256b2a65f4059b6cf0e5c07f5f5305043254fb71`",
            "local annotated rollback checkpoint `adaptiveplotter-pre-episode-migration-20260825`",
            "retirement of BASE-01/BASE-02/BASE-03 as migration prerequisites without rewriting their failed evidence",
            "no remote ref or application source changed",
        ),
        "EA-03A": (
            "one unbound `EpisodeStore` service",
            "owns its one versioned journal-persistence adapter",
            "add no effect lane, operation owner, or app caller",
        ),
        "EA-03B": (
            "one unbound `PlotterOperationRegistry` runtime service",
            "canonical operation identity binds episode ID, request ID, typed intent identity, effect ID and revision, and typed environment",
            "original typed handle and lane",
            "operation-bound `CompletionCapability` for direct settlement",
            "typed result or typed refusal before any terminal mutation",
            "refused cancellation attempt recoverably active with durable observability",
            "`start` checks admission before recoverable acceptance",
            "a retained unstarted permit cannot authorize work after shutdown closure",
            "typed-refused and retired without start/progress mutation",
            "later correct shutdown settlement can terminalize without fabricated execution",
            "retain the full terminal record",
            "add no journal store, device adapter, or app caller",
        ),
        "EA-04": (
            "transfer exact-frame human point-selection authority",
            "one FIFO mutation/publication boundary",
            "serialized re-evaluation, transaction-complete selection/observation/evidence publication",
            "exact-owner Learning-Off cancellation, typed refusal for unrelated work",
            "EA-05A camera recording, and an invokable remedy-bearing Learning button",
            "delete old selection state, presentation-context/admission copies, Task-returning cancellation, continuations, closures, guards, and fixtures",
            "Delivered by `TASK-A5FF364B`",
        ),
        "EA-05A": (
            "one unbound lossless `EpisodeRecordingStore` service",
            "add no current-device hook, effect port, or app caller",
        ),
        "EA-05B": (
            "one unbound deterministic transcript replay service",
            "sealed `PlotterEpisodeReplayExecutableDescriptor` and private concrete adapter",
            "own the executable domain, evaluator, reducer, state/event/journal-schema, and build revision facts, a canonical-digest literal pinned to `PlotterEpisodeCanonicalDigestV1.revision`, and deterministic-seed applicability",
            "compare the corresponding manifest executable pins",
            "compare the corresponding manifest executable pins and the descriptor digest pin before reduction",
            "compare definition pins with the supplied typed definition",
            "retain full recorded effect revisions as identity-only facts with no effect-executor revision-validation claim",
            "checking progress/result identity and first-terminal ordering",
            "reconstruct and independently verify every recorded journal prefix",
            "failing closed without publishing lifecycle-invalid prefixes",
            "retain emitted effects only as inert values",
            "classify started-unsettled work as possible physical effect with a never-resume disposition",
            "attribute start evidence only through exactly one complete available operation-bound provenance tuple",
            "apply exact replay plus only causality-preserving controller fragmentation, delay, timeout, and cancellation perturbations",
            "prevalidating the source schedule",
            "refusing nil/empty source",
            "absent read traffic",
            "non-read delay",
            "deadline violations for successful or failed reads",
            "delay with timeout/cancellation for one invocation independent of declaration order",
            "terminal-boundary or downstream-order violations",
            "retime the causal suffix and embedded read chunks with checked overflow or underflow",
            "validate the complete transformed schedule across all outstanding invocations",
            "transforming A cannot push overlapping B past B's deadline",
            "move B traffic before B's invocation",
            "typed-refusing any invalid transformed schedule with unchanged source at the typed transcript layer",
            "add no `MachineLink` conformance, effect executor, permit restoration, device port, app caller, or current-authority transfer",
            "Delivered by `TASK-32F536F4`",
        ),
        "EA-05C": (
            "one unbound headless bounded incident-package assembler/exporter",
            "owns no artifact store, UI, device port, or app caller",
            "Delivered by `TASK-1DDBA6F2`",
        ),
        "EA-09": (
            "UI request/progress/result presentation for the EA-05C incident service",
            "Add no recorder, package assembler, artifact store, or export backend.",
        ),
        "EA-10G": (
            "advisory-speech effect authority",
            "Retain `NativeSpeechAnnouncer`/AVFoundation synthesis ownership",
            "delete `AnnouncementActions`",
            "shutdown cancellation",
        ),
        "EA-11A": (
            "controller-session readiness authority",
            "Retain `MachineController` and `RunInterpreter` transport/safety ownership",
            "direct `MachineActions` calls",
        ),
        "EA-11B": (
            "observation-environment configuration authority",
            "Retain `CameraCapture` device/frame ownership",
            "direct `CameraActions` calls",
        ),
        "EA-11C": (
            "transfer only final application composition",
            "making `PlotterIntentGateway` and `PlotterOperationRegistry` globally exclusive",
            "Delete the `OperatorWorkspace` effect closures",
            "`ActiveStoppableOperation`",
            "`LearningSessionState`",
            "may not absorb an unnamed feature migration",
            "any unassigned inventory item fails the package",
        ),
    }
    for package_id, phrases in outcome_requirements.items():
        for phrase in phrases:
            if phrase not in rows[package_id]["outcome"]:
                fail(f"{package_id} atomic outcome is missing: {phrase}")

    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(package_id: str) -> None:
        if package_id in visiting:
            fail(f"ledger dependency cycle reaches {package_id}")
        if package_id in visited:
            return
        visiting.add(package_id)
        for dependency in rows[package_id]["dependencies"]:
            visit(dependency)
        visiting.remove(package_id)
        visited.add(package_id)

    for package_id in rows:
        visit(package_id)

    gate_rows = markdown_table(text, ["Gate", "Exact command or evidence procedure", "Created or owned by"])
    gates: dict[str, tuple[str, str]] = {}
    for gate_cell, procedure, owner in gate_rows:
        match = re.fullmatch(r"`([A-Z][A-Z0-9-]*)`", gate_cell)
        if not match:
            fail(f"invalid gate catalog identity: {gate_cell}")
        gate = match.group(1)
        if gate in gates:
            fail(f"duplicate gate catalog identity: {gate}")
        if not procedure or not owner:
            fail(f"gate {gate} lacks an exact procedure or owner")
        if re.search(r"\b(?:TBD|undefined|all .* below|to be decided)\b", procedure, re.IGNORECASE):
            fail(f"gate {gate} contains a deferred procedure: {procedure}")
        gates[gate] = (procedure, owner)

    actual_gate_names = set(gates)
    expected_gate_names = set(EXPECTED_GATES)
    if actual_gate_names != expected_gate_names:
        missing = sorted(expected_gate_names.difference(actual_gate_names))
        extra = sorted(actual_gate_names.difference(expected_gate_names))
        fail(f"gate catalog mismatch; missing={missing}, extra={extra}")
    for gate, expected in EXPECTED_GATES.items():
        if gates[gate] != expected:
            fail(f"gate {gate} procedure/owner drifted; expected {expected}, found {gates[gate]}")

    for package_id, row in rows.items():
        for gate in row["gates"]:
            if gate not in gates:
                fail(f"{package_id} references undefined gate {gate}")

    for required_gate in ("PILOT", "PHYSICAL-FINAL", "FINAL-GATE", "DELETE"):
        if required_gate not in gates:
            fail(f"gate catalog is missing {required_gate}")

    for required_phrase in (
        "`failed` and `skipped` are truthful evidence outcomes but cannot satisfy a required gate",
        "package `<ID>` complete; migration remains incomplete",
        "The gate moves no authority and cannot repair implementation while assessing it.",
        "Every `software` outcome begins `Foundation:`, `Correction:`, or `Cutover:`",
        "`EA-01` may not add, remove, combine, split, or reorder packages.",
        "`EA-11C` makes the gateway the globally exclusive effect-bearing/domain-mutation ingress",
        "`GATE-02` only verifies that landed fact",
        "This table remains the immutable EA-01 characterization baseline after assigned WorkPackages land",
        "A `delete` row assigned to any completed package in the inventory's assignable WorkPackage set is historical deletion authority",
        "excludes only those completed assignable `delete` rows from live source-presence equality",
        "Rows assigned to pending WorkPackages, plus every `retain` or `adapt` row regardless of package status, remain live-presence obligations",
        "`UI.learningModePresentation`",
        "`learningModePresentation` is projection-only and adds no Learning decision or mutation authority",
        "Wave selection takes the first eligible row in this table's literal order",
        "`attended-physical` and `remote-git` still require their own explicit package and execution-class authorization",
    ):
        if required_phrase not in normalized:
            fail(f"completion or gate contract is missing: {required_phrase}")
    return rows


def validate_completed_gate_result(package_id: str, gate: str, result: str) -> None:
    if re.fullmatch(r"passed — \S(?:.*\S)?", result) is None:
        fail(
            f"{package_id} detailed gate {gate} must use final passed evidence "
            f"form `passed — ...`: {result}"
        )

    normalized = re.sub(r"\s+", " ", result).casefold().replace("re-run", "rerun")
    if re.search(r"\brerun\b", normalized) is not None:
        fail(
            f"{package_id} detailed gate {gate} defers validation to a rerun: "
            f"{result}"
        )
    if re.search(r"\bskipped\b", normalized) is not None:
        fail(
            f"{package_id} detailed gate {gate} reports skipped evidence as "
            f"passed: {result}"
        )

    failed_occurrences = list(re.finditer(r"\bfailed\b", normalized))
    zero_failed_starts = {
        match.start("failed")
        for match in re.finditer(
            r"(?<![\w.,/+\-])0 (?P<failed>failed)\b",
            normalized,
        )
    }
    invalid_failed = next(
        (match for match in failed_occurrences if match.start() not in zero_failed_starts),
        None,
    )
    if invalid_failed is not None:
        fail(
            f"{package_id} detailed gate {gate} reports failed evidence without "
            f"the explicit zero form `0 failed`: {result}"
        )

    incomplete_state = re.search(
        r"\b(?:incomplete|unfinished|unverified|unvalidated|blocked|unresolved|"
        r"not[\s-]+(?:run|executed|performed|verified|validated|complete|"
        r"completed|finished))\b",
        normalized,
    )
    if incomplete_state is not None:
        fail(
            f"{package_id} detailed gate {gate} reports incomplete evidence "
            f"state {incomplete_state.group(0)!r}: {result}"
        )

    uncertainty = re.search(
        r"\b(?:candidate|provisional|pending|await(?:ing|s)?|"
        r"defer(?:red|s)?|future|follow(?:s|ing)?|not\s+yet|not\s+happened)\b",
        normalized,
    )
    if uncertainty is not None:
        fail(
            f"{package_id} detailed gate {gate} contains uncertain or deferred "
            f"evidence word {uncertainty.group(0)!r}: {result}"
        )

    numeric_result = re.compile(
        r"\b(?P<label>exit(?:ed)?(?:\s+(?:code|status))?|status|"
        r"return\s+code|rc)\s*(?:=|:)?\s*"
        r"(?P<token>[+-]?(?:\d|\.\d)[^\s|]*)"
    )
    complete_integer = re.compile(
        r"(?P<value>[+-]?\d+)[,;:.!?)}\]`]*"
    )
    for numeric_match in numeric_result.finditer(normalized):
        label = numeric_match.group("label")
        token = numeric_match.group("token")
        integer_match = complete_integer.fullmatch(token)
        if integer_match is None:
            fail(
                f"{package_id} detailed gate {gate} has malformed numeric "
                f"{label} token {token!r}; expected a complete signed decimal "
                f"integer: {result}"
            )
        value = integer_match.group("value")
        if int(value) != 0:
            fail(
                f"{package_id} detailed gate {gate} reports nonzero "
                f"{label} {value} as passed: {result}"
            )

    if re.search(r"\bnon[- ]?zero\b", normalized) is not None:
        fail(
            f"{package_id} detailed gate {gate} explicitly reports a nonzero "
            f"result as passed: {result}"
        )


def validate_evidence(text: str, rows: dict[str, dict[str, object]]) -> None:
    evidence_rows = markdown_table(
        text,
        ["Package", "Blackdog task", "Gate results", "Evidence section"],
    )
    evidence_by_package: dict[str, list[str]] = {}
    for package_id, task, result_cell, section in evidence_rows:
        if package_id in evidence_by_package:
            fail(f"duplicate Work package gate evidence row: {package_id}")
        if package_id not in rows:
            fail(f"gate evidence references unknown package {package_id}")
        if rows[package_id]["status"] != "complete":
            fail(f"non-complete package {package_id} has a completion evidence row")
        if not re.fullmatch(r"`TASK-[A-F0-9]+`", task):
            fail(f"{package_id} has invalid Blackdog task evidence {task}")
        if not re.fullmatch(
            r"`[A-Z][A-Z0-9-]*=passed`(?:, `[A-Z][A-Z0-9-]*=passed`)*",
            result_cell,
        ):
            fail(f"{package_id} gate results are not exact passed tokens: {result_cell}")
        actual_gates = re.findall(r"`([A-Z][A-Z0-9-]*)=passed`", result_cell)
        expected_gates = rows[package_id]["gates"]
        if actual_gates != expected_gates:
            fail(f"{package_id} evidence gates must be {expected_gates}; found {actual_gates}")
        section_match = re.search(
            rf"^## {re.escape(section)}$(.*?)(?=^## |\Z)",
            text,
            re.MULTILINE | re.DOTALL,
        )
        if section_match is None:
            fail(f"{package_id} evidence section does not exist: {section}")
        validation_rows = markdown_table(
            section_match.group(1),
            ["Validation", "Result", "Scope"],
        )
        detailed_gates: dict[str, str] = {}
        for validation, result, _scope in validation_rows:
            gate_match = re.fullmatch(r"`([A-Z][A-Z0-9-]*)`", validation)
            if gate_match is None:
                continue
            gate = gate_match.group(1)
            if gate in detailed_gates:
                fail(f"{package_id} repeats detailed gate evidence for {gate}")
            validate_completed_gate_result(package_id, gate, result)
            detailed_gates[gate] = result
        if list(detailed_gates) != expected_gates:
            fail(
                f"{package_id} detailed evidence gates must be {expected_gates}; "
                f"found {list(detailed_gates)}"
            )
        if "CRITIC" in detailed_gates and "UNANIMOUS PASS — no material disagreement" not in detailed_gates["CRITIC"]:
            fail(f"{package_id} CRITIC detail lacks the exact unanimous verdict")
        if "ARCHIVED" in detailed_gates and "d33d4ff" not in detailed_gates["ARCHIVED"]:
            fail(f"{package_id} ARCHIVED detail lacks d33d4ff")
        evidence_by_package[package_id] = actual_gates

    complete_packages = {package_id for package_id, row in rows.items() if row["status"] == "complete"}
    evidenced_packages = set(evidence_by_package)
    if complete_packages != evidenced_packages:
        missing = sorted(complete_packages.difference(evidenced_packages))
        extra = sorted(evidenced_packages.difference(complete_packages))
        fail(f"complete-package evidence mismatch; missing={missing}, extra={extra}")

    for required_phrase in (
        "Episode deterministic replay foundation",
        "`PlotterEpisodeCanonicalDigestV1`",
        "`PlotterEpisodeReplayExecutableDescriptor`",
        "`PlotterEpisodeReplayExecutableAdapter`",
        "no replay entry point accepts either",
        "Caller metadata cannot spoof executable agreement",
        "`PlotterEpisodeRecordedEffectRevision` values are recorded identity only",
        "`recordedIdentityOnlyNoExecutorValidation`",
        "Replay has no effect executor",
        "reduces every journal prefix",
        "possible physical effect",
        "never-resume disposition",
        "typed transcript-layer service, not a `MachineLink`",
        "exact unperturbed transcript replay",
        "controller transcript completeness, byte/order integrity, and operation",
        "Missing, truncated, byte-count-mismatched, or hash-mismatched camera bytes remain typed incompleteness",
        "A `RunLedger` reference remains diagnostic-only",
        "manifest-to-executable revision binding",
        "full effect identity and first-terminal ordering",
        "causal controller timing and missing-source refusals",
        "exact operation-bound recording provenance",
        "executable facts were caller-asserted",
        "failed-read completion delay could exceed",
        "declaration order could change",
        "nil or empty controller input could be accepted",
        "rejects delay plus timeout/cancellation for one invocation",
        "enforces successful and failed timed-read deadlines",
        "preserves the exact terminal boundary and downstream ordering",
        "refuses nil or empty exact replay",
        "global transformed-schedule causal validation",
        "across all outstanding invocations",
        "`invalidTransformedSchedule` refusal",
        "The replacement fresh source critic also returned `RETASK`, not pass",
        "per-target transformation checks did not validate causal truth for the complete schedule",
        "Adversarial overlapping-read coverage",
        "`PlotterEpisodeCanonicalDigestV1.revision`",
        "Invalid effect-lifecycle prefixes fail closed",
        "one complete available operation-bound provenance tuple",
        "The source schedule is validated",
        "causal suffix, including embedded read chunks, with checked overflow",
        "causal suffix and chunks with checked underflow",
        "edited only the replay source and focused tests before",
        "invalidated all overlapping",
        "performed read-only attribution",
        "classified the delta `RETASK`",
        "reconciled it non-destructively",
        "foreign edits were not accepted wholesale",
        "passed 14/14 replay tests with no warnings",
        "The completed post-integration ordered gate set passed",
        "documentation and architecture contracts plus 29/29",
        "diff-check exit 0 with no output",
        "quick 621/621",
        "exactly 10 configured exclusions and no warnings",
        "strict 631/631 plus",
        "29/29 with zero exclusions or warnings",
        "launcher, negative-bundle, and documentation checks also passed",
        "631/631 Swift tests plus 29/29 documentation/checker tests",
        "five unidentified issues",
        "no retained output adequate to establish a result",
        "intermittent validation-observability history",
        "These are the completed ordered source, replay, build, test, and repository",
        "A fresh critic pass remains required before landing",
        "Canonical routed-document review dispositions:",
        "Reviewed no change — Product Contract and Episode Architecture Vocabulary",
        "Reviewed no change — Attended Hardware Runbook",
        "Reviewed no change — `AGENTS.md`, the AdaptivePlotter skill, episode-migration",
        "Reviewed no change at that landing — capsule fixture",
        "retained FIX-010 controller fixtures",
        "`package EA-05B complete; migration remains incomplete`",
    ):
        if required_phrase not in text:
            fail(f"EA-05B completion evidence is missing: {required_phrase}")

    for required_phrase in (
        "Episode incident package foundation",
        "`PlotterIncidentPackageAssembler`",
        "`PlotterIncidentPackageSource`",
        "`sourceReportedRecording`",
        "`sourceSnapshotNotRevalidated`",
        "source-reported open state, durability uncertainty, completeness",
        "missing optional episode or environment provenance as diagnostic",
        "explicit foreign episode ID in any recording entry",
        "Assessment evidence is restricted to evidence accepted by its referenced outcome",
        "Accepted observation evidence `inputEnvironment` must equal the referenced observation environment",
        "Accepted measurement evidence `inputEnvironment` must equal every source observation environment",
        "preserves LIVE/SIMULATED truth without moving evidence-acceptance authority",
        "Every `possibleInk` or `unclear`",
        "missing, duplicate, foreign, and spurious links are refused",
        "never certifies or revalidates recording format, controller, camera, lifecycle, frame descriptors, frame layout, frame hashes, frame paths, duplicate store records, `RunLedger`, or store completeness truth",
        "deterministic sorted-key `canonicalJSONV1`",
        "`envelopeIntegrityConfirmed`",
        "proves only deterministic versioned byte integrity and canonical reassembly",
        "`maximumReferencedFrameByteCount` independently bounds checked referenced-frame",
        "Count and byte arithmetic is checked",
        "Exact frame bytes are never embedded",
        "checks only incident-package sensitive-ID linkage, checked referenced-byte accounting",
        "remain source-reported and are not frame-store validation",
        "possible-ink incompleteness remains typed",
        "23/23 tests passed, exit 0",
        "The frozen-tree gate set passed as recorded below",
        "package is complete on this landing",
        "Static inspection found 29 capsule/checker test methods",
        "`QUICK` 644/644",
        "`STRICT` 654/654",
        "documentation and architecture contracts plus 29/29 documentation/checker tests passed with no warnings",
        "`git diff --check`; exit 0, no output",
        "644/644 tests passed with exactly 10 configured exclusions and no warnings",
        "654/654 Swift tests plus 29/29 documentation/checker tests passed with zero exclusions or warnings",
        "warning-as-errors build, signing, launcher, negative-bundle, and documentation checks passed",
        "After this landing, `EA-04` is the first eligible ordinary WorkPackage",
        "no product or application caller",
        "does not implement the later EA-09 UI request/progress/result presentation",
        "Canonical routed-document review dispositions:",
        "Reviewed no change — Product Contract and Episode Architecture Vocabulary",
        "Reviewed no change — Attended Hardware Runbook",
        "Reviewed no change — `AGENTS.md`, the AdaptivePlotter skill",
        "`package EA-05C complete; migration remains incomplete`",
    ):
        if required_phrase not in text:
            fail(f"EA-05C completion evidence is missing: {required_phrase}")

    for required_phrase in (
        "Episode point-selection cutover",
        "`TASK-A5FF364B`",
        "`PlotterIntentGateway` is the stateless typed decision boundary",
        "`PlotterPointSelectionRuntime` is the single actor owner",
        "`EpisodeStore<PlotterEpisodeReducer, PointSelectionJournalPersistence>`",
        "`PlotterOperationRegistry`",
        "One FIFO mutation/publication boundary surrounds",
        "one copied admission decision",
        "`PlotterLearningIntentRules.modeAvailability` is the one pure availability rule",
        "`submitLearningModeChange` has no local guard",
        "runtime commits either its typed acceptance or typed refusal with a visible remedy",
        "`plotter-point-selection-journal-v1`",
        "`PointSelectionJournalPersistence` retains the `plotter-point-selection-journal-v1` schema and uses a macOS-14-compatible `OSAllocatedUnfairLock` compare-and-swap commit",
        "The episode model and runtime contain no `@unchecked Sendable` escape hatch",
        "`AdaptivePlotter/EpisodeRecordings/<recording UUID>`",
        "64-unique-frame, 512 MiB retention policy",
        "Store startup failure and per-stage archival failure remain visible nonblocking diagnostics",
        "Recording is never safety, evidence, or exact-frame authority",
        "Submission fails closed before mutation",
        "The production ActionSurface click path uses `ExactFramePointSubmissionBuilder.submission`",
        "point geometry comes from the current viewport, while authority identity comes from the staged request's exact `request.presentationTransformRevision`; the builder owns no admission authority",
        "The current request admits and a replaced request typed-refuses at the runtime boundary",
        "One accepted selection becomes publicly visible only after the select event, point observation, and accepted `PlotterEvidence` with class `.operatorAssertion` have all committed",
        "no caller can observe a partially committed accepted selection",
        "Pen-cap sampling is owned by runtime `PlotterPenCapPointSampler`",
        "accepted result carries the exact `DisplayedFrame` used for sampling to the app adapter",
        "The button remains invokable when refusal is predicted, displays that remedy, and has no local guard or silent no-op",
        "`PlotterPointSelectionRuntime.setLearningEnabled` accepts a typed `PlotterLearningActivityFactProviding`, obtains a fresh fact inside the FIFO boundary for initial evaluation, and reacquires a fresh fact after exact continuation cancellation before reevaluation",
        "`OperatorWorkspace` passes that provider through the Task hop instead of capturing an activity fact before the hop",
        "`PlotterPointSelectionActivityOwner(selectionID: PlotterPointSelectionID, exerciseAttemptID: UUID)` binds the exact owner used by both the initial and post-suspension fresh-fact evaluations",
        "The same item and selection with a successor exercise-attempt token typed-refuses",
        "workspace rechecks that exact attempt identity before post-runtime attempt cancellation",
        "Learning Off is admitted only as the one typed accepted click that owns EA-04 exact selection/pen-cap continuation",
        "For a latched continuation, the FIFO boundary remains held while the runtime latches that exact owner, awaits `registry.stop`, and privately clears the runtime continuation handle without publishing episode-state mutation",
        "gateway reevaluates the bound exact owner against the still-private `.continuing` plus `continuationIsActive` state",
        "An admitted Off commit clears the selection",
        "A successor or unrelated refusal first publishes inactive continuation and then the final typed refusal behind the same FIFO boundary",
        "no caller sees partial state and later settlement cannot revive the continuation",
        "For that continuation path, `setLearningEnabled` returns only after registry settlement and final publication",
        "there is no replacement settlement helper, poll, sleep, or state variable",
        "Focused tests assert the immutable returned/current projection plus observable continuation-port state",
        "`PlotterLearningIntentRules.modeAvailability` independently admits the exact exception only for `.collecting` or for `.continuing` with `continuationIsActive`",
        "`OperatorWorkspace` emits a point-selection activity owner only for those same phases",
        "Retained `.accepted` Pen first-question/discovery and sparse batch/calibration attempts typed-refuse even when a caller supplies a matching owner",
        "Unrelated calibration, exploration, motion, or exercise-attempt work instead typed-refuses through the sole pure `PlotterLearningIntentRules.modeAvailability` rule",
        "`PlotterPointSelectionIntentSink`",
        "`ActionSurface` sends only inverse-transformed click submissions through the click-only `PlotterPointSelectionIntentSink`",
        "Retained `OperatorWorkspace` undo, clear, and cancel action adapters invoke the same runtime/store authority",
        "those actions do not originate in `ActionSurface` or the sink protocol",
        "`PlotterLearningModeIntentSink`",
        "`learningModePresentation` is projection-only",
        "`UI.learningModePresentation` consumer is retained under inventory item UI-008",
        "future EA-09 presentation cutover",
        "`PointSelectionPresentationContext`, its copied request/admission comparison, and the Task-returning app cancellation helper are deleted",
        "`submitCurrentPenCapPoint` and `OperatorWorkspace.awaitPenCapAcceptedClickTransition` are also deleted",
        "focused tests use generic point submissions and bounded observable-state waits",
        "`frozenPointSelectionFrame` bytes remain presentation-only",
        "`pendingToolContactEvidence` remains adapter data for the retained sparse-tip calibration fit",
        "app cancellation helper is now async and awaits the runtime owner directly",
        "`SparseTipCalibrationCoordinator` retains machine-position association",
        "`CameraCapture` still owns device discovery, capture, and exact stamped frames",
        "discovered and passed 11/11 tests, exit 0",
        "0.23-second build, 0 failed, suite 0.206 seconds, run 0.206 seconds, and no warnings or errors",
        "The app-level direct-authority test deterministically holds camera reconfiguration until projection is `.continuing` with `continuationIsActive`",
        "proves Learning Off cancels the exact attempt without changing machine authorization or accepted artifacts",
        "Settled accepted-request refusal remains separate focused coverage",
        "concurrent FIFO re-evaluation; transaction-complete public projection",
        "Static inspection found 29 capsule/checker test methods",
        "The untracked focused file contains eleven `@Test` methods",
        "adds eleven net Swift tests to the preceding 644/654 baselines",
        "`QUICK` 655/655",
        "`STRICT` 665/665",
        "all 36 exact EA-04 cutover scans have zero matches",
        "`submitCurrentPenCapPoint`",
        "`OperatorWorkspace.awaitPenCapAcceptedClickTransition`",
        "scoped `@unchecked Sendable` prohibition across the episode model and runtime",
        "task-owner/polling semantic-deletion scan also proves `awaitContinuationSettlement` is absent from the episode runtime and tests",
        "prior fresh read-only critic returned `RETASK` with 2/10 dimensions passing; it was not a pass or final verdict",
        "later fresh read-only critic returned `RETASK` with 5/10 dimensions passing (4, 5, 7, 8, and 10)",
        "subsequent fresh read-only critic also returned `RETASK` with 5/10 dimensions passing (3, 4, 5, 8, and 10)",
        "A fourth fresh read-only critic returned `RETASK` with 8/10 dimensions passing (1, 2, 3, 4, 5, 6, 8, and 10)",
        "failures in dimensions 7 and 9 required the waiter deletion and canonical corrections recorded here",
        "Those four pre-`ACCEPT` `RETASK` results remain nonpasses and accepted/retasked slice evidence; none is rewritten as a pass or final verdict",
        "An earlier fresh read-only critic returned `ACCEPT`: all 10/10 dimensions passed",
        "Its permitted `make docs-check` passed the documentation and architecture contracts plus 29/29 documentation/checker tests, and `git diff --check` was clean",
        "It did not rerun SwiftPM and ended exactly `UNANIMOUS PASS — no material disagreement`",
        "preceding final-tree critic returned `RETASK` with 9/10 dimensions passing (1, 2, 3, 4, 5, 6, 7, 8, and 10)",
        "dimension 9 failed on the canonical Product Contract contradiction",
        "earlier 10/10 `ACCEPT` is preserved as history but superseded as the final landing verdict by that later contradiction",
        "latest fresh critic returned `RETASK` with 7/10 dimensions passing (1, 2, 4, 5, 7, 8, and 10)",
        "dimensions 3, 6, and 9 failed on the settled-owner runtime and canonical-description mismatch",
        "After the settled-owner and Product Contract corrections, the current final fresh critic returned `ACCEPT`: all 10/10 dimensions passed",
        "For this current verdict, permitted `make docs-check` passed the documentation and architecture contracts plus 29/29 documentation/checker tests, and `git diff --check` was clean",
        "The critic did not rerun SwiftPM and ended exactly `UNANIMOUS PASS — no material disagreement`",
        "No transient critic report, including the current final report, is checked in",
        "After this landing, `EA-06` is the first eligible ordinary WorkPackage",
        "Affected: Product Contract, Episode Architecture Execution Plan, Current Evidence, Swift Architecture, the executable episode contract checker, executable inventory checker, and capsule fixtures",
        "`Scripts/check_episode_inventory.py` adds completed-package retirement behavior",
        "admits the scoped `forbidden-conformance` scan class",
        "`Scripts/test_episode_wave_capsule.py` advances the frontier fixture from `EA-04` to `EA-06`",
        "Reviewed no change — Discovery and Observed-Trial Protocol and Learning Path Button Transitions",
        "bounded inspection found no conflicting global Learning-Off admission statement",
        "both retain button-owned Cancel/Stop and the existing exercise flow without weakening operator authority",
        "Reviewed no change — Episode Architecture Vocabulary",
        "Reviewed no change — Attended Hardware Runbook and Roadmap",
        "Reviewed no change — `AGENTS.md`, `blackdog.toml`, `.gitignore`",
        "static capsule/checker method count remains 29",
        "documentation and architecture contracts plus 29/29 documentation/checker tests passed with no warnings",
        "655/655 tests passed with exactly 10 configured exclusions and no warnings",
        "665/665 Swift tests plus 29/29 documentation/checker tests passed with zero exclusions or warnings",
        "`package EA-04 complete; migration remains incomplete`",
    ):
        if required_phrase not in text:
            fail(f"EA-04 completion evidence is missing: {required_phrase}")

    historical_section = re.search(
        r"^## Historical: initial canonical episode migration documentation$(.*?)(?=^## |\Z)",
        text,
        re.MULTILINE | re.DOTALL,
    )
    if historical_section is None or "d33d4ff" not in historical_section.group(1):
        fail("DOC-00 ARCHIVED evidence section must identify d33d4ff")


def parse_wave_admission_blockers(
    evidence: str,
    rows: dict[str, dict[str, object]],
) -> dict[str, dict[str, str]]:
    blocker_rows = markdown_table(
        evidence,
        ["Package", "Blocker", "Required input or canonical correction"],
    )
    blockers: dict[str, dict[str, str]] = {}
    for package_id, blocker, required_input in blocker_rows:
        if package_id in blockers:
            fail(f"duplicate wave admission blocker for {package_id}")
        if package_id not in rows:
            fail(f"wave admission blocker references unknown package {package_id}")
        row = rows[package_id]
        if row["status"] != "pending" or row["class"] not in {"repository", "software", "gate"}:
            fail(f"wave admission blocker must name a pending ordinary package: {package_id}")
        if not blocker or not required_input:
            fail(f"wave admission blocker lacks exact disposition for {package_id}")
        if re.search(r"\b(?:TBD|unknown|to be decided)\b", f"{blocker} {required_input}", re.IGNORECASE):
            fail(f"wave admission blocker contains a deferred disposition for {package_id}")
        blockers[package_id] = {
            "blocker": blocker,
            "required_input_or_correction": required_input,
        }
    return blockers


def first_eligible_ordinary(rows: dict[str, dict[str, object]]) -> str | None:
    allowed_classes = {"repository", "software", "gate"}
    eligible = [
        package_id
        for package_id, row in rows.items()
        if row["status"] == "pending"
        and row["class"] in allowed_classes
        and all(rows[dependency]["status"] == "complete" for dependency in row["dependencies"])
    ]
    return eligible[0] if eligible else None


def ordinary_wave_frontier(
    rows: dict[str, dict[str, object]],
    evidence_blocked_packages: set[str] | None = None,
) -> str | None:
    selected = first_eligible_ordinary(rows)
    if selected is not None and selected in (evidence_blocked_packages or set()):
        return None
    return selected


def validate_wave_frontier(
    rows: dict[str, dict[str, object]], evidence: str
) -> None:
    blockers = parse_wave_admission_blockers(evidence, rows)
    selected = ordinary_wave_frontier(rows, set(blockers))
    if selected is not None:
        if selected != "EA-06":
            fail(f"unexpected current ordinary wave frontier: {selected}")
        for phrase in (
            "Episode point-selection cutover",
            "After this landing, `EA-06` is the first eligible ordinary WorkPackage.",
            "The retired `PHYSICAL-BASE` result is `failed`",
        ):
            if phrase not in evidence:
                fail(f"current ordinary wave frontier lacks evidence: {phrase}")
        return

    first_eligible = first_eligible_ordinary(rows)
    if first_eligible is not None and first_eligible in blockers:
        return

    incomplete = [package_id for package_id, row in rows.items() if row["status"] != "complete"]
    if not incomplete:
        return
    fail(f"no eligible ordinary wave package; first incomplete row is {incomplete[0]}")


def validate_live_repository_gates(rows: dict[str, dict[str, object]]) -> None:
    complete_gates = {
        gate
        for package_id, row in rows.items()
        if row["status"] == "complete"
        for gate in row["gates"]
    }
    if "ARCHIVED" in complete_gates:
        result = subprocess.run(
            ["git", "merge-base", "--is-ancestor", "d33d4ff", "HEAD"],
            cwd=ROOT,
            check=False,
        )
        if result.returncode != 0:
            fail("live ARCHIVED gate failed for d33d4ff")
    if "DIFF" in complete_gates:
        result = subprocess.run(
            ["git", "diff", "--check"],
            cwd=ROOT,
            check=False,
        )
        if result.returncode != 0:
            fail("live DIFF gate failed")


def validate_protocol(text: str, skill: str, wave_skill: str, wave_protocol: str) -> None:
    normalized = re.sub(r"\s+", " ", text)
    required = (
        "There is no unscoped continuation mode. Automatic selection is available only through `$run-multi-agent-wave`",
        "If any unrelated unfinished task exists",
        "named-package execution is not authority to advance, cancel, land, or clean unrelated work",
        "Wave mode instead follows its coordination reference",
        "failed`, `skipped`, or missing required evidence cannot satisfy a gate",
        "Tag creation and branch publication are separate packages and permissions",
        "AdaptivePlotter episode WorkPackage: <ID>",
        "`DOC-02` records the operator-accepted pre-migration rollback checkpoint",
        "leaves final attended validation in `VAL-01`",
    )
    for phrase in required:
        if phrase not in normalized:
            fail(f"execution protocol is missing: {phrase}")
    if re.search(r"\b(?:scheduled|scheduler|automation)\b", text, re.IGNORECASE):
        fail("execution protocol contains rejected task-orchestration design")
    skill_normalized = re.sub(r"\s+", " ", skill)
    for phrase in (
        "use only for work outside the episode architecture and migration",
        "stop this generic path and require a named episode command below or `$run-multi-agent-wave`",
        "The generic path can never authorize an attended-physical or remote-Git episode package",
        "That skill cannot authorize attended-physical or remote-Git work",
        "Episode audit and compile modes stop before `task begin` and therefore never validate, land, or clean a task",
        "For mutation modes only, validate as required by `AGENTS.md`",
    ):
        if phrase not in skill_normalized:
            fail(f"generic skill bypass protection is missing: {phrase}")

    wave_skill_normalized = re.sub(r"\s+", " ", wave_skill)
    for phrase in (
        "This invocation authorizes that selection. It does not authorize an `attended-physical` or `remote-git` package.",
        "consume the mode-0600 hash-bound launch capsule directly",
        "at most four active agents total",
        "Require a serial documentation integrator in every wave",
        "Generate the successor capsule mechanically",
        "Act only as coordinator",
        "Do not implement, edit, or run validation yourself",
        "If the atomic reservation loses a race, return to claim resolution instead of selecting a different row",
    ):
        if phrase not in wave_skill_normalized:
            fail(f"wave skill is missing: {phrase}")

    wave_protocol_normalized = re.sub(r"\s+", " ", wave_protocol)
    for phrase in (
        "One wave is exactly one canonical WorkPackage executed in exactly one Blackdog task worktree.",
        "Use its exact package-specific pointers instead of loading the whole ledger",
        "At most four agents are active at once",
        "Assign exactly one serial documentation integrator",
        "sole workflow-metadata generation exception",
        "do not use a successor reconnaissance agent",
        "do not start or recover a second task",
        "ask that coordinator for a bounded offload",
        "Select the first eligible row.",
        "No two live workers may write the same file",
        "Editing stops before validation begins.",
        "fresh-context read-only critic",
        "If the target becomes stale, stop workers.",
        "STATUS: ACCEPT_CANDIDATE | BLOCKED | FAILED",
        "no lifecycle/Git/hardware/remote/child-agent action and no unassigned edit",
    ):
        if phrase not in wave_protocol_normalized:
            fail(f"wave coordination protocol is missing: {phrase}")
    if "attended controller/camera/motion/Pen work" not in wave_protocol_normalized:
        fail("wave coordination protocol can bypass attended-physical authorization")
    if "branch publication, tag creation, a remote push" not in wave_protocol_normalized:
        fail("wave coordination protocol can bypass remote-Git authorization")


def main() -> int:
    try:
        plan = PLAN_PATH.read_text(encoding="utf-8")
        vocabulary = VOCAB_PATH.read_text(encoding="utf-8")
        protocol = PROTOCOL_PATH.read_text(encoding="utf-8")
        skill = SKILL_PATH.read_text(encoding="utf-8")
        wave_skill = WAVE_SKILL_PATH.read_text(encoding="utf-8")
        wave_protocol = WAVE_PROTOCOL_PATH.read_text(encoding="utf-8")
        evidence = EVIDENCE_PATH.read_text(encoding="utf-8")
        product = PRODUCT_PATH.read_text(encoding="utf-8")
        validate_vocabulary(vocabulary)
        validate_product_contract(product)
        rows = validate_plan(plan)
        validate_evidence(evidence, rows)
        validate_wave_frontier(rows, evidence)
        validate_live_repository_gates(rows)
        validate_protocol(protocol, skill, wave_skill, wave_protocol)
    except (OSError, ValueError) as error:
        print(f"episode architecture contract: {error}", file=sys.stderr)
        return 1
    print("episode architecture contract passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
