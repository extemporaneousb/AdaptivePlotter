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
   - **4.1 Run Predicted Isolated Line Trial**

The visible curriculum finishes at 4.1. After the fifth valid Stage 3.4 click
commits the drawing map, one **Go** previews the predicted line and owns the
normal baseline, motion, drawing, reveal, Vision, and comparison phases. Those
phases are visible activity, not six approval buttons. The exact post-line
comparison remains reviewable after the exercise finishes. That attributable
validation unlocks the separate **Drawing Studio**; adaptive model fitting and
adaptive readiness remain Roadmap scope and are not Learning Path stages.

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
compatible pins and context, current MPos when required, single-operation
ownership, and no sticky ambiguity. Manual direction controls do not additionally
depend on camera, Vision, Learning state, current-camera calibration, or a
visually confirmed pen pose.

The application does not home, reset the controller, write firmware settings,
or treat entered bounds, a Learning Path stage, or model confidence as motion
authority. Connect never clears an alarm implicitly; only the explicit,
limit-aware **Clear Alarm** action can send one guarded `$X` request.

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
Each LIVE sample requires exactly three strictly newer compatible exact
inspection frames with one accepted unambiguous cap per frame and no more than
2 px maximum pairwise cap-centroid spread. The newest third frame and its cap
measurement become evidence; geometry is not averaged, and the preliminary
freshness boundary is not evidence. SIMULATED geometry is separate nonphysical
evidence and does not prove live stability.
The first three fit an affine machine-to-visible-cap map; the last two are
independent holdouts. Both holdouts must pass before a weighted all-five refit
can be explicitly accepted as `MachineCameraRegistration`. The visible cap
landmark is not the hidden paper-contact point.

Stage 3.4 uses one supervised **Draw Five 2 mm Circles** action. One circle is
at the accepted Boundary envelope's geometric center. The other four circle
centers are the rectangle corners at `minX + 2 mm`, `minY + 2 mm`,
`maxX − 2 mm`, and `maxY − 2 mm`, so every 2 mm-radius path stays inside the
accepted envelope while framing essentially the complete drawable region.
Stage 3.3 retains its separate existing ±24 mm camera-calibration spacing. One
exercise attempt and one stoppable operation draw the five circles in canonical
evidence-slot order. For every circle the app travels and settles Pen Up at the
intended position, retains its exact pre-mark frame/cap/controller evidence,
moves Pen Up to the circle start, lowers and settles using the current Pen
Interaction profile, draws one closed 16-chord circle of 2 mm radius at no more
than 100 mm/min, then raises and settles Pen Up before any inter-circle travel.
There are exactly 80 circle chords and no connecting Pen-Down strokes; the
accepted drawable-region overlay supplies the bounding box without adding slow
or ambiguous perimeter ink.

Only after the fifth circle does the app return Pen Up to the rectangle center,
require Idle/final-MPos settlement, revalidate the current camera/cap
applicability, and capture one newer exact frame. That exact frame is frozen
unchanged for all five clicks. Accepting the resulting tip map makes the four
outer circle centers its applicability rectangle and Drawing Studio drawable
region. Stage 3.4 does not change zoom, pan, preferred zoom, or viewport focus
automatically; manual presentation transforms remain operator controlled.

Pen Interaction retains its existing Up → Down → Up exercise. Its Up and Down
steps expose sliders displaying the current settings, seeded at `S40` and
`S760` for a fresh session; **Next** accepts the currently displayed value.
Those are mutable current settings, not one fixed
calibration for an entire run. Repeating the existing exercise at another
position may select different values, and the exercise evidence retains the
actual value plus the controller outcome, timestamp, and current MPos when each
is available for later learning. Refusal, ambiguity, or unavailable MPos stays
explicit and never disables **Next**. It does not create a separate servo-
calibration entity.

A complete commanded actuation plus its settlement is controller evidence;
only attended observation can prove that the physical pen cleared or reached
the paper.

The UI shows click count and all collected markers. Click order has no semantic
meaning. After the fifth click, the app projects all five known machine
positions through the current `MachineCameraRegistration`, centers projected
and clicked point sets to remove their common cap-to-tip translation, evaluates
all 5! one-to-one assignments, and selects the minimum total squared pixel
distance with canonical calibration-position order as the exact-tie break.
There is no click-distance or ambiguity threshold. **Undo Last Click** or
**Clear Clicks on This Frame** changes only same-frame click evidence and causes
no motion, ink, redraw, frame capture, zoom, or pan.

The app constructs a direct affine machine-to-tip map from all five accepted
observations first. Constant camera-pixel correction on the accepted cap map is
used only when affine construction itself throws. All-five residuals, RMS,
covariance, and uncertainty remain diagnostics; their magnitude never rejects
a model or blocks proposal creation. Stage 3.4 has no holdouts and numerical
fitting cannot request paper replacement or route to a no-redraw recovery.
The fifth valid click atomically commits `TipCameraRegistration` and makes Stage
4 current. A separate action appears only to retry a failed atomic commit.

Stage 3.4 therefore means the machine-to-paper-pixel map is ready within its
recorded applicability. Stage 4.1 validates that map once: the app draws the
predicted cyan line before motion, then shows observed white ink and orange
residuals after Vision and retains that exact-frame comparison for later review.
It does not claim a generally trained adaptive model. It does permit direct
placed-vector drawing with the current map; automated coverage selection,
candidate model fitting, and an accepted typed readiness assessment remain
Roadmap work.

An uncertain circle chord, Pen Down/Up outcome, or motion outcome blacklists
that circle center/radius on the current paper and stops the workflow. Possible ink never causes automatic
retry, redraw, resend, or continuation. Paper replacement is recorded only for
an actual replacement or as the existing possible-ink recovery, never because
of numerical fitting.

## Tip authority and persistence

`ToolContactObservation` is immutable evidence. It binds intended and settled
machine poses, controller context, the 2 mm-radius/16-chord/100 mm/min-capped mark geometry, the
actual current Down/Up actuation values, Pen Down/Up outcomes, tool and paper
identities, exact pre/post frames, cap-map checks, asserted camera point,
pointing uncertainty, presentation-transform revision, disposition, and
consumed algorithm/artifact revisions.

`TipCameraRegistration` maps machine coordinates directly to paper-contact
pixels. It retains the chosen model form, affine transform, diagnostic
residuals/covariance/uncertainty, applicability rectangle, all five observation
identities and revisions, semantic optical/machine/tool/paper identities, and
accepted revision. A diagnostic cap-to-tip pixel difference at one pose is not
a durable camera-independent tool vector.

The machine-only checkpoint remains separate. `AcceptedTipCalibrationCheckpoint`
loads quarantined and cannot restore authority without current semantic
identity plus fresh controller/cap evidence. An unchanged paper/capture restart
requires a fresh cap frame and no new mark. Paper identity is split into a
replaceable `PaperInstanceRevision` and the support/stock/contact-height
`PaperContactPlaneRevision`. A new sheet explicitly placed on the unchanged
contact plane rotates only the instance, clears sheet coverage and ink-specific
state, and retains the tip map. A changed contact plane rotates both and
invalidates tip authority. Known pixel
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

## Drawing Studio

After one attributable Stage 4.1 validation, the top capability indicator says
**Interactive learning complete · one validation** and Drawing Studio becomes
available independently of the Learning Path. The operator can select one of
11 deterministic `DrawingProgram` producers—line, polyline, rectangle, square,
triangle, regular polygon, circle, ellipse, star, pyramid, or elephant—then
place its target on the video, resize it, rotate it, and inspect the projected
plan. Curves are deterministically tessellated before execution.

The accepted tip-map applicability projects a persistent calibrated drawable
outline and the current predicted tip point. Paper is a separate operator fact:
**Confirm Paper Coverage** binds the current sheet and exact frame to the
outlined region before Run can become eligible. **New Sheet — Same Contact
Plane** preserves learned geometry but requires a fresh coverage confirmation;
**Contact Plane Changed** invalidates the tip map.

`DrawingPlanner` refuses any transformed stroke outside the calibrated region
and emits an immutable content-addressed execution-plan revision with one
checkpoint per logical stroke. `RunInterpreter` owns Pen-Up travel, lowering,
every finite drawing segment, raising, Stop, and checkpoint progress as one
operation. A completed run returns to the preselected observation pose, captures
a newer exact frame, compares arbitrary planned polylines with new ink, and
retains intended, observed, and residual overlays for review. Refusal,
cancellation, ambiguity, or possible ink is terminal and never redraws.

Stage 4 validation and later run evidence are stored in a checksummed,
append-only archive with fixed predeclared roles: ordinary drawing, training,
reserved holdout, or evaluation holdout. These records may feed later model
estimation, but they do not themselves promote a model. A typed readiness schema
exists; no current workflow emits **Adaptive drawing ready** without all of its
future declared coverage/model-comparison/holdout requirements.

## Workbench and evidence

One singleton window contains the Learning Path, always-mounted camera/action
surface, selected exercise, Motion region, optional Drawing Studio, and optional Video Settings. The
state-dependent Show/Hide controls and matching panel close controls share one
grammar. A panel that owns the only active Stop cannot be hidden until its
operation settles.

Video Settings combines camera selection, adjacent Refresh, scene-analysis
frames per second, viewport zoom/drag/region lock, and exactly two readable
one-column global overlay cards: **Pen cap** and **Armature envelope**. Each card
keeps persistent On/Off preference separate from typed status, reason, region,
cadence, exact analyzed frame, and result age. The armature envelope is inferred
from the detected cap and is not independently segmented. Selecting either
overlay directly keeps bounded newest-only analysis running; there is no
separate Analyze/Resume control.
Automatic overlay computation does not dim, badge, or pause preview
publication. A completed overlay remains visible over its matching displayed
frame with its completed status while the next frame is analyzed, then the
displayed-frame/overlay pair is replaced atomically. Entering or leaving
Learning and other compatible presentation-context changes preserve the exact
effective visible camera-pixel rectangle, including when Stage 3.3 publishes
learned fitted bounds; a source or camera-configuration change still resets it.
Explicit Full, Fit, zoom, and pan actions remain authoritative. Stage 3.4
sparse-mark actions never change viewport zoom, pan, fitted region, preferred
zoom, or focus. Locking the viewport admits only that camera-pixel subregion to
generic scene-analysis scans without cropping or rewriting the exact stamped
frame, and Stage 3.3 does not rewrite that lock. A generic viewport region never
constrains calibration or observed-trial measurements, and full-frame lock is
canonicalized to default unlocked analysis.

Pen-cap appearance is learned only by the first **Identify Pen Cap** action in
Pen Interaction. The operator clicks the colored cap body, not the tip, on one
frozen exact frame. A clipped 9 x 9 sample rejects gray, white, dark, or
insufficiently chromatic pixels and persists the accepted median RGB color with
the click, frame hash, source, camera configuration, dimensions, pixel format,
sample counts, and algorithm revision. This supports arbitrary visibly colored
caps, including blue; there is no editable color picker. Until a LIVE selection
has been learned, Pen cap and Armature envelope remain selected according to the
operator's persisted overlay preferences but report Unavailable and render no
LIVE geometry.

Overlay preferences are operator-owned persisted choices. Camera lifecycle,
workflow activity, errors, stale frames, suspension, and load shedding change
status or renderability, never the selection. Scene, workflow, and simulator
results have separate owners and are composed only when their frame and camera
configuration exactly match. Stage 4 intended geometry, observed ink, and
residuals are required contextual evidence rather than global toggles.

The toolbar owns controller selection, Connect/Disconnect, Enable Motion, and
compact status. Exercise Start, choices, Cancel, Stop, Restart, Redo, and Record
Another Attempt stay with the exercise. A settled failed or cancelled attempt
keeps Restart on its own review row but does not replace the next unmet exercise
or its Start control. Buttons are authoritative input; speech is advisory output
only.

Manual X distance, Y distance, and feed remain editable text fields initialized
to 50 mm, 50 mm, and 500 mm/min. After Motion is enabled, camera, Vision,
Learning, current-camera calibration, and visually confirmed pen pose do not
disable the direction controls.

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
make run-app-simulated
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

`make run-app-simulated` uses the same signed bundle, singleton launcher,
identity validation, and activation proof, but passes a nonpersistent startup
argument that enters causal **SIMULATED** mode without camera discovery,
selection, or startup. It refuses an already-running app because that process's
startup mode cannot be changed or proven. This is the reproducible nonphysical
visual-inspection command; it does not provide camera, controller, motion, pen,
calibration, operator-click, or observed-ink evidence.

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
