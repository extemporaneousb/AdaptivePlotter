# Prototype Status

Status date: 2026-08-04
Target: this Mac and attached plotter only

## Bottom line

AdaptivePlotter is one local SwiftPM application with a camera-first action
surface, explicit AVFoundation camera selection, immutable latest-frame capture,
a simulator rendered through the same pixels-to-view path, one persistent native
controller session, and a closed bounded relative-jog operation. The action
surface and motion widget show direct camera/controller state, MPos, operation,
outcome, and one actionable blocker.

The live camera and bounded jog paths are implemented and covered by automated
tests. The controller path now has physical evidence: the attached controller
was probed and completed bounded X and Y jogs. A later 10 mm X jog requested at
900 mm/min became correctly sticky-ambiguous because the running build's
completion deadline expired while the controller still reported `Jog`. The
source now derives a conservative trapezoidal/triangular deadline from parsed
per-axis feed caps and acceleration, but that correction still needs a fresh
physical session before further motion.
The rebuilt app now has camera permission and captured three current 1920x1080
C920 frames with exact manifest provenance. The scene is stable and supplies
useful cap and frame-side priors without supplying pixel-to-mm calibration.
Pen actuation, drawing, and observed-ink residuals remain unimplemented.

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
- Typed controller state, MPos, asserted X/Y limits, pen state, motion limits,
  relative-jog request, refusal, completion, and ambiguity.
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
  newest-frame-only stream of owned immutable BGRA `StampedFrame` values.
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
- Deterministic simulated logical/predicted/observed/residual geometry through a
  known field-to-camera transform and the same renderer as live pixels.
- A fully wired X−/X+/Y−/Y+ widget with independent X/Y step values, feed,
  direct session limits, explicit pen-up confirmation, MPos, controller state,
  current operation, last outcome, and one actionable disabled reason.
- Provisional local motion inputs of 1 mm per axis, 100 mm/min, 5 mm maximum
  command distance, and X -100...100 / Y -40...40 around the observed
  session-start zero. These reflect the operator's roughly 2.5:1 travel prior
  and must still be reviewed and explicitly applied.

The candidate-promotion, checkpoint-resolution, execution-authority, replay,
and armature-envelope domain scaffolds were deleted. The retained drawing model
is one affine transform, an optional constant correction, and machine bounds.

## Current C920 scene priors

The first captured set is under
`~/Library/Application Support/AdaptivePlotter/CameraSamples/startup-2026-08-05T06-50-16Z-ba4e0a9a-9bd7-4b69-a92f-4e3d16a0452e/`.
All three PNGs decode back to BGRA bytes matching the manifest SHA-256 values.
Sequence/time spacing indicates about 24 frames per second. Mean absolute
channel difference from the first image to each later sample is about 1.61 on
the 0...255 scale; no scene motion is visible.

The local debug app consumed roughly 180...217% CPU during continuous 1080p
capture. The newest-frame stream bounds queued frames but currently still
copies and SHA-256-hashes every 8.3 MB BGRA frame before older frames can be
dropped, then performs presentation conversion. At the observed roughly 24 fps,
the raw input alone is about 200 MB/s. Preserve exact immutable measurement
frames, but move full materialization/hashing behind a bounded preview cadence
or explicit vision snapshot request before continuous supervision.

A broad experimental green mask finds one dominant connected component at
image bounds X 1081...1106, Y 357...396. Its area is 660...671 pixels and its
centroid remains within 0.06 pixel across the three samples, near
X 1094.05, Y 375.76. A second green component at the controller is only
19...21 pixels. The existing whole-region green aggregation would merge those
objects into one false large bounding box; cap detection must use connected
components before centroid or bounds reporting.

The paper/work region is visually dominated by a blue-taped top edge and right
edge, with steel rulers partially occluding both and strong machine shadows on
the paper. An experimental robust fit to the inner blue edges gives:

```text
top:   y = -0.01601 x + 203.44
right: x =  0.01682 y + 1669.92
intersection: approximately (1672.9, 176.7) camera pixels
```

Those edges are nearly orthogonal in this view and are better initial line
priors than ruler markings. The equations are observations from this one fixed
camera scene, not accepted thresholds, calibration, or motion bounds. Use
gradient/line support plus robust fitting and temporal persistence; treat ruler
ticks, text, magnets, shadows, and the blue hose as distractors.

## Not yet implemented

- Fresh physical verification of the controller-aware jog deadline after the
  earlier session became sticky-ambiguous.
- Live plotter-camera stop/restart and source-switch verification.
- Connected-component cap measurement and robust frame-side measurement in
  `VisionWorker`, with exact frame/configuration provenance and overlays.
- Bounded live-frame materialization so continuous preview does not copy, hash,
  and convert every 1080p camera frame when only the newest presentation frame
  or one requested vision frame is needed.
- Pen Up/Pen Down commands verified on this mechanism.
- One fixed camera observation region and clear tool pose.
- Isolated line drawing, ink detection, and simple residual display.
- Small multi-stroke drawing and optional affine correction.
- Portrait-to-vector input.

## Next action

Implement the two smallest current-scene measurements: a connected-component
green-cap detector and robust top/right frame-side fits, both tied to one exact
frame and camera configuration. Do not OCR the rulers or infer pixel-to-mm
scale. Redesign the operator surface around the full camera image and a compact
jog overlay while preserving the current typed owners. Then begin a fresh
controller session and re-verify the corrected controller-aware deadline with
only the smallest low-feed round trip in
[First Hardware Session](FIRST_HARDWARE_SESSION.md). Stop on any alarm, asserted
limit, disconnect, unexpected motion, or ambiguity; do not Home, unlock, reset,
write settings, resume, or lower the pen.
