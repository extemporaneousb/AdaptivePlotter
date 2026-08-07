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
- one controller picker that remembers the last selected device without
  connecting on selection, plus one explicit Connect action whose green status
  requires a successful blocker-free passive inspection;
- a closed typed relative-jog command with explicit local bounds, feed and
  distance limits, known pen-up state, Idle completion polling, and sticky
  ambiguous outcomes;
- AVFoundation camera discovery, explicit selection, lifecycle/error state,
  bounded preview materialization, and explicit immutable latest-frame capture;
- startup preference for the attached C920 plus three provenance-bearing PNG
  samples for offline vision analysis after camera access is granted;
- connected-component green-cap and robust top/right frame-side measurement,
  plus inferred drawing-frame and cap-anchored armature envelopes, with every
  overlay bound to the exact measured frame/configuration;
- one camera-dominant action surface shared by live BGRA frames and a
  deterministic model-mismatch simulator;
- a compact top-edge workbench bar plus independently openable and collapsible
  Motion/Controller left docks and Camera/Overlays/Learning right docks; opening
  controls reserves space and reframes rather than covers the camera surface;
- compact red/green camera-live and plotter-connected indicators at the top
  right, derived from current capture/frame and controller-inspection facts;
- distinct controller-link, motion-command, and motor-power reporting: a
  responsive USB controller is not presented as proof that motor supply power
  is present;
- bounded continuous scene analysis at a selectable 2/5/10 Hz, with one active
  and one newest pending frame plus visible delivery/materialization/analysis
  counts and latency;
- closed typed Pen Up/Pen Down actuation for this mechanism, serialized with
  probes and jogs and using the verified local `M3 S40` / `M3 S760` /
  `G4 P0.3` profile;
- a native voice-operator session using the selected Mac audio input, Apple's
  Speech framework, and `AVSpeechSynthesizer`, with explicit permission and
  listening state, newest-only transcripts, spoken current outcomes, and
  bounded automatic recovery from Apple's ordinary no-speech interval;
- a button-armed boundary-teaching interaction with only two context-bound
  speech commands: `READY` is accepted only after the operator chooses a side,
  and `STOP` is accepted only while that side's capped jog is moving. Ambient,
  wrong-context, and compound phrases have no controller meaning;
- one closed GRBL realtime Jog Cancel byte (`0x85`) for an active `$J` move.
  It has no ordinary acknowledgement: the original jog owner continues polling
  until Idle and reports the actual final MPos or ambiguity;
- boundary positions recorded only when that jog resolves as cancelled with a
  controller-reported final MPos. Reaching the command cap is normal completion,
  not evidence of a physical boundary; proximity beeps are not produced because
  there is not yet a trusted distance-to-boundary estimate;
- an optional observed-jog operation that brackets exactly one accepted motion
  with immutable live C920 frames and controller-owned start/final MPos samples;
- one SwiftUI operator window whose local launcher ignores stale AppKit window
  restoration and whose app delegate refuses future state save/restore;
  closing it drains the delegate-owned workspace, terminates the app, and
  releases camera, microphone, and serial ownership instead of leaving a hidden
  session; termination remains bounded to three seconds if a hardware intent
  does not drain;
- a current-session jog-response dataset with fixed training/holdout membership,
  a fitted 2x2 machine-delta-to-camera-delta matrix, and separate residuals;
- typed geometry, a polyline `DrawingProgram`, affine camera/field math, and one
  immutable affine-model learning path with training/holdout evaluation.

Typed Pen Up and Pen Down are implemented and physically verified over white
paper. The historical `S720` down value moved the mechanism but left no mark;
one explicit conservative adjustment to `S760` produced a green contact dot,
and an `S40` command was separately observed lifting the tip after the earlier
down attempt. The final `S40` command after the marked contact was acknowledged
without ambiguity and left the controller-commanded state Up. These are direct
operator observations because the camera cannot see the vertical pen transition.
Drawing and observed-ink extraction are not implemented. The camera source path
has captured and analyzed exact current C920 samples. The
controller-aware completion deadline passed fresh 1 mm X and Y round trips at
100 mm/min with Idle completion and exact inverse returns. A second conservative
30 mm/min check on the delivered controller-evidence path again passed both
axes: X reported +1.020/-1.020 mm and Y +0.998/-0.998 mm, ending at the exact
starting MPos. Bracketed C920 samples showed the green cap move and return. The
camera did not and cannot establish pen height from that view. A subsequent
current-session observation pass recorded eight integrated 1 mm jogs at the
actual 100 mm/min feed: four fixed training episodes and four fixed holdout
episodes, with confidence 1.000 cap measurements and exact return to controller
X0/Y0 after every inverse pair. The through-origin camera-response fit was
`[[-1.6907, 0.1585], [-0.1581, -1.2680]]` pixels/mm, with 0.164 px training RMS
(0.205 px maximum) and 0.337 px holdout RMS (0.551 px maximum). This is
inspectable current-session response evidence, not a motion transform or
calibration authority.

The current paper area has two visible wood rails parallel to X. They reduce
usable Y and are treated as physical obstacles: the operator must apply a
conservative session-local MachineSpace envelope inside their inner edges.
Camera pixels and firmware travel settings do not become motion bounds.

On this BlackBox X32, identical passive observations with motor power on and
off both report a responsive USB link, grblHAL `Idle`, MPos, no asserted pins,
and the same status fields. The controller therefore does not report motor
supply state. The UI separates `LINK last inspection responsive`, `MOTION
request eligible` or `blocked`, and `Motor power: not reported by controller`
rather than inventing a powered claim.

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
executable and prefers a valid local identity named `AdaptivePlotter Local
Development` (or `ADAPTIVEPLOTTER_CODESIGN_IDENTITY`). It reports the selected
mode and falls back to ad-hoc signing rather than pretending identity stability.
Both modes bind `Contents/Info.plist` and the identifier
`com.bullard.AdaptivePlotter`. This Mac currently has no valid code-signing
identity: importing a self-signed key succeeded, but macOS required an
interactive trust approval before use, so the incomplete key was removed. Until
that one-time approval is completed, an ad-hoc designated requirement contains
the executable CDHash and a changed executable can require a fresh camera
decision.
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
samples and a JSON manifest under the path below. **Save Snapshot** writes one
additional exact frame and manifest there on request.

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
  -> VisionPipeline       bounded newest-only feature measurement
  -> JogResponseDataset   current-session diagnostic fit only
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
- an immutable accepted affine snapshot; candidates train on an explicit split,
  must improve held-out error, and are accepted only at a pen-up checkpoint;
- no spline field, neural model, bootstrap program, continuous pen-down model
  update, or generalized adaptive-model UI.

If the affine transform draws acceptably, stop adding model complexity.

The current jog-response fit is deliberately inspectable preparation for later
online adaptation on this one machine. It records what controller motion and
camera displacement were actually observed, keeps holdout episodes separate,
and reports residuals. It cannot issue motion, accept a drawing model, persist
or replay training data, or automatically change controller behavior. More
sophisticated or reinforcement-learning models belong after the direct
controller-camera-draw-observe loop supplies trustworthy outcomes.

The voice surface follows the same rule. Speech is inert until the operator
presses a boundary-side control. In that interaction, exact `READY` advances
the armed side into one closed, capped jog, and exact `STOP` requests Jog Cancel
only while that jog is moving. Neither word is an ambient priority command, and
speech cannot request general axis motion, Pen Up, status, raw G-code, or a
safety override. The current build requires on-device Apple recognition rather
than adding a network or API dependency. Spoken prompts and a start cue provide
turn-taking; faster proximity beeps are intentionally absent until a trusted
distance-to-boundary estimate exists. A future OpenAI Realtime dialogue layer
may explain state or collect teaching input, but it must remain above this same
typed boundary and must not become a motion authority or calibration workflow.

A taught side is accepted only from `MotionOutcome.cancelled(finalPosition:)`:
the Jog Cancel must settle at Idle and supply final controller MPos. A jog that
reaches its requested command cap is completed motion, not a measured boundary.
This increment still requires direct physical validation with the attached
plotter before its prompts, cancellation timing, or recorded boundary positions
are claimed as observed hardware behavior.

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
> The controller inspection, current camera analysis, typed limits, verified
> `S760` Pen Down / `S40` Pen Up contact pair, and bounded 1 mm X/Y round trips
> in `docs/implementation/FIRST_HARDWARE_SESSION.md` are complete. The next
> physical slice is one explicit clear pose followed by one bounded isolated
> line and exact-frame ink observation; do not skip directly to multi-stroke
> drawing.
> Refuse a physical command
> only for a concrete current hazard or ambiguous outcome, show the reason, and
> permit retry as soon as it is corrected.
