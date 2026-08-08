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
| 3 Human-Guided Discovery | Observe pen interaction, one or more boundaries, and a Clear pose. | Presentation and local evidence only. |
| 4 Observed Drawing Trials | Create attributable marks, clear the tool, observe ink, and compare geometry. | Presentation and local evidence only. |
| 5 Adaptive Drawing | Multi-stroke drawing with observation and checkpoint learning. | Future until implemented. |

Learning status does not authorize ordinary movement. Manual motion continues to
depend only on direct machine facts. A stage action may require the evidence it
actually consumes.

## Human-Guided Discovery

### 3.1 Pen Interaction

The operator answers typed YES/NO questions about physical pen pose. Lower and
raise commands are announced before actuation and settle through the controller
owner. The sequence succeeds only after the final human confirmation of Up.
Commanded pen state and observed physical pose remain distinct evidence.

### 3.2 Boundary Discovery

The operator selects a side, confirms the path is clear, and starts one bounded
Pen Up jog. One contextual Stop records the choice before one cancel byte is
issued. The original owner settles at Idle with final MPos; a strictly newer
exact frame then supplies the tool centroid and drawing-frame side association.

One successful relevant side is sufficient for the current path. Additional
directions refine the current-session posterior but are not required for manual
motion or Clear-View Discovery.

### 3.3 Clear-View Discovery

The operator labels the exact current frame Blocked, Partial, or Clear. A Clear
label and its matching armature observation may establish a repeatable Pen Up
pose for vision-consuming drawing trials. It is not a workspace boundary or a
manual-motion gate.

## Observed Drawing Trials

The deterministic sequence is:

1. capture an exact clean reference;
2. choose and retain a controller line start;
3. create one attributable anchor mark;
4. draw one closed isolated line;
5. return the tool to the accepted Clear pose and capture post-line pixels;
6. record a typed human comparison of intended and observed geometry.

The three-frame clean/anchor/post subtraction may produce an
`IsolatedInkObservation` with residual geometry. A rejection records
`Ink or Geometry Unclear` and never causes a redraw. The episode retains exact
frame, controller, action, assessment, and residual provenance in memory.

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
- anchor, observed ink, residual, human assessment, and termination.

The word **training** is reserved for an actual model dataset partition or
fitting operation. The current online jog-response dataset uses preassigned
training and reserved observations to fit and evaluate a through-origin
camera-displacement diagnostic. That candidate grants no motion authority and
is not promoted automatically.

## Model targets

Near-term models should remain small and attributable:

1. **Tool displacement response** — estimate camera-pixel displacement from
   closed Pen Up X/Y jogs within one camera configuration.
2. **Drawing-frame side posterior** — associate exact-frame boundary
   observations with camera-space sides and retain uncertainty.
3. **Clear-view overlap** — summarize observed armature/tool overlap in one
   exact camera region and propose a repeatable Clear pose.
4. **Ink residual** — compare intended anchor-relative line geometry with
   observed new ink.
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

Buttons own every question, label, assessment, progression decision, and Stop.
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
4. choose one Boundary Discovery direction;
5. confirm the spoken cue finishes before movement;
6. press Stop once at the observed boundary;
7. verify Idle/final MPos and a strictly newer exact frame;
8. accept a Clear view;
9. execute one Observed Drawing Trial;
10. inspect actual ink before recording the typed comparison.

If no operator is present, physical validation is skipped. Automated tests,
simulator execution, and controller responses remain software/controller
evidence only.
