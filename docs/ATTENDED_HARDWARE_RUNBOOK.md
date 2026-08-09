# Attended Hardware Runbook

Status: current operator checklist for the integrated one-window workbench
Requirement: one operator present with the physical power cutoff reachable

## Purpose

This pass validates the integrated signed-bundle workflow from Connect through
one Observed Drawing Trial. It must keep controller, camera, human observation,
and observed ink claims separate.

Use this checklist only with the integrated one-window workbench and its typed
attempt, dependency, and operator-stopped Boundary Discovery behavior.

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

## 3.2 Paired Boundary Discovery and Centering

1. Choose whichever of X+, X-, Y+, or Y- is nearest to the current position and
   has a clear observable path.
2. Confirm the current action shows the controller-reported applicable feed
   ceiling and source. For a single-axis direction it must match that axis.
3. With the path clear and cutoff reachable, press the explicit **Start**. There
   is no generic YES/NO ceremony.
4. Confirm the complete spoken movement announcement finishes before motion.
5. Observe movement directly and press the one exercise-strip **Stop Boundary**
   once at the observed side. Do not press Cancel unless abandoning the attempt.
6. Verify one operator Stop event, one Jog Cancel, original-owner Idle/final
   MPos, one strictly newer exact frame/SHA/configuration, one typed
   bottom-center contact estimate, and one atomic accepted side aggregate.
7. Confirm the next direction is the forced opposite of the first. Repeat the
   same Start/Stop/settle/frame sequence.
8. Choose either sign on the remaining axis, then repeat its forced opposite.
9. Verify all four side aggregates are accepted and the UI shows local
   coordinates as primary learned-area presentation, raw signed controller MPos
   as provenance, both spans, the estimated local center, N, uncertainty, and
   consumed revisions.
10. Press the explicit **Move to Estimated Center** action and retain its Stop
    within reach. Verify Pen Up travel settles at Idle/final MPos before 3.3.

There must be no normal fixed-distance completion before Stop. A controller
limit, alarm, disconnect, or fault ends the attempt as Needs Attention and is
not a boundary observation. If an underlying finite segment completes while the
attempt remains healthy, continuation stays under the same logical owner and
must not duplicate after Stop or ambiguity.
Requested feed is not proof of achieved physical speed.

## 3.3 Visibility Target and Clear-View Registration

1. At the estimated center with Pen Up, capture the exact **Target-Pose
   Registration** frame. The armature is expected to be present; this is not the
   blank baseline.
2. Inspect the proposed target ROI and tool contact point. Confirm it refers to
   the marker contact location (initially the green component bottom center),
   not the cap centroid, then accept or reject it explicitly.
3. Choose a Pen Up Clear-search direction and one explicit 10, 5, 2, or optional
   1 mm move. Settle, capture a newer exact frame, and label it Blocked, Partial,
   or Clear. Blocked/Partial must keep the same transaction active.
4. Repeat coarse-to-fine moves until a reproducible Clear view is observed, then
   accept the Clear pose.
5. Capture the **Pre-Target Clear-View Baseline** and confirm the accepted ROI is
   blank. Record exact frame/configuration, MPos, paper revision, and ROI.
6. Press **Return to Registered Target Pose** and verify settlement.
7. Press **Draw Visibility Target** once. Verify one compound owner performs
   Pen Up approach, lower, eight forward segments forming a 4 mm regular
   octagon, eight reverse segments retracing that perimeter, and one raise.
   Record plan revision `visibility-target-octagon-double-trace-v2`; keep the
   one contextual Stop and cutoff reachable.
8. Press **Return to Accepted Clear Pose** and verify Pen Up settlement.
9. Press **Observe Existing Visibility Target**. Verify the exact target ROI is
   magnified, progress names both captures and both analyses, competing controls
   are refused, repeated Observe cannot queue, and only **Cancel Vision** remains.
   Then verify two strictly fresh compatible frames agree and list both IDs.
10. Accept the visibility registration only after inspecting the evidence.

If target drawing is cancelled, partial, or ambiguous after Pen Down acceptance,
do not redraw. Use Observe Existing Target only with the retained compatible
baseline, or explicitly register a new target area/paper revision. The Clear pose
and target evidence are local dependencies, not manual-motion gates.

## 4. Observed Drawing Trial

Proceed through the exact numbered actions:

1. **Choose Isolated Line Plan** — choose one target-perimeter direction and the
   displayed 5 mm outward line.
2. **Capture Target-Anchored Baseline** — at the accepted Clear pose, record one
   fresh frame in which the target is present.
3. **Move to Line Start** — verify Pen Up travel to the selected target
   perimeter point.
4. **Draw Isolated Line** — verify one closed stroke and no resend.
5. **Return to Clear Pose and Observe New Ink** — verify Pen Up settlement and a
   strictly fresh compatible post-line frame.
6. **Compare Intended and Observed Geometry** — inspect actual ink, then choose
   one typed assessment and inspect quantitative residual only when the current
   affine registration is valid.

Record exact target-baseline/post frame identities, controller start/final MPos,
registration identity/residuals, observed new ink, intended/observed overlay,
line residual when available, and the human comparison.

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
