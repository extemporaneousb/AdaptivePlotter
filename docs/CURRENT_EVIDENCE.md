# AdaptivePlotter Current Evidence

Status: current evidence ledger; software, simulator, controller, and attended
physical claims are recorded separately

This document records what was actually verified. Product meaning belongs to
[Product Contract](PRODUCT_CONTRACT.md), package ownership to
[Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md), and the physical
procedure to [Attended Hardware Runbook](ATTENDED_HARDWARE_RUNBOOK.md).

## Implemented software surface

### Stage 3.3 exact viewport and analysis-lock continuity

Implemented and validated 2026-08-17 in Blackdog task `TASK-B1EB11D5`,
targeting `main` from base `4b78432d619c31fb76947a7dd9aaa12799ab3d97`.

Stage 3.3 acceptance previously preserved only the numeric zoom and pan values.
Acceptance also changed the viewport fitted target from the pre-registration
fallback to learned plotter bounds, so those same numbers produced a different
effective camera-pixel rectangle. A locked analysis region remained the old
rectangle, leaving the displayed view inconsistent with the still-active lock.

`ActionSurfaceViewportState` now snapshots the exact effective visible
camera-pixel rectangle before a compatible source/configuration context replaces
its fitted target. Stage 3.3 acceptance and later compatible fitted-bound
replacements retain that rectangle and leave `VideoAnalysisRegionLock`
unchanged. An explicit Full, Fit, slider, or pan action remains authoritative;
source or camera-configuration incompatibility still resets the viewport.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused viewport suite | passed — 10 tests | real Stage 3.3 `nil`-to-learned fit transition, replacement fit, exact visible rectangle, locked analysis-region continuity, explicit controls, pan, clipping, and incompatible-camera reset |
| `make quick-test` | passed — 448 tests | fast unit/component partition with retained journeys excluded |
| `make journey-test` | passed — 10 tests | sparse calibration, checkpoint revalidation, exact tip revision, reset, Boundary, drawing, and Stop journeys |
| `make strict-check` | passed — 458 tests | strict concurrency, warnings as errors, signed bundle, launcher checks, full tests, repository contract, and diff check |
| `git diff --check` | passed | whitespace and conflict markers |

These are source, deterministic fixture, simulator, build, signed-bundle, and
repository-contract results. The new binary was not launched for an attended
camera workflow. No physical camera, controller, motion, Pen, operator-click,
or observed-ink validation was performed.

### Durable Learning Path prefix and restart pose revalidation

Implemented and validated 2026-08-17 in Blackdog task `TASK-69EC31D1`,
targeting `main`.

One integrity-checked atomic checkpoint now retains the accepted LIVE Learning
Path prefix: Pen Interaction, Boundary and center artifacts, the Stage 3.3
machine-to-cap registration, the accepted Stage 3.4 tip registration, and the
Stage 4 evidence-record reference. Production migrates the former separate
machine and tip checkpoint files when possible. Because those legacy files did
not contain Pen Interaction, Stage 3.3, or Stage 4 payloads, they cannot
manufacture the missing historical stages; future acceptance under this build
records the complete prefix.

Restart loads learned values but never restores Motion authorization, current
Pen pose, active ownership, Stop capabilities, camera frames, or pending
commands. A fresh passive controller-identity probe restores parked machine and
Stage 3.3 authority. Reported MPos displacement is diagnostic and leaves
coordinate-dependent Learning and Drawing Studio blocked until one fresh exact
cap frame revalidates pose. It is not authority over direct manual controls:
manual jog and manual Pen commands remain gated by Motion authorization and the
controller's current connection, alarm, readiness, safety, and serialization
facts. Under unchanged machine, camera-mount, optical, tool, and paper-plane
identities, the fresh cap may establish a pure coordinate translation; accepted
Boundary, machine-camera, and tip geometry then move together under a new
coordinate revision. Rotation, scale, and uncertain identity are not inferred.

The fifth Stage 3.4 click now produces a reviewable frozen-frame proposal.
**Accept Tip Map** is the explicit durable commit. Reject, undo, and clear retain
the same frozen frame and perform no redraw or motion. **Reset From This Step**
writes or clears the retained durable prefix before changing in-memory learning;
a storage failure leaves the current learning state intact. Stage 4 completion
is accepted only against the exact saved tip revision. Paper coverage wording
now identifies **Assert Sheet Covers Outline** as an operator assertion rather
than measured paper-edge evidence.

A read-only direct serial probe was also performed while the application was
closed on `/dev/cu.usbserial-A10OF67O` at 115200 baud. Only `?`, `$G`, `$#`, and
`$I` were transmitted. The controller reported Idle, `MPos:277.560,-39.875,0`,
zero G54 offsets, and grblHAL BlackBox X32 identity. No jog, Pen command, alarm
clear, reset, or other motion-capable command was transmitted. This proves a
responsive controller and reported state only; it does not prove physical pose
after unpowered carriage movement.

| Validation | Result | Scope |
| --- | --- | --- |
| Restart/reset focused suites | passed — 8 tests | atomic store integrity, saved Boundary restore, no-mark tip revalidation, and reset-prefix atomicity |
| `make quick-test` | passed — 437 tests | fast unit/component partition with retained journeys excluded |
| `make journey-test` | passed — 10 tests | sparse calibration, checkpoint revalidation, exact tip revision, reset, Boundary, drawing, and Stop journeys |
| `make strict-check` | passed — 447 tests | complete strict concurrency, warnings as errors, signed bundle, launcher checks, full tests, repository contract, and diff check |
| `git diff --check` | passed | whitespace and conflict markers |

These results are source, deterministic fixture, simulator, build, signed
bundle, repository-contract, and read-only controller-query evidence. The new
binary was not launched for an attended camera workflow. No physical motion,
Pen Down/Up, operator click, paper placement, cap revalidation, or observed ink
was exercised by this task.

### Retained comparison, paper lineage, and placed-vector Drawing Studio

Implemented and validated 2026-08-17 in Blackdog task `TASK-FF3A5E6A`,
targeting `main`.

Stage 4 now finishes with a retained exact post-frame comparison of the cyan
predicted line, measured ink, and residuals. The workbench reports **Map ready**,
**Interactive learning complete**, or the separately scoped **Adaptive drawing
ready** state without treating one isolated line as model-training completion.
Entering Drawing Studio releases the retained Stage 4 frame and projects its
target only onto the currently displayed exact frame.

Paper identity is split into replaceable sheet instance and calibrated contact
plane. Declaring a new sheet on the same contact plane preserves the accepted
tip map, rotates ink-specific identity, and requires fresh explicit coverage.
Declaring a changed contact plane invalidates the tip map. Paper coverage,
drawable-region, and predicted-tip overlays retain exact frame/configuration
provenance. Both paper identities, coverage evidence, accepted tip checkpoints,
and drawing-run evidence survive restart through separate typed stores.

Drawing Studio consumes the canonical Model `DrawingProgram` path. Its fixed
catalog contains line, polyline, rectangle, square, triangle, regular polygon,
circle, ellipse, star, pyramid, and elephant programs. Placement produces a
content-addressed machine execution plan inside the learned drawable region;
the Runtime owns ordered Pen-Up travel, Pen Down, logical strokes, Pen Up, and
per-stroke checkpoints. The generic observer compares all planned polylines
with new ink on an exact same-pose frame pair. The append-only run record pins
program, placement, plan, model, registration, paper, request and execution
frontiers, terminal disposition, observation, and evidence role.

Audit corrections keep paper management and draft mutation unavailable while a
run owns execution or evidence capture, expose Stop only while a motion owner
exists, retain an execution-only record when post-run frame evidence is
unavailable, and block an already-commanded plan from redraw. Those exact plan
hashes are reconstructed from the durable archive after restart; a new sheet
clears only the prior sheet's ink-specific block. **New Run** retains archived
evidence and requires a distinct safe placement before a possibly inked plan
can execute again.

The deterministic catalog, trial roles, evidence archive, and typed readiness
schema are foundations for later active learning. No coverage selector,
candidate residual model, model promotion coordinator, or emitted adaptive-ready
assessment is implemented by this task.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused Model suites | passed — 19 tests | catalog determinism, curve tessellation, placement, planning, content identity, and typed readiness |
| Focused Runtime/evidence suites | passed — 25 tests | paper semantics, coverage, multi-stroke ownership, exact execution frontiers, no resend, planned-ink observation, archive integrity, and frame-unavailable evidence |
| Focused App/workspace suites | passed — 21 tests | retained comparison, exact-frame Studio projection, truthful capability/paper state, immutable editing states, processing without Stop, and new-run review controls |
| `make quick-test` | passed — 432 tests | fast unit/component partition with retained journeys excluded |
| `make journey-test` | passed — 10 tests | sparse calibration, checkpoint revalidation, exact tip revision, one-Go/reset, Boundary, drawing, and Stop journeys |
| `make strict-check` | passed — 442 tests | strict concurrency, warnings as errors, signed bundle, launcher validation, full suite, repository contract, and diff check |
| `git diff --check` | passed | whitespace and conflict markers |

These results are software, deterministic fixture, simulator, build, signed
bundle, and repository-contract evidence. No attended hardware, live camera,
physical motion, physical Pen Down/Up, operator click, paper placement, or
observed physical ink was exercised by this task.

### One-Go predicted isolated-line validation

Implemented 2026-08-16 in Blackdog task `TASK-ED0800E2`, targeting `main`.

The visible Stage 4 surface is now one 4.1 exercise. One **Go** chooses the first
clear signed-axis 5 mm plan, renders its model-predicted cyan line on the current
video before motion, then owns baseline capture, Pen-Up travel, the single
stroke, same-pose reveal, strictly newer frame capture, isolated-ink Vision, and
the normal typed comparison. Motion retains **Stop**. Foreground trial Vision is
named as the active operation owner. Possible ink, rejected Vision evidence, or
ambiguous controller outcomes stop without automatic redraw.

The fifth valid Stage 3.4 click now atomically constructs and commits the
`TipCameraRegistration`; only an actual commit failure exposes a retry. The UI
distinguishes **Map ready** after Stage 3.4 and **One attributable validation
complete** after Stage 4.1 from a future scoped **Trained/Ready** assessment.
Repeated coverage, reserved holdouts, candidate/prior comparison, shape
holdouts, and typed readiness remain roadmap work.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused Stage 3.4/4.1 suites | passed — 49 tests | one-Go ownership, predicted preview before motion, foreground Vision status, automatic comparison, fifth-click commit, Stop/no-redraw recovery, and atomic reset |
| `make quick-test` | passed — 384 tests | fast unit/component partition with retained journeys excluded |
| `make journey-test` | passed — 10 tests | sparse calibration, checkpoint, exact tip revision, one-Go reset, Boundary, drawing, and Stop journeys |
| `make strict-check` | passed — 394 tests | strict concurrency, warnings as errors, signed bundle, launcher validation, complete suite, repository contract, and diff check |
| `git diff --check` | passed | whitespace and conflict markers |

These results are software, deterministic fixture, simulator, build, and bundle
evidence. Attended hardware, camera, physical motion, Pen Down/Up,
operator-click, and observed-ink validation were not performed by this change.

### Stage 3.4 five-circle batch and affine-first authority

Implemented and landed locally 2026-08-16 in Blackdog task `TASK-0D8990BE` as
commit `b93e49fb3cf4fc39704f8b3da299b6affff537c3` on its recorded target branch,
`main`.

The implementation replaces per-circle progression with one supervised action
that draws five separated 2 mm-radius circles at Stage 3.4 offsets of ±30 mm,
settles Pen Up between circles, performs one final reveal, and freezes one exact
frame for five arbitrary-order clicks. Centered projected/clicked point sets and
an exhaustive deterministic 5! assignment associate clicks without a distance
or ambiguity threshold. All five observations enter affine construction first;
constant correction is only the construction fallback. Residuals, RMS,
covariance, and uncertainty are diagnostic only. Stage 3.4 has no holdouts or
numerical route to paper replacement, does not change viewport state, and makes
Stage 4 current only after explicit tip-registration acceptance. Stage 3.3
retains its separate ±24 mm camera calibration and holdout authority.

Focused software validation passed: 11 TipCalibrationAuthority tests, 3 sparse
coordinator tests, 12 calibration-planning tests, 7 sparse workspace tests, 18
ActionSurface/viewport tests, and 11 Learning Path projector tests.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused Stage 3.4 suites | passed — 62 tests | affine-first authority, batch planning and coordination, shared frozen frame, arbitrary-order association, viewport continuity, and Stage 4 progression |
| `make quick-test` | passed — 377 tests | fast unit/component partition |
| `make journey-test` | passed — 10 tests | sparse calibration, reset, Boundary, drawing, and Stop journeys |
| `make strict-check` | passed — 387 tests | strict concurrency, warnings as errors, signed bundle, launcher validation, and full test suite |
| `git diff --check` | passed | whitespace and conflict markers |

Attended hardware, camera, motion, Pen Down/Up, operator-click, and observed-ink
validation were skipped and remain unproven.

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
still reset the viewport. Its former sparse-mark automatic focus was historical
behavior and is superseded by the Stage 3.4 batch above.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused overlay, viewport, and Identify Pen Cap tests | passed — 46 tests | analyze-cycle retention and stale refusal, Learning visibility, compatible zoom/pan continuity, source/configuration reset, superseded sparse viewport behavior, and frozen-frame overlay identity |
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
- 3.4 one supervised five-circle batch at fixed ±30 mm offsets, with five
  centered 2 mm-radius/16-chord marks capped at 100 mm/min, independent
  Down/Up evidence, settled Pen Up before every inter-circle travel, one final
  X-max/Y-zero-biased reveal, one shared frozen exact frame, arbitrary-order
  clicks with deterministic global assignment, all-five affine-first
  construction, constant construction fallback, diagnostic-only residuals and
  uncertainty, stable operator viewport state, and atomic tip-map commit.

`TipCameraRegistration` maps machine coordinates directly to contact pixels.
Stage 4 consumes its exact revision, selects a 5 mm line that clears persistent
calibration circles, and owns its own local baseline, reveal MPos, drawing
execution, newer post-line frame, and generic ink observation.

The separate tip checkpoint loads quarantined. Same-paper restart uses a fresh
controller/cap frame and no new mark. An actual paper replacement rotates paper
identity and requires current calibration on that paper. Possible ink is keyed
by machine position plus mark radius plus paper identity and survives cancel,
restart, and reset on that paper; it never triggers automatic redraw.

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

The visible Learning Path ends at the one-Go 4.1 observed-line validation. The former
selectable future stage, speculative online model-learning dataset, policy/reward
episode scaffolding, model-mismatch renderer, and model-prediction overlay kind
are deleted. Adaptive requirements remain roadmap-only.

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
| Focused Stage 3.4 and checkpoint tests | passed — 83 tests | 2 mm/16-chord/100 mm/min geometry, far reveal, full configured Down outcome, superseded frozen-frame viewport behavior, Stop blacklist, checkpoint reconstruction, Stage 4 clearance, rebased numerical-zero travel, scoped overlay retention |
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
| Checkpoint restart and paper-plane journey | passed within focused/journey gates | same-paper no-mark restore; legacy changed-paper contact-plane route now superseded by full recalibration |
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
