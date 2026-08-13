# AdaptivePlotter

AdaptivePlotter is a native macOS Swift application for one local plotter and
one camera. It keeps controller settlement, exact camera pixels, Vision
inference, operator assertions, and observed ink as separate evidence classes.

The application is deliberately local:

- one signed application bundle and one foreground process;
- one controller owner and one camera owner;
- one camera-first workbench;
- typed, bounded controller requests rather than arbitrary controller text;
- exact-frame and semantic optical provenance;
- no automatic resend, resume, retap, or redraw after an uncertain physical
  outcome.

## Operator journey

The persistent **Learning Path** is an ergonomic navigator, not a motion
authorization ladder:

1. **Connect**
2. **Enable Motion**
3. **Human-Guided Discovery**
   - **3.1 Pen Interaction**
   - **3.2 Paired Boundary Discovery and Centering**
   - **3.3 Calibrate Camera and Visible Cap**
   - **3.4 Calibrate Pen Contact from Sparse Marks**
4. **Observed Drawing Trials**
   - **4.1 Choose Isolated Line Plan**
   - **4.2 Capture Local Pre-Line Baseline**
   - **4.3 Move to Line Start**
   - **4.4 Draw Isolated Line**
   - **4.5 Reveal and Observe New Ink**
   - **4.6 Compare Intended and Observed Geometry**
5. **Adaptive Drawing** — Future

Connect and Enable Motion expose direct current-session facts. Selecting a row
changes presentation only; it cannot admit motion, change runtime current state,
or promote evidence.

Presentation zoom is available after 3.2. Zoom, pan, and **Fit Learned Plotter
Bounds** change only the view transform. They never change camera-pixel evidence,
frame identity, or calibration authority.

The exact operating sequence is defined by
[Discovery and Observed-Trial Protocol](docs/DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md).

## Mechanical authority

`MachineController` owns serial state, direct admission checks, command
serialization, settlement, and sticky ambiguity. `RunInterpreter` owns the one
active logical operation. The UI issues typed intent but cannot weaken either
owner.

Applicable motion requires the direct facts consumed by the request: a selected
responsive session, current Motion authorization, recognized controller state,
compatible pins and context, current MPos when required, correct pen state,
single-operation ownership, and no sticky ambiguity.

The application does not home, unlock, clear alarms, reset the controller,
write firmware settings, or treat entered bounds, a Learning Path stage, or
model confidence as motion authority.

Controller `ok` proves acceptance only. Motion completes after fresh Idle and
final MPos. Every production pose comparison uses attributable controller
evidence and the shared 0.05 mm Euclidean settlement policy. Unknown post-write
state is sticky and is never automatically resent.

## Sparse tip calibration

Stage 3.3 derives a bounded rectangle from the accepted Boundary envelope with
a 10 mm safety inset. Until paper coverage and visibility are separately known,
the bootstrap rectangle is reduced symmetrically around its center. It must
retain at least 10 mm usable span on each axis.

Five Pen-Up cap samples use the normalized cross `C`, `X−`, `Y+`, `X+`, `Y−`.
The first three fit an affine machine-to-visible-cap map; the last two are
independent holdouts. Both holdouts must pass before a weighted all-five refit
can be explicitly accepted as `MachineCameraRegistration`. The visible cap
landmark is not the hidden paper-contact point.

Stage 3.4 uses the same ordered cross. At each position the app:

1. settles Pen Up at the intended MPos;
2. captures an exact pre-mark frame and revalidates the cap map;
3. moves Pen Up to the circle start, commands the complete configured lower
   operation (`M3 S760`, then the configured 0.3 s settle), and accepts only a
   settled Down outcome;
4. draws one closed 16-chord circle of 2 mm radius at no more than 100 mm/min,
   raises once, then moves Pen Up to the learned safe X+ limit and as close to
   machine Y=0 as the 10 mm Boundary inset permits;
5. settles, captures a newer exact frame, and revalidates the cap map;
6. freezes that exact frame, opens a stronger presentation-only focus around
   the pre-mark cap anchor, and asks the operator to click the circle center;
7. allows re-clicking only on the same frame, with no motion or ink action.

The protocol has no independent pressure control and does not overdrive the
actuator beyond its fixed local profile. A complete commanded lower plus its
settlement is controller evidence; only attended observation can prove that the
physical pen reached the paper.

The predicted tip point is hidden until the click is made. Before accepted
authority exists, the UI says **Tip not calibrated**. After a click, the UI
shows the selected point and uncertainty, model prediction, and residual.

The first three accepted marks fit candidates; `X+` and `Y−` remain holdouts.
The smallest passing model wins: a constant camera-pixel correction on the cap
map is tried first, and a direct affine tip map is considered only after
coherent failure at both holdouts. Both holdouts must pass. The selected model
is refit on all five observations and becomes current only after explicit
**Accept Tip Calibration**.

An uncertain circle chord, Pen Down/Up outcome, or motion outcome blacklists
that circle center/radius on the current paper and stops the workflow. Possible ink never causes automatic
retry, redraw, resend, or continuation.

## Tip authority and persistence

`ToolContactObservation` is immutable evidence. It binds intended and settled
machine poses, controller context, the 2 mm-radius/16-chord/100 mm/min-capped mark geometry, the
fixed pen-actuation profile revision, Pen Down/Up outcomes, tool and paper
identities, exact pre/post frames, cap-map checks, asserted camera point,
pointing uncertainty, presentation-transform revision, disposition, and
consumed algorithm/artifact revisions.

`TipCameraRegistration` maps machine coordinates directly to paper-contact
pixels. It retains the chosen model form, affine transform, uncertainty,
applicability rectangle, sealed holdouts, all five observation identities,
semantic optical/machine/tool/paper identities, and accepted revision. A
diagnostic cap-to-tip pixel difference at one pose is not a durable
camera-independent tool vector.

The machine-only checkpoint remains separate. `AcceptedTipCalibrationCheckpoint`
loads quarantined and cannot restore authority without current semantic
identity plus fresh controller/cap evidence. A paper-plane change requires
one new accepted circle-center observation; an unchanged paper/capture
restart requires a fresh cap frame and no new mark. Both routes derive a new
accepted revision and retain their revalidation evidence. Known pixel
transforms and known machine-coordinate
rebases may derive rebased authority with propagated uncertainty; unknown
optical, geometry, coordinate, tool, contact-profile, or LIVE/SIMULATED changes
invalidate or quarantine it as defined by the Product Contract.

A frame hash and metadata prove provenance only. Durable reprocessing requires
a content-addressed locator for archived bytes.

## Stage 4

Observed Drawing Trials require accepted Boundary evidence and the exact current
`TipCameraRegistration` revision. Stage 4 chooses a local 5 mm line that clears
every retained 2 mm calibration circle; it blocks if the accepted domain is too
crowded rather than letting old ink split the new observation. It projects that
line through the registration and owns its own:

- local pre-line baseline and Pen-Up reveal MPos;
- line-start travel and one closed drawing owner;
- Pen-Up return to the same reveal pose;
- strictly newer post-line frame;
- generic black/new-ink observation and residual.

No Stage 3 scene artifact is reused as a Stage 4 baseline or observation pose.
An attributable observed line may become future refinement evidence, but it
cannot silently promote a model. Ambiguous motion or possible ink never causes
an automatic redraw.

## Workbench and evidence

One singleton window contains the Learning Path, always-mounted camera/action
surface, selected exercise, Motion region, and optional Video Settings. The four
state-dependent Show/Hide controls and matching panel close controls share one
grammar. A panel that owns the only active Stop cannot be hidden until its
operation settles.

Video Settings combines camera selection, adjacent Refresh, scene-analysis
frames per second, viewport zoom/drag/region lock, and a three-column overlay
grid without tabs. Selecting any scene-derived overlay directly keeps bounded
newest-only analysis running; there is no separate Analyze/Resume control.
During a computation, raw camera capture continues while preview publication is
held and the visible frame is dimmed. Locking the viewport admits only that
camera-pixel subregion to generic scene-analysis scans without cropping or
rewriting the exact stamped frame.

The toolbar owns controller selection, Connect/Disconnect, Enable Motion, and
compact status. Exercise Start, choices, Cancel, Stop, Restart, Redo, and Record
Another Attempt stay with the exercise. Buttons are authoritative input; speech
is advisory output only.

Evidence claims remain separate:

- build/test output is automated software evidence;
- simulator output is deterministic nonphysical evidence;
- controller acceptance and Idle/MPos are controller evidence;
- a frame is exact captured-pixel evidence;
- Vision geometry is an inference;
- a click is an explicit operator assertion;
- only observed physical ink proves a physical mark.

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

`make quick-test` runs unit and component tests while excluding retained
end-to-end Learning Path routes. `make journey-test` runs those routes
sequentially. `make test` runs the complete suite. `make check` adds signed app,
launcher, repository-contract, and diff validation; `make strict-check` repeats
that gate with complete Swift concurrency checking and warnings as errors.

`make run-app` constructs the signed bundle and uses the single-instance
launcher. Do not run the raw SwiftPM executable for camera or controller work.
The launcher activates the exact existing bundle when possible and refuses
wrong-path or competing raw processes without terminating them.

The current sparse calibration implementation has automated and simulated
evidence only. No current physical camera/controller/pen/operator-click or
observed-ink validation is implied. See [Current Evidence](docs/CURRENT_EVIDENCE.md).

## Authoritative documents

- [Product Contract](docs/PRODUCT_CONTRACT.md) — product semantics, authority,
  safety, evidence, calibration applicability, and Stage 4 dependency boundary.
- [Discovery and Observed-Trial Protocol](docs/DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md)
  — exact operating sequence and recovery.
- [Architecture](docs/SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md) — package and
  runtime ownership.
- [Attended Hardware Runbook](docs/ATTENDED_HARDWARE_RUNBOOK.md) — explicitly
  authorized, attended physical verification.
- [Current Evidence](docs/CURRENT_EVIDENCE.md) — what is actually verified.
- [Roadmap](docs/ROADMAP.md) — unfinished work only.

Git history and Blackdog replay artifacts preserve implementation history. They
are not current product authority.

## Development contract

Follow `AGENTS.md`, `.codex/skills/adaptiveplotter/SKILL.md`, and
`blackdog.toml`. Normal implementation begins and lands through repo-local
Blackdog in its recorded task worktree and target branch. Never upgrade
automated or simulator results into attended physical evidence.
