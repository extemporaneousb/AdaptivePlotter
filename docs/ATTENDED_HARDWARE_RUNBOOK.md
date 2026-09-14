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
invoking the script directly. Use `make app launcher APP_CONFIGURATION=release`
for an optimized bundle; `make preview-performance-gate APP_CONFIGURATION=release`
includes both build steps and the preview measurement:

```sh
sh Scripts/check_running_app_preview_performance.sh .build/AdaptivePlotter.app /tmp/adaptiveplotter-native-workbench.json native-workbench
```

The `adaptiveplotter.native-workbench.v2` report requires all five controls in all
four slots (right, left, lower-right, lower-left) at 1000 and 1600 points, full
body/header native hit visibility through every containing clip, native View
menu/hide/scroll/resize/On-Off receipts, and eight retained workbench bitmaps.
The permanent canvas must also remain visible with every control closed at both
widths. Nested scrolling requires before/after bounds of the identified
overflowing inner clip caused by its correlated native wheel; programmatic
reveal and outer-only scrolling do not satisfy it. Resize chooses a feasible
direction at the production minimum. Current software validation and the exact
signed bundle identity are recorded in [Current Evidence](CURRENT_EVIDENCE.md).
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
3. Choose **Enable Motion & Raise Pen** only after those facts are acceptable.
   It commands and settles Pen Up unless the pen is already Up. Observe the actual
   lift and record any refusal or uncertain outcome; software settlement alone is
   not attended pen evidence. For saved-position recovery, **Raise Pen** beside
   **Re-establish Position from Camera** retries preparation without opening Motion.
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
   frames, each with one unambiguous cap candidate; records maximum pairwise
   cap-centroid spread without rejecting a numerical magnitude; and retains only the newest third exact
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
  command replay. Confirm Learning is complete while calibrated Drawing remains
  blocked until **Re-establish Position from Camera** uses a current exact-frame
  cap observation at settled Pen Up. Record reported MPos separately from the
  physical cap/tip location and verify the corrected overlay against the paper.
  Repeat with **Start New Learning** and confirm the last complete package
  remains available until a complete replacement is saved.
- Powered-off carriage drift with unchanged MPos: retain the saved Learning,
  use the same camera and explicit camera-position recovery, and verify that the
  observed translation rebases Boundary, camera and tip overlays coherently
  without travel, marks or a new Learning exercise. This requires attended
  physical evidence; a controller trace or synthetic test cannot prove it.
- Actual controller reset, camera
  bump/remount/reframe, or tool/contact-profile change: do not perform the
  unchanged-restart case. Use **Reset From This Step** at the owning physical
  dependency (or the explicit semantic-revision control when implemented).
  Confirm a detected controller/optical mismatch never restores Drawing
  authority. Only an explicitly proven pure coordinate translation may use the
  saved-tip revalidation/rebase path without new contact marks.
- New sheet on the same unchanged support/stock/contact plane: choose **New
  Sheet — Same Contact Plane**. Confirm the paper instance changes, tip authority
  and completed Learning remain current, the calibrated outline is visible,
  prior sheet coverage is cleared, and a new exact-frame coverage assertion
  is required before drawing. Choose Draw border separately for the new ordinary
  drawing; it must not repeat Learning. Retain both drawing records under their
  original sheet identities. Do not use this branch after changing stock
  thickness, support, fixture, or contact height.
- Changed support, stock thickness, contact height, or contact plane: choose
  **Contact Plane Changed**. Confirm tip authority is invalidated while unrelated
  valid machine boundaries and camera Learning remain. Rebuild camera authority
  only if its own dependency changed, then run a complete new
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

1. Show **Guided Learning**, **Video Settings**, **Motion**, and **Portrait Studio**
   from native **View** Show/Hide commands. Panes fill right, left, lower-right,
   lower-left around the permanent canvas; native dividers resize them.
   Apply **Use Saved Learning** and verify the complete accepted checkpoint,
   including Border completion. Selecting Portrait preparation uses the face
   camera in the permanent canvas; **Show on Plotter Video** selects the
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
7. Only after the first result and publication are understood, replace the sheet
   on the same unchanged support/stock/contact plane and record **New Sheet —
   Same Contact Plane**. Confirm the new instance, retained calibration/completed
   Learning, current outline, and cleared coverage. Confirm coverage against the
   current exact frame, inspect the second plan, and click **Draw** once. Repeat
   this two-sheet sequence with **Draw border** off and on; retain each program
   identity, border inclusion, Stop/cancellation outcome where exercised, and
   both immutable record/frame pairs. Verify Motion changes during manual and
   automatic motion and marks stale/disconnected data without needing a checkbox.
   Hide/reopen Motion and confirm the report returns without affecting the run.
   These records may later be selected in **Active Learning > Analyze for
   Learning**; never relabel holdouts.

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

## Trainable Drawing Studio campaign — DS-10 acceptance

This section is the attended procedure for the 2026-09-13 campaign. It is a
procedure, not an execution receipt. Keep four outcomes separate: delivered
software, observed native interaction, learned preference quality, and attended
physical behavior. A completed fit or controller run does not close the latter
two. Record `not run`, `passed`, `failed`, or `insufficient evidence` for each
applicable row; explain a skipped or dependent row explicitly.

### Bind the test artifact and preserve the current session

1. Select one immutable signed campaign test app and its release receipt from
   [Current Evidence](CURRENT_EVIDENCE.md). Record the full landed commit, absolute
   app path, source-tree/build-input identity, executable SHA-256, signing identity,
   macOS version and launch arguments. Verify that the app's SourceCommit agrees
   with the release receipt. Do not rebuild over, re-sign, replace or edit this app
   or any previous test app to conduct acceptance.
2. Inspect the running AdaptivePlotter PID, bundle path and available loaded-artifact
   evidence. Preserve that process, its cameras and in-memory captures. If a
   different app must run, obtain authorization naming the exact existing session
   to close and exact immutable app to launch; explain that transient photos may
   be lost. An earlier authorization to launch another increment does not select
   this one. The generic build/launch steps above do not override this requirement.
3. Record separate authorization for native camera/microphone capture, controller
   settings application, and each attended motion/ink procedure being performed.
   Code implementation or permission to launch an app is not settings or motion
   authorization. Do independent imported-photo/native checks while physical work
   remains unavailable. Use an unlocked desktop and the ordinary native controls;
   do not change OS permissions or activation policy to manufacture a passing run.
4. Create a dated acceptance record outside mutable app state. For each comparison
   retain candidate ID, source-byte hash, crop/raster and recipe/seed identity,
   source-program ID/hash, placement/plan ID/hash, active checkpoint and dataset/split
   IDs, registration and geometry identity, material revision/applicability, feed,
   Pen profile, paper instance/contact plane, and drawing record/run IDs. Capture
   unavailable fields as unavailable; do not substitute a current selection for a
   historical identity. The coordinator can read full IDs from existing durable
   archives when the UI shows shortened labels.

### Native Studio and durable authoring sequence

Use an imported photo first. Real burst capture is a separate authorized native
camera check. Record actual mouse/keyboard events and visible results, with the
exact artifact above; offscreen hosting, programmatic scrolling, synthetic input
into model methods and screenshots alone are not native interaction evidence.

1. Open the Portrait Studio and Drawing panels. At the production minimum width
   and a normal wider arrangement, inspect the ordering: source and exploration,
   preview and ratings/gallery, named training, projection; then placement,
   material/paper, and Draw. Dock, move and resize the panels through the native
   workbench controls. Scroll both long galleries and expanded training controls.
   Check that selected content, labels and action buttons remain reachable and
   unclipped, including the prior/checkpoint comparison at narrow widths.
2. With the operator's normal macOS keyboard-navigation setting recorded, traverse
   focus with Tab/Shift-Tab and activate supported buttons with the keyboard.
   Inspect focus visibility, selection changes, photo-import cancellation, image
   inspection dismissal and return to the originating control. If the platform's
   accessibility host cannot expose a control, record the exact unavailable
   evidence; bitmap appearance cannot fill that gap. Never use keyboard activation
   of Draw or calibration Apply as an incidental navigation check.
3. Choose a photo, run **Random Style**, and inspect the source and proportions through
   the preview. Explicitly select contour, tonal-contour, clean-line, hatch,
   crosshatch and sketch choices where offered. Retain the seeds/recipes for the
   agreed sample. A few plausible Random results establish operation, not a
   statistical claim about family balance. Verify the main viewer has the current
   drawing region aspect ratio and explicit reference status before projection.
   After projection, compare its rotation, uniform scale and offset with existing
   placement controls; artwork dimensions must be readouts, with no height or ink
   override sliders. Check the material-width source and re-adaptation warning.
   Switch to an unprojected candidate: ratings remain available and actual size is
   unavailable. Revisit saved ratings to verify their historical display context.
4. On one exact candidate choose **More Like This**, **Parent**, **Back**,
   **Forward**, and a visible child variation. Confirm restored candidates recover
   the same source/crop, geometry and recipe; ordinary local variations keep source,
   crop, family and head treatment fixed. Navigate photos independently, then use
   **Return to Current Edit** after inspecting a retained drawing. Deleting an
   unneeded recent photo must not destroy an already qualified candidate's source.
5. Test the distinct retention triggers on identified candidates: **Keep Sketch**,
   a rating of 1, a rating of 5, and accepted **Show on Plotter Video**. Mere
   generation or history navigation must not create a durable rated/kept sibling.
   Record scope, objective, presentation size/width and label revision for each
   rating. A low rating is retained evidence; Keep/projection is not a score.
   Observe pending/saved/error presentation and retained size. Do not deliberately
   corrupt the operator's archive to test recovery.
6. Compare supported **Big Head** treatment with its exact parent on frontal and
   non-frontal sources. Inspect forehead/eye-region expansion, taper and protected
   mouth/chin recognition, clipping and orientation. Record landmark/pose support
   and unsupported-region reasons. Do not describe estimated forehead bounds or
   unavailable ears/hairline as measured landmarks. Recognition is assessed in the
   held-out human procedure below, not inferred from the semantic warp metadata.
7. Under **Named style training**, create a named screen-appearance scope from the
   selected drawing and inspect its active/fixed parameters and allowed families.
   Rate identified candidates in that scope, then **Train Style**. Record the frozen
   dataset, group split, optimization outcome and pending checkpoint. Check that a
   completed pending fit does not activate itself. Use **Compare with Prior**, then
   **Activate**, and **Explore This Style** on the fixed source. Compare exact actual
   generated candidates and shared seed, rather than only a weight summary.
8. Add or revise scoped labels, **Update Style**, and inspect the completed child,
   parent checkpoint and deterministic full-refit/reset-optimizer semantics.
   Activate the child, compare, **Roll Back**, and **Use Renderer Prior**. Check that
   each affects future proposals while prior candidates, labels and drawings remain
   unchanged. Repeat the named-scope flow using **Semantic Big Head** and **Vary Big
   Head** on supported source evidence. Cancel one fit and verify that the previous
   completed checkpoint remains usable; insufficient labels must remain explicit.
9. Once saves have settled, perform durable restart/reload only with the specific
   session-switch authorization above. Reopen retained candidates, linked physical
   images when available, scopes and checkpoints; recover the exact source, labels,
   activation and lineage. If no restart is authorized, mark restart verification
   pending and continue the other checks. Never discard captures to finish this row.
10. On an authorized attended run, inspect run status and global **Stop** while the
    Studio is scrolled and another panel has focus. Exercise the native Stop action
    only under the separately agreed physical procedure, and record controller
    terminal facts and direct motion observation. A stopped or ambiguous run must
    not automatically reposition for photography. A synthetic held-run Stop test
    and live inkless Stop check support different claims.

### Independent axis calibration and frozen geometry holdouts

The provisional report of X 159.5 mm and Y 177 mm is not an accepted four-edge
measurement. Do not populate missing opposite sides, uncertainty or axis
association from that report. A camera affine cannot supply the independent
physical ruler measurement.

1. Associate the existing completed Learning Border record with the actual paper
   and historical accepted Learning package. In **Physical Axis Calibration**, match
   all four numbered segments to the signed controller axes: 1 +Y, 2 +X, 3 −Y,
   4 −X. Record which physical endpoints define each ink centreline span, the
   independent instrument and calibration/resolution, repeat readings, uncertainty
   and paper/region identity. The diagram shows planned controller geometry with
   controller completion, not exact transmitted wire or physical dimensions.
2. Enter only observed lengths and explicit uncertainties, describe the method,
   and confirm axis association only when established. **Save Measurements** may
   retain a partial observation without moving the plotter. Opposite-edge intervals
   must be compatible before a proposal exists. The separate ±0.001 mm nominal
   command-encoding allowance is not ruler precision or proof of actual travel.
   Conflicting sides, missing association or inadequate precision are insufficient
   evidence; do not average them into a passing calibration.
3. Review the exact measurement/proposal IDs, historical and freshly probed
   controller context, separate X/Y factors, and proposed `$100`/`$101` commands.
   Obtain settings authorization for those exact commands before **Apply Axis
   Calibration**. Verify the terminal preserves attempted versus written bytes,
   acknowledgements and settings readback. A partial, interrupted or ambiguous
   result is not applied calibration; preserve it and inspect the real controller
   before deciding recovery. **Retry calibration evidence save** retries retained facts,
   not settings. Never replay Apply to fill a missing receipt.
4. After a successful settings change, complete the required Boundary, camera,
   tip/contact and Drawing Border Learning again. Verify the new geometry identity
   and registration/material applicability and retain the old full package as
   historical evidence. Scale calibration does not repair skew, backlash or slip.
5. Before any held-out ink, freeze a manifest containing the exact test programs,
   placements, location list, orientation, instrument/error model, measurement
   repeats and intended comparisons. Use a 40 mm square and measure its four
   sides and both diagonals, plus a 40 × 20 mm rectangle at explicit 0° and 90°,
   at the centre and representative permitted locations. Diagonals are independent
   centreline corner-to-corner measurements; distinguish the separate diagonal
   strokes from pooled ink at vertices when locating endpoints.
   Calibration frame edges cannot be reused as held-out results; identify independent
   held-out locations before calibration and keep those locations out of fitting.
6. Select **Metric square 40 × 40 mm + diagonals (100%)** (`metricSquare40`) and
   **Metric rectangle 40 × 20 mm (100%)** (`metricRectangle40x20`) through the ordinary
   Drawing **Test Target** menu, then **Show Target** there if the overlay is hidden.
   Select the **100%** placement action explicitly: source
   selection preserves the previous scale, which may be 0.25×. Confirm the resulting
   **Size 1.00×**, exact source-program and plan endpoints, explicit 0° or 90° rotation,
   and the predeclared centre/location before Draw. The separate
   diagonal strokes belong to the square's same immutable source/plan. Record the
   exact catalog identifiers from that artifact; selecting a source is not motion
   authorization. **Fit to Drawing Area** changes scale and therefore changes the
   physical target. Do not use Fit after freezing these target dimensions.
   The older generic square's 96-unit ink span and generic rectangle's 96 × 66-unit
   spans are different targets. If the delivered app lacks the exact holdout
   entries or cannot place them within the accepted region, record preparation
   unavailable and stop this physical row. Do not inject raw controller commands,
   approximate the Size slider or add an independent stretching path to bypass it.
7. Keep the predeclared acceptance fixed: **the entire propagated uncertainty
   interval must lie within 2% of each intended segment ratio and within 1° of
   orthogonality; length uncertainty must be no more than 0.2 mm on 40 mm targets**.
   Compare the square's axis ratio with 1:1 and the rectangle with 2:1 in each
   orientation, alongside absolute side lengths. Record both diagonals and derive
   angle intervals using the predeclared endpoint/measurement model, or use an
   independently calibrated angle measurement. Preserve correlated uncertainties;
   do not assume independent errors merely to narrow an interval.
8. If targets do not fit or the instrument cannot resolve them, declare smaller
   targets and appropriate uncertainty **before acquisition**, retaining the same
   ratio/angle tolerances. An unresolved interval is insufficient evidence, not a
   pass. Never loosen tolerances or substitute a favourable location after a failed
   result. A correction begins a new calibration revision and new held-out drawings;
   preserve failed originals and explain the change.

### Measured material and photographed physical drawings

1. Predeclare the pen/tool/mount, paper stock/contact plane, actuation profile,
   feed, final physical size and material revision for each comparison. Record the
   measurement instrument, spatial resolution and uncertainty before evaluating
   deposited widths, gaps or merged details. Separate a material change from a
   geometry correction; changed applicability needs a new applicable observation.
2. Use **Inspect Material Measurement Images** on the existing Border segments or
   existing 2 mm-radius, 16-chord marks. Inspect original pixels and paper on both
   sides in every frozen image. Confirm the declared material/settings and absence
   of obstruction only when directly established. Single-image existing ink has
   unknown deposition time; a matched before/after pair has stronger temporal
   provenance but does not by itself prove unobstructed coverage.
3. Retain width distributions, direction, sample/exclusion counts, uncertainty and
   the actual qualification. Filled holes, overlaps, pooled vertices, blurred
   edges, occlusion or inadequate resolution must remain excluded, bounded or
   unavailable. Do not upgrade an estimate in controller coordinates to an
   independently measured width after axis calibration. Compare with independent
   instrument measurements where resolvable; do not invent a quality threshold
   finer than the instrument or image can support.
4. At the accepted final placement scale, apply the material to the portrait and
   inspect the new candidate/plan identity, hatch spacing, minimum gaps and detail
   feasibility. Compare nominal and measured preview meaning. A rating's preview
   height does not change actual placement. Resizing or changing material requires
   a newly accepted adapted candidate; previously rated and drawn candidates stay
   immutable. Record intended and realized features, including lost/merged detail.
5. For each separately authorized drawing, confirm current paper coverage against
   the exact frame and inspect the immutable plan before clicking Draw once. Check
   durable intent and raw baseline, actual Pen/motion chronology, controller outcome,
   and terminal images. Prefer the recorded reachable pen-up observation pose
   clearing the whole region. If bounded multi-pose capture is used, retain each
   original, pose/registration, composite coverage and per-pixel provenance.
   Unknown masks or uncovered pixels cannot count as observed ink.
6. Open the linked physical drawing images in the gallery and compare them with
   the exact candidate and planned features. Record obstruction and missing-coverage
   reasons alongside the raw images. A direct independent photograph may supplement
   the attended receipt, with its time, view and record association; it does not
   silently replace missing app-owned originals. A failed or cancelled attempt
   remains a physical attempt, without automatic redraw or photo repositioning.
7. Rate the linked photographed attempt under a **Physical drawing** objective.
   Keep these labels separate from screen appearance, operator visibility assertions,
   material measurements and Keep/projection retention events.

### Grouped likeness and training-quality evaluation

Before looking at evaluation results, freeze the scope/objective and active/fixed
parameter mask, training dataset and checkpoint IDs, source/session/ancestry group
IDs, training/holdout partition, evaluation source list, seeds, presentation sizes,
material conditions, rater instructions and planned aggregation. Declare sample
and rater counts, rating anchors, missing-data handling, comparison order and the
uncertainty method appropriate to those counts. If a quality pass criterion is
needed, declare it with a defensible resolution before evaluation; this runbook
adds no arbitrary numeric likeness or physical-quality threshold.

Use the actual **Compare with Prior** candidates for matched source and seed, or
record equally explicit frozen prior/checkpoint pairs. Counterbalance presentation
order and conceal which member used the checkpoint from the rater when feasible;
record when blinding was impossible. Evaluate screen aesthetics, recognizable
likeness/Big Head treatment and photographed physical realization as distinct
objectives. Use source/session/ancestry groups, not near-duplicate variants, as the
independent unit. Keep physical comparisons at matched final scale and applicable
material conditions or report that confound explicitly.

Retain every included and excluded comparison, individual label revisions and
group-level results. Report the model's training/holdout ordinal loss and comparable
pair counts separately from independent human results and physical feature results.
No usable holdout groups, no comparable pairs, uniform/degenerate labels, excessive
missing coverage, instrument limits or confidence intervals that cannot resolve the
predeclared criterion yield **insufficient evidence**. Do not select only successful
faces or reassign evaluation groups after fitting. New or revised labels used in
an update form a new frozen dataset/child checkpoint; evaluation examples consumed
by that update are no longer independent evidence for that child.

Finish with a per-row receipt linking raw evidence and exact artifact identities.
Leave pending native, learning-quality or physical rows open in the canonical
ledger even when all software gates pass. A blocker in physical metric, material
resolution or attended access blocks the dependent claim, not unrelated authoring
or persistence verification.

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
