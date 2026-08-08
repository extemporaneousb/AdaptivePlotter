# Next Slice Multi-Agent Execution Prompt

Copy everything below into a new AdaptivePlotter discussion.

---

You are the coordinator for one decisive AdaptivePlotter implementation and
physical-learning slice. Use multiple worker agents in parallel, but retain one
architectural owner, one Blackdog task, one task workspace, and one landing.

## Outcome

Implement and exercise this complete loop:

```text
start one persistent voice ExplorationSession
-> run a Motion Preflight episode without restarting the microphone
-> run Armature Guidance and teach one clear observation pose
-> capture one exact clean reference
-> create and observe one voice-confirmed anchor dot at the recorded line start
-> use the anchored frame as the exact line baseline
-> draw one fixed short isolated green line
-> raise and return the armature to the taught clear pose
-> capture one strictly newer exact frame
-> extract the new ink and show intended versus observed residual
-> accept immediate spoken human assessment
-> record one attributable ExplorationEpisode
```

This is the slice. Do not stop after designing types or adding another setup
screen. Reach the deterministic simulator quickly, then run the real hardware
in the same discussion when the operator is present and the basic preparation
below is true.

## Repository and authority

Repository: `/Users/bullard/Projects/AdaptivePlotter`

Read completely before editing:

- `AGENTS.md`
- `.codex/skills/adaptiveplotter/SKILL.md`
- `README.md`
- `docs/PROJECT_SCOPE_AND_MODEL_TRAINING.md`
- `docs/FEASIBILITY_REVIEW_AND_BINDING_AMENDMENTS.md`
- `docs/SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md`
- `docs/SWIFT_ADAPTIVE_PLOTTER_SEQUENTIAL_REBUILD.md`
- `docs/implementation/CURRENT_IMPLEMENTATION_STATUS.md`
- `docs/implementation/FIRST_HARDWARE_SESSION.md`

Treat the current repository as implementation truth. The documents above are
the selected product direction. Legacy `/Users/bullard/Projects/Plotter` is
forensic evidence only; do not port from it.

## Blackdog single-owner contract

The coordinator is the only Blackdog owner.

1. Create the two required mode-0600 UTF-8 temporary files outside the repo.
   Put this exact triggering request in `request_file` and the coordinator's
   composed goal/context/constraints/done condition in `execution_prompt_file`.
   Delete them only if `task begin` returns both nonempty replay artifact paths;
   otherwise preserve both inputs.
2. Run exactly one normal structured `task begin` with actor
   `codex-supervisor`. For every structured task result, execute the exact
   `next_action.argv` when `kind=command`; choose only a complete emitted choice
   or alternative; stop when `kind=blocked` or `kind=complete`. Never infer an
   action from prose or invent missing arguments.
3. Work only in the returned `workspace role: task` worktree.
4. Workers do not invoke Blackdog, start tasks/worktrees, create branches,
   commit, land, close, or clean up. They work inside the supervisor-owned task
   workspace and report evidence to the coordinator.
5. The coordinator owns shared interfaces, integration, validation, physical
   coordination, documentation truth, and landing.
6. Before landing, report only validations actually run. Follow the exact
   Blackdog landing action; do not invent recovery or stale-work commands.

## Bias for action and risk posture

This is one spare-parts, 3D-printed, end-stop-equipped machine. Optimize for
short attributable experiments, not for constructing virtual travel limits or
eliminating all hardware wear.

Retain only these immediate machine guards:

- selected responsive controller and explicit Motion Guard activation;
- no current controller alarm, relevant asserted end stop, or disconnect;
- one in-flight controller owner and no earlier sticky ambiguity;
- closed finite typed request and feed within controller-reported capability;
- known Pen Up for travel; pen-down XY motion only through the closed drawing
  stroke operation;
- current exact camera frame only when the episode actually consumes vision.

Do not add or consult operator-entered coordinates, absolute bounds, firmware
travel as a bound, maximum-jog values, learned-boundary motion gates, completed-
curriculum gates, model-confidence gates, document gates, repeated approvals,
or separate motion/pen arms. Missing preflight evidence may block a drawing
episode that consumes that evidence; it does not block ordinary manual motion
or a preflight/Armature Guidance experiment.

`STOP` is the fastest applicable typed software cancellation. For a jog it is
GRBL Jog Cancel, not a physical emergency stop. Never automatically resend,
redraw, invert, resume, unlock, home, reset, clear an alarm, or write settings.

## Current implementation facts

- Controller connection, passive inspection, explicit Activate Motion,
  relative jog, Jog Cancel, typed `S40` Pen Up / `S760` Pen Down, current MPos,
  exact C920 frames, and current-session observed-jog fitting exist.
- Pen Up/Down, 1 mm X/Y round trips, and eight exact current-session observed
  jogs have physical evidence. Motor power is not observable through USB status.
- Motion Preflight currently starts/stops listening per transaction and accepts
  exact context-bound phrases. Partial/final transcript identity and newest-only
  speech output already exist. This lifecycle is the bootstrap to replace.
- A cancelled boundary jog plus final MPos and a strictly newer exact tool
  observation currently feeds a heuristic nearest-edge quadrilateral average.
  Final MPos is recorded but not numerically fused; uncertainty does not narrow.
  Physical validation and the selected per-side posterior remain.
- The current armature overlay is inferred image-space geometry. Armature
  Guidance, human visibility labels, and a taught clear pose do not exist.
- Ordinary relative jog deliberately refuses Pen Down. A separate closed
  drawing-stroke request does not exist.
- Current green-ink vision measures one frame/component. Clean-reference /
  anchored-baseline / post-line extraction and a live residual do not exist.
- Physical camera observations do not yet have an accepted, provenance-bearing
  `FieldRegistration`; keep this slice's residual in `CameraPixelSpace` and do
  not admit it to the existing machine-to-`FieldSpace` affine trainer.
- Simulator output is not physical evidence. Controller `ok`/Idle/MPos and cap
  displacement are not observed ink.

## Coordinate the work

Before spawning workers, inspect the relevant current source/tests and publish
a small interface sketch for:

1. `ExplorationSession`, contextual voice intent/label, and
   `ExplorationEpisode`;
2. one closed pen-down drawing-stroke request/outcome;
3. Armature Guidance observation/clear pose;
4. per-side image-space drawing-frame posterior;
5. clean-reference/anchored-baseline/post-line observation and residual.

Spawn exactly three bounded workers. All agents share the task filesystem.
Give each worker non-overlapping primary files, require a message before it
touches another ownership area, and keep the coordinator out of those files
until the worker reports complete. The coordinator owns
`OperatorWorkspace`, app composition, SwiftUI integration, cross-area tests,
and final reconciliation so workers do not build competing state machines.
Every assignment must include the exact task-workspace path returned by
Blackdog. Each worker verifies that path before reading or editing and must not
fall back to the primary checkout.

### Worker 1 — ExplorationSession and voice runtime

Primary ownership:

- `Sources/PlotterRuntime/VoiceInteraction.swift`
- new narrowly scoped ExplorationSession/episode/intent model files
- corresponding `PlotterRuntimeTests`

Deliver:

- one session that starts microphone ownership once and remains listening
  across multiple active episodes;
- explicit inactive/starting/listening/ending/failed state and generation-safe
  teardown so stale authorization or recognition callbacks cannot revive a
  cancelled session;
- operator barge-in that cancels current app speech immediately;
- stable-partial `STOP`, deduplicated by utterance identity;
- final/stable contextual continue, keep going, reverse, X+/X-/Y+/Y-, accept,
  again, skip, and end-session intents only when declared by the active episode;
- a separate flexible teaching-label result for clear/partial/blocked,
  visibility explanations, shape features, rankings, and reward language;
- no ambient raw motion grammar and no raw controller text;
- monotonic timing fields for speech hypothesis, accepted intent/label, and
  feedback so end-to-end latency can be displayed and measured;
- unit tests for multi-episode lifetime, barge-in, partial STOP, duplicate
  suppression, context rejection, generation races, and teardown.

Do not add a network/OpenAI speech dependency. Keep the native on-device path.

### Worker 2 — Closed drawing-stroke runtime

Primary ownership:

- `Sources/PlotterRuntime/MachineProtocol.swift`
- `Sources/PlotterRuntime/MachineController.swift`
- `Sources/PlotterRuntime/RunInterpreter.swift`
- corresponding controller/interpreter tests

Implement a distinct typed drawing-stroke operation. Do not weaken ordinary
`RelativeJogRequest`; normal travel still requires Pen Up.

The drawing stroke must:

- accept only one closed finite machine delta and positive feed;
- require selected/connected controller, active Motion Guard, fresh recognized
  Idle/non-alarm state, no relevant asserted end stop, known MPos, Pen Down,
  one owner, and no sticky ambiguity;
- enforce controller-reported feed capability;
- use locale-independent closed GRBL encoding and the controller-aware
  completion deadline;
- keep one owner through acceptance and final Idle/MPos;
- expose the existing one-shot Jog Cancel as explicit `STOP`/Abort;
- define cancellation while Pen Down precisely: if Jog Cancel settles cleanly
  at Idle with final MPos, issue the typed Pen Up command once, end the episode
  cancelled, and do not return automatically to the clear pose; if cancellation
  or final position is ambiguous, send nothing further and require physical
  cutoff/inspection;
- never automatically repeat, invert, resume, unlock, home, reset, clear an
  alarm, or write settings;
- make any uncertain post-write outcome sticky and end automatic follow-on work.

Test success, Pen Up/unknown refusal, alarm/end-stop/feed/in-flight/ambiguity
refusal, cancellation, timeout/disconnect, and exact no-resend behavior.

### Worker 3 — Armature Guidance and ink observation

Primary ownership:

- `Sources/PlotterRuntime/VisionWorker.swift`
- `Sources/PlotterRuntime/PreflightCalibration.swift`
- new narrowly scoped Armature Guidance and isolated-ink model files
- `Sources/PlotterTestSupport` scene/simulator support
- corresponding `PlotterRuntimeTests` and test-support tests

Deliver Armature Guidance:

- input one exact frame, current MPos, fixed observation region, and conservative
  armature-region overlap estimate;
- accept human clear/partial/blocked labels and directional/accept-pose outcomes;
- record estimate-versus-human agreement and labelled pose observations; fit a
  visibility estimate only after multiple nonduplicate poses;
- represent one accepted clear pose and pen-up return path;
- propose only nearby enumerated finite actions when another pose is useful;
- do not make vision confidence a motion gate or build 3D/generalized planning.
- invalidate automated clear-pose return after controller coordinate reset or
  reconnect, camera-configuration/region change, or tool/paper change; this must
  not disable manual motion.

Deliver the drawing-frame posterior:

- replace the heuristic whole-quadrilateral average with one image-space offset
  and uncertainty per selected side;
- on a side's first observation, associate its machine-side label with the
  nearest candidate camera edge only when a tested distance margin makes the
  choice unique; persist that association for the camera configuration,
  initialize orientation from the candidate edge and offset with a broad prior
  variance, and reject ambiguous association without blocking motion;
- use the sequence direction as side identity and the exact post-stop centroid
  plus explicit observation variance as the image-space measurement;
- narrow uncertainty under repeated nonduplicate observations and derive
  displayed corners from side intersections;
- retain final controller MPos as provenance/repeatability context only; do not
  claim it is an image-space constraint until a registration exists;
- keep missing sides uncertain without blocking unrelated motion.

Deliver paired isolated-ink observation:

- inputs are one exact clean reference, one exact anchored baseline captured
  after a stationary dot and clear-pose settlement, one strictly newer post-line
  frame captured after the next clear-pose settlement, one fixed pixel region,
  green thresholds, and the projected camera-space stroke delta;
- require matching dimensions, pixel format, and camera configuration;
- find the new anchor dot from clean-reference versus anchored-baseline pixels,
  then find the new line from anchored-baseline versus post-line pixels so the
  anchor and pre-existing marks are ignored;
- reject missing, too-small, or non-line-like results with one direct reason;
- fit simple endpoints/centreline;
- construct the intended camera line from the anchor-dot centroid plus the
  projected actual stroke delta; without anchor or projection, expose only
  displacement/orientation measurements and mark absolute residual unavailable;
- return exact three-frame provenance plus intended/observed overlay and
  deterministic RMS/maximum or cross-track residual when prediction exists;
- create no calibration, readiness, motion, model-promotion, or persistence
  authority.

Test clear/partial/blocked updates, accepted pose, deterministic active-pose
choice, synthetic anchor/line pairs, pre-existing green ink, missing/ambiguous
anchor or line, camera-
configuration mismatch, padded pixel rows, and residuals. Test declared-side
association initialization/persistence/invalidation, ambiguous nearest-edge
rejection, uncertainty narrowing under repeated boundary observations, corner
derivation, missing-side behavior, and that final MPos is provenance rather
than silently treated as image geometry.

## Coordinator integration

The coordinator integrates the three worker surfaces into one state machine and
one natural macOS Learning window. Do not create separate controller windows or
another wizard.

Required UI flow:

1. The existing top toolbar retains remembered controller picker, Connect,
   Activate Motion, and truthful camera/plotter/motion badges.
2. Learning has one prominent **Start Exploration** / **End Exploration**
   action beside permission/listening state. Starting it turns listening on;
   there is no separate listening action.
3. Motion Preflight, Armature Guidance, and Isolated Line are episode sections
   inside the same session. Show the active participant/action/observation
   sequence, not historical replay or documentation prose.
4. Spoken feedback is brief: action/result/current assessment/next needed input.
   New operator speech interrupts it.
5. Motion Preflight reuses the existing typed transaction and posterior update,
   but transaction completion no longer tears down the microphone. Replace its
   heuristic quadrilateral averaging with the worker's per-side posterior and
   display uncertainty. At least one physical boundary episode must be possible
   without all four sides or any typed limits.
6. Armature Guidance moves through explicit small pen-up actions, displays the
   observation region and visibility estimate, accepts voice labels, and stores
   one current-session clear pose.
7. Isolated Line captures a clean reference at the clear pose, lets the operator
   use normal pen-up motion to choose and record a start MPos, transacts physical
   Pen Down confirmation followed by Pen Up to create an anchor dot, returns
   clear, captures the anchored baseline and detects the dot, returns pen-up to
   the recorded start, executes exactly one fixed short stroke, raises once,
   returns clear, and captures the post-line frame after return settlement.
8. Show intended, predicted when available, observed ink, residual, current
   episode outcome, and latest human assessment. A current-session jog-response
   matrix may project intended camera displacement for display only; its absence
   cannot authorize or change motion. If it is absent, the app may still draw
   and observe the line but must label the physical camera-space residual
   unavailable rather than comparing incompatible units.
9. Missing/unclear ink displays the exact frame and reason. It never redraws.
   Ambiguity stops all automatic follow-on commands.

Use one in-memory `ExplorationEpisode` sufficient for the current slice:

```text
session/episode identity, learning rung, live/simulated source, and termination
utterance identity, partial/final timing, transcript, accepted intent/label
episode-level training/reserved split assigned before action
candidate action set, model/policy version, and selection propensity
typed proposed and executed action plus model/policy snapshot
controller start/final MPos, sample/settlement times, outcome, and ambiguity
exact frame IDs, raw hashes, capture times, camera configuration, algorithm revision
line-start MPos and detected anchor-dot centroid
vision estimate, human assessment, residual/reward, and provenance
```

All endpoints, centreline samples, frames, and labels from one physical line
share its preassigned episode split. Do not split one line across training and
reserved data.

Persist exact bytes only for frames deliberately admitted to a learning episode.
Route those selected clean-reference/anchored-baseline/post-line frames through the existing camera-owner
`CameraSamples` PNG/manifest export path so frame/configuration/hash provenance
has one owner. Export failure does not block motion or immediate display, but
the incomplete episode cannot be admitted to durable training. Do not add
continuous audio/video recording, a second artifact store, replay system,
experiment database, model history UI, or recovery protocol.

## Simulation-first integration

The simulator must exercise the same app-level episode coordinator while
remaining unable to reach physical `MachineActions`:

1. Start Exploration and keep listening presentation active across episodes
   without acquiring a real microphone in SIMULATED mode.
2. Rehearse Pen Up and one boundary posterior adjustment.
3. Present at least blocked then clear Armature Guidance observations and accept
   the clear pose.
4. Execute deterministic anchor-dot and isolated-line machine outcomes with the
   three exact frames.
5. Render intended, observed, residual, human label, and completed episode.
6. Prove `STOP`, ambiguity, missing ink, and camera-configuration mismatch stop
   the correct episode without automatic retry.

Run focused tests throughout, then run:

```text
make check
git diff --check
```

`make strict-check` is optional diagnostic evidence, not a routine landing gate.

## Evidence boundaries

- Automated tests prove software ordering, refusal behavior, and deterministic
  vision results only.
- Simulator output is never physical evidence and cannot update a physical
  model or satisfy a physical observation.
- Controller `ok`, Idle, and final MPos are controller evidence, not ink.
- Cap displacement is motion evidence, not drawing success.
- Boundary learning requires Jog Cancel settlement plus final MPos and a
  strictly newer exact tool observation in the same camera configuration.
- Physical line success requires newly visible attributable green ink in a
  strictly newer exact post-clear frame.
- Absolute camera-space residual requires the observed anchor-dot centroid plus
  the current-session projected stroke delta; otherwise report only relative
  displacement/orientation measurements.
- Pen height and accepted clear pose require direct operator observation because
  the current camera cannot prove vertical pen state.
- Human visibility/preference feedback is authoritative for that label but does
  not become a claim that vision already agreed.
- Missing/unclear ink is an observation, never permission to redraw.
- Any ambiguous controller outcome stops automatic follow-on work.
- SQLite remains best-effort diagnostics and cannot gate motion.

## Physical preparation and run

Do not require hardware to build, test, or land the coherent software slice. If
the operator is absent, finish simulation, land, and report physical validation
as pending. If the operator is present, do not stop at a runbook. Before the
first physical motion, ask for only the facts software cannot observe: the
operator is beside the machine, the workspace is visibly clear, the physical
cutoff is reachable, and the pen is physically Up. Before the first ink stroke,
also confirm clean replaceable white paper and the green pen. These statements
apply to that experiment; they are not a readiness workflow and do not gate
unrelated motion or preflight.

The app and coordinator derive everything else just in time: launch through
`make run-app` for TCC identity, C920 LIVE, selected responsive controller,
current alarm/end-stop/ambiguity state, and Motion Guard activation. Show and
correct a failing current fact directly; do not ask the operator to attest to a
machine-readable checklist.

Then perform exactly one initial physical loop:

1. Start Exploration; verify speech remains active and interruptible.
2. Run physical Pen Up confirmation, then one relevant boundary Motion
   Preflight episode. Say `STOP` while moving
   and verify Jog Cancel settlement, final MPos, a newer exact tool observation,
   and visible selected-edge posterior/uncertainty adjustment.
3. Run Armature Guidance with small pen-up moves until the operator says the
   fixed ink region is clear, then accept that pose.
4. If the current session lacks a camera-space response projection, record two
   linearly independent accepted `PhysicalJogObservation` training episodes.
   Prefer to admit two already useful Armature Guidance moves when they satisfy
   the same exact-frame/controller evidence contract rather than repeating
   motion solely for the fit.
   They are a diagnostic input required to accept a camera-space residual, not
   motion authority, calibration, or a prerequisite for unrelated motion.
5. Capture the exact clean reference at the clear pose.
6. Use ordinary pen-up controls to place the tool at a harmless line start while
   watching the camera and record its MPos. Enter no coordinates, bounds, or
   maximums.
7. At that start, run physical Pen Down confirmation followed by physical Pen
   Up confirmation to create one anchor dot. This is local first-mark evidence,
   not a manual-motion gate.
8. Return clear, wait for settlement, capture the exact anchored baseline, and
   detect the new dot relative to the clean reference.
9. Return pen-up to the recorded start MPos and run exactly one fixed short line.
10. Directly observe that the pen rises and the armature returns clear.
11. After the return settles unambiguously, capture the strictly newer post-line
   frame, inspect newly added line ink, display the anchored
   `CameraPixelSpace` residual,
   and collect one spoken assessment.
12. Stop after that one line and review the complete episode before choosing a
   second experiment.

Stop the affected physical episode on unexpected motion, physical mismatch,
alarm, asserted end stop, disconnect, unavailable cutoff, or ambiguity. A
recognition miss, vision disagreement, or large residual is a debugging result;
correct it or choose a different finite experiment without adding a new global
gate. Do not automatically retry the physical line.

If `STOP` cancels the pen-down stroke and the controller reaches an unambiguous
Idle/final MPos, raise the pen once and end the episode cancelled in place. Do
not return to the clear pose or claim ink success. If cancellation is ambiguous,
send no Pen Up or follow-on command; use the physical cutoff and inspect.

## Scope exclusions

Do not add:

- controller popup windows, arbitrary G-code, typed coordinate limits, or
  maximum-jog fields;
- vector import, portrait input, general multi-stroke execution, or automatic
  redraw in this slice;
- full affine-model training/promotion UI, preference model, contextual bandit,
  or RL policy yet—the episode schema must support them, but this slice produces
  their first valid ink/voice transition. A later slice must create a cited
  current-session `FieldRegistration` before physical ink enters the existing
  machine-to-`FieldSpace` trainer;
- generalized calibration, workflow/readiness framework, 3D armature model,
  collision planner, archival evidence/replay, accessibility, release, CI, or
  distribution infrastructure.

Remove dead scaffolding introduced during integration. Do not preserve obsolete
sequence-owned microphone code for compatibility when no live caller needs it.

## Done condition

The task is complete when:

- the simulator executes the entire persistent-session, preflight, Armature
  Guidance, isolated-line, ink-observation, and spoken-assessment flow;
- the production app exposes the same physical-capable flow with one obvious
  camera-first UI path;
- listening survives episode boundaries and shuts down cleanly only at session
  end/failure/app shutdown;
- out-of-context speech cannot reach machine actions;
- ordinary manual jog still requires Pen Up and only the new closed stroke can
  move XY while Pen Down;
- the clear pose, line-start MPos, anchor centroid, and exact clean-reference /
  anchored-baseline / post-line frame identities are enforced;
- intended, observed, and residual overlays are visible;
- cancellation, ambiguity, stale-callback, missing-anchor/ink, and mismatched-
  frame behavior are tested;
- `make check` and `git diff --check` pass;
- current implementation docs state only evidence actually obtained;
- Blackdog lands one supervisor-owned coherent increment.

If the physical loop ran, report exact controller, camera, ink, voice-latency,
and human observations separately. If it did not, say plainly that physical
validation remains pending; do not let that absence expand scope or block the
software landing.

---
