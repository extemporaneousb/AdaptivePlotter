# Feasibility Review and Binding Amendments

Status: binding product and engineering constraints
Target: one local Mac, one attached plotter, one camera, one operator

## Precedence

This document overrides broader or older product descriptions when they conflict
with the direct authority and evidence rules below. The five-stage Learning Path
and its repeat controls organize work and evidence; they do not replace or
extend mechanical authority. The operator-stopped Boundary Discovery correction
changes operation lifetime, not its direct controller safeguards or evidence
threshold.

## Feasibility verdict

The short controller-camera-draw-observe loop is feasible as a single native
Swift process. The application already has the required narrow owners:

- `MachineController` and `RunInterpreter` for one persistent typed controller
  session;
- `CameraCapture` and `VisionWorker` for exact-frame capture and measurement;
- `OperatorWorkspace` for projection and orchestration;
- SwiftUI for one camera-first workbench with the Learning Path integrated into
  the singleton main window;
- `NativeSpeechAnnouncer` for bounded advisory output only.

The feasible path is empirical and incremental. It does not require entered
coordinate envelopes, homing, firmware writes, a second backend, or a global
workflow authority.

## Binding operator journey

The visible journey is:

1. Connect
2. Enable Motion
3. Human-Guided Discovery
4. Observed Drawing Trials
5. Adaptive Drawing

Connect and Enable Motion are current-session mechanical prerequisites. Stages
3–5 organize work and report status; they do not authorize manual movement.
Stage completion must never be added to the manual motion admission path.

The current deterministic sequences are:

- 3.1 Pen Interaction
- 3.2 Boundary Discovery
- 3.3 Clear-View Discovery
- 4.1 Capture Clean Reference
- 4.2 Choose Line Start
- 4.3 Create Anchor Mark
- 4.4 Draw Isolated Line
- 4.5 Clear Tool and Observe Ink
- 4.6 Compare Intended and Observed Geometry

Adaptive Drawing remains Future until multi-stroke observation and checkpoint
learning are operational.

## Binding workbench interaction

The main frame has three user-resizable vertical regions:

1. a native, selection-driven Learning Path navigator containing the big picture
   and the exact numbered stage/step order;
2. the always-mounted camera/action surface, which remains the largest protected
   region;
3. the selected exercise detail with instructions, evidence, questions, and a
   pinned action strip.

There is one singleton application window. No auxiliary Learning Path window,
Open Learning Path action, fixed custom dock allocator, or exercise-specific
toolbar Stop belongs in the target. Motion, camera, overlay, and diagnostic
utilities may use one optional native inspector, which collapses before the
camera is starved.

`Jog Observations` is not a Learning Path exercise or an inspector utility. Its
standalone recording surface and jog-response diagnostic model are superseded.
Repeated learning evidence belongs to the numbered exercise that produced it
and enters only that exercise's typed attempt set. Do not preserve the old
workflow by renaming it `Record Another Attempt`.

Path selection is presentation state only. Reviewing a completed/future item
must not mutate a transaction, accepted evidence, controller/camera state, or
machine eligibility. The current action remains separately identifiable and a
Return to Current action restores its selection.

The pinned action strip owns the exercise controls. Start is positive and green;
Cancel is a distinct red exercise-cancellation intent; contextual Stop is red
and active only during stoppable motion; Restart appears only for a stopped,
cancelled, or failed attempt that has a defined restart route. Once an exercise
starts, typed choices such as YES/NO replace Start when the runtime is awaiting
that choice. Critical words are structured presentation values, not parsed from
arbitrary prose.

## Binding revision and attempt semantics

Visible sequence order defines the normal performance order. It does not define
data invalidation.

`Redo This Step` creates a replacement attempt. On successful commit, the
new artifact replaces the accepted artifact for that step and the prior accepted
artifact becomes superseded. Invalidation follows explicit, transitive data-
dependency edges from the replaced artifact. A later step with no such edge is
retained. In particular, redoing Pen Interaction does not invalidate independent
boundary measurements merely because Pen Interaction precedes Boundary
Discovery. Current Pen Up remains a direct prerequisite for a new carriage move
without rewriting historical boundary evidence.

`Record Another Attempt` adds one compatible attempt instead of replacing the
accepted attempt set. Every attempt retains its provenance and inclusion status.
The derived aggregate is recomputed from all valid compatible attempts and
reports the valid count `N` plus the estimator/revision used. Numeric and
geometric values use a declared estimator with uncertainty; categorical values
use counts or a typed posterior; current state observations use the latest
accepted observation. Exact frames, controller events, strings, and state labels
are not arithmetically averaged. Incompatible camera configuration, coordinate
space, units, or algorithm revision prevents silent pooling.

An unclear, refused, or ambiguous attempt remains evidence of that outcome but
does not enter a successful-value aggregate. Neither Redo nor another attempt
may automatically resend, redraw, expand motion scope, or grant authority.

## Direct motion eligibility

Every physical request is admitted from current direct facts, then checked again
by the controller owner. Applicable facts include:

- explicit selected controller and responsive open session;
- current internal `MotionGuard` activation;
- recognized Idle, non-alarm controller state;
- no asserted relevant X/Y limit input;
- known position where required;
- finite nonzero typed delta and positive applicable feed;
- controller-reported feed support;
- required commanded pen state;
- no operation already in flight;
- no sticky ambiguity.

Ordinary manual movement does not require a camera, learned boundary, Clear pose,
trial count, model confidence, or Learning Path completion. A vision-consuming
operation may require its own exact frame. A drawing trial may require its own
anchor and Clear pose. Those are local evidence dependencies, not global gates.

The application must not add homing, reset, unlock, alarm clearing, entered
limits, firmware writes, automatic resume, automatic resend, or automatic redraw.

## Minimum physical loop

The smallest attended useful loop is:

```text
supported signed bundle launch
-> Connect
-> Enable Motion
-> confirm the pen physically Up
-> issue one bounded Pen Up move
-> settle at Idle with final MPos
-> capture a strictly newer exact frame when the operation consumes vision
-> draw one attributable isolated mark only when the pen state is appropriate
-> clear the tool
-> observe actual ink
-> compare intended and observed geometry
```

Controller acceptance, final Idle/MPos, a camera frame, inferred geometry, a
human label, and observed ink are distinct facts. Only observed ink proves a
mark.

## Cancel and Stop contract

One visible Stop in the persistent exercise action strip owns contextual
software stopping. It is enabled only for stoppable motion and is not the
physical emergency cutoff.

For Boundary Discovery the order is binding:

1. record `operatorStopRequested(direction)`;
2. send one Jog Cancel byte;
3. await the original jog owner through Idle and final MPos;
4. set the fresh-frame boundary after controller settlement;
5. accept only an exact frame strictly newer than that boundary;
6. measure the chosen side and update the posterior;
7. advance the transaction.

The active discovery owns boundary motion until that Stop event or a real typed
controller terminal condition such as an asserted limit, alarm, disconnect, or
fault. Hard-coded application search distances such as an X/Y millimetre cap
must not terminate the exercise. A finite controller command horizon may be
renewed only under the same logical owner after an unambiguous completed
segment, with Stop admission closed before renewal. Natural segment completion
creates no boundary evidence and cannot be surfaced as successful completion.
An ambiguous segment is never renewed.

A repeated button press must not emit another cancel. Manual Stop uses the same
surface and primitive but creates no boundary evidence. Shutdown closes new
intent admission, settles the already latched owner once, then drains and
disconnects.

Cancel is an exercise disposition, not an alias for successful Stop. Cancelling
an attempt during active motion may use the one shared mechanical cancel/settle
primitive, but it records no boundary or trial success and cannot race a second
cancel. Restart begins a fresh attempt after the previous owner has settled; it
never reuses or resends an ambiguous write.

## Feed contract

For non-drawing Pen Up travel, select the controller-reported ceiling for the
participating axes. Multi-axis travel uses the minimum participating-axis
ceiling. If the capability is missing, retain the existing positive feed
request; do not create a blocker. Never turn reported feed into a claim of
achieved physical speed. Pen Down drawing feed remains unchanged.

## Speech contract

Spoken announcements are output-only, concise, serialized, and bounded. The
visible cue exists before announcement starts. The operation awaits completion,
timeout, cancellation, or explicit output failure, rechecks current typed state,
and proceeds only through the button-owned action.

Speech-output failure is advisory. It cannot grant authority, block unrelated
motion, or deadlock the workflow. No audio-input device, recognition permission,
transcript, ambient command parser, or hidden compatibility mode belongs in the
product.

## Camera and geometry contract

Camera liveness derives from a fresh validated capture heartbeat, not the
currently displayed or analyzed frame. Measurements and overlays retain exact
`FrameID` and `CameraConfigurationID`. Mismatched provenance is hidden or
rejected.

Frame-side and cap detections are camera-space measurements. Drawing-frame and
armature envelopes are inferences. Controller MPos remains controller provenance
until an explicit current-session registration gives it camera-space meaning.
Ruler observations and motion priors are provisional diagnostics, never motion
authority.

## Local application contract

Supported physical launch is `make run-app`. It builds and validates the current
signed `com.bullard.AdaptivePlotter` bundle and uses LaunchServices. The launcher
must:

- activate one exact already-running bundled instance;
- never request a forced new instance;
- reject a same-name raw SwiftPM executable with PID and path;
- reject wrong-path or duplicate bundle instances;
- prove exact bundle identity, bundled executable, finished launch, regular
  activation policy, and foreground activation;
- never kill a user-owned process.

The bundle declares camera purpose only. Closing the last window performs
bounded workspace shutdown and terminates the application.

## Evidence and validation discipline

Report automated, simulated, controller, camera, human-observed, and
ink-observed evidence separately. A passing test proves software behavior. It
does not prove audible output, physical movement, pen pose, or ink.

Physical validation requires an operator present with the power cutoff
reachable. If that condition is absent, record the physical pass as skipped and
leave all physical outcomes unclaimed.

## Fixed exclusions

Do not introduce:

- a learning-stage motion gate or alternate authority state machine;
- a renamed startup ceremony;
- persistent workflow restoration or historical replay;
- a compatibility alias for deleted concepts;
- an auxiliary Learning Path window or fixed-dock compatibility layout;
- a standalone Jog Observations surface, jog-response dataset, or renamed
  compatibility route outside a numbered Learning Path exercise;
- a hard-coded application travel horizon that normally ends Boundary
  Discovery before the operator's Stop;
- invalidation derived from row order instead of declared data dependencies;
- naïve averaging of frames, categorical labels, controller events, or current
  state facts;
- a second process, service, bridge, event bus, or duplicated state owner;
- ambient natural-language machine control;
- model-selected movement except a future explicit bounded experiment inside
  Adaptive Drawing;
- any implication that simulator output or controller settlement proves ink.
