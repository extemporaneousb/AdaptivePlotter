# AdaptivePlotter Roadmap

Status: unfinished work only; never completion evidence

Current implementation and verification are recorded in
[Current Evidence](CURRENT_EVIDENCE.md). Product authority is
[Product Contract](PRODUCT_CONTRACT.md). The architecture migration and its
dependencies are owned exclusively by
[Episode Architecture Execution Plan](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md);
this roadmap does not restate or reorder them.

## Drawing Exchange

### Current-format app delivery

The release target is a usable Drawing workflow in both applications. Start with a
fresh Library. Import a photo, generate alternatives, choose or refine one, edit
its strokes, and reopen the same retained revision. Browse by photo date, rank
without retaining rejected drawings, and export the selected revision. Import that
export into the other app's fresh Library. Repeat with a source-free Drawing.
Prepare on Plotter must select the exact revision and show the actual readiness
reason with Stop accessible. Use fake effects for automated handoff. A signed
native check covers visible navigation, focus, and reopen on the running UI.

Historical authoring archives, old catalog schemas, file associations, saved
layouts and portfolio continuity are outside this release. Existing files stay
untouched. The current Drawing Exchange v1 profile, new-library restart/recovery,
digest verification and raw physical evidence remain required. The completed
[DX-01 inventory](CURRENT_EVIDENCE.md#reachable-callers-replacement-and-retained-owners)
records the former owners. Use current call sites for implementation.

### Delivery rules and ownership

DX-10 is adopted under its recorded definition. Group the eligible slices in each
row below into one Blackdog task, one workspace,
one integration owner and one configured validation on the integrated tree.
Retain the individual DX IDs and their acceptance criteria. Within a group, reuse
the preceding slice's work directly. Split a group when a genuine dependency,
separate execution authority or independently shippable outcome requires it.

During development run `make drawing-app-test` and the tests specific to the
changed behavior. Reuse the worktree's incremental build. Run the configured
suite at landing and rerun affected checks after a fix. Keep one short outcome
receipt for the group with the actual commands, results and any unverified
interaction. Use Blackdog’s validation event and commit for provenance. Keep raw
logs with the run, outside Git. Assign one owner to run a check and wait for
its exit. Send updates when a decision, failure or completed interaction changes
the work.

### DAG and delivery milestones

| Delivery order | Work and dependencies | Acceptance |
|---|---|---|
| 1. Native Drawing workflow | DX-10 builds on DX-08/09. Follow it with DX-11, the current-format app packaging in DX-18, the corresponding DX-19 cleanup and the native authoring cases of DX-20. | Demonstrate the fresh-library journey above in both signed apps. Measure browsing and editing, and remove replaced screens and readers alongside their callers. This milestone can ship independently of the engine. |
| 2. Job protocol | DX-12 uses DX-02/06. DX-13 depends on DX-12 and an eligible named episode package. | Exercise separate-process job identity, refusal and restart on disposable stores. Record the exact unavailable runtime seam if DX-13 is blocked. |
| 3. Returning results | After the DX-13 seam, group the eligible DX-14/15 adapters. DX-16 consumes DX-09 and DX-15. Finish engine-specific DX-18/19 integration with its owning change. | Prepare the exact Drawing, recover jobs through the existing runtime, and inspect returned evidence offline. Keep the raw owner of Stop, possible ink, retry and run evidence. |
| 4. Integrated software release | Complete the remaining DX-20 regression and scale cases on the integrated tree, then DX-21 independent final review. Reuse applicable native evidence from the first delivery. | Both app routes, current-format integrity/recovery, responsiveness and simulated return pass their gates. |
| 5. Attended deployment | DX-22 follows DX-21 and requires separate operator authorization. | Signed-app handoff and attended ink evidence each have their own result. |

DX-17a/b are deferred. No active milestone depends on either. Any change to an
episode-owned runtime seam still requires a named eligible package under the
[episode workflow](../.codex/guidance/adaptiveplotter-workflow.md). A blocked
seam cannot block the native Drawing workflow. Production data, physical motion
and model promotion remain separate operator decisions.

### Ticket acceptance contracts

DX-01's baseline, adopted DX-02/DX-03 contracts and DX-04's implemented
single-writer storage scope are retained in their dated
[Current Evidence receipts](CURRENT_EVIDENCE.md#drawing-exchange-dx-04-single-writer-catalog-receipt-2026-11-07).
Those receipts retain accepted scope/gate/recovery constraints and distinguish
source observations from authoritative validation/adoption. The
[DX-05 cutover receipt](CURRENT_EVIDENCE.md#drawing-first-canonical-adoption-2026-11-08)
records adoption of the single active format.

The adopted DX-06 inert public result API is recorded in the
[dated canonical receipt](CURRENT_EVIDENCE.md#dx-06-canonical-adoption-2026-11-08):
normal landing at `7d67e815fb07045933ed5fa23d0bea8cc7bef0d5`, with all seven
bounded caller-declared criteria current/met. Result identity remains the exact
index/inventory pair; inert result support does not change physical authority.

The adopted DX-07 source/metadata/retention boundary is recorded in the
[canonical receipt](CURRENT_EVIDENCE.md#dx-07-canonical-adoption-2026-11-08):
normal main landing `8291a0a8b0f766e2fc0b80257727066d82e41a9a`, all eight bounded
caller-declared criteria current/met. Its strict forward-only schema 11, one live
Photo metadata authority and Photo-only frozen metadata isolation do not complete
DX-09 feature/feedback manifests, historical import or GC.

**DX-08 — Shared Drawing membership editor production routes.** Adopted on main at
`6a1108dc311ce90c2c24ebad7f13dc43125b98ac`, all eight bounded caller-declared artifact
criteria current/met after verified normal landing. The shared browser/editor reuses
one collection and native canvas with exact/drained saves and stale-completion guards.
The [canonical receipt](CURRENT_EVIDENCE.md#dx-08-canonical-adoption-2026-11-08) retains
its test/host limits: default constructor/canvas/separate-model evidence is not hosted
browser private-state/button/sheet or AX acceptance. Flow pruning remains intact.

DX-09 completed normal main adoption at `c7b29057eaf6426bdeb0f3d27a59e91201872fe0`,
all nine bounded caller-declared artifact criteria current/met. Its
[canonical receipt](CURRENT_EVIDENCE.md#dx-09-canonical-adoption-2026-11-08) retains
actual full-gate, grouping/provenance and environment limits; no whole-campaign or
physical/model-promotion claim follows.

**DX-10 — Photos/Drawings browser and Curate cutover.** Adopted normally on main at
`ac0e53e500a0c673343aae7280668f6d14573439`, exact validated tree
`e52c17b76503de6e28d868dffb153e68b0582e33`, all ten bounded caller-declared artifact
criteria current/met. The [canonical receipt](CURRENT_EVIDENCE.md#dx-10-canonical-adoption-2026-11-08)
records the actual gate, verified adoption and separate unknown terminal environment.
The implementation boundary is in
`DrawingLibrary{Reads,Sources,Records,Results,Attempts}`, `PortraitSketchCollection`,
`FlowPortfolioStore/Graph`, `PortraitDrawingAttemptBinding`, `FlowDojoModel`, shared
`DrawingLibrary{Browser,Navigation,SourceView}` and actual embedded/standalone route owners.
The top row uses Library/Drawing Studio/Plotter; optional contextual Photo metadata
replaces Curate, exact existing Photo adoption preserves identity/metadata, typed
current-format collection/Photo/Input/Drawing/branch bookmarks reopen without fuzzy
fallback, and result snapshots/staged bindings/raw evidence remain distinct. Existing
Stop and raw possible-ink authority remain accessible and current; no issuance bridge
is claimed. See [scoped software observations](CURRENT_EVIDENCE.md#dx-10-library-and-drawing-studio-cutover-2026-11-08).

Native focus/button/sheet/AX and signed-app interaction remain bounded by actual host
evidence. The current DX-11/current-app DX-18/caller-proven DX-19/native-authoring DX-20
software slice is `task-1eea571945e34554aebcc95ffa636824`; its
[dated pre-gate receipt](CURRENT_EVIDENCE.md#current-native-drawing-workflow-group-2026-11-08)
records affected measurements, the bound-cursor correction, current-tool checks and
prepared signed bundles. Final configured acceptance/adoption belongs to that task.
Actual signed UI interaction and the remaining engine/return/full-scale/10-GiB/native/
physical gates remain unfinished; historical schemas/files/layout continuity stay out
of this release.

**DX-11 — Interactive performance and cache discipline.** Allowed:
DX-08/10 UI/model files, `Sources/PortraitStudioUI/{FlowDojoRenderer,FlowPresentationImageCache,FlowDojoPresentation,FramePresentationImageCache,PortraitPlanePreview}.swift`,
`Sources/PortraitLibrary/` query/cache implementations and targeted performance tests.
Remove decode/allocation from SwiftUI body (including `NSImage(data:)` in
`FlowDojoView`), avoid checkpoint revalidation/training-summary rebuild on every
`FlowDojoModel.refresh`, bound preview cache and key by exact revision/input/render
context. Add cancellation and generation guards against stale async selection.
Gate: budgets below, unchanged geometry/feedback hashes, decode/query instrumentation,
rapid navigation and close/reopen tests. Recovery: invalidate derived caches only;
never evict retained originals to achieve budgets.

**DX-12 — Local engine/document/job protocol, no device.** Allowed:
new exchange service/transport files in `Sources/PortraitCore/`, `Sources/PortraitLibrary/`,
`Sources/PlotterApp/` composition adapters and `Sources/PortraitStudio/` handoff;
protocol and separate-process harness tests. Implement Describe/Prepare/Submit/
Status/Cancel/ExportResult with typed capability/readiness reasons and durable
(client namespace, request ID) → request digest/job mapping. Accept only after
engine-owned authored closure is durable. Same ID/same request returns same job;
changed digest/options/plan/destination conflicts. Timeouts poll status. Use identical
in-process contracts and atomically published owner-written local transport files;
opening a document remains inert. Gate: separate-process disposable harness,
disconnect/relaunch at each boundary, no-device refusal, changed prepared-plan
return to preview and cancellation acknowledgement distinguished from settlement.
Recovery: reconciling jobs never issue another Start; failed return is publication
retry. This ticket cannot implement a replacement executor.

**DX-13 — Existing draft/run issuance seam, via named eligible episode package.**
Allowed only after the episode eligibility gate: the exact package-approved changes
to `Sources/PlotterEpisodeModel/{PlotterDrawingDraft,PlotterDrawingRun}.swift`,
`Sources/PlotterEpisodeRuntime/{PlotterDrawingDraftRuntime,PlotterDrawingRunRuntime}.swift`,
`Sources/PlotterRuntime/{DrawingRunIntent,DrawingRunEvidenceStore}.swift` and exact
corresponding tests/composition callers. Record package name/dependencies before
execution; if ineligible, report a bounded blocker and continue independent DX work.
Bind DrawingRef/digest, prepared plan and unique issuance to one RunID durably before
physical effects. Current `start` allocates fresh RunID and intent dedup is run-scoped;
prove reconciliation across that window instead of adding a second authority.
Gate: simulated crashes before/after acceptance, issuance, RunID binding, intent,
possible ink and run-link publication; repeated request never admits another run.
Existing Start/Stop/readiness/recovery behavior remains authoritative. Recovery:
uncertain issuance exposes reconciliation/possible ink, never automatic resubmission.

**DX-14 — Draft projection, parking and readiness presentation.** Allowed:
`Sources/PlotterApp/{DrawingStudioPresentation,DrawingStudioPreview,DrawingFrameInteraction,DrawingTransferView,PortraitDrawingActions,OperatorWorkspace}.swift`,
existing draft interfaces and matching draft/overlay/layout tests. Episode-owned
edits route through DX-13's package. Carry source-to-plan stroke mapping and border
roles, explicit material mapping, finite field-to-machine transform and intended
physical size. Preserve selected revision/placement across parked preparation;
readiness changes invalidate applicability without rewriting artwork. Show target,
placement, Draw border, calibration/sheet/readiness reasons and stale state. Sheet
confirmation must expose the correct outline independently of Video Settings
(`paperCoverageOutlineIsVisible`); overlay lifetime follows active/parked draft,
not random view lifetime. Gate: hide/reopen, stale plan, changed calibration/material,
new sheet, source-free and portrait selection, asynchronous completion and no-device
native regression. Only destination's explicit Plot submits the reviewed plan.
Recovery: invalidate/reprepare changed plans, retain parked authored selection.

**DX-15 — Raw attempt snapshots and offline mounting.** Allowed:
`Sources/PlotterRuntime/{DrawingRunIntent,DrawingRunEvidence,DrawingRunMedia,DrawingRunMediaCoverage,DrawingRunObservationPlan}.swift`,
`Sources/PortraitLibrary/DrawingTransfer.swift`, new snapshot adapters,
`Sources/PlotterApp/{DrawingRunEvidenceComposition,DrawingStudioPhysicalEvidence,DrawingStudioPhysicalGallery,DrawingReviewPresentation}.swift`
and evidence/publication tests; episode seams only through DX-13. Extend v1's
terminal/transferred-origin restriction through a new adapter: native/source-free,
refused-with-zero-attempt, staged/interrupted, failed/cancelled and sealed runs.
Publish monotonic meaningful-boundary cumulative snapshots with exact predecessor,
pre-motion drawing/job/plan bindings and all available original media; preserve
raw archive authority and `finishPortraitBinding` compatibility proof. Separate
planned, requested, controller-completed and ink-verified frontiers. Replace the fixed extreme carriage park in `DrawingRunObservationPlan` through the owning runtime workflow. Choose the shortest admitted pen-up move that clears the actual placed strokes plus measured carriage/camera clearance, including zero travel when the current pose already provides a clear view. Preserve the conservative park or report unavailable when geometry is unknown or no safe clear pose exists. Assert bounds, swept clearance, Stop and observation coverage for small centered, off-center, rotated and full-field fixtures. Require attended confirmation before claiming physical clearance.
Gate: sequence-N empty import, missing predecessor/media, duplicate/divergent
snapshots, sealed supplements, coverage/missing reasons, clock domains and imported
no-ink assertion cannot release local retry. Recovery preserves interrupted and
possible-ink history even when no portable result can yet be published.

**DX-16 — Task-specific evidence and training export.** Allowed:
DX-09 training/review files, `Sources/PortraitArtists/PortraitAttemptHistory.swift`,
exchange assessment/coverage/export adapters, offline reader and dataset tests.
Export exact authored/deployed/observation/interpretation closure and explicit loss
reasons; keep operator testimony, later analysis, synthetic media and artistic
preference distinct. Freeze task/version, input/label contracts, snapshot/assessment
digests, included-as-of, extractor/model revisions, exclusions and grouped splits.
Gate: independent empty-machine inspection and task eligibility for accepted,
rejected, refused, interrupted and missing observations; feature-only Rank cannot
claim geometry re-extraction or residual labels. No success-only filtering or
implicit negative label. Recovery: create a new immutable training manifest;
never mutate a checkpoint's prior dataset or activate physical correction.

**DX-17a/b — Historical archive import, deferred.** Neither authored-data conversion
nor run-history reconciliation is scheduled for the Drawing refactor. A future
importer needs its own scope and disposable inputs. Current-format ZIP/directory
exchange and reopening a library created by this version are supported release paths.

**DX-18 — Current-format apps and supported tools.** Package the actual standalone
and embedded routes with their existing bundle IDs. Exercise launch, current file
handling and explicit export/import between fresh libraries. A retired format
can be refused without modifying it. Keep the independent current-format reader,
SwiftSketch worker and converter usable. Test the current CLI, failed opens and
signed bundles. Add the separate-process job smoke when DX-12/15 are ready.

**DX-19 — Remove superseded callers during their cutover.** Delete replaced
writers, queries, format-only commands, UI entrypoints and their exclusive tests
in the same delivery that removes their use. Check live callers, build both
products and exercise the replacement interaction where one exists. Update the
operator instructions at the same time. The final audit checks the remaining
active routes for duplicate owners and old-format dependencies. Dated evidence
and historical user files can remain in their original format.

**DX-20 — Native regression and final scale/performance gate.** Allowed:
related native/app integration/performance tests and harnesses, targeted fixes only
within owning prior tickets, Current Evidence receipts. Exercise standalone and
embedded Studio, source-free import, photo stream, photo metadata, prepared inputs, Choose,
Refine, no-op/changed prune, undo, Rank commit/advance, Fit, exact Plot selection,
park/reopen/overlay/readiness, simulated cancellation/result return and offline
inspection. Include keyboard/focus, accessibility, window close/reopen and restarts;
source/test receipts alone do not prove native behavior. Run same-host cold/warm
A/B scale protocol below against DX-01 and contract budgets. Gate: native evidence,
all invariant budgets and supported regression suites pass; any material slowdown,
memory growth or missing stage gets an owned fix/retest, not a prose waiver.
Recovery: retain test library, exact app identity and logs for diagnosis; no reset
of the user's running app or physical archive.

**DX-21 — Independent final critique, owner fix and re-review.** Allowed:
read-only independent review of final diff, contract/DAG, native/performance receipts,
current-format fixtures, deleted callers and packaging; fixes only through a bounded
owner ticket in its permitted paths. Assign a non-author reviewer explicitly for
this gate (do not reuse an author's self-review). Cover correctness, data loss,
identity/capability confusion, UI regressions, current tool failures,
performance, new-library recovery and physical authority leaks. Findings name severity,
reproducer/evidence, owning ticket and required validation. Owner fixes each release
blocker; reviewer re-reviews the landed fix and rerun evidence, iterating until
closed. If capacity or evidence is unavailable, leave M5 blocked and identify the
missing review; do not call it accepted. Gate: independent critique record,
findings→owner→fix→re-review closure and no unresolved release blockers. This is
a requested independent-review work item, not authorization to delegate every task.

**DX-22 — Operator-controlled deployment and attended evaluation.** After
separate authorization for the specific action, verify the signed native handoff
and attend a source-free and photo-derived drawing through the existing runbook.
Check readiness, exact plan/run binding, returned observations and Drawing
identity. Record controller settlement and observed ink independently. Retain the
original archive, raw evidence and existing no-redraw recovery. Physical model
promotion needs its own holdouts and authorization.

### Quantitative scale and regression protocol

DX-01 freezes reproducible fixture seeds, host/OS/build/storage identity and exact
baseline commands. Use (a) a small interactive library, (b) at least 10,000 photos,
50,000 retained drawings, 100,000 jobs/attempt records and multiple snapshots per
run, with realistic shared parents/masks/feedback and equal-byte captures, and
(c) at least 10 GiB mixed original/prepared images and raw attempt frames. Include
one unusually large drawing and long interrupted history; document byte/stroke/frame
distributions rather than claiming row counts represent media cost. Use synthetic
fixtures in the current format. A disposable current-format archive can supplement
these measurements. Generate synthetic media locally for reproducible runs.

The contract's invariant budgets in [Drawing Exchange](DRAWING_EXCHANGE.md) apply:
metadata paging performs zero full artwork/media payload reads and zero renderer
jobs; indexed pagination is O(log n + k); ordinary rename/Rank does not reread or
rehash unrelated immutable assets; camera display frames perform zero library
queries; hashes/import/export stream files rather than materializing an archive.
Instrument assertions for these counts, not just elapsed-time tests. Measure
first-page/next-page, selection-to-preview, edit-to-durable-commit, Rank-to-next,
photo metadata, reopen, import/export, mount and current-library recovery separately.

For elapsed/RSS gates use at least 30 measured warm interactive operations after
warm-up and five cold launches per condition; report median/p95, peak RSS, allocation,
query and decode counts, bytes read/written and exact corpus. An ordinary metadata
operation must not regress p95 or peak RSS by more than 10% versus DX-01 on the
same host/corpus; a justified intentional tradeoff needs measured evidence and
explicit contract approval before acceptance. At 10× indexed catalog scale with
fixed page size, metadata p95 must remain within 2× and live page/cache memory
within 1.25×; preloaded fixtures/cache warming cannot hide full scans. For streaming
10 GiB export/import, doubling payload bytes must not double peak working memory;
measure throughput and all hashing passes, and require bounded-buffer behavior.
Large result throughput is reported against baseline and correctness;
it cannot silently weaken byte validation to meet time. Preserve device/camera
frame scheduling under UI/library work; benchmark acquisition-free and simulated
frame-fed modes separately. Re-run affected measurements after final fixes.

Every performance receipt states cold/warm conditions, repetitions and limitations.
Counterfactual SQL/query-count and allocation tests catch scaling regressions;
wall-clock noise alone does not establish improvement. If carrier crash handling
and independent-reader complexity materially favor a different carrier, stop that
choice for contract review while preserving the drawing/job/attempt identities.

## Portrait Studio: remaining acceptance

The shipped baseline is the Flow Edge Dojo: one portfolio curation, ranking,
pruning and fitting loop shared by standalone and embedded Studio. Its current
operator/model contract is in [Portrait Studio](PORTRAIT_STUDIO.md), its authority
boundaries in [Product Contract](PRODUCT_CONTRACT.md), and software receipts in
[Current Evidence](CURRENT_EVIDENCE.md). Earlier multi-artist, SwiftSketch and
preprocessing pilot plans are superseded as product direction; their retained
artifacts and dated evidence remain historical.

The revision-527 artist audit found 50 new rounds and 358 drawings on one new
photo, 99 weaker choice comparisons, one current completed target (78 removals,
228 retained lines), no explicit rankings and no fitted checkpoint. Six source-hash
groups are not six independently identified people. Photo-centered coverage and
feedback queries therefore prioritize additional source groups over more unlabelled
alternatives on the same photo.
A subsequent fit on an exact copy proposed zero of that target's 78 intended
removals at the deployed policy, matching keep-all in sample. A converged reference
at the same regularization leaves that result unchanged. The remove-only holdout
cannot establish false-deletion cost, so completed targets and explicit comparisons
across additional photos remain the next evidence requirement rather than automatic
threshold tuning.

Remaining acceptance and conditional improvement work:

- Collect the artist's explicit within-round, cross-round, pruned-revision and
  cross-photo rankings, along with remove/restore corrections and completed masks.
  Measure preference and correction burden on excluded photo groups. A synthetic
  fitting/deployment loop establishes mechanics, not learned human taste.
- Compare the deployed two-component artist against untrained Flow Edge sampling
  and keep-all deletion on the same held-out inputs. Preserve exact proposal
  identities, model versions, thresholds and source/group declarations. A small
  personal archive does not establish new-subject generalization.
- Measure native broad-round and refinement latency, cancellation, warm source
  reuse, reopening larger portfolios and edit-to-durable-commit latency. Test
  rollover of the local fitting capacity against realistic curated portfolios;
  do not silently trim observations or rewrite committed history.
- Evaluate whether the native parameter range produces enough useful variation
  across organic, straight-tonal, angular, wavy and closed-mark constructions. Diverse parameter
  vectors alone do not prove visible diversity or artistic value. Preserve failed
  and duplicate attempts when measuring usable results.
- Expand feature/model capacity only if retained failures show a limitation of the
  current regularized preference and deletion models. Freeze new feature/model
  revisions and compare on held-out groups before activation. Flow Edge plus exact
  line selection remains the declared drawing representation; new generators,
  line-addition tools or alternate authoring workflows are not implied.
- Validate exported drawings through the existing attended Drawing flow when
  separately authorized, recording actual pen separation and ink quality. Model
  fitting, UI screenshots and controller settlement cannot establish physical art.

These are acceptance gaps, not a second implementation sequence. The current
portfolio format and model lifecycle remain owned by their canonical guide and
contract; future changes must update those owners rather than add competing plans.

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
