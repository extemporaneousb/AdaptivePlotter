# Discovery and Observed-Trial Protocol

Status: current operating protocol for Learning Path 3.2 through 4.6

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
the operator must inspect the physical cause before choosing **Clear Alarm**.
That explicit action sends one alarm-lock override and immediately runs a fresh
complete passive probe. It does not home, recover position, clear limit inputs,
or enable Motion. No unlock is sent during Connect, no failed clear is retried,
and **Enable Motion** remains a separate operator action after a clean probe.

Cancel abandons a settled attempt. Stop settles an admitted stoppable owner.
They may share a mechanical Jog Cancel primitive but never share a successful
semantic disposition. Sticky ambiguity suppresses new physical motion.

Every production comparison of requested pose and settled MPos uses fresh
attributable controller evidence, compatible context, and the shared 0.05 mm
Euclidean policy.

Presentation zoom, pan, and fitted bounds are available after 3.2. They are
view-only. Exact camera-pixel evidence and calibration authority do not change
when the presentation transform changes.

## 3.2 Paired Boundary Discovery and Centering

1. The operator selects any first X or Y direction. Selection is inert.
2. **Start** admits one operator-stopped Boundary owner.
3. The controller begins with one 20 mm segment. After each unambiguous
   Idle/MPos, a strictly newer advisory frame may choose a 50, 20, 10, 5, or
   2 mm renewal while retaining direction and controller-derived feed.
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

The advisory frame cannot identify or veto a side. Missing, stale,
camera-incompatible, low-confidence, or unusable advice selects a conservative
renewal and cannot alter direction, feed authority, Stop, or side acceptance.

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
3. At every position, move Pen Up under the existing stoppable owner, require
   fresh Idle/final MPos within 0.05 mm, capture one exact frame, and record the
   visible cap bottom-center with estimator provenance.
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
7. Command the complete fixed local lower operation: `M3 S760`, controller
   acknowledgement, `G4 P0.3`, controller acknowledgement, and a settled Down
   outcome. There is no independent pressure command or permitted overdrive.
8. Draw one closed 16-chord circle under typed drawing ownership. Cap drawing
   feed at 100 mm/min or the lower controller-reported axis ceiling. Each chord
   is finite and stoppable; the 16-chord radial approximation error is about
   0.038 mm, below the shared 0.05 mm position policy. Require settled final MPos
   after every chord.
9. Command Pen Up once and require an unambiguous settled Up outcome. If any
   chord or Pen outcome after possible contact is stopped or ambiguous,
   blacklist this circle center/radius on the current paper and stop. Never
   redraw it automatically.
10. Move Pen Up to the learned safe X+ limit and toward machine Y=0, clamping Y
    to the Boundary's 10 mm safety inset when zero is outside that safe interval.
11. Require reveal-pose Idle/final MPos within 0.05 mm.
12. Capture one strictly newer exact post-reveal frame and revalidate the cap
    map at that pose.
13. Freeze that frame. Open a one-third-frame presentation-only focus around
    the pre-mark cap anchor, suppress every predicted tip overlay, and ask
    **Click the center of the new black circle**.
14. Convert the zoomed/letterboxed view click back to exact camera pixels. Bind
    it to frame ID, SHA-256, source, capture session, semantic optical identity,
    dimensions, and presentation-transform revision.
15. Show the asserted point, 1.5 px per-axis pointing uncertainty, current
    prediction if one exists, and residual.
16. **Re-click This Exact Frame** clears only the point and reuses the same
    frame. It performs no motion and creates no ink.
17. **Accept Mark Center** atomically commits one immutable
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
9. **Accept Tip Calibration** atomically commits `TipCameraRegistration`, saves
   the separate quarantined tip checkpoint, and advances to Stage 4.
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
6. Rebuild the five immutable observation graph nodes under the current machine-
   camera revision and derive a new accepted tip revision with the fresh
   revalidation evidence.

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
persistent 2 mm-radius calibration circle by at least 0.25 mm. If the domain is
too crowded, planning stops and requests a larger clean calibration area rather
than crossing old ink. It projects start
and end directly through the current tip registration.

### 4.2 Capture Local Pre-Line Baseline

With Pen Up and the controller Idle, capture one exact fresh frame and record
the current MPos as this trial's local reveal pose. This baseline belongs only
to the trial.

### 4.3 Move to Line Start

Move Pen Up under one stoppable owner to the recorded start. Completion requires
fresh Idle/final MPos within 0.05 mm. Stop, refusal, or ambiguity creates no
drawing evidence.

### 4.4 Draw Isolated Line

Confirm current MPos at the recorded start. Lower the pen, execute one typed
5 mm stroke under one drawing owner, and raise. A stopped or ambiguous result
never causes an automatic successor or redraw.

### 4.5 Reveal and Observe New Ink

1. Return Pen Up to the trial's recorded reveal MPos under one stoppable owner.
2. Require fresh Idle/final MPos within 0.05 mm.
3. Capture a post-line frame strictly newer than both the local baseline and
   final drawing settlement.
4. Project the intended line through the exact cited tip registration and form
   bounded local observation support.
5. Compare the same-pose baseline/post pair for black/new ink using bounded
   fixed-camera alignment.
6. Retain observed line geometry and residual, or a typed rejection. A rejection
   requests no redraw.

### 4.6 Compare Intended and Observed Geometry

Display intended, predicted, and observed geometry plus residuals only when the
cited tip registration remains current. Record one typed operator assessment.
An attributable line may be future candidate evidence; this action cannot
promote a model.

## Dependency and recovery contract

```text
four side aggregates -> center -> center arrival
-> five-cap machine-camera registration
-> five immutable contact observations -> accepted tip-camera registration
-> local line plan + local baseline/reveal pose
-> line execution + newer post-line frame
-> ink observation -> residual -> typed comparison
```

Redo invalidates named transitive dependents only after a successful replacement
commit. Failure preserves the current accepted value. Record Another Attempt
adds only compatible successful evidence.

Reset From This Step is a separate operator-authored chronological rewind. It
shows the exact suffix and rejects a stale summary. Reset All Learning anchors
the same operation at Pen Interaction. Neither action moves, changes pen state,
resends, redraws, or claims to erase ink.

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
