# Current Implementation Status

Status date: 2026-08-08
Target: this Mac and attached plotter only

The canonical product purpose and training procedure are in
[Project Scope and Learning Architecture](../PROJECT_SCOPE_AND_MODEL_TRAINING.md).
This document records implementation and physical-evidence status.

## Bottom line

AdaptivePlotter is one local SwiftPM application with a camera-dominant action
surface, explicit AVFoundation camera selection, bounded preview work, exact
latest-frame capture/analysis, and a deterministic simulator rendered through
the same pixels-to-view path. One persistent native controller session owns
passive probes, bounded relative jogs, and typed pen actuation. A native unified
macOS toolbar opens independently collapsible and hideable workbench panels in
reserved left/right docks. The docks reframe the action surface and never cover
it; all detailed controls begin hidden so the camera owns the primary area.
The toolbar has one remembered device picker, one Connect/Disconnect action,
and one Activate Motion action; selection alone does not open a session. It also
shows current camera-live, plotter-connected, and motion-guard indicators. The
bottom status is an action that reveals and expands the Motion dock, where the
session guard can be activated or deactivated. Plotter turns green only after a
blocker-free passive inspection.
Motion turns green only when the guard is activated and an ordinary carriage
request is currently eligible, including a known Pen Up state.

Controller presentation separates the last responsive serial inspection from
software eligibility to send a motion request. It explicitly reports that
grblHAL does not provide motor-supply state instead of treating USB response as
proof of energized motors. Pen buttons are actions, not selected-state controls,
and the adjacent state says commanded Up/Down or unknown without claiming visual
confirmation.

Speech is owned by one persistent `ExplorationSession` started and ended from
the Learning window. It keeps one microphone/recognizer lifetime across Motion
Preflight, Armature Guidance, and Isolated Line episodes; episode completion or
cancellation changes contextual grammar without stopping listening. There is no
second recognizer owned by Motion Preflight. Permission-free injected simulator
speech uses the same routing boundary. Every nonempty operator hypothesis
interrupts spoken feedback before parsing, and stable partial `STOP` is accepted
once per utterance only in a cancellable active context.

Motion Preflight presents contextual questions and the complete set of answer
buttons for each current step. **Use Voice** is optional: when enabled, the
persistent session reads the same question and recognizes the same short
choices; turning it off switches the same active episode to injected/button
input and releases the microphone, while the physical answer buttons remain
usable. Re-enabling it reacquires microphone input without replacing the
session or episode. The surface shows `LISTENING`, the active
system input device, and a live 0...1 input-energy meter that is explicitly not
recognition confidence.

There are four boundary sequences and one Pen Cycle. Boundary prompts use
`YES`/`NO`, plus `STOP` during active motion; only `YES` or `STOP` can request
the typed cancellation path. The Pen Cycle asks whether the pen is initially
up, whether it is clear to lower, whether it is down after the settled lower
command, then raises and asks whether it is up. On-screen choices and speech
use one handler, so they cannot diverge in controller authority. Pen-state
answers remain operator observations paired with exact immutable camera frames;
the camera is not claimed to prove height. Wrong-context, ambient, and compound
phrases are rejected rather than partially executed.

The session has a closed contextual reflex grammar and a separate teaching-label
path for visibility, shape features, rankings, and reward. Its in-memory
`ExplorationEpisode` records preassigned training/reserved split, exact speech
hypothesis/acceptance/feedback timing, typed proposed and executed actions,
controller evidence, exact frame provenance, assessment, and residual. It is
not an audio recorder, replay system, or experiment database.

With the camera source set to SIMULATED, Learning can execute the complete
persistent-session ordering: Motion Preflight, blocked then clear Armature
Guidance, an accepted clear pose, exact clean/anchor/post frames, deterministic
anchor and line outcomes, paired ink subtraction, intended/observed/residual
overlays, and one contextual spoken assessment. Voice practice off selects
permission-free injected speech; on selects the real microphone. The full
simulator runner has no `MachineActions` path, and automated coverage proves it
invokes no controller closure. Its frames and outcomes remain simulated and
cannot satisfy physical evidence or update a physical model.

The Learning panel also exposes **Practice Voice (SIMULATED)** directly. It
opens the same question-and-choice timeline without physical authority; Voice
practice reads each question and accepts the displayed choices, while turning
Voice off leaves button-only practice. Completing or cancelling this standalone
practice stops its microphone. The practice path cannot touch `MachineActions`,
record physical evidence, satisfy a live episode observation, update the
drawing-frame posterior, or affect motion eligibility.

A boundary side is recorded only when cancellation resolves at Idle as
`MotionOutcome.cancelled(finalPosition:)`. Current code records the final
controller MPos as provenance and uses the strictly newer exact-frame tool
centroid to update one uniquely associated camera edge. Each side has an
image-space precision posterior; repeated nonduplicate observations narrow its
offset variance. Controller MPos is never numerically fused into image geometry.
Partial side posteriors and uncertainty remain visible; a closed frame estimate
does not exist until all four associated side lines intersect.
If the jog reaches its internal search horizon, normal completion is reported
and no boundary is recorded. Physical validation of this Motion Preflight
increment is still pending.

The on/off comparison was run with USB continuously attached. Both states
returned the same BlackBox X32/grblHAL identity, `Idle`, MPos X/Y 0.000, no
asserted pins, `Bf:100,1023`, `FS:0,0`, and `H:0`; all five passive exchanges
completed. Motor-supply state is therefore not observable through this serial
surface. An eligible request and a previously responsive controller cannot by
themselves prove that physical motion will occur.

The live camera and bounded jog paths are implemented and covered by automated
tests. The controller path now has physical evidence: the attached controller
was probed and completed bounded X and Y jogs. A later 10 mm X jog requested at
900 mm/min became correctly sticky-ambiguous because the running build's
completion deadline expired while the controller still reported `Jog`. The
source now derives a conservative trapezoidal/triangular deadline from parsed
per-axis feed caps and acceleration. A fresh powered session on 2026-08-05
verified that correction with non-ambiguous 1 mm X and Y round trips at
100 mm/min and exact inverse returns to MPos X 29.192 / Y -10.002.
The delivered controller-evidence path was checked again at 30 mm/min: X moved
+1.020/-1.020 mm and Y +0.998/-0.998 mm, with exact return to the same MPos,
Idle completion, no asserted pins, and no ambiguity. C920 frames bracketed
around those moves show the detected green cap displace and return. Those
separately captured samples are physical visual confirmation, but they are not
an integrated `PhysicalJogObservation` because restarting capture changed the
camera configuration identity between samples. A later current-session pass
closed that evidence gap with eight integrated 1 mm observations at the actual
100 mm/min feed: four immutable training episodes and four immutable holdout
episodes, all with 1.000 cap confidence. Every inverse pair returned to
controller X0/Y0. The resulting through-origin diagnostic matrix was
`[[-1.6907, 0.1585], [-0.1581, -1.2680]]` pixels/mm; training RMS/max residuals
were 0.164/0.205 px and holdout RMS/max residuals were 0.337/0.551 px. The fit
remains current-session diagnostic evidence only and grants no motion or model
promotion authority.
The rebuilt app now has camera permission and captured three current 1920x1080
C920 frames with exact manifest provenance. The production detector finds the
cap and two useful frame sides consistently in all three without deriving any
pixel-to-mm calibration. Typed Pen Up and Pen Down are now physically verified
over white paper. `S720` moved down but did not mark; one explicit adjustment to
the closed local profile at `S760` produced a green contact dot. An `S40`
command was separately observed lifting the tip after the earlier down attempt;
the final `S40` after contact was acknowledged and left the controller-commanded
state Up. Every command and settle completed without ambiguity. The closed
drawing-stroke and paired observed-ink software paths are now implemented, but
they have not yet been exercised on the physical machine.

## Simplifications now implemented

- Passive probes may be retried in the same app launch.
- The app no longer scans old SQLite files or blocks a new session because an
  earlier journal is empty, corrupt, unfinished, or unresolved.
- The optional log records controller exchanges and probe results but is not on
  the controller command path.
- SQLite uses WAL with normal rather than full synchronous durability.
- Recorded-run reducer/replay state and its UI timeline were removed.
- The remaining transcript replay/offline runtime composition was removed; the
  scripted GRBL link now exists only in `PlotterTestSupport`.
- Unused stable-frame selection, phantom coordinate spaces, polygon geometry,
  and the self-validating legacy evidence-fixture archive were removed.
- Accessibility-specific SwiftUI behavior and tests were removed.
- Normal build/test no longer forces complete strict concurrency or
  warnings-as-errors.
- Swift uses compatibility language mode; `make strict-check` remains optional.

## Recorded local environment

| Fact | Recorded value |
| --- | --- |
| Host | `x86_64` MacBook Pro (`MacBookPro15,1`) |
| macOS | 15.7.8 |
| Swift | Apple Swift 6.1.2 from Command Line Tools |
| Camera inventory | HD Pro Webcam C920 and FaceTime HD Camera (Built-in); C920 auto-selected and captured at 1920x1080 |
| Serial/controller | `/dev/cu.usbserial-A10OF67O`; grblHAL 1.1f on BlackBox X32, passively probed |
| Controller axis settings | X 40.18235 steps/mm, Y 45.09100 steps/mm; X/Y max feed 500 mm/min and acceleration 10 mm/s^2 |
| Operator travel prior | About 250 mm X by less than 100 mm usable Y after two X-parallel wood rails were added; controller zero is near physical center; not a safety limit |
| SQLite | System library available |

This environment is sufficient. No other Mac, full Xcode install, distribution
signing identity, app distribution configuration, or CI result is required. The
local bundle still uses an available development identity or ad-hoc fallback for
TCC attribution.

## Delivered source

### Controller

- `/dev/cu.*` discovery and explicit selection.
- BSD `termios` link at 115200 baud.
- GRBL/grblHAL-tolerant parser retaining raw bytes and unknown fields.
- Fixed `$I`, `$G`, `?`, `$$`, `$#` probe.
- Two-second absolute query deadline and bounded response size.
- Stop on timeout, disconnect, malformed required reply, `error:`, or `ALARM:`.
- Repeatable probe requests after completion or failure.
- One persistent selected-device session rather than one connection per probe.
- Typed controller state, MPos, asserted X/Y end-stops, commanded pen state,
  Motion Guard state, relative-jog/pen requests, refusals, completion, and
  ambiguity.
- Closed locale-independent `$J=G91 G21 ...` encoding; the UI cannot supply
  controller text or bytes.
- Direct pre-write checks for connection, recognized Idle state, asserted
  end-stops, MPos, finite nonzero delta, controller-reported feed capability,
  known pen-up state, Motion Guard activation, in-flight work, and sticky
  ambiguity. Operator coordinates and maximum-jog values are absent.
- `ok` is acceptance only; completion is a bounded status poll ending at Idle
  with final MPos. Uncertain physical outcomes are sticky and never resent.
- The only jog-interruption encoding is GRBL realtime Jog Cancel byte `0x85`.
  It is available only for the one transmitted `$J` operation, is prioritized
  ahead of queued ordinary writes, and is never resent. The byte has no `ok`;
  the original jog poll remains the only reply reader and resolves cancellation
  only after Idle supplies final MPos. A write/disconnect/uncertain final state
  remains sticky ambiguity. Jog Cancel is not Hold or an emergency stop.
- Successful passive configuration parsing supplies `$110/$111` axis feed caps
  and `$120/$121` acceleration to the jog deadline model. Firmware travel
  settings are not used as workspace bounds or calibration.
- The pen wire surface is closed to `PenCommand.raise/lower`. This mechanism's
  verified local profile emits `M3 S40` or `M3 S760`, followed by `G4 P0.3`;
  the UI cannot supply controller text or servo values.
- Probe, jog, and pen requests serialize through the same owner. Pen Down needs
  fresh Idle/non-alarm status, Motion Guard activation, and clear XY end-stop
  pins. Pen Up is available as the recovery direction without requiring MPos.
  Any uncertain post-write result becomes sticky, sets commanded pen state
  unknown, and is never resent.
- A successful pen outcome means both controller commands were acknowledged. It
  is explicitly not camera proof that the mechanism reached the requested pose.
- `DrawingStrokeRequest` is a distinct finite XY operation admitted only while
  controller-commanded pen state is Down. It owns acceptance through final
  Idle/MPos. A settled `STOP` raises once and ends cancelled in place; ambiguity
  sends no Pen Up or follow-on command and becomes sticky. Ordinary jog remains
  Pen-Up-only.

### Current-session diagnostics

- One SQLite file per selected-device machine session.
- Ordered diagnostic events.
- Ordered raw controller exchanges and probe summaries when logging is
  available.
- Probe execution continues if logging cannot be created or written.
- No old-run admission scan, artifact store, export subsystem, quota, retention
  policy, tombstone system, or replay product.

### Camera, geometry, and app shell

- Typed `FieldSpace`, `MachineSpace`, `CameraPixelSpace`, and related values.
- Polyline `DrawingProgram` and affine forward/inverse transform.
- Finite-value and coordinate-bound validation.
- AVFoundation discovery, explicit selection, permission/lifecycle state, and a
  newest-frame-only stream. Preview materialization is capped at 10 fps; skipped
  driver frames retain/coalesce pixel buffers instead of copying and hashing
  every 1920x1080 delivery. An explicit analysis/snapshot request still creates
  one exact immutable BGRA `StampedFrame`.
- Automatic startup preference for a C920/HD Pro Webcam when present, followed
  by three 750 ms-spaced PNG samples and a provenance manifest under
  `~/Library/Application Support/AdaptivePlotter/CameraSamples/` after capture
  actually reaches Running. The samples are offline vision inputs, not
  calibration evidence.
- Monotonic frame sequence/timestamps and configuration identity changes across
  selection/restart.
- One `ActionSurface` for both LIVE and SIMULATED `DisplayedFrame` values using
  a tested aspect-fit, top-left-origin camera-pixel projection.
- Typed camera-pixel overlay geometry with exact source frame and camera
  configuration provenance; mismatched overlays are hidden.
- Manual **Analyze Frame** holds the exact measured frame while showing the
  connected-component cap and robust top/right side overlays; **Resume Preview**
  releases it. **Save Snapshot** writes an exact PNG plus provenance manifest.
- **Auto Analyze** runs at an explicit 2, 5, or 10 Hz target through a bounded
  pipeline with at most one active and one newest pending frame. Delivery,
  preview/exact materialization, analyzed/superseded counts, and last latency are
  shown in the Camera panel. Live throughput still needs measurement on this Mac.
- Overlay kinds and sources are typed. Pen cap and frame sides are measured;
  drawing-frame and armature envelopes are labeled inferred. Each kind can be
  toggled independently, including the plotter-model estimate when present.
- Deterministic model-mismatch simulation supplies logical, predicted,
  simulated-observed, residual, cap, frame-side, and commanded-pen layers through
  the same renderer. It is labeled `SIMULATED — NOT PHYSICAL EVIDENCE` and has no
  machine-link dependency.
- A fully wired X−/X+/Y−/Y+ widget with independent X/Y step values, feed,
  actual Pen Up/Pen Down commands, MPos, controller state, current operation,
  last outcomes, and one actionable disabled reason. It has no operator-entered
  coordinate envelope, maximum-jog field, typed-limit review, or apply step.
- The initial UI values are 1 mm per axis and 100 mm/min. They are editable
  request values, not calibration, learned bounds, or retained motion authority.
- Optional **Record Jog Observations** changes one manual jog into one typed
  `PhysicalJogObservationRequest`: an exact attested live frame/cap measurement,
  exactly one controller jog with controller-owned start/final evidence, then an
  exact strictly later frame from the same camera configuration and vision
  revision. A pre-frame failure writes nothing; a post-frame failure preserves
  the completed motion and never causes resend or inverse motion.
- SIMULATED mode cannot reach the machine action surface for jog or pen commands.
  Ordinary LIVE jog remains camera-independent when observation recording is off.
- Native Speech/AVAudioEngine input and AVSpeechSynthesizer output remain inside
  one process. Transcript delivery is newest-only. Motion Preflight accepts only
  a displayed choice for its current question; the same choice may arrive from
  speech or a button. Speech contains no ambient axis, pen, status,
  raw-controller, or arbitrary language-to-action authority.
- The signed local bundle declares camera, microphone, and speech-recognition
  purposes. Recognition is currently configured to require Apple's on-device
  path; failure is shown directly rather than silently switching to a network
  recognizer.
- The local product has one primary SwiftUI operator window and one Learning
  window backed by the same delegate-owned
  `OperatorWorkspace`. The local launcher starts with
  `ApplePersistenceIgnoreState`, and the delegate rejects AppKit
  application-state save and restore, so stale state cannot suppress the next
  operator window. Closing the last window first drains
  `OperatorWorkspace.shutdown()` for at most three seconds and then terminates
  the process, so camera, microphone, and serial resources cannot remain owned
  by an invisible windowless session and a second UI cannot compete for the
  same workspace authority.

### Affine training and online-learning boundary

- One immutable accepted snapshot owns one affine machine-to-field transform,
  one separately represented constant correction, provenance, version, and
  machine bounds.
- Up-front observations have immutable training or holdout membership. Candidate
  fitting uses only training points and reports baseline/candidate RMS and maximum
  error on both splits. Acceptance is explicit, version-increasing, and requires
  configured held-out improvement.
- The online accumulator records observations and may propose a candidate only
  at a pen-up-between-strokes or run-complete checkpoint. It has no API that can
  replace its accepted snapshot. A pen-down stroke pins one model version and
  blocks observation/proposal changes until the stroke ends.
- Affine translation and constant cap-to-tip/ink offset are unidentifiable from
  the same point pairs. The fitter therefore holds the accepted constant offset
  fixed. Later offset learning needs separately observed cap-versus-tip/ink
  evidence; this implementation does not disguise that as affine training.
- There is no spline/neural model family, replay store, continuous visual servo,
  or model update inside an irreversible ink stroke.
- The Learning window contains Motion Preflight, Armature Guidance, and Isolated
  Line sections under one persistent session, plus a live
  participant/action/observation sequence. The current-session diagnostic
  controls **Record Jog
  Observations**, selects the next immutable training/holdout split, clears
  current samples, and shows sample
  counts, last paired result, response matrix, and separate residuals under the
  label `DIAGNOSTIC — NOT MOTION AUTHORITY`.
- Physical observation provenance binds immutable attested frame bytes/hash,
  live camera/configuration/time, measured cap point/confidence/revision, exact
  controller start/final MPos and sample times, and fixed split. Public code
  cannot mint the live attestation or reconstruct physical training authority
  from decoded/scalar values.
- The current-session response learner fits only a through-origin 2x2 mapping
  from actual controller delta to camera-pixel delta. It rejects duplicate,
  mismatched, insufficient, rank-deficient, or non-finite data; holdout episodes
  never fit the candidate. It has no controller, interpreter, inverse-command,
  acceptance, promotion, persistence, replay, or recovery authority.
- This small diagnostic makes the eventual online-learning data path visible on
  this one machine without introducing a deep model. Active experiment
  selection, preference learning, and bounded policy optimization are intended
  later rungs, after drawing actions produce attributable camera/ink and human
  outcomes. They do not need a deep model, but they do need valid transitions.
- The affine drawing-model trainer, held-out acceptance decision, immutable
  version replacement, and pen-down pinning are implemented in the model layer
  and simulator. Physical jog evidence can be converted through one identified
  field registration into sealed training observations. The app can now collect
  one exact clean/anchored/post frame triplet and paired anchor/line observation.
  It does not yet own an accepted physical drawing model, fit a live drawing
  candidate, or apply one to drawing execution.

## Current C920 scene priors

The first captured set is under
`~/Library/Application Support/AdaptivePlotter/CameraSamples/startup-2026-08-05T06-50-16Z-ba4e0a9a-9bd7-4b69-a92f-4e3d16a0452e/`.
All three PNGs decode back to BGRA bytes matching the manifest SHA-256 values.
Sequence/time spacing indicates about 24 frames per second. Mean absolute
channel difference from the first image to each later sample is about 1.61 on
the 0...255 scale; no scene motion is visible.

The earlier local debug app consumed roughly 180...217% CPU because it copied
and SHA-256-hashed every 8.3 MB BGRA frame at about 24 fps. The source now
coalesces unmaterialized driver frames and materializes preview frames no more
than every 100 ms. Exact hashing remains at explicit analysis/snapshot and the
bounded preview cadence. This source change has automated coverage but still
needs a fresh live CPU observation.

The implemented connected-component detector run over the three captured PNGs
finds 724/730/732 cap pixels. Bounds are X 1081...1106 and Y 357...396 (the last
frame is two pixels shorter); centroids are (1093.87, 375.48), (1093.89, 375.62),
and (1093.83, 375.62). Component size/shape rejects the small controller light
and long green ink rather than aggregating unrelated green pixels.

The paper/work region is visually dominated by a blue-taped top edge and right
edge, with steel rulers partially occluding both and strong machine shadows on
the paper. An experimental robust fit to the inner blue edges gives:

```text
top:   y = -0.01601 x + 203.44
right: x =  0.01682 y + 1669.92
intersection: approximately (1672.9, 176.7) camera pixels
```

The implemented robust fit reports top-side RMS 1.21...1.35 pixels with 624...646
inliers and confidence about 0.79...0.81. The right side reports RMS 1.54...1.58
pixels with 410...425 inliers and confidence about 0.76. Representative endpoints
are top (652, 192.7) to (1689, 172.0), and right (1675.6, 151) to (1685.7, 734).
These remain single-camera image-space observations, not calibration or motion
bounds; rulers, shadows, magnets, and the blue hose remain distractors.

The current live scene also includes two wood rails running parallel to X above
the paper. They are intentionally visible in the action surface and reduce the
usable Y corridor. Motion Preflight must learn the relevant edges from exact
frames; the operator is not asked to convert them into MachineSpace coordinates
or enter limits before motion.

The final signed task bundle was also exercised directly on 2026-08-06. The
toolbar met the window content edge with no camera strip above it. Motion and
Camera were opened together in reserved left/right docks; the center surface
remained disjoint and showed the complete aspect-fit simulator frame. The same
running bundle completed LIVE → SIMULATED → LIVE: source labels changed, the
simulator displayed its full 640×480 canonical frame and typed layers, and the
returning C920 stream resumed advancing 1920×1080 frames without simulator
geometry crossing into the live configuration. The live and simulated pixels
therefore exercised the same resized center renderer while both docks remained
open.

On 2026-08-07, the native toolbar and SIMULATED Accepted Training presentation
were exercised in the rebuilt app. Accepted Training remained selected and
rendered rather than falling back to LIVE. The Learning panel opened Motion
Preflight in Simulator Rehearsal mode, and Pen Up visibly progressed through all
six typed steps to REHEARSED while the UI reported no microphone, controller,
physical evidence, live episode observation, or effect on motion eligibility.
That observation remains evidence for the unchecked silent path. The later
**Practice with Voice** path is covered by automated microphone/phrase/lifecycle
fixtures but has not yet been exercised with the actual microphone in the
signed app bundle.

## Not yet implemented or not yet physically verified

- Live measurement of preview and auto-analysis throughput/latency on this Mac.
- Physical validation of the question-guided boundary and Pen Cycle workflows,
  optional Voice turn-taking, on-device microphone meter, Jog Cancel timing,
  and final-MPos boundary records.
- Signed-bundle physical verification of persistent ExplorationSession
  microphone ownership, barge-in, contextual reflex routing, teaching labels,
  and measured end-to-end latency. No OpenAI or network speech dependency is
  selected.
- FaceTime-camera operator-presence observation. It is not a motion gate, and a
  second camera owner or identity/video-recording subsystem has not been added.
- Physical Armature Guidance observations and acceptance of one real clear pose.
- One physical anchor and isolated line, exact post-clear ink observation, and
  camera-space residual. Software and deterministic simulator coverage exist.
- Small multi-stroke drawing and optional affine correction.
- Portrait-to-vector input.

## Next action

The coherent software slice and deterministic simulator loop are complete. The
next action is one operator-gated physical pass through the Learning window:
Pen Up plus one cancelled boundary observation, Armature Guidance and one
human-clear pose, exact clean reference, one anchor, one fixed short isolated
line, clear return, exact post-line observation, and one spoken assessment.
Stop the affected physical episode on an alarm, asserted limit, disconnect,
unexpected actuation, or ambiguity; do not Home, unlock, reset, write settings,
resume, or automatically redraw. Cap motion, a stationary dot, controller `ok`,
and simulator output must not stand in for observed physical line success.
