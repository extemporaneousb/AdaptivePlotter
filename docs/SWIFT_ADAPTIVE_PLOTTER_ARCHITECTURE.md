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
  coordinate-space types, geometry, drawing programs

PlotterRuntime
  MachineController, RunInterpreter, CameraCapture, VisionWorker
  learning artifacts and dependency graph
  sparse contact evidence, tip model selection, applicability, checkpoints
  causal nonphysical simulator and workflow telemetry

PlotterApp
  OperatorWorkspace orchestration and artifact commits
  immutable LearningPathProjectionSnapshot and pure LearningPathProjector
  shared VideoPresentationPreferences and WorkbenchWindowState
  SwiftUI combined LearningExercisePane, ActionSurface, Motion and inspectors
  production authority-manifest/safety-history stores and semantic identity composition

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
selection produce identical tree rows and one compact exercise containing a
numbered heading, actor-tagged script, optional question, typed actions, and
invalidation preview. It cannot mutate a session, admit motion, persist,
perform I/O, or accept an artifact. One `LearningExercisePane` consumes one
fresh aggregate projection for both rail and detail and sends selected typed
actions back to `OperatorWorkspace`. Diagnostics separately derives detailed
activity, subsystem, evidence, provenance, and failure facts.

LIVE and SIMULATED each own one `LearningSessionState` value under that shared
contract. Within each value, compiler-enforced substates prevent invalid
cross-field combinations: one exercise-attempt lifecycle owns attempt identity,
item owner, and mode; one sparse-selection lifecycle owns pending evidence,
the frozen frame, request, and selected point; and one Drawing Trial state owns
subject-bound Stage 4 payloads and nonauthoritative history. Supervised
Learning Path travel and settlement carry typed `LearningMotionAction` identity;
display text is derived only by the presentation boundary.

`RunLedger` and workflow telemetry record diagnostics only. They do not replay
commands, restore owners, or promote artifacts.

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

- `SparseTipCalibrationCoordinator` owns the fixed position order, exact frozen-
  frame selection states, immutable accepted observation list, possible-ink
  terminal state, holdout review, rejection, and final acceptance state.
- `OperatorWorkspace` owns supervised Pen-Up travel, the current Pen Interaction
  Up/Down values, 16 typed drawing chords capped at 100 mm/min for one centered 2
  mm-radius circle, explicit Pen Up, far X-max/Y-zero-biased reveal travel, actual settled timestamps,
  exact frame/cap capture, UI action routing, and atomic graph/checkpoint commits.
- `TipCalibrationAuthority` owns validated evidence types, smallest-passing
  model selection, uncertainty, applicability decisions, rebase derivations,
  and durable checkpoint validation.

Before a click, `ActionSurfacePointSelectionRequest` binds one frozen
`ExactTipCalibrationFrame` and presentation-transform revision. `ActionSurface`
maps a view click back to camera pixels without mutating the operator-owned
viewport. It hides model geometry
before the click, then draws asserted point/uncertainty, prediction, and residual
from `ActionSurfaceTipReviewGeometry`.

The accepted graph shape is:

```text
current MachineCameraRegistration
  -> five ToolContactObservation revisions
  -> current TipCameraRegistration
```

A replacement-paper checkpoint restoration additionally consumes the one new
contact-plane `ToolContactObservation`. Stage 4 line plan and local context
consume the exact current tip revision; line-start arrival, execution, atomic
post-line observation, and comparison retain that dependency transitively.

## Chronology and possible ink

Live Pen Down and Pen Up timestamps are taken only after the corresponding
settled controller outcomes. Reveal settlement is timestamped after final MPos
acceptance and before a newer exact frame is captured. The reveal cites the
refreshed controller-context baseline returned with that capture.

`LearningSurfaceExposureLedger` is the sole active-session no-redraw authority
for both calibration circles and isolated lines. A LIVE entry is a conservative
possible-physical-ink reservation atomically persisted before Pen Down and
reloaded by paper identity after process restart; a rejected load or failed save
blocks contact. SIMULATED uses the same typed ledger with explicitly nonphysical
entries and never calls the production store. This safety history is separate
from current accepted Learning authority, survives cancellation and graph
invalidation, and cannot be erased or made eligible for redraw. Explicit paper
replacement rotates applicability without deleting prior entries. If the LIVE
store is corrupt, that same operator transaction archives the rejected bytes and
atomically creates a fresh ledger generation for the replacement paper; the
same-paper blocker is never cleared by treating corruption as empty.

## Learning-authority manifest and semantic identity

`LearningAuthorityManifest` is the only durable accepted-authority store. Its
single generation atomically carries optional `AcceptedMachineArtifactCheckpoint`
and `AcceptedTipCalibrationCheckpoint` payloads in one checksummed envelope.
Every accepted-authority save, and each causal invalidation that removes either
durable payload, uses an exact generation/digest compare-and-commit and one
atomic replacement. Nondurable graph-only invalidation does not depend on the
manifest; there are no independent
machine/tip clear ports or rollback sequence. `OperatorWorkspace` first builds
and validates a pure graph/payload draft, commits the complete manifest, then
performs one nonthrowing in-memory swap and post-commit presentation effects.

Production semantic identities are composed from stable persisted revisions for
machine geometry, tool assembly, pen-contact profile, paper plane, camera mount,
and camera reframing. Capture-session and camera-configuration IDs remain
ephemeral operational provenance; they are not substituted for mount/reframing
identity.

Loading a tip payload sets `quarantinedTipCalibrationCheckpoint` only. A
same-paper restore constructs fresh `TipCalibrationRevalidationEvidence` from a
settled controller/cap frame and creates one new accepted tip revision directly
from the checkpoint summary; it does not counterfeit current raw-observation
nodes. A paper change retains quarantine and requires one new accepted
circle-center observation. The revalidation evidence is durable and the new
contact revision is a graph dependency. An invalidation that removes durable
authority commits the complete manifest generation before replacing in-memory
authority; a nondurable invalidation has no manifest effect.

Unknown semantic changes cannot be inferred from a UUID. The attended operator
must refuse revalidation after an unrecorded physical remount or assembly
change; explicit operator-facing revision controls remain a roadmap item.

## Stage 4 ownership

Stage 4 does not reuse a Stage 3 target, baseline, or reveal pose.
`ObservedDrawingTrialLinePlan` creates a 5 mm local line inside the tip
applicability rectangle only when it clears every retained ink-exposure
geometry; a crowded domain blocks instead of weakening new-ink attribution. It
starts a six-subject chain with one authoritative payload per visible leaf:

- immutable line plan consuming the exact tip registration;
- atomic local baseline/reveal context consuming plan and tip;
- line-start arrival consuming plan and local context, including zero travel;
- LIVE/SIMULATED line-execution evidence consuming plan, context, and arrival;
- atomic post-line observation consuming execution, context, and tip, and
  containing reveal settlement, newer exact frame, bounded observed geometry,
  and required residual;
- typed comparison consuming that observation.

The intended line, observed ink, and residual are contextual Stage 4 results,
not global overlay preferences. The implemented curriculum ends at this
assessment. No Stage 4 result automatically changes accepted calibration.

## Simulator boundary

`SimulatedLearningRuntime` owns a nonphysical controller session, Motion flag,
MPos, pen pose, Boundary motion, large nonzero cap-to-tip truth, paper revision,
16-segment circular marks, line ink, and causal frames. Its frame clock can advance
past an asserted settlement boundary so simulated exact-frame chronology stays
causal.

The simulator uses the same public workspace actions and artifact graph but
never calls production machine actions. The primary Action Surface carries the
concise `SIMULATED` badge; Diagnostics and simulator evidence records carry the
full `SIMULATED — NOT PHYSICAL EVIDENCE` qualification. An annotation is
presentation-only and cannot alter canonical pixels or hashes.

`OperatorWorkspace` owns two independent `LearningSessionState` values,
one LIVE and one SIMULATED, under one structural contract. Session state owns
the graph, subject payloads and proposals, attempt histories, accepted-attempt
sequence, quarantine status, paper identity, one typed surface-exposure ledger,
and learning errors. A current subject revision exists if and only if its exact
authoritative payload is current. The active frame source selects which value
all learning projections and mutations address. Camera/controller owners,
operation tasks, Stop capabilities, and other runtime lifetimes remain outside
the session values. One `ActiveStoppableOperation` binds the exact owner task,
capability, high-level Boundary termination intent, first-winner latch, and cancellation-request phase;
those facts are not independently mutable. Drawing execution likewise carries
typed not-admitted, possible-ink, and naturally-completed state so no-redraw
recovery is independent of presentation wording.

Workflow failures retain typed kind and recovery separately from actionable
presentation text. Boundary disposition, attempt disposition, sparse
surface-exposure recovery, current-camera phases, and telemetry failure codes consume those
typed identities through exhaustive switches; rendered text is never parsed to
recover workflow meaning.

The durable Learning-authority manifest port is a capability of the LIVE session
only. SIMULATED receives no such capability, so its public actions cannot load,
save, clear, replace, or otherwise mutate physical durable authority. LIVE and
SIMULATED session state remain source-isolated; returning to a retained
simulator paper also retains its nonphysical surface-exposure ledger.

## Validation structure

Swift Testing suites cover evidence constructors, holdout/model selection,
checkpoint quarantine and revalidation, graph dependency shapes, frozen-frame
re-click, complete-geometry surface-exposure persistence, ActionSurface projection,
five-mark acceptance, checkpoint restart/paper recovery, and Stage 4 causal
ink. `make quick-test` excludes the explicitly retained journeys;
`make journey-test` runs the current sparse/Stage 4 routes sequentially; and
`make strict-check` applies complete concurrency checking and warnings as
errors in addition to bundle, launcher, full-test, contract, and diff gates.

No automated architecture result is physical validation.
