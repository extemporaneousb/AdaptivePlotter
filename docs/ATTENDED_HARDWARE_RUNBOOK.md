# Attended Hardware Runbook

Status: attended physical procedure; never an automation recipe

This runbook owns the human procedure for validating the sparse tip workflow on
one real plotter, camera, pen, and paper. Product meaning is defined by
[Product Contract](PRODUCT_CONTRACT.md); exact software sequencing is defined by
[Discovery and Observed-Trial Protocol](DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md).
Record results in [Current Evidence](CURRENT_EVIDENCE.md) without upgrading a
claim beyond what was directly observed.

## Attendance and stop rules

Do not begin unless one operator can see the mechanism and paper continuously
and can reach the physical power cutoff. This is not an unattended test.

Stop immediately after any unexpected motion, controller alarm, disconnect,
unknown Pen state, ambiguous Pen Down/Up, uncertain circle motion/contact, camera
identity change, paper shift, tool change, or loss of direct view. Do not resend,
resume, retap, redraw, or choose ours/theirs-style recovery. Preserve the app's
state and record the exact visible/controller outcome.

A click asserts a pixel location. It does not prove a physical mark exists.
Only the operator's direct observation and the captured paper can support a
physical-ink claim.

## Preconditions

1. Use a disposable sheet with room for five 4 mm-diameter circular marks and one isolated
   5 mm line.
2. Confirm the pen, holder, cap landmark, camera, mount, crop/orientation, paper,
   and controller are the intended unchanged assembly for this run.
3. Confirm the mechanism is clear and the physical cutoff is reachable.
4. Inspect existing processes with `ps -axo pid=,command= | rg '[A]daptivePlotter'`.
   Do not terminate an unknown or user-owned process.
5. From the repository root, build and validate the signed bundle with
   `make app` and `make validate-app`.
6. Launch only with `make run-app`. Do not use the raw SwiftPM executable for
   camera or controller validation.
7. Confirm exactly one intended bundle instance owns the camera and serial
   resources.

Record the commit, bundle path, macOS/Swift version, controller identity and
settings, camera/device identity, pen/tool description, paper description, and
operator name or identifier.

## 1. Establish machine-space authority

1. Connect the intended controller and request the passive probe.
2. Verify current units, distance mode, coordinate system, settings digest,
   pins, Pen state, Idle state, and MPos are expected.
3. Enable Motion only after those facts are acceptable.
4. Complete Pen Interaction without bypassing an unknown pose.
5. For X−, X+, Y−, and Y+, choose the direction explicitly, start Boundary
   Discovery, watch the motion, and use the operation's exact **Stop**.
6. Confirm each accepted side cites the selected direction plus final Idle/MPos.
   Camera advice must not identify or veto the side.
7. Move to the derived center and confirm the final MPos meets the displayed
   0.05 mm settlement policy.

Any ambiguous or out-of-tolerance result ends this run. It is not evidence for
the requested side or center.

## 2. Stage 3.3 — camera and visible-cap calibration

1. Confirm Pen Up and an unobstructed camera view of the complete five-position
   cross.
2. Start **Capture Five Cap Samples**.
3. Observe Pen-Up travel through `C`, `X−`, `Y+`, `X+`, and `Y−`.
4. At each pose, confirm the carriage settles before the exact frame is used and
   that the cap landmark is the visible cap bottom-center, not the hidden tip.
5. Review the three-fit/two-holdout proposal. Both holdouts must pass.
6. Accept only if source, dimensions, optical setup, applicability rectangle,
   residuals, and correspondence roles are correct.

Do not accept after a camera/device/mount/crop/orientation/focus change. Restart
the attended run with explicit invalidation and new evidence.

## 3. Stage 3.4 — five sparse 2 mm-radius circles

For each of `C`, `X−`, `Y+`, `X+`, and `Y−`:

1. Press **Create Next 2 mm Circle** once.
2. Watch Pen-Up travel to the intended MPos and confirm it settles.
3. Confirm the pre-mark frame and cap-map check are current.
4. Watch Pen-Up travel 2 mm to the circle start and confirm settlement.
5. Confirm the app commands the fixed complete lower profile (`M3 S760` and
   0.3 s settlement). Directly observe whether the mechanism actually reaches
   the paper; the command outcome alone is not physical proof. Stop the run if
   the pen does not fully lower. Do not increase the spindle value ad hoc.
6. Watch one closed 4 mm-diameter circle complete as 16 short chords at no more
   than 100 mm/min, then one explicit Pen Up. Any stop, hesitation, unexpected path, or ambiguous chord
   ends the calibration and blacklists that circle location.
7. Confirm Pen Up settles, then watch reveal travel go to the learned safe X+
   limit and toward machine Y=0. Confirm the armature is materially clear of
   the entire circle before accepting the frame.
8. Confirm the displayed frame is frozen after reveal settlement and opens at
   the stronger one-third-frame presentation focus.
9. Before clicking, verify no predicted tip point or residual is shown.
10. Click the observed center of the new physical black circle.
11. After clicking, review the cyan asserted point and uncertainty, purple model
   prediction, and orange residual. Presentation zoom may help view the pixels;
   it must not change the selected camera coordinates.
12. If the click is wrong, use **Re-click This Exact Frame**. Confirm that no
    motion or ink action occurs.
13. Use **Accept Mark Center** only when the click and provenance are correct.

If any chord, contact, or Pen state is ambiguous, stop. The circle center/radius
on this paper is blacklisted. Do not retry it or reset around it. The only
same-workflow recovery is an explicit paper replacement.

After five accepted observations, review the model form, fit roles, two sealed
holdouts, residuals, covariance/uncertainty, applicability, semantic identities,
and consumed revisions. **Accept Tip Calibration** only if they are coherent.
Rejecting causes no motion or redraw and requires a new physical attempt.

## 4. Checkpoint recovery branches

Test these only as separately recorded attended cases; neither is implicit
restoration.

- Same unchanged paper and assembly after app/capture restart: choose
  **Revalidate Saved Tip Calibration**. Confirm a fresh settled controller/cap
  frame is captured, no contact mark occurs, and a new accepted tip revision is
  derived from the quarantined checkpoint.
- Explicit paper replacement: record the replacement, rebuild current machine-
  camera authority if required, then create one new 2 mm-radius center circle
  and click it. Confirm exactly one new mark is used as contact-plane evidence
  and the restored tip revision consumes it.

If any semantic identity is uncertain, do not revalidate. Clear the durable tip
checkpoint and perform a new five-mark calibration.

## 5. Stage 4 — isolated observed line

1. Record the exact current tip registration revision.
2. Choose one signed-axis 5 mm line plan.
3. Capture the trial-local pre-line baseline and record its Pen-Up reveal MPos.
4. Watch Pen-Up travel settle at line start.
5. Draw once under the single drawing owner. Do not resend after ambiguity.
6. Return Pen Up to the same trial-local reveal MPos and require settlement.
7. Capture a strictly newer post-line frame.
8. Review intended, predicted, and observed geometry only if the exact tip
   revision remains current.
9. Record the operator assessment. It may retain candidate refinement evidence;
   it must not silently change the accepted model.

## Evidence record

For each section record `passed`, `failed`, or `skipped`, plus exact identities
and failure text. Keep these claims separate:

- controller acceptance and final Idle/MPos;
- camera frame/source/semantic optical provenance;
- operator click and direct observation;
- Pen Down/Up and motion chronology;
- physical mark and line observations;
- software/simulator results.

If any physical section was not performed, write that it was skipped. A clean
build, a passing simulator journey, and a signed bundle are not camera,
controller, pen, operator-click, or observed-ink validation.
