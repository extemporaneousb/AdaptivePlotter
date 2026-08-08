# Current Implementation Status

Status date: 2026-08-08
Target: this Mac and attached plotter only

This document separates implemented software, automated evidence, recorded
camera/controller evidence, earlier attended physical evidence, and work that
still requires an operator.

## Bottom line

AdaptivePlotter is one native Swift application with a camera-first workbench,
one persistent controller owner, one camera owner, typed bounded motion, exact
frame provenance, deterministic simulated imagery, and a persistent five-stage
Learning Path.

The implemented operator journey is:

1. Connect
2. Enable Motion
3. Human-Guided Discovery
4. Observed Drawing Trials
5. Adaptive Drawing

Stage 3 is visibly ordered as Pen Interaction, Boundary Discovery, and
Clear-View Discovery. Stage 4 is visibly ordered through the six clean/start/
anchor/draw/clear/compare actions. Stage 5 is truthfully Future. These stages are
ergonomic presentation and do not gate ordinary manual motion.

Buttons own every question, label, progression decision, typed comparison, and
Stop. Spoken announcements are output-only, serialized, completion-aware, and
advisory. The old audio-input and recognition stack is absent from source,
tests, bundle privacy declarations, and current UI.

## Implemented application behavior

### Workbench and Learning Path

- The current source still has a primary camera-first workspace plus an
  auxiliary Learning Path window, a fixed custom dock allocator, a toolbar
  contextual Stop, and a standalone Jog Observations diagnostic surface.
- Those presentation surfaces are superseded. The accepted next increment has
  one singleton window with resizable Learning Path, always-mounted camera, and
  selected exercise/action regions. Stop moves into the exercise action strip;
  no separate Learning Path or Jog Observations window/control survives.
- Visible motion language is Enable Motion, Motion Enabled, or Motion Disabled.
  The internal runtime retains `MotionGuard` as its precise safety type.
- The Learning Path shows Complete, Current, Next, Future, and Needs Attention,
  with no global percentage.
- One current panel shows number, participant, action, expected observation,
  requested feed/source, typed choices, and an actionable runtime-owned
  unavailable reason.
- Start actions cannot silently no-op; their direct unavailable reason is shown.
- Clear acceptance is unavailable until the current label and observation are
  both Clear.

The accepted workbench and typed Redo/Record Another Attempt semantics are
specified but not yet implemented in the source described above.

### Controller

- Explicit `/dev/cu.*` discovery and selection.
- One persistent BSD `termios` link at 115200 baud.
- GRBL/grblHAL-tolerant parsing with raw bytes and unknown fields retained.
- Fixed passive `$I`, `$G`, `?`, `$$`, `$#` inspection with bounded responses.
- Typed controller state, MPos, X/Y pins, commanded pen state, internal motion
  authorization, feed limits, acceleration, operation, refusal, completion, and
  ambiguity.
- Closed locale-independent `$J=G91 G21 ... F...` encoding; the UI cannot
  provide controller text or bytes.
- Direct checks for selected responsive link, controller state/alarm, pins,
  position, feed support, required pen state, operation ownership, and sticky
  ambiguity.
- `ok` is acceptance only. Completion requires bounded polling to fresh Idle
  with final MPos. Uncertain outcomes are sticky and never resent.
- Pen actuation is closed to `PenCommand.raise/lower` with the local profile.
- `DrawingStrokeRequest` is a distinct finite Pen Down operation; cancellation
  raises once after settled cancellation, while ambiguity sends no follow-on.
- The controller's `$110/$111` values are exposed read-only as
  `ControllerAxisFeedLimits`.

### Unified Stop

- `ContextualStopTarget` covers Boundary Discovery, manual jog, observed jog,
  and drawing trial.
- The primary toolbar is currently the only visible contextual software Stop;
  that placement is outgoing.
- Boundary Stop records the operator event before one cancel byte, awaits the
  original owner through Idle/final MPos, captures a strictly newer exact frame,
  updates the selected side posterior, and advances.
- Repeated Stop calls share a target latch and emit one cancel.
- Manual Stop uses the same surface and creates no boundary evidence.
- Shutdown closes new admission, settles an active owner once, then drains,
  stops camera capture, disconnects, and clears current-session evidence.

### Human-Guided Discovery

- Pen Interaction uses typed YES/NO questions and leaves successful completion
  dependent on the final human observation of Up.
- Boundary Discovery supports four directions, but one successful relevant side
  is sufficient for the visible transition.
- The current implementation uses fixed 300 mm X and 150 mm Y jog horizons and
  fails the transaction if the request completes before Stop. Those hard-coded
  horizons are a known defect: the accepted behavior is one operator-stopped
  logical boundary owner, with a real controller limit/fault producing Needs
  Attention rather than boundary evidence.
- Other directions remain optional evidence.
- Boundary evidence retains final controller MPos, exact post-stop frame and
  configuration, observed tool centroid, side association, uncertainty, and
  posterior count.
- Clear-View Discovery records Blocked/Partial/Clear exact-frame labels and one
  accepted repeatable Clear pose.
- Controller/camera authority invalidation clears dependent current-session
  completion presentation.

### Travel feed

- X-only Pen Up discovery/travel requests the reported X ceiling.
- Y-only requests the reported Y ceiling.
- Multi-axis Pen Up travel requests the minimum participating-axis ceiling.
- Missing controller capability uses the existing positive feed as a nonblocking
  fallback.
- No firmware settings are written and Pen Down drawing feed is unchanged.
- The UI reports the requested feed and source; it does not claim achieved
  physical speed.

### Observed Drawing Trials

- Capture Clean Reference retains an exact frame and begins one attributable
  in-memory episode.
- Choose Line Start retains current MPos.
- Create Anchor Mark performs announced lower/raise, returns Clear, and observes
  the anchor.
- Draw Isolated Line uses one closed drawing request with no auto-resend.
- Clear Tool and Observe Ink returns Pen Up to the accepted Clear pose and
  compares exact clean/anchor/post frames.
- Compare Intended and Observed Geometry records one of two typed human
  assessments.
- Missing or unclear ink is explicit and never triggers redraw.

### Outgoing Jog Observations diagnostic

- The current source can separately record physical jog observations and fit a
  current-session online jog-response diagnostic.
- This is not a numbered Learning Path exercise and is inconsistent with the
  accepted attempt model. The next increment removes its UI, observed-jog Stop
  target, dataset/model path, tests, and documentation unless an implementation
  audit proves a lower-level primitive is consumed by a real numbered exercise.
- `Record Another Attempt` must be implemented on each exercise's typed attempt
  group and must not rename or wrap this diagnostic.

### Camera and vision

- AVFoundation discovery, explicit selection, authorization, lifecycle, and a
  newest-frame-only stream.
- Preview materialization capped at 10 fps; exact analysis creates immutable
  BGRA `StampedFrame` bytes.
- `latestLiveCameraFrame` drives liveness independently of held analysis pixels.
- Exact `FrameID` and `CameraConfigurationID` bind measurements and overlays.
- Manual snapshot/analysis and bounded 2/5/10 Hz automatic analysis.
- Green-cap and frame-side camera measurements; drawing-frame and armature
  overlays explicitly inferred.
- A one-entry frame/configuration image cache and shared LIVE/SIMULATED
  aspect-fit renderer.
- SIMULATED actions cannot reach machine closures and remain nonphysical.

### Spoken output

- `NativeSpeechAnnouncer` uses an identity-bound serialized queue.
- Outcomes are completed, failed, timed out, or cancelled.
- Late delegate callbacks cannot resolve the next request.
- Relevant movement waits for a bounded output outcome and rechecks the typed
  context.
- Output failure leaves the visible action available.

### Signed launch and lifecycle

- `make run-app` builds the current bundle before launch.
- `Scripts/build_local_app.sh` prefers `AdaptivePlotter Local Development` or an
  explicit `ADAPTIVEPLOTTER_CODESIGN_IDENTITY`.
- The bundle identifier is `com.bullard.AdaptivePlotter` and camera is its only
  privacy-purpose declaration.
- The launcher scans current-user executable paths and running applications.
- One exact already-running bundle is activated and reported by PID.
- A raw SwiftPM executable, wrong-path instance, or duplicate instance causes an
  actionable refusal with PID/path and is never killed automatically.
- Launch completion proves exact bundle/executable, regular activation policy,
  and foreground activation.
- Closing the last window drains workspace shutdown with a bounded AppKit
  termination deadline.

## Automated evidence for this increment

The currently recorded automated coverage includes:

- exact five-stage/substep presentation vocabulary and typed operator actions;
- one-cancel manual and boundary Stop behavior;
- Stop-before-cancel event order, Idle/final MPos, exact newer frame, posterior,
  and one-boundary progression;
- active-boundary shutdown settlement;
- controller-ceiling and fallback feed selection;
- output announcement ordering, identity isolation, and advisory failure;
- typed discovery transactions and 4.6 assessment;
- simulator isolation;
- launcher exact-instance decisions and synthetic raw-process refusal;
- signed bundle and camera-only privacy validation;
- full normal and strict Swift builds/tests.

Automated evidence proves software behavior only.

## Recorded local environment

| Fact | Recorded value |
| --- | --- |
| Host | x86_64 MacBook Pro (`MacBookPro15,1`) |
| macOS | 15.7.8 |
| Swift | Apple Swift 6.1.2 from Command Line Tools |
| Camera | HD Pro Webcam C920 and built-in FaceTime camera; C920 observed at 1920×1080 |
| Controller | `/dev/cu.usbserial-A10OF67O`; grblHAL 1.1f on BlackBox X32 |
| Controller settings | X 40.18235 steps/mm, Y 45.09100 steps/mm; recorded X/Y maximum feed 500 mm/min; acceleration 10 mm/s² |
| Local signing | `AdaptivePlotter Local Development` available in the login keychain |

These values are observations from this machine, not portable safety limits.

## Earlier attended physical evidence

The repository's prior attended sessions recorded the following physical facts:

- passive controller exchanges completed in powered and unpowered comparisons;
  grblHAL did not expose motor-supply state;
- bounded X/Y jogs completed with Idle/final MPos and inverse returns;
- eight integrated 1 mm observations at 100 mm/min produced four training and
  four reserved camera-displacement episodes, all with cap confidence 1.000;
- the diagnostic through-origin matrix was
  `[[-1.6907, 0.1585], [-0.1581, -1.2680]]` pixels/mm, with training RMS/max
  0.164/0.205 px and reserved RMS/max 0.337/0.551 px;
- three current 1920×1080 C920 frames were captured with exact manifest
  provenance;
- typed Pen Up and Pen Down were physically observed; the local lower profile at
  `S760` produced a green contact dot, and the final `S40` left commanded state
  Up.

Those facts remain bounded to their recorded sessions. They do not validate the
new integrated Learning Path, spoken cue timing, operator-stopped Boundary
Discovery, unified Stop progression, or full observed line trial.

The recorded jog-response matrix is historical evidence only. Its existence
does not justify retaining the outgoing Jog Observations product surface or
model path.

## Not yet physically verified

This increment did not perform an attended hardware run. The following remain
unverified for the integrated current build:

- real existing-bundle activation and foreground/Dock behavior;
- audible native announcement completion before movement;
- no audio-input permission prompt in a clean interactive run;
- Pen Interaction's full physical sequence and final observed Up;
- operator-stopped Boundary Discovery without a hard-coded application travel
  horizon;
- one-button one-cancel behavior on the attached controller;
- exact post-stop frame and visible progression on live hardware;
- Clear-pose repeatability;
- anchor, isolated line, cleared-tool observation, and intended/observed
  comparison with actual ink;
- Adaptive Drawing, which is intentionally unavailable.

## Next attended action

First land the one-window workbench, attempt model, Jog Observations deletion,
and operator-stopped Boundary Discovery increment. Then close any raw SwiftPM
process, run `make run-app`, verify one exact bundled instance, keep the cutoff
reachable, and execute [First Hardware Session](FIRST_HARDWARE_SESSION.md).
Record controller, camera, human-observation, and ink evidence separately.
