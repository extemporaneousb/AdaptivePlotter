# Project Scope and Model Learning

Status: canonical product scope
Target: a local adaptive plotter that learns from attributable physical trials

## Product purpose

AdaptivePlotter should learn enough about one attached mechanism, camera view,
paper scene, and drawing medium to make progressively better drawings while an
operator can see and stop every physical action.

The useful loop is short:

```text
typed action
-> controller settlement
-> exact camera observation
-> human or vision assessment
-> retained evidence
-> next bounded action
```

The product is not a form-driven robotics framework, a remote service, a raw
controller console, or an offline experiment manager. It remains one native
application with direct controller safeguards and evidence that is explicit
about its source.

## Five-stage presentation

The Learning Path is the sole visible journey:

| Stage | Current meaning | Authority meaning |
| --- | --- | --- |
| 1 Connect | Select and establish one responsive controller session. | Real current-session prerequisite. |
| 2 Enable Motion | Perform the one visible operator arming action. | Real current-session prerequisite backed by internal `MotionGuard`. |
| 3 Human-Guided Discovery | Observe pen interaction, all paired boundaries, center the tool, and register a visible target from a Clear pose. | Presentation and local evidence only. |
| 4 Observed Drawing Trials | Draw a target-anchored attributable line, clear the tool, observe new ink, and compare geometry. | Presentation and local evidence only. |
| 5 Adaptive Drawing | Multi-stroke drawing with observation and checkpoint learning. | Future until implemented. |

Learning status does not authorize ordinary movement. Manual motion continues to
depend only on direct machine facts. A stage action may require the evidence it
actually consumes.

## One-window Learning Path

The Learning Path is integrated into the singleton camera-first main frame. A
user-resizable left navigator shows the big picture and exact numbered path; the
camera remains mounted and visible in the center; a user-resizable right region
shows the selected exercise, evidence, questions, and pinned action controls.
Browsing a row is presentation only and never advances, resets, or authorizes
work. The current runtime action remains identifiable while history is reviewed.

The exercise action strip shows only typed operations: Start, contextual choices,
Cancel, motion-only Stop, Restart after settlement, Redo This Step, and Record
Another Attempt where their runtime semantics are available. Critical cues are
structured and emphasized so UP/DOWN, YES/NO, STOP, and directions cannot be
lost inside prose. There is no separate Learning Path window or fixed-dock
compatibility surface.

## Human-Guided Discovery

### 3.1 Pen Interaction

The operator answers typed YES/NO questions about physical pen pose. Lower and
raise commands are announced before actuation and settle through the controller
owner. The sequence succeeds only after the final human confirmation of Up.
Commanded pen state and observed physical pose remain distinct evidence.

### 3.2 Paired Boundary Discovery and Centering

The operator selects a side and presses the one explicit Start for an
operator-stopped Pen Up boundary motion. There is no additional generic YES/NO
start ceremony. One capability-bound contextual Stop records the first semantic
intent before one cancel byte is issued. The original owner settles at Idle
with final MPos; a strictly newer exact frame then supplies the typed tool
contact-point estimate. The operator's typed direction is the machine-side
identity. Drawing-frame geometry remains an optional diagnostic and no nearest
edge, uniqueness rule, or inferred quadrilateral may veto the accepted sample.

Boundary Discovery does not complete at a fixed application-selected travel
distance. It remains active until the operator stops at the observed side or a
real controller terminal condition ends the attempt. A controller limit, alarm,
disconnect, fault, or ambiguity yields Needs Attention and no boundary
evidence. Unambiguous finite-segment completion renews under the same logical
owner and is never a successful side observation.

The first side is operator-selected from X+, X-, Y+, or Y-. Its opposite is
forced next. The operator then chooses either sign of the remaining axis and the
fourth side is its forced opposite. Redo and Record Another Attempt explicitly
name a side. Each direction owns an accepted machine-space aggregate; the four
aggregate estimates derive an `EstimatedMachineCenter` and invertible
lower-side-origin `LearnedLocalCoordinateFrame`. The operator explicitly
starts one stoppable Pen Up move to that center. Neither the sides nor the center
become a manual-motion envelope.

Manual jog owns its own unique Stop capability and presents **Stop Manual Jog**
in the Motion panel. A stale capability cannot stop a later jog. The toolbar's
Motion Enabled state reports session authorization, including while the one
owner is busy; transient request availability and its exact refusal reason are
separate projections.

### 3.3 Visibility Target and Clear-View Registration

At the centered target pose, the armature remains in view. The app captures one
exact target-pose registration frame and proposes a `ToolContactPointEstimate`
and ROI. The initial estimator is the detected green component's bottom center,
not its centroid; it retains exact frame/configuration and algorithm provenance
and requires operator acceptance.

The operator searches for a Clear view with typed Pen Up moves. Each move names
a direction and 10, 5, 2, or optional 1 mm distance. It settles before a
strictly newer frame is labeled Blocked, Partial, or Clear. Blocked and Partial
continue the same transaction. A Clear label and matching observation establish
the repeatable Clear pose. The app then captures a blank ROI baseline at that
pose, returns to the registered target pose, and draws one 4 mm diameter regular
octagon under a single `VisibilityTargetOperation` owner. It returns Pen Up to
the accepted Clear pose and requires two compatible fresh frames to agree on the
existing target before visibility registration can be accepted.

Once Pen Down is accepted the paper is `inkPossible`. Cancellation, partial
completion, or ambiguity never redraws automatically. A compatible baseline can
be used to Observe Existing Target; otherwise recovery creates a new target-area
identity and requires an explicit Pen Up relocation before recapture, or records
Paper Replaced and increments both paper and target-area revisions.

## Observed Drawing Trials

The deterministic sequence is:

1. **4.1 Choose Isolated Line Plan** — select a visibility-target perimeter
   direction and define one 5 mm outward line;
2. **4.2 Capture Target-Anchored Baseline** — at the accepted Clear pose,
   capture a fresh frame in which the existing visibility target is present;
3. **4.3 Move to Line Start** — travel Pen Up to the selected perimeter point;
4. **4.4 Draw Isolated Line** — execute one closed line operation;
5. **4.5 Return to Clear Pose and Observe New Ink** — return Pen Up and capture
   strictly fresh compatible pixels;
6. **4.6 Compare Intended and Observed Geometry** — record a typed human
   comparison and, when registration is valid, quantitative residual geometry.

No stage redraws automatically. Quantitative comparison requires a compatible
`MachineCameraRegistrationFit` from at least three non-collinear accepted
machine/contact pairs, with transform residuals and uncertainty retained. Exact
frames, controller actions, registration, scene disposition, assessment, and
residual provenance remain attributable in memory.

## Simulator parity and isolation

SIMULATED uses the same one-window Learning Path, motion controls, camera
utilities, questions, and action strip as LIVE. Its typed in-memory runtime owns
a simulated session, Motion authorization, known MPos, pen pose, manual jog,
renewable Boundary operation, Stop/Cancel disposition, compound visibility
target operation, drawing operation, paper revision, persistent ink, and causal
deterministic frames. Every simulator evidence surface is marked
`SIMULATED — NOT PHYSICAL EVIDENCE`; the path invokes no `MachineActions` and
cannot create physical controller, camera, pen-pose, movement, or ink evidence.

The full simulated path cannot use pre-rendered discovery success frames.
Rendered pixels are derived from the simulated MPos, pen pose, operation
segments, camera geometry, paper identity, and retained ink. Mocked operator
actions must prove both initial direction variants, forced opposites, center
arrival, multi-move Blocked/Partial/Clear search, two-frame target agreement,
Stage 4 observation, target interruption recovery without redraw, and ambiguity
with no follow-on command.

One uniform world-to-camera transform auto-fits arbitrary translated or negative
truth bounds with declared padding and armature/protocol margin. Exact-frame
simulator truth and learned-evidence annotations are presentation-only and
cannot change canonical pixels, hashes, vision results, learning state, camera
registration, or physical authority.

Switching to SIMULATED parks accepted LIVE authority and starts a separate
simulated learning set. Returning to LIVE discards the simulated set and
restores the parked LIVE authority unchanged.

## Evidence hierarchy

Evidence is typed by what it actually establishes:

| Evidence | Establishes | Does not establish |
| --- | --- | --- |
| Controller acceptance | The controller accepted the wire command. | Completion or physical movement. |
| Idle plus final MPos | Controller-side settlement and reported final position. | Camera displacement or ink. |
| Exact camera frame | Pixels at one frame/configuration identity. | Pen height, movement intent, or drawing success by itself. |
| Vision measurement | An algorithmic camera-space estimate. | Human observation or machine authority. |
| Typed human label | What the operator reported for that context. | Independent sensor proof. |
| Observed ink | A physical mark is present in the compared scene. | Perfect intended geometry. |

Only observed ink proves a drawn mark. A model candidate, preview, `ok`, Idle,
or simulator frame cannot substitute.

## Step revisions, dependencies, and attempts

Each accepted step result is a typed artifact revision. It names the exact
attempt that produced it and the artifact revisions it actually consumed.
Normal execution remains sequential, but invalidation follows this dependency
graph rather than sequence number.

Redo This Step produces a replacement attempt. Once that attempt succeeds,
its artifact becomes current, the old accepted value becomes superseded, and all
transitive derived artifacts that consumed the old revision are invalidated.
Chronologically later but independent evidence is retained. Redoing the current
Pen Interaction result therefore does not discard recorded boundary
measurements; current Pen Up may still be required before any new movement.

Boundary Redo replaces the entire currently accepted aggregate for the named
direction and starts its successful replacement at N=1. A failed, refused,
cancelled, or ambiguous Boundary Redo preserves every prior included sample,
current aggregate, graph edge, center, arrival, local frame, and downstream
accepted authority.

Record Another Attempt preserves the existing valid attempts and adds one more.
The visible derived result is recalculated from every valid compatible attempt
and reports its sample count. Aggregation is type-specific:

- numeric and geometric measurements use a declared estimator and uncertainty;
- categorical observations use counts, proportions, or a typed posterior;
- current state facts use the latest accepted observation;
- exact frames, controller exchanges, text, identifiers, and ambiguity are
  retained individually and never averaged.

An attempt excluded because it is unclear, refused, ambiguous, or incompatible
remains visible evidence of that outcome. Boundary numeric aggregation groups by
direction, controller session, coordinate revision, machine coordinates,
millimetres, and numeric estimator revision, deliberately excluding camera
configuration. Optical registration independently requires compatible exact
frame, source, camera configuration, contact estimator, and algorithm identity.

## Episode and dataset contract

`ExplorationEpisode` remains a technical in-memory evidence record. It is not a
broad input session, workflow owner, persistent log, or replay mechanism. It may
retain:

- a unique evidence-session and episode identity;
- source (`live` or `simulated`);
- a data split assigned before action;
- typed proposed and executed action summaries;
- controller start/final evidence and ambiguity;
- exact frames and camera configuration;
- visibility target, observed ink, residual, human assessment, and termination.

Multiple attempts remain separate episodes or attempt records even when they
contribute to one typed aggregate. The aggregate references its included attempt
identities; it never replaces their exact provenance.

The word **training** is reserved for an actual model dataset partition or
fitting operation. There is no standalone Jog Observations workflow or online
jog-response diagnostic in the target product. A repeated physical observation
must belong to a numbered Learning Path exercise, retain that exercise's typed
attempt provenance, and enter only a compatible declared aggregate. Removing
the old diagnostic does not authorize replacing it with a hidden dataset or a
renamed compatibility action.

## Model targets

Near-term models should remain small and attributable:

1. **Paired boundary center** — retain four side observations and a typed
   controller-space midpoint with uncertainty.
2. **Tool contact and clear-view overlap** — retain the contact-point estimator,
   ROI, armature overlap, explicit search moves, and repeatable Clear pose.
3. **Machine-camera registration** — fit an affine transform from compatible
   non-collinear machine/contact pairs and retain residuals and uncertainty.
4. **Ink residual** — compare intended visibility-target-relative line geometry
   with observed new ink.
5. **Stroke and shape preference** — later, compare candidate physical outcomes
   using retained observed-ink evidence.

Models must retain units, coordinate spaces, frame/configuration identity,
algorithm revision, and uncertainty. Controller position must not be fused into
camera geometry without a current-session registration.

## Losses and rewards

Useful losses are local to an attributable experiment:

- endpoint and cross-track residual in camera pixels;
- observed versus intended displacement residual;
- failure to observe new ink;
- Clear-pose repeatability;
- operator comparison or ranking tied to the exact episode.

A loss summarizes evidence; it does not admit motion. Rewards must never hide a
controller refusal, ambiguity, missing exact frame, or unclear ink.

## Active learning

Active learning has one precise future meaning: a model selects among already
safe, typed candidate experiments to reduce uncertainty or disagreement. It is
not the name of the Learning Path, ordinary drawing adaptation, or every
operator interaction.

Any future selected experiment must still pass the same direct machine checks,
remain bounded, expose its proposed action, and require the evidence it consumes.
No model may choose arbitrary controller text, bypass current authorization, or
turn confidence into workspace admission.

## Adaptive Drawing boundary

Adaptive Drawing becomes implemented only when the app can:

- execute multiple attributable strokes;
- observe at defined checkpoints;
- distinguish absent/unclear ink from a successful mark;
- preserve sticky ambiguity and no-auto-redraw behavior;
- update or compare a model candidate from exact retained evidence;
- show what changed and why without converting the model into authority.

Until then, Stage 5 remains Future.

## Spoken output and buttons

Buttons own every question, label, assessment, progression decision, Cancel,
Stop, Restart, Redo, and additional-attempt request.
Spoken announcements are serialized output preceding relevant movement. The app
awaits a bounded completion outcome and rechecks the typed context. Output
failure is advisory and does not block the visible action or relax safeguards.

No audio-input acquisition, recognition state, ambient grammar, transcript
stream, or speech-owned workflow lifetime is part of this scope.

## Physical learning procedure

An attended physical pass should proceed only through the signed bundle:

1. verify one running bundled instance and the physical cutoff;
2. Connect and Enable Motion;
3. complete Pen Interaction and leave the pen explicitly observed Up;
4. choose the first Boundary direction, then record its forced opposite;
5. choose either sign on the remaining axis, then record its forced opposite;
6. verify each contextual Stop settles at Idle/final MPos with a strictly newer
   exact frame;
7. explicitly move to the estimated center;
8. register the contact point/ROI, search with explicit coarse-to-fine moves,
   and accept a Clear pose plus blank baseline;
9. draw the visibility target once, return Clear, and accept two-frame target
   observation;
10. execute the target-anchored Observed Drawing Trial and inspect actual ink
    before recording the typed comparison.

If no operator is present, physical validation is skipped. Automated tests,
simulator execution, and controller responses remain software/controller
evidence only.
