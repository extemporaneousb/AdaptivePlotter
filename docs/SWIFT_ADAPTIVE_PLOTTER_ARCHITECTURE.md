# AdaptivePlotter Minimal Local Architecture

Status: current target architecture
Platform: native macOS Swift/SwiftPM

## 1. Product decision

AdaptivePlotter is one signed local application with one operator workspace,
one Learning Path, one controller owner, and one camera owner. The application
does not depend on a local web service, Python process, bridge, remote API,
duplicated state store, or arbitrary language-to-controller translation.

The camera-first workbench is the primary action surface. Detailed panels reserve
side rails instead of covering the image. The toolbar owns controller selection,
Connect/Disconnect, Enable Motion, one contextual Stop, and compact truthful
camera/plotter/motion indicators.

## 2. Package shape

```text
PlotterModel
  typed geometry, identifiers, drawing programs, residuals, model snapshots

PlotterRuntime
  controller protocol and parser
  MachineController / RunInterpreter
  CameraCapture / VisionWorker / analysis pipeline
  HumanGuidedDiscovery transactions and boundary posterior
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
question -> YES -> spoken cue -> bounded jog
-> contextual Stop event -> one cancel
-> original owner Idle/final MPos
-> strictly newer exact frame
-> side measurement -> posterior update
```

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
- exact current participant/action/expected-observation projection;
- button routing to typed runtime operations;
- the one contextual Stop target and one-cancel latch;
- current-session discovery, Clear-view, and drawing-trial evidence;
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

`LearningPathFlowCoordinator` stores presentation location only. It cannot make
a controller request eligible.

## 5. Mechanical admission

The direct request path is:

```text
button-owned typed intent
-> OperatorWorkspace presentation check
-> RunInterpreter operation ownership
-> MachineController repeats direct safety checks
-> closed wire command
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

## 6. Stop ownership and shutdown

`ContextualStopTarget` distinguishes Boundary Discovery, manual jog, observed
jog, and drawing trial. The toolbar shows Stop only while a target exists.

The one-cancel latch prevents repeated button presses and shutdown from emitting
duplicate cancellation. Boundary Stop records the typed operator event before
the byte and awaits the original boundary task through its frame/posterior
continuation. Manual Stop awaits its owner and creates no discovery evidence.

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

SIMULATED content uses the same renderer but cannot invoke machine actions or
produce physical evidence.

## 9. Learning evidence and models

`ExplorationEpisode` is retained only as a typed evidence record. It may contain
exact action, controller, frame, ink, residual, assessment, source, and actual
dataset-split fields. It is not a lifecycle owner.

Actual model fitting may use training and reserved observations. Model
candidates remain diagnostic until explicitly compared with held-out evidence.
Active learning is reserved for a future model-selected bounded experiment; it
does not describe the current stage sequence.

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
- boundary natural completion records no boundary;
- unclear ink records no success and triggers no redraw;
- speech-output failure leaves visible buttons available;
- conflicting process identity refuses supported launch with PID/path.

No failure path silently changes authority or invents physical evidence.

## 12. Validation boundary

Automated tests cover parsing, direct safety checks, one-cancel behavior,
shutdown settlement, announcement serialization, exact-frame provenance,
presentation, simulator isolation, bundle validation, and launcher decisions.

Audible output, camera throughput, physical movement, physical pen pose, and ink
require attended validation. They remain unverified whenever that pass is
skipped.
