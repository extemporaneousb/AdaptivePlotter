# AdaptivePlotter Roadmap

Status: unfinished work only; never completion evidence

Current implementation and verification are recorded in
[Current Evidence](CURRENT_EVIDENCE.md). Product authority is
[Product Contract](PRODUCT_CONTRACT.md).

## 1. Attended sparse-calibration validation

Run the complete [Attended Hardware Runbook](ATTENDED_HARDWARE_RUNBOOK.md) on a
disposable sheet. Validate actual controller settlement, five cap captures,
five 2 mm-radius circular marks with Pen Up between them, one final
X+/machine-Y-zero-biased Pen-Up reveal, one shared frozen exact frame, five
arbitrary-order human center clicks, deterministic global association, the
all-five affine-first commit on click five, one predicted-line preview before
motion, and one complete one-Go Stage 4.1 observed line. Record failures without
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

Add a bounded training batch that selects clean lines across the accepted map's
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

After line evidence is reliable, add corners, polylines, repeated reversals, and
speed-sensitive trials. Keep request geometry, executed controller evidence,
and observed pixels distinct. These are evaluation holdouts, not more fitting
data after inspection. Do not introduce automatic redraw after an ambiguous
stroke.

## 4.5 Typed Drawing Readiness

Introduce a scoped `DrawingReadinessAssessment` rather than a generic
"trained" boolean. **Ready** must cite one current model revision, semantic
machine/tool/paper/camera identities, applicability bounds, the complete
coverage set, untouched holdouts, candidate-versus-prior comparison, and shape
holdouts. It may be emitted only when every predeclared requirement passes and
no counted trial is refused, ambiguous, possible-ink, or Vision-unclear.

Until 4.2–4.5 exist and pass attended physical evaluation, the truthful states
are **Map ready** after Stage 3.4 and **One attributable validation complete**
after Stage 4.1—not **Trained**. Adaptive Drawing may return only as a consumer
of a current scoped Ready assessment; it must not infer readiness from a
completed Learning Path row.

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

## 7. Adaptive Drawing

Adaptive Drawing is an unapplied future requirement, not a selectable current
Learning Path stage. Before adding it, define attributable repeated-trial data,
reserved physical holdouts, candidate-versus-prior promotion, applicability and
uncertainty, and the typed 4.5 readiness boundary. Do not restore the
deleted speculative online dataset, policy/reward scaffolding, model-mismatch
overlay, or dormant navigation route as a compatibility surface.
