# Discovery and Observed-Trial Protocol

Status: current operating protocol for Learning Path 3.1 through 4.6

This document owns the exact actor, action, evidence, dependency, and recovery
sequence. Durable semantics remain in [Product Contract](PRODUCT_CONTRACT.md).

## Common actor contract

Every interactive step presents one numbered title, a short Plotter/You
script, an optional question, and typed answer controls. One exact operation
owner exists when controller or simulator state may change, and accepted results
cite exact causal subjects. Detailed activity, subsystem facts, evidence, and
failure history belong to Diagnostics rather than the exercise.

Announcements are advisory output. Buttons own answers, Start, Cancel, Stop,
Restart, Redo, re-click, and acceptance. Commit/advance is green, interruption
and invalidation red, same-stage value input blue, and view utility gray.

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

During active Boundary motion, Stop & Accept, Stop, and Cancel carry the same
exact owner capability and race through one first-winner latch. They share a
mechanical Jog Cancel primitive but never a semantic result. Stop & Accept alone
may commit after clean attributable settlement. Stop records `.stopped` and
exposes Restart only after clean settlement. Cancel records `.cancelled` and
abandons the attempt. Escape binds Stop, never Stop & Accept. Sticky ambiguity
suppresses new physical motion and acceptance.

Every production comparison of requested pose and settled MPos uses fresh
attributable controller evidence, compatible context, and the shared 0.05 mm
Euclidean policy.

Presentation zoom, pan, and fitted bounds are view-only. Learning visibility,
step changes, frozen frames, sparse-mark selection, and inspector changes never
alter operator geometry or a locked ROI. Unlocked rendering does not constrain
backend analysis. Lock atomically captures the visible camera-pixel rectangle;
Unlock clears that ROI without moving the view. Camera source/configuration
replacement resets geometry and lock only.

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

## 3.2 Set X, Y Boundaries

1. The operator selects any first X or Y direction. Selection is inert.
2. **Start** admits one Boundary owner and one bounded controller request.
3. **Stop & Accept**, **Stop**, and **Cancel** remain bound to that exact owner.
4. The first accepted action emits one Jog Cancel; stale/repeated actions are inert.
5. The original owner settles through fresh attributable Idle and final MPos.
6. Stop & Accept alone atomically commits typed direction, controller
   session/revision, final MPos, side attempt, and aggregate. Stop retains only
   operational audit and exposes Restart after clean settlement. Cancel abandons
   the attempt after clean settlement. Ambiguity commits nothing.
8. The forced opposite direction is shown as required noninteractive content.
9. After the pair, the operator chooses either sign on the remaining axis and
   records its forced opposite.
10. After all four sides, **Move to Estimated Center** admits one stoppable
    Pen-Up move.
11. Arrival succeeds only when the final MPos is within 0.05 mm of the derived
    center.

Boundary has no Vision adviser. Natural completion of the bounded request is
not side evidence: it ends Needs Attention and does not renew or resend.
Operator termination, limit, alarm, disconnect, shutdown, or ambiguity also
never resends. A longer request is prohibited until signed remaining travel and
attended stop latency/overshoot are proven for every direction.
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
   nothing.

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

### Ordered physical sequence

Use `C`, `X−`, `Y+`, `X+`, `Y−`. Every sample is the center of one 2 mm-radius
circular mark.

For each mark:

1. Press **Create Next 2 mm Circle**.
2. Move Pen Up to the intended position under the existing bounded, stoppable
   owner and consistent final approach.
3. Require fresh Idle/final MPos within 0.05 mm.
4. Capture an exact pre-mark frame and current cap anchor. Reject the operation
   if the accepted cap map misses that anchor by more than its declared policy.
5. Retain the pre-mark frame as local evidence.
6. Verify the full 2 mm-radius circle lies within the learned Boundary's 10 mm
   safety inset, then move Pen Up to the circle's +X start point and settle.
7. Before any LIVE Pen Down, reserve the complete circle geometry and current
   paper identity in the single checksummed surface-exposure store. Stop without
   contact if the save fails or the store was rejected. SIMULATED runs reserve
   the same geometry as explicitly nonphysical in-memory state only.
8. Command the complete lower operation with the current Down value accepted in
   Pen Interaction (`S760` initially), controller acknowledgement, configured
   settlement and acknowledgement, and a settled Down outcome. Record the
   actual value consumed by this mark.
9. Draw one closed 16-chord circle under typed drawing ownership. Cap drawing
   feed at 100 mm/min or the lower controller-reported axis ceiling. Each chord
   is finite and stoppable; the 16-chord radial approximation error is about
   0.038 mm, below the shared 0.05 mm position policy. Require settled final MPos
   after every chord.
10. Command Pen Up once using the current Up value accepted in Pen Interaction
   (`S40` initially) and require an unambiguous settled Up outcome. If any chord
   or Pen outcome after possible contact is stopped or ambiguous,
   retain the complete reserved circle geometry as possible ink on the current
   paper and stop. Never redraw it automatically.
11. Move Pen Up to the learned safe X+ limit and toward machine Y=0, clamping Y
    to the Boundary's 10 mm safety inset when zero is outside that safe interval.
12. Require reveal-pose Idle/final MPos within 0.05 mm.
13. Capture one strictly newer exact post-reveal frame and revalidate the cap
    map at that pose.
14. Freeze that frame without changing the operator's zoom, pan, or locked ROI,
    hide the expected tip point, and ask
    **Click the center of the new black circle**.
15. Convert the zoomed/letterboxed view click back to exact camera pixels. Bind
    it to frame ID, SHA-256, source, capture session, semantic optical identity,
    dimensions, and presentation-transform revision.
16. Show the asserted point, 1.5 px per-axis pointing uncertainty, the expected
    point from the current tip-calibration candidate if one exists, and residual.
17. **Re-click This Exact Frame** clears only the point and reuses the same
    frame. It performs no motion and creates no ink.
18. **Accept Mark Center** atomically commits one immutable
    `ToolContactObservation` revision.

The click is role `assertedCenter`. The commanded circle geometry is retained,
but the click is still a human assertion rather than automatic shape evidence.
Controller completion does not prove physical contact or ink; attended
observation owns those claims.

### Model selection and final acceptance

1. `C`, `X−`, and `Y+` are the fit set. `X+` and `Y−` are sealed holdouts.
2. Fit a constant camera-pixel correction on the accepted cap map.
3. If both holdouts pass, select that smallest model.
4. If and only if both fail coherently, fit a direct affine machine-to-tip map
   from the three fit samples and test it on both holdouts.
5. A lone failing holdout blocks acceptance and does not justify affine
   escalation.
6. Both holdouts must pass the selected form.
7. Refit the selected form on all five observations.
8. Present model form, sealed holdout evidence, all-five residuals, uncertainty,
   applicability rectangle, semantic identities, and consumed observation
   revisions.
9. **Accept Tip Calibration** atomically commits `TipCameraRegistration` and a
   new generation of the single Learning-authority manifest, then advances to
   Stage 4.
10. **Reject Tip Calibration** retains immutable observation history and causes
    no motion or redraw.

### Quarantined checkpoint recovery

Loading never restores authority automatically.

For an unchanged paper plane and matching semantic machine/tool/optical
identities:

1. Rebuild and accept current Stage 3.3 machine-to-cap authority.
2. Choose **Revalidate Saved Tip Calibration**.
3. Require a settled Pen-Up controller position and capture one fresh exact cap
   frame.
4. Revalidate the current cap map and semantic identities.
5. Perform no contact mark.
6. Derive one new accepted tip revision directly from the checkpoint's complete
   evidence summary and the fresh revalidation evidence. Do not fabricate
   current raw-observation graph nodes without matching current payloads.

After explicit paper replacement:

1. Retain the old checkpoint in quarantine and rotate the paper-plane identity.
2. Rebuild and accept current Stage 3.3 authority.
3. Start Stage 3.4 and create one new 2 mm-radius center circle using the full
   settle/draw/reveal/frozen-click sequence above.
4. Require the new click to agree with the quarantined tip projection within the
   declared eight-pixel policy.
5. Derive a new accepted tip revision that consumes the original five evidence
   identities plus the new contact-plane observation.

Any mismatch or ambiguous contact leaves authority unavailable. It never falls
back to automatic redraw or silent checkpoint promotion.

## 4. Observed Drawing Trial

Stage 4 requires the exact current accepted `TipCameraRegistration` revision.
Every request/result cites that revision.

### 4.1 Choose Isolated Line Plan

Choose a signed axis direction. The app selects a start inside the tip model's
applicability rectangle and constructs one 5 mm local line that clears every
retained current-paper circle and prior isolated-line exposure by the declared
ink-clearance margin. If the domain is too crowded, planning stops and requests
a larger clean calibration area rather than crossing old ink. It projects start
and end directly through the current tip registration.

### 4.2 Capture Local Pre-Line Baseline

With Pen Up and the controller Idle, atomically capture one exact fresh frame
and same-time attributable reveal MPos/context. This subject consumes the
immutable line plan and exact tip registration and belongs only to the group.

### 4.3 Move to Line Start

Move Pen Up under one stoppable owner to the recorded start. Completion requires
fresh Idle/final MPos within 0.05 mm and creates a line-start-arrival subject even
for zero travel. Stop, refusal, or ambiguity creates no arrival authority.

### 4.4 Draw Isolated Line

Confirm current MPos at the recorded start. Before LIVE Pen Down, reserve and
atomically persist the complete line geometry and current paper identity in the
same surface-exposure ledger as calibration circles. A rejected load or failed
save blocks contact. Lower the pen, execute one typed 5 mm stroke under one
drawing owner, and raise. A stopped, rejected, ambiguous, or interrupted result
retains that reservation and never causes an automatic successor or redraw.

### 4.5 Reveal and Observe New Ink

1. Return Pen Up to the trial's recorded reveal MPos under one stoppable owner.
2. Require fresh Idle/final MPos within 0.05 mm.
3. Capture a post-line frame strictly newer than both the local baseline and
   final drawing settlement.
4. Project the intended line through the exact cited tip registration and form
   bounded local observation support.
5. Compare the same-pose baseline/post pair for black/new ink using bounded
   fixed-camera alignment.
6. Atomically retain return settlement, newer exact frame, observation region,
   observed line geometry, and required residual as one post-line-observation
   subject, or retain a typed rejection. No partial current nodes are created and
   a rejection requests no redraw.

### 4.6 Compare Intended and Observed Geometry

Display intended and observed geometry plus residuals only when the cited
post-line observation remains current. Record one typed operator assessment.
An attributable line may be future candidate evidence; this action cannot
promote a model.

Completion remains on 4.6 with recovery operations available. There is no
selectable Adaptive Drawing stage in the current application.

## Dependency and recovery contract

```text
pen-cap appearance -> Pen Interaction
four side aggregates -> center/local frame -> center arrival
pen-cap appearance + center arrival -> five-cap machine-camera registration
-> five immutable contact observations -> accepted tip-camera registration
-> line plan -> local baseline/reveal context -> line-start arrival
-> line execution -> atomic post-line observation -> typed comparison
```

Redo invalidates named transitive dependents only after a successful replacement
commit. Failure preserves the current accepted value. Record Another Attempt
adds only compatible successful evidence.

Invalidate This Step roots only that leaf's current subject(s); Invalidate This
Branch roots every descendant-owned subject. The graph removes exact transitive
consumers. The preview binds source, current subject/revision and payload
versions, accepted sequence, and the exact manifest revision only when durable
machine/tip authority is removed, rejecting stale state. Retained sparse
exposure prevents same-paper Redo. Once a Stage 4 group has any line exposure,
invalidating or repeating 4.1–4.4 abandons it and returns to a fresh 4.1 plan;
it never captures a new baseline against exposed geometry. Neither action moves,
changes pen state, cancels, resends, redraws, clears safety exposure, or claims
to erase ink. Redo remains a distinct successful atomic replacement.

Semantic optical changes invalidate optical dependents but do not invalidate
compatible machine-space Boundary aggregates. Presentation-only transform
changes invalidate nothing. Paper-plane changes quarantine contact authority;
raw observations remain history.

## Causal simulator contract

SIMULATED traverses the same public actions and dependency graph. It owns a
simulated session, Motion authorization, MPos, pen pose, bounded Boundary
motion, 2 mm-radius circular marks, isolated line drawing, paper revision,
persistent ink, causal frames, and a real nonzero cap-to-tip truth.

Annotations are exact identity-bound presentation only. They do not modify
canonical pixels or hashes. Stop, ambiguity, cancellation, and shutdown win
before later mutations. The primary surface uses the concise `SIMULATED` badge;
Diagnostics and simulator evidence use the full
`SIMULATED — NOT PHYSICAL EVIDENCE` qualification. No route invokes physical
machine actions.
