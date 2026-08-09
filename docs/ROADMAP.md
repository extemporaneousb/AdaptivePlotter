# AdaptivePlotter Roadmap

Status: unfinished work only

The current software already provides the local app shell, controller and
camera ownership, one-window Learning Path, Human-Guided Discovery, visibility
registration, one isolated-line observed trial, causal simulation, artifact
dependencies, and conservative attempt replacement. See
[Current Evidence](CURRENT_EVIDENCE.md) for verified status rather than treating
this roadmap as completion evidence.

## 1. Repeatable geometric learning

Goal: move from one isolated line comparison to enough repeated attributable
observations to estimate a useful first correction model.

Required outcomes:

- repeat target-anchored lines at multiple directions and locations;
- preserve exact intended, predicted, observed, frame, controller, pen, paper,
  camera, and model provenance;
- separate immediate state correction from slow model parameters;
- reserve whole trials for held-out evaluation;
- compare candidate, prior, and null improvements;
- reject underidentified or context-incompatible fits;
- expose uncertainty and applicability rather than one global confidence value;
- require explicit acceptance before changing the current model.

Physical completion requires attended observed-ink trials. Simulator and tests
can verify structure but cannot establish physical model quality.

## 2. Stroke and shape preference

Goal: establish observed behavior beyond a single straight isolated line.

Candidate work:

- repeated directions, lengths, and drawing feeds;
- separated travel, drawing, corner, reversal, and pen-cycle effects;
- line-width and pen-profile evidence;
- closed-shape and multi-stroke observations;
- whole-stroke holdouts and residual decomposition;
- explicit ambiguity handling without automatic redraw.

Prefer the simplest interpretable model that improves held-out physical trials.
Affine geometry, cap-to-tip offset, direction-dependent backlash, and a
regularized low-resolution residual field are progressively more complex
options, not mandatory stages.

## 3. Active experiment selection

Goal: choose a bounded next observation only when it is expected to reduce a
specific uncertainty safely.

Required before activation:

- a current accepted model and comparable candidate family;
- explicit uncertainty or identifiability target;
- bounded typed action candidates;
- direct mechanical eligibility checked independently of model preference;
- operator-visible proposal and explicit Start;
- no hidden motion and no automatic retry;
- outcome recorded as evidence rather than immediate authority.

The existing future-facing action, dataset, and model types may support this
work. They do not make active experiment selection a current product feature.

## 4. Adaptive Drawing

Goal: execute useful multi-stroke programs while preserving checkpoint evidence
and refusing ambiguous continuation.

Required outcomes:

- immutable logical drawing programs;
- finite execution-plan revisions ending at checkpoints;
- distinct commanded, controller-completed, and ink-verified frontiers;
- ambiguity attached to affected blocks or strokes;
- no redraw of controller-completed but ink-unverified work;
- accepted-model identity and planning basis recorded per revision;
- forward-model inversion with domain and forward checks;
- model updates only at safe checkpoints, never during a Pen Down stroke;
- explicit human recovery when physical outcome is uncertain.

## Validation milestones

Each increment reports automated, simulator, signed-launch, controller, camera,
human, and observed-ink evidence separately. A feature remains software-only
until its required attended physical evidence exists.
