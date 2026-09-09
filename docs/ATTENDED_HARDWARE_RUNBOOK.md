# Attended Hardware Runbook

Status: attended physical procedure

This runbook owns the human procedure for validating the sparse tip workflow on
one real plotter, camera, pen, and paper. Product meaning is defined by
[Product Contract](PRODUCT_CONTRACT.md); exact software sequencing is defined by
[Discovery and Observed-Trial Protocol](DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md).
Record results in [Current Evidence](CURRENT_EVIDENCE.md) without upgrading a
claim beyond what was directly observed.

## Software native workbench check

Before physical work, the existing signed-app gate can exercise production
window controls with simulated startup and no real capture or controller effects.
The desktop must be unlocked and visible for native input. On 2026-09-09 the
console explicitly reported locked since 00:10:16 PDT; native 20 and 22 reached
no controls, and macOS rejected native 22 activation despite exact regular-app
identity. Unlock through the normal macOS login UI before retrying; do not change
activation policies, permissions or lock behavior to force this gate. Launcher
logic passes and an inactive-window bitmap are not native interaction proof.

The gate script immediately asks the existing launcher to activate only its
exact spawned PID, preserving arguments and prohibiting a new-instance fallback.
It does not await the physical review marker before activation because Connect
is a native action preceding that marker. Build the existing launcher before
invoking the script directly (`make preview-performance-gate` includes it):

```sh
sh Scripts/check_running_app_preview_performance.sh .build/AdaptivePlotter.app /tmp/adaptiveplotter-native-workbench.json native-workbench
```

The `adaptiveplotter.native-workbench.v1` report requires all five panels in all
three docks at 1000 and 1600 points, full body/header native hit visibility through
every containing clip, native menu/hide/scroll/resize/On-Off receipts, and six
retained workbench bitmaps. Video proof targets the actual canvas, including
panel ancestry. Nested scrolling requires before/after bounds of the identified
overflowing inner clip caused by its correlated native wheel; programmatic
reveal and outer-only scrolling do not satisfy it. Resize chooses a feasible
direction at the production minimum. Their software contracts pass full strict
run 31 (997 Swift functions passed, five opt-in skips, zero failures), and
independent critic 9 found no blocking software issue. The exact signed run-31
bundle is delivered at the canonical path; it has not been launched. At
11:06:55 UTC on 2026-09-09, the desktop still explicitly reported locked.
Actual interaction, the 20-switch/90-second learned camera workload and the
physical sequence remain unverified. Use the exact delivered identity and
receipts in [Current Evidence](CURRENT_EVIDENCE.md) after normal GUI unlock;
software gate success does not satisfy these remaining checks.
The pending learned-camera acceptance run sets
`PREVIEW_PERFORMANCE_DURATION_SECONDS=90`; the general gate's default and minimum
remain 60 seconds.
The harness preserves user layout and accepted artifacts.
Its logs/captures remain beside the selected evidence path on failure. These
checks use the real AppKit event loop; bitmap-only SwiftPM tests cannot replace
them. The separate held-Draw software Stop test and the physical inkless native
jog/Stop below prove different boundaries. No native input into a held synthetic
Drawing Run or physical ink is claimed by this scenario.

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

1. Use a disposable sheet with room for four 4 mm-diameter corner marks and the
   closed Drawing Border connecting their centers.
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
4. Start Exercise 1.1. Its first action is **Identify Pen Cap**. Confirm the
   app freezes one current exact frame before any pen question or actuation, then
   click a visibly colored area of the cap body, not the tip. Confirm the
   accepted learned color visually corresponds to the cap and that the recorded
   frame/source/configuration/click provenance and sample counts are current.
   Reject stale-frame, gray/white/dark, or insufficiently chromatic samples;
   do not work around refusal with a color picker.
5. Complete the Up → Down → Up sequence. Use the Up and Down sliders to choose
   functional values at the current position; **Confirm Pen Up** or **Confirm
   Pen Down** must immediately replace the clicked confirmation with a busy/Stop
   surface before any predecessor wait. Confirm that slow advisory audio does
   not delay the corresponding Pen command or successor prompt. The runtime
   accepts the displayed value only after a commanded-and-settled controller
   outcome. A refusal or ambiguity becomes Needs Attention/possible physical
   change and cannot be confirmed through. Record the values and whatever
   controller outcome, timestamp, and MPos are available. A fresh
   session is seeded at `S40` and `S760`; repeated attempts start with the
   current values and may legitimately differ by position.
6. For X−, X+, Y−, and Y+, choose the direction explicitly, start Boundary
   Discovery, watch the motion, and use the operation's exact **Stop**.
7. Confirm each accepted side cites the selected direction plus final Idle/MPos.
   Boundary renewal uses fixed bounded controller segments and never consults
   Camera or Vision advice.
8. Move to the derived center and confirm the final MPos meets the displayed
   0.5 mm settlement policy.

Any ambiguous or out-of-tolerance result ends this run. It is not evidence for
the requested side or center.

## 2. Exercise 1.3 — camera calibration from Pen Cap positions

1. Confirm Pen Up and an unobstructed camera view of the complete five-position
   cross. Confirm Exercise 1.3 is using the accepted **Identify Pen Cap** appearance
   from Exercise 1.1 and exposes no independent color-editing control.
2. Establish a non-full zoom and pan, lock the analysis region, and record the
   exact displayed and locked camera-pixel rectangle.
3. Press **Run Five-Position Camera Calibration**.
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

## 3. Exercise 1.4 — four 10 mm-inset 2 mm-radius circles

Confirm Exercise 1.4 plans no center circle. Its four corner-circle centers are
exactly 10 mm inside the accepted Boundary on both adjacent axes, so each 2 mm-
radius footprint remains 8 mm clear of those edges. Exercise 1.3
remains on its separate center plus four ±24 mm camera-calibration positions.

1. Press **Draw Four Calibration Circles** once.
2. For each of the four framing marks, watch Pen-Up travel settle at the
   intended MPos, compare each center with the accepted Boundary coordinate and
   exact 10 mm inset, confirm the pre-mark
   frame/cap/controller evidence is retained, and watch Pen-Up travel settle at
   the circle start.
3. Confirm the app commands and settles the current Exercise 1.1 Pen Down value.
   Directly observe physical contact; the command outcome alone is not proof.
4. Watch one closed 4 mm-diameter circle complete as 16 short chords at the
   app-owned 500 mm/min request, subject to the controller-reported feed ceiling.
   Confirm Pen Up settles before any travel toward the next
   circle. Across the batch, confirm exactly four separated circles, no center
   circle, and no connecting ink stroke during calibration.
5. Confirm there is no reveal, frame selection, or click request between
   circles. After the fourth circle only, watch one Pen-Up reveal return to the
   outer rectangle's geometric center, then confirm Idle/final-MPos settlement.
6. Confirm the app captures one newer exact frame after reveal, revalidates
   camera/cap applicability once, and freezes that unchanged frame for all four
   clicks. Confirm batch start, drawing, reveal, clicks, fitting, and proposal
   presentation never alter the operator's zoom, pan, fitted region, or focus.
7. Click the four observed circle centers in a deliberately noncanonical order.
   Confirm the UI shows all markers and click count. The app must associate them
   globally and deterministically; it must not impose a click order, distance
   threshold, or ambiguity blocker.
8. If a click is wrong, use **Undo Last Click** or **Clear Clicks on This
   Frame**. Confirm no motion, ink, redraw, new frame, zoom, or pan occurs.
9. On the fourth valid click, confirm the app constructs but does not yet accept
   the all-corner affine `TipCameraRegistration`. Review the frozen-frame markers,
   the separately labeled accepted Drawing Boundary, the cyan inset Drawing Border through
   the four selected centers, diagnostic residuals, RMS, covariance, and
   uncertainty. Choose **Accept Pen-Tip Calibration** and confirm Stage 2
   becomes current. Also exercise **Reject Pen-Tip Calibration**
   once and confirm the same frame remains available without motion, capture,
   ink, or redraw. Constant correction is expected only if affine construction
   itself fails. **Retry Pen-Tip Calibration Save** is valid only after an actual
   atomic acceptance failure.

If any chord, contact, or Pen state is ambiguous, stop. The circle center/radius
on this paper is blacklisted. Do not retry it or reset around it. The only
same-workflow recovery is an explicit paper replacement.

Exercise 1.4 has no holdouts or numerical model-failure state. Paper replacement is
available only after the operator actually replaces paper or as the existing
possible-ink recovery; numerical fitting cannot offer it.

## 4. Checkpoint recovery branches

Test these only as separately recorded attended cases; neither is implicit
restoration.

- Same unchanged paper and assembly after binary/app/capture restart: keep
  Motion disabled and start the same camera. Before either decision, inspect
  the saved Drawing Border, inner applicability region, cap/tip when supported, prior
  drawing paths, and advisory optical comparison projected into the current
  frame. Confirm neither preview nor **Start New Learning** changes the active
  dependency graph, registration, controller pose, session ownership, or
  hardware. Choose **Use Saved Learning** only when the overlays are correct;
  confirm it applies the exact saved revisions atomically without motion or
  command replay. Repeat with **Start New Learning** and confirm the last
  complete package remains available until a complete replacement is saved.
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
  four-circle Exercise 1.4 calibration, then review and accept the new calibration.

If any semantic identity is uncertain, do not revalidate. Clear the durable tip
checkpoint and perform a new four-mark calibration.

## 5. Exercise 2.1 — draw and validate the Drawing Border

1. Record the exact current tip registration revision.
2. Press **Draw and Validate Drawing Border** once. Confirm a cyan planned Drawing Border through the four
   accepted circle centers appears inside the separately labeled accepted Drawing
   Boundary on the current video before motion and that its machine path and
   exact tip revision are visible. There is no direction
   prompt or phase-by-phase approval.
3. Observe the displayed activity move through plan, local baseline, Pen-Up
   travel, draw, reveal/observe, and comparison. During motion, confirm the exact
   **Stop** remains available. No additional continuation or approval should
   be required on the normal path.
4. Watch Pen-Up travel settle at the lower-left Drawing Border start, then directly
   observe four orthogonal edges and four right-angle turns under the single
   drawing-plan owner. Do not resend after ambiguity.
5. Confirm the plotter returns Pen Up to the trial-local reveal MPos, settles,
   and captures a strictly newer post-frame.
6. While the same-pose baseline/post pair is analyzed, confirm the Learning UI
   visibly reports **Trial ink analysis · active** with Vision as operation
   owner. Apparent inactivity without that state is a failure.
7. Confirm the normal result records automatically and renders predicted cyan,
   observed white, and orange residual geometry on the exact post-frame.
   It may retain candidate refinement evidence; it must not silently change the
   accepted pen-tip calibration or its exact `TipCameraRegistration` revision.
8. Confirm the exact post-frame and cyan intended, white observed, and
   orange residual overlays remain available through **Review Comparison**
   after live preview resumes.
9. Confirm the result says **Learning complete** and the graduation cap is filled
   and does not claim **Trained** or **Adaptive drawing ready**.

If Vision rejects a comparison after controller-completed drawing, confirm
Learning completes while the rejection is retained as `visionUnclear`, with
zero verified ink strokes. If possible ink or an uncertain controller outcome
occurs, confirm the automatic chain stops. Any offered recovery may return Pen
Up and observe the existing stroke, but it must not redraw it.

## 6. Portrait Studio — two distinct physical plans

1. Show **Guided Learning**, **Video**, **Motion**, and **Portrait Studio** from
   the panel menu. Each panel may remain visible in Left, Bottom, or Right.
   Apply **Use Saved Learning** and verify the complete accepted checkpoint,
   including Border completion. Selecting Portrait preparation uses the face
   camera in the shared Video panel; **Show on Plotter Video** selects the
   plotter camera while retaining the portrait controls.
2. Inspect the fresh plotter frame, controller position, accepted region, and
   actual contact plane. An existing sheet assertion does not detect paper
   edges. Only assert **Sheet Covers Target** after inspecting the sheet.
3. With Pen Up, perform one inward 2 mm X jog at 60 mm/min and press global
   **Stop**. Record the exact active manual capability, native input handler
   receipt, controller cancellation/Idle settlement, and final position
   separately. The synthetic held Drawing Run test proves prompt typed software
   Stop acceptance before deliberately held lower work settles; it supplies no
   native input or actual-controller Stop evidence.
4. Import the face reference in Portrait Studio, choose the portrait style,
   and use **Show on Plotter Video**. Fit uses the better 0° or 90° orientation.
   Adjust scale/placement so the first portrait occupies one half of the region.
   Inspect the complete immutable plan and exact plotter frame before **Draw**.
   No pre-run Learning/evidence-role selector is required.
5. Click **Draw** once. Keep global **Stop** reachable. Record its actual plan
   identity and capability, Pen Up normalization/travel, pen actuation, execution
   frontiers, controller settlement, baseline/post frame identities, and terminal
   observation. A transmitted command or completed controller path alone does
   not establish attributable ink.
6. Export the first immutable record and its exact baseline/post pixel buffers
   before **New Drawing** releases the owner's in-memory frames. Inspect the
   terminal result and paper. A possible-ink, ambiguous, incomplete-publication,
   or rejected observation ends this sequence without replay.
7. Only after the first result is understood, create a second distinct plan in
   the other half of the same region, with no overlap including line width.
   Review its frame and plan, then click **Draw** once. Retain the second exact
   record/frame pair. Keep both ordinary records immutable; they may be selected
   later in **Active Learning > Analyze for Learning**. Never relabel holdouts.

The explicit harness scenario composes these existing controls and owners:

```sh
PORTRAIT_REFERENCE_PHOTO=/absolute/path/to/face.png \
PHYSICAL_CONTROLLER=/dev/cu.exact-controller \
Scripts/check_running_app_preview_performance.sh \
  .build/AdaptivePlotter.app /absolute/path/to/physical-evidence.json physical-portrait
```

This is an opt-in physical scenario; default `preview` and `learned-portrait`
remain motion-free. The signed app publishes a report and a review marker before
its inkless trial and before each portrait. Inspect `factsPath`, adjacent review
PNG, full plan, prior record/frame exports, and actual paper/mechanism. Under the
already granted operator authorization, the validator advances only that stage
by writing the marker's exact `continuation` JSON object to `continuationPath`.
The token includes a fresh session/nonce, executable SHA, stage, and plan SHA;
stale or mismatched tokens are refused. This marker stages the harness only;
the native click still uses current ordinary UI admission and owner checks.

The per-stage timeout is `PREVIEW_PERFORMANCE_DURATION_SECONDS` (default 600,
maximum 600). Timeout, refusal, success, shell interruption, and failure all retain
the app and artifact directory; none automatically redraws, resets paper/Learning,
or kills a controller-owning process. On failure inspect the active owner and
use its existing Stop if needed. The scenario stops before the second Draw when
the first terminal is not successful and attributable. Exported `.pixels` plus
frame JSON preserve exact source bytes/provenance; PNG is a visual derivative.
These are bounded copies of existing snapshots/archive records, not another
recorder or source of truth. Native CGEvents, controller evidence, software
attribution, and independently observed physical ink/attendance remain separate.

## Automatic retention and diagnostics

Confirm the accepted Learning checkpoint and completed Border outcome are
retained without a Save action. Open **View > Diagnostics** and inspect the
source, Learning episode identity, runtime/UI revisions, Border phase/outcome,
and terminal details. **Copy Diagnostics** is available for a support report.
Inspect the existing transition/refusal records and the explicitly declared
omissions. The snapshot does not include raw controller traffic or camera
pixels and is not a complete replay archive. Direct operator observations and
attended ink evidence remain separate. A complete canonical archive is no
longer a prerequisite for this diagnostic check.

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
