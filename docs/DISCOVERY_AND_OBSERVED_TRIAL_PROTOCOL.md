# Learning Path Operating Protocol

Status: current operating protocol for Learning Path 1.1 through visible 2.1

This document owns the exact actor, action, evidence, dependency, and recovery
sequence. Durable semantics remain in [Product Contract](PRODUCT_CONTRACT.md).

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
attributable controller evidence, compatible context, and the shared 0.5 mm
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

1. Start Exercise 1.1. Before any pen-position
   question or pen request, **Identify Pen Cap** freezes the current exact frame
   and asks the operator to click the colored cap body, not the tip.
   When a valid LIVE cap appearance already exists, the frozen frame receives
   its own exact requested scene-overlay analysis; geometry from an earlier
   frame is never carried onto it. A first, unlearned appearance still requires
   the click before LIVE overlay recognition can run.
2. Map the presentation click back to the frozen camera frame, submit it through
   the existing projection-bound UI request without another button, and inspect the
   clipped 9 x 9 neighborhood. Reject a stale frame, unsupported pixel format,
   too few chromatic pixels, or a gray, white, or dark median with a concrete
   reason. An accepted sample persists its median RGB color, click point, exact
   frame hash and identity, source, camera configuration, dimensions, pixel
   format, usable/total sample counts, and algorithm revision. There is no
   editable color picker. The learned appearance feeds generic scene analysis
   and every Exercise 1.3 exact-frame inspection, so arbitrary visibly colored caps
   such as blue are supported.
3. Cap identification requires only the current exact frame. The accepted click
   immediately opens the first Up question even when the controller is not yet
   connected or Motion is not enabled. In that blocked state the Up slider and
   **Confirm Pen Up** stays visible but disabled with the exact workbench remedy. Selecting
   a device, **Connect**, and **Enable Motion** remain available in the toolbar;
   completing them enables the existing question without another cap click or
   a Learning Path continuation step.
4. The Up step presents the current Up slider. It is seeded at `S40` in a fresh
   session and otherwise starts from the already-current value. Moving it
   commands the displayed value. Once operational dependencies admit the
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
segmented.

The accepted values become the current Up and Down settings consumed by later
pen operations. They are not required to remain constant across the run.
Repeating Exercise 1.1 at another position creates another attempt
with its actual values and available position/actuation evidence so future
learning can evaluate positional variation. It does not create a separate
calibration exercise or artifact.

If a settled attempt elsewhere exposes **Restart**, select that exercise to use
its recovery. The recovery row does not replace the current exercise selected
by the dependency chain and does not hide Exercise 1.1 or the next physical action.

## 1.2 Measure and Center the Drawing Boundary

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
11. Arrival succeeds only when the final MPos is within 0.5 mm of the derived
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
   require fresh Idle/final MPos within 0.5 mm. Establish a preliminary fresh-
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
8. **Accept Camera Calibration** commits the current
   `MachineCameraRegistration` atomically. **Reject Camera Calibration** commits
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
2. Command and settle Pen Up once before the first travel. Retain that
   batch-scoped Pen-Up authorization through approach, circle-start,
   inter-circle, and reveal travel; do not issue another raise solely to begin
   travel while the authorization remains current. At each canonical position,
   require fresh Idle/final MPos
   within 0.5 mm, capture and retain that circle's exact pre-mark frame and cap
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
   drawing plans projected on the current frame.
3. Read the advisory optical comparison. A compatible bounded reference reports
   integer X/Y shift and background mean absolute difference; incompatible or
   legacy packages report why the comparison is unavailable. No value gates the
   operator choice.
4. Choose exactly **Use Saved Learning** or **Start New Learning**. Use applies
   the exact saved dependency revisions atomically without motion or Pen-pose
   restoration. Start New applies nothing and retains the last complete package.
5. Connecting and probing remain ordinary controller-session work; they do not
   implicitly apply saved Learning. Require no cap capture, click, mark, paper
   replacement, or Learning Path replay for an operator-accepted unchanged setup.

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
2. Retain current tip authority and the attributable Drawing Border validation lineage.
3. Place the new sheet over the calibrated outline and explicitly assert that
   it covers the outline before drawing. This is an operator assertion; paper
   edges are not measured.

After a changed support, stock thickness, contact height, or contact plane:

1. Rotate `PaperInstanceRevision` and `PaperContactPlaneRevision` and invalidate
   current tip authority.
2. Rebuild and accept current Exercise 1.3 authority.
3. Run the complete Exercise 1.4 four-circle calibration on the new plane; review and
   explicitly accept its new tip registration.

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
   Border is not an admission boundary. Current source still expands that
   envelope axis-wise by the unrelated 0.5 mm settlement value. That known
   defect is assigned to `FIX-00`; no run admitted only by the expansion proves
   Boundary-contained planning.
2. **Capture local baseline.** With Pen Up and the controller Idle, capture one
   exact fresh frame and record the current MPos as this validation's reveal pose.
3. **Move to Drawing Border start.** Move Pen Up under one stoppable owner. Completion
   requires fresh Idle/final MPos within 0.5 mm.
4. **Draw Drawing Border.** Confirm the start, lower the pen once, execute all
   four orthogonal edges under the canonical drawing-plan owner, and raise.
5. **Reveal and observe.** Return Pen Up to the recorded reveal MPos, require
   fresh Idle/final MPos within 0.5 mm, capture a post-frame strictly newer
   than the baseline and drawing settlement, and run bounded same-pose
   black/new-ink Vision. While this runs, the UI states that drawing-validation Vision owns
   processing. Retain observed geometry and residual, or a typed rejection.
6. **Compare.** On normal observed-ink success, record the typed intended versus
   observed comparison automatically and display predicted cyan, observed white,
   and residual orange geometry on the exact post-frame. Pin that frame and
   comparison for explicit later review, and append an evaluation-holdout
   drawing-run record.

**Stop** remains available for active motion. Refusal or ambiguity before
contact creates no drawing evidence and stops for recovery. Once stroke
admission or possible ink exists, no path may redraw automatically; recovery
continues only with Pen-Up return and observation of the existing mark. A Vision
rejection or comparison-commit failure stops for review or retry without
drawing again.

Completion remains on Exercise 2.1 with review/reset operations available. It proves one
attributable validation of the current map, not a generally trained adaptive
drawing model. The toolbar reports **Drawing validation complete** and exposes
Drawing Studio as a separate direct workbench, not a
selectable Learning Path stage.

## Drawing Studio — place, run, and observe

1. Open **Drawing Studio** after the attributable Exercise 2.1 result. Use
   **Review Comparison** to return to the pinned exact post-frame or
   **Resume Live Preview** before placement.
2. Confirm the accepted Drawing Boundary outline is visible. Place the current
   physical sheet over it and choose **Assert Sheet Covers Outline**. The assertion
   cites the current paper instance, contact plane, source, exact frame, and
   camera configuration. It does not change calibration.
3. Select a deterministic built-in program: line, polyline, rectangle, square,
   triangle, regular polygon, circle, ellipse, star, pyramid, or elephant.
   Curves use bounded deterministic tessellation.
4. Click the video to place its center, then set uniform scale and rotation.
   The workspace creates a new immutable placement and content-addressed plan on
   each change. A stroke outside the accepted Drawing Boundary refuses planning; no
   clipping or machine request occurs.
5. Review the projected target on the exact current frame. Before Run, select
   its fixed evidence role: ordinary drawing, training, reserved holdout, or
   evaluation holdout. Do not change the role after seeing the outcome.
6. Press **Run Drawing** only when LIVE controller admission, Motion, current
   paper coverage, and the exact plan are all current. The app redundantly
   commands and settles Pen Up before observation-position travel; prior Pen
   command knowledge is not trusted. It then selects the plan's final point as
   the same-pose observation location and captures the local pre-drawing baseline there.
7. One `RunInterpreter` owner redundantly normalizes Pen Up again, performs plan travel, lower, each finite segment,
   raise, and the logical-stroke checkpoint sequence. **Stop** is capability-
   bound to that owner. Competing plans are refused without replacing active
   progress.
8. On controller-completed execution, require final MPos at the observation
   location, capture a strictly newer post frame, associate new ink against all
   planned polylines, and retain intended, observed, and residual overlays on
   that exact frame. The target contract makes projection outside the current
   tip-registration applicability diagnostic-only and the camera/ink result
   non-attributable unless a newer validated applicability revision covers it.
   Current source at DOC-01 violates that contract: it can reuse extrapolated
   projection for run geometry and classify a later Vision success attributable.
   Until `FIX-01` lands, any run using outside-applicability projection is known
   invalid as attributable evidence and is excluded from later fitting even if
   the current application labels it attributable.
9. Append the terminal record even when execution is refused, cancelled,
   ambiguous, possible-ink, or Vision-unclear. Never resend or redraw after a
   terminal result. Only attributable predeclared training records are eligible
   for later fitting; reserved/evaluation holdouts remain sealed evaluation.

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

Redo invalidates named transitive dependents only after a successful replacement
commit. Failure preserves the current accepted value. Record Another Attempt
adds only compatible successful evidence.

Reset From This Step is a separate operator-authored chronological rewind. It
shows the exact suffix and rejects a stale summary. Reset All Learning is always
available from the Learning Path menu. It cancels and settles a current
Learning-owned operation through its typed owner, then clears all accepted
Learning authority for the current source, including the durable accepted
checkpoint, and returns progression to Exercise 1.1. Reset itself admits no
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
