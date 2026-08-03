# Prototype Status

Status date: 2026-08-02  
Target: this Mac and attached plotter only

## Bottom line

AdaptivePlotter builds as one local SwiftPM application. It can discover serial
devices and issue the fixed passive controller query sequence through the
native parser. It has typed vector geometry, an affine transform, a static
simulated preview, and a best-effort current-session diagnostic log.

It does not yet move the machine, control the pen, capture the live camera, or
draw and observe ink. Those are the immediate work items.

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
| Camera inventory | FaceTime HD Camera (Built-in), not yet opened by the app |
| Serial inventory at last check | Bluetooth callout devices only; controller not connected |
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

### Current-session diagnostics

- One SQLite file per passive run.
- Ordered diagnostic events.
- Ordered raw controller exchanges and probe summaries when logging is
  available.
- Probe execution continues if logging cannot be created or written.
- No old-run admission scan, artifact store, export subsystem, quota, retention
  policy, tombstone system, or replay product.

### Geometry and app shell

- Typed `FieldSpace`, `MachineSpace`, `CameraPixelSpace`, and related values.
- Polyline `DrawingProgram` and affine forward/inverse transform.
- Finite-value and coordinate-bound validation.
- Static simulated logical/predicted/observed overlay for UI development.
- A minimal controller pane showing selection, probe result, optional log path, and
  actionable errors.

The candidate-promotion, checkpoint-resolution, execution-authority, replay,
and armature-envelope domain scaffolds were deleted. The retained drawing model
is one affine transform, an optional constant correction, and machine bounds.

## Not yet implemented

- Connection to the actual controller.
- Live AVFoundation camera preview and latest-frame capture.
- Configured local motion bounds and one bounded pen-up move.
- Pen Up/Pen Down commands verified on this mechanism.
- One fixed camera observation region and clear tool pose.
- Isolated line drawing, ink detection, and simple residual display.
- Small multi-stroke drawing and optional affine correction.
- Portrait-to-vector input.

## Next action

Connect the controller and run the passive probe repeatedly using
[First Hardware Session](FIRST_HARDWARE_SESSION.md). After that works, implement
one bounded low-speed pen-up relative move. Do not stop for camera/model/replay
work before trying that move; apply only the direct controller, bounds, feed,
pen-up, and ambiguous-command checks described in the implementation plan.
