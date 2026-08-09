# Visibility Target and Clear-View Training Protocol

Status: binding implementation contract for the current increment

## Outcome

This increment replaces the one-boundary/label-only Clear-View path and the
single-dot Anchor Mark path with one causal training slice. It establishes four
operator-observed boundary sides, a derived machine-space center, an
operator-guided clear-view pose, a same-pose pre-target baseline, a visible
closed target, and a current-session machine-to-camera registration before the
first quantitative line comparison.

The Learning Path remains ergonomic presentation. It does not authorize
ordinary manual motion. Learned sides and the estimated center are evidence
consumed by this training operation, never a machine safety envelope.

## Independent critic resolution

An independent read-only critic accepted the sequence only after the following
deadlock and evidence defects were made binding here:

- partial or ambiguous target drawing uses a non-erasable paper-scene
  disposition and cannot silently redraw;
- tool contact point is a typed estimate distinct from cap/component centroid;
- quantitative Stage 4 geometry requires a real non-collinear affine fit;
- target drawing is one compound owner with Stop latched before any next phase;
- same-pose frame comparison includes source/session/paper/ROI and alignment,
  not just equal MPos and camera configuration;
- controller-space center and camera-space registration have separate
  compatibility domains;
- Stage 4 takes a fresh target-present baseline immediately before departure;
- Blocked and Partial labels continue one clear-search transaction;
- boundary repeat actions name their side; and
- two-frame target agreement exposes deterministic thresholds, N, estimator,
  uncertainty, and both exact frame IDs.

## Visible Learning Path

```text
1 Connect
2 Enable Motion

3 Human-Guided Discovery
  3.1 Pen Interaction
  3.2 Paired Boundary Discovery and Centering
  3.3 Visibility Target and Clear-View Registration

4 Observed Drawing Trials
  4.1 Choose Isolated Line Plan
  4.2 Capture Target-Anchored Baseline
  4.3 Move to Line Start
  4.4 Draw Isolated Line
  4.5 Return to Clear Pose and Observe New Ink
  4.6 Compare Intended and Observed Geometry

5 Adaptive Drawing
```

The existing Complete, Current, Next, Future, and Needs Attention statuses are
unchanged. Navigator selection remains inert.

## Actor contract

| Actor | Responsibility | Explicit exclusion |
| --- | --- | --- |
| Operator | Selects boundary direction, clear-view direction and distance, line direction, labels observations, and presses every Start, Stop, Cancel, Accept, replacement, and repeat action. | Does not hand-move the armature during the protocol. |
| `OperatorWorkspace` | Projects the current typed state, submits operator intents, sequences exact evidence, and commits artifacts atomically. | Does not duplicate controller admission or infer physical success. |
| `RunInterpreter` / `MachineController` | Own one physical operation, repeat direct controller checks, transmit typed commands, settle at Idle/final MPos, and preserve sticky ambiguity. | Learned geometry never becomes their general motion authority. |
| `CameraCapture` | Captures immutable exact frames after the declared freshness boundary. | A frame alone is not motion, pen-pose, or ink proof. |
| `VisionWorker` | Estimates the contact point, armature overlap, frame alignment, target component, registration, and line residual. | A vision estimate does not authorize motion or replace the operator label. |
| Simulator | Implements causal nonphysical equivalents behind the same app presentation and action seam. | It cannot call `MachineActions` or manufacture physical evidence. |

The operator moves toward a Clear pose by pressing one typed direction-and-
distance action. The application requests exactly one finite Pen-Up move,
awaits controller settlement, captures a strictly newer frame, and waits for
the operator label. The model may display a recommendation but cannot select or
admit the next move.

## 3.2 Paired Boundary Discovery and Centering

### Direction sequence

The allowed selection is deterministic:

```text
no accepted side       -> X+, X-, Y+, or Y-
first accepted side    -> its opposite only
first axis completed   -> either sign on the remaining axis
third accepted side    -> its opposite only
four accepted sides    -> no further normal boundary selection
```

Selecting a direction changes presentation only. Every boundary still requires
an explicit Start, and only the owner-bound operator Stop produces a successful
side observation. Cancel, refusal, ambiguity, limit, alarm, disconnect, fault,
or natural finite-segment completion produces no accepted side.

Every accepted side retains:

- direction and accepted artifact revision;
- controller session and coordinate revision;
- final controller MPos after Stop/Idle;
- exact fresh frame and camera configuration;
- a typed camera-space tool-contact estimate, not an armature or cap centroid;
- side-association estimator, uncertainty, and algorithm revision.

The contact estimate is initially the bottom-center of the measured green tool
component with an explicit estimator revision and confidence. Boundary-side
correspondences remain typed vision inferences paired with the operator's Stop
and side association; they are eligible for a fit only when their confidence
and compatibility checks pass. The operator explicitly accepts the centered
target-pose contact overlay before it may define the target ROI, and that
accepted center pair independently validates the boundary-derived fit.

### Estimated center

Four current side revisions in the same controller session and coordinate
revision produce:

```text
center.x = midpoint(X-.finalMPos.x, X+.finalMPos.x)
center.y = midpoint(Y-.finalMPos.y, Y+.finalMPos.y)
```

The artifact reports both spans, the four consumed revisions, estimator
revision, sample counts, and available uncertainty. Its compatibility does not
include camera configuration. Replacing one side retains the other three and
invalidates only the center and downstream artifacts that consumed it.

The operator reviews the four positions, center, current position, requested
delta, and feed, then presses **Move to Estimated Center**. This starts one
stoppable supervised Pen-Up owner. Natural target completion plus final MPos is
success. Stop, Cancel, shutdown, refusal, or ambiguity produces no
`CenterArrival`. Restart recomputes the remaining delta from the new current
MPos and never resends an ambiguous request.

## 3.3 Visibility Target and Clear-View Registration

### Local sequence

1. **Capture Target-Pose Registration**
   - Requires the accepted center arrival, Idle, Pen Up, and a current exact
     frame.
   - The armature is expected to be present. This frame is not a baseline.
2. **Accept Target Contact Point and ROI**
   - The operator accepts or rejects the typed contact-point overlay.
   - The ROI is derived from the current machine-camera scale and target plan,
     clipped to the exact frame.
3. **Search for Clear View**
   - The operator selects X+/X-/Y+/Y- and 10, 5, or 2 mm; 1 mm is an optional
     fine action.
   - Each press executes one finite Pen-Up move and then captures one strictly
     newer exact frame.
   - Blocked and Partial observations remain in the same search transaction.
     They never force a restart.
4. **Accept Clear Pose**
   - Requires a human Clear label and a compatible armature-overlap estimate
     that agrees the target ROI is clear.
5. **Capture Pre-Target Clear-View Baseline**
   - Requires Idle, Pen Up, the accepted Clear MPos, unchanged controller and
     camera contexts, and explicit operator confirmation that the ROI is blank.
   - This is the baseline later compared with target-present frames.
6. **Return to Registered Target Pose**
   - Explicit operator action; one stoppable supervised Pen-Up owner.
7. **Draw Visibility Target**
   - Explicit operator action; one logical compound owner.
8. **Return to Accepted Clear Pose**
   - Explicit operator action; no capture occurs until settlement and pose
     compatibility are established.
9. **Observe Existing Visibility Target**
   - Capture two distinct strictly newer exact frames and compare both with the
     same pre-target baseline.
10. **Accept Visibility Registration**
   - Requires deterministic agreement of both measurements and explicit
     operator acceptance.

### Visibility target plan

`VisibilityTargetPlanV1` is a 4 mm diameter regular octagon:

- radius 2 mm;
- eight vertices at 45-degree intervals;
- one Pen-Up approach from the registered center to the first perimeter point;
- eight finite Pen-Down deltas whose vector sum is zero;
- one final settled Pen Up;
- retained size, segment count, start convention, and algorithm revision.

One logical operation owns approach, lower, all eight segments, and raise.
Stop latches before deciding whether to issue another segment. Segments one
through seven cannot complete the operation. No segment or Pen command follows
ambiguity. Stop, Cancel, and shutdown race through one first-intent latch and at
most one compatible mechanical cancel.

### Physical-scene disposition and recovery

The attempt retains a non-erasable typed scene disposition:

| Disposition | Meaning | Permitted recovery |
| --- | --- | --- |
| `pristine` | No Pen Down was accepted. | Restart may reuse the target and baseline. |
| `inkPossible` | Pen Down or drawing was accepted; ink may exist. | Observe the existing target with the retained compatible baseline. Never redraw. |
| `targetObserved` | Compatible target ink was measured and accepted. | Repeat observation or begin an explicit replacement at a new target area. |
| `targetUnusable` | Partial/conflicting ink cannot be accepted. | Register a new target area or explicitly record Paper Replaced. |

Losing the pre-target baseline or changing camera configuration after ink
becomes possible forbids redraw at that ROI. **Register New Target Area** creates
a new target-area identity, retains the old chain, and requires at least one
explicit operator-selected 10/5/2/optional-1 mm Pen-Up relocation before target
registration can be captured again. **Paper Replaced** is an explicit human fact
that increments both tool/paper and target-area revisions; because the paper is
explicitly new, recapture may start at the current pose. Sticky ambiguity
exposes neither redraw nor resume.

### Comparison compatibility

Equal controller MPos is necessary but does not prove identical image pose.
Every pre/post comparison requires:

- same source and camera configuration;
- same controller session and coordinate revision;
- same tool/paper revision and ROI;
- Idle and Pen Up;
- reported Clear MPos within the declared controller-resolution tolerance;
- strictly increasing frame IDs and timestamps;
- bounded image-space alignment; and
- background residual below the declared policy threshold.

Excessive shift or residual is a typed rejection, not absent ink.

The target detector retains the baseline plus both included post-frame IDs,
component identity, centroid, pixel count and bounds per sample, estimator and
algorithm revisions, N=2, centroid uncertainty, area ratio, expected-diameter
range derived from the current registration, background alignment, and the
target-plan revision. Synthetic success is software evidence only.

## Machine-camera registration

The machine-space center and the camera registration have different
compatibility domains. `EstimatedCenter` survives a camera restart while its
controller session and coordinate revision remain current.

Quantitative Stage 4 geometry requires an affine current-session
`MachineCameraRegistration` fitted from at least three non-collinear compatible
MachinePosition/contact-point pairs. The normal path uses the four boundary
pairs and validates with the accepted center contact point. It retains camera
configuration, controller session, coordinate revision, correspondence frame
and artifact identities, estimator revision, RMS/max pixel residual, and
uncertainty. A camera change invalidates this registration and camera-dependent
baselines, not the machine-space center.

No identity transform or historical camera prior may stand in for this
registration.

## Stage 4 reuse of the visibility target

The accepted visibility target is the stable visual reference for a line trial.

1. The operator chooses a typed direction for one 5 mm outward line whose start
   is the corresponding 2 mm target perimeter point.
2. At the accepted Clear pose, the camera captures a fresh target-present
   baseline immediately before leaving for the line start.
3. The operator explicitly starts the Pen-Up move to line start.
4. The operator explicitly starts the one stoppable line owner.
5. The operator explicitly returns to the accepted Clear pose; the camera then
   captures the post-line frame.
6. Vision differences the post-line frame against the trial-local
   target-present baseline and compares the result with geometry projected by
   the current `MachineCameraRegistration`.
7. The operator records the typed comparison. Unclear or absent ink never
   redraws automatically.

## Artifact dependency graph

```text
four Boundary Observation revisions
  -> Estimated Center
  -> Center Arrival
  -> Target-Pose Registration
  -> Clear Pose
  -> Pre-Target Clear-View Baseline
  -> Visibility Target Execution
  -> Visibility Target Observation
  -> Visibility Registration
  -> Target-Anchored Trial Baseline
  -> Line Plan
  -> Line Execution
  -> Post-Line Frame
  -> Ink Observation
  -> Comparison
```

The machine-camera registration separately consumes compatible boundary
contact-point revisions plus target registration. Stage 4 line plans consume
that registration. Camera reconfiguration invalidates camera registrations and
baselines but not the estimated machine center. Invalidation never deletes
partial-ink, refusal, cancellation, or ambiguity provenance. Failed replacement
attempts never change the current accepted artifact.

On completed 3.2, repeat controls name the selected side explicitly, such as
**Redo X+ Boundary** and **Record Another X+ Attempt**. Row selection remains
inert. Redo of completed 3.3 begins a replacement target-area transaction; it
does not redraw the accepted target. Record Another Attempt recaptures and
aggregates a compatible observation of the existing target.

## Causal simulator contract

SIMULATED uses the identical visible path and public app actions. Its runtime is
stateful and causal:

- known configurable boundary truth and dynamic MPos;
- operator-controlled boundary Stop timing;
- current pen pose and one active owner;
- dynamic contact point, armature bounds, ROI, and clear-view movement;
- persistent simulated ink paths, including partial target ink;
- frames rendered from current pose, ink, and camera configuration;
- monotonic exact frame IDs and timestamps;
- the same compound visibility-target phase and scene dispositions;
- fault injection for refusal, Stop races, stale capability, ambiguity,
  configuration change, pose mismatch, absent ink, unstable target, excessive
  background residual, and shutdown;
- structural `SIMULATED — NOT PHYSICAL EVIDENCE` provenance; and
- zero calls to physical `MachineActions`.

The acceptance test uses a mocked operator that invokes only the public
presentation/action seam. It runs at least two complete routes with different
first boundary axis/sign choices through accepted visibility registration, and
one route continues through Stage 4 comparison. Static pre-rendered success
frames cannot satisfy the test.

## Deterministic validation matrix

Focused tests must cover:

- every first boundary choice, forced opposites, remaining-axis choice, and
  inert selection;
- Stop/Cancel/stale capability/ambiguity/shutdown for boundary, centering,
  search travel, target drawing, and line drawing;
- four-side midpoint derivation and controller-context incompatibility;
- camera reconfiguration preserving center but invalidating camera artifacts;
- non-clear labels preserving one active search transaction;
- exact 10/5/2/1 mm search actions with no model-selected movement;
- contact point distinct from component centroid and explicit ROI acceptance;
- baseline pose/configuration/freshness/background compatibility;
- exact octagon geometry, zero-sum deltas, one compound owner, Stop between
  segments, and Pen Up on successful completion;
- `pristine`, `inkPossible`, `targetObserved`, and `targetUnusable` recovery;
- two-frame stable target detection with N, estimator, uncertainty, and exact
  included frame IDs;
- target-present trial-local baseline and quantitative line projection only
  through a valid machine-camera registration;
- dependency-scoped replacement and retention of physical-scene provenance;
- two full mocked-operator simulated variants, one complete Stage 4 trial, no
  `MachineActions`, and explicit nonphysical evidence.

Broad validation remains the repository build/test/check/strict-check/app and
signed-bundle construction suite. Physical movement, camera throughput, pen
pose, target ink, and line ink require a separate attended signed-bundle pass.
