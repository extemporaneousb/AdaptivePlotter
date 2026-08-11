# AdaptivePlotter Architecture

Status: current native macOS architecture

This document owns package boundaries, runtime owners, and dependency direction.
Product invariants live in [Product Contract](PRODUCT_CONTRACT.md); the exact
operator sequence lives in
[Discovery and Observed-Trial Protocol](DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md).

## Package topology

```text
PlotterModel
  typed coordinates and geometry
  identifiers and canonical drawing programs
  registration, transforms, residuals, model candidates and datasets

PlotterRuntime
  GRBL protocol, MachineController and RunInterpreter
  CameraCapture, VisionWorker and bounded analysis
  HumanGuidedDiscovery and learning artifacts
  armature guidance and isolated-ink observation
  causal learning simulator and output-only announcements
  in-memory workflow evidence plus durable accepted-artifact checkpoints

PlotterApp
  OperatorWorkspace composition and projection
  SwiftUI workbench, camera surface and lifecycle

PlotterTestSupport
  deterministic links, clocks, transcripts and scene fixtures
```

Dependencies point inward. Runtime does not import SwiftUI. App composition
constructs closures around runtime actors; views receive one observable
`OperatorWorkspace`.

## Runtime owners

### MachineController

`MachineController` exclusively owns the selected `MachineLink`, GRBL parsing,
passive inspection, internal Motion authorization, direct admission checks,
command serialization, deadlines, final settlement, and sticky ambiguity.

Its write surface is closed:

- typed finite relative jogs;
- typed pen commands using the local pen profile;
- typed drawing strokes;
- one GRBL realtime Jog Cancel byte for the exact active operation.

UI and learning code cannot provide G-code, bytes, servo values, homing, unlock,
reset, alarm clear, or firmware writes.

### RunInterpreter

`RunInterpreter` owns one current logical operation and delegates mechanical
execution to `MachineController`. It does not replay history or duplicate
controller state. Its Jog Cancel route is the mechanical primitive behind the
workspace's contextual Stop capabilities.

### CameraCapture and VisionWorker

`CameraCapture` owns AVFoundation device discovery, selection, authorization,
stream lifetime, capture heartbeat, exact-frame materialization, and shutdown.
Capability-scoped preview holds suppress materialization and publication without
stopping AVFoundation delivery or changing camera configuration. The newest raw
buffer replaces older buffers during a hold; releasing the final current-session
capability publishes at most one newest preview. A held display frame remains
the exact computation input and is not relabeled as newly captured evidence.

`VisionWorker` consumes immutable frame bytes and emits typed measurements.
Visibility-target observation is a foreground owner with an ID, cancel
capability, authority generation/context, phase, and stored Task. Cooperative
cancellation reaches capture polling and Vision loops; shutdown and authority
erasure cancel and await it before teardown. Late or incompatible completions
are discarded before artifact or overlay mutation.
The analysis pipeline admits one active request and retains only the newest
pending request. Measurement and overlay provenance include exact frame,
camera-configuration, source, kind, and algorithm revision.
Newest-only scene analysis is a scoped producer, not an authority. Camera
startup does not enable it. Supervised Pen-Up Learning Path movement may own it
at 2 Hz; final settlement stops it and discards pending work. A LIVE Boundary
owner instead uses finite explicit exact-frame inspections for renewal advice.
No producer survives its movement or inspection owner.
All expensive Vision paths use the same still-frame computation lease: preview
publication pauses and raw capture continues. Motion-scoped cadence is a
post-completion recovery interval, not permission to outlive the motion owner.
Pixel scans use immutable-buffer access and cooperative row-level cancellation
so finite explicit inspection can settle without waiting for a full-frame scan.

### Human-Guided Discovery

`DiscoveryTransaction` records current-session typed questions, button choices,
announcements, controller events, frames, human observations, and vision facts.
It is not persistent workflow authority.

A Boundary operation is distinct from an ordinary manual jog. Selecting a side
is inert; explicit Start admits one renewable logical owner. Operator Stop
closes renewal, emits one cancel, awaits final Idle/MPos, and atomically commits
the controller-side attempt and per-side aggregate. The commit contains no
frame, cap/contact centroid, confidence, or Vision result. No preparatory generic
YES/NO question or camera edge association exists in this sequence.

`BoundaryApproachPlanner` consumes consecutive compatible exact-frame cap
bottom-center observations and the controller's settled MPos displacement. It
derives an observed pixels/mm scale, ray-projects motion to the inferred drawing
frame envelope, and chooses a bounded coarse-to-fine segment tier. Its async
runtime seam consumes only the latest completed advisory and launches the next
Camera/Vision inspection off the motion-owner critical path. It immediately
returns the cached tier or 20 mm fallback. `RunInterpreter` reconstructs
direction and feed from the admitted request and checks the Stop latch before
and after advice retrieval and immediately before any successor write.

Accepted artifacts are a separate persistence boundary. The durable checkpoint
contains only current accepted machine-space Boundary payloads and dependency
revisions. It is loaded as quarantined evidence and promoted only after a fresh
compatible passive controller probe and MPos comparison. It cannot serialize or
restore a `DiscoveryTransaction`, operation ownership, authorization, live Stop
capability, pending command, or successor action.

The machine-space aggregate consumes typed direction and compatible settled
MPos samples. Separate current-camera calibration owns exact frame/contact
provenance for optical registration. Estimated center and learned local
coordinates derive from the four current aggregate revisions.

`ControllerPositionAcceptancePolicy` compares every production requested pose
and final controller MPos using Euclidean residual and a quantization-aware
0.05 mm tolerance. Exact pose means fresh attributable MPos in compatible
controller context, not mathematically zero residual. Failed or stopped center
travel leaves the four aggregate revisions current and projects one center-only
**Retry Center Arrival** action; it does not route through generic exercise
Restart. The same policy governs bounded camera-calibration samples, returns to
captured or registered poses, and other production pose checks.

### SpeechAnnouncements

`NativeSpeechAnnouncer` is an identity-bound output queue. Each request ends as
completed, failed, timed out, or cancelled. Late callbacks cannot resolve a
successor request. Speech owns no answer, machine intent, Stop, or workflow
state.

### OperatorWorkspace

`OperatorWorkspace` is the single app-side observable owner. It projects facts
and sequences typed actions without replacing runtime admission.

It owns:

- controller and camera selection/status projection;
- Learning Path runtime current state and separate navigator selection;
- current exercise presentation and typed actions;
- contextual Stop identity and one-cancel latching;
- discovery, visibility, and observed-trial orchestration;
- accepted artifact slots, attempt histories, aggregates, and dependency
  invalidation;
- LIVE/SIMULATED authority parking;
- bounded shutdown.

At Stage 3.3, `OperatorWorkspace` routes one public capture-and-build intent. It
captures target-pose MPos and an exact frame, runs the bounded three-sample Pen
Up calibration if required, returns under the shared settlement policy, and
stages a proposal. Proposal acceptance and rejection remain separate typed
operator intents.

Views own no independent workflow state. Presentation helpers may format or
reduce immutable values but cannot admit commands or promote evidence.

### RunLedger

`RunLedger` stores ordered diagnostic transactions and facts. It does not decide
eligibility, restore a workflow, or promote model state.

## Workbench composition

One SwiftUI window contains:

```text
Learning Path navigator | camera/action surface | exercise detail/actions
                                      + Motion region
                                      + optional Utilities inspector
```

The camera surface remains mounted while selection or pane visibility changes.
Native split views own user resizing. Static minimum dimensions are inputs to
the real SwiftUI layout; there is no parallel arithmetic layout simulator.

The toolbar owns global controller selection, Connect/Disconnect, Enable
Motion, and compact current status. Exercise detail owns Start, choices, Cancel,
Stop, Restart, Redo, and Record Another Attempt. Manual jog owns Stop Manual Jog
in Motion. A unique active Stop remains reachable even while another row is
being reviewed.

A protocol-forced Boundary direction is rendered as required noninteractive
content. A chooser is rendered only when two or more valid directions remain.

Pane and Utilities visibility are window-local presentation state. They cannot
change runtime current state, controller authorization, accepted evidence, or
camera lifetime. A pane holding the only active Stop cannot collapse.

## Mechanical request path

```text
button-owned typed intent
-> OperatorWorkspace presentation check
-> RunInterpreter one-owner admission
-> MachineController direct checks
-> typed controller write
-> acceptance
-> bounded status polling
-> final Idle/MPos or typed refusal/ambiguity
```

Learning stage, boundary count, Clear pose, trial count, local coordinate frame,
and model confidence are absent from ordinary manual-motion admission.

Finite Boundary segments may renew only under the same owner after unambiguous
completion. Natural segment completion produces no side evidence. Stop closes
renewal before cancellation. Sticky ambiguity produces no successor write.

Shutdown closes new admission, cancels advisory output, settles an already
latched mechanical owner once, drains remaining hardware intents, stops camera
capture, disconnects the controller, and clears workspace presentation.

## Coordinates, frames, and registration

- `MachineSpace` is controller position and motion.
- `CameraPixelSpace` is captured image geometry.
- `FieldSpace` is drawing-program and accepted-model geometry.
- learned local millimetres are a derived presentation mapping over current
  Boundary aggregates.

`FrameID` identifies exact bytes. `CameraConfigurationID` rotates when optical
capture context changes. Frame-derived evidence and overlays cannot cross that
boundary silently.

Cancel is a typed exercise disposition presented only when no physical movement
owner is active. While motion is active, its unique Stop is the sole visible
movement-ending action. The runtime first-intent latch still rejects stale or
programmatic races. Cancel abandons the settled current attempt without
recording the successful Boundary Stop event or manufacturing completion
evidence. Restart is available only after settlement and creates a new attempt;
it cannot resend an ambiguous operation.

Machine-space Boundary aggregates are compatible by direction, controller
session, coordinate revision, space, units, and estimator. Camera configuration
does not split them. Machine-camera registration instead consumes compatible
exact machine/contact samples with their original frame and configuration.

The simulator uses an invertible uniform world-to-camera auto-fit whose identity
is recorded in every causal simulated frame. Presentation annotations are bound
to exact frame/configuration/viewport identity and do not modify canonical pixel
bytes or hashes.

## Artifact dependencies

The current dependency spine is:

```text
four boundary aggregates -> estimated center -> center arrival
-> target pose/contact/ROI -> accepted clear pose
-> blank baseline -> visibility-target execution
-> two-frame target observation -> visibility registration
-> target-present trial baseline -> line plan/execution
-> post-line frame -> ink observation -> comparison
```

Machine-camera registration separately consumes compatible exact current-camera
machine/contact samples. Learned local coordinates separately consume the same
four side aggregates and never enter motion admission.

Redo stages a replacement and atomically changes the accepted slot on success.
Only named transitive dependents are invalidated. Record Another Attempt adds a
compatible sample and recomputes the aggregate. Exact evidence remains
individually attributable.

`LearningVacatePlan` is the internal immutable summary and stale-state guard for
deliberate chronological resets. The UI presents it as Reset From This Step or
Reset All Learning with one Reset button and no typed phrase.
`OperatorWorkspace` derives its artifact roots from visible
Learning Path order, then asks `LearningDependencyGraph` to invalidate the named
current revisions and their causal consumers while clearing the matching payload
slots and active aggregate histories. This sequencing policy stays outside the
graph: causal Redo and chronological Reset are intentionally distinct operations.
The plan is source-bound (LIVE or SIMULATED), includes the accepted-attempt
sequence and current revision identities, and must still match when confirmed.

## Model boundary

`PlotterModel` may hold future-facing immutable drawing programs, transforms,
residuals, candidate fitting, dataset splits, and acceptance criteria. These
types are legitimate architecture when they implement the documented Adaptive
Drawing direction; their existence is not a claim that model-selected drawing
is current.

Accepted-model changes require explicit evidence comparison and occur only at a
safe checkpoint. No model chooses hidden motion, bypasses controller admission,
or redraws an ambiguous stroke.

## Launch and failure behavior

`make run-app` builds and validates the signed `.app`, builds the single-instance
launcher, inspects current-user processes, and either activates the exact bundle
or launches it through LaunchServices. Wrong-path, raw, or duplicate processes
cause refusal with PID/path; the launcher does not terminate them.

Failures are typed and actionable. They name the missing direct fact, retained
accepted artifact where applicable, and explicit recovery. No failure path
silently changes authority, retries a write, or invents physical evidence.

## Validation boundary

Automated tests cover parsing, direct admission, one-owner cancellation,
shutdown settlement, exact-frame provenance, dependency-aware attempts,
simulator isolation, presentation reducers, bundle validation, and launcher
decisions. Audible output, camera throughput, physical movement, physical pen
pose, human observations, and ink require attended validation.
