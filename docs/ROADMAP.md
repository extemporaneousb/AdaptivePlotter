# AdaptivePlotter Roadmap

Status: unfinished work only; never completion evidence

Current implementation and verification are recorded in
[Current Evidence](CURRENT_EVIDENCE.md). Product authority is
[Product Contract](PRODUCT_CONTRACT.md). The architecture migration and its
dependencies are owned exclusively by
[Episode Architecture Execution Plan](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md);
this roadmap does not restate or reorder them.

## Drawing Exchange

Status: DX-01 through DX-03 are adopted; the dated
[DX-03 receipt](CURRENT_EVIDENCE.md#drawing-exchange-dx-03-closed-carrier-receipt-2026-11-07)
records canonical adoption and its configured gate. DX-04's implemented storage
foundation and measured software evidence are retained in its
[dated receipt](CURRENT_EVIDENCE.md#drawing-exchange-dx-04-single-writer-catalog-receipt-2026-11-07);
its two configured gates failed; subsequent reader and composition-owner
corrections, focused checks and source-specific measurements are recorded there.
The third configured gate and adoption remain pending. DX-05 still requires
adopted DX-03 and completed DX-04. This status does not select work; no unfinished
ticket below is implementation or acceptance evidence.
The accepted target is [Drawing Exchange](DRAWING_EXCHANGE.md). The Flow Edge Dojo
section below describes the shipped baseline and outstanding model evaluation;
it does not authorize a competing portfolio, retention or storage authority.
This campaign replaces its relevant internals with the shared library/authoring
contract while preserving useful renderer, editing and learning capabilities.

### Delivery rules and ownership

Execute one ticket at a time through the normal Blackdog task workflow. Each
DX ID is stable; completed tickets move to dated Current Evidence receipts rather
than becoming completion claims here. A ticket may be split into suffixed IDs
without weakening its parent acceptance. Record exact changed symbols, deleted
callers, validation commands, fixture identities and remaining blockers in each
receipt. `docs/DRAWING_EXCHANGE.md` is the contract; this section is the execution
DAG. A contract conflict blocks the affected ticket for explicit resolution.

Every ticket permits changes only to its listed paths, directly corresponding
tests, and the canonical documentation needed to describe that change. A directory
scope permits new files for that responsibility, not unrelated cleanup. Before
editing, resolve the named symbols against the current tree and record callers;
a renamed/deleted symbol requires a current replacement proof. Software tickets use local Git and disposable stores. Stage and inspect the signed artifact before a restart after a fix, as authorized by the operator. Reserve physical operation, destructive cleanup and production data promotion for their specific operator handoff. Use disposable library/archive copies and
simulated devices. Keep machine execution, calibration, paper, Stop, possible-ink,
retry admission and raw evidence with their existing owners.

An authoring/exchange adapter can consume an existing episode interface. Changes
to episode-owned runtime seams require a *named eligible package* selected under
[episode workflow](../.codex/guidance/adaptiveplotter-workflow.md) and the existing
[execution plan](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md); do not invent eligibility
or reorder that ledger. DX-13 records the specific package or a blocker after
inspection. Unrelated document/library/UI/tool tickets proceed independently.
No new episode runtime, planner, physical archive or competing library writer is
permitted. Refusal/cancellation is a durable outcome, not permission to retry.

### Replacement inventory at 6305c05

Use this map as the starting worklist. DX-01 reconciles it against current callers, including fixtures, command-line launch variants and conditional compilation. A read-compatible decoder or raw evidence owner may be required even after its UI writer disappears.

| Area and tickets | Baseline callers and disposition |
|---|---|
| Object and edit operations (02–03, 05, 08) | `PlotterModel/{CanonicalEncoding,DrawingProgram,DrawingPlacement,DrawingExecutionPlan,DrawingOriginReference}.swift` retain existing hash and planning semantics. Adapt `PortraitCore/{DrawingPackage,PlotAttachment,DrawingStrokeSelection}.swift`, `PortraitArtists/{PortraitCandidate,PortraitAttemptHistory,PortraitDrawing}.swift` and `PortraitLibrary/SavedDrawing.swift` at their producer/import edges. Move shared draw/summary/edit operations and reference/asset verification into the common value or codec. Prove the same revision survives title changes, handoffs and child edits. |
| Producer and dependency cutover (02, 07–08, 19) | Update `Package.swift` and both executable compositions. Split the camera materialization adapter out of `PortraitPhotoCapture.swift`. Keep `PortraitSourcePreparation`, `PortraitImageAnalyzer`, `PortraitFlowRenderer`, `FlowDojoRenderer` and typed recipes/analysis in the producer. Move library-to-artist semantic validation and library-to-runtime reconciliation to integration adapters with injected typed callbacks. Prove the common object/catalog targets compile without Artists or device runtime. Use the existing source-free catalog plus Flow Edge to exercise both producer paths. |
| Storage, old identity and selective cleanup (04–07, 17, 19) | Cover **all** files in `Sources/PortraitLibrary/`. Retire Flow portfolio live writes only after replacing capture, rounds/choice/refinement, pruning, ranking, fitting/activation and restart recovery. Keep immutable old delta/head readers for import, conflict/tombstone proof and source evidence. Include `PortraitPhotoPage`, `PortraitParameterPreferenceArchive`, `PortraitEvidenceSource`, legacy snapshot/reconciliation and review jobs/exports in migration. Dry run separately reports explicit retention, protected physical history, provably generated-only and unresolved legacy candidates. Remove generated-only entries from active storage using reversible compaction. Quarantine uncertain originals; never convert a missing old intent log into proof of nonselection. |
| Browser and workbench routing (08, 10–11, 18–20) | Reachable root `PlotterApplicationRuntimeView`, `WorkbenchTopBar`, `WorkbenchLayout`, `WorkbenchPanels`, `DrawingReviewerView` in `DrawingStudioPhysicalGallery.swift`, `DrawingTransferView`, standalone `PortraitStudioApp` and embedded `PortraitStudioView`. Present Library, Drawing Studio and Plotter as workspace destinations. Move Motion/Video under Plotter and import/export to Library actions. Replace both independent browser selections with exact refs. Keep native session/Stop controls accessible. Preserve layout migration, deep links, focus, old bundle identity/associations and chronological recent-photo access even when starting in Studio. |
| Authoring and feedback (07–11, 16) | `FlowDojo{Model,View,Sidebar,CameraPanel,Files,Presentation,Training,TrainingProgress,TrainingFeedback}`, `PortraitLine{EditModel,Editor,EditorCanvas,SelectionGeometry}`. Keep real renderer controls, reversible edits and worker cancellation. Replace `FlowPortfolioStore.completeCandidate` durable generation and `PortraitSketchCollection` legacy rate→retain. Replace Curate's button with contextual photo fields; preserve subject/session/exclusion meaning. Move rank comparison to the next set after a committed preference. Keep active checkpoint selection, human/computed mask distinction and held-out groups. |
| Physical selection, observation and return (12–16) | `PortraitDrawingActions`, `OperatorWorkspace`, `DrawingRunEvidenceComposition`, `PaperCoverageComposition`, `DrawingRunMedia{,Coverage,Validation}`, `DrawingRunProgressFrame`, `DrawingRunObservationPlan`, `DrawingRetrospectiveResidualAnalysis`. A source ref bound before motion is the join key. Retain current camera, interpreter, controller, Stop, no-redraw and raw evidence owners. Passive preview and causal trial simulation have different evidence classes. Exercise the ordinary-run admission with fake ports in tests; do not turn simulated preview into a physical attempt. |
| Dormant implementations and external tools (16–19) | `PortraitStudio{RootView,Composition,ArtistView,ReviewView,LibraryView}`, their model/launch/file/artist-input helpers and tests require separate caller proof. The standalone entrypoint still references a composition constant. Preserve SwiftSketch protocol/client/converter, model pins and archived experiments where required for interpretation. Cover `Tools/SwiftSketch/{README.md,face_pilot.py,worker.py,prepare.py,prove.py,pilot.py,acquire.py,run_bounded.py}`, `Tools/portrait-library-reconcile`, both Info.plists, Makefile, bundle launch/build/sign/validate scripts, native report/performance gate, repository checker and tests. Change CLI examples and regression filters alongside the caller they exercise. |
| Evidence and documentation (every cutover, 19–21) | `README.md`, `docs/{INDEX,PRODUCT_CONTRACT,PORTRAIT_STUDIO,SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE,ROADMAP,CURRENT_EVIDENCE}.md`, operator guides and tool READMEs. Add a dependency/forbidden-call check scoped to reachable production targets, allowlist legacy readers by path/purpose, and update executable-path/name checks. Keep historical receipts dated. For every deleted old route require a replacement interaction test and a source search for remaining callers. |

### DAG and delivery milestones

| Milestone | Tickets and prerequisites | Reviewable delivery boundary |
|---|---|---|
| M0: baseline and frozen contracts | DX-01 → DX-02 | Inventory, reference vectors, budgets and ownership; no user behavior change |
| M1: inert interoperable library | DX-03 ← 02; DX-04 ← 02; DX-05 ← 03,04; DX-06 ← 05 | Independent offline reader; immutable import/export; crash-safe copied library |
| M2: authoring and browsing cutover | DX-07 ← 05; DX-08 ← 06,07; DX-09 ← 07; DX-10 ← 08,09; DX-11 ← 08,10 | Photos/Drawings, photo metadata, intentional retention and feedback work without hardware |
| M3: printer boundary and returned evidence | DX-12 ← 02,06; DX-13 ← 01,12; DX-14 ← 06,12,13; DX-15 ← 14; DX-16 ← 09,15 | Separate-process simulated recovery and offline results; physical seam blockers explicit |
| M4: migration and distribution | DX-17a ← 06,07,11; DX-17b ← 17a,15; DX-18 ← 10,11,12,15; DX-19 ← 11,16,17b,18 | Copied archive rehearsal, signed native apps, obsolete reachable writers removed |
| M5: software release gate | DX-20 ← 19; DX-21 ← 20 | Native regression, performance and independent critique closed with re-review |
| M6: separately authorized deployment | DX-22 ← 21 | Operator-approved production migration and attended ink evaluation; separate receipts |

DX-13's runtime prerequisites may hold M3 onward; they must not hold M1/M2 or
DX-17's authored-data rehearsal. Partial deliveries identify which operations
remain unavailable. A signed app with simulated results is software evidence.
M5 does not imply M6 or physical readiness.

### Ticket acceptance contracts

DX-01's baseline, adopted DX-02/DX-03 contracts and DX-04's implemented
single-writer storage scope are retained in their dated
[Current Evidence receipts](CURRENT_EVIDENCE.md#drawing-exchange-dx-04-single-writer-catalog-receipt-2026-11-07).
Those receipts retain accepted scope/gate/recovery constraints and distinguish
source observations from authoritative validation/adoption. The contracts below
remain unfinished; the existing dependency DAG is unchanged.

**DX-05 — Introduce common Library API and retire shadow identity paths.** Allowed:
`Sources/PortraitLibrary/{SavedDrawing,PortraitLibraryQueries,PortraitSketchCollection,PortraitCandidateStore,DrawingTransfer}.swift`,
associated browse/lineage/store tests, `Package.swift`, and all of
`Sources/PortraitLibrary/` specifically for moving producer/runtime imports
and legacy adapter responsibilities out of the common catalog. This permits
mechanical moves and caller updates for old reconciliation, review, training
and checkpoint paths without preempting their later behavior cutovers. Include producer validators in
`Sources/PortraitArtists/` and integration adapters in the two executable
compositions and Studio UI. Move runtime evidence reconciliation and producer-specific
decode/validation out of the core catalog. Prove the common value and catalog can
build without depending on PortraitArtists or PlotterRuntime (inspect the real
package graph and imports; compile a client using a source-free drawing). Route
source-free, portrait and imported revisions through one exact-reference API;
retain frozen producer records and parent/input closure. Replace ambiguous
`loadDrawing(String)` and candidate-only caches at reachable callers; legacy
aliases require proven occurrence identity. Make generic drawings visible without
inventing photos. Gate: same candidate ID in two photos/issuers, identical geometry
in separate selections, renamed title, forked archive and stale cache tests.
Delete superseded live query/write paths in the same cutover; retain needed v1
read adapters. Recovery: copied-library rollback preserves original bytes/aliases.

**DX-06 — Atomic import/export/mount API.** Allowed:
`Sources/PortraitLibrary/DrawingTransfer.swift`, new exchange library adapter files,
`Sources/PortraitCore/PlotAttachment.swift` read compatibility, transfer/library
and admission tests. Publish verified immutable objects before one visible catalog
transaction; export snapshot scope with exact bytes and required parent/input/source
closure. Result-on-empty-library and sequence-N import must include 1…N and all
required assets. Deduplicate identical delivery and reject divergent sequence or
predecessor/job/drawing chains. Gate: interrupted staging, duplicate redelivery,
conflict quarantine, missing media, unsupported profile and offline re-export tests.
No mount changes live retry/no-ink authority. Recovery is retryable publication,
never another physical submission.

**DX-07 — Canonical photos, prepared inputs and retention reasons.** Allowed:
`Sources/PortraitLibrary/{FlowPortfolioPhotoCollection,FlowPortfolioStore,FlowPortfolioStorage,FlowPortfolioDelta,FlowPortfolioValidation,FlowPortfolioTypes,PortraitPhotoPage}.swift`,
`Sources/PortraitArtists/PortraitSourcePreparation.swift`, image/retention tests and
Library API files from DX-04/05. Preserve original acquisition occurrences, source
dates with provenance, exact raster/mask bytes and ordered transforms on each retained
branch; identity preparation can alias identical original bytes. Persist explicit
Choose/Refine/prune/Plot/explicit-save retention reasons and tombstones. Rank feedback writes its own record. Generate,
browse, editor-open and Rank alone must not retain sibling geometry. Define
deletion/GC reachability proofs across retained parents, jobs, attempts, assessments,
metadata and historical aliases; hide/tombstone precedes separately deliberate
asset deletion. Gate: equal-byte captures, unknown dates, shared objects, clear and
reapply retention, crash during commit and missing-mask corruption fixtures.
Recovery: retain sources and quarantine ambiguity; no production cleanup.

**DX-08 — Authoring selection, pruning and Plot handoff.** Allowed:
`Sources/PortraitStudioUI/{FlowDojoModel,FlowDojoFiles,PortraitLineEditModel,PortraitLineEditor,PortraitStudioModel}.swift`,
`Sources/PortraitStudio/{PortraitStudioComposition,PortraitStudioFiles,PortraitStudioLibraryModel}.swift`,
`Sources/PlotterApp/PortraitDrawingActions.swift` adapter calls only, selection/edit
and handoff tests. Pin selected revision once on commit, preserve stable stroke IDs,
make pruning a child with exact parent; explicit unchanged completion labels/retains
the base without a synthetic child. Undo/redo stays reversible before commit.
Plot… retains only the selected path and opens Prepare; changing a title or medium
cannot mutate frozen drawing/style. Gate: crash/reopen, wrong-selection, undo,
cancelled handoff and identical geometry occurrence tests; no implicit Submit.
Remove package encode/decode internal round trips replaced by Library API.
Recovery: unsent drafts remain local; committed revisions are immutable.

**DX-09 — Feature-only Rank capsule and explicit training membership.** Allowed:
`Sources/PortraitLibrary/{FlowPortfolioStore,FlowPortfolioTypes,FlowPortfolioDelta,PortraitReviewStore,PortraitReviewCommit,PortraitReviewExport,PortraitCheckpointStore}.swift`,
`Sources/PortraitArtists/{FlowArtistTraining,PortraitTrainingContract,PortraitAttemptHistory,PortraitTrainingValidation}.swift`,
`Sources/PortraitStudioUI/{FlowDojoTraining,FlowDojoTrainingFeedback,FlowDojoModel}.swift`
and ranking/training tests. Freeze ordered presentation IDs, features, producer and
extractor versions, question, tie/skip/rank response and geometry-omitted status.
Advance only after durable feedback commit. Curate grouping/exclusion is attributed
metadata, not changed photo identity or silent negative label. Freeze task manifests,
selected input/label/snapshot digests, exclusions, grouping/splits and checkpoint
revision; no discarded geometry dependency. Gate: failure before commit, ties/skips,
legacy review compatibility, unavailable weights, frozen-membership reload and
source/session leakage fixtures. Recovery retains earlier feedback and names
superseding assessments; aesthetic activation affects future authoring only.

**DX-10 — Photos/Drawings browser and Curate cutover.** Allowed:
`Sources/PortraitStudioUI/{PortraitLibraryBrowsePresentation,PortraitRecentItemsView,PortraitSavedStylesView,FlowDojoSidebar,FlowDojoView,FlowDojoPresentation}.swift`,
`Sources/PortraitStudio/{PortraitStudioLibraryView,PortraitStudioRootView,PortraitStudioGroupDeclarationView}.swift`,
Library query files, `Sources/PlotterApp/{PlotterApplicationRuntimeView,WorkbenchTopBar,WorkbenchLayout,WorkbenchPanels,DrawingStudioPhysicalGallery,DrawingTransferView}.swift`
and browser/navigation tests. Cut over the actual top row to the three workspaces.
Exercise restored layouts, embedded and standalone entrypoints, keyboard focus,
picker/Exchange actions and persistent global Stop in native navigation. Provide chronological Photos,
retained Drawings including source-free/imported work, prepared-input/branch navigation
and Attempts. Show acquisition/import/unknown date truthfully; separate retained
drawing, attempted run and attributable-evidence counts (snapshots do not inflate
attempts). Remove the Curate button. Expose grouping/exclusion metadata on the selected photo.
Use typed selection across app modes/relaunch; no hidden current-portfolio authority.
Gate: empty and large catalogs, generic drawings, same-date ordering/pagination,
tombstones, interrupted/failed attempts, unknown dates, keyboard/accessibility and
wrong-selection regressions. Delete replaced reachable duplicate browser/query paths;
source-only historical screens require caller proof before deletion. Recovery:
retain catalog backup and preserve selection aliases rather than fuzzy reattachment.

**DX-11 — Interactive performance and cache discipline.** Allowed:
DX-08/10 UI/model files, `Sources/PortraitStudioUI/{FlowDojoRenderer,FramePresentationImageCache,PortraitPlanePreview}.swift`,
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

**DX-17 — Proven-identity migration and copied-archive rehearsal.** DX-17a inventories and rehearses authored storage. DX-17b verifies run/evidence attachment and dependent rollback once DX-15 lands. Allowed:
`Sources/PortraitLibrary/{PortraitLegacySnapshot,PortraitLibraryReconciler,PortraitLibraryReconciliation,FlowPortfolioLegacyImport,FlowPortfolioStorage,FlowPortfolioPhotoCollection,PortraitReviewStore,PortraitReviewCommit,PortraitReviewExport,PortraitCheckpointStore}.swift`,
`Tools/portrait-library-reconcile`, migration tests and explicit migration docs.
Inventory v1 packages, legacy index/SQLite rows, generic drawings, portfolio
occurrences, root/parent aliases, masks, feedback, checkpoints, run bindings,
tombstones and source dates. Translate only with exact identity evidence;
equal hashes alone do not prove occurrence. Preserve original package/media bytes;
unproven lineage/binding goes to inspectable quarantine with a reason, never fuzzy
mounting. Rehearse a fresh target on disposable copies with external backup,
byte/ID/count/date/lineage/possible-ink comparison manifest and deterministic restart.
Gate: independently checked before/after manifest, interrupted migration, missing
assets, old namespace forks, competing writers, backup restore and rollback launch.
No deletion of old archives or production migration. Authored-data rehearsal can
proceed before blocked physical adapters; label excluded run evidence explicitly.

**DX-18 — Supported tools, app launch and distribution.** Allowed:
`Package.swift`, `Resources/{AdaptivePlotter-Info,PortraitStudio-Info}.plist`,
`Scripts/{build_local_app,build_portrait_studio_app,validate_local_app_bundle,validate_portrait_studio_app_bundle}.sh`,
launch/inspect/launcher scripts when directly affected, `Tools/SwiftSketch/`,
`Tools/portrait-library-reconcile`, app launch option/composition files, related
script/CLI tests and their docs. Trace actual products, flags and open-document
handlers before retaining or removing surfaces. Keep supported CLI/SwiftSketch
conversion and inspection usable through the same contract; review `face_pilot.py`,
worker/prove/pilot/run_bounded/prepare/acquire readers and independent fixtures.
Historical pilots/fixtures are labelled historical, not silently promoted or
indiscriminately deleted. Specify bundle IDs, UTIs/extensions, upgrade associations,
old filenames and v1 open compatibility; preserve provenance's retained node names
where required. Gate: clean supported CLI smoke, invalid argument/error paths,
Python reader against shipped exports, signed-bundle validation, upgrade/open
fixture, singleton ownership and separate-process no-hardware flow. Never replace
the operator's running artifact. Recovery: old app/library backup opens retained
v1 bytes; package handler mismatch is a visible refusal.

**DX-19 — Delete superseded reachable authorities and synchronize docs.** Allowed:
only obsolete code/callers established in DX-01 and removed by DX-05…18,
`README.md`, `docs/{INDEX,PRODUCT_CONTRACT,PORTRAIT_STUDIO,CURRENT_EVIDENCE,DRAWING_EXCHANGE,ROADMAP}.md`,
other affected routed/runbook/tool docs and direct tests. Produce a deletion receipt
for each replaced writer/query, JSON/DB mirror, portfolio/package round trip,
legacy fallback, source-only view or obsolete UI/CLI surface: prior caller chain,
replacement owner, removed symbols/files, retained read compatibility and negative
reachability proof (`rg`, product dependency/build and runtime route evidence).
Keep historical evidence/fixtures and supported v1 readers where still required;
no implementation deletion merely because an old name appears. Reconcile source
photo, retention, mask, ranking, Curate, training, browser counts, draft and packaging
contracts with the target; remove contradictory current instructions and link dated
history. Gate: supported products compile, narrow tests, `make docs-check`,
`git diff --check`; no competing active writer or orphan reachable route. Recovery:
revert code cutover on disposable data, preserve migrated data and original archive.

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
fixtures, migration/deletion proofs and packaging; fixes only through a new bounded
owner ticket in its permitted paths. Assign a non-author reviewer explicitly for
this gate (do not reuse an author's self-review). Cover correctness, data loss,
identity/capability confusion, UI regressions, unsupported legacy/tool casualties,
performance, migration rollback and physical authority leaks. Findings name severity,
reproducer/evidence, owning ticket and required validation. Owner fixes each release
blocker; reviewer re-reviews the landed fix and rerun evidence, iterating until
closed. If capacity or evidence is unavailable, leave M5 blocked and identify the
missing review; do not call it accepted. Gate: independent critique record,
findings→owner→fix→re-review closure and no unresolved release blockers. This is
a requested independent-review work item, not authorization to delegate every task.

**DX-22 — Operator-controlled production rollout and attended evaluation.** Allowed
only after separate explicit authorization for the exact action: backed-up production
migration using DX-17's verified tool; signed-app native handoff with operator;
attended plotting through existing machine owners/runbook. Do not bundle migration,
hardware motion and model promotion into one approval. Inspect current artifact/PID,
writer ownership, device/readiness and possible-ink state before action. Verify a
source-free and photo-derived drawing's exact intended plan, actual run binding,
returned observations and immutable library identity; compare paper/pen results with
software expectations. Record controller settlement separately from observed ink.
Gate: production migration receipt, native interoperability receipt and attended ink
receipt are separate; physical model promotion requires its own predeclared holdouts
and explicit acceptance. Failure retains source backups and raw evidence, quarantines
uncertain bindings and uses existing no-redraw recovery. No automatic retry, source
cleanup or physical promotion follows software success.

### Quantitative scale and regression protocol

DX-01 freezes reproducible fixture seeds, host/OS/build/storage identity and exact
baseline commands. Use (a) a small interactive library, (b) at least 10,000 photos,
50,000 retained drawings, 100,000 jobs/attempt records and multiple snapshots per
run, with realistic shared parents/masks/feedback and equal-byte captures, and
(c) at least 10 GiB mixed original/prepared images and raw attempt frames. Include
one unusually large drawing and long interrupted history; document byte/stroke/frame
distributions rather than claiming row counts represent media cost. Use synthetic
fixtures plus an opt-in disposable copy of a representative real archive; no real
archive mutation or benchmark dependence on network/model downloads.

The contract's invariant budgets in [Drawing Exchange](DRAWING_EXCHANGE.md) apply:
metadata paging performs zero full artwork/media payload reads and zero renderer
jobs; indexed pagination is O(log n + k); ordinary rename/Rank does not reread or
rehash unrelated immutable assets; camera display frames perform zero library
queries; hashes/import/export stream files rather than materializing an archive.
Instrument assertions for these counts, not just elapsed-time tests. Measure
first-page/next-page, selection-to-preview, edit-to-durable-commit, Rank-to-next,
photo metadata, reopen, import/export, mount, migration and recovery separately.

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
Large result/migration throughput is reported against baseline and correctness;
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
