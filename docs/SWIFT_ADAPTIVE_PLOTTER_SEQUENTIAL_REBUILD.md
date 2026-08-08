# AdaptivePlotter Direct Implementation Plan

Status: ordered action backlog
Canonical learning contract: [Project Scope and Learning Architecture](PROJECT_SCOPE_AND_MODEL_TRAINING.md)

## Prompt for the implementation team

Build the smallest local Swift macOS application that can move this attached
plotter, see what it did, ask the operator for fast spoken feedback, and make the
next action more informed. Optimize for physical learning and short iteration
time.

Use `AGENTS.md`, the repo-local AdaptivePlotter skill, and one Blackdog task
workspace for retained changes. Use focused tests while iterating, run
`make check` before landing, and try the actual hardware as soon as a typed
operation is available and the operator is present. Hardware absence does not
block coherent software landing; it leaves the physical claim pending.

No phase document, readiness package, historical replay, generalized model
framework, or polished UI is required for an ordinary feature.

## Fixed product contract

- One local native Swift process owns controller, camera, voice, vision,
  exploration context, and UI.
- One remembered controller picker, explicit Connect/Disconnect, and explicit Activate
  Motion action are the complete operator startup surface.
- Starting an `ExplorationSession` once keeps speech listening active across
  Motion Preflight and later learning episodes. There is no separate listening
  toggle and no sequence-owned microphone lifecycle.
- Voice has a contextual reflex lane for closed typed actions and a flexible
  teaching lane for labels, rankings, features, and rewards. Neither path can
  emit raw G-code.
- Actual observed ink is drawing authority. Controller `ok`, Idle, MPos, cap
  movement, simulation, or human preference alone is not proof of a drawn line.
- Learning evidence cites exact selected frames and attributable controller and
  speech context. This compact current learning dataset is not an archival
  replay product.
- No operator-entered coordinates, travel envelope, maximum-jog value, firmware
  travel setting, or learned drawing-frame bound admits ordinary motion.
- No automatic resend, redraw, unlock, home, reset, settings write, alarm clear,
  or resume after ambiguity.
- No live Python, HTTP bridge, network speech dependency, release pipeline,
  CI program, accessibility program, or multi-machine abstraction.

## Working method and risk posture

For each slice:

1. Define one closed action and the observation or human label that makes its
   outcome attributable.
2. Exercise the complete flow in the deterministic simulator.
3. Put the smallest useful action in the native UI with concise visible and
   spoken feedback.
4. Run it on the attached replaceable machine when the operator is beside the
   physical cutoff.
5. Treat a model miss, recognition miss, or failed visual extraction as data and
   continue with a corrected or different experiment.
6. Stop only the affected physical operation on a current alarm/asserted limit,
   disconnect, unexpected actuation, physical mismatch, or sticky ambiguity.
7. Land the coherent software increment with automated and physical claims
   clearly separated.

The words “finite” and “deadline-bounded” describe a closed request and its
completion wait. They do not create an operator-entered workspace bound or a
global maximum-jog gate.

## Direct motion eligibility

Activate Motion is the only operator arming action. Every command immediately
checks only what it consumes:

- selected responsive controller and activated Motion Guard;
- no current alarm, relevant asserted end stop, disconnect, or unsupported
  controller state;
- one in-flight owner and no earlier ambiguous outcome;
- finite closed request and feed within controller-reported axis capability;
- known appropriate pen state;
- current exact camera frame only for an operation whose purpose requires
  vision.

Incomplete Motion Preflight, a missing learned boundary, unavailable model,
low vision confidence, or absent camera for an ordinary manual jog does not
disable unrelated motion. Correct a refusal and retry immediately.

## Landed base

The current implementation and hardware evidence are recorded only in
[Current Implementation Status](implementation/CURRENT_IMPLEMENTATION_STATUS.md)
and [First Hardware Session](implementation/FIRST_HARDWARE_SESSION.md). In
summary, controller contact, typed pen actuation, 1 mm X/Y round trips, exact
C920 analysis, Motion Preflight transactions, heuristic drawing-frame updates,
current-session jog-response fitting, and affine training primitives exist. The
per-side posterior specified below is not yet implemented.

Do not rebuild those capabilities. The remaining plan begins at their current
interface boundaries.

## Work item 1 — Persistent ExplorationSession

Replace sequence-owned speech lifetime with one Learning-owned session:

```text
Start Exploration
-> microphone remains warm
-> active episode supplies parser context
-> typed reflex intent or structured teaching label
-> action/assessment/brief feedback
-> next episode
-> explicit End Exploration or terminal failure
```

Deliver:

- explicit session state, active learning rung/episode, permission/listening
  state, latest transcript/intent/label, concise feedback, and failure;
- barge-in that immediately stops app speech;
- stable-partial `STOP` with duplicate suppression for one utterance;
- final/stable contextual continue, reverse, direction, accept, again, skip,
  and end-session intents only where the active episode declares them;
- a teaching-label path that can store flexible visibility and preference
  feedback without synthesizing controller commands;
- timing points for recognition, intent dispatch, action settlement, next frame,
  assessment, and feedback;
- clean microphone teardown on end, permission loss, app shutdown, or an
  unrecoverable recognition failure.

Motion Preflight uses the current question's visible `YES`/`NO`/`STOP` choices
for both buttons and optional speech. The persistent session's reflex grammar
remains contextual; do not replace either path with ambient arbitrary motion.

Done when the simulator runs at least two consecutive episodes without
restarting the microphone, operator speech interrupts machine speech, and no
out-of-context transcript reaches `MachineActions`.

## Work item 2 — Physical Motion Preflight episode

Use the persistent session to exercise the physical Pen Cycle and one
relevant boundary sequence on the attached machine. The Pen Down/Up first-mark
transaction belongs to the anchored isolated-line episode below. Starting an
episode may speak one short cue; it must not read instructions or require a
separate listening action.

An accepted boundary observation is:

```text
selected side
+ cancelled jog final controller MPos at Idle
+ strictly newer exact-frame tool centroid
+ unchanged camera configuration
```

Replace the current heuristic quadrilateral average with one image-space offset
and uncertainty per selected side. The sequence supplies side identity; the
strictly newer tool centroid plus observation variance updates that side,
repeated observations narrow uncertainty, corners derive from edge
intersections, and the live overlay updates. Final MPos remains provenance and
repeatability context until a registration gives it image-space meaning.
Reaching the finite search horizon is ordinary motion completion and supplies
no boundary. Missing other sides remain uncertain and do not block motion.

For a side's first observation, associate the machine-side label with the
nearest candidate camera edge only when a configured distance margin makes the
choice unique. Persist it for that camera configuration; initialize orientation
from the candidate edge and use a broad prior variance. An ambiguous association
records no posterior observation and blocks no motion.

Done when physical Jog Cancel latency and final-MPos/new-frame posterior update
are observed once without automatic resend. Simulation and tests cannot satisfy
this physical claim.

## Work item 3 — Armature Guidance

Armature Guidance is the first visibility and pose-selection episode. Establish one fixed ink
observation region and move pen-up through small closed actions while comparing
vision's visibility estimate with the operator's spoken ground truth:

```text
CLEAR | PARTIAL | BLOCKED
KEEP GOING | REVERSE | STOP
ACCEPT THIS POSE
```

Deliver:

- one exact frame, controller MPos, conservative armature/region overlap
  estimate, human label, and outcome per pose;
- labelled pose observations and one accepted clear-pose fact; fit a visibility
  estimate only after multiple nonduplicate poses;
- one operator-accepted current-session clear pose and a typed pen-up return
  path;
- active selection of the next nearby pose when another observation is useful;
- visible clear/partial/blocked estimate and disagreement, without making model
  confidence a motion gate.

Start with one clear-pose fact. Add a small pose/visibility model only when more
than one observation is useful. Do not build 3D kinematics, generalized
collision planning, or a full-field occlusion map.

Invalidate automated clear-pose return after controller coordinate reset or
reconnect, camera-configuration or observation-region change, or tool/paper
change. That invalidates the automated return only; manual motion remains.

Done when the simulator and then the operator identify one repeatable clear
pose from which the current ink region is visible.

## Work item 4 — One isolated ink line

Implement the first complete drawing observation:

```text
capture exact clean reference at the clear pose
-> move pen-up to one known start
-> transact Pen Down confirmation then Pen Up to create one anchor dot
-> return clear and capture an exact anchored baseline
-> detect the new dot and bind its camera centroid to the start MPos
-> return pen-up to the recorded start
-> pen down
-> execute one closed short stroke
-> pen up
-> return to the Armature Guidance clear pose and settle
-> capture a strictly newer exact frame after settlement
-> isolate newly added green ink
-> fit endpoints/centreline
-> show intended, predicted, observed, and residual geometry
-> record one ExplorationEpisode
```

Ordinary relative jog must continue to require Pen Up. Pen-down XY motion needs
its own closed stroke request and controller owner. Missing or unclear ink shows
the exact frame and reason; it never triggers automatic redraw. The first large
residual is useful evidence, not a failed project.

Camera-space residual requires a current machine-delta-to-camera-delta
projection. If none exists, collect two linearly independent accepted observed
pen-up jogs in that session or label the physical residual unavailable. The
projection is measurement context, never motion authority.

The intended camera line starts at the detected anchor-dot centroid and ends at
that point plus the projected actual stroke delta. The anchored frame is the
line baseline, so the dot is not misclassified as new line ink. Without both the
anchor and projection, report only displacement/orientation measurements and
label absolute camera-space residual unavailable.

Done when one real command produces one attributable visible line and the app
shows its residual. Controller evidence without new ink does not satisfy this
definition.

## Work item 5 — Geometric learning

First create one provenance-bearing current-session `FieldRegistration` from
the accepted drawing-frame estimate and exact camera configuration. Until that
bridge exists, isolated-line evidence and residuals remain in
`CameraPixelSpace` and cannot enter the existing machine-to-`FieldSpace`
trainer. The registration is model context, not motion authority.

Then admit isolated-line episodes to the existing affine drawing-model boundary:

- assign training/reserved membership before each outcome;
- fit only training observations;
- report training and held-out endpoint/centreline RMS and maximum error;
- keep any constant tool/ink offset fixed until separate evidence identifies it;
- accept a candidate only when reserved error improves;
- apply a new immutable version only at a pen-up or run-complete checkpoint;
- pin one model version through every pen-down stroke.

If the affine mapping is adequate, stop increasing geometric complexity. A
failed candidate does not disable drawing or further experiments.

## Work item 6 — Stroke and shape preference

Draw small fixed candidate sets, beginning with simple line/stroke recipes and
then four hearts. Collect pairwise or best-of-set spoken feedback plus optional
features such as closure, width, symmetry, or smoothness.

Combine objective ink residual with a small contextual preference model. Keep
reserved shapes/locations for evaluation. Do not build a general aesthetic
model or neural generator.

Done when the next candidate set is measurably more likely to match the
operator's held-out choices without regressing geometric error or ambiguity.

## Work item 7 — Active selection and bounded policy learning

First choose experiments with a separate acquisition score based on expected
information gain or model disagreement. Then
evaluate a policy in shadow mode against the deterministic baseline. Use
reinforcement learning only when sequential choices have meaningful future
effects.

Reward may combine:

```text
- geometric loss
+ human visibility/shape reward
- motion and elapsed-time cost
- intervention, ambiguity, and non-completion penalty
```

Do not add acquisition score to product reward. Promote a policy only on
external held-out ink/preference quality, time/intervention, ambiguity, and
completion; otherwise it can improve its score merely by seeking uncertainty.

The policy chooses only enumerated finite macro-actions. It cannot bypass the
MachineController, emit controller text, change the pen profile, home, unlock,
reset, write settings, or promote itself. Begin with a contextual bandit if the
problem is one-step; use sequential RL only when the data demonstrates delayed
credit assignment.

Done when held-out/shadow evaluation beats the baseline and a small operator-
supervised physical batch improves reward without more ambiguity or emergency
intervention.

## Work item 8 — Continuous adaptive drawing

Run a small multi-stroke `DrawingProgram` with the accepted geometric model and
policy pinned for each pen-down stroke. Observe after each stroke initially,
update only at pen-up checkpoints, and keep voice available for interruption and
occasional teaching. Reduce intervention frequency only after physical runs
show that passive supervision is credible.

Portrait-to-vector input comes after this path works. It gets no controller,
camera, safety, model-promotion, or persistence authority.

## Minimal UI contract

Keep the camera dominant. Show only:

- remembered controller selection, Connect, Activate Motion, and truthful
  camera/controller/motion indicators;
- current ExplorationSession/listening state and active episode;
- latest transcript/intent or teaching label;
- current action, machine/vision assessment, and concise feedback;
- Armature Guidance visibility/clear pose;
- intended/observed ink and residual;
- Run, `STOP`/Cancel Stroke, physical-cutoff reminder, and End Exploration where
  applicable.

An active participant/action/observation timeline is useful. Historical replay,
model/trial browsers, storage dashboards, generalized workflow UI, and
operator-entered calibration forms are not.

## Completion definition

The initial active-learning product slice is complete when:

- one persistent voice session survives Motion Preflight and Armature Guidance;
- the operator can stop and redirect motion without looking away from the
  machine;
- one physical boundary observation visibly updates the frame posterior;
- one clear pose is taught from human/vision agreement;
- one isolated real line is anchored and extracted from exact clean-reference,
  anchored-baseline, and post-line frames and shown against its intended
  geometry;
- the episode contains attributable controller, frame, model, speech, and human
  feedback;
- no entered bounds, readiness ceremony, automatic redraw, or alternate machine
  authority exists;
- normal build/tests and Blackdog landing pass.

The next copy-paste implementation handoff is
[Next Slice Multi-Agent Execution Prompt](implementation/NEXT_SLICE_MULTI_AGENT_PROMPT.md).
