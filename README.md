# AdaptivePlotter

AdaptivePlotter is a local Swift macOS application for this operator Mac and
its attached plotter. There is no distribution, release, signing, notarization,
sandbox, CI, support-matrix, or second-computer requirement.

The goal is direct:

```text
connect controller and camera
-> load or create a vector path
-> preview it
-> draw it within fixed local bounds
-> lift and move the tool clear
-> look at the actual ink
-> show the result and simple position error
```

Getting that loop working takes precedence over infrastructure, generalized
architecture, exhaustive evidence systems, advanced modeling, and polished UI.

## Current state

The repository contains one SwiftPM application with:

- native `/dev/cu.*` discovery and GRBL/grblHAL parsing;
- the fixed passive query sequence `$I`, `$G`, `?`, `$$`, `$#`;
- one persistent selected-device controller session with repeatable passive
  probes and best-effort SQLite diagnostics;
- a closed typed relative-jog command with explicit local bounds, feed and
  distance limits, known pen-up state, Idle completion polling, and sticky
  ambiguous outcomes;
- AVFoundation camera discovery, explicit selection, lifecycle/error state,
  and immutable latest-frame capture;
- startup preference for the attached C920 plus three provenance-bearing PNG
  samples for offline vision analysis after camera access is granted;
- one dominant action surface shared by live BGRA frames and a deterministic
  simulator, with exact frame/configuration overlay matching;
- typed geometry, a polyline `DrawingProgram`, and affine camera/field math.

Pen actuation, drawing, and observed-ink residuals are not implemented. The
camera source path has captured exact current C920 samples. The controller has
completed bounded X and Y jogs; its newly controller-aware completion deadline
still needs a fresh physical recheck.

Old or corrupt journal files do not block a new session. The app does not have
an archival replay product, artifact store, retention policy, accessibility
program, advanced model family, or release pipeline.

## Build and run

The installed Apple Command Line Tools and SwiftPM are the supported local
toolchain:

```bash
make build
make test
make check
make app
make run-app
```

`make app` assembles `.build/AdaptivePlotter.app` around the current SwiftPM
executable, then applies a local ad-hoc signature whose designated identifier is
`com.bullard.AdaptivePlotter` and whose seal binds `Contents/Info.plist`. This
gives the request the right app name and camera-usage description; it is not a
stable TCC identity across rebuilds. An ad-hoc designated requirement contains
the executable CDHash, and this Mac currently has no valid code-signing
identity, so a changed executable can require a fresh camera decision.
`make run-app` compiles the small checked-in AppKit launcher and asks
LaunchServices to start a new instance of that exact bundle. The launcher waits
for the launch result, reports an error if activation fails, and exits without
owning the application lifetime. It does not invoke `/usr/bin/open` or the
macOS `open` command. LaunchServices is required here so TCC names
AdaptivePlotter rather than the terminal or Codex process that ran `make`. Use
the bundle for physical camera work and expect to re-allow camera access after
a rebuild until a stable local signing identity exists. The raw
`.build/debug/AdaptivePlotter` executable remains useful for non-TCC
command-line diagnosis but is not the physical-camera launch path.

On the first successful live-camera start, the app writes three startup scene
samples and a JSON manifest under:

```text
~/Library/Application Support/AdaptivePlotter/CameraSamples/
```

Those files are vision-development inputs, not calibration or drawing evidence.

Normal development uses Swift 5 language compatibility mode with the installed
Swift 6 compiler. Strict concurrency and warnings-as-errors are optional:

```bash
make strict-check
```

Do not turn `strict-check` into a prerequisite for ordinary development or
landing unless a concrete concurrency problem makes it relevant.

Fixture provenance can still be checked when useful:

```bash
Scripts/validate_evidence_manifest.sh
Scripts/validate_evidence_manifest.sh --verify-source
```

The second command requires the legacy source archive at its recorded path or
`LEGACY_PLOTTER_ROOT`.

## Development contract

Use the repo-local AdaptivePlotter skill and Blackdog for retained changes.
Blackdog remains the project workflow.

Outside that workflow, development is deliberately lightweight:

- implement the highest-value working capability next;
- use focused tests while iterating and `make check` before landing;
- hardware absence never blocks source work, simulation, UI work, or landing;
- no phase document, evidence package, or historical replay is required for a
  routine implementation change;
- do not add an abstraction, framework, model family, or persistence feature
  until the working local app needs it.

Physical operations use direct runtime checks, not a hierarchy of gates or
separate motion/pen arms. At session start, establish the selected controller,
current controller state, configured bounds/feed, known pen-up state, and—when
drawing needs observation—a working camera. Recheck only a fact invalidated by
a disconnect, alarm/reset, configuration change, or camera change.

A physical command may be refused only for a concrete current reason such as:

- no unique selected serial device;
- controller alarm, limit, disconnect, or outstanding ambiguous command;
- command outside configured distance, feed, or workspace bounds;
- unknown pen state for a move that requires pen up;
- missing current camera frame for an operation that actually needs vision.

That refusal stops the affected run or command, not development and not
unrelated hardware work. Show the reason and allow an immediate retry after it
is corrected.

## Minimal architecture

Keep one native process and direct Swift calls:

```text
PlotterApp
  -> RunInterpreter       current operation and visible status
  -> MachineController    serial bytes and controller state
  -> CameraCapture        latest local frame
  -> vision functions     ink/feature measurement
  -> RunLedger            optional current-session diagnostics
```

The session log records useful controller exchanges when storage is available.
It is best effort: logging failure cannot prevent a controller operation. The
in-memory controller result is the source for the current operation. Do not add
pre-write database commits, command-lifecycle recovery, content-addressed blobs,
immutable run bundles, replay reducers, algorithm re-evaluation, quotas,
tombstones, export workflows, or old-run admission scans.

Use the simplest geometry that works:

- typed `FieldSpace`, `MachineSpace`, and `CameraPixelSpace` values;
- polylines first;
- one affine machine-to-field transform plus a constant tool offset if needed;
- direct forward check of generated machine points;
- no spline field, neural model, promotion framework, bootstrap statistics,
  factorial trial program, or generalized adaptive-model UI.

If the affine transform draws acceptably, stop adding model complexity.

## What the UI must show

The rudimentary application needs only:

- selected serial device and connection/controller state;
- latest camera image when camera support exists;
- logical path preview and, after drawing, observed ink/error overlay;
- current operation or stroke;
- last command outcome;
- a concise actionable error;
- Run, Hold, and Abort controls once those operations exist.

Accessibility work, a multi-pane evidence workspace, semantic history timeline,
model comparison UI, archival replay, storage management, and operator studies
are out of scope.

## Immediate build order

1. Run the passive controller probe repeatedly on the actual controller.
2. Verify the live camera preview and latest-frame capture on the plotter camera.
3. Verify one bounded low-speed pen-up relative move and inverse return using
   explicitly configured local bounds.
4. Verify pen up/down with one direct local control.
5. Draw one isolated line, clear the tool, observe the ink, and show error.
6. Draw a small multi-stroke vector program.
7. Add portrait-to-vector input only after the same drawing path works.

These are priorities, not repository gates. Software for a later item may land
early when it directly shortens the path to a working app.

## Legacy boundary

`/Users/bullard/Projects/Plotter` is forensic reference only. Do not copy its
Python bridge, localhost protocol, DTOs, workflow wizard, compatibility paths,
Blackdog state, virtual environment, or live source layout.

The reviewed source documents originally came from legacy commit
`4f5478e0230cb8028b13cf3ebf0e83b631bffe1c`. Current documents in this
repository intentionally supersede their earlier process, replay, accessibility,
and advanced-model requirements.

## Next-agent directive

> Continue AdaptivePlotter through the normal Blackdog workflow. Optimize for a
> working local controller-camera-draw-observe loop. Use the current Command
> Line Tools and SwiftPM. Do not add release infrastructure, accessibility
> scope, archival replay, advanced models, separate arms, or phase-wide gates.
> First verify the implemented live camera and bounded relative-jog paths on the
> attached hardware. Refuse a physical command only for a concrete current
> hazard or ambiguous command outcome, show the reason, and permit retry as soon
> as it is corrected.
