# Portrait Studio

Portrait Studio owns authoring and the photo library. Browse photos with or without
drawings, explore Flow Edge alternatives, prune lines, rank drawings and fit the
artist. Send the selected revision to AdaptivePlotter for placement and execution.

[Product Contract](PRODUCT_CONTRACT.md) defines the operator controls and evidence.
[Drawing Exchange](DRAWING_EXCHANGE.md) defines the files the apps exchange.

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

Portrait Studio opens the following authoring library by default.

```text
~/Library/Application Support/PortraitStudio/DrawingLibrary/
```

Use `--library` with an absolute directory to open a different catalog in Studio.
AdaptivePlotter keeps its received revisions and job records in its machine-local
storage. Both apps can run together. The [offline conversion instructions](#recover-historical-photos-and-plotted-drawings)
cover previous formats.

Camera photos retain exact capture time, frame identity/timestamp, acquisition
session, source pixel extent and burst-selection measurements beside their source
image hash. Retrying the same capture identity is idempotent; distinct capture
identities remain separate observations even when image bytes match. The actual
acquisition session can join training partitions; it is not a person identity.

The top row has **Photo Booth**, **Photos**, **Drawing**, and one right-aligned
**Send to Plotter** action. **File → Import Photo…** imports one original;
**File → Import Photo Set…** imports several original images or an existing curated
photo-collection folder. Import and export commands belong to the active window.

**Photo Booth** has resizable photo and drawing panes. The left pane shows the
immutable, oriented original: drag outside the current rectangle to make a region,
drag inside to move it, or drag a corner to resize. **Whole photo** bypasses face
cropping; **Auto face** restores automatic face framing. **Selection** inspects the
draft without changing it. **Apply region** commits once and requests a drawing for
that exact region; dragging never renders on each pixel. Leaving with an unapplied
draft discards it. Historical regions and their drawings remain available in Drawing.

The right pane shows **Suggested drawing** for an untrained artist. It says
**Predicted favorite** only when a valid active preference checkpoint scored the
bounded produced set and selected its actual best candidate with the exact displayed
removal mask. Editing that mask downgrades the label to Suggested drawing; undoing
back to the scored membership can restore it. Clicking the suggestion
opens Drawing immediately and begins broad exploration without recording feedback.
The clicked suggestion remains a temporary Starting drawing anchor while that broad
set loads; it creates no parent relation or direction-choice judgment.

No camera starts at launch or on tab changes. **Live preview** opens deliberate
camera selection; **Start preview** acquires only that chosen Studio camera.
Repeated captures reuse the owned session, freeze separate immutable originals, and
update the suggestion without rendering continuously from video. **Use still photo**,
leaving Photo Booth, and closing Studio cancel capture, clear illumination and release
Studio's session. File-photo authoring works without a camera. Explicit capture uses the
existing camera acquisition owner. Quit cancels and joins generation and fitting,
stops capture and waits for durable work. The standalone app has no controller,
calibration, motion, paper-clearance or mechanical Learning controls.

## Edit a retained Drawing

In Portrait Studio, open **Photos** and choose **Drawings**, or select a photo
and follow its prepared inputs to their drawings. A photo can have zero or more
drawings. Photo rows show their images and drawing rows preview their strokes.
Titles are optional. Titles and training annotations belong to the catalog. The original pixels,
date facts and photo identity are immutable.
Studio restores the selected revision by its exact reference.

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
Flow choice/ranking. Use the handoff action to prepare a saved revision or
**Export Drawing** to write a portable copy.

## Send to Plotter

Select a visible drawing and choose the top-row **Send to Plotter**. It is disabled
for a photo-only or empty selection, a stale source/region, an unsupported or empty
drawing, generation/loading, local edit recovery, or an active handoff. A valid
unplaced drawing can be sent independently of Plotter's connection, calibration or
current motion. Changing tabs, photos, regions or revisions cancels stale handoff
publication; the exact selected revision is rechecked across asynchronous work.
Studio records a Prepare request for the exact revision. It opens the running
Plotter or the sibling AdaptivePlotter bundle on a cold launch. The destination
shows the reference drawing and reports any missing tip registration or Drawing
Boundary. Once placement is available, review the prepared drawing in the
plotter's Drawing panel. Opening a Drawing Exchange document in Studio selects
the imported revision in Drawing.

Prepare and document opening issue no Start/controller commands. Explicit native
**Draw** uses the existing Run owner and durably binds the exact request, Drawing,
reviewed plan and one attempt before effects. File handoff remains Prepare-only.
A cached preparation response is a recorded snapshot; current submission facts
must still match. Recovery reconciles that attempt without another dispatch.

A pending request is durable before handoff. If the open event/reply is lost, relaunch
republishes it; the running destination's Prepare-only recovery can consume it without
another open event or foreground action. Closing a source view with already-admitted
work can leave that durable Prepare queued. Valid replies retire only client pending
files/records, not the engine's facts. Imports remain explicit: no generic ZIP association
is installed by these declarations. Exact Drawing bytes/connections and unknown nominal
width remain intact. Signed native interaction and physical execution remain separate
acceptance steps; agent checks use disposable owners/offscreen callbacks/helper processes.

For the developer's disposable protocol check, the current script builds the real
non-device helper and runs the two affected suites serially:

```sh
bash Scripts/test_drawing_destination.sh \
  --scratch-path /absolute/disposable/swift-scratch \
  --xunit-output /absolute/disposable/destination-tests.xml \
  --jobs 4 --evidence-directory /absolute/disposable/refusals
```

This does not launch either app. It is not a production execution command. Current
process/log/XML/refusal artifacts and scope are in
[Current Evidence](CURRENT_EVIDENCE.md#dx-12-local-destination-and-prepare-software-receipt-2026-11-08).

## Build a portfolio

1. **File → Import Photo…** retains the supplied PNG or JPEG bytes inside the portfolio.
   **Capture photo** in Photo Booth retains the selected frame through the existing acquisition
   path. The photo list uses representative artwork or source thumbnails and durable
   names. Browsing a photo, round or drawing records navigation without creating a
   preference; clicking a generated tile is an explicit **Choose and refine** direction judgment. Renaming never changes
   image, geometry or training labels. **Import Photo Set** accepts a self-contained
   curated collection of original sources with hash-bound provenance; it creates no
   rankings, targets or inferred subject identities.
2. In **Drawing → Explore**, choose three to nine drawings and start **Broad sample**.
   A seeded, bounded panel spans native Flow Edge settings and named geometry
   families. Source context and an activated preference model can guide a bounded
   portion of the panel; generation still performs the requested number of full
   renders. Each completed candidate saves an exact private authoring closure of
   its Drawing, producer, units, prepared input, raster and preview before completion
   is published. This does not add a gallery Drawing or an artistic judgment.
   **Choose**, pruning or explicit Plot handoff retains the exact Drawing revision
   and dependencies in the gallery. Rank captures durable exact
   feature capsules and previews for its presentations.
   Failed, duplicate and cancelled slots remain recorded; a failed slot does not
   silently become another source or a successful drawing.
3. Click any completed drawing tile to **Choose and refine**: this records one
   weak direction choice against the exact offered alternatives and immediately
   opens a child page around that recipe. The chosen parent and its existing mask
   remain the unchanged anchor while nearby results appear. The first neighborhood
   has radius 0.06; each deeper choice contracts it by 0.85 to a floor of 0.015.
   **Broad sample** starts a fresh wide root; **Back** and branch history restore
   saved sets without rendering or recording preference. New branches and unchosen
   siblings remain exactly usable through multiple levels, photo/region switches
   and reopening while their private disk closures remain within the history bound.
   The RAM hot tier remains count/byte limited and rehydrates verified material
   without rendering. The private disk spool permits at most 512 entries, 2 GiB
   of logical file bytes in total and 64 MiB per exact closure, including staging
   and complete orphan entries. It never silently evicts an older promised branch
   to admit new work: quota refusal stops new generation locally and preserves
   existing history. Legacy pre-spool drawings with genuinely missing artifacts
   may remain **Preview only**, with the reason and unavailable actions explicit. Completed tiles and history
   remain navigable during generation; replacing a request cancels stale publication.
   **Edit drawing** opens line editing separately from the tile's direction choice.
   Refinement preserves earlier rounds and supplies no strong rating or explicit
   pairwise ranking for unchosen drawings.
4. **Prune** opens the frozen drawing. Click to Delete removes an entire polyline;
   Lasso selects whole intersecting polylines for Delete Selected. **Restore**
   recovers original lines. Undo/Redo retain their operation relationships.
   **Original**, **Photo**, zoom and Fit provide inspection; **Return to editing**
   exits comparison explicitly, and opening an edit clears inherited comparisons.
   Any disabled editor reports its local reason. A separate running Plotter has no
   authority over Studio line editing. There is no drawing,
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

In **Photos**, choose a Photo to edit its optional title, subject/session
and training exclusion. These fields replace the Curate popover and use the same
neutral metadata authority. Accepted edits drain before shutdown. Exclusion retains
images, descendants and judgments; subject identity is never inferred from appearance.
**Open in Photo Booth** uses the photo’s exact reference and preserves its dates and
cleared metadata. Supported PNG/JPEG sources remain authorable; raw/unsupported sources
stay browsable/exportable with an explicit authoring refusal. Photos show capture,
import-fallback or unknown date truthfully, with exact prepared Inputs and branches.
Source-free Drawings remain available in the global Drawings collection without a Photo.

**Attempts** belongs to the selected Drawing. Declared portable result snapshots,
staged raw bindings and verified current raw evidence are distinguished; snapshot or
binding counts do not prove physical attempts or ink. Stored environment is displayed
rather than borrowed from the current controller mode. Missing evidence remains
unavailable. Plotter keeps Stop accessible while Studio browses or edits.

In AdaptivePlotter, open **Execution History** in the Drawing panel or **Review Run**
after execution. Select a job-bound attempt and choose **Export Run Result** to
write its Drawing Exchange ZIP with the retained staged, interrupted or terminal evidence. It does not create a new attempt. Missing/corrupt evidence
produces a visible refusal while recovery and possible-ink facts stay retained.

The retained drawing browser in **Photos** and **Drawing** offers **Import Result** and export of an exact mounted result. The read-only inspector shows job/attempt identity, recorded frontiers,
missing reasons and separately attributed annotations. Open an original image
explicitly to preview it; unsupported or oversized previews keep the retained
original available for export. Unknown annotations do not invent a physical
interpretation. A returned result cannot authorize local retry, redraw or model
activation. Existing sealed snapshots are immutable.

## What the artist learns

The drawing model is a deterministic Flow Edge renderer followed by learned
whole-line selection. Its native recipe has twelve normalized coordinates:
spacing, minimum line length, simplification, tone density, coherence, edge
threshold, rectilinearity, tone support, structure support, evidence scale,
seed irregularity and angularity. An optional version-two mark recipe adds wave,
polygon, loop and scale coordinates. Missing mark settings preserve exact legacy
rendering. New broad samples use Outline, Fluid, Rectilinear, Angular, Wavy and
supported blends. New proposals and refinements exclude synthesized circular loop
marks, including noise or blend paths that previously reintroduced them. Natural
curved image contours remain supported. Historical circle-bearing recipes still
decode and render exactly; their old drawings remain available.

Local exploration perturbs nearby effective controls within the contracting radius.
An older circle-bearing parent remains a historical anchor. Its new descendants use
sanitized recipes and are rendered again; their new geometry does not inherit an
index-based removal mask from the incompatible old basis.

Rectilinearity controls straight horizontal/vertical tonal strokes. Angularity
uses the existing supported face-region contour treatment; it requires applicable
landmark evidence and is not a promise of arbitrary jagged geometry. Source
preparation and the renderer's existing point/path/material bounds still apply.
Wave and polygon controls mix native tonal constructions within the same
image-evidence and occupancy field. Their maximum controls the probability of a
new mark form, their relative weights choose the form, and the remainder uses
legacy tonal flow. Scale controls wave period and angular segment length. The
historical renderer also supports polygon/loop mixtures and loop-only circles for
retained recipes; these controls do not enter new authoring proposals. Every
segment is checked against support, image/field bounds and occupancy before
commitment. These are generated bases, not an edit-time line-add operation. The source photo, recipe and resulting complete geometry remain available
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
second giant JSON allocation. The frozen task reader and local trainer accept up to
ten million logical feature values and 20,000 comparisons or deletion observations.
Examples that share verified stroke features reuse the same backing storage. If a
selection exceeds the limit, the full portfolio remains available for a smaller fit.

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
flow-authoring-history-v1/ private bounded exact candidate closure spool
```

SQLite owns transactional catalog and authoring metadata. Sources, prepared inputs,
retained Drawings, parent/edit relationships, ranking features and previews, frozen
training snapshots, reports, checkpoints and activation history use this owner.
Objects are installed before their metadata is selected. The writer lease prevents
competing writers; changed or corrupt selected files fail visibly rather than
opening an empty replacement library. Pending mutations reconcile through the same
owner before retrying an uncertain commit. No separate portfolio head or delta
publisher remains.

New generated candidates have hash-anchored immutable private history closures,
with a bounded RAM hot tier. This history is separate from retained gallery Drawings
and learning judgments. Photo/region navigation and reopening do not delete or
regenerate within-bound alternatives. The single store writer publishes each
complete closure atomically before its candidate metadata, accounts staging and
complete orphans against quota, and refuses new admission when full. Missing or
corrupt material fails visibly; legacy missing closures are not invented.
Selection, committed pruning and explicit Plot handoff retain exact immutable
revisions in the common Library; pruning creates a child reference and preserves
its required parent. Rank retains exact features and previews for its judgments. Copy the entire closed
library directory for a backup; the SQLite file alone does not include its assets.
The offline converter reads the historical authoring files from their original directories.

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
parent/assets. Every reference pins issuer, revision and record digest. Sending a
drawing between the applications uses an exact-revision Prepare request.

Retained stroke coordinates, IDs, order and styles remain unchanged. Pruning makes
an immutable child Drawing. An all-removed mask can remain training evidence but
cannot become an executable drawing. Field-space preview width does not establish
millimeters. Nominal physical pen width is optional for fresh and retained Drawings;
unknown width adds no required field or setup step.

In AdaptivePlotter continue with ordinary Drawing placement, material/paper setup
and explicit **Draw**. Export, import, choosing, pruning, fitting and activation
never move hardware or alter mechanical Learning. Explicit Draw retains the exact
original request, Drawing and reviewed plan under one durable job and Run attempt.
Stop is available while preparation is pending. A retry or recovered acknowledgement
reconciles that attempt and never starts another drawing. Later edits cannot mutate
placed or executed geometry.

The existing raw DrawingEvidence owner retains execution, possible-ink and
no-redraw authority. The destination records an exact DrawingRef association
to an already-staged run through the existing pre-motion adapter; that association
is not physical evidence. Controller settlement does not prove deposited ink.
Historical plot references are available from converted Drawings and the accompanying
raw archive. A drawing export is a handoff artifact, not a backup of
all training records.

## Derived presentation work

Photo/candidate previews load through bounded derived caches with cancellation and
stale-selection guards. Rename/navigation reuses an unchanged active checkpoint and
training summary; feedback, grouping/exclusion and fit changes invalidate the relevant
work. Cache eviction preserves the retained originals and canonical feedback. These
changes add no setup, physical-width field or new learning action. The measured
current-format fixture and its limits are in Current Evidence. See the personal archive
receipt there for signed native interaction with historical photos and drawings.

## Recover historical photos and plotted drawings

From the repository, run the converter with a new output directory. The default sources are the
old Portrait Library SQLite catalog and the adjacent DrawingEvidence archive in Application
Support. Include the Flow portfolio to recover its photos and their acquisition metadata.

```sh
python3 Scripts/convert_historical_drawings.py "$HOME/Documents/Recovered Drawings" \
  --portfolio "$HOME/Documents/Flow Edge Portfolio.flowportfolio"
```

Open the resulting `DrawingLibrary` directory with Studio's existing `--library` launch argument
after quitting that Studio instance. In **Photos**, select a photo to browse its prepared inputs and exact
drawings, or use **Drawings** for the full list. Expand **Historical plot runs** on a recovered
drawing to inspect recorded status, stroke counts and operator no-ink confirmations.
Choose the top-row **Send to Plotter** to send the selected revision.

The default selection includes all source photo occurrences, catalog drawings associated with
execution or possible ink, and the saved transfers. The adjacent `conversion.json` maps the old
IDs to current Photo and Drawing refs and indexes the copied raw evidence by run ID and digest.
The `Plot Photographs` folder contains viewable PNGs of retained live terminal frames from
linked runs. The report records each original frame digest and capture reference.
Quarantined runs retain their original reason. An interrupted attempt may have no terminal
record. Only the recorded ink-verified frontier supports a verified stroke count.

Use `--drawing ID` for an additional catalog drawing or Flow candidate or pruning revision, `--all-drawings` for
all stored candidate programs and nonempty Flow pruning revisions, `--photo-library DIRECTORY` for another catalog's photos, or
`--package FILE.portraitdrawing.json` for a frozen Flow export or line edit. These options are
offline imports into a fresh directory. Existing libraries, portfolio journals and evidence
stay at their original paths. Fully removed drawings appear in the report as
empty masks. A missing preparation stays explicitly unavailable.

### Recover an existing artist portfolio

For the two catalogs created by the earlier apps, quit both apps and reconcile
their contents into a new directory. Then recover the original Flow Edge
decisions against the photo and drawing references from the first conversion.

```sh
recovery_dir="$HOME/Documents/Studio Catalog Recovery"
app_data="$HOME/Library/Application Support"
python3 Tools/DrawingExchange/reconcile_catalogs.py \
  --authoritative "$app_data/PortraitStudio/DrawingLibrary" \
  --received "$app_data/AdaptivePlotter/DrawingLibrary" \
  --output "$recovery_dir/DrawingLibrary"
swift build -c release --product HistoricalDrawingImport
python3 Tools/DrawingExchange/recover_flow_learning.py \
  --archive "$HOME/Documents/Flow Edge Portfolio.flowportfolio" \
  --references "$HOME/Documents/Recovered Drawing Archive/conversion.json" \
  --library "$recovery_dir/DrawingLibrary" \
  --importer "$(swift build -c release --show-bin-path)/HistoricalDrawingImport" \
  --receipt "$recovery_dir/flow-recovery.json"
```

The recovered library includes the original choices, rankings and stroke edits.
Studio uses those decisions in its current training inputs. The original fit
reports, checkpoints and their frozen training documents retain their original
bytes and provenance. The importer also freezes the recovered decisions, fits the
current trainer and verifies that the task reopens. The receipt identifies the new
fit. The artist controls activation in Studio. Open a recovered library with
`--library`. The
importer’s `--export-flow-history LIBRARY ARCHIVE_ID NEW_DIRECTORY` command
recreates the original portfolio from the recovered catalog. Use the archive
ID in the recovery receipt.

## Historical research and baseline

The tag `portrait-studio-baseline-2026-10-11` remains a reproducible reference for
Flow Edge, Contour and Sketch renderer outputs. `make portrait-baseline-check`
checks those frozen kernels; it does not restore their old UI. Earlier SwiftSketch
feasibility, face-framing comparisons and sparse-surface exercises are recorded in
[Current Evidence](CURRENT_EVIDENCE.md). Their existing libraries and signed bundles
remain historical evidence. The current Flow Edge workspace does not launch their workers or
route new authoring through their separate Artists, Review or Save Drawing flows.

Native layout regression checks run with `make native-layout-test` (also included
in `make journey-test`). The bounded-workspace fixture covers all authoring stages
at both sizes, including fresh ranking pairs and pruning canvas bounds. Production
hosts retain the minimum-size and larger-size geometry, photo/branch scrolling,
workspace identity and render-count checks; shared sidebar OCR runs once per size.
These owned offscreen windows do not establish attended interaction or camera use.
Set `PORTRAIT_NATIVE_AX_CHECK=1` only on an AX-capable test host to include the
native accessibility interaction checks. `make quick-test` excludes these native
journeys; use both targets when changing Portrait layout.

Run `make drawing-architecture-test` after changing package dependencies. It
passes SwiftPM's evaluated manifest to the dependency contract test, retaining the
Drawing and artist transitive-closure assertions without a nested SwiftPM process
inside the normal unit suite. `SWIFT_FLAGS` applies to its Swift test invocation.
