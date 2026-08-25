# Episode Architecture Execution Plan

Status: sole target architecture, migration sequence, and landed-work ledger

This document owns the intended episode architecture and its replacement
sequence. It does not describe current implementation. The current package and
runtime owners remain in [Swift Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md),
product invariants remain in [Product Contract](PRODUCT_CONTRACT.md), and
verified results remain in [Current Evidence](CURRENT_EVIDENCE.md).

No temporary review report, research memo, execution prompt, rejected proposal,
or competing architecture plan is authority. Accepted conclusions must be
integrated here and the source note deleted. Git history and Blackdog prompt
artifacts are history, not current design.

## Decision

Keep one AdaptivePlotter application and the existing controller, camera,
Vision, planning, and evidence authorities. Add a headless episode kernel and
runtime as internal SwiftPM targets, make Plotter their first concrete domain,
and migrate complete workflows by replacement. A cutover is incomplete until
the old action, state, guard, task, effect, and test-fixture path is deleted.

Do not create a second production application or publish a general SDK before
the kernel has survived the three representative Plotter slices, the pilot
gate, and a complete Learning Path migration. A separate SDK remains a later
packaging decision requiring a genuinely distinct second client.

## Vocabulary authority

[Episode Architecture Vocabulary](EPISODE_ARCHITECTURE_VOCABULARY.md) is the
sole definition source for target names and relationships. This plan uses those
exact names and does not restate or alias them. Exact current-code identifiers
are allowed only when describing as-built owners or their named deletion.

## Target packages

```text
EpisodeCore
  EpisodeGoal, EpisodeDefinition<Intent>, EpisodeManifest<DomainManifest>,
  IntentDecision,
  EpisodeEvent, reducer and EpisodeJournal schemas
  Foundation only; no Plotter, device, persistence, or UI imports

EpisodeRuntime -> EpisodeCore
  serialized store, journal/replay, internal EffectPermit
  effect lanes, operation registry, cancellation and lifetime settlement

PlotterEpisodeModel -> EpisodeCore + PlotterModel
  Plotter bindings for definition/manifest plus intent/state/event/effect/result
  scoped semantic rules, reducer, evidence/assessment values, projections

PlotterEpisodeRuntime
  -> EpisodeRuntime + PlotterEpisodeModel + PlotterRuntime
  LIVE and SIMULATED capability providers and effect runners
  controller/camera recording, replay, and artifact adapters

PlotterUI -> PlotterEpisodeModel
  immutable projections and one typed intent sink; no effect ports

PlotterApp
  composition root during and after migration
```

`PlotterModel`, `PlotterRuntime`, and `PlotterTestSupport` remain current
authorities until an explicit work package moves a responsibility. Temporary
bridges must name their deletion package and may not become stable APIs.

## Central semantic ingress

Exactly one ingress exists for each semantic intent throughout migration.
Migrated `PlotterIntent` cases enter only through
`PlotterIntentGateway.submit`. Unmigrated intent cases retain only the current
owner declared by `EA-01`; no intent may be submitted through both. `EA-11C`
makes the gateway the globally exclusive effect-bearing/domain-mutation ingress;
`GATE-02` only verifies that landed fact. Local pane, window, and viewport-only state remains in small UI
reducers unless it changes evidence or domain authority.

`PlotterIntentGateway` is a thin submission façade. It owns no feature rules,
reducer state, evidence acceptance, operation lanes, tasks, device ports, or
persistence. Its only responsibilities are request identity, current-fact
acquisition, reevaluation, and delegation to the store/runtime contracts below.

`PlotterIntent` is an exhaustive root sum with scoped cases such as session,
observation, point selection, manual motion, drawing, Learning, and evidence.
The root evaluator delegates to pure feature rule sets and has no `default`.
Rule sets may evaluate named semantic requirements. They cannot mutate state,
call ports, issue execution permission, construct effects, or accept evidence.

The normal submission order is:

1. reserve request identity before suspension;
2. acquire versioned `CapabilityFact` values;
3. recheck state and manifest revisions;
4. produce the scoped `IntentDecision`;
5. append a typed accepted or refused event;
6. reduce the committed `EpisodeEvent` into state and typed effects;
7. register effect identity and lane, then mint its internal one-shot
   `EffectPermit`;
8. record effect start before external invocation;
9. execute outside `MainActor` through the existing environment owner;
10. validate the `EffectResult` identity and revisions, commit the corresponding
    `EpisodeEvent`, and reduce it.

Reduction of any committed `EpisodeEvent` may emit zero or more typed successor
effects. Each successor records the triggering event as causation and repeats
steps 7–10. A multi-effect workflow therefore advances through committed result
events; it never uses a callback mutation or manufactures another intent.

The UI uses the same pure evaluator to display `IntentAvailability`, but submission
always reevaluates current state. Presentation values can never be supplied as
authorization.

## Operation ownership and safety priority

For each migrated effect, one `PlotterOperationRegistry` exclusively owns
application-level effect identity, lanes, `StopCapability`, cancellation
request, original task/handle, and terminal disposition. Every unmigrated effect
retains exactly one current operation owner declared by `EA-01`; a logical
operation can never be registered in both. `EA-11C` makes the registry the
globally exclusive application effect/Stop/cancellation owner; `GATE-02` only
verifies that landed fact.
It supports at least one exclusive machine lane, one exclusive
exact-workflow capture/Vision lane, bounded background analysis, and serialized
durable append where required. `RunInterpreter` remains the logical machine
operation owner below it.

Cancellation is request, exact-owner validation, one latched cancel request,
owner observation, original-owner await, terminal disposition, and capability
retirement. A stale capability cannot stop a successor.

Normal new effects require committed accepted/start history before external
invocation. Stop and shutdown are a narrow priority path because persistence
must never delay reduction of physical activity. That path may only close
admission, cancel, or settle existing work; it latches the exact owner before
suspension, issues cancellation without waiting for journal I/O, and can never
start or repeat a physical effect. Journal failure degrades trace completeness
but cannot block Stop.

## Guard ownership

Every guard has exactly one owner within its layer:

| Layer | Owner | Examples |
| --- | --- | --- |
| semantic workflow | scoped evaluator | phase, episode owner, prerequisite, no-redraw, plan revision |
| runtime coordination | store and operation registry | lane occupancy, deduplication, cancellation, stale result, terminality |
| fresh physical safety | `MachineController` and `RunInterpreter` | connection, Alarm/Pn/Idle/MPos, Motion, feed, pen, wire settlement |
| evidence and provenance | existing typed evidence authorities | frame/config/hash, pose, applicability, algorithm/model revision |
| presentation | projector or local UI reducer | layout, label, visibility, exact-frame display |
| lifetime priority | runtime Stop/shutdown route | close admission, cancel/await owner, reject stale commits |

Semantic rules consume versioned device/evidence facts. They do not recreate
the controller's safety algorithm or the evidence authority's applicability
algorithm. Rechecking across layers is intentional only when the question and
owner differ: current semantic readiness versus fresh safety immediately before
I/O.

## Non-negotiable observability

Observability is product behavior, not optional debug instrumentation.

1. Every refused `PlotterIntent` exposes a typed requirement ID, authoritative
   owner, compared source/state revisions, concise operator remedy, and the
   intent request identity. No effect-bearing control silently ignores a click.
2. Every active effect exposes episode/intent/effect identity, lane, environment,
   owning subsystem, phase, start time, last attributable progress time, the
   result currently awaited, declared deadline when one exists, cancellation
   availability and phase, and eventual terminal disposition.
3. Progress is evidence of an attributable `EpisodeEvent`, not a fabricated heartbeat.
   The UI distinguishes `waiting`, `progressing`, `cancelling`, `settling`,
   `suspectedStall`, and terminal state without claiming a deadlock merely from
   elapsed time.
4. Every reachable nonterminal state has at least one admissible intent, an
   explicitly owned wait/progress state, an exact refusal with remedy, or an
   owner-bound Stop/cancel. A silent actionless state fails tests.
5. Runtime state revision and UI projection revision/timestamps are visible and
   comparable. Runtime progress with a stale UI projection identifies a
   presentation/MainActor problem rather than a controller deadlock.
6. Journal, controller transcript, camera lifecycle, and structured diagnostic
   recording run outside `MainActor`. If SwiftUI is starved, the last durable
   runtime state remains externally inspectable.
7. The operator can export one bounded incident package containing the episode
   manifest/journal, controller transcript completeness, camera/frame artifact
   references, observations, evidence decisions, assessment, current owners,
   UI/runtime revisions, and unresolved ambiguity. Sensitive frame retention is
   explicit and bounded.
8. Recording failure is visible and degrades diagnostic completeness, but it
   never authorizes work, changes controller safety, manufactures evidence, or
   delays Stop/shutdown.

The primary UI should show the current reason, owner, progress, remedy, and Stop
without forcing the operator through a developer console. A detailed inspector
and export may carry identifiers and revisions. Structured logs and the journal
remain the fallback when the UI itself cannot render.

## Replay and simulation

The episode manifest pins definition, schemas, evaluator/reducer/build revisions,
seed, and referenced drawing, calibration, paper, camera, controller, and model
artifacts. Each event records sequence, actor/origin, causation/correlation,
intent/effect IDs, pre/post revisions, typed payload, artifact references, and a
canonical post-state digest.

Replay begins from the manifest, folds the production reducer, verifies hashes
and revisions, recomputes projection/`IntentAvailability`, and executes no effect. Every
truncated prefix is tested. A trace ending after physical effect start but before
settlement becomes possible physical effect and is never automatically resumed.

`RecordingMachineLink` records invocation and completion separately for open,
close, discard, raw writes, and timed reads, including exact chunks, parameters,
typed errors, partial counts, monotonic offsets, integrity, and completeness.
`ReplayMachineLink` supports exact replay and causality-preserving perturbation
of legal fragmentation, delay, timeout, and cancellation points.

Camera recording binds lifecycle events separately from content-addressed exact
frame artifacts. Retention is explicitly evidence-only, bounded incident ring,
or bounded diagnostic capture. Missing frame bytes remain visible and cannot
pretend to support Vision replay.

LIVE and SIMULATED implement the same effect/result vocabulary while preserving
different provenance and evidence classes. The simulator separates commanded
controller state, plant/pen truth, paper/ink truth, camera observation, and
Vision measurement. Simulation can never satisfy LIVE physical evidence.

## Same-landing deletion rule

Every migrated slice must remove or explicitly prove a remaining unmigrated
consumer for each of the following:

- old root intent/action case and dispatcher branch;
- old `...UnavailableReason` and handler guard for migrated semantics;
- old mutable workflow/workspace field;
- old task, generation, latch, and Stop/cancel owner;
- old direct controller/camera/Vision/persistence port call;
- old LIVE/SIMULATED workflow branch;
- old high-level fixture or polling helper after its last consumer;
- obsolete current documentation and tests.

A new path working beside the old path is not migration. Shadow comparison may
observe and report, but may issue no effect or authoritative durable write.

## Structural enforcement

- migrated UI targets cannot import effect runtime or see raw effect ports;
- each migrated intent has the gateway as its only public effect-bearing/domain
  mutation entry; `EA-11C` establishes global exclusivity and `GATE-02` verifies it;
- root intent switches are exhaustive without `default`;
- requirement IDs are typed and map to one declared owner;
- evaluators cannot emit effects or issue runtime permission;
- the reducer is the sole effect producer;
- the registry is the sole application effect/Stop/cancellation owner for each
  migrated effect; `EA-11C` establishes global exclusivity and `GATE-02` verifies it;
- results require matching episode/intent/effect/environment revisions;
- UI availability cannot be resubmitted as authority;
- episode layers add no `Any`, arbitrary effect closures, reflected/string action
  registries, or `@unchecked Sendable` escape hatches;
- each cutover adds deleted-symbol, forbidden-import, and direct-port-call checks.

## Known prerequisite corrections

Commit `bab0900` deliberately made accepted Drawing Boundary geometry available
to Drawing Studio, but introduced two implementation assumptions that must not
enter the episode runtime:

1. `OperatorWorkspace.inferredDrawingStudioPixel` may extrapolate the current
   affine mapping outside `TipCameraRegistration.applicabilityRectangle` for
   diagnostic presentation. That projection is not attributable evidence. An
   evidence-producing path must refuse it, classify it as typed non-attributable
   diagnostic output, or consume a newly validated evidence-authority revision
   whose applicability actually covers the point.
2. `ContinuousMachineCoordinateTolerance` made one 0.5 mm value answer both
   Euclidean controller-settlement and axis-expanded drawing-region containment
   questions. `FIX-00` deleted that shared owner and replaced it with separately
   typed metrics and revisions: 0.5 mm Euclidean controller settlement and a
   1e-9 mm axis-containment epsilon for accepted-Boundary drawing geometry.

`FIX-00` completed the settlement/containment policy split in `TASK-1B5992CF`.
`FIX-01` still owns outside-applicability evidence attribution and must complete
before the attended baseline. Both preserve the current Boundary/Border
distinction and durable overlay decoding without preserving either incorrect
semantic.

Camera-frame names that actually identify exact frames remain valid. Durable
`calibratedDrawableRegion`, `localPreLineBaseline`, `linePlan`, `lineExecution`,
and `postLineFrame` wire values may remain only inside versioned decode adapters
with proved callers. Active emission and active owners move to canonical
episode/Border vocabulary in `EA-10E`; parallel alias types are forbidden.

## EA-01 current-source inventory

This is the exhaustive DOC-01 source characterization. Each stable ID names one
bounded current seam or family whose members share one current owner, one
disposition, one cutover package, and one fixed focused command. `retain` means
the lower-level owner survives without duplication; `adapt` means that owner
survives but its caller or adapter moves; `delete` means the named current seam
must be absent in the cutover landing. A row never authorizes work outside its
named package.

The `INVENTORY` gate extracts every case from the four current action enums,
every named `OperatorWorkspace` unavailable-reason guard, every injected action
port, every declared `Task` owner in the named application/runtime owners, and
every direct SwiftUI `workspace`/`actionWorkspace` consumer. It requires exact
set equality with the seams below, so a new or omitted member fails rather than
falling into a generic remainder.

| Inventory ID | Category | Current source seams | Current owner and behavior | Disposition | Cutover | Focused command |
| --- | --- | --- | --- | --- | --- | --- |
| INT-001 | semantic-intent | `OperatorWorkspace.performApplicationStartup`<br>`OperatorWorkspace.shutdown` | application delegate plus `OperatorWorkspace`; policy startup and bounded shutdown | delete | `EA-11C` | `swift test --filter PlotterEpisodeCompositionTests` |
| INT-002 | semantic-intent | `OperatorWorkspace.selectSerialDevice`<br>`OperatorWorkspace.performControllerConnectionAction`<br>`OperatorWorkspace.connectSelectedController`<br>`OperatorWorkspace.disconnectMachineSession` | `OperatorWorkspace`; controller selection and session connect/disconnect requests | delete | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| INT-003 | semantic-intent | `OperatorWorkspace.requestPassiveProbe`<br>`OperatorWorkspace.clearControllerAlarm`<br>`OperatorWorkspace.performMotionAuthorizationAction` | `OperatorWorkspace`; passive probe, explicit alarm clear, and session Motion request | delete | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| INT-004 | semantic-intent | `OperatorWorkspace.requestJog`<br>`OperatorWorkspace.stopManualMotion` | `OperatorWorkspace`; manual jog/drawing-stroke request and exact Stop | delete | `EA-06` | `swift test --filter PlotterManualMotionEpisodeTests` |
| INT-005 | semantic-intent | `OperatorWorkspace.requestPenActuation` | `OperatorWorkspace`; direct manual pen actuation | delete | `EA-06` | `swift test --filter PlotterManualMotionEpisodeTests` |
| INT-006 | semantic-intent | `OperatorWorkspace.selectToolContactPoint` | `OperatorWorkspace`; exact-frame cap/tip point selection and evidence routing | delete | `EA-04` | `swift test --filter PlotterPointSelectionEpisodeTests` |
| INT-007 | semantic-intent | `OperatorWorkspace.toggleLearningMode` | `OperatorWorkspace`; Learning on/off admission and active point-continuation cancellation | delete | `EA-04` | `swift test --filter PlotterPointSelectionEpisodeTests` |
| INT-008 | semantic-intent | `DrawingStudioAction.selectCatalogItem`<br>`DrawingStudioAction.setParameter`<br>`DrawingStudioAction.placeAtCameraPoint`<br>`DrawingStudioAction.setUniformScale`<br>`DrawingStudioAction.setRotationDegrees`<br>`DrawingStudioAction.centerInDrawableRegion`<br>`CompletedComparisonReviewAction.openDrawingStudio` | `OperatorWorkspace.performDrawingStudioAction`; draft, placement, parameter, planning, and open/new-plan semantics | delete | `EA-08A` | `swift test --filter PlotterDrawingDraftEpisodeTests` |
| INT-009 | semantic-intent | `DrawingStudioAction.run`<br>`DrawingStudioAction.stop`<br>`DrawingStudioAction.reviewRun`<br>`DrawingStudioAction.resumeLivePreview`<br>`DrawingStudioAction.newRun`<br>`CompletedComparisonReviewAction.reviewComparison`<br>`CompletedComparisonReviewAction.resumeLivePreview` | `OperatorWorkspace`; Drawing Studio execute/Stop/observe/review/no-redraw lifecycle | delete | `EA-08B` | `swift test --filter PlotterDrawingRunEpisodeTests` |
| INT-010 | semantic-intent | `ExerciseActionKind.setPenSetpoint`<br>`OperatorWorkspace.beginPenInteraction` | `OperatorWorkspace`; Pen Interaction attempt and value-bearing Up/Down semantics | delete | `EA-10A` | `swift test --filter PlotterPenInteractionEpisodeTests` |
| INT-011 | semantic-intent | `ExerciseActionKind.redoBoundary`<br>`ExerciseActionKind.recordAnotherBoundaryAttempt`<br>`ExerciseActionKind.selectDirection`<br>`ExerciseActionKind.moveToEstimatedCenter`<br>`OperatorWorkspace.beginPairedBoundarySide` | `OperatorWorkspace`; Drawing Boundary acquisition, renewal, aggregation, and center arrival | delete | `EA-10B` | `swift test --filter PlotterBoundaryEpisodeTests` |
| INT-012 | semantic-intent | `ExerciseActionKind.runCameraCalibrationAndBuildProposal`<br>`ExerciseActionKind.acceptCameraCalibrationProposal`<br>`ExerciseActionKind.rejectCameraCalibrationProposal` | `OperatorWorkspace`; camera-from-cap five-position execution/proposal/acceptance | delete | `EA-10C` | `swift test --filter PlotterCameraCalibrationEpisodeTests` |
| INT-013 | semantic-intent | `ExerciseActionKind.drawFourCornerTipCircles`<br>`ExerciseActionKind.undoLastSparseTipClick`<br>`ExerciseActionKind.clearSparseTipClicks`<br>`ExerciseActionKind.revalidateTipCalibrationCheckpoint`<br>`ExerciseActionKind.acceptTipCalibrationProposal`<br>`ExerciseActionKind.rejectTipCalibrationProposal`<br>`ExerciseActionKind.retryTipCalibrationCommit` | `OperatorWorkspace` plus `SparseTipCalibrationCoordinator`; pen-tip physical batch, same-frame clicks, proposal, and commit | delete | `EA-10D` | `swift test --filter PlotterTipCalibrationEpisodeTests` |
| INT-014 | semantic-intent | `OperatorWorkspace.runObservedDrawingTrial` | `OperatorWorkspace`; Drawing Border plan/capture/execute/observe/compare chain | delete | `EA-10E` | `swift test --filter PlotterBorderValidationEpisodeTests` |
| INT-015 | semantic-intent | `ExerciseActionKind.useSavedTraining`<br>`ExerciseActionKind.startNewLearning`<br>`ExerciseActionKind.restart`<br>`ExerciseActionKind.redoThisStep`<br>`ExerciseActionKind.recordAnotherAttempt`<br>`ExerciseActionKind.paperReplaced`<br>`OperatorWorkspace.performResetAllLearning` | `OperatorWorkspace`; Saved Learning choice, replacement attempts, paper lifecycle, and reset | delete | `EA-10F` | `swift test --filter PlotterArtifactResetEpisodeTests` |
| INT-016 | semantic-intent | `OperatorWorkspace.announceAdvisory` | `OperatorWorkspace`; application-level advisory speech request/result | delete | `EA-10G` | `swift test --filter PlotterSpeechEffectEpisodeTests` |
| INT-017 | semantic-intent | `OperatorWorkspace.switchFrameMode`<br>`OperatorWorkspace.selectAndStartCamera`<br>`OperatorWorkspace.setVisionAnalysisCadence`<br>`OperatorWorkspace.setVideoAnalysisRegion`<br>`OperatorWorkspace.setOverlay` | `OperatorWorkspace`; observation source, camera selection, cadence, region, and overlay configuration | delete | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| INT-018 | semantic-intent | `ExerciseActionKind.start`<br>`ExerciseActionKind.choice`<br>`ExerciseActionKind.cancel`<br>`ExerciseActionKind.stop`<br>`OperatorWorkspace.performExerciseAction` | `OperatorWorkspace`; generic Learning action dispatcher and task owner after all feature cases move | delete | `EA-11C` | `swift test --filter PlotterEpisodeCompositionTests` |
| INT-019 | semantic-intent | `VideoSettingsVisibilityAction.show`<br>`VideoSettingsVisibilityAction.hide` | `WorkbenchLayoutState`; window-local Video Settings visibility only | retain | `EA-09` | `swift test --filter PlotterEpisodeUIActionabilityTests` |
| GRD-001 | guard | `ContinuousMachineCoordinateTolerance.minimumMM` | shared model/runtime constant currently answers settlement and containment | delete | `FIX-00` | `swift test --filter CoordinateAcceptancePolicyTests` |
| GRD-002 | guard | `OperatorWorkspace.inferredDrawingStudioPixel` | `OperatorWorkspace`; currently permits diagnostic extrapolation to feed attribution | delete | `FIX-01` | `swift test --filter TipApplicabilityEvidencePolicyTests` |
| GRD-003 | guard | `OperatorWorkspace.learningModeChangeUnavailableReason` | `OperatorWorkspace`; prevents Learning Off while current work/continuation owns settlement | delete | `EA-04` | `swift test --filter PlotterPointSelectionEpisodeTests` |
| GRD-004 | guard | `OperatorWorkspace.directCarriageMotionUnavailableReason`<br>`OperatorWorkspace.directManualMotionUnavailableReason`<br>`OperatorWorkspace.directMotionUnavailableReason`<br>`OperatorWorkspace.motionUnavailableReason`<br>`OperatorWorkspace.ordinaryRelativeJogUnavailableReason`<br>`OperatorWorkspace.penUnavailableReason` | `OperatorWorkspace`; duplicated manual semantic admission around controller facts | delete | `EA-06` | `swift test --filter PlotterManualMotionEpisodeTests` |
| GRD-005 | guard | `OperatorWorkspace.simulatedManualMotionUnavailableReason` | `OperatorWorkspace`; separate SIMULATED manual branch admission | delete | `EA-07` | `swift test --filter PlotterCausalEpisodeEnvironmentTests` |
| GRD-006 | guard | `OperatorWorkspace.drawingStudioPanelChangeUnavailableReason` | `OperatorWorkspace`; draft/panel mutation admission | delete | `EA-08A` | `swift test --filter PlotterDrawingDraftEpisodeTests` |
| GRD-007 | guard | `OperatorWorkspace.drawingStudioRunUnavailableReason`<br>`OperatorWorkspace.paperManagementUnavailableReason` | `OperatorWorkspace`; run/no-redraw/paper-change admission | delete | `EA-08B` | `swift test --filter PlotterDrawingRunEpisodeTests` |
| GRD-008 | guard | `OperatorWorkspace.penInteractionSequenceUnavailableReason` | `OperatorWorkspace`; Pen Interaction prerequisite guard | delete | `EA-10A` | `swift test --filter PlotterPenInteractionEpisodeTests` |
| GRD-009 | guard | `OperatorWorkspace.drawingTrialActionUnavailableReason` | `OperatorWorkspace`; Drawing Border step/action admission | delete | `EA-10E` | `swift test --filter PlotterBorderValidationEpisodeTests` |
| GRD-010 | guard | `OperatorWorkspace.learningVacateUnavailableReason` | `OperatorWorkspace`; reset/rewind/current-owner guard | delete | `EA-10F` | `swift test --filter PlotterArtifactResetEpisodeTests` |
| GRD-011 | guard | `OperatorWorkspace.controllerAlarmClearActionUnavailableReason`<br>`OperatorWorkspace.controllerConnectionActionUnavailableReason`<br>`OperatorWorkspace.controllerPoseRevalidationUnavailableReason`<br>`OperatorWorkspace.controllerSelectionUnavailableReason`<br>`OperatorWorkspace.motionAuthorizationActionUnavailableReason`<br>`OperatorWorkspace.motionGuardActivationUnavailableReason`<br>`OperatorWorkspace.passiveProbeUnavailableReason` | `OperatorWorkspace`; duplicated controller-session readiness guards | delete | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| GRD-012 | guard | `OperatorWorkspace.frameModeSwitchUnavailableReason` | `OperatorWorkspace`; observation source/configuration change guard | delete | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| GRD-013 | guard | `OperatorWorkspace.discoveryStartUnavailableReason`<br>`OperatorWorkspace.learningCarriageMotionUnavailableReason`<br>`OperatorWorkspace.learningConnectionAndMotionUnavailableReason`<br>`OperatorWorkspace.learningExerciseMotionUnavailableReason` | `OperatorWorkspace`; generic residual Learning guards after feature cutovers | delete | `EA-11C` | `swift test --filter PlotterEpisodeCompositionTests` |
| OWN-001 | authority-owner | `OperatorWorkspace` | single observable composition owner, semantic router, workflow state, and artifact commits | delete | `EA-11C` | `swift test --filter PlotterEpisodeCompositionTests` |
| OWN-002 | authority-owner | `MachineController` | selected serial transport, parsing, fresh safety, serialization, settlement, ambiguity | retain | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| OWN-003 | authority-owner | `RunInterpreter` | logical machine operation, plan execution, checkpoints, lower-level cancel settlement | retain | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| OWN-004 | authority-owner | `PersistentMachineSession` | application composition of controller, interpreter, and bounded ledger | adapt | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| OWN-005 | authority-owner | `CameraCapture` | camera discovery, selection, lifecycle, exact frames, preview holds | retain | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| OWN-006 | authority-owner | `CameraSourceSession` | automatic-analysis configuration and exact-workflow Vision leases | retain | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| OWN-007 | authority-owner | `VisionWorker` | typed measurement and diagnostic computation | retain | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| OWN-008 | authority-owner | `PlotterSceneAnalysisPipeline` | newest-only ambient analysis state and progress | adapt | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| OWN-009 | authority-owner | `LearningPathProjector`<br>`LearningPathProjectionSnapshot` | pure current Learning presentation over copied workspace facts | delete | `EA-09` | `swift test --filter PlotterEpisodeUIActionabilityTests` |
| OWN-010 | authority-owner | `WorkbenchLayoutState`<br>`ActionSurfaceViewportState` | window/pane/viewport-local presentation state | retain | `EA-09` | `swift test --filter PlotterEpisodeUIActionabilityTests` |
| OWN-011 | authority-owner | `LearningSessionState` | current LIVE/SIMULATED workflow/artifact state aggregate | delete | `EA-11C` | `swift test --filter PlotterEpisodeCompositionTests` |
| OWN-012 | authority-owner | `SparseTipCalibrationCoordinator` | current sparse physical-batch and proposal state machine | delete | `EA-10D` | `swift test --filter PlotterTipCalibrationEpisodeTests` |
| OWN-013 | authority-owner | `DrawingPlanner` | deterministic geometry admission and content-addressed execution plans | retain | `EA-08A` | `swift test --filter PlotterDrawingDraftEpisodeTests` |
| OWN-014 | authority-owner | `TipCalibrationAuthority`<br>`TipCameraRegistration` | evidence validation, construction, applicability, and checkpoint semantics | retain | `EA-10D` | `swift test --filter PlotterTipCalibrationEpisodeTests` |
| OWN-015 | authority-owner | `DrawingRunEvidenceArchive` | checksummed append-only drawing-run evidence value and append rules | retain | `EA-08B` | `swift test --filter PlotterDrawingRunEpisodeTests` |
| OWN-016 | authority-owner | `SimulatedLearningRuntime` | nonphysical controller/plant/pen/paper/camera causal truth | adapt | `EA-07` | `swift test --filter PlotterCausalEpisodeEnvironmentTests` |
| OWN-017 | authority-owner | `NativeSpeechAnnouncer` | AVFoundation synthesis, identity queue, timeout, shutdown cancellation | retain | `EA-10G` | `swift test --filter PlotterSpeechEffectEpisodeTests` |
| OWN-018 | authority-owner | `RunLedger` | low-level ordered SQLite device/workflow diagnostics | adapt | `EA-05A` | `swift test --filter PlotterRecordingStoreTests` |
| OWN-019 | authority-owner | `StartupFrameRecorder` | unbound file recorder with test-only consumers | delete | `EA-05A` | `swift test --filter PlotterRecordingStoreTests` |
| OWN-020 | authority-owner | `OverlayResultChannels`<br>`OverlayPresentationComposer` | source-separated results and pure exact-frame overlay composition | adapt | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| OWN-021 | authority-owner | `PaperCoverageValidationContext` | exact-frame/paper/source coverage evidence decision | retain | `EA-08A` | `swift test --filter PlotterDrawingDraftEpisodeTests` |
| OWN-022 | authority-owner | `AcceptedLearningPathCheckpoint` | atomic durable accepted Learning prefix value and validation | adapt | `EA-10F` | `swift test --filter PlotterArtifactResetEpisodeTests` |
| PRT-001 | direct-port | `MachineActions.select`<br>`MachineActions.snapshot`<br>`MachineActions.requestPassiveProbe`<br>`MachineActions.requestControllerAlarmClear`<br>`MachineActions.activateMotionGuard`<br>`MachineActions.deactivateMotionGuard`<br>`MachineActions.beginRelativeJog`<br>`MachineActions.beginDrawingStroke`<br>`MachineActions.beginDrawingPlan`<br>`MachineActions.requestPenActuation`<br>`MachineActions.beginBoundaryMotion`<br>`MachineActions.requestJogCancel`<br>`MachineActions.disconnect` | `OperatorWorkspace.MachineActions`; arbitrary closure façade over `PersistentMachineSession` | delete | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| PRT-002 | direct-port | `CameraActions.discover`<br>`CameraActions.select`<br>`CameraActions.start`<br>`CameraActions.stop`<br>`CameraActions.restart`<br>`CameraActions.snapshot`<br>`CameraActions.frames`<br>`CameraActions.inspectWorkflowScene`<br>`CameraActions.captureFrame`<br>`CameraActions.captureStableWorkflowCap`<br>`CameraActions.setSceneAnalysisRegion`<br>`CameraActions.setPenCapColor`<br>`CameraActions.setAutomaticInspection`<br>`CameraActions.analysisUpdates`<br>`CameraActions.visionDiagnostics`<br>`CameraActions.observePlannedDrawingInk` | `OperatorWorkspace.CameraActions`; arbitrary closure façade over camera/session/Vision owners | delete | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| PRT-003 | direct-port | `AnnouncementActions.announce`<br>`AnnouncementActions.cancelForShutdown` | `OperatorWorkspace.AnnouncementActions`; application speech effect seam | delete | `EA-10G` | `swift test --filter PlotterSpeechEffectEpisodeTests` |
| PRT-004 | direct-port | `WorkflowTelemetryActions.record` | `OperatorWorkspace.WorkflowTelemetryActions`; diagnostic append seam | adapt | `EA-05A` | `swift test --filter PlotterRecordingStoreTests` |
| PRT-005 | direct-port | `AcceptedLearningPathCheckpointActions.load`<br>`AcceptedLearningPathCheckpointActions.save`<br>`AcceptedLearningPathCheckpointActions.clear` | `OperatorWorkspace.AcceptedLearningPathCheckpointActions`; LIVE-only durable checkpoint seam | delete | `EA-10F` | `swift test --filter PlotterArtifactResetEpisodeTests` |
| PRT-006 | direct-port | `DrawingEvidenceActions.load`<br>`DrawingEvidenceActions.append` | `OperatorWorkspace.DrawingEvidenceActions`; drawing-run archive seam | delete | `EA-08B` | `swift test --filter PlotterDrawingRunEpisodeTests` |
| PRT-007 | direct-port | `PaperCoverageActions.load`<br>`PaperCoverageActions.save`<br>`PaperCoverageActions.clear` | `OperatorWorkspace.PaperCoverageActions`; paper coverage persistence seam | delete | `EA-08A` | `swift test --filter PlotterDrawingDraftEpisodeTests` |
| MOD-001 | environment-branch | `OperatorWorkspace.frameMode`<br>`OperatorWorkspace.requestSimulatedRelativeJog`<br>`OperatorWorkspace.executeSimulatedBoundaryMotion` | `OperatorWorkspace`; direct LIVE/SIMULATED effect branches | delete | `EA-07` | `swift test --filter PlotterCausalEpisodeEnvironmentTests` |
| MOD-002 | environment-branch | `OperatorWorkspace.liveLearningSession`<br>`OperatorWorkspace.simulatedLearningSession`<br>`OperatorWorkspace.activeLearningSession` | `OperatorWorkspace`; parallel current workflow state selected by source | delete | `EA-11C` | `swift test --filter PlotterEpisodeCompositionTests` |
| MOD-003 | environment-branch | `SimulatedLearningRuntime.beginManualJog`<br>`SimulatedLearningRuntime.beginBoundary`<br>`SimulatedLearningRuntime.beginDrawing` | `SimulatedLearningRuntime`; effect-capable nonphysical environment API | adapt | `EA-07` | `swift test --filter PlotterCausalEpisodeEnvironmentTests` |
| TSK-001 | task-cancel-owner | `OperatorWorkspace.penSetpointActuationTask` | `OperatorWorkspace`; current Pen setpoint task | delete | `EA-10A` | `swift test --filter PlotterPenInteractionEpisodeTests` |
| TSK-002 | task-cancel-owner | `OperatorWorkspace.activeLearningActionTask`<br>`OperatorWorkspace.activeStoppableOperation`<br>`OperatorWorkspace.activeHardwareIntentCount`<br>`OperatorWorkspace.intentDrainWaiters` | `OperatorWorkspace`; generic action task, Stop owner, and shutdown drain | delete | `EA-11C` | `swift test --filter PlotterEpisodeCompositionTests` |
| TSK-003 | task-cancel-owner | `OperatorWorkspace.penCapAcceptedClickContinuationTask`<br>`OperatorWorkspace.penCapVisionReconfigurationTask` | `OperatorWorkspace`; exact point-selection continuation/reconfiguration tasks | delete | `EA-04` | `swift test --filter PlotterPointSelectionEpisodeTests` |
| TSK-004 | task-cancel-owner | `OperatorWorkspace.boundaryMotionTask` | `OperatorWorkspace`; Boundary workflow task | delete | `EA-10B` | `swift test --filter PlotterBoundaryEpisodeTests` |
| TSK-005 | task-cancel-owner | `OperatorWorkspace.currentCameraCalibrationTask` | `OperatorWorkspace`; camera-calibration workflow task | delete | `EA-10C` | `swift test --filter PlotterCameraCalibrationEpisodeTests` |
| TSK-006 | task-cancel-owner | `OperatorWorkspace.savedTrainingComparisonTask` | `OperatorWorkspace`; Saved Learning comparison task | delete | `EA-10F` | `swift test --filter PlotterArtifactResetEpisodeTests` |
| TSK-007 | task-cancel-owner | `OperatorWorkspace.frameTask`<br>`OperatorWorkspace.visionUpdateTask`<br>`CameraSourceSession.automaticInspectionFrameTask` | workspace/session ambient frame and Vision subscriptions | delete | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| TSK-008 | task-cancel-owner | `AdaptivePlotterApplicationDelegate.terminationTask`<br>`AdaptivePlotterApplicationDelegate.terminationDeadlineTask` | application delegate; shutdown task/deadline | adapt | `EA-11C` | `swift test --filter PlotterEpisodeCompositionTests` |
| TSK-009 | task-cancel-owner | `CameraCapture.eventConsumer` | `CameraCapture`; driver-event owner under camera lifecycle | retain | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| TSK-010 | task-cancel-owner | `PlotterSceneAnalysisPipeline.drainTask` | scene pipeline; newest-only analysis task owner | retain | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| TSK-011 | task-cancel-owner | `MachineController.ledgerWriteTail` | `MachineController`; ordered nonblocking ledger append tail | adapt | `EA-05A` | `swift test --filter PlotterRecordingStoreTests` |
| TSK-012 | task-cancel-owner | `NativeSpeechAnnouncer.timeoutTask` | `NativeSpeechAnnouncer`; lower-level synthesis timeout | retain | `EA-10G` | `swift test --filter PlotterSpeechEffectEpisodeTests` |
| TSK-013 | task-cancel-owner | `RunInterpreter.cancelTask` | `RunInterpreter`; lower-level jog/plan cancellation settlement | retain | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| PER-001 | persistence-path | `AdaptivePlotter.selectedSerialDeviceIdentifier` | `OperatorWorkspace` default closures; selected serial preference | delete | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| PER-002 | persistence-path | `AdaptivePlotter.penCapAppearanceSelection`<br>`AdaptivePlotter.userSceneOverlays` | `OperatorWorkspace` default closures; recognition input and overlay preference | delete | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| PER-003 | persistence-path | `AcceptedArtifactCheckpointComposition`<br>`AcceptedLearningPathCheckpointStore` | checkpoint composition; canonical atomic prefix plus migration | adapt | `EA-10F` | `swift test --filter PlotterArtifactResetEpisodeTests` |
| PER-004 | persistence-path | `AcceptedArtifactCheckpointStore`<br>`AcceptedTipCalibrationCheckpointStore` | versioned legacy decode adapters with proved migration callers | delete | `EA-10F` | `swift test --filter PlotterArtifactResetEpisodeTests` |
| PER-005 | persistence-path | `DrawingRunEvidenceComposition`<br>`DrawingRunEvidenceStore` | append-only drawing-run evidence persistence | adapt | `EA-08B` | `swift test --filter PlotterDrawingRunEpisodeTests` |
| PER-006 | persistence-path | `PaperCoverageComposition`<br>`PaperCoverageObservation` | paper coverage persistence and validation | adapt | `EA-08A` | `swift test --filter PlotterDrawingDraftEpisodeTests` |
| PER-007 | persistence-path | `RunLedger.sqlite`<br>`MachineSessionRetentionPolicy` | bounded SQLite session diagnostics | adapt | `EA-05A` | `swift test --filter PlotterRecordingStoreTests` |
| PER-008 | persistence-path | `StartupFrameRecorder.Manifest` | unbound test-only frame/manifest file writer | delete | `EA-05A` | `swift test --filter PlotterRecordingStoreTests` |
| PER-009 | persistence-path | `AdaptivePlotter.paperInstanceRevision`<br>`AdaptivePlotter.paperContactPlaneRevision` | application-composed durable paper semantic identities | adapt | `EA-10F` | `swift test --filter PlotterArtifactResetEpisodeTests` |
| UI-001 | ui-consumer | `UI.serialDevices`<br>`UI.selectedSerialDevice`<br>`UI.selectSerialDevice`<br>`UI.controllerSelectionUnavailableReason`<br>`UI.controllerConnectionActionTitle`<br>`UI.performControllerConnectionAction`<br>`UI.controllerConnectionActionUnavailableReason`<br>`UI.controllerSessionEstablished`<br>`UI.performMotionAuthorizationAction`<br>`UI.motionAuthorizationActionUnavailableReason`<br>`UI.motionAuthorizationEnabled`<br>`UI.motionRequestStatusPresentation`<br>`UI.controllerConnectionText`<br>`UI.controllerStateText`<br>`UI.controllerAttentionText`<br>`UI.controllerLimitInputsText`<br>`UI.controllerAlarmUnlockReadinessText`<br>`UI.controllerAlarmEvidenceText`<br>`UI.clearControllerAlarm`<br>`UI.controllerAlarmClearInProgress`<br>`UI.controllerAlarmClearActionUnavailableReason`<br>`UI.motorPowerText`<br>`UI.motionGuardIsActive`<br>`UI.motionPermissionText`<br>`UI.currentOperationText`<br>`UI.machinePositionText`<br>`UI.lastMotionOutcomeText`<br>`UI.lastPenOutcomeText` | SwiftUI controller toolbar/Motion diagnostics; direct workspace reads and handlers | delete | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| UI-002 | ui-consumer | `UI.frameMode`<br>`UI.cameraIsLive`<br>`UI.cameraDevices`<br>`UI.refreshVideoSources`<br>`UI.refreshVideoDiagnostics`<br>`UI.currentCameraCalibrationBusyReason`<br>`UI.cameraStateText`<br>`UI.captureThroughputText`<br>`UI.visionThroughputText`<br>`UI.cameraError`<br>`UI.visionError`<br>`UI.videoAnalysisRegionLock`<br>`UI.setVisionAnalysisCadence`<br>`UI.visionAnalysisCadence`<br>`UI.setVideoAnalysisRegion`<br>`UI.overlayCardPresentation`<br>`UI.penCapAppearanceSelection`<br>`UI.overlayPreferenceState`<br>`UI.setOverlay`<br>`UI.selectedCameraID`<br>`UI.switchFrameMode`<br>`UI.selectAndStartCamera`<br>`UI.frameModeSwitchUnavailableReason`<br>`UI.simulatorEvidenceLabel`<br>`UI.simulatorLearningSummary` | SwiftUI Video Settings/source/overlay direct workspace consumers | delete | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| UI-003 | ui-consumer | `UI.manualMotionPresentation`<br>`UI.xStepText`<br>`UI.yStepText`<br>`UI.feedText`<br>`UI.stopManualMotion`<br>`UI.requestPenActuation`<br>`UI.penUnavailableReason`<br>`UI.penStateText`<br>`UI.manualMotionModeText`<br>`UI.requestJog` | SwiftUI manual jog/Pen direct workspace consumers | delete | `EA-06` | `swift test --filter PlotterManualMotionEpisodeTests` |
| UI-004 | ui-consumer | `UI.selectToolContactPoint`<br>`UI.toggleLearningMode`<br>`UI.learningModeActionTitle`<br>`UI.learningModeChangeUnavailableReason` | Action Surface point and Learning on/off direct workspace handlers | delete | `EA-04` | `swift test --filter PlotterPointSelectionEpisodeTests` |
| UI-005 | ui-consumer | `UI.interactiveLearningIsComplete`<br>`UI.drawingStudioIsPresented`<br>`UI.drawingStudioPanelChangeUnavailableReason`<br>`UI.openDrawingStudio`<br>`UI.closeDrawingStudio`<br>`UI.confirmCurrentPaperCoversDrawableRegion` | Drawing Studio open/draft/paper-coverage direct workspace consumers | delete | `EA-08A` | `swift test --filter PlotterDrawingDraftEpisodeTests` |
| UI-006 | ui-consumer | `UI.performCompletedComparisonReviewAction`<br>`UI.performDrawingStudioAction`<br>`UI.paperManagementUnavailableReason` | Drawing Studio run/review direct workspace handlers | delete | `EA-08B` | `swift test --filter PlotterDrawingRunEpisodeTests` |
| UI-007 | ui-consumer | `UI.recordNewPaperSheetOnCurrentPlane`<br>`UI.recordPaperContactPlaneChanged`<br>`UI.performLearningVacate`<br>`UI.performResetAllLearning`<br>`UI.learningAuthorityError` | Saved Learning/reset/paper lifecycle direct workspace consumers | delete | `EA-10F` | `swift test --filter PlotterArtifactResetEpisodeTests` |
| UI-008 | ui-consumer | `UI.actionSurfacePresentation`<br>`UI.currentLearningPathItemID`<br>`UI.exercisePaneProtectionPresentation`<br>`UI.learningIsEnabled`<br>`UI.learningPathProjection`<br>`UI.drawingStudioPresentation`<br>`UI.workbenchCapabilityPresentation`<br>`UI.performExerciseAction` | aggregate Learning/Action Surface/Drawing presentation and semantic dispatch | delete | `EA-09` | `swift test --filter PlotterEpisodeUIActionabilityTests` |
| UI-009 | ui-consumer | `UI.performApplicationStartup`<br>`UI.shutdown` | application lifecycle direct workspace consumer | delete | `EA-11C` | `swift test --filter PlotterEpisodeCompositionTests` |
| FIX-001 | high-level-fixture | `SimulatedWorkspaceHarness`<br>`makeSimulatedHarness`<br>`performPublicAction` | high-level workspace closure fixture bypassing target intent/event seams | delete | `EA-07` | `swift test --filter PlotterCausalEpisodeEnvironmentTests` |
| FIX-002 | high-level-fixture | `MachineFixture`<br>`isolatedMachineActions` | app-level machine closure fixture | delete | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| FIX-003 | high-level-fixture | `CameraFixture`<br>`cameraActions` | app-level camera closure fixture | delete | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| FIX-004 | high-level-fixture | `completePenInteraction`<br>`identifyPenCap` | high-level Pen Interaction journey helper | delete | `EA-10A` | `swift test --filter PlotterPenInteractionEpisodeTests` |
| FIX-005 | high-level-fixture | `completeLiveBoundaries`<br>`completeSimulatedBoundariesAndCenter` | high-level Boundary workflow helper | delete | `EA-10B` | `swift test --filter PlotterBoundaryEpisodeTests` |
| FIX-006 | high-level-fixture | `completeSimulatedSparseTipCalibration` | high-level pen-tip workflow helper | delete | `EA-10D` | `swift test --filter PlotterTipCalibrationEpisodeTests` |
| FIX-007 | high-level-fixture | `completeSimulatedStageFour` | high-level Drawing Border workflow helper | delete | `EA-10E` | `swift test --filter PlotterBorderValidationEpisodeTests` |
| FIX-008 | high-level-fixture | `drawingPresentationTestFrame` | current direct presentation construction helper | delete | `EA-09` | `swift test --filter PlotterEpisodeUIActionabilityTests` |
| FIX-009 | high-level-fixture | `manualCameraSnapshotPreservesExactFrame` | test-only consumer of unbound startup frame recorder | delete | `EA-05A` | `swift test --filter PlotterRecordingStoreTests` |
| FIX-010 | high-level-fixture | `SimulatedGRBLLink`<br>`ControllerTranscriptFixtures`<br>`DeterministicRuntimeClock` | low-level deterministic controller transcript/replay fixtures | retain | `EA-05B` | `swift test --filter PlotterRecordingReplayTests` |
| FIX-011 | high-level-fixture | `PaperSceneSimulator`<br>`BlockingMachineLink` | causal paper and bounded controller-fault fixtures | retain | `EA-07` | `swift test --filter PlotterCausalEpisodeEnvironmentTests` |
| FIX-012 | high-level-fixture | `AnnouncementFixture` | app-level advisory closure fixture | delete | `EA-10G` | `swift test --filter PlotterSpeechEffectEpisodeTests` |
| FIX-013 | high-level-fixture | `CameraInspectionGate`<br>`CameraReconfigurationGate`<br>`CameraAnalysisTrafficFixture` | high-level camera task/lease fixtures | delete | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| FIX-014 | high-level-fixture | `WorkflowTelemetryFixture` | app-level diagnostic closure fixture | adapt | `EA-05A` | `swift test --filter PlotterRecordingStoreTests` |

### Exact cutover zero-match scans

`Scripts/check_episode_cutover.sh <PACKAGE-ID>` reads this closed table. Paths
are repository-relative comma-separated globs and every literal is matched
without regex interpretation. Each named cutover must pass all of its rows;
unknown/non-cutover IDs are rejected. Retained lower-level owners are
deliberately absent from deletion scans.

| Package | Scan class | Paths | Zero-match literal |
| --- | --- | --- | --- |
| `EA-04` | deleted-symbol | `Sources/PlotterApp/*.swift` | `ActionSurfacePointSelectionRequest` |
| `EA-04` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `selectToolContactPoint` |
| `EA-04` | task-owner | `Sources/PlotterApp/*.swift` | `penCapAcceptedClickContinuationTask` |
| `EA-04` | task-owner | `Sources/PlotterApp/*.swift` | `penCapVisionReconfigurationTask` |
| `EA-04` | fixture | `Tests/PlotterAppTests/*.swift` | `submitPenCapClick` |
| `EA-06` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `stopManualMotion` |
| `EA-06` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `requestRelativeJog` |
| `EA-06` | direct-port | `Sources/PlotterApp/*.swift` | `machineActions.beginRelativeJog` |
| `EA-06` | direct-port | `Sources/PlotterApp/*.swift` | `machineActions.requestPenActuation` |
| `EA-06` | fixture | `Tests/PlotterAppTests/*.swift` | `isolatedMachineActions` |
| `EA-07` | environment-branch | `Sources/PlotterApp/*.swift` | `requestSimulatedRelativeJog` |
| `EA-07` | environment-branch | `Sources/PlotterApp/*.swift` | `executeSimulatedBoundaryMotion` |
| `EA-07` | environment-branch | `Sources/PlotterApp/*.swift` | `simulatedLearningRuntime.requestManualMotion` |
| `EA-07` | fixture | `Tests/PlotterAppTests/*.swift` | `SimulatedWorkspaceHarness` |
| `EA-08A` | deleted-symbol | `Sources/PlotterApp/*.swift` | `drawingStudioDraftMutationIsAvailable` |
| `EA-08A` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `rebuildDrawingStudioPlan` |
| `EA-08A` | direct-port | `Sources/PlotterApp/*.swift` | `DrawingPlanner.plan` |
| `EA-08A` | fixture | `Tests/PlotterAppTests/*.swift` | `drawingPresentationTestFrame` |
| `EA-08B` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `runDrawingStudioPlan` |
| `EA-08B` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `performCompletedComparisonReviewAction` |
| `EA-08B` | direct-port | `Sources/PlotterApp/*.swift` | `machineActions.beginDrawingPlan` |
| `EA-08B` | direct-port | `Sources/PlotterApp/*.swift` | `cameraActions.observePlannedDrawingInk` |
| `EA-08B` | fixture | `Tests/PlotterAppTests/*.swift` | `makeDrawingStudioRunRecord` |
| `EA-09` | deleted-symbol | `Sources/PlotterApp/*.swift` | `LearningPathProjectionSnapshot` |
| `EA-09` | deleted-symbol | `Sources/PlotterApp/*.swift` | `LearningPathProjector` |
| `EA-09` | forbidden-import | `Sources/PlotterUI/*.swift` | `import PlotterRuntime` |
| `EA-09` | duplicate-ingress | `Sources/PlotterApp/LearningPathView.swift` | `actionWorkspace.performExerciseAction` |
| `EA-09` | task-owner | `Sources/PlotterApp/LearningPathView.swift` | `Task { await perform` |
| `EA-09` | fixture | `Tests/PlotterAppTests/*.swift` | `drawingPresentationTestFrame` |
| `EA-10A` | deleted-symbol | `Sources/PlotterApp/*.swift` | `penAttemptHistory` |
| `EA-10A` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `beginPenInteraction` |
| `EA-10A` | task-owner | `Sources/PlotterApp/*.swift` | `penSetpointActuationTask` |
| `EA-10A` | fixture | `Tests/PlotterAppTests/*.swift` | `completePenInteraction` |
| `EA-10B` | deleted-symbol | `Sources/PlotterApp/*.swift` | `boundarySideAggregates` |
| `EA-10B` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `beginPairedBoundarySide` |
| `EA-10B` | direct-port | `Sources/PlotterApp/*.swift` | `machineActions.beginBoundaryMotion` |
| `EA-10B` | task-owner | `Sources/PlotterApp/*.swift` | `boundaryMotionTask` |
| `EA-10B` | fixture | `Tests/PlotterAppTests/*.swift` | `completeLiveBoundaries` |
| `EA-10C` | deleted-symbol | `Sources/PlotterApp/*.swift` | `currentCameraCalibrationPhase` |
| `EA-10C` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `runCameraCalibrationAndBuildProposal` |
| `EA-10C` | task-owner | `Sources/PlotterApp/*.swift` | `currentCameraCalibrationTask` |
| `EA-10C` | fixture | `Tests/PlotterAppTests/*.swift` | `stageMachineCameraRegistrationProposal` |
| `EA-10D` | deleted-symbol | `Sources/PlotterApp/*.swift` | `SparseTipCalibrationCoordinator` |
| `EA-10D` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `drawFourCornerTipCircles` |
| `EA-10D` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `undoLastSparseTipClick` |
| `EA-10D` | fixture | `Tests/PlotterAppTests/*.swift` | `completeSimulatedSparseTipCalibration` |
| `EA-10E` | deleted-symbol | `Sources/PlotterApp/*.swift` | `DrawingTrialState` |
| `EA-10E` | deleted-symbol | `Sources/PlotterApp/*.swift` | `ObservedDrawingTrialStep` |
| `EA-10E` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `runObservedDrawingTrial` |
| `EA-10E` | task-owner | `Sources/PlotterApp/*.swift` | `activeExplorationOperation` |
| `EA-10E` | fixture | `Tests/PlotterAppTests/*.swift` | `completeSimulatedStageFour` |
| `EA-10F` | deleted-symbol | `Sources/PlotterApp/*.swift` | `SavedLearningPackageState` |
| `EA-10F` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `useSavedTraining` |
| `EA-10F` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `performResetAllLearning` |
| `EA-10F` | task-owner | `Sources/PlotterApp/*.swift` | `savedTrainingComparisonTask` |
| `EA-10F` | fixture | `Tests/PlotterAppTests/*.swift` | `LearningPathCheckpointBox` |
| `EA-10G` | deleted-symbol | `Sources/PlotterApp/*.swift` | `AnnouncementActions` |
| `EA-10G` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `announceAdvisory` |
| `EA-10G` | direct-port | `Sources/PlotterApp/*.swift` | `announcementActions?.announce` |
| `EA-10G` | fixture | `Tests/PlotterAppTests/*.swift` | `AnnouncementFixture` |
| `EA-11A` | deleted-symbol | `Sources/PlotterApp/*.swift` | `struct MachineActions` |
| `EA-11A` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `performControllerConnectionAction` |
| `EA-11A` | direct-port | `Sources/PlotterApp/*.swift` | `machineActions.` |
| `EA-11A` | task-owner | `Sources/PlotterApp/*.swift` | `pendingBoundaryStopCapabilities` |
| `EA-11A` | fixture | `Tests/PlotterAppTests/*.swift` | `MachineFixture` |
| `EA-11B` | deleted-symbol | `Sources/PlotterApp/*.swift` | `struct CameraActions` |
| `EA-11B` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `setVisionAnalysisCadence` |
| `EA-11B` | direct-port | `Sources/PlotterApp/*.swift` | `cameraActions.` |
| `EA-11B` | task-owner | `Sources/PlotterApp/*.swift` | `visionUpdateTask` |
| `EA-11B` | fixture | `Tests/PlotterAppTests/*.swift` | `CameraFixture` |
| `EA-11C` | deleted-symbol | `Sources/PlotterApp/*.swift` | `final class OperatorWorkspace` |
| `EA-11C` | deleted-symbol | `Sources/PlotterApp/*.swift` | `ActiveStoppableOperation` |
| `EA-11C` | deleted-symbol | `Sources/PlotterApp/*.swift` | `LearningSessionState` |
| `EA-11C` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `performExerciseAction` |
| `EA-11C` | direct-port | `Sources/PlotterApp/*.swift` | `@Sendable (` |
| `EA-11C` | task-owner | `Sources/PlotterApp/*.swift` | `activeLearningActionTask` |
| `EA-11C` | fixture | `Tests/PlotterAppTests/*.swift` | `func workspace(` |
| `EA-11C` | forbidden-import | `Sources/PlotterUI/*.swift` | `import PlotterRuntime` |
| `EA-11C` | environment-branch | `Sources/PlotterApp/*.swift` | `activeLearningSession` |

## Work ledger

Blackdog owns active task state. This table records only not-started work,
explicit blockers, and landed completion. Never mark a row active here.

Execution classes are `repository`, `software`, `attended-physical`,
`remote-git`, and `gate`. A direct named-package request or an invocation of
`$run-multi-agent-wave` may authorize one `repository`, `software`, or `gate`
mutation. Wave selection takes the first eligible row in this table's literal
order and cannot redefine its outcome, dependencies, authority, deletions, or
gates. `attended-physical` and `remote-git` still require their own explicit
package and execution-class authorization; wave or generic authorization is
insufficient.

| ID | Status | Dependencies | Class | Atomic package outcome | Required gates |
| --- | --- | --- | --- | --- | --- |
| DOC-00 | complete | none | repository | Initial canonical docs, observability contract, ledger, and skill landed in `TASK-C86132F1` at `d33d4ff` | `ARCHIVED` |
| DOC-01 | complete | DOC-00 | repository | Canonical vocabulary, incremental cutover, completion hierarchy, execution modes, atomic ledger, evidence-history repair, and contract check delivered by `TASK-F2387A9A` | `DOC`, `DIFF`, `CRITIC` |
| EA-01 | complete | DOC-01 | repository | Exhaustive current intent/guard/owner/port/mode/fixture inventory, retain/adapt/delete dispositions, current owners, cutover packages, exact deleted-symbol/direct-port scans, and exact focused test commands delivered by `TASK-513DC8A7`; no application source changed. | `DOC`, `DIFF`, `INVENTORY` |
| FIX-00 | complete | EA-01 | software | Correction: separate Euclidean controller-pose settlement from drawing-region containment, give each one typed owner/metric/revision, and delete the shared 0.5 mm policy assumption and its tests. Preserve strict accepted-Boundary drawing containment apart from an explicitly justified numerical epsilon. Delivered by `TASK-1B5992CF`. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `FIX-CONTAINMENT` |
| FIX-01 | complete | FIX-00 | software | Correction: prevent projection outside `TipCameraRegistration.applicabilityRectangle` from becoming attributable evidence unless a newly validated evidence-authority revision expands applicability. Delete the evidence bypass assumption and its tests while retaining typed diagnostic-only projection. Delivered by `TASK-05D1DCBD`. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `FIX-APPLICABILITY` |
| BASE-01 | pending | FIX-01 | attended-physical | Record the exact clean-main `TESTED-BASELINE-COMMIT`, build/sign that commit, and complete the attended known-good Learning Path with the mechanism continuously observed. Land evidence and limitations containing exactly one machine-readable `TESTED-BASELINE-COMMIT: <40-lowercase-hex>` line; the landing may change only this ledger and Current Evidence and must not tag or push. | `DOC`, `DIFF`, `STRICT`, `PHYSICAL-BASE` |
| BASE-02 | pending | BASE-01 | remote-git | After separate authorization for this exact branch-ref push, prove the Current Evidence `TESTED-BASELINE-COMMIT` remains source-identical through the BASE-01 evidence-only landing, publish exactly that tested commit to `refs/heads/main` without force, and verify the remote ref. It creates no tag. | `PUBLISH-MAIN` |
| BASE-03 | pending | BASE-02 | remote-git | After separate authorization for this exact tag push, prove the published `TESTED-BASELINE-COMMIT` is the `origin/main` tip, then idempotently create or recover the active-task-bound annotated tag `adaptiveplotter-episode-baseline-v1` on that commit and push only that tag without force. It never creates a previously absent canonical local tag, deletes or moves a canonical local/remote tag, force-updates, or updates a branch; temporary validation refs are always removed. | `TAG` |
| EA-02A | pending | EA-01, BASE-03 | software | Foundation: add one compile-only domain-generic `EpisodeCore` contract module containing the canonical value types and pure evaluator/reducer protocols; add no Plotter, device, persistence, UI, effect port, or app caller. | `DOC`, `DIFF`, `QUICK`, `CORE` |
| EA-02B | pending | EA-02A | software | Foundation: add one compile-only `PlotterEpisodeModel` contract module that binds concrete Plotter intents, state, events, effects, results, observations, evidence, and assessments to `EpisodeCore`; add no runtime, device port, persistence, UI, or app caller. | `DOC`, `DIFF`, `QUICK`, `PLOTTER-MODEL` |
| EA-03A | pending | EA-02B | software | Foundation: add one unbound `EpisodeStore` service that atomically validates and appends `EpisodeEvent` values to a durable `EpisodeJournal`, owns its one versioned journal-persistence adapter, and reconstructs `EpisodeState`; add no effect lane, operation owner, or app caller. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `STORE` |
| EA-03B | pending | EA-03A | software | Foundation: add one unbound `PlotterOperationRegistry` runtime service owning one-shot effect permits, typed lanes, original handles, exact `StopCapability`, cancellation, terminal disposition, and Stop/shutdown priority semantics; add no journal store, device adapter, or app caller. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `RUNTIME` |
| EA-05A | pending | EA-03A | software | Foundation: add one unbound lossless `EpisodeRecordingStore` service with typed controller-transcript and camera-lifecycle/frame channels plus content-addressed frame references; add no current-device hook, effect port, or app caller. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `RECORDING` |
| EA-05B | pending | EA-03A, EA-05A | software | Foundation: add one unbound deterministic replay service that reconstructs every recorded journal prefix and supports declared controller-traffic perturbations without executing an effect; add no app caller. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `REPLAY` |
| EA-05C | pending | EA-05B | software | Foundation: add one unbound headless bounded incident-package assembler/exporter that references manifests, journals, recordings, frames, observations, evidence, outcomes, assessments, and runtime/UI revisions; it owns no artifact store, UI, device port, or app caller. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `INCIDENT` |
| EA-04 | pending | EA-03B, EA-05B | software | Cutover: transfer exact-frame human point-selection authority, including stale refusal, observation/evidence acceptance, projection, EA-05A camera recording, and the continuation-cancellation semantics used by Learning Off; delete old selection state, continuations, closures, guards, and fixtures. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `POINT`, `DELETE` |
| EA-06 | pending | EA-04, EA-05C | software | Cutover: transfer manual jog, direct manual pen-actuation, exact owner-bound Stop, and EA-05A controller recording authority through LIVE/SIMULATED adapters; delete old manual ingress, guards, task/cancel owner, mode branches, and direct ports. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `MOTION`, `DELETE` |
| EA-07 | pending | EA-06 | software | Cutover: transfer causal-simulator environment authority to the adapter with shared intent/effect/result grammar and distinct controller, plant/pen, paper/ink, camera, Vision, and evidence truth; delete obsolete effect-capable simulator workflow branches. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `SIM`, `DELETE` |
| EA-08A | pending | EA-05C, EA-07 | software | Cutover: transfer Drawing Studio draft authority for catalog selection, open/new-plan/rebuild semantics, placement, parameter changes, `DrawingProgram`, planning, preview, and paper-coverage assertion; delete old draft/planning ingress and mutable draft state. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `DRAW-DRAFT`, `DELETE` |
| EA-08B | pending | EA-08A | software | Cutover: transfer Drawing Studio run authority for capture, execute, observe, evidence, outcome, assessment, close/review-pin semantics, ambiguity, and no-redraw terminal handling; delete old run/evidence closures, tasks, direct ports, and high-level fixtures. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `DRAW-RUN`, `DELETE` |
| EA-09 | pending | EA-04, EA-06, EA-08B | software | Cutover: transfer episode UI presentation authority to bounded reachability, an immutable compiler boundary, intent-actionability invariants, runtime/UI revision diagnostics, and UI request/progress/result presentation for the EA-05C incident service. Keep pane/window/viewport and unsubmitted draft-text changes in UI-local reducers; route Learning on/off continuation cancellation to EA-04 and Drawing Studio domain-changing open/close actions to EA-08A/EA-08B. Delete migrated SwiftUI workspace reads and direct semantic dispatch. Add no recorder, package assembler, artifact store, or export backend. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `UI`, `DELETE` |
| GATE-01 | pending | EA-09 | gate | Decide pilot continuation from deletion, replay, typing, owner, observability, simulation, and physical-boundary evidence. It moves no authority. | `DOC`, `DIFF`, `PILOT` |
| EA-10A | pending | GATE-01 | software | Cutover: transfer Pen Interaction intent/evidence authority and delete its old workspace state, guards, tasks, and fixtures. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `PEN`, `DELETE` |
| EA-10B | pending | EA-10A | software | Cutover: transfer Boundary acquisition/renewal intent/evidence authority and delete its old workspace state, guards, tasks, and fixtures while retaining controller-only movement authority. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `BOUNDARY`, `DELETE` |
| EA-10C | pending | EA-10B | software | Cutover: transfer camera-from-cap calibration intent/evidence authority and delete its old workspace state, capture/Vision tasks, guards, and fixtures. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `CAMERA-CAL`, `DELETE` |
| EA-10D | pending | EA-10C | software | Cutover: transfer pen-tip calibration intent/evidence authority and delete its old workspace state, capture/Vision tasks, guards, and fixtures. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `TIP-CAL`, `DELETE` |
| EA-10E | pending | EA-10D | software | Cutover: transfer Drawing Border validation authority and delete `DrawingTrialState`, `ObservedDrawingTrialStep`, `.drawingTrial`, `.observedDrawingTrial`, their old owners, and active old-label emission; retain old labels only inside versioned decode adapters with callers proved. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `BORDER-VALIDATION`, `DELETE` |
| EA-10F | pending | EA-10E | software | Cutover: transfer Saved Learning/artifact lifecycle authority, including checkpoint, redo, paper replacement, possible ink, and reset; delete old workspace ownership and compatibility fixtures. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `ARTIFACT-RESET`, `DELETE` |
| EA-10G | pending | EA-10F | software | Cutover: transfer advisory-speech effect authority to a typed registry lane with identity-bound queueing, bounded completion/failure/timeout/cancellation results, preserved advisory-only failure semantics, ordering before dependent physical commands, and shutdown cancellation. Retain `NativeSpeechAnnouncer`/AVFoundation synthesis ownership; delete `AnnouncementActions`, `OperatorWorkspace.announceAdvisory`, direct announcement calls, duplicate queue/task ownership, and high-level announcement fixtures. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `SPEECH`, `DELETE` |
| EA-11A | pending | EA-10G | software | Cutover: transfer controller-session readiness authority for serial selection, connect/disconnect, passive probe, explicit alarm clear, session-scoped Motion authorization, and complete EA-05A controller-session recording through typed intents, rules, events, and effects. Retain `MachineController` and `RunInterpreter` transport/safety ownership; delete the workspace/UI handlers, duplicated unavailable-reason guards, in-progress/task/generation state, direct `MachineActions` calls, LIVE/SIMULATED session branches, serial-preference closure, and old fixtures. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `SESSION`, `DELETE` |
| EA-11B | pending | EA-10G | software | Cutover: transfer observation-environment configuration authority for camera discovery/selection/lifecycle, LIVE/SIMULATED source selection, automatic-analysis cadence, exact-frame region policy, overlay-feature preferences, bounded diagnostic requests, complete EA-05A camera recording, and ambient frame/Vision task-result routing. Retain `CameraCapture` device/frame ownership, camera-session analysis/lease ownership, Vision measurement authority, and evidence-applicability authority; delete direct SwiftUI/workspace handlers and reads, duplicated config/guard state, mode branches, frame/Vision tasks, direct `CameraActions` calls, persistence closures, and old fixtures. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `OBSERVATION-CONFIG`, `DELETE` |
| EA-11C | pending | EA-11A, EA-11B | software | Cutover: transfer only final application composition and policy-originated startup/shutdown authority to immutable projections and one typed intent sink, making `PlotterIntentGateway` and `PlotterOperationRegistry` globally exclusive. Delete the `OperatorWorkspace` effect closures plus `ActiveStoppableOperation`, `LearningSessionState`, `liveLearningSession`, `simulatedLearningSession`, `activeLearningSession`, `hasShutdown`, `lifetimeGeneration`, `activeHardwareIntentCount`, `intentDrainWaiters`, `beginHardwareIntent`, `endHardwareIntent`, `canCommit`, `waitForHardwareIntentsToDrain`, and every migrated direct UI read named by EA-01. It may not absorb an unnamed feature migration; any unassigned inventory item fails the package. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `COMPOSITION`, `DELETE` |
| VAL-01 | pending | EA-11C | attended-physical | On the exact migrated signed build, execute the complete attended runbook including Drawing Studio, exercise visible refusal/progress/Stop and incident export, and land controller/camera/operator/ink evidence and limitations without changing architecture. | `DOC`, `DIFF`, `STRICT`, `PHYSICAL-FINAL` |
| GATE-02 | pending | VAL-01 | gate | Prove globally exclusive `PlotterIntentGateway`, complete operator journey, replay/simulation/incident evidence, same-landing deletion, final attended evidence, and packaging decision. It moves no authority. | `DOC`, `DIFF`, `FINAL-GATE` |

`repository`, `attended-physical`, `remote-git`, and `gate` rows move no product
authority. Every `software` outcome begins `Foundation:`, `Correction:`, or
`Cutover:` with the exact meaning defined by the vocabulary authority.

`EA-01` is the only package allowed to add current-source characterization
commands, source-symbol inventories, and package-specific
deleted-symbol/direct-port scan data. The target focused-suite names and gate
commands below are fixed; `EA-01` cannot rename or replace them, and an
implementation package creates its named suite with its corresponding code.
`EA-01` may not add, remove, combine, split, or reorder packages. If its
inventory proves that any row contains more than one authority transfer or
rollback boundary, or that any semantic intent lacks a package, `EA-01` fails.
A separate repository-contract correction must revise this plan and its exact
checker and earn a fresh `CRITIC` verdict before `EA-01` is retried. A
lower-reasoning executor may implement a fully specified package but may not
choose scope, dependencies, owners, deletion disposition, lifecycle design, or
completion status.

### Validation gate catalog

Angle-bracket values are compiled from the named row and landed Current
Evidence; they are not executor choices. Test filters name suites that the
owning implementation package must add. A filter that selects zero tests fails
the gate. All commands run from the task workspace on the recorded target.

| Gate | Exact command or evidence procedure | Created or owned by |
| --- | --- | --- |
| `ARCHIVED` | `git merge-base --is-ancestor d33d4ff HEAD` and the `TASK-C86132F1` Current Evidence entry identifies `d33d4ff` | DOC-00 |
| `DOC` | `make docs-check` | repository |
| `DIFF` | `git diff --check` | repository |
| `CRITIC` | A fresh-context read-only critic inspects the actual candidate tree, runs `make docs-check` and `git diff --check`, gives PASS on all ten readiness dimensions in the execution prompt, and ends exactly `UNANIMOUS PASS — no material disagreement`; Current Evidence records that verdict while the full transient report is not checked in | DOC-01 |
| `QUICK` | `make quick-test` | repository |
| `JOURNEY` | `make journey-test` | repository |
| `STRICT` | `make strict-check` | repository |
| `INVENTORY` | `sh Scripts/check_episode_inventory.sh` proves every semantic intent, guard, owner, direct device/evidence port, environment branch, task/cancel owner, persistence path, UI consumer, and high-level fixture has one stable inventory ID, one current owner, one disposition, and one cutover package | EA-01 |
| `FIX-CONTAINMENT` | `swift test --filter CoordinateAcceptancePolicyTests` | FIX-00 |
| `FIX-APPLICABILITY` | `swift test --filter TipApplicabilityEvidencePolicyTests` | FIX-01 |
| `CORE` | `swift test --filter EpisodeCoreTests` | EA-02A |
| `PLOTTER-MODEL` | `swift test --filter PlotterEpisodeModelContractTests` | EA-02B |
| `STORE` | `swift test --filter EpisodeStoreTests` | EA-03A |
| `RUNTIME` | `swift test --filter EpisodeRuntimeTests` | EA-03B |
| `RECORDING` | `swift test --filter PlotterRecordingStoreTests` | EA-05A |
| `REPLAY` | `swift test --filter PlotterRecordingReplayTests` | EA-05B |
| `INCIDENT` | `swift test --filter PlotterIncidentPackageTests` | EA-05C |
| `POINT` | `swift test --filter PlotterPointSelectionEpisodeTests` | EA-04 |
| `MOTION` | `swift test --filter PlotterManualMotionEpisodeTests` | EA-06 |
| `SIM` | `swift test --filter PlotterCausalEpisodeEnvironmentTests` | EA-07 |
| `DRAW-DRAFT` | `swift test --filter PlotterDrawingDraftEpisodeTests` | EA-08A |
| `DRAW-RUN` | `swift test --filter PlotterDrawingRunEpisodeTests` | EA-08B |
| `UI` | `swift test --filter PlotterEpisodeUIActionabilityTests` | EA-09 |
| `PILOT` | `sh Scripts/check_episode_pilot_gate.sh` proves the exact Pilot continuation gate predicates below against landed rows and Current Evidence | EA-09 |
| `PEN` | `swift test --filter PlotterPenInteractionEpisodeTests` | EA-10A |
| `BOUNDARY` | `swift test --filter PlotterBoundaryEpisodeTests` | EA-10B |
| `CAMERA-CAL` | `swift test --filter PlotterCameraCalibrationEpisodeTests` | EA-10C |
| `TIP-CAL` | `swift test --filter PlotterTipCalibrationEpisodeTests` | EA-10D |
| `BORDER-VALIDATION` | `swift test --filter PlotterBorderValidationEpisodeTests` | EA-10E |
| `ARTIFACT-RESET` | `swift test --filter PlotterArtifactResetEpisodeTests` | EA-10F |
| `SPEECH` | `swift test --filter PlotterSpeechEffectEpisodeTests` | EA-10G |
| `SESSION` | `swift test --filter PlotterControllerSessionEpisodeTests` | EA-11A |
| `OBSERVATION-CONFIG` | `swift test --filter PlotterObservationConfigurationEpisodeTests` | EA-11B |
| `COMPOSITION` | `swift test --filter PlotterEpisodeCompositionTests` | EA-11C |
| `DELETE` | `sh Scripts/check_episode_cutover.sh <PACKAGE-ID>` executes the exact zero-match deleted-symbol, forbidden-import, direct-port, duplicate-ingress, task-owner, fixture, and environment-branch scans recorded by EA-01 for that package; any unassigned remaining consumer fails | EA-01 |
| `PHYSICAL-BASE` | On the exact signed clean-main commit, one continuously attending operator executes Attended Hardware Runbook sections 1 through 5 and completes its Evidence record; the landed record must contain exactly one `TESTED-BASELINE-COMMIT: <40-lowercase-hex>` line and separately identify controller, camera, operator, and observed-ink claims, ambiguities, and skipped steps | BASE-01 |
| `PUBLISH-MAIN` | Blackdog `task show --json` for the current `<TASK-ID>` must report target branch `main`. Substitute `<TESTED-BASELINE-COMMIT>` from BASE-01 Current Evidence, then run `git fetch --no-tags origin main`, `git merge-base --is-ancestor origin/main "<TESTED-BASELINE-COMMIT>"`, `git merge-base --is-ancestor "<TESTED-BASELINE-COMMIT>" HEAD`, `test -z "$(git diff --name-only "<TESTED-BASELINE-COMMIT>"..HEAD -- . ':(exclude)docs/CURRENT_EVIDENCE.md' ':(exclude)docs/EPISODE_ARCHITECTURE_EXECUTION_PLAN.md')"`, `git push origin "<TESTED-BASELINE-COMMIT>:refs/heads/main"`, and verify `git ls-remote --heads origin refs/heads/main` returns exactly `<TESTED-BASELINE-COMMIT>` | BASE-02 |
| `TAG` | After separate exact tag-push authorization, run only `sh Scripts/publish_episode_baseline_tag.sh "<TASK-ID>" "<TESTED-BASELINE-COMMIT>"`. The checked-in procedure verifies the active in-progress repo-skill Blackdog task ID, `main` target, task worktree, verified prompt lineage, first-line `AdaptivePlotter episode WorkPackage: BASE-03` marker, second-line tested-commit binding, the sole BASE-01 `TESTED-BASELINE-COMMIT` Current Evidence line, and `origin/main`. It validates every new or remote-only annotated object through a temporary ref, re-observes the remote tag and `origin/main` before success, leaves a remote-only tag remote-only, removes the temporary ref on every exit, resumes only an exact verified local-only tag, and blocks wrong task/package/target/commit, lightweight, malformed, differently targeted, differently tasked, disagreeing, or raced tags without creating a previously absent canonical local ref, deleting/replacing a canonical tag, moving a tag, updating a branch, or forcing | BASE-03 |
| `PHYSICAL-FINAL` | On the exact signed landed EA-11C commit, one continuously attending operator executes Attended Hardware Runbook sections 1 through 6 and completes its Evidence record; the record must additionally capture one visible typed refusal/remedy, active owner/progress/Stop, runtime/UI revisions, one bounded incident export, controller transcript completeness, camera artifact presence or declared absence, and observed-ink/ambiguity outcomes | VAL-01 |
| `FINAL-GATE` | `sh Scripts/check_episode_final_gate.sh` proves every ledger row through VAL-01 complete, all final-matrix software/replay/simulation/UI evidence linked from Current Evidence, one globally exclusive gateway and registry by structural scan, zero superseded paths, and a passed PHYSICAL-FINAL record for the exact EA-11C commit | EA-11C |

## Package completion contract

Completion has three noninterchangeable levels:

1. A Blackdog operation is complete when its structured result says so. This
   proves only that the lifecycle operation completed.
2. A `WorkPackage` is complete only when one bounded authority/deletion outcome
   is landed on Blackdog's recorded canonical `main` target, every gate named in
   its ledger row passed, every same-landing deletion is proved, matching Current
   Evidence is landed, its structured Work package gate evidence row records
   every required gate as `passed`, and the ledger row is landed as `complete`.
3. The migration is complete only when every executable row is complete and
   both pilot and final gates have passed. Until then, every handoff says
   “package `<ID>` complete; migration remains incomplete.”

`failed` and `skipped` are truthful evidence outcomes but cannot satisfy a
required gate. Missing required evidence also prevents completion. A blocked
package may land only a canonical blocker/evidence update after all partial
authority-transfer code, bridges, tests, and ledger `complete` claims are
removed; the row remains `blocked`. Blackdog's task close/land state never
overrides these conditions.

Every executable package prompt copies verbatim its row, exact expanded gate
commands, current owners and behavior, authority transfer, observability impact,
same-landing deletion set, and done condition. Validation runs serially when
SwiftPM shares `.build`. Software, replay, and simulation never prove attended
controller, camera, motion, pen, paper, operator click, or observed ink.

## Pilot continuation gate

`Scripts/check_episode_pilot_gate.sh`, created and tested in `EA-09`, evaluates
the following closed set of predicates against landed ledger rows, inventory
scans, and linked Current Evidence. `GATE-01` may mark only its own row complete
after that command, `DOC`, and `DIFF` pass:

- domain-generic `EpisodeCore` required no forbidden type-erasure or concurrency
  escape hatch, and Plotter-specific values remain in `PlotterEpisodeModel`;
- replay reconstructs canonical state, projection, and availability without
  executing effects;
- captured device traffic reaches production controller/camera owners;
- LIVE and SIMULATED share semantic grammar without equating evidence;
- migrated slices have zero old entrypoints, guards, task/Stop owners, and
  direct ports;
- independently authored admission sites, workspace task owners, mode branches,
  and direct effect calls decreased;
- every observability non-negotiable has deterministic coverage and an operator
  presentation or external fallback;
- `OperatorWorkspace` lost policy/state instead of accumulating adapters;
- physical safety owners and evidence-class boundaries remain intact.

If genericity, same-slice deletion, device-owner preservation, deterministic
replay, or truthful observability fails, the gate fails and the migration stops
rather than maintaining dual authority.

## Final continuation gate

`Scripts/check_episode_final_gate.sh`, created and tested in `EA-11C`, evaluates
the following closed set of predicates. `GATE-02` runs only after `VAL-01` has
landed the exact attended record for the EA-11C commit. It may mark only its own
row complete after `FINAL-GATE`, `DOC`, and `DIFF` pass:

- every ledger row through `VAL-01` is `complete`, with passed required gates
  and matching Current Evidence;
- the `EA-11C` landing made `PlotterIntentGateway` the only application semantic
  mutation ingress and `PlotterOperationRegistry` the only application
  effect/Stop/cancellation owner;
- all same-landing deletion inventories are empty and no compatibility bridge,
  old workspace owner, alternate environment branch, or high-level fixture
  remains without a proved non-episode consumer;
- the final matrix links passed evaluator, reachability, replay, perturbation,
  simulation, UI-actionability, refusal, stalled-prefix, incident-export, and
  operator-journey evidence;
- `PHYSICAL-FINAL` links the exact signed EA-11C commit to attended controller,
  camera, operator, UI observability, incident-export, and ink/ambiguity records;
- the packaging decision is explicit: retain the internal packages unless a
  separately authorized second-client proposal proves an SDK boundary.

Any failed or missing predicate leaves `GATE-02` pending or blocked. The gate
moves no authority and cannot repair implementation while assessing it.

## Final validation matrix

| Concern | Required evidence |
| --- | --- |
| state and intent correctness | pure evaluator/reducer cases plus bounded reachability |
| refusal and lock observability | typed owner/revision/remedy, effect progress, UI/runtime revision, stalled-prefix tests |
| episodic memory | durable manifest/event replay, every prefix, corruption and schema tests |
| controller communication | exact and perturbed link replay through production owners |
| camera lifecycle and video | lifecycle replay plus exact frame artifacts where retained |
| physical causality and faults | controller/plant/pen/paper/camera/Vision causal simulation |
| UI actionability | every reached state renders action, wait/progress, remedy, or exact Stop/cancel |
| actual hardware and ink | explicitly attended runbook evidence only |
