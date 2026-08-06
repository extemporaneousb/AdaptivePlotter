# Prototype Status

Status date: 2026-08-05
Target: this Mac and attached plotter only

## Bottom line

AdaptivePlotter is one local SwiftPM application with a camera-dominant action
surface, explicit AVFoundation camera selection, bounded preview work, exact
latest-frame capture/analysis, and a deterministic simulator rendered through
the same pixels-to-view path. One persistent native controller session owns
passive probes, bounded relative jogs, and typed pen actuation. A compact top bar
opens five independently draggable, collapsible, and hideable workbench panels;
all detailed controls begin hidden so the camera owns the primary area.

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
camera configuration identity between samples.
The rebuilt app now has camera permission and captured three current 1920x1080
C920 frames with exact manifest provenance. The production detector finds the
cap and two useful frame sides consistently in all three without deriving any
pixel-to-mm calibration. Typed Pen Up was acknowledged in the powered session
after the operator confirmed the pen was already physically clear. Pen Down was
not issued, so powered travel from a lowered pose remains unverified. Drawing
and observed-ink extraction remain unimplemented.

## Simplifications now implemented

- Passive probes may be retried in the same app launch.
- The app no longer scans old SQLite files or blocks a new session because an
  earlier journal is empty, corrupt, unfinished, or unresolved.
- The optional log records controller exchanges and probe results but is not on
  the controller command path.
- SQLite uses WAL with normal rather than full synchronous durability.
- Recorded-run reducer/replay state and its UI timeline were removed.
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
| Operator travel prior | About 250 mm X by 100 mm Y, with controller zero near physical center; not a calibration or safety limit |
| SQLite | System library available |

This environment is sufficient. No other Mac, full Xcode install, signing
identity, app distribution configuration, or CI result is required.

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
- Typed controller state, MPos, asserted X/Y limits, commanded pen state, motion
  limits, relative-jog/pen requests, refusals, completion, and ambiguity.
- Closed locale-independent `$J=G91 G21 ...` encoding; the UI cannot supply
  controller text or bytes.
- Direct pre-write checks for connection, recognized Idle state, limits, MPos,
  finite nonzero delta, feed, distance, destination bounds, known pen-up state,
  in-flight work, and sticky ambiguity.
- `ok` is acceptance only; completion is a bounded status poll ending at Idle
  with final MPos. Uncertain physical outcomes are sticky and never resent.
- Successful passive configuration parsing supplies `$110/$111` axis feed caps
  and `$120/$121` acceleration to the jog deadline model. Firmware travel
  settings are not used as workspace bounds or calibration.
- The pen wire surface is closed to `PenCommand.raise/lower`. This mechanism's
  fixed profile emits `M3 S40` or `M3 S720`, followed by `G4 P0.3`; the UI cannot
  supply controller text or servo values.
- Probe, jog, and pen requests serialize through the same owner. Pen Down needs
  fresh Idle/non-alarm status, applied bounds, fresh in-bounds MPos, and clear XY
  limit pins. Pen Up is available as the recovery direction without requiring
  MPos or limits. Any uncertain post-write result becomes sticky, sets commanded
  pen state unknown, and is never resent.
- A successful pen outcome means both controller commands were acknowledged. It
  is explicitly not camera proof that the mechanism reached the requested pose.

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
  direct session limits, actual Pen Up/Pen Down commands, MPos, controller state,
  current operation, last outcomes, and one actionable disabled reason.
- Provisional local motion inputs of 1 mm per axis, 100 mm/min, 5 mm maximum
  command distance, and X -100...100 / Y -40...40 around the observed
  session-start zero. These reflect the operator's roughly 2.5:1 travel prior
  and must still be reviewed and explicitly applied.
- Optional **Record Jog Observations** changes one manual jog into one typed
  `PhysicalJogObservationRequest`: an exact attested live frame/cap measurement,
  exactly one controller jog with controller-owned start/final evidence, then an
  exact strictly later frame from the same camera configuration and vision
  revision. A pre-frame failure writes nothing; a post-frame failure preserves
  the completed motion and never causes resend or inverse motion.
- SIMULATED mode cannot reach the machine action surface for jog or pen commands.
  Ordinary LIVE jog remains camera-independent when observation recording is off.

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
- The Learning panel is a direct current-session diagnostic, not a sequence or
  readiness flow. It controls **Record Jog Observations**, selects the next
  immutable training/holdout split, clears current samples, and shows sample
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
  this one machine without introducing a deep model. Reinforcement learning or
  other adaptive policies remain deferred until drawing actions have trustworthy
  camera/ink outcomes and an explicit safe policy boundary.

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

## Not yet implemented

- Live plotter-camera source-switch verification on the final rebuilt bundle;
  advancing C920 frames and stop/restart recovery were observed locally.
- Live measurement of preview and auto-analysis throughput/latency on this Mac.
- Physical Pen Down followed by Pen Up over replaceable paper; the powered
  Pen Up command path is acknowledged, but the pen began physically up.
- One fixed camera observation region and clear tool pose.
- Isolated line drawing, ink detection, and simple residual display.
- Small multi-stroke drawing and optional affine correction.
- Portrait-to-vector input.

## Next action

The fresh passive probe, typed limits, Pen Up command path, and 1 mm X/Y round
trips in [First Hardware Session](FIRST_HARDWARE_SESSION.md) are complete. The
next machine-affecting step requires explicit operator authorization: stationary
Pen Down followed once by Pen Up over replaceable paper while observing the
mechanism. Stop on any alarm, asserted limit, disconnect, unexpected actuation,
or ambiguity; do not Home, unlock, reset, write settings, or resume. After that
pair and live camera checks are clean, the next software/physical slice is one
bounded isolated-line operation followed by tool clear, exact-frame ink
observation, and residual display. Cap motion and controller `ok` must not
stand in for observed ink.
