# AdaptivePlotter Swift Architecture

Status: current package and ownership architecture

This document owns package boundaries, runtime owners, data flow, and dependency
direction. Product invariants live in [Product Contract](PRODUCT_CONTRACT.md),
the exact operator sequence in
[Discovery and Observed-Trial Protocol](DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md),
and verified status in [Current Evidence](CURRENT_EVIDENCE.md).

## Package topology

```text
PlotterModel
  coordinate-space types, geometry, deterministic drawing-program catalog
  placements, drawable regions, content-addressed plans, readiness schema

PlotterRuntime
  MachineController, RunInterpreter, CameraCapture, VisionWorker
  learning artifacts and dependency graph
  sparse contact evidence, affine-first tip construction, applicability, checkpoints
  owner-bound multi-stroke execution, generic planned-ink observation
  paper and append-only drawing-run evidence
  causal nonphysical simulator and workflow telemetry

PlotterApp
  OperatorWorkspace orchestration and artifact commits
  immutable LearningPathProjectionSnapshot and pure LearningPathProjector
  SwiftUI Learning Path, ActionSurface, Drawing Studio, Motion and Video Settings
  production checkpoint/evidence stores and semantic identity composition

PlotterTestSupport
  deterministic machine links, clocks, transcripts, and paper scenes
```

Dependencies point inward. Runtime does not import SwiftUI. Views receive
projected immutable presentation values and typed closures; they do not own the
controller, camera, calibration, or learning graph.

## Runtime owners

`MachineController` is the only selected serial owner. It parses GRBL, admits
typed requests, serializes commands, proves settlement, and latches sticky
ambiguity. It also owns the explicit typed alarm-clear operation: admission
requires current typed Alarm status with no X/Y/Z `Pn` input asserted, then
rechecks realtime status immediately before any `$X` write. A physical limit or
unknown current input state refuses without unlock transmission. `$X`
acknowledgement is recorded separately from motion outcomes, and Motion
authorization remains inactive. `RunInterpreter` serializes alarm clearing with
every other logical operation. `OperatorWorkspace` projects limit-input evidence
and alarm-unlock readiness separately, then follows an acknowledged clear with a
fresh full passive probe before projecting a responsive session; Connect never
clears an alarm implicitly.

`CameraCapture` owns device discovery, authorization, selection, capture
sessions, exact stamped frames, and scoped preview publication holds. A hold
does not stop raw capture. `VisionWorker` owns bounded inference and returns
measurements; it never supplies motion or click authority.

`OverlayPreferenceState` contains only the persistent operator selections
`penCap` and `armatureEnvelope`. `SceneFeatureSet` expands the armature dependency
to pen-cap computation and requests no unrelated kernel. Typed
`OverlayLayerStatus` values keep run state, reason, cadence, region, frame, and
age out of preference. `OverlayResultChannels` owns independent scene, workflow,
and simulation results. `OverlayPresentationComposer` is pure and renders only
source/configuration/frame-exact geometry, so one producer cannot clear another.
If the displayed frame still matches the completed scene result, the composer
retains that geometry and its completed typed status while the next frame is
analyzing, and swaps only after a new completed exact-frame result is installed.

`OperatorWorkspace` maps the selected scene features to one newest-only
automatic-analysis request and one selected cadence. Video Settings may lock the
current zoomed/panned camera-pixel rectangle as the generic scene-analysis
region. `CameraSourceSession` passes that region into
`PlotterSceneAnalysisPipeline`; `VisionWorker` scans only requested pen-cap
pixels and derives the armature envelope from an accepted cap. Full-frame lock
is canonicalized to default analysis, and cap component size is evaluated against
whole-frame policy. Specialized calibration and observed-trial exact-frame
measurements retain independent typed regions.

`PenCapAppearanceSelection` is the only persisted LIVE recognition input. The
first Pen Interaction action freezes an exact frame and issues a
`penCapAppearance` point-selection request. `PenCapAppearanceSampler` maps the
operator's cap-body click to a clipped 9 x 9 RGBA/BGRA neighborhood, filters out
gray, white, dark, and otherwise insufficiently chromatic pixels, then records
the channel-wise median RGB color. The stored selection binds that color to the
click point, frame ID and hash, source, camera configuration, dimensions, pixel
format, sample counts, and sampler revision. `CameraSourceSession` applies the
accepted color to both newest-only scene analysis and exclusive Stage 3.3
inspection. There is no `ColorPicker` owner or mutable color preference seam.

`OperatorWorkspace` is the single `@Observable` application owner. It composes
controller/camera actors through typed actions, owns Learning Path attempts,
constructs immutable evidence, commits the dependency graph, routes view
intent, and copies current state into `LearningPathProjectionSnapshot`. It
cannot replace controller settlement or exact-frame provenance with UI state.

`LearningPathProjectionSnapshot` is values-only. It contains copied typed facts
and precomputed policy/admission results, not controller or camera actors,
persistence capabilities, task handles, mutating closures, or authority-
changing methods. It also narrows mutable session values such as discovery
transactions and Boundary progress to immutable presentation facts.

`LearningPathProjector` is a pure value. Identical snapshots and review
selection produce identical navigator rows, current item, status, summaries,
action strips, exact Stop capability presentation, evidence, activity,
subsystem status, timeline, and reset surfaces. It cannot mutate a session,
admit motion, persist, perform I/O, or accept an artifact. SwiftUI consumes one
aggregate projection per Learning Path render and sends selected typed actions
back to `OperatorWorkspace`.

LIVE and SIMULATED each own one `LearningSessionState` value under that shared
contract. Within each value, compiler-enforced substates prevent invalid
cross-field combinations: one exercise-attempt lifecycle owns attempt identity,
item owner, and mode; one sparse-selection lifecycle owns pending evidence,
the frozen frame, request, and selected point; and one Drawing Trial state owns
the complete trial payload, history, rollback, and rewind transitions. A
separate Drawing Studio state owns catalog selection, placement, immutable plan,
run presentation, and retained exact-frame review, but not controller or camera
authority. Supervised
Learning Path travel and settlement carry typed `LearningMotionAction` identity;
display text is derived only by the presentation boundary.

`RunLedger` and workflow telemetry record diagnostics only. They do not replay
commands, restore owners, or promote artifacts.

`DrawingProgramCatalog` produces deterministic field-space geometry. A
`DrawingPlacement` is the only field-to-machine transform, and `DrawingPlanner`
is the only producer of content-addressed `ExecutionPlanRevision` values.
Planning refuses geometry outside `DrawableMachineRegion`; neither App nor
Runtime clips it. `RunInterpreter` owns a whole plan as one `RunOperation`, with
subordinate Pen-Up travel, pen actuation, finite drawing segments, Stop, and one
checkpoint per logical stroke. `PlannedDrawingObservation` operates only after
execution and returns exact-frame observed/residual evidence or a typed
rejection; it has no motion, resend, or promotion capability.

## Pen Interaction and manual controls

`OperatorWorkspace` starts Pen Interaction with **Identify Pen Cap**. Until the
exact-frame cap-body click is accepted, no Pen Interaction question is opened
and no pen request is issued. Rejection or stale provenance leaves the point
selection pending. After acceptance, the exercise's Up and Down sliders issue
typed value-bearing pen requests; **Next** retains the displayed value in the
current setting and the existing attempt evidence. `MachineController`
serializes the requested value and settlement under its existing pen-operation
ownership. There is no parallel servo-calibration owner, checkpoint, or
artifact graph.

`LearningPathProjector` derives current progression from the active owner and
the first unmet dependency. `restartableExerciseItemID` is recovery state for
the owning review row; it does not redirect progression. The persisted
`PenCapAppearanceSelection` is loaded by `OperatorWorkspace`; its color is then
applied by `CameraSourceSession`. Before it exists, LIVE Pen cap and Armature
envelope statuses are Unavailable while their operator-owned overlay
preferences remain unchanged. An accepted replacement clears stale scene
geometry and admits only newly analyzed frames without becoming calibration
authority.

Manual X distance, Y distance, and feed fields initialize to 50 mm, 50 mm, and
500 mm/min while remaining editable. Manual direction routing depends on direct
controller facts and the current commanded pen state, not camera, Vision,
Learning, current-camera calibration, or visually confirmed pose. Known Down
uses drawing ownership; Up or unknown uses ordinary manual-jog ownership, with
unknown pose preserved in the resulting evidence.

## Sparse calibration data flow

Stage 3.3 builds `CurrentCameraCalibrationPlan` from current Boundary aggregates
and center arrival. `MachineCameraRegistration` retains five machine/cap
correspondences: `C`, `X−`, and `Y+` fit the initial affine map; `X+` and `Y−`
are independent holdouts; acceptance follows the all-five refit.

For each LIVE correspondence, `OperatorWorkspace.captureStableWorkflowCap`
acquires exactly three strictly newer exact `inspectWorkflowScene` results after
a preliminary frame boundary. `FixedCameraOpticalSettlingPolicy` requires one
source/configuration, exact measurement/frame identity, an accepted unambiguous
cap in every frame, and maximum pairwise component-centroid spread of at most 2 px.
It returns the newest third inspection unchanged; no centroid, bounds, or
confidence is averaged. The preliminary frame is freshness control, not accepted
cap evidence. SIMULATED causal geometry is source-separated nonphysical evidence
and cannot establish live optical stability.

Stage 3.4 is split across three owners:

- `SparseTipCalibrationCoordinator` owns the compact batch state machine, one
  attempt/operation identity, canonical `C`, `X−`, `Y+`, `X+`, `Y−` positions,
  one shared final frozen frame, unordered click collection, immutable accepted
  observations, possible-ink terminal state, proposal review, and acceptance.
- `OperatorWorkspace` owns the ±30 mm Stage 3.4 batch plan, supervised Pen-Up
  travel, current Pen Interaction Up/Down values, five closed 16-chord 2 mm-
  radius circles capped at 100 mm/min, settled Pen Up before every inter-circle
  travel, one final X-max/Y-zero-biased reveal, exact frame/cap capture, and
  atomic graph/checkpoint commits. Stage 3.3 retains its existing ±24 mm plan.
- `TipCalibrationAuthority` owns validated evidence types, all-five affine-first
  construction, constant construction fallback, diagnostic residual/covariance/
  uncertainty, applicability decisions, rebase derivations, and checkpoints.

`ActionSurfacePointSelectionRequest` binds the shared frozen
`ExactTipCalibrationFrame` and presentation-transform revision. `ActionSurface`
maps each view click back through the exact inverse presentation transform,
renders click count and all markers, and supports same-frame undo/clear without
motion, ink, capture, zoom, or pan. Stage 3.4 never installs a fitted region or
changes viewport state.

After click five, the app projects all known machine positions through current
`MachineCameraRegistration`, centers projected and clicked sets to remove their
common cap-to-tip translation, evaluates all 5! assignments, and selects the
minimum total squared pixel distance with canonical-position exact-tie breaking.
There is no distance or ambiguity gate. The five associated observations feed
direct affine construction first; constant correction is constructed only when
affine construction throws. Residuals, RMS, covariance, and uncertainty are
diagnostic and never block progression.

The accepted graph shape is:

```text
current MachineCameraRegistration
  -> five ToolContactObservation revisions
  -> current TipCameraRegistration
```

A new paper instance on an explicitly unchanged contact plane consumes no new
contact observation and retains tip authority. A changed contact plane
invalidates the tip registration and requires the normal five-observation
Stage 3.4 graph. Stage 4 line plans and local baselines consume the exact current
tip revision; later line/post-frame/ink/residual nodes retain that dependency
transitively.

## Chronology and possible ink

Live Pen Down and Pen Up timestamps are taken only after the corresponding
settled controller outcomes. Reveal settlement is timestamped after final MPos
acceptance and before a newer exact frame is captured. The reveal cites the
refreshed controller-context baseline returned with that capture.

The no-redraw key is `BlacklistedToolContactLocation`: calibration role, circle
center/radius, and replaceable paper-instance revision. `OperatorWorkspace` retains
that set across attempt cancel, restart, and Learning Path reset. The coordinator
re-enters a terminal possible-ink state on the same sheet. Explicit sheet
replacement rotates instance identity and clears that sheet-specific recovery;
it rotates contact-plane identity only when support, stock, or contact height
changed. Numerical model construction cannot request paper replacement or a
no-redraw recovery route.

## Tip checkpoint and semantic identity

Machine-only persistence remains in `AcceptedMachineArtifactCheckpoint`.
`AcceptedTipCalibrationCheckpoint` stores the accepted direct machine-to-tip
registration and acceptance event separately.

Production semantic identities are composed from stable persisted revisions for
machine geometry, tool assembly, pen-contact profile, paper instance, paper
contact plane, camera mount, and camera reframing. Capture-session and camera-configuration IDs remain
ephemeral operational provenance; they are not substituted for mount/reframing
identity.

Loading a tip checkpoint sets `quarantinedTipCalibrationCheckpoint` only. A
same-plane restore constructs fresh `TipCalibrationRevalidationEvidence` from a
settled controller/cap frame, rebuilds current graph revisions, and creates a
new accepted tip revision while preserving the original validated revision
lineage across repeated restarts. Replacing only the paper instance retains that
authority; changing the contact plane invalidates it and requires the full
five-mark calibration. The revalidation evidence is durable. Reset clears the
affected durable machine and/or tip checkpoint before clearing in-memory
authority.

Unknown semantic changes cannot be inferred from a UUID. The attended operator
must refuse revalidation after an unrecorded physical remount or assembly
change; explicit operator-facing revision controls remain a roadmap item.

## Stage 4 ownership

Stage 4 does not reuse a Stage 3 target, baseline, or reveal pose.
`ObservedDrawingTrialLinePlan` creates a 5 mm local line inside the tip
applicability rectangle only when it clears every retained circular-mark
geometry; a crowded domain blocks instead of weakening new-ink attribution.
The visible 4.1 row owns one attempt from **Go** through normal comparison; its
six typed phases update activity and subsystem presentation but do not create
six UI action owners. It stores:

- the exact tip registration revision;
- a trial-local pre-line exact frame and reveal MPos;
- line-start settlement and one drawing owner;
- a Pen-Up return to the same reveal MPos;
- a strictly newer post-line exact frame;
- bounded generic black/new-ink observation, residual, and assessment.

Before motion, `OperatorWorkspace` projects the stored machine start/end through
the exact current `TipCameraRegistration`. `ActionSurfacePresentation` binds the
planned polyline to each currently displayed frame/configuration, so the cyan
prediction remains visible over live video without freezing preview or treating
planned geometry as measured pixels. The post-line observer replaces that
preview with exact-frame intended, measured-ink, and residual overlays.

`exclusiveWorkflowVisionRequestCount` is projected separately from background
scene-analysis state. While isolated-ink comparison is in flight, Learning
reports **Trial ink analysis · active** and names Vision as the processing owner.
Normal observed-ink success commits the typed comparison in the same exercise
attempt. Only a failure, ambiguity, possible-ink recovery, rejected observation,
or atomic-commit error ends the automatic chain early.

The intended line, observed ink, and residual are contextual Stage 4 results,
not global overlay preferences. The implemented curriculum ends at this one
attributable validation. Its post frame and overlays remain explicitly
reviewable, and its typed comparison is adapted into an evaluation-holdout
`DrawingRunEvidenceRecord`. No Stage 4 result automatically changes accepted
calibration or establishes a generally trained adaptive model.

## Drawing Studio ownership

`OperatorWorkspace` derives a continuously projected calibrated region and
predicted current tip point from `TipCameraRegistration`. `PaperCoverageObservation`
is a separate paper-instance assertion. Its polygon is shown only on its exact
frame, while its current/not-current decision also requires current paper,
source, and camera configuration. It never expands the calibrated region.

Drawing Studio views consume immutable catalog, placement, target-preview,
parameter, and run-state presentations. A video click is inverted through the
current registration into a machine anchor; scale or rotation creates a new
placement and replans. App composition passes the exact accepted plan to
`PersistentMachineSession`, which delegates it to `RunInterpreter`; no view or
workspace loop emits individual controller segments.

For observation, the coordinator preselects the plan's final point, captures a
local baseline there, executes the owner-bound plan, verifies the final MPos,
captures a newer frame, and calls the generic observer under the camera's
exclusive Vision lease. `OverlayResultChannels` retains Drawing Studio workflow
results independently of scene overlays and Stage 4. `DrawingRunEvidenceStore`
owns the checksummed append-only archive. Archive load/append can never restore
runtime ownership or replay a plan. `DrawingReadinessAssessment` is a Model
value consumed only as a presentation capability statement; construction does
not bypass its complete typed requirements.

## Simulator boundary

`SimulatedLearningRuntime` owns a nonphysical controller session, Motion flag,
MPos, pen pose, Boundary motion, large nonzero cap-to-tip truth, paper instance,
16-segment circular marks, line ink, and causal frames. Its frame clock can advance
past an asserted settlement boundary so simulated exact-frame chronology stays
causal.

The simulator uses the same public workspace actions and artifact graph but
never calls production machine actions. Every simulator surface is labeled
`SIMULATED — NOT PHYSICAL EVIDENCE`. An annotation is presentation-only and
cannot alter canonical pixels or hashes.

`OperatorWorkspace` owns two independent `LearningSessionState` values,
one LIVE and one SIMULATED, under one structural contract. Session state owns
the graph, artifact payloads and proposals, attempt histories, accepted-attempt
sequence, quarantine status, paper identity, possible-ink blacklist, drawing
trial state, and learning errors. The active frame source selects which value
all learning projections and mutations address. Camera/controller owners,
operation tasks, Stop capabilities, and other runtime lifetimes remain outside
the session values. One `ActiveStoppableOperation` binds the exact owner task,
contextual Stop target, latched disposition, and cancellation-request phase;
those facts are not independently mutable. Drawing execution likewise carries
typed not-admitted, possible-ink, and naturally-completed state so no-redraw
recovery is independent of presentation wording.

Workflow failures retain typed kind and recovery separately from actionable
presentation text. Boundary disposition, attempt disposition, sparse-mark
blacklisting, current-camera phases, and telemetry failure codes consume those
typed identities through exhaustive switches; rendered text is never parsed to
recover workflow meaning.

Durable machine and tip checkpoint ports are capabilities of the LIVE session
only. SIMULATED receives no active durable checkpoint capability, so its public
actions cannot load, save, clear, replace, or otherwise mutate physical durable
authority. Entering SIMULATED replaces only its previous nonphysical session;
the LIVE session remains stored independently and is selected unchanged on
return.

## Validation structure

Swift Testing suites cover evidence constructors, affine-first construction and
constant construction fallback, checkpoint quarantine and revalidation, graph
dependency shapes, shared-frame unordered clicks, physical-location blacklist
persistence, ActionSurface projection, five-mark batch acceptance, checkpoint
restart/paper recovery, and Stage 4 causal ink, plus drawing catalog/planning,
plan execution, planned-ink observation, paper evidence, and append-only run
evidence. `make quick-test` excludes the explicitly retained journeys;
`make journey-test` runs the current sparse/Stage 4 routes sequentially; and
`make strict-check` applies complete concurrency checking and warnings as
errors in addition to bundle, launcher, full-test, contract, and diff gates.

No automated architecture result is physical validation.
