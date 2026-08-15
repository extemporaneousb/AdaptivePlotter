# AdaptivePlotter Roadmap

Status: unfinished work only; never completion evidence

Current implementation and verification are recorded in
[Current Evidence](CURRENT_EVIDENCE.md). Product authority is
[Product Contract](PRODUCT_CONTRACT.md).

## 1. Attended sparse-calibration validation

Run the complete [Attended Hardware Runbook](ATTENDED_HARDWARE_RUNBOOK.md) on a
disposable sheet. Validate actual controller settlement, five cap captures,
five 2 mm-radius circular marks, far X-max/Y-zero-biased reveals, frozen-frame
human center clicks, post-click geometry, smallest-passing model review, and one
Stage 4 observed line. Record failures without redrawing ambiguous locations.

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

## 4. Repeated attributable drawing trials

Collect multiple attended line observations across position and direction.
Keep trial-local baseline/reveal provenance, exact tip revision, controller and
paper identities, and held-out evaluation. Compare null, prior, and candidate
models; expose uncertainty/applicability; require explicit acceptance for any
refinement.

## 5. Stroke and shape evaluation

After line evidence is reliable, add corners, polylines, repeated reversals, and
speed-sensitive trials. Keep request geometry, executed controller evidence,
and observed pixels distinct. Do not introduce automatic redraw after an
ambiguous stroke.

## 6. Drift and lifecycle studies

Measure within-session and cross-session sensitivity to focus, mount, tool,
paper, temperature, controller-coordinate, and capture restarts. Use those
results to set revalidation frequency and residual thresholds; do not tune
thresholds merely to pass simulator fixtures.

## 7. Operational hardening

- export a redacted evidence bundle with schema/version validation;
- add explicit storage inspection and checkpoint deletion UI;
- exercise upgrade/migration and corrupted-checkpoint refusal;
- expand accessibility and keyboard operation for exact-frame clicking;
- keep signed-bundle, singleton, camera, and serial ownership tests current.

## 8. Adaptive Drawing

Adaptive Drawing is an unapplied future requirement, not a selectable current
Learning Path stage. Before adding it, define attributable repeated-trial data,
reserved physical holdouts, candidate-versus-prior acceptance, applicability and
uncertainty, and an explicit operator promotion boundary. Do not restore the
deleted speculative online dataset, policy/reward scaffolding, model-mismatch
overlay, or dormant navigation route as a compatibility surface.
