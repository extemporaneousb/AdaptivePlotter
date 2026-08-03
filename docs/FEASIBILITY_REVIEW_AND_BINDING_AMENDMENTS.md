# Feasibility Review and Binding Amendments

Status: binding handoff supplement  
Scope: feasibility, execution determinism, and new-repository adaptation only

## Precedence

This document records the review of the architecture and sequential rebuild
plan. Where this document resolves an ambiguity or names a narrower contract,
it controls implementation. It does not replace the selected architecture,
actor boundaries, causal model, execution frontiers, checkpoint strategy, or
evidence requirements.

## Feasibility verdict

The selected architecture is implementable as one native Swift 6 macOS
application. The software boundaries are not the primary feasibility risk.

For the initial vertical slice, take as an explicit product assumption that a
sufficiently large isolated green pen mark can be detected and fitted against
clean white paper. No separate disposable ink-recognition architecture or
pre-repository experiment is required.

The unresolved physical feasibility question is narrower:

> Can the complete pen armature, including the pen, holder, linkage, and actuator
> servo assembly, be moved through a bounded safe pen-up path to a camera pose
> where it does not occlude the observation region?

Phase 4 must answer that question before the first physical training stroke.
Failure to establish viewability and a safe clear path blocks that physical
action and requires tool/camera geometry redesign. It does not block unrelated
software implementation, simulation, replay, or testing, and it is not
permission to weaken freshness, clearance, or evidence requirements.

## Binding Phase 4 amendment: armature viewability

Phase 4 must add a narrow, versioned geometric clearance contract. Do not build
a general viewability framework or a 3D digital twin.

Initial values:

```text
ToolOcclusionEnvelope
ClearancePose
ClearancePath
ClearanceEvidence
```

`ToolOcclusionEnvelope` describes the conservative camera projection of the
complete armature for a named camera configuration, tool configuration,
carriage/cap pose, and pen/servo state. It is measurement geometry, not part of
`AdaptiveDrawingModel` and not evidence of successful ink.

Conceptually:

```text
ToolOcclusionEnvelope(
    cameraConfiguration,
    toolConfiguration,
    carriagePose,
    penOrServoState
) -> conservative polygon in CameraPixelSpace
```

The observation region remains canonical in `FieldSpace` and is projected into
camera space through the current `FieldRegistration`. A candidate clear pose is
viewable only when:

```text
inflate(toolOcclusionEnvelope, poseUncertainty + fixedMargin)
    intersects projectedObservationRegion
    == false
```

Model occlusion in camera coordinates because the armature is three-dimensional
and elevated above the paper. Do not apply the paper-plane homography to the
armature as if it were coplanar with the drawing surface. Begin with an empirical
conservative polygon or union of observed silhouettes. Promote a more complex,
position-dependent model only if held-out viewability trials show the simple
envelope is inadequate.

For the first ink slice, one fixed reserved `ObservationRegion`, one verified
`ClearancePose`, and one bounded `ClearancePath` are sufficient. General
field-wide clearance planning is deferred until a delivered capability requires
it.

Phase 4 acceptance must additionally prove:

- a known sufficiently large green reference mark is visible when the armature
  is absent from its observation region;
- the complete armature envelope is measured from exact retained frames at the
  poses used to build it;
- the chosen clear pose keeps the inflated envelope disjoint from the projected
  observation region;
- a bounded pen-up path reaches that pose without leaving fixed machine safety;
- a fresh post-move frame independently confirms the expected region is not
  occluded;
- camera, tool, pen/servo state, registration, configuration, frame, algorithm,
  uncertainty, margin, path, and pose identities are recorded;
- a camera/tool/configuration change invalidates the clearance evidence.

`VisionWorker` measures exact-frame occlusion geometry. Pure geometry selects or
validates a clearance pose/path. `RunInterpreter` owns the trial transition and
authority decision. No new actor, manager, repository, or service is justified.

## Binding Phase 5 amendment: bootstrap trial order

The first training trial executes sequentially:

```text
verify clean reserved region
  -> acquire and retain fresh stable baseline
  -> travel to the known start
  -> draw one isolated green stroke under bounded training authority
  -> request pen lift and reconcile controller state
  -> execute the Phase-4-proven clearance path
  -> verify the inflated armature envelope is outside the ROI
  -> acquire and retain a demonstrably newer stable frame
  -> detect and fit the isolated mark
  -> record intended, commanded, predicted, observed, and corresponded geometry
  -> record goal residual and model innovation
  -> accept or reject the measurement independently of drawing success
  -> retain the prior model unless later evidence supports a candidate
```

The initial observation region and matching search bounds must be deliberately
large enough to contain bootstrap error. Large residual magnitude alone does not
make an observation invalid.

Keep these facts separate:

- **Evidence accepted:** the mark is fresh, visible, uniquely associated, and
  measured with sufficient coverage, topology, and covariance.
- **Drawing succeeded:** the accepted observation meets the declared goal-error
  tolerance.
- **Model candidate accepted:** sufficient independent evidence shows a bounded,
  identifiable candidate improves held-out prediction without violating
  applicability, uncertainty, continuity, or inversion gates.

A large but unambiguous first residual may be accepted as training evidence
while failing drawing tolerance and producing no immediate model promotion.
Rejecting it solely for its magnitude would discard the evidence needed to
initialize correction.

## Bootstrap execution authority

The architecture's `ExecutionAuthority.operation` must become concrete before
the first pen-down trial. At minimum distinguish:

```text
passiveInterrogation
boundedPenUpTrial
isolatedTrainingProbe
generalDrawing
```

`isolatedTrainingProbe` is not general drawing authority. It requires:

- explicit independent motion and pen arms;
- current machine, safety, camera, registration, tool, and pen-profile evidence;
- one reserved uncontaminated observation region;
- a bounded path, feed, distance, and command horizon;
- current Phase-4 clearance evidence;
- durable command preparation and complete provenance;
- no automatic redraw.

Cap motion, preview, controller `ok`, controller `Idle`, or commanded pen state
may not authorize `generalDrawing`.

## Canonical execution vocabulary

The architecture's names control. Use `ExecutionInstruction`, not a parallel
`PlanInstruction` synonym. The closed initial vocabulary is:

```text
liftPen
travel
draw
clearObservationRegion
awaitControllerIdle
acquireStableFrame
inspect
checkpoint
```

Use `CheckpointDecision` for the interpreter's typed domain decision. If a
`CheckpointResolution` value exists, it is the durable atomic record containing
the decision, evidence disposition, frontier changes, selected state/model, and
next planning basis. It is not a second decision system.

## Registration and canonical identity

Physical `FieldRegistration` acceptance requires independent reference geometry
and redundant held-out points. A four-point homography evaluated only on the
same four points that define it is not validation.

Before hashing programs, models, plans, commands, or checkpoint records, define
a versioned canonical encoding, including key/order rules, identifier encoding,
floating-point normalization, non-finite-value rejection, and byte-level golden
fixtures. Do not assume ordinary `Codable` output is a stable content-addressing
format across builds.

## New-repository adaptation

The sequential plan was written when the new product was expected to coexist
temporarily inside the legacy repository. This directory instead becomes a
brand-new repository.

Therefore:

- the repository root is the new product boundary; do not create a nested
  `macos/AdaptivePlotter/` merely to mirror the legacy layout;
- Phase 1 inspects `/Users/bullard/Projects/Plotter` read-only and imports only
  explicitly curated small fixtures with hashes and provenance;
- the new repository never contains legacy live code, so Phase 8 performs a
  proof-based product-readiness declaration rather than deleting legacy files
  locally;
- retirement, archival, or deletion in the old Plotter repository is a separate
  user-authorized task and must not be inferred from work in this repository;
- legacy `make check`, Python packaging, launch scripts, routes, and tests are
  not copied. Establish native repository validation from the first phase;
- no compatibility bridge is needed because there is no in-place migration.

## Local-only development contract

AdaptivePlotter targets this operator Mac and this attached plotter only. The
installed Apple Command Line Tools, Swift 6 compiler, macOS SDK, and SwiftPM are
the supported development toolchain. Do not require release tooling, a
developer identity, notarization, sandbox policy work, a cross-Mac support
matrix, or CI coverage. Create a stable ad-hoc local `.app` wrapper only if a
macOS API such as camera permission handling needs bundle identity; otherwise
the SwiftPM executable is a valid development artifact.

Development is capability-driven rather than phase-blocked:

- missing controller or camera hardware never blocks pure implementation,
  simulation, replay, UI projection, documentation, or landing;
- run the native passive probe against the actual controller before enabling
  any powered motion action;
- verify local camera access and retain exact frames before camera evidence can
  authorize a physical action;
- verify each bounded motion or pen dependency immediately before that class of
  physical action becomes reachable;
- label simulated, historical, and physically unverified results honestly.

Toolchain or OS work becomes required only after a concrete local build or API
failure demonstrates it. Do not provision speculative infrastructure.

## Iteration rule

The phases describe dependency order for physical authority, not a global
development queue. When physical evidence invalidates a prior assumption:

1. disable only the affected physical action and any authority derived from it;
2. update the owning architecture or capability contract;
3. correct the earliest affected implementation;
4. rerun the directly affected tests, simulations, and physical evidence;
5. retain the failed experiment and decision in the evidence history.

Continue unrelated work. Do not propagate a known mismatch into physical
authority merely to preserve schedule or phase numbering.

## What remains unchanged

Do not revise these decisions without new contradictory physical evidence:

- one native Swift application process;
- four initial actors and queue-confined `CameraCapture`;
- `DrawingProgram` -> finite checkpointed `ExecutionPlan` -> exact controller
  command batches;
- commanded, controller-completed, ink-verified, and ambiguous execution facts;
- one causal forward model with numerical inverse and forward check;
- separate fast run state and immutable slow model versions;
- no model switch during a pen-down stroke;
- no command buffering beyond an inspection checkpoint;
- evidence acceptance separate from model promotion;
- UI presentation separate from runtime authority;
- durable semantic ledger, recorded-decision replay, and non-authoritative
  algorithm re-evaluation;
- no live Python, localhost bridge, DTO mirror, compatibility lane, digital
  twin, workflow framework, or speculative plugin architecture.
