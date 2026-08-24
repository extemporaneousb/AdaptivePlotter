# Episode Architecture Execution Plan

Status: sole target architecture, migration sequence, and landed-work ledger

This document owns the intended episode architecture and its replacement
sequence. It does not describe current implementation. The current package and
runtime owners remain in [Swift Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md),
product invariants remain in [Product Contract](PRODUCT_CONTRACT.md), and
verified results remain in [Current Evidence](CURRENT_EVIDENCE.md).

No temporary review report, research memo, execution prompt, rejected proposal,
or competing architecture plan is authority. Accepted conclusions must be
integrated here and the source note deleted. Git history and Blackdog prompt
artifacts are history, not current design.

## Decision

Keep one AdaptivePlotter application and the existing controller, camera,
Vision, planning, and evidence authorities. Add a headless episode kernel and
runtime as internal SwiftPM targets, make Plotter their first concrete domain,
and migrate complete workflows by replacement. A cutover is incomplete until
the old action, state, guard, task, effect, and test-fixture path is deleted.

Do not create a second production application or publish a general SDK before
the kernel has survived the three representative Plotter slices, the pilot
gate, and a complete Learning Path migration. A separate SDK remains a later
packaging decision requiring a genuinely distinct second client.

## Vocabulary

- **Goal specification** defines desired outcome constraints, assessment, and
  termination. It is not an action and does not imply reachability.
- **Episode definition** is the immutable bounded-attempt specification: goal,
  initial context, permitted semantic-action grammar, budgets, and assessment.
- **Episode manifest** pins the definition plus domain, reducer, evaluator,
  model, drawing, calibration, environment, and build revisions.
- **Episode state** is the decision-relevant value reconstructed by reducing
  the ordered event history. It is not the trace.
- **Plotter intent** is one operator-, policy-, or system-originated semantic
  request. It says what is requested, not how hardware performs it.
- **Action availability** is a copied pure admitted/refused projection with
  typed requirement results. It is never a capability.
- **Action receipt** is the recorded result of actual submission.
- **Plotter effect** is a typed external request emitted only by the reducer.
- **Effect result** is the typed completion, refusal, cancellation, ambiguity,
  timeout, evidence-unavailable result, or failure returned by an environment.
- **Observation** is a source-, time-, configuration-, and revision-bound
  reading. It is not automatically evidence.
- **Evidence** is an observation or measurement accepted for a declared
  episode, plan, paper, model, or assessment question after provenance and
  applicability validation.
- **Assessment** compares accepted outcome/evidence with the goal criteria.
- **Episode journal** is the ordered semantic event authority for one episode.
- **Episode trace** is an immutable export of journal events and referenced
  transcripts, frames, evidence, and assessment. It is not mutable state.

Do not introduce `EpisodePlan` as a synonym for `EpisodeDefinition`. A separate
episode plan is justified only when it represents a computed, revisable
strategy. `DrawingProgram` remains what is to be drawn;
`ExecutionPlanRevision` remains the embodiment- and calibration-bound drawing
plan. Generic episode code contains no strokes or GRBL primitives.

## Target packages

```text
EpisodeCore
  definitions, manifests, typed decisions, reducer and journal schemas
  Foundation only; no Plotter, device, persistence, or UI imports

EpisodeRuntime -> EpisodeCore
  serialized store, journal/replay, internal effect permission
  effect lanes, operation registry, cancellation and lifetime settlement

PlotterEpisodeModel -> EpisodeCore + PlotterModel
  Plotter intent/state/event/effect/result vocabulary
  scoped semantic rules, reducer, evidence/assessment values, projections

PlotterEpisodeRuntime
  -> EpisodeRuntime + PlotterEpisodeModel + PlotterRuntime
  LIVE and SIMULATED capability providers and effect runners
  controller/camera recording, replay, and artifact adapters

PlotterUI -> PlotterEpisodeModel
  immutable projections and one typed intent sink; no effect ports

PlotterApp
  composition root during and after migration
```

`PlotterModel`, `PlotterRuntime`, and `PlotterTestSupport` remain current
authorities until an explicit work package moves a responsibility. Temporary
bridges must name their deletion package and may not become stable APIs.

## Central semantic ingress

Every effect-bearing or domain-authority-changing operator or policy action
enters through one `PlotterIntentGateway.submit` boundary. Local pane, window,
and viewport-only state remains in small UI reducers unless it changes evidence
or domain authority.

`PlotterIntent` is an exhaustive root sum with scoped cases such as session,
observation, point selection, manual motion, drawing, Learning, and evidence.
The root evaluator delegates to pure feature rule sets and has no `default`.
Rule sets may evaluate named semantic requirements. They cannot mutate state,
call ports, issue execution permission, construct effects, or accept evidence.

The normal submission order is:

1. reserve request identity before suspension;
2. acquire versioned capability facts;
3. recheck state and manifest revisions;
4. evaluate the scoped semantic rules;
5. append a typed accepted or refused event;
6. reduce the committed event into state and typed effects;
7. register effect identity, lane, and internal one-shot permission;
8. record effect start before external invocation;
9. execute outside `MainActor` through the existing environment owner;
10. return a typed result as an event and reduce it.

The UI uses the same pure evaluator to display availability, but submission
always reevaluates current state. Presentation values can never be supplied as
authorization.

## Operation ownership and safety priority

One `PlotterOperationRegistry` owns application-level effect identity, lanes,
Stop capability, cancellation request, original task/handle, and terminal
disposition. It supports at least one exclusive machine lane, one exclusive
exact-workflow capture/Vision lane, bounded background analysis, and serialized
durable append where required. `RunInterpreter` remains the logical machine
operation owner below it.

Cancellation is request, exact-owner validation, one latched cancel request,
owner observation, original-owner await, terminal disposition, and capability
retirement. A stale capability cannot stop a successor.

Normal new effects require committed accepted/start history before external
invocation. Stop and shutdown are a narrow priority path because persistence
must never delay reduction of physical activity. That path may only close
admission, cancel, or settle existing work; it latches the exact owner before
suspension, issues cancellation without waiting for journal I/O, and can never
start or repeat a physical effect. Journal failure degrades trace completeness
but cannot block Stop.

## Guard ownership

Every guard has exactly one owner within its layer:

| Layer | Owner | Examples |
| --- | --- | --- |
| semantic workflow | scoped evaluator | phase, episode owner, prerequisite, no-redraw, plan revision |
| runtime coordination | store and operation registry | lane occupancy, deduplication, cancellation, stale result, terminality |
| fresh physical safety | `MachineController` and `RunInterpreter` | connection, Alarm/Pn/Idle/MPos, Motion, feed, pen, wire settlement |
| evidence and provenance | existing typed evidence authorities | frame/config/hash, pose, applicability, algorithm/model revision |
| presentation | projector or local UI reducer | layout, label, visibility, exact-frame display |
| lifetime priority | runtime Stop/shutdown route | close admission, cancel/await owner, reject stale commits |

Semantic rules consume versioned device/evidence facts. They do not recreate
the controller's safety algorithm or the evidence authority's applicability
algorithm. Rechecking across layers is intentional only when the question and
owner differ: current semantic readiness versus fresh safety immediately before
I/O.

## Non-negotiable observability

Observability is product behavior, not optional debug instrumentation.

1. Every refused semantic action exposes a typed requirement ID, authoritative
   owner, compared source/state revisions, concise operator remedy, and the
   action request identity. No effect-bearing control silently ignores a click.
2. Every active effect exposes episode/action/effect identity, lane, environment,
   owning subsystem, phase, start time, last attributable progress time, the
   result currently awaited, declared deadline when one exists, cancellation
   availability and phase, and eventual terminal disposition.
3. Progress is evidence of an attributable event, not a fabricated heartbeat.
   The UI distinguishes `waiting`, `progressing`, `cancelling`, `settling`,
   `suspectedStall`, and terminal state without claiming a deadlock merely from
   elapsed time.
4. Every reachable nonterminal state has at least one admissible action, an
   explicitly owned wait/progress state, an exact refusal with remedy, or an
   owner-bound Stop/cancel. A silent actionless state fails tests.
5. Runtime state revision and UI projection revision/timestamps are visible and
   comparable. Runtime progress with a stale UI projection identifies a
   presentation/MainActor problem rather than a controller deadlock.
6. Journal, controller transcript, camera lifecycle, and structured diagnostic
   recording run outside `MainActor`. If SwiftUI is starved, the last durable
   runtime state remains externally inspectable.
7. The operator can export one bounded incident package containing the episode
   manifest/journal, controller transcript completeness, camera/frame artifact
   references, observations, evidence decisions, assessment, current owners,
   UI/runtime revisions, and unresolved ambiguity. Sensitive frame retention is
   explicit and bounded.
8. Recording failure is visible and degrades diagnostic completeness, but it
   never authorizes work, changes controller safety, manufactures evidence, or
   delays Stop/shutdown.

The primary UI should show the current reason, owner, progress, remedy, and Stop
without forcing the operator through a developer console. A detailed inspector
and export may carry identifiers and revisions. Structured logs and the journal
remain the fallback when the UI itself cannot render.

## Replay and simulation

The episode manifest pins definition, schemas, evaluator/reducer/build revisions,
seed, and referenced drawing, calibration, paper, camera, controller, and model
artifacts. Each event records sequence, actor/origin, causation/correlation,
action/effect IDs, pre/post revisions, typed payload, artifact references, and a
canonical post-state digest.

Replay begins from the manifest, folds the production reducer, verifies hashes
and revisions, recomputes projection/availability, and executes no effect. Every
truncated prefix is tested. A trace ending after physical effect start but before
settlement becomes possible physical effect and is never automatically resumed.

`RecordingMachineLink` records invocation and completion separately for open,
close, discard, raw writes, and timed reads, including exact chunks, parameters,
typed errors, partial counts, monotonic offsets, integrity, and completeness.
`ReplayMachineLink` supports exact replay and causality-preserving perturbation
of legal fragmentation, delay, timeout, and cancellation points.

Camera recording binds lifecycle events separately from content-addressed exact
frame artifacts. Retention is explicitly evidence-only, bounded incident ring,
or bounded diagnostic capture. Missing frame bytes remain visible and cannot
pretend to support Vision replay.

LIVE and SIMULATED implement the same effect/result vocabulary while preserving
different provenance and evidence classes. The simulator separates commanded
controller state, plant/pen truth, paper/ink truth, camera observation, and
Vision measurement. Simulation can never satisfy LIVE physical evidence.

## Same-landing deletion rule

Every migrated slice must remove or explicitly prove a remaining unmigrated
consumer for each of the following:

- old root action case and dispatcher branch;
- old `...UnavailableReason` and handler guard for migrated semantics;
- old mutable workflow/workspace field;
- old task, generation, latch, and Stop/cancel owner;
- old direct controller/camera/Vision/persistence port call;
- old LIVE/SIMULATED workflow branch;
- old high-level fixture or polling helper after its last consumer;
- obsolete current documentation and tests.

A new path working beside the old path is not migration. Shadow comparison may
observe and report, but may issue no effect or authoritative durable write.

## Structural enforcement

- migrated UI targets cannot import effect runtime or see raw effect ports;
- the gateway is the only public effect-bearing/domain mutation entry;
- root intent switches are exhaustive without `default`;
- requirement IDs are typed and map to one declared owner;
- evaluators cannot emit effects or issue runtime permission;
- the reducer is the sole effect producer;
- the registry is the sole application effect/Stop/cancellation owner;
- results require matching episode/action/effect/environment revisions;
- UI availability cannot be resubmitted as authority;
- episode layers add no `Any`, arbitrary effect closures, reflected/string action
  registries, or `@unchecked Sendable` escape hatches;
- each cutover adds deleted-symbol, forbidden-import, and direct-port-call checks.

## Work ledger

Blackdog owns active task state. This table records only not-started work,
explicit blockers, and landed completion. Never mark a row active here.

| ID | Status | Dependencies | Atomic outcome |
| --- | --- | --- | --- |
| DOC-00 | complete | none | Canonical docs, observability contract, work ledger, and continuation skill landed in `TASK-C86132F1` |
| BASE-00 | pending | DOC-00 | Rebuild exact current `main`, complete attended known-good Learning Path, record evidence, and push an annotated baseline tag |
| EA-01 | pending | BASE-00 | Inventory every action/guard/owner/port/mode branch and assign retain/adapt/delete plus one authority layer |
| EA-02 | pending | EA-01 | Compile-only generic kernel spike; fall back to concrete Plotter types if clean Swift typing fails |
| EA-03 | pending | EA-02 | Atomic store, durable journal/replay, effect lanes, single operation registry, and Stop/shutdown priority contract |
| EA-04 | pending | EA-03 | Exact-frame human point-selection slice with stale refusal, observation/evidence, projection, and old-path deletion |
| EA-05 | pending | EA-03 | Lossless controller/camera recording, exact/perturbed replay, content-addressed artifacts, and incident export foundation |
| EA-06 | pending | EA-04, EA-05 | Manual motion and exact owner-bound Stop through LIVE/SIMULATED adapters; delete old manual authority |
| EA-07 | pending | EA-06 | Causal environment adapter with shared semantic vocabulary and distinct evidence classes |
| EA-08 | pending | EA-05, EA-07 | Drawing Studio draft and run as reducer-visible plan/capture/execute/observe/evidence/assess stages |
| EA-09 | pending | EA-04, EA-06, EA-08 | Bounded reachability, UI compiler boundary, actionability invariants, runtime/UI revision diagnostics |
| GATE-01 | pending | EA-09 | Pilot continuation decision using deletion, replay, typing, owner, observability, and physical-boundary evidence |
| EA-10 | pending | GATE-01 | Migrate Pen Interaction, Boundary, camera/tip calibration, Drawing Trial, redo/replacement, artifacts, and reset by family |
| EA-11 | pending | EA-10 | Remove remaining workspace effect closures/owners, finish UI composition, validate complete journey, and decide SDK packaging |

## Package completion contract

Every package records in its Blackdog prompt and landing:

1. exact scope and dependencies;
2. current owners and preserved behavior;
3. intended authority transfer;
4. observability requirements affected;
5. same-landing deletion ledger;
6. focused, replay, simulation, UI, repository, and physical validation classes;
7. Current Evidence update with passed, failed, or skipped claims;
8. this ledger's landed status update.

Validation runs serially when SwiftPM shares `.build`. Software, replay, and
simulation never prove attended controller, camera, motion, pen, paper,
operator-click, or observed-ink behavior.

## Pilot continuation gate

Continue past `GATE-01` only when:

- generic code required no forbidden type-erasure or concurrency escape hatch,
  or the documented concrete Plotter fallback cleanly satisfies the contracts;
- replay reconstructs canonical state, projection, and availability without
  executing effects;
- captured device traffic reaches production controller/camera owners;
- LIVE and SIMULATED share semantic grammar without equating evidence;
- migrated slices have zero old entrypoints, guards, task/Stop owners, and
  direct ports;
- independently authored admission sites, workspace task owners, mode branches,
  and direct effect calls decreased;
- every observability non-negotiable has deterministic coverage and an operator
  presentation or external fallback;
- `OperatorWorkspace` lost policy/state instead of accumulating adapters;
- physical safety owners and evidence-class boundaries remain intact.

If clean genericity fails, use concrete Plotter types. If same-slice deletion,
device-owner preservation, deterministic replay, or truthful observability
fails, stop rather than maintain dual authority.

## Final validation matrix

| Concern | Required evidence |
| --- | --- |
| state and action correctness | pure reducer cases plus bounded reachability |
| refusal and lock observability | typed owner/revision/remedy, effect progress, UI/runtime revision, stalled-prefix tests |
| episodic memory | durable manifest/event replay, every prefix, corruption and schema tests |
| controller communication | exact and perturbed link replay through production owners |
| camera lifecycle and video | lifecycle replay plus exact frame artifacts where retained |
| physical causality and faults | controller/plant/pen/paper/camera/Vision causal simulation |
| UI actionability | every reached state renders action, wait/progress, remedy, or exact Stop/cancel |
| actual hardware and ink | explicitly attended runbook evidence only |
