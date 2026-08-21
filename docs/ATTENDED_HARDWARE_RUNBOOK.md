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
2. Establish a non-full zoom and pan, lock the analysis region, and record the
   exact displayed and locked camera-pixel rectangle.
3. Start **Capture Five Cap Samples**.
4. Observe Pen-Up travel through `C`, `X−`, `Y+`, `X+`, and `Y−`.
5. At each pose, confirm the carriage settles before inspection. Confirm the app
   accepts exactly three strictly newer source/configuration-compatible LIVE
   frames, each with one unambiguous cap candidate; refuses more than 2 px
   maximum pairwise cap-centroid spread; and retains only the newest third exact
   frame and measurement without averaging. The preliminary freshness frame is
   not accepted evidence. The cap landmark is the visible cap bottom-center, not
   the hidden tip.
6. Review the three-fit/two-holdout proposal. Both holdouts must pass.
7. Accept only if source, dimensions, optical setup, applicability rectangle,
   residuals, and correspondence roles are correct.
8. Confirm acceptance publishes learned fitted bounds without changing the
   displayed camera-pixel rectangle, the locked analysis rectangle, or the lock
   state.

Do not accept after a camera/device/mount/crop/orientation/focus change. Restart
the attended run with explicit invalidation and new evidence.

## 3. Stage 3.4 — five sparse 2 mm-radius circles

Confirm Stage 3.4 plans one center circle and four corner circles whose centers
are 2 mm inside the accepted X−/X+/Y−/Y+ Boundary envelope; Stage 3.3 remains on
its separate existing ±24 mm camera-calibration plan.

1. Press **Draw Five 2 mm Circles** once.
2. For the center and each of the four maximum drawable corners, watch Pen-Up
   travel settle at the intended MPos, compare each outer center with the
   accepted Boundary coordinate and 2 mm radius inset, confirm the pre-mark
   frame/cap/controller evidence is retained, and watch Pen-Up travel settle at
   the circle start.
3. Confirm the app commands and settles the current Pen Interaction Down value.
   Directly observe physical contact; the command outcome alone is not proof.
4. Watch one closed 4 mm-diameter circle complete as 16 short chords at no more
   than 100 mm/min. Confirm Pen Up settles before any travel toward the next
   circle. Across the batch, confirm exactly five separated circles and no
   connecting ink stroke. Confirm the calibrated drawable-region overlay, not
   physical perimeter ink, supplies the bounding box through the outer centers.
5. Confirm there is no reveal, frame selection, or click request between
   circles. After the fifth circle only, watch one Pen-Up reveal return to the
   outer rectangle's geometric center, then confirm Idle/final-MPos settlement.
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
9. On the fifth valid click, confirm the app constructs but does not yet accept
   the all-five affine `TipCameraRegistration`. Review the frozen-frame markers,
   diagnostic residuals, RMS, covariance, and uncertainty. Choose **Accept Tip
   Map** and confirm Stage 4 becomes current. Also exercise **Reject Tip Map**
   once and confirm the same frame remains available without motion, capture,
   ink, or redraw. Constant correction is expected only if affine construction
   itself fails. **Retry Calibration Commit** is valid only after an actual
   atomic acceptance failure.

If any chord, contact, or Pen state is ambiguous, stop. The circle center/radius
on this paper is blacklisted. Do not retry it or reset around it. The only
same-workflow recovery is an explicit paper replacement.

Stage 3.4 has no holdouts or numerical model-failure state. Paper replacement is
available only after the operator actually replaces paper or as the existing
possible-ink recovery; numerical fitting cannot offer it.

## 4. Checkpoint recovery branches

Test these only as separately recorded attended cases; neither is implicit
restoration.

- Same unchanged paper and assembly after binary/app/capture restart: keep
  Motion disabled, start the same camera, connect, and complete the read-only
  passive controller-context probe. Confirm completed Pen, Boundary, Stage 3.3,
  Stage 3.4, and attributable Stage 4 authority returns automatically with the
  exact accepted tip revision. Confirm no **Revalidate Saved Tip Calibration**
  action, cap capture, click, contact mark, paper operation, or Learning Path
  replay occurs. Optionally inspect the projected region/plan against the
  unchanged sheet; record that as an operator sanity check, not a new
  calibration acceptance.
- Actual controller reset, powered-off carriage uncertainty, camera
  bump/remount/reframe, or tool/contact-profile change: do not perform the
  unchanged-restart case. Use **Reset From This Step** at the owning physical
  dependency (or the explicit semantic-revision control when implemented).
  Confirm a detected controller/optical mismatch never restores Drawing
  authority. Only an explicitly proven pure coordinate translation may use the
  saved-tip revalidation/rebase path without new contact marks.
- New sheet on the same unchanged support/stock/contact plane: choose **New
  Sheet — Same Contact Plane**. Confirm the paper instance changes, tip authority
  remains current, prior sheet coverage is cleared, and a new coverage assertion
  is required before drawing. Do not use this branch after changing stock
  thickness, support, fixture, or contact height.
- Changed support, stock thickness, contact height, or contact plane: choose
  **Contact Plane Changed**. Confirm tip authority is invalidated, rebuild
  current machine-camera authority if required, then run a complete new
  five-circle Stage 3.4 batch, then review and accept the new map.

If any semantic identity is uncertain, do not revalidate. Clear the durable tip
checkpoint and perform a new five-mark calibration.

## 5. Stage 4 — isolated observed line

1. Record the exact current tip registration revision.
2. Press **Go** once. Confirm a cyan predicted 5 mm line appears on the current
   video before motion and that its machine endpoints and exact tip revision are
   visible. The runtime selects the first clear signed-axis plan; there is no
   direction prompt or phase-by-phase approval.
3. Observe the displayed activity move through plan, local baseline, Pen-Up
   travel, draw, reveal/observe, and comparison. During motion, confirm the exact
   **Stop** remains available. No additional **Go**, **Next**, or approval should
   be required on the normal path.
4. Watch Pen-Up travel settle at line start, then directly observe one physical
   stroke under the single drawing owner. Do not resend after ambiguity.
5. Confirm the plotter returns Pen Up to the trial-local reveal MPos, settles,
   and captures a strictly newer post-line frame.
6. While the same-pose baseline/post pair is analyzed, confirm the Learning UI
   visibly reports **Trial ink analysis · active** with Vision as operation
   owner. Apparent inactivity without that state is a failure.
7. Confirm the normal result records automatically and renders predicted cyan,
   observed white, and orange residual geometry on the exact post-line frame.
   It may retain candidate refinement evidence; it must not silently change the
   accepted model.
8. Confirm the exact post-line frame and cyan intended, white observed, and
   orange residual overlays remain available through **Review Comparison**
   after live preview resumes.
9. Confirm the result says **Interactive learning complete · one validation**
   and does not claim **Trained** or **Adaptive drawing ready**.

If possible ink, rejected Vision evidence, or an uncertain controller outcome
occurs, confirm the automatic chain stops. Any offered recovery may return Pen
Up and observe the existing stroke, but it must not redraw it.

## 6. Drawing Studio — first physical plan

1. Open **Drawing Studio** and confirm the calibrated drawable outline and
   predicted current tip point are correctly overlaid on live video.
2. Replace the disposable sheet if necessary using **New Sheet — Same Contact
   Plane**. Place it fully over the outline and press **Assert Sheet Covers
   Outline**. Confirm the top paper status names this as an operator assertion,
   not measured paper edges, without changing the accepted tip map.
3. Select a square first. Place it near the drawable-region center, resize and
   rotate it, and confirm the projected target follows the video click while
   remaining entirely inside the outline. Move it partly outside and verify Run
   is refused before moving the plotter.
4. Return it inside, use **Ordinary drawing**, and record the displayed program
   and execution-plan hashes. Confirm Pen Up, Idle, Motion, paper, and controller
   eligibility are current before pressing **Run Drawing**.
5. Observe one owner perform Pen-Up travel, Pen Down, all square segments, Pen
   Up, and logical-stroke checkpoint completion. Confirm **Stop** remains bound
   to that exact plan and no competing Run replaces it.
6. On completion, confirm the carriage is at the same observation pose used for
   the local baseline, a newer exact post frame is captured, and intended,
   observed, and residual overlays are retained for review.
7. Inspect the immutable run record: ordinary role, program/placement/plan and
   calibration/paper provenance, request/execution frontiers, controller
   disposition, and observation outcome. Restart the app and confirm the
   attributable Stage 4 validation and Drawing Studio availability restore
   after the matching camera plus controller-context probe, without
   tip-checkpoint revalidation or replaying motion.
8. Repeat with one tessellated curve and one multi-stroke catalog item only if
   the square is clean. Stop on any uncertain mark; do not resend or redraw.

This section validates direct placed drawing, not adaptive fitting. Training and
holdout roles are data declarations only until the future active-selection,
candidate-comparison, and readiness protocols are implemented and physically
validated.

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
