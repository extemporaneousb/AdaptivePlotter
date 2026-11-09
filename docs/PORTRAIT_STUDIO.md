# Portrait Studio

Status: current operator and file-format guide for the Flow Edge Dojo. Product
semantics belong to [Product Contract](PRODUCT_CONTRACT.md); implementation owners
belong to [Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md). Actual validation
receipts remain in [Current Evidence](CURRENT_EVIDENCE.md). The shared Drawing contract lives in [Drawing Exchange](DRAWING_EXCHANGE.md); remaining adoption work lives in the [Roadmap](ROADMAP.md#drawing-exchange).

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

Custom scratch builds pass the same `SWIFT_FLAGS` to each build/validation target.
The app builders resolve the actual SwiftPM binary directory with those flags and
`APP_CONFIGURATION`; bundle validation checks configuration, stable identity/signature,
source executable SHA-256 and matching Mach-O UUID. A direct builder's explicit
`APP_BINARY_DIRECTORY` must be a nonempty absolute directory. These are local build-input
provenance checks, not notarization or evidence that the signed app was launched.
Prepared signed artifacts and software coverage are recorded in the
[dated group receipt](CURRENT_EVIDENCE.md#current-native-drawing-workflow-group-2026-11-08).

The standalone default Drawing Library is:

```text
~/Library/Application Support/PortraitStudio/DrawingLibrary/
```

Embedded Studio uses `~/Library/Application Support/AdaptivePlotter/DrawingLibrary/`.
The standalone executable accepts one absolute `--library` directory argument.
Each library admits one writer. Close the first app before another app opens the
same directory for writing. Old authoring formats are not active library inputs;
historical files remain untouched and historical import is deferred.

Camera photos retain exact capture time, frame identity/timestamp, acquisition
session, source pixel extent and burst-selection measurements beside their source
image hash. Retrying the same capture identity is idempotent; distinct capture
identities remain separate observations even when image bytes match. The actual
acquisition session can join training partitions; it is not a person identity.

Startup discovers cameras without beginning capture. Explicit capture uses the
existing camera acquisition owner. Quit cancels and joins generation and fitting,
stops capture and waits for durable work. The standalone app has no controller,
calibration, motion, paper-clearance or mechanical Learning controls.

## Edit a retained Drawing

Open **Library** and choose **Drawings** in either app. Both routes use the same
browser/editor and the application's existing Library/collection selection.
AdaptivePlotter's top row is **Library**, **Drawing Studio**, **Plotter**;
Motion/Video remain Plotter-local. Standalone has Library and Drawing Studio, without
device authority. Exact current-format selections and collection scope reopen by ref;
a missing/conflicting ref is unavailable rather than reattached to equal geometry.

Select a retained drawing and choose **Edit**. Click to delete a whole stroke,
use **Lasso** for a selection, or choose **Restore**; Undo/Redo and **Restore All**
remain local until **Done**. **Original** shows the opening drawing. Done saves
an immutable child with the exact parent and surviving stroke IDs/points. Done
with no membership change retains the base without creating a duplicate child.
Removing every stroke cannot be saved. Unsupported preview/edit actions remain
unavailable rather than dropping their requirements. No Photo overlay or pen-width
entry is required by this editor.

**Cancel** before saving discards the local draft without writing. During an admitted
save the button says **Close**: the save can finish, but a closed sheet or changed
selection cannot adopt its late result. After a save error, choose Done again to
retry the same intent; abandoning a draft releases local preparations without deleting committed
data or recovery journals. Editing alone does not send to the plotter or record a
Flow choice/ranking. Embedded **Send to Drawing** is a separate action opening the
existing preparation route; only the existing explicit **Draw** action starts a run.
The standalone browser offers inert **Export Drawing** for transfer.

These operator paths have scoped software coverage. Full hosted button/sheet AX
acceptance is a separate strict host-dependent check; no signed-app restart or
physical plotting validation is implied. See the [dated receipt](CURRENT_EVIDENCE.md#dx-08-shared-drawing-editor-software-receipt-2026-11-08).

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
   renders. Completed candidate metadata is saved. Unselected geometry, rasters and
   previews stay temporary and bounded; **Choose**, pruning or explicit Plot handoff
   retains the exact Drawing revision and dependencies. Rank captures durable exact
   feature capsules and previews for its presentations.
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
the durable library state before retrying when the commit outcome is uncertain. The
acknowledged in-memory state stays unchanged until reconciliation succeeds.
There is no requirement to save photos, drawings, choices, rankings or line edits
explicitly. Source identity declarations and training exclusions are also retained.

In **Library → Photos**, choose a Photo to edit its optional title, subject/session
and training exclusion. These fields replace the Curate popover and use the same
neutral metadata authority. Accepted edits drain before shutdown. Exclusion retains
images, descendants and judgments; subject identity is never inferred from appearance.
Open **Drawing Studio** adopts that exact existing Photo, preserving its dates and
cleared metadata. Supported PNG/JPEG sources remain authorable; raw/unsupported sources
stay browsable/exportable with an explicit authoring refusal. Photos show capture,
import-fallback or unknown date truthfully, with exact prepared Inputs and branches.
Source-free Drawings remain available in the global Drawings collection without a Photo.

**Attempts** belongs to the selected Drawing. Declared portable result snapshots,
staged raw bindings and verified current raw evidence are distinguished; snapshot or
binding counts do not prove physical attempts or ink. Stored environment is displayed
rather than borrowed from the current controller mode. Missing evidence remains
unavailable. Existing global Stop remains usable across workspaces; active-run guards
prevent editor/picker presentation from hiding it. No implicit project or Start occurs.

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

Train freezes an exact feature-only task before fitting. It pins canonical human
feedback, exact feature/label bytes, producer receipts, extractor and trainer versions,
recipe, curation, seed/configuration and group/split assignments. The fitter reads only
that manifest's dependencies; it does not look up a current UUID or re-extract geometry.
Later edits or grouping/exclusion changes affect only future fits. Missing, corrupt or
unsupported frozen dependencies produce an unavailable result, not regeneration.
There is no additional setup, width declaration or required field.

The coverage display and freeze use the same effective-supervision resolver. Explicit
rankings, partial ranks, Neither and Skip remain distinct; unranked is unknown. Choose
records only the selected direction against offered alternatives, not loser-versus-loser
judgments. Remove/Restore and Finish pruning retain their existing explicit-label rules.
Choose/prune retains the requested Drawing first, then commits canonical feedback and
navigation atomically; acknowledgement waits for both. A failed feedback phase can leave
that explicitly requested Drawing retained without claiming a saved judgment. Rank
retains features and optional display previews, not compared Drawing geometry. The
portable training task excludes those previews, source photos and the UI portfolio view.

Connectivity is frozen across every source before exclusions, including unlabelled
bridges: exact encoded-source-byte identity and connected declared subject/session
groups stay together. Equal decoded pixels across different encodings are not established
as equivalent here. Three or more groups reserve a deterministic held-out subset;
smaller fits remain experimental. Comparisons crossing the split are excluded. Source
counts, observation counts, training loss, held-out loss and baseline loss remain separate.
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

## Drawing Library format and durability

The concrete `DrawingLibrary` actor owns the selected directory:

```text
drawing-library.sqlite   strict local schema 10, profile adaptiveplotter.drawing-library/1
objects/sha256/<digest>   immutable content-addressed records and assets
```

SQLite owns transactional catalog and authoring metadata. Sources, prepared inputs,
retained Drawings, parent/edit relationships, ranking features and previews, frozen
training snapshots, reports, checkpoints and activation history use this owner.
Objects are installed before their metadata is selected. The writer lease prevents
competing writers; changed or corrupt selected files fail visibly rather than
opening an empty replacement library. Pending mutations reconcile through the same
owner before retrying an uncertain commit. No separate portfolio head or delta
publisher remains.

Generated geometry is temporary and bounded. Selection, committed pruning and
explicit Plot handoff retain exact immutable revisions; pruning creates a child
reference and preserves its required parent. Rank may keep durable features and
preview bytes for unselected alternatives without keeping their full geometry.
Reopening does not silently regenerate evicted geometry. Copy the entire closed
library directory for a backup; the SQLite file alone does not include its assets.
Historical authoring files remain untouched outside this format. Their import is
deferred and is not a startup requirement.

A curated `.flowphotos` folder contains `photo-collection.json` and original bytes
at `images/<sha256>.asset`. Its schema-one entries retain names, image hashes/sizes,
original JSON provenance and optional known acquisition-session keys. Loading
checks bounded counts/sizes, safe paths, image decoding and all hashes. Import is
one atomic source-only transaction, deduplicated by exact image hash and idempotent
on retry. Existing sources, names, grouping, selections and judgments are preserved.
The original manifest is retained as a hash-addressed portfolio object, so the
source collection is not required after import.

## Drawing exchange and physical evidence

**Export Drawing** exports the selected immutable Drawing revision through the
Drawing Exchange v1 directory/ZIP carrier. Studio's file export writes a ZIP;
AdaptivePlotter accepts the current directory or ZIP carrier. The closed payload
retains the exact program, producer receipt, declared source/input and required
parent/assets. Every reference pins issuer, revision and record digest. Embedded
**Send to Drawing** passes the admitted Drawing and reference directly, without
serializing and reimporting a package.

Retained stroke coordinates, IDs, order and styles remain unchanged. Pruning makes
an immutable child Drawing. An all-removed mask can remain training evidence but
cannot become an executable drawing. Field-space preview width does not establish
millimeters. Nominal physical pen width is optional for fresh and retained Drawings;
unknown width adds no required field or setup step.

In AdaptivePlotter continue with ordinary Drawing placement, material/paper setup
and explicit **Draw**. Export, import, choosing, pruning, fitting and activation
never move hardware or alter mechanical Learning. Later edits cannot mutate placed
or executed geometry.

The existing raw DrawingEvidence owner retains execution, possible-ink and
no-redraw authority. The authoring library records an exact DrawingRef association
to an already-staged run through the existing pre-motion adapter; that association
is not physical evidence. Controller settlement does not prove deposited ink.
Historical drawing packages and plot attachments remain untouched files, with
historical import deferred. A drawing export is a handoff artifact, not a backup of
all training records.

## Derived presentation work

Photo/candidate previews load through bounded derived caches with cancellation and
stale-selection guards. Rename/navigation reuses an unchanged active checkpoint and
training summary; feedback, grouping/exclusion and fit changes invalidate the relevant
work. Cache eviction preserves the retained originals and canonical feedback. These
changes add no setup, physical-width field or new learning action. The measured
current-format fixture and its limits are in Current Evidence; remaining signed native
interaction and large-media performance acceptance are separate.

## Historical research and baseline

The tag `portrait-studio-baseline-2026-10-11` remains a reproducible reference for
Flow Edge, Contour and Sketch renderer outputs. `make portrait-baseline-check`
checks those frozen kernels; it does not restore their old UI. Earlier SwiftSketch
feasibility, face-framing comparisons and sparse-surface exercises are recorded in
[Current Evidence](CURRENT_EVIDENCE.md). Their existing libraries and signed bundles
remain historical evidence. The current Dojo does not launch their workers or
route new authoring through their separate Artists, Review or Save Drawing flows.
