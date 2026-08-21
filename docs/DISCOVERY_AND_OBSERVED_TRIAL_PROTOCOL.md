# Discovery and Observed-Trial Protocol

Status: current operating protocol for Learning Path 3.1 through visible 4.1

This document owns the exact actor, action, evidence, dependency, and recovery
sequence. Durable semantics remain in [Product Contract](PRODUCT_CONTRACT.md).

## Common actor contract

Every interactive step exposes:

- one current participant: App, Operator, Controller, Camera, Vision, or Pen;
- one typed current action and expected observation;
- one explicit button-owned transition;
- one operation owner when controller or simulator state may change;
- one contextual Stop while that owner is stoppable;
- one typed attempt and disposition;
- exact artifact dependencies for every accepted result.

Announcements are advisory output. Buttons own answers, Start, Cancel, Stop,
Restart, Redo, re-click, and acceptance.

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

Cancel abandons a settled attempt. Stop settles an admitted stoppable owner.
They may share a mechanical Jog Cancel primitive but never share a successful
semantic disposition. Sticky ambiguity suppresses new physical motion.

Every production comparison of requested pose and settled MPos uses fresh
attributable controller evidence, compatible context, and the shared 0.05 mm
Euclidean policy.

Presentation zoom, pan, and fitted bounds are available after 3.2. They are
view-only. Exact camera-pixel evidence and calibration authority do not change
when the presentation transform changes. Learning visibility and compatible
presentation-context changes preserve the operator's exact effective visible
camera-pixel rectangle; preserving only numeric zoom and pan is insufficient
when fitted bounds change. Stage 3.3 proposal review preserves the viewport;
acceptance may publish a new fitted target but does not auto-focus or rewrite a
locked analysis region. Camera source or configuration changes reset the
viewport. Explicit operator Full, Fit, zoom, and pan actions may replace it.
Stage 3.4 never changes zoom, pan, fitted region, preferred zoom, or viewport
focus automatically.

The only global scene-overlay preferences are **Pen cap** and **Armature
envelope**. The envelope is inferred from the cap, not segmented. Generic
viewport ROI affects only generic requested scene analysis; it never constrains
the specialized regions used below. Intended geometry, observed ink, and
residuals are mandatory contextual evidence in Stage 4 and are not toggles.

## 3.1 Pen Interaction

1. Start the existing Pen Interaction attempt. Before any Pen Interaction
   question or pen request, **Identify Pen Cap** freezes the current exact frame
   and asks the operator to click the colored cap body, not the tip.
   When a valid LIVE cap appearance already exists, the frozen frame receives
   its own exact requested scene-overlay analysis; geometry from an earlier
   frame is never carried onto it. A first, unlearned appearance still requires
   the click before LIVE overlay recognition can run.
2. Map the presentation click back to the frozen camera frame and inspect the
   clipped 9 x 9 neighborhood. Reject a stale frame, unsupported pixel format,
   too few chromatic pixels, or a gray, white, or dark median with a concrete
   reason. An accepted sample persists its median RGB color, click point, exact
   frame hash and identity, source, camera configuration, dimensions, pixel
   format, usable/total sample counts, and algorithm revision. There is no
   editable color picker. The learned appearance feeds generic scene analysis
   and every Stage 3.3 exact-frame inspection, so arbitrary visibly colored caps
   such as blue are supported.
3. The Up step presents the current Up slider. It is seeded at `S40` in a fresh
   session and otherwise starts from the already-current value. Moving it
   commands the displayed value. **Next** remains available and accepts that
   value together with the available controller outcome, timestamp, and current
   MPos. Refusal, ambiguity, or unavailable evidence remains explicit and does
   not disable **Next**.
4. The Down step presents the current Down slider, seeded at `S760` in a fresh
   session and otherwise starting from the already-current value, with the same
   move-and-accept behavior.
5. The final Up step commands the accepted current Up value and completes the
   existing Up → Down → Up attempt.

If no LIVE appearance has been accepted, the persisted Pen cap and Armature
envelope overlay choices do not change, but both layers report Unavailable and
no LIVE geometry is rendered. An armature envelope is available only from an
accepted cap result and remains explicitly inferred, not independently
segmented.

The accepted values become the current Up and Down settings consumed by later
pen operations. They are not required to remain constant across the run.
Repeating Pen Interaction at another position creates another existing attempt
with its actual values and available position/actuation evidence so future
learning can evaluate positional variation. It does not create a separate
calibration exercise or artifact.

If a settled attempt elsewhere exposes **Restart**, select that exercise to use
its recovery. The recovery row does not replace the current exercise selected
by the dependency chain and does not hide Pen Interaction or the next **Start**.

## 3.2 Paired Boundary Discovery and Centering

1. The operator selects any first X or Y direction. Selection is inert.
2. **Start** admits one operator-stopped Boundary owner.
3. The controller uses finite 50 mm segments at 500 mm/min under one logical
   owner. After each unambiguous Idle/MPos it may renew another fixed segment
   while retaining direction and feed.
4. **Stop Boundary** remains bound to the original owner.
5. Operator Stop closes renewal and emits one Jog Cancel.
6. The original owner settles through fresh Idle and final MPos.
7. Typed direction, Stop disposition, controller session/revision, and final
   MPos commit atomically as the side attempt and aggregate.
8. The forced opposite direction is shown as required noninteractive content.
9. After the pair, the operator chooses either sign on the remaining axis and
   records its forced opposite.
10. After all four sides, **Move to Estimated Center** admits one stoppable
    Pen-Up move.
11. Arrival succeeds only when the final MPos is within 0.05 mm of the derived
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

## 3.3 Calibrate Camera and Visible Cap

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

1. Press **Capture Five Cap Samples**.
2. The first fresh passive probe establishes this operation's controller-context
   baseline. Each later sample must compare compatible and advance that local
   baseline.
3. At every LIVE position, move Pen Up under the existing stoppable owner and
   require fresh Idle/final MPos within 0.05 mm. Establish a preliminary fresh-
   frame boundary, then acquire exactly three strictly newer exact inspection
   frames with one unchanged source and camera configuration. The preliminary
   boundary frame is not accepted cap evidence. Every inspection frame must
   yield one accepted unambiguous cap candidate; zero-threshold-pixel,
   rejected-component, ambiguous, and failed results refuse the sample. Refuse
   the sample when maximum pairwise cap-component centroid spread exceeds 2 px.
   When all three are stable, retain only the newest third frame and its measured
   centroid, bounds, confidence, bottom-center anchor, and estimator provenance
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
8. **Accept Camera and Visible-Cap Fit** commits the current
   `MachineCameraRegistration` atomically. **Reject Camera Fit** commits
   nothing. Installing the registration and its fitted presentation bounds
   preserves the exact visible camera-pixel rectangle and any compatible locked
   analysis region.

The cap landmark is not the hidden paper-contact point. Three non-collinear
samples without the two holdouts cannot become authority.

SIMULATED uses separate causal generated geometry. It exercises the same sample
roles and downstream fit contract but is nonphysical and does not prove live cap
stability, camera behavior, or attended optical reliability.

A device, build, units, distance mode, work coordinate, controller setting, or
coordinate-offset change stops the operation with typed recovery. App-owned
Pen Up modal changes remain visible provenance but do not masquerade as a
coordinate change.

## 3.4 Calibrate Pen Contact from Sparse Marks

### One supervised physical batch

Stage 3.4 draws one circle at the accepted Boundary envelope's geometric center
and four circles at the maximum drawable corners formed by `minX + 2 mm`,
`minY + 2 mm`, `maxX − 2 mm`, and `maxY − 2 mm`. The complete radius remains
inside the envelope, and the four outer centers become the accepted tip-map and
Drawing Studio applicability rectangle. `C`, `X−`, `Y+`, `X+`, and `Y−` remain
canonical evidence-slot identities. Stage 3.3 retains its existing separate
±24 mm spacing and camera-holdout authority.

1. Press **Draw Five 2 mm Circles** once. One exercise attempt and one existing
   stoppable operation own the complete batch and expose the contextual Stop.
2. At each canonical position, travel Pen Up, require fresh Idle/final MPos
   within 0.05 mm, capture and retain that circle's exact pre-mark frame and cap
   anchor, and retain its controller and settled-position evidence.
3. Verify the full circle lies inside the accepted Boundary envelope. Move Pen Up
   to its +X start point and settle.
4. Lower and settle with the current Pen Interaction Down profile. Draw one
   closed 16-chord, 2 mm-radius circle at no more than 100 mm/min or the lower
   controller-reported axis ceiling, requiring settled chord endpoints.
5. Raise and settle Pen Up. Only then travel to the next circle. Repeat steps
   2–5 without a reveal or click between circles. The batch contains exactly 80
   circle chords and no connecting Pen-Down stroke. The accepted calibrated-
   region overlay supplies the bounding box through the four outer centers.
6. After the fifth circle, return Pen Up to the outer rectangle's geometric
   center. Require Pen Up, Idle, and final-MPos settlement.
7. Capture one strictly newer exact frame and revalidate current camera/cap
   applicability once. Freeze that one frame unchanged for all five clicks.
   Do not change viewport zoom, pan, fitted region, preferred zoom, or focus.

If a chord, motion outcome, or Pen state after possible contact is stopped or
ambiguous, blacklist the affected circle location on the current paper and
stop. Never retry, resend, redraw, or continue automatically. Each resulting
`ToolContactObservation` retains its own physical operation evidence while all
five share the final reveal frame. Controller completion does not prove
physical contact or ink; attended observation owns those claims.

### Unordered clicks, model construction, and acceptance

1. Show all collected click markers and the count on the shared frozen frame.
   Convert every presentation click through the exact inverse transform to
   camera pixels and retain exact frame/provenance identity.
2. Clicks may arrive in any order. After click five, project the five known
   machine positions through current `MachineCameraRegistration`. Center both
   projected and clicked point sets to remove their unknown common cap-to-tip
   translation. Retain each earlier cap-map residual as diagnostic evidence;
   do not gate a Boundary-corner observation on extrapolation from the smaller
   Stage 3.3 bootstrap rectangle.
3. Evaluate all 5! one-to-one assignments and choose the minimum total squared
   pixel distance. Resolve an exact numerical tie in canonical calibration-
   position order. Apply no distance or ambiguity threshold.
4. **Undo Last Click** or **Clear Clicks on This Frame** changes same-frame
   click evidence only. It performs no motion, ink, redraw, capture, zoom, or
   pan.
5. After click five, atomically create the five accepted observations. Fit one
   direct affine machine-to-tip map from all five first. Construct constant
   camera-pixel correction only if affine construction throws.
6. Display model form, all-five residuals, RMS, covariance/uncertainty,
   applicability, semantic identities, and consumed revisions as diagnostics.
   Stage 3.4 has no holdouts and no numerical magnitude can block proposal
   creation or progression. Numerical fitting never requests paper replacement
   and never routes to **No Automatic Redraw**.
7. The fifth valid click constructs a reviewable `TipCameraRegistration`
   proposal. Inspect the exact-frame markers and diagnostic fit, then choose
   **Accept Tip Map** to commit it, save the accepted Learning Path prefix,
   finish Stage 3.4, and make Stage 4 current. **Reject Tip Map**, **Undo Last
   Click**, and **Clear Clicks on This Frame** keep the same frozen frame and
   perform no motion or redraw. If acceptance fails atomically, expose **Retry
   Calibration Commit**.

### Durable restart restoration and changed-setup recovery

Loading restores accepted learning values but never restores operational
authority. Motion, current Pen pose, active owners, Stop capabilities, frames,
and pending commands remain session-local.

For an unchanged physical setup:

1. Start the replacement binary or restart the process/capture session. These
   software lifetimes do not rotate a physical semantic identity.
2. Start the same camera device. Its current source and semantic optical
   configuration must match the saved registration.
3. Connect and complete the read-only passive controller-context probe. A
   matching probe restores Boundary, center, Stage 3.3, the five Stage 3.4
   observation revisions, the exact accepted tip revision, and attributable
   Stage 4 completion without replaying motion.
4. Require no **Revalidate Saved Tip Calibration** action, cap capture, click,
   mark, paper replacement, or Learning Path replay.
5. An operator may keep Motion disabled and inspect the current projected
   region/plan against the unchanged scene as a manual sanity check. That
   inspection is optional and does not create a new calibration gate.

If the controller coordinate frame was actually reset, the camera was moved or
reframed, the tool/contact profile changed, or the contact plane changed, do
not claim the unchanged-restart path. A detectable controller or optical
mismatch keeps authority unavailable. Use the owning reset/recovery path; only
a proven pure coordinate translation may rebase accepted machine/camera/tip
geometry without new marks. Unknown physical change requires rebuilding the
affected suffix.

After a new sheet on the explicitly unchanged contact plane:

1. Rotate only `PaperInstanceRevision` and clear sheet-specific paper coverage,
   possible-ink locations, and retained drawing review state.
2. Retain current tip authority and the attributable line-validation lineage.
3. Place the new sheet over the calibrated outline and explicitly assert that
   it covers the outline before drawing. This is an operator assertion; paper
   edges are not measured.

After a changed support, stock thickness, contact height, or contact plane:

1. Rotate `PaperInstanceRevision` and `PaperContactPlaneRevision` and invalidate
   current tip authority.
2. Rebuild and accept current Stage 3.3 authority.
3. Run the complete Stage 3.4 five-circle batch on the new plane; review and
   explicitly accept its new tip registration.

Any mismatch or ambiguous contact leaves authority unavailable. It never falls
back to automatic redraw or silent checkpoint promotion.

## 4.1 Run Predicted Isolated Line Trial

Stage 4.1 requires the exact current accepted `TipCameraRegistration` revision.
Every request/result cites that revision. It is one visible exercise with one
normal **Go** action; the following are truthful runtime phases, not selectable
exercises or approval gates:

1. **Plan and preview.** In deterministic X+, X−, Y+, Y− preference order, the
   app chooses the first 5 mm local line inside the applicability rectangle that
   clears every persistent 2 mm-radius calibration circle by at least 0.25 mm.
   A crowded domain blocks. The app projects both endpoints through the current
   tip registration and renders the predicted line in cyan on the current live
   frame before any motion.
2. **Capture local baseline.** With Pen Up and the controller Idle, capture one
   exact fresh frame and record the current MPos as this trial's reveal pose.
3. **Move to line start.** Move Pen Up under one stoppable owner. Completion
   requires fresh Idle/final MPos within 0.05 mm.
4. **Draw isolated line.** Confirm the start, lower the pen, execute one typed
   5 mm stroke under one drawing owner, and raise.
5. **Reveal and observe.** Return Pen Up to the recorded reveal MPos, require
   fresh Idle/final MPos within 0.05 mm, capture a post-line frame strictly newer
   than the baseline and drawing settlement, and run bounded same-pose
   black/new-ink Vision. While this runs, the UI states that trial Vision owns
   processing. Retain observed geometry and residual, or a typed rejection.
6. **Compare.** On normal observed-ink success, record the typed intended versus
   observed comparison automatically and display predicted cyan, observed white,
   and residual orange geometry on the exact post-line frame. Pin that frame and
   comparison for explicit later review, and append an evaluation-holdout
   drawing-run record.

**Stop** remains available for admitted motion. Refusal or ambiguity before
contact creates no drawing evidence and stops for recovery. Once stroke
admission or possible ink exists, no path may redraw automatically; recovery
continues only with Pen-Up return and observation of the existing mark. A Vision
rejection or comparison-commit failure stops for review or retry without
drawing again.

Completion remains on 4.1 with review/reset operations available. It proves one
attributable validation of the current map, not a generally trained adaptive
drawing model. The toolbar reports **Interactive learning complete · one
validation** and exposes Drawing Studio as a separate direct workbench, not a
selectable Learning Path stage.

## Drawing Studio — place, run, and observe

1. Open **Drawing Studio** after the attributable Stage 4.1 result. Use
   **Review Comparison** to return to the pinned exact post-line frame or
   **Resume Live Preview** before placement.
2. Confirm the calibrated drawable-region outline is visible. Place the current
   physical sheet over it and choose **Assert Sheet Covers Outline**. The assertion
   cites the current paper instance, contact plane, source, exact frame, and
   camera configuration. It does not change calibration.
3. Select a deterministic built-in program: line, polyline, rectangle, square,
   triangle, regular polygon, circle, ellipse, star, pyramid, or elephant.
   Curves use bounded deterministic tessellation.
4. Click the video to place its center, then set uniform scale and rotation.
   The workspace creates a new immutable placement and content-addressed plan on
   each change. A stroke outside the calibrated region refuses planning; no
   clipping or machine request occurs.
5. Review the projected target on the exact current frame. Before Run, select
   its fixed evidence role: ordinary drawing, training, reserved holdout, or
   evaluation holdout. Do not change the role after seeing the outcome.
6. Press **Run Drawing** only when LIVE controller admission, Motion, settled
   Pen Up, current paper coverage, and the exact plan are all current. The app
   first selects the plan's final point as the same-pose observation location
   and captures the local pre-drawing baseline there.
7. One `RunInterpreter` owner performs Pen-Up travel, lower, each finite segment,
   raise, and the logical-stroke checkpoint sequence. **Stop** is capability-
   bound to that owner. Competing plans are refused without replacing active
   progress.
8. On controller-completed execution, require final MPos at the observation
   location, capture a strictly newer post frame, associate new ink against all
   planned polylines, and retain intended, observed, and residual overlays on
   that exact frame.
9. Append the terminal record even when execution is refused, cancelled,
   ambiguous, possible-ink, or Vision-unclear. Never resend or redraw after a
   terminal result. Only attributable predeclared training records are eligible
   for later fitting; reserved/evaluation holdouts remain sealed evaluation.

**New Sheet — Same Contact Plane** retains the accepted map and validation but
rotates sheet identity and requires a new coverage assertion. **Contact Plane
Changed** invalidates the tip map and returns the dependency chain to contact
calibration. Simulation may exercise catalog placement and exact plan preview;
it cannot run the physical Drawing Studio operation or produce physical run
evidence.

## Dependency and recovery contract

```text
four side aggregates -> center -> center arrival
-> five-cap machine-camera registration
-> five immutable contact observations -> accepted tip-camera registration
-> local line plan + local baseline/reveal pose
-> line execution + newer post-line frame
-> ink observation -> residual -> typed comparison + durable validation record
-> paper coverage + placed DrawingProgram -> immutable execution plan
-> controller execution -> exact-frame planned-ink observation -> run record
```

Redo invalidates named transitive dependents only after a successful replacement
commit. Failure preserves the current accepted value. Record Another Attempt
adds only compatible successful evidence.

Reset From This Step is a separate operator-authored chronological rewind. It
shows the exact suffix and rejects a stale summary. Reset All Learning is always
available from the Learning Path menu. It cancels and settles a current
Learning-owned operation through its typed owner, then clears all accepted
Learning authority for the current source, including the durable accepted
checkpoint, and returns progression to Pen Interaction. Reset itself admits no
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
motion, 2 mm-radius circular marks, isolated line drawing, paper revision,
persistent ink, causal frames, and a real nonzero cap-to-tip truth.

Annotations are exact identity-bound presentation only. They do not modify
canonical pixels or hashes. Stop, ambiguity, cancellation, and shutdown win
before later mutations. Every simulator surface states
`SIMULATED — NOT PHYSICAL EVIDENCE`; no route invokes physical machine actions.
