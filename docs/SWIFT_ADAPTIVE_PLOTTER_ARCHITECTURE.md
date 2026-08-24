# AdaptivePlotter Swift Architecture

Status: current as-built package and ownership architecture

This document owns package boundaries, runtime owners, data flow, and dependency
direction. Product invariants live in [Product Contract](PRODUCT_CONTRACT.md),
the exact operator sequence in
[Discovery and Observed-Trial Protocol](DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md),
the sole target migration in
[Episode Architecture Execution Plan](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md),
and verified status in [Current Evidence](CURRENT_EVIDENCE.md). Planned episode
packages and ownership transfers do not become part of this as-built document
until their work package lands and its superseded path is removed.

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
does not stop raw capture. Exact workflow capture materializes the newest raw
frame with `.returnOnly`; that private value does not enter preview or automatic
analysis until its owning workflow explicitly publishes the validated selection.
Publication is active-generation checked and idempotent. `VisionWorker` owns
bounded inference and returns measurements; it never supplies motion or click
authority.

`CameraSourceSession` owns automatic-analysis configuration and exclusive Vision
leases. Reapplying identical cadence/features, analysis region, or cap color is
a no-op; it does not restart the pipeline or its frame subscription. Semantic
pipeline revisions are pushed to `OperatorWorkspace`. Video Settings counters
and lifecycle statistics are pull-only diagnostics and do not invalidate the
Learning presentation. One caller-supplied exact workflow batch owns one lease
from preview hold through automatic-analysis restoration, including failure or
cancellation settlement.

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

`ActionSurfaceViewportState` owns the current exact presentation pixel
rectangle. `ActionSurfaceViewportContext.fittedRegion` is only a target for an
explicit Fit or zoom action. Compatible context reconciliation snapshots and
retains the effective rectangle even when Exercise 1.3 replaces the fitted target.
`VideoAnalysisRegionLock` is a separate policy copy owned by
`OperatorWorkspace`; Exercise 1.3 does not rewrite it. Source or camera-
configuration incompatibility remains the viewport reset seam.

`PenCapAppearanceSelection` is the only persisted LIVE recognition input. The
first Exercise 1.1 action freezes an exact frame and issues a
`penCapAppearance` point-selection request. `PenCapAppearanceSampler` maps the
operator's cap-body click to a clipped 9 x 9 RGBA/BGRA neighborhood, filters out
gray, white, dark, and otherwise insufficiently chromatic pixels, then records
the channel-wise median RGB color. The stored selection binds that color to the
click point, frame ID and hash, source, camera configuration, dimensions, pixel
format, sample counts, and sampler revision. `CameraSourceSession` applies the
accepted color to both newest-only scene analysis and exclusive Exercise 1.3
inspection. There is no `ColorPicker` owner or mutable color preference seam.

`ExactWorkflowVisionOwner` is the typed app-level identity for the one active
exact inspection: pen-cap appearance, camera calibration, sparse-tip
calibration, observed Drawing Trial, or Drawing Studio. It is projected
separately from automatic overlay analysis. Supervised Pen-Up travel does not
acquire an exact Vision lease and therefore never claims that Vision owns
processing or that preview is held merely because motion is active.

`OperatorWorkspace` is the single `@Observable` application owner. It composes
controller/camera actors through typed actions, owns Learning Path attempts,
constructs immutable evidence, commits the dependency graph, routes view
intent, and reads current state into `LearningPathProjectionSnapshot`. Its
LIVE/SIMULATED session accessor uses read/modify accessors, and related session
writes are batched into one semantic publication instead of copying and
reassigning the complete `LearningSessionState` for each field. It cannot
replace controller settlement or exact-frame provenance with UI state.
Restored-pose revalidation is admission policy for coordinate-dependent
Learning and Drawing actions only. Operator-authored manual jog and manual Pen
actions bypass Learning admission and use the Motion toggle plus the
controller's native connection, alarm, readiness, safety, and serialization
checks.

`LearningPathProjectionSnapshot` is values-only. It contains copied typed facts
and precomputed policy/admission results, not controller or camera actors,
persistence capabilities, task handles, mutating closures, or authority-
changing methods. It also narrows mutable session values such as discovery
transactions and Boundary progress to immutable presentation facts.

`LearningPathProjector` is a pure value. Identical snapshots and review
selection produce identical navigator rows, current item, status, summaries,
action strips, exact Stop capability presentation, evidence, activity,
subsystem status, timeline, scoped reset surface, and stable Learning Path menu
actions. Its navigator projects only curriculum stages and exercises. Controller
connection and Motion authorization remain copied workbench facts; Motion is
normalized false unless a connected session exists. A missing runtime dependency
disables the exercise's existing typed action with a precise remedy rather than
creating a Learning Path row or generic forward action. It cannot mutate a session,
admit motion, persist, perform I/O, or accept an artifact. SwiftUI consumes one
aggregate projection per Learning Path render and sends selected typed actions
back to `OperatorWorkspace`. `OperatorWorkspace` builds one revision-keyed
Learning presentation base containing the snapshot, reset plans, current item,
current projection, and Exercise-pane protection. It also retains one
revision-and-selection-keyed review projection. Only a semantic Learning input
change advances that revision and invalidates those caches; exact-frame pixels,
unchanged Vision requests, and pull-only diagnostics do not. Action Surface
presentation has a separate revision so video/overlay changes do not force a
Learning snapshot/reset-plan rebuild. The destructive Reset All Learning action is
presented in the navigator menu; the exercise detail presents only the scoped
Reset From This Step action.

`WorkbenchLayoutState` owns window-local pane visibility and Video Settings
presentation as one value. A permitted Show computes protected-pane collapse
and commits the complete next layout in one synchronous main-actor assignment;
there is no pending Show or `Task.yield()` phase. The same cached action-strip
projection supplies Exercise-pane protection, so a pane containing the active
Stop remains visible without performing another Learning projection.

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
commands, restore owners, or promote artifacts. The existing persistent machine-
session owner retains at most 10 complete SQLite session groups and 50 MiB;
unknown files are not deleted. Camera startup does not record PNG samples.
Only explicit operator snapshots/evidence may create camera sample files.

Exercise 1.4 workflow telemetry schema v2 records one ordered semantic sequence:
batch admission, one completion event for each whole 16-chord circle, reveal,
and terminal disposition. Individual chords emit no workflow telemetry.
`RunInterpreter` forwards these non-authoritative facts to
`MachineController`'s existing ordered ledger-write tail. Enqueue is non-blocking
with respect to workflow progression; disconnect drains the tail, and encoding
or storage failure is reported diagnostically rather than becoming admission or
evidence authority.

`DrawingProgramCatalog` produces deterministic field-space geometry. A
`DrawingPlacement` is the only field-to-machine transform, and `DrawingPlanner`
is the only producer of content-addressed `ExecutionPlanRevision` values.
`DrawableMachineRegion` applies the shared minimum continuous-coordinate tolerance;
planning refuses geometry outside that tolerance-aware region and neither App
nor Runtime clips it. `RunInterpreter` owns a whole plan as one `RunOperation`, with
subordinate Pen-Up travel, pen actuation, finite drawing segments, Stop, and one
checkpoint per logical stroke. `PlannedDrawingObservation` operates only after
execution and returns exact-frame observed/residual evidence or a typed
rejection; it has no motion, resend, or promotion capability.

## Exercise 1.1 and manual controls

`OperatorWorkspace` starts Exercise 1.1 with **Identify Pen Cap**. Until the
exact-frame cap-body click is accepted, no pen-position question is opened
and no pen request is issued. Rejection or stale provenance leaves the point
selection pending. Cap identification itself does not require a controller
session or Motion. After acceptance, the first question remains active; its
**Confirm Pen Up** action and servo slider are dependency-blocked until connection and
Motion exist, while the external controller toolbar remains operable. The
exercise's Up and Down sliders then issue typed value-bearing pen requests;
**Confirm Pen Up** or **Confirm Pen Down** retains the displayed value in the current setting and the existing
attempt evidence. `MachineController`
serializes the requested value and settlement under its existing pen-operation
ownership. There is no parallel servo-calibration owner, checkpoint, or
artifact graph.

On an automatic Pen Down or Pen Up, `DiscoveryTransaction` applies the settled
controller outcome and presents the immediately following question as one
validated transaction transition. `OperatorWorkspace` publishes the resulting
transaction and command evidence in one session mutation and one semantic
revision, so the next action strip is not delayed behind an intermediate
post-settlement projection.

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
500 mm/min while remaining editable. Manual direction routing normally depends
on direct controller facts and the current commanded pen state, not Learning
Path completion or restored-pose applicability. A restored durable session may
leave coordinate-dependent Learning and Drawing gated until fresh cap
revalidation, but it does not gate direct manual motion or manual Pen commands.
Known Down
uses drawing ownership; Up or unknown uses ordinary manual-jog ownership, with
unknown pose preserved in the resulting evidence.

## Sparse calibration data flow

Exercise 1.3 builds `CurrentCameraCalibrationPlan` from current Drawing Boundary aggregates
and center arrival. `MachineCameraRegistration` retains five machine/cap
correspondences: `C`, `X−`, and `Y+` fit the initial affine map; `X+` and `Y−`
are independent holdouts; acceptance follows the all-five refit. Publishing the
accepted registration also publishes learned fitted presentation bounds, but
that target change does not change the current exact viewport rectangle, camera
evidence, or a compatible `VideoAnalysisRegionLock`.

For each LIVE correspondence, `OperatorWorkspace.captureStableWorkflowCap`
acquires exactly three strictly newer exact `inspectWorkflowScene` results after
a preliminary frame boundary. `FixedCameraOpticalSettlingPolicy` requires one
source/configuration, exact measurement/frame identity, an accepted unambiguous
cap in every frame, and maximum pairwise component-centroid spread of at most 2 px.
It returns the newest third inspection unchanged; no centroid, bounds, or
confidence is averaged. The preliminary frame is freshness control, not accepted
cap evidence. All three strictly newer samples are materialized `.returnOnly`
inside one exclusive `CameraSourceSession` lease. Only the selected newest stable
sample is explicitly published, once; failure or cancellation publishes none,
settles that same lease, and restores the requested automatic-analysis stream.
SIMULATED causal geometry is source-separated nonphysical evidence and cannot
establish live optical stability.

Exercise 1.4 is split across four owners:

- `SparseTipCalibrationCoordinator` owns the compact batch state machine, one
  attempt/operation identity, four canonical corner evidence slots,
  one shared final frozen frame, unordered click collection, immutable accepted
  observations, possible-ink terminal state, proposal review, and acceptance.
- `SparseTipBatchMarkPlan` derives the four mark centers from the accepted
  Drawing Boundary
  Boundary envelope with one canonical 10 mm inset, drawing no center mark. Its
  2 mm-radius outlines therefore retain 8 mm of adjacent-edge clearance. Its
  corner-center rectangle is the proposed tip-map
  applicability rectangle, and its final reveal pose is the rectangle center.
- `OperatorWorkspace` composes that plan as one typed batch. It performs one
  initial Pen-Up normalization, preserves that batch-scoped Pen-Up authorization
  across approach/start/reveal travel, and consumes four Pen Down plus four
  post-circle Pen Up settlements. The complete batch therefore has five Pen Up
  settlements, 64 typed chord outcomes, four pre-mark controller-context probes,
  one reveal probe, and one final machine snapshot. Per-chord progress remains
  controller typed for Stop and possible-ink handling but does not rebuild a
  Learning projection or fetch another workspace machine snapshot. The existing
  camera presentation renders the accepted Drawing Boundary separately from the
  inset proposed/accepted Drawing Border; Exercise 2.1 later draws that physical
  connecting Border. Exercise 1.3 retains its center plus four
  ±24 mm positions.
- `TipCalibrationAuthority` owns validated evidence types, four-corner affine-first
  construction, constant construction fallback, diagnostic residual/covariance/
  uncertainty, applicability decisions, rebase derivations, and checkpoints.

`ActionSurfacePointSelectionRequest` binds the shared frozen
`ExactTipCalibrationFrame` and presentation-transform revision. `ActionSurface`
maps each view click back through the exact inverse presentation transform,
renders click count and all markers, and supports same-frame undo/clear without
motion, ink, capture, zoom, or pan. Tip-map acceptance installs the outer-center
applicability rectangle without changing viewport state.

After click four, the app projects all four corner machine positions through
current `MachineCameraRegistration`, centers projected and clicked sets to
remove their common cap-to-tip translation, evaluates all 4! assignments, and selects the
minimum total squared pixel distance with canonical-position exact-tie breaking.
There is no distance or ambiguity gate. The four associated observations feed
direct affine construction first; constant correction is constructed only when
affine construction throws. Residuals, RMS, covariance, and uncertainty are
diagnostic and never block progression.

The accepted graph shape is:

```text
current MachineCameraRegistration
  -> four corner ToolContactObservation revisions
  -> current TipCameraRegistration
```

A new paper instance on an explicitly unchanged contact plane consumes no new
contact observation and retains tip authority. A changed contact plane
invalidates the tip registration and requires the normal four-observation
Exercise 1.4 graph. Stage 2 Drawing Border plans and local baselines consume the exact current
tip revision; later frame/post-frame/ink/residual nodes retain that dependency
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

## Learning Path checkpoint and semantic identity

`AcceptedLearningPathCheckpoint` is the single atomic production envelope for
the accepted LIVE prefix. It composes the accepted Exercise 1.1 record,
`AcceptedMachineArtifactCheckpoint`, Exercise 1.3 registration/revision,
`AcceptedTipCalibrationCheckpoint`, accepted pen-cap appearance, one bounded
reference frame, and the Exercise 2.1 drawing-evidence reference.
The inner types retain their domain validation and provenance; the envelope
owns cross-stage semantic identity and atomic storage.

Production semantic identities are composed from stable persisted revisions for
machine geometry, tool assembly, pen-contact profile, paper instance, paper
contact plane, camera mount, and camera reframing. Capture-session and camera-configuration IDs remain
ephemeral operational provenance; they are not substituted for mount/reframing
identity.

Loading produces one exhaustive saved-package candidate and mutates no
`LearningDependencyGraph` or registration owner. `OperatorWorkspace` projects
compatible saved geometry and uses the package's one bounded reference frame to
produce an advisory integer-shift/background-MAD report. **Use Saved Learning**
calls the checkpoint-owned exact graph reconstruction once, stages all fallible
decoding locally, then assigns the complete accepted prefix atomically. **Start
New Learning** retains the package but applies no values. Neither action restores
Motion authorization, Pen state, controller pose trust, frames, operation
owners, or Stop capabilities, and neither issues motion.

Explicit changed-coordinate recovery may still construct fresh
`TipCalibrationRevalidationEvidence` and rebase the machine checkpoint,
`MachineCameraRegistration`, and `TipCameraRegistration` under one new
coordinate revision when a pure translation is actually proven. Direct manual
controls remain independent. Replacing only the
paper instance retains that authority; changing the contact plane invalidates
it and requires the full four-mark calibration. The revalidation evidence is
durable. Reset clears the affected durable machine and/or tip checkpoint before
clearing in-memory authority.

Process restart does not rotate persisted semantic identities. Unknown physical
changes still cannot be inferred from a UUID: after an unrecorded camera bump,
machine reset, remount, or assembly change, the operator must use the owning
reset rather than accepting unchanged restoration. Explicit operator-facing
revision controls remain a roadmap item.

## Stage 2 ownership

Stage 2 does not reuse a Stage 1 target, baseline, or reveal pose.
`DrawingBorderPlan` creates one closed polyline through the four accepted
10 mm-inset circle centers, with four orthogonal edges and right-angle turns.
`OperatorWorkspace` supplies the accepted Drawing Boundary—not that inset
Drawing Border—as the plan's `DrawableMachineRegion`, with the canonical 0.5 mm
continuous-coordinate tolerance.
The visible 2.1 row owns one attempt from **Draw and Validate Drawing Border** through normal comparison; its
six typed phases update activity and subsystem presentation but do not create
six UI action owners. It stores:

- the exact tip registration revision;
- a trial-local pre-frame exact frame and reveal MPos;
- Drawing-Border-start settlement and one canonical drawing-plan owner;
- a Pen-Up return to the same reveal MPos;
- a strictly newer post-frame exact frame;
- bounded generic black/new-ink observation, residual, and assessment.

Before motion, `OperatorWorkspace` projects the stored closed machine path through
the exact current `TipCameraRegistration`. `ActionSurfacePresentation` binds the
planned polyline to each currently displayed frame/configuration, so the cyan
prediction remains visible over live video without freezing preview or treating
planned geometry as measured pixels. The post-frame observer replaces that
preview with exact-frame intended, measured-ink, and residual overlays.

The typed `ExactWorkflowVisionOwner.observedDrawingTrial` is projected separately
from background scene-analysis state. While planned-drawing comparison is in
flight, Learning reports **Trial ink analysis · active** and names Vision as the
processing owner.
Normal observed-ink success commits the typed comparison in the same exercise
attempt. Only a failure, ambiguity, possible-ink recovery, rejected observation,
or atomic-commit error ends the automatic chain early.

Planned observation uses alignment revision
`bounded-subsampled-finalist-background-mad-v2`: it scores the complete bounded
integer-shift envelope on a deterministic two-pixel lattice, then evaluates at
most three finalists at full resolution. Coarse scores never become acceptance
evidence. Alignment, new-ink extraction, and path association expose bounded
cancellation checkpoints; cancellation returns typed `computationCancelled`,
publishes no partial observation, and settles the one exclusive Vision lease.
Successful evidence records exact work counters and algorithm revisions as
diagnostics. Intended overlays retain planned provenance, observed ink retains
measured provenance, and residuals retain diagnostic provenance on the exact
post-frame.

The intended Drawing Border, observed ink, and residual are contextual Stage 2 results,
not global overlay preferences. The implemented curriculum ends at this one
attributable validation. Its post frame and overlays remain explicitly
reviewable, and its typed comparison is adapted into an evaluation-holdout
`DrawingRunEvidenceRecord`. No Stage 2 result automatically changes accepted
calibration or establishes a generally trained adaptive model.

## Drawing Studio ownership

`OperatorWorkspace` derives the drawable region from the accepted Drawing Boundary
and projects it with the current registration's inferred affine transform, including
the area between the inset applicability rectangle and Boundary, alongside the
predicted current tip point. This does not enlarge the recorded tip-calibration
applicability. `PaperCoverageObservation`
is a separate paper-instance assertion. Its polygon is shown only on its exact
frame, while its current/not-current decision also requires current paper,
source, and camera configuration. It never expands the accepted Drawing Boundary.

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
results independently of scene overlays and Stage 2. `DrawingRunEvidenceStore`
owns the checksummed append-only archive. New records embed the complete
immutable `ExecutionPlanRevision`, allowing prior planned paths to be
reprojected without making the archive executable; legacy hash-only records
remain readable but explicitly lack reconstructable geometry. Archive load/append can never restore
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

The durable Learning Path checkpoint port is a capability of the LIVE session
only. SIMULATED receives no active durable checkpoint capability, so its public
actions cannot load, save, clear, replace, or otherwise mutate physical durable
authority. Entering SIMULATED replaces only its previous nonphysical session;
the LIVE session remains stored independently and is selected unchanged on
return.

## Validation structure

Swift Testing suites cover evidence constructors, affine-first construction and
constant construction fallback, checkpoint quarantine and revalidation, graph
dependency shapes, shared-frame unordered clicks, physical-location blacklist
persistence, ActionSurface projection, four-mark batch acceptance, checkpoint
restart/paper recovery, and Stage 2 causal ink, plus drawing catalog/planning,
plan execution, planned-ink observation, paper evidence, and append-only run
evidence. `make quick-test` excludes the explicitly retained journeys;
`make journey-test` runs the current sparse/Stage 2 routes sequentially; and
`make strict-check` applies complete concurrency checking and warnings as
errors in addition to bundle, launcher, full-test, contract, and diff gates.

No automated architecture result is physical validation.
