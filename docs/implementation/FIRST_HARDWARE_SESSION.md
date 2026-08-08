# Attended Hardware Session

Status: operator checklist after the accepted one-window workbench increment lands
Requirement: one operator present with the physical power cutoff reachable

## Purpose

This pass validates the integrated signed-bundle workflow from Connect through
one Observed Drawing Trial. It must keep controller, camera, human observation,
and observed ink claims separate.

Do not use this checklist against the superseded auxiliary-window build. First
land the one-window workbench, typed attempt semantics, Jog Observations removal,
and operator-stopped Boundary Discovery described by the canonical plan.

Do not run this checklist unattended. If the operator or reachable cutoff is
absent, stop and record physical validation as skipped.

## Before launch

1. Place the mechanism and paper where the operator can see them directly.
2. Keep the physical power cutoff reachable.
3. Confirm the intended camera and controller are attached.
4. Inspect all AdaptivePlotter processes:

   ```sh
   ps -axo pid=,command= | rg '[A]daptivePlotter'
   ```

5. Close any raw SwiftPM executable manually. Do not kill an unknown or
   user-owned process from an automated check.
6. Ensure no duplicate bundle instance owns camera or serial resources.

## Supported launch

Run from the repository root:

```sh
make run-app
```

The command must build and validate the signed
`com.bullard.AdaptivePlotter` bundle, then use LaunchServices. Expected outcomes:

- no existing instance: launch one exact bundle and report its PID;
- one exact existing instance: activate it and report its PID, with an explicit
  warning that rebuilt bits are not loaded into that process;
- raw, wrong-path, or duplicate instance: refuse with PID/path and launch
  nothing.

After a successful launch, verify one process, the expected bundle/executable,
regular foreground activation, and Dock/application-switcher presence. Do not
use the raw executable for camera or hardware validation.

Verify the singleton main frame shows the resizable Learning Path navigator,
always-mounted camera, and selected exercise region together. The camera must
remain visible while navigating and acting. There must be no Open Learning Path
action, auxiliary Learning Path window, standalone Jog Observations surface, or
exercise-specific toolbar Stop.

## 1. Connect

1. Select `/dev/cu.usbserial-A10OF67O` if it remains the attached controller.
2. Press **Connect**.
3. Verify the UI reports Plotter Connected only after the current responsive
   inspection.
4. Record controller identity, state, pins, MPos, reported X/Y feed limits, and
   any actionable refusal.

A connected USB controller does not prove motor power. Keep that claim
unverified unless observed independently.

## 2. Enable Motion

1. Confirm controller state is Idle and no relevant limit input is asserted.
2. Press the one visible **Enable Motion** action.
3. Verify the status reads Motion Enabled.
4. Confirm there is no second arming/deactivation control in the Motion panel.

Enable Motion authorizes only direct typed operations for this controller
session. It does not establish a workspace envelope or learned boundary.

## 3.1 Pen Interaction

1. Select Pen Interaction in the integrated Learning Path and verify the exact
   five stages remain visible.
2. Press the exercise action strip's green **Start**.
3. Observe the mechanism before answering whether the pen is Up.
4. Confirm the visible lowering cue appears first.
5. Confirm the complete spoken lowering announcement finishes before actuation.
6. Answer whether the observed physical pen is Down.
7. Confirm the visible raising cue and complete spoken announcement precede the
   raise command.
8. Observe and answer that the final physical pen position is Up.
9. Verify Stage 3 advances to Boundary Discovery.

Record separately:

- controller command acceptance/settlement;
- commanded pen state;
- human-observed pen state;
- exact captured frame identity.

Do not infer pen height from controller state or one camera frame.

## 3.2 Boundary Discovery

1. Select one direction with a clear observable path.
2. Confirm the current action shows the controller-reported applicable feed
   ceiling and source. For a single-axis direction it must match that axis.
3. Answer YES only when the path is clear and the cutoff is reachable.
4. Confirm the complete spoken movement announcement finishes before motion.
5. Observe movement directly.
6. Press the one exercise action strip **Stop** once at the observed boundary.
7. Do not press any secondary cancellation control; none should exist.

Verify and record in order:

1. one contextual operator Stop event;
2. one Jog Cancel request;
3. original jog owner reaches Idle;
4. final MPos is retained;
5. exact camera frame is strictly newer than controller settlement;
6. selected side measurement/posterior is accepted, or the UI gives a precise
   current reason;
7. the Learning Path advances to Clear-View Discovery after this one relevant
   boundary.

There must be no normal fixed-distance completion before Stop. A controller
limit, alarm, disconnect, or fault ends the attempt as Needs Attention and is
not a boundary observation. If an underlying finite segment completes while the
attempt remains healthy, continuation stays under the same logical owner and
must not duplicate after Stop or ambiguity.
Requested feed is not proof of achieved physical speed.

## 3.3 Clear-View Discovery

1. Use typed Pen Up moves only as needed to expose the tool/paper scene.
2. Label exact frames Blocked or Partial as observed.
3. Label an exact current frame Clear only when the operator agrees.
4. Confirm **Accept Current Clear View** remains disabled until the current
   runtime label and observation are Clear.
5. Accept the Clear pose.

The accepted pose supports vision-consuming travel in this session. It is not a
manual-motion gate.

## 4. Observed Drawing Trial

Proceed through the exact numbered actions:

1. **Capture Clean Reference** — record the exact clean frame/configuration.
2. **Choose Line Start** — record current controller MPos.
3. **Create Anchor Mark** — verify announced lower/raise ordering and observe the
   anchor after the tool returns Clear.
4. **Draw Isolated Line** — verify one closed stroke and no resend.
5. **Clear Tool and Observe Ink** — verify Pen Up travel uses the appropriate
   reported ceiling and the tool returns Clear before the post frame.
6. **Compare Intended and Observed Geometry** — inspect actual ink, then choose
   one typed assessment.

Record exact clean/anchor/post frame identities, controller start/final MPos,
observed new ink, intended/observed overlay, residual when available, and the
human comparison.

If ink or geometry is unclear, select that outcome. The app must not redraw
automatically.

## Negative checks

During the pass verify:

- no audio-input permission prompt or input-level presentation appears;
- buttons remain usable if spoken output fails or times out;
- no ambient speech can answer, move, or Stop;
- no standalone Jog Observations control or online jog-response diagnostic is
  presented as part of the Learning Path;
- ordinary manual XY jog remains available from direct machine facts without
  requiring Learning Path completion;
- SIMULATED mode cannot reach controller actions or create physical evidence;
- exactly one app instance owns camera and serial resources.

## Stop conditions

Stop the attempt immediately if:

- the operator loses direct view or cutoff access;
- an unexpected instance owns camera or serial resources;
- controller state, pins, position, pen state, or sticky ambiguity is unclear;
- movement starts before its full spoken cue finishes;
- one action-strip Stop emits more than one cancellation;
- Boundary Discovery ends normally at an application-selected travel distance
  instead of waiting for Stop;
- the original owner does not settle at Idle with final MPos;
- frame provenance crosses camera configurations;
- the app proposes resend, resume, or redraw after uncertainty;
- UI status is being treated as physical movement or ink evidence.

## Report format

Report four sections independently:

1. **Automated** — exact commands and results.
2. **Controller/camera** — wire settlement, MPos, frame/configuration, and
   requested feed.
3. **Human-observed** — physical pen pose, motion, Clear view, and cutoff access.
4. **Ink-observed** — whether a mark exists and how intended/observed geometry
   compares.

An incomplete section remains explicitly unverified; do not fill it from another
evidence class.
