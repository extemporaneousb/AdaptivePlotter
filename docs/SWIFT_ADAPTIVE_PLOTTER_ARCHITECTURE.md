# AdaptivePlotter Minimal Local Architecture

Status: current target architecture
Platform: native macOS Swift/SwiftPM

## 1. Product decision

AdaptivePlotter is one signed local application with one operator workspace,
one Learning Path, one controller owner, and one camera owner. The application
does not depend on a local web service, Python process, bridge, remote API,
duplicated state store, or arbitrary language-to-controller translation.

The camera-first workbench is the primary action surface. One singleton window
uses a stable, user-resizable three-region split: Learning Path navigator,
always-mounted camera/action surface, and selected exercise detail/action strip.
The camera keeps a protected minimum and remains visible throughout operator
interaction. The toolbar owns global controller selection, Connect/Disconnect,
Enable Motion, and compact truthful camera/plotter/motion indicators; it does not
own exercise-specific Stop.

## 2. Package shape

```text
PlotterModel
  typed geometry, identifiers, drawing programs, residuals, model snapshots

PlotterRuntime
  controller protocol and parser
  MachineController / RunInterpreter
  CameraCapture / VisionWorker / analysis pipeline
  HumanGuidedDiscovery transactions and boundary posterior
  typed step artifacts, attempt groups, and dependency invalidation
  armature guidance and isolated-ink observation
  output-only SpeechAnnouncements
  in-memory learning evidence

PlotterApp
  OperatorWorkspace
  camera and controller composition
  Learning Path presentation
  SwiftUI workbench and lifecycle

PlotterTestSupport
  deterministic links, clocks, scene fixtures, and controller transcripts
```

Dependencies point inward. Runtime does not import SwiftUI. App composition
constructs closures around the runtime actors; views receive one observable
`OperatorWorkspace`.

## 3. Runtime owners

### MachineController

`MachineController` exclusively owns the selected `MachineLink`, probe parsing,
controller state, internal `MotionGuard`, command serialization, deadlines,
final settlement, and sticky ambiguity.

Its wire surfaces are closed:

- passive `$I`, `$G`, `?`, `$$`, `$#` inspection;
- typed `RelativeJogRequest` encoded as locale-independent GRBL `$J`;
- typed `PenCommand` using the closed local pen profile;
- typed `DrawingStrokeRequest`;
- one GRBL realtime Jog Cancel byte for the one active compatible operation.

The UI cannot provide G-code, bytes, servo values, homing, unlock, reset, alarm
clear, or firmware writes.

### RunInterpreter

`RunInterpreter` exposes one current operation and delegates execution to
`MachineController`. It does not replay history or create an alternate motion
authority. Its Jog Cancel function is the internal mechanical primitive behind
the workspace's single contextual Stop.

### CameraCapture

`CameraCapture` owns AVFoundation device discovery, explicit selection,
authorization, stream lifetime, newest-frame delivery, exact-frame capture, and
shutdown. Preview materialization is bounded; exact analysis materializes an
immutable `StampedFrame`.

`latestLiveCameraFrame` is the capture heartbeat. `displayedFrame` may be held
for analysis and must not drive liveness.

### VisionWorker and analysis pipeline

`VisionWorker` consumes exact bytes and produces typed camera-space
measurements. The bounded analysis pipeline has one active request and one
newest pending request. Overlay provenance includes exact frame,
camera-configuration, kind, source, and algorithm revision.

### Human-Guided Discovery

`DiscoveryTransaction` is a small in-memory deterministic transaction. It
records typed questions, button choices, announcements, controller events,
frames, human observations, and vision evidence. It has no persistence,
historical replay, or cross-launch authority.

Boundary transactions use the binding order:

```text
question -> YES -> spoken cue -> operator-stopped boundary owner
-> contextual Stop event -> one cancel
-> original owner Idle/final MPos
-> strictly newer exact frame
-> side measurement -> posterior update
```

The boundary owner is a typed operation distinct from an ordinary manual
`RelativeJogRequest`. It remains active until the operator Stop or a real typed
controller terminal condition. It does not expose a hard-coded X/Y search
distance as exercise completion. If GRBL requires finite jog segments, only an
unambiguously completed segment may renew under that same logical owner; Stop
closes renewal before cancellation, and ambiguity is never renewed or resent.
Segment completion alone records no boundary evidence.

`DrawingFramePosterior` retains associated side observations and uncertainty in
camera space. Controller MPos is retained as provenance, not numerically fused
into pixels.

### SpeechAnnouncements

`NativeSpeechAnnouncer` is output-only. A pure identity-bound queue serializes
requests. Each caller receives `completed`, `failed`, `timedOut`, or `cancelled`.
Late synthesizer callbacks cannot resolve a successor request. Shutdown cancels
the active and queued output exactly once.

Speech is advisory. It owns no machine intent, question answer, Stop decision,
or workflow state.

### OperatorWorkspace

`OperatorWorkspace` projects runtime state and sequences current actions. It
does not replace the controller checks. Its responsibilities include:

- controller/camera selection and current status;
- action-specific disabled reasons;
- five-stage Learning Path presentation;
- presentation-only navigator selection distinct from the runtime current step;
- exact current participant/action/expected-observation projection;
- button routing to typed runtime operations;
- typed Start, Cancel, Stop, Restart, Redo, and Record Another Attempt routing;
- the one contextual Stop target and one-cancel latch shared by Stop, Cancel,
  and shutdown settlement without conflating their semantic dispositions;
- current-session discovery, Clear-view, and drawing-trial evidence;
- current accepted step artifacts, preserved attempts, typed aggregates, and
  explicit data-dependency invalidation;
- advisory announcement ordering;
- bounded shutdown.

Disconnect, camera/controller authority change, and shutdown clear dependent
current-session presentation facts. Learning completion cannot remain true after
its supporting session evidence is invalidated.

## 4. Operator presentation

The exact visible stage model is:

```text
1 Connect
2 Enable Motion
3 Human-Guided Discovery
  3.1 Pen Interaction
  3.2 Boundary Discovery
  3.3 Clear-View Discovery
4 Observed Drawing Trials
  4.1 Capture Clean Reference
  4.2 Choose Line Start
  4.3 Create Anchor Mark
  4.4 Draw Isolated Line
  4.5 Clear Tool and Observe Ink
  4.6 Compare Intended and Observed Geometry
5 Adaptive Drawing (Future)
```

Stage states are Complete, Current, Next, Future, and Needs Attention. There is
no global percentage. A deterministic transaction may show its local numbered
position. Previous steps remain visible.

Navigator selection is window-local presentation state. It cannot make a
controller request eligible, change the runtime current step, or mutate accepted
evidence. The current step remains a separate runtime projection; reviewing
another row exposes a Return to Current affordance.

The main split is structurally stable:

```text
Learning Path navigator | camera/action surface | selected exercise and actions
```

The navigator is a native sidebar-style list. The camera is outside selection
conditionals. Native split dividers resize the visible regions, while explicit
Hide/Show controls collapse and restore the navigator, exercise detail, and
lower Motion region. A pane that owns the only contextual Stop cannot be hidden
until that operation settles. The exercise detail recovers the prior presentation's useful
question-card and timeline hierarchy without restoring its removed workflow
model. Its pinned action strip shows the state-appropriate Start, choices,
Cancel, Stop, Restart, Redo, or Record Another Attempt control. Critical cues
such as UP, DOWN, YES, NO, STOP, and typed directions are structured fragments
with accessible emphasis, never view-side searches through prose.

Toolbar status separates responsive-session state, Motion authorization, and
transient request availability. Authorization remains enabled while the one
owner is moving or actuating; Ready/Busy/Unavailable/Needs Attention is a
separate projection. Operation activity records identify actor, action,
outcome, detail, and recovery. The optional Utilities region has explicit
Show/Hide state and yields a collapsible side pane before the protected camera.
Successful LIVE camera start and restart enable bounded automatic scene
analysis at the selected cadence; semantic overlay layers begin visible and
remain exact-frame/configuration filtered.

There is no standalone Jog Observations presentation or hidden diagnostic
workflow. Repeat collection is an action on a numbered exercise and uses that
exercise's typed artifact, attempt group, and aggregate. The removed online
jog-response path is not reused as a generic repeat mechanism.

## 5. Mechanical admission

The direct request path is:

```text
button-owned typed intent
-> OperatorWorkspace presentation check
-> RunInterpreter operation ownership
-> MachineController repeats direct safety checks
-> typed controller command or boundary-motion segment
-> acceptance
-> bounded status polling
-> Idle and final MPos, or typed refusal/ambiguity
```

The repeated runtime checks include selected responsive session, current
internal authorization, controller state/alarm/pins, operation ownership,
position, pen state, feed support, and sticky ambiguity. Learning stage,
boundary count, Clear pose, trial count, and model confidence are absent from
ordinary manual admission.

`ok` is never completion. Unknown post-write state is sticky and never resent.

## 6. Exercise actions, Stop ownership, and shutdown

`ContextualStopTarget` distinguishes Boundary Discovery, manual jog, and drawing
trial and carries a unique capability identity. Exercise targets render Stop in
the persistent exercise action strip; a manual target renders **Stop Manual
Jog** in the Motion panel. Exactly one contextual Stop is visible for the exact
active owner even when another row is reviewed. The former observed-jog target
and its separate workflow are absent.

The one-cancel latch prevents repeated button presses and shutdown from emitting
duplicate cancellation. Boundary Stop records the typed operator event before
the byte and awaits the original boundary task through its frame/posterior
continuation. Manual Stop awaits its owner and creates no discovery evidence.
A stale capability is inert and cannot cancel a later operation.

Cancel is a typed exercise disposition. If no motion is active it abandons the
current attempt directly. If motion must settle, Cancel uses the same one-cancel
mechanical primitive and awaits the original owner, but it does not record the
successful Boundary Stop event or manufacture completion evidence. Restart is
available only after settlement and creates a new attempt; it cannot resend an
ambiguous operation. Start and typed choices continue to use existing direct
eligibility facts.

Shutdown first closes admission and increments the lifetime generation. It then
cancels advisory output, settles an already latched motion owner once, drains
other hardware intents, stops the camera, disconnects the controller, and clears
the workspace. Closing the last window has a bounded AppKit termination deadline.

## 7. Feed selection

The passive probe exposes read-only `ControllerAxisFeedLimits` in
`MachineSnapshot`. `TravelFeedSelection` records the requested value and whether
it came from `controllerReportedCeiling` or `existingFallback`.

Pen Up non-drawing travel uses the relevant axis ceiling, or the minimum for a
multi-axis path. Missing capability falls back to the existing positive feed.
No firmware write occurs. `DrawingStrokeRequest` retains its explicit drawing
feed.

## 8. Frames, coordinates, and observation

Coordinate types remain explicit:

- `MachineSpace` for controller positions and deltas;
- `CameraPixelSpace` for captured pixels and observed geometry;
- `FieldSpace` for drawing programs and accepted transforms.

`FrameID` identifies exact bytes. `CameraConfigurationID` changes across camera
selection/restart and prevents measurements from silently crossing optical
contexts. The shared aspect-fit renderer projects top-left-origin camera pixels
into the view.

SIMULATED content uses the same renderer and the same Learning Path/action
presentation. A separate typed actor owns simulated session, Motion
authorization, MPos, pen pose, manual jog, renewable Boundary motion,
Stop/Cancel, and drawing outcomes. It cannot invoke machine actions or produce
physical evidence. Every simulated evidence surface carries the exact
`SIMULATED — NOT PHYSICAL EVIDENCE` notice. LIVE accepted learning authority is
parked across simulation and restored unchanged when simulation is discarded.

## 9. Learning evidence and models

`ExplorationEpisode` is retained only as a typed evidence record. It may contain
exact action, controller, frame, ink, residual, assessment, source, and actual
dataset-split fields. It is not a lifecycle owner.

Actual model fitting may use training and reserved observations. Model
candidates remain diagnostic until explicitly compared with held-out evidence.
Active learning is reserved for a future model-selected bounded experiment; it
does not describe the current stage sequence.

Every repeatable learning step produces a typed artifact revision with an
attempt identity and explicit dependencies on the artifacts it consumed. The
accepted artifact slot is distinct from attempt history and from a derived
aggregate.

Redo runs a replacement attempt and atomically changes the accepted artifact on
success. The replaced artifact becomes superseded and is excluded from current
derived results. Only transitive dependents named by the artifact dependency
graph are invalidated; chronological successors without a dependency edge
survive.

Record Another Attempt preserves a compatible sample and recomputes the typed
aggregate from all valid compatible attempts. Aggregates expose `N`, estimator
identity, and uncertainty or categorical counts as applicable. Exact frames and
controller events remain separate provenance. Current-state facts such as pen
pose select the latest accepted observation rather than an arithmetic mean.
Attempts cannot be pooled across incompatible camera configurations, coordinate
spaces, units, or algorithm revisions.

## 10. Launch and lifecycle

`make run-app` is the physical launch boundary:

```text
swift build
-> construct signed .app
-> validate bundle/signature/privacy
-> compile launcher
-> inspect current-user processes
-> activate exact existing bundle OR LaunchServices-open exact bundle
-> prove identity/path/regular foreground activation
```

The launcher refuses raw SwiftPM executables, wrong-path instances, or
duplicates and reports their PID/path without terminating them. It never forces
a new application instance. The bundle identifier is
`com.bullard.AdaptivePlotter` and the preferred identity is
`AdaptivePlotter Local Development`.

## 11. Failure behavior

Failures must be typed and actionable:

- controller refusal identifies the current direct fact;
- ambiguity remains sticky and prevents automatic follow-on;
- missing newer camera frame names the freshness requirement;
- a boundary segment's natural completion records no boundary and may continue
  only under the same unambiguous active owner;
- a real controller limit, alarm, disconnect, or fault ends the boundary attempt
  as Needs Attention rather than success;
- unclear ink records no success and triggers no redraw;
- speech-output failure leaves visible buttons available;
- conflicting process identity refuses supported launch with PID/path.

No failure path silently changes authority or invents physical evidence.

## 12. Validation boundary

Automated tests cover parsing, direct safety checks, one-cancel behavior,
shutdown settlement, announcement serialization, exact-frame provenance,
presentation, dependency-aware replacement, attempt aggregation, simulator
isolation, bundle validation, and launcher decisions. UI tests exercise pure
selection/action/layout models and application lifecycle rather than parsing
Swift source text or preserving superseded view structure.

Audible output, camera throughput, physical movement, physical pen pose, and ink
require attended validation. They remain unverified whenever that pass is
skipped.
