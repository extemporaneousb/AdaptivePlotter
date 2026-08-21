# AdaptivePlotter Roadmap

Status: unfinished work only; never completion evidence

Current implementation and verification are recorded in
[Current Evidence](CURRENT_EVIDENCE.md). Product authority is
[Product Contract](PRODUCT_CONTRACT.md).

## 1. Attended sparse-calibration validation

Run the complete [Attended Hardware Runbook](ATTENDED_HARDWARE_RUNBOOK.md) on a
disposable sheet. Validate actual controller settlement, five cap captures,
one center and four Boundary-corner 2 mm-radius circular marks with Pen Up
between them, one final center Pen-Up reveal, the calibrated drawable-region
bounding overlay, one shared frozen exact frame, five
arbitrary-order human center clicks, deterministic global association, the
all-five affine-first commit on click five, one predicted-line preview before
motion, one complete one-Go Stage 4.1 observed line, retained exact comparison
review, new-sheet coverage confirmation, and one simple physical Drawing Studio
plan with post-run planned-versus-observed review. Record failures without
redrawing ambiguous locations.

This is the highest-priority gap. Automated and simulated evidence cannot close
it. In particular, C920 reliability for click-learned arbitrary cap colors,
cap-body click usability and sampling tolerance, the usefulness of the
cap-inferred armature envelope, preview fluidity, and attended calibration remain
unproven until this run is explicitly authorized and performed.

## 2. Operator-declared semantic revision controls

Add deliberate attended controls for tool/holder/contact-profile replacement,
camera mount/reframing changes, and known machine-geometry revisions. Each
control must rotate the correct semantic identity, show the affected checkpoint
and graph suffix, preserve raw history, and require explicit invalidation or
revalidation. It must never infer physical sameness from app restart alone.

## 3. Durable exact-frame archive

Current exact frames retain hashes and metadata but no content-addressed pixel
locator. Add an opt-in bounded archive before claiming reprocessing across app
sessions. Define retention, privacy, disk limits, corruption checks, and atomic
association with the evidence graph.

## 4.2 Coverage Line Trials

The typed run record, fixed evidence roles, multi-stroke execution owner,
generic planned-ink observer, and append-only archive now exist. Add the active
selection policy and bounded training batch that choose clean lines across the accepted map's
position range and all four signed axis directions. One operator **Go** starts
the batch; software owns normal trial-to-trial progression and **Stop** remains
available throughout. Each line keeps its own baseline/reveal frames, exact tip
revision, controller and paper identities, request, execution, ink, and
residual. Possible ink, ambiguous motion, or unclear Vision stops the batch
without redrawing or silently counting the trial.

Reserve some coverage locations before fitting. They are holdouts and cannot be
promoted into training evidence after results are known.

## 4.3 Direction and Residual Model Training

Compare the current affine map against bounded candidate corrections for
direction-dependent backlash and spatial residual. Fit only attributable
training trials. Preserve the accepted affine map as the prior and rollback
authority. Report applicability, uncertainty, training residuals, and reserved
holdout residuals separately. A candidate may advance only when it improves the
predeclared held-out metric without regressing any declared region or direction;
software failure or inconclusive evidence leaves the prior current.

## 4.4 Stroke and Shape Holdouts

The deterministic catalog and planner now provide lines, polylines, corners,
polygons, tessellated curves, stars, a pyramid, and an elephant as immutable
programs. After coverage-line evidence is reliable, define predeclared corner,
reversal, curve, and speed-sensitive holdout batches and their metrics. Keep
request geometry, executed controller evidence, and observed pixels distinct.
These are evaluation holdouts, not more fitting data after inspection. Do not
introduce automatic redraw after an ambiguous stroke.

## 4.5 Typed Drawing Readiness

The scoped `DrawingReadinessAssessment` schema and truthful toolbar states now
exist, but no active-learning coordinator currently emits a ready assessment.
**Ready** must cite one current model revision, semantic
machine/tool/paper/camera identities, applicability bounds, the complete
coverage set, untouched holdouts, candidate-versus-prior comparison, and shape
holdouts. It may be emitted only when every predeclared requirement passes and
no counted trial is refused, ambiguous, possible-ink, or Vision-unclear.

Until 4.2–4.5 pass attended physical evaluation, the truthful states are **Map
ready** after Stage 3.4 and **Interactive learning complete · one validation**
after Stage 4.1—not **Trained**. Direct Drawing Studio execution may use that
validated current map and records every outcome, but **Adaptive drawing ready**
may appear only from a current scoped Ready assessment.

## 5. Drift and lifecycle studies

Measure within-session and cross-session sensitivity to focus, mount, tool,
paper, temperature, controller-coordinate, and capture restarts. Use those
results to characterize drift, revalidation cadence, and diagnostic residual
distributions. They must not create Stage 3.4 residual, confidence, or
model-quality gates.

## 6. Operational hardening

- export a redacted evidence bundle with schema/version validation;
- add explicit storage inspection and checkpoint deletion UI;
- exercise upgrade/migration and corrupted-checkpoint refusal;
- expand accessibility and keyboard operation for exact-frame clicking;
- keep signed-bundle, singleton, camera, and serial ownership tests current.

## 7. Adaptive model promotion and face programs

Direct placed-vector drawing is implemented outside the Learning Path. The next
adaptive step is not another execution path: implement the 4.2 selector, 4.3
candidate-versus-prior fitter, sealed physical holdouts, and readiness emission
on the existing program/plan/evidence types. Do not restore the deleted
speculative online dataset, policy/reward scaffolding, model-mismatch overlay,
or dormant navigation route as a compatibility surface.

The historical face renderer should return only as another deterministic
`DrawingProgram` producer consumed by the existing placement, planning, preview,
execution, observation, and evidence flow. It must not own calibration,
controller commands, paper state, plan execution, or model promotion.
