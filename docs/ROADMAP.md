# AdaptivePlotter Roadmap

Status: unfinished work only; never completion evidence

Current implementation and verification are recorded in
[Current Evidence](CURRENT_EVIDENCE.md). Product authority is
[Product Contract](PRODUCT_CONTRACT.md). The architecture migration and its
dependencies are owned exclusively by
[Episode Architecture Execution Plan](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md);
this roadmap does not restate or reorder them.

The next named product correction is the execution plan's
[Trainable Drawing Studio campaign](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md#trainable-drawing-studio-campaign-2026-09-13).
It prioritizes the reported physical aspect-ratio defect, qualified durable
candidate/realization evidence, balanced local variation, semantic Big Head,
measured material behavior and an operational style-scoped preference learner.
Its coordinator task/dependency/acceptance register is canonical; all implementation
rows are pending. It does not select or reorder historical migration packages.

The preceding presentation correction is the execution plan's
[permanent canvas and native control panes](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md#permanent-canvas-and-native-control-panes-2026-09-12).
It supersedes the layout and diagnostic portions of the
[workbench and portrait correction](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md#workbench-and-portrait-completion-correction-2026-09-08).
Current Evidence records software verification separately from the remaining
native interaction, sustained workload, and attended physical requirements.
The physical model experiments below remain separate from the campaign's aesthetic
style learner and ordinary portrait drawing.

## Parking lot: Portrait Studio UI refresh and guided exploration

Saved September 13, 2026 at the operator's request. **Deferred: planning only;
implementation is not authorized by this entry.** This records future product
work and open decisions; it does not select, schedule, or change the execution
register of the
[Trainable Drawing Studio campaign](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md#trainable-drawing-studio-campaign-2026-09-13).
Reconcile the affected campaign requirements when the operator resumes this work.

### Proposed experience and future work

- **Nonlinear authoring:** organize setup, capture, and exploration into distinct
  tabs or sections that can be revisited independently. Studio experimentation
  must be available without plotter information or a connected plotter.
- **Plotter setup:** obtain available dimensions and model details from the
  plotter and its existing model authority. When unavailable, offer a small set
  of aspect ratios and explicit pen/marker thickness for authoring. Identify
  assumed inputs separately from device-derived values. Center on Target, zoom,
  and related placement/view controls belong outside setup. Authoring defaults
  do not establish physical calibration or drawing readiness.
- **Capture series:** retain the set of images acquired during each capture
  series, allowing more than 25 images. Group each series as a collapsible unit
  and support deleting a whole series in one action. The proposed example is
  "For 5 I can imagine 30 images max"; its duration/unit and limit semantics
  remain open below. A global 25-image limit must not silently truncate a series.
- **Paired exploration view:** show the selected source photo beside its drawing,
  with the same aspect ratio. This comparison could occupy the main frame in
  place of the live camera image; define how capture/live view is revisited.
- **Separate feedback axes:** keep keyboard-driven exploration and apply the
  exact mapping below. Each action assesses only its named subject; the other
  subject receives no assessment from that action. Absence of assessment must
  not become a negative or positive label, or erase an earlier explicit label.
- **Adaptive exploration:** use these choices to change the subsequent drawing
  proposals and where exploration concentrates. Distinguish source-image
  preference from generated-drawing preference so a rejected photo is not
  treated as a rejected rendering style. Retain enough source/candidate context
  to attribute each choice. These are screen preferences, separate from physical
  drawing outcomes.

| Arrow | Source image assessment | Drawing assessment |
| --- | --- | --- |
| Left | None | Dislike |
| Right | None | Like |
| Down | Dislike | None |
| Up | Like | None |

### Decisions to resolve when work resumes

- Tabs versus sections, placement/view control grouping, and switching between
  live capture and paired comparison.
- What "For 5" means (possibly five seconds, not yet confirmed), the capture
  cadence, whether 30 is a per-series maximum or an example, and how series are
  bounded. Also specify reload persistence, storage visibility and deletion
  behavior for source images referenced by retained candidates or run evidence;
  reconcile this with the campaign's qualified-evidence retention policy.
- Fallback aspect-ratio presets, thickness units/defaults, and how manually
  supplied authoring inputs behave when plotter information becomes available.
- Whether each rating automatically advances, how unrated browsing remains
  available, key handling while editing controls, and undo/reassessment.
- How image and drawing feedback separately affect proposal selection, including
  continued exploration and how to verify that choices change later proposals.

Future acceptance should demonstrate disconnected Studio use, complete capture
series above 25 images, collapse and bulk deletion, matched-aspect comparison,
independent four-arrow labels, and observable changes in exploration. These are
future checks, not implementation or validation evidence.

### Original operator proposal (verbatim)

> The Portrait studio needs a UI refresh/redo. One issue is that the workflow is not entirely linear and one might not have the information from the plotter and still want to play in the studio.
>
> I'm thinking that the way to do this is to have maybe tabs or better org of the elements. There should be a plotter setup tab and that should basically get the dimensions and model details from the plotter itself and whatever information is necessary if it is absent then we can use one of a few aspect ratios and pen/marker thickness. Those are the main details that will effect the drawing at the studio level. Things like center on target zoom and things like that should not be next to the setup section.The next tab or section will be for capturing photos with the camera - we should allow more than 25 images, we should just store the set of images that are acquired during one capture series, whatever that is. For 5 I can imagine 30 images **max**. Capture sequences should be deletable en masse and should be collapsable.
>
> Ideally, we would have something like the photo next to the drawing same aspect ratio - these could go in the main frame instead of a live image. The arrow keys for moving through items are great and I only want to make that better by making the arrows do the following: left means i don't like the drawing, the image is not assessed. right means that i like the drawing and the image is not assessed. down means i don't like image and the drawing not assessed, up means like image drawing not assessed.
>
> Those choices change the sequence of drawings that we explore - so this way, I can influence where in the space to explore more of.

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
four 10 mm-inset Boundary-corner 2 mm-radius circular marks with no center
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

Remaining portrait work is specified by the
[Trainable Drawing Studio campaign](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md#trainable-drawing-studio-campaign-2026-09-13),
including physical proportions, durable qualified evidence, contour/local variation,
semantic Big Head, material-aware rendering, scoped fitting and Studio layout.
Attended burst-camera/screen-light evaluation and ink-quality comparison across
marker widths, paper sizes, frontal and three-quarter views remain required. The
current studio offers individual burst frames, adjustable head framing, coarse vector
controls, angled hatch, centerline Sketch, deterministic face-anchored big-head geometry,
independent frame/style browsing, seeded recipe history, and bounded exportable
preference examples. It does not yet perform
multi-view fusion, registered temporal averaging, facial-part parsing, learned
caricature, or identity-aware automatic preference fitting.

An optional later learned image producer can be assessed against
[APDrawingGAN](https://github.com/yiranran/APDrawingGAN), which uses aligned faces,
landmarks and masks, and
[Informative Drawings](https://carolineec.github.io/informative_drawings/), which uses
semantic and geometric objectives for raster line drawings. Their output still needs
centerline vectorization, marker/paper-scale evaluation, and likeness ratings before
being called festival-quality portrait drawing. The shipped local Sketch uses the
[difference-of-Gaussians stylization family](https://www.cs.northwestern.edu/~sco590/winnemoeller-cag2012.pdf),
not those learned models or a full XDoG reproduction. Apple's
[face capture quality guidance](https://developer.apple.com/videos/play/wwdc2019/222/)
supports future advisory same-subject frame ranking; it should preserve the operator's
ability to choose useful profile frames. Naively averaging a rotating face would blur
features, so any future averaging requires registration and motion rejection first.

Different angles are useful source choices and may later supply identity information:
[PhotoMaker](https://github.com/TencentARC/PhotoMaker) aggregates multiple reference
images through identity embeddings without per-person model training. This is a research
candidate, not a shipped dependency or a claim that arbitrary video frames reconstruct
an identity. [CariGANs](https://doi.org/10.1145/3272127.3275046) separates geometric
exaggeration from appearance; the current native implementation exposes those axes
through deterministic face geometry and ink recipes. It does not claim a learned caricature.

Grades currently capture generated candidates, not the artwork a supervised GAN
should imitate; no fitting, upload or score-dependent generation currently runs.
The campaign's first learner will fit a native scoped ordinal model over the
existing deterministic renderer and semantic warp parameters, persist/activate
checkpoints and change production proposals. Exact presentation context and label
revisions, grouped holdouts, prior/current comparison and rollback are in scope;
export-and-train-later is not completion. A pretrained generator is optional later
work, not a prerequisite for learning recipe preferences. [Diffusion-DPO](https://arxiv.org/abs/2311.12908)
uses paired preferences to adapt a pretrained diffusion model and is a distinct
future approach. Screen aesthetic and physical realization objectives stay separate.

No portrait feature should own calibration, controller commands, paper state,
plan execution, physical machine-model promotion, or Draw locks. Scoped aesthetic
checkpoint activation belongs to the authoring producer and cannot change an
active physical plan or confer machine readiness.
