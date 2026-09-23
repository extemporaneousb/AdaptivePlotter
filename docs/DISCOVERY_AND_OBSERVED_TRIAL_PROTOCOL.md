# Learning Path Operating Protocol

Status: current operating protocol for Learning Path 1.1 through visible 2.1

This document owns the exact actor, action, evidence, dependency, and recovery
sequence. Durable semantics remain in [Product Contract](PRODUCT_CONTRACT.md).

The accepted [workbench and portrait completion correction](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md#workbench-and-portrait-completion-correction-2026-09-08)
passed full strict run 31: 997 Swift functions passed, five opt-in skips, zero
failures; release, signing, launcher, bundle and documentation checks passed.
Independent critic 9 found no blocking software issue, and the exact tested app
was delivered without launching. The execution-plan matrix owns remaining native
and physical acceptance. Attempts reached no controls while the GUI was locked;
actual camera workload and physical workflow remain unverified. Current Evidence
records the exact software/delivery receipts and does not claim Git landing or
attended Learning completion.

## Common actor contract

Every interactive step exposes:

- one current participant: App, Operator, Controller, Camera, Vision, or Pen;
- one typed current action and expected observation;
- one explicit operator-action transition; exact camera point selections submit
  directly on the click and do not add a confirmation button;
- one operation owner when controller or simulator state may change;
- one contextual Stop while that owner is stoppable;
- one typed attempt and disposition;
- exact artifact dependencies for every accepted result.

Announcements are advisory output. Buttons own answers, Start, Cancel, Stop,
Restart, Redo, and acceptance. Pen Up/Down cue admission precedes the matching
Pen command, but playback completion does not gate that command or the next
physical-confirmation prompt. Boundary retains its separately bounded
output-before-motion terminal wait. The exact camera click owns its point
assertion and submits it directly; there is no **Apply Learning Point** step.

**Connect** and **Enable Motion** are workbench-toolbar controls, not Learning
Path rows or exercise transitions. Motion Enabled implies a current connected
session. A motion-dependent Learning action stays at its exercise and names the
missing toolbar dependency; satisfying it enables the existing action rather
than generating another **Start**, **Continue**, or acceptance button. The
complete Learning Path button graph is
[Learning Path Button Transitions](LEARNING_PATH_BUTTON_TRANSITIONS.md).

Before Learning Path motion, **Connect** performs only the complete passive
controller probe. A returned alarm or fault remains visible as typed current
controller evidence while the failed link is closed. If an alarm is reported,
the Motion panel separately shows sampled X/Y/Z axis-limit inputs and whether manual
alarm unlock is armed. An asserted X or Y physically blocks **Clear Alarm**;
release the switch and press **Connect** to resample. A past alarm with no
currently asserted axis-limit input is manually clearable. The explicit action checks
realtime status again immediately before its one alarm-lock override and refuses
without sending it if a limit is now asserted, status is unknown, or the
controller is no longer in Alarm. It then runs a fresh complete passive probe.
It does not home, recover position, clear limit inputs, or enable Motion. No
unlock is sent during Connect, no failed clear is retried, and **Enable Motion**
remains a separate operator action after a clean probe.

Cancel abandons a settled attempt. Stop settles the active stoppable operation.
They may share a mechanical Jog Cancel primitive but never share a successful
semantic disposition. Sticky ambiguity suppresses new physical motion.

Every production comparison of requested pose and settled MPos uses fresh
attributable controller evidence, compatible context, and the shared 1 mm
Euclidean policy.

Presentation zoom, pan, and fitted bounds are available after Exercise 1.2. They are
view-only. Exact camera-pixel evidence and calibration authority do not change
when the presentation transform changes. Learning visibility and compatible
presentation-context changes preserve the operator's exact effective visible
camera-pixel rectangle; preserving only numeric zoom and pan is insufficient
when fitted bounds change. Exercise 1.3 proposal review preserves the viewport;
acceptance may publish a new fitted target but does not auto-focus or rewrite a
locked analysis region. Camera source or configuration changes reset the
viewport. Explicit operator Full, Fit, zoom, and pan actions may replace it.
Exercise 1.4 never changes zoom, pan, fitted region, preferred zoom, or viewport
focus automatically.

The only global scene-overlay preferences are **Pen cap** and **Armature
envelope**. The envelope is inferred from the cap, not segmented. Generic
viewport ROI affects only generic requested scene analysis; it never constrains
the specialized regions used below. Intended geometry, observed ink, and
residuals are mandatory contextual evidence in Stage 2 and are not toggles.

## 1.1 Identify and Calibrate the Pen

1. Start Exercise 1.1. **Identify Pen Cap** freezes the current exact frame.
   Drag a rectangle around the cap and nearby holder that moves with it. Include
   edges and exclude stationary rails, independently moving structure and paper.
   Then click the cap inside the rectangle. Further drags pan the video without
   changing the reference; **Redraw Reference** starts a replacement rectangle.
   **Pan Video** is available before the rectangle, too. The cap does
   not need to be centered. Existing geometry from another frame is never reused.
2. The anchor click submits both rectangle and point with exact-frame provenance.
   A small bounded RGB image reference retains black and colored details. A region
   smaller than 12 camera pixels per side, larger than half the frame per side,
   without enough visual detail, or with its anchor outside is refused explicitly.
   The accepted Learning package persists the reference, anchor and exact frame
   provenance. Generic and calibration analysis use the same reference identity.
   Weak/competing matches, excessive deformation, clipping and abrupt position
   jumps report tracking lost. Replaced pens and incompatible camera configurations
   require a new reference. Same-anchor reacquisition can retain at most two prior
   compatible operator-confirmed appearances alongside the new one, without
   averaging their pixels or anchors. Old color-only selections require **Reidentify Pen Cap**
   from **Learning Path Actions** when accepted Pen Learning is already present.
3. Cap identification requires only the current exact frame. The accepted click
   immediately opens the first Up question even when the controller is not yet
   connected or Motion is not enabled. In that blocked state the Up slider and
   **Confirm Pen Up** stays visible but disabled with the exact workbench remedy. Selecting
   a device, **Connect**, and **Enable Motion** remain available in the toolbar;
   completing them enables the existing question without another cap click or
   a Learning Path continuation step.
4. The Up step presents the current Up slider. It is seeded at `S40` in a fresh
   session and otherwise starts from the already-current value. Dragging edits a
   local draft; releasing commands the selected value once. Confirm remains
   visible with “Applying the selected servo setting…” during the drain. Once operational dependencies admit the
   request, **Confirm Pen Up** immediately replaces itself with a non-clickable
   confirming revision before waiting for any setpoint/terminal drain. A stale
   second click cannot duplicate confirmation or actuation. The first request
   accepts that value together with the available controller outcome, timestamp,
   and current MPos. Refusal, ambiguity, unavailable
   evidence, and admission blockers remain explicit without introducing a
   separate forward gate. If exact Stop or application shutdown displaces the
   published confirming revision, the request is superseded: it records no
   accepted Pen evidence and the discovery transaction does not advance.
5. The Down step presents the current Down slider, seeded at `S760` in a fresh
   session and otherwise starting from the already-current value, with the same
   move-and-accept behavior.
6. The final Up step commands the accepted current Up value and completes the
   existing Up → Down → Up attempt.

The Down and final-Up confirmations use the same confirm-before-wait rule. The
following spoken cue is admitted before the next Pen command; held or slow audio
playback cannot hold that command or its next prompt.

If no LIVE appearance has been accepted, the persisted Pen cap and Armature
envelope overlay choices do not change, but both layers report Unavailable and
no LIVE geometry is rendered. An armature envelope is available only from an
accepted cap result and remains explicitly inferred, not independently
segmented. The Video settings show each enabled overlay's analysis status. A
missing cap reports **No pen cap detected**; a learned color alone is not proof
that the cap remains detectable.

The accepted values become the current Up and Down settings consumed by later
pen operations. They are not required to remain constant across the run.
Repeating Exercise 1.1 at another position creates another attempt
with its actual values and available position/actuation evidence so future
learning can evaluate positional variation. It does not create a separate
calibration exercise or artifact.

If a settled attempt elsewhere exposes **Restart**, select that exercise to use
its recovery. The recovery row does not replace the current exercise selected
by the dependency chain and does not hide Exercise 1.1 or the next physical action.

Selecting a future or unavailable exercise does not display another exercise's
controls beneath its instructions. If work is still active elsewhere, its required
Stop appears separately under **Active exercise**, naming the exact owner. Return
to the current exercise to use its ordinary controls.

## 1.2 Measure and Center the Drawing Boundary

After a settled refusal or cancellation, inspect the previous-attempt diagnosis,
resolve the current admission blocker, and explicitly retry the allowed side or
center arrival. The old diagnostic does not disable a now-admissible action.
Accepted sides remain retained. A settled center-position miss may offer the
owner-issued **Retry Center Arrival**, still gated by current position and ambiguity
checks. Active effects, pending publication/reset, unknown position and sticky
ambiguity retain their owning controls and restrictions; nothing is replayed
merely because a prerequisite changed.

1. The operator selects any first X or Y direction. Selection is inert.
2. **Move Toward X−/X+/Y−/Y+** starts one operator-stopped Drawing Boundary search.
3. The controller uses finite 50 mm segments at 500 mm/min under one logical
   owner. After each unambiguous Idle/MPos it may renew another fixed segment
   while retaining direction and feed.
4. **Stop Boundary Search** remains bound to that motion.
5. Operator Stop closes renewal and emits one Jog Cancel.
6. The original owner settles through fresh Idle and final MPos.
7. Typed direction, Stop disposition, controller session/revision, and final
   MPos commit atomically as the side attempt and aggregate.
8. The forced opposite direction is shown as required noninteractive content.
9. After the pair, the operator chooses either sign on the remaining axis and
   records its forced opposite.
10. After all four sides, **Move to Estimated Center** admits one stoppable
    Pen-Up move.
11. Arrival succeeds only when the final MPos is within 1 mm of the derived
    center.

Boundary renewal has no Vision adviser. Controller authority, the fixed bounded
fallback segment, operator Stop, and final Idle/MPos evidence remain unchanged.

Natural completion of a finite segment is not side evidence. A healthy owner
may renew; operator Stop, limit, alarm, disconnect, or ambiguity terminates it.
Stopped or out-of-tolerance center travel preserves all four side aggregates
and exposes **Retry Center Arrival** for the remaining delta only.

The four current aggregates derive:

```text
center.x = (X− estimate + X+ estimate) / 2
center.y = (Y− estimate + Y+ estimate) / 2
local.x  = raw.x - X− estimate
local.y  = raw.y - Y− estimate
```

Learned local coordinates are presentation evidence. They do not rewrite MPos,
configure a work offset, clamp commands, or authorize motion.

## 1.3 Calibrate Camera from Pen Cap Positions

### Rectangle and roles

1. Require current accepted X−, X+, Y−, and Y+ Boundary aggregates, a current
   controller session/revision, Pen Up, and center arrival.
2. Inset the Boundary envelope by 10 mm.
3. Reduce it symmetrically around center when paper coverage or visibility of
   the full safe envelope is not separately known.
4. Require at least 10 mm usable span on both axes.
5. Record the chosen applicability rectangle and derivation.

The ordered positions and roles are:

| Order | Position | Normalized coordinate | Role |
| --- | --- | --- | --- |
| 1 | `C` | 50% X, 50% Y | fit |
| 2 | `X−` | 10% X, 50% Y | fit |
| 3 | `Y+` | 50% X, 90% Y | fit |
| 4 | `X+` | 90% X, 50% Y | holdout |
| 5 | `Y−` | 50% X, 10% Y | holdout |

### Capture, fit, and acceptance

1. Press **Run Five-Position Camera Calibration**.
2. The first fresh passive probe establishes this operation's controller-context
   baseline. Each later sample must compare compatible and advance that local
   baseline.
3. At every LIVE position, move Pen Up under the existing stoppable owner and
   require fresh Idle/final MPos within 1 mm. Establish a preliminary fresh-
   frame boundary, then acquire exactly three strictly newer exact inspection
   frames with one unchanged source and camera configuration. The preliminary
   boundary frame is not accepted cap evidence. Every inspection frame must
   yield one observed unambiguous cap candidate. Search the whole frame, centered
   on a predicted cap position when available; a wrong prediction never excludes
   pixels or resolves ambiguity. Visual-reference rejection retains candidate
   bounds and anchor, best score against 0.82, competing-match margin against
   0.06, and prediction residual when available. No accepted geometry is published
   for a weak or ambiguous match. Maximum pairwise centroid spread is diagnostic,
   without numerical rejection thresholds. Retain only the newest third frame and its measured
   centroid, reference bounds, confidence, selected cap anchor, and estimator provenance
   as authoritative evidence. Do not average geometry across the three frames.
4. Use a consistent final approach. Travel between already selected positions
   may be diagonal, but only the listed positions are model samples.
5. Fit an affine machine-to-cap map from `C`, `X−`, and `Y+`.
6. Predict the sealed `X+` and `Y−` holdouts. Both residuals must be at most the
   declared eight-pixel policy in the bootstrap implementation.
7. If both pass, refit all five with confidence-derived weights and stage one
   proposal containing residuals, uncertainty, exact-frame provenance,
   applicability, semantic optical identity, machine geometry, and coordinate
   revision.
8. **Accept Camera Calibration** commits the current
   `MachineCameraRegistration` atomically. **Reject Camera Calibration** commits
   nothing. Installing the registration and its fitted presentation bounds
   preserves the exact visible camera-pixel rectangle and any compatible locked
   analysis region.

Camera-calibration failures remain visible in the Learning instructions with
the detector's concrete reason and available score, margin and prediction
residual. For the same cap, choose **Learning Path Actions → Reidentify Pen Cap**
and click the same physical anchor on the fresh frozen frame. The previous
rectangle follows the stored anchor offset; redraw it only when needed. This
is an operator observation, not a successful detector result. With compatible
camera/controller/map context and settled Idle/Pen-Up, the app can retain
accepted camera, tip and drawing calibration and record the residual and reference
lineage. Inside the map domain, the residual must be at most eight pixels. Outside
it, the operator's same-anchor observation may update appearance while its
residual is labeled extrapolated and advisory; the accepted map and domain stay
unchanged, without extending motion authority or calibration applicability.
A successfully saved new camera calibration
supersedes the recovery lineage and binds the new map to the current appearance;
failed or cancelled proposals retain the previous map and lineage. An incompatible
context or an excessive in-domain residual refuses the change and retains the prior Learning package.
Down or unknown pen state requires an explicit Raise Pen action; recovery does
not raise the pen automatically.

For a changed cap or anchor, choose **Replace Pen Cap Reference** and select a
new rectangle and anchor. It preserves accepted pen-up/down actuation, X/Y
boundaries, estimated center and center arrival. Only a successfully saved
replacement invalidates the camera/cap map and downstream tip/drawing calibration.
Both paths are observation-only and are permitted after a settled possible-ink
failure; neither clears existing-mark exclusions nor permits another mark.
Active motion and unresolved owners still block recovery. Cancellation, stale
selection and save failure retain previous in-memory authority. A failed save
attempts to restore the preceding checkpoint and reports uncertain durability
if restoration also fails. Each operator-started
calibration retry captures a new reference frame and current machine pose;
it does not reuse the reference from a failed attempt that may have stopped
at another position.

The cap landmark is not the hidden paper-contact point. Three non-collinear
samples without the two holdouts cannot become authority.

SIMULATED uses separate causal generated geometry. It exercises the same sample
roles and downstream fit contract but is nonphysical and does not prove live cap
stability, camera behavior, or attended optical reliability.

A device, build, units, distance mode, work coordinate, controller setting, or
coordinate-offset change stops the operation with typed recovery. App-owned
Pen Up modal changes remain visible provenance but do not masquerade as a
coordinate change.

## 1.4 Calibrate Pen Tip from Corner Marks

### One supervised physical batch

Exercise 1.4 draws no center mark. It places four 2 mm-radius circles with every
center exactly 10 mm inside its two adjacent accepted Boundary edges. Every
circle footprint therefore remains 8 mm clear of those edges. Those
four centers bound the accepted tip-map applicability and subsequent Drawing
Border validation. Exercise 1.3 retains its separate center plus four ±24 mm positions
and camera-holdout authority.

1. Press **Draw Four Calibration Circles** once. One exercise attempt and one existing
   stoppable operation own the complete batch and expose the contextual Stop.
2. The app commands and settles Pen Up once before the first travel. No separate
   manual Pen Up is required, including after applying Saved Learning with an
   Unknown or Down current pen pose. Failed settlement prevents travel. Retain that
   batch-scoped Pen-Up authorization through approach, circle-start,
   inter-circle, and reveal travel; do not issue another raise solely to begin
   travel while the authorization remains current. At each canonical position,
   require fresh Idle/final MPos
   within 1 mm, capture and retain that circle's exact pre-mark frame and cap
   anchor, and retain its controller and settled-position evidence.
3. Verify the full circle lies inside the accepted Boundary envelope. Move Pen Up
   to its +X start point and settle.
4. Lower and settle with the current Exercise 1.1 Pen Down profile. Draw one
   closed 16-chord, 2 mm-radius circle at 500 mm/min or the lower
   controller-reported axis ceiling, requiring settled chord endpoints.
5. Raise and settle Pen Up. Only then travel to the next circle. Repeat steps
   2–5 without a reveal or click between circles. The batch contains exactly 64
   typed circle-chord outcomes, four Pen Down settlements, five Pen Up
   settlements including the initial normalization, and no connecting Pen-Down
   stroke. It performs four pre-mark controller-context probes, not one per
   chord.
6. After the fourth circle, return Pen Up to the rectangle's geometric
   center. Require Pen Up, Idle, and final-MPos settlement.
7. Capture one strictly newer exact frame and revalidate current camera/cap
   applicability once using the fifth controller-context probe. Publish one
   final machine snapshot and freeze that cap-bearing reveal frame as the first
   exact click request. Do not change viewport zoom, pan, fitted region,
   preferred zoom, or focus.
8. After the operator clears the armature, **Capture New Click Frame** may be
   used only while the current request has zero retained clicks. Reacquire
   current connected Idle, Pen Up, no active controller operation, no sticky
   ambiguity, unchanged attempt and paper, unchanged source and semantic
   optical identity, and one strictly newer exact frame. Atomically supersede
   the old request; do not move, actuate the Pen, redraw, retry automatically,
   or fabricate another cap estimate. Preserve the original reveal evidence.

If a controller-completed circle batch is unusable, **Cancel Attempt** settles the
existing calibration owner and clears its pending click/proposal state. **Restart
Attempt**, **Redo This Step**, or **Reset Selected Step…** are explicit recovery
choices; reset previews its selected suffix and names existing calibration marks.
These actions do not declare the sheet clear or replay the completed circles.
All completed circle locations remain possible-ink exclusions on that sheet.
Record a new sheet on the same contact plane before another attempt needs those
locations, then accept its displayed placement and explicitly start the attempt.
Compatible upstream Learning and physical history remain retained. An unsuccessful
replacement attempt preserves the previous accepted tip calibration; chronological
scoped reset still invalidates its disclosed suffix. Stop settles active work;
Cancel abandons transient review; terminal shutdown permanently closes admission.

When calibration stops after possible ink, the Learning prompt names the original
failure and explains paper recovery. Paper replacement clears the marked-sheet
restriction; it does not claim the original detection problem was fixed.

If a chord, motion outcome, or Pen state after possible contact is stopped or
ambiguous, blacklist the affected circle location on the current paper and
stop. Never retry, resend, redraw, or continue automatically. Each resulting
`ToolContactObservation` retains its own physical operation evidence while all
four share the final reveal frame. Controller completion does not prove
physical contact or ink; attended observation owns those claims.

### Unordered clicks, model construction, and acceptance

1. Show all collected click markers and the count on the current shared frozen
   click frame. Convert every presentation click through the exact inverse
   transform to camera pixels and retain exact frame/provenance identity. Each
   accepted click cites that exact frame; older persisted observations without
   a separate click frame use their original reveal frame.
2. Clicks may arrive in any order. After click four, project the four known
   corner machine positions through current `MachineCameraRegistration`. Center both
   projected and clicked point sets to remove their unknown common cap-to-tip
   translation. Retain each earlier cap-map residual as diagnostic evidence;
   do not gate a Boundary-corner observation on extrapolation from the smaller
   Exercise 1.3 bootstrap rectangle.
3. Evaluate all 4! one-to-one assignments and choose the minimum total squared
   pixel distance. Resolve an exact numerical tie in canonical calibration-
   position order. Apply no distance or ambiguity threshold.
4. **Undo Last Click** or **Clear Clicks on This Frame** changes same-frame
   click evidence only. It performs no motion, ink, redraw, capture, zoom, or
   pan. **Capture New Click Frame** is available only at zero clicks; a partial
   click set must be explicitly cleared before replacement.
5. After click four, atomically create the four accepted observations. Fit one
   direct affine pen-tip calibration from all four first. Construct constant
   camera-pixel correction only if affine construction throws.
6. Display model form, all-corner residuals, RMS, covariance/uncertainty,
   applicability, semantic identities, and consumed revisions as diagnostics.
   Exercise 1.4 has no holdouts and no numerical magnitude can block proposal
   creation or progression. Numerical fitting never requests paper replacement
   and never routes to **No Automatic Redraw**.
7. The fourth valid click constructs a reviewable `TipCameraRegistration`
   proposal. On the same frozen frame, inspect the exact markers, the separately
   labeled projected Drawing Boundary, the cyan proposed rectangle through the four
   selected centers, and the diagnostic fit, then choose
   **Accept Pen-Tip Calibration** to commit it, save the accepted Learning Path prefix,
   finish Exercise 1.4, and make Stage 2 current. **Reject Pen-Tip Calibration**, **Undo Last
   Click**, and **Clear Clicks on This Frame** keep the same frozen frame and
   perform no motion or redraw. If acceptance fails atomically, expose **Retry
   Calibration Commit**.

### Durable restart restoration and changed-setup recovery

Loading is presentation-only and never restores Learning or operational
authority. Motion, current Pen pose, active owners, Stop capabilities, current
frames, and pending commands remain session-local.

For an unchanged physical setup:

1. Start the replacement binary or restart the process/capture session. These
   software lifetimes do not rotate a physical semantic identity.
2. Start the same camera device. Before applying anything, inspect the saved
   Drawing Border, predicted cap/tip where available, and reconstructable prior
   drawing plans projected on the current frame. Old-coordinate archived paths
   are omitted after rebase when their typed applicability no longer matches;
   their evidence remains retained, and current Boundary/Border still appears.
3. Read the advisory optical comparison. A compatible bounded reference reports
   integer X/Y shift and background mean absolute difference; incompatible or
   legacy packages report why the comparison is unavailable. No value gates the
   operator choice.
4. Choose exactly **Use Saved Learning** or **Start New Learning**. Use applies
   the exact saved dependency revisions atomically without motion or Pen-pose
   restoration. Start New applies nothing and retains the last complete package.
5. Connecting and probing remain ordinary controller-session work; they do not
   implicitly apply saved Learning or prove physical carriage position. MPos can
   stay unchanged while the unpowered armature moves under gravity.
6. Choose **Enable Motion & Raise Pen** when motion is disabled. It authorizes
   motion and settles Pen Up with the current learned settings, skipping an
   already-Up pen. If preparation fails, use **Raise Pen** beside position
   recovery and resolve its displayed prerequisite; opening Motion is unnecessary.
   A finite held pen operation remains busy until its existing owner settles.
   If Saved Learning was loaded after enabling, a different accepted pen profile
   makes the prior Up state Unknown without issuing motion; use adjacent Raise
   Pen to settle those settings. Identical settings retain the settled state.
   With the same live camera and settled Pen Up, choose
   **Re-establish Position from Camera**. The existing tip-checkpoint owner
   captures fresh exact-frame learned-cap evidence without moving or marking.
   A compatible observation verifies the current position or coherently rebases
   the retained machine Boundary, camera map and tip calibration for a supported
   translation. Learning remains complete. Unavailable, ambiguous, stale or
   incompatible evidence leaves drawing blocked with the specific recovery
   reason; cancellation or persistence failure publishes no partial authority.
7. Confirm coverage for the current sheet and exact frame, choose **Draw border**
   if wanted, and Draw. Do not repeat Learning merely to recover a compatible
   carriage translation. A verified uninterrupted session does not require this
   recovery again for ordinary known motion or a same-plane replacement sheet.
   If the saved prefix has only Boundary artifacts and no camera/cap map, follow
   the specific Boundary/Camera recovery remedy; direct manual controls remain
   available under their existing controller/Motion requirements.

When the saved package and drawing archive contain a completed Drawing Border
result for that calibration, applying Saved Learning restores **Learning
complete** and the filled graduation cap. Current Pen Unknown or Down does not
reopen cap identification or accepted Pen calibration; Draw's existing Pen Up
normalization must settle before travel. Controller, physical-position applicability, Motion, paper, camera and
plan currentness remain separate execution prerequisites. Tip
checkpoint revalidation retains the original accepted calibration lineage, so
its existing Border result can survive subsequent save/load cycles without
another Border draw.

If the controller coordinate frame was actually reset, the camera was moved or
reframed, the tool/contact profile changed, or the contact plane changed, do
not claim the unchanged-restart path. A detectable controller or optical
mismatch keeps authority unavailable. Use the owning reset/recovery path; only
a proven pure coordinate translation may rebase accepted machine/camera/tip
geometry without new marks. Unknown physical change requires rebuilding the
affected suffix.

Before tip calibration is accepted, place paper using the visible canonical
four-circle frame, centers and paths. These calibration guides remain visible when
artwork is hidden and never substitute for its exact preview frame or geometry.
The machine-camera/cap-map guide explicitly
has unknown tip offset and may extrapolate. **Accept Sheet Placement** records
only this qualified placement assertion for the current sheet and displayed
context. It does not complete calibration or enable calibrated Drawing. Start the
next admissible Learning action explicitly. Once compatible tip calibration exists,
use **Sheet Covers Target** for calibrated coverage. A disabled action explains
which current frame, Boundary or compatible calibration is missing.

After a new sheet on the explicitly unchanged contact plane:

1. Wait for the current run and evidence publication to settle; then record
   **New Sheet — Same Contact Plane**. Persistence precedes publication of the
   new paper instance. A failed or partially completed checkpoint save restores
   the exact predecessor. Once committed, final coverage/run handoff and
   projection settle even if shutdown begins.
2. Expect “New sheet recorded. Calibration retained.” Accepted pen settings,
   boundaries, camera/tip calibration and completed Learning remain current.
   Prior records retain their original sheet and calibration identities;
   sheet coverage, transient proposals/captures and sheet exclusions clear.
   The existing no-redraw owner indexes the new current sheet; a previous
   sheet's completed plan does not prohibit the next sheet, and same-sheet
   possible ink still prohibits replay.
3. Inspect the calibrated outline on the current compatible camera view, then
   **Sheet Covers Target**. Before tip acceptance, use the qualified guide and
   **Accept Sheet Placement** instead; that assertion does not satisfy Drawing
   readiness. The action seals the frame actually visible on
   the canvas and binds it to the relevant coverage or qualified placement assertion;
   passive video does no hashing. A late older analysis cannot substitute another
   frame. Draft and Run retain a coherent selected frame. Neither assertion
   measures paper edges or requires existing ink.
4. Choose **Draw border** if this ordinary drawing should ink the calibrated
   border. Each new drawing defaults off; edits of that drawing retain the
   explicit choice. It shares the drawing's plan/Stop/evidence and does
   not repeat the Learning exercise. Inspect the target and click **Draw**.

If accepted data survives but active calibration was lost by an earlier reset,
use **Use Saved Learning** to reapply the compatible package through current
accepted-checkpoint validation. The startup choice need not still be pending.
Do not use that route to conceal an incompatible physical dependency.

After a changed support, stock thickness, contact height, or contact plane:

1. Record **Contact Plane Changed**, rotating both paper identities and
   invalidating dependent tip calibration.
2. Retain accepted machine boundaries and machine/camera Learning while their
   own dependencies remain valid; revalidate only an actually changed dependency.
3. Run the complete Exercise 1.4 four-circle calibration on the new plane;
   review and explicitly accept its new tip registration before drawing.

Any mismatch or ambiguous contact leaves authority unavailable. It never falls
back to automatic redraw or silent checkpoint promotion.

## 2.1 Draw and Validate the Drawing Border

Exercise 2.1 requires the exact current accepted `TipCameraRegistration` revision.
Every request/result cites that revision. It is one visible exercise with one
normal **Draw and Validate Drawing Border** action; the following are truthful runtime phases, not selectable
exercises or approval gates:

1. **Plan and preview.** The app constructs the closed Drawing Border
   through the four accepted circle centers in minimum/minimum,
   minimum/maximum, maximum/maximum, maximum/minimum order, then returns to the
   start. It retains the projected accepted Drawing Boundary as separate context,
   projects the immutable inset plan through the current tip registration, and
   renders the predicted Drawing Border in cyan before any motion. The Drawing
   Border remains exactly 10 mm inside the accepted Drawing Boundary. Planning
   uses the accepted Drawing Boundary as its spatial envelope; the Drawing
   Border is not an admission boundary. `DrawingRegionContainmentPolicy` uses
   closed accepted-Boundary bounds with only its 1e-9 mm numerical epsilon.
   Controller-pose settlement uses its separate Euclidean policy and cannot
   enlarge the drawing region. Completed `FIX-00` removed the former shared
   0.5 mm expansion.
2. **Capture local baseline.** With Pen Up and the controller Idle, capture one
   exact fresh frame and record the current MPos as this validation's reveal pose.
3. **Move to Drawing Border start.** Move Pen Up under one stoppable owner. Completion
   requires fresh Idle/final MPos within 1 mm.
4. **Draw Drawing Border.** Confirm the start, lower the pen once, execute all
   four orthogonal edges under the canonical drawing-plan owner, and raise.
5. **Reveal and observe.** Return Pen Up to the recorded reveal MPos, require
   fresh Idle/final MPos within 1 mm, capture a post-frame strictly newer
   than the baseline and drawing settlement, and run bounded same-pose
   new-ink difference Vision. While this runs, the UI states that drawing-validation Vision owns
   processing. Match detected pixels to the nearest planned path without a
   distance cutoff, so geometric error produces a residual. Retain observed
   geometry and residual, or a typed rejection with the detected pixel count
   when extraction ran. A correspondence rejection does not mean no pixels
   were detected.
6. **Compare.** On normal observed-ink success, record the typed intended versus
   observed comparison automatically and display predicted cyan, observed white,
   and residual orange geometry on the exact post-frame. Retain that frame for
   explicit later review, resume live preview, and append an evaluation-holdout
   drawing-run record. A naturally completed draw with a rejected Vision
   observation also completes Learning: retain the exact rejection as
   `visionUnclear`, with zero verified ink strokes and no successful comparison
   artifact. Both paths retain the result automatically in the existing drawing
   evidence archive and accepted Learning checkpoint.

**Stop** remains available for active motion. Refusal or ambiguity before
contact creates no drawing evidence and stops for recovery. Once stroke
admission or possible ink exists, no path may redraw automatically; recovery
continues only with Pen-Up return and observation of the existing mark. A Vision
rejection after controller-completed drawing is an observation-quality result,
not a reason to repeat the drawing. Motion failures and comparison-commit
failures remain visible with their actual phase and detail.

Completion marks Exercise 2.1 complete with review/reset operations available.
The graduation cap fills and the toolbar reports **Learning complete**. Drawing
Studio running becomes available; its authoring controls are always accessible.
Trial completion and observation quality are
separate facts; completion does not assert general adaptive-drawing readiness.

## Portrait Studio — prepare, place, draw, and observe

1. Reveal **Portrait Studio** from **View**, including before Learning completion.
   Use the persistent camera button for a burst or import a photo, then adjust
   framing and the chosen style. Expand Styles to compare the five existing
   algorithms; folded Styles renders only the chosen algorithm.
   **Send to Drawing** saves the candidate, installs its immutable program,
   selects the plotter camera role and opens Drawing. **Save Imagination** is optional
   library storage. Neither action moves hardware. Complete Exercise 2.1 before drawing.
   Use **Review Comparison** in **Video Settings** to return to the pinned exact
   post-frame. Close its canvas box with **×**, or use **Resume Live Preview** in
   Video Settings before placement. Closing retains the comparison and removes
   the box entirely; it does not leave another Review notification on the canvas.
2. Confirm the accepted Drawing Boundary outline is visible. Place the current
   physical sheet over it and choose **Sheet Covers Target**. The assertion
   cites the current paper instance, contact plane, source, exact frame, and
   camera configuration. It does not change calibration.
3. Review the retained portrait target. **Fit to Drawing Area** recomputes uniform
   scale while preserving rotation. **Center Drawing** centers transformed ink
   bounds without changing scale or rotation. The plan remains deterministic.
   Active Learning separately supplies sealed coverage-experiment programs.
4. Click the video to place its center, then set uniform scale and rotation.
   The workspace creates a new immutable placement and content-addressed plan on
   each change. Ordinary artwork is clipped at the accepted Drawing Boundary;
   exits and re-entries become separate strokes without bridges. Fully excluded
   artwork has no runnable plan. Metric/calibration targets retain strict containment.
5. Review the exact plan in Drawing and on advancing compatible plotter frames.
   The Drawing image remains visible above scrolling controls. Ordinary portrait
   drawing has no pre-run learning-role selector. Active Learning assigns its
   predeclared experimental roles internally.
6. Press **Draw** only when LIVE controller admission, Motion, current
   paper coverage, and the exact plan are all current. The app redundantly
   commands and settles Pen Up before observation-position travel; prior Pen
   command knowledge is not trusted. It then selects the plan's final point as
   the same-pose observation location and captures the local pre-drawing baseline there.
7. One `RunInterpreter` owner preflights the controller-precision schedule, then
   redundantly normalizes Pen Up again, performs plan travel, lower, each finite segment,
   raise, and the logical-stroke checkpoint sequence. **Stop** is capability-
   bound to that owner. Competing plans are refused without replacing active
   progress. The command-bar Stop remains reachable when Motion, Portrait Studio,
   or any other panel is hidden or redocked; unavailable requests show their remedy.
8. On controller-completed execution, require final MPos at the observation
   location, capture a strictly newer post frame, associate new ink against all
   planned polylines, and retain intended, observed, and residual overlays on
   that exact frame. The target contract makes projection outside the current
   tip-registration applicability diagnostic-only and the camera/ink result
   non-attributable unless a newer validated applicability revision covers it.
   An outside-applicability plan can execute but invokes no Vision and records
   zero verified strokes as non-attributable, retaining the exact
   `projectionOutsideTipApplicability` reason. Completed `FIX-01` corrected the
   extrapolation defect documented at `DOC-01`; it is not a current evidence path.
9. Append the terminal record even when execution is refused, cancelled,
   ambiguous, possible-ink, or Vision-unclear. Never resend or redraw after a
   terminal result. Retained outcomes stay visible until **Prepare Next Drawing**
   acknowledges the exact run; an unresolved evidence publication remains visible
   and blocks handoff. In **Active Learning**, select retained attributable ordinary
   or training drawings and choose **Analyze for Learning**. This fits only
   identifiable constant X/Y translation from stroke normals, shows the result
   or insufficiency reason, and neither changes the archived role nor applies
   a model. Reserved/evaluation holdouts remain sealed evaluation.

**New Sheet — Same Contact Plane** retains the accepted map and validation but
rotates sheet identity and requires a new coverage assertion. **Contact Plane
Changed** invalidates the pen-tip calibration and returns the dependency chain to contact
calibration. Simulation may exercise catalog placement and exact plan preview;
it cannot run the physical Drawing Studio operation or produce physical run
evidence.

## Dependency and recovery contract

```text
four side aggregates -> center -> center arrival
-> five-cap machine-camera registration
-> four immutable contact observations -> accepted tip-camera registration
-> closed Drawing Border plan + local baseline/reveal pose
-> Drawing Border execution + newer post-frame
-> planned ink observation -> residual -> typed comparison + durable validation record
-> paper coverage + placed DrawingProgram -> immutable execution plan
-> controller execution -> exact-frame planned-ink observation -> run record
```

For Exercise 1.3, **Redo This Step** prepares a fresh camera-calibration attempt
while retaining the accepted map. Click **Run Five-Position Camera Calibration**
to acquire a new proposal. Cancel/Stop discard the unaccepted proposal and join the
current owner; **Restart Attempt** prepares fresh acquisition rather than presenting
the cancelled proposal's Accept/Reject controls. Failure or rejection retains the
accepted fallback. Successful acceptance alone replaces it and invalidates affected
dependents. These preparations never request movement automatically.

Redo invalidates named transitive dependents only after a successful replacement
commit. Failure preserves the current accepted value. Record Another Attempt
adds only compatible successful evidence. Preparation and point-selection
acknowledgements follow the actual owner result; refusal, capture/sampling failure
or persistence failure must not be shown as a successful button action.

When resetting a later suffix, retained Pen Learning includes its original
compatible cap appearance and reference frame in the saved prefix. Reloading that prefix must
not require re-identifying the cap or reading a legacy appearance preference.
Incompatible tool/camera context is not silently reused, and resetting Pen clears
its appearance authority as before.

Reset From This Step is a separate operator-authored chronological rewind. It
shows the exact suffix, includes unaccepted circle batches/pending selections and
calibration marks, and rejects a stale summary. The Learning menu exposes **Reset
Selected Step…** for that selected suffix. Selected exercise controls take precedence
over unrelated settled recovery; an active owner retains its Stop. Reset All Learning is always
available from the Learning Path menu. It cancels and settles a current
Learning-owned operation through its typed owner, then clears all accepted
Learning authority for the current source, including the durable accepted
checkpoint, and returns progression to Exercise 1.1. Reset also clears the selected cap appearance for the current source and stops
analysis with that old color, so Exercise 1.1 requires a new exact-frame cap
selection. Reset itself admits no
new motion, changes no pen state merely to reset, never resends or redraws, and
does not claim to erase ink. It preserves the controller session, Motion
authorization, and selected camera so direct manual controls remain independent.

Restored Learning coordinates that require visual revalidation block only
coordinate-dependent Learning and Drawing work. They do not block an
operator-authored manual jog or manual Pen command. Direct manual controls use
the Motion toggle and the controller's native connection, alarm, readiness,
safety, and command-serialization checks; no Learning Path state is an extra
manual-motion gate.

Semantic optical changes invalidate optical dependents but do not invalidate
compatible machine-space Boundary aggregates. Presentation-only transform
changes invalidate nothing. Paper-plane changes quarantine contact authority;
raw observations remain history.

## Causal simulator contract

SIMULATED traverses the same public actions and dependency graph. It owns a
simulated session, Motion authorization, MPos, pen pose, renewable Boundary
motion, 2 mm-radius circular marks, closed Drawing Border drawing, paper revision,
persistent ink, causal frames, and a real nonzero cap-to-tip truth.

Annotations are exact identity-bound presentation only. They do not modify
canonical pixels or hashes. Stop, ambiguity, cancellation, and shutdown win
before later mutations. Every simulator surface states
`SIMULATED — NOT PHYSICAL EVIDENCE`; no route invokes physical machine actions.
