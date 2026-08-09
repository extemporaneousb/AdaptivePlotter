# AdaptivePlotter Coordinated Learning Workbench Implementation

Status: retained implementation and acceptance record for completed Work item 7.
Statements below that describe outgoing source identify the surfaces this
increment removed; they are not endorsements of current behavior.

The stage 3/4 vocabulary and one-side/anchor-dot workflow frozen in this
historical prompt were superseded on 2026-08-09 by
[Visibility Target and Clear-View Protocol](VISIBILITY_TARGET_AND_CLEAR_VIEW_PROTOCOL.md).
They remain below only as the exact execution record for the earlier landed
increment. Current product behavior and new implementation work must follow the
new protocol and canonical documents, not the older visible-journey section.

You are the coordinating implementation agent for
`/Users/bullard/Projects/AdaptivePlotter`. This is an execution request, not a
request to stop after analysis, a proposal, or a mock-up. Plan the work, freeze
the shared contracts, allocate non-overlapping lanes, implement every lane,
integrate the result, delete the superseded implementation, run the required
validation, and land the completed change into the Blackdog-selected target
branch.

## Required working method

1. Read `AGENTS.md`, the repo-local AdaptivePlotter skill, `README.md`, and all
   four routed canonical documents before editing:
   - `docs/FEASIBILITY_REVIEW_AND_BINDING_AMENDMENTS.md`
   - `docs/PROJECT_SCOPE_AND_MODEL_TRAINING.md`
   - `docs/SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md`
   - `docs/SWIFT_ADAPTIVE_PLOTTER_SEQUENTIAL_REBUILD.md`
2. Use one supervisor-owned Blackdog task and its returned task worktree. The
   coordinator alone begins, lands, closes, and cleans the task. Workers share
   that task workspace; they do not create Blackdog tasks, branches, worktrees,
   commits, PRs, or landings.
3. Inspect the current code and tests before assigning files. Publish a concise
   implementation plan, exact file ownership, frozen shared types/API seams,
   dependency edges, and validation matrix. Then dispatch exactly three workers
   in parallel. Planning is the first phase of execution, not the deliverable.
4. Give every file one owner. A worker may inspect any file but may edit only
   its frozen lane. Shared-seam changes belong to the named owner or the
   coordinator. Workers must report a contract concern instead of editing
   another lane.
5. The coordinator remains responsible for integration, missing work, conflict
   resolution, full validation, deletion audits, documentation truthfulness,
   and Blackdog landing. Do not accept a compile-only or worker-handoff result
   as completion.
6. Preserve unrelated user changes. Do not kill user-owned processes, launch a
   raw SwiftPM executable for physical QA, or claim camera, controller, audible,
   pen-pose, movement, or ink evidence that was not directly observed.

## Product outcome

Deliver one coherent camera-first operating surface in exactly one singleton
macOS application window. The operator must be able to navigate and perform the
Learning Path without opening a second window or losing the video.

The stable main frame has three user-resizable vertical regions:

1. a left Learning Path navigator containing the big picture and exact numbered
   stage/step order;
2. an always-mounted center camera/action surface that remains the largest
   protected region;
3. a right selected-exercise detail containing instructions, evidence,
   questions, and a pinned action strip.

Use canonical macOS SwiftUI structure. Prefer a native `HSplitView` when
adaptive `NavigationSplitView` collapse could remove the camera; use
`NavigationSplitView` only if tests prove the center camera remains structurally
mounted and visible at the supported widths. An optional native inspector may
hold Motion, Camera, Overlay, and real diagnostics, but it must collapse before
the camera is starved. Do not recreate the outgoing fixed dock allocator with
new names.

The toolbar retains only global controller/session controls and compact truthful
status: controller selection, Connect/Disconnect, Enable Motion, and status.
Exercise Stop does not belong in the toolbar.

## Frozen visible journey

Keep this exact order and vocabulary:

1. Connect
2. Enable Motion
3. Human-Guided Discovery
   - 3.1 Pen Interaction
   - 3.2 Boundary Discovery
   - 3.3 Clear-View Discovery
4. Observed Drawing Trials
   - 4.1 Capture Clean Reference
   - 4.2 Choose Line Start
   - 4.3 Create Anchor Mark
   - 4.4 Draw Isolated Line
   - 4.5 Clear Tool and Observe Ink
   - 4.6 Compare Intended and Observed Geometry
5. Adaptive Drawing

Keep Complete, Current, Next, Future, and Needs Attention. Do not add a global
percentage, a wizard, calibration/readiness/preflight terminology, a second
start ceremony, or a learning-completion motion gate.

Clicking a navigator row changes selection only. It must not start, advance,
redo, cancel, authorize, invalidate, or make a machine request. The real current
runtime step remains visibly marked while another row is reviewed, and Return
to Current restores its selection. A future row has no action controls. A
completed repeatable row may expose an explicit Redo This Step or Record Another
Attempt action; the click itself remains inert.

## Exercise presentation and actions

Recover the useful hierarchy of the earlier exercise presentation—focused
question/instruction card, current timeline position, expected observation, and
prominent choices—without restoring its obsolete workflow model.

Use structured presentation fragments for critical cues. UP, DOWN, YES, NO,
STOP, and typed directions must be visually emphasized and accessible values,
not words found by searching an arbitrary prose string.

The pinned exercise action strip is the only exercise-control location:

- Start is green and appears when the selected current exercise can begin.
- Once started, Start is replaced by the runtime's typed YES/NO or other choice
  controls when a choice is awaited.
- Cancel is red and is available for a live exercise attempt. It is an attempt
  disposition, not successful Boundary Stop.
- Stop is red and enabled only while the runtime exposes one stoppable motion
  owner. There is exactly one visible Stop and one mechanical cancel route.
- Restart appears only after the stopped, cancelled, or failed attempt has
  settled and the runtime has a typed restart route. It creates a new attempt;
  it never resends an ambiguous write.
- Redo This Step is an explicit action on an accepted completed step. It runs a
  replacement attempt with the semantics below.
- Record Another Attempt is available only for a repeatable step with a defined
  typed aggregate. It does not mean Redo.

Browsing a noncurrent row must never replace or duplicate the interactive
current-action owner. Keep exactly one machine-interactive action strip.

## Redo, dependency, and attempt semantics

Implement typed artifact revisions and explicit data-dependency edges. Visible
sequence order defines normal performance order; it is not the invalidation
graph.

Redo This Step runs a replacement attempt. When the replacement succeeds,
commit it atomically as the accepted artifact, mark the old accepted artifact
superseded and exclude it from current derived values, then invalidate only the
transitive artifacts that explicitly consumed the replaced revision. A failed,
cancelled, refused, or ambiguous replacement does not silently create a new
accepted value or physical evidence.

At minimum prove these dependency behaviors:

- Redoing Pen Interaction does not discard independent boundary observations
  merely because 3.2 follows 3.1. Current Pen Up may still be required for a
  new movement.
- Replacing an accepted Clear pose invalidates drawing-trial artifacts that
  explicitly consumed that pose, not unrelated boundary evidence.
- Replacing a clean reference invalidates the anchor/post-frame/ink/residual/
  comparison artifacts in the trial that consumed that reference.
- Replacing one boundary-side observation invalidates only posteriors and
  derived associations that reference that revision.

Record Another Attempt preserves the compatible attempt history and recomputes
the declared aggregate from all valid included attempts. Every aggregate exposes
valid sample count `N`, estimator/revision identity, and uncertainty or typed
categorical counts as applicable.

- Numeric and geometric measurements use a declared estimator and uncertainty.
- Categorical observations use counts, proportions, or a typed posterior.
- Current state such as observed pen pose uses the latest accepted observation.
- Exact frames, controller events, strings, identifiers, refusals, and ambiguity
  remain individual provenance and are never arithmetically averaged.
- Camera configuration, coordinate space, units, direction/group identity, and
  algorithm revision define compatibility. Do not silently pool incompatible
  attempts.
- An unclear, refused, cancelled, or ambiguous attempt remains recorded with
  its disposition but is excluded from a successful-value aggregate.

Do not implement a global workflow store, persistent replay, a generic evidence
bag, or a view-owned cache of eligibility/completion. Runtime facts remain the
authority; views directly project them.

## Remove Jog Observations completely

The current `JOG OBSERVATIONS` / `Record Jog Observations` surface is a separate
diagnostic/model-fitting workflow, not a Learning Path exercise. Remove it; do
not sweep it into the new UI, put it in the inspector, hide it, or rename it
Record Another Attempt.

Audit and delete the observed-jog-specific family across:

- `Sources/PlotterApp/AdaptivePlotterApp.swift`
- `Sources/PlotterApp/OperatorWorkspace.swift`
- `Sources/PlotterApp/PassiveProbeComposition.swift`
- `Sources/PlotterRuntime/OnlineJogResponseDataset.swift`
- `Sources/PlotterRuntime/RunInterpreter.swift`
- `Tests/PlotterRuntimeTests/OnlineJogResponseDatasetTests.swift`
- the observed-jog cases in app/runtime tests and canonical documentation.

Remove `requestObservedJog`, observed-jog workspace fields/presentations,
`ContextualStopTarget.observedJog`, online jog-response dataset/model state, and
their dedicated tests when their consumers are deleted. Preserve only genuinely
generic controller/camera primitives that still have a named non-observed-jog
consumer. There must be no dormant compatibility type, dead test fixture,
hidden action, or stale documentation for the removed workflow.

Record Another Attempt must use the new typed per-exercise attempt model. It may
not wrap the old online jog dataset.

## Fix Boundary Discovery motion ownership

The current source has `MotionPriors.boundarySearchXDistanceMM = 300.0` and
`boundarySearchYDistanceMM = 150.0`. `makeBoundaryJogRequest` creates one finite
`RelativeJogRequest`, and `executeBoundaryMotion` fails when that request
completes before Stop. This is not the required product behavior.

Replace those application-selected completion horizons with one typed logical
Boundary Discovery motion owner. From the operator's perspective it continues
until:

1. the operator presses the exercise action strip Stop; or
2. the controller reports a real terminal condition such as an asserted limit,
   alarm, refusal, disconnect, or fault.

The only successful boundary path remains:

```text
typed operator Stop event
-> close further boundary-motion admission/renewal
-> one Jog Cancel byte
-> await the original logical owner through Idle and final MPos
-> set the post-settlement freshness boundary
-> capture one strictly newer exact frame
-> measure the selected side
-> update the posterior/artifact
-> complete the attempt
```

GRBL `$J` is finite. Implement that protocol fact below a typed
operator-stopped boundary operation. If finite segments are required, an
unambiguously completed segment may renew under the same logical owner. Renewal
must recheck the same direct controller facts, never create a successful
boundary, and never open a second owner. Stop must latch before deciding whether
to renew so a Stop/segment-completion race cannot emit another motion command.
An ambiguous segment is sticky and is never renewed or resent. A real limit,
alarm, refusal, disconnect, or fault ends the attempt as Needs Attention and
creates no boundary evidence. Natural segment completion is not a successful
exercise result.

Do not remove controller checks, the one-operation invariant, limit/alarm
handling, typed finite wire requests, bounded polling, or sticky ambiguity in
the name of continuous behavior. Do not add an entered workspace envelope,
homing, unlock, reset, firmware writes, an arbitrary view timer, or an inferred
machine boundary.

Cancel during Boundary Discovery may share the one mechanical cancel/settle
primitive, but records a cancelled attempt and no `operatorStopRequested`
success, side measurement, posterior update, or sequence advance. Shutdown also
settles the same owner once without racing Stop or renewal.

## Superseded UI/source/test removal

Delete, rather than deprecate or alias:

- the auxiliary Learning Path scene/window and its identifier;
- `openWindow` use and the Open Learning Path action;
- the fixed custom `WorkbenchLayout` dock-allocation model and panel launcher
  chrome when no target consumer remains;
- the toolbar exercise Stop and duplicate cancellation affordances;
- the standalone Jog Observations UI and observed-jog runtime/model family;
- outgoing learning/preflight/exploration compatibility names and dead routes;
- tests whose only purpose is to freeze the deleted fixed dock/window/source
  structure.

Do not delete valuable behavior tests before deleting their active production
behavior. Delete feature code and its dedicated tests atomically, then add tests
for the replacement behavior. Avoid source-text parsing tests for positive UI
wiring. A bounded stale-surface `rg` audit is validation, not an invitation to
add unrelated global repository guards.

## Direct authority constraints

Do not let any worker “improve safety” by adding a learning-stage prerequisite,
new readiness gate, arbitrary maximum distance, camera requirement for ordinary
manual jog, boundary-count requirement, Clear-pose requirement for unrelated
motion, model-confidence gate, or duplicated controller state machine.

The only mechanical guards are the existing direct facts at their proper
owners: selected responsive controller session, current internal Enable Motion
authorization, recognized non-alarm state, relevant pins/limits, known position
where needed, typed finite command values, applicable feed, commanded pen state,
one operation owner, and no sticky ambiguity. New local checks are allowed only
where the operation actually consumes that evidence and must be implemented at
the authoritative owner, not scattered through views.

Do not add repository checks, policy, persistence, compatibility layers, DTO
mirrors, or unrelated refactors outside this contract. Workers do not moonlight.

## Three frozen lanes

After the coordinator's initial audit, freeze exact files around these lanes.
Adjust a filename only before dispatch when the live dependency graph requires
it; never allow overlapping edits after dispatch.

### Worker 1 — macOS workbench and Learning Path presentation

Own the SwiftUI scene/root/navigation/detail/action-strip refactor and its pure
presentation/layout tests. This lane removes the second Learning Path window,
Open Learning Path action, fixed dock UI, toolbar Stop, and Jog Observations
controls. It consumes coordinator-frozen `OperatorWorkspace` presentation and
actions without inventing runtime state. It must preserve the camera surface and
XY jog ergonomics.

Likely files include `AdaptivePlotterApp.swift`, `WorkbenchTopBar.swift`,
`WorkbenchLayout.swift`, `LearningPathView.swift`,
`LearningPathPresentation.swift`, and their PlotterApp presentation/layout
tests. Worker 1 does not edit `OperatorWorkspace.swift` or runtime files.

### Worker 2 — runtime attempts, dependencies, boundary owner, and model deletion

Own typed artifact revisions, explicit dependency invalidation, attempt groups,
type-specific aggregates, the operator-stopped Boundary Discovery runtime, and
the deletion of observed-jog-specific PlotterRuntime types/models/tests. Preserve
MachineController's direct checks, typed wire encoding, one-operation ownership,
bounded settlement, and sticky ambiguity.

Likely files include the relevant PlotterRuntime model/operation files,
`HumanGuidedDiscovery.swift`, `RunInterpreter.swift`,
`OnlineJogResponseDataset.swift`, and PlotterRuntime tests. Worker 2 does not
edit SwiftUI or `OperatorWorkspace.swift`.

### Worker 3 — workspace orchestration and app/runtime seam

Own `OperatorWorkspace` integration of the frozen runtime types with the frozen
presentation contract: selection-independent current action, Start/choice/
Cancel/Stop/Restart/Redo/Record Another Attempt routing, atomic replacement,
unavailable reasons, one-cancel settlement, boundary owner continuation, and
observed-jog removal. Own composition changes such as
`PassiveProbeComposition.swift` and focused `OperatorWorkspaceTests`.

Worker 3 does not edit Worker 1's views or Worker 2's runtime types. If a frozen
seam proves insufficient, report the exact type/signature problem to the
coordinator and wait for a coordinator-approved seam revision.

## Coordinator-owned integration

The coordinator owns the shared contract, Package manifest changes, canonical
documentation reconciliation, repository check scripts if genuinely required,
full validation, stale-surface audit, signed-bundle QA, commit, and Blackdog
landing. The coordinator must review every worker diff for authority drift,
duplicate types, compatibility leftovers, and out-of-lane edits before accepting
it.

Require each worker to hand off:

1. behavior delivered;
2. exact files changed;
3. exact files/types/tests deleted or replaced;
4. superseded surfaces removed;
5. commands and results;
6. skipped validation;
7. residual concerns;
8. scope confirmation;
9. authority confirmation.

Workers must not claim physical results or landing.

## Required automated acceptance

Add focused deterministic tests before the broad suite.

### Presentation and layout

- Exactly one singleton `Window`; no auxiliary Learning Path scene,
  `openWindow`, Open Learning Path action, or standalone Jog Observations UI.
- The exact stages, 3.1–3.3, and 4.1–4.6 retain their order and statuses.
- Navigator selection alone changes no workspace stage, transaction, artifact,
  dependency, attempt count, or machine-action count.
- Return to Current restores selection only.
- A future row has no actions; a completed row's explicit Redo/another-attempt
  action is distinct from selecting it.
- Exactly one interactive exercise action strip and one visible contextual Stop;
  toolbar Stop is absent.
- Start/choice/Cancel/Stop/Restart transitions project runtime state and exact
  unavailable reasons.
- Critical cues are typed/structured and have accessible emphasis.
- Camera is structurally outside selection conditionals and remains allocated at
  the repository's minimum window width, 1440 points, and a wide/full-screen
  case. The camera retains at least the frozen minimum; optional inspector/side
  regions collapse or scroll before overlapping it.

Prefer pure selection/action/layout policy tests and normal SwiftUI compilation.
Do not assert implementation by reading Swift source strings except for the
coordinator's bounded final stale-surface audit.

### Redo and attempt data

- Atomic replacement makes the new successful artifact current and marks the
  old one superseded.
- Failed/cancelled/ambiguous replacement does not manufacture a current result.
- Dependency invalidation is transitive over declared edges only.
- Redo Pen Interaction retains independent boundary observations.
- Redo Clear pose invalidates only consuming trial artifacts.
- Redo clean reference invalidates its consuming trial chain.
- Two-attempt and N-attempt aggregates expose `N`, estimator/revision,
  uncertainty or categorical counts, and included attempt IDs.
- Incompatible configuration/coordinates/units/algorithm revisions are not
  pooled.
- Refused/unclear/cancelled/ambiguous attempts remain provenance but are excluded
  from successful aggregates.
- Current-state facts use the latest accepted observation, not an average.

### Boundary motion, Stop, Cancel, and shutdown

- The hard-coded 300/150 mm application horizons and their presentation are
  absent.
- Unambiguous finite segment completion keeps the same logical Boundary
  Discovery owner active and emits no boundary evidence.
- Stop before segment completion emits one cancel, waits for the original owner,
  captures a strictly newer frame, and records one boundary result.
- A deterministic Stop-versus-segment-completion race proves the Stop latch
  prevents a renewal write and still emits at most one cancel.
- Repeated Stop emits no duplicate cancel.
- Cancel during boundary motion settles once but records no successful Stop
  event, side measurement, posterior, or progression.
- Limit/alarm/refusal/disconnect/fault produces Needs Attention and no boundary.
- Ambiguous accepted motion never renews or resends.
- Shutdown during active boundary motion closes renewal, settles once, and
  creates no boundary success.
- Manual and drawing Stop behavior remains correct.

### Deletion and regression

- No observed-jog-specific UI, workspace action/state, Stop target, online
  dataset/model, fixture, test, or canonical endorsement remains.
- Existing controller parsing, direct motion admission, feed selection,
  exact-frame freshness, drawing no-redraw, simulator isolation, speech queue,
  launcher identity, and one-instance behavior remain green.
- The stale-surface audit covers the exact removed names only. It must not become
  a new general workflow authority or a collection of speculative guards.

## Required validation and evidence report

Run the narrowest relevant tests throughout integration, then from the task
workspace run at least:

```sh
git diff --check
swift build --target PlotterApp
make build
make test
make check
make strict-check
make app
```

Run the focused presentation, OperatorWorkspace, HumanGuidedDiscovery,
MachineController/RunInterpreter boundary-motion, dependency, aggregation,
simulator, launcher, and bundle tests explicitly so failures are attributable.

Perform a final tracked-source audit with `rg` for the deleted scene/window,
Open Learning Path, fixed dock, toolbar Stop, Jog Observations,
`requestObservedJog`, `OnlineJogResponseDataset`, observed-jog target, and the
300/150 boundary-search constants. Interpret matches; removal-language in
canonical docs is allowed, active/compatibility code is not.

For signed launch validation, follow the repository launcher contract. Inspect
processes first, never kill an unknown/user-owned process, never force a new
instance, and do not use the raw executable. If safe attended live launch is not
available, mark it skipped rather than inventing evidence. Physical camera,
serial, motion, pen, audible speech, and ink validation are separate and may be
skipped unless the operator is present with the cutoff reachable.

Before landing, confirm the task branch, exact diff, and dirty state. Supply
Blackdog a truthful completion summary and named passed/failed/skipped
validations. Follow every structured `next_action` exactly until the task is
landed and complete. Verify the Blackdog-selected target branch contains the
landed commit and is clean.

## Done condition

Do not stop until all requested source, tests, UI, runtime behavior, deletions,
documentation, integration, broad checks, and landing are complete, or until a
real external blocker prevents progress and is reported with exact evidence.

The result is incomplete if it is only a plan, mock-up, view refactor, runtime
refactor, compile pass, worker branch, unlanded task, or compatibility layer. The
final report must state what landed, exact automated results, exact deletions,
and which physical evidence classes remain unverified.
