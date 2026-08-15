# AdaptivePlotter Current Evidence

Status: current evidence ledger; software, simulator, controller, and attended
physical claims are recorded separately

This document records what was actually verified. Product meaning belongs to
[Product Contract](PRODUCT_CONTRACT.md), package ownership to
[Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md), and the physical
procedure to [Attended Hardware Runbook](ATTENDED_HARDWARE_RUNBOOK.md).

## Implemented software surface

### Stable exact-frame overlays and Learning viewport continuity

Validated 2026-08-15 in Blackdog task `TASK-912F3060`, targeting `main`
from base `6846f0b880622e24a78b3d5c5e85e30d9a934a44`.

Automatic scene analysis now retains the last completed Pen cap and inferred
Armature envelope geometry while the next frame is analyzing, but only while
that completed result still matches the displayed exact frame. Its completed
typed status also remains stable instead of oscillating through Analyzing. A
stale frame or camera configuration still renders no scene geometry. Re-entering Identify Pen
Cap with a valid LIVE appearance analyzes the newly frozen frame itself before
presenting overlays; a first unlearned appearance still requires its exact-frame
operator click before LIVE recognition can run.

Action-surface zoom and pan now survive entering or leaving Learning and other
compatible presentation-context revisions. Camera source/configuration changes
still reset the viewport, and sparse-mark selection retains its explicit stronger
initial focus.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused overlay, viewport, and Identify Pen Cap tests | passed — 46 tests | analyze-cycle retention and stale refusal, Learning visibility, compatible zoom/pan continuity, source/configuration reset, sparse focus, and frozen-frame overlay identity |
| `make quick-test` | passed — 377 tests | fast unit/component partition |
| `make journey-test` | passed — 10 tests | sparse calibration, reset, Boundary, drawing, and Stop journeys |
| `make strict-check` | passed — 387 tests | strict concurrency, warnings as errors, signed bundle, launcher validation, full test suite, and repository checks |
| `git diff --check` | passed | whitespace and conflict markers |

These results are software and deterministic fixture/simulator evidence. No
attended camera, controller, motion, pen, operator-click, or observed-ink
validation was performed, and the changed app was not launched against physical
hardware.

### Limit-aware manual alarm unlock

Validated 2026-08-14 in Blackdog task `TASK-01E545BB`, targeting `main`
from base `b609c4103099ede12775be0f1dd26545ada10576`.

The Motion panel now projects the sampled X/Y/Z axis-limit inputs separately
from the latched controller alarm and labels manual alarm unlock as armed,
blocked, or not armed. A current Alarm report with no asserted axis-limit input
arms **Clear Alarm**. An asserted `Pn:X`, `Pn:Y`, or `Pn:Z` disables it and tells
the operator to release the physical switch and Connect again. Missing current
limit evidence remains unarmed.

`MachineController` also performs a second realtime status query immediately
before `$X`. If any axis limit became asserted after Connect, current status is
unavailable, or the controller is no longer in Alarm, it records a typed refusal
without transmitting `$X`. A historical alarm with currently clear axis inputs
remains an explicit operator-owned unlock; Connect remains passive and Motion
authorization remains inactive.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused controller and UI selection | passed — 64 tests | XYZ limit sampling, visible armed/blocked state, fresh pre-write race, no `$X` on asserted Z, acknowledged unlock, and fresh reprobe |
| `make quick-test` | passed — 345 tests | fast unit/component partition |
| `make strict-check` | passed — 355 tests | strict concurrency, warnings as errors, signed bundle, launcher validation, full test suite, and repository checks |
| `git diff --check` | passed | whitespace and conflict markers |

These are software and deterministic transcript results. No attended controller
connection, physical switch assertion/release, alarm unlock, homing, motion,
pen, camera, or ink validation was performed.

### Controller alarm visibility and explicit clearing

Validated 2026-08-14 in Blackdog task `TASK-415B504F`, targeting `main`
from base `34de05332cd5d4c0154c402c4609d881b20b9687`.

A failed Connect probe now preserves and projects its exact typed controller
alarm, controller error, timeout, invalid-reply, or transport blocker instead
of collapsing the workbench to generic Disconnected status. The Motion panel
shows the current controller alert. A reported alarm exposes one explicit
**Clear Alarm** action with an in-context warning that unlock is not homing,
position recovery, limit clearing, Motion authorization, or proof of safe
movement.

The runtime admits `$X` only from current alarm evidence for the selected
controller, serializes it against every other controller operation, records raw
I/O plus a typed alarm-clear outcome, and never sends it during Connect. An
acknowledged unlock clears no evidence authority by itself: the same operator
action runs a fresh complete passive probe, leaves Motion inactive, and requires
the operator to press **Enable Motion** separately. Rejection or transport
uncertainty closes the link, remains visible, and is never retried
automatically.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused controller and UI selection | passed — 62 tests | alarm retention, no implicit unlock, typed clear admission/refusal/acknowledgement/rejection, fresh reprobe, UI status, and Motion remaining disabled |
| `make quick-test` | passed — 343 tests | fast unit/component partition including typed alarm-clear ledger evidence |
| `make strict-check` | passed — 353 tests | complete concurrency, warnings-as-errors, signed bundle and launcher validation, full test suite, repository checks |
| `git diff --check` | passed | whitespace/conflict markers |

These are software and deterministic transcript results. The already-running
app and physical controller were inspected read-only before implementation,
but this change was not launched into that app. No alarm was cleared, and no
attended controller connection, physical limit inspection, homing, reset,
Motion enablement, physical movement, pen action, camera validation, or ink
validation was performed.

### Pen-Down manual motion and Learning Off

Validated 2026-08-12 in Blackdog task `TASK-F782C7D6`, targeting `main`
from base `57406224cb5556cfa54df3332988c877148bff9c`.

The four manual direction controls now route a known commanded Pen Up state to
ordinary relative travel and a known commanded Pen Down state to the existing
bounded drawing-stroke owner. Consecutive clean Pen-Down moves retain Pen Down,
so the operator can request all four sides of a square. The drawing path has its
own typed telemetry and capability-bound Stop; a clean Stop waits for Idle and
retains the drawing owner's one Pen Up outcome. Unknown pen state remains a
pre-request refusal.

The workbench also exposes explicit **Turn Learning Off** and **Turn Learning
On** actions. Off hides the Learning Path and Exercise panes and refuses new
Learning actions without clearing accepted learning, disconnecting, disabling
Motion, stopping video, or gating direct manual control. An active Learning
attempt must settle through its existing Cancel/Stop action first.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused manual/Learning tests | passed — 5 tests | four-side Pen-Down square, drawing Stop/Pen Up, Learning Off authority preservation, active-attempt interlock, causal simulator drawing with zero machine actions |
| `make quick-test` | passed — 329 tests | fast unit/component partition |
| `make journey-test` | passed — 10 tests | retained sparse, checkpoint, Stage 4, Boundary, reset, and simulator journeys |
| `make strict-check` | passed — 339 tests | complete concurrency, warnings-as-errors, signed bundle and launcher validation, full test suite, repository checks |
| `git diff --check` | passed | whitespace/conflict markers |

These are software and simulator results. The app was not launched for this
change. No controller connection, physical pen actuation, physical motion,
manual square, camera observation, or observed ink validation was performed.

### Learning recovery progression and pen-cap color transport

Validated 2026-08-15 in Blackdog task `TASK-51E90720`, targeting `main` from
base `cce86f38150b2b83e9cb44e89148920c4a578a46`.

`LearningPathProjector` derives the current exercise from the active owner and
unmet dependency chain; a settled restartable attempt remains a selectable
needs-attention row with its own **Restart** action and cannot replace the
current exercise action strip. This historical change also established RGB
color propagation through continuous bounded analysis and exclusive Stage 3.3
inspections, with color-specific estimator revisions preventing one five-sample
proposal from mixing recognition settings. Its editable Video Settings color
well has since been removed. The current and only selection contract is the
exact-frame **Identify Pen Cap** action recorded below.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused projector, Vision, and workspace tests | passed — 19 tests | recovery/current-action separation, green-to-magenta component selection, camera-owner propagation |
| `make quick-test` | passed — 355 tests | fast unit/component partition |
| `make journey-test` | passed — 10 tests | retained causal simulator journeys |
| `make strict-check` | passed — 365 tests | strict concurrency, warnings-as-errors, signed app bundle and launcher, full tests, repository checks |
| `git diff --check` | passed | whitespace/conflict markers |

These are software and deterministic simulator claims. The application UI was
not launched. No attended camera, controller, motion, pen, operator color
selection, calibration click, or observed-ink validation was performed, so the
results do not establish physical color tolerance or cap-recognition reliability.

### Pure Learning Path projection

Validated 2026-08-13 in Blackdog task `TASK-F6773B41`, targeting `main`
from base `0a04af61581552f7613faf53b8968c5ef8f5c030`.

One values-only `LearningPathProjectionSnapshot` now feeds the pure
`LearningPathProjector`. The projector owns current-item and navigator status,
review detail, action strips, exact Stop capability presentation, typed failure
rendering, evidence, timeline/activity/subsystem rows, sparse-calibration and
Drawing Trial presentation, and reset surfaces. `OperatorWorkspace` retains
controller/camera/persistence ownership, operational policy and admission,
artifact acceptance, reset execution and stale-plan guards, and typed intent
routing. SwiftUI consumes one aggregate projection per Learning Path render.

The extraction deleted the parallel workspace presentation path.
`OperatorWorkspace.swift` fell from 10,197 to 8,905 lines and from 226 to 202
function declarations by the repository's source inventory. Direct projector
tests cover deterministic repeated projection, every row/state, LIVE/SIMULATED
parity, Stop ownership, typed failures, reset/vacate presentation, sparse
phases, Drawing Trial progression, and immutable review selection. Existing
workspace integration tests continue to cover routed actions and authority.

Validation results are recorded by the Blackdog landing result. These are
software and deterministic simulator claims only. No application launch,
controller, attended camera, physical motion, Pen Down, click, or observed-ink
validation was performed.

### Cohesive Learning Path state and typed transitions

Validated 2026-08-13 in Blackdog task `TASK-40195892`, targeting `main`
from base `57406224cb5556cfa54df3332988c877148bff9c`.

An independent cumulative re-audit after the source-session and workflow-
lifecycle landings found four remaining synchronized-field clusters. The
exercise attempt is now one idle/active lifecycle; sparse frozen-point
selection is one idle/awaiting-click/selected lifecycle; Drawing Trial payload,
history, rollback, and rewind are one cohesive value; and supervised motion
plus settlement use exhaustive typed action identity. The unused raw camera-
proposal UUID sentinel and the former manual Drawing Trial snapshot copy are
deleted.

Focused tests cover duplicate-start rejection, typed motion identity, sparse
re-click frame/point consistency, source isolation, invalidation/reset, atomic
fallback, ambiguous/lost terminal cleanup, checkpoint recovery, and no-redraw
behavior. Full validation is recorded by the Blackdog landing result. No app
launch, controller, camera, motion, pen, click, or physical ink validation was
performed.

### Source-indexed learning sessions

Validated 2026-08-12 in Blackdog task `TASK-3E783DB1`, targeting `main`
from base `adcf90f9095ac40c395178366ee79f7fe1a7060c`.

`OperatorWorkspace` now holds independent LIVE and SIMULATED
`LearningSessionState` values governed by one structural contract. Source
switching selects the active value instead of snapshotting and restoring a
shared authority surface. Entering SIMULATED creates a fresh nonphysical
session; returning to LIVE selects the unchanged LIVE value. Durable machine
and tip checkpoint capabilities are LIVE-only, and the full simulated sparse
calibration journey proves no additional durable loads and zero saves or clears.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused workspace and sparse-tip suites | passed — 36 tests | source switching, independent resets, checkpoint isolation and revalidation, Boundary, Stage 4, possible ink |
| `make quick-test` | passed — 322 tests | fast unit/component partition |
| `make journey-test` | passed — 10 tests | retained sparse, checkpoint, Stage 4, Boundary, reset, and simulator journeys |
| `make strict-check` | passed — 332 tests | complete concurrency, warnings-as-errors, signed bundle and launcher validation, full test suite, repository checks |
| obsolete snapshot-symbol scan | passed — zero source/test matches | former snapshot type and parked/capture/restore/reset compatibility paths |
| `git diff --check` | passed | whitespace/conflict markers |

These are software and simulated-workflow results. No app launch, controller
connection, physical motion, camera capture, Pen Down observation, or observed
physical ink validation was performed.

The current source contains exactly two post-Boundary calibration exercises:

- 3.3 five-cap machine-to-visible-cap registration with three fit samples and
  two sealed holdouts. Each LIVE sample requires three strictly newer compatible
  exact inspections, refuses any non-accepted or ambiguous cap and more than
  2 px maximum pairwise cap-centroid spread, and retains the newest third exact
  frame/measurement without averaging;
- 3.4 five centered 2 mm-radius, 16-chord circular-mark observations capped at
  100 mm/min and using the current Up/Down values from the existing Pen
  Interaction exercise, far safe X-max/Y-zero-biased Pen-Up reveal,
  stronger presentation-only focus, frozen exact-frame human center clicks,
  post-click uncertainty/prediction/residual review, two holdouts,
  smallest-passing model selection, and explicit tip acceptance.

`TipCameraRegistration` maps machine coordinates directly to contact pixels.
Stage 4 consumes its exact revision, selects a 5 mm line that clears persistent
calibration circles, and owns its own local baseline, reveal MPos, drawing
execution, newer post-line frame, and generic ink observation.

The separate tip checkpoint loads quarantined. Same-paper restart uses a fresh
controller/cap frame and no new mark. Replacement-paper recovery requires one new
accepted contact observation. Possible ink is keyed by machine position plus
mark radius plus paper identity and survives cancel/restart/reset on that paper.

The former multi-step target/region workflow, its runtime protocol, simulator
fixtures, exclusive tests, actions, artifacts, and detector composition are
deleted rather than retained as compatibility code.

## Stable preview during automatic overlay analysis

Validated 2026-08-12 in Blackdog task `TASK-D2BD0315`, targeting `main` from
base `d191045ef20026626437a3d92943cd0d80e7c167`.

Automatic overlay analysis no longer changes ActionSurface opacity, presents an
analysis badge, or owns a preview-publication pause token. Its subsystem status
is stable across individual analysis start/completion transitions. The separate
exclusive preview lease remains for explicit exact-frame operations such as
calibration and isolated-ink observation.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused ActionSurface, workspace, and scene-pipeline tests | passed - 32 tests | canonical rendering, overlay lifecycle, region/cadence propagation, scoped Vision settlement, bounded pipeline behavior |
| `make quick-test` | passed - 322 tests | fast unit/component partition |
| `make strict-check` | passed - 332 tests | complete concurrency, warnings-as-errors, signed bundle and launcher validation, full test suite, repository checks |
| obsolete-state scan | passed | no ActionSurface analysis-active state, analyzing badge, dimming rule, automatic preview gate, or oscillating overlay-analysis status remains |
| `git diff --check` | passed | whitespace/conflict markers |

These are software and simulated-workflow results. The app was not launched for
this correction. No attended camera, controller, motion, pen, pen-cap,
armature, preview-fluidity, or observed-ink validation was performed.

## Overlay ownership and implemented curriculum endpoint

The current implementation exposes exactly two persistent global controls:
**Pen cap** and **Armature envelope**. The envelope is explicitly inferred from
the cap and is not independently segmented. Operator/persistence-owned
preference is separate from requested features, typed status, and exact-frame
geometry. Scene, workflow, and simulation results have independent owners and
compose only for the exact displayed source, camera configuration, and frame.

The first Pen Interaction action is **Identify Pen Cap**. Before any question
or pen request, the operator clicks the colored cap body, not the tip, on one
frozen exact frame. The implementation samples a clipped 9 x 9 neighborhood,
rejects stale or unsupported evidence and gray, white, dark, or insufficiently
chromatic pixels, and persists the accepted median RGB color with exact frame,
source, camera configuration, click, sample-count, pixel-format, and algorithm
provenance. It supports arbitrary visibly colored caps, including blue. There
is no editable `ColorPicker`. Without an accepted LIVE appearance, the two
overlay preferences remain unchanged while LIVE cap and inferred-armature
statuses are Unavailable and no LIVE geometry is rendered.

Generic ROI is independent from workflow ROI, full-frame lock is canonicalized
to default analysis, and ROI does not change whole-frame cap-size eligibility.
Frame-side/drawing-frame analysis and the optional Boundary Vision adviser are
absent; fixed bounded Boundary renewal, Stop, Idle/MPos settlement, and fallback
authority remain. Stage 4 intended geometry, observed ink, and residuals are
contextual evidence with no global toggles.

The visible Learning Path ends after the implemented 4.6 assessment. The former
selectable future stage, speculative online model-learning dataset, policy/reward
episode scaffolding, model-mismatch renderer, and model-prediction overlay kind
are deleted. Adaptive requirements remain roadmap-only.

The first integrated focused run passed before independent criticism. It is not
the current completeness result: `critic_4` rejected that state because a
persisted SIMULATED cap appearance could authorize LIVE analysis and because the
pre-question click continuation did not have an explicit owned, guarded, and
cancelable lifecycle. The critic's 101-test suite also failed. The ownership
retask separated LIVE and SIMULATED appearance state and passed its production
build, dedicated 11-test suite, and combined 53-test suite. The recovery retask
then made the click continuation owned, guarded, and cancelable, corrected the
stale tests, and passed the exact 108-test critic suite. The coordinator
independently reran the combined 53-test and exact 108-test suites and the diff
checks. Independent `critic_5` subsequently returned overall **ACCEPT** with no
software FAIL: C1 through C14 PASS, and C15 UNPROVEN only for final
landing/clean-state evidence and the explicitly unproven physical limitations
below. No landed or clean-checkout state is claimed here.

| Validation | Result | Scope |
| --- | --- | --- |
| Pre-critic integrated focused suites | passed — 95 tests | historical pre-critic result only; later rejected as completeness evidence by `critic_4` |
| `critic_4` exact suite against pre-retask state | failed — 101-test run | exposed SIMULATED-to-LIVE appearance authorization and unowned click continuation defects |
| Ownership retask production build | passed | LIVE and SIMULATED pen-cap appearance ownership separated |
| Ownership retask dedicated suite | passed — 11 tests | source separation and LIVE authorization boundary |
| Ownership retask combined suite | passed — 53 tests | corrected ownership integrated with cap, overlay, lifecycle, and simulator behavior |
| Recovery retask exact critic suite | passed — 108 tests | click continuation ownership, guards, cancellation, and corrected stale tests |
| Coordinator independent combined rerun | passed — 53 tests | independent rerun of the ownership-focused integration set |
| Coordinator independent exact critic rerun | passed — 108 tests | independent rerun of the complete current critic set after recovery |
| Independent `critic_5` | overall ACCEPT — C1–C14 PASS; C15 UNPROVEN | no software FAIL; final landing/clean state and physical limitations remain unproven |
| Final combined focused suites | passed — 157 tests | overlay ownership/status, click-first appearance, source separation, guarded recovery, Vision/ROI, curriculum, layout, lifecycle, and simulator behavior |
| `make quick-test` | passed — 374 tests | complete quick unit/component partition |
| `make journey-test` | passed — 10 tests | retained current curriculum and recovery journeys |
| `make strict-check` | passed — 384 tests | strict-concurrency warnings-as-errors build, signed launcher checks, full test suite, and repository gates |
| Focused `OperatorWorkspaceControllerAndBoundaryTests` | passed — 21 tests | stable three-frame LIVE cap evidence retains the newest exact result; bounded wobble passes; centroid spread above 2 px refuses; MPos authority remains separate |
| Focused overlay, curriculum, registration, Stage 3.3/3.4, Stage 4, reset, lifecycle, and simulator tests | passed — 132 tests | persistent preference, exact result ownership, all status cases, layout widths, one implemented curriculum endpoint, finite LIVE cap stability/refusal and newest-frame evidence, sparse calibration, no-redraw recovery, artifacts, ink observation, and causal simulation |
| Deleted-symbol scans | passed — zero matches | removed future route, model-learning/mismatch types, prediction overlay kind, speculative episode fields, field-registration/drawing-transform types, MachineActions request closures, and prior frame/Boundary adviser types across source, tests, README, and current docs |
| `git diff --cached --check` and deletion scans | passed | staged whitespace/conflict checks and removed-surface inventory |
| Signed LIVE C920 visual inspection | passed — UI inspection only | camera live with blue cap visibly in frame at 1610 × 897 and actual minimum 1440 × 798; exactly two vertically stacked overlay controls; both preferences On; wrapped Not learned status; no ColorPicker; settings usable; Learning Path auto-hidden at minimum width |

These are software, deterministic simulator, signed-launcher, and attended
camera/UI presentation results for unlanded changes. They do not establish a
successful pen-cap identification or any controller, motion, pen, calibration,
or ink outcome. Final landing and clean-checkout evidence are not claimed.

During signed LIVE inspection the C920 camera was live and a blue cap was
visibly present, but **Identify Pen Cap** was not clicked: reaching Pen
Interaction requires the preceding controller/Motion curriculum, which was
outside the authorization for this inspection. The controller stayed
disconnected, Motion stayed disabled, and no operation was admitted. No
Connect, Start, Enable Motion, manual-motion, pen, or calibration action was
used. The reported physical pen position remains ambiguous and therefore
possible ink; no motion or pen action occurred.

Blue-cap detection reliability, click ergonomics, cap-inferred armature
usefulness, preview fluidity, attended calibration, controller behavior, motion,
pen behavior, and observed ink remain skipped and unproven. Seeing the cap in a
live preview and verifying the UI layout does not establish any of those claims.

## Stage 3.4 circular-mark visibility correction

Validated 2026-08-12 in Blackdog task `TASK-BAD20882`, targeting `main` from
base `3a025e489c6f1115faaa2b107c7eb33a8db4ba09`.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused Stage 3.4 and checkpoint tests | passed — 83 tests | 2 mm/16-chord/100 mm/min geometry, far reveal, full configured Down outcome, frozen-frame focus, Stop blacklist, checkpoint reconstruction, Stage 4 clearance, rebased numerical-zero travel, scoped overlay retention |
| `make quick-test` | passed — 321 tests | fast unit/component partition |
| `make journey-test` | passed — 10 tests | retained sparse-circle, checkpoint, Stage 4, Boundary, reset, and simulator journeys |
| `make strict-check` | passed — 331 tests | complete concurrency, warnings-as-errors, signed bundle and launcher validation, full test suite, repository checks |
| `git diff --check` | passed | whitespace/conflict markers |

These are software and simulated-workflow results. No app launch, controller
connection, physical motion, camera capture, Pen Down observation, or observed
ink validation was performed for this correction.

## Phase 4 automated evidence

Validated 2026-08-12 in Blackdog task `TASK-2AF7445C`, targeting `main` from
base `02f8431ad5af762f0a293912435fa7f6834181b9`.

The integrated validation matrix is populated from the landing run. Commands
are executed in the Blackdog task worktree and are software evidence only.

| Validation | Result | Scope |
| --- | --- | --- |
| Independent architecture/deletion review | passed with fixes | chronology, checkpoint restore, post-click drawing, blacklist/reset lifecycle, journey routing, stale symbols |
| Focused sparse authority and ActionSurface tests | passed — 72 tests | model/evidence constructors, checkpoint, frozen click, review geometry, planning, simulator |
| Checkpoint restart and paper-plane journey | passed within focused/journey gates | same-paper no-mark restore; changed-paper one-circle restore |
| LIVE reset durable-tip test | passed | quarantined tip store is cleared by affected Reset All plan |
| `git diff --check` | passed | whitespace/conflict markers |
| `make quick-test` | passed — 312 tests | unit/component partition with retained journeys excluded |
| `make journey-test` | passed — 11 tests | retained sparse, checkpoint, Stage 4, Boundary, reset, and simulator journeys |
| `make strict-check` | passed — 323 tests | signed bundle, launcher, full tests, repository contract, strict concurrency, warnings-as-errors, diff check |
| Deleted-symbol search | passed — zero matches | removed workflow types/actions/labels across source, tests, current docs, and Makefile |
| Blackdog configured validation (`git diff --check`) | passed | repository-configured landing validation |

The pre-landing patch touches 48 paths: 7,077 added lines and 12,317 deleted
lines, net −5,240. This is strongly net-negative even with all five new
untracked implementation/test files counted. The primary checkout remained
clean at the same base commit during validation. The landed commit and cleanup
state are recorded in the external phase coordination ledger because a commit
cannot truthfully contain its own hash.

A passing row means only that exact command and scope passed in this task
worktree.

## Simulator evidence

The causal simulator retains a large nonzero cap-to-tip truth, persistent black
16-segment circular marks, isolated line ink, paper identity, and exact causal frames. It
traverses the same public actions and dependency graph without calling physical
machine actions. It validates workflow structure and provenance plumbing only.

Every simulator claim is labeled `SIMULATED — NOT PHYSICAL EVIDENCE`.

## Physical-validation boundary

For this replacement run, all of the following were deliberately skipped:

- physical camera capture and optical-identity validation;
- physical controller connection, command acceptance, Idle/MPos settlement, or
  motion observation;
- physical full Pen Down/Up, 2 mm-radius circle motion, and contact behavior;
- a human operator clicking real observed marks;
- physical paper/contact-plane checkpoint revalidation;
- observed physical black marks or Stage 4 line ink.

Therefore this run does **not** establish physical calibration accuracy,
physical contact safety, camera quality, controller behavior, pen behavior,
operator-click usability, or observed-ink performance. Use the attended
runbook to create those evidence classes.

## Known limitation

Machine/tool/contact/mount/reframing semantic revisions are stable across app
restarts, and paper replacement has an explicit revision rotation. The current
UI does not yet provide dedicated revision-rotation controls for every other
physical assembly change. An attended operator must refuse checkpoint
revalidation after any unrecorded remount or assembly change and perform a full
reset/recalibration. Dedicated controls remain roadmap work.

Frame hashes and metadata are provenance. Current tip evidence does not promise
durable pixel reprocessing because no content-addressed frame archive is stored.
