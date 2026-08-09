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

Cancel abandons the current attempt. Stop settles an admitted stoppable owner.
They may share one mechanical Jog Cancel primitive but never share a successful
semantic disposition. Sticky ambiguity suppresses new physical motion.

## 3.2 Paired Boundary Discovery and Centering

### Direction sequence

1. The operator selects any first X or Y direction. Selection is inert.
2. Explicit **Start** admits one operator-stopped Boundary owner.
3. The controller begins with one 10 mm probe segment under that same owner.
   After each unambiguous Idle/MPos, a strictly newer advisory frame may project
   remaining camera-space clearance and choose 40, 20, 10, 5, or 2 mm. The
   planner retains 4 mm estimated clearance, consumes at most half the remaining
   estimate, and never increases again after its first valid projection.
4. **Stop** is visible immediately and remains bound to that owner.
5. Operator Stop closes renewal and emits one Jog Cancel.
6. The original owner settles through fresh Idle and final MPos.
7. The camera supplies one frame strictly newer than settlement.
8. Vision supplies one typed bottom-center contact estimate from that exact
   frame.
9. The workspace atomically commits the side attempt and accepted aggregate.
10. The forced opposite side becomes next.
11. After the pair, the operator selects either sign on the other axis and then
    records its forced opposite.
12. After four sides, explicit **Move to Estimated Center** admits one stoppable
    Pen Up move.
13. Arrival succeeds when the exact final controller MPos is within 0.05 mm
    Euclidean residual of the derived target.

The advisory frame used between segments is not accepted side evidence. A
missing, stale, camera-incompatible, low-confidence, or geometrically unusable
observation selects 10 mm or less and cannot alter direction, feed, Stop, or
side acceptance.
14. Stop or out-of-tolerance settlement retains all four side aggregates and
    exposes **Retry Center Arrival** for only the remaining delta.

There is no generic preparatory YES/NO question. A detected drawing-frame edge,
quadrilateral, or nearest-edge association cannot identify or veto a side. The
typed direction is authoritative; the contact estimate is optical evidence.

Natural completion of one finite segment is not side evidence. An unambiguous
segment may renew while the same owner remains active. A controller limit,
alarm, disconnect, or ambiguity ends the attempt as Needs Attention rather than
inventing success.

### Side attempts and aggregates

A successful exact attempt retains:

- attempt and operation-owner identity;
- typed direction and Stop disposition;
- controller session and coordinate revision;
- final settled MPos;
- frame source, ID, SHA-256, capture time, and camera configuration;
- contact estimator, confidence, and contact point.

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

## 3.3 Visibility Target and Clear-View Registration

### Target pose and ROI

At the accepted target pose:

1. record current controller MPos;
2. capture one exact compatible frame;
3. record the tool contact point and target ROI;
4. construct or refresh machine-camera registration from compatible exact
   machine/contact samples.

If the current camera lacks enough compatible samples, the UI names that exact
fact and offers an explicit capture-only evidence action. It does not redo a
Boundary, move the plotter, or erase machine-space aggregates.

### Clear search

The operator chooses a typed Pen Up search direction and one of 10, 5, 2, or
optional 1 mm. Each **Start** admits one bounded move. After settlement, the
camera captures an exact frame and Vision reports Clear, Partial, or Blocked.

Partial or Blocked keeps the search transaction current. The operator may move
again, change direction/distance, record an attributable human observation, or
cancel. The app does not infer a useful pose from elapsed travel alone.

An accepted Clear pose records controller context, MPos, exact frame and camera
configuration, ROI, armature evidence, source, and algorithm revision.

### Visibility target

1. Capture a blank baseline at the accepted Clear pose.
2. Return to the registered target pose.
3. Draw one 4 mm diameter octagonal target under one owner.
4. Return to the accepted Clear pose.
5. Capture two fresh exact observation frames.
6. Require compatible target detection and two-frame agreement.
7. Accept the visibility registration.

The target plan is immutable for the attempt and cites the target pose,
machine-camera registration, camera context, blank baseline, paper revision,
and drawing parameters. The target is never automatically redrawn after an
uncertain result.

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
