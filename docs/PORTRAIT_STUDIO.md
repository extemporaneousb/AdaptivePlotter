# Portrait Studio

Status: current operator and file-format guide for the Flow Edge Dojo. Product
semantics belong to [Product Contract](PRODUCT_CONTRACT.md); implementation owners
belong to [Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md). Actual validation
receipts remain in [Current Evidence](CURRENT_EVIDENCE.md).

Portrait Studio has one authoring journey: choose a photo, explore Flow Edge
constructions, refine a choice, prune whole lines, rank drawings, fit the artist,
and activate a checkpoint for subsequent rounds. The standalone app and embedded
workspace use the same Dojo. Historical Contour, Sketch, SwiftSketch, saved-style
and separate review interfaces are not alternative current authoring paths.

## Build and open

```sh
make portrait-studio-app
make validate-portrait-studio-app
```

These commands build and sign `.build/PortraitStudio.app` without launching it.
Use `APP_CONFIGURATION=release` for an optimized build. The bundle identifier is
`com.bullard.PortraitStudio`, version 0.1.0; it requires macOS 14 or later. Its
Info.plist contains camera permission wording. Launch the signed bundle explicitly;
the raw SwiftPM executable does not have that application identity.

The default portfolio is:

```text
~/Documents/Flow Edge Portfolio.flowportfolio/
```

**Portfolio → New Portfolio…** creates an independent directory. **Open Portfolio…**
reopens an existing one. The standalone executable also accepts one absolute
`--portfolio` directory argument. The old `--review-library` argument is refused
with an explanation; old databases are not interpreted as portfolios or overwritten.
Each portfolio admits one writer. A second app must use another portfolio or wait
for the first writer to close it.

Camera photos retain exact capture time, frame identity/timestamp, acquisition
session, source pixel extent and burst-selection measurements beside their source
image hash. Retrying the same capture identity is idempotent; distinct capture
identities remain separate observations even when image bytes match. The actual
acquisition session can join training partitions; it is not a person identity.

Startup discovers cameras without beginning capture. Explicit capture uses the
existing camera acquisition owner. Quit cancels and joins generation and fitting,
stops capture and waits for durable work. The standalone app has no controller,
calibration, motion, paper-clearance or mechanical Learning controls.

## Build a portfolio

1. **Import Photo** retains the supplied PNG or JPEG bytes inside the portfolio.
   **Capture Photo** retains the selected frame through the existing acquisition
   path. The photo list uses representative artwork or source thumbnails and durable
   names. Browsing a photo, round or drawing records navigation without creating a
   preference; **Choose** is the explicit weaker judgment. Renaming never changes
   image, geometry or training labels. **Import Photo Set** accepts a self-contained
   curated collection of original sources with hash-bound provenance; it creates no
   rankings, targets or inferred subject identities.
2. In **Explore**, choose three to nine drawings and start **Broad exploration**.
   A seeded, bounded panel spans native Flow Edge settings and named geometry
   families. Source context and an activated preference model can guide a bounded
   portion of the panel; generation still performs the requested number of full
   renders. Every completed drawing,
   its exact recipe, raster, program and preview is retained before publication.
   Failed, duplicate and cancelled slots remain recorded; a failed slot does not
   silently become another source or a successful drawing.
3. **Choose** records the displayed alternatives and chosen drawing. **Refine chosen
   drawing** makes a narrower panel around that recipe, including the selected
   parent and its existing mask as an unchanged anchor. Refinement does not erase
   earlier rounds or imply that unchosen alternatives were tied or rejected.
4. **Prune** opens the frozen drawing. Click to Delete removes an entire polyline;
   Lasso selects whole intersecting polylines for Delete Selected. **Restore**
   recovers original lines. Undo/Redo retain their operation relationships.
   **Original**, **Photo**, zoom and Fit provide inspection. There is no drawing,
   replacement or reshaping tool: every target is an exact subset of its basis.
5. **Finish pruning** declares the current kept/removed mask to be the intended
   training target. It is not a Save button: every preceding edit is already on
   disk. An unfinished edit supplies explicit correction labels only; finishing
   supplies target-membership supervision for the entire mask. Further edits create
   a new unfinished revision.
6. In **Rank**, request random sets from this round, this photo, the selected
   drawing's revisions, or the whole portfolio. Rank 1 is the favorite. Equal ranks
   are explicit ties; unranked items remain unknown. Each rank change is autosaved.
   **Neither / none worth keeping** and **Skip** are distinct retained outcomes and
   do not fabricate pairwise preferences. **Compare this set** freezes one current
   version of each included panel drawing; it does not substitute older intermediate
   masks. Random version sets deduplicate exact source/ordered-geometry/style/mask combinations, ignoring generated IDs and provenance.
   Two-item sets prefer pairs with no current judgment; when exhausted, revise a
   previous comparison or create another version. Previous comparisons reopen their
   exact presentation and latest judgment.
7. In **Fit & deploy**, **Fit portfolio** freezes a dataset revision, fits the two
   model components and retains the report and any compatible checkpoint. **Activate**
   makes that checkpoint govern recommendations and proposed removals in new rounds.
   Activate an older retained checkpoint to roll back, or use **Use untrained
   exploration**. Existing drawings and edits never change when activation changes.

Photo and portfolio coverage report effective choices/comparisons, artistic rankings,
remove/keep labels and completed targets. Counts do not treat generated alternatives,
undone edits or inherited masks as new approvals. Comparison counts precede numeric
feature-degeneracy filtering; actual fit reports give usable observation counts.
The most recent fit attempt, most recent usable checkpoint and currently active
checkpoint remain distinct. Feedback changes are compared with exact frozen fit
inputs, including withdrawals, exclusions and declared grouping changes; browsing,
renaming and unrelated unlabelled photos do not make a model stale. A failed attempt
never consumes pending feedback.

The status bar distinguishes busy work, committed revision and persistence errors.
A failed mutation never reports success; it retains pending intent and reconciles
the durable head before retrying when the commit outcome is uncertain. The
acknowledged in-memory state stays unchanged until reconciliation succeeds.
There is no requirement to save photos, drawings, choices, rankings or line edits
explicitly. Source identity declarations and training exclusions are also retained.

**Curate source** can declare an optional subject and photographic session and
exclude a source from fitting. Individual drawings can also be excluded. Exclusion
retains original images, descendants and historical judgments. Identity is a human
declaration; matching appearance is not used to invent subject identity.

## What the artist learns

The drawing model is a deterministic Flow Edge renderer followed by learned
whole-line selection. Its native recipe has twelve normalized coordinates:
spacing, minimum line length, simplification, tone density, coherence, edge
threshold, rectilinearity, tone support, structure support, evidence scale,
seed irregularity and angularity. An optional version-two mark recipe adds wave,
polygon, loop and scale coordinates. Missing mark settings preserve exact legacy
rendering. Outline, Fluid, Rectilinear, Angular, Wavy, Looped, Polygon loops and Blend
families guide broad seeded sampling; local sampling retains the exact selected
basis and perturbs nearby native coordinates.

Rectilinearity controls straight horizontal/vertical tonal strokes. Angularity
uses the existing supported face-region contour treatment; it requires applicable
landmark evidence and is not a promise of arbitrary jagged geometry. Source
preparation and the renderer's existing point/path/material bounds still apply.
Wave, polygon and loop controls mix native tonal constructions within the same
image-evidence and occupancy field. Their maximum controls the probability of a
new mark form, their relative weights choose the form, and the remainder uses
legacy tonal flow. Scale controls wave period, angular segment length and bounded
loop radius. Polygon/loop mixtures can produce closed polygons; loop-only marks
produce circles. Every segment is checked against support, image/field bounds and
occupancy before commitment. These are generated bases, not an edit-time line-add
operation. The source photo, recipe and resulting complete geometry remain available
even when the learned mask removes most lines.

The fitted artist has two components:

- **Drawing preference:** regularized Bradley–Terry logistic utility over recipe,
  photo evidence and actual output geometry. Rankings train score differences.
  Features include quadratic parameter terms, photo interactions, stroke/path
  burden, straightness, turning and spatial coverage of the exact retained mask.
  Two differently pruned versions of one recipe therefore have different features.
- **Line deletion:** regularized logistic prediction using stroke geometry,
  sampled image evidence, landmark-relative support, local neighbors, recipe and
  photo interactions. Explicit remove/restore decisions and completed target masks
  supply direct supervision. Explicitly ranked masks on the same exact basis also
  train pairwise aggregate stroke utility. Comparisons across different bases
  cannot identify which deletion caused a preference and do not supply this loss.

A choice made to refine is weaker evidence than an explicit artistic ranking.
Only the chosen item is compared with the offered alternatives; no ties among
unchosen items are inferred. Ranked lists are weighted per presentation rather than
pretending all their pairwise comparisons are independent judgments. Observations
are reweighted by source-group burden. Single-source observations receive equal
aggregate group weight; arbitrary cross-photo comparisons do not guarantee exact
balance between their source groups. Generated model removals are proposals,
not human labels, until corrected or explicitly completed as a target.

The version-two implementation uses 153 drawing features and 106 stroke features with fixed
normalization. Photo interactions matter: additive photo features alone would
cancel when comparing two drawings of the same photo. These are small generalized
linear models, not a trained image encoder or a claim of complete artistic
understanding. The model can select Flow Edge constructions and exact subsets;
it cannot invent a line absent from the generated basis.

The score-difference formulation follows the
[Bradley–Terry preference likelihood described by Park et al.](https://proceedings.mlr.press/v37/park15.pdf).
[Regularized logistic regression](https://scikit-learn.org/stable/modules/linear_model.html#logistic-regression)
and [grouped evaluation](https://scikit-learn.org/stable/modules/cross_validation.html)
provide the statistical basis; the runtime implementation is local Swift and does
not require Python, a cloud API, pretrained weights or network access.

## Fitting, evaluation and deployment

A fit freezes the exact portfolio revision and retained observation identities.
The coverage display and fit adapter share one effective-supervision projection.
Only bases/versions participating in current comparisons or effective correction
labels allocate features; all unused generated artifacts remain in the portfolio.
Completed masks expand only after allocation limits are checked. Group connectivity
is computed across every source first, including excluded or unlabelled bridges.
All variants of an exact photo, plus connected declared subject/session groups,
remain in one partition. Three or more groups reserve a deterministic held-out
subset; smaller fits are explicitly experimental and have no independent-photo
measurement. Comparisons crossing the split are excluded. Source counts, observation
counts, training loss, held-out loss and baseline loss remain separate quantities.
Mostly one person's photographs cannot establish generalization to new subjects.

A missing component remains inactive. In particular, remove-only corrections do
not create a deletion classifier by labeling all untouched lines as positive.
The user must provide keep evidence through Restore, a completed target, or
attributable ranked mask alternatives. A preference-only checkpoint can recommend
results while leaving every generated line available. If neither component can be
fit, the report is retained without a deployable checkpoint.

The retained fitting configuration includes trainer/renderer/feature/recipe
revisions, regularization, iteration limit, convergence tolerance, seed and the
inference policy. Training uses L2 regularization 0.015, at most 700 full-batch
iterations and gradient tolerance 1e-7. Checkpoints bind the ordered digests of
training examples and rankings rather than duplicating the complete dataset in a
second giant JSON allocation. A local fit is bounded to eight million feature
values and 20,000 comparisons or deletion observations; exceeding the bound
requires a smaller included training selection and never discards portfolio data.

Deployment proposes removal at probability 0.65 or above. If that would remove
every line, it retains the line with the lowest deletion probability, breaking
exact ties by original order. Probabilities, threshold, policy and checkpoint
identity are retained with the proposal. The ranker evaluates the actual masked
output; it recommends a result without deleting the exploration alternatives.
Cancellation returns no new active model. Invalid or incompatible checkpoints
are refused before activation. Archived version-one checkpoints remain readable
with their original identities and reports, but require a new fit for version-two
inference. Reopening a portfolio never relabels or rerenders its old artwork.

Deletion reports retain precision/recall and correction rate for the actual
deployment threshold and nonempty safeguard, alongside the keep-all correction
baseline where held-out direct labels exist. Reports also show explicit remove/keep
counts separately for training and holdout; old reports without these fields display
unknown coverage. A checkpoint remains experimental unless both heads improve their
holdout losses, the deletion holdout includes both classes, and deployed correction
burden improves on keep-all. A remove-only holdout cannot measure false deletions.
Pairwise and binary log losses measure prediction, not physical ink or artistic acceptance. A successful fixture fit and
activation prove the complete software loop; a human preference improvement still
requires held-out human judgments. Validation-fixture portfolios are visibly marked
and cannot masquerade as the artist's real preferences.

Fit readiness means the saved feedback can supply an optimization objective; it
does not mean the fitted model will be useful. The October 31 genuine-feedback copy
fit proposed none of the 78 intended removals on its only completed 306-stroke target,
matching keep-all even in sample. More unlabelled generation cannot fix that evidence
gap. Complete intentional pruning targets and rank alternatives on additional photos,
then compare correction burden on excluded groups. The exact diagnostic and its
limits are recorded in [Current Evidence](CURRENT_EVIDENCE.md).

## Portable portfolio format and durability

The entire `.flowportfolio` directory is the training portfolio. It contains:

```text
portfolio.json   writer-floor version, identity, revision, record hash
records/         immutable hash-addressed operation deltas and parent links
objects/         immutable hash-addressed image, raster, geometry, preview,
                 historical package, frozen dataset, report and model bytes
writer.lock      process-owned exclusive writer lease
```

Every referenced object carries its SHA-256, byte count and media type. Source
photos, analysis rasters, exact generated programs, recipes, generation seeds and
outcomes, ancestry, shown choices, ordered remove/restore/undo/redo revisions,
randomized ranking presentations, judgments, exclusions, frozen fit inputs,
checkpoints, reports, durable names, curated source manifests and activation history
live inside this directory. There are
no required paths back to an imported image, old library or external model runtime.

Objects and operation records are synchronized before an atomic head replacement.
Reopening verifies the hash chain, graph and referenced objects. Interrupted rounds
remain explicit; they are not silently regenerated. The writer lease prevents two
apps from updating the same portfolio. Missing or corrupted committed content is
an error, not permission to replace the portfolio with an empty one. Copy the whole
directory with its writer closed to make a portable backup; copying only
`portfolio.json` does not copy the dataset.

The current writer accepts head versions one and two and publishes version two
on the first mutation or fresh portfolio creation. Opening a version-one history
does not rewrite it. Version two prevents the earlier application from writing
away optional mark recipes, names, or import provenance it does not understand.
Immutable records and frozen document envelopes retain schema one; unknown head
versions are rejected without resetting history.

This is a new training-centered format. Historical `PortraitLibrary` databases,
old source files, selections and experiment exports remain historical artifacts.
An explicit historical import can retain their original packages and exact edited
masks with their provenance; it does not invent rankings, completion declarations
or positive labels. They are not silently migrated into the active artist.

A curated `.flowphotos` folder contains `photo-collection.json` and original bytes
at `images/<sha256>.asset`. Its schema-one entries retain names, image hashes/sizes,
original JSON provenance and optional known acquisition-session keys. Loading
checks bounded counts/sizes, safe paths, image decoding and all hashes. Import is
one atomic source-only transaction, deduplicated by exact image hash and idempotent
on retry. Existing sources, names, grouping, selections and judgments are preserved.
The original manifest is retained as a hash-addressed portfolio object, so the
source collection is not required after import.

## Drawing exchange and physical evidence

**Export Drawing** exports the selected candidate and exact selected pruning
revision as a version-one Drawing Package. Embedded **Send to Drawing** uses the
same package and existing canonical import/handoff owners. The package contains
source bytes, raster input, recipe, original complete program, selected mask,
preview and hash-bound portfolio/source/result identity. Its artist identifier is
`adaptiveplotter.flow-artist`; artist, recipe and renderer revisions follow the
frozen candidate's actual legacy or mark-enabled recipe. Retained stroke coordinates,
IDs, order and pen
styles are unchanged; program identity records the derived result.

An empty mask result remains useful portfolio evidence but cannot be exported as
an executable `DrawingProgram`. In AdaptivePlotter use the ordinary Drawing
placement, material/paper setup and explicit Draw action. Export, import, choosing,
pruning, fitting and activation never move hardware or alter mechanical Learning.
Later portfolio edits cannot mutate a drawing already placed or executed.

The receiving canonical `SavedDrawing` and DrawingEvidence owners continue to own
execution provenance and physical results. Existing Drawing Packages and optional
Plot Attachments retain their version-one contracts; returned records and original
frames are inspection evidence, not motion or redraw authority. Controller
settlement is not evidence of deposited ink. The full portfolio is the training
archive; a single exported drawing is a handoff artifact, not a replacement for it.

## Historical research and baseline

The tag `portrait-studio-baseline-2026-10-11` remains a reproducible reference for
Flow Edge, Contour and Sketch renderer outputs. `make portrait-baseline-check`
checks those frozen kernels; it does not restore their old UI. Earlier SwiftSketch
feasibility, face-framing comparisons and sparse-surface exercises are recorded in
[Current Evidence](CURRENT_EVIDENCE.md). Their existing libraries and signed bundles
remain historical evidence. The current Dojo does not launch their workers or
route new authoring through their separate Artists, Review or Save Drawing flows.
