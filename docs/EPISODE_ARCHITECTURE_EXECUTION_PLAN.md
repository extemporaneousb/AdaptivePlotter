# Episode Architecture Execution Plan

Status: sole target architecture, migration sequence, and landed-work ledger

This document owns the intended episode architecture and its replacement
sequence. It does not describe current implementation. The current package and
runtime owners remain in [Swift Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md),
product invariants remain in [Product Contract](PRODUCT_CONTRACT.md), and
verified results remain in [Current Evidence](CURRENT_EVIDENCE.md).

No temporary review report, research memo, execution prompt, rejected proposal,
or competing architecture plan is authority. Accepted conclusions must be
integrated here and the source note deleted. Git history and Blackdog prompt
artifacts are history, not current design.

## Trainable Drawing Studio campaign, 2026-09-13

This is the canonical implementation plan for the operator's Drawing/Portrait
Studio correction and trainable-style request. Planning task
`task-2cc60c7340414b9ebcbec83e275333ec` assessed base
`69ba9df7b752516780d98c051bc966316f970f13`. Implementation and evidence states are recorded independently in the ledger below. This named product corrective campaign does not select, reorder,
complete, or reopen any historical episode migration package; do not invoke
`run-multi-agent-wave` to select its work. Product Contract and Architecture remain
as-built authorities until implementation actually changes them. Planning receipts
and the supplied screenshot are recorded in
[Current Evidence](CURRENT_EVIDENCE.md#trainable-drawing-studio-planning-2026-09-13).

The coordinator owns the whole campaign: contract integration, worker assignment,
submission review, validation, dependency closure, landing and final completeness.
The priority is the actual proportion defect, followed by a production learner
whose retained labeled examples change future generation. A checkbox, export-only
ratings, hardcoded variations, or a collection of individually passing patches is
not completion. Native interaction and attended realization have separate gates.

### Assessed starting point and scope boundaries

The operator reports material X-axis stretch and supplied a camera screenshot of a
sideways portrait, planned overlay and visible ink. The screenshot is useful
reported evidence, but it does not bind the exact source image, program, placement,
plan, registration or running binary, and is not a calibrated physical measurement.
Current source uses uniform vector/preview/placement scaling. That does not prove
the controller coordinates form the expected physical Euclidean metric. The free
affine machine-to-camera registration can include anisotropy and shear; its inverse
alone cannot distinguish camera perspective from physical axis scale. Existing Fit
also tries a 90-degree rotation to maximize occupancy. Keep rotation, fit and
distortion separate in both diagnosis and authoring.

The existing production seam remains source image -> analysis/vector producer ->
`DrawingProgram` -> `PlotterDrawingDraftRuntime` -> placement/planning ->
`PlotterDrawingRunRuntime` -> existing interpreter, camera and evidence owners.
Do not add another planner, runner, camera capture owner, Learning authority, Draw
lock, physical model promoter or run recorder. Style training owns aesthetic
generation policy; it does not learn around a broken coordinate transform or grant
machine readiness. Existing Stop, possible-ink/no-redraw, exact-frame confirmation,
paper applicability and accepted Learning behavior remain regression obligations.

Current Random samples five modes equally; three contain hatching (approximately
60 percent). Big Head uses a face rectangle rather than semantic facial landmarks.
Kept sketches and rated examples are session collections with silent oldest-item
eviction. Ratings do not currently train any generator or ranker. Run evidence owns
reconstructable execution plans, including full placement values; the top-level
placement reference is a hash, while the source-program payload is missing.
Ordinary raw baseline/result frames are not durably owned. Nominal 0.4 mm stroke
width and preview sliders are not measured deposited-ink width.

### Requirement register and traceability

Each requirement below must have an artifact receipt and an integrated journey
check. `G` identifiers name evidence gates defined below; task dependencies do not
waive a requirement. Software evidence cannot substitute for native or attended
evidence. Any unavailable result remains explicit in the campaign ledger.

| Requirement | Required behavior | Task owners | Evidence |
| --- | --- | --- | --- |
| R01 | Trace exact source/crop/raster/vector/field/placement/controller/camera/display geometry and identify the first failing transform. | DS-01, DS-09 | G01, G09, G10 |
| R02 | Preserve physical drawing proportions by default across every primitive and portrait producer; never independently fill X/Y. | DS-01 | G01, G10 |
| R03 | Keep source crop metric distinct from raster sampling; cover minimum-eight/maximum-160 raster dimensions and extreme aspect ratios. | DS-01 | G01 |
| R04 | Make rotation explicit; an optional unlocked stretch is versioned authored intent shared by preview, plan and ink, with hashes and invalidation. | DS-01, DS-08 | G01, G08, G10 |
| R05 | Prove the physical coordinate metric independently of camera affine anisotropy/shear, or implement the missing calibrated metric through existing owners. | DS-01, DS-10 | G01, G10 |
| R06 | Retain candidates only for shortlist, any 1–5 rating, successful projection acceptance or physical attempt; all other generation/navigation stays transient. | DS-02, DS-03, DS-08 | G02, G08, G09 |
| R07 | One candidate owns exact source bytes, analyzed raster, masks/landmarks, crop, recipe/seed, vectors, producer/checkpoint revisions and provenance. | DS-02, DS-04, DS-07 | G02, G04, G07 |
| R08 | Retain immutable label revisions, scope and lineage; a qualified child cannot implicitly retain full unqualified ancestors or browsing siblings. | DS-02, DS-03, DS-07 | G02, G03, G07 |
| R09 | Durable assets survive restart and recent-photo eviction; atomic writes, visible pending/failure, corruption/recovery and explicit deletion are covered. | DS-02, DS-06 | G02, G06, G09 |
| R10 | Never silently FIFO-evict qualified candidate/training/physical evidence; storage policy exposes retained size and unresolved persistence. | DS-02, DS-08 | G02, G08 |
| R11 | Broad Random gives contours, tonal contours and clean-line work prominent, balanced exploration; hatching remains available deliberately. | DS-03 | G03, G08 |
| R12 | More like this explores bounded local variations with source/crop/family/head fixed; parent/back/branch navigation recovers exact candidates. | DS-03, DS-08 | G03, G08, G09 |
| R13 | Keep photo navigation separate from style navigation; favorites/shortlist, current edit and branches remain understandable. | DS-03, DS-08 | G03, G08 |
| R14 | Big Head expands forehead height/width and supported eye/lateral/ear regions, tapers through nose, and protects mouth/chin recognition. | DS-04 | G04, G10 |
| R15 | Warp in face-local coordinates with pose/landmark provenance, positive Jacobian, bounded displacement, no unintended clipping and explicit unsupported cases. | DS-04 | G04, G10 |
| R16 | Train a named labeled style scope, including Big Head, using durable aesthetic ratings and explicit active/frozen parameter masks. | DS-02, DS-04, DS-07 | G02, G07, G09 |
| R17 | Fit and continue fitting from compatible reloaded checkpoints with new/revised scoped labels and declared warm-start/full-refit semantics; persist child lineage, activate production proposals, compare and roll back. | DS-07, DS-08 | G07, G08, G09 |
| R18 | Preserve comparable datasets and complete training manifests; group holdouts by source/session/ancestry before evaluation. | DS-02, DS-07 | G07, G10 |
| R19 | Handle insufficient/degenerate labels, cancellation, nonfinite optimization and missing/corrupt checkpoints honestly; retain a usable prior. | DS-07 | G07, G09 |
| R20 | Bind on-screen labels to exact presentation context and objective; distinguish physical-realization labels; retention events are not scores or implicit negatives. | DS-02, DS-07, DS-08 | G02, G07, G08 |
| R21 | Each physical attempt links candidate, full source program and placement, immutable plan, reconstructable calibration, material/mount/paper/feed and outcome. | DS-02, DS-05, DS-06 | G02, G05, G06, G09 |
| R22 | Persist intent and baseline before dispatch, then seal terminal evidence; retain partial, failed, cancelled and interrupted attempts without redraw. | DS-06 | G06, G09, G10 |
| R23 | Own raw before/after images and derived comparisons with exact source/frame identities and asset integrity, not only hashes. | DS-06 | G06, G09, G10 |
| R24 | Prefer one reachable pen-up pose clearing the drawing region; capture matched baseline/result views at that pose. | DS-06 | G06, G10 |
| R25 | If necessary use bounded registered multi-pose coverage, originals, occlusion masks and per-pixel provenance; never invent unseen ink. | DS-06 | G06, G10 |
| R26 | Stop/ambiguous motion never causes automatic photo repositioning; preserve available terminal frames and explicit missing-coverage reasons. | DS-06 | G06, G10 |
| R27 | Separate replaceable material behavior from kinematics, while binding tool/mount/contact/paper/speed and calibration applicability. | DS-05 | G05, G09, G10 |
| R28 | Estimate deposited width/distribution/direction from border segments and existing 2 mm-radius, 16-chord marks using calibrated local metric and uncertainty. | DS-05, DS-06 | G05, G10 |
| R29 | Filled holes, overlapping ink, vertices/pooling, occlusion and inadequate resolution yield exclusions, bounds or unavailable estimates, not false precision. | DS-05 | G05, G10 |
| R30 | Measured width affects hatch spacing, minimum gaps, detail feasibility and preview at actual accepted placement scale. | DS-01, DS-03, DS-05 | G01, G03, G05, G10 |
| R31 | Geometry/material/scale/model changes create new candidate/plan revisions; rated, active and historic drawings remain immutable. | DS-01, DS-02, DS-05, DS-07 | G02, G05, G07, G09 |
| R32 | Creative controls precede projection/placement/material setup, then paper and Draw at the bottom; existing useful controls remain. | DS-08 | G08, G09 |
| R33 | Gallery recovers exact retained drawings and linked plotted-object images; explicit export can remain additional to automatic qualified retention. | DS-02, DS-06, DS-08 | G02, G06, G08, G09 |
| R34 | Keep Stop/status accessible, keyboard/native navigation functional and high-rate camera/render state local with quiet training status. | DS-08, DS-09 | G08, G09, G10 |
| R35 | Coordinator validates every worker and complete cross-feature journey, records exact build/artifact identity and closes all requirement gaps. | DS-09, DS-10 | G09, G10 |
| R36 | Report software/native/attended results separately; insufficient held-out or physical evidence cannot be labeled total quality completion. | DS-07, DS-09, DS-10 | G07, G09, G10 |

### Contract freeze before parallel implementation

The coordinator integrates four shared contracts before workers edit consumers.
C1 defines source metric, explicit rotation/stretch intent, immutable candidate ID,
full program/placement payloads and content hashes. C2 defines retention reasons,
content-addressed asset ownership, label revisions, lineage, style scope and deletion
semantics. C3 defines material measurement/applicability and run-media references,
observation plans, staged run intent and terminal evidence. C4 defines renderer/warp
feature schemas, dataset snapshots and trainable checkpoints. These are contracts
within existing feature owners, not a new event bus or second source of truth.

Freeze concrete Swift type and serialization changes, producer/consumer ownership,
legacy decoding, invalidation and migration tests before parallel leases. Full
source and analysis assets must be owned where reproducibility needs them: a Vision
version plus a photo cannot reproduce landmarks or masks by assertion. Preserve
the exact analyzed raster, mask/landmarks and preprocessing transform used to render.

### Dependency-ready implementation ledger

This table is independent of the historical migration ledger below. Each row starts
PENDING. The coordinator replaces states only with actual receipts and keeps
software, native and attended fields independent; a dependency is accepted only
for the evidence class needed by its consumer. Contract-only early work may be
reviewed, but cannot complete the whole row.

| Campaign task | Deliverable and dependency | Worker file/semantic lease | Overall | Software | Native | Attended |
| --- | --- | --- | --- | --- | --- | --- |
| DS-01 | Source/crop metric and explicit Fit correction; C1 frozen for candidate consumers. Physical metric remains open. | Task `task-34dc69ed47f94ed695a7e7da85632890`; [receipts](CURRENT_EVIDENCE.md#ds-01-proportional-geometry-correction-2026-09-13). | PARTIAL: R05/attended open | COMPLETE: first correction, G01 software; 84 focused, 1102 quick, 10 journey, signed app, one-shot ACCEPT | PENDING | PENDING |
| DS-02 | Candidate, label and owned asset persistence; freeze C2 after C1 identity contract. | Persistence worker: `PortraitSketchCollection.swift`, `PortraitPreferenceCollection.swift`, new adjacent typed store/asset files and focused persistence tests. `PortraitStudioModel.swift` integration is serialized. | PENDING | PENDING | PENDING | PENDING |
| DS-03 | Balanced broad/local exploration and exact branch navigation; depends on DS-01/C1 and DS-02/C2. | Exploration worker: `PortraitStyleRecipe.swift`, `PortraitStyleBrowser.swift`, dedicated branch/proposal types and tests; exclusive sequential lease for `PortraitStudioModel.swift` and `PortraitDrawing.swift`. | PENDING | PENDING | PENDING | PENDING |
| DS-04 | Semantic Big Head and retained pose analysis; depends on DS-01 and DS-02. | Warp worker: `PortraitHeadTransform.swift`, new adjacent landmark/warp types and tests; sequential leases for `PortraitImageAnalyzer.swift`, `PortraitDrawing.swift` and shared recipe schema. | PENDING | PENDING | PENDING | PENDING |
| DS-05 | Effective material profile, measurement and final-scale feasibility; depends on DS-01/DS-02 and frozen C3. Consumes DS-06 media in integration. | Material worker: new `PlotterModel` material types, measurement beside the existing `PlotterRuntime` Vision worker and corresponding tests; coordinator integrates `DrawingProgram.swift`, `CurrentCameraCalibrationPlanning.swift`, tip evidence and renderer/draft consumers. | PENDING | PENDING | PENDING | PENDING |
| DS-06 | Durable run images, recoverable attempts and observation coverage; depends on DS-01/DS-02 and frozen C3 material references. | Run-evidence worker: `Sources/PlotterRuntime/DrawingRunEvidence.swift`, `DrawingRunEvidenceStore.swift`, `PlannedDrawingObservation.swift`; `Sources/PlotterEpisodeRuntime/PlotterDrawingRunRuntime.swift`; `Sources/PlotterApp/DrawingRunEvidenceComposition.swift`; corresponding tests. | PENDING | PENDING | PENDING | PENDING |
| DS-07 | Operational scoped preference fitting/proposals/checkpoints; depends on DS-02/DS-03/DS-04/DS-05 and frozen C4. | Training worker: new adjacent typed preference-training, dataset and checkpoint files/tests; coordinator leases shared recipe/model consumers after exploration integration. | PENDING | PENDING | PENDING | PENDING |
| DS-08 | Integrated authoring/gallery/training/material/Draw layout; depends on DS-02/DS-03/DS-04/DS-05/DS-06/DS-07 APIs. | UI worker: `PlotterApplicationRuntimeView.swift`, `PortraitStudioView.swift`, `PortraitPreferenceControls.swift`, `PortraitRecentItemsView.swift`, `DrawingStudioPresentation.swift`, focused UI tests; coordinator owns semantic intent/projection integration. | PENDING | PENDING | PENDING | PENDING |
| DS-09 | Full software/native journey, stable artifact, fresh requirements critic and integration repairs; depends on DS-01 through DS-08. | Coordinator plus fresh critic: cross-feature tests, exact build/provenance artifacts, current product/architecture/evidence docs; no concurrent full builds on a changing tree. | PENDING | PENDING | PENDING | PENDING |
| DS-10 | Attended geometry, likeness, material and realized drawing closure; depends on DS-09 and explicit attended authorization. | Coordinator with operator: runbook/evidence receipts, independently measured geometry/material and source-grouped comparisons; corrective source work returns to its owning task. | PENDING | PENDING | PENDING | PENDING |

At most three workers run alongside the coordinator. Parallelize only disjoint
file and semantic leases: DS-01 investigation and DS-02 persistence can start after
the identity contract; DS-04 and DS-06 can overlap once their dependencies settle.
The task table is not permission for simultaneous edits of shared files.
`OperatorWorkspace.swift`, shared models, runtime ports and schema migrations are
coordinator-owned integration surfaces. No worker starts Blackdog lifecycle,
creates its own task/worktree, lands, cleans up, starts hardware or replaces the app.

### Geometry and physically meaningful placement

DS-01 captures one reproducible fixture from original image through exact
preprocessing transforms, sampled dimensions, vector points, field extent,
placement, plan vertices, accepted model/registration and view transform. Record
source/plan/build hashes. Test vertices, basis lengths/orthogonality and segment
ratios; axis-aligned bounding boxes alone can hide rotation and shear. Preserve
source crop metric even when integer raster dimensions are clamped or rounded.

Exercise circles, squares, non-square rectangles, intended ellipses, tall/wide
portraits and extreme aspect ratios, multiple drawing regions, rotation, fit, and
border off/on. Default placement uses a similarity transform in a proved physical
metric; unused region area is expected. Separate rotation choice from proportional
fit. If unlocking proportions is supported, persist the explicit authored transform,
show its state, revise hashes and invalidate the same downstream draft/plan; no
preview-only stretch or unversioned axis multiplier is allowed.

First reproduce a failing invariant and identify its owning stage before applying
the correction. If controller units do not establish a physical metric, DS-01 must
scope a calibrated metric through the existing model/registration authority, with
independently measured orthogonal lengths/shape constraints and uncertainty. Do not
blindly invert the camera affine, force the overlay to look proportional, or let
style learning compensate. DS-10 must bind an actual calibration, exact plan and
artifact to independently observed physical segment ratios and orthogonality.
Camera projection may be oblique; the physical drawing must still meet the declared
metric tolerance. Missing metric evidence leaves R05 and the defect open.

### DS-01 contract and physical metric evidence boundary

The first correction uses `PortraitSourceCropExtent` (positive finite crop width
and height in original oriented source pixel coordinates) and versioned `PortraitRaster` serialization.
`PortraitAcquiredPhoto` and each recent photo/render request carry the original
source extent beside normalized bytes. Raster sample centers map through the source
crop metric; neither 1200-pixel thumbnail rounding nor the 8...160 raster sample
limits define source proportions. New portrait producer provenance is v3.
A missing crop extent denotes legacy sample-lattice geometry explicitly; existing
immutable programs are not rewritten. `DrawingProgram.id` plus `contentHash`, full
program payload, and `DrawingPlacement`'s anchor/uniform-scale/rotation remain C1
identity and authored-placement authorities. Fit retains authored rotation. No
unlocked stretch is provided. C2 will bind candidate identity to these exact values.

Controller `G21` coordinates supply nominal millimetres, but neither those units nor
the accepted camera affine prove equal physical axis scale or orthogonality. R05
and reported physical stretch remain open. The missing calibrated-metric scope is
within existing machine-geometry/registration acceptance and checkpoint ownership:
independent commanded basis vectors, physical lengths and included angle/diagonals,
measurement uncertainty and method, applicability region, machine geometry identity,
and immutable evidence digest. Absence means unmeasured. A measured positive-definite
Gram matrix can later determine physical similarity placement through the existing
planning adapter; containment, Fit, preview and material consumers must use that
same transform. Never derive this correction from camera-affine inversion alone.

Predeclared DS-10 geometry procedure: bind the exact app, source, plan, registration,
material and paper, then measure a 40 mm square with diagonals and a 40 x 20 mm
rectangle at explicit 0 and 90 degrees through the ordinary attended runner.
Use independently calibrated centreline measurements at the centre and representative
permitted locations. Require the full uncertainty intervals within 2 percent of
intended segment ratios and 1 degree of orthogonality, with length uncertainty no
more than 0.2 mm for 40 mm targets. If these shapes do not fit or cannot be resolved,
predeclare smaller targets and appropriate uncertainty before acquisition; record
insufficient evidence rather than loosening failed tolerances. A metric correction
requires separate calibration and held-out shapes/locations. Overlay agreement,
software geometry and physical likeness remain distinct evidence classes.

### Retained candidates, labels and realized drawings

DS-02 replaces session-only keep/rating collections with one durable candidate
identity and explicit retention reasons. The four qualifying events are shortlist,
any 1–5 rating, successful Show on Plotter acceptance and physical attempt. Completed
renders, Random, More like this, slider updates and browsing do not qualify alone.
Retain a source once and reference owned assets from candidates; never rely on a
recent-photo entry that can disappear. A retained child's parent ID/hash and recipe
metadata may describe ancestry without preserving full unqualified ancestors.

Store immutable rating revisions and selected scope, not just the latest score.
Each label pins what was shown: candidate, source/crop, preview/render revision,
displayed drawing height/scale, marker-width estimate/material revision and
prompt/objective/scope. Identical vectors displayed at different ink widths are
different evaluation contexts. Prefer the shared actual-scale/material projection;
nominal unmeasured profiles remain labeled estimated. Later material measurements
must not silently reinterpret an old rating's presentation.
Shortlist/projection/plot are retention events, not aesthetic labels. A 1/5 example
is as durably retained as a 5/5 example. Explicit source/candidate deletion updates
future eligible datasets; past manifests retain reproducible identities and honest
tombstone/missing-asset status when payload deletion prevents rerunning them. Do not
silently erase qualified records to satisfy former session count/byte limits.
Background persistence publishes pending/saved/failed states without losing the
current work. Crash-safe asset installation and index association must prevent
references to unwritten blobs and recover or identify interrupted saves.

DS-06 extends `DrawingRunEvidenceStore` and its port. Add the full source
`DrawingProgram` payload and reuse the full `DrawingPlacement` already owned by
the archived `ExecutionPlanRevision`/`DrawingExecutionPlan`; do not introduce a
second placement owner. Preserve that exact plan and reconstructable
calibration/model/registration payloads or durably owned assets, not only hashes.
Associate candidate, material revision, mounting/contact, actuation, feed and paper
with each attempt. Stage intent and baseline assets before ink dispatch, then seal
the existing immutable terminal record. Restart classifies interrupted attempts
honestly; it never authorizes replay. Preserve partial/failure/controller/observation
outcomes and available raw terminal frames, even where comparison is unavailable.

Current baseline positioning uses the last drawing endpoint so baseline and result
share a pose. Replace it with an explicit observation plan, not a post-only jog.
Prefer one reachable pen-up pose clearing the drawing region; baseline and result
use that same pose. Verify visible coverage rather than claiming that choosing a
pose guarantees it. If no single view covers the region, use bounded matched
baseline/result views, registration transforms, per-view occlusion masks and a
composite with per-pixel source provenance. Retain raw originals and derivation
versions. Unseen regions remain unknown. Stop, unsafe/ambiguous motion or failed
execution never triggers automatic repositioning for photography; preserve the
available view and explicit missing-coverage reason.

### Measured material behavior at actual drawing size

DS-05 owns a versioned replaceable material profile, separate from machine
kinematics but linked to existing tool assembly, mounting, contact plane, paper,
speed, actuation and calibration applicability. Nominal width remains distinguishable
from measured effective deposited width, its spread, directional dependence and
uncertainty. Profile replacement must not manufacture unchanged physical tip pose.

Measure isolated straight Drawing Border interiors and the existing 2 mm-radius,
16-chord calibration marks. Use both ink edges, perpendicular to observed paths;
exclude corners/vertices, pooling, crossings and occluded areas. For a resolved
approximately uniform ring, half the outer-minus-inner diameter is a useful
estimate, not an assumption that the commanded circle was realized exactly. Use
the actual polygon/observed geometry and calibrated local metric/Jacobian. A single
average pixels-per-mm conversion is inadequate for directional distortion. Filled
centers, merged ink or insufficient image resolution yield bounds or unavailable
estimates. Predeclare uncertainty and tolerance from camera/geometry resolution;
do not infer physical width accuracy from an ideal-circle fixture alone.

The profile must change production hatch spacing, clear gaps, retained detail and
preview at the accepted placement scale. Re-evaluate final-size feasibility after
placement changes. When geometry changes, produce a new candidate/plan revision
with visible provenance; never silently rewrite a rated candidate, active plan or
historic drawing. Validate with known-width synthetic images and independently
measured physical widths under stated paper/contact/speed conditions.

### Broad exploration, semantic Big Head and operational training

DS-03 makes broad family sampling explicit and balanced, giving contour, tonal
contour and clean-line recipes prominent representation and testing declared family
weights. Hatching remains a deliberate available component. Local More like this
keeps source/crop/family/head fixed and varies bounded relevant tone/line parameters;
parent/back/branch navigation restores exact configurations. Its action alone does
not retain candidates. Gallery shortlist and rating are intentional retention paths.

DS-04 introduces versioned face-local landmark analysis and smooth semantic warp:
taller/wider forehead, larger eyes and supported lateral/ear regions, a transition
through the nose, and protected mouth/chin aspect and identity structure. Ear or
forehead anatomy may require estimation beyond available landmarks; absent support
must be explicit. Handle roll and frontal/three-quarter/profile support deliberately.
Require finite bounded displacement, positive Jacobian/no foldovers, controlled
edge behavior and no unintended clipping. Compare multi-pose likeness against the
previous transform. Downstream placement preserves these intentional proportions.

The first production learner is a native, style-scoped ordinal preference model
and proposal/reranking policy over the deterministic renderer and semantic Big Head
parameters. It learns algorithm configuration; it does not claim neural line
extraction or diffusion RL. Parameter exploration has precedent in
[Sequential Gallery](https://koyama.xyz/project/sequential_gallery/); ordinal
preference learning has precedent in
[Chu and Ghahramani](https://www.jmlr.org/papers/v6/chu05a.html). These references
motivate the approach; the ordinal paper is not a claim that it implements our
specific proposed logistic model.

Initial model: `u(c) = theta^T phi(c)`, regularized ordinal-logistic negative
log-likelihood for 1–5 labels with four ordered thresholds. Use a small normalized
feature set of active recipe/warp parameters, source context and render descriptors,
plus limited quadratic terms. Score a seeded bounded proposal pool with the fitted
model, retain explicit diversity/exploration, and route selected recipes through
the real producer. Proposal-parameter fitting may follow measured results inside
DS-07; hardcoded local variation cannot substitute for a trained policy.

A named training scope has stable ID/name, objective, allowed families, active
parameter mask, frozen parameters and model lineage. Train Big Head holds source,
crop and line style fixed while varying semantic warp. Ordinary More like this
holds head geometry fixed. Show Train/Update Style, prior/current comparison,
checkpoint activation and rollback. Checkpoint changes affect future generation,
never an active physical plan. Screen aesthetic and physical-realization ratings
are different typed objectives. Do not create pseudo-pairs across unrelated source
images, infer negative scores from unselected variants, or convert retention signals
into labels. Label scarcity is explicit prior/limited-evidence behavior.

Freeze dataset snapshots with candidate IDs, exact label revisions, feature schema,
analysis versions and split identities. Group holdouts by source plus capture
session and branch ancestry; never split sibling variants randomly across train
and test. Retain weights, ordered thresholds, normalization, optimizer/configuration,
seed, dataset hash, parent checkpoint and renderer/warp lineage. Define numerical,
degenerate-data and cancellation behavior; corrupted/missing checkpoints leave the
prior usable. Rerating or deletion changes future datasets while past manifests
retain exact identity and honest asset availability.

DS-07 must demonstrate durable labels -> fitted checkpoint -> activation -> changed
production generation -> held-out evaluation -> restart -> rollback. A synthetic
known-preference dataset must change production sampled rankings with finite,
deterministic weights. Real held-out loss/within-source ordering and human
before/after likeness are separate evidence. Insufficient real data cannot produce
a fabricated generalization pass or total quality-complete status.

Continued fitting is required: reload a completed checkpoint, incorporate new or
revised labels in the same scope, fit an updated frozen dataset and persist a child
checkpoint with exact parent lineage. Declare whether initialization uses the
parent's weights/thresholds as a warm start or a deterministic full refit, and
whether optimizer state is restored or reset; retain those semantics in the update
manifest. Validate loaded parent checkpoint, feature/normalization/renderer schemas
and scope compatibility before update; incompatible inputs require explicit
versioned migration or a declared compatible full refit, never silent reuse.
Demonstrate
activation, prior/current comparison and rollback after the update. Cancelled or
interrupted updates leave the previous completed checkpoint active; retry starts
from the declared completed checkpoint and dataset. Mid-iteration recovery is not
required and must not be implied by restart support.

A pretrained [Informative Drawings](https://carolineec.github.io/informative_drawings/)
or [APDrawingGAN](https://github.com/yiranran/APDrawingGAN) producer is an optional
later upgrade through the same `DrawingProgram` producer boundary, with vector
conversion and physical evaluation. [Diffusion-DPO](https://arxiv.org/abs/2311.12908)
concerns adapting a pretrained diffusion generator and does not describe this first
native learner. Optional backbone work is not a reason to defer operational
training, durable evidence or labeled Big Head scope in this campaign.

### Studio composition and evidence gates

DS-08 preserves useful controls in this order: capture/import and photo navigation;
families/Random/More like this; adjustments and preview; shortlist/rating/gallery
and training; projection/placement/material setup; paper; Draw at the bottom. Keep
Stop and active status reachable. Gallery items recover exact candidate content,
retention reasons, training scope and linked physical attempts/result images.
Explain screen-sketch ratings separately from physical realization. Training status
states whether a checkpoint is active, pending or limited by evidence without
publishing camera-frame updates across operator controls.

| Gate | Required retained acceptance evidence |
| --- | --- |
| G01 Geometry | Reproduced failing fixture, first-transform diagnosis, exact input/vertex/transform hashes, basis and segment-ratio assertions, all primitive/raster/rotation/border cases, serialize/hash/invalidation checks, and a predeclared physical-metric protocol. Checkbox-only and uniform-scale assertions do not pass. |
| G02 Persistence | Restart/round-trip identity; each qualifying trigger and nonqualifying browse stress case; candidate deduplication with distinct label presentation contexts, any rating including 1, label history, unqualified ancestors, photo eviction, crash/partial-write/corruption/deletion and disk-failure behavior; owned payload integrity and no qualified FIFO loss. |
| G03 Exploration | Deterministic broad-family distribution under declared weights; source/family/head invariants for local proposals; exact parent/back/branch recovery; immutable previous candidates; no retention from Random/More like this alone. |
| G04 Big Head | Retained source/analysis/landmark/warp revisions; frontal/rolled/three-quarter/profile fixtures; feature-region displacement and protected lower-face ratios; bounded Jacobian/clipping tests; blind paired likeness review with unavailable poses explicit. |
| G05 Materials | Known-width synthetic images, direction/blur/pooling/occlusion/filled-hole rejection or bounds, geometry-aware uncertainty; independent physical measurements; profile applicability and final-placement spacing/gap/detail/preview correspondence. |
| G06 Realization | Exact candidate/program/placement/plan/calibration/media linkage; pre-dispatch staging and crash recovery; complete/partial/cancelled/failed cases; matched poses, source/frame integrity, raw/composite/mask provenance, unknown coverage, no motion after Stop and no automatic redraw. |
| G07 Trainability | Frozen grouped dataset and numerical configuration; deterministic finite fit; synthetic preference changes real generation; real grouped holdout metrics and human comparison; compatible parent/schema reload then continued fitting with new/revised scoped labels, declared warm-start/full-refit and optimizer semantics, and child lineage; activate/compare/rollback; interrupted update preserves previous completed active checkpoint and retries from declared completed checkpoint/dataset; corruption/degenerate-data behavior and immutable historic manifests. |
| G08 Native workflow | Actual native gallery, keyboard/source/style/branch navigation, rating scope, Train/Update/compare/activate/rollback, resize/scroll and bottom paper/Draw; persistence feedback and Stop reachable; high-rate preview remains local. Offscreen snapshots supplement rather than replace interaction evidence. |
| G09 Integration | Stable-source focused and integrated suites, complete cross-feature journey, app/source/build hash binding, fresh independent full requirement assessment and repaired findings, truthful as-built docs/evidence, clean authoritative target and Blackdog receipts. |
| G10 Attended closure | Authorized run binding source, plan, material, calibration and app; independently measured physical aspect/orthogonality and width; actual unobstructed/covered drawing images and realized-feature comparison; source-grouped human likeness/training comparisons and explicit failures/unknowns. |

Before final evaluation, the coordinator freezes dataset/split IDs, test scenes,
numeric tolerances and metrics, including physical ratio/angular/width uncertainty
and held-out ordinal loss/within-source ordering. These must reflect calibrated
camera/geometry resolution and independent measurement capability. Tolerances may
not be loosened after failure to declare success. If the setup cannot resolve the
declared physical tolerance, record insufficient evidence and improve measurement.

### Coordinator execution and aggregate completion

Executing this named campaign assigns the coordinator all DS rows, not just the
first task. After each individual landing, continue into the next dependency-ready
authorized software task without requiring the operator to reissue the remaining
rows. Preserve this register, accepted receipts, leases and next actions across
context compaction, worker retasks and coordinator resumption. Actual external or
attended-authorization blockers stop only dependent work; advance independent
authorized rows meanwhile. The present planning task completes by landing the plan
and routed documentation; it does not execute or complete the PENDING DS rows.

Delivery is incremental to local `main`, task by task. Start each new Blackdog
task from the primary `/Users/bullard/Projects/AdaptivePlotter` checkout on `main`
and verify that its recorded `target_branch` is `main`. A coordinator launched in
another linked worktree must use that primary checkout as the task entrypoint;
do not silently deliver to the linked branch or manually rewrite a recorded target.
Resolve any target/claim mismatch through the existing Blackdog lifecycle.

DS-01 is the first user-testable delivery. Land its coherent, reviewed correction
as soon as its applicable software and build gates pass, with physical metric and
attended acceptance still explicitly pending where unmeasured. Do not withhold it
for the learner, the final UI integration, or aggregate DS-09/DS-10 completion.
Freeze C1 and any other contract actually needed for that correction; unrelated
C2–C4 design must not delay this first delivery. A speculative axis multiplier,
diagnostic-only patch or checkbox alone is not the promised aspect-ratio fix.

Apply the same release discipline to subsequent dependency-ready tasks: integrate
and validate a usable increment, review its changed requirements/consumers, land
and finalize through Blackdog, then continue from the advanced `main`. A DS row may
need multiple independently coherent landings; record each commit without marking
the whole row complete prematurely. The full R01–R36 critic and integrated journey
remain aggregate obligations, not prerequisites for every earlier release.

For each user-facing delivery, stage an immutable signed test bundle from the exact
landed source with source/build identity and validation receipts. Preserve prior
test bundles and the running user's app/captures; use isolated staging and serialize
builds. Report the `main` commit, bundle path, what is ready to test, a short test
procedure and remaining evidence limits. A Git landing does not update the running
binary. Obtain authorization before replacing/restarting that live session, and
continue independent implementation while the operator tests or a switchover is
pending. Consume test feedback as campaign input and prioritize confirmed defects
in the delivered slice without abandoning the remaining task register.

Reviews have fixed scope and a one-pass limit, not an arbitrary time limit. Each
increment gets one independent review of its diff, directly affected consumers, requirement IDs and
existing validation receipts. At final DS-09 acceptance, allow one cross-feature
R01–R36 completeness review.
Each fresh critic gets exactly one pass to label findings: no critic recheck or
second review of repairs. Earlier accepted slices are reopened only for concrete
integration evidence, not a repeat of their original reviews.

The coordinator supplies the frozen candidate and explicit scope.
Reviewers return a compact ACCEPT, RETASK or BLOCKED with
finding IDs, severity, affected requirement/files, evidence and coverage gaps.
They do not run duplicate builds or full test suites, widen into repository audits,
or introduce speculative redesigns.
Reuse retained validation receipts; the coordinator owns necessary new validation.
A new commit, replacement critic or renamed task does not reset the one-pass limit
for the same work. Once the critic reports, the coordinator owns triage, worker
retasking, repair integration and direct verification through targeted checks and
tests. Record each finding's disposition and verification evidence without sending
repairs back to a critic or commissioning another review of the same work;
if a blocking defect or material coverage gap remains, keep the affected release
pending with its exact issue, owner and next action and advance independent work.
Finishing the critic's pass never converts an unresolved finding into a pass.

1. Recheck current target, relevant docs and Blackdog claims. Enter each logical
   implementation landing through structured `task begin`, with exact request and
   composed prompt replay artifacts. Use only its returned task workspace and
   authoritative target. Follow every typed `next_action` exactly; never infer a
   recovery/landing action, bypass an owner claim, or select unrelated migration work.
2. Freeze the C1–C4 contracts needed by the current slice and issue bounded worker
   leases with requirement IDs, files, base identity, expected artifacts, exclusions
   and acceptance evidence.
   At most three workers overlap. Serialize shared schema/runtime/composition edits
   and SwiftPM validation. Keep the coordinator's ledger current without promoting
   pending native/physical evidence from software receipts.
3. Require each submission to report requirement IDs, exact files/base/source
   hashes, contract changes, actual validation commands/results/artifact paths and
   open issues. Inspect its diff and consumer paths. Reject incomplete submissions
   or unsupported claims and return them for repair; an agent's final message is not
   acceptance. Resolve dependencies in the integrated tree, not just worker fixtures.
4. Run narrow meaningful checks per slice, then stable integrated quick/journey,
   strict concurrency/warnings-as-errors, app and documentation checks as applicable.
   Use existing repo commands and retain their actual logs. Do not run independent
   full builds per worker against changing sources. Run `git diff --check` at the
   final candidate. Native/runtime checks must use the exact retained artifact.
5. Review each increment before its landing. At aggregate DS-09 acceptance, assign
   one fresh nonauthor critic the entire R01–R36 register and stable candidate,
   including production consumers, failure paths and the complete journey. Apply
   the fixed scope and one-pass rule above. The coordinator retasks
   workers for actionable gaps and verifies their repairs directly. Record every
   disposition; incomplete review coverage or unresolved blocking
   findings remain explicit rather than causing an unbounded review cycle.
6. Validate the complete journey: create -> branch -> rate in named scope -> train ->
   activate changed generation -> restart/reload compatible checkpoint -> add/revise
   scoped labels -> continue fitting with declared warm-start/full-refit and
   optimizer semantics -> persist/activate child checkpoint -> compare and rollback
   -> recover retained candidate
   -> proportional projection -> measured material/final scale -> Draw -> durable raw
   realization -> comparison linked back to candidate, checkpoint and scoped labels.
   Verify old/rated/active drawings remain immutable at every step.
7. Update Product Contract/Architecture only for delivered behavior and Current
   Evidence only with actual receipts. Land and finalize through Blackdog as the
   sole coordinator. Recheck authoritative target branch, source/build identity and
   clean state; do not leave uncommitted work or silently unowned follow-ups.
8. Arrange DS-10 with the operator at the attended gate. This planning task changes
   no runtime/hardware state and does not restart the active app. Campaign execution
   authorization permits controlled native software checks that preserve the live
   user session and captures. Obtain explicit approval when a check requires
   restarting/replacing that session, or when attended physical motion requires
   authorization; do not add a separate approval gate to ordinary native software
   checks. Automated/replay/controller evidence never proves camera alignment,
   pen/paper contact, attended clicks or observed ink.

Aggregate completion requires every R01–R36 mapping, every dependency and every
applicable G01–G10 receipt to be reviewed, with no unresolved actionable defect.
Report software delivered, native verified, learned-quality evidence and attended
physical realization separately. An operational learner with insufficient real
holdouts is operational but not quality-proven; software-ready geometry with no
attended metric check does not close the reported physical stretch. Explicitly
unavailable evidence remains pending, with an exact remaining action and owner;
it cannot be relabeled complete to finish the campaign.

## Pen readiness beside position recovery, 2026-09-12

Task `task-d431b9891cb949d28072588618977a00` is a bounded correction to explicit
motion authorization and existing manual Pen Up composition, plus adjacent
position-recovery controls. It introduces no new episode owner or migration wave.
The combined source preserves the independently landed portrait correction at
`19bb6a68b955c249c88e0a173027038add221db5`. Default warnings-as-errors compilation,
strict quick validation (1067 tests, five existing opt-in skips) and strict journey
validation (10 tests) and strict signed-debug bundle validation passed together.
The separate unlaunched candidate matches all 180 source/build inputs and passed
stable-local signature verification. One full independent nonauthor assessment
passed all 74 register items with no actionable P0–P3 finding or residual issue;
no repair pass or delta was needed. Final integrated documentation checks passed
in 36.016895 seconds, including contracts and Python suites of 13, 9 and 39 tests.
Local Blackdog landing remains coordinator-owned. Current behavior belongs to Product Contract and
Architecture; exact validation and remaining gates belong to
[Current Evidence](CURRENT_EVIDENCE.md#pen-readiness-beside-position-recovery-2026-09-12).
Final delivery receipts belong to Blackdog task history and the coordinator's report.

## Saved Learning physical-position correction, 2026-09-12

Task `task-c94d61ea72b34c8e9e1500d25f97900a` is a bounded correction to the
existing accepted-checkpoint, tip-calibration, Boundary and Drawing Run owners.
It retains accepted Learning while requiring current visual position after
restoration or controller continuity loss, including gravity movement that leaves
MPos unchanged. Supported translation recovery publishes coherent geometry;
Boundary admission and pretravel checks retain physical applicability, and compact
placement identities preserve the UI compiler boundary without weakening exact
intent/frame validation. No new motion runner, Learning exercise, migration wave
or attended VAL-01 execution is selected.

The pre-assessment candidate passed strict quick tests (1035, five opt-in skips),
strict journey tests (10), default warnings-as-errors and signed debug validation.
Before assessment began, a final prefix correction retained camera position
recovery after a contact-plane change invalidated tip calibration but retained the
machine/cap map. The earlier signed candidate is superseded for delivery. The
updated default warnings-as-errors build passed, and the final-source strict
quick suite passed 1036 tests with five existing opt-in skips; the final-source
strict journey suite passed 10 tests. That signed candidate remains staged and
unlaunched. The sole full independent assessment found F-01/P2 (busy connected
states mistaken for physical continuity loss) and F-02/P3 (generic recovery
blocker copy), requiring one consolidated repair. Repaired default compilation
and a separately staged replacement signed debug artifact passed validation.
The focused repair regressions passed all three tests. The repaired integrated
strict quick suite passed 1039 tests with five existing opt-in skips, and the
repaired strict journey suite passed 10 tests. All repaired Swift gates passed
together. Repaired documentation contracts and Python suites of 13, 9 and 39 tests
passed in 31.203834 seconds; working and staged whitespace checks passed. After
the sole full independent assessment and consolidated repair, the same assessor's
one bounded delta closed F-01/P2 and F-02/P3 with no residual finding or new serious
defect. No implementation, validation or assessment blocker remains. Actual
results and limitations belong to
[Current Evidence](CURRENT_EVIDENCE.md#saved-learning-physical-position-correction-2026-09-12).
Native/performance and attended physical gates remain skipped to preserve the
running user session. The authoritative target branch, landed commit and cleanup
receipt belong to this task's Blackdog history and the coordinator's final delivery
report.

## Bounded paper, ordinary border, and Motion correction, 2026-09-12

Task `task-cceb274a51cd443696f191f1233ab3e4` is the explicitly authorized
corrective campaign against existing owners, not another migration wave or
attended VAL-01 selection. Its scope separates same-plane paper transients from
accepted calibration, restores compatible accepted data after active loss,
adds optional ordinary-drawing border geometry through the canonical program,
and isolates visible controller telemetry from broad semantic projection.
Prior permanent-canvas/native-pane, debug build, Pen Up, comparison-close and
Achtung behavior remain regression obligations. Voice stays parked.

The durable behavior belongs to Product Contract, current ownership to
Architecture, and actual integrated validation/assessment/delivery to
[Current Evidence](CURRENT_EVIDENCE.md#bounded-paper-border-and-motion-correction-2026-09-12).
No historical package completion or physical evidence is changed by this
correction. The integrated focused 144-test, quick 1021-test and journey 10-test
strict runs, signed debug validation, documentation contracts plus 13/9/39 Python
tests and whitespace checks passed. The single full independent nonauthor
assessment found one actionable P2 (F-01): failed typed Paper declarations lost
their visible refusal despite correct rollback. The consolidated repair passed
its seven-test strict Paper suite, including six failure/retry combinations.
An existing computation test was adapted to join pending Draft-to-Run publication
without reducing no-rebuild assertions; the whole 14-test diagnostics suite
passed. Final repaired strict quick1021 and journey10 suites passed with the
same five existing opt-in skips in quick. The final repaired signed-debug
artifact passed strict bundle/signature validation and is separately staged;
Current Evidence records its matching executable hash. Repaired documentation
contracts and 13/9/39 Python tests and staged whitespace checks passed. The same
nonauthor's sole bounded delta closed F-01 and found no residual P0/P1/P2/P3
finding or introduced serious defect. The validated correction has no remaining
implementation, validation or assessment blocker. Local Blackdog landing and
finalization receipts are recorded by the coordinator in
`task-cceb274a51cd443696f191f1233ab3e4` history and the final delivery report;
this ledger does not assert a landing before that receipt exists.

## Permanent canvas and native control panes, 2026-09-12

This user-approved product correction supersedes the layout and diagnostic
presentation portions of the September 8 workbench correction below. It does
not reopen historical episode migration packages or change their evidence.

The workbench keeps its video/portrait/simulation canvas permanently in the main
window. The canvas has no close control or View-menu visibility command. Five
optional control panes are Guided Learning, Video Settings, Motion, Active
Learning, and Portrait Studio. Native View-menu Show/Hide commands and
Command-Option-1 through Command-Option-5 control their visibility. Opening fills
right, left, lower-right, then lower-left. A side with one pane uses its full
height; two panes share that side through a native draggable divider. Closing a
pane preserves sibling slots; an empty side returns its space to the canvas.
A fifth opening replaces the oldest visible pane while retaining its workflow
state. Layout preferences migrate from the former dock model, and native split
views save divider sizes. There is no full-width bottom area, position menu,
move icon, automatic workflow reset, or closable Video panel.

The session toolbar owns controller selection, amber Connect/Disconnect and
Enable/Disable Motion actions, the diagnostic export tool, and the far-right
red Achtung! control. Existing typed Stop requests and Escape routing are
preserved; passive status badges and the separate command strip are removed.
Voice remains unchanged and its input/output split is deferred in the Roadmap.

Video Settings contains source choice, zoom, overlays, analysis cadence and
region controls. Showing or hiding control panes does not select a camera;
explicit camera controls and workflow-title actions retain projected requests.
The permanent canvas uses the existing frame/overlay leaf and portrait renderer.
With no available image it displays an identified simulator preview, without
switching execution environment, consuming simulator faults, publishing an
observation, or altering Learning. Explicit frozen evidence and available
portrait photos remain displayable. These presentation changes never establish
camera or physical ink evidence.

Diagnostics becomes a toolbar-triggered background JSON file export of the same
bounded current-owner snapshot. Acceptance requires slot order/close/replacement
and migration tests, exact Stop preservation, return-only simulator fallback,
export completion/failure/responsiveness, native View commands and permanent
canvas visibility at 1000/1600-point widths, and unchanged preview isolation.
The native-workbench v2 scenario checks all 20 control/slot combinations at both
widths, eight bitmaps, actual body scrolling and menu/close/resize input. Runtime
and native evidence remain separate; Current Evidence records executed results.

## Decision

Keep one AdaptivePlotter application and the existing controller, camera,
Vision, planning, and evidence authorities. Add a headless episode kernel and
runtime as internal SwiftPM targets, make Plotter their first concrete domain,
and migrate complete workflows by replacement. A cutover is incomplete until
the old action, state, guard, task, effect, and test-fixture path is deleted.

Do not create a second production application or publish a general SDK before
the kernel has survived the three representative Plotter slices, the pilot
gate, and a complete Learning Path migration. A separate SDK remains a later
packaging decision requiring a genuinely distinct second client.

## Workbench and portrait completion correction, 2026-09-08

Historical correction ledger: the panel placement, canvas visibility, menu and
native-gate descriptions in this section were superseded by the September 12
permanent-canvas correction above. They document that earlier candidate and its
validation limits; do not use its left/bottom/right workflow as current guidance.


The accepted product correction is tracked in Blackdog task
`task-26f65c0e4e7b4a3b9d445b26c59c86f0`. This section is its sole implementation
plan and progress matrix. It does not reopen, replace, or claim completion of
the historical episode migration packages below. **Full strict run 31 passed:
997 Swift functions passed, five opt-in checks skipped, zero failures; release,
signing, launcher, bundle, documentation, repository and diff checks passed.
Independent critic 9 found no remaining blocking software issues.** The software
implementation is accepted; actual native and physical checks remain unverified
because the desktop is locked. Final documentation and delivery receipts are
recorded separately from Git landing.
[Current Evidence](CURRENT_EVIDENCE.md) records exact candidates and distinguishes
software proof from performed native/physical validation and landing.

The workbench has five independently visible panels: **Guided Learning**,
**Video**, **Motion**, **Active Learning**, and **Portrait Studio**. Every panel,
including the actual Video canvas, can occupy the left, bottom, or right region;
regions support multiple panels with usable resizing and scrolling. Placement
and visibility persist. Defaults are Guided Learning left, Video right, and
Motion bottom. The Panels menu exposes all five; Video Settings is a concise
accessory inside Video, not a sixth workflow panel. Active Learning and Portrait
Studio are sibling panels, with no modal portrait sheet or permanent central-only
camera. Stop remains in the command bar independently of panel visibility.
Selecting an already-visible Guided Learning or Active Learning title selects
the plotter camera; selecting Portrait Studio selects the face camera. Video
also offers an explicit Plotter/Portrait selector. Hiding or moving any panel
changes window preferences only, without restarting capture or hiding the target.
Guided Learning retains the existing Learning On/Off action and current state
even when Off hides exercise navigation. This neither changes accepted artifacts
nor adds a portrait acquisition or drawing-mode choice.

Opening portrait preparation selects the face camera in the shared Video panel
and stops plotter capture and automatic analysis. **Show on Plotter Video** keeps
Portrait Studio controls and the authored program, settles face capture, and
selects plotter capture in that same Video panel. Source transitions preserve
accepted Learning when the returning plotter camera has unchanged physical
optics; capture-session identity must not stand in for optical identity.

Full strict run 31 passed all 997 executed Swift functions. The retained
synchronization chain joins nested publication,
shutdown cannot create successor work, and exact returned Run terminal/progress
state survives buffered older publications. The post-drawing 30-frame test keeps
all zero-churn assertions: its diagnostic future-frame failures were corrected
with one shared pure-read fixture timeline, without changing production freshness.
Large-displacement contour, finite-width hatch, alias/ROI/cancellation and
retrospective archive regressions pass. Source-start admission captures its role
identity before Task creation, joins the existing transition drain, and cannot
overwrite a newer role choice. Held interleaving tests prove exact publication
and maximum one active capture. Remaining iterative-fit coverage limits and
physical-ink accuracy remain separate.

Native 20 reached a real finished-launching app but no active/key/main window
or usable controls. Native 22 verified the exact regular app PID, but macOS
rejected activation. Neither posted native input or produced the six acceptance
bitmaps. Launcher logic/no-launch checks passed; activation did not. At 02:37
PDT, the console explicitly reported locked since 00:10:16 PDT, with loginwindow
owning foreground and secure input; the 11:06:55 UTC inventory still found it
locked. The user has been asked to unlock normally;
no permission or lock bypass is planned. The lock also predates native 14–16,
so their empty AX/activation failures cannot be attributed solely to SwiftPM
hosting, although the missing AppKit event loop is independently a code fact.

Actual checks remain in the existing signed-app native-workbench scenario with
simulated startup: all 15 placements at both widths, actual canvas/body clipping,
identified inner-wheel movement, feasible resize/hide/On-Off and six bitmaps.
Native-gate contract regressions pass through run 31; actual input coverage remains empty.
Software held-Draw Stop and physical inkless native jog/Stop are distinct proofs;
no native click into a synthetic held Draw owner is claimed. Fresh compatible
ordinary archive evidence is still needed; holdouts cannot be relabeled. Exact
artifacts and limits are retained in [Current Evidence](CURRENT_EVIDENCE.md).

| Item | Required result and retained owners | Completion proof, including obsolete-test replacement | Progress |
| --- | --- | --- | --- |
| Saved Learning restoration | Restore the completed milestones and retained Border outcome from the accepted checkpoint. Separate current Pen pose and controller readiness from accepted training; unknown/down pose uses the existing Pen Up path without cap identification or Learning replay. Retain checkpoint, artifact/reset, Pen, and Drawing Run owners. | Production-route checkpoint reloads with unknown and down pose; all accepted milestones remain complete, exact incompatible dependencies retain their real remedy, and execution readiness resolves without restarting Exercise 1.1. Replace fixtures whose default Up pose hid this defect. | Software accepted in run 31: complete saved Unknown/Down restoration and retained milestones pass. Native On/Off and physical readiness remain unverified |
| Quiet video and controls | Keep frames and analysis in the existing video leaf. Remove frame counters, changing measurement/status/age text, overlay diagnostic cards, and control subscriptions to analysis revisions; retain stable questions, actual operation transitions, and one actionable error. Pass small settings/viewport values to controls rather than frame-bearing presentations. | Advancing active-analysis traffic changes no sibling-panel text or layout and performs no frame-buffer equality in control updates. Retain exact geometry/evidence tests; replace tests requiring diagnostic captions or frame counters to change on every frame. | Software accepted in run 31: active-analysis, 120-frame ambient and post-drawing 30-frame zero-churn cases pass, including publication/shutdown and remedy deduplication. Signed active-camera text, equality-cost and latency proof remain unverified |
| Five dockable panels | Use the existing window-local layout owner for all five panels, arbitrary left/bottom/right placement, multiple panels per region, persisted visibility/placement, resize/scroll, and the specified defaults. Replace mixed Drawing Studio navigation and the portrait sheet. | Exhaustive placement/visibility restoration across five panels and three regions, plus native resize/navigation/scroll and Stop reachability. Delete tests that require protected-pane collapse, a fixed central Video, the old menu, or modal portrait presentation. | Software accepted in run 31: persisted placement/visibility for all five panels and all three docks passes. Actual canvas/body clipping at both widths, scrolling/resize/hide/On-Off and six bitmaps remain unverified; native 20/22 reached no controls while locked |
| One selected camera | Retain existing capture and observation owners; stop and settle the old capture/analysis before starting the selected source. Preserve portrait captures and draft across navigation; returning unchanged plotter optics retains Learning. | Deterministically held stop/start and rapid source changes prove no simultaneous capture, no stale source publication, reusable capture after cancellation, and unchanged accepted Learning. Replace the portrait test that asserts plotter capture continues. | Software accepted in run 31: held lifecycle and source-admission interleavings preserve newer choices, exact publication, reusable capture, accepted Learning and maximum one active capture. Critic 9 closed the ordering finding. Actual-device switching remains unverified |
| Persistent portrait placement and Draw | Use the existing DrawingProgram, draft/planning adapter, and Drawing Run chain. Show on Plotter Video installs the retained program and fits both upright and 90-degree candidates, choosing the larger valid uniform fit with upright tie-breaking. Share fit/scale calculations; preserve manual adjustment. Persist predicted plan geometry across compatible advancing frames while measured overlays/clicks stay exact. Render availability and refusal/remedy from the existing run owner. | Portrait import/capture through projection-bound Show, fit, adjust, and Draw binds one program/placement/plan identity. Test both aspect ratios and ties, continued target visibility, changed authority, and every actual run-unavailability remedy. Replace tests that hide predicted geometry solely because the video advanced or duplicate run admission in UI. | Software accepted in run 31: production immediate Show/fit/adjust/Draw, exact identities, changed-readiness refusal and compatible-frame target persistence pass. Native and physical routes remain unverified |
| Retrospective residual use | Remove the ordinary portrait training/drawing selector. Every run retains its intended/executed/observed/residual or rejection facts through the existing archive. Later analysis references those immutable records; Active Learning assigns experimental roles internally. Reuse existing model-fitting/evidence owners and state which arbitrary-portrait residuals are identifiable. | Same portrait acquisition and run path regardless of later analysis intent; archived provenance and rejection remain inspectable. Exercise supported retrospective fitting from archived ordinary runs and clearly separate unsupported residual components. Replace tests demanding a pre-run ordinary portrait role choice. Data used for fitting cannot later be counted as untouched holdout evidence. | Software accepted in run 31: immutable ordinary archive selection/analysis, large contour accuracy, finite-width hatch and rejection/cancellation cases pass. Iteration/rank/competing-basin coverage limits remain explicit. Native record selection and actual eligible ordinary evidence remain unverified |
| Cancellation and liveness | Coalesce and cancel portrait work through its existing model, bound worker concurrency, observe cancellation in expensive stages, and settle work on source change/shutdown without tying lifetime to panel visibility. Make the existing draft mutation queue remove cancelled waiters and settle each continuation once across held persistence. No second task owner, recorder, or state authority. | Hold image analysis/vectorization, capture startup/stop, persistence, and controller settlement at real await boundaries while editing, switching, cancelling, dismissing, and invoking Stop; prove responsive acknowledgment, bounded work, current results only, exactly-once settlement, and subsequent reuse. Distinguish software held-Draw ingress/settlement from native functional controls and actual-controller native Stop; record the lack of native input into the held synthetic Draw owner explicitly. Replace sleep-based or helper-completed fixtures that bypass these paths. | Software accepted in run 31: retained worker, queue, nested publication, shutdown and source admission tests pass. Exact held-Draw acknowledgment precedes lower release and terminal publication settles once. Native Stop under actual load remains unverified; no native-held-Draw claim |
| Integrated workload, critic, and physical proof | Validate the exact signed candidate with accepted training, active plotter analysis, a dense portrait, actual visible controls, repeated camera switches, and drawing/evidence review. Coordinator assigns work and owns integration/landing; an independent critic assesses every item and residual before final completion. | Require workload prerequisites, event-to-handler-to-visible-ack timing, zero analysis-driven panel text changes, at least 20 source switches, and a sustained session. Capture a process sample on latency failure. Run affected serial software gates and exact-candidate physical workflow where observable; separately record controller, camera, clicks, motion, Pen/paper, and actual ink. Critic findings are corrected and rechecked. | Full strict run 31 passed and critic 9 found no blocking software issues. Software gate/schema requirements are accepted. Actual native placements, six images, On/Off/Stop, 20-switch/90-second camera workload and two physical portraits with ordinary residual evidence remain unverified in the locked GUI; launcher logic is not activation proof |

Implementation proceeds from restored Learning and quiet layout to exclusive
camera selection, complete placement/Draw, retrospective evidence use, and
integrated liveness verification. Disjoint source/test leases may run in parallel;
shared composition files and documentation have one writer at a time. Workers
must report changed ownership, removed obsolete paths/tests, exact commands and
results, artifact identities, and remaining limitations. Green focused tests do
not substitute for the integrated workload or independent completion assessment.
Every changed behavior requires an audit of its existing tests: remove or replace
all assertions and fixtures enforcing the superseded behavior, while retaining
unrelated valid physical-authority and evidence tests. Retrospective use includes
a working operator selection of retained ordinary/portrait runs and analysis of
their identifiable residual components; naming unsupported model components
does not excuse leaving that visible selection path unimplemented.
The coordinator integrates and reassigns corrections until the matrix is
supported by evidence, then lands through Blackdog's recorded target branch.

The signed-app probe must fail a scenario with missing accepted training,
analysis, portrait/plan, or source-switch workload instead of passing an empty
Studio. UI acknowledgment targets remain p95 at most 100 ms and maximum 250 ms;
measure native event delivery, handler entry, and visible acknowledgment
separately from long operation completion. MainActor scheduling latency alone
does not establish click responsiveness. Release builds remain useful packaging,
not evidence that the code-level churn or liveness defects are corrected.

Physical acceptance uses the exact signed candidate: load the existing accepted
training, establish operational readiness, prepare a portrait, show the target on
the plotter, draw and inspect ink/residuals, then complete a distinct nonoverlapping
second run. The explicit physical harness composes ordinary owners and native
controls, stages exact candidate/run/plan inspection, preserves the first record
and exact frame pair before changing plans, and retains the app/evidence on
every outcome. Its continuation marker is test staging, not a new application
admission or operator-approval rule. Exercise
Guided Learning and Stop under camera load separately while preserving the
existing durable checkpoint until a replacement is accepted. The user has
authorized machine testing in this task; software, simulation, controller
completion, or a live camera alone cannot be labeled observed physical ink or
complete attended Learning. Unobservable or unperformed portions remain explicit
residual work. No new interlock, admission rule, or operator confirmation step is
part of this correction; preserve the existing physical/evidence owners and fix
their defects, duplicated decisions, obsolete UI, and liveness failures.

## Vocabulary authority

[Episode Architecture Vocabulary](EPISODE_ARCHITECTURE_VOCABULARY.md) is the
sole definition source for target names and relationships. This plan uses those
exact names and does not restate or alias them. Exact current-code identifiers
are allowed only when describing as-built owners or their named deletion.

## Target packages

```text
EpisodeCore
  EpisodeGoal, EpisodeDefinition<Intent>, EpisodeManifest<DomainManifest>,
  IntentDecision,
  EpisodeEvent, reducer and EpisodeJournal schemas
  Foundation only; no Plotter, device, persistence, or UI imports

EpisodeRuntime -> EpisodeCore
  serialized store, journal/replay, internal EffectPermit
  effect lanes, operation registry, cancellation and lifetime settlement

PlotterEpisodeModel -> EpisodeCore + PlotterModel
  Plotter bindings for definition/manifest plus intent/state/event/effect/result
  scoped semantic rules, reducer, evidence/assessment values, projections

PlotterEpisodeRuntime
  -> EpisodeRuntime + PlotterEpisodeModel + PlotterRuntime
  LIVE and SIMULATED capability providers and effect runners
  controller/camera recording, replay, and artifact adapters

PlotterUI -> PlotterEpisodeModel
  immutable projections and one typed intent sink; no effect ports

PlotterApp
  composition root during and after migration
```

`PlotterModel`, `PlotterRuntime`, and `PlotterTestSupport` remain current
authorities until an explicit work package moves a responsibility. Temporary
bridges must name their deletion package and may not become stable APIs.

## Central semantic ingress

Exactly one public application ingress exists for each rendered semantic
action: the production `PlotterApplicationRuntime` is the sole
`PlotterUIIntentSink` conformer, validates exact projection membership plus
UI/runtime revisions, and delegates to the already-authoritative typed feature
runtime. `PlotterIntentGateway` remains an internal typed evaluator used by
the point-selection and manual-motion runtimes; EA-11C does not add a redundant
root gateway or reevaluate a request after the public sink has accepted its
exact projection binding. Local pane, window, and viewport-only state remains
in small UI reducers unless it changes evidence or domain authority.

That one sink is not enough when the projection has already erased meaning.
Every effect-bearing Learning control must carry its model-owned typed item,
action, request, identity, and current availability from `PlotterEpisodeModel`
through immutable `PlotterUI` projection to the owning feature runtime. The App
may not recompile a display ID into semantic meaning, recover a typed action
from an opaque ID-to-action dictionary, maintain an application-side semantic
registry, or add an opaque intent case that only another App map can decode. An
enabled control must contain its exact current request; submission cannot
silently return because a request, registry entry, or availability is nil.

`PlotterIntentGateway` is a thin feature-runtime evaluation façade. It owns no feature rules,
reducer state, evidence acceptance, operation lanes, tasks, device ports, or
persistence. Its only responsibilities are request identity, current-fact
acquisition, evaluation, and delegation within the runtime that composes it.
Public exclusivity means one projection-bound application submission route. It does
not collapse the named point-selection, manual-motion, Pen Interaction,
Boundary, calibration, Drawing, controller-session, observation, speech, or
artifact runtimes into one dispatcher. Those runtimes remain the typed internal
owners of their feature rules, tasks, exact Stop capabilities, and settlement.

`PlotterIntent` is an exhaustive root sum with scoped cases such as session,
observation, point selection, manual motion, drawing, Learning, and evidence.
The root evaluator delegates to pure feature rule sets and has no `default`.
Rule sets may evaluate named semantic requirements. They cannot mutate state,
call ports, issue execution permission, construct effects, or accept evidence.

The normal submission order is:

1. reserve request identity before suspension;
2. acquire versioned `CapabilityFact` values;
3. recheck state and manifest revisions;
4. produce the scoped `IntentDecision`;
5. append a typed accepted or refused event;
6. reduce the committed `EpisodeEvent` into state and typed effects;
7. register effect identity and lane, then mint its internal one-shot
   `EffectPermit`;
8. record effect start before external invocation;
9. execute outside `MainActor` through the existing environment owner;
10. validate the `EffectResult` identity and revisions, commit the corresponding
    `EpisodeEvent`, and reduce it.

Reduction of any committed `EpisodeEvent` may emit zero or more typed successor
effects. Each successor records the triggering event as causation and repeats
steps 7–10. A multi-effect workflow therefore advances through committed result
events; it never uses a callback mutation or manufactures another intent.

The UI uses the same pure evaluator to display `IntentAvailability`, but submission
always reevaluates current state. Presentation values can never be supplied as
authorization.

## Operation ownership and safety priority

For each migrated effect, the one owning typed runtime uses the
`PlotterOperationRegistry` mechanism for application-level effect identity,
lanes, `StopCapability`, cancellation request, original task/handle, and
terminal disposition. Every unmigrated effect retains exactly one current
operation owner declared by `EA-01`; a logical operation can never be
registered in both. `EA-11C` gives the application root one shared residual
adapter backed directly by the package `PlotterOperationRegistry` for the
remaining root-owned operations. It forbids a second ad-hoc task registry,
closure bag, or workspace Stop owner. This does not mean one monolithic registry
instance owns the internal coordination of every feature runtime: their named
registries, tasks, handles, and Stop lanes remain distinct. `GATE-02` only
verifies that landed topology.
It supports at least one exclusive machine lane, one exclusive
exact-workflow capture/Vision lane, bounded background analysis, and serialized
durable append where required. `RunInterpreter` remains the logical machine
operation owner below it.

Cancellation is request, exact-owner validation, one latched cancel request,
owner observation, original-owner await, terminal disposition, and capability
retirement. A stale capability cannot stop a successor. A migrated operator
Stop first latches that exact owner without suspension, durably publishes
`requested`, invokes the original handle once, durably publishes `observed`,
enters settlement, durably publishes `settling`, and only then awaits the
original owner result. Failure to append one of those semantic stages retains
the exact owner and exposes a typed stage plus recovery capability; it cannot
issue a second cancellation, fabricate settlement, retire the owner, or admit a
successor.

Normal new effects require committed accepted/start history before external
invocation. Shutdown remains the narrow lifetime-priority path: it may only
close admission, cancel, or settle existing work; it latches exact owners before
suspension, issues every cancellation without waiting for journal I/O, and can
never start or repeat a physical effect. Journal failure may leave shutdown
publication incomplete but cannot prevent the underlying cancellation. An
operator Stop instead follows the durable staged contract above so the public
episode state never claims a cancellation phase that has not occurred.

## Guard ownership

Every guard has exactly one owner within its layer:

| Layer | Owner | Examples |
| --- | --- | --- |
| semantic workflow | scoped evaluator | phase, episode owner, prerequisite, no-redraw, plan revision |
| runtime coordination | store and operation registry | lane occupancy, deduplication, cancellation, stale result, terminality |
| fresh physical safety | `MachineController` and `RunInterpreter` | connection, Alarm/Pn/Idle/MPos, Motion, feed, pen, wire settlement |
| evidence and provenance | existing typed evidence authorities | frame/config/hash, pose, applicability, algorithm/model revision |
| presentation | projector or local UI reducer | layout, label, visibility, exact-frame display |
| lifetime priority | runtime Stop/shutdown route | close admission, cancel/await owner, reject stale commits |

Semantic rules consume versioned device/evidence facts. They do not recreate
the controller's safety algorithm or the evidence authority's applicability
algorithm. Rechecking across layers is intentional only when the question and
owner differ: current semantic readiness versus fresh safety immediately before
I/O.

## Non-negotiable observability

Observability is product behavior, not optional debug instrumentation.

1. Every refused `PlotterIntent` exposes a typed requirement ID, authoritative
   owner, compared source/state revisions, concise operator remedy, and the
   intent request identity. No effect-bearing control silently ignores a click.
2. Every active effect exposes episode/intent/effect identity, lane, environment,
   owning subsystem, phase, start time, last attributable progress time, the
   result currently awaited, declared deadline when one exists, cancellation
   availability and phase, and eventual terminal disposition.
3. Progress is evidence of an attributable `EpisodeEvent`, not a fabricated heartbeat.
   The UI distinguishes `waiting`, `progressing`, `cancelling`, `settling`,
   `suspectedStall`, and terminal state without claiming a deadlock merely from
   elapsed time.
4. Every reachable nonterminal state has at least one admissible intent, an
   explicitly owned wait/progress state, an exact refusal with remedy, or an
   owner-bound Stop/cancel. A silent actionless state fails tests.
5. Runtime state revision and UI projection revision/timestamps are visible and
   comparable. Runtime progress with a stale UI projection identifies a
   presentation/MainActor problem rather than a controller deadlock.
6. Journal, controller transcript, camera lifecycle, and structured diagnostic
   recording run outside `MainActor`. If SwiftUI is starved, the last durable
   runtime state remains externally inspectable.
7. The operator can export an on-demand bounded diagnostic snapshot of existing
   Learning transitions, current owner/UI revisions, available actions, and
   refusals. Complete manifest/journal/transcript/frame archive integration is
   deferred until a concrete continuity or replay/debugging need requires it;
   no parallel event stream or full-archive Learning prerequisite is introduced.
   Sensitive frame retention remains explicit and bounded.
8. Recording failure is visible and degrades diagnostic completeness, but it
   never authorizes work, changes controller safety, manufactures evidence, or
   delays Stop/shutdown.
9. A migrated runtime exposes its durable journal artifact and exact loaded
   snapshot independently of optional recording. Terminal or Stop-stage append
   failure retains the current operation owner, the uncommitted publication
   cursor, and a typed recovery capability. Optional recording durability and
   completeness remain separate incident-source facts.

The primary UI should show the current reason, owner, progress, remedy, and Stop
without forcing the operator through a developer console. A detailed inspector
and export may carry identifiers and revisions. Structured logs and the journal
remain the fallback when the UI itself cannot render.

## Replay and simulation

The episode manifest pins definition, schemas, evaluator/reducer/build revisions,
seed, and referenced drawing, calibration, paper, camera, controller, and model
artifacts. Each event records sequence, actor/origin, causation/correlation,
intent/effect IDs, pre/post revisions, typed payload, artifact references, and a
canonical post-state digest.

Replay begins from the manifest, folds the production reducer, verifies hashes
and revisions, recomputes projection/`IntentAvailability`, and executes no effect. Every
truncated prefix is tested. A trace ending after physical effect start but before
settlement becomes possible physical effect and is never automatically resumed.

`RecordingMachineLink` records invocation and completion separately for open,
close, discard, raw writes, and timed reads, including exact chunks, parameters,
typed errors, partial counts, monotonic offsets, integrity, and completeness.
`ReplayMachineLink` supports exact replay and causality-preserving perturbation
of legal fragmentation, delay, timeout, and cancellation points.

Camera recording binds lifecycle events separately from content-addressed exact
frame artifacts. Retention is explicitly evidence-only, bounded incident ring,
or bounded diagnostic capture. Missing frame bytes remain visible and cannot
pretend to support Vision replay.

LIVE and SIMULATED implement the same effect/result vocabulary while preserving
different provenance and evidence classes. The simulator separates commanded
controller state, plant/pen truth, paper/ink truth, camera observation, and
Vision measurement. Simulation can never satisfy LIVE physical evidence.

## Same-landing deletion rule

Every migrated slice must remove or explicitly prove a remaining unmigrated
consumer for each of the following:

- old root intent/action case and dispatcher branch;
- old `...UnavailableReason` and handler guard for migrated semantics;
- old mutable workflow/workspace field;
- old task, generation, latch, and Stop/cancel owner;
- old direct controller/camera/Vision/persistence port call;
- old LIVE/SIMULATED workflow branch;
- old high-level fixture or polling helper after its last consumer;
- obsolete current documentation and tests.

A new path working beside the old path is not migration. Shadow comparison may
observe and report, but may issue no effect or authoritative durable write.

## Structural enforcement

- migrated UI targets cannot import effect runtime or see raw effect ports;
- each migrated intent has the gateway as its only public effect-bearing/domain
  mutation entry; `EA-11C` establishes global exclusivity and `GATE-02` verifies it;
- root intent switches are exhaustive without `default`;
- requirement IDs are typed and map to one declared owner;
- evaluators cannot emit effects or issue runtime permission;
- the reducer is the sole effect producer;
- the package `PlotterOperationRegistry` is the sole application-level
  operation mechanism: typed feature runtimes retain their own registry-backed
  lanes, and `EA-11C` adds exactly one shared residual root adapter backed by
  that same mechanism rather than a monolithic registry instance or ad-hoc task
  registry; `GATE-02` verifies the landed topology;
- results require matching episode/intent/effect/environment revisions;
- UI availability cannot be resubmitted as authority;
- opaque ID-to-semantic side registries, semantic recompilation from display
  identifiers, enabled controls without exact current requests, and silent nil
  dispatch are forbidden;
- episode layers add no `Any`, arbitrary effect closures, reflected/string action
  registries, or `@unchecked Sendable` escape hatches;
- each cutover adds deleted-symbol, forbidden-import, and direct-port-call checks.

## Known prerequisite corrections

Commit `bab0900` deliberately made accepted Drawing Boundary geometry available
to Drawing Studio, but introduced two implementation assumptions that must not
enter the episode runtime:

1. `OperatorWorkspace.inferredDrawingStudioPixel` may extrapolate the current
   affine mapping outside `TipCameraRegistration.applicabilityRectangle` for
   diagnostic presentation. That projection is not attributable evidence. An
   evidence-producing path must refuse it, classify it as typed non-attributable
   diagnostic output, or consume a newly validated evidence-authority revision
   whose applicability actually covers the point.
2. `ContinuousMachineCoordinateTolerance` made one 0.5 mm value answer both
   Euclidean controller-settlement and axis-expanded drawing-region containment
   questions. `FIX-00` deleted that shared owner and replaced it with separately
   typed metrics and revisions: 0.5 mm Euclidean controller settlement and a
   1e-9 mm axis-containment epsilon for accepted-Boundary drawing geometry.

`FIX-00` completed the settlement/containment policy split in `TASK-1B5992CF`.
`FIX-01` completed outside-applicability evidence attribution in
`TASK-05D1DCBD`. Both preserve the current Boundary/Border distinction and
durable overlay decoding without preserving either incorrect semantic.

EA-06 integration inspection found a separate transport-observability
prerequisite. At that inspection, the then-current `MachineLink` operations
returned either no value or untimestamped bytes, so a later
`RecordingMachineLink` could not truthfully recover the exact configuration
actually applied at open, discarded and written byte counts, the monotonic time
bytes crossed the receive boundary, close failure, or partial transfer progress.
`FIX-02` has corrected that canonical contract before EA-06. The landed
correction uses the sole existing `MachineLink` protocol, adds no sibling
observability port or default implementation, and never manufactures serial
settings or zero-count progress. This repository correction moved no
`MachineController` or `RunInterpreter` authority, installed no recorder, and
produced no physical evidence.

Camera-frame names that actually identify exact frames remain valid. Durable
`calibratedDrawableRegion`, `localPreLineBaseline`, `linePlan`, `lineExecution`,
and `postLineFrame` wire values may remain only inside versioned decode adapters
with proved callers. Active emission and active owners move to canonical
episode/Border vocabulary in `EA-10E`; parallel alias types are forbidden.

EA-11C inventory exposed a final-composition prerequisite inside the same
slice/task/landing, not an unnamed feature migration. Renaming the workspace or
putting LIVE and SIMULATED values in a dictionary is insufficient. The landing
must establish `PlotterApplicationRuntime` as the root composition/runtime with
one canonical `environmentStates` map of source-indexed
`PlotterApplicationEnvironmentState` entries, one public
projection-bound `PlotterUIIntentSink`, and nominal lower effect/persistence
ports. `PlotterApp` must depend directly on `EpisodeRuntime`; the root owns one
residual adapter formed by `PlotterApplicationResidualOperation`,
`PlotterApplicationResidualHandle`, `PlotterApplicationResidualContext`, and
its `residualRegistry` backed by package `PlotterOperationRegistry`, with no
sibling task registry.

The root closes its MainActor admission latch synchronously before the first
shutdown await, then closes/cancels/joins the residual registry and every named
feature runtime owner. It persists accepted residual application state in
declared order before publishing the corresponding immutable projection or a
successful terminal. A deadline, cancelled waiter, append failure, or one
nonterminal feature owner cannot publish `terminated`, `quiescent`, or an
equivalent success. The exact remaining owner/progress/publication cursor stays
visible and joinable. `PlotterEpisodeCompositionTests` must exercise these
contracts through the production root and nominal ports.

The post-FIX-09 DOC-05 audit proved that the landed root topology still does not
provide one model-owned Learning authority. `PlotterBorderValidationRuntime`
and `PlotterApplicationEnvironmentState.borderValidation` are simultaneous
mutable Border Validation stores; App-owned Learning action dictionaries and
opaque UI intent cases erase and later reconstruct model meaning; retained
Learning effects generate identity outside one ordered model journal. The
incident-export boundary therefore cannot truthfully select one canonical
Learning episode without fabricating or merging unrelated journals. DOC-05
moves no authority; it inserts `TRANCHE-MODEL-UI-CONSOLIDATION` before FIX-10 so
those three coupled authority gaps are replaced in order and their redundant
state and UI paths are deleted before incident-source binding.

## EA-01 current-source inventory

This is the exhaustive DOC-01 source characterization. Each stable ID names one
bounded current seam or family whose members share one current owner, one
disposition, one cutover package, and one fixed focused command. `retain` means
the lower-level owner survives without duplication; `adapt` means that owner
survives but its caller or adapter moves; `delete` means the named current seam
must be absent in the cutover landing. A row never authorizes work outside its
named package.

The `INVENTORY` gate extracts every case from the current action enums, every
named unavailable-reason guard on the unique application root (legacy
`OperatorWorkspace` or target `PlotterApplicationRuntime`), every injected
action port, every declared `Task` owner in the named application/runtime
owners, and every direct SwiftUI `workspace`/`actionWorkspace` consumer. It
requires exact set equality with the seams below, so a new or omitted member
fails rather than falling into a generic remainder.

This table remains the immutable EA-01 characterization baseline after assigned
WorkPackages land. A `delete` row assigned to any completed package in the
inventory's assignable WorkPackage set is historical deletion authority, not a
claim that its named source still exists. The inventory checker excludes only
those completed assignable `delete` rows from live source-presence equality
while retaining every row and all applicable exact zero-match scans. Rows
assigned to pending WorkPackages, plus every `retain` or `adapt` row regardless
of package status, remain live-presence obligations.

| Inventory ID | Category | Current source seams | Current owner and behavior | Disposition | Cutover | Focused command |
| --- | --- | --- | --- | --- | --- | --- |
| INT-001 | semantic-intent | `PlotterApplicationRuntime.performApplicationStartup`<br>`PlotterApplicationRuntime.shutdown` | the application delegate calls one root runtime whose idempotent startup and synchronous close-before-await shutdown coordinate, cancel, and join the distinct typed owners without taking over their feature admission | adapt | `EA-11C` | `swift test --filter PlotterEpisodeCompositionTests` |
| INT-002 | semantic-intent | `PlotterControllerSessionIntent.selectSerialDevice`<br>`PlotterControllerSessionIntent.toggleConnection`<br>`PlotterControllerSessionRequest`<br>`PlotterControllerSessionIntentSink.submitControllerSessionRequest` | typed controller-session intent/request/sink lane; revision-and-capability-bound selection and connect/disconnect requests enter `PlotterControllerSessionRuntime`, while `OperatorWorkspace` supplies copied current facts and applies completed lower results only | adapt | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| INT-003 | semantic-intent | `PlotterControllerSessionIntent.requestPassiveProbe`<br>`PlotterControllerSessionIntent.clearAlarm`<br>`PlotterControllerSessionIntent.toggleMotionAuthorization`<br>`PlotterControllerSessionRuntime.submit` | `PlotterControllerSessionRuntime`; typed passive-probe, explicit alarm-clear, and session Motion admission runs one bounded request against immutable facts and returns a typed completed/refused/cancelled disposition | adapt | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| INT-004 | semantic-intent | `OperatorWorkspace.requestJog`<br>`OperatorWorkspace.stopManualMotion` | `OperatorWorkspace`; manual jog/drawing-stroke request and exact Stop | delete | `EA-06` | `swift test --filter PlotterManualMotionEpisodeTests` |
| INT-005 | semantic-intent | `OperatorWorkspace.requestPenActuation` | `OperatorWorkspace`; direct manual pen actuation | delete | `EA-06` | `swift test --filter PlotterManualMotionEpisodeTests` |
| INT-006 | semantic-intent | `OperatorWorkspace.selectToolContactPoint` | `OperatorWorkspace`; exact-frame cap/tip point selection and evidence routing | delete | `EA-04` | `swift test --filter PlotterPointSelectionEpisodeTests` |
| INT-007 | semantic-intent | `OperatorWorkspace.toggleLearningMode` | `OperatorWorkspace`; Learning on/off admission and active point-continuation cancellation | delete | `EA-04` | `swift test --filter PlotterPointSelectionEpisodeTests` |
| INT-008 | semantic-intent | `PlotterDrawingDraftIntent.open`<br>`PlotterDrawingDraftIntent.close`<br>`PlotterDrawingDraftIntent.selectCatalogItem`<br>`PlotterDrawingDraftIntent.setEvidenceRole`<br>`PlotterDrawingDraftIntent.placeAtCameraPoint`<br>`PlotterDrawingDraftIntent.setUniformScale`<br>`PlotterDrawingDraftIntent.setRotationDegrees`<br>`PlotterDrawingDraftIntent.centerInDrawableRegion`<br>`PlotterDrawingDraftIntent.beginNewPlan`<br>`PlotterDrawingDraftIntent.assertPaperCoverage` | `PlotterDrawingDraftRuntime.submit`; one source-indexed draft authority evaluates revision-bound `PlotterDrawingDraftSubmission` values, returns exact typed refusals/remedies, and publishes immutable `PlotterDrawingDraftSnapshot` values through `PlotterDrawingDraftIntentSink`; the deleted `DrawingStudioAction`, `performDrawingStudioAction`, direct open/close/confirm helpers, and local rebuild ingress have no authority | adapt | `EA-08A` | `swift test --filter PlotterDrawingDraftEpisodeTests` |
| INT-009 | semantic-intent | `PlotterDrawingRunIntent.start`<br>`PlotterDrawingRunIntent.stop`<br>`PlotterDrawingRunIntent.pinReview`<br>`PlotterDrawingRunIntent.unpinReview`<br>`PlotterDrawingRunIntent.beginNewRun`<br>`PlotterDrawingRunIntent.recoverPublication` | `PlotterDrawingRunRuntime.submit`; one source-indexed EA-08B authority evaluates revision/plan-bound `PlotterDrawingRunSubmission` values and owns exclusive start, exact-capability Stop, terminal publication recovery, no-redraw, review, and new-run handoff; the deleted App run/review action enums and raw handlers have no authority | adapt | `EA-08B` | `swift test --filter PlotterDrawingRunEpisodeTests` |
| INT-010 | semantic-intent | `PlotterPenInteractionIntent.start`<br>`PlotterPenInteractionIntent.capSelectionAccepted`<br>`PlotterPenInteractionIntent.setpoint`<br>`PlotterPenInteractionIntent.actuate`<br>`PlotterPenInteractionIntent.confirm`<br>`PlotterPenInteractionIntent.abortAndRaise`<br>`PlotterPenInteractionIntent.finish`<br>`PlotterPenInteractionIntent.cancel`<br>`PlotterPenInteractionIntent.stop`<br>`PlotterPenInteractionIntent.reset` | `PlotterPenInteractionRuntime.submit`; one actor-isolated source-indexed authority evaluates exact projection/environment/operation-bound `PlotterPenInteractionSubmission` values, owns value-bearing Up/Down admission, latest-only setpoint coalescing, exact cancellation/Stop/settlement/shutdown, and immutable attempt evidence; the deleted `ExerciseActionKind.setPenSetpoint` and `OperatorWorkspace.beginPenInteraction` paths have no authority | adapt | `EA-10A` | `swift test --filter PlotterPenInteractionEpisodeTests` |
| INT-011 | semantic-intent | `PlotterLearningActionRequest`<br>`PlotterLearningSemanticAction.boundary`<br>`PlotterBoundarySubmission`<br>`PlotterBoundaryIntent`<br>`PlotterBoundaryProjectionReference` | the exact model request survives immutable projection and sole-sink submission unchanged; `PlotterBoundaryRuntime` remains the source-indexed direction, acquisition, center-travel/retry, exact Stop/cancel, publication-recovery, and non-destructive-reset authority | adapt | `EA-12B` | `swift test --filter PlotterLearningUIAuthorityTests` |
| INT-012 | semantic-intent | `PlotterLearningActionRequest`<br>`PlotterLearningSemanticAction.cameraCalibration` | the exact model request routes through the sole public sink to `PlotterCameraCalibrationRuntime`, which owns capture, five-position proposal, acceptance/rejection, task, failure/recovery, and terminal truth | adapt | `EA-12B` | `swift test --filter PlotterLearningUIAuthorityTests` |
| INT-013 | semantic-intent | `PlotterLearningActionRequest`<br>`PlotterLearningSemanticAction.tipCalibration`<br>`PlotterLearningSemanticAction.pointSelectionCorrection` | exact model requests route to `PlotterTipCalibrationRuntime`; the distinct `PlotterPointSelectionRuntime` remains the sole click add/undo/clear/four-point batch owner. Retry exists only in the stable recoverable state and is absent during commit/revalidation | adapt | `EA-12B` | `swift test --filter PlotterLearningUIAuthorityTests` |
| INT-014 | semantic-intent | `PlotterLearningActionRequest`<br>`PlotterLearningSemanticAction.borderValidation`<br>`PlotterBorderValidationIntent.begin`<br>`PlotterBorderValidationIntent.acceptObservedPrediction`<br>`PlotterBorderValidationIntent.reject` | `PlotterBorderValidationRuntime` is the sole source-indexed mutable Border Validation state, operation, task, review, possible-ink, reset, result, and shutdown owner; `PlotterApplicationRuntime` supplies lower effects and copies immutable projections only. The duplicate environment snapshot, forwarding paths, `replaceSnapshot`, and zero-caller retry intent are deleted | adapt | `EA-12A` | `swift test --filter PlotterBorderValidationEpisodeTests` |
| INT-015 | semantic-intent | `PlotterLearningActionRequest`<br>`PlotterLearningSemanticAction.artifactReset`<br>`PlotterArtifactResetIntent` | the exact model request routes to `PlotterArtifactResetRuntime`, the sole Saved Learning comparison/apply/retain/reject, redo/additional-attempt, paper-replacement, reset, task, persistence, and terminal authority; no App semantic registry or request recompilation remains | adapt | `EA-12B` | `swift test --filter PlotterLearningUIAuthorityTests` |
| INT-016 | semantic-intent | `PlotterSpeechEffectRuntime.perform` | `PlotterSpeechEffectRuntime`; typed application-level advisory speech admission with identity-bound terminal tracking and advisory-only outcomes; the retired `OperatorWorkspace.announceAdvisory` ingress is enforced by EA-10G's exact deletion scan | adapt | `EA-10G` | `swift test --filter PlotterSpeechEffectEpisodeTests` |
| INT-017 | semantic-intent | `PlotterObservationOperatorIntent`<br>`PlotterObservationOperatorSubmission`<br>`PlotterApplicationRuntime.submitObservationConfiguration`<br>`PlotterObservationConfigurationRuntime.submit` | typed observation operator intent/submission lane; immutable-projection-bound source, camera, cadence, region, overlay, and diagnostics requests enter `PlotterObservationConfigurationRuntime`, while `PlotterApplicationRuntime` only validates the copied projection reference, routes the typed submission, and installs returned lower snapshots | adapt | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| INT-018 | semantic-intent | `PlotterLearningRecordRequest`<br>`PlotterUIIntent.learningAction`<br>`PlotterUIIntent.learningReset`<br>`PlotterLearningEpisodeRecord.reserve`<br>`PlotterLearningEpisodeRecord.publish` | one stable model-owned `PlotterLearningEpisodeID` spans the bounded record; each ordered `PlotterLearningTransitionID` binds the exact typed action-or-reset request, source, pre revision, typed accepted/refused result/remedy, and bounded immutable post-transition projection. `PlotterApplicationRuntime` routes the admitted request to the retained feature owner, while its transition-keyed task exists only to preserve root cancel/join across genuinely asynchronous residual work | adapt | `EA-12C` | `swift test --filter PlotterEpisodeCompositionTests` |
| INT-019 | semantic-intent | `VideoSettingsVisibilityAction.show`<br>`VideoSettingsVisibilityAction.hide` | `WorkbenchLayoutState`; window-local Video Settings visibility only | retain | `EA-09` | `swift test --filter PlotterEpisodeUIActionabilityTests` |
| GRD-001 | guard | `ContinuousMachineCoordinateTolerance.minimumMM` | shared model/runtime constant currently answers settlement and containment | delete | `FIX-00` | `swift test --filter CoordinateAcceptancePolicyTests` |
| GRD-002 | guard | `OperatorWorkspace.inferredDrawingStudioPixel` | `OperatorWorkspace`; currently permits diagnostic extrapolation to feed attribution | delete | `FIX-01` | `swift test --filter TipApplicabilityEvidencePolicyTests` |
| GRD-003 | guard | `OperatorWorkspace.learningModeChangeUnavailableReason` | `OperatorWorkspace`; prevents Learning Off while current work/continuation owns settlement | delete | `EA-04` | `swift test --filter PlotterPointSelectionEpisodeTests` |
| GRD-004 | guard | `OperatorWorkspace.directCarriageMotionUnavailableReason`<br>`OperatorWorkspace.directManualMotionUnavailableReason`<br>`OperatorWorkspace.directMotionUnavailableReason`<br>`OperatorWorkspace.motionUnavailableReason`<br>`OperatorWorkspace.ordinaryRelativeJogUnavailableReason`<br>`OperatorWorkspace.penUnavailableReason`<br>`OperatorWorkspace.simulatedManualMotionUnavailableReason` | `OperatorWorkspace`; duplicated LIVE/SIMULATED manual semantic admission around controller facts | delete | `EA-06` | `swift test --filter PlotterManualMotionEpisodeTests` |
| GRD-005 | guard | `PlotterApplicationRuntime.manualMotionDraftUnavailableReason`<br>`PlotterApplicationRuntime.incidentPackageUIActionUnavailableReason` | `PlotterApplicationRuntime`; UI-local presentation guards only: numeric manual-draft validation and the deliberately unavailable incident-source explanation; neither owns semantic admission, source identity fabrication, assembly/export, controller, Learning, or episode authority | adapt | `EA-09` | `swift test --filter PlotterEpisodeUIActionabilityTests` |
| GRD-006 | guard | `PlotterApplicationRuntime.drawingStudioPanelChangeUnavailableReason` | immutable `PlotterDrawingRunSnapshot` facts prevent hiding the panel during run/evidence capture; this root presentation guard owns no run or draft admission | adapt | `EA-08A` | `swift test --filter PlotterDrawingDraftEpisodeTests` |
| GRD-007 | guard | `PlotterDrawingRunRefusalReason`<br>`PlotterDrawingRunNoRedrawState`<br>`PlotterDrawingRunEvidencePersistence`<br>`PlotterApplicationRuntime.paperManagementUnavailableReason` | `PlotterDrawingRunRuntime` state is the run-related semantic authority for exact-projection admission, possible-ink/no-redraw, review/new-run, and append-before-success recovery; `PlotterApplicationRuntime.paperManagementUnavailableReason` is projection-only for paper mutation while active/publication ownership exists, and paper lifecycle semantics remain later EA-10F authority | adapt | `EA-08B` | `swift test --filter PlotterDrawingRunEpisodeTests` |
| GRD-008 | guard | `PlotterPenInteractionRefusalReason`<br>`PlotterPenInteractionRemedy`<br>`PlotterPenInteractionProjection` | `PlotterPenInteractionRuntime`; exact revision, environment, operation, phase, controller/Motion, lower-owner, ambiguity, value-range, cancellation-capability, and shutdown facts produce typed refusal/remedy state; the deleted workspace prerequisite guard has no authority | adapt | `EA-10A` | `swift test --filter PlotterPenInteractionEpisodeTests` |
| GRD-009 | guard | `PlotterApplicationRuntime.borderValidationActionUnavailableReason` | `PlotterApplicationRuntime`; lower Border step availability projection over current effects/environment; it owns no Border operation identity, phase, task admission, terminal, possible-ink, accept/reject, or shutdown authority | adapt | `EA-10E` | `swift test --filter PlotterBorderValidationEpisodeTests` |
| GRD-010 | guard | `PlotterApplicationRuntime.artifactResetUnavailableReason` | `PlotterArtifactResetRuntime` supplies the runtime-backed reset-admission refusal over immutable facts; `PlotterApplicationRuntime` projects it only. Possible ink and active Stop remain hard blockers, while settleable Learning work and independent manual motion are not conflated with reset admission | adapt | `EA-10F` | `swift test --filter PlotterArtifactResetEpisodeTests` |
| GRD-011 | guard | `PlotterControllerSessionRules.project`<br>`PlotterControllerSessionRules.refusal`<br>`PlotterControllerSessionProjection` | `PlotterControllerSessionRules` and its immutable projection; one centralized typed rules/refusal authority derives selection, connection, Motion, alarm, controller-state, and LIVE/SIMULATED availability from copied session facts. No `OperatorWorkspace.*UnavailableReason` controller seam remains assigned | adapt | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| GRD-012 | guard | `PlotterObservationConfigurationProjection`<br>`PlotterObservationConfigurationDisposition`<br>`PlotterApplicationRuntime.observationSourceChangeUnavailableReason` | immutable typed projection/disposition plus the residual root source-change pre-submission gate. The residual guard only reports current calibration/operation conflict facts; it does not own observation runtime admission, camera effects, configuration ordering, subscriptions, or terminal truth | adapt | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| GRD-013 | guard | `PlotterApplicationRuntime.controllerCarriageTravelUnavailableReason`<br>`PlotterApplicationRuntime.discoveryStartUnavailableReason`<br>`PlotterApplicationRuntime.learningCarriageMotionUnavailableReason`<br>`PlotterApplicationRuntime.learningConnectionAndMotionUnavailableReason`<br>`PlotterApplicationRuntime.learningExerciseMotionUnavailableReason`<br>`PlotterApplicationRuntime.learningPenCommandUnavailableReason` | residual application-composition guards project copied cross-feature controller, Motion, camera, and active-owner facts for retained Learning presentation; they own no lower effect, typed feature admission, Stop, settlement, or evidence authority | adapt | `EA-11C` | `swift test --filter PlotterEpisodeCompositionTests` |
| OWN-001 | authority-owner | `PlotterApplicationRuntime` | sole observable application composition root and projection-bound public sink; it coordinates copied typed-runtime facts, residual application state, startup, and shutdown without duplicating feature-runtime effect authority | adapt | `EA-11C` | `swift test --filter PlotterEpisodeCompositionTests` |
| OWN-002 | authority-owner | `MachineController` | selected serial transport, parsing, fresh safety, serialization, settlement, ambiguity | retain | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| OWN-003 | authority-owner | `RunInterpreter` | logical machine operation, plan execution, checkpoints, lower-level cancel settlement | retain | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| OWN-004 | authority-owner | `PlotterMachineSession`<br>`PersistentMachineSession`<br>`MachineSessionComposition.session` | `MachineSessionComposition` installs the nominal lower `PlotterMachineSession` capability backed by `PersistentMachineSession`; it retains controller/interpreter/ledger composition while `PlotterControllerSessionRuntime` owns only typed controller-session admission and its bounded request lane, not duplicate lower effects | adapt | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| OWN-005 | authority-owner | `CameraCapture` | camera discovery, selection, lifecycle, exact frames, preview holds | retain | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| OWN-006 | authority-owner | `CameraSourceSession` | automatic-analysis configuration, its sole `automaticInspectionFrameTask` pipeline frame-ingestion lane, and exact-workflow Vision leases | retain | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| OWN-007 | authority-owner | `VisionWorker` | typed measurement and diagnostic computation | retain | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| OWN-008 | authority-owner | `PlotterObservationConfigurationRuntime`<br>`PlotterSceneAnalysisPipeline` | `PlotterObservationConfigurationRuntime` owns typed observation configuration admission, ordering, recording boundary, frame-event observation, semantic-analysis-update observation, and shutdown; `PlotterSceneAnalysisPipeline` retains newest-only analysis state and progress, while `CameraSourceSession` alone owns automatic frame ingestion | adapt | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| OWN-009 | authority-owner | `PlotterUICompiler`<br>`PlotterUIProjection`<br>`PlotterUILearningActionabilityCompiler`<br>`PlotterUILearningActionabilityProjection` | canonical bounded immutable UI compilers/projections over copied episode facts; the Learning compiler solely decides current owner, item status, action/Stop strips, availability, Pen adjustment, direction, and reset reachability, while neither compiler owns runtime mutation, effect, controller, camera, Vision, or persistence authority | adapt | `EA-09` | `swift test --filter PlotterEpisodeUIActionabilityTests` |
| OWN-010 | authority-owner | `WorkbenchLayoutState`<br>`ActionSurfaceViewportState` | window/pane/viewport-local presentation state | retain | `EA-09` | `swift test --filter PlotterEpisodeUIActionabilityTests` |
| OWN-011 | authority-owner | `PlotterApplicationState` | one source-indexed residual application-state aggregate; typed feature projections and effect truth remain in their named runtimes | adapt | `EA-11C` | `swift test --filter PlotterEpisodeCompositionTests` |
| OWN-012 | authority-owner | `PlotterTipCalibrationRuntime` | sole typed sparse physical-batch, proposal, recoverable accepted-tip checkpoint, possible-ink, terminal, task, shutdown, and atomic commit/revalidation-installation workflow owner; the retired coordinator remains EA-10D deletion authority | adapt | `EA-10D` | `swift test --filter PlotterTipCalibrationEpisodeTests` |
| OWN-013 | authority-owner | `DrawingPlanner` | lower pure deterministic geometry admission and content-addressed execution-plan authority, reached by upper layers only through the one `PlotterDrawingPlanningAdapter`; its package-only retained Border route preserves EA-10E semantics without draft authority | retain | `EA-08A` | `swift test --filter PlotterDrawingDraftEpisodeTests` |
| OWN-014 | authority-owner | `TipCalibrationAuthority`<br>`TipCameraRegistration`<br>`AcceptedTipCalibrationCheckpoint` | retained lower evidence validation, construction, applicability, and accepted-checkpoint value semantics reached through the typed tip-calibration workflow; the runtime owns checkpoint retention/installation and neither lower owner owns workflow admission, task, phase, or terminal authority | retain | `EA-10D` | `swift test --filter PlotterTipCalibrationEpisodeTests` |
| OWN-015 | authority-owner | `DrawingRunEvidenceArchive` | checksummed append-only drawing-run evidence value and append rules | retain | `EA-08B` | `swift test --filter PlotterDrawingRunEpisodeTests` |
| OWN-016 | authority-owner | `SimulatedLearningRuntime` | nonphysical controller/plant/pen/paper/camera causal truth | adapt | `EA-07` | `swift test --filter PlotterCausalEpisodeEnvironmentTests` |
| OWN-017 | authority-owner | `NativeSpeechAnnouncer` | lower AVFoundation synthesis, identity queue, timeout, and shutdown cancellation; `PlotterSpeechEffectRuntime` owns upper admission, request identity, bounded terminal tracking, and the pre-suspension shutdown latch | retain | `EA-10G` | `swift test --filter PlotterSpeechEffectEpisodeTests` |
| OWN-018 | authority-owner | `RunLedger` | low-level ordered SQLite device/workflow diagnostics | adapt | `EA-05A` | `swift test --filter PlotterRecordingStoreTests` |
| OWN-019 | authority-owner | `StartupFrameRecorder` | unbound file recorder with test-only consumers | delete | `EA-05A` | `swift test --filter PlotterRecordingStoreTests` |
| OWN-020 | authority-owner | `OverlayResultChannels`<br>`OverlayPresentationComposer` | source-separated camera/analysis results and pure exact-frame overlay composition remain rendering/evidence-applicability authority; observation configuration only supplies typed lower updates and does not own overlay rendering or applicability | adapt | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| OWN-021 | authority-owner | `PaperCoverageValidationContext` | paper/source/camera-configuration/contact-plane currentness decision independent of exact-frame polygon display; a newer same-context frame can remain current while only the accepted exact frame may display the polygon | retain | `EA-08A` | `swift test --filter PlotterDrawingDraftEpisodeTests` |
| OWN-022 | authority-owner | `AcceptedLearningPathCheckpoint` | retained atomic durable accepted Learning prefix value and validation; it carries no reset admission, task, terminal, or effect authority | retain | `EA-10F` | `swift test --filter PlotterArtifactResetEpisodeTests` |
| OWN-023 | authority-owner | `PlotterArtifactResetRuntime` | sole typed Saved Learning/artifact lifecycle owner: explicit comparison/apply/retain/reject/redo/additional-attempt/paper/reset intents, admission, active operation/task, saved state, bounded terminals, durable-before-projection ordering, and shutdown latch | adapt | `EA-10F` | `swift test --filter PlotterArtifactResetEpisodeTests` |
| OWN-024 | authority-owner | `PlotterDrawingRunRuntime.facts`<br>`PlotterDrawingRunRuntime.interpreter`<br>`PlotterDrawingRunRuntime.camera`<br>`PlotterDrawingRunRuntime.vision` | `PlotterDrawingRunRuntime` directly retains exactly one nominal fact, interpreter, camera, and Vision capability; `PlotterDrawingRunComposition` is construction-only and `PlotterApplicationRuntime` stores only the typed Drawing Run runtime, while the existing machine session and observation runtime remain the lower controller/camera/Vision owners without wrapper, root-port, task, Stop, or duplicate operation authority | adapt | `FIX-05` | `swift test --filter PlotterEpisodeCompositionTests` |
| PRT-001 | direct-port | `PlotterMachineSession.select`<br>`PlotterMachineSession.snapshot`<br>`PlotterMachineSession.requestPassiveProbe`<br>`PlotterMachineSession.requestControllerAlarmClear`<br>`PlotterMachineSession.activateMotionGuard`<br>`PlotterMachineSession.deactivateMotionGuard`<br>`PlotterMachineSession.beginRelativeJog`<br>`PlotterMachineSession.beginDrawingStroke`<br>`PlotterMachineSession.beginDrawingPlan`<br>`PlotterMachineSession.beginPenActuation`<br>`PlotterMachineSession.beginBoundaryMotion`<br>`PlotterMachineSession.requestJogCancel`<br>`PlotterMachineSession.disconnect` | nominal lower actor protocol retained by `PersistentMachineSession`; typed controller-session and episode runtimes call only its named capabilities. It is not a `PORT_STRUCTS` closure façade and owns no admission, projection, or UI policy | adapt | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| PRT-002 | direct-port | `PlotterObservationCameraSessionPort.discover`<br>`PlotterObservationCameraSessionPort.select`<br>`PlotterObservationCameraSessionPort.start`<br>`PlotterObservationCameraSessionPort.startLifecycle`<br>`PlotterObservationCameraSessionPort.stop`<br>`PlotterObservationCameraSessionPort.restart`<br>`PlotterObservationCameraSessionPort.snapshot`<br>`PlotterObservationCameraSessionPort.frames`<br>`PlotterObservationCameraSessionPort.inspectWorkflowScene`<br>`PlotterObservationCameraSessionPort.captureFrame`<br>`PlotterObservationCameraSessionPort.captureStableWorkflowCap`<br>`PlotterObservationCameraSessionPort.setSceneAnalysisRegion`<br>`PlotterObservationCameraSessionPort.setPenCapColor`<br>`PlotterObservationCameraSessionPort.setAutomaticInspection`<br>`PlotterObservationCameraSessionPort.analysisUpdates`<br>`PlotterObservationCameraSessionPort.visionDiagnostics`<br>`PlotterObservationCameraSessionPort.observePlannedDrawingInk` | nominal lower observation-camera-session protocol retained by `CameraSourceSession`; the typed observation runtime calls only named lifecycle/configuration/evidence capabilities. CameraSourceSession retains its own automatic pipeline frame-ingestion task, so no duplicate forwarding owner remains. This port is outside the static closure-facade family and owns no operator admission, projection, or UI policy | adapt | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| PRT-003 | direct-port | `PlotterSpeechEffectRuntime.shutdown` | `PlotterSpeechEffectRuntime`; typed application speech-effect shutdown boundary that closes admission before delegating lower queue cancellation; the retired `AnnouncementActions` closure façade is enforced by EA-10G's exact deletion scan | adapt | `EA-10G` | `swift test --filter PlotterSpeechEffectEpisodeTests` |
| PRT-004 | direct-port | `PlotterApplicationResidualEffectPort.discoverSerialDevices`<br>`PlotterApplicationResidualEffectPort.nowNanoseconds`<br>`PlotterApplicationResidualEffectPort.recordWorkflowTelemetry` | nominal residual root effect protocol; its methods supply serial discovery, monotonic time, and diagnostic append only, with no stored closure façade and no admission, task, Stop, or terminal authority | adapt | `EA-05A` | `swift test --filter PlotterRecordingStoreTests` |
| PRT-005 | direct-port | `PlotterApplicationStatePersistencePort.loadAcceptedLearningPathCheckpoint`<br>`PlotterApplicationStatePersistencePort.saveAcceptedLearningPathCheckpoint`<br>`PlotterApplicationStatePersistencePort.clearAcceptedLearningPathCheckpoint`<br>`PlotterApplicationStatePersistencePort.persistPaperRevisionContext`<br>`PlotterArtifactResetEffectPort.execute`<br>`PlotterArtifactResetPersistencePort.persist`<br>`PlotterApplicationRuntimeArtifactResetRelay` | `PlotterApplicationStatePersistencePort` is the one nominal root durable boundary for accepted Learning checkpoints and paper identity. `PlotterArtifactResetComposition` retains one weak nominal relay between the typed runtime and root lower effects/persistence; the runtime owns admission, ordering, settlement, and terminal truth | adapt | `EA-10F` | `swift test --filter PlotterArtifactResetEpisodeTests` |
| PRT-006 | direct-port | `PlotterDrawingRunFactSource`<br>`PlotterDrawingRunInterpreterPort`<br>`PlotterDrawingRunCameraPort`<br>`PlotterDrawingRunVisionPort`<br>`PlotterDrawingRunEvidencePort` | nominal EA-08B adapters preserve retained MachineController/RunInterpreter, CameraCapture, VisionWorker, and checksummed archive owners without arbitrary closure authority; the deleted `DrawingEvidenceActions` façade and direct App run ports have no authority | adapt | `EA-08B` | `swift test --filter PlotterDrawingRunEpisodeTests` |
| PRT-007 | direct-port | `PlotterDrawingDraftPaperPersistence.load`<br>`PlotterDrawingDraftPaperPersistence.save`<br>`PlotterDrawingDraftPaperPersistence.clear` | `PlotterDrawingDraftRuntime`; one nominal persistence protocol whose LIVE save completes before accepted snapshot publication; SIMULATED remains nonphysical and the deleted workspace closure port has no authority | adapt | `EA-08A` | `swift test --filter PlotterDrawingDraftEpisodeTests` |
| MOD-001 | environment-branch | `OperatorWorkspace.frameMode`<br>`OperatorWorkspace.executeSimulatedBoundaryMotion` | `OperatorWorkspace`; residual nonmanual LIVE/SIMULATED effect branches after EA-06 retires the manual branch | delete | `EA-07` | `swift test --filter PlotterCausalEpisodeEnvironmentTests` |
| MOD-002 | environment-branch | `PlotterApplicationState.environmentStates` | one canonical dictionary keyed by `OperatorFrameMode` replaces the parallel LIVE/SIMULATED root aggregates; switching source selects a value without creating a second application owner | adapt | `EA-11C` | `swift test --filter PlotterEpisodeCompositionTests` |
| MOD-003 | environment-branch | `PlotterCausalSimulatorEffectAdapter.admitManualJog`<br>`PlotterCausalSimulatorEffectAdapter.admitRetainedWorkflowBoundary`<br>`PlotterCausalSimulatorEffectAdapter.admitRetainedWorkflowDrawing`<br>`PlotterCausalSimulatorEffectAdapter.admitRetainedWorkflowTravel`<br>`PlotterCausalSimulatorEffectAdapter.executeRetainedWorkflowPen` | `PlotterCausalSimulatorEffectAdapter`; sole shared typed simulated effect-admission seam and occupancy owner; manual admission owns episode attribution, while retained Boundary/drawing/travel/Pen work carries its explicit owner with nil `effectResult` and no fabricated plan revision; Pen ingress refuses the exact reserved predecessor without lower mutation, while admitted lower Pen mutation plus causal truth is returned atomically by package-only `SimulatedLearningRuntime.setPenPoseWithCausalTruth` | adapt | `EA-07` | `swift test --filter PlotterCausalEpisodeEnvironmentTests` |
| TSK-001 | task-cancel-owner | `PlotterPenInteractionRuntime.actuationTask`<br>`PlotterPenInteractionRuntime.shutdown`<br>`PlotterPenInteractionProjectionSink`<br>`PlotterPenInteractionPhase.drainingSetpoint` | `PlotterPenInteractionRuntime`; one exact lower actuation task, cancellation latch, synchronously claimed setpoint drain, terminal publication, admission closure, and runtime-owned weak projection sink own Pen Interaction lifetime; `.drainingSetpoint` is published before the first await, permits exact latest replacement and capability-bound Stop but no confirmation, and transitions to lower settling before post-publication confirmation; the sink requires no workspace observer task/latch/retry, and the deleted workspace setpoint task has no replacement task owner | adapt | `EA-10A` | `swift test --filter PlotterPenInteractionEpisodeTests` |
| TSK-002 | task-cancel-owner | `PlotterApplicationLearningTask.task`<br>`PlotterApplicationRuntime.drawingRunProjectionTask` | the root retains an asynchronous Learning task only for exact cancel/join and keys it by `PlotterLearningTransitionID`; it owns no parallel admission, latch, journal, or feature effect. The Drawing Run subscription installs immutable runtime snapshots and owns no run/effect/Stop authority | adapt | `EA-12C` | `swift test --filter PlotterEpisodeCompositionTests` |
| TSK-003 | task-cancel-owner | `OperatorWorkspace.penCapAcceptedClickContinuationTask`<br>`OperatorWorkspace.penCapVisionReconfigurationTask` | `OperatorWorkspace`; exact point-selection continuation/reconfiguration tasks | delete | `EA-04` | `swift test --filter PlotterPointSelectionEpisodeTests` |
| TSK-004 | task-cancel-owner | `PlotterBoundaryRuntime.operationTasks`<br>`PlotterBoundaryProjectionSink.publishBoundarySnapshot` | `PlotterBoundaryRuntime`; synchronously reserved environment-local operation/cancellation capability and sole lower-execution/settlement/publication task lane wait on one production reservation-publication latch until the genuinely async sink returns from `.reserving`; this is ownership ordering rather than a test gate, and the workspace `boundaryMotionTask` is deleted | adapt | `EA-10B` | `swift test --filter PlotterBoundaryEpisodeTests` |
| TSK-005 | task-cancel-owner | `PlotterCameraCalibrationRuntime.activeTask` | `PlotterCameraCalibrationRuntime`; sole typed camera-calibration effect task, bounded terminal tracking, and shutdown admission/cancellation owner; the retired workspace task remains an EA-10C exact deletion scan | adapt | `EA-10C` | `swift test --filter PlotterCameraCalibrationEpisodeTests` |
| TSK-006 | task-cancel-owner | `PlotterArtifactResetRuntime.activeTask` | `PlotterArtifactResetRuntime`; sole typed lower-effect/persistence task with shutdown cancellation and bounded terminal ownership; the retired workspace comparison task remains exact deletion authority | adapt | `EA-10F` | `swift test --filter PlotterArtifactResetEpisodeTests` |
| TSK-007 | task-cancel-owner | `CameraSourceSession.automaticInspectionFrameTask`<br>`PlotterObservationConfigurationRuntime.frameSubscription`<br>`PlotterObservationConfigurationRuntime.analysisSubscription`<br>`PlotterApplicationRuntime.observationProjectionTask` | `CameraSourceSession` solely ingests automatic-pipeline frames and cancels/settles that task with automatic inspection and exclusive Vision leases; the runtime owns distinct frame-event/recording observation plus semantic-analysis-update observation and shutdown; the application root retains only the projection-event subscription that installs immutable lower snapshots and owns no camera/configuration effect | adapt | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| TSK-008 | task-cancel-owner | `AdaptivePlotterApplicationDelegate.terminationTask` | the application delegate retains one shutdown join task and reports termination only after `PlotterApplicationRuntime.shutdown` returns; no deadline task may fabricate quiescence | adapt | `EA-11C` | `swift test --filter PlotterEpisodeCompositionTests` |
| TSK-009 | task-cancel-owner | `CameraCapture.eventConsumer` | `CameraCapture`; driver-event owner under camera lifecycle | retain | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| TSK-010 | task-cancel-owner | `PlotterSceneAnalysisPipeline.drainTask` | scene pipeline; newest-only analysis task owner | retain | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| TSK-011 | task-cancel-owner | `MachineController.ledgerWriteTail` | `MachineController`; ordered nonblocking ledger append tail | adapt | `EA-05A` | `swift test --filter PlotterRecordingStoreTests` |
| TSK-012 | task-cancel-owner | `SpeechSynthesisQueue.Request.timeoutTask` | lower native synthesis request; one per-utterance timeout owned and cancelled by the retained identity queue, not by the application speech-effect runtime | retain | `EA-10G` | `swift test --filter PlotterSpeechEffectEpisodeTests` |
| TSK-013 | task-cancel-owner | `RunInterpreter.cancelTask` | `RunInterpreter`; lower-level jog/plan cancellation settlement | retain | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| TSK-014 | task-cancel-owner | `OperatorWorkspace.drawingRunTask` | `OperatorWorkspace`; redundant stored join for Drawing Run submission and shutdown settlement around the already-authoritative `PlotterDrawingRunRuntime` | delete | `FIX-03` | `swift test --filter PlotterDrawingRunEpisodeTests` |
| TSK-015 | task-cancel-owner | `PlotterTipCalibrationRuntime.activeTask` | `PlotterTipCalibrationRuntime`; sole typed lower-effect task and shutdown cancellation owner for the calibration workflow | adapt | `EA-10D` | `swift test --filter PlotterTipCalibrationEpisodeTests` |
| TSK-016 | task-cancel-owner | `PlotterBorderValidationRuntime.activeTask` | `PlotterBorderValidationRuntime`; sole typed active-step effect task, terminal history, and shutdown cancellation owner for Border validation | adapt | `EA-10E` | `swift test --filter PlotterBorderValidationEpisodeTests` |
| TSK-017 | task-cancel-owner | `PlotterControllerSessionRuntime.activeTask`<br>`PlotterControllerSessionRuntime.shutdown` | `PlotterControllerSessionRuntime`; sole bounded controller-session request task and shutdown cancellation owner; lower disconnect remains a nominal `PlotterMachineSession` effect and no workspace controller-session task replaces it | adapt | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| PER-001 | persistence-path | `PlotterControllerSessionFacts.selectedSerialDevice`<br>`PlotterControllerSessionProjection.selectedSerialDevice` | no selected-serial preference is persisted: the selected descriptor is current session fact projected immutably to the typed controller UI and is cleared/revalidated by typed controller-session results | adapt | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| PER-002 | persistence-path | `PlotterObservationPreferencePort.loadLegacyPenCapAppearance`<br>`PlotterObservationPreferencePort.clearLegacyPenCapAppearance`<br>`PlotterObservationPreferencePort.loadOverlayPreference`<br>`PlotterObservationPreferencePort.persistOverlayPreference`<br>`PlotterObservationConfigurationProjection.enabledOverlays`<br>`PlotterObservationConfigurationProjection.penCapAppearance` | typed preference port owns atomic legacy pen-cap migration input and overlay preference reads/writes; immutable observation projection exposes the current persisted overlay/appearance result, while runtime ordering and UI submission remain separate | adapt | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| PER-003 | persistence-path | `AcceptedArtifactCheckpointComposition`<br>`AcceptedLearningPathCheckpointStore` | production canonical Learning Path composition and atomic durable prefix store; the runtime requests persistence through its typed port and only applies reset projection after durable success | adapt | `EA-10F` | `swift test --filter PlotterArtifactResetEpisodeTests` |
| PER-004 | persistence-path | `AcceptedLearningPathLegacyMigrationAdapter` | one-shot, version-aware pre-canonical migration proof: canonical short-circuit; explicit corrupt/unsupported/rejected handling; canonical atomic save before reversible legacy cleanup; failures preserve legacy bytes. `AcceptedArtifactCheckpointStore` and `AcceptedTipCalibrationCheckpointStore` are deleted and remain zero-match authority only | adapt | `EA-10F` | `swift test --filter PlotterArtifactResetEpisodeTests` |
| PER-005 | persistence-path | `DrawingRunEvidenceComposition`<br>`DrawingRunEvidencePort`<br>`DrawingRunEvidenceStore` | `PlotterDrawingRunRuntime` appends the exact immutable proposed record through one nominal port before successful terminal publication; append failure retains identity-bound recovery and cannot publish success, while the checksummed store remains the lower persistence owner | adapt | `EA-08B` | `swift test --filter PlotterDrawingRunEpisodeTests` |
| PER-006 | persistence-path | `PaperCoverageComposition.drawingDraftRuntime`<br>`UserDefaultsDrawingDraftPaperPersistence`<br>`PaperCoverageObservation` | production composition injects one nominal durable paper store into the draft runtime; save-before-publish, explicit persistence refusal, retained lifecycle clear, and validation stay separated from presentation | adapt | `EA-08A` | `swift test --filter PlotterDrawingDraftEpisodeTests` |
| PER-007 | persistence-path | `RunLedger.sqlite`<br>`MachineSessionRetentionPolicy` | bounded SQLite session diagnostics | adapt | `EA-05A` | `swift test --filter PlotterRecordingStoreTests` |
| PER-008 | persistence-path | `StartupFrameRecorder.Manifest` | unbound test-only frame/manifest file writer | delete | `EA-05A` | `swift test --filter PlotterRecordingStoreTests` |
| PER-009 | persistence-path | `AdaptivePlotter.paperInstanceRevision`<br>`AdaptivePlotter.paperContactPlaneRevision` | application-composed durable paper semantic identities; the typed runtime carries the immutable admitted reset plan and requests lower paper-revision persistence before reset projection | adapt | `EA-10F` | `swift test --filter PlotterArtifactResetEpisodeTests` |
| UI-001 | ui-consumer | `UI.controllerSessionProjection`<br>`UI.submitControllerSessionRequest`<br>`UI.motionRequestStatusPresentation` | SwiftUI controller controls read one immutable controller-session projection and submit only its exact typed request through the sink; the retained Motion status presentation is a direct workspace consumer but not controller-session admission, lower effect, or guard authority | adapt | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| UI-002 | ui-consumer | `UI.observationConfigurationProjection`<br>`UI.submitObservationConfiguration` | SwiftUI Video Settings/source/overlay controls read one immutable observation projection and submit only revision/capability-bound typed observation requests; direct workspace camera/configuration reads and handlers are retired | adapt | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| UI-003 | ui-consumer | `UI.manualMotionPresentation`<br>`UI.xStepText`<br>`UI.yStepText`<br>`UI.feedText`<br>`UI.stopManualMotion`<br>`UI.requestPenActuation`<br>`UI.penUnavailableReason`<br>`UI.penStateText`<br>`UI.manualMotionModeText`<br>`UI.requestJog` | SwiftUI manual jog/Pen direct workspace consumers | delete | `EA-06` | `swift test --filter PlotterManualMotionEpisodeTests` |
| UI-004 | ui-consumer | `UI.selectToolContactPoint`<br>`UI.toggleLearningMode`<br>`UI.learningModeActionTitle`<br>`UI.learningModeChangeUnavailableReason` | Action Surface point and Learning on/off direct workspace handlers | delete | `EA-04` | `swift test --filter PlotterPointSelectionEpisodeTests` |
| UI-005 | ui-consumer | `PlotterUIIntent.drawingDraft` | EA-09 replaced the direct `UI.drawingDraftSnapshot`/`UI.submitDrawingDraft` consumers with an action member of the immutable `PlotterUIProjection` and exact production sink validation; retained `PlotterDrawingDraftRuntime` still owns draft admission and paper assertion | adapt | `EA-09` | `swift test --filter PlotterEpisodeUIActionabilityTests` |
| UI-006 | ui-consumer | `UI.currentDrawingRunFacts`<br>`UI.paperManagementUnavailableReason` | `currentDrawingRunFacts` is composition-only immutable fact acquisition; SwiftUI presentation and submission use `PlotterDrawingRunSnapshot` and `PlotterDrawingRunIntentSink` without direct workspace semantic authority, while residual paper-management presentation remains later EA-10F scope | adapt | `EA-08B` | `swift test --filter PlotterDrawingRunEpisodeTests` |
| UI-007 | ui-consumer | `UI.recordNewPaperSheetOnCurrentPlane`<br>`UI.recordPaperContactPlaneChanged`<br>`PlotterUIIntent.retainedLearningAction`<br>`PlotterUIIntent.retainedLearningReset` | EA-09 replaced direct `UI.performLearningVacate`, `UI.performResetAllLearning`, and `UI.learningAuthorityError` consumers with exact canonical Learning action decisions, immutable membership/availability, and typed sink routing; the sink resolves that exact canonical action before retained-owner dispatch, while Saved Learning/reset/paper lifecycle semantics remain EA-10F authority | adapt | `EA-09` | `swift test --filter PlotterEpisodeUIActionabilityTests` |
| UI-008 | ui-consumer | `UI.plotterUIProjection`<br>`UI.submitPlotterUIRequest`<br>`PlotterLearningActionabilityFactAdapter`<br>`PlotterLearningDetailedPresentationNormalizer` | SwiftUI consumes one immutable aggregate `PlotterUIProjection` and submits through one UI-revision/runtime-revision-bound typed `PlotterUIIntentSink`; the App fact adapter only translates Runtime facts into copied PlotterUI facts and the detailed normalizer only renders canonical decisions cosmetically, so none owns Learning actionability, controller, camera, Vision, persistence, Stop, or episode admission | adapt | `EA-09` | `swift test --filter PlotterEpisodeUIActionabilityTests` |
| UI-009 | ui-consumer | `UI.performApplicationStartup`<br>`UI.shutdown` | application lifecycle direct workspace consumer | delete | `EA-11C` | `swift test --filter PlotterEpisodeCompositionTests` |
| UI-010 | ui-consumer | `UI.currentBoundaryExternalFacts`<br>`UI.installBoundarySnapshot` | `PlotterBoundaryComposition`; composition-only acquisition of copied immutable Boundary external facts and installation of runtime-owned immutable snapshots; its EA-10G speech-effect dependency invokes the typed runtime directly before LIVE Boundary motion, so no workspace advisory forwarding seam remains. Neither retained seam owns semantic admission, actionability, effect, Stop, settlement, evidence, controller, announcement, or UI authority | adapt | `EA-10B` | `swift test --filter PlotterBoundaryEpisodeTests` |
| UI-011 | ui-consumer | `UI.executeCameraCalibrationEffect`<br>`UI.isShutdown` | `PlotterApplicationRuntimeCameraCalibrationEffectPort`; App composition forwards one typed lower camera-calibration effect request and observes root admission closure for the typed `PlotterCameraCalibrationRuntime`; it owns no typed admission, active task, terminal history, Stop/shutdown decision, or evidence authority | adapt | `EA-10C` | `swift test --filter PlotterCameraCalibrationEpisodeTests` |
| UI-012 | ui-consumer | `UI.executeArtifactResetEffect`<br>`UI.persistArtifactReset` | `PlotterApplicationRuntimeArtifactResetRelay`; App composition forwards only lower effect and persistence requests for `PlotterArtifactResetRuntime`. It owns no artifact/reset intent admission, task, state, terminal, possible-ink/Stop decision, durable ordering, shutdown decision, or UI authority | adapt | `EA-10F` | `swift test --filter PlotterArtifactResetEpisodeTests` |
| FIX-001 | high-level-fixture | `SimulatedWorkspaceHarness`<br>`makeSimulatedHarness`<br>`performPublicAction` | high-level workspace closure fixture bypassing target intent/event seams | delete | `EA-07` | `swift test --filter PlotterCausalEpisodeEnvironmentTests` |
| FIX-002 | high-level-fixture | `LowerMachineSessionFixture` | focused lower nominal test fixture; tests exercise `PlotterControllerSessionRuntime` through typed requests and a `PlotterMachineSession` port, with no high-level workspace handler or completion bypass | adapt | `EA-11A` | `swift test --filter PlotterControllerSessionEpisodeTests` |
| FIX-003 | high-level-fixture | `TestObservationCameraSession`<br>`TestObservationCameraSessionPort` | focused nominal lower observation-camera fixture and port; tests submit typed observation requests through the runtime and cannot bypass source/configuration admission or lower effect ordering | adapt | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| FIX-004 | high-level-fixture | `PlotterPenInteractionEpisodeTests.startReady`<br>`PenInteractionPortFixture` | focused typed-admission prerequisite and nominal lower-port fixtures only; tests submit exact runtime intents and cannot complete cap identification, Pen Interaction, or terminal settlement through a high-level helper; `completePenInteraction`, `identifyPenCap`, and `finishPenInteraction` are retired | adapt | `EA-10A` | `swift test --filter PlotterPenInteractionEpisodeTests` |
| FIX-005 | high-level-fixture | `PlotterBoundaryEpisodeTests`<br>`BoundaryEpisodeEffectPort`<br>`submitRenderedBoundaryAcquisition`<br>`submitRenderedBoundaryStop` | focused typed Boundary suite plus nominal lower-effect port and production-route fixtures that submit the exact rendered direction selection, acquisition, and capability-bound Stop; no fixture can complete Boundary acquisition, center travel, cancellation, settlement, or publication through a generic start or direct workspace submission helper; `completeLiveBoundaries`, `completeSimulatedBoundariesAndCenter`, and test calls to `submitBoundaryIntent` are retired and remain separately enforced by EA-10B DELETE scans | adapt | `EA-10B` | `swift test --filter PlotterBoundaryEpisodeTests` |
| FIX-006 | high-level-fixture | `PlotterTipCalibrationEpisodeTests`<br>`TipPortFixture` | focused typed runtime-admission suite and nominal lower effect-port fixture only; the deleted `completeSimulatedSparseTipCalibration` high-level helper remains EA-10D deletion authority | adapt | `EA-10D` | `swift test --filter PlotterTipCalibrationEpisodeTests` |
| FIX-007 | high-level-fixture | `PlotterBorderValidationEpisodeTests`<br>`BorderValidationPortFixture` | focused typed Border runtime suite and nominal lower effect-port fixture only; the deleted `completeSimulatedStageFour` and `completeSimulatedBorderValidation` high-level helpers remain EA-10E deletion authority | adapt | `EA-10E` | `swift test --filter PlotterBorderValidationEpisodeTests` |
| FIX-008 | high-level-fixture | `drawingPresentationTestFrame` | deleted direct Drawing Studio presentation-construction helper; retired with the EA-08A draft/presentation fixture cutover | delete | `EA-08A` | `swift test --filter PlotterDrawingDraftEpisodeTests` |
| FIX-009 | high-level-fixture | `manualCameraSnapshotPreservesExactFrame` | test-only consumer of unbound startup frame recorder | delete | `EA-05A` | `swift test --filter PlotterRecordingStoreTests` |
| FIX-010 | high-level-fixture | `SimulatedGRBLLink`<br>`ControllerTranscriptFixtures`<br>`DeterministicRuntimeClock` | low-level deterministic controller transcript/replay fixtures | retain | `EA-05B` | `swift test --filter PlotterRecordingReplayTests` |
| FIX-011 | high-level-fixture | `PaperSceneSimulator`<br>`BlockingMachineLink` | causal paper and bounded controller-fault fixtures | retain | `EA-07` | `swift test --filter PlotterCausalEpisodeEnvironmentTests` |
| FIX-012 | high-level-fixture | `ScriptedSpeechAnnouncer`<br>`BlockingSpeechAnnouncer` | focused lower `SpeechAnnouncing` test doubles for typed runtime terminal and shutdown behavior; the retired app-level `AnnouncementFixture` closure is enforced by EA-10G's exact deletion scan | adapt | `EA-10G` | `swift test --filter PlotterSpeechEffectEpisodeTests` |
| FIX-013 | high-level-fixture | `TestInspectionSuspension`<br>`TestConfigurationSuspension` | focused nominal lower-port suspension fixtures used to hold inspection/configuration at a deterministic await boundary; they cannot complete a camera request, create analysis traffic, or bypass typed observation admission | adapt | `EA-11B` | `swift test --filter PlotterObservationConfigurationEpisodeTests` |
| FIX-014 | high-level-fixture | `WorkflowTelemetryFixture` | app-level diagnostic closure fixture | adapt | `EA-05A` | `swift test --filter PlotterRecordingStoreTests` |
| FIX-015 | high-level-fixture | `PlotterArtifactResetEpisodeTests`<br>`ArtifactResetPortFixture`<br>`AcceptedLearningPathLegacyMigrationTests`<br>`PlotterApplicationRuntimeTests` | focused typed artifact/reset runtime, nominal effect/persistence port, one-shot legacy migration, and production root routing fixtures; none can bypass runtime admission, durable-before-projection ordering, or shutdown | adapt | `EA-10F` | `swift test --filter PlotterArtifactResetEpisodeTests` |

### Current target-topology manifest

The EA-01 table above remains historical current-source characterization. The
following manifest is the exact positive topology after EA-12C and is what the
inventory checker discovers in the current candidate. Historical EA-11C names
remain only in its completed ledger/deletion evidence.

| Target ID | Required target seams | Exact topology obligation |
| --- | --- | --- |
| ROOT-001 | `PlotterApplicationRuntime`<br>`import EpisodeRuntime` | One MainActor application composition/runtime in `PlotterApp`; `PlotterApp` has a direct SwiftPM dependency on `EpisodeRuntime`. The root composes named feature runtimes without absorbing their internal state/task/Stop authority. |
| STATE-001 | `PlotterApplicationEnvironmentState`<br>`PlotterApplicationState.environmentStates` | One canonical residual application schema/map indexed by the typed source; no parallel `liveLearningSession`, `simulatedLearningSession`, or computed `activeLearningSession` authority remains. |
| INGRESS-001 | `PlotterUIIntentSink.submitPlotterUIRequest` | `PlotterApplicationRuntime` is the one production public `PlotterUIIntentSink` conformer. Every submission is bound to an exact immutable projection member/revisions before delegation to a typed feature runtime; no redundant root `PlotterIntentGateway` reevaluator or competing public application ingress exists. |
| OPR-001 | `PlotterLearningEpisodeRecord`<br>`PlotterLearningEpisodeID`<br>`PlotterLearningTransitionID`<br>`PlotterApplicationLearningTask` | The model record owns bounded ordered Learning admission/result truth, while the root task exists only to cancel/join a genuinely asynchronous admitted transition. Named feature runtimes retain distinct tasks, handles, Stop lanes, effects, and journals. A task dictionary, closure registry, second semantic latch, or second journal is forbidden. |
| PRT-009 | `PlotterApplicationResidualEffectPort.discoverSerialDevices`<br>`PlotterApplicationResidualEffectPort.nowNanoseconds`<br>`PlotterApplicationResidualEffectPort.recordWorkflowTelemetry`<br>`PlotterApplicationStatePersistencePort.loadAcceptedLearningPathCheckpoint`<br>`PlotterApplicationStatePersistencePort.saveAcceptedLearningPathCheckpoint`<br>`PlotterApplicationStatePersistencePort.clearAcceptedLearningPathCheckpoint`<br>`PlotterApplicationStatePersistencePort.persistPaperRevisionContext` | Nominal root residual effect and persistence methods replace the deleted `WorkflowTelemetryActions` and `AcceptedLearningPathCheckpointActions` closure façades. These ports mint no admission, task, Stop, or terminal authority. |
| PRT-008 | `PlotterBoundaryEffectPort`<br>`PlotterBoundaryPersistencePort`<br>`PlotterArtifactResetEffectPort`<br>`PlotterArtifactResetPersistencePort`<br>`PlotterCameraCalibrationEffectPort`<br>`PlotterTipCalibrationEffectPort` | Named nominal feature effect/persistence ports replace arbitrary root effect/persistence closures. No port may mint admission or Stop authority; every persistence port commits the accepted candidate before projection or successful terminal publication. |
| LIFE-001 | `PlotterApplicationRuntime.admissionState`<br>`PlotterApplicationRuntime.shutdown` | `shutdown` synchronously latches root admission closed on MainActor before any await. It cancels the exact transition-keyed retained Learning task, closes the Pen owner, joins that task, and then closes/cancels/joins every named feature runtime; timeout, cancellation, persistence failure, or a nonterminal owner remains visible and cannot publish false termination/quiescence. |
| FIX-016 | `PlotterEpisodeCompositionTests` | A discoverable seven-test focused suite exercises production-root projection-bound submission, stable ordered Learning episode transitions, transition-keyed task cancel/join, close-before-await, ordered persistence, exact remaining-owner reporting, and no false termination/quiescence. High-level completion helpers cannot bypass these paths. |

Historical EA-10B composition used `UI.announceBoundaryAdvisory` as the
Boundary workspace advisory seam. In that historical three-seam composition,
none of the three seams owns semantic admission, actionability, effect, Stop,
settlement, evidence, controller, announcement, or UI authority. EA-10G retired
and deleted the announcement seam in favor of the typed
`PlotterSpeechEffectRuntime`; live inventory now contains only the truthful two
non-owning Boundary workspace seams plus `PlotterSpeechEffectRuntime` as
speech-effect authority.

### Exact cutover zero-match scans

`Scripts/check_episode_cutover.sh <PACKAGE-ID>` reads this closed table. Paths
are repository-relative comma-separated globs and every literal is matched
without regex interpretation. Each named cutover must pass all of its rows;
unknown/non-cutover IDs are rejected. Retained lower-level owners are
deliberately absent from deletion scans.

| Package | Scan class | Paths | Zero-match literal |
| --- | --- | --- | --- |
| `EA-04` | deleted-symbol | `Sources/PlotterApp/*.swift` | `ActionSurfacePointSelectionRequest` |
| `EA-04` | deleted-symbol | `Sources/PlotterApp/*.swift` | `ActionSurfacePointSelectionPurpose` |
| `EA-04` | deleted-symbol | `Sources/PlotterApp/*.swift` | `ActionSurfacePointSelection` |
| `EA-04` | deleted-symbol | `Sources/PlotterApp/*.swift` | `ToolContactSelectionContext` |
| `EA-04` | deleted-symbol | `Sources/PlotterApp/*.swift` | `PenCapAppearanceSelectionContext` |
| `EA-04` | deleted-symbol | `Sources/PlotterApp/*.swift` | `PenCapAcceptedClickContinuationIdentity` |
| `EA-04` | deleted-symbol | `Sources/PlotterApp/*.swift` | `ToolContactSelectionState` |
| `EA-04` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `selectToolContactPoint` |
| `EA-04` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `toggleLearningMode` |
| `EA-04` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `learningModeActionTitle` |
| `EA-04` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `learningModeChangeUnavailableReason` |
| `EA-04` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `selectPoint:` |
| `EA-04` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `toggleLearning:` |
| `EA-04` | task-owner | `Sources/PlotterApp/*.swift` | `penCapAcceptedClickContinuationTask` |
| `EA-04` | task-owner | `Sources/PlotterApp/*.swift` | `penCapAcceptedClickContinuationIdentity` |
| `EA-04` | task-owner | `Sources/PlotterApp/*.swift` | `penCapVisionReconfigurationTask` |
| `EA-04` | task-owner | `Sources/PlotterApp/*.swift` | `penCapVisionReconfigurationIdentity` |
| `EA-04` | task-owner | `Sources/PlotterApp/*.swift` | `startPenCapAcceptedClickContinuation` |
| `EA-04` | task-owner | `Sources/PlotterApp/*.swift` | `startPenCapVisionReconfiguration` |
| `EA-04` | task-owner | `Sources/PlotterApp/*.swift` | `cancelPenCapAcceptedClickContinuation` |
| `EA-04` | task-owner | `Sources/PlotterApp/*.swift` | `penCapAcceptedClickContinuationStillOwnsAttempt` |
| `EA-04` | task-owner | `Sources/PlotterApp/*.swift` | `penCapVisionReconfigurationStillOwnsAttempt` |
| `EA-04` | task-owner | `Sources/PlotterApp/*.swift` | `finishPenCapAcceptedClickContinuation` |
| `EA-04` | task-owner | `Sources/PlotterApp/*.swift` | `finishPenCapVisionReconfiguration` |
| `EA-04` | deleted-symbol | `Sources/PlotterApp/*.swift` | `toolContactSelection` |
| `EA-04` | deleted-symbol | `Sources/PlotterApp/*.swift` | `frozenToolContactSelectionFrame` |
| `EA-04` | deleted-symbol | `Sources/PlotterApp/*.swift` | `penCapAppearanceSelectionContext` |
| `EA-04` | deleted-symbol | `Sources/PlotterApp/*.swift` | `toolContactPointSelectionRequest` |
| `EA-04` | deleted-symbol | `Sources/PlotterApp/*.swift` | `PointSelectionPresentationContext` |
| `EA-04` | deleted-symbol | `Sources/PlotterApp/*.swift` | `context.request.matches(context.frame)` |
| `EA-04` | task-owner | `Sources/PlotterApp/*.swift` | `cancelPointSelectionContinuation` |
| `EA-04` | fixture | `Tests/PlotterAppTests/*.swift` | `submitPenCapClick` |
| `EA-04` | duplicate-ingress | `Sources/PlotterApp/*.swift, Tests/PlotterAppTests/*.swift` | `submitCurrentPenCapPoint` |
| `EA-04` | task-owner | `Sources/PlotterApp/*.swift, Tests/PlotterAppTests/*.swift` | `awaitPenCapAcceptedClickTransition` |
| `EA-04` | forbidden-conformance | `Sources/PlotterEpisodeModel/**/*.swift, Sources/PlotterEpisodeRuntime/**/*.swift` | `@unchecked Sendable` |
| `EA-04` | task-owner | `Sources/PlotterEpisodeRuntime/**/*.swift, Tests/**/*.swift` | `awaitContinuationSettlement` |
| `EA-06` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `stopManualMotion` |
| `EA-06` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `func requestJog(_ direction: JogDirection) async` |
| `EA-06` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `func requestPenActuation(_ command: PenCommand) async -> PenOutcome?` |
| `EA-06` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `requestRelativeJog` |
| `EA-06` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `requestManualDrawingStroke` |
| `EA-06` | environment-branch | `Sources/PlotterApp/*.swift` | `requestSimulatedRelativeJog` |
| `EA-06` | environment-branch | `Sources/PlotterApp/*.swift` | `requestSimulatedManualMotion` |
| `EA-06` | deleted-symbol | `Sources/PlotterApp/*.swift` | `var manualMotionPresentation:` |
| `EA-06` | deleted-symbol | `Sources/PlotterApp/*.swift` | `xStepText` |
| `EA-06` | deleted-symbol | `Sources/PlotterApp/*.swift` | `yStepText` |
| `EA-06` | deleted-symbol | `Sources/PlotterApp/*.swift` | `feedText` |
| `EA-06` | deleted-symbol | `Sources/PlotterApp/*.swift` | `manualMotionPenState` |
| `EA-06` | deleted-symbol | `Sources/PlotterApp/*.swift` | `lastManualMotionWasDrawing` |
| `EA-06` | deleted-symbol | `Sources/PlotterApp/*.swift` | `lastManualMotionMayHaveProducedInk` |
| `EA-06` | deleted-symbol | `Sources/PlotterApp/*.swift` | `ContextualStopTarget.manualJog` |
| `EA-06` | deleted-symbol | `Sources/PlotterApp/*.swift` | `ContextualStopTarget.manualDrawingStroke` |
| `EA-06` | deleted-symbol | `Sources/PlotterApp/*.swift` | `directCarriageMotionUnavailableReason` |
| `EA-06` | deleted-symbol | `Sources/PlotterApp/*.swift` | `directManualMotionUnavailableReason` |
| `EA-06` | deleted-symbol | `Sources/PlotterApp/*.swift` | `directMotionUnavailableReason` |
| `EA-06` | deleted-symbol | `Sources/PlotterApp/*.swift` | `motionUnavailableReason` |
| `EA-06` | deleted-symbol | `Sources/PlotterApp/*.swift` | `ordinaryRelativeJogUnavailableReason` |
| `EA-06` | deleted-symbol | `Sources/PlotterApp/*.swift` | `penUnavailableReason` |
| `EA-06` | deleted-symbol | `Sources/PlotterApp/*.swift` | `simulatedManualMotionUnavailableReason` |
| `EA-06` | direct-port | `Sources/PlotterApp/*.swift` | `machineActions.beginRelativeJog` |
| `EA-06` | direct-port | `Sources/PlotterApp/*.swift` | `machineActions.requestPenActuation` |
| `EA-06` | fixture | `Tests/PlotterAppTests/*.swift` | `isolatedMachineActions` |
| `EA-07` | environment-branch | `Sources/PlotterApp/*.swift` | `requestSimulatedRelativeJog` |
| `EA-07` | environment-branch | `Sources/PlotterApp/*.swift` | `executeSimulatedBoundaryMotion` |
| `EA-07` | environment-branch | `Sources/PlotterApp/*.swift` | `simulatedLearningRuntime.requestManualMotion` |
| `EA-07` | fixture | `Tests/PlotterAppTests/*.swift` | `SimulatedWorkspaceHarness` |
| `EA-08A` | deleted-symbol | `Sources/PlotterApp/*.swift` | `drawingStudioDraftMutationIsAvailable` |
| `EA-08A` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `rebuildDrawingStudioPlan` |
| `EA-08A` | direct-port | `Sources/PlotterApp/*.swift` | `DrawingPlanner.plan` |
| `EA-08A` | fixture | `Tests/PlotterAppTests/*.swift` | `drawingPresentationTestFrame` |
| `EA-08B` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `runDrawingStudioPlan` |
| `EA-08B` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `performCompletedComparisonReviewAction` |
| `EA-08B` | direct-port | `Sources/PlotterApp/*.swift` | `machineActions.beginDrawingPlan` |
| `EA-08B` | direct-port | `Sources/PlotterApp/*.swift` | `cameraActions.observePlannedDrawingInk` |
| `EA-08B` | fixture | `Tests/PlotterAppTests/*.swift` | `makeDrawingStudioRunRecord` |
| `EA-09` | deleted-symbol | `Sources/PlotterApp/*.swift` | `LearningPathProjectionSnapshot` |
| `EA-09` | deleted-symbol | `Sources/PlotterApp/*.swift` | `LearningPathProjector` |
| `EA-09` | forbidden-import | `Sources/PlotterUI/*.swift` | `import PlotterRuntime` |
| `EA-09` | duplicate-ingress | `Sources/PlotterApp/*.swift,Tests/PlotterAppTests/*.swift` | `appRequest(` |
| `EA-09` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `extension PlotterUICompiler` |
| `EA-09` | duplicate-ingress | `Sources/PlotterApp/LearningPathView.swift` | `actionWorkspace.performExerciseAction` |
| `EA-09` | duplicate-ingress | `Sources/PlotterApp/LearningPathView.swift` | `actionWorkspace.performLearningVacate` |
| `EA-09` | duplicate-ingress | `Sources/PlotterApp/LearningPathView.swift` | `actionWorkspace.performResetAllLearning` |
| `EA-09` | duplicate-ingress | `Sources/PlotterApp/LearningPathView.swift` | `actionWorkspace.selectToolContactPoint` |
| `EA-09` | duplicate-ingress | `Sources/PlotterApp/LearningPathView.swift` | `actionWorkspace.performCompletedComparisonReviewAction` |
| `EA-09` | task-owner | `Sources/PlotterApp/LearningPathView.swift` | `Task { await perform` |
| `EA-09` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `ExerciseActionDescriptor(` |
| `EA-09` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `-> LearningPathStageStatus` |
| `EA-09` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `intent: .retainedLearningAction` |
| `EA-09` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `intent: .retainedLearningReset` |
| `EA-09` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `reachability: .learningOwner` |
| `FIX-03` | task-owner | `Sources/PlotterApp/OperatorWorkspace.swift` | `drawingRunTask` |
| `EA-10A` | deleted-symbol | `Sources/PlotterApp/*.swift` | `penAttemptHistory` |
| `EA-10A` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `beginPenInteraction` |
| `EA-10A` | task-owner | `Sources/PlotterApp/*.swift` | `penSetpointActuationTask` |
| `EA-10A` | fixture | `Tests/PlotterAppTests/*.swift` | `completePenInteraction` |
| `EA-10A` | duplicate-ingress | `Sources/PlotterApp/LearningPathPresentation.swift` | `case setPenSetpoint(` |
| `EA-10A` | deleted-symbol | `Sources/PlotterApp/*.swift` | `penInteractionSequenceUnavailableReason` |
| `EA-10A` | fixture | `Tests/PlotterAppTests/*.swift` | `identifyPenCap(` |
| `EA-10A` | fixture | `Tests/PlotterAppTests/*.swift` | `finishPenInteraction(` |
| `EA-10B` | deleted-symbol | `Sources/PlotterApp/OperatorWorkspace.swift` | `boundarySideAggregates` |
| `EA-10B` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `beginPairedBoundarySide` |
| `EA-10B` | direct-port | `Sources/PlotterApp/*.swift` | `machineActions.beginBoundaryMotion` |
| `EA-10B` | task-owner | `Sources/PlotterApp/*.swift` | `boundaryMotionTask` |
| `EA-10B` | fixture | `Tests/PlotterAppTests/*.swift` | `completeLiveBoundaries` |
| `EA-10B` | fixture | `Tests/PlotterAppTests/*.swift` | `completeSimulatedBoundariesAndCenter` |
| `EA-10B` | fixture | `Tests/PlotterAppTests/*.swift` | `submitBoundaryIntent(` |
| `EA-10B` | fixture | `Tests/PlotterAppTests/PlotterBoundaryEpisodeTests.swift` | `.start` |
| `EA-10C` | deleted-symbol | `Sources/PlotterApp/*.swift` | `currentCameraCalibrationPhase` |
| `EA-10C` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `runCameraCalibrationAndBuildProposal` |
| `EA-10C` | task-owner | `Sources/PlotterApp/*.swift` | `currentCameraCalibrationTask` |
| `EA-10C` | fixture | `Tests/PlotterAppTests/*.swift` | `stageMachineCameraRegistrationProposal` |
| `EA-10D` | deleted-symbol | `Sources/PlotterApp/*.swift` | `SparseTipCalibrationCoordinator` |
| `EA-10D` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `drawFourCornerTipCircles` |
| `EA-10D` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `undoLastSparseTipClick` |
| `EA-10D` | fixture | `Tests/PlotterAppTests/*.swift` | `completeSimulatedSparseTipCalibration` |
| `EA-10E` | deleted-symbol | `Sources/PlotterApp/*.swift` | `DrawingTrialState` |
| `EA-10E` | deleted-symbol | `Sources/PlotterApp/*.swift` | `ObservedDrawingTrialStep` |
| `EA-10E` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `runObservedDrawingTrial` |
| `EA-10E` | task-owner | `Sources/PlotterApp/*.swift` | `activeExplorationOperation` |
| `EA-10E` | fixture | `Tests/PlotterAppTests/*.swift` | `completeSimulatedStageFour` |
| `EA-10E` | fixture | `Tests/PlotterAppTests/*.swift` | `completeSimulatedBorderValidation` |
| `EA-10E` | deleted-symbol | `Sources/**/*.swift,Tests/**/*.swift` | `.drawingTrial` |
| `EA-10E` | deleted-symbol | `Sources/**/*.swift,Tests/**/*.swift` | `.observedDrawingTrial` |
| `EA-10E` | deleted-symbol | `Sources/**/*.swift,Tests/**/*.swift` | `drawingTrial` |
| `EA-10E` | deleted-symbol | `Sources/**/*.swift,Tests/**/*.swift` | `observedDrawingTrial` |
| `EA-10F` | deleted-symbol | `Sources/PlotterApp/*.swift` | `SavedLearningPackageState` |
| `EA-10F` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `useSavedTraining` |
| `EA-10F` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `performResetAllLearning` |
| `EA-10F` | task-owner | `Sources/PlotterApp/*.swift` | `savedTrainingComparisonTask` |
| `EA-10F` | fixture | `Tests/PlotterAppTests/*.swift` | `LearningPathCheckpointBox` |
| `EA-10F` | deleted-symbol | `Sources/**/*.swift,Tests/**/*.swift` | `AcceptedArtifactCheckpointStore` |
| `EA-10F` | deleted-symbol | `Sources/**/*.swift,Tests/**/*.swift` | `AcceptedTipCalibrationCheckpointStore` |
| `EA-10G` | deleted-symbol | `Sources/PlotterApp/*.swift` | `AnnouncementActions` |
| `EA-10G` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `announceAdvisory` |
| `EA-10G` | direct-port | `Sources/PlotterApp/*.swift` | `announcementActions?.announce` |
| `EA-10G` | fixture | `Tests/PlotterAppTests/*.swift` | `AnnouncementFixture` |
| `EA-11A` | deleted-symbol | `Sources/PlotterApp/*.swift` | `struct MachineActions` |
| `EA-11A` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `performControllerConnectionAction` |
| `EA-11A` | direct-port | `Sources/PlotterApp/*.swift` | `machineActions.` |
| `EA-11A` | task-owner | `Sources/PlotterApp/*.swift` | `pendingBoundaryStopCapabilities` |
| `EA-11A` | fixture | `Tests/PlotterAppTests/*.swift` | `MachineFixture` |
| `EA-11B` | deleted-symbol | `Sources/PlotterApp/*.swift` | `struct CameraActions` |
| `EA-11B` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `setVisionAnalysisCadence` |
| `EA-11B` | direct-port | `Sources/PlotterApp/*.swift` | `cameraActions.` |
| `EA-11B` | task-owner | `Sources/PlotterApp/*.swift` | `visionUpdateTask` |
| `EA-11B` | fixture | `Tests/PlotterAppTests/*.swift` | `CameraFixture` |
| `EA-11C` | deleted-symbol | `Sources/PlotterApp/*.swift` | `final class OperatorWorkspace` |
| `EA-11C` | deleted-symbol | `Sources/PlotterApp/*.swift` | `ActiveStoppableOperation` |
| `EA-11C` | deleted-symbol | `Sources/PlotterApp/*.swift` | `LearningSessionState` |
| `EA-11C` | duplicate-ingress | `Sources/PlotterApp/*.swift` | `performExerciseAction` |
| `EA-11C` | direct-port | `Sources/PlotterApp/*.swift` | `@Sendable (` |
| `EA-11C` | task-owner | `Sources/PlotterApp/*.swift` | `activeLearningActionTask` |
| `EA-11C` | fixture | `Tests/PlotterAppTests/*.swift` | `func workspace(` |
| `EA-11C` | forbidden-import | `Sources/PlotterUI/*.swift` | `import PlotterRuntime` |
| `EA-11C` | environment-branch | `Sources/PlotterApp/*.swift` | `activeLearningSession` |
| `FIX-05` | deleted-symbol | `Sources/PlotterApp/*.swift` | `drawingRunFactSource` |
| `FIX-05` | direct-port | `Sources/PlotterApp/*.swift` | `drawingRunFactSource` |
| `FIX-05` | deleted-symbol | `Sources/PlotterApp/*.swift` | `drawingRunInterpreterPort` |
| `FIX-05` | direct-port | `Sources/PlotterApp/*.swift` | `drawingRunInterpreterPort` |
| `FIX-05` | deleted-symbol | `Sources/PlotterApp/*.swift` | `drawingRunCameraPort` |
| `FIX-05` | direct-port | `Sources/PlotterApp/*.swift` | `drawingRunCameraPort` |

### EA-12 consolidation inventory and deletion obligations

DOC-05 adds this future-slice inventory beside, not inside, the immutable EA-01
baseline. Every row is fail-closed: the named slice must prove the owner/result
contract and the exact zero-consumer or zero-match obligation in the same
landing. `AFFECTED-CONSUMERS` runs the listed consumer-only procedures before
`DELETE`; `DELETE` repeats them and fails if a named superseded declaration,
opaque ingress, semantic side registry, ID recompilation, silent nil dispatch,
or dead UI symbol remains. A remaining use is acceptable only when the slice
documents a current nonsemantic UI-local layout, viewport, selection, or
unsubmitted-text consumer and the literal is not one of the mandatory deletions
below.

| Slice | Current owner/result contract | Exact affected-consumer procedure | Exact deletion and zero-match obligations |
| --- | --- | --- | --- |
| EA-12A | `PlotterBorderValidationRuntime` is the sole source-indexed mutable Border Validation owner and publishes immutable projection/result values; App is lower-effect composition only | `rg -n -e "currentEnvironmentState\\.borderValidation" -e "environmentStates\\[.*\\]\\?\\.borderValidation" -e "replaceSnapshot" Sources/PlotterApp Sources/PlotterEpisodeRuntime Tests` returns only explicitly historical test evidence; every production mutation or whole-snapshot copy fails | zero production matches for `PlotterApplicationEnvironmentState.borderValidation` (`var borderValidation: PlotterBorderValidationSnapshot`), `currentEnvironmentState.borderValidation`, `replaceSnapshot`, and `case retryFrom(`; `ContextualStopActionPresentation`, `StableWorkflowCapCaptureRunner`, and `PlotterSystemSerialDeviceDiscoveryAdapter` have zero consumers and are deleted |
| EA-12B | `PlotterEpisodeModel` owns typed Learning item/action/request identity and availability end-to-end through immutable `PlotterUI` projection, the one public `PlotterUIIntentSink`, and the exact feature runtime | `rg -n -e "PlotterApplicationBoundAction" -e "currentApplicationActions" -e "currentPlotterUIResetPlans" -e "applicationAction" -e "retainedLearningAction" -e "retainedLearningReset" -e "String\\(describing: action" -e "String\\(describing: kind" Sources/PlotterApp Sources/PlotterUI Sources/PlotterEpisodeModel Tests` must find no App semantic registry/recompiler and no opaque UI intent; rendered-action tests enumerate every enabled effect-bearing control and exact projected request | delete `PlotterApplicationBoundAction`, `currentApplicationActions`, `currentPlotterUIResetPlans`, `PlotterUIIntent.applicationAction`, `PlotterUIIntent.retainedLearningAction`, `PlotterUIIntent.retainedLearningReset`, `retainedLearningAction(for:)`, dead IDs `controllerProbe`, `observationStop`, and `observationRestart`, plus zero-consumer `ActionSurfaceOverlayStyleToken`/`styleToken(for:)`; zero production matches for `.discardCameraSamples` and **Discard Camera Samples** until a real current sample-owning typed intent exists and for the silent placement branch `guard let request = plotterUIProjection.request(matching: .drawingDraft(intent)) else { return }` |
| EA-12C | one stable model-owned `PlotterLearningEpisodeID` plus bounded ordered `PlotterLearningTransitionID` record spans retained feature runtimes; each effect-bearing transition admits one exact `PlotterLearningRecordRequest` action/reset union value and publishes one typed result plus bounded immutable post-transition projection after owner settlement without merging unrelated feature journals | `rg -n -e "intentIdentity: \\.learningAction" -e "residualLearningAdmissionID" -e "runResidualLearningAction" -e "performAdmittedExerciseAction" Sources/PlotterApp Sources/PlotterEpisodeModel Sources/PlotterEpisodeRuntime Tests` shows only the typed model request/result/record route and no direct semantic ingress; rendered slider/direction tests prove exact per-value/per-option candidates survive projection unchanged | residual unjournaled per-click `UUID()` Learning-operation identity, reflected `.learningAction("...String(describing:)...")` identity, duplicate retained-action ingress, and owner/title/number reconstruction are deleted; every effect-bearing Learning action/reset has a typed request, accepted/refused event, typed result, and bounded immutable post-transition projection; distinct feature runtime task/effect/Stop ownership remains and journals are never fabricated or merged |

The rendered-control proof for EA-12B/EA-12C must additionally cover default
Learning actions, tip fitting/commit/revalidation, Drawing Placement, completed-
comparison controls, Drawing Studio, and every other effect-bearing control.
**Retry Calibration Commit** is absent while commit or revalidation is busy and
is available only for the runtime's exact stable recoverable review state.
**Apply Drawing Placement** is enabled only when its exact placement request is
present in the current projection. An enabled control that can reach nil or
unavailable request dispatch fails `UI-AUTHORITY`, `UI`, and `DELETE`.

## Work ledger

Blackdog owns active task state. This table records only not-started work,
explicit blockers, and landed completion. Never mark a row active here.

Execution classes are `repository`, `software`, `authority-slice`,
`attended-physical`, `remote-git`, and `gate`. A direct named request or an
invocation of `$run-multi-agent-wave` may authorize one selectable
`repository`, `software`, or `gate` work item. An `authority-slice` is never
selected, claimed, landed, or evidence-completed independently: its named
tranche is the one Blackdog task/worktree/landing that executes it in order.
Wave selection takes the first eligible selectable row in this table's literal
order and cannot redefine its outcome, dependencies, authority, deletions, or
gates. `attended-physical` and `remote-git` still require their own explicit
package and execution-class authorization; wave or generic authorization is
insufficient.

## Sprint tranche execution

The migration has used four completed selectable software tranches. The most
recent, `TRANCHE-MODEL-UI-CONSOLIDATION`, completed the prerequisite model/UI
authority correction. The user-directed FIX-10 correction now delivers practical
diagnostics and interaction improvements; a complete replay archive is no longer
a prerequisite for using or validating Learning. This changes landing cadence, not product authority: every
`EA-*` row below remains one typed authority slice with its own current owner,
same-slice deletion, build, focused suite, affected-consumer scan, `DIFF`, and
`DELETE` proof. A tranche is complete only when all of its ordered slices are
complete in the same Blackdog landing; no slice can be claimed or marked
complete separately. Contract and capsule admission reject a completed tranche
or successor selection unless its tranche row and every slice completion row
share one nonempty Blackdog task/landing; the capsule carries each slice's
current-owner inventory row and exact same-slice deletion scans.

`DOC-04` is the repository-only predecessor of `TRANCHE-LEARNING`. It does not
move product authority: it makes capsule claim classification fail closed while
separating live Blackdog ownership from terminal, fully cleaned history whose
replay identity is either removed from the ledger or is currently
dependency-ineligible. The diagnostic remains visible and hash-bound; a missing
or unverifiable replay identity, retained owner/worktree/branch, required owner
finalization, active attempt, or current dependency-ready recoverable ordinary
package remains a launch blocker.

1. `TRANCHE-LEARNING` executes `EA-10G`, then `EA-10C`, `EA-10D`, `EA-10E`,
   and `EA-10F` in that exact order.
2. `TRANCHE-DEVICE-ENVIRONMENT` executes `EA-11A`, then `EA-11B`.
3. `TRANCHE-FINAL-COMPOSITION` executes `EA-11C`.
4. `TRANCHE-MODEL-UI-CONSOLIDATION` executed `EA-12A`, then `EA-12B`, then
   `EA-12C`; the completed transaction is the required predecessor of FIX-10.

After the final-composition tranche, `FIX-05` is one ordinary software
correction before `GATE-01`. It removes real remaining application-root
cross-owner adapter authority and installs the executable source-identity
manifests needed by the unchanged Pilot reduction thresholds. It is not a
second tranche, does not absorb any typed feature runtime, and cannot complete
by wrapping, grouping, erasing, or cosmetically renaming retained properties.

The first attended `VAL-01` attempt stopped in section 1 after exact-frame
selection currentness failed and center travel consumed a cached presentation
MPos instead of the latest controller settlement. `FIX-06` is the one ordinary
software correction before another attended attempt. It repairs the single
cross-feature external-fact currentness invariant without transferring device,
evidence, persistence, or feature-runtime authority. The failed physical prefix
remains evidence; it is not replaced by later software or simulator results.

The next attended Exercise 1.4 attempt proved the camera session still produced
frames while the exact point-selection presentation remained intentionally
pinned to its cap-bearing reveal. `FIX-07` adds the missing explicit no-motion
replacement transition before another attended attempt: the tip runtime owns
admission, the point-selection runtime owns atomic exact-request supersession,
and each accepted click retains its independently exact frame without rewriting
the original reveal evidence.

Only a tranche boundary runs `QUICK`, `JOURNEY`, `STRICT`, batched canonical
documentation/evidence synchronization, and at most one bounded fresh-context
critic, with no critic recheck. A critic may block only a red-line defect: compiler or test failure,
duplicate effect-producing authority, unauthorized motion, a Stop/shutdown
race capable of starting effects, automatic retry/redraw with possible ink,
destructive persistence ordering, or fabricated evidence. Record every other
finding in Current Evidence as deferred follow-up without retasking the active
tranche. A red-line final-gate defect may receive one narrow repair and affected
validation, but never reopens criticism. Use high reasoning for implementation and fixture work; use xhigh
only for a tranche critic or tranche-final gates when the task can select a
model. Ordinary software/gate work continues; no tranche authorizes attended
physical or remote-Git work.

`DOC-02` records the operator's acceptance of the pre-migration `main` state as
a rollback checkpoint and retires the unsuccessful BASE-01/BASE-02/BASE-03
campaign from this dependency graph. That decision does not turn its failed
physical evidence into passed evidence, publish a remote ref, or weaken the
final `VAL-01` attended validation boundary.

| ID | Status | Dependencies | Class | Atomic package outcome | Required gates |
| --- | --- | --- | --- | --- | --- |
| DOC-00 | complete | none | repository | Initial canonical docs, observability contract, ledger, and skill landed in `TASK-C86132F1` at `d33d4ff` | `ARCHIVED` |
| DOC-01 | complete | DOC-00 | repository | Canonical vocabulary, incremental cutover, completion hierarchy, execution modes, atomic ledger, evidence-history repair, and contract check delivered by `TASK-F2387A9A` | `DOC`, `DIFF`, `CRITIC` |
| EA-01 | complete | DOC-01 | repository | Exhaustive current intent/guard/owner/port/mode/fixture inventory, retain/adapt/delete dispositions, current owners, cutover packages, exact deleted-symbol/direct-port scans, and exact focused test commands delivered by `TASK-513DC8A7`; no application source changed. | `DOC`, `DIFF`, `INVENTORY` |
| FIX-00 | complete | EA-01 | software | Correction: separate Euclidean controller-pose settlement from drawing-region containment, give each one typed owner/metric/revision, and delete the shared 0.5 mm policy assumption and its tests. Preserve strict accepted-Boundary drawing containment apart from an explicitly justified numerical epsilon. Delivered by `TASK-1B5992CF`. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `FIX-CONTAINMENT` |
| FIX-01 | complete | FIX-00 | software | Correction: prevent projection outside `TipCameraRegistration.applicabilityRectangle` from becoming attributable evidence unless a newly validated evidence-authority revision expands applicability. Delete the evidence bypass assumption and its tests while retaining typed diagnostic-only projection. Delivered by `TASK-05D1DCBD`. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `FIX-APPLICABILITY` |
| DOC-02 | complete | FIX-01 | repository | Operator acceptance of clean `main` commit `256b2a65f4059b6cf0e5c07f5f5305043254fb71` as the local annotated rollback checkpoint `adaptiveplotter-pre-episode-migration-20260825`, retirement of BASE-01/BASE-02/BASE-03 as migration prerequisites without rewriting their failed evidence, deletion of their publication tooling, and restoration of the ordinary software frontier; no remote ref or application source changed. Delivered by `TASK-24BD26E8`. | `DOC`, `DIFF` |
| EA-02A | complete | DOC-02 | software | Foundation: add one compile-only domain-generic `EpisodeCore` contract module containing the canonical value types and pure evaluator/reducer protocols; add no Plotter, device, persistence, UI, effect port, or app caller. Delivered by `TASK-55097CA4`. | `DOC`, `DIFF`, `QUICK`, `CORE` |
| EA-02B | complete | EA-02A | software | Foundation: add one compile-only `PlotterEpisodeModel` contract module that binds concrete Plotter intents, state, events, effects, results, observations, evidence, and assessments to `EpisodeCore`; add no runtime, device port, persistence, UI, or app caller. Delivered by `TASK-B6E16E08`. | `DOC`, `DIFF`, `QUICK`, `PLOTTER-MODEL` |
| EA-03A | complete | EA-02B | software | Foundation: add one unbound `EpisodeStore` service that atomically validates and appends `EpisodeEvent` values to a durable `EpisodeJournal`, owns its one versioned journal-persistence adapter, and reconstructs `EpisodeState`; add no effect lane, operation owner, or app caller. Delivered by `TASK-439EDDB1`. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `STORE` |
| EA-03B | complete | EA-03A | software | Foundation: add one unbound `PlotterOperationRegistry` runtime service whose canonical operation identity binds episode ID, request ID, typed intent identity, effect ID and revision, and typed environment; retain its original typed handle and lane, exact `StopCapability`, and Stop/shutdown cancellation-attempt sharing; mint an operation-bound `CompletionCapability` for direct settlement; validate a typed result or typed refusal before any terminal mutation; keep a refused cancellation attempt recoverably active with durable observability; `start` checks admission before recoverable acceptance so a retained unstarted permit cannot authorize work after shutdown closure, is typed-refused and retired without start/progress mutation, and later correct shutdown settlement can terminalize without fabricated execution; retain the full terminal record; add no journal store, device adapter, or app caller. Correction delivered by `TASK-39BC99B5`. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `RUNTIME` |
| EA-05A | complete | EA-03A | software | Foundation: add one unbound lossless `EpisodeRecordingStore` service with typed controller-transcript and camera-lifecycle/frame channels plus content-addressed frame references; add no current-device hook, effect port, or app caller. Delivered by `TASK-57FE4C62`. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `RECORDING` |
| EA-05B | complete | EA-03A, EA-05A | software | Foundation: add one unbound deterministic transcript replay service whose sealed `PlotterEpisodeReplayExecutableDescriptor` and private concrete adapter own the executable domain, evaluator, reducer, state/event/journal-schema, and build revision facts, a canonical-digest literal pinned to `PlotterEpisodeCanonicalDigestV1.revision`, and deterministic-seed applicability; compare the corresponding manifest executable pins and the descriptor digest pin before reduction; compare definition pins with the supplied typed definition; retain full recorded effect revisions as identity-only facts with no effect-executor revision-validation claim while checking progress/result identity and first-terminal ordering; reconstruct and independently verify every recorded journal prefix with caller-supplied recorded decision frames, failing closed without publishing lifecycle-invalid prefixes; retain emitted effects only as inert values; classify started-unsettled work as possible physical effect with a never-resume disposition; preserve channel-specific recording completeness and attribute start evidence only through exactly one complete available operation-bound provenance tuple; and apply exact replay plus only causality-preserving controller fragmentation, delay, timeout, and cancellation perturbations, prevalidating the source schedule and refusing nil/empty source, absent read traffic, non-read delay, deadline violations for successful or failed reads, delay with timeout/cancellation for one invocation independent of declaration order, and terminal-boundary or downstream-order violations; retime the causal suffix and embedded read chunks with checked overflow or underflow; validate the complete transformed schedule across all outstanding invocations so transforming A cannot push overlapping B past B's deadline or move B traffic before B's invocation, typed-refusing any invalid transformed schedule with unchanged source at the typed transcript layer; add no `MachineLink` conformance, effect executor, permit restoration, device port, app caller, or current-authority transfer. Delivered by `TASK-32F536F4`. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `REPLAY` |
| EA-05C | complete | EA-05B | software | Foundation: add one unbound headless bounded incident-package assembler/exporter that references manifests, journals, recordings, frames, observations, evidence, outcomes, assessments, and runtime/UI revisions; it owns no artifact store, UI, device port, or app caller. Delivered by `TASK-1DDBA6F2`. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `INCIDENT` |
| EA-04 | complete | EA-03B, EA-05B | software | Cutover: transfer exact-frame human point-selection authority to one FIFO mutation/publication boundary, including serialized re-evaluation, transaction-complete selection/observation/evidence publication, exact-owner Learning-Off cancellation, typed refusal for unrelated work, EA-05A camera recording, and an invokable remedy-bearing Learning button; delete old selection state, presentation-context/admission copies, Task-returning cancellation, continuations, closures, guards, and fixtures. Delivered by `TASK-A5FF364B`. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `POINT`, `DELETE` |
| FIX-02 | complete | EA-04, EA-05C | repository | Correct the sole `MachineLink` contract and every production/test conformance to expose transport-discriminated applied-open configuration, exact discard/write/read transfer facts, monotonic receive timestamps, observable close failure, and operation-specific partial-failure progress without a sibling port, default implementation, fabricated values, recorder installation, product-authority transfer, or physical-evidence claim. Delivered by `TASK-30357281`. | `LINK-OBS`, `LINK-SAFETY`, `RUNTIME`, `JOURNEY`, `DOC`, `DIFF`, `QUICK`, `STRICT` |
| EA-06 | complete | EA-04, EA-05C, FIX-02 | software | Cutover: transfer manual jog, async direct manual pen-actuation, exact owner-bound staged Stop with atomic pre-suspension cancellation issuance, shutdown takeover of the same requested owner/handle without journal dependency or duplicate authority, identity-bound `cancelledBeforeStart` retirement with inert later start and zero LIVE/SIMULATED native invocation, a runtime-owned shutdown latch set before the sole registry shutdown suspension and rechecked after accepted progress so the same shutdown terminal is published before active installation or native start, observed/settling `settledByShutdown` handoff that leaves the original public Stop cursor as sole publisher, FIFO-isolated cancellation publication, and pre-gateway active-owner busy refusal, plus required durable episode-journal publication/recovery, typed incident-source references, and EA-05A controller recording authority at `AdaptivePlotter/EpisodeArtifacts/<episode UUID>/controller-recording` through fail-closed environment-bound LIVE/SIMULATED facts and adapters; retain nominal owner-returned operation handles with no arbitrary effect closure or unchecked-sendability escape, give direct Pen no Stop capability, keep the exact owner plus typed cursor and recovery capability when a Stop/terminal append is incomplete including after shutdown, project one capability-only intent-specific recovery that disables manual effects, hides stale Stop, rejects stale capabilities, resumes only the exact runtime cursor, clears only its matching diagnostic, and reissues no controller work, and derive manual availability plus exact effect/environment/observation possible-ink or ambiguity disposition from runtime phase with every effect disabled until matching explicit operator evidence and no retry, redraw, or reissue; bind one operation recorder around the sole production BSD `MachineLink` through terminal LIVE settlement while returning unrepresentable applied-open receipts unchanged, recording no fabricated successful pair, keeping recording-open failure diagnostic-only, and leaving SIMULATED recorder-free; keep recording Store/Replay partial-discard validation identical, and delete old manual ingress, guards, task/cancel owner, mode branches, and direct ports. Completed by `TASK-FE9C9CB3`, attempt `TASK-FE9C9CB3-54834fa90e36`; package EA-06 complete, migration remains incomplete. `CITED_RACE_CLOSED` closes the same-critic delta and no further critic is required or allowed. Blackdog landing/cleanup and successor-capsule creation are the only remaining steps. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `MOTION`, `DELETE` |
| EA-07 | complete | EA-06 | software | Cutover: transfer causal-simulator effect admission, exact raw operation identity, Stop/cancel/shutdown settlement, typed SIMULATED observation/result provenance, and separated controller-command, plant/Pen, paper/ink, camera, Vision, and evidence truth to one production `PlotterCausalSimulatorEffectAdapter`; compose `PlotterManualMotionRuntimeComposition` so its manual runtime and `OperatorWorkspace` share that exact adapter authority; adapt `SimulatedLearningRuntime` to one package-only plant admission; route typed manual jog through `admitManualJog` and retained work through `admitRetainedWorkflowBoundary`, `admitRetainedWorkflowDrawing`, `admitRetainedWorkflowTravel`, and `executeRetainedWorkflowPen` with explicit owner attribution, nil `effectResult`, and no fabricated plan revision; make Pen ingress share adapter occupancy so an exact reserved predecessor causes `.operationAlreadyActive(predecessor.id)` without lower Pen mutation, while an admitted lower Pen mutation and its causal truth are returned atomically by package-only `setPenPoseWithCausalTruth`; retain the active owner from lower terminal settlement through one atomic cached outcome/truth publication so a successor refuses until the predecessor operation ID, observation, disposition, plant/Pen/ink/frame truth, and typed result when applicable are bound together; and delete `beginManualJog`, `beginBoundary`, `beginDrawing`, `executeSimulatedBoundaryMotion`, the App-local simulated adapter, `SimulatedWorkspaceHarness`, `makeSimulatedHarness`, `performPublicAction`, and fake-log authority while retaining adapted later-workflow helpers. A package-only terminal-publication gate proves both retained Pen refusal/no mutation and drawing successor isolation deterministically without sleeps or polling. Delivered by `TASK-6C2D055B`, attempt `TASK-6C2D055B-4df3ee7abec3`, and landed with cleanup verified on canonical `main` at `ac6a6688`; package EA-07 complete, migration remains incomplete. The landed candidate passed `SIM` 15/15, `DELETE` 4/4, `DOC` 29/29, clean `DIFF`, `QUICK` 705/705, `JOURNEY` 7/7, and `STRICT` 712/712 plus its warning-as-error strict-concurrency build, signing, launcher, and negative-bundle checks. The original critic RETASK and correction-cycle-1 RETASK remain nonpass history; the same sole critic's correction-cycle-2 final verdict was exactly `UNANIMOUS PASS — no material disagreement`. Policy allowed one critic and at most two correction/delta cycles, and forbids a post-pass critic. No physical or remote-Git validation occurred or is claimed. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `SIM`, `DELETE` |
| EA-08A | complete | EA-05C, EA-07 | software | Cutover: transfer Drawing Studio draft authority to source-indexed `PlotterDrawingDraftRevision` and `PlotterDrawingDraftExternalFactRevisions`, revision-bound `PlotterDrawingDraftSubmission`, typed `PlotterDrawingDraftIntent`, exact owner/reason/remedy refusals, and immutable `PlotterDrawingDraftSnapshot` publication through one `PlotterDrawingDraftRuntime` and `PlotterDrawingDraftIntentSink`; produce deterministic catalog/program/placement identity and content-addressed plans only through `PlotterDrawingPlanningAdapter`, which is also the sole upper route to retained EA-10E Border planning without moving Border semantics; refuse exact-frame/registration, invalid parameter, stale revision, run-owner, handoff, and outside-region cases without clipping; separate exact-frame/applicability/diagnostic-only preview from evidence; adapt `PlotterDrawingDraftPaperPersistence` with one FIFO mutation boundary around validation, LIVE save, and publication, nominal save-before-publish storage, exact-frame polygon display, and paper/source/configuration/contact-plane currentness; hand one immutable plan to retained EA-08B run authority only after its explicit new-plan handoff, with fresh complete-fact and exact-plan revalidation before its first and later physical-effect boundaries; and delete `DrawingStudioAction`, old draft/open/close/paper-confirm/rebuild ingress, App `DrawingPlanner.plan`, mutable duplicate draft state, `drawingPresentationTestFrame`, and tautological presentation fixtures. Completed only in the task-local candidate by `TASK-5700F7F5`, attempt `TASK-5700F7F5-0ad2465cded1`; package EA-08A complete, migration remains incomplete. All six package gates passed: `DRAW-DRAFT` 17/17, `DELETE` 4/4, `DOC` 29/29, clean `DIFF`, `QUICK` 720/720, and `STRICT` 727/727 plus strict-concurrency warnings-as-errors, signing, launcher, negative-bundle, and documentation checks. Earlier failed/interrupted invocations remain nonpass history. The sole fresh critic returned `RETASK` on a persistence lost-update window, stale retained-run admission, and scale clipping; the corrected focused gate covers all three, and the same critic's delta-only recheck ended exactly `UNANIMOUS PASS — no material disagreement`. Criticism is closed: no new/full or post-pass critic is allowed. No physical or remote-Git validation occurred or is claimed. Blackdog landing, canonical-`main` cleanup verification, and conditional successor-capsule creation remain pending. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `DRAW-DRAFT`, `DELETE` |
| EA-08B | complete | EA-08A | software | Cutover: transfer Drawing Studio run authority to one source-indexed actor `PlotterDrawingRunRuntime` with revision/plan-bound `PlotterDrawingRunSubmission`, typed intents/refusals/remedies, immutable snapshots, FIFO-exclusive admission, exact Stop capability, and RunID-bound review/new-run/publication recovery; revalidate the exact immutable EA-08A plan plus complete facts before effects; execute the LIVE baseline-capture, lower-plan, final-MPos, newer-frame, applicability-aware observation, and append-before-success chain through nominal retained-owner ports; preserve non-attribution outside tip applicability, explicit publication failure, possible-ink/no-redraw truth independent of save, and SIMULATED zero-LIVE-effect refusal; and delete workspace run/review state, latches, closure façade, raw actions/handlers, direct App machine/camera paths, and high-level fixture. Completed only in the task-local candidate by `TASK-51550DB1`, attempt `TASK-51550DB1-84f1763c31b5`; package EA-08B complete, migration remains incomplete. All seven package gates passed: `DOC` 29/29 in 11.35 seconds, clean `DIFF`, `QUICK` 730/730 in 15.19 seconds, `JOURNEY` 7/7 in 6.32 seconds, `STRICT` 737/737 plus 29/29 docs in approximately 112.10 seconds, `DRAW-RUN` 12/12 in 0.343 seconds, and `DELETE` 5/5 in 0.10 seconds. The strict gate included its warnings-as-errors build in 37.85 seconds, strict build in 41.47 seconds, strict test duration 13.565 seconds, stable-local signing, launcher logic/validation, and negative-bundle pass. The sole fresh critic's original verdict was `RETASK`; its correction-cycle-1 exact final verdict was `UNANIMOUS PASS — no material disagreement`, so criticism is closed and no new, full, or post-pass critic is required or allowed. Only Blackdog landing, canonical-`main` cleanup verification, and conditional EA-09 successor-capsule creation remain pending. No attended physical or remote-Git validation occurred or is claimed. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `DRAW-RUN`, `DELETE` |
| EA-09 | complete | EA-04, EA-06, EA-08B | software | Cutover: transfer episode UI presentation authority to `PlotterUI -> PlotterEpisodeModel` only, with one bounded `PlotterUICompiler` over copied candidates and one bounded `PlotterUILearningActionabilityCompiler` that solely decides copied-fact current owner, item status, action/Stop strips, availability, Pen adjustment, direction, and reset reachability; emit one immutable `PlotterUIProjection` that enumerates every rendered semantic action, require exact action-membership/bound-intent/availability/UI-revision/runtime-revision validation in the production sink, and bound diagnostics and UI-local pane/window/viewport/unsubmitted-text reducers. Keep `PlotterLearningActionabilityFactAdapter` as fact translation only and `PlotterLearningDetailedPresentationNormalizer` as cosmetic canonical-decision rendering only; require `OperatorWorkspace` to consume canonical actionability and resolve the exact canonical action before retained-owner dispatch. Route Learning on/off continuation cancellation to EA-04 and Drawing Studio domain-changing open/close actions to EA-08A/EA-08B; delete migrated SwiftUI workspace reads, `appRequest`, App compiler extensions, App-owned Learning status/completion/action-strip/Stop/sparse/actionability compilers, direct Learning point/reset/workspace dispatch, and any renamed or split raw-fact-to-semantic-output mapping proved by the EA-09 behavior/topology checker. Present one App-bound truthful unavailable-source incident lifecycle through request-owned bounded streams around the sole existing `PlotterIncidentPackageAssembler`, with visible format/digest/count/refusal/remedy/`canonicalEnvelopeOnly`/nonphysical metadata; require an exact complete identity for real assembly and fabricate none for the unavailable path. Add no recorder, second/source assembler, artifact store, filesystem/export backend, device port, or physical-evidence claim. Completed only in the task-local candidate by `TASK-D55FD455`, attempt `TASK-D55FD455-1d0731730d03`; package EA-09 complete, migration remains incomplete. All seven package gates passed: `DOC` 29/29 in a final real 14.82 seconds, clean `DIFF` in a real 0.05 seconds, `QUICK` 750/750 after 15.778 seconds in a real 18.22 seconds, `JOURNEY` 7/7 after 7.347 seconds in a real 8.66 seconds, `STRICT` 757/757 plus 29/29 docs in a real 141.81 seconds, `UI` 17/17 after 0.093 seconds in a final real 85.36 seconds, and `DELETE` 16/16 plus topology validation in a real 0.45 seconds. The original critic and correction-cycle-1 verdicts were `RETASK`; correction-cycle-2 ended exactly `UNANIMOUS PASS — no material disagreement`. After stale integration tests caused a 134.84-second QUICK failure/hang, the user authorized one exceptional gate-repair cycle; production source remained unchanged, five test files were repaired, and the same critic's exceptional delta verdict was exactly `UNANIMOUS PASS — no material disagreement`. Final gates then passed, criticism is closed, and no new or post-pass critic occurred. Blackdog landing, canonical-`main` cleanup verification, GATE-01, attended physical validation, and remote-Git action remain pending and are not claimed. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `UI`, `DELETE` |
| FIX-03 | complete | EA-09 | software | Correction: transfer Drawing Run submission and shutdown-quiescence lifetime from the stored `OperatorWorkspace.drawingRunTask` join into the already-authoritative `PlotterDrawingRunRuntime`; make the App sink await runtime submission directly, close runtime admission and await exact active-run terminal publication during shutdown, and delete the workspace task, tracked/untracked start split, and workspace shutdown join. Preserve exact RunID/Stop/cancellation/no-redraw/publication recovery and all retained controller/interpreter/camera/Vision/evidence owners. Add a source-derived EA-01-baselined workspace Task metric that proves direct stored `OperatorWorkspace` Task owners decrease from 9 to 8, with exactly `drawingRunTask` removed relative to the pre-correction EA-09 landing, and reconcile landed Current Evidence without rerunning GATE-01 or starting EA-10A. Completed by `TASK-0A7AB3EE`, attempt `TASK-0A7AB3EE-80f88f4a41d8`; package FIX-03 complete, migration remains incomplete. | `DRAW-RUN`, `TASK-METRIC`, `DELETE`, `DOC`, `DIFF`, `QUICK`, `STRICT` |
| DOC-03 | complete | FIX-03 | repository | Relocate the unchanged `GATE-01` Pilot continuation decision after `EA-11C` because the pre-relocation source-derived measurements proved `operator-workspace-policy-state` remained 6 to 6 and `operator-workspace-adapters` increased from 7 to 10, while the authority transfers required to satisfy those unchanged thresholds belong to EA-10A through EA-11C. Make EA-10A depend on DOC-03 and VAL-01 depend on GATE-01 without moving product authority, weakening any Pilot predicate or threshold, running GATE-01, or claiming it passed. Completed by `TASK-B7C9E592`, attempt `TASK-B7C9E592-3408edcef715`; package DOC-03 complete, migration remains incomplete. Both package gates passed: `DOC` 29/29 in 14.014 seconds with 14.770 seconds wall time and documentation/architecture contracts passed; `DIFF` exit 0 with no output in less than 0.01 seconds. | `DOC`, `DIFF` |
| EA-10A | complete | DOC-03 | software | Cutover: transfer Pen Interaction value-bearing Up/Down intent, revision/operation/cancellation-bound admission, exact task/Stop/settlement/shutdown lifetime, latest-only setpoint coalescing, and immutable attempt evidence to one actor-isolated `PlotterPenInteractionRuntime`; keep exact-frame cap selection in EA-04 and retained controller, simulator, checkpoint, replay, incident, and evidence owners below nominal ports; preserve distinct LIVE/SIMULATED state, truthful refusal/ambiguity/possible-change state, no automatic resend, and no camera or physical-evidence fabrication; delete workspace draft/profile/history/pending-command/task/guard/helper authority plus high-level test fixtures while retaining the terminology constant and canonical PlotterUI intent. The original fresh critic returned `RETASK`: workspace busy feedback made production coalescing unreachable, exact capability-bound Stop and terminal refusal/possible-change truth were dropped, and fresh SIMULATED re-entry retained stale Pen state. Correction cycle 1 removed duplicate workspace busy authority, projected exact Stop/refusal/possible-change truth through a runtime-owned weak projection sink without a workspace observer Task/latch/retry, preserved Pen Interaction through the Learning replacing reset, and reset only simulated Pen state on fresh SIMULATED admission while preserving LIVE. The same critic's cycle-1 delta recheck closed the Stop/truth and SIM blockers but returned `RETASK` on the sole remaining original blocker: confirmation remained reachable before the first setpoint drain claimed ownership. Correction cycle 2 synchronously claims the drain and publishes `.drainingSetpoint` before the first await; this phase permits exact latest replacement and capability-bound Stop but no confirmation, transitions to settling for lower execution, and restores confirmation only after terminal publication. Completed in the task-local landing candidate by `TASK-539931AC`, attempt `TASK-539931AC-49f2e7307f76`; the same critic's correction-cycle-2 final delta verdict was exactly `UNANIMOUS PASS — no material disagreement`, criticism is closed, and no new or post-pass critic occurred. The final `QUICK` attempt was nonpass at 753/755 with 9 issues, and separate focused `PEN` nonpass at 12/13 remain truthful history; the accepted corrections route rendered exact Stop, made that Stop settle the already-admitted EA-04 point-selection continuation before Pen terminal settlement, prevent attempt revival, and use test-only `PenInteractionCancellationPublicationProbe` to observe real `.cancelling` publication without sleep, polling, yield, production change, fabricated truth, or new authority. All six package gates passed on the frozen candidate: `DOC` contracts plus 29/29 in 11.921 seconds with 12.554 seconds wall, clean `DIFF`, `QUICK` 755/755 in 14.270 seconds after a 0.51-second build, `STRICT` 762/762 plus 29/29 docs in approximately 110.94 seconds with strict-concurrency build 39.36 seconds, full build 43.16 seconds, tests 16.462 seconds, docs 11.414 seconds, signing, launcher, and negative-bundle passes, `PEN` 13/13 in 0.766 seconds after a 71.02-second build, and `DELETE` 8/8 in 0.109 seconds. EA-10A is semantically complete and migration remains incomplete. Only Blackdog landing, canonical-main cleanup verification, and conditional EA-10B successor-capsule generation remain pending; EA-10B is not selected or dispatched. No attended physical or remote-Git validation occurred or is claimed. | `DOC`, `DIFF`, `QUICK`, `STRICT`, `PEN`, `DELETE` |
| EA-10B | complete | EA-10A | software | Cutover: transfer Boundary direction, normal/replacement/additional side acquisition, center move/retry, source-indexed revision/request/attempt/operation/cancellation/recovery identity, exact Stop/cancel/shutdown, immutable accepted aggregates/center/arrival/terminal truth, save-before-publication, and identity-bound no-resend recovery to one actor-isolated `PlotterBoundaryRuntime` with independent LIVE/SIMULATED state, synchronous reservation, one runtime task/latch, a genuinely async runtime-owned weak Sendable projection sink, typed UI/runtime revision routing, and deterministic post-reservation/pre-fact plus post-lower/pre-publication gates; retain controller-only fixed 50 mm renewal and Stop in `RunInterpreter`/`MachineActions`, retained supervised center travel/Pen ownership, the EA-07 causal simulator, durable `AcceptedMachineArtifactCheckpoint.boundarySideAggregates`, camera/Vision/checkpoint/replay/incident/later-package authority, and nonphysical SIM truth; delete workspace Boundary state/history/evidence/aggregates/center/frame/arrival/activity/pending dictionaries, `boundaryMotionTask`, `BoundaryAtomicCommitFailurePoint`, `beginPairedBoundarySide`, direct `machineActions.beginBoundaryMotion`, obsolete center/execution/commit helpers, generic Boundary Stop/reset/shutdown branches, five obsolete Boundary `ExerciseActionKind` cases, and high-level fixtures without replacement authority. The original fresh critic and correction history remains explicit: fact-late reservation, unsupervised center Pen Up, missing recovery/reset authority, missing publication happens-before, and destructive reset were corrected through exact pre-await ownership, async publication ordering, supervised travel, recovery-only UI, and two-phase reset. The user-authorized final-gate repair derived and enforced exact first-vs-retry center truth, advanced accepted-side direction deterministically, moved retained Discovery advisory into runtime-controlled pre-admission, rechecked cancellation/shutdown and fresh effect identity before LIVE motion, migrated every Boundary fixture to exact rendered select/acquire/capability-bound Stop, exposed terminal-derived retry/activity, routed actionable localized residual/tolerance detail, required fresh settled Camera Calibration MPos matching accepted center, and aligned SIMULATED Boundary truth with accepted sparse-tip geometry. The first remaining-gate pass recorded `BOUNDARY` 18/18, `DELETE` 8/8, `DOC` 29/29, clean `DIFF`, and `JOURNEY` 5/5, while initial `STRICT` failed at two sites because the MainActor projection sink was non-Sendable. The bounded fix makes `PlotterBoundaryProjectionSink` Sendable and removes the redundant relay's `@unchecked Sendable`; strict production build passed in 29.97 seconds, Boundary remained 18/18, and the same critic passed that bounded delta. Post-fix `QUICK` then reproduced a deterministic 772/773 failure in `shutdownDoesNotReviveAcceptedClick`: async retained Pen admission resumed after shutdown and created a zero-step `DiscoveryTransaction`. Entry and post-await shutdown guards prevent that revival; the exact regression passed 1/1, Pen-cap passed 17/17, and the same critic passed that bounded delta. Task-local candidate `TASK-6DAB256F` preserves frozen Sources `9abeef29df0364b87029bbcd621a82a4c433588a4de56a54aeaed8c5f400a5c8` and Tests `8998beb7745c07c5a261757a0fdb2c572e3f63a715b536854375a6804489c48e`. Final `QUICK` passed 773/773 in 13.957 seconds tests and 15.41 seconds real with log `/var/folders/c0/zjcj7q3d0mzf06v_qmdjk3vm0000gn/T/ea10b-racefix-quick.6TzUPaxfmJ`; final `JOURNEY` passed 5/5 in 4.916 seconds tests and 6.05 seconds real with log `/var/folders/c0/zjcj7q3d0mzf06v_qmdjk3vm0000gn/T/ea10b-racefix-journey.Fs3ODxsqNk`. Truthful nonpass history retains broad QUICK cascades, intermediate 771/773, initial strict Sendable failure, post-fix 772/773, missing center wait, stale-MPos camera ingress, Drawing Run sparse-fixture timeout, simulator Boundary-truth mismatch/out-of-frame clicks, point-selection repeated-refusal wait, generic center-retry ordering, activity legacy-failure dependency, `LocalizedError` wiring, compile-only helper defects, and all earlier sink/reset/operator-path failures. All seven final gates passed on the frozen candidate: `BOUNDARY` 18/18, `DELETE` 8/8, `QUICK` 773/773 in 13.957 seconds tests and 15.41 seconds wall, `JOURNEY` 5/5 in 4.916 seconds tests and 6.05 seconds wall, `DOC` contracts plus 29/29 in 12.694 seconds tests and 13.49 seconds wall, clean `DIFF` in 0.03 seconds, and `STRICT` 778/778 Swift in 14.540 seconds plus docs 29/29 in 23.453 seconds with 64.95 seconds wall. The final logs are `/var/folders/c0/zjcj7q3d0mzf06v_qmdjk3vm0000gn/T/ea10b-racefix-quick.6TzUPaxfmJ`, `/var/folders/c0/zjcj7q3d0mzf06v_qmdjk3vm0000gn/T/ea10b-racefix-journey.Fs3ODxsqNk`, `/tmp/ea10b-doc-final.jnbNGm`, `/tmp/ea10b-diff-final.Vcy9oB`, and `/tmp/ea10b-strict-final-resumable.oonlrS`. The final task-local sentence is historical: EA-10B subsequently landed on canonical `main` at `a388859`, and the successor policy is now the explicit tranche sequence below; no physical or remote-Git validation is claimed. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `BOUNDARY`, `DELETE` |
| DOC-04 | complete | EA-10B | repository | Correction: classify Blackdog summary records fail closed so active attempts, task/workset claims, retained owner/worktree/branch, required finalization, unknown replay identity, and dependency-ready recoverable ordinary packages remain live blockers, while fully cleaned terminal history bound to removed or dependency-ineligible packages remains a visible hash-bound diagnostic. It moves no product authority, changes no GATE-01 predicate, and does not reopen, cancel, or hide historical tasks. Delivered by `TASK-A7C0E999`. | `DOC`, `DIFF` |
| TRANCHE-LEARNING | complete | DOC-04 | software | Tranche: one Blackdog task/worktree/landing completed all ordered typed authority slices `EA-10G`, `EA-10C`, `EA-10D`, `EA-10E`, and `EA-10F`. Boundary `DOC` 35/35 and `DIFF` first passed, then `QUICK` first failed 4 tests/6 issues at 799; the first red-line EA-10D/E/F repair passed focused regressions and `QUICK` 799/799 for Sources `6dc363241c4b9f747fb2a791d26533c4f511601d2d32f97314318e2b9458392c`/Tests `a9ba97238089155cc5a33fb462db3f6c3d96b5bde03d1ff485c0ae1b6f56afab`. A second red-line EA-10D JOURNEY repair moved recoverable accepted-tip checkpoint retention into the runtime and atomically installs accepted registration; `JOURNEY` passed 5/5 for Sources `63ff15afa9716404367d8dbaf3cbdc111cb92e346cf816063ece2e7846f0fbd6`/Tests `1cc69013a0ed30b74a19ca21daa0a6cf408945e73fadf17e9c37563624731b9e`. One bounded critic then returned four P1 red-lines: camera semantic authority/false-terminal truth, Border explicit review/accept-reject, paper persist-before-memory atomicity, and reversible staged legacy cleanup. All four were repaired without a critic recheck. On final Sources `18ae4d43717629a3944ced33a6bab7b21f0fdabdcb45baee5704a34e94ebf796`/Tests `586d3de73b048efab7555332dbc17077c5e9fc3d4e1920084d5c6e0391bbacca`, `QUICK` passed 807/807 (build 2.63 seconds; tests 14.090 seconds), `JOURNEY` passed current discovery 5/5 in 5.273 seconds (the canonical filter lists ten names but only five exist/discover), and `STRICT` passed its strict build 48.90 seconds, full strict build 48.49 seconds, 812/812 in 14.873 seconds, docs/checker 35/35 in 21.517 seconds, signing/launcher/negative-bundle, and clean `DIFF`, all with 0 warnings/errors. The common landing proof is Blackdog task `TASK-5C0B3F27`, attempt `TASK-5C0B3F27-77bbbc6c5a59`, implementation commit `2d488025a6b8a5fa129023a1a61e98b817106990`, and canonical `main` target/landing `a1cfb05ca58f6805a973748958915fdbdd0ec117`. The non-red-line deferred item is `PlotterBorderValidationIntent.retryFrom`, which has no production caller; attended physical validation was not performed. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `CRITIC` |
| EA-10G | complete | EA-10B | authority-slice | Cutover: transfer advisory-speech effect authority to a typed registry lane with identity-bound queueing, bounded completion/failure/timeout/cancellation results, preserved advisory-only failure semantics, ordering before dependent physical commands, and shutdown cancellation. Retain `NativeSpeechAnnouncer`/AVFoundation synthesis ownership; delete `AnnouncementActions`, `OperatorWorkspace.announceAdvisory`, direct announcement calls, duplicate queue/task ownership, and high-level announcement fixtures. Landed with the ordered tranche in Blackdog task `TASK-5C0B3F27`, attempt `TASK-5C0B3F27-77bbbc6c5a59`, implementation commit `2d488025a6b8a5fa129023a1a61e98b817106990`, and canonical `main` target/landing `a1cfb05ca58f6805a973748958915fdbdd0ec117`; `BUILD`, `SPEECH`, `AFFECTED-CONSUMERS`, `DIFF`, and `DELETE` passed. | `BUILD`, `SPEECH`, `AFFECTED-CONSUMERS`, `DIFF`, `DELETE` |
| EA-10C | complete | EA-10G | authority-slice | Cutover: transfer camera-from-cap calibration intent/evidence authority and delete its old workspace state, capture/Vision tasks, guards, and fixtures. `PlotterCameraCalibrationRuntime` owns phase, failure, reference/correspondence evidence, staged proposal, accepted registration, active task, terminal history, shutdown admission, and semantic terminal truth; `OperatorWorkspace` only derives/proxies runtime state and supplies lower effects plus atomic application. The tranche critic's camera semantic-authority/false-terminal P1 was repaired without a critic recheck. Landed with the ordered tranche in Blackdog task `TASK-5C0B3F27`, attempt `TASK-5C0B3F27-77bbbc6c5a59`, implementation commit `2d488025a6b8a5fa129023a1a61e98b817106990`, and canonical `main` target/landing `a1cfb05ca58f6805a973748958915fdbdd0ec117`; `BUILD`, `CAMERA-CAL`, `AFFECTED-CONSUMERS`, `DIFF`, and `DELETE` passed. | `BUILD`, `CAMERA-CAL`, `AFFECTED-CONSUMERS`, `DIFF`, `DELETE` |
| EA-10D | complete | EA-10C | authority-slice | Cutover: transfer pen-tip calibration intent/evidence authority and delete its old workspace state, capture/Vision tasks, guards, and fixtures. `PlotterTipCalibrationRuntime` owns workflow/task/phase/proposal/commit/revalidate/reject/retry, terminal-history, and possible-ink blacklist semantics through one effect-port `execute(_:)`; `PlotterPointSelectionRuntime` remains sole click add/undo/clear/four-point batch owner, and `OperatorWorkspace` supplies only lower effects/projection. Landed with the ordered tranche in Blackdog task `TASK-5C0B3F27`, attempt `TASK-5C0B3F27-77bbbc6c5a59`, implementation commit `2d488025a6b8a5fa129023a1a61e98b817106990`, and canonical `main` target/landing `a1cfb05ca58f6805a973748958915fdbdd0ec117`; `BUILD`, `TIP-CAL`, `AFFECTED-CONSUMERS`, `DIFF`, and `DELETE` passed. | `BUILD`, `TIP-CAL`, `AFFECTED-CONSUMERS`, `DIFF`, `DELETE` |
| EA-10E | complete | EA-10D | authority-slice | Cutover: transfer Drawing Border validation authority to one typed `PlotterBorderValidationRuntime` with operation identity, phase, active step/task admission, bounded terminal history, possible-ink disposition, explicit review/accept/reject, and shutdown/no-start-after-cancel. `ExerciseActionKind.borderValidation` is the typed App adapter only. Retain canonical Border stage/item/step/phase vocabulary and distinct Draft/Run runtimes; `OperatorWorkspace` supplies one exhaustive lower effect-port switch and projection only, while preserving the EA-10D tip dependency. Delete all old DrawingTrial/ObservedDrawingTrial labels, owners, ingress, task, and high-level fixtures; no decode adapter or old active label remains. The critic's explicit-review/accept-reject P1 was repaired without a critic recheck. Landed with the ordered tranche in Blackdog task `TASK-5C0B3F27`, attempt `TASK-5C0B3F27-77bbbc6c5a59`, implementation commit `2d488025a6b8a5fa129023a1a61e98b817106990`, and canonical `main` target/landing `a1cfb05ca58f6805a973748958915fdbdd0ec117`; `BUILD`, `BORDER-VALIDATION`, `AFFECTED-CONSUMERS`, `DIFF`, and `DELETE` passed. | `BUILD`, `BORDER-VALIDATION`, `AFFECTED-CONSUMERS`, `DIFF`, `DELETE` |
| EA-10F | complete | EA-10E | authority-slice | Cutover: `PlotterArtifactResetRuntime` now owns explicit Saved Learning comparison/apply/retain/reject/redo/additional-attempt/paper/reset admission, one task, state, bounded terminals, shutdown, and durable-before-projection ordering. `AdaptivePlotterApplicationDelegate` composes and installs its weak lower effect/persistence relay; `OperatorWorkspace` only routes typed actions, projects runtime facts, and applies lower effects/persistence. `AcceptedLearningPathLegacyMigrationAdapter` canonical-short-circuits, rejects corrupt/unsupported legacy bytes explicitly, atomically saves canonical state before reversible staged cleanup, and preserves legacy bytes on failure; the two legacy stores and their direct tests are deleted. The critic's paper persist-before-memory atomic-transaction and legacy reversible staged-cleanup P1s were repaired without a critic recheck. Landed with the ordered tranche in Blackdog task `TASK-5C0B3F27`, attempt `TASK-5C0B3F27-77bbbc6c5a59`, implementation commit `2d488025a6b8a5fa129023a1a61e98b817106990`, and canonical `main` target/landing `a1cfb05ca58f6805a973748958915fdbdd0ec117`; `BUILD`, `ARTIFACT-RESET`, `AFFECTED-CONSUMERS`, `DIFF`, and `DELETE` passed. | `BUILD`, `ARTIFACT-RESET`, `AFFECTED-CONSUMERS`, `DIFF`, `DELETE` |
| TRANCHE-DEVICE-ENVIRONMENT | complete | TRANCHE-LEARNING | software | Tranche: the staged completion transaction uses one Blackdog task/worktree/landing for ordered typed authority slices `EA-11A` and `EA-11B`: task `TASK-4C16F56F`, attempt `TASK-4C16F56F-8af99cc51c68`, target `main`. It preserves each slice's same-slice deletion and per-slice gates, batches broad gates/docs/evidence at the boundary, and records the one critic RETASK repair without recheck. This completion becomes canonical only upon successful Blackdog landing of this exact transaction; no landed commit hash is asserted before that landing. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `CRITIC` |
| EA-11A | complete | TRANCHE-LEARNING | authority-slice | Cutover: transfer controller-session readiness authority for serial selection, connect/disconnect, passive probe, explicit alarm clear, session-scoped Motion authorization, and complete EA-05A controller-session recording through typed intents, rules, events, and effects. Retain `MachineController` and `RunInterpreter` transport/safety ownership; delete the workspace/UI handlers, duplicated unavailable-reason guards, in-progress/task/generation state, direct `MachineActions` calls, LIVE/SIMULATED session branches, serial-preference closure, and old fixtures. Completed only through the shared staged `TASK-4C16F56F` / `TASK-4C16F56F-8af99cc51c68` Device-tranche transaction; canonical completion requires that transaction's successful landing into `main`, with no pre-land commit hash asserted. | `BUILD`, `SESSION`, `AFFECTED-CONSUMERS`, `DIFF`, `DELETE` |
| EA-11B | complete | EA-11A | authority-slice | Cutover: transfer observation-environment configuration authority for camera discovery/selection/lifecycle, LIVE/SIMULATED source selection, automatic-analysis cadence, exact-frame region policy, overlay-feature preferences, bounded diagnostic requests, complete EA-05A camera recording, and ambient frame/Vision task-result routing. Retain `CameraCapture` device/frame ownership, `CameraSourceSession` automatic ingestion/analysis/lease ownership, Vision measurement authority, and evidence-applicability authority; delete direct SwiftUI/workspace handlers and reads, duplicated config/guard state, mode branches, frame/Vision tasks, direct `CameraActions` calls, persistence closures, and old fixtures. Completed only through the shared staged `TASK-4C16F56F` / `TASK-4C16F56F-8af99cc51c68` Device-tranche transaction; canonical completion requires that transaction's successful landing into `main`, with no pre-land commit hash asserted. | `BUILD`, `OBSERVATION-CONFIG`, `AFFECTED-CONSUMERS`, `DIFF`, `DELETE` |
| TRANCHE-FINAL-COMPOSITION | complete | TRANCHE-DEVICE-ENVIRONMENT | software | Tranche: one Blackdog task/worktree/landing executes the typed final-composition authority slice `EA-11C`, including its named root-schema/lifecycle prerequisite in that same slice/task/landing; it preserves same-slice deletion and per-slice gates, batches broad gates/docs/evidence at the boundary, and records non-red-line findings without retask. Staged complete in `TASK-FFD5D897`, attempt `TASK-FFD5D897-06c5758ade77`, after one bounded critic found the feature-shutdown join red-line; the repair passed affected suites, `DOC`, `DIFF`, `QUICK` 820/820, `JOURNEY` 10/10, and `STRICT` 830/830 without a critic recheck. Canonical completion requires this exact task's successful Blackdog landing. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `CRITIC` |
| EA-11C | complete | TRANCHE-DEVICE-ENVIRONMENT | authority-slice | Cutover: transfer only final application composition and policy-originated startup/shutdown authority to `PlotterApplicationRuntime`, one canonical source-indexed `PlotterApplicationState`, immutable projections, and one projection-bound public `PlotterUIIntentSink`. The sink is the exclusive public application ingress and delegates to the already-authoritative typed feature runtimes; it does not add a redundant root `PlotterIntentGateway` reevaluator. Use the package `PlotterOperationRegistry` mechanism without claiming that one monolithic registry instance owns named feature-runtime coordination. Add the direct `PlotterApp -> EpisodeRuntime` dependency and one `PlotterApplicationResidualOperationAdapter` backed by a residual registry; retain distinct typed feature runtime authorities/tasks/Stop lanes. Through nominal `PlotterApplicationResidualEffectPort` and `PlotterApplicationStatePersistencePort`, synchronously close MainActor admission before any await, join residual and feature owners, persist accepted state before projection/terminal publication, and never report false termination or quiescence. Delete the `OperatorWorkspace` effect closures plus `ActiveStoppableOperation`, `LearningSessionState`, `liveLearningSession`, `simulatedLearningSession`, `activeLearningSession`, `hasShutdown`, `lifetimeGeneration`, `activeHardwareIntentCount`, `intentDrainWaiters`, `beginHardwareIntent`, `endHardwareIntent`, `canCommit`, `waitForHardwareIntentsToDrain`, and every migrated direct UI read named by EA-01. It may not absorb an unnamed feature migration; any unassigned inventory item or second root task/operation registry fails the slice. `PlotterEpisodeCompositionTests` must be discoverable and now passed 5/5. The exact shutdown repair retains and joins cancellation-insensitive artifact/reset and tip-calibration operations before root persistence or AppKit termination; focused artifact reset 12/12, tip calibration 7/7, lifecycle 9/9, affected consumers 4 scans, DELETE 9 scans, and the source-derived task metric 9-to-0 passed. Staged complete only through the shared `TASK-FFD5D897` / `TASK-FFD5D897-06c5758ade77` landing transaction. | `BUILD`, `COMPOSITION`, `AFFECTED-CONSUMERS`, `DIFF`, `DELETE` |
| FIX-05 | complete | TRANCHE-FINAL-COMPOSITION | software | Correction: transfer remaining cross-owner façade/port/fact-source/adapter ownership out of the application root and into already-distinct typed owners, removing at least three qualifying top-level stored `PlotterApplicationRuntime` properties from the pinned current set `residualOperationAdapter`, `machineSession`, `drawingRunFactSource`, `drawingRunInterpreterPort`, `drawingRunCameraPort`, `observationPreferences`, `statePersistencePort`, `drawingEvidencePort`, `residualEffectPort`, and `causalSimulatorEffectAdapter`, so `operator-workspace-adapters` decreases from the EA-01 baseline 7 to 7 after the pre-correction failing 10. A property counts as removed only when its authority and consumers move to an existing correct typed owner and the old root property and direct use are deleted; wrapper aggregation, another root property, type erasure, nominal-port exemption, or absorbing a typed feature runtime does not count. Preserve distinct feature runtimes and registries, exactly one residual `PlotterOperationRegistry` adapter, synchronous close-before-await shutdown and complete joins, retained controller/camera/Vision/planning/persistence/evidence safety owners, no automatic motion or redraw, and truthful possible-ink/termination/quiescence state. Install a pinned executable source-identity manifest checker for all six Pilot metrics using EA-01 commit `96253197a42dc6052ef76ad53c4c94c1c5f745a1` and the exact candidate identity; prove `independent-admission-sites` 18-to-2, `workspace-task-owners` 9-to-0, `environment-mode-branches` 2-to-0, `direct-effect-calls` 40-to-0, `operator-workspace-policy-state` 6-to-1, and `operator-workspace-adapters` 7-to-7 without weakening or silently changing inclusion/exclusion rules. If any literal metric cannot be pinned and proved, FIX-05 fails. Exact deletion and consumer scans prove `drawingRunFactSource`, `drawingRunInterpreterPort`, and `drawingRunCameraPort` absent while `PlotterDrawingRunRuntime` owns facts, interpreter, camera, and Vision. Completed by `TASK-2BF894FC`, attempt `TASK-2BF894FC-06f14a3e1a5b`; package FIX-05 complete, migration remains incomplete. All nine package gates passed; `PILOT` and GATE-01 remain unclaimed. | `BUILD`, `COMPOSITION`, `PILOT-METRICS`, `AFFECTED-CONSUMERS`, `DELETE`, `DOC`, `DIFF`, `QUICK`, `STRICT` |
| GATE-01 | complete | FIX-05 | gate | Decide pilot continuation from deletion, replay, typing, owner, observability, simulation, and physical-boundary evidence. It moves no authority. The fail-closed checker accepted all 9 predicates, 6 source-derived reduction metrics, and 18 cutover scan sets after a narrow evidence-order parser repair covered by 13/13 focused unit tests. Completed by `TASK-5E431BE7`, attempt `TASK-5E431BE7-59658505ced4`; GATE-01 complete, migration remains incomplete, and attended `VAL-01` is not authorized or started by this result. | `DOC`, `DIFF`, `PILOT` |
| FIX-06 | complete | GATE-01 | software | Correction: enforce one complete external-fact currentness invariant across the existing typed owners. LIVE Boundary relative motion must acquire the controller-session owner's latest settled Idle/MPos immediately before computing its delta and must publish terminal MPos before dependent admission; retry recomputes from that fresh position and produces no lower effect after accepted arrival. Exact-frame point selection must invalidate pending UI submission whenever request, frame/hash, source, camera configuration, presentation revision, environment, or reset identity changes and must never expose a stale request against a different displayed frame. Restored Drawing Evidence may project as current only when complete paper instance plus contact-plane identity matches, and beginning new exact-frame Learning hides prior saved-path presentation without deleting the last complete durable package. Preserve `MachineController`/`RunInterpreter`, `PlotterBoundaryRuntime`, `PlotterPointSelectionRuntime`, camera/Vision, checkpoint, evidence, reset, and no-redraw authority; add no second fact source, UI ingress, automatic retry, redraw, compatibility path, or physical-evidence claim. Completed by `TASK-4194B778`, attempt `TASK-4194B778-238b4ef7adb1`; package FIX-06 complete, migration remains incomplete. All eleven package gates passed; this software completion neither retries the failed attended run nor satisfies `PHYSICAL-FINAL`. | `BUILD`, `BOUNDARY`, `POINT`, `UI`, `ARTIFACT-RESET`, `DRAW-RUN`, `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT` |
| FIX-07 | complete | FIX-06 | software | Correction: add the missing operator-admitted replacement-frame transition after Exercise 1.4 has completed its physical four-circle batch. `PlotterTipCalibrationRuntime` owns a typed **Capture New Click Frame** intent only while awaiting its exact point selection with zero retained clicks; `PlotterPointSelectionRuntime` atomically supersedes the old request and archives/stages one strictly newer frame. The lower adapter must reacquire current connected Idle, Pen Up, no operation, no sticky ambiguity, unchanged exercise/paper/source/semantic optical identity, and a newer exact frame before replacement. Preserve the original mark, controller, Pen, pre-mark, and cap-bearing reveal evidence while recording the separately exact click-frame identity in each accepted observation; legacy observations without that field decode against their original reveal frame. Camera refresh or raw capture never silently changes the staged request, and a partial click set must be explicitly cleared before replacement. Add no motion, Pen command, redraw, automatic refresh/retry, duplicate UI ingress, fabricated cap estimate, or physical-evidence claim. Completed by `TASK-EA60F469`, attempt `TASK-EA60F469-a83fe1fa0c15`; package FIX-07 complete, migration remains incomplete. All ten software/repository gates passed on the exact candidate; this correction does not satisfy `PHYSICAL-FINAL` or authorize `VAL-01`. | `BUILD`, `TIP-CAL`, `POINT`, `UI`, `ARTIFACT-RESET`, `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT` |
| FIX-08 | complete | FIX-07 | software | Correction: implement the operator-authorized throughput policy through the existing UI, observation, drawing-run, and machine owners without moving authority. An exact-frame camera click now submits its Learning point through the existing projection-bound `PlotterUIIntentSink`; the green **Apply Learning Point** button and user-visible confirmation step are deleted, and only a transient clicked value remains while the same exact request is compiled. `VisionAnalysisCadence` and Video Settings now offer exactly `0.05`, `1`, `2`, `2.58`, `3`, `4`, and `5` frames per second. `PlotterMotionThroughput.applicationXYFeedMMPerMinute` is the single `500` mm/min model value for app-generated XY travel and drawing: already-fast manual, Boundary, baseline-positioning, and supervised-travel paths retain that behavior, while Drawing Studio drawing, Drawing Border drawing, and sparse four-circle calibration now request `500`; superseded production `100` feed literals and the `10 FPS` option are absent. Existing controller-reported feed-ceiling refusal and Stop owners remain; the correction issues no firmware write and adds no guard, interlock, retry, redraw, or ingress. Completed by `TASK-EB3E64FA`, attempt `TASK-EB3E64FA-67fdbd7ab2a2`; package FIX-08 complete, migration remains incomplete. All seven software/repository gates passed on the exact candidate, with the initial QUICK cadence-fixture nonpass corrected before the final full pass. No attended controller, camera, motion, Pen, paper, click, speed, or observed-ink result is claimed. | `BUILD`, `THROUGHPUT`, `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT` |
| FIX-09 | complete | FIX-08 | software | Correction: remove initial-Learning transition latency and make every affected workbench action truthful without adding a second authority. `PlotterPenInteractionRuntime` publishes a monotonic `.confirming` revision before any predecessor drain/publication wait, stale repeated Confirm invokes no duplicate actuation, and an exact Stop or root shutdown that displaces held Confirm returns typed superseded truth without accepted evidence or a discovery successor; root shutdown closes the Pen owner before joining retained UI work. Pen speech admission no longer waits for playback terminal before the command or successor prompt. `PlotterCameraCalibrationRuntime` is the sole revisioned phase/proposal/evidence/failure/accepted/terminal owner, publishes busy before every lower suspension, returns immutable facts to the App, and exposes exact failure/refusal rather than discarded or generic workspace state; production projection-bound tests execute the green run/accept actions. Learning Reset cancels and settles only its current camera operation while keeping admission reusable, and a reset-to-camera projection-bound regression proves the successor green action; only application shutdown closes admission. Connect/Disconnect title, role, and lower dispatch derive from one semantic enum; every Disconnect is red, while unavailable Enable Motion remains correctly gray with its full blocker rendered as visible text. Interactive camera capture makes a best-effort 10 FPS device request, reports applied versus unapplied truth without failing otherwise-valid startup, and retains the independent 10 FPS materialization bound. Passive preview performs no SHA-256 work; automatic analysis and exact evidence explicitly promote one shared memoized frame digest, with actual computation metrics and production-overlay reuse coverage. Passive root presentation, Drawing Draft/currentness, point-selection, and saved-Learning optical/reference projection consume only an already-sealed digest and otherwise publish unavailable exact-frame facts without hashing or trapping. Camera preview processing remains separate from Vision. The no-source Incident Package action is disabled and its unavailable reason is readable multiline secondary status instead of an enabled guaranteed refusal or clipped yellow text. Completed by `TASK-9C229F54`, attempt `TASK-9C229F54-1984133960c1`; local software diagnostics/benchmarking do not claim attended controller, camera, motion, Pen, paper, click, ink, application CPU, or operator transition-speed evidence. | `BUILD`, `RESPONSIVENESS`, `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT` |
| DOC-05 | complete | FIX-09 | repository | Correct the disproved post-FIX-09 frontier after independent code and documentation audits found duplicate Border Validation state, App-owned opaque Learning action registries, unjournaled retained-Learning operation identity, and rendered controls whose enabled state was not bound to an exact current request. Insert one ordered model/UI consolidation tranche before incident export, fully specify its owners, preservation boundary, gates, and deletion obligations, reconcile current architecture and controls, and update the fail-closed checker/capsule contract without changing product source, Swift tests, hardware, or physical evidence. Completed by `TASK-5168D237`, attempt `TASK-5168D237-5c8c54d403c2`; package DOC-05 complete, migration remains incomplete, subject to this exact task's successful Blackdog landing. | `DOC`, `DIFF` |
| TRANCHE-MODEL-UI-CONSOLIDATION | complete | DOC-05 | software | Tranche: completed `EA-12A`, `EA-12B`, and `EA-12C` in that exact order through `TASK-34928BFE`, attempt `TASK-34928BFE-a221afbd5d52`. It removed duplicate mutable Border Validation state, carries model-owned typed Learning requests and availability through the one public UI sink, and established one stable Learning episode identity plus ordered action/reset transition record before incident binding. It introduced no replacement dictionary, closure bag, type erasure, second sink, monolithic feature owner, automatic retry/redraw, or fabricated/merged journal; UI-local layout/viewport/selection/unsubmitted text and the named device, feature, Stop, shutdown, possible-ink, persistence, and evidence owners remain distinct. A fresh critic required exact per-value slider/direction candidates, action/reset post-transition projection, and retained Border accept/reject cancel/join guards; final broad-test repair added exact immutable Boundary snapshot publication so the canonical Learning request immediately renders its capability-bound Stop, plus one established semantic-cache invalidation after the test bridge installs a runtime-owned recoverable tip checkpoint. Those correctness repairs changed cumulative production `Sources` to `+1631/-1600`, net `+31`; therefore the original net-deletion target did not pass. The coordinator accepted this narrow exception only after the named obsolete parallel systems remained deleted and no replacement side registry appeared. Package TRANCHE-MODEL-UI-CONSOLIDATION complete; migration remains incomplete, subject to this exact task's successful Blackdog landing. | `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT`, `CRITIC` |
| EA-12A | complete | DOC-05 | authority-slice | Cutover: `PlotterBorderValidationRuntime` is the sole source-indexed mutable Border Validation owner and publishes immutable projections/results to App. The duplicate environment snapshot, all forwarding and whole-snapshot copy paths, `replaceSnapshot`, zero-caller retry intent, and declaration-only dead symbols are deleted. Slice-boundary `BUILD`, Border 7/7, and composition 6/6 passed; the repaired candidate passed 7 consumer and 23 full cutover scans. Exact controller/camera/Vision/evidence owners, Draft/Run, Stop, possible-ink/no-redraw, review, reset, persistence, and shutdown behavior remain. | `BUILD`, `BORDER-VALIDATION`, `COMPOSITION`, `AFFECTED-CONSUMERS`, `DIFF`, `DELETE` |
| EA-12B | complete | EA-12A | authority-slice | Cutover: model-owned typed Learning item/action/request identity and availability now travel unchanged through immutable `PlotterUI` projection and the one public `PlotterUIIntentSink` to the authoritative feature runtime. App semantic side registries, opaque retained/application intents, ID recompilation, redundant `ExerciseActionKind` translations, dead IDs/UI declarations, and **Discard Camera Samples** are deleted. Tip retry is absent during busy commit/revalidation; every touched effect-bearing control binds its exact projected request/remedy and cannot silently terminate. At the slice boundary, `BUILD`, UI-authority 19/19, model 20/20, composition 6/6, and UI 20/20 passed; the repaired candidate passed 22 consumer and 29 full cutover scans. | `BUILD`, `UI-AUTHORITY`, `PLOTTER-MODEL`, `COMPOSITION`, `UI`, `AFFECTED-CONSUMERS`, `DIFF`, `DELETE` |
| EA-12C | complete | EA-12B | authority-slice | Cutover: one stable model-owned `PlotterLearningEpisodeID` and bounded ordered `PlotterLearningTransitionID` record spans retained feature requests without fabricating or merging their journals. Every effect-bearing Learning action/reset records its exact union request/source, pre revision, typed accepted/refused result/remedy, and bounded immutable post-transition projection; the retained root task is keyed by transition only for asynchronous cancel/join. Slider/direction controls carry exact per-value requests, and both LIVE/SIMULATED Border runtimes retain, cancel, and join step/accept/reject effects before root persistence. Residual UUID/string identity, duplicate ingress, duplicate controller/observation bridge types, and request reconstruction helpers are deleted. Final focused repair validation passed `BUILD`, UI-authority 21/21, Border 9/9, model 22/22, composition 8/8, and UI 22/22; 12 consumer and 26 full cutover scans passed. This slice does not assemble or export an incident package, and the accepted `Sources +1631/-1600` exception means the original net-deletion target did not pass. | `BUILD`, `UI-AUTHORITY`, `BORDER-VALIDATION`, `PLOTTER-MODEL`, `COMPOSITION`, `UI`, `AFFECTED-CONSUMERS`, `DIFF`, `DELETE` |
| FIX-10 | complete | TRANCHE-MODEL-UI-CONSOLIDATION | software | Correction: user-directed scope replacement for practical debugging and operator throughput. Export an on-demand bounded diagnostic snapshot of the existing Learning record, current UI actions/refusals, source, and runtime/UI revisions. Do not create a second event stream, merge unrelated feature journals, or require a complete replay archive for the Learning Path. Keep the canonical incident assembler as an unbound archival foundation. Improve measured live-preview cost, native workbench layout, and contextual spoken responses through the existing projected requests without changing the Learning sequence or adding admission rules. Complete archive/source integration is deferred until a concrete continuity or replay need justifies it. Completed through `TASK-128DF0C7`, attempt `TASK-128DF0C7-93f0fac9a2b1`; software checks and measured live-camera rendering do not claim attended physical or microphone evidence. | `BUILD`, `INCIDENT-APP`, `UI`, `DOC`, `DIFF`, `QUICK`, `JOURNEY`, `STRICT` |
| VAL-01 | pending | FIX-10 | attended-physical | On the exact signed landed FIX-10 validation candidate, execute the complete attended runbook including Drawing Studio, exercise visible refusal/progress/Stop and diagnostic snapshot export, and land controller/camera/operator/ink evidence and limitations without changing architecture. The failed 2026-08-31 section-1 prefix and the incomplete 2026-09-01 Exercise 1.4 frame-handoff attempt remain nonpass evidence and cannot satisfy `PHYSICAL-FINAL`. | `DOC`, `DIFF`, `STRICT`, `PHYSICAL-FINAL` |
| GATE-02 | pending | VAL-01 | gate | Prove one globally exclusive projection-bound public `PlotterUIIntentSink`, complete operator journey, replay/simulation/incident evidence, same-landing deletion, final attended evidence, and packaging decision. It moves no authority and does not require a redundant root intent reevaluator. | `DOC`, `DIFF`, `FINAL-GATE` |

EA-10B critic history remains explicit: The original fresh critic returned
`RETASK` for exactly three blockers. The ledger row above preserves every later
correction, bounded-delta acceptance, nonpass, and final-gate receipt.
Correction cycle 2 installs the exact owner/capability/task and one-shot latch
before awaits and uses non-destructive exact reset reserve/commit/abort. The
later repair moves the retained advisory into a runtime-controlled pre-admission
step and preserves exact typed retry and terminal-derived activity. Camera
Calibration requires a fresh settled MPos matching accepted center. SIMULATED
sparse-tip fixtures bind simulator Boundary truth to accepted checkpoint
geometry. The bounded Sendable fix makes `PlotterBoundaryProjectionSink`
Sendable and removes the redundant relay's `@unchecked Sendable`.
Earlier focused receipts remain recorded as migrated Boundary filters 13/13,
computation 9/9, sparse tip 8/8, Drawing Run 13/13, and center regression 1/1.

`repository`, `attended-physical`, `remote-git`, and `gate` rows move no product
authority. Every `software` outcome begins `Foundation:`, `Correction:`, or
`Cutover:` with the exact meaning defined by the vocabulary authority.

`EA-01` is the only package allowed to add current-source characterization
commands, source-symbol inventories, and package-specific
deleted-symbol/direct-port scan data. The target focused-suite names and gate
commands below are fixed; `EA-01` cannot rename or replace them, and an
implementation package creates its named suite with its corresponding code.
`EA-01` may not add, remove, combine, split, or reorder packages. If its
inventory proves that any row contains more than one authority transfer or
rollback boundary, or that any semantic intent lacks a package, `EA-01` fails.
A separate repository-contract correction must revise this plan and its exact
checker and earn a fresh `CRITIC` verdict before `EA-01` is retried. A
lower-reasoning executor may implement a fully specified package but may not
choose scope, dependencies, owners, deletion disposition, lifecycle design, or
completion status.

### Validation gate catalog

Angle-bracket values are compiled from the named row and landed Current
Evidence; they are not executor choices. Test filters name suites that the
owning implementation package must add. A filter that selects zero tests fails
the gate. All commands run from the task workspace on the recorded target.

| Gate | Exact command or evidence procedure | Created or owned by |
| --- | --- | --- |
| `ARCHIVED` | `git merge-base --is-ancestor d33d4ff HEAD` and the `TASK-C86132F1` Current Evidence entry identifies `d33d4ff` | DOC-00 |
| `DOC` | `make docs-check` | repository |
| `DIFF` | `git diff --check` | repository |
| `CRITIC` | At most one bounded fresh-context read-only critic per tranche boundary inspects the stable actual candidate and reports only red-line blockers; Current Evidence records its verdict and every deferred non-red-line finding while the full transient report is not checked in | tranche boundary |
| `QUICK` | `make quick-test` | repository |
| `JOURNEY` | `make journey-test` | repository |
| `STRICT` | `make strict-check` | repository |
| `BUILD` | `swift build` | authority slice |
| `THROUGHPUT` | `swift test --filter PlotterOperatorThroughputPolicyTests` | FIX-08 |
| `RESPONSIVENESS` | `make responsiveness-test` proves pre-wait Pen/camera state publication, Stop/shutdown supersession without Pen evidence or successor, non-gating advisory playback, projection-bound camera run/accept/reset reuse, semantic controller color/dispatch and visible Motion blocker, best-effort camera delivery plus zero passive-preview hashing and one instrumented cached analysis/exact promotion, passive-overlay reuse, passive root presentation without exact-frame facts, readable disabled incident action, and exact failure/status projection | FIX-09 |
| `INVENTORY` | `sh Scripts/check_episode_inventory.sh` proves every semantic intent, guard, owner, direct device/evidence port, environment branch, task/cancel owner, persistence path, UI consumer, and high-level fixture has one stable inventory ID, one current owner, one disposition, and one cutover package; the current target-topology manifest additionally proves the direct `PlotterApp -> EpisodeRuntime` dependency, one public sink conformer, one stable model Learning episode record, one transition-keyed retained-task join, nominal ports, and the discoverable composition suite | EA-01 |
| `FIX-CONTAINMENT` | `swift test --filter CoordinateAcceptancePolicyTests` | FIX-00 |
| `FIX-APPLICABILITY` | `swift test --filter TipApplicabilityEvidencePolicyTests` | FIX-01 |
| `LINK-OBS` | `swift test --filter MachineLinkTranscriptObservabilityTests` | FIX-02 |
| `LINK-SAFETY` | `swift test --filter MachineLinkSafetyTests` | FIX-02 |
| `CORE` | `swift test --filter EpisodeCoreTests` | EA-02A |
| `PLOTTER-MODEL` | `swift test --filter PlotterEpisodeModelContractTests` | EA-02B |
| `STORE` | `swift test --filter EpisodeStoreTests` | EA-03A |
| `RUNTIME` | `swift test --filter EpisodeRuntimeTests` | EA-03B |
| `RECORDING` | `swift test --filter PlotterRecordingStoreTests` | EA-05A |
| `REPLAY` | `swift test --filter PlotterRecordingReplayTests` | EA-05B |
| `INCIDENT` | `swift test --filter PlotterIncidentPackageTests` | EA-05C |
| `INCIDENT-APP` | `swift test --filter WorkbenchDiagnosticsTests` proves on-demand export of existing Learning identity, ordered transitions, source, current actions/refusals, and runtime/UI revisions with declared omissions and no new event stream | FIX-10 |
| `POINT` | `swift test --filter PlotterPointSelectionEpisodeTests` | EA-04 |
| `MOTION` | `swift test --filter PlotterManualMotionEpisodeTests` | EA-06 |
| `SIM` | `swift test --filter PlotterCausalEpisodeEnvironmentTests` | EA-07 |
| `DRAW-DRAFT` | `swift test --filter PlotterDrawingDraftEpisodeTests` | EA-08A |
| `DRAW-RUN` | `swift test --filter PlotterDrawingRunEpisodeTests` | EA-08B |
| `UI` | `swift test --filter PlotterEpisodeUIActionabilityTests` | EA-09 |
| `UI-AUTHORITY` | `swift test --filter PlotterLearningUIAuthorityTests` selects a nonzero production-projection suite proving every rendered effect-bearing Learning, Drawing Placement, completed-comparison, and Drawing Studio control carries its model-owned typed item/action/request identity and exact current availability through the sole public sink; no enabled control can reach nil/unavailable or opaque ID-registry dispatch, **Discard Camera Samples** has no rendered path without a real sample-owning request, and tip commit retry is absent while commit/revalidation is busy | EA-12B |
| `TASK-METRIC` | `PYTHONDONTWRITEBYTECODE=1 python3 Scripts/check_episode_task_metric.py` preserves the source-derived FIX-03 9-to-8 legacy `OperatorWorkspace` `Swift.Task` evidence while EA-11C is pending; after EA-11C completes it may record 9-to-0 only when a masked scan of all production Swift source proves the `OperatorWorkspace` declaration truly absent | FIX-03 |
| `PILOT` | `sh Scripts/check_episode_pilot_gate.sh` proves the exact Pilot continuation gate predicates below against landed rows and Current Evidence | EA-09 |
| `PILOT-METRICS` | `PYTHONDONTWRITEBYTECODE=1 python3 Scripts/check_episode_pilot_metrics.py` proves the six pinned EA-01-to-candidate source-identity manifests, exact inclusion/exclusion rules, identity presence, and required decrease/not-increase thresholds without trusting Current Evidence counts | FIX-05 |
| `PEN` | `swift test --filter PlotterPenInteractionEpisodeTests` | EA-10A |
| `BOUNDARY` | `swift test --filter PlotterBoundaryEpisodeTests` | EA-10B |
| `CAMERA-CAL` | `swift test --filter PlotterCameraCalibrationEpisodeTests` | EA-10C |
| `TIP-CAL` | `swift test --filter PlotterTipCalibrationEpisodeTests` | EA-10D |
| `BORDER-VALIDATION` | `swift test --filter PlotterBorderValidationEpisodeTests` | EA-10E |
| `ARTIFACT-RESET` | `swift test --filter PlotterArtifactResetEpisodeTests` | EA-10F |
| `SPEECH` | `swift test --filter PlotterSpeechEffectEpisodeTests` | EA-10G |
| `SESSION` | `swift test --filter PlotterControllerSessionEpisodeTests` | EA-11A |
| `OBSERVATION-CONFIG` | `swift test --filter PlotterObservationConfigurationEpisodeTests` | EA-11B |
| `COMPOSITION` | `swift test --filter PlotterEpisodeCompositionTests` selects a nonzero discoverable suite proving production-root projection-bound submission, ordered model Learning episode transitions, transition-keyed retained-task cancel/join, synchronous close-before-await, feature joins, ordered persistence, exact nonterminal-owner reporting, and no false termination/quiescence | EA-11C |
| `AFFECTED-CONSUMERS` | `sh Scripts/check_episode_cutover.sh <PACKAGE-ID> --consumer-only` proves the exact direct-port, duplicate-ingress, forbidden-import, forbidden-conformance, and environment-branch consumer scans for that slice; it does not substitute for `DELETE` | EA-01 |
| `DELETE` | `sh Scripts/check_episode_cutover.sh <PACKAGE-ID>` executes the exact zero-match deleted-symbol, forbidden-import, forbidden-conformance, direct-port, duplicate-ingress, task-owner, fixture, and environment-branch scans recorded by EA-01 for that package; any unassigned remaining consumer fails | EA-01 |
| `PHYSICAL-FINAL` | On the exact signed landed FIX-10 validation candidate, one continuously attending operator executes Attended Hardware Runbook sections 1 through 6 and completes its Evidence record; the record must additionally capture one visible typed refusal/remedy, active owner/progress/Stop, runtime/UI revisions, one bounded diagnostic snapshot export, controller transcript completeness, camera artifact presence or declared absence, and observed-ink/ambiguity outcomes | VAL-01 |
| `FINAL-GATE` | `sh Scripts/check_episode_final_gate.sh` proves every ledger row through VAL-01 complete, all final-matrix software/replay/simulation/UI evidence linked from Current Evidence, one globally exclusive public gateway and one package `PlotterOperationRegistry` mechanism by structural scan while retaining named feature-runtime lanes, zero superseded paths, and a passed PHYSICAL-FINAL record for the exact signed landed FIX-10 validation candidate | EA-11C |

## Package completion contract

Completion has three noninterchangeable levels:

1. A Blackdog operation is complete when its structured result says so. This
   proves only that the lifecycle operation completed.
2. A `WorkPackage` is complete only when one bounded authority/deletion outcome
   is landed on Blackdog's recorded canonical `main` target, every gate named in
   its ledger row passed, every same-landing deletion is proved, matching Current
   Evidence is landed, its structured Work package gate evidence row records
   every required gate as `passed`, and the ledger row is landed as `complete`.
3. The migration is complete only when every executable row is complete and
   both pilot and final gates have passed. Until then, every handoff says
   “package `<ID>` complete; migration remains incomplete.”

`failed` and `skipped` are truthful evidence outcomes but cannot satisfy a
required gate. Missing required evidence also prevents completion. A blocked
package may land only a canonical blocker/evidence update after all partial
authority-transfer code, bridges, tests, and ledger `complete` claims are
removed; the row remains `blocked`. Blackdog's task close/land state never
overrides these conditions.

Every executable package prompt copies verbatim its row, exact expanded gate
commands, current owners and behavior, authority transfer, observability impact,
same-landing deletion set, and done condition. Validation runs serially when
SwiftPM shares `.build`. Software, replay, and simulation never prove attended
controller, camera, motion, pen, paper, operator click, or observed ink.

## Pilot continuation gate

`Scripts/check_episode_pilot_gate.sh`, created and tested in `EA-09`, evaluates
the following closed set of predicates against landed ledger rows, inventory
scans, and linked Current Evidence. `DOC-03` relocates that unchanged decision
after `EA-11C`; `FIX-05` must complete before the gate. Its pre-relocation
6-to-6 policy-state and pre-FIX-05 7-to-10 adapter
measurements could not satisfy the existing thresholds until the authority
transfers assigned to EA-10A through EA-11C had run, while those packages had
incorrectly depended on the gate. The checker therefore requires completed
evidence through DOC-03, EA-10A through EA-10G, EA-11A through EA-11C, and
FIX-05, including every required `DELETE` gate and its executable metric
manifests. `GATE-01` may mark only its own row
complete after that command, `DOC`, and `DIFF` pass:

- domain-generic `EpisodeCore` required no forbidden type-erasure or concurrency
  escape hatch, and Plotter-specific values remain in `PlotterEpisodeModel`;
- replay reconstructs canonical state, projection, and availability without
  executing effects;
- captured device traffic reaches production controller/camera owners;
- LIVE and SIMULATED share semantic grammar without equating evidence;
- migrated slices have zero old entrypoints, guards, task/Stop owners, and
  direct ports;
- independently authored admission sites, workspace task owners, mode branches,
  and direct effect calls decreased;
- every observability non-negotiable has deterministic coverage and an operator
  presentation or external fallback;
- `OperatorWorkspace` lost policy/state instead of accumulating adapters;
- physical safety owners and evidence-class boundaries remain intact.

FIX-05's executable source-identity checker now pins the EA-01 baseline and the
exact current candidate for all six literal metrics: `independent-admission-sites`
18-to-2, `workspace-task-owners` 9-to-0, `environment-mode-branches` 2-to-0,
`direct-effect-calls` 40-to-0, `operator-workspace-policy-state` 6-to-1, and
`operator-workspace-adapters` 7-to-7. Its manifest records the exact
inclusion/exclusion rules, rejects identity drift and wrapper-style replacement,
and does not turn the retained causal simulator or nominal typed runtime ports
into cosmetic exemptions. These facts satisfied only the metric prerequisite;
`GATE-01` subsequently passed its own `PILOT`, `DOC`, and `DIFF` gates through
`TASK-5E431BE7`, attempt `TASK-5E431BE7-59658505ced4`. This authorizes no
attended physical action; `VAL-01` remains the explicit attended boundary.

If genericity, same-slice deletion, device-owner preservation, deterministic
replay, or truthful observability fails, the gate fails and the migration stops
rather than maintaining dual authority.

## Final continuation gate

`Scripts/check_episode_final_gate.sh`, created and tested in `EA-11C`, evaluates
the following closed set of predicates. `GATE-02` runs only after `VAL-01` has
landed the exact attended record for the signed landed FIX-10 validation
candidate. It may mark only its own
row complete after `FINAL-GATE`, `DOC`, and `DIFF` pass:

- every ledger row through `VAL-01` is `complete`, with passed required gates
  and matching Current Evidence;
- the `EA-11C` landing made the projection-bound `PlotterUIIntentSink` the only
  public application semantic-mutation ingress and package `PlotterOperationRegistry` the only
  application-level operation mechanism: one shared residual root adapter plus
  the retained distinct typed feature-runtime lanes, not one monolithic
  registry instance;
- the application root has one source-indexed residual state, one
  projection-bound public sink, nominal lower ports, synchronous
  close-before-await, exact residual/feature joins, persist-before-publish
  ordering, and no reachable false terminated/quiescent state;
- all same-landing deletion inventories are empty and no compatibility bridge,
  old workspace owner, alternate environment branch, or high-level fixture
  remains without a proved non-episode consumer;
- the final matrix links passed evaluator, reachability, replay, perturbation,
  simulation, UI-actionability, refusal, stalled-prefix, incident-export, and
  operator-journey evidence;
- `PHYSICAL-FINAL` links the exact signed landed FIX-10 validation candidate to attended controller,
  camera, operator, UI observability, incident-export, and ink/ambiguity records;
- the packaging decision is explicit: retain the internal packages unless a
  separately authorized second-client proposal proves an SDK boundary.

Any failed or missing predicate leaves `GATE-02` pending or blocked. The gate
moves no authority and cannot repair implementation while assessing it.

## Final validation matrix

| Concern | Required evidence |
| --- | --- |
| state and intent correctness | pure evaluator/reducer cases plus bounded reachability |
| refusal and lock observability | typed owner/revision/remedy, effect progress, UI/runtime revision, stalled-prefix tests |
| episodic memory | durable manifest/event replay, every prefix, corruption and schema tests |
| controller communication | exact and perturbed link replay through production owners |
| camera lifecycle and video | lifecycle replay plus exact frame artifacts where retained |
| physical causality and faults | controller/plant/pen/paper/camera/Vision causal simulation |
| UI actionability | every reached state renders action, wait/progress, remedy, or exact Stop/cancel |
| actual hardware and ink | explicitly attended runbook evidence only |
