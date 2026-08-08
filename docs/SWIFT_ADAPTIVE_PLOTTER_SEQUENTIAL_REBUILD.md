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
- No release, Developer ID/distribution signing, notarization, sandbox, CI, or
  support-matrix work. Keep the local TCC-attributable bundle and launcher.
- No accessibility scope.
- No archival replay, algorithm re-evaluation, content-addressed evidence,
  exports, quotas, tombstones, or old-run admission scans.
- No advanced adaptive model, spline, generalized promotion framework,
  bootstrap statistics, or factorial experiment plan. The one affine model may
  use an explicit training/holdout split and checkpoint-only immutable
  acceptance.
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
Motion Guard activated for the current controller session
known pen-up state before travel
camera frame available if the requested operation needs vision
```

That is one reusable session check. Recheck only after disconnect, reset/alarm,
configuration change, manual loss of position, tool change, or camera change.

Every command still receives direct closed-request, finite-value, controller
feed-capability, alarm/end-stop, pen-state, in-flight, and ambiguity checks. A
failure rejects that command with an actionable message and allows retry when
corrected. There is no operator-entered coordinate envelope or maximum-jog
prerequisite.

## Work item 1 — Repeatable controller contact

Deliver:

- device refresh and explicit `/dev/cu.*` selection;
- repeatable `$I`, `$G`, `?`, `$$`, `$#` passive probes in one app launch;
- current controller state and raw error display;
- no scan of prior journal files before connecting;
- one optional journal per selected-device machine session, reused across that session's probes.

Keep the two-second response deadline and bounded response size because they
prevent a stuck serial read. Stop the current probe on transport error, alarm,
or malformed required response. Permit immediate retry after correction.

Done when the actual controller can be probed repeatedly without restarting or
clearing historical data.

## Work item 2 — Live camera

Implementation status: the native source path, shared live/simulated renderer,
and automated lifecycle/provenance tests are implemented. The real C920 has
permission, advancing frames, exact newest-frame capture, and stop/restart
evidence on this Mac. The rebuilt bundle passed a manual
LIVE/SIMULATED/LIVE source-switch check on 2026-08-06. The simulator now also
renders prior-mismatch and accepted-training variants atomically and can play
the typed Motion Preflight timeline without acquiring physical authority.

Deliver:

- local AVFoundation camera selection;
- live preview;
- latest-frame capture with a timestamp;
- one fixed observation rectangle;
- a visible capture/interruption error.

The camera API did require attributable bundle identity, so the repository now
builds a local `.app` and launches that exact bundle through LaunchServices. Keep
that local TCC path. Do not turn it into distribution infrastructure or add a
camera evidence archive, multi-camera support matrix, accessibility layer, or
generalized vision bus.

Done when the app shows the real camera and can capture the newest frame on
demand.

## Work item 3 — One bounded pen-up move

Implementation status: the persistent session, typed relative-jog request,
direct safety checks, closed GRBL jog encoding, acceptance/Idle completion,
sticky ambiguity, manual widget, and automated simulation tests are implemented.
The attached mechanism has completed non-ambiguous 1 mm X and Y round trips at
100 mm/min and again at 30 mm/min, returning to the exact starting MPos.

Deliver one direct low-speed relative move control. Before sending it, check:

- controller connected and non-alarm;
- pen known up;
- requested delta finite and nonzero, with feed within controller capability;
- no asserted end-stop;
- no outstanding ambiguous command.

Show completion or the exact error in memory. Record it in the best-effort
session log when available. Do not require a distinct motion arm, model, camera,
registration, trial bundle, persistence write, or phase acceptance record.

Done when the real mechanism performs a small known pen-up move and can perform
another after returning to idle.

## Work item 4 — Pen control and clear pose

Implementation status: typed Pen Up/Pen Down, fixed local servo values, fixed
settle, serialized ownership, sticky uncertainty, direct UI, and automated tests
are implemented. The powered Pen Up command path and pen-up X/Y travel are
verified. Stationary Pen Down at the local `S760` value produced an
operator-observed green contact dot and the following `S40` command returned
the controller-commanded state Up; a separately observed clear pose remains.

Deliver:

- explicit Pen Up and Pen Down commands using locally verified servo values;
- a conservative settle delay;
- one known pen-up clear pose and bounded path that the operator verifies in the
  live image.

No separate pen arm, pen-mark learning model, 3D tool model, or generalized
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

Do not require covariance propagation, topology taxonomies, a generalized model
promotion product, a replayable run bundle, or fixed trial counts.

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
reducer, in-stroke model update, or scheduling optimization. A later-stroke
affine candidate may be accepted only from held-out improvement at a pen-up
checkpoint.

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

Use an affine transform and optional constant tool offset. The implemented
trainer fits only the affine coefficients from explicit training observations,
reports held-out error, and creates an immutable candidate. Acceptance is
explicit and checkpoint-only; one model version remains pinned through a
pen-down stroke. The online accumulator may collect observations and propose but
cannot replace the accepted snapshot.

Affine translation and constant cap-to-tip/ink offset cannot be separated from
the same point pairs. Keep the offset fixed until independent cap-versus-tip/ink
evidence exists. If the affine model works, keep it. If it does not, identify one
repeated observed-ink error and add only the smallest correction for that error.

Advanced model ideas are outside the development plan. They may return only by
an explicit user request after the simple system demonstrably fails.

## Completion definition

The rudimentary product is complete when:

- the local app connects to the real controller and camera;
- it draws a small vector program within the learned drawing frame;
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
