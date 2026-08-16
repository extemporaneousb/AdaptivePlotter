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
   - **3.2 Set X, Y Boundaries**
   - **3.3 Calibrate Camera and Visible Cap**
   - **3.4 Calibrate Pen Contact from Sparse Marks**
4. **Observed Drawing Trials**
   - **4.1 Choose Isolated Line Plan**
   - **4.2 Capture Local Pre-Line Baseline**
   - **4.3 Move to Line Start**
   - **4.4 Draw Isolated Line**
   - **4.5 Reveal and Observe New Ink**
   - **4.6 Compare Intended and Observed Geometry**

The visible curriculum finishes at 4.6. Adaptive Drawing is roadmap scope and is
not a selectable current stage.

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
authority. A guarded manual **Clear Alarm** action may issue one `$X` only from
fresh Alarm evidence with freshly clear X/Y/Z limit inputs; it neither homes nor
enables Motion.

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

Stage 3.4 uses the same ordered cross. At each position the app:

1. settles Pen Up at the intended MPos;
2. captures an exact pre-mark frame and revalidates the cap map;
3. moves Pen Up to the circle start, commands the complete lower operation with
   the current Down value from Pen Interaction (`S760` initially, then the
   configured settle), and accepts only a settled Down outcome;
4. draws one closed 16-chord circle of 2 mm radius at no more than 100 mm/min,
   raises once, then moves Pen Up to the learned safe X+ limit and as close to
   machine Y=0 as the 10 mm Boundary inset permits;
5. settles, captures a newer exact frame, and revalidates the cap map;
6. freezes that exact frame without changing the operator's zoom, pan, or
   locked analysis region, and asks the operator to click the circle center;
7. allows re-clicking only on the same frame, with no motion or ink action.

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

The expected tip point is hidden until the click is made. Before accepted
authority exists, the UI says **Tip not calibrated**. After a click, the UI
shows the selected point and uncertainty, the expected point from the current
tip-calibration candidate, and residual.

The first three accepted marks fit candidates; `X+` and `Y−` remain holdouts.
The smallest passing model wins: a constant camera-pixel correction on the cap
map is tried first, and a direct affine tip map is considered only after
coherent failure at both holdouts. Both holdouts must pass. The selected model
is refit on all five observations and becomes current only after explicit
**Accept Tip Calibration**.

Before any LIVE Pen Down, the complete circle geometry is conservatively
reserved in the one current-paper surface-exposure ledger and atomically
persisted. An uncertain circle chord, Pen Down/Up outcome, motion outcome, or
process exit therefore leaves that circle unavailable on the same paper and
stops the workflow. A rejected or corrupt ledger blocks contact; it is never
treated as empty on the same paper. Explicit paper replacement archives the
rejected bytes and atomically begins a fresh ledger for the replacement paper.
Possible ink never causes automatic retry, redraw, resend, or continuation.
SIMULATED learning uses the same typed ledger in memory with
explicitly nonphysical entries and never writes the LIVE store.

## Tip authority and persistence

`ToolContactObservation` is immutable evidence. It binds intended and settled
machine poses, controller context, the 2 mm-radius/16-chord/100 mm/min-capped mark geometry, the
actual current Down/Up actuation values, Pen Down/Up outcomes, tool and paper
identities, exact pre/post frames, cap-map checks, asserted camera point,
pointing uncertainty, presentation-transform revision, disposition, and
consumed algorithm/artifact revisions.

`TipCameraRegistration` maps machine coordinates directly to paper-contact
pixels. It retains the chosen model form, affine transform, uncertainty,
applicability rectangle, sealed holdouts, all five observation identities,
semantic optical/machine/tool/paper identities, and accepted revision. A
diagnostic cap-to-tip pixel difference at one pose is not a durable
camera-independent tool vector.

`LearningAuthorityManifest` is the one checksummed durable authority file. One
generation atomically carries the optional machine-only and accepted-tip
checkpoint payloads. Each accepted-authority save, and each invalidation that
actually removes either durable payload, uses an exact manifest revision CAS so
machine/tip authority cannot land in mixed generations. Nondurable graph-only
invalidation neither reads nor rewrites that manifest.
The tip payload loads quarantined and cannot restore authority without current
semantic identity plus fresh controller/cap evidence. A paper-plane change requires
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
`TipCameraRegistration` revision. Stage 4 chooses an immutable local 5 mm line
that clears every retained surface exposure; it blocks if the accepted domain is too
crowded rather than letting old ink split the new observation. Each visible leaf
owns one current subject and payload: line plan, local baseline/reveal context,
line-start arrival, line execution, atomic post-line observation, and comparison.
Those subjects cite their exact causal predecessors. Invalidating a leaf removes
that subject and only its graph consumers. Once a line group has any reserved
exposure, however, invalidating or repeating 4.1 through 4.4 abandons that group
and returns to a fresh 4.1 plan; it never captures a false post-ink baseline or
reuses exposed geometry. Before LIVE Pen Down, the complete
line geometry is reserved and atomically persisted in the same surface-exposure
ledger used for calibration circles. That history survives process restart and
Learning invalidation and is never made eligible for redraw; explicit paper
replacement changes applicability without deleting safety history.

No Stage 3 scene artifact is reused as a Stage 4 baseline or observation pose.
An attributable observed line may become future refinement evidence, but it
cannot silently promote a model. Ambiguous motion or possible ink never causes
an automatic redraw.

## Workbench and evidence

One singleton window contains the always-mounted camera/action surface, Motion,
and one combined Learning interface. A narrow Learning Path rail is embedded on
the leading edge of the Exercise pane; both consume one fresh projection. The
exercise body contains only its numbered title, Plotter/You script, optional
question, typed answer controls, and the contextual invalidation action. Native
toolbar and View commands share one window-state owner for Learning, Motion, and
the mutually exclusive Video/Diagnostics inspector. Window resizing never opens,
closes, or substitutes a pane.

Video Settings contains camera selection, Refresh, scene-analysis cadence,
viewport zoom/drag/region lock, and exactly two global overlay choices: **Pen
cap** and **Armature envelope**. Detailed camera, Vision, controller, workflow,
frame, ROI, cadence, provenance, and failure facts live in Diagnostics instead
of being copied into primary panels. The armature envelope is inferred from the
detected cap and is not independently segmented. Selecting either overlay keeps
bounded newest-only analysis running; there is no separate Analyze/Resume
control.
Automatic overlay computation does not dim, badge, or pause preview
publication. A completed overlay remains visible over its matching displayed
frame with its completed status while the next frame is analyzed, then the
displayed-frame/overlay pair is replaced atomically. Entering or leaving
Learning steps, fitted bounds, frozen frames, sparse-mark selection, and inspector
changes never mutate operator zoom or pan. Unlocked zoom changes rendering only;
generic analysis remains full-frame. Lock atomically captures the current visible
camera-pixel rectangle as the generic analysis ROI, and Unlock clears that ROI
without changing the view. Only a camera source/configuration replacement resets
view geometry and lock; cadence and the two overlay choices persist. A generic
analysis ROI never constrains calibration or observed-trial measurements.

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

The toolbar owns controller selection, Connect/Disconnect, Enable Motion, pane
visibility, inspectors, and compact status. Exercise actions stay with the
exercise. Commit/advance controls are green; Stop, Cancel, rejection, and
invalidation are red; same-stage value-entry controls are blue; view utilities
are gray; unavailable controls are dark and noninteractive. During active
Boundary motion the exercise exposes three capability-bound choices: **Stop &
Accept**, **Stop**, and **Cancel**. Only Stop & Accept may commit the settled side.
Escape activates red Stop, never acceptance. Buttons are authoritative input;
speech is advisory output only.

The selected Learning leaf or branch may be invalidated explicitly. A leaf roots
only its current subjects and the dependency graph removes true consumers. A
branch roots its descendant subjects. Plans are source-, revision-, payload-, and
sequence-bound; a scope that removes durable machine/tip authority also binds
the exact manifest revision. Stale plans are inert. Retained sparse exposure
requires paper replacement rather than same-paper Redo. An exposed Stage 4
group routes any 4.1–4.4 replacement through a fresh 4.1 plan. Invalidation never moves the plotter,
changes pen state, resends, redraws, or erases possible physical ink.

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
