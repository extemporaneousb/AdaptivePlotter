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
4. Start Pen Interaction. Its first action is **Identify Pen Cap**. Confirm the
   app freezes one current exact frame before any pen question or actuation, then
   click a visibly colored area of the cap body, not the tip. Confirm the
   accepted learned color visually corresponds to the cap and that the recorded
   frame/source/configuration/click provenance and sample counts are current.
   Reject stale-frame, gray/white/dark, or insufficiently chromatic samples;
   do not work around refusal with a color picker.
5. Complete the Up → Down → Up sequence. Use the Up and Down sliders to choose
   functional values at the current position; **Next** accepts the displayed
   value even if the request was refused or ambiguous. Record the values and
   whatever controller outcome, timestamp, and MPos are available. A fresh
   session is seeded at `S40` and `S760`; repeated attempts start with the
   current values and may legitimately differ by position.
6. For X−, X+, Y−, and Y+, choose the direction explicitly, start Boundary
   Discovery, watch the motion, and use the operation's exact **Stop**.
7. Confirm each accepted side cites the selected direction plus final Idle/MPos.
   Boundary renewal uses fixed bounded controller segments and never consults
   Camera or Vision advice.
8. Move to the derived center and confirm the final MPos meets the displayed
   0.05 mm settlement policy.

Any ambiguous or out-of-tolerance result ends this run. It is not evidence for
the requested side or center.

## 2. Stage 3.3 — camera and visible-cap calibration

1. Confirm Pen Up and an unobstructed camera view of the complete five-position
   cross. Confirm Stage 3.3 is using the accepted **Identify Pen Cap** appearance
   from Pen Interaction and exposes no independent color-editing control.
2. Start **Capture Five Cap Samples**.
3. Observe Pen-Up travel through `C`, `X−`, `Y+`, `X+`, and `Y−`.
4. At each pose, confirm the carriage settles before inspection. Confirm the app
   accepts exactly three strictly newer source/configuration-compatible LIVE
   frames, each with one unambiguous cap candidate; refuses more than 2 px
   maximum pairwise cap-centroid spread; and retains only the newest third exact
   frame and measurement without averaging. The preliminary freshness frame is
   not accepted evidence. The cap landmark is the visible cap bottom-center, not
   the hidden tip.
5. Review the three-fit/two-holdout proposal. Both holdouts must pass.
6. Accept only if source, dimensions, optical setup, applicability rectangle,
   residuals, and correspondence roles are correct.

Do not accept after a camera/device/mount/crop/orientation/focus change. Restart
the attended run with explicit invalidation and new evidence.

## 3. Stage 3.4 — five sparse 2 mm-radius circles

Confirm Stage 3.4 lists fixed offsets of 30 mm from `C`; Stage 3.3 remains on its
separate existing ±24 mm camera-calibration plan.

1. Press **Draw Five 2 mm Circles** once.
2. For each of `C`, `X−`, `Y+`, `X+`, and `Y−`, watch Pen-Up travel settle at
   the intended MPos, confirm the pre-mark frame/cap/controller evidence is
   retained, and watch Pen-Up travel settle at the circle start.
3. Confirm the app commands and settles the current Pen Interaction Down value.
   Directly observe physical contact; the command outcome alone is not proof.
4. Watch one closed 4 mm-diameter circle complete as 16 short chords at no more
   than 100 mm/min. Confirm Pen Up settles before any travel toward the next
   circle. Across the batch, confirm exactly five separated circles and no
   connecting ink stroke.
5. Confirm there is no reveal, frame selection, or click request between
   circles. After the fifth circle only, watch one Pen-Up reveal go to the safe
   X+ limit and toward machine Y=0, then confirm Idle/final-MPos settlement.
6. Confirm the app captures one newer exact frame after reveal, revalidates
   camera/cap applicability once, and freezes that unchanged frame for all five
   clicks. Confirm batch start, drawing, reveal, clicks, fitting, and proposal
   presentation never alter the operator's zoom, pan, fitted region, or focus.
7. Click the five observed circle centers in a deliberately noncanonical order.
   Confirm the UI shows all markers and click count. The app must associate them
   globally and deterministically; it must not impose a click order, distance
   threshold, or ambiguity blocker.
8. If a click is wrong, use **Undo Last Click** or **Clear Clicks on This
   Frame**. Confirm no motion, ink, redraw, new frame, zoom, or pan occurs.
9. Review the all-five affine proposal and diagnostic residuals, RMS,
   covariance, and uncertainty. Their magnitude must not block the proposal or
   route to paper replacement. Constant correction is expected only if affine
   construction itself fails.
10. Explicitly accept the staged `TipCameraRegistration` and confirm Stage 4
    becomes current.

If any chord, contact, or Pen state is ambiguous, stop. The circle center/radius
on this paper is blacklisted. Do not retry it or reset around it. The only
same-workflow recovery is an explicit paper replacement.

Stage 3.4 has no holdouts or numerical model-failure state. Paper replacement is
available only after the operator actually replaces paper or as the existing
possible-ink recovery; numerical fitting cannot offer it.

## 4. Checkpoint recovery branches

Test these only as separately recorded attended cases; neither is implicit
restoration.

- Same unchanged paper and assembly after app/capture restart: choose
  **Revalidate Saved Tip Calibration**. Confirm a fresh settled controller/cap
  frame is captured, no contact mark occurs, and a new accepted tip revision is
  derived from the quarantined checkpoint.
- Explicit paper replacement: record the replacement, rebuild current machine-
  camera authority if required, then run and explicitly accept a complete new
  five-circle Stage 3.4 batch on the replacement paper.

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
8. Review intended and observed geometry plus residuals only if the exact tip
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
