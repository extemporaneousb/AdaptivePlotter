# AdaptivePlotter

AdaptivePlotter is a native macOS Swift application for a short
controller-camera-draw-observe loop on one attached plotter. It keeps controller
authority, camera evidence, human observation, inferred geometry, and observed
ink separate.

The product is intentionally local and narrow:

- one signed application bundle and one native process;
- one persistent controller owner and one camera owner;
- a camera-first workbench with typed, bounded actions;
- exact frame and camera-configuration provenance;
- no arbitrary controller text, remote backend, second process, or hidden
  compatibility workflow;
- no automatic resend, resume, or redraw after an uncertain physical outcome.

## Operator journey

The persistent **Learning Path** organizes the current work:

1. **Connect**
2. **Enable Motion**
3. **Human-Guided Discovery**
4. **Observed Drawing Trials**
5. **Adaptive Drawing**

This numbering is ergonomic presentation, not a machine-authority ladder.
Connect and Enable Motion are current-session mechanical prerequisites. Learning
status never becomes a global motion gate, and ordinary manual jogs do not
depend on learning completion. Each operation requires only the direct facts and
evidence it consumes.

Human-Guided Discovery is ordered as:

1. **3.1 Pen Interaction** — observe Up, follow the spoken lowering cue,
   observe Down, retract, and finish with an explicit human confirmation of Up.
2. **3.2 Paired Boundary Discovery and Centering** — choose any first side,
   record it with operator-stopped boundary motion, record its forced opposite,
   choose either sign on the remaining axis, then record that forced opposite.
   Each Stop retains the settled MPos plus one exact newer frame and typed
   bottom-center contact sample. Typed operator direction, never a nearest
   camera edge, identifies the side. Per-side machine-space aggregates define
   the estimated center and learned local millimetre frame. The operator then
   explicitly starts one stoppable Pen Up move to that center. Center arrival
   accepts a controller-reported final MPos within 0.05 mm of the derived target
   so normal step quantization cannot create an unreachable retry loop. A failed
   or stopped center move preserves all four accepted sides and exposes **Retry
   Center Arrival**, not a Boundary-discovery restart.
3. **3.3 Visibility Target and Clear-View Registration** — register the tool's
   camera-space contact point and target ROI while the armature is present;
   find and accept a repeatable clear pose with explicit 10, 5, 2, or optional
   1 mm Pen Up search moves; capture a blank baseline at that clear pose; return
   to the registered target pose; draw one 4 mm diameter octagonal visibility
   target under one operation owner; return to the accepted clear pose; observe
   the existing target in two fresh frames; and accept the registration.

A fixed application travel distance is never a boundary. Natural completion of
an underlying finite GRBL segment renews the same logical owner and cannot
complete a side. Stage 3.2 completes only after all four sides and the explicit
center move. A Blocked or Partial clear-view label keeps the same search
transaction active; it does not fail the entire step.

Observed Drawing Trials are ordered as:

1. **4.1 Choose Isolated Line Plan**
2. **4.2 Capture Target-Anchored Baseline**
3. **4.3 Move to Line Start**
4. **4.4 Draw Isolated Line**
5. **4.5 Return to Clear Pose and Observe New Ink**
6. **4.6 Compare Intended and Observed Geometry**

The first line plan starts at a selected perimeter point of the accepted
visibility target and extends 5 mm outward. The baseline is captured at the
accepted clear pose immediately before leaving it. The trial never redraws
automatically after an uncertain physical outcome.

The complete actor, provenance, recovery, and simulator contract is
[Visibility Target and Clear-View Protocol](docs/implementation/VISIBILITY_TARGET_AND_CLEAR_VIEW_PROTOCOL.md).

Only observed ink proves that a mark exists. Adaptive Drawing remains visibly
Future until multi-stroke observation and checkpoint learning are implemented.

The accepted workbench target is one singleton window with three user-resizable
vertical regions: the Learning Path navigator on the left, the always-mounted
camera/action surface in the center, and the selected exercise plus its controls
on the right. The navigator, exercise detail, and lower Motion region also have
explicit Hide/Show controls; hiding them never dismounts the camera or changes
runtime authority. Selecting a completed or future row changes presentation only.
The camera remains visible while the operator reads, starts, answers, stops,
cancels, retries, or reviews an exercise. There is no auxiliary Learning Path
window and no launcher panel for one.

The right exercise region keeps the current instruction and action strip
visible. Critical cues such as **UP**, **DOWN**, **YES**, **NO**, **STOP**, and
typed directions use structured emphasis rather than undifferentiated prose or
fragile string parsing. **START** is the positive entry action, **CANCEL**
abandons the current exercise attempt through its typed cancellation route,
**STOP** becomes active only for stoppable motion, and **RESTART** is offered
only after a stopped, cancelled, or failed current attempt can truthfully be
restarted.

Boundary Discovery has no generic preparatory YES/NO ceremony. Selecting a
direction is inert; the explicit Start action admits the logical owner, and the
next operator action is its owner-bound Stop or Cancel. The manual Motion panel
labels X/Y distance and feed units, labels every direction control, and exposes
its own red **Stop Manual Jog** only while that exact manual owner is active.

Buttons are authoritative for questions, labels, progression, assessment,
Cancel, Stop, and Restart. Spoken movement announcements are output-only and
advisory. They are serialized and completion-aware; a bounded speech-output
failure never grants authority and never makes the visible buttons unusable. No
audio-input or speech-recognition subsystem is part of the product.

There is no separate **Jog Observations** exercise or diagnostic control
surface. Repeated evidence is collected only by **Record Another Attempt** on a
numbered Learning Path exercise, using that exercise's typed attempt and
aggregate semantics. The removed jog-response diagnostic must not survive as a
renamed or hidden compatibility workflow.

## Redo and additional attempts

**Redo This Step** replaces that step's accepted value with the new accepted
value. It invalidates the transitive outputs that actually consumed the
replaced value. Execution order is not itself a data-dependency graph: redoing
Pen Interaction does not discard independent boundary measurements merely
because Boundary Discovery followed it in the visible path. Current mechanical
facts still apply to any new motion without retroactively erasing valid recorded
evidence.

Replacement is committed atomically after the new attempt succeeds. The old
value is no longer current and is excluded from derived current results; any
retained diagnostic record is explicitly marked superseded.

For a Boundary side, Redo replaces the entire accepted aggregate. A successful
replacement begins again at N=1; a failed, refused, cancelled, or ambiguous
replacement leaves the old aggregate, graph, center, arrival, local frame, and
current path unchanged.

**Record Another Attempt** preserves each compatible attempt and recomputes the
typed aggregate from all valid attempts in that group. The aggregate exposes its
valid sample count. Numeric or geometric measurements use their declared
estimator and uncertainty; categorical observations use counts or a typed
posterior; current state facts such as observed pen pose use the latest accepted
observation and are never arithmetically averaged. Exact frames and controller
events remain provenance, not averageable values. Boundary numeric compatibility
uses direction, controller session, coordinate revision, machine coordinates,
millimetres, and numeric-estimator revision; camera configuration is deliberately
absent. Optical registration separately requires compatible exact frames,
camera configuration, contact estimator, and algorithm revision.
When a current camera lacks three compatible non-collinear correspondences, the
operator gets a typed **Collect Current-Camera Contact Evidence** action. It
captures exact MPos/contact provenance only; it admits no motion and leaves all
accepted machine-space Boundary authority unchanged.

## Direct mechanical authority

The internal runtime retains its precise `MotionGuard` type, but the operator
surface says **Enable Motion**, **Motion Enabled**, or **Motion Disabled**.
There is no second arming control.

The green Motion Enabled indicator reports current-session authorization and
therefore remains green while that authorized session is busy moving or
actuating. A separate request-status projection reports Ready, Busy,
Unavailable with the exact reason, or Needs Attention. Needs Attention detail
names the actor, action, outcome, and recovery rather than replacing those facts
with a bare status label. The optional Utilities region has an explicit Hide
action and yields width before the protected camera.

Typed motion continues to require the applicable direct facts:

- one explicitly selected, responsive controller session;
- current internal motion authorization;
- recognized non-alarm controller state and Idle admission;
- no relevant asserted X/Y limit pin;
- known MPos where the requested operation requires it;
- controller-reported feed capability;
- the appropriate commanded pen state;
- one-operation ownership;
- no sticky ambiguity.

Disconnect and shutdown invalidate current authorization. The application does
not home, clear alarms, unlock, reset, write firmware settings, accept entered
workspace bounds, or use learned geometry or model confidence to admit manual
motion.

Controller `ok` means acceptance, not completion. A jog completes only after
bounded polling reaches fresh Idle with final MPos. An uncertain outcome becomes
sticky and is never automatically resent.

## Cancel and Stop semantics

The persistent exercise action strip owns one visible contextual **Stop**. It is
enabled only while a typed software operation is stoppable. It is not a physical
emergency stop; the physical power cutoff remains the operator's safety
boundary. The window toolbar retains global connection and status controls, not
exercise-specific cancellation.

During Boundary Discovery, Stop has one deterministic order:

1. record the contextual operator Stop event;
2. emit exactly one GRBL Jog Cancel byte;
3. await the original jog owner through Idle and final MPos;
4. capture a strictly newer exact camera frame;
5. obtain one typed bottom-center tool-contact estimate;
6. atomically commit the exact attempt evidence and accepted side aggregate;
7. recompute paired progress, center, and learned local coordinates;
8. advance the visible sequence.

Boundary motion remains owned by the active discovery attempt until Stop or a
real controller limit, alarm, disconnect, or other typed fault. The application
must not end it normally at a hard-coded X/Y distance. Any controller-native
finite command horizon is an implementation detail that must continue the same
logical owner without inventing a successful boundary, duplicating motion after
ambiguity, or racing Stop. Reaching a controller safety limit is Needs Attention,
not observed-boundary evidence.

The same Stop route cancels a manual jog without creating boundary evidence.
Drawing Stop retains the controller owner's Pen Up behavior; an ambiguous
outcome causes no follow-on command.

Cancel is a distinct exercise intent. It never masquerades as a successful
Boundary Stop and never manufactures boundary, trial, or completion evidence.
If cancellation must settle active motion, the runtime emits at most the same
single mechanical cancel and awaits the original owner before marking the
attempt cancelled. Restart creates a fresh attempt for the same current step;
it does not resend an ambiguous command or silently revive an old owner.

## Travel feed selection

Successful passive controller inspection exposes the reported X and Y maximum
feeds as read-only runtime facts. Non-drawing, Pen Up discovery and travel select:

- the X ceiling for X-only motion;
- the Y ceiling for Y-only motion;
- the minimum participating-axis ceiling for multi-axis motion.

If that capability is unavailable, the existing positive request feed remains
the fallback; its absence does not create a new learning prerequisite. The app
does not write firmware settings. Pen Down drawing feed remains an ink-quality
choice and is not automatically increased.

## Camera and evidence

`CameraCapture` owns AVFoundation discovery, selection, authorization, capture,
and shutdown. `latestLiveCameraFrame` is the live heartbeat; it is deliberately
separate from an analyzed or held display frame. `StampedFrame`, `FrameID`, and
`CameraConfigurationID` bind pixels, measurements, and overlays to exact
provenance.

After a successful LIVE camera start or restart, bounded automatic scene
analysis starts at the selected cadence and all semantic overlay layers are
visible by default. The operator can still stop automatic analysis or hide
individual overlay kinds. Utilities remains reachable at the supported minimum
window width by yielding a collapsible side pane before reducing camera width.

The evidence boundaries are explicit:

- controller acceptance proves only that the command was accepted;
- Idle and final MPos prove controller-side settlement;
- a camera frame proves captured pixels at its recorded provenance;
- vision geometry is an inference from those pixels;
- a button label records a human observation;
- observed ink is the only proof of a drawn mark.

SIMULATED frames share the renderer but are labeled nonphysical and cannot reach
machine actions or satisfy physical evidence. Their pixels are causal:
simulated MPos, pen pose, accepted motion segments, paper identity, and retained
ink determine the rendered scene. Boundary Stop positions, center arrival,
target drawing, clear-view search, two-frame target observation, and the Stage 4
line trial therefore exercise the same visible actions instead of consuming a
pre-rendered success script.

The simulator fits arbitrary translated or negative truth bounds into each
camera configuration with one stable uniform transform. Its truth envelope,
direction labels, learned markers, current pose, target ROI, trail, and ink
annotations are exact-frame presentation only: they never alter canonical
pixels, frame hashes, vision results, accepted evidence, or physical authority.

LIVE and SIMULATED use the same Learning Path, motion panel, camera utilities,
questions, and action locations. The deterministic simulator implements its
own session, motion authorization, MPos, pen pose, manual jog, Boundary owner,
Stop/Cancel, drawing, and camera evidence. Simulated learning is discarded when
returning to LIVE; parked LIVE accepted authority is restored unchanged.

## Build, test, and launch

Requirements: macOS 14 or later and Swift 6.1 or later.

```sh
make build
make test
make check
make strict-check
```

For supported local application launch:

```sh
make run-app
```

`make run-app` builds the current `.app`, prefers the stable
`AdaptivePlotter Local Development` signing identity (or the explicit
`ADAPTIVEPLOTTER_CODESIGN_IDENTITY`), validates the bundle and camera-only
privacy declaration, then launches through LaunchServices.

The launcher accepts only `com.bullard.AdaptivePlotter` at the expected bundle
path. It activates one already-running exact bundled instance instead of
creating another and reports its PID. It refuses a same-name raw SwiftPM
executable or any conflicting instance with PID and path, and never kills a
user-owned process. A rebuilt bundle does not replace the bits already loaded by
an existing process.

Do not use `swift run AdaptivePlotter` for camera, controller, or physical
validation. Direct executable launch gives the wrong application identity and
can create competing camera/serial owners.

## Documentation map

- [Binding amendments](docs/FEASIBILITY_REVIEW_AND_BINDING_AMENDMENTS.md)
  define the non-negotiable authority and evidence rules.
- [Project scope and model learning](docs/PROJECT_SCOPE_AND_MODEL_TRAINING.md)
  defines the five-stage product scope and technically precise model terms.
- [Architecture](docs/SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md) defines module and
  owner boundaries.
- [Direct implementation plan](docs/SWIFT_ADAPTIVE_PLOTTER_SEQUENTIAL_REBUILD.md)
  records implemented and remaining delivery order.
- [Current implementation status](docs/implementation/CURRENT_IMPLEMENTATION_STATUS.md)
  separates automated, camera, controller, and physical evidence.
- [Physical session procedure](docs/implementation/FIRST_HARDWARE_SESSION.md)
  is the operator checklist for the next attended hardware pass.
- [Learning workbench execution prompt](docs/implementation/LEARNING_WORKBENCH_MULTI_AGENT_EXECUTION_PROMPT.md)
  is the copy-paste coordinator prompt for implementing the accepted one-window
  UI and dependency-aware attempt semantics.
- [Boundary evidence and simulator viewport execution prompt](docs/implementation/BOUNDARY_EVIDENCE_AND_SIMULATOR_VIEWPORT_EXECUTION_PROMPT.md)
  is the retained coordinator record for the atomic Boundary aggregate,
  learned-local-coordinate, recovery, and simulator auto-fit correction.

## Development contract

Use the repository-local AdaptivePlotter skill and the Blackdog workflow in
`AGENTS.md`. Implementation belongs in the task workspace returned by
`blackdog task begin`; the recorded target branch is authoritative.

Normal integrated validation is:

```sh
make build
make test
make check
make strict-check
git diff --check
```

Physical claims require an attended physical run with the cutoff reachable.
Builds, tests, simulator output, controller `ok`, Idle, UI state, or camera
preview must never be reported as physical movement or ink proof.

The legacy `/Users/bullard/Projects/Plotter` repository is forensic product
evidence only. Do not port its bridges, routes, DTOs, lifecycle ceremonies,
compatibility layers, or tests.
