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
EXPECTED_LEDGER_SHA256 = "3894d897f4e684a02b73ca8e93591ad8a6a7d8c8ea1595a95c1e8acc4ec5fd5c"


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
    "LINK-OBS": ("`swift test --filter MachineLinkTranscriptObservabilityTests`", "FIX-02"),
    "LINK-SAFETY": ("`swift test --filter MachineLinkSafetyTests`", "FIX-02"),
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
    "FIX-02": (
        ["EA-04", "EA-05C"],
        "repository",
        ["LINK-OBS", "LINK-SAFETY", "RUNTIME", "JOURNEY", "DOC", "DIFF", "QUICK", "STRICT"],
    ),
    "EA-06": (["EA-04", "EA-05C", "FIX-02"], "software", ["DOC", "DIFF", "QUICK", "JOURNEY", "STRICT", "MOTION", "DELETE"]),
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
    "FIX-02",
    "EA-06",
    "EA-07",
    "EA-08A",
}

# Staged-complete rows let post-cutover DELETE and documentation contracts
# inspect the task-local final manifest without fabricating final gate evidence.
# EA-06 retains its accepted historical landing boundary. EA-07 is ordinary
# landed evidence on canonical main. EA-08A has its corrected focused
# DRAW-DRAFT result; the stale-manifest DELETE failure remains nonpass history,
# every post-integration gate remains required, and the sole critic's original
# RETASK awaits only a delta recheck of its three corrected findings.
EXPECTED_UNLANDED_COMPLETION_CANDIDATES = {
    "EA-06": (
        "`TASK-FE9C9CB3`",
        ["DOC", "DIFF", "QUICK", "JOURNEY", "STRICT", "MOTION", "DELETE"],
    ),
    "EA-08A": (
        "`TASK-5700F7F5`",
        ["DOC", "DIFF", "QUICK", "STRICT", "DRAW-DRAFT", "DELETE"],
    ),
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
    if "Production opens a unique directory beneath `AdaptivePlotter/EpisodeRecordings/<recording UUID>` with schema `adaptive-plotter-manual-motion-v1`" in normalized:
        fail("Product Contract retains the stale manual recording topology")
    for required_phrase in (
        "The sole active-work exception is EA-04 point selection",
        "Learning Off may itself typed-cancel only the exact point-selection/pen-cap continuation owner bound by both its selection ID and exercise-attempt token",
        "It awaits that same owner to settlement and re-evaluates the exact owner after suspension before committing Off",
        "A successor attempt token, another selection, or unrelated Learning, calibration, exploration, motion, or attempt work typed-refuses with the existing Cancel/Stop remedy",
        "This exception does not authorize Learning Off to cancel physical motion or any other owner and does not weaken operator or safety authority",
        "Every other active Learning attempt must finish or use its existing Cancel/Stop contract before Learning can be turned off",
        "the operation-bound recorder attaches before native launch to one transparent decorator around the sole production BSD `MachineLink`",
        "remains attached through natural or exact Stop/cancellation settlement",
        "Unsupported applied configuration, failed open without applied settings, timestamp mismatch, and persistence failure are diagnostic-only",
        "an applied BSD open receipt whose `localModeEnabled` or `receiverEnabled` value is false is not representable",
        "returns that native receipt unchanged",
        "records no successful open invocation or completion",
        "The ordinary true/true BSD mapping remains unchanged",
        "SIMULATED receives no controller recorder",
        "discard failure may report truthful nonnegative discarded-byte progress but no partial read chunks",
        "The episode runtime owns the exact nominal operation handle retained by `PlotterOperationRegistry`",
        "it does not replace that owner with an arbitrary effect closure, cancellation task, or unchecked-sendability escape",
        "`RunInterpreter` returns an async `PenActuationOperation` carrying its owner-minted operation identity and eventual outcome",
        "manual Pen therefore exposes no Stop capability",
        "Manual admission fails closed on capability provenance",
        "Connection, Motion, pose, and manual-controller facts must describe the submitted LIVE or SIMULATED environment",
        "Production manual motion requires a durable `EpisodeJournalPersistenceAdapter` journal",
        "runtime snapshot exposes the exact loaded journal, durable file reference and digest, plus typed incident-source references",
        "Failure to open that recording remains a visible diagnostic",
        "The production recording topology is exactly `AdaptivePlotter/EpisodeArtifacts/<episode UUID>/controller-recording`",
        "not the point-selection `EpisodeRecordings/<recording UUID>` topology",
        "A Motion-disabled refusal derives its remedy from that typed intent",
        "The workbench's busy state reads the exact active operation projected by `PlotterManualMotionRuntime`",
        "`PlotterOperationRegistry.beginStop` latches the exact original handle without invoking cancellation",
        "durably publishes cancellation `requested`",
        "marks that same transaction `issuingCancellation` atomically before the cancellation suspension",
        "durably publishes `observed`",
        "durably publishes `settling` before awaiting the owner-returned result",
        "shutdown closes admission and atomically takes over that same requested owner and handle",
        "Journal availability is not a prerequisite for shutdown cancellation",
        "one identity-bound `cancelledBeforeStart` settlement",
        "neither LIVE nor SIMULATED invokes its native operation",
        "the registry marks that same transaction `settledByShutdown`",
        "the original public Stop cursor remains the sole journal and recovery publisher",
        "Cancellation and settlement each occur exactly once",
        "operator-authorized Option A gives the runtime one shutdown latch set synchronously before its sole `registry.shutdown()` suspension",
        "After accepted `recordProgress` and before installing the runtime-active owner, submission rechecks that latch",
        "waits for that same shutdown's registry settlement",
        "publishes it through `publishPrestartTerminalSubmission`",
        "returns before active installation or native start",
        "one typed cancelled `effectResult` and leaves no registry or runtime active owner",
        "Each cancellation journal commit, its pre-state read, and its failure snapshot owns the runtime FIFO mutation/publication boundary",
        "refused as busy from the current transaction-complete snapshot before gateway evaluation",
        "commits no successor refusal event, effect, or revision",
        "reports `publicationPending` with a typed stage and recovery capability",
        "Explicit recovery resumes only that cursor",
        "the same publication-recovery capability survives with the exact terminal cursor",
        "projects only the runtime's typed recovery capability with an intent-specific manual jog, drawing, Pen Up, or Pen Down remedy",
        "disables every manual effect control, hides the stale Stop action, and rejects a stale recovery capability",
        "calls only `recoverTerminalPublication`",
        "Successful recovery clears only the matching publication diagnostic",
        "Manual availability is derived from the runtime's actual episode phase",
        "bound to its exact effect ID, environment, and observation ID",
        "all manual effects are disabled and stale disposition actions are rejected",
        "Only explicit operator evidence for the matching typed action advances the episode",
        "It never retries, redraws, reissues, cancels, or settles controller work",
        "The complete result becomes idempotently cached only after terminal publication",
        "legacy-compatible diagnostic accepted and terminal workflow-telemetry events keyed by the typed effect ID",
        "EA-07 routes every causal-simulator effect through the production `PlotterCausalSimulatorEffectAdapter`",
        "the workspace owns no second simulated manual adapter, Boundary executor, or test-only effect closure bag",
        "the exact same adapter instance as the manual runtime",
        "explicit retained-workflow owner attribution, nil `effectResult`, and no fabricated episode intent, effect, or plan revision",
        "`PlotterCausalSimulatorEffectAdapter` is the sole effect-capable SIMULATED environment boundary",
        "shared `PlotterIntent`, `PlotterEffect`, and `PlotterEffectResult` grammar",
        "`admitRetainedWorkflowBoundary`, `admitRetainedWorkflowDrawing`, `admitRetainedWorkflowTravel`, or `executeRetainedWorkflowPen`",
        "`admitManualJog` remains the typed episode-attributed path",
        "One immutable raw simulator operation ID owns admission, natural execution, original-owner waiting, and the first Stop, cancel, or shutdown settlement",
        "Manual and retained Pen ingress participates in that same adapter occupancy",
        "Pen ingress refuses with `.operationAlreadyActive(predecessor.id)` before lower Pen mutation",
        "`SimulatedLearningRuntime.setPenPoseWithCausalTruth` returns the admitted Pen mutation response and complete causal truth from one lower-runtime actor turn",
        "The adapter cannot combine a Pen result with a later, separately sampled plant, Pen, ink, or frame state",
        "The active adapter owner remains reserved after lower-runtime settlement until one atomic terminal publication binds the exact operation ID, disposition, observation, typed result when applicable, final MPos, completed Boundary count, and immutable plant/Pen/paper/ink/camera/frame truth snapshot",
        "A successor refuses until that bundle is cached and cannot contaminate the predecessor snapshot",
        "The package-only deterministic terminal-publication gate can hold that exact boundary for tests but cannot choose admission, settlement, truth, or effect authority",
        "A settled ID is idempotent only for its own result and cannot stop a successor",
        "Simulator command attribution, plant MPos and Pen pose, paper identity and ink, camera configuration/viewport/frame publication, Vision measurement, and evidence classification are separate truth layers",
        "Simulator frames are causal observations, not Vision measurements",
        "Every simulator observation and typed result has `.simulated` provenance",
        "`physicalEvidenceClaimed` is false",
        "It exposes no public `beginManualJog`, `beginBoundary`, or `beginDrawing` authority",
        "Execution pacing can change future suspension policy for deterministic tests but cannot admit, Stop, cancel, settle, or reattribute an effect",
        "Drawing Studio draft edits are revision-bound requests, not direct workspace mutations",
        "`PlotterDrawingDraftIntent` values submitted against the immutable draft and external-fact revisions shown to the operator",
        "A stale draft; changed Learning, registration, region, paper, frame, or run fact; closed studio; active run; or retained terminal receives an exact owner/reason/remedy refusal",
        "One planning adapter is the only upper route to that pure planner",
        "does not move Border sequencing, execution, observation, or evidence semantics into Drawing Studio draft authority",
        "Paper assertion persistence is nominal authority, not a presentation cache",
        "The paper polygon is displayable only on the exact accepted frame",
        "a newer exact frame can remain current when paper, source, camera configuration, and contact plane are unchanged",
        "The retained run/evidence owner authorizes the new-plan handoff after terminal review",
        "draft actions invoke no controller motion, Pen, Stop, camera, Vision, drawing-run archive, or other physical/evidence effect",
        "SIMULATED draft and paper results remain **SIMULATED — NOT PHYSICAL EVIDENCE**",
    ):
        if required_phrase not in normalized:
            fail(f"Product Contract is missing the exact Learning-Off exception: {required_phrase}")


def validate_architecture(text: str) -> None:
    normalized = re.sub(r"\s+", " ", text)
    if "Production manual motion independently creates one UUID directory under the same root" in normalized:
        fail("Swift Architecture retains the stale manual recording topology")
    for required_phrase in (
        "PlotterEpisodeRuntime -> EpisodeCore + EpisodeRuntime + PlotterEpisodeModel + PlotterRuntime",
        "The sole `MachineLink` transport contract now returns a `MachineLinkOpenReceipt`, `MachineLinkDiscardReceipt`, `MachineLinkWriteReceipt`, or `MachineLinkReadReceipt`",
        "the link-boundary `receivedAtMonotonicNanoseconds: UInt64` sampled from that link's `RuntimeClock`",
        "`MachineLinkError.discardFailed`, `.writeFailed`, and `.readFailed` retain operation-specific partial progress",
        "The production-used `BSDPendingInputDiscarder` observes one pending-input byte count and must drain that complete snapshot before success",
        "Its read size and `EINTR` retries are bounded",
        "only snapshot acquisition failure has an unknown total",
        "tests exercise the production termios mapper and discard core directly",
        "no sibling port or default protocol implementation exists",
        "EA-06 now installs one transparent `RecordingMachineLink` around the sole production BSD link at `PersistentMachineSession` composition",
        "`LiveManualMotionAdapter` attaches it to the single `ManualMotionControllerRecordingRouter` before native launch",
        "retains the lease through natural or exact Stop/cancellation settlement, and detaches only after terminal settlement",
        "An unsupported applied configuration or failed open without an applied receipt is diagnostic-only",
        "`controllerOpenParameters` also requires both applied BSD `localModeEnabled` and `receiverEnabled` to be true",
        "returns the native receipt unchanged, emits the lossless-mapping diagnostic, and records neither a successful open invocation nor completion",
        "the true/true mapping remains unchanged",
        "SIMULATED receives no controller recorder",
        "Discard failure accepts truthful nonnegative partial byte progress but no read chunks",
        "`motionRequestStatusPresentation` reads the snapshot's exact active manual operation",
        "EpisodeJournalPersistenceAdapter<PlotterEpisodeEventPayload>",
        "Production creates the journal directory as required authority and fails closed before app composition",
        "one typed `PlotterIncidentSourceArtifactReferences` value carrying recording durability/completeness separately from journal truth",
        "One FIFO mutation/publication boundary surrounds each admission or cancellation journal commit, its pre-state read and failure snapshot",
        "not held across controller cancellation or settlement suspension",
        "`submit` refuses a concurrent manual request as transiently busy from the transaction-complete snapshot before `PlotterIntentGateway` evaluation",
        "It writes no successor refusal event, effect, or revision",
        "`PlotterOperationRegistry.beginStop` latches the original nominal `ManualMotionOperationHandle`",
        "`observeStop` atomically marks the same transaction `issuingCancellation` before invoking cancellation exactly once",
        "The runtime then commits `observed`, calls `beginStopSettlement`, commits `settling`, and only then calls `finishStop`",
        "registry shutdown closes admission and atomically takes over that same staged owner and retained handle",
        "The takeover has no journal prerequisite and creates no second cancellation, settlement, or publication authority",
        "one identity-bound `cancelledBeforeStart` result",
        "makes the later `start()` inert",
        "zero native start or cancellation invocations",
        "completes the same staged transaction as `settledByShutdown`",
        "the original public Stop transaction remains the only journal/recovery publisher",
        "Operator-authorized Option A closes the remaining post-progress/pre-activation race inside `PlotterManualMotionRuntime`",
        "synchronously sets its runtime-owned `shutdownIsLatched` before the sole `registry.shutdown()` await",
        "publishes completion to waiters only after retaining every registry terminal",
        "After `recordProgress` accepts the exact identity and before assigning `active`, `submit` rechecks the latch",
        "consumes the retained exact terminal disposition",
        "Its early return precedes both runtime active-owner installation and `ManualMotionOperationHandle.start()`",
        "one typed cancelled effect publication with no native start/cancel and no residual registry or runtime owner",
        "only after `publishTerminalIfCurrent` completes",
        "A failed Stop-stage append returns `publicationPending` without advancing that stage",
        "`nextObservationIndex`; append failure leaves the exact owner active",
        "`recoverTerminalPublication` resumes only that retained cursor",
        "reuses the pending Stop recovery capability for that same owner and terminal publication cursor",
        "`manualMotionPublicationRecoveryPresentation` projects the issue's exact `PlotterManualMotionPublicationRecoveryCapabilityID`",
        "every manual effect control receives that remedy, `stopAction` is absent",
        "`recoverManualMotionPublication` rejects a stale capability",
        "clears `machineError` only when it still equals the matching publication remedy",
        "derives availability from the actual runtime phase",
        "binds the exact effect ID, environment, observation ID, and possible-ink versus other-ambiguity disposition",
        "Every manual effect stays disabled until the exact current action records explicit operator evidence",
        "stale or mismatched actions are rejected",
        "neither retries nor redraws",
        "transaction-complete result is cached only after terminal publication",
        "The package-only typed Stop-publication gate can pause deterministically after registry settlement and before episode publication",
        "It cannot choose an outcome, cancel, publish, or grant authority, and its tests require no sleeps or polling",
        "The registry retains the nominal `ManualMotionOperationHandle`",
        "neither the registry nor the episode runtime stores an arbitrary effect closure, replacement cancellation task, or `@unchecked Sendable` escape",
        "Native direct Pen admission returns an async nominal `PenActuationOperation` from `RunInterpreter` with its owner-minted ID",
        "its cancellation switch deliberately issues no Stop for Pen",
        "Connection, Motion, pose, and `PlotterManualControllerFact` values are environment-bound",
        "missing or cross-environment facts fail closed",
        "`EpisodeRecordingStore` and `PlotterEpisodeReplayService` deliberately share the same failure validator",
        "Production manual motion instead opens EA-05A at the exact topology `AdaptivePlotter/EpisodeArtifacts/<episode UUID>/controller-recording`",
        "The point-selection `EpisodeRecordings/<recording UUID>` path above is a separate topology and is not reused for manual motion",
        "The evaluator supplies an intent-specific Motion remedy",
        "legacy-compatible accepted and terminal diagnostic telemetry under the typed `EpisodeEffectID`",
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
        "`PlotterCausalSimulatorEffectAdapter` is the sole effect-capable simulator seam",
        "`PlotterManualMotionRuntimeComposition` containing the manual runtime, lower simulator runtime, and shared `PlotterCausalSimulatorEffectAdapter`",
        "retained workflows use the exact same adapter authority as the manual runtime",
        "Its public effect APIs are `admitManualJog`, `admitRetainedWorkflowBoundary`, `admitRetainedWorkflowDrawing`, `admitRetainedWorkflowTravel`, and `executeRetainedWorkflowPen`",
        "Retained work requires an exact `EpisodeAuthorityID`, carries `.retainedWorkflow(owner:)`, returns nil `effectResult`, and creates no fabricated intent, effect, or plan revision",
        "retains the raw `SimulatedLearningOperationID` as the immutable Stop/cancel/shutdown and settlement identity",
        "Manual and retained Pen ingress enters the same adapter actor and observes the same `activeOperation` reservation",
        "returns `.operationAlreadyActive(predecessor.id)` with the current lower causal truth before calling the lower Pen mutator",
        "`SimulatedLearningRuntime.setPenPoseWithCausalTruth` performs the admitted Pen mutation and captures `SimulatedLearningCausalTruth` in one lower-runtime actor turn",
        "The adapter therefore cannot pair a Pen response with a separately sampled later plant/Pen/ink/frame state",
        "keeps that active owner reserved after lower-runtime settlement until one actor-isolated `publishTerminalOutcome` atomically caches the operation identity, disposition, observation, typed result when applicable, final plant position, completed Boundary count, and immutable separated truth snapshot",
        "A successor refuses until that publication completes; it cannot contaminate the predecessor's MPos, Pen, ink, or frame snapshot",
        "`PlotterCausalSimulatorTerminalPublicationGate` can pause exactly after lower settlement and before publication for deterministic regression tests",
        "A settled predecessor is idempotent for its own ID and cannot cancel a successor",
        "Mutable execution pacing is a lock-backed suspension policy snapshotted before execution, not effect authority",
        "`SimulatedLearningRuntime` has no public `beginManualJog`, `beginBoundary`, or `beginDrawing` effect API",
        "Its one package-scoped `admitCausalOperation` is called only by the adapter",
        "`OperatorWorkspace.executeSimulatedBoundaryMotion` and the former App-local simulated adapter are absent",
        "`PlotterCausalSimulatorTruthSnapshot` keeps controller-command attribution distinct from plant MPos/Pen, paper/ink, camera publication, Vision, and evidence truth",
        "declares `PlotterCausalSimulatorVisionTruth.notComputedBySimulator`",
        "reports `.simulatedCausal`, sets `physicalEvidenceClaimed` false, and emits `.notPhysicalEvidence`",
        "The removed `SimulatedWorkspaceHarness`, `makeSimulatedHarness`, and `performPublicAction` cannot bypass the workspace composition",
        "App tests retain only a read-only causal snapshot plus explicit fault-injection probe",
        "fifteen causal-environment tests for shared grammar/provenance, separated truth, exact settlement",
        "holds the predecessor while proving both retained Pen refusal with no lower mutation and retained drawing refusal",
        "proves drawing successor isolation plus unchanged cached predecessor truth",
        "The focused workspace authority suite's 24/24 correction evidence includes the regression proving manual runtime and retained workflows occupy one shared production adapter authority",
        "`PlotterDrawingDraftRuntime` is the single source-indexed draft owner",
        "`PlotterDrawingDraftSubmission` binds a `PlotterDrawingDraftRequestID`, one immutable `PlotterDrawingDraftRevision`, the complete `PlotterDrawingDraftExternalFactRevisions`, and a typed `PlotterDrawingDraftIntent`",
        "SwiftUI receives immutable `PlotterDrawingDraftSnapshot` values and submits only through `PlotterDrawingDraftIntentSink`",
        "`PlotterDrawingPlanningAdapter` is the sole upper-layer route into the retained lower pure `DrawingPlanner`",
        "`planRetainedDrawingBorder` route lets the explicitly retained EA-10E Border workflow reuse the same pure planner",
        "Planning clips nothing: one outside-region point refuses the complete plan",
        "Preview binds the exact displayed frame, program content hash, and plan revision",
        "`PlotterDrawingDraftPaperPersistence` is the sole draft persistence seam",
        "A LIVE save completes before the accepted snapshot is published",
        "Currentness is a separate `PaperCoverageValidationContext` decision",
        "newer same-context frames remain current, while paper, source, camera configuration, or contact-plane changes invalidate the assertion",
        "Draft mutation refuses while retained EA-08B run/evidence work owns the workflow or a terminal still requires its explicit new-plan handoff",
        "no draft action invokes machine motion, Stop, camera, Vision, run evidence, or another physical effect",
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
    for required_phrase in (
        "At that inspection, the then-current `MachineLink` operations returned either no value or untimestamped bytes",
        "`FIX-02` has corrected that canonical contract before EA-06",
        "The landed correction uses the sole existing `MachineLink` protocol, adds no sibling observability port or default implementation",
    ):
        if required_phrase not in normalized:
            fail(f"FIX-02 historical/current plan boundary is missing: {required_phrase}")
    for forbidden_phrase in (
        "The current `MachineLink` operations return either no value or untimestamped bytes",
        "`FIX-02` corrects that canonical contract before EA-06",
    ):
        if forbidden_phrase in normalized:
            fail(f"FIX-02 plan retains a stale present-tense contradiction: {forbidden_phrase}")
    for required_phrase in (
        "project one capability-only intent-specific recovery that disables manual effects, hides stale Stop, rejects stale capabilities, resumes only the exact runtime cursor, clears only its matching diagnostic, and reissues no controller work",
        "returning unrepresentable applied-open receipts unchanged, recording no fabricated successful pair",
        "shutdown takeover of the same requested owner/handle without journal dependency or duplicate authority",
        "FIFO-isolated cancellation publication, and pre-gateway active-owner busy refusal",
        "keep the exact owner plus typed cursor and recovery capability when a Stop/terminal append is incomplete including after shutdown",
        "identity-bound `cancelledBeforeStart` retirement with inert later start and zero LIVE/SIMULATED native invocation",
        "observed/settling `settledByShutdown` handoff that leaves the original public Stop cursor as sole publisher",
        "EA-05A controller recording authority at `AdaptivePlotter/EpisodeArtifacts/<episode UUID>/controller-recording`",
        "derive manual availability plus exact effect/environment/observation possible-ink or ambiguity disposition from runtime phase",
        "a runtime-owned shutdown latch set before the sole registry shutdown suspension and rechecked after accepted progress",
        "Completed by `TASK-FE9C9CB3`, attempt `TASK-FE9C9CB3-54834fa90e36`",
        "package EA-06 complete, migration remains incomplete",
        "`CITED_RACE_CLOSED` closes the same-critic delta and no further critic is required or allowed",
        "Blackdog landing/cleanup and successor-capsule creation are the only remaining steps",
    ):
        if required_phrase not in normalized:
            fail(f"EA-06 plan outcome is missing accepted RETASK authority: {required_phrase}")
    for required_phrase in (
        "`PlotterCausalSimulatorEffectAdapter.admitManualJog`",
        "`PlotterCausalSimulatorEffectAdapter.admitRetainedWorkflowBoundary`",
        "`PlotterCausalSimulatorEffectAdapter.admitRetainedWorkflowDrawing`",
        "`PlotterCausalSimulatorEffectAdapter.admitRetainedWorkflowTravel`",
        "`PlotterCausalSimulatorEffectAdapter.executeRetainedWorkflowPen`",
        "retained Boundary/drawing/travel/Pen work carries its explicit owner with nil `effectResult` and no fabricated plan revision",
        "Pen ingress refuses the exact reserved predecessor without lower mutation, while admitted lower Pen mutation plus causal truth is returned atomically by package-only `SimulatedLearningRuntime.setPenPoseWithCausalTruth`",
        "retain the active owner from lower terminal settlement through one atomic cached outcome/truth publication",
        "A package-only terminal-publication gate proves both retained Pen refusal/no mutation and drawing successor isolation deterministically without sleeps or polling",
        "The landed candidate passed `SIM` 15/15, `DELETE` 4/4, `DOC` 29/29, clean `DIFF`, `QUICK` 705/705, `JOURNEY` 7/7, and `STRICT` 712/712 plus its warning-as-error strict-concurrency build, signing, launcher, and negative-bundle checks",
        "The original critic RETASK and correction-cycle-1 RETASK remain nonpass history",
        "the same sole critic's correction-cycle-2 final verdict was exactly `UNANIMOUS PASS — no material disagreement`",
        "Policy allowed one critic and at most two correction/delta cycles, and forbids a post-pass critic",
        "No physical or remote-Git validation occurred or is claimed",
        "landed with cleanup verified on canonical `main` at `ac6a6688`",
    ):
        if required_phrase not in normalized:
            fail(f"EA-07 plan outcome is missing corrected simulator authority: {required_phrase}")
    for required_phrase in (
        "`PlotterDrawingDraftRuntime.submit`",
        "source-indexed `PlotterDrawingDraftRevision` and `PlotterDrawingDraftExternalFactRevisions`",
        "revision-bound `PlotterDrawingDraftSubmission`",
        "exact owner/reason/remedy refusals",
        "immutable `PlotterDrawingDraftSnapshot` publication through one `PlotterDrawingDraftRuntime` and `PlotterDrawingDraftIntentSink`",
        "only through `PlotterDrawingPlanningAdapter`",
        "retained EA-10E Border planning without moving Border semantics",
        "refuse exact-frame/registration, invalid parameter, stale revision, run-owner, handoff, and outside-region cases without clipping",
        "exact-frame/applicability/diagnostic-only preview",
        "nominal save-before-publish storage",
        "exact-frame polygon display, and paper/source/configuration/contact-plane currentness",
        "retained EA-08B run authority only after its explicit new-plan handoff",
        "Completed only in the task-local candidate by `TASK-5700F7F5`, attempt `TASK-5700F7F5-0ad2465cded1`",
        "All six package gates passed: `DRAW-DRAFT` 17/17, `DELETE` 4/4, `DOC` 29/29, clean `DIFF`, `QUICK` 720/720, and `STRICT` 727/727",
        "Earlier failed/interrupted invocations remain nonpass history",
        "The sole fresh critic returned `RETASK` on a persistence lost-update window, stale retained-run admission, and scale clipping",
        "the same critic's delta-only recheck ended exactly `UNANIMOUS PASS — no material disagreement`",
        "Criticism is closed: no new/full or post-pass critic is allowed",
        "Blackdog landing, canonical-`main` cleanup verification, and conditional successor-capsule creation remain pending",
    ):
        if required_phrase not in normalized:
            fail(f"EA-08A plan outcome is missing drawing-draft authority: {required_phrase}")
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
        "FIX-02": (
            "sole `MachineLink` contract",
            "every production/test conformance",
            "transport-discriminated applied-open configuration",
            "exact discard/write/read transfer facts",
            "monotonic receive timestamps",
            "observable close failure",
            "operation-specific partial-failure progress",
            "without a sibling port, default implementation, fabricated values, recorder installation, product-authority transfer, or physical-evidence claim",
            "Delivered by `TASK-30357281`",
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
    normalized = re.sub(r"\s+", " ", text)
    if "Production opens a unique directory beneath `AdaptivePlotter/EpisodeRecordings/<recording UUID>` with schema `adaptive-plotter-manual-motion-v1`" in normalized:
        fail("Current Evidence retains the stale manual recording topology")
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
            if gate not in expected_gates:
                continue
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

    candidate_rows = markdown_table(
        text,
        [
            "Candidate package",
            "Blackdog task",
            "Current gate state",
            "Landing boundary",
        ],
    )
    candidates: set[str] = set()
    for package_id, task, gate_cell, landing_boundary in candidate_rows:
        if package_id in candidates:
            fail(f"duplicate unlanded completion candidate: {package_id}")
        if package_id not in EXPECTED_UNLANDED_COMPLETION_CANDIDATES:
            fail(f"unexpected unlanded completion candidate: {package_id}")
        if package_id in evidence_by_package:
            fail(f"{package_id} cannot have candidate and final gate evidence")
        if rows[package_id]["status"] != "complete":
            fail(f"unlanded candidate {package_id} is not staged complete")
        expected_task, expected_gates = EXPECTED_UNLANDED_COMPLETION_CANDIDATES[package_id]
        if task != expected_task:
            fail(f"{package_id} unlanded candidate task drifted: {task}")
        if not re.fullmatch(
            r"`[A-Z][A-Z0-9-]*`=(?:passed|rerun-required)(?:, `[A-Z][A-Z0-9-]*`=(?:passed|rerun-required))*",
            gate_cell,
        ):
            fail(f"{package_id} candidate gates are not exact passed/rerun results: {gate_cell}")
        actual_pairs = re.findall(
            r"`([A-Z][A-Z0-9-]*)`=(passed|rerun-required)", gate_cell
        )
        actual_gates = [gate for gate, _state in actual_pairs]
        if actual_gates != expected_gates or actual_gates != rows[package_id]["gates"]:
            fail(
                f"{package_id} candidate gates must be {rows[package_id]['gates']}; "
                f"found {actual_gates}"
            )
        expected_states = {
            "EA-06": {
                "DOC": "rerun-required",
                "DIFF": "rerun-required",
                "QUICK": "rerun-required",
                "JOURNEY": "passed",
                "STRICT": "rerun-required",
                "MOTION": "passed",
                "DELETE": "passed",
            },
            "EA-08A": {
                "DOC": "passed",
                "DIFF": "passed",
                "QUICK": "passed",
                "STRICT": "passed",
                "DRAW-DRAFT": "passed",
                "DELETE": "passed",
            },
        }[package_id]
        if dict(actual_pairs) != expected_states:
            fail(f"{package_id} candidate gate-state drifted: {dict(actual_pairs)}")
        if package_id == "EA-06":
            if "Refresh affected `DOC`, `DIFF`, `QUICK`, and `STRICT`" not in landing_boundary:
                fail(f"{package_id} candidate lacks the exact affected-gate boundary")
            if "`CITED_RACE_CLOSED` already closes the critic boundary" not in landing_boundary:
                fail(f"{package_id} candidate lacks the closed same-critic delta boundary")
            if "no further critic is required or allowed" not in landing_boundary:
                fail(f"{package_id} candidate incorrectly leaves critic work open")
        else:
            for phrase in (
                "All six package gates passed: `DRAW-DRAFT` 17/17, `DELETE` 4/4, `DOC` 29/29, clean `DIFF`, `QUICK` 720/720, and `STRICT` 727/727",
                "its corrected three-finding delta recheck ended exactly `UNANIMOUS PASS — no material disagreement`",
                "Blackdog landing, canonical-`main` cleanup verification, and conditional EA-08B successor-capsule creation remain pending",
                "No landing or cleanup is claimed",
            ):
                if phrase not in landing_boundary:
                    fail(f"{package_id} candidate lacks landing boundary: {phrase}")
        candidates.add(package_id)

    expected_candidates = set(EXPECTED_UNLANDED_COMPLETION_CANDIDATES)
    if candidates != expected_candidates:
        missing = sorted(expected_candidates.difference(candidates))
        extra = sorted(candidates.difference(expected_candidates))
        fail(f"unlanded completion candidate mismatch; missing={missing}, extra={extra}")

    complete_packages = {package_id for package_id, row in rows.items() if row["status"] == "complete"}
    evidenced_packages = set(evidence_by_package)
    accounted_packages = evidenced_packages | candidates
    if complete_packages != accounted_packages:
        missing = sorted(complete_packages.difference(accounted_packages))
        extra = sorted(accounted_packages.difference(complete_packages))
        fail(f"complete-package evidence mismatch; missing={missing}, extra={extra}")

    for required_phrase in (
        "Machine-link transcript observability correction",
        "Delivered 2026-08-28 in Blackdog task `TASK-30357281`",
        "FIX-02 corrects the canonical transport-observability prerequisite before EA-06",
        "`MachineLinkOpenReceipt` with a transport-discriminated `MachineLinkAppliedConfiguration`",
        "`MachineLinkBSDSerialAppliedConfiguration`",
        "`.simulated(identifier:)`; it does not manufacture baud, parity, flow-control, or other serial facts",
        "`MachineLinkDiscardReceipt` and `MachineLinkWriteReceipt` with exact byte counts",
        "`MachineLinkReadReceipt` with the exact bytes and the link-boundary `receivedAtMonotonicNanoseconds: UInt64`",
        "`MachineLinkError.discardFailed`, `.writeFailed`, and `.readFailed` preserve operation-specific partial counts or timestamped partial read receipts",
        "The production-used `BSDPendingInputDiscarder` first observes the pending-input snapshot, then drains that complete observed byte count through bounded reads",
        "It returns success only after every observed byte is discarded",
        "exhausted bounded `EINTR` retry budget instead returns exact `MachineLinkError.discardFailed` progress",
        "including zero or partial discarded counts and the observed total",
        "Only snapshot acquisition failure leaves the total unknown",
        "production termios mapper and discard core are exercised by applied-configuration and discard regression tests",
        "At the FIX-02 landing, there was no protocol default implementation, alternate effect path, new semantic ingress, or installed `RecordingMachineLink`",
        "10/10 tests passed, 0 failed, with no warnings or errors",
        "`LINK-SAFETY` | passed — `swift test --filter MachineLinkSafetyTests`; 12/12 tests passed, 0 failed, with no warnings or errors",
        "88/88 tests passed across 4 suites, 0 failed, with no warnings or errors",
        "10/10 tests passed across 3 suites, 0 failed, with no warnings or errors",
        "documentation and architecture contracts plus 29/29 documentation/checker tests passed, 0 failed, with no warnings or errors",
        "`git diff --check`; exit 0, no output",
        "665/665 tests passed with the 10 JOURNEY tests explicitly excluded, 0 failed, with no warnings or errors",
        "675/675 Swift tests passed with no exclusions and 0 failed; strict-concurrency warnings-as-errors, app signing, launcher logic and validation, negative bundle, and documentation 29/29 passed with no warnings or errors",
        "The prior fresh read-only critic returned `RETASK`, not pass",
        "dimensions 4, 5, 8, and 9 failed",
        "Dimension 4 found swallowed close failures",
        "dimension 5 found zero-progress and partial-transfer derivation gaps",
        "dimension 8 required production-derived observability tests",
        "dimension 9 rejected the provisional canonical documentation",
        "A second fresh read-only critic also returned `RETASK`, not pass",
        "dimensions 1, 4, 5, 7, and 9 failed",
        "discard could report success without draining the complete observed snapshot",
        "zero-progress and partial discard failures were not exact",
        "`EINTR` retry was unbounded",
        "production-derived applied-configuration and discard coverage was deficient",
        "canonical evidence overclaimed completion",
        "The second RETASK remains nonpass history",
        "Those source, test, and documentation findings were corrected and revalidated",
        "The second critic's source, test, and evidence findings were corrected, and all eight gates above were rerun against the integrated frozen tree",
        "A later landing critic returned `RETASK`, not pass",
        "Dimension 9 failed because the execution plan described the pre-FIX-02 transport deficiency in present tense",
        "That historical/current contradiction was corrected",
        "This RETASK remains nonpass history",
        "the preceding fresh context-isolated critic returned `ACCEPT`: all 10/10 dimensions passed with no material findings",
        "`make docs-check` passed both contracts and 29/29 documentation/checker tests",
        "`git diff --check` was clean",
        "The critic performed no Swift test, build, hardware, remote-Git, or lifecycle action",
        "ended exactly `UNANIMOUS PASS — no material disagreement`",
        "This recorded verdict predates this critic-verdict integration",
        "A new final critic after this integration remains required; no post-edit critic pass is claimed",
        "After this landing, `EA-06` is the first eligible ordinary WorkPackage",
        "Its dependencies `EA-04`, `EA-05C`, and `FIX-02` are complete",
        "No attended controller, camera, motion, Pen, paper, operator-click, or observed ink validation occurred",
        "no physical or remote-Git evidence is claimed",
        "`package FIX-02 complete; migration remains incomplete`",
    ):
        if required_phrase not in normalized:
            fail(f"FIX-02 completion evidence is missing: {required_phrase}")

    for required_phrase in (
        "Episode manual-motion cutover candidate",
        "`TASK-FE9C9CB3`",
        "Operator-authorized Option A candidate after critic RETASK #6, 2026-08-28",
        "`c17cddb971f6df9e0ddefb0fd98991f94fad1deec2cf72a9f02992182211fd7b`",
        "`5dbe44431fe5f955ec336b5f769281635ca638e8add5564e6ed78b6d5cbf1310`",
        "`707a30cdb8a540e28a5a02176c77bb751503a8845218947b6527fbe697806ff6`",
        "`7c78ec2edd4f4beb9e8e2098570127bd127eac9e91e744780b290514de7028ab`",
        "`975d1dc9feb49e4488634824a12315c3da063dd825eed61f82b959ffc58c66e2`",
        "Every previously recorded package-wide green sequence remains historical evidence for its exact earlier tree only",
        "Critic RETASK #6 was material, not acceptance",
        "The accepted source correction and same-critic delta closure are recorded below",
        "This exact five-bound tree passed all seven package gates serially",
        "no new or full critic was commissioned and no further critic is required or allowed",
        "`TASK-FE9C9CB3-54834fa90e36`",
        "EA-06 is complete in the task-local candidate",
        "migration remains incomplete",
        "Blackdog landing/cleanup and successor-capsule creation are the only remaining steps",
        "`7f2823a78b8a1c7be75f9b7e4caadc1deca70949166bd23226c4712a9fa30181`",
        "`d21660321c1aa15594bea246a7e4a1b140020eeeab6c501d534ba9347f66d393`",
        "`e0edfb9145bc52396fdc754aed7f492ddc14aa7050f489ca7f6e1ad3cbe78e74`",
        "one `ManualMotionControllerRecordingRouter` before native launch",
        "retains the lease through natural or exact Stop/cancellation settlement",
        "wraps it once in a transparent `RecordingMachineLink`",
        "applied BSD open configuration",
        "A configuration that cannot be represented losslessly and a failed open without an applied configuration produce diagnostics only",
        "truthful nonnegative partial discard progress with no partial read chunks",
        "SIMULATED receives no controller recorder and proves no physical behavior",
        "Fresh critic RETASK #4 found that applied BSD `localModeEnabled=false` or `receiverEnabled=false` could not be represented",
        "returns the native receipt unchanged, records no successful open invocation or completion",
        "The true/true mapping is unchanged",
        "projects only the exact `PlotterManualMotionPublicationRecoveryCapabilityID` with an intent-specific manual jog, drawing, Pen Up, or Pen Down remedy",
        "disables every manual effect, hides stale Stop, and refuses stale recovery capabilities",
        "calls only `recoverTerminalPublication`, clears only its matching publication diagnostic",
        "It cannot re-admit the intent or reissue, cancel, or settle controller work",
        "applies that partial-discard rule identically in `EpisodeRecordingStore` and deterministic replay",
        "The registry retains `ManualMotionOperationHandle`, not an erased closure or replacement cancellation task",
        "the episode model/runtime add no `@unchecked Sendable` authority escape",
        "Direct LIVE Pen now admits through the nominal async `PenActuationOperation` returned by `RunInterpreter`",
        "neither the registry nor the public manual projection creates a Pen Stop token",
        "Capability provenance now fails closed",
        "connection, Motion, pose, and `PlotterManualControllerFact` values are bound to the submitted LIVE or SIMULATED environment",
        "Production requires its UUID-scoped `EpisodeJournalPersistenceAdapter` journal",
        "Controller-recording open failure remains diagnostic-only",
        "Every runtime snapshot exposes the exact loaded `EpisodeJournal`",
        "typed `PlotterIncidentSourceArtifactReferences`",
        "Append failure retains the exact owner, stage/result cursor, and typed recovery capability",
        "durably publishes `requested`; the registry atomically marks the same transaction `issuingCancellation` before suspension and invokes cancellation once",
        "Fresh critic RETASK #5 found two material authority defects",
        "leave shutdown waiting forever on an attempt that nobody owned to advance",
        "a concurrent gateway refusal could terminalize the model request and clear the still-active owner",
        "shutdown sees the same transaction still at requested, it closes admission and takes over that exact owner and handle",
        "there is no journal dependency, duplicate cancel, settlement, or publication authority",
        "pending Stop recovery capability survives with the exact terminal-publication cursor",
        "Each cancellation journal commit, its pre-state read, and its failure snapshot now owns the FIFO mutation/publication boundary",
        "a concurrent submission is refused transiently as busy from the transaction-complete snapshot before gateway evaluation",
        "records no successor refusal event, effect, or revision collision",
        "Critic RETASK #6 found four material gaps",
        "shutdown could race a registered operation before native start without one terminal owner-retirement path",
        "shutdown joining a Stop already at observed or settling needed an explicit ownership handoff",
        "derive manual availability and possible-ink/ambiguity disposition from the actual runtime phase",
        "canonical documents named the point-selection recording root instead of the production manual recording topology",
        "identity-bound `cancelledBeforeStart` result",
        "makes any later start inert",
        "LIVE and SIMULATED therefore perform zero native start or cancellation invocation",
        "registry shutdown hands the same transaction to `settledByShutdown`",
        "the original public Stop cursor remains the sole journal and recovery publisher",
        "cancellation and settlement occur exactly once",
        "typed disposition bound to the exact effect ID, environment, and observation ID",
        "All manual effects stay disabled while it is unresolved",
        "stale or mismatched actions are rejected",
        "only explicit operator evidence for that matching action advances the episode",
        "never retries, redraws, reissues, cancels, or settles controller work",
        "`AdaptivePlotter/EpisodeArtifacts/<episode UUID>/controller-recording`",
        "This is distinct from the retained point-selection `EpisodeRecordings/<recording UUID>` topology",
        "no successor can be admitted until publication completes",
        "Accepted-slice history now records six coordinator `RETASK` decisions",
        "None was an acceptance verdict",
        "Store/Replay partial-discard consistency",
        "nominal typed handle ownership without closure or unchecked-sendability escape",
        "durably staged Stop progress and retained-owner cursor recovery after append failure",
        "async owner-identified direct Pen without Stop",
        "fail-closed LIVE/SIMULATED capability provenance",
        "required journal plus typed recording/incident-source truth",
        "Its focused development evidence was 4/4 new tests plus 3/3 retained tests",
        "two intermediate compile/test nonpasses were corrected before those accepted focused results",
        "requested-owner shutdown takeover test passed 1/1",
        "FIFO publication test passed 1/1 after two truthful development nonpasses",
        "related regression groups passed 6/6 and 4/4",
        "deterministic repeats passed 50/50",
        "the owned suites passed 29/29",
        "the focused source diff check was clean",
        "the runtime group passed 14/14",
        "ambiguity UI passed 3/3",
        "retained recovery passed 3/3",
        "deterministic race repeats passed 60/60",
        "Development nonpasses encountered while compiling/testing the correction were corrected before those accepted focused results",
        "Operator-authorized Option A closes the remaining accepted-progress/pre-activation race with one runtime-owned shutdown latch",
        "`PlotterManualMotionRuntime.swift:1329-1356`",
        "sets `shutdownIsLatched` synchronously before the sole `registry.shutdown()` suspension",
        "retains every exact registry terminal, and only then releases the same-shutdown completion waiters",
        "`PlotterManualMotionRuntime.swift:1101-1123`",
        "rechecks that latch after accepted `recordProgress` and before `active` installation",
        "returns through `publishPrestartTerminalSubmission`",
        "The active-install and native-start lines are below that return and are not reached",
        "the new deterministic filter passed 1/1",
        "the complete manual suite passed 15/15",
        "shutdown remained bounded for both LIVE and SIMULATED",
        "neither registry nor runtime retained an active owner",
        "one typed cancelled `effectResult`",
        "native start and cancellation counts were both zero",
        "`PlotterManualMotionEpisodeTests.swift:74-136`",
        "The same critic returned the exact delta verdict `CITED_RACE_CLOSED`",
        "All earlier passed critic dimensions remained closed",
        "no new or full critic was commissioned; no further critic is required or allowed",
        "These focused results and the delta verdict accept the Option A source correction but do not by themselves satisfy any package gate",
        "Current serial validation on the exact Option A tree",
        "`swift test --filter PlotterManualMotionEpisodeTests`; 15/15 tests passed",
        "`9aaa0b87c20d05ae3d98d3c5c9c50a79d00942547e3fafd2e7f93f637fdc873f`",
        "`sh Scripts/check_episode_cutover.sh EA-06`; all 26 exact scans had zero matches",
        "`b841daa4968ac8fa3bb03058663abc9e8fbcab9fd5d65487b6fb2aa786afb04e`",
        "`make docs-check`; both documentation contracts plus 29/29 documentation/checker tests passed",
        "`8986b9a8dc4091c34c32da507c6a29c0ebb54685067335f5641007868c26ce8d`",
        "`git diff --check`; clean with no output",
        "`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`",
        "`make quick-test`; 699/699 tests passed with exactly 10 configured exclusions",
        "`6d9cc817581951b1ec9e024f9522e43337f81a6ff06bc4a90973efd7998c1794`",
        "`make journey-test`; 10/10 filter-selected tests passed",
        "`a4370968c633e28fbdb6685017c4c200f68eb5dd66be1efa876b378ad9fcc27c`",
        "`make strict-check`; strict-concurrency/warnings-as-errors, 709/709 tests with no exclusions",
        "`06c6f7c1a5aef895850bedc4c502c8a0acf60aa7836d754e69225dd7c564f06a`",
        "This final evidence/checker delta affects `DOC`, `DIFF`, `QUICK`, and `STRICT`",
        "refresh those four gates on the final candidate before recording landed evidence",
        "`MOTION`, `DELETE`, and `JOURNEY` are source-sensitive and remain bound to the unchanged frozen tree",
        "No Blackdog landing or canonical-main result is claimed",
        "Two compile-only development failures were corrected before the accepted focused checks",
        "`ef61b0f24251708c24d8fcf00a155377c5869eae92c3dbcc146dc87f66893c16`",
        "`a1aa2e57d97b9e0cba44030fdb1bff0c27157a7887a53a66d2f70c0b58e0ceec`",
        "`MOTION` 5/5 passed, `DELETE` 26/26 exact zero-match scans passed, `DOC` 29/29 passed, and `DIFF` clean",
        "`QUICK` then failed with exit 2 after 676 tests and reported 7 issues across four named failures",
        "Its output was truncated, so exhaustive warning status is unevidenced",
        "`JOURNEY` and `STRICT` were not started",
        "superseded `RETASK`/nonpass history, never current passed gate evidence",
        "direct Pen refusal reused the jog-specific Motion remedy",
        "workbench busy projection omitted the episode-owned active manual operation",
        "retired manual diagnostic telemetry had no episode-terminal replacement",
        "a duplicate exact Stop arriving during or after terminal publication could be misclassified stale under load",
        "`6183d29c055e1d686fb15267b172d4b2c6f6857fd009a7e78d794b97936738a9`",
        "`5ca6ec7ea37299cc76757db7c1ce6f09a2988e05f2ef467520c1cf0e56cdeee3`",
        "`3ec2ac439e1d5a43049f8bbd8e0c4a7f3a1f725e751e18674d73300cfc584e34`",
        "`13dd31759fef587206aaf37116925f4cee54ab10e9d578791d2420e68a4cd2d2`",
        "`8289be44304ec49c41970456f73ccbe649bf5a044a7d4a1d10eb63b154f149c5`",
        "development-only `PlotterRecordingStoreTests`: 37/37 passed",
        "development-only `PlotterManualMotionEpisodeTests`: 5/5 passed",
        "the three parallel `liveManualMotion` focused tests: 3/3 passed",
        "the original four failures reproduced independently",
        "the corrected workspace trio passed 3/3 in parallel",
        "the corrected `PlotterManualMotionEpisodeTests` suite passed 5/5",
        "`exactStop` passed 20/20 across ten repeated parallel runs",
        "the final combined parallel filters passed 6/6",
        "new `directPenMotionRemedy` passed 1/1",
        "One attempted `--num-workers` invocation was rejected before any test ran because that option is XCTest-only",
        "`make docs-check`; exit 0; both documentation contracts and 29/29 documentation/checker tests passed with no exclusions, warnings, or errors; real 9.65, user 6.42, sys 3.11 seconds",
        "`git diff --check`; exit 0 with no output or errors; real 0.03, user 0.02, sys 0.01 seconds",
        "`make quick-test`; exit 0; 677/677 tests passed with exactly 10 configured exclusions",
        "`f83bedda24f7252f55fbf2ebdc26d4a3f21fd308484926c203922f28584ec59a`",
        "`make journey-test`; exit 0; 10/10 filter-selected tests passed with no explicit exclusions, warnings, or errors; real 6.16, user 5.92, sys 0.24 seconds",
        "`701035fde2219b4c8c508b3130d87493434a025eacd1e5ee6527f13adcb2149e`",
        "`make strict-check`; exit 0; strict-concurrency and warnings-as-errors build, 687/687 tests with no exclusions",
        "`4234b7805fb5bd382d6d24c64454952c783777e1ebba033d9df2dfa3a71b32ab`",
        "read-only progress inspection at about 74 seconds showed active compiler workers and advancing build step 48/77",
        "`swift test --filter PlotterManualMotionEpisodeTests`; exit 0; 5/5 tests passed with no exclusions, warnings, or errors; real 1.42, user 1.12, sys 0.23 seconds",
        "`sh Scripts/check_episode_cutover.sh EA-06`; exit 0; all 26 exact scans had zero matches with no warnings or errors; real 0.34, user 0.30, sys 0.03 seconds",
        "That table remains exact historical evidence for frozen diff",
        "its current-pass claim was superseded by the second affected-gate tree",
        "`DOC` passed 29/29, `DIFF` was clean, and `QUICK` failed with exit 2 after 677 executed, 676 passed, 1 failed, and 2 issues",
        "with 10 configured exclusions and no warning or compiler-error lines",
        "real 79.91, user 578.63, sys 61.29 seconds",
        "`STRICT` was not started",
        "This is second-`RETASK` nonpass evidence, not a passed gate sequence",
        "one caller received `.settled` with a pre-terminal snapshot whose `lastTerminalEffect` was nil",
        "typed cancellation settlement was missing at test lines 66 and 70",
        "`/tmp/adaptiveplotter-ea06-final-quick.jrV95l`",
        "154880 bytes with SHA-256 `5924c5e19282dfff13d56aeeaaedfc7172cbe1780d82f287d70fd36d426cb21b`",
        "That retained artifact is failed evidence, not a pass",
        "prior settled-capability cache became visible before `publishTerminalIfCurrent` completed",
        "one exact public Stop transaction installed before the first registry await",
        "duplicates join continuations; every joined caller receives the identical result and snapshot only after terminal publication",
        "transaction-complete result remains cached only until successor admission clears it",
        "It introduces no second cancel, settlement, or publication authority",
        "package-only typed Stop-publication gate deterministically pauses after registry settlement and before episode publication",
        "It cannot choose an outcome, cancel, publish, or grant authority, and uses no sleeps or polling",
        "`daaa90de14158ef42bf928fc1e781275461111c731fddf5a437ac158e70f86d0`",
        "`8641f3228e3cdf87b9af94d07ee22e1800669dab2482305d30be9df7c1066858`",
        "`998c6acb5d30c7302e1c829cf9b29134f3e5c41dde2b5f8fc1ce1b1c5233930d`",
        "the publication test passed 1/1",
        "the manual suite passed 6/6 in parallel",
        "50 repeated paired `exactStop`/publication runs passed 150/150",
        "the final visible filters passed 3/3",
        "complete sequence supplied the package-gate evidence for the exact five-bound historical identity set",
        "`make docs-check`; exit 0; both documentation contracts plus 29/29 documentation/checker tests passed with no exclusions, warnings, or errors; real 9.80, user 6.55, sys 3.11 seconds",
        "`git diff --check`; exit 0 with no output or errors; real 0.03, user 0.02, sys 0.01 seconds",
        "`make quick-test`; exit 0; 678/678 tests passed with exactly 10 configured exclusions",
        "`4b3097d66504b648d8ac4ae4d449b06265086dd9895f90268ff42fd363cc3519`",
        "`make journey-test`; exit 0; 10/10 filter-selected tests passed with no explicit exclusions, warnings, or errors; real 6.15, user 5.90, sys 0.24 seconds",
        "`58e8f8552b3454097039227e02c99b39c2dcecd12cfabc6981dd66b714ce5a8c`",
        "`make strict-check`; exit 0; strict-concurrency and warnings-as-errors build, 688/688 tests with no exclusions",
        "`4693c18feeacfc7b70288253f4be3225bdcdd03daba7c2067d997a890b914bf6`",
        "a read-only progress inspection showed active compilation and did not interrupt the command",
        "`swift test --filter PlotterManualMotionEpisodeTests`; exit 0; 6/6 tests passed with no exclusions, warnings, or errors; real 1.43, user 1.15, sys 0.24 seconds",
        "`sh Scripts/check_episode_cutover.sh EA-06`; exit 0; all 26 exact scans had zero matches with no warnings or errors; real 0.35, user 0.30, sys 0.03 seconds",
        "The complete QUICK, JOURNEY, and STRICT success logs had the recorded hashes and were then removed",
        "the retained failed QUICK log above remains distinct nonpass history",
        "The next fresh critic RETASK and completed source correction superseded it at that time",
        "Before RETASK #4, the corrected frozen five-bound candidate bound tracked diff",
        "`3e9dad0f8957f913d7a3c3077f47bb6033b3cbc7bdb1f0c515cd5f665c23a68a`",
        "`66250a0edb70827b2afcc450c02ed47278f755faacc00d6d5129440bfbdc7b69`",
        "That exact earlier tree completed this serial package-gate sequence",
        "`swift test --filter PlotterManualMotionEpisodeTests`; 9/9 tests passed",
        "`79c1a3cb24ffe3b1b68cb44dcf733029cabde976f0be8f88899f369e9cccfa60`",
        "`sh Scripts/check_episode_cutover.sh EA-06`; all 26 exact scans had zero matches",
        "`b841daa4968ac8fa3bb03058663abc9e8fbcab9fd5d65487b6fb2aa786afb04e`",
        "`make docs-check`; both documentation contracts plus 29/29 documentation/checker tests passed",
        "`e9c69abd7637c66d18f6569db229df29c58d4fd1b67d981ab888164b1abc5e2e`",
        "`git diff --check`; clean with no output",
        "`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`",
        "`make quick-test`; 685/685 tests passed with exactly 10 configured exclusions",
        "`fcd13343eb389a6f4aafc79bf2dbd04c377285d8deb8980916d3791f078e43fe`",
        "`make journey-test`; 10/10 filter-selected tests passed",
        "`900a61fc976464b2c3566e63655357dbb04b2aab130c372e1dc21bb9b9dc8981`",
        "`make strict-check`; strict-concurrency/warnings-as-errors, 695/695 tests with no exclusions",
        "`05b8de2e979b9fb2993e3c181997e939ea475f83feb1acbeee28682960b0e6a1`",
        "That full pass is historical evidence only for its exact earlier identity set",
        "RETask #4 and its accepted source correction superseded it at that time",
        "The retained failed QUICK log remains explicit second-RETASK nonpass history",
        "The RETASK #4 five-bound candidate bound tracked diff",
        "`3c18f0cdd7cee68d20ba567e0a14485a939110eec99c634e06c51fe6c889bd08`",
        "`11b4277578448a692e7c969eacdb42f63146716ab59a13cb13f409182866b5bd`",
        "`0b31a505069c5b89fbe4b92e21195e0904a4deb31801ada72d4ab720456da7df`",
        "Historical validation after RETASK #4",
        "`46e903c4887afccb8a923bc24c1d15a25580f4d49e092af9cb833970bc2d2668`",
        "`165e67df305197f32573dda575d5a962b652e2994000adde1435ae64db1f2f4a`",
        "`make quick-test`; 689/689 tests passed with exactly 10 configured exclusions",
        "`b76e6eb98482633fce2b8e5fa7e77ccb0ca0f8377e9a3937c7cdf4caf5a760c7`",
        "`a67d2ebf0cc79d60b0ab7a04fa36514154f0eb8e0488ab76b3db664b2843fb46`",
        "`make strict-check`; strict-concurrency/warnings-as-errors, 699/699 tests with no exclusions",
        "`91fbd693409017c51d64e347766297b9a19fd6f5bab08a88b54b5d53db7172c0`",
        "This full pass is historical evidence only for the exact RETASK #4 identity set above",
        "RETASK #5 and its accepted source correction superseded it at that time",
        "The exact RETASK #5 five-bound candidate identified by tracked diff",
        "`0b2b2c477f8a9e0d66a25fcdd9472cfb56a71d69da21eef33a93c14131d4eda4`",
        "Historical validation after RETASK #5",
        "`swift test --filter PlotterManualMotionEpisodeTests`; 11/11 tests passed",
        "`67616011ecfe0439498f8249acc831768036ecc9c9181c2f4e9d8ae8a8e8ff9b`",
        "`sh Scripts/check_episode_cutover.sh EA-06`; all 26 exact scans had zero matches",
        "`75442517166490b5410f0bafa1cf6f532341a2e85915c46b87ba0b3f2da776d5`",
        "`make quick-test`; 692/692 tests passed with exactly 10 configured exclusions",
        "`61334548a852aedd1250a2f408d9453eff0720f3192ee506d748e5da29e28163`",
        "`ea66db8f0d68d7dff76df5e99c98733bcc3a2aed541ed8e9fd6fb88e8a6cc7da`",
        "`make strict-check`; strict-concurrency/warnings-as-errors, 702/702 tests with no exclusions",
        "`7a5b7dddad8258595c4783328cd5badcb9715bb7b065588d791ea5785af5bd0d`",
        "This full pass is historical evidence only for that exact RETASK #5 identity set",
        "RETASK #6, Option A, and the current seven-gate sequence above supersede it",
        "same critic's delta-only cited-findings recheck is closed with `CITED_RACE_CLOSED`",
        "no new or full critic was commissioned and no further critic is required or allowed",
        "Blackdog landing, canonical-`main` cleanup verification, and successor-capsule creation remain pending",
        "No attended controller, camera, motion, Pen, paper, operator-click, or observed-ink validation occurred",
        "EA-07 becomes eligible only after all seven gates pass on the exact Option A candidate",
        "the final evidence delta's affected gates are refreshed",
        "This task does not select or dispatch EA-07",
        "Affected executable contract surface: `Scripts/check_episode_contract.py`",
        "the exact current seven-gate pass, the four affected reruns",
        "Reviewed no change — `Scripts/test_episode_wave_capsule.py`",
        "Reviewed no change — `Scripts/check_episode_inventory.py`",
        "Reviewed no change — `Scripts/check_episode_cutover.sh`",
        "Reviewed no change — `Scripts/episode_wave_capsule.py`",
    ):
        if required_phrase not in normalized:
            fail(f"EA-06 completion evidence is missing: {required_phrase}")

    for required_phrase in (
        "Causal simulator environment cutover",
        "`TASK-6C2D055B`",
        "`TASK-6C2D055B-4df3ee7abec3`",
        "EA-07 landed and cleanup was verified on canonical `main` at `ac6a6688`; package EA-07 is complete while migration remains incomplete",
        "`PlotterCausalSimulatorEffectAdapter`",
        "`admitManualJog` uses the shared `PlotterIntent`/`PlotterEffect`/`PlotterEffectResult` grammar",
        "Retained Boundary, drawing, travel, and Pen work instead keeps its explicit `EpisodeAuthorityID`, returns nil `effectResult`, and fabricates neither an episode intent/effect nor a plan revision",
        "retains the exact raw simulator operation ID as immutable owner identity",
        "settles natural execution, exact Stop, cancel, shutdown, and original-owner wait through one adapter-owned result",
        "keeps the active owner reserved after lower-runtime terminal settlement until `publishTerminalOutcome` atomically caches one `PlotterCausalSimulatorOperationOutcome`",
        "A successor therefore refuses until the predecessor outcome is cached, cannot contaminate the predecessor snapshot, ink, or frame",
        "Pen ingress for manual and retained work uses that same adapter occupancy",
        "Pen ingress refuses with `.operationAlreadyActive(predecessor.id)`, returns nil `effectResult` for retained attribution, and does not call or mutate the lower Pen owner",
        "`SimulatedLearningRuntime.setPenPoseWithCausalTruth` performs the admitted Pen mutation and captures its complete causal truth in the same lower-runtime actor turn",
        "`PlotterCausalSimulatorTruthSnapshot` keeps commanded controller attribution, plant MPos and Pen pose, paper identity and ink, camera configuration/viewport/ frame publication, Vision authority, and evidence classification separate",
        "Vision truth is `notComputedBySimulator`",
        "physical evidence is false",
        "`SIMULATED — NOT PHYSICAL EVIDENCE`",
        "The production adapter is the sole admission surface through `admitManualJog`, `admitRetainedWorkflowBoundary`, `admitRetainedWorkflowDrawing`, `admitRetainedWorkflowTravel`, and `executeRetainedWorkflowPen`",
        "one package-scoped causal-operation admission to the adapter",
        "retains only lower causal truth and exact operation settlement",
        "`beginManualJog`, `beginBoundary`, and `beginDrawing` surfaces are deleted",
        "One `PlotterManualMotionRuntimeComposition` owns the manual runtime, lower simulator runtime, and causal adapter",
        "uses the exact same adapter authority for SIMULATED manual effects, Boundary, drawing, supervised travel, sparse-tip execution, and Drawing Border execution",
        "Retained workflows without a target semantic package carry an explicit retained-workflow owner with nil `effectResult` and no fabricated plan revision",
        "`OperatorWorkspace.executeSimulatedBoundaryMotion`",
        "`SimulatedWorkspaceHarness`, `makeSimulatedHarness`, `performPublicAction`",
        "cannot admit, execute, Stop, cancel, or settle an effect",
        "The original critic returned `RETASK`, not pass",
        "the focused authority regression exercises occupancy through both call paths",
        "return nil `effectResult` without synthetic intent, effect, or plan revision",
        "`PlotterCausalSimulatorTerminalPublicationGate` deterministically proves predecessor refusal, cached publication, and successor isolation without sleeps or polling",
        "The source correction also preserves one exact observation across an adapter admission refusal and its manual-runtime mapping",
        "The same critic's correction-cycle-1 delta recheck also returned `RETASK`, not pass",
        "original blocker 2 remained because Pen ingress did not yet prove shared adapter occupancy and atomic lower Pen/truth capture",
        "Bounded correction cycle 2 addressed only that remaining blocker",
        "both a retained Pen refusal with no lower Pen/truth mutation and the retained drawing refusal/successor path",
        "The same sole critic's correction-cycle-2 final verdict was exactly `UNANIMOUS PASS — no material disagreement`",
        "The bounded policy permits one critic and at most two correction/delta cycles",
        "It forbids a post-pass critic, so the exact cycle-2 pass terminates criticism",
        "the original and correction-cycle-1 RETASK verdicts remain truthful nonpass history",
        "`AdaptivePlotterApp.swift` `9541e1ab283b3974ab0050737cc5a664575b1f144453e45e6acbfd9327c4734e`",
        "`PlotterCausalSimulatorEffectAdapter.swift` `d1a8362644a6d6436e21e9876fa03e6d4df028f103f130b33f968d9c4e154365`",
        "`SimulatedLearningRuntime.swift` `e190cb015a87e8970d90ade38112cedad7a3207432b6bc7eead573ca0e749072`",
        "`OperatorWorkspace.swift` `f3c794b66825040b5aabf2dd26f49f6f2bfe4436edc7ec96f648dcc17f174366`",
        "`PlotterManualMotionComposition.swift` `552783b72e04077075730f53bc6c5c6564c72f83622cbe83b82d54041db6aa36`",
        "`ActionSurfaceTests.swift` `b7308effd860c5904ef61444ec4ae311a044b36c3761b1438e89b5c81fd985d9`",
        "`LearningWorkbenchLayoutTests.swift` `c3c2bcfef0d14bfd487292aa7879b5b9f5558a3b94d10d7727d0ed3c85e82cee`",
        "`OperatorWorkspaceAuthorityTests.swift` `9186c0f5815eac88b90c03cab4a0294d04518968a21d8c387a733a62a2e399eb`",
        "`OperatorWorkspaceLifecycleTests.swift` `1fe1ecec5890283cc6e6d0c1ad5ecad215b42a7bceb63b7c2709f3d899502cfe`",
        "`OperatorWorkspaceResetTests.swift` `56c7144c0281c99652041141fab0b47762e4b92b168cf7cfe9cb90eec821b01b`",
        "`OperatorWorkspaceSparseTipCalibrationTests.swift` `d820b1ba921ec44d46c549c84c61369e3626e8e9b5fa95f5fb35c84c61a7dbdb`",
        "`OperatorWorkspaceComputationDiagnosticsTests.swift` `b013f5eeae9d4ec02a53d24d305672028b20cf5fa0970f7933001bb1c00cf75d`",
        "`OperatorWorkspaceTestSupport.swift` `d828936b3b73a432f28f563955da78446eeee15804440703e182c7590cddbc41`",
        "`SimulatorPresentationTests.swift` `6e16a34b1bba95ce23dbd35ac2a8b0930085836c7866a0269eca576b763b7f04`",
        "`PlotterCausalEpisodeEnvironmentTests.swift` `f5f4ff6a33b082fdd40d6a3d3591e2a4d58370884b7d57ac3904803af8588a61`",
        "`DOC` | passed — `make docs-check`; both contracts plus 29/29 documentation/checker tests passed",
        "`DIFF` | passed — `git diff --check`; clean with no output",
        "`QUICK` | passed — `make quick-test`; 705/705 passed",
        "`JOURNEY` | passed — `make journey-test`; 7/7 passed",
        "`STRICT` | passed — `make strict-check`; 712/712 passed plus warning-as-error strict-concurrency build, signing, launcher, and negative-bundle checks",
        "`SIM` | passed — `swift test --filter PlotterCausalEpisodeEnvironmentTests`; 15/15 passed",
        "`AUTHORITY-FOCUSED` | passed — `swift test --filter OperatorWorkspaceAuthorityTests`; 24/24 passed; correction evidence, not an additional EA-07 package gate",
        "The first DELETE invocation is retained nonpass integration history, not a passed gate",
        "it failed only because the pending EA-01 manifest still required the removed MOD-001 seam",
        "`DELETE` | passed — `sh Scripts/check_episode_cutover.sh EA-07`; current post-cutover run passed 4/4",
        "All seven required EA-07 gates passed on its frozen integrated candidate before landing",
        "EA-07 then landed and cleanup was verified on canonical `main` at `ac6a6688`",
        "No attended physical controller, camera, motion, Pen, paper, operator-click, or observed-ink validation occurred",
        "No remote-Git action occurred",
        "Reviewed no additional change — Swift Architecture and Product Contract",
        "Reviewed no change — Document Routing (`docs/INDEX.md`)",
        "Affected mechanically — `Scripts/test_episode_wave_capsule.py`",
        "Reviewed no change — `Scripts/check_episode_documentation.sh`",
        "EA-07's successor capsule was generated from clean canonical `main` and EA-08A was selected in `TASK-5700F7F5`",
    ):
        if required_phrase not in normalized:
            fail(f"EA-07 landed evidence is missing: {required_phrase}")

    for required_phrase in (
        "Drawing draft episode cutover candidate",
        "`TASK-5700F7F5`",
        "`TASK-5700F7F5-0ad2465cded1`",
        "EA-08A is complete only in this task-local candidate; migration remains incomplete",
        "`PlotterDrawingDraftRuntime` the single source-indexed Drawing Studio draft authority",
        "`PlotterDrawingDraftSubmission` binds one `PlotterDrawingDraftRequestID`, the immutable `PlotterDrawingDraftRevision`, the complete `PlotterDrawingDraftExternalFactRevisions`, and one typed `PlotterDrawingDraftIntent`",
        "Refusal fixes the exact request, compared facts, owner, `PlotterDrawingDraftRefusalReason`, and operator remedy",
        "`PlotterDrawingPlanningAdapter` is the sole upper-layer route into the retained pure `DrawingPlanner`",
        "`planRetainedDrawingBorder` route for the explicitly retained EA-10E Border workflow",
        "planning never clips a stroke",
        "Preview is a projection, not evidence",
        "`PlotterDrawingDraftPaperPersistence` is the sole draft paper-store seam",
        "an accepted LIVE assertion is not published until save succeeds",
        "The accepted paper polygon displays only on the exact accepted frame",
        "a newer frame in the same paper/source/camera-configuration/contact-plane context remains current",
        "The retained EA-08B run/evidence boundary still owns execution, Stop, camera, Vision, archive, review, terminal no-redraw state",
        "EA-08A itself never invokes machine motion, Stop, camera, Vision, run evidence, or another physical effect",
        "`DrawingStudioAction`, direct `performDrawingStudioAction`, direct open/close/paper-confirm actions",
        "`drawingStudioDraftMutationIsAvailable`, `rebuildDrawingStudioPlan`, direct App `DrawingPlanner.plan`",
        "`drawingPresentationTestFrame` fixture",
        "`4171ee3d0a0064fb2e1fbcd7de426334395ae6a2415e51cc7421d0940a9e0b52`",
        "`459e3f065ea75e003a5cf6c5ffc8b84477c61744ee396454752dc8263f95a060`",
        "`cc5107ff6400b00033ddf2df5e026c9b48598b8321f75f05b1f0401ca22c723d`",
        "`c454b84edde46b250566d8fe14fd53a63730a6d308dffeb4e17af4729494b4f2`",
        "`eec626a6fe14ddc34bafdf198b8d428e5a99452fd627d07ab46d6a2f570d23fb`",
        "`15953c7002c624d2722bb77300e510cde9777a95ccc807983c713da914877c20`",
        "`70f534d5c49fa3e098137cfdcc571708964b72c654c01c41af9d1d98505e1690`",
        "`f59257098e76e0a23cd2269cb8689f09ac91d0f48d8c10b872a69e6880a5e063`",
        "`b26e2c1297fd1748eeb7a2e7f18882eb3116ab7fb3308844cd69384c699b4d00`",
        "`b77d9ed7102f2eea492ccf505daaa11319570460b2915b5a5e72f6e5f0fe3719`",
        "`590e0361f4230c204ec63f9b3a39fb41cc1f695d7eedc8034f7e516bee5a3323`",
        "`cc99960c7375fc0d5a045335b6e91af694cdb9563a31f11673c733c4da8aa8fc`",
        "`e48ea8f3af841a93a630ac4c075f59dbbce1e9b47263415085c662ee81788128`",
        "`3663fb00ec5627e8369e9476dd0ce35bef5ac435a7fd2fe2eebb57dfdd0caf15`",
        "`83d14a2354979cb5b51b95f6b425567137a4c77ec7be2a8ec0ef35672c9b0985`",
        "`a377b62ad2e38ee8dcb0785cd66b1b09dc7cd2990ec354a2bea6eb16cffdffe9`",
        "`dc5f0ad336dd22d119f426cfa1ff94c786cfbd8f1d62767282177e6e32745ba7`",
        "`873279f1f8b3b812dcb0db28761122732636a1e421958a50a6fb688d3e999ede`",
        "Deleted test path: `Tests/PlotterAppTests/DrawingPresentationTestSupport.swift`",
        "`DRAW-DRAFT` | passed — `swift test --filter PlotterDrawingDraftEpisodeTests`; 17/17 passed",
        "The first `DELETE` invocation failed only because the stale inventory still required the deleted `DrawingStudioAction`",
        "The sole fresh critic returned `RETASK`, not pass",
        "The same sole critic's delta-only recheck ended exactly `UNANIMOUS PASS — no material disagreement`",
        "no new/full critic was commissioned, and no post-pass critic is allowed",
        "The affected computation diagnostics passed 11/11 and `DRAW-DRAFT` passed 17/17 after that correction",
        "this gate-found local correction did not reopen or replace the closed critic",
        "The first `STRICT` run then failed at compile time on two redundant `#require` calls",
        "The accepted broad results are `QUICK` 720/720 and `STRICT` 727/727",
        "No landing or cleanup pass is inferred from the focused suites, critic pass, or broad gates",
        "Reviewed no change — Document Routing (`docs/INDEX.md`)",
        "EA-08B becomes eligible only after EA-08A lands through Blackdog",
        "This task does not select or dispatch EA-08B",
        "No remote-Git action occurred",
    ):
        if required_phrase not in normalized:
            fail(f"EA-08A candidate evidence is missing: {required_phrase}")

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
    normalized = re.sub(r"\s+", " ", evidence)
    blockers = parse_wave_admission_blockers(evidence, rows)
    selected = ordinary_wave_frontier(rows, set(blockers))
    if selected is not None:
        if selected != "EA-08B":
            fail(f"unexpected current ordinary wave frontier: {selected}")
        for phrase in (
            "Drawing draft episode cutover candidate",
            "`DRAW-DRAFT` passed 17/17",
            "EA-08B becomes eligible only after EA-08A lands through Blackdog",
            "This task does not select or dispatch EA-08B",
            "The retired `PHYSICAL-BASE` result is `failed`",
        ):
            if phrase not in normalized:
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
        "exactly one fresh-context read-only critic",
        "same critic for delta-only rechecks",
        "at most two correction/recheck cycles",
        "Never commission a post-pass, fresh, confirmation, or precautionary critic.",
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
