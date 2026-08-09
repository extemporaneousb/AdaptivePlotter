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

- One singleton window contains a user-resizable Learning Path navigator, the
  always-mounted protected camera/action surface, and selected exercise detail.
- The persistent pinned exercise strip is the sole exercise-control location;
  no auxiliary path window, fixed dock allocator, panel-launcher chrome,
  separate jog-recording surface, or exercise-specific toolbar Stop survives.
- Visible motion language is Enable Motion, Motion Enabled, or Motion Disabled.
  The internal runtime retains `MotionGuard` as its precise safety type.
- The Learning Path shows Complete, Current, Next, Future, and Needs Attention,
  with no global percentage.
- Structured exercise detail shows number, participant, timeline, instructions,
  expected observation, evidence, requested feed/source, typed choices, and an
  actionable runtime-owned unavailable reason.
- Needs Attention names the current actor, action, typed outcome, detail, and
  recovery. The optional Utilities region has explicit Show/Hide control and
  collapses before it can starve the protected camera.
- Motion Enabled reflects current-session authorization and remains enabled
  while its owner is busy. Ready, Busy, Unavailable with the exact reason, and
  Needs Attention are separate request-status projections.
- The Motion panel labels X/Y distance and feed units, labels each direction,
  and shows one red Stop Manual Jog only for the exact active manual owner.
- Start actions cannot silently no-op; their direct unavailable reason is shown.
- Clear acceptance is unavailable until the current label and observation are
  both Clear.

Redo This Step and Record Another Attempt are distinct typed actions. Successful
replacement atomically supersedes the old accepted artifact and invalidates only
declared transitive consumers. Additional attempts retain compatible provenance
and expose typed aggregates with sample count, estimator identity, uncertainty
or categorical counts, and included attempt identities.

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

- `ContextualStopTarget` covers Boundary Discovery, manual jog, and drawing
  trial with a unique capability identity.
- Exercise Stop lives only in the pinned action strip; manual Stop lives only in
  the Motion panel. Exactly one contextual software Stop is visible for the
  current owner.
- Boundary Stop records the operator event before one cancel byte, awaits the
  original owner through Idle/final MPos, captures a strictly newer exact frame,
  updates the selected side posterior, and advances.
- Repeated Stop calls share a target latch and emit one cancel.
- Manual Stop uses the same mechanical primitive, rejects stale capabilities,
  and creates no boundary evidence.
- Shutdown closes new admission, settles an active owner once, then drains,
  stops camera capture, disconnects, and clears current-session evidence.

### Human-Guided Discovery

- Pen Interaction uses typed YES/NO questions and leaves successful completion
  dependent on the final human observation of Up.
- Boundary Discovery supports four directions, but one successful relevant side
  is sufficient for the visible transition.
- Boundary selection is inert and Start directly admits the logical owner;
  there is no generic preparatory Boundary YES/NO question.
- One typed logical boundary owner renews finite GRBL wire segments after
  unambiguous natural completion. Stop closes renewal before controller cancel;
  a real limit, alarm, refusal, disconnect, fault, or ambiguity produces Needs
  Attention and no boundary evidence. There is no application-selected
  completion horizon.
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

### Artifact revisions and exercise attempts

- Each accepted step result has a typed artifact revision and exact attempt ID.
- Declared consumed-revision edges, not row order, drive transitive
  invalidation. Independent boundary observations survive a Pen Interaction
  replacement; replacing a Clear pose or clean reference invalidates only the
  trial artifacts that cite that exact revision.
- Failed, refused, unclear, cancelled, and ambiguous attempts remain provenance
  but cannot manufacture an accepted value or enter a successful aggregate.
- Compatibility binds camera configuration, coordinate space, units,
  direction/group, and algorithm revision. Incompatible attempts are not pooled.
- Numeric aggregates expose estimator revision and uncertainty; categorical
  aggregates expose counts/proportions; current state uses the latest accepted
  observation. Exact frames, controller events, strings, identifiers, refusals,
  and ambiguity remain individual provenance.

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
- SIMULATED uses the same Learning Path, motion controls, questions, camera
  utilities, and action locations as LIVE. Its typed runtime covers session,
  authorization, MPos, pen pose, manual jog, renewable Boundary Stop/Cancel,
  drawing, and deterministic camera evidence.
- A complete simulated Learning Path reaches Adaptive Drawing with zero
  `MachineActions` calls. Every simulated evidence surface is marked
  `SIMULATED — NOT PHYSICAL EVIDENCE`; returning to LIVE discards simulated
  artifacts and restores the parked LIVE authority unchanged.

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

The automated coverage includes:

- exact five-stage/substep presentation vocabulary, pure navigator selection,
  protected camera allocation, structured cues, and typed operator actions;
- atomic replacement, explicit dependency invalidation, compatible attempt
  aggregation, unsuccessful-attempt exclusion, and latest-state selection;
- one logical boundary owner across finite segments, Stop-versus-renewal
  latching, and one-cancel manual and boundary Stop behavior;
- Stop-before-cancel event order, Idle/final MPos, exact newer frame, posterior,
  and one-boundary progression;
- Cancel and active-boundary shutdown settlement without successful boundary
  evidence;
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

The recorded response matrix is historical evidence only. Its existence does
not justify restoring the removed jog-response product surface or model path.

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

Close any raw SwiftPM process manually, run `make run-app`, verify one exact
bundled instance, keep the cutoff reachable, and execute
[First Hardware Session](FIRST_HARDWARE_SESSION.md). Record controller, camera,
human-observation, and ink evidence separately.
