The fresh critic strengthened the plan around atomic commits, aggregate semantics, simulator Stop races, and numeric-versus-camera compatibility. The copy-paste execution prompt is below.
# AdaptivePlotter Boundary Evidence, Coordinate, and Simulator Correctness Implementation

You are the coordinating implementation agent for:

`/Users/bullard/Projects/AdaptivePlotter`

This is an execution request. Do not stop after analysis, planning, worker handoff, compilation, or an unlanded branch. Plan, freeze contracts, implement every lane, integrate, delete superseded code, reconcile documentation, validate, and land the completed change through Blackdog.

## Observed defect and fixed diagnosis

The attended failure occurred after a valid operator Stop:

- the logical Boundary owner admitted and moved;
- Stop latched;
- one Jog Cancel was sent;
- the original owner reached Idle with final MPos;
- a strictly newer frame was captured;
- boundary completion then failed with:

`Drawing-frame posterior update failed: candidateEdgeAlreadyAssociated(candidateEdgeIndex: 0)`

The failing run included these accepted controller positions:

- X−: `X -351.473 Y -38.877`
- X+: `X -164.923 Y -38.877`
- Y−: `X -351.473 Y -76.534`
- Y+: `X -351.473 Y 82.633`

These imply:

- X span: `186.550 mm`
- Y span: `159.167 mm`
- raw estimated center: `X -258.198 Y 3.0495`

The Stop/cancel/Idle/final-MPos sequence worked. Failure occurred afterward because `DrawingFramePosterior` assigned each machine direction to the nearest detected quadrilateral edge and prohibited two directions from selecting the same candidate edge.

Machine direction is already established by the typed operator action. Nearest camera edge is not machine authority and must never veto an otherwise valid boundary observation.

The current simulator also masks this defect by manufacturing direction-specific quadrilaterals. It uses a fixed 4 pixels/mm mapping, renders little contextual geometry, reaches its known boundary before publishing Stop, and does not naturally execute ordinary simulated manual jogs. These defects are part of this corrective increment.

## Required working method

1. Before editing, read completely:

   - `AGENTS.md`
   - `.codex/skills/adaptiveplotter/SKILL.md`
   - `README.md`
   - `docs/FEASIBILITY_REVIEW_AND_BINDING_AMENDMENTS.md`
   - `docs/PROJECT_SCOPE_AND_MODEL_TRAINING.md`
   - `docs/SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md`
   - `docs/SWIFT_ADAPTIVE_PLOTTER_SEQUENTIAL_REBUILD.md`
   - `docs/implementation/CURRENT_IMPLEMENTATION_STATUS.md`
   - `docs/implementation/VISIBILITY_TARGET_AND_CLEAR_VIEW_PROTOCOL.md`
   - `docs/implementation/FIRST_HARDWARE_SESSION.md`
   - `docs/implementation/LEARNING_WORKBENCH_MULTI_AGENT_EXECUTION_PROMPT.md`

2. Use one supervisor-owned Blackdog task and its returned task workspace.

   - Use `--actor codex-supervisor`.
   - The coordinator alone runs Blackdog begin, land, close, recovery, and cleanup commands.
   - Workers share the returned task workspace.
   - Workers do not create tasks, branches, worktrees, commits, PRs, or landings.
   - Treat every structured `next_action` as the sole authority and execute its exact command or stop at its blocker.

3. Preserve unrelated user changes. Confirm the initial branch, commit, dirty state, Blackdog-selected target branch, and task workspace before editing.

4. Inspect current source and tests before assigning files. Publish:

   - a concise implementation plan;
   - exact file ownership;
   - frozen shared types and signatures;
   - artifact dependency edges;
   - authority boundaries;
   - deletion targets;
   - focused and broad validation matrices.

5. Dispatch exactly three workers in parallel after the contract is frozen. Every file has one owner. Workers may inspect any file but edit only their lane. A worker reports an insufficient seam instead of editing another lane.

6. Require the nine-part worker handoff:

   1. behavior delivered;
   2. exact files changed;
   3. exact types/tests deleted or replaced;
   4. superseded surfaces removed;
   5. commands and results;
   6. skipped validation;
   7. residual concerns;
   8. scope confirmation;
   9. authority confirmation.

7. The coordinator owns integration, shared-contract resolution, documentation, missing work, full validation, deletion audits, diff review, commit, Blackdog landing, and final clean-state verification.

## Product outcome

Deliver a Boundary workflow in which:

```text
typed side selection
→ explicit Start
→ one logical operator-stopped owner
→ typed operator Stop
→ close segment renewal
→ one Jog Cancel byte
→ await original owner through Idle and final MPos
→ establish post-settlement freshness boundary
→ capture one strictly newer exact frame
→ obtain one typed bottom-center tool-contact observation
→ atomically commit the side sample and accepted side aggregate
→ update paired progress and derived machine center
→ expose the next truthful action
The exact frame and tool-contact sample remain required evidence for downstream machine-camera registration. However:
no detected drawing-frame edge;
no nearest-edge classification;
no candidate-edge uniqueness;
no inferred quadrilateral association;
and no closed drawing-frame posterior
may determine whether the selected machine side is X−, X+, Y−, or Y+ or veto its successful commit.
Generic DrawingFrameEstimate, FrameSideMeasurement, automatic scene analysis, and generic measured/inferred overlays may remain where they have independent diagnostic consumers. They are not Boundary completion authority.
Frozen boundary sample and aggregate model
Freeze two separate typed concepts.
Immutable attempt evidence
Add or evolve a typed BoundarySideAttemptEvidence containing at minimum:
ExerciseAttemptID;
BoundaryDirection;
controller session ID;
coordinate revision;
logical Boundary owner ID;
contextual Stop capability ID or equivalent immutable owner reference;
typed Stop disposition;
final settled MachinePosition;
frame source;
exact FrameID;
frame SHA-256;
capture timestamp;
CameraConfigurationID;
ToolContactPointEstimate;
contact estimator revision and confidence;
attempt disposition.
Do not include a candidate frame edge, inferred side index, or averaged frame/contact value.
Partial unsuccessful evidence remains attributable when available, but unsuccessful attempts cannot contribute a successful numeric value or accepted artifact.
Per-direction accepted aggregate
Add or evolve a typed BoundarySideAggregate for each direction containing:
direction;
current aggregate revision ID;
controller session and coordinate revision;
estimate in millimetres;
valid sample count N;
declared estimator/revision;
typed uncertainty, including explicit unavailable uncertainty when N == 1;
included attempt IDs;
superseded/excluded attempt provenance.
Numeric aggregation compatibility is defined by:
direction;
controller session;
coordinate revision;
machine coordinate space;
millimetre units;
numeric estimator revision.
Camera configuration is not part of numeric Boundary compatibility. A camera restart must not split, discard, or invalidate machine-space side estimates or the estimated center.
Optical registration compatibility remains separate and includes source, camera configuration, controller context, exact frame, contact-estimator revision, and algorithm revision.
Redo and Record Another
Freeze these semantics:
Record Another <side> Attempt adds one compatible successful sample, recomputes the side aggregate as N + 1, and atomically recomputes or invalidates the center and its explicit consumers.
Redo <side> Boundary replaces the entire currently accepted per-direction aggregate. On success, all formerly included samples remain provenance but cease contributing to the current aggregate; the successful replacement begins at N == 1.
A successful replacement supersedes the previous accepted aggregate revision.
A failed, refused, cancelled, or ambiguous Redo leaves the old aggregate, included sample set, graph revision, center, arrival, and downstream accepted authority unchanged.
Test Redo after an aggregate already has at least three included samples. Do not leave the existing ambiguity of replacing one sample while calling the result a replacement of the accepted step.
If the generic attempt-history API cannot atomically supersede an entire included set, add the narrow typed operation required by this exercise. Do not introduce a generic evidence bag or global workflow store.
Atomic boundary commit
Do not write candidate data into accepted-looking workspace fields before successful commit.
Stage copies of all affected values:
attempt history;
exact attempt evidence;
side aggregate;
artifact graph;
paired-direction progress;
estimated center;
local coordinate frame;
overlays/presentation evidence;
invalidated revision IDs.
Validate every candidate and dependency first. Swap the staged values into current authority only after all validations succeed.
Inject deterministic failures at these boundaries and prove no accepted partial mutation:
settlement failure;
missing newer frame;
missing or rejected contact estimate;
aggregate construction;
artifact-graph commit;
center derivation;
local-coordinate derivation.
Failure provenance may append separately, but accepted facts must remain byte-for-value equivalent at the model level.
boundaryPositions[direction] must not be overwritten by a failed replacement candidate. Prefer one attempt-bound pending value and one accepted aggregate authority instead of two competing “current” position stores.
Artifact graph
Replace the current boundary graph shape with explicit current aggregate dependencies:
BoundarySideAggregate(X−) ─┐
BoundarySideAggregate(X+) ─┼→ EstimatedMachineCenter
BoundarySideAggregate(Y−) ─┤          ↓
BoundarySideAggregate(Y+) ─┘     CenterArrival
                                      ↓
                           downstream consumers that
                           explicitly cite these revisions
Machine-camera registration separately consumes compatible exact machine/contact samples plus its target validation capture. It does not consume nearest-edge associations or averaged frames.
Delete graph kinds whose only purpose is the outgoing classifier:
.boundaryPosterior(direction)
.boundaryAssociation(direction)
Use one clearly named current aggregate artifact kind, such as:
.boundarySideAggregate(direction)
Do not retain aliases for the deleted graph kinds.
A camera change invalidates optical registration and camera-derived descendants. It does not invalidate side aggregates, estimated center, center arrival, or the learned local coordinate frame.
A successful side replacement invalidates only the center and explicit transitive consumers. A failed replacement changes no accepted graph edge.
Remove the nearest-edge family completely
Delete the boundary-specific family when its consumers are removed:
DrawingFramePosteriorError
DrawingFrameBoundaryObservationKey
DrawingFrameBoundaryObservation
DrawingFrameSideAssociation
DrawingFrameSidePosterior
DrawingFrameCorner
DrawingFramePosterior
adjustDrawingFramePosterior
drawingFramePosteriorAdjusted
boundary-only posterior state, observation maps, rollback snapshots, graph branches, overlays, invalidation branches, text, and dedicated fixtures
boundary-side-posterior-v1
human-guided-discovery-posterior-v1
the adjust-posterior discovery step
Replace the Boundary sequence’s posterior phase with a typed atomic boundary-observation commit.
Do not broadly delete:
generic DrawingFrameEstimate;
generic FrameSideMeasurement;
generic scene-analysis overlays;
ToolContactPointEstimate;
MachineCameraRegistrationFit;
MachineCameraRegistration;
CameraOverlayMeasurement;
Pen Interaction’s separate fresh-frame capture.
The generic drawing-frame diagnostic may fail or be absent without failing Boundary Discovery.
Failed attempt routing and actionable activity
Fix the current Cancel-only/Restart-only deadlock.
Normal attempt with no accepted result
After the owner has settled:
record the exact failed/refused/cancelled disposition;
finish and clear the active owner;
offer typed Restart only when a real restart route exists;
suppress Restart under sticky ambiguity;
retain the exact missing fact and recovery explanation.
Replacement or additional attempt with an accepted fallback
After failed, refused, or cancelled settlement:
retain the old aggregate and every accepted dependency;
append excluded attempt provenance;
finish and clear the replacement/additional owner;
do not set a stage-global restartableExerciseItemID;
do not make the failed reviewed row the runtime current step;
do not replace the normal current interactive action strip;
show the failed attempt as activity on the reviewed row;
restore the explicit side-bearing Redo/Record Another actions;
if all four accepted sides exist but center arrival does not, keep Move to Estimated Center available;
if runtime current has advanced, keep it advanced and preserve Return to Current.
An ambiguous replacement/additional attempt also retains the accepted fallback for review, but sticky ambiguity disables all new physical motion with the exact reason.
Generic Restart is for failed normal attempts. A replacement retry must remain a typed replacement intent carrying the exact side and accepted revision it intends to replace.
Typed activity record
Replace stage-global loose-string inference with a narrow typed activity record containing:
stable activity ID and occurrence time;
actor;
typed operation/action;
phase, such as admission, moving, Stop latched, settling, frame capture, contact measurement, commit, or recovery;
exact disposition;
attempt ID;
side;
operation owner and Stop capability IDs where applicable;
final MPos where available;
exact frame/configuration references where consumed;
affected or retained artifact revision IDs;
structured detail;
structured recovery;
whether an accepted fallback remains current.
This record is reporting/provenance only. It is not eligibility authority, a generic event bus, persistence, or replay.
The UI should produce language such as:
Actor: Vision
Action: Record X+ boundary contact
Outcome: Failed after controller settlement
Detail: Stop succeeded at final MPos and a fresh frame was captured, but no acceptable tool-contact estimate was available.
Accepted result: The previous X+ aggregate remains current.
Recovery: Continue with the accepted boundaries, or explicitly retry X+.
Never expose a raw Swift enum such as candidateEdgeAlreadyAssociated(...) as the only operator explanation.
Learned local coordinates
Preserve raw GRBL MPos exactly. It is millimetre-valued controller position relative to the controller’s current coordinate origin, not raw motor-step count and not universal paper coordinates.
Add a typed, derived LearnedLocalCoordinateFrame with:
controller session;
coordinate revision;
lower-side origin derived from accepted X− and Y− aggregate estimates;
X/Y spans;
four consumed aggregate revision IDs;
estimator revision;
explicit millimetre units;
invertible raw-to-local and local-to-raw conversion.
The local mapping is:
local.x = raw.x - acceptedXMinus
local.y = raw.y - acceptedYMinus
For the observed regression fixture:
raw X− = -351.473
raw X+ = -164.923
raw Y− = -76.534
raw Y+ = 82.633

local X range = 0 ... 186.550
local Y range = 0 ... 159.167
local center = 93.275, 79.5835
After all four sides are accepted:
show local coordinates as the primary learned-area presentation;
label the coordinate frame and millimetre units;
retain raw Controller MPos as secondary provenance;
show local spans and center.
Before all four sides exist:
show raw Controller MPos;
explain that positive/negative signs are relative to the controller origin;
do not manufacture a local frame.
This local coordinate frame is not:
homing;
a controller work offset;
a rewritten MPos;
camera calibration;
an entered envelope;
clamping;
collision protection;
motion admission;
a learning-stage gate.
It must not appear in MachineController or RunInterpreter motion-admission inputs.
Simulator viewport and causal presentation
Keep the existing shared ActionSurface camera-pixel-to-view aspect-fit renderer. That transform is already correct and must remain common to LIVE and SIMULATED.
Replace only the defective simulated-world-to-camera mapping.
World-to-camera transform
Add a pure, invertible typed transform such as SimulatedWorldToCameraTransform or SimulatedCameraViewport derived from:
arbitrary translated or negative SimulatedLearningBoundaryTruth;
frame width and height;
declared padding;
declared armature/protocol margin.
Requirements:
one uniform aspect-fit scale;
no independent fixed pixelsPerMillimeter initializer controlling scene size;
arbitrary translated and negative worlds are centered correctly;
all truth-boundary corners and declared armature/target extents remain inside the padded frame;
machine X+ maps consistently to the right;
the Y convention is explicit and tested while camera pixels remain top-left/+Y-down;
the transform remains stable within one camera configuration;
any true refit rotates CameraConfigurationID;
every SimulatedLearningSceneFrame includes the exact transform or viewport identity used for its pixels.
Use this transform for:
armature/contact rendering;
persistent ink;
visibility target;
line drawing;
all machine-space scene geometry.
Do not create a second SwiftUI renderer.
Presentation-only simulated annotations
Add exact-frame/configuration-bound simulated annotations for:
simulation truth envelope;
X−, X+, Y−, Y+ axes/direction labels;
accepted learned-side markers;
accepted learned center, only once learned;
current contact/MPos;
a bounded recent motion trail;
current operation direction/owner;
target ROI where defined;
existing ink.
Clearly distinguish simulator truth from accepted learned evidence.
Annotations:
are marked SIMULATED;
carry exact frame/configuration identity;
include typed kind, anchor/geometry, visible label, accessible value, and algorithm revision;
hide when stale;
are presentation only;
must not be baked into canonical pixels used by vision;
must not affect frame SHA, target detection, ink observation, artifacts, or authority;
begin visible by default.
Toggling or resizing annotations must change presentation only and leave frame bytes, frame identity, evidence, and learning state unchanged.
Cooperative simulated Boundary motion
Fix simulated Boundary timing:
publish the unique Stop capability immediately after owner admission;
begin cooperatively paced finite segment execution under that same owner;
recheck the first-intent latch before every segment and before every causal frame update;
advance the displayed causal frame after each accepted segment;
allow Stop, Cancel, or shutdown to win before renewal;
a Stop-versus-segment/frame race must emit no later motion or frame mutation;
reaching simulator truth must not naturally succeed;
at truth, stop generating zero-motion renewals and remain efficiently active awaiting Stop, Cancel, or shutdown;
operator Stop at truth records the successful side;
natural finite segment completion remains non-evidence;
ambiguity remains sticky and emits no following segment/frame.
Simulated manual motion
Fix simulated manual jog so it:
publishes Stop Manual Jog for the admitted owner;
starts the runtime’s cooperative natural executor;
naturally completes a finite request;
refreshes the causal frame on completion;
remains interruptible so deterministic pacing can let Stop win before the delta is applied;
creates no Boundary evidence.
Remove fabricated simulator geometry
Delete the direction-conditioned quadrilaterals currently created in captureDiscoveryInspection to avoid candidate-edge collisions.
Selecting X versus Y must not change scene geometry by itself. One causal simulated world transform and runtime state determine the frame.
Remove dead simulator UI
Audit SimulatorModelMode and the visible PRIOR MISMATCH / ACCEPTED MODEL picker.
If, as current inspection indicates, it changes only a label and recaptures the same causal frame, delete the picker, app state, routes, and dedicated UI tests. Do not pretend Adaptive Drawing model comparison exists.
Preserve independently named generic model-mismatch renderer/test-support types only if they still have a real, explicit non-UI test consumer. Do not retain dormant app compatibility controls.
Camera-change behavior
Keep numeric and optical compatibility separate:
accepted Boundary aggregates, estimated center, center arrival, and local coordinate frame survive a camera restart while controller session and coordinate revision remain current;
exact contact samples retain their original camera configuration;
optical registration uses only a named compatible subset of included exact machine/contact samples;
do not average frames or contact points before registration;
MachineCameraCorrespondenceProvenance must retain frame SHA, capture time, attempt ID, contact estimator/confidence, source, camera configuration, controller session, coordinate revision, and artifact revision;
a camera change invalidates the optical registration and camera-derived descendants;
a camera change alone must not route runtime current back to 3.2 or relabel a physical Boundary redo as “Refresh Camera Contact.”
If the current camera configuration lacks enough compatible registration samples, report that exact 3.3 registration unavailability. Recovery must be an explicit, typed evidence-collection action; it must not silently redo a Boundary, move the plotter, or erase accepted machine-space evidence. Do not add a hidden registration workflow or automatic motion.
Simulator and physical authority isolation
SIMULATED must retain:
the identical visible Learning Path and public performExerciseAction seam;
the same action locations;
causal state and frames;
explicit SIMULATED — NOT PHYSICAL EVIDENCE;
zero calls to physical MachineActions;
parked LIVE authority restored unchanged after leaving SIMULATED.
Simulator truth, viewport bounds, overlays, local coordinates, and model state are never:
physical evidence;
entered workspace limits;
manual-motion guards;
camera calibration;
permission to draw;
evidence that ink physically exists.
Direct authority constraints
Do not alter or duplicate MachineController’s direct checks:
selected responsive controller session;
current internal Enable Motion authorization;
recognized state/alarm/pins;
known MPos where consumed;
typed finite deltas;
applicable feed;
commanded pen state;
one operation owner;
sticky ambiguity.
Do not add:
homing;
reset/unlock/alarm clear;
firmware writes;
entered bounds;
learned-envelope admission;
camera requirement for ordinary manual jog;
boundary-count prerequisite for unrelated motion;
arbitrary application travel horizons;
automatic resend;
automatic redraw;
model-selected movement;
a second controller state machine;
a global workflow store;
persistence/replay;
generic evidence bags;
compatibility aliases;
speculative repository policy guards.
RunInterpreter and MachineController are inspection/regression-only unless a focused test reveals a separate runtime-owner defect. Do not rewrite the working Stop/cancel/settlement protocol merely because the camera continuation was wrong.
Frozen worker lanes
Adjust a filename only during the coordinator’s pre-dispatch audit. After dispatch, ownership does not overlap.
Worker 1 — Boundary runtime, aggregates, dependencies, and deletion
Own:
Sources/PlotterRuntime/HumanGuidedDiscovery.swift
Sources/PlotterRuntime/LearningArtifacts.swift
Tests/PlotterRuntimeTests/HumanGuidedDiscoveryTests.swift
Tests/PlotterRuntimeTests/LearningArtifactsTests.swift
any narrowly required model-coordinate file and its tests, only if frozen before dispatch
Deliver:
immutable boundary attempt evidence;
accepted per-direction aggregate;
whole-aggregate Redo semantics;
Record Another aggregation;
learned local coordinate frame;
atomic graph contracts;
removal of the nearest-edge/posterior family and graph kinds;
runtime-focused tests.
Do not edit SwiftUI, OperatorWorkspace.swift, simulator files, controller files, or docs.
Worker 2 — Workspace orchestration, recovery, activity, and public workflows
Own:
Sources/PlotterApp/OperatorWorkspace.swift
Sources/PlotterApp/LearningPathPresentation.swift
Sources/PlotterApp/LearningPathView.swift
Tests/PlotterAppTests/OperatorWorkspaceTests.swift
Tests/PlotterAppTests/LearningPathPresentationTests.swift
Tests/PlotterAppTests/SimulatorPresentationTests.swift
Deliver:
attempt-bound candidate staging;
atomic workspace swap;
normal versus replacement/additional recovery;
typed activity projection;
raw/local coordinate presentation;
camera-change routing;
deletion of fake direction-conditioned quadrilaterals;
complete public-action workflow tests.
Do not edit Worker 1 runtime types, Worker 3 simulator/rendering files, controller files, or docs.
Worker 3 — Simulator viewport, cooperative execution, rendering, and layout
Own:
Sources/PlotterRuntime/SimulatedLearningRuntime.swift
Sources/PlotterRuntime/SimulatedFrameSource.swift, only if genuinely required
Sources/PlotterApp/ActionSurface.swift
Sources/PlotterApp/AdaptivePlotterApp.swift
Sources/PlotterApp/WorkbenchLayout.swift
Sources/PlotterTestSupport/PaperSceneSimulator.swift, only if required
Tests/PlotterRuntimeTests/SimulatedLearningRuntimeTests.swift
Tests/PlotterRuntimeTests/SimulatedModelOverlayTests.swift
Tests/PlotterAppTests/ActionSurfaceTests.swift
Tests/PlotterAppTests/LearningWorkbenchLayoutTests.swift
Tests/PlotterAppTests/WorkbenchPresentationTests.swift
Deliver:
pure stable world-to-camera auto-fit;
causal armature/ink projection;
exact-frame simulated annotations;
cooperative Boundary and manual execution;
Stop-race coverage;
useful visual footprint and layout coverage;
dead model-picker deletion.
Do not edit Worker 1 boundary types, Worker 2 workspace/presentation files, controller files, or docs.
AdaptivePlotterApp.swift belongs exclusively to Worker 3.
If Worker 2 needs a new presentation type owned by Worker 3, or Worker 3 needs a workspace projection owned by Worker 2, use the coordinator-frozen signatures. Report seam insufficiency instead of cross-editing.
Coordinator-owned files and responsibilities
The coordinator owns:
shared seam adjudication;
Package.swift or Makefile changes, if genuinely necessary;
canonical documentation;
the new retained execution-prompt record;
integration fixes not owned by a worker;
review of every worker diff;
focused and broad validation;
stale-surface audits;
signed-bundle validation;
commit and Blackdog landing.
Reconcile:
README.md
docs/FEASIBILITY_REVIEW_AND_BINDING_AMENDMENTS.md
docs/PROJECT_SCOPE_AND_MODEL_TRAINING.md
docs/SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md
docs/SWIFT_ADAPTIVE_PLOTTER_SEQUENTIAL_REBUILD.md
docs/implementation/CURRENT_IMPLEMENTATION_STATUS.md
docs/implementation/VISIBILITY_TARGET_AND_CLEAR_VIEW_PROTOCOL.md
docs/implementation/FIRST_HARDWARE_SESSION.md
Add a new retained implementation record such as:
docs/implementation/BOUNDARY_EVIDENCE_AND_SIMULATOR_VIEWPORT_EXECUTION_PROMPT.md
Preserve the body of LEARNING_WORKBENCH_MULTI_AGENT_EXECUTION_PROMPT.md as a historical execution record. Add only a clear supersession note/link for the obsolete boundary posterior and simulator assumptions; do not rewrite history.
Documentation must state:
machine direction comes from typed operator intent;
exact contact is a sample, not side identity;
nearest camera edge never vetoes Boundary success;
machine aggregates and camera compatibility are separate;
local coordinates are learned presentation only;
simulator auto-fit is not camera registration;
failed replacement fallback remains actionable;
current software tests do not prove physical movement, camera quality, pen pose, or ink;
attended physical verification remains pending after this software correction.
Do not change the visible stage or step names.
Focused deterministic acceptance
Boundary observation and deletion
The Boundary sequence has no generic preparatory YES/NO ceremony.
It ends in one typed boundary evidence/aggregate commit, not posterior adjustment.
Four directions whose contact points are all nearest the same detected quadrilateral edge still commit successfully.
A missing or ambiguous generic drawing-frame estimate does not fail Boundary completion when exact contact evidence exists.
Exact side evidence retains owner, Stop disposition, final MPos, frame ID, SHA, capture time, configuration, attempt ID, and contact estimator.
The entire outgoing nearest-edge/posterior type and graph family is absent.
Generic drawing-frame diagnostics remain functional.
Atomic attempt and aggregate semantics
First success creates N=1 with unavailable sample uncertainty.
Record Another creates N=2 and N=3 with estimator, uncertainty, and included attempt IDs.
Center uses aggregate estimates rather than the latest incidental sample.
Successful Redo after N=3 makes the replacement aggregate current at N=1 and supersedes the prior accepted aggregate/sample set.
Failed/refused/cancelled/ambiguous Redo preserves the N=3 aggregate, graph, progress, center, arrival, and downstream current path.
Exact frames, contact samples, controller events, refusals, and ambiguity remain individual provenance.
Incompatible controller context is not pooled.
Camera configuration does not split the numeric side aggregate.
Optical registration rejects incompatible camera samples.
No injected failure leaves a partially current aggregate, graph, progress, center, local frame, or overlay.
Routing and activity
A failed normal attempt with no accepted side exposes Restart only after settlement and only without sticky ambiguity.
A failed replacement/additional attempt never leaves Cancel as its sole action.
It never assigns generic restartableExerciseItemID.
It never replaces the accepted runtime current step.
It reports actor, action, phase, exact outcome, retained accepted revision, and recovery.
Move to Estimated Center remains available after a failed side Redo when four accepted sides remain.
Browsing and Return to Current remain selection-only.
Exactly one machine-interactive action owner remains.
Local coordinates
Incomplete sides produce no local frame.

Context mismatch is rejected.

Raw-to-local and local-to-raw round-trip.

The physical regression values map to:
lower side: 0,0;
upper side: 186.550,159.167;
center: 93.275,79.5835.

Raw negative Controller MPos remains visible.

Camera restart preserves the local frame.

Successful Redo/Record Another recomputes it through graph dependencies.

No motion-admission test or input consumes the local frame.

Simulator transform and visibility
Auto-fit works for wide, tall, translated, and fully negative truth bounds.
Use the observed negative regression bounds with an initial MPos inside them, not raw zero outside the X range.
Uniform scale, padding, invertibility, and center placement are exact.
Armature, 4 mm target, line ink, and truth envelope occupy a frozen useful visual footprint at 640×480.
Armature/ink remain inside the frame at all four limits.
Resize changes presentation coordinates only, not frame ID/SHA/evidence.
New annotations hide on frame/config mismatch.
Toggling annotations leaves canonical pixels, SHA, and vision results unchanged.
Truth envelope and learned sides are visibly distinct.
Simulator overlays begin visible.
Simulator motion parity
Boundary Stop is visible immediately after owner admission.
At least one causal frame advances while the owner is active.
Stop before the first segment applies no movement.
Stop between segment and frame publication prevents later mutation.
Stop at the truth boundary succeeds without natural completion or zero-motion spinning.
Repeated Stop emits one semantic result.
Cancel and shutdown create no boundary evidence.
Ambiguity emits no next segment/frame and remains sticky.
Manual jog naturally completes under immediate pacing.
Controlled pacing lets Stop win before manual delta application.
Manual Stop creates no Boundary mutation.
End-to-end public simulation
Using only the public presentation/action seam and a mocked operator:
execute a complete route beginning with an X side;
execute a complete route beginning with a Y side;
exercise forced opposites;
show changing causal boundary frames;
derive the center and local coordinate frame;
move to center;
register target pose/contact/ROI;
perform multi-move Clear search;
draw and observe the visibility target;
accept registration;
continue one route through the complete Stage 4 line comparison;
prove exact simulated annotations and ink;
prove zero physical MachineActions;
prove every evidence surface remains SIMULATED — NOT PHYSICAL EVIDENCE;
leave and return to SIMULATED/LIVE without crossing authority.
Do not satisfy this test with final artifact booleans or direction-specific pre-rendered success geometry.
Regression
Keep green:
MachineController parsing and direct admission;
RunInterpreter one-owner finite boundary renewal;
Stop/Cancel/shutdown races;
final Idle/MPos settlement;
exact-frame freshness;
feed selection;
Pen Interaction;
camera capture and analysis;
visibility-target no-redraw;
Stage 4 ink observation;
dependency invalidation;
launcher identity and singleton behavior;
signed bundle validation;
simulator isolation.
Validation commands
Run the narrowest relevant suites continuously. Before landing, run explicitly:
git diff --check

swift build --target PlotterRuntime
swift build --target PlotterRuntimeTests
swift build --target PlotterApp
swift build --target PlotterAppTests

swift test --filter HumanGuidedDiscoveryTests
swift test --filter LearningArtifactsTests
swift test --filter MachineControllerTests
swift test --filter RunInterpreterTests
swift test --filter SimulatedLearningRuntimeTests
swift test --filter SimulatedModelOverlayTests
swift test --filter OperatorWorkspaceTests
swift test --filter LearningPathPresentationTests
swift test --filter WorkbenchPresentationTests
swift test --filter ActionSurfaceTests
swift test --filter LearningWorkbenchLayoutTests
swift test --filter SimulatorPresentationTests
swift test --filter RegistrationTests

make build
make test
make check
make strict-check
make app
make validate-launcher
make validate-app
Do not run overlapping SwiftPM builds against actively changing shared files. Coordinate stable validation windows.
Final bounded stale-surface audit
Run a tracked-source/document audit for:
candidateEdgeAlreadyAssociated
ambiguousEdgeAssociation
DrawingFrameBoundaryObservationKey
DrawingFrameBoundaryObservation
DrawingFrameSideAssociation
DrawingFrameSidePosterior
DrawingFrameCorner
DrawingFramePosterior
adjustDrawingFramePosterior
drawingFramePosteriorAdjusted
boundaryFrameObservationsByAttemptID
boundaryDerivedValueSnapshot
boundary-side-posterior-v1
human-guided-discovery-posterior-v1
adjust-posterior
.boundaryPosterior
.boundaryAssociation
SimulatorModelMode
PRIOR MISMATCH
ACCEPTED MODEL
Also verify:
no direction-conditioned synthetic Boundary quadrilateral remains;
no camera-configuration condition routes accepted 3.2 evidence back to 3.2;
no replacement failure assigns generic Restart or overrides runtime current;
SimulatedLearningRuntime no longer uses a free fixed pixelsPerMillimeter scene scale.
Interpret matches. Historical removal language in retained execution records is allowed. Active source, tests, current canonical endorsements, compatibility aliases, dead fixtures, and hidden actions are not.
Do not turn the audit into a global policy mechanism or add speculative repository guards.
Signed-bundle and physical validation
Follow the repository launcher contract:
inspect processes first;
never kill an unknown or user-owned process;
never launch the raw SwiftPM executable;
never force a second app instance;
activate the exact existing signed bundle when appropriate.
If a safe attended launch is unavailable, mark launch observation skipped.
Physical camera quality, controller behavior, motion, Stop effectiveness, pen pose, audible output, target ink, and line ink remain separate evidence classes. Do not claim them from builds, tests, simulator output, screenshots, controller transcripts, or prior sessions.
Landing and done condition
Before landing:
review every worker diff;
confirm no out-of-lane edits;
confirm exact task branch and Blackdog target branch;
inspect exact diff and dirty state;
confirm documentation matches implemented behavior;
name every passed, failed, and skipped validation;
provide Blackdog a truthful completion summary;
follow every structured next_action exactly through landing, close, and cleanup.
Verify that the Blackdog-selected target branch contains the landed commit and is clean.
Do not stop until source, tests, simulator behavior, UI presentation, deletion, documentation, broad validation, and Blackdog landing are complete—or until a real external blocker prevents progress and is reported with exact evidence.
The result is incomplete if it is only:
a plan;
a weakened exception;
a retained compatibility posterior;
a simulator mock-up;
a compile pass;
a worker handoff;
an unlanded task;
or a claim unsupported by the required evidence.
