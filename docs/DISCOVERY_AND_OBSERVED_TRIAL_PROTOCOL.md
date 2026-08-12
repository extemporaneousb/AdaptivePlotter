# Discovery and Observed-Trial Protocol

Status: current operating protocol for Learning Path 3.2 through 4.6

This document owns the exact actor, action, evidence, dependency, and recovery
sequence. Product invariants remain in [Product Contract](PRODUCT_CONTRACT.md).

## Common actor contract

Every interactive step exposes:

- one current participant: App, Operator, Controller, Camera, Vision, or Pen;
- one typed current action;
- one expected observation;
- one explicit button-owned transition;
- one operation owner when controller or simulator state may change;
- one contextual Stop capability while that owner is stoppable;
- one typed attempt and disposition;
- exact artifact dependencies for any accepted result.

Announcements are advisory output. Buttons own answers, Start, Cancel, Stop,
Restart, Redo, and Record Another Attempt.
Boundary announcements name the plotter and say positive or negative X/Y in
words. Compact X−/X+/Y−/Y+ glyphs remain visual labels and are never sent to
speech synthesis.

Cancel abandons the current attempt. Stop settles an admitted stoppable owner.
They may share one mechanical Jog Cancel primitive but never share a successful
semantic disposition. Sticky ambiguity suppresses new physical motion.

Every production comparison of a requested controller pose with settled MPos
uses fresh attributable controller evidence, compatible context, and at most
0.05 mm Euclidean residual. **Exact pose** names that quantization-aware policy;
it does not require mathematically zero residual when configured steps/mm cannot
represent the requested coordinate exactly.

## 3.2 Paired Boundary Discovery and Centering

### Direction sequence

1. The operator selects any first X or Y direction. Selection is inert. When
   the protocol requires the opposite side, the UI presents that direction as
   required noninteractive content rather than a disabled choice.
2. Explicit **Start** admits one operator-stopped Boundary owner.
3. The controller begins with one 20 mm probe segment under that same owner.
   After each unambiguous Idle/MPos, a strictly newer advisory frame may project
   remaining camera-space clearance and choose 50, 20, 10, 5, or 2 mm. The
   planner retains 4 mm estimated clearance, consumes at most half the remaining
   estimate, and never increases again after its first valid projection. Every
   directional owner has an independent planner. If its initial camera seed is
   unavailable, the first later compatible frame establishes that side's
   baseline; one more 20 mm probe can then produce coarse advice instead of
   leaving the rest of that side permanently on the fallback tier.
   During the LIVE owner, these finite explicit renewal inspections are the only
   scene-analysis producer; camera startup and stopped state admit none.
4. **Stop** is visible immediately and remains bound to that owner.
5. Operator Stop closes renewal and emits one Jog Cancel.
6. The original owner settles through fresh Idle and final MPos.
7. The workspace atomically commits typed direction, Stop owner/disposition,
   controller session/revision, and final MPos as the side attempt and aggregate.
8. The forced opposite side becomes next.
9. After the pair, the operator selects either sign on the other axis and then
    records its forced opposite.
10. After four sides, explicit **Move to Estimated Center** admits one stoppable
    Pen Up move.
11. Arrival succeeds when the exact final controller MPos is within 0.05 mm
    Euclidean residual of the derived target.

The advisory frame used between segments is not accepted side evidence. A
missing, stale, camera-incompatible, low-confidence, or geometrically unusable
observation selects 20 mm or less and cannot alter direction, feed, Stop, or
side acceptance.
Stop or out-of-tolerance center settlement retains all four side aggregates and
exposes **Retry Center Arrival** for only the remaining delta.

There is no generic preparatory YES/NO question. A detected drawing-frame edge,
quadrilateral, or nearest-edge association cannot identify or veto a side. The
typed direction and settled controller position are authoritative. Optical
contact evidence begins in 3.3 and is not part of a Boundary attempt.

Natural completion of one finite segment is not side evidence. An unambiguous
segment may renew while the same owner remains active. A controller limit,
alarm, disconnect, or ambiguity ends the attempt as Needs Attention rather than
inventing success.

### Side attempts and aggregates

A successful machine-side attempt retains:

- attempt and operation-owner identity;
- typed direction and Stop disposition;
- controller session and coordinate revision;
- final settled MPos;

The accepted aggregate for one direction retains its revision, numeric
compatibility, estimate in millimetres, sample count, estimator, uncertainty,
included attempt IDs, and excluded/superseded provenance.

Numeric compatibility includes direction, controller session, coordinate
revision, machine space, millimetre units, and estimator revision. Camera
configuration is not a numeric compatibility key.

Record Another Attempt adds one compatible success. Redo replaces the entire
accepted side aggregate on success; the replacement starts at N=1. Failure,
refusal, cancellation, or ambiguity preserves the previous aggregate, graph,
center, local frame, arrival, and downstream accepted path.

### Center and local coordinates

The four current side aggregates derive:

```text
center.x = (X− estimate + X+ estimate) / 2
center.y = (Y− estimate + Y+ estimate) / 2
local.x  = raw.x - X− estimate
local.y  = raw.y - Y− estimate
```

The UI shows learned local millimetres as primary only after all four sides
exist and keeps raw Controller MPos as provenance. Local coordinates do not
rewrite MPos, establish homing, configure a work offset, clamp requests, or
admit motion.

Center retry is not Boundary retry. It retains the accepted sides, estimated
center, learned local frame, exact failed settlement, and Needs Attention
detail. The retry recomputes the remaining delta from current MPos. It does not
repeat side discovery or manufacture a center-arrival artifact.

## 3.3 Register Target Pose and Camera Geometry

At the accepted target pose:

1. press one explicit **Capture Target Pose and Build Geometry Proposal**
   action;
2. under that action, record current controller MPos and capture one exact
   compatible frame;
3. measure the bottom-center tool contact point, which is not the component
   centroid;
4. fit machine-camera registration from compatible exact machine/contact
   samples or run the one bounded three-sample Pen Up calibration owner and
   return to the captured target MPos under the shared pose policy;
   the calibration's first fresh passive probe establishes an operation-local
   controller-context baseline, and every later before/after-capture probe must
   match and advance that baseline;
5. stage the fit, projected target ROI, validation residual, and provenance as
   a non-authoritative proposal; the ROI retains a 12 px perimeter on left,
   right, and top, then extends its pre-expansion height by 50 percent at the
   bottom to cover tool-to-ink Y error without broadening the other sides;
6. inspect the complete exact frame, ROI outline, and adjustable
   presentation-only zoom; then explicitly accept or reject the proposal.

There is no preceding generic Start and no separate public Capture then Build
sequence.

Calibration never accepts geometry. One explicit acceptance atomically makes
the target-pose, machine-camera, and typed target-ROI revisions current. No one
of those revisions becomes current if proposal construction or acceptance
fails. Viewport zoom never mutates the target ROI used by Vision.

An application-owned parser transition such as Pen Up `M5/S0` to `M3/S40` is
recorded but does not invalidate coordinate identity. A device, build, units,
distance-mode, work-coordinate, controller-setting, or coordinate-offset change
discards the staged calibration sample, names the changed fields, disables
calibration retry, and requires controller-context revalidation. Other failures
derive recovery from current MPos: retry directly when still at the registered
target, or expose Return to Captured Target Pose when it actually moved.

## 3.4 Discover and Accept Clear View

The operator chooses a typed Pen Up signed axis direction and either 50 or
10 mm. Each action admits one bounded move. After settlement, the
camera captures an exact frame and Vision reports Clear, Partial, or Blocked.
The bounded move may own newest-only scene analysis while it is in flight and
must stop it at controller settlement. The subsequent explicit inspection
freezes preview publication on its exact input frame while raw camera delivery
remains active, and resumes from the newest buffered frame only after Vision
settles.

The operator's explicit human label owns the Clear-pose acceptance decision.
The action strip shows both that recorded label and Vision's exact-frame report.
A disagreement remains attributable evidence but cannot veto an explicit
**Accept Clear Pose**.

Partial or Blocked keeps the search transaction current. The operator may move
again, change direction/distance, record an attributable human observation, or
cancel. The app does not infer a useful pose from elapsed travel alone.

An accepted Clear pose records controller context, MPos, exact frame and camera
configuration, ROI, armature evidence, source, and algorithm revision.

## 3.5 Confirm Blank Target Baseline

At the accepted Clear MPos, capture a fresh exact candidate frame and explicitly
choose **Confirm ROI Is Blank** or **Not Blank**. Capture alone creates no
baseline authority. Acceptance records frame/configuration, MPos, paper
revision, target-ROI revision, and Clear-pose revision.

## 3.6 Return to Registered Target Pose

Move Pen Up under one stoppable owner to the registered target MPos. Completion
requires Idle, final MPos accepted by the shared 0.05 mm pose policy, no sticky
ambiguity, and a retained settlement.

## 3.7 Draw Visibility Target

Execute `visibility-target-octagon-double-trace-v2`: draw one 4 mm diameter
   octagon forward, then retrace the same perimeter in reverse under the same
   owner and Pen Down interval.

The target plan is immutable for the attempt and cites the target pose,
machine-camera registration, target-ROI registration, camera context, blank
baseline, paper revision, and drawing parameters. Possible ink advances to
observation or explicit recovery. The target is never automatically redrawn
after an uncertain result.

## 3.8 Return and Observe Existing Target

Return Pen Up under one stoppable owner to accepted Clear and retain Idle/final
MPos. Then capture two strictly newer exact frames and require compatible
target detection plus two-frame agreement in the accepted ROI.

Observation is one foreground, single-flight Vision operation. It publishes
ownership before capture, searches bounded target-local support, and presents
an exact-frame ROI magnifier. Fixed-camera comparison searches at most 3 px and
accepts at most 2 px of global translation for mount wobble; the separate
controller pose tolerance remains 0.05 mm. Controller, motion, pen, camera,
source, analysis, Restart, and learning mutations are
refused until settlement. **Cancel Vision** is the sole mutating action and
preserves possible ink and the active attempt. Only a matching operation
generation and complete captured authority context may commit.
Preview publication is held during computation without stopping the camera
session; success, rejection, failure, and cancellation all release that hold.

**Record Another Observation** repeats only this two-frame observation against
the existing target and baseline. It never executes 3.7 again.

## 3.9 Accept Visibility Registration

Review the exact frames, centroid, area, uncertainty, immutable plan revision,
ROI, retained execution-attempt disposition, and consumed revision provenance.
The controller must remain Pen Up and Idle at the accepted Clear pose. Motion
after observation routes back through the 3.8 Return action; exact settlement
reuses the existing observation and does not capture or draw again. Explicit
acceptance creates the current visibility-registration revision. Rejection
retains the observation and physical target provenance and performs no redraw.

If the physical scene is unusable, record the disposition:

- `clear` — continue with compatible evidence;
- `obstructed` — retain provenance and reacquire a Clear pose;
- `targetUnusable` — retain the failed target evidence and require an explicit
  new target attempt.

## 4. Observed Drawing Trial

### 4.1 Choose Isolated Line Plan

Choose one accepted visibility-target perimeter point and a 5 mm outward line.
The immutable plan cites the accepted visibility registration, current
machine-camera registration, controller context, paper revision, pen profile,
and explicit drawing feed.

### 4.2 Capture Target-Anchored Baseline

At the accepted Clear pose, capture a fresh frame immediately before leaving.
The target must be present and compatible with the plan. A blank pre-target
baseline is not a substitute.

### 4.3 Move to Line Start

Move Pen Up under one stoppable owner. Completion requires final Idle/MPos. Stop
or ambiguity creates no drawing evidence.

### 4.4 Draw Isolated Line

Execute the immutable line under one drawing owner and explicit Pen Down feed.
Stop retains the controller owner's Pen Up recovery behavior. Ambiguity causes
no automatic follow-on or redraw.

### 4.5 Return and Observe New Ink

Return to the accepted Clear pose, capture a fresh exact post-line frame, align
it to the target-present baseline, isolate new ink, and preserve rejection
evidence when measurement is unclear.

### 4.6 Compare Geometry

Only a valid machine-camera registration may project intended machine geometry
into the exact camera context. The comparison records intended, predicted, and
observed geometry plus residual metrics and provenance. It does not promote a
model automatically.

## Dependency and recovery contract

```text
four side aggregates -> center -> center arrival
-> target pose/contact/ROI -> clear pose
-> blank baseline -> target execution
-> two-frame target observation -> visibility registration
-> target-present line baseline -> line plan/execution
-> post-line frame -> ink observation -> comparison
```

Redo invalidates only explicit transitive dependents after a successful
replacement commit. Record Another Attempt recomputes the compatible aggregate
and the same named dependents. Chronological successors without a dependency
edge survive.

Reset From This Step is deliberately different from Redo. It is an explicit
operator-authored chronological reset, so it clears the selected exercise's
current accepted result and every later Learning Path exercise even when two rows
have no causal dependency edge. Selecting or reviewing a row alone never does
this. The compact reset sheet lists the exact suffix and has one Reset button; it
does not require phrase entry. Any accepted-state change makes the summary stale
and requires the operator to review the updated steps.

Reset All Learning is the same operation anchored at Pen Interaction. It preserves
the selected responsive controller and current Enable Motion fact. LIVE Boundary
rewinds clear the durable accepted-artifact checkpoint before in-memory state is
changed. SIMULATED rewinds cannot touch parked LIVE authority. Neither operation
starts, stops, resends, redraws, disconnects, or changes pen state, and neither
erases ink already on paper.

Camera reconfiguration invalidates optical registration, ROI, baseline, and
image-derived descendants. It does not by itself invalidate compatible side
aggregates, center, center arrival, or learned local coordinates.

A failed normal attempt with no accepted result may expose Restart after
settlement. A failed replacement or additional attempt with an accepted fallback
restores the exact Redo/Record Another actions and keeps the accepted fallback
current. It never replaces the runtime current step with a dead-end failure row.

## Causal simulator contract

SIMULATED traverses the same public actions and dependency graph. Its runtime
owns simulated session, Motion authorization, MPos, pen pose, renewable
Boundary motion, manual jog, target/line operations, paper revision, persistent
ink, and causal frames.

The world-to-camera transform is uniform, invertible, auto-fit, and stable for
one simulated camera configuration. Exact annotations show truth envelope,
learned sides, center, current contact, motion trail, owner/direction, ROI, and
ink without modifying canonical pixels or hashes.

Boundary Stop is available immediately. Stop, Cancel, ambiguity, and shutdown
win before any later segment or frame mutation. Reaching simulator truth waits
efficiently for explicit Stop; it does not naturally manufacture Boundary
success. Simulated manual jog can complete naturally or be stopped without
creating Boundary evidence.

Every simulated surface says `SIMULATED — NOT PHYSICAL EVIDENCE`; no simulated
route invokes physical machine actions.
