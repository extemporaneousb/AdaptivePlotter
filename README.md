# AdaptivePlotter

AdaptivePlotter is a native macOS Swift application for one attached plotter.
It closes a short controller-camera-draw-observe loop while keeping controller
authority, captured pixels, vision inference, human observation, and observed
ink distinct.

The product is deliberately local:

- one signed application bundle and one foreground process;
- one controller owner and one camera owner;
- one camera-first operator window;
- typed, bounded commands rather than arbitrary controller text;
- exact frame and camera-configuration provenance;
- no automatic resend, resume, or redraw after an uncertain physical outcome.
- one revisioned 4 mm target traced forward and reverse, followed by
  single-flight, cancellable, target-ROI-local foreground Vision.

## Operator journey

The persistent **Learning Path** is an ergonomic organization, not a motion
authority ladder:

1. **Connect**
2. **Enable Motion**
3. **Human-Guided Discovery**
   - **3.1 Pen Interaction**
   - **3.2 Paired Boundary Discovery and Centering**
   - **3.3 Register Target Pose and Camera Geometry**
   - **3.4 Discover and Accept Clear View**
   - **3.5 Confirm Blank Target Baseline**
   - **3.6 Return to Registered Target Pose**
   - **3.7 Draw Visibility Target**
   - **3.8 Return and Observe Existing Target**
   - **3.9 Accept Visibility Registration**
4. **Observed Drawing Trials**
   - choose a target-anchored isolated line;
   - capture its baseline;
   - move and draw under one operation owner;
   - return to the accepted clear pose;
   - observe new ink and compare geometry.
5. **Adaptive Drawing** — Future

Connect and Enable Motion are direct current-session prerequisites. Ordinary
manual jogs do not depend on Learning Path completion. Selecting a row changes
presentation only; it cannot change runtime current state, admit motion, or
alter accepted evidence.

The exact Boundary, visibility-target, clear-view, and drawing-trial sequence is
defined once in
[Discovery and Observed-Trial Protocol](docs/DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md).

## Mechanical authority

`MachineController` owns serial state, direct safety checks, command
serialization, settlement, and sticky ambiguity. `RunInterpreter` owns the one
active logical operation. The UI issues typed intents but cannot weaken either
owner.

Applicable motion requires the direct facts consumed by that request, including
a selected responsive session, current Motion authorization, recognized
controller state, compatible pins, known MPos where needed, correct pen state,
one-operation ownership, and no sticky ambiguity.

The application does not home, unlock, clear alarms, reset the controller, write
firmware settings, accept entered workspace bounds, or use learning stage or
model confidence as manual-motion authority.

Controller `ok` means acceptance, not completion. Motion completes only after
fresh Idle and final MPos. Unknown post-write state is sticky and is never
automatically resent.

## Stop and evidence

The active exercise owns one contextual **Stop**. Manual motion owns **Stop
Manual Jog** in the Motion region. Repeated Stop cannot emit repeated semantic
results or cancellation bytes. While physical movement owns an exercise, its
capability-bound Stop is the only movement-ending action shown; Cancel becomes
available only after movement settles.

Foreground visibility observation publishes its owner before capture. While it
is active, controller, motion, pen, camera, source, analysis, and learning
mutations are refused; capability-bound **Cancel Vision** is the sole operation
control. Read-only Learning Path review and the ROI/full-frame display toggle
remain inert.

Boundary Stop records the typed operator intent, closes renewal, emits one GRBL
Jog Cancel, awaits the original owner through final Idle/MPos, and atomically
commits the selected side attempt and aggregate without Camera or Vision
evidence. Typed operator direction—not a detected camera edge—identifies the
side. Strictly newer frames may advise later renewal segments, but cannot
identify or veto the machine-space Boundary result.

LIVE camera start, restart, and source selection never start an unowned analysis
loop. Boundary renewal uses only its finite explicit inspections. Supervised
Pen-Up Learning Path travel may admit newest-only scene analysis at 2 Hz while
the movement owner is active; it stops and discards pending work when that owner
settles. A forced opposite direction is displayed as required, noninteractive
content rather than as a disabled choice.

Every expensive Vision computation owns one immutable frame. While it runs,
`CameraCapture` keeps AVFoundation alive and retains the newest raw buffer, but
pauses preview materialization/publication so frame hashing and SwiftUI updates
cannot compete with analysis. Preview resumes from at most one newest buffered
frame after settlement. Explicit inspection is finite and motion-scoped
analysis reserves a 2 Hz post-completion recovery interval; neither can survive
its owning operation.

After four sides, **Move to Estimated Center** accepts a controller-reported
final MPos within 0.05 mm of the derived target. A stopped or out-of-tolerance
move preserves all four accepted side aggregates and exposes **Retry Center
Arrival**, which requests only the remaining delta; it never restarts Boundary
Discovery.

Every production controller-pose comparison uses one quantization-aware
settlement policy: fresh attributable controller MPos and Euclidean residual at
most 0.05 mm. Here, **exact** means exact controller provenance under that
policy; it does not mean mathematically zero residual from an unrepresentable
stepper position.

At 3.3, one public **Capture Target Pose and Build Geometry Proposal** action
captures the exact target pose and frame, runs the bounded three-sample Pen Up
camera calibration when needed, returns under the same settlement policy, and
stages the proposal. There is no preceding generic Start or separate public
capture/build ceremony. The action never accepts geometry. The operator still
explicitly accepts or rejects the target pose, camera fit, and ROI after review.

Accepted LIVE machine-space Boundary artifacts are durably checkpointed by
atomic file replacement after each accepted commit. Relaunch loads the file as
quarantined evidence. Fresh passive `$I`, `$G`, `?`, `$$`, and `$#` evidence
must match the recorded controller context, and MPos must be within 0.05 mm,
before accepted sides, center, local frame, or center arrival become current.
The checkpoint contains no active workflow, Motion authorization, operation
owner, live Stop capability, pending command, or replay instruction.

Evidence claims remain separate:

- command acceptance proves controller acceptance only;
- Idle and final MPos prove controller-side settlement;
- a frame proves captured pixels with recorded provenance;
- vision geometry is an inference from those pixels;
- a button records a human observation;
- only observed ink proves that a mark exists;
- simulator output is software evidence and never physical evidence.

Redo replaces a current accepted result only after the replacement commits.
Failure preserves the old accepted result and its dependents. Record Another
Attempt retains compatible samples and recomputes the typed aggregate. Exact
frames and controller events remain individual provenance.

## Workbench

One singleton window contains a resizable Learning Path navigator, an
always-mounted camera/action surface, selected exercise detail, a Motion region,
and optional Utilities. Hiding a pane is presentation-only. A pane that owns the
only active Stop cannot be hidden until its operation settles.

The toolbar owns global controller selection, Connect/Disconnect, Enable Motion,
and compact status. Exercise Start, choices, Cancel, Stop, Restart, Redo, and
Record Another Attempt remain with the selected exercise. Buttons are the
authoritative input surface; speech is output-only advisory guidance.

Selecting an older Learning Path row remains review-only. Its Reset Learning
section offers **Reset From This Step…**, which shows the exact later steps that
will also be cleared and uses one ordinary Reset button—no phrase entry.
**Reset All Learning…** uses the same compact summary and returns the current LIVE
or SIMULATED learning source to Pen Interaction without disconnecting the
controller or changing Enable Motion. A LIVE reset that reaches Boundary learning
also removes the saved accepted-Boundary checkpoint. Neither action erases marks
on the paper; contaminated target areas remain unusable until the operator chooses
a new area or records paper replacement.

## Build, test, and launch

Requirements:

- macOS 14 or later;
- Swift 6.1.2 or later;
- Xcode Command Line Tools;
- a signed-bundle launch for camera or controller work.

Common commands:

```bash
make help
make build
make quick-test
make journey-test
make test
make check
make strict-check
make app
make validate-app
make run-app
```

Use `make quick-test` during ordinary edits. It keeps the unit and component
suite while excluding the retained end-to-end simulated Learning Path routes.
Use `make journey-test` when changing those routes, and `make test` for the
complete suite. `make check` and `make strict-check` always run the complete
suite; the strict gate is intended once before landing, not after every edit.

`make run-app` constructs the signed bundle and uses the single-instance
launcher. Do not run the raw SwiftPM executable for camera, microphone, or
serial work. The launcher activates the exact existing bundle when possible and
refuses wrong-path or competing raw processes without terminating them.

## Authoritative documents

- [Product Contract](docs/PRODUCT_CONTRACT.md) — product boundary, authority,
  evidence, safety, and valid model-learning direction.
- [Architecture](docs/SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md) — package and
  runtime ownership boundaries.
- [Discovery and Observed-Trial Protocol](docs/DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md)
  — exact current operator/runtime protocol.
- [Roadmap](docs/ROADMAP.md) — unfinished work only.
- [Current Evidence](docs/CURRENT_EVIDENCE.md) — current automated, environment,
  and attended physical evidence.
- [Attended Hardware Runbook](docs/ATTENDED_HARDWARE_RUNBOOK.md) — supported
  physical verification procedure.

Git history and Blackdog replay artifacts retain implementation history and
execution prompts. They are not duplicated as current product documentation.

## Development contract

Follow `AGENTS.md`, `.codex/skills/adaptiveplotter/SKILL.md`, and
`blackdog.toml`. Normal implementation starts with repo-local Blackdog and lands
through its recorded target branch. Keep automated, simulator, controller,
camera, human, and observed-ink evidence explicitly classified.
