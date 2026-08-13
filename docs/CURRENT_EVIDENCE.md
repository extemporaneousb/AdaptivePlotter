# AdaptivePlotter Current Evidence

Status: current evidence ledger; updated for the sparse human-click replacement

This document records what was actually verified. Product meaning belongs to
[Product Contract](PRODUCT_CONTRACT.md), package ownership to
[Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md), and the physical
procedure to [Attended Hardware Runbook](ATTENDED_HARDWARE_RUNBOOK.md).

## Implemented software surface

The current source contains exactly two post-Boundary calibration exercises:

- 3.3 five-cap machine-to-visible-cap registration with three fit samples and
  two sealed holdouts;
- 3.4 five centered 2 mm-radius, 16-chord circular-mark observations capped at
  100 mm/min and using the full fixed Pen Down profile, far safe X-max/Y-zero-biased Pen-Up reveal,
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

## Video Settings and direct overlay analysis

Validated 2026-08-12 in Blackdog task `TASK-AC50EDC1`, targeting `main` from
base `9a68ff7d4e90fcd3f07de4fcd2c8e9f8e3664720`.

The former Utilities Camera/Overlays tabs and Analyze/Resume action are deleted.
Video Settings owns camera selection plus adjacent Refresh, 2/5/10 frames-per-
second scene cadence, zoom/drag camera-pixel region readout and lock, and one
three-column grid of direct overlay toggles. Selected cap, measured-frame-side,
drawing-frame, or armature layers keep newest-only scene analysis running.
During each computation, preview publication is held and the visible frame is
dimmed while raw capture continues. A locked region bounds every generic scene
pixel scan without changing whole-frame identity or overlay coordinates.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused ActionSurface, panel, workspace, pipeline, and frame/Vision tests | passed — 65 tests | drag/zoom clamp, region lock, overlay-owned analysis, cadence, preview activity, exact overlay identity, bounded scans |
| `make quick-test` | passed — 322 tests | fast unit/component partition |
| `make journey-test` | passed — 10 tests | retained sparse-circle, checkpoint, Stage 4, Boundary, reset, and simulator journeys |
| `make strict-check` | passed — 332 tests | complete concurrency, warnings-as-errors, signed bundle and launcher validation, full test suite, repository checks |
| obsolete-surface scan | passed | no Utilities labels, Camera/Overlays tab types, CameraUtility actions, Analyze Current Frame, or Resume Preview symbols remain |
| `git diff --check` | passed | whitespace/conflict markers |

These are software and simulated-workflow results. The app was not launched for
this change. No attended camera, controller, motion, pen, green-cap detection,
armature detection, preview behavior, or observed-ink validation was performed.

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
