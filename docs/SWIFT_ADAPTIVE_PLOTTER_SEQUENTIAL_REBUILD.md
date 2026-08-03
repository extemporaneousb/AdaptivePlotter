# AdaptivePlotter Direct Implementation Plan

## Prompt for the implementation team

Build the smallest local Swift macOS application that makes this attached
plotter draw and lets this camera observe the ink. Optimize for working hardware
and short iteration time.

Use the repository's `AGENTS.md`, repo-local AdaptivePlotter skill, and Blackdog
task workspace for retained changes. Keep Blackdog. Do not turn architecture,
validation, hardware absence, or old run evidence into global progress gates.

Use focused tests while working. Run `make check` before landing. Normal checks
must not require complete strict concurrency or warnings-as-errors;
`make strict-check` is optional diagnostic work.

## Fixed minimal contract

- One local Swift application process.
- This Mac and attached controller/camera are the only supported environment.
- No live Python, HTTP, localhost bridge, DTO mirror, compatibility lane, or
  external service.
- SwiftPM and the installed Command Line Tools are enough.
- No release/signing/notarization/sandbox/CI/support-matrix work.
- No accessibility scope.
- No archival replay, algorithm re-evaluation, content-addressed evidence,
  exports, quotas, tombstones, or old-run admission scans.
- No advanced adaptive model, spline, promotion framework, grouped-holdout
  program, bootstrap statistics, or factorial experiment plan.
- No separate motion and pen arms or phase/action authority hierarchy.
- No arbitrary G-code, automatic unlock/home/reset/settings writes, or automatic
  resend/redraw after an ambiguous command.

## Working method

For each Blackdog task:

1. Choose the smallest change that gets closer to the live
   controller-camera-draw-observe loop.
2. Implement it directly in the existing targets.
3. Run the narrowest relevant tests during iteration.
4. Try the hardware immediately when the operation is available and physically
   reasonable.
5. If hardware is unavailable, label the physical result unverified and land
   the software anyway.
6. Run `make check` and land through Blackdog.

Do not require a new phase document, evidence bundle, replay fixture, operator
study, model comparison, or generalized abstraction for an ordinary feature.

## Runtime readiness

At the start of a machine session, establish:

```text
selected controller
controller responsive and not in alarm
configured local bounds, distance limit, and conservative feed
known pen-up state before travel
camera frame available if the requested operation needs vision
```

That is one reusable session check. Recheck only after disconnect, reset/alarm,
configuration change, manual loss of position, tool change, or camera change.

Every command still receives direct bounds/feed/distance and pen-state checks.
A failure rejects that command with an actionable message and allows retry when
corrected. It does not block source work or unrelated operations.

## Work item 1 — Repeatable controller contact

Deliver:

- device refresh and explicit `/dev/cu.*` selection;
- repeatable `$I`, `$G`, `?`, `$$`, `$#` passive probes in one app launch;
- current controller state and raw error display;
- no scan of prior journal files before connecting;
- a new small journal file per probe/session.

Keep the two-second response deadline and bounded response size because they
prevent a stuck serial read. Stop the current probe on transport error, alarm,
or malformed required response. Permit immediate retry after correction.

Done when the actual controller can be probed repeatedly without restarting or
clearing historical data.

## Work item 2 — Live camera

Deliver:

- local AVFoundation camera selection;
- live preview;
- latest-frame capture with a timestamp;
- one fixed observation rectangle;
- a visible capture/interruption error.

Use a local app wrapper only if the camera API actually needs stable bundle
identity. Do not add a camera evidence archive, formal freshness framework,
multi-camera support matrix, accessibility layer, or generalized vision bus.

Done when the app shows the real camera and can capture the newest frame on
demand.

## Work item 3 — One bounded pen-up move

Deliver one direct low-speed relative move control. Before sending it, check:

- controller connected and non-alarm;
- pen known up;
- requested delta and feed within configured limits;
- projected destination within configured local bounds;
- no outstanding ambiguous command.

Show completion or the exact error in memory. Record it in the best-effort
session log when available. Do not require a distinct motion arm, model, camera,
registration, trial bundle, persistence write, or phase acceptance record.

Done when the real mechanism performs a small known pen-up move and can perform
another after returning to idle.

## Work item 4 — Pen control and clear pose

Deliver:

- explicit Pen Up and Pen Down commands using locally verified servo values;
- a conservative settle delay;
- one known pen-up clear pose and bounded path that the operator verifies in the
  live image.

No separate pen arm, pen learning model, 3D tool model, or generalized
clearance planner.

Done when the operator can raise/lower the pen and move the complete assembly to
the one viewable pose.

## Work item 5 — One observed line

Deliver the first end-to-end result:

```text
capture clean baseline
-> travel pen-up to start
-> pen down
-> draw one bounded line
-> pen up
-> move to clear pose
-> capture post frame
-> isolate the new green line
-> show intended, observed, and error
```

Use simple baseline subtraction and line/centreline fitting. An observation is
usable when the mark is visible and uniquely associated with this line. If it
is missing or unclear, show the image and error; do not automatically redraw.

Do not require covariance propagation, topology taxonomies, model innovation,
candidate promotion, a replayable run bundle, or fixed trial counts.

Done when one real command produces visible ink that the app displays against
the requested line.

## Work item 6 — Small vector drawing

Deliver:

- a hand-authored or imported polyline `DrawingProgram`;
- preview generated from the same points used for execution;
- sequential travel/draw/lift behavior;
- observation after each stroke initially;
- simple affine correction for later unexecuted strokes when useful;
- Hold and Abort controls.

Track enough current-run state to avoid automatically repeating a command whose
outcome is unknown. Do not build immutable plan-revision history, a replay
reducer, model promotion, or scheduling optimization.

Done when a small multi-stroke drawing completes and the UI shows the resulting
ink and errors.

## Work item 7 — Portrait input

Convert one captured or imported raster into polylines and send those polylines
through the same preview and execution path. The source converter gets no
machine, camera, safety, or persistence authority.

Do not add broad image tools, plugin architecture, alternate drawing engines,
or an advanced vision research program.

Done when a portrait-derived vector program draws through the already working
path.

## Best-effort session log contract

When SQLite is available, record ordered raw controller exchanges and operation
summaries for the current session. The log is diagnostic only. Never require a
database transaction before a hardware write, never build durable command
recovery, and never refuse an operation because logging failed.

After a crash or disconnect, do not resume automatically. Query the controller,
inspect physical state, and start a new explicit operation.

## Minimal UI contract

The UI needs:

- device and controller status;
- camera image;
- preview;
- current operation/stroke;
- last command outcome;
- intended/observed ink and simple error;
- Run, Hold, and Abort;
- concise actionable errors.

Do not add accessibility work, a multi-pane evidence browser, semantic timeline,
model/trial inspectors, replay mode, history navigation, storage dashboard, or
developer telemetry program.

## Model rule

Use an affine transform and optional constant tool offset. If it works, keep it.
If it does not, collect a few direct repeated measurements, identify the single
dominant systematic error, and add only the smallest correction for that error.

Advanced model ideas are outside the development plan. They may return only by
an explicit user request after the simple system demonstrably fails.

## Completion definition

The rudimentary product is complete when:

- the local app connects to the real controller and camera;
- it draws a small vector program inside configured bounds;
- it lifts and clears the tool;
- it observes and displays the actual ink;
- it shows simple drawing error and can use an affine correction for remaining
  strokes if helpful;
- Hold/Abort and concrete error recovery work;
- no Python bridge or alternate execution path exists;
- normal build/tests and Blackdog landing pass.

It does not require archival replay, accessibility, advanced modeling,
generalized observability, formal experimental sample counts, or distribution
infrastructure.
