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
  coordinate-space types, geometry, drawing programs, transforms

PlotterRuntime
  MachineController, RunInterpreter, CameraCapture, VisionWorker
  learning artifacts and dependency graph
  sparse contact evidence, tip model selection, applicability, checkpoints
  causal nonphysical simulator and workflow telemetry

PlotterApp
  OperatorWorkspace orchestration and artifact commits
  SwiftUI Learning Path, ActionSurface, Motion and Video Settings composition
  production checkpoint stores and semantic identity composition

PlotterTestSupport
  deterministic machine links, clocks, transcripts, and paper scenes
```

Dependencies point inward. Runtime does not import SwiftUI. Views receive
projected immutable presentation values and typed closures; they do not own the
controller, camera, calibration, or learning graph.

## Runtime owners

`MachineController` is the only selected serial owner. It parses GRBL, admits
typed requests, serializes commands, proves settlement, and latches sticky
ambiguity. `RunInterpreter` owns one logical run and delegates mechanical
execution to the controller.

`CameraCapture` owns device discovery, authorization, selection, capture
sessions, exact stamped frames, and scoped preview publication holds. A hold
does not stop raw capture. `VisionWorker` owns bounded inference and returns
measurements; it never supplies motion or click authority.

`OperatorWorkspace` maps the selected scene-derived overlay layers to one
newest-only automatic-analysis request and one selected cadence. Video Settings
may lock the current zoomed/panned camera-pixel rectangle as the generic scene
analysis region. `CameraSourceSession` passes that region into
`PlotterSceneAnalysisPipeline`; `VisionWorker` derives all generic cap/frame-side
pixel scan priors within it while retaining whole-frame coordinates and exact
frame identity for every result. Specialized exact-frame workflow measurements
retain their own typed regions.

`OperatorWorkspace` is the single `@Observable` application owner. It composes
controller/camera actors through typed actions, owns Learning Path attempts,
constructs immutable evidence, commits the dependency graph, and exposes
presentation state. It cannot replace controller settlement or exact-frame
provenance with UI state.

LIVE and SIMULATED each own one `LearningSessionState` value under that shared
contract. Within each value, compiler-enforced substates prevent invalid
cross-field combinations: one exercise-attempt lifecycle owns attempt identity,
item owner, and mode; one sparse-selection lifecycle owns pending evidence,
the frozen frame, request, and selected point; and one Drawing Trial state owns
the complete trial payload, history, rollback, and rewind transitions. Supervised
Learning Path travel and settlement carry typed `LearningMotionAction` identity;
display text is derived only at presentation boundaries. These cohesive values
are the intended immutable input seams for a pure Learning Path projector.

`RunLedger` and workflow telemetry record diagnostics only. They do not replay
commands, restore owners, or promote artifacts.

## Sparse calibration data flow

Stage 3.3 builds `CurrentCameraCalibrationPlan` from current Boundary aggregates
and center arrival. `MachineCameraRegistration` retains five machine/cap
correspondences: `C`, `X−`, and `Y+` fit the initial affine map; `X+` and `Y−`
are independent holdouts; acceptance follows the all-five refit.

Stage 3.4 is split across three owners:

- `SparseTipCalibrationCoordinator` owns the fixed position order, exact frozen-
  frame selection states, immutable accepted observation list, possible-ink
  terminal state, holdout review, rejection, and final acceptance state.
- `OperatorWorkspace` owns supervised Pen-Up travel, the full fixed Pen Down
  profile, 16 typed drawing chords capped at 100 mm/min for one centered 2
  mm-radius circle, explicit Pen Up, far X-max/Y-zero-biased reveal travel, actual settled timestamps,
  exact frame/cap capture, UI action routing, and atomic graph/checkpoint commits.
- `TipCalibrationAuthority` owns validated evidence types, smallest-passing
  model selection, uncertainty, applicability decisions, rebase derivations,
  and durable checkpoint validation.

Before a click, `ActionSurfacePointSelectionRequest` binds one frozen
`ExactTipCalibrationFrame` and presentation-transform revision. `ActionSurface`
maps a view click back to camera pixels and initializes a one-third-frame
presentation-only focus around the pre-mark cap anchor. It hides model geometry
before the click, then draws asserted point/uncertainty, prediction, and residual
from `ActionSurfaceTipReviewGeometry`.

The accepted graph shape is:

```text
current MachineCameraRegistration
  -> five ToolContactObservation revisions
  -> current TipCameraRegistration
```

A replacement-paper checkpoint restoration additionally consumes the one new
contact-plane `ToolContactObservation`. Stage 4 line plans and local baselines
consume the exact current tip revision; later line/post-frame/ink/residual nodes
retain that dependency transitively.

## Chronology and possible ink

Live Pen Down and Pen Up timestamps are taken only after the corresponding
settled controller outcomes. Reveal settlement is timestamped after final MPos
acceptance and before a newer exact frame is captured. The reveal cites the
refreshed controller-context baseline returned with that capture.

The no-redraw key is `BlacklistedToolContactLocation`: calibration role, circle
center/radius, and paper-contact-plane revision. `OperatorWorkspace` retains
that set across attempt cancel, restart, and Learning Path reset. The coordinator
re-enters a terminal possible-ink state on the same paper. Explicit paper
replacement rotates the plane identity and is the only workflow recovery.

## Tip checkpoint and semantic identity

Machine-only persistence remains in `AcceptedMachineArtifactCheckpoint`.
`AcceptedTipCalibrationCheckpoint` stores the accepted direct machine-to-tip
registration and acceptance event separately.

Production semantic identities are composed from stable persisted revisions for
machine geometry, tool assembly, pen-contact profile, paper plane, camera mount,
and camera reframing. Capture-session and camera-configuration IDs remain
ephemeral operational provenance; they are not substituted for mount/reframing
identity.

Loading a tip checkpoint sets `quarantinedTipCalibrationCheckpoint` only. A
same-paper restore constructs fresh `TipCalibrationRevalidationEvidence` from a
settled controller/cap frame, rebuilds current graph revisions, and creates a
new accepted tip revision. A paper change retains quarantine and requires one
new accepted circle-center observation. The revalidation evidence is
durable and the new contact revision is a graph dependency. Reset clears the
affected durable machine and/or tip checkpoint before clearing in-memory
authority.

Unknown semantic changes cannot be inferred from a UUID. The attended operator
must refuse revalidation after an unrecorded physical remount or assembly
change; explicit operator-facing revision controls remain a roadmap item.

## Stage 4 ownership

Stage 4 does not reuse a Stage 3 target, baseline, or reveal pose.
`ObservedDrawingTrialLinePlan` creates a 5 mm local line inside the tip
applicability rectangle only when it clears every retained circular-mark
geometry; a crowded domain blocks instead of weakening new-ink attribution. It
stores:

- the exact tip registration revision;
- a trial-local pre-line exact frame and reveal MPos;
- line-start settlement and one drawing owner;
- a Pen-Up return to the same reveal MPos;
- a strictly newer post-line exact frame;
- bounded generic black/new-ink observation, residual, and assessment.

Candidate refinement evidence is append-only. No Stage 4 result automatically
changes the current tip model.

## Simulator boundary

`SimulatedLearningRuntime` owns a nonphysical controller session, Motion flag,
MPos, pen pose, Boundary motion, large nonzero cap-to-tip truth, paper revision,
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

Swift Testing suites cover evidence constructors, holdout/model selection,
checkpoint quarantine and revalidation, graph dependency shapes, frozen-frame
re-click, physical-location blacklist persistence, ActionSurface projection,
five-mark acceptance, checkpoint restart/paper recovery, and Stage 4 causal
ink. `make quick-test` excludes the explicitly retained journeys;
`make journey-test` runs the current sparse/Stage 4 routes sequentially; and
`make strict-check` applies complete concurrency checking and warnings as
errors in addition to bundle, launcher, full-test, contract, and diff gates.

No automated architecture result is physical validation.
