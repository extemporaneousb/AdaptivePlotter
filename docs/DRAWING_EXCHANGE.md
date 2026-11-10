# Drawing Exchange

**ADR DX-0001 · Accepted 2026-11-06 · Wire profile 1.** This is the normative target for Studio/Library/Plotter interoperability. The reviewed source baseline is `6305c0503ae3cae7130bd38d0e2def309a927e88`. Adoption progress belongs to the [Drawing Exchange backlog](ROADMAP.md#drawing-exchange). The [Studio guide](PORTRAIT_STUDIO.md) describes the currently shipped UI and current-format exchange.

Change control: preserve issued revision bytes, job identities and historical evidence. The 2026-11-07 operator-directed Drawing-first cutover supersedes the requirement to keep legacy v1–4 authoring readers, writers and fallbacks active. The release target set on November 8 uses fresh libraries. Importing historical portfolios, upgrading their storage and restoring retired file handlers are deferred. Historical files stay untouched. Current-format library reopen, exchange integrity and exact job/attempt identities remain release requirements. Breaking changes to a required wire meaning need a successor ADR, a new profile and a lossless compatibility strategy. Compatible optional fields require a fixture that round-trips through an older preserving reader. Implementation improvements inside these boundaries use ordinary review. The [wire schema](../Resources/DrawingExchange/v1/schema.json) specifies structural admission. This document specifies semantic admission. A decoder must satisfy both before claiming support for an operation.

## Decision

Use one immutable authored **Drawing revision**, one separately issued **plot job**, and zero or one physical **Attempt** per job. A drawing can have any number of jobs and attempts. The plotter returns immutable snapshots of an attempt. The library mounts them under the exact drawing revision. A user opening that drawing sees its history, while its original bytes and identity stay stable.

Use a directory for local storage, versioned UTF-8 JSON for typed records, ordinary binary files for media, and SHA-256 for file integrity. Use a closed **BagIt 1.0** directory profile for exchange, optionally wrapped in ZIP for a single-file handoff. Use SQLite for local browsing and transactional metadata. The two applications communicate through document, job and result contracts, without sharing mutable database tables. A local transport can deliver identical requests in process or across two app processes.

## Data contracts

| Record | Immutable content and identity | Who can publish it |
|---|---|---|
| Photo | Namespaced acquisition ID, original asset digest, media type and dimensions, acquired/imported times with their provenance, available capture/session facts. Two captures with equal bytes remain separate. | Capture/import owner |
| Image input | Exact photo reference, declared pixel coordinate basis, orientation, crop/rotate/scale/mask, preparation implementation revision and exact resulting raster. Identity preparation is valid. Retain the exact consumed raster and mask bytes on every retained image branch. Identity preparation can reference the original bytes when these are identical. | Studio preparation |
| Drawing | Namespaced revision UUID, format/profile, exact authored representation, optional image-input reference, optional exact parent revision, creation time, producer revision and frozen authoring/edit record. The first profile carries the existing DrawingProgram. Preserve the frozen producer record. Recognized producers verify their typed claims. Unsupported producer claims are displayed as unverified. | Authoring capability through the Library |
| Job | Client request ID, destination engine identity, drawing reference and digest, requested medium/options. Engine returns its durable job ID, current state/reason and optional attempt reference. Refusal before staging a physical attempt has zero attempts. | Client identifies request. Plotter owns accepted jobs |
| Projection | Selected drawing plus placement and frozen context yields the target preview and a specific execution plan revision. Bind the source-to-plan stroke correspondence, including added border strokes; never train the artist on the border as authored ink. | Existing plotter draft/planner |
| Attempt snapshot | Producer archive ID, run ID, snapshot sequence, predecessor digest, exact pre-motion drawing binding, job/request, applicable intent/plan and observations as of a stated point. Cumulative snapshots preserve earlier dispatch/frontier facts. Sealed indicates the producer has closed the run history, independent of success, failure or cancellation. A pending cancellation can still be moving. A terminal run, including failure, remains addressable. An interrupted run can yield a provisional snapshot. | Plotter publishes from its raw run/evidence owner |
| Assessment or feedback | Target digest(s), human/algorithm identity and version, time, question, typed answer, relevant region/stroke and supporting assets. Corrections can supersede earlier assertions. | Named reviewer or analysis tool |

On the wire a drawing reference is always `{issuer, revision, digest}`. The first two fields are its lookup key. The digest pins the exact frozen UTF-8 record bytes and is supplied by referring records, outside the record itself. Assign the reference once when committing the selected revision. Identical geometry may legitimately occur in two separate selections. `DrawingProgram.contentHash` keeps its current canonical algorithm and semantics. File digest, program digest, drawing occurrence, job identity and attempt identity answer different questions. Changing a title changes catalog metadata; pruning strokes creates a child drawing revision. A physical medium substitution changes the job/plan, with an explicit mapping to the authored style. It cannot silently rewrite `penProfileID` in an existing drawing.

One required representation per revision. The initial identifier is `adaptiveplotter.stroke-program/1`. It carries the existing field extent, ordered strokes with stable IDs, style, field-space points, semantic role, provenance and verified program hash. Authored coordinates are finite binary64 field units in a closed rectangle from (0,0) at the lower left to (width,height) at the upper right, with X right and Y up. Field units have no intrinsic millimeter scale. Nominal pen width in millimeters is optional for retained and newly authored drawings. When declared it must be positive and finite; when unavailable it remains explicitly unknown. No authoring, selection, import or plot handoff may add a mandatory width field, declaration, setup step or deferred data-entry obligation. Preserve any producer-declared intended physical field size separately from the abstract field extent. Carry a historical unit only when supported by the producer receipt; a nominal width is distinct from a measured deposited width. An image crop is defined in oriented source pixels, origin top left, X right, Y down. Pixel edges use integer coordinates with centers offset by 0.5. Record the ordered source-to-input transform then the input-to-field transform explicitly. Placement maps field to machine coordinates using the existing anchored transform with scale, rotation and calibrated correction, in the order defined by `DrawingPlacement`; store the resulting mapping and its millimeter/controller calibration. Unknown units remain unknown for both fresh and historical artifacts; absence does not assert a historical origin. A declared nominal authoring width is distinct from measured physical pen width; future calibration is optional and is not required by this cutover. No conversion changes legacy program bytes. A pen plotter advertises support for this representation and its material capabilities. A future watercolor device could accept the same intent with its own supported material mapping. An extrusion process needing volume or deposition semantics would introduce a separately specified representation. An older tool can preserve an unfamiliar drawing and report which capability it lacks. It cannot silently flatten an unknown representation into pen strokes.

A valid package can be preserved and re-exported even when the consumer lacks the producer. Evaluate three independent states: **integrity** (bytes, closure, supported schema), **capabilities** (view/plot/edit/regenerate/train), and **current device readiness**. Known stroke geometry with an unfamiliar producer remains eligible for preview and plot when all execution-relevant claims are supported. Preserve verified unknown optional fields and their original bytes. Unknown required features and unknown enum values block only the operations that need their semantics. Unknown major schemas permit opaque preservation, not rewriting. An invalid claim from a known producer is a validation failure.

Readers accept omission of `requiredFeatures` on ExchangeIndex as empty to preserve the frozen fixture. Writers emit the array on new records. The common envelope uses `requiredFeatures` (an array of stable namespaced feature IDs, empty when none). On the wire Photo, ImageInput, Drawing and Assessment references share `{issuer,revision,digest}`. A Job handle is `{engine,job}`; the attempt additionally pins the immutable submission receipt digest. An Attempt snapshot reference is `{archive,run,sequence,digest}`. Use lowercase UUIDs and 64 lowercase hex digits for SHA-256. An issuer identifies a producing namespace. Machine/device identity, engine build, checkpoint identity and attributed human are separate fields. A read-only archive copy retains its identity; a diverging writable fork gets a new archive namespace for new records. A copied namespace or checksum supplies no authentication.

A source or parent declaration is one of `{"state":"none"}`, `{"state":"present","ref":…}`, or `{"state":"unavailable","reason":…,"knownRef":…}` (knownRef optional). “None” is an affirmative declaration. Migrated evidence with an unresolved drawing binding can be inspected separately but must never be mounted by fuzzy matching. Omitted or unknown optional facts do not become negative observations.

## Swift API and dependency direction

The following signatures specify responsibility and cost. They are Swift interface sketches for implementation, not already-shipped declarations. Keep the package internal until there is a real external Swift client. The wire spec is independently consumable.

| Existing owner | Adopted boundary | Remove after callers move |
|---|---|---|
| `PlotterModel.DrawingProgram`, geometry, canonical encoder, placement and planner | Reuse the original program instance, stable stroke IDs and verified content hash. Compute field bounds and stroke summary once per materialized revision where consumers repeatedly need them. | Per-view geometry hashing, ID reconstruction and duplicate bounds walkers with the same semantics. Keep camera/machine-space bounds separate. |
| Existing `PortraitCore` authoring/exchange contracts | House a producer-independent Drawing value, typed refs, asset descriptors, v1 record codecs, capabilities, pure edits and closure validation in the authoring model. Store photos/inputs lazily by reference. The shared module depends on the geometry model. | The native/transferred/source-free switches outside their importers and validators. Keep v1 decoding and preservation of original bytes. |
| `PortraitArtists`, Studio render workers | Compile concrete producers with associated Input/Settings types. Emit the common program, optional input reference and validated receipt. UI owns transient proposals and edit state. | Producer-specific write-on-generation, direct physical ports and reconstructed photo identities. Capture adapters belong in app composition. |
| `PortraitLibrary` and the existing SQLite owner | One actor/write lease for retain/load/page/purge/import/mount. Commit selected ancestry and assets together. Emit immutable summary pages and exact typed references. Raw evidence lookup uses read-only projections. | Full archive loads for browsing, per-producer query fallbacks, portfolio-as-library routing and parallel UI autosaves. |
| Application composition and the existing draft/run runtimes | Resolve and validate a DrawingRef outside the device runtime. Pass one immutable selection carrying ref, program and verified authored provenance. Each effect remains with its current owner. | Package reimport during embedded Send, unbound program-plus-side-channel selection, ad hoc per-view readiness and mapping of failure to a lone string. |

```swift
// Value operations: deterministic, independent of filesystem and actor state.
struct Drawing: Sendable {
    let program: DrawingProgram
    let input: SourceLink<ImageInputRef>
    let parent: SourceLink<DrawingRef>
    let producer: ProducerReceipt
    var programDigest: Digest { program.contentHash }
    func summary() -> DrawingSummary
    func applying(_ edit: StrokeEdit, to parent: DrawingRef) throws -> Drawing
}
// The library freezes once and returns the retained reference.
// Browsing always returns compact projections; loading materializes an exact revision.
protocol DrawingLibrary {
    func retain(_ drawing: Drawing, reason: RetentionReason) async throws -> RetentionReceipt
    func drawing(_ ref: DrawingRef) async throws -> Drawing
    func photos(_ query: PhotoQuery, after: PhotoCursor?) async throws -> PhotoPage
    func drawings(_ query: DrawingQuery, after: DrawingCursor?) async throws -> DrawingPage
    func mount(_ verified: VerifiedExchange) async throws -> MountReceipt
}
// Shared between applications, backed by the existing planner/run/Stop owners.
protocol PlotterDestination {
    func describe() async -> DestinationCapabilities
    func prepare(_ selection: DrawingSelection, options: PlotOptions) async -> PreparationResult
    func submit(_ ticket: PreparedPlanRef, request: ClientRequestRef) async -> JobDisposition
    func status(_ job: JobRef) async -> JobStatus
    func cancel(_ job: JobRef) async -> CancellationDisposition
    func exportResult(_ job: JobRef, through snapshot: SnapshotRef?) async throws -> ResultPackage
}
```

`Drawing` is the materialized stroke representation. Other representations remain opaque records until their capability exists. Its summary uses the already validated program; persisted list rows read the stored summary directly. Bind a source-independent draft selection to the expected draft revision. A failed fit reports the selected drawing and current draft revision alongside a typed refusal. Refusal before load/retain produces no selection. Persisting a job is distinct from settling motion. Do not attach arrays of attempts, UI state, ML checkpoints or database handles to this value. Add convenience methods only when shared callers need the same operation.

Specify typed errors at their owning seam: missing/deleted revision, key/digest conflict, unsupported required feature, missing or corrupt claimed asset, stale draft or plan, refused device precondition, uncertain dispatch, pending result delivery. Put revision and concrete remedy on UI-facing receipts. Derived thumbnails and decodes are bounded caches keyed by drawing/input digest, edit revision and render parameters. Use the existing producer-specific semantic validator when present.

## Performance and compatibility obligations

| Operation | Contract to measure |
|---|---|
| Chronological photo/drawing pages | Index stable sort keys and use keyset cursors with tie-breaking identity; photo chronology uses capture time, explicit import fallback and deterministic unknown-date treatment. A bounded page of k rows reads no full program, input raster, evidence frame or portfolio snapshot. Counts use indexed relations or maintained summaries. |
| Exact drawing load or edit | Indexed lookup plus work proportional to selected bytes/strokes. Verify once per immutable file version/commit. Repeated selection reuses verified bytes/hash; same ID with changed bytes fails admission. Stroke edits address stable IDs, use one pass through affected geometry and never reconstruct by current browser filter. |
| Generation, rename, Rank | Reuse prepared input per exact preparation/renderer key. Generate/view/open editor: zero retained drawing writes. Rank: one feedback commit, then advance; failed commit keeps the same comparison. Rename: zero checkpoint decodes, training regroupings, geometry regenerations or unrelated thumbnail invalidations. |
| Camera and placement | Zero catalog queries, full-program hashes or training refreshes per live frame. A placement change may rebuild the plan and affected preview, never rewrite the authored program or source. |
| Import/export, restart and replay | Stream each distinct blob once per verification pass, bounded buffers, cancellation-safe staging, reads proportional to declared closure. Replaying the same result creates zero new revisions/runs. Measure bytes read/written, asset count, peak RSS, p50/p95 latency, and UI-thread occupancy. Raw run durability must precede any dependent effects. |

Before moving a hot path record a comparable baseline using the same build configuration, host, input and cold/warm cache conditions. Exercise a small fixture and at least 10,000 synthetic retained drawing summaries plus realistic deduplicated raw frames on disposable data. Hold page size fixed as archive size grows. Gate structural counters above and existing native responsiveness budgets. Record at least 30 warm trials per scenario, report distributions, archive size and configuration, and investigate regressions beyond baseline noise before landing. An optimization claim needs before/after numbers; a cold start observation must identify its cache state. Measure signed-app/native and physical behavior separately from Swift and Python fixture checks.

### Current derived presentation and cursor implementation

The current Dojo image body displays an asynchronously prepared image. Its derived
cache keys immutable caller identity plus decode dimension, bounds resident entries/
bytes and actual unsettled workers, and uses cancellation/generation guards. Encoded
provider retention counts toward the decoded-cache budget. Current checkpoint and
supervision keys distinguish relevant immutable fit/snapshot/feedback/curation changes
from title/navigation changes. Original images, feature/feedback records and geometry
remain authoritative; cache eviction removes derived values only. Existing camera-frame
and per-view placement caches remain separate.

Global chronological Drawing cursors use two disjoint indexed ranges inside one read
snapshot: same-date `(namespace, identity)` successors, followed by older dates for the
remaining page. This preserves mixed descending-date/ascending-identity order without
scanning from the index head through a large tie group. Scope/generation/full-ref and
tombstone rules remain unchanged. The dated [group receipt](CURRENT_EVIDENCE.md#current-native-drawing-workflow-group-2026-11-08)
records the actual bound-plan finding, affected fixture/work counters and measurement
limits; it does not establish the remaining full-scale/media/native gates.

## Current local destination boundary

`PortraitCore.DrawingDestinationRequest` defines Describe, Prepare, Submit, Status,
Cancel and ExportResult; `DrawingDestinationReply` carries typed descriptions,
tickets, decisions, refusals, cancellation acknowledgement/settlement and result URLs.
`PortraitLibrary.DrawingDestinationService` and its file adapters use the same contract.

| Operation | Current behavior |
| --- | --- |
| Describe | Stable local engine identity, current exchange/Drawing/stroke profiles, authored-style preservation and captured destination applicability. Placement/border/material/readiness options are captured; arbitrary overrides and a nominal-width requirement are absent. Production execution is unavailable. |
| Prepare | Through the existing projection-bound app/draft owners, load/retain the exact Drawing/input/parent closure, select/fit and capture a genuine current plan/options. No executable plan means typed refusal and no ticket. A ticket pins full DrawingRef, destination, draft revision, actual plan ID/hash and plan/options asset digests. |
| Submit | Recheck a new request against the stored ticket and live facts; changed facts require a new preview. A decided same-key retry returns the original decision. Production durably refuses with `issuance-seam-unavailable`; it never falls back to legacy Start. |
| Status | Look up by JobRef or client namespace/request after a lost reply; compact domain rows contain no geometry/plan bytes. Metadata counter evidence excludes explicit owner opening/recovery. |
| Cancel | Acknowledgement and settlement are separate fields. A refused job is already settled and retains its immutable receipt. Only the disposable non-device harness exercises accepted/held/reconciling cancellation. |
| ExportResult | A genuine prepared refusal exports engine-owned authored closure, actual frozen plan/options and refused receipt, zero attempts/issuance. Missing return publication may be repaired without submitting/dispatching again. Accepted zero-attempt results remain invalid. |

The existing Library actor/journal/CAS owns the engine/client identities, prepared
records, namespace-qualified request digest mappings, job decisions and pending deliveries.
A namespace is part of the request record kind, so equal request UUIDs from different
clients do not collide. Admission queues the complete operation across awaits. Decision
and request mapping commit atomically; uncertainty recovers through the existing writer
and exact lookup. Preparation owns plan/options assets before acknowledging its ticket;
status rows retain only their pins. There is no new database or Library writer.

Control JSON is bounded to 1 MiB. Client-owned requests/artwork and engine-owned replies
are published atomically under
`~/Library/Application Support/AdaptivePlotter/DrawingDestination/`. The narrow
`.drawingrequest` declaration belongs to AdaptivePlotter; neither app claims generic ZIP
ownership. Existing explicit Drawing import and direct delegate paths remain. Startup
republishes client pending Prepare; the engine receives only after runtime startup and
saved view/Photo restoration. Recovery polls Prepare only, ignores Submit, skips valid
responses without rewriting, and reveals a matching current ticket once without foreground.
Explicit user handoff may foreground the destination. View-owned route/layout callbacks
and dynamic request/ticket guards prevent stale completion from retargeting selection.

Result publication streams its seal, builds a same-directory private ZIP, synchronizes
it and installs with exclusive atomic rename. A verified same-job result is reused;
a divergent target is preserved. `includedAsOf` is the immutable refusal wall time.
The local `adaptiveplotter.local-prepared-plan/1` and
`adaptiveplotter.local-medium-options/1` validators decode the actual owner plan/options,
with their existing validation/bounds; the exact plan asset pin is not the authored
program hash when placement/border composition differs, and grants no physical authority.
The independent Python carrier checks known envelope/hash/reference closure; its
`unsupported []` for these refusal envelopes does not implement native physical-plan,
intent/frontier/assessment codecs or prove readiness/issuance/ink.

Existing Draw/Start/Stop/run ownership is unchanged in adopted DX-12. Definition-only
DOC-06 canonically defines the later DX-13-ISSUANCE correction, without executing
it. See [Current Evidence](CURRENT_EVIDENCE.md#doc-06-drawing-issuance-definition-candidate)
for actual DX-12 closure and remaining issuance/native-codec/scale/physical limits.

## Persistence, exchange and atomic mounting

The active local Library uses one selected SQLite catalog and a content-addressed
object store. Full typed references and original-byte digests establish identity;
titles and dates are catalog metadata, not paths. Renaming does not move or
reidentify a record, and an unknown date remains unknown.

```text
DrawingLibrary/
  drawing-library.sqlite          # typed relationships, queries, mutable metadata, transaction/intent identities
  drawing-authority.json          # selected-catalog marker
  objects/sha256/<digest>          # exact immutable records, programs, originals and prepared inputs
```

Photo, prepared-input and parent links are typed catalog relationships resolved by
full reference. Photo-derived children and source-free drawings use the same
catalog/object store; no per-photo folder mirror is another authority. Raw physical
attempts remain in their independently authoritative evidence archive, including
when a drawing disappears from ordinary browsing. Portable inspection copies do
not replace that authority. Derived summaries can be rebuilt from verified
immutable records; durable mutable metadata, retention reasons, tombstones and
transaction/intent associations need a recoverable metadata backup and cannot be
reconstructed from geometry alone. Use one Library writer/lease. A separate
plotter writes its own evidence archive and publishes an importable result; it
does not write into an open Studio Library.

A portable export is a snapshot with a closed payload. For this closed profile, bagit.txt contains exactly the two required lines, `BagIt-Version: 1.0` then `Tag-File-Character-Encoding: UTF-8`, each LF-terminated, UTF-8 without BOM. manifest-sha256.txt lists every payload file exactly once. tagmanifest-sha256.txt lists bagit.txt, the payload manifest and any other non-manifest tag files, never itself or payload files. No fetch.txt, links, devices or special archive entries. Implement the declared application profile, without claiming general BagIt validator conformance. Store the original file bytes without base64. ZIP changes transport only. For a returned result, include the exact authored document even when the receiving library is empty.

```text
<export>/
  bagit.txt
  manifest-sha256.txt
  tagmanifest-sha256.txt
  data/exchange.json                # profile, kind, selected roots, included-as-of scope
  data/drawings/<issuer>/<revision>/drawing.json
  data/attempts/<archive>/<run>/<sequence>/attempt.json
  data/photos/<issuer>/<revision>/photo.json          # when a source exists
  data/inputs/<issuer>/<revision>/input.json         # when a prepared input exists
  data/assessments/<issuer>/<id>.json
  data/jobs/<engine>/<job>/receipt.json
  data/objects/sha256/<digest>       # programs, originals, input, plan, records, media
```

`data/exchange.json` lists the profile, kind, digest-pinned roots, included-as-of timestamp, asset descriptors and included attempt/assessment references. Object references in the drawing and attempt manifests resolve through those descriptors. The bag manifest covers every payload file. Each typed relationship resolves to the intended bytes and type. Preserve original immutable JSON bytes across imports and re-exports. Encoding uses UTF-8, unique JSON keys, finite numbers, explicit schema versions and units. Store clock values that may exceed exact JSON integer portability as decimal strings in the exchange envelope. Media objects carry encoding, length, digest, dimensions and the pixel layout/stride, channel order or container type needed to decode them. Keep legacy Swift record bytes as typed payloads; publish their wire schema and independent-reader fixtures. Object digests are computed over exact bytes. Consumers verify the existing semantic program digest after decoding the program. They need no JSON normalization to verify a transferred record.

Asset references carry `{object,byteLength,mediaType,encoding}`, where object is the exact-byte SHA-256. Interpret encoding by explicit schema. UTF-8 records identify a JSON profile. PNG/JPEG originals declare encoded dimensions, orientation and color space where known. Raw frames declare width, height, pixel format, component type/bit depth, channel order, row stride, byte order, orientation and color interpretation; preserve the exact original including padding. Arrays, if present, declare shape, dtype, layout, byte order and units. The original decoded-image/frame digest, when available, is an additional algorithm-qualified value. Check decoded size/stride arithmetic before allocating. Timestamps carry wall time when available and an event or capture time with clock ID/boot-session. Only compare different clocks using a recorded synchronization mapping and error bound.

```json
{
  "profile": "adaptiveplotter.drawing/1",
  "ref": {"issuer": "550e8400-e29b-41d4-a716-446655440000", "revision": "e95e1607-a025-4598-880a-221077f27cc1"},
  "createdAt": "2026-11-03T18:00:00Z",
  "representation": {"kind": "adaptiveplotter.stroke-program/1", "object": "<program-file-sha256>", "programHash": "<existing-semantic-digest>"},
  "requiredFeatures": [], "input": {"state": "none"}, "parent": {"state": "none"},
  "producer": {"id": "adaptiveplotter.catalog", "version": "1", "record": "<producer-record-sha256>"}
}
```

```json
{
  "profile": "adaptiveplotter.plot-attempt/1", "requiredFeatures": [],
  "issuerArchive": "<plotter-archive-uuid>", "run": "<run-uuid>",
  "sequence": 1, "previous": null, "sealed": false,
  "drawing": {"issuer": "<author-uuid>", "revision": "<revision-uuid>", "digest": "<drawing-record-sha256>"},
  "job": {"engine": "<engine-namespace>", "job": "<job-uuid>", "receiptDigest": "<receipt-sha256>"},
  "environment": "live",
  "intent": "<durable-intent-sha256>", "coverage": "<coverage-and-missing-reasons-sha256>",
  "state": "interrupted", "dispatch": "possibleInk", "observation": "unavailable",
  "terminalRecord": null, "assessments": []
}
```

Examples show the field structure. Angle-bracket values denote deliberately omitted fixture values. The interruption was recorded before a terminal result. A training consumer can read the intent and coverage, and can exclude this attempt from image residual training.

A reader checks version, safe relative paths, unique entries, declared kinds, byte/count/image-expansion limits, hashes and semantic links before publishing. Reject path traversal, links escaping the root, duplicates including case-fold collisions, or a changed digest at the same issuer/revision. Stage files on the destination volume and verify them. With the writer lease, publish immutable assets first and make the SQLite link visible in one committed transaction. Recovery can finish installation or collect unreferenced staging assets. Reimporting an identical revision is a no-op. Importing a conflicting one reports the collision and preserves both the existing state and incoming bytes for inspection. A checksum establishes integrity, not the authenticity of an external authority.

Mount is a library operation, not a mutation of a previously delivered bag. Snapshot key is (archive, run, sequence). The engine allocates sequence per run on content change. Preserve earlier snapshots, deduplicate exact redelivery and refuse divergent content at the same sequence. A closed result export contains sequences 1 through its selected snapshot, all predecessor manifests and their required assets, deduplicated by digest. Sequence 1 has no predecessor. Each later record pins exactly its same-run predecessor. Verify an unbroken chain and consistent job/drawing before mounting. A partial incoming fragment may wait for repair but cannot be advertised as a self-contained result. Emit snapshots at meaningful boundaries such as interrupted recovery and terminal publication, without issuing one per frame. After sealing, further testimony and analysis are independent supplements. Evidence after a sealed result, a new interpretation, a human note, or a no-ink declaration is a separate attributed record pointing at the exact result. Imported assertions cannot clear local possible-ink state. A newly exported bag may include the drawing and any selected attempts together.

## The printer-like boundary

A refused submission can return a closed result with one drawing and a refused
job receipt, zero runs and zero attempt snapshots. Verify the receipt's drawing
and refusal before admitting this form. For a job with a staged run the portable
result includes its snapshot chain. Separate refusal, interruption and terminal
execution when reporting counts and computing training eligibility.

| Operation | Request → response | Owner and invariant |
|---|---|---|
| Describe | destination → supported document profiles, media mappings and options | Engine advertises what it understands |
| Prepare | exact Drawing + requested options → preview, draft revision and plan reference or typed missing requirement | Existing draft/planner. No machine dispatch |
| Submit | client request ID + drawing digest + exact prepared plan/options → job ID, state and reason | Plotter persists the receipt before acknowledging. The receiver compares the expected plan and current applicability |
| Status / Cancel | job ID → current state, attempt link and reason, or cancellation disposition | Only the run owner admits Start/Stop. A cancellation request can precede settlement |
| ExportResult / Mount | job/attempt and snapshot selection → closed result package → library commit receipt | Plotter exports facts. Studio validates, deduplicates and displays them |

Two separate applications can use local request/receipt files, each written by its owner and atomically published, with an OS document-open event to foreground the destination. Use the same typed call within the combined app. Studio's Plot… pins the explicitly selected drawing and opens Prepare in the destination. Only an explicit Plot in the destination submits the reviewed plan and enters the existing Start admission. A changed plan returns the user to preview. To acknowledge an accepted job, Plotter must already own a durable verified copy of the drawing/input/parent bytes needed for its eventual result. Disconnecting Studio or losing its pathname after acceptance cannot destroy that closure. Delivery order, visible job state and relaunch recovery matter more than transport choice. A drawing file alone is inert.

Keep a durable mapping from (client namespace, request ID) to the request digest, job ID and optional run. Retrying the same request yields the original job. Reusing an ID with a different drawing, destination, prepared plan or options is a conflict. A timeout triggers a status lookup. Before Start persist a unique issuance identity for the job. Bind it to the runtime request and one RunID in durable storage before any physical effect. The execution owner must return or reconcile the same run for that issuance, using its staged intent/request evidence. A crash between acceptance, Start, intent staging and publishing the run link leaves the job reconciling; uncertain issuance never initiates a second Start. This is a new boundary requirement: today Start allocates a fresh RunID and stages intent later. After an uncertain dispatch the job exposes possible ink and requires the existing recovery process. A deliberate physical retry is a new job with fresh paper/readiness checks. Raw intent and possible-ink persistence complete locally before their respective effects. Portable publication is a retryable export after local recording. If the destination disappears, expose “result waiting to return” and retry publication without dispatch. We guarantee deduplication of admission and never infer exactly-once deposition.

The runtime continues through `DrawingPlacement → ExecutionPlanRevision → PlotterDrawingRunPlan → DrawingPlanRequest → RunInterpreter → MachineController`. Use its actual check-before-motion, stage-intent, possible-ink, progress and evidence records. The exchange layer reads them and returns their classifications. A result that opens in Studio carries no live calibration, paper, retry, or actuation authority.

## What self-sufficient means for training

A result package must allow an independent offline reader on an empty machine to answer: what was intended, what was prepared for this medium, what was actually requested or observed, which claims can be supported, and what is missing? It is a declared data closure for those questions. It is not a promise that every camera view or label exists or that the original generator binary/model is redistributable.

| Group | Required information or explicit loss reason |
|---|---|
| Intended work | Exact drawing, ordered strokes or representation, retained input/parent chain, producer settings/model revision/seed when applicable, source original and exact prepared raster for image-derived work. Pin checkpoint digest even when weights are unavailable. |
| Physical deployment | Exact pre-motion binding, composed program and its authored-stroke mapping, placement/coordinate frames and units, plan, accepted region, device/software, calibration/registration, paper/surface and pen/tool/material settings, motion recipe and any material substitution. |
| Timeline and command facts | Environment, job/request/run identities, sequence, clock domains, recorded timestamps, preparation, dispatch possibility, planned/commanded/controller-completed/ink-verified frontiers kept distinct. Include available interpreter/segment transcript or mark unavailable. |
| Observations | Indexed baseline/progress/terminal frames, original bytes and decoding metadata, capture source/time, registration to target, coverage/occlusion, measured intended/observed geometry, accepted/rejected/unavailable outcome and reason, measurement algorithm and version. |
| Interpretation | Human feedback, positive and negative labels, later analyses and their inputs, included-as-of scope. Separate outcome, operator confirmation, artistic preference and measured physical error. Missing observations carry no positive or negative label. |

Every claimed reference in the exported scope must resolve locally. A missing historical component gets an explicit status such as never captured, unavailable, or intentionally withheld. A file claimed present but absent is corruption. Portable **inspection** remains possible with missing data. Eligibility is per task. A residual example needs an aligned attributable observation and target. An interruption example needs an observed stage/frontier. The feature-only Rank capsule has its own digest, ordered presentation IDs, features/producer/extractor versions, evaluation question, ranking/tie/skip response, and an explicit geometry-omitted declaration. It is a feedback target independent of a retained DrawingRef. An authoring preference example needs the presented alternatives and explicit judgment. The teaching record can freeze comparison features, producer settings and extractor revision without retaining rank-only drawing geometry. Such features cannot support re-extraction or arbitrary future image labels; make that limitation visible.

Freeze a training manifest with task ID/version, input and label contract, exact selected snapshot and assessment digests, split/group assignments, exclusions and reasons, extractor revision, and included-as-of time. An offline export includes all dependencies required for that specific task. Keep failures, refusals and interruptions as explicit categories to avoid success-only bias. Freeze dataset membership, label/feature/model revisions and source/session grouping at training time. Group related captures/attempts to avoid train/test leakage. A checkpoint belongs to the learner and changes only future deployments. Physical quality feedback is distinct from the aesthetic question “which drawing do I prefer?” Review notes, no-ink confirmations, synthetic frames and imported media retain their provenance. A raw photo is evidence only in its accepted observation context.

## User activities and retention

Library offers a chronological Photos stream, retained Drawings and their Attempts. Show capture date, retained drawing count, attempted count and drawings with attributable plot evidence separately. Allow switching from a photo to its prepared inputs and retained branches. Rank only writes feedback and advances after its durable commit. Choose/Refine/intentional pruning retain the selected path. Completing an explicit unchanged pruning target can retain and label the base without creating a fake child revision. Generating, browsing or opening the editor does not retain generated siblings. The portrait capability and a source-free catalog fixture both send the identical Drawing contract. Studio's **Plot…** pins and retains the specifically submitted revision and selected parent/input path. The destination shows the target preview, material mapping and actual readiness reason. Only its explicit **Plot** action submits the prepared job. After a run, the drawing shows the attempted plan, outcome, available photographs and missing evidence. Plotter owns calibration, sheet confirmation and Stop. A sheet-confirmation interaction can reveal the correct outline without depending on an unrelated Video Settings toggle.

See the [Roadmap](ROADMAP.md#drawing-exchange) for implementation dependencies, cutover checks and deployment gates.

## Technology and precedent

| Technology | Decision and reason |
|---|---|
| BagIt directory + ZIP | Adopt a closed BagIt profile for immutable transfer with a complete payload manifest, and ZIP as optional transport. Its existing file-integrity conventions suit original media. We supply relationship and training semantics. [RFC 8493](https://www.rfc-editor.org/rfc/rfc8493.html) |
| Open Packaging Conventions | Strong alternative for independent tools needing standardized typed parts, content types and relationship discovery. The initial two applications mainly need integrity and file closure, which BagIt supplies with less relationship machinery. Revisit if an external vendor already consumes OPC. [ECMA-376 Part 2](https://ecma-international.org/publications-and-standards/standards/ecma-376/) |
| 3MF | Borrow resources/build-instance separation and required extension handling. A 3MF file would require additive-manufacturing model semantics on a 2D stroke document; our physical-attempt evidence still needs its own profile. [3MF specifications](https://3mf.io/spec/) · [3MF Core](https://github.com/3MFConsortium/spec_core/blob/master/3MF%20Core%20Specification.md) |
| SVG and InkML | SVG can carry a drawing preview or a separately validated vector import. InkML offers typed stylus traces and capture context useful for a future signature capability. Neither existing representation defines our operator selection, machine attempt and camera evidence semantics. [SVG paths](https://www.w3.org/TR/SVG2/paths.html) · [InkML](https://www.w3.org/TR/InkML/) |
| IPP | Adopt the printer/document/job split, capability query, job state and reason, status and cancellation. Use the local application transport above. A job's terminal state does not establish observed ink. [IPP model and semantics](https://www.rfc-editor.org/rfc/rfc8011.html) |
| SQLite | Use for the library index, metadata and atomic local transactions. It is a credible single-file alternative if real benchmarks favor single-file updates over directly accessible media and independent exports. [SQLite as an application file](https://www.sqlite.org/appfileformat.html) |
| HDF5 | Strong for heterogeneous typed datasets and partial access to large chunked numeric arrays. Consider it as a derived training export if data access patterns justify it. It adds a container/runtime dependency and does not settle drawing identity or job semantics. [HDF5 data model](https://portal.hdfgroup.org/documentation/hdf5/latest/_h5_d_m__u_g.html) · [HDF5 single-writer model](https://portal.hdfgroup.org/documentation/hdf5/latest/_s_w_m_r_t_n.html) |
| BSON | Can encode typed binary values conveniently. It supplies document encoding but still requires our identity, membership, durability, result and schema rules. Prefer JSON plus original binaries for inspection. [BSON specification](https://bsonspec.org/spec.html) |
| MCAP / RLDS | Optional downstream formats. MCAP is a candidate for high-rate timestamped traces. RLDS's distinction between a final recorded step and a terminal state is useful for training exports of interrupted attempts. Neither is required to open a drawing. [MCAP specification](https://mcap.dev/spec) · [RLDS dataset format](https://github.com/google-research/rlds#dataset-format) |
| PROV / RO-Crate | Borrow explicit derivation and attribution. Consider RO-Crate for publishing research datasets. Its JSON-LD metadata can live in a file. Our two applications have a fixed relationship vocabulary, so the interoperability benefit currently belongs at the research export boundary. [W3C PROV-DM](https://www.w3.org/TR/prov-dm/) · [RO-Crate](https://www.researchobject.org/ro-crate/specification/1.3/structure.html) |
| Historical DrawingPackage / PlotAttachment | Preserve historical files and frozen hashes untouched. Legacy authoring-format runtime readers and writers are retired by the Drawing-first cutover; a future explicit importer may recover proven facts without inventing origin or media. Physical run/evidence ownership remains unchanged. |

## Inert Library result API scope, 2026-11-08

The adopted DX-06 public layer belongs to the existing concrete DrawingLibrary
owner. A result reference consists of the exact original exchange index digest and
complete publication inventory digest. Multiple result deliveries and an authored
publication can contain the same DrawingRef; selected result reads/exports must
use that result's inventory, never a first Drawing match. Indexed declared root
metadata carries no interpretation privilege. Admission of the selected verified
inventory recomputes Core capabilities, including unknown-feature restrictions.
Original index, receipts, snapshots, assessments, media and extension bytes remain
the export representation. Closed results can end at an unsealed, nonterminal
sequence N, provided the finite 1…N/media closure is self-contained. Refused jobs
with zero attempts remain run-free. Read-only pages use catalog metadata without
acquiring a writer or reading artwork. Global result metadata discovery includes
opaque deliveries after restart; a full-DrawingRef selector is an optional narrower
query scope, and cursors cannot cross scopes. Ordinary Drawing summaries are
installed atomically only for admitted materialized declared roots, using their
original record dates. Opaque roots do not gain invented program metrics, and
existing titles, retention reasons and tombstones remain unchanged.
This scoped work grants no execution,
retry, no-ink or other live physical authority; historical import stays deferred.

## Shared membership editor boundary, 2026-11-08

The embedded and standalone Drawing browsers share one `DrawingLibraryBrowser`
and `DrawingMembershipEditor`, borrowing the existing `PortraitSketchCollection`.
UI request/sheet state is transient; it is not another collection or selection
owner. The native canvas uses stable stroke IDs, and only admitted `.edit`/`.preview`
values render/edit. Source-dependent overlays are not invented. Fresh unknown pen
width is valid and introduces no additional required input.

Explicit Done enters collection-admitted save, checks the exact retained parent,
then uses existing atomic parent/child retention and exact reload. Surviving IDs,
order, points and immutable ancestry/source bytes stay exact. Unchanged Done retains
the base with no synthetic child. Cancellation before Save writes nothing; Close
while saving allows the admitted operation to settle while invalidating UI adoption.
Live Retry reuses stable intents; abandonment/replacement releases local pending
preparations through the collection drain, never durable journals or committed CAS.

Sheet base, opening selection epoch and completion identity prevent late retargeting
when a sheet closes or another occurrence is selected. Save returns a Drawing without
selection mutation; current completion alone can adopt it. Generic editing neither
creates Flow feedback/targets nor implicitly projects or starts a run. Explicit Send
uses the original full-ref/request guard without rejecting its own expected selection
publication. Existing device/runtime/physical authority is unchanged.

These are dated DX-08 implementation observations for task
`task-67802fca3f9b44dc9e8b024dfa58ccc4`. Default software tests cover real constructors,
a separate real browser model/shared collection, hosted native canvas and save APIs;
interactive hosted button/sheet acceptance remains strict AX opt-in and unverified
in the observed host. Final configured validation/landing belong to the task. See
[Current Evidence](CURRENT_EVIDENCE.md#dx-08-shared-drawing-editor-software-receipt-2026-11-08)
for exact proof and limits; this is not campaign completion or historical import.

## Canonical feedback and frozen training task, 2026-11-08

DX-09's dated pre-gate software boundary uses the existing DrawingLibrary journal/CAS.
`commitFeedback`, `feedback`, `mountFeedback` and `exportFeedback` select exact index/
inventory pairs and preserve original bytes; read/export recheck admission. Canonical
ranking capsules alone own the human presentation, exact features, question and response.
A software-attributed Assessment records a selected revision, targets/answers only its
exact capsule and supersedes the prior marker within the same presentation/feature basis.
It is not another human judgment. Common Assessment answer semantics remain conservative;
the Flow reader accepts only its known questions, adapter and exact basis.

`feature-ranking/1` exhaustive ranking and Skip are unchanged. Partial ranking uses
`adaptiveplotter.feature-ranking.partial-ranking/1` with groups plus an explicit
unranked partition (empty groups/all-unranked is valid); Neither uses
`adaptiveplotter.feature-ranking.neither/1`. These features apply only to that profile.
Choice is an asset-targeted selected/ordered-offered observation, not a tied ranking of
losers. Pruning assessments name stable stroke IDs on an exact feature basis, with
remove/restore/undo/redo/completed-mask semantics; authored Drawing refs stay in local
navigation, not canonical answers. Earlier judgments remain immutable.

Explicit Choose/prune has two durable facts: atomic authored parent/child retention,
then atomic canonical feedback/dependencies/navigation with a distinct stable intent.
UI acknowledgement waits for both. Failure between them may retain the explicitly
requested Drawing without claiming feedback success. Rank/view creates no retained
Drawing. Optional display-preview PNGs can accompany exact feedback export; they are
neither source Photos nor authored geometry nor training inputs.

`freezeTrainingSnapshot` emits a digest-addressed `adaptiveplotter.flow-training-task/1`
manifest. It pins canonical Assessment/Ranking refs, exact JSON feature/label/producer/
extractor assets, program digest, ordered stroke IDs, resolved supervision, curation and
reasons, connectivity/splits, seed (current pipeline 42), trainer/configuration and recipe.
The actual fitter receives the frozen seed/configuration/split. Online and offline reads
use the same strict exact-files task decoder; missing, corrupt or unsupported dependencies
refuse rather than fall back to live UUID lookup, geometry extraction or regeneration.
JSON-only task export follows those dependencies, excluding display rasters, source
Photos, Drawing programs and the separate frozen UI projection. Later metadata/feedback/
extraction changes affect only future tasks. Unique materialized bytes and feature values
are bounded across each read/freeze; selected-example limits remain separately enforced.

This implementation snapshot is tracked by
`task-222f2a729f8b4f9781bf4eb7f0c4095f`; final configured acceptance/landing belongs to that
task. See the [dated receipt](CURRENT_EVIDENCE.md#dx-09-canonical-feedback-and-frozen-training-inputs-2026-11-08).
Historical import remains deferred; no additional UI/width/setup input or physical,
Runtime/Episode, signed deployment or model-promotion authority is introduced.

## Current Library navigation boundary, 2026-11-08

The production Library routes reuse `DrawingLibraryBrowser`, the membership editor
and `PortraitSketchCollection`; they do not create another Drawing selection owner.
`drawings(in:limit:after:)` scopes compact metadata to all retained Drawings, exact
Photo, exact Input or direct children of an exact parent. Existing Photo/Input pages
and scoped Drawing cursors bind complete refs and catalog generation. Metadata pages
read indexed SQL projections, not Drawing programs, raster assets or whole portfolios.
Missing/conflicting selections remain unavailable; capability refusals apply to
operations that depend on unsupported semantics, preserving independent known geometry.

`attempts(for:limit:after:)` projects only known declared snapshot targets and returns
one latest snapshot per archive/run. Several index roots are not assigned every
attempt. Each row preserves declared environment/state/dispatch/observation, unsupported
reasons and the exact result publication handle; none grants physical interpretation.
The projection is frozen/verified with the existing publication journal/SQL transaction.
Raw binding `adaptiveplotter.drawing-run-binding/2` is minimal staged navigation:
full DrawingRef, archive/run/request and staged generation. It contains no duplicated
execution program/intent. Bounded exact-ref domain pages locate bindings; explicit
selected verification checks the existing raw owner. Binding alone proves neither
Start, current RunID nor ink. Raw media/notes/possible-ink authority stays unchanged;
deleted/dismissed review rows are not resurrected, and metadata-only refresh keys
observe same-revision attempt/visibility changes without hashing whole programs.

`adoptExistingPhoto(_:)` uses the original verified Photo/assets for current PNG/JPEG
authoring and reuses its occurrence/navigation. It neither reimports the image nor
initializes metadata over existing clears/groups/exclusions. Raw/opaque sources remain
browsable/exportable with dependent authoring refused. `exportPhoto(_:to:)` preserves a
verified containing publication, including opaque context; it is not a pixel conversion
or a Photo-based selector for a particular result inventory. Collection-admitted optional
field patches serialize and drain on close; view dismissal cannot lose an accepted write.
No new metadata owner, mandatory field, normalization algorithm or runtime owner is added.

## Neutral source and metadata boundary, 2026-11-08

DX-07's concrete `DrawingLibrary` exposes `photos(limit:after:)`,
`inputs(for:limit:after:)`, `photo(_:)` and `input(_:)`. Exact loads use Core
validated original files and return `FrozenPhotoRecord`/`FrozenImageInputRecord`
without re-freezing JSON or altering descriptors, mask/transforms or alias roles.
Unknown index/Photo/Input requirements cannot become reusable known source facts;
opaque metadata can still be listed with unavailable facts and an unsupported
reason. Known explicit unknown dated facts retain their provenance. Known PNG/JPEG
headers do not establish decoded pixel semantics. Producer input preparation binds
supplied bytes and dimensions to the exact Photo original asset.

Photo metadata pages use compact journaled SQL projections, capture/import fallback
and an explicit unknown-date bucket. Inputs use exact-ref keysets, because their
wire records have no authored date. Cursors bind full scope and catalog generation;
readonly absence creates no catalog or writer. The current internal schema is 12;
it requires source metadata and derived result-attempt tables and rejects older
internal schemas without migration or backfill. The wire profile remains unchanged.

`DrawingLibraryPhotoMetadata` is the one live optional title/subject/session/
exclusion authority. Patches explicitly distinguish unchanged from set/clear;
blank text clears to nil after raw size checks. Existing commit intents bind the
captured request, so uncertain retry cannot replay old edits over later metadata.
Source publication, initial metadata and Flow domain rows share one journal/SQL
transaction. Flow source fields are cached projections, refreshed only when the
neutral metadata revision or source membership changes; absent titles display the
derived “Photo” label. They are not a second writable authority.

Collection idempotence uses collection ID plus original entry ID, binding original
bytes/length/session/provenance rather than mutable curation or pixel equality.
Exact equal-source-byte acquisitions retain distinct Photo refs and shared leakage
grouping, joined transitively with declared subject/session groups. Decoded-pixel
equivalence across different encodings has not been established.
Drawing-only `retention`, `setRetentionReason` and `restore` expose reversible
reason/hide state; these operations neither delete CAS/evidence nor establish GC
eligibility. No Photo/Input tombstone API is introduced.

Photo-metadata training isolation means future freezes sample current neutral
values and old frozen training documents retain their bytes/values. Canonical feature membership belongs to the DX-09 boundary above, independently
of the frozen Photo metadata projection. Historical import,
reachability/GC and physical execution remain separate. No mandatory new user
fields, width declarations or setup are introduced. This dated pre-gate scope is
tracked by task `task-660bbaadb1c6459aac41feaae2902409`; final validation and landing
belong to that task. See the [scoped software receipt](CURRENT_EVIDENCE.md#dx-07-neutral-source-metadata-software-receipt-2026-11-08).

## Current software cutover boundary, 2026-11-08

The concrete `DrawingLibrary` target supplies the active shared owner, exact-ref
Drawing loading/retention, chronological metadata pages, and current directory/ZIP
authored transfer. Both actual application compositions use the current format;
old authoring readers/writers/fallbacks are retired. Historical files stay untouched
for a later explicit importer. No new mandatory UI width or declaration field is
introduced. Raw execution, Stop and physical evidence remain with their existing
owners. These implementation observations have scoped
[probe receipts](CURRENT_EVIDENCE.md#drawing-first-software-probe-receipt-2026-11-08).
They are a **2026-11-08 pre-gate snapshot**; authoritative later configured
validation, acceptance and landing state belongs to Blackdog task
`task-89f7fee3b6c847e9ae9acebb9b901347`.

A materialized stroke value is not permission to use every operation. Consumers
must honor the admitted `.preview` and `.plot` capabilities before rendering,
handoff effects, execution-reference adaptation or bare-program selection. At
Run, a known denied projection matching the authored draft must refuse before any
source-free fallback, including when execution contains border/placement geometry.
Unknown per-Drawing features therefore remain denied even under a known index;
original bytes remain browseable/exportable. The
[capability supplement](CURRENT_EVIDENCE.md#per-drawing-capability-closure-supplement-2026-11-08)
records scoped software proof; no raw runtime protocol was changed.

A fresh Flow producer validates its supplied artifacts. The app's default read
registry does not semantically revalidate arbitrary persisted Flow receipts;
known-program preview/plot/edit support and byte preservation are distinct from
producer verification. Generic regeneration/training capabilities must remain
unadvertised without that proof. Current Dojo learning/material operations use
exact domain capsules and references; this does not complete future portable
producer-proof, mount, job or result-adoption gates.

## Baseline and bounded format check

The raw execution owner distinguishes a staged intent, possible ink and terminal observations. The historical v1 attachment was limited to a transferred origin and terminal ordinary run; its retired exporter is not an active compatibility route. Current authored transfers use the exact-ref Drawing Exchange carrier. Portable result adoption remains a separate later gate: review notes and no-ink confirmations retain their raw archive authority and need explicit scope/attribution in an exchange snapshot. [Staged intent](../Sources/PlotterRuntime/DrawingRunIntent.swift) · [Terminal record](../Sources/PlotterRuntime/DrawingRunEvidence.swift) · [Current authored transfer](../Sources/DrawingLibrary/DrawingLibraryExchange.swift) · [Start allocation](../Sources/PlotterEpisodeRuntime/PlotterDrawingRunRuntime.swift)

The [source-free drawing example](../Tests/Fixtures/DrawingExchange/v1/source-free.zip) is the v1 authored-side reference vector. A temporary build from the current PlotterModel generated the built-in line from (5,50) to (95,50) in its 100 × 100 field. Swift decoded the program and verified its canonical content hash. An independent Python reader opened the ZIP alone, checked both manifests, resolved the drawing and assets, verified asset lengths/digests, and recovered the two points. A separate Python implementation recomputed the existing APCB canonical stroke-program digest from the decoded fields and matched Swift. A deliberately changed payload failed integrity checking. Program digest `960ce7fe5f34203bdaa451fbd48f401cdb34598bebcb3a8be7a739645f236097`. Drawing-record digest `e6f9f570fa580fa59cb5f6f3435641aa5c5c3acbcc4eeb944f3a606fe0b55ddd`. This exercises the proposed carrier and existing stroke representation. An actual result export from an interrupted or completed run, cross-language coverage of the other program and evidence fixtures, and separate-process job recovery remain implementation gates. Historical archive migration is deferred.

The source-free vector is checked by `python3 Scripts/check_drawing_exchange_fixture.py` and `make docs-check`.

For schema changes, run `python Scripts/check_drawing_exchange_schema.py` in
a development environment with `jsonschema[format-nongpl]==4.26.0`. It checks
the Draft 2020-12 schema, inline examples, real fixture envelopes and refusal
cases. Cross-record constraints, package integrity and physical evidence each
need the separate checks specified above.

## Cost and reversal criterion

The cost of the proposed package is the validator and the file/SQLite publish protocol. An index cannot certify that an original frame still exists. Measure allocations, seek/decode behavior, atomic recovery and missing-asset detection before fixing physical disk layout as a forever contract. If independent-reader and crash fixtures are materially simpler with SQLite-per-document, retain the same drawing/job/attempt contracts and reconsider the carrier. A more expressive medium must provide a real second producer/device fixture before the common representation changes.

## Named issuance definition boundary

[DOC-06](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md#doc-06-drawing-issuance-definition)
is definition-only. DX-13-ISSUANCE remains pending: its fixed lifecycle
binds original request/full Drawing refs and reviewed plan/options to one atomic raw
stage and durable accepted Run link before effects. Only the original live newly-
staged continuation can dispatch. Status/Cancel share short monotonic metadata
transitions; restart never reissues. Current production remains refusal-only.
Accepted zero-attempt export remains invalid; real accepted result snapshots belong
to DX-15. DX-14 parking/outline policy is outside issuance currentness. No additional
UI field, learning/setup step, width declaration or historical loading is required.
