# Episode Architecture Vocabulary

Status: sole authority for target episode-architecture terminology

This document defines the names used by the target architecture and its
migration. The current implementation still has older identifiers; those are
as-built facts, not synonyms or permission to introduce compatibility wrappers.
The [execution plan](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md) assigns their
replacement and deletion.

## Specifications and state

- `EpisodeGoal` specifies desired terminal and intermediate outcome constraints,
  assessment criteria, and termination conditions. It does not specify an
  intent, an effect, a trajectory, or reachability.
- `EpisodeDefinition` is the domain-generic immutable bounded-attempt
  specification. In `EpisodeCore` it is parameterized as
  `EpisodeDefinition<Intent>` and contains one `EpisodeGoal`, initial context,
  the permitted domain-intent grammar, budgets, and assessment rules.
  `PlotterEpisodeModel` supplies `PlotterIntent` as that binding.
- `EpisodeManifest` is the domain-generic revision envelope. In `EpisodeCore`
  it is parameterized as `EpisodeManifest<DomainManifest>` and pins the
  definition, domain/evaluator/reducer/schema/build revisions, and the typed
  domain payload. `PlotterEpisodeModel` supplies the payload that pins drawing,
  execution-plan, calibration, paper, environment, and model revisions.
- `EpisodeState` is the decision-relevant value reconstructed by reducing the
  ordered `EpisodeEvent` history. It is neither a trace nor an independently
  mutable cache of UI fields.

`EpisodePlan` is not a synonym for `EpisodeDefinition`. That name may be added
only if the system later owns a computed, revisable strategy distinct from the
immutable definition. `DrawingProgram` remains the embodiment-independent
geometry to draw. `ExecutionPlanRevision` remains the immutable,
calibration-bound plan for executing a `DrawingProgram`. Generic episode code
contains neither strokes nor GRBL primitives.

## Semantic request and decision

- `PlotterIntent` is one operator-, policy-, or system-originated semantic
  request. It states what is requested without embedding controller, camera,
  Vision, persistence, or drawing primitives.
- `IntentDecision` is the pure evaluator result for a `PlotterIntent` against an
  exact `EpisodeState` revision and exact `CapabilityFact` revisions. It is
  admitted or refused and carries typed requirement results. It is not an
  `EffectPermit`, an event, or authorization to bypass submission.
- `IntentAvailability` is a copied, immutable presentation projection of an
  `IntentDecision`. The UI may render it, but it can never submit it as current
  authority.
- `IntentReceipt` records the result of submitting one identified
  `PlotterIntent`: accepted or refused, the compared revisions, and the committed
  event identities. It does not claim that any resulting physical effect
  completed.

The target architecture does not use `ActionDecision`, `ActionAvailability`,
`ActionReceipt`, `SemanticActionAuthority`, or `SemanticActionGateway` as
aliases. The word “action” remains valid in generic prose, operator-facing copy,
and exact current-code identifiers; target type and protocol names use
`PlotterIntent` and the `Intent...` family.

## Events, effects, and capabilities

- `EpisodeEvent` is an immutable, identified, ordered reducer input durably
  committed to an `EpisodeJournal`. It carries episode sequence, causation,
  correlation, actor/origin, pre/post revision, typed payload, artifact
  references, and canonical post-state digest.
- `PlotterEffect` is a typed external request emitted only by reducing a
  committed `EpisodeEvent`. An accepted-intent event may emit the first effect;
  a committed result event may emit a causally linked successor effect. It says
  what environment interaction is required; its runner supplies the
  device-specific method. No callback or hidden intent may emit one.
- `EffectPermit` is an internal, one-shot, identity- and revision-bound runtime
  permission minted only after the accepted event is committed and the effect is
  registered. It is not serializable application state, UI capability, or a
  public API.
- `EffectResult` is the typed completion, refusal, cancellation, ambiguity,
  timeout, evidence-unavailable result, or failure returned by an environment.
  It is data awaiting identity/revision validation, not yet an `EpisodeEvent`.
- `CapabilityFact` is a read-only, versioned fact acquired from an authoritative
  environment or evidence owner for semantic evaluation. It describes current
  connection, Motion, pose, camera, evidence, lane, or related conditions. It
  does not authorize an effect.
- `StopCapability` is the revocable handle bound to one exact active operation
  owner. It permits only cancellation/settlement of that owner, never creation,
  repetition, or cancellation of a successor effect.

An `EffectResult`, `Observation`, or `Measurement` becomes event payload only
after the runtime validates episode, intent, effect, environment, and relevant
artifact revisions and durably commits the resulting `EpisodeEvent`. Reducing
that committed event—not mutating fields from a callback—changes
`EpisodeState`.

## Observation, evidence, and assessment

- `Observation` is a source-, time-, configuration-, identity-, and
  revision-bound reading, such as a controller reply or exact camera frame. It
  is not automatically evidence.
- `Measurement` is a typed quantity derived from one or more observations by a
  pinned algorithm or model revision. It retains those inputs and uncertainty or
  diagnostic qualifications.
- `Evidence` is an `Observation` or `Measurement` accepted by the authoritative
  evidence owner for a declared episode, intent, plan, paper, calibration,
  outcome, or assessment question after provenance and applicability checks.
- `EpisodeOutcome` is the typed terminal result and accepted evidence set
  produced by one episode. It records what happened, including cancellation,
  ambiguity, or failure; it is not the desired `EpisodeGoal`.
- `Assessment` compares an `EpisodeOutcome` and its accepted `Evidence` with the
  criteria in `EpisodeGoal`. Estimation may update a separately versioned model
  after assessment, but assessment itself does not mutate an accepted estimator,
  policy, or calibration revision or start another episode.

Outside-applicability camera projection is diagnostic presentation, not
attributable `Evidence`, unless the evidence authority has accepted a new
revision with that applicability. Controller settlement, a simulator result,
and software tests cannot promote a camera observation or physical-ink claim.

## Memory and repository execution

- `EpisodeJournal` is the ordered semantic-event authority for one episode.
- `EpisodeTrace` is an immutable export of a manifest, journal events, and
  referenced transcripts, frames, observations, evidence, outcomes, and
  assessments. It is not mutable state and cannot restore an effect capability.
- `WorkPackage` is one bounded repository migration unit with one atomic package
  outcome, exact dependencies, one rollback/evidence/decision boundary, and
  exact required validation gates. A `software` outcome is exactly one of:
  `Foundation`, which adds one isolated contract/service with no production
  caller or current authority transfer; `Correction`, which replaces one named
  coupled invariant inside its current owners; or `Cutover`, which transfers
  exactly one product authority and deletes its superseded path in the same
  landing.
  `repository`, `attended-physical`, `remote-git`, and `gate` packages transfer
  no product authority; they respectively change contracts, acquire evidence,
  create the named remote artifact, or record a decision.
- `BlackdogTask` is the branch-backed implementation transaction used to execute
  one `WorkPackage`. Blackdog lifecycle completion is evidence about that
  transaction, not proof that the package or migration is complete.

Current `RunLedger` is retained as low-level device diagnostic history below
`EpisodeJournal`; `EA-05A` records its references and completeness,
`EA-05B` consumes them for replay, and `EA-05C` links them into incident
artifacts without promoting it to semantic authority. Current
`ActiveStoppableOperation` remains the sole owner for unmigrated operations,
then its declaration and final consumers are deleted in `EA-11C` after the
registry owns every effect. Current `LearningSessionState` is decomposed by the
feature cutovers in `EA-04`, `EA-06`, `EA-08A`, `EA-08B`, and `EA-10A` through
`EA-10G`, followed by controller-session and observation-configuration
cutovers in `EA-11A` and `EA-11B`; `EA-11C` deletes its declaration and any
residue. `EA-01` assigns each field exactly one of those cutovers. None of these current types is an
`EpisodeJournal`, `EpisodeTrace`, or target operation registry.

Current `SpeechAnnouncing`, `NativeSpeechAnnouncer`, and its identity-bound
queue retain advisory synthesis and shutdown-cancellation ownership until
`EA-10G`. That cutover moves only the application-level announcement effect,
result, and operation lane; AVFoundation synthesis remains below the target
runtime and speech failure never becomes physical permission.

## Supporting roles and field correspondence

The evaluator is the pure function that produces `IntentDecision`. The reducer
is the pure function that folds committed `EpisodeEvent` values into
`EpisodeState` and emits `PlotterEffect` values. A policy, when one is later
introduced, chooses a `PlotterIntent` from decision-relevant state or a belief
estimate; it does not call ports or mint permission. The environment boundary
supplies `CapabilityFact` values, executes permitted effects through current
device owners, and returns `EffectResult`, `Observation`, or `Measurement`
values. LIVE and SIMULATED environments share typed contracts but never
provenance or evidence class.

In control and reinforcement-learning literature, `EpisodeGoal` corresponds to
a task objective, terminal set, or constrained performance criterion depending
on the method; it is not necessarily one scalar reward. `PlotterIntent` is the
high-level decision variable often called an action or option. `PlotterEffect`
is closer to an environment command, while GRBL bytes and camera calls remain
embodiment-specific plant or sensor I/O below the runner. `Observation` and
`Measurement` correspond to sensor outputs and estimator products; neither is
the full physical state. `Assessment` may produce reward, cost, constraint, or
comparison values, but those values are outputs of declared criteria rather
than synonyms for evidence.

The controller is not modeled as a write-only actuator and video is not modeled
as “the state.” The controller link is a bidirectional device boundary whose
replies become observations and capability facts only through its existing
authority. Camera frames are observations; Vision outputs are measurements;
the evidence authority decides applicability. Physical plant/pen/paper truth is
separate and is directly available only inside causal simulation.

## Canonical target seams

- `PlotterIntentGateway` is the single public submission façade for migrated
  `PlotterIntent` cases. It owns no feature rules, reducer state, evidence
  acceptance, effect lanes, tasks, device ports, or persistence.
- `PlotterOperationRegistry` is the sole target application-level owner of
  effect identity, lanes, original task/handle, `StopCapability`, cancellation,
  and terminal disposition.

During migration, exactly one ingress exists per semantic intent. Migrated
intents use `PlotterIntentGateway`; unmigrated intents retain their one declared
current owner. No intent may be reachable through both. `EA-11C` makes the
gateway the globally exclusive public mutation ingress. `GATE-02` later
verifies that landed fact and moves no authority.
