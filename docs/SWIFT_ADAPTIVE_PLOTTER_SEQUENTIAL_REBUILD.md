# AdaptivePlotter Direct Implementation Plan

Status: integrated baseline plus remaining delivery order

## Fixed product contract

AdaptivePlotter remains one native Swift process with one controller owner, one
camera owner, one observable workspace, and one signed application identity.
The Learning Path is presentation; direct machine facts remain authority.

The visible order is fixed:

1. Connect
2. Enable Motion
3. Human-Guided Discovery
4. Observed Drawing Trials
5. Adaptive Drawing

Buttons own all choices, labels, progression, assessment, and Stop. Spoken
announcements are output-only and advisory. Ordinary manual motion never depends
on Learning Path completion.

## Working method

Each increment must:

1. preserve typed controller and evidence boundaries;
2. implement source, tests, UI, and canonical documentation together;
3. delete superseded surfaces instead of retaining aliases;
4. run focused tests, then `make build`, `make test`, `make check`, and
   `make strict-check`;
5. separate automated, simulator, controller, camera, human, and ink evidence;
6. land through one supervisor-owned Blackdog task.

Physical work requires an operator with the cutoff reachable. Otherwise the
physical portion is explicitly skipped.

## Implemented foundation

The following foundation is present:

- native package/module boundaries;
- immutable exact frames and camera configuration identity;
- camera-first aspect-fit rendering for LIVE and SIMULATED sources;
- bounded preview and automatic analysis;
- one persistent controller session with typed passive inspection;
- typed bounded relative jog, pen actuation, drawing stroke, and Jog Cancel;
- controller `ok` versus Idle/final-MPos distinction;
- sticky ambiguity and no automatic resend/redraw;
- internal `MotionGuard` with one visible Enable Motion action;
- armature visibility evidence and isolated-ink observation;
- stable local signing and LaunchServices bundle launch;
- exact-instance activation and raw-process refusal.

## Work item 1 — Learning Path sequence model — implemented

The UI presents one numbered path with Complete, Current, Next, Future, and
Needs Attention. It retains completed rows, uses one current action panel, shows
participant/action/expected observation, and displays runtime-owned disabled
reasons.

There is no global percentage, arbitrary stage tab order, second start ceremony,
or duplicate open action. Adaptive Drawing remains Future.

The Learning Path now lives in the singleton camera-first window. Its navigator,
always-mounted camera, and exercise detail use native resizable regions, and the
one contextual Stop lives only in the pinned exercise action strip.

## Work item 2 — Human-Guided Discovery — implemented in software

### Pen Interaction

The sequence asks for explicit physical Up, authorization to lower, observed
Down, and final observed Up. Announcements precede lower/raise. Controller state
and human physical observation remain separate.

### Boundary Discovery

A typed direction maps to one operator-stopped Pen Up boundary-motion owner.
Stop records its event before one cancel, awaits the original owner through
Idle/final MPos, captures a strictly newer exact frame, updates a side posterior,
and advances. One relevant side is sufficient for the current path; other sides
remain optional.

Boundary motion remains one logical attempt until operator Stop or a real
controller limit, alarm, disconnect, or fault. Finite GRBL segments continue
only after unambiguous completion, with Stop closing renewal first; a segment
completion never becomes boundary evidence and ambiguity is never resent. There
is no application-selected completion horizon.

### Clear-View Discovery

The operator labels an exact frame Blocked, Partial, or Clear. Accept is disabled
until the current runtime observation is Clear. The accepted pose is local
evidence for vision-consuming travel, not manual-motion authority.

Automated behavior is complete. The integrated physical sequence still needs an
attended run.

## Work item 3 — Unified Stop runtime — implemented in software

One typed Stop route covers boundary, manual, and drawing targets. The former
observed-jog target and standalone diagnostic workflow are absent. A target
latch prevents repeated cancel bytes. Manual cancellation creates no boundary
evidence. Its only visual control is in the persistent exercise action strip
without duplicating the runtime route.

Shutdown closes new admission, settles a latched motion once, then drains and
disconnects. Regression coverage includes the former boundary-stall path and
active-boundary shutdown.

## Work item 4 — Output-only announcements — implemented in software

The native announcement queue is serialized, completion-aware, bounded, and
identity-safe against late delegate callbacks. Visible cues and typed button
actions remain authoritative. Output failure is recorded but advisory.

The product contains no audio-input ownership, recognition permission,
transcript stream, ambient parser, or speech-owned workflow lifetime. Audible
native output remains to be verified interactively.

## Work item 5 — Controller-ceiling Pen Up travel — implemented in software

Passive controller inspection exposes X/Y feed limits read-only. Non-drawing
Pen Up movement selects the applicable reported ceiling, using the minimum for
multi-axis travel. Missing capability retains the existing positive feed.
Firmware is never changed and Pen Down drawing feed is not increased.

Software tests prove requested selection, not achieved physical speed. An
attended boundary run must compare the visible request with the controller
facts.

## Work item 6 — Observed Drawing Trials — implemented in software

The current trial is:

1. Capture Clean Reference
2. Choose Line Start
3. Create Anchor Mark
4. Draw Isolated Line
5. Clear Tool and Observe Ink
6. Compare Intended and Observed Geometry

It records one attributable episode, exact frames, controller evidence, anchor,
new-ink observation, residual, and typed human comparison. Unclear ink causes no
redraw. Physical end-to-end ink validation remains pending.

## Work item 7 — One-window learning workbench and repeat semantics — implemented

This coordinated increment delivers:

- retain exactly one singleton main window;
- delete the auxiliary Learning Path window, Open Learning Path action, fixed
  custom dock allocator, and exercise-specific toolbar Stop;
- render a user-resizable Learning Path navigator, always-mounted camera, and
  selected exercise/action region;
- keep browsing selection local to the window and distinct from the current
  runtime step;
- restore the useful focused question card, current timeline highlighting, and
  pinned footer hierarchy without restoring removed workflow concepts;
- render UP, DOWN, YES, NO, STOP, and typed directions as structured accessible
  cues;
- provide typed Start, Cancel, Stop, and Restart states with exactly one
  mechanical cancel path;
- remove the standalone Jog Observations controls, observed-jog target, online
  jog-response dataset/model, and associated source/tests/docs unless a
  lower-level primitive has a concrete typed consumer in a numbered Learning
  Path exercise; do not preserve or rename that workflow as Record Another
  Attempt;
- removal of the former fixed X/Y Boundary Discovery completion horizons in
  favor of one typed operator-stopped logical owner; Stop prevents segment renewal,
  natural segment completion creates no evidence, faults become Needs Attention,
  and ambiguity is never renewed;
- implement Redo This Step as atomic accepted-value replacement followed by
  transitive invalidation over declared data dependencies, not row order;
- prove that redoing Pen Interaction does not discard independent boundary
  observations;
- implement Record Another Attempt as preserved compatible attempts plus a typed
  aggregate over every valid attempt, with `N`, estimator identity, uncertainty
  or categorical counts, and full provenance;
- refuse silent aggregation across incompatible frame/configuration, coordinate,
  units, or algorithm revisions;
- deletion of old source, views, tests, and documentation that encoded the
  outgoing model.

Cancel is not a successful Boundary Stop. During active motion it may share the
one cancel/settle primitive but records an abandoned attempt and no boundary or
trial success. Restart begins only after the original owner settles and never
resends an ambiguous write.

The copy-paste coordinator specification is
[Learning Workbench Multi-Agent Execution Prompt](implementation/LEARNING_WORKBENCH_MULTI_AGENT_EXECUTION_PROMPT.md).

### Work item 7a — Stop identity, status truth, and simulator parity — implemented

- bind every contextual Stop to one unique operation capability and latch the
  first Stop/Cancel/shutdown disposition before mechanical settlement;
- route Boundary Stop through the same action descriptor the UI renders, with
  no extra generic YES/NO start ceremony;
- render **Stop Manual Jog** in the labeled Motion panel and reject stale Stop
  capabilities from prior jogs;
- keep Motion Enabled tied to current-session authorization while Ready, Busy,
  Unavailable, and Needs Attention describe the current request separately;
- project Needs Attention with actor, action, outcome, detail, and recovery;
- make Utilities explicitly hideable and keep it subordinate to camera width;
- make the navigator, exercise detail, and lower Motion region explicitly
  collapsible/restorable while retaining native split resizing when visible;
- keep the sole Stop-owning pane visible until its operation settles;
- start bounded LIVE automatic vision analysis after successful camera
  start/restart with all semantic overlay layers initially visible;
- use the same Learning Path and camera-utility presentation in LIVE and
  SIMULATED;
- run the complete deterministic simulated path through Boundary Stop and the
  observed drawing trial with zero `MachineActions` calls and explicit
  nonphysical evidence labels;
- discard simulated artifacts on return to LIVE and restore the parked LIVE
  accepted authority unchanged.

## Work item 8 — Repeatable geometric learning — next

After the attended single-trial loop is reliable:

- collect multiple attributable line trials without changing camera identity;
- retain intended and observed geometry in explicit coordinate spaces;
- split actual model data before actions;
- compare candidate response models on reserved episodes;
- expose uncertainty and residuals without changing motion admission;
- reject cross-configuration frame or model mixing.

Do not promote a model automatically from trial count or one good residual.

## Work item 9 — Stroke and shape preference — later

Add closed typed candidate shapes only after observed line evidence is reliable.
Retain exact proposed/executed actions, observed ink, human comparison, and
residual. Preference or reward summarizes the episode; it cannot hide a refusal
or ambiguous physical outcome.

## Work item 10 — Active experiment selection — later

Active learning may select among already safe typed experiments to reduce model
uncertainty or disagreement. It must show the candidates, selected experiment,
selection propensity when applicable, expected evidence, and stop boundary.

It may not create controller text, enlarge physical scope, bypass Enable Motion,
or turn model confidence into authority.

## Work item 11 — Adaptive Drawing — future

Stage 5 becomes available only after the app supports:

- multiple attributable strokes;
- explicit observation checkpoints;
- reliable absent/unclear-ink handling;
- model comparison from exact retained evidence;
- bounded correction without automatic resend or redraw;
- visible explanation of the current model and next action.

## Current validation definition

Software completion requires:

- exact five-stage and numbered-substep presentation tests;
- one-window selection/action/layout model tests that do not parse source text;
- dependency-aware Redo replacement and nondependency-retention tests;
- two-attempt and N-attempt typed aggregation/provenance tests;
- Cancel-versus-Stop disposition and one-cancel settlement tests;
- boundary-motion tests covering continuation under one owner, Stop-versus-
  renewal races, no app-distance completion, limit/fault handling, and no
  ambiguity resend;
- one-Stop boundary, manual, and shutdown regression tests;
- announcement queue order/identity tests;
- controller-axis feed selection and fallback tests;
- exact-frame freshness and posterior tests;
- drawing-trial no-redraw tests;
- launcher identity, existing-instance, and raw-process tests;
- bundle/signature/privacy validation;
- full and strict repository checks;
- clean stale-surface scan.

Physical completion requires an attended supported-bundle run and must report
each observation separately. Until that occurs, software completion is not a
physical movement, audible-output, or ink claim.
