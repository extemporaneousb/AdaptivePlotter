# AdaptivePlotter Roadmap

Status: unfinished work only; never completion evidence

Current implementation and verification are recorded in
[Current Evidence](CURRENT_EVIDENCE.md). Product authority is
[Product Contract](PRODUCT_CONTRACT.md). The architecture migration and its
dependencies are owned exclusively by
[Episode Architecture Execution Plan](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md);
this roadmap does not restate or reorder them.

## Portrait Studio: remaining acceptance

The current single-canvas contract lives in Product Contract; dated implementation
and measurements live in Current Evidence. Retired grid, prototype and training
interfaces are not future obligations. Remaining work is:

- Measure native capture-to-first-drawing, warm edit/Next, retained navigation and
  Drawing handoff separately. Cached navigation targets <100 ms and useful warm
  Next roughly 0.5 seconds; software fixture timings do not prove click-to-paint.
- Compare independently tuned Flow Edge, tonal contours and Sketch on retained real
  photos at matched drawing size and path/ink budgets. Judge identity, actual age,
  expression, structure and tone independently of waiting time. Regional/eye recipes
  require the same evaluation before claims of usefulness.
- Validate capture/exposure and actual line separation with the chosen camera, pen,
  paper and size through the existing attended Drawing flow. No screenshot or
  nominal spacing proves physical quality.
- Extend shared source evidence only when controlled comparisons establish a need;
  current supports cover landmarks, estimated face skin and observed jaw. Hair/clothing,
  registered multi-frame evidence, depth and learned abstraction remain research.
- Verify cold-start behavior on the user's actual archive and native saved-style chooser.
  The committed compact manifest and early legacy catalog read are implemented. A first
  legacy read still pays the large JSON/checksum cost; the next normal save upgrades it.
  Do not migrate the operator's archive merely for a benchmark. Moving each candidate
  program into content-addressed assets and lazy history materialization remain possible
  later reductions of bulk load/save cost under the same archive owner.
- Evaluate the experimental shared-parameter preference policy against baseline Next on
  attributable real-photo feedback. The implemented model gates use on independent
  source/session/ancestry groups and frozen renderer/material/pose/region context, and
  preserves baseline exploration. Synthetic fitting proves mechanics only. Thirteen saved
  recipes are seeds, not paired drawing targets or invented preference votes. Record
  explicit comparisons across photos before claiming learned drawing quality.

### Research decision: trainable portrait representation, 2026-10-01

One trainable drawing system does not require one line-extraction algorithm. The current
system has shared source evidence, parameters and landmark-based regional processing;
Contour is tonal marching squares, Flow Edge combines structure and tonal streamlines,
and Sketch uses DoG/thinning. Flow samples at 320 pixels, other kernels at 160. They output
immutable fixed-pen polylines through the same Drawing pipeline. The new binary policy
learns preferences over their shared coordinates in a fixed context. It cannot learn a
new stroke vocabulary or an artist's style from thirteen parameter recipes.

| Direction / primary evidence | Relevance and strongest limitation here |
| --- | --- |
| [APDrawingGAN](https://cg.cs.tsinghua.edu.cn/people/~Yongjin/Yi_APDrawingGAN_Generating_Artistic_Portrait_Drawings_From_Face_Photos_With_Hierarchical_CVPR_2019_paper.pdf) | Global/local portrait networks support treating identity-bearing features separately. This is hierarchical region specialization, not evidence that a generic learned router over our two kernels will help. Its output is raster and its paired artist drawings differ fundamentally from saved parameter recipes. |
| [Chan et al., geometry and semantics](https://carolineec.github.io/informative_drawings/) | Geometry and semantic objectives provide a better training target than geometric novelty alone. Raster output still needs a tested fixed-pen vector representation; semantic recognizability alone does not establish this subject's identity or age. |
| [DiffVG](https://people.csail.mit.edu/tzumao/diffvg/) and [CLIPasso](https://clipasso.github.io/clipasso/) | Differentiable curves provide one optimizable stroke representation and explicit abstraction by stroke count. Per-image optimization and generic CLIP semantics need portrait-specific geometry/likeness checks; they are not a ready native low-latency replacement. |
| [PortraVec v2](https://arxiv.org/html/2410.04182v2) | Most relevant first vector benchmark: facial initialization, second-pass contour refinement, region freezing and fixed-width black cubic curves. The authors report about five minutes for image-guided optimization and evaluate sampled CelebA-HQ portraits; neither interactive performance, child likeness nor physical pen quality transfers automatically. |
| [SwiftSketch](https://swiftsketch.github.io/) | Amortized image-conditioned vector generation addresses eventual interactive speed. Its project describes 35,000 synthetic image/vector pairs across 100 categories and training on 15 categories. That is not our sparse feedback archive, and object-level generalization is not individual portrait identity evidence. |
| [Single-Line Drawing, 2026](https://arxiv.org/abs/2606.01910) | Continuous vector-path optimization is relevant to pen-lift economy. Connectivity is a stylistic constraint, not established portrait fidelity or mechanical benefit in this application; compare it only after a useful sparse multi-stroke baseline. |

Selected direction: retain one parameter representation and two explicit deterministic
baselines while measuring the small preference policy. Next, evaluate one budgeted set of
fixed-width cubic curves with separate facial structure and tone objectives, landmark
initialization, and frozen unrelated regions. A bounded image-guided PortraVec/DiffVG
prototype is the first comparison; no prompt-driven identity/expression deformation is
selected. Compile accepted curves into the existing `DrawingProgram` with material,
spacing, clipping and point/path budgets. Only after useful accepted targets exist should
we consider distilling into an image-conditioned vector model for interactive inference.

The strongest objection to the selected near-term policy is its limited representation:
it can prefer existing parameter settings but cannot recover information discarded by
analysis or create a new grammar. A single collapsed kernel would lose useful baselines;
a learned mixture/router currently lacks attributable expert-quality labels and adds
routing/coverage failure modes. Region experts can be reconsidered if independent
comparisons show systematic gains over the shared curve model.

Acceptance for the vector experiment: compare current kernels and learned/optimized
curves on the same held-out real portraits at matched physical size, pen width and
30/60/120 stroke budgets; record identity and actual age, feature topology, tone, clutter,
operator preference, failure rate and generation/choice latency. Include profiles,
occlusions and the user's intended subjects, with source/session/ancestry separation.
The online policy's grouped holdout is per fit, not a permanent subject-level benchmark;
curated experiments need subject identity grouping beyond source/session/ancestry links.
Use attended final-scale plotting later to establish line separation and ink quality.
Fewer strokes, CLIP similarity, synthetic holdout success or a paper's benchmark cannot
substitute for those observations. No research model, dataset or cloud upload is installed
or invoked by the current implementation.

These are acceptance gaps and conditional research, not authorization to restore
parallel sampling interfaces or add new generation systems. Historical scope remains
in the [deterministic Studio correction](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md#deterministic-portrait-studio-correction-2026-09-18).

## Drawing motion: attended continuous-polyline comparison

The selected software portion of the September 19, 2026 backlog is implemented
through the existing Drawing path. New general Drawing attempts retain an immutable
versioned motion recipe bound to the exact intended plan and use bounded ACK-driven
`$J` refill within each stroke. Current behavior and ownership belong to
[Product Contract](PRODUCT_CONTRACT.md) and
[Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md); validation receipts belong to
[Current Evidence](CURRENT_EVIDENCE.md). Legacy attempts with absent policy remain
unknown, and no-recipe callers retain isolated execution.

Attended physical acceptance remains pending and requires separate explicit
authorization: compare matched polylines, curves and corners under the same
geometry, feeds, pen, paper and controller settings, recording elapsed operation
time and observed ink. Determine the speed benefit and tracking/line quality
without treating transcript tests, command acknowledgement or controller settlement
as physical proof. No numerical speedup, uninterrupted physical velocity or
aesthetic equivalence is claimed. Retained lower-plan timing excludes baseline and
post-drawing observation work and is not total end-to-end run latency.

No new UI, route reordering, stroke reversal, geometry optimization, feed increase,
firmware settings change, automatic experimentation or learning-model integration
is selected by this remaining scope. Future aesthetic feedback judges the drawing
alone; time remains separately measured evidence. The work neither selects an
episode-migration package nor changes migration order.

## Parking lot: voice input and speech output

Deferred by the operator on September 12, 2026. The current Voice switch controls
recognition and contextual prompting; workflow speech has a separate runtime.
A future change should provide independent Voice Input and Speech Output controls,
with output mute cancelling active/queued speech and suppressing all announcement
sources. Leave voice behavior, preferences, recognition and synthesis unchanged
in the bounded paper/border/Motion correction campaign as well.

The operator also reported silence until "Drawing the four-edge Drawing Border."
Code inspection confirms that Drawing Border execution calls
`PlotterApplicationRuntime.performSpeechEffect` in `OperatorWorkspace.swift`
directly, without the window-local
`WorkbenchVoiceController.isEnabled` gate. Four-circle pen normalization uses
the lower pen-command path and does not announce that command. Include both
paths when implementing the independent output control; the reported toggle
state and attended audio behavior have not been verified.

## 0. Episode architecture migration

Execute the plan's named packages in ledger order. The execution-plan ledger and
Current Evidence own the live frontier; this roadmap deliberately does not copy
a package ID that becomes stale after every landing. Continue through the pilot,
Learning Path family cutovers, composition cleanup, final attended validation,
and final gate.
Every package must preserve existing device/evidence authorities, satisfy the
observability contract, delete its superseded authority in the same landing,
and update Current Evidence. Do not create a parallel application, architecture
plan, compatibility workflow, or effect-capable shadow path.

The product experiments below may supply requirements to a package, but they do
not bypass its dependencies or introduce another episode runtime. Adaptive
selection and cross-track candidate fitting now use the canonical
program/plan/evidence path. Batch execution and model acceptance remain product
work on those owners.

## 1. Attended sparse-calibration validation

Run the complete [Attended Hardware Runbook](ATTENDED_HARDWARE_RUNBOOK.md) on a
disposable sheet. Validate actual controller settlement, five cap captures,
selection of the paper working extent inside the machine Boundary, four
2 mm-radius circular marks inset 10 mm from its corners with no center
mark and Pen Up
between them, one final center Pen-Up reveal, the separately labeled accepted
Exercise 1.2 Drawing Boundary and inset Drawing Border overlays, one shared frozen exact frame, four
arbitrary-order human center clicks, deterministic global association, the
all-corner affine-first commit on click four, one predicted Drawing Border preview before
motion, one complete Exercise 2.1 Drawing Border validation, retained exact comparison
review, two consecutive ordinary drawings across same-plane sheet replacement,
with Draw border off and on, exact new-sheet coverage confirmation, and retained
calibration/completion/outline. Check visible Motion values during both manual
and automatic paths, stale/disconnected labeling, hide/reopen, and current
blocker recovery. Verify the explicit Enable Motion & Raise Pen lift and adjacent
position-recovery Raise Pen retry in attended use; automated settlement cannot
prove the physical pen lifted. Record post-run planned-versus-observed review and failures without
redrawing ambiguous locations.

This remains an attended release gap, alongside the campaign's first-priority
physical proportion check. Automated and simulated evidence cannot close it.
In particular, C920 reliability for click-learned arbitrary cap colors,
cap-body click usability and sampling tolerance, the usefulness of the
cap-inferred armature envelope, preview fluidity, and attended calibration remain
unproven until this run is explicitly authorized and performed.

## 2. Operator-declared semantic revision controls

Add deliberate attended controls for tool/holder/contact-profile replacement,
camera mount/reframing changes, and known machine-geometry revisions. Each
control must rotate the correct semantic identity, show the affected checkpoint
and graph suffix, preserve raw history, and require explicit invalidation or
revalidation. Binary/process/capture restart retains the persisted semantic
identities. Camera-based position recovery now separates accepted Learning from
physical carriage continuity; unchanged MPos cannot prove an unpowered armature
stayed still. The controls must still let the operator declare camera, tool or
geometry changes beyond the supported translation recovery. Attended validation
of gravity-drift recovery and corrected overlay/ink placement remains required;
software fixtures do not establish it.

## Diagnostic archive integration

The delivered workbench snapshot exports the existing bounded Learning record
and current owner projections. Integrate the existing canonical incident
assembler with durable feature recordings only when a concrete continuity,
replay, or debugging need requires those raw artifacts. Do not add a parallel
Learning event stream or make a complete archive a prerequisite for the normal
operator path. Contextual Voice is native speech recognition; open-ended
conversational reasoning and learned dialogue policies remain future work.

## 3. Durable exact-frame archive

Current exact frames retain hashes and metadata but no content-addressed pixel
locator. The Trainable Drawing Studio campaign owns the next candidate/run-media
integration through existing evidence authorities: retain only shortlisted, rated,
successfully projected or physically attempted candidates, with exact raw/derived
assets and recoverable run evidence. Ordinary browsing remains transient. Define
disk visibility, corruption checks, atomic association and explicit deletion; do
not silently evict qualified evidence under former session-cache limits. Wider
camera archival remains separate work and cannot be inferred from this retention
authorization.

## 4.2 Coverage Line Trials

The sealed coverage selector and operator-stepped trials are implemented.
Automate the bounded batch so one operator action starts it, software owns normal
trial-to-trial progression, and **Stop** remains available throughout. Preserve
the delivered exact per-line baseline/reveal, role, provenance, controller, ink,
and residual records. Possible ink, ambiguous motion, unclear Vision, or archive
failure must stop the batch without redraw. Keep the split fixed before results.
Validate the line dimensions, spacing, observer coverage, and selection policy on
attended physical hardware before claiming training reliability.

## 4.3 Direction and Residual Model Training

Bounded spatial and signed-direction **cross-track** candidate fitting and
reserved-holdout prediction comparison are implemented. Add experiments that can
identify along-track backlash and other effects that straight-line interiors
cannot measure. Evaluate corrected execution against the affine prior with
predeclared physical holdouts, then add explicit scoped candidate acceptance and
rollback. The current candidate is diagnostic and never changes execution.
Retain separate applicability, uncertainty, training error, and holdout error;
failed or inconclusive evidence must leave the affine prior current.

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
ready** after Exercise 1.4 and **Learning complete**
after Exercise 2.1—not **Trained**. Direct Drawing Studio execution may use that
validated current map and records every outcome, but **Adaptive drawing ready**
may appear only from a current scoped Ready assessment.

## 5. Drift and lifecycle studies

Measure within-session and cross-session sensitivity to focus, mount, tool,
paper, temperature, controller-coordinate, and capture restarts. Use those
results to characterize drift, revalidation cadence, and diagnostic residual
distributions. They must not create Exercise 1.4 residual, confidence, or
model-quality gates.

## 6. Operational hardening

- export a redacted evidence bundle with schema/version validation;
- add explicit storage inspection and checkpoint deletion UI;
- exercise upgrade/migration and corrupted-checkpoint refusal;
- expand accessibility and keyboard operation for exact-frame clicking;
- keep signed-bundle, singleton, camera, and serial ownership tests current.

## 7. Adaptive model promotion and face programs

Direct placed-vector drawing is implemented outside the Learning Path. The next
adaptive step is bounded batch progression, corrected-execution physical
holdouts, explicit model acceptance, and readiness emission on the existing
program/plan/evidence types. The selector and diagnostic cross-track fitter are
implemented. Do not restore the deleted
speculative online dataset, policy/reward scaffolding, model-mismatch overlay,
or dormant navigation route as a compatibility surface.

Portrait acceptance and conditional research are listed above. The historical
[Trainable Drawing Studio campaign](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md#trainable-drawing-studio-campaign-2026-09-13)
retains dated evidence, not a requirement to restore retired interfaces. Screen
preference and physical realization remain separate objectives.

No portrait feature should own calibration, controller commands, paper state,
plan execution, physical machine-model promotion, or Draw locks. Scoped aesthetic
checkpoint activation belongs to the authoring producer and cannot change an
active physical plan or confer machine readiness.
