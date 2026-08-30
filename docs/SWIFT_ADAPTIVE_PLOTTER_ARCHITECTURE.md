# AdaptivePlotter Swift Architecture

Status: current as-built package and ownership architecture

This document owns package boundaries, runtime owners, data flow, and dependency
direction. Product invariants live in [Product Contract](PRODUCT_CONTRACT.md),
the exact operator sequence in
[Discovery and Observed-Trial Protocol](DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md),
the sole target migration in
[Episode Architecture Execution Plan](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md),
and verified status in [Current Evidence](CURRENT_EVIDENCE.md). Planned episode
packages and ownership transfers do not become part of this as-built document
until their work package lands and its superseded path is removed.

## Package topology

```text
EpisodeCore
  Foundation-only domain-generic episode identities, goals, definitions, manifests
  capability facts and intent decisions, events, pure reducers, validated journals
  internal target consumed by the point-selection and manual-motion production compositions

EpisodeRuntime -> EpisodeCore
  EpisodeStore actor with one in-memory state and one durable event journal
  versioned integrity-checked persistence adapter, atomic append, reconstruction
  PlotterOperationRegistry bound by the point-selection and manual-motion production compositions
  typed lanes, move-only effect permits, original handles, exact Stop
  operation-bound completion, typed result/refusal, shared cancellation, terminal record
  internal target with no package product or direct application import

PlotterModel
  coordinate-space types, geometry, deterministic drawing-program catalog
  placements, drawable regions, content-addressed plans, readiness schema

PlotterEpisodeModel -> EpisodeCore + PlotterModel
  Plotter-bound definitions, manifests, intents, state, events, effects, and results
  observations, measurements, evidence, outcomes, assessments, and capability facts
  committed attributable progress, retained terminal projection, pure evaluators/reducer
  independent PlotterEpisodeCanonicalDigestV1 ownership for replay state verification
  internal target with production point-selection and manual-motion bindings

PlotterUI -> PlotterEpisodeModel
  bounded candidate compiler plus sole bounded PlotterUILearningActionabilityCompiler
  copied-fact current owner, status, action/Stop, availability, Pen, direction, reset reachability
  immutable aggregate projection with exact action membership, bound intent,
  availability, UI revision, runtime revisions, and bounded diagnostics
  typed request values and sink contract; no runtime, device, persistence, Stop,
  camera, Vision, evidence, or effect authority

PlotterEpisodeRuntime -> EpisodeCore + EpisodeRuntime + PlotterEpisodeModel + PlotterRuntime
  PlotterIntentGateway, PlotterPointSelectionRuntime, PlotterManualMotionRuntime,
  and PlotterCausalSimulatorEffectAdapter compositions
  one FIFO mutation/publication boundary, EpisodeStore owner, and exact-workflow continuation lane
  optional exact-frame recording with bounded retention and visible diagnostics
  one exact manual machine-lane owner with typed LIVE/SIMULATED effects and successor-isolated Stop
  sole causal-simulator effect admission, exact raw operation identity, typed settlement/provenance,
  and separated controller-command, plant/Pen, paper/ink, camera, Vision, and evidence truth
  EpisodeRecordingStore with typed controller and camera recording channels
  descriptor-anchored versioned manifest persistence and content-addressed exact frames
  ordered completeness, integrity, bounded retention, close, and reopen contracts
  unbound PlotterEpisodeReplayService with sealed executable descriptor/private adapter
  manifest-pin and canonical-digest-literal checks, fail-closed every-prefix reduction
  recorded effect-revision identity only, inert effect and never-resume inspection
  exact operation-bound start provenance, channel-specific recording completeness
  source-prevalidated exact/perturbed typed transcripts with causal suffix retiming
  no MachineLink conformance or production adapter
  pure unbound PlotterIncidentPackageAssembler with deterministic canonical JSON export
  source-reported recording snapshot and diagnostics without recording revalidation
  fail-closed typed package/environment relationships and incident-only sensitive-frame linkage
  checked referenced-byte accounting without frame-store validation
  deterministic envelope integrity/canonical reassembly without truth promotion
  one nominal PlotterIncidentPackageUIService around that sole assembler
  exact-identity assembly or truthful no-source refusal through request-owned bounded streams
  values-only format/count/digest/remedy/integrity-scope/nonphysical result metadata
  internal target with no package product or physical device adapter;
  point selection, manual motion, causal simulator, and incident presentation are app-bound

PlotterRuntime
  MachineController, RunInterpreter, CameraCapture, VisionWorker
  sole MachineLink transport contract with typed open/discard/write/read receipts
  monotonic receive timing, observable close failure, and partial-transfer errors
  learning artifacts and dependency graph
  sparse contact evidence, affine-first tip construction, applicability, checkpoints
  owner-bound multi-stroke execution, generic planned-ink observation
  paper and append-only drawing-run evidence
  causal nonphysical simulator and workflow telemetry

PlotterApp -> PlotterEpisodeRuntime + PlotterUI + retained application/runtime dependencies
  OperatorWorkspace projection/adaptation and retained artifact commits
  one production PlotterUIIntentSink with exact current membership, bound-intent,
  availability, UI-revision, and runtime-revision validation
  typed point-selection, Learning-mode, manual-motion, Drawing, Comparison,
  retained Learning/reset, and incident-presentation ingress
  LIVE manual adapter plus the production causal-simulator adapter and neutral lower controller ports
  explicitly attributed retained simulator workflow commands for later semantic packages
  copied PlotterUICompilerInput facts and one immutable PlotterUIProjection
  pane/window/viewport and unsubmitted manual text retained as UI-local state
  SwiftUI Learning Path, ActionSurface, Drawing Studio, Motion and Video Settings
  production checkpoint/evidence stores and semantic identity composition

PlotterTestSupport
  deterministic machine links, clocks, transcripts, and paper scenes

EpisodeCoreTests -> EpisodeCore
  domain-generic value, evaluator, reducer, event, and journal contracts

EpisodeStoreTests -> EpisodeCore + EpisodeRuntime
  store/reducer validation, atomic publication, persistence and writer-exclusion contracts

EpisodeRuntimeTests -> EpisodeCore + EpisodeRuntime
  typed-lane, move-only permit, attribution, observability, Stop, and lifecycle contracts

PlotterEpisodeModelContractTests -> EpisodeCore + PlotterEpisodeModel + PlotterModel
  Plotter binding, exhaustive-family, purity, provenance, and topology contracts

PlotterEpisodeRuntimeTests -> EpisodeCore + PlotterEpisodeModel + PlotterEpisodeRuntime + PlotterRuntime + PlotterTestSupport
  lossless recording, durable ordering, frame integrity, retention, and concurrency contracts
  every-prefix replay, revision/digest binding, lifecycle publication, inert effects
  exact start provenance, source/schedule causality, and perturbation contracts
  bounded incident assembly/export, relationship closure, canonical integrity, and authority-boundary contracts
  request-owned bounded incident UI progress, exact terminal identity, truthful unavailable-source lifecycle
  fifteen causal-environment tests for shared grammar/provenance, separated truth, exact settlement,
  Stop/cancel/shutdown, stale-owner isolation, explicit retained attribution, atomic terminal publication,
  Boundary/drawing/travel/Pen, paper/ink/camera, and ambiguity

PlotterAppTests -> PlotterApp + episode packages + retained application/runtime dependencies
  eleven focused PlotterPointSelectionEpisodeTests for production ingress, identity, provenance,
  recording, FIFO re-evaluation, complete publication, fresh Learning fact reacquisition,
  exact-owner Learning-Off cancellation, checked journal synchronization, scoped Sendable safety,
  semantic deletion, sparse-tip selection, and LIVE/SIMULATED separation
  production PlotterUI projection/sink membership, binding, availability, revision, and boundedness contracts
```

Dependencies point inward. Runtime does not import SwiftUI. Views receive
projected immutable presentation values and typed closures; they do not own the
controller, camera, calibration, or learning graph.

`EpisodeCore` has no declared SwiftPM dependency and imports only Foundation. It
is not exposed as a package product. `EpisodeCoreTests` depends only on
`EpisodeCore`. EA-04 binds this foundation through the inward-only episode
package chain for point-selection state, intents, events, and projections; it
does not move controller, camera, calibration, device, or UI authority.

`EpisodeRuntime` depends only on `EpisodeCore`, is not exposed as a package
product, and has no direct application import. `PlotterPointSelectionRuntime`
is its only production consumer: it composes one `EpisodeStore` and one
`PlotterOperationRegistry` exact-workflow lane. `EpisodeStoreTests` and
`EpisodeRuntimeTests` retain the generic foundation contracts. The
`EpisodeStore` actor serializes one in-memory state and one durable
`EpisodeJournal`: it validates a candidate append and
typed reducer result, commits the journal through its sole persistence adapter,
and only then publishes state. The committed reduction's effects are returned
as typed data but are not executed, queued, or retained; reconstruction applies
historical events in order while ignoring their effects.

The file adapter writes a typed `Codable`, versioned,
schema-revision-bound, checksummed envelope; no `Any` or `JSONSerialization`
path remains. Adapters for one canonical URL share in-process writer exclusion,
and a kernel `fcntl` lock extends exclusion across processes. The durable
expected journal is compared inside that exclusive region, so one stale writer
cannot replace a newer append.

The destination parent must already exist and be a directory. Missing and
non-directory parents receive typed refusal without ancestry creation, so
storage-directory provisioning and its entry are outside this adapter's and
package's authority. The crash-durability guarantee is intentionally scoped to
an already provisioned destination directory.

For an admitted replacement there, the adapter creates a same-directory
mode-0600 temporary file with `O_EXCL`, completes partial writes while retrying
`EINTR`, performs macOS `F_FULLFSYNC`, closes the temporary file, atomically
renames it, and `fsync`s the destination parent directory. Success is returned
only after all barriers complete. A pre-rename failure removes the temporary
file and preserves the prior durable journal. A post-rename directory-open or
synchronization failure throws
`postRenameDirectorySynchronizationUncertain`; because the candidate may
already be installed, `EpisodeStore` publishes no candidate in-memory state or
journal and requires the caller to reopen and reconcile durable truth.

The generic `PlotterOperationRegistry` actor separately owns admission
for one full canonical `PlotterOperationIdentity`: episode ID, intent-request
ID, typed intent identity, effect ID, effect revision, and typed environment.
Those intent and environment values live only in the identity.
`PlotterOperationContext` supplies their associated types but stores only the
owning subsystem and the typed result currently awaited, so it cannot become a
second synchronized identity authority. Registration also retains the supplied
original typed operation handle and typed lane. Its fixed lane roles are
exclusive machine, exclusive exact-workflow capture/Vision, bounded background
analysis, and serialized durable append.

Successful registration mints an identity-bound, structurally noncopyable
`EffectPermit` inside a structurally noncopyable
`PlotterOperationRegistration`, an optional exact `StopCapability`, and an
operation-bound `CompletionCapability`. The permit initializer and registration
storage are private; consuming `takePermit()` moves it out exactly once, and
consuming start moves it into the registry. No copyable wrapper, remint surface,
or UI-state copy can retain or duplicate effect authority. Successful start,
cancellation, or retirement destroys that authority. The completion capability
is separately unforgeable and can directly settle only its exact started
operation; it cannot settle a foreign active operation.

Start and progress require a typed `PlotterOperationEventAttribution` containing
the exact operation identity, `EpisodeEventID`, event sequence, pre- and
post-state revisions, and recorded timestamp. Identity mismatch, duplicate
event ID, invalid state transition, regressing sequence/state, or regressing
timestamp is refused without mutating the snapshot. The registry validates
reference identity and local ordering only; it neither proves nor performs the
`EpisodeStore` commitment that a later composition must complete before
supplying the reference.

An identity or event-attribution refusal returns the same move-only permit in a
noncopyable outcome without changing lane occupancy or any snapshot field,
allowing one corrected retry without minting replacement authority.

Start checks admission closure before those recoverable identity and
attribution paths. A retained unstarted permit cannot authorize work after
shutdown closes admission: start returns typed `.admissionClosed`, retires the
permit, and changes no start, progress, or attribution fact. The operation
remains observably unstarted so a later correct shutdown result can terminalize
it without fabricating execution.

Direct settlement requires the operation-bound `CompletionCapability` and a
typed `PlotterOperationResult` that carries the exact canonical identity,
terminal disposition, and settlement time. The registry classifies identity
mismatch, duplicate identical result, and conflicting terminal result before
any terminal mutation. A typed refusal leaves the active operation, lane,
original handle, permit/capability state, and observability intact. An accepted
result alone removes the active record, retires its effect/Stop authority,
releases the lane, and appends the full terminal record.

An optional exact `StopCapability` latches one cancellation-attempt owner,
requests cancellation once on the original handle, and awaits that same
handle's typed result. Shutdown first closes admission, latches every otherwise
unowned active operation before suspension, and issues all new cancellation
requests before awaiting settlement. Concurrent or repeated Stop and shutdown
observers share the already latched cancellation attempt and its one original-
owner await; they do not issue duplicate cancellation. If the handle returns a
mismatched result, the registry publishes the same typed refusal to all attempt
observers, releases the attempt latch, and keeps the operation recoverably
active. Its active snapshot durably retains the refusal, cancellation reason,
and `.refused` phase for registry-lifetime observability; a later correct direct
settlement or a new cancellation attempt can recover without releasing
the lane prematurely.

Revisioned active snapshots expose admission, full identity, lane and role,
context, owning subsystem, awaited result, lifecycle phase, admission/start/
last-attributable-progress timing, deadline, last accepted event attribution,
cancellation availability/phase/reason, last cancellation-result refusal, and
exact Stop capability. Every terminal record retains the typed result and full
canonical identity, disposition and settlement time, lane and role, context and
its observable owner/awaited result, terminal phase, admission/start/progress
timing, deadline, last attribution, cancellation availability/phase/reason, and
the last cancellation-result refusal. The durable-append lane is coordination
only: the registry has no `EpisodeStore` or journal coupling, effect runner,
device adapter, application composition, or app caller.

EA-04 binds one registry lane to the pen-cap continuation only. Every other
runtime, controller, camera, Vision, persistence, simulator, Stop, and
cancellation owner remains unchanged; accepted point-selection evidence and
continuation cancellation now belong to the episode runtime rather than a
parallel `OperatorWorkspace` task/closure path.

`PlotterEpisodeRuntime` depends inward only on `EpisodeCore`, `EpisodeRuntime`,
`PlotterEpisodeModel`, and `PlotterRuntime`, and is not exposed as a package
product. EA-04 gives it one application caller through
`PlotterPointSelectionRuntime`; replay and incident assembly remain unbound.
`PlotterIntentGateway` evaluates each typed point-selection or Learning-mode
intent against the current projection and returns the accepted/refused event
payload without owning mutable state. `PlotterLearningIntentRules.modeAvailability`
is the one pure Learning-mode availability rule used by both the evaluator and
the immutable workspace presentation. `submitLearningModeChange` has no local
guard or early return: every operator click reaches the runtime, which commits
the typed acceptance or refusal event. A refusal remains visible with its
remedy; there is no silent no-op or second semantic owner.
`PlotterPointSelectionRuntime` is the
single actor owner for the point-selection `EpisodeStore`, journal projection,
optional `EpisodeRecordingStore`, exact frozen-frame map, and active pen-cap
continuation. Its FIFO mutation/publication boundary covers mutations and
projection reads; a concurrent mutation re-evaluates the state serialized by
the one ahead of it. `PointSelectionJournalPersistence` uses a macOS-14-compatible `OSAllocatedUnfairLock` compare-and-swap commit, and the episode model/runtime contain no `@unchecked Sendable` escape hatch.
Staging cancels the superseded request, archives the exact frame
when recording is available, commits its observation, and stages the typed
request. Production point ingress uses `ExactFramePointSubmissionBuilder.submission`:
it computes point geometry from the current viewport but carries authority
identity from the staged request's exact `request.presentationTransformRevision`,
and owns no admission authority.
The current request admits and a replaced request receives a typed runtime refusal.
Submission refuses stale identity, source, camera configuration,
frame hash/layout, presentation revision/bounds, or capacity before committing
anything. An accepted selection becomes publicly visible only after the select
event, point observation, and accepted operator-assertion evidence have all
committed; the FIFO projection boundary exposes no partial accepted state.
Runtime `PlotterPenCapPointSampler` owns exact-frame color sampling, and an
accepted pen-cap result carries that exact `DisplayedFrame` to the app adapter.

The runtime registers the accepted pen-cap continuation in the registry's
exclusive exact-workflow lane with its full operation identity, move-only
permit, Stop capability, and operation-bound completion. Learning Off is one
typed accepted intent only when the active work is the EA-04-owned exact
selection/pen-cap continuation: cancellation settles that owner, clears the
selection and commits Off only after the final exact-owner decision. Unrelated
calibration, exploration, motion, or exercise-attempt work receives the typed
refusal from `PlotterLearningIntentRules.modeAvailability`.
`PlotterPointSelectionRuntime.setLearningEnabled` accepts a typed `PlotterLearningActivityFactProviding` and obtains a fresh fact inside the FIFO boundary for initial evaluation.
It reacquires a fresh fact after exact continuation cancellation before reevaluation.
`OperatorWorkspace` passes the provider through the Task hop rather than capturing a fact before it.
`PlotterPointSelectionActivityOwner(selectionID: PlotterPointSelectionID, exerciseAttemptID: UUID)` binds the exact selection and attempt identity across those initial and post-suspension evaluations.
The same item and selection with a successor attempt token typed-refuses, and `OperatorWorkspace` rechecks the exact attempt identity before post-runtime attempt cancellation.
For a latched continuation, the FIFO remains held while `setLearningEnabled` latches that owner, awaits `registry.stop`, and privately clears the runtime continuation handle without publishing episode-state mutation.
It reacquires the fresh typed fact and reevaluates the bound exact owner against the still-private `.continuing` plus `continuationIsActive` state.
An admitted Off event clears selection; a successor or unrelated refusal publishes continuation inactive and then its final typed refusal behind the same boundary, preserving transaction-complete public state and nonrevival.
For that continuation path, `setLearningEnabled` returns only after registry settlement and final publication; no replacement settlement helper, poll, sleep, or state exists.
Tests use the immutable returned/current projection and observable continuation-port state.
The model exception independently requires `.collecting` or `.continuing` with `continuationIsActive`, and `OperatorWorkspace` emits the owner only in those phases.
Retained `.accepted` Pen first-question/discovery and sparse batch/calibration attempts typed-refuse even with a matching supplied owner. Undo, clear, cancel, sparse four-point acceptance, and
runtime shutdown also stay inside this one owner. Recording failure remains a
visible nonblocking diagnostic and never promotes evidence or relaxes exact
provenance.

The `EpisodeRecordingStore` actor owns one recording document and retains a contiguous sequence and
nonregressing monotonic offsets. Controller invocation and completion are
separate typed records for open, close, input discard, raw write, and timed read;
parameters, exact read chunks, partial counts, typed failures, and completion
matching remain explicit. Camera start, reconfiguration, stop, and failure
lifecycle records remain separate from exact frame references, and a frame is
admitted only for its exact active source/configuration identity.
Open and close failures require zero partial bytes and no read chunks. Discard
failure accepts truthful nonnegative partial byte progress but no read chunks;
write failure is bounded by the invocation bytes and has no read chunks; timed
read failure binds its byte count to the exact partial chunks and invocation
maximum. These constraints validate transcript shape only and do not promote a
failure record to controller settlement or physical evidence.

The store opens only a pre-provisioned, owner-matching recording directory. Its
root file descriptor pins device and inode identity, so replacement of the path
after admission cannot redirect manifest, lock, or frame writes. A durable
initialization marker binds recording ID, schema revision, and the explicit
maximum unique-frame count and byte budget. The sorted-key `Codable` manifest
envelope separately binds format version and payload checksum. Reopen refuses
unsupported format, schema/identity/retention mismatch, corrupt envelope or
payload, sequence or time regression, unsafe files, and missing initialized
manifest state without silently creating or repairing diagnostic facts.

Manifest replacement uses one in-process lock per pinned directory identity and
a kernel `fcntl` lock across processes. Under that lock it compares the durable
document with the expected base, writes a mode-0600 same-directory temporary
file through partial-write/`EINTR` handling, performs `F_FULLFSYNC`, atomically
renames, and synchronizes the parent directory. A stale independent store cannot
overwrite an accepted successor. A post-rename synchronization uncertainty is
typed and leaves the actor unable to mutate until reopen; the snapshot says
whether the candidate was observed rather than inventing a durable outcome.
The cross-process CAS contract is tested with explicit child-ready and
immediately-before-kernel-lock commit-boundary handshakes, so the external
successor wins deterministically before the store compares its expected base.
Test-only process and commit-attempt wait helpers have bounded completion and
terminate or kill an overdue child. A separate non-cooperative attempt proves
that timeout reporting does not await cancellation cooperation from the loser.

Exact frame bytes are named by verified SHA-256 under the pinned recording
directory. Equal content is idempotent, while missing, truncated, byte-count-
mismatched, hash-mismatched, unreadable, symbolic-link, ownership, and external-
hard-link conditions remain distinct typed outcomes. The manifest publishes a
frame reference only after one locked transaction compares the durable manifest
with its expected base, accounts the complete artifact inventory, durably
installs and verifies the frame, and then atomically replaces and synchronizes
the manifest. A CAS loser therefore installs no artifact; a definite manifest
failure after frame installation may leave an unreferenced orphan, and
post-rename uncertainty retains its explicit durability state.

Retention charges every durable frames-directory entry by one count and its
nonnegative filesystem byte length, including valid unreferenced artifacts and
unrecognized, unreadable, unsafe, hash-mismatched, or otherwise orphaned files.
It performs no automatic artifact deletion. Count and byte arithmetic is checked
and fail-closed: aggregate or proposed overflow refuses mutation, including
duplicate-content admission, with typed `frameRetentionAccountingOverflow`
before any new artifact or manifest successor is published. Snapshot inspection
reports the same accounting overflow as typed incompleteness. Independently, a
checksum-valid manifest whose referenced-frame byte sum overflows is corrupt
recording state and cannot reopen. The pinned policy refuses admission beyond
either limit and never relabels deletion as completeness. Closing ends admission
but separately reports unmatched controller invocations, unfinished camera
lifetimes, incomplete `RunLedger` ranges or integrity, referenced-frame defects,
and valid or invalid unreferenced durable artifacts.

Optional typed episode, intent-request, effect, correlation, and environment
identities are diagnostic provenance only. A typed `RunLedger` reference records
its sequence range, integrity, and completeness; the new service never opens or
mutates that ledger. It is not an `EpisodeJournal`, replay engine, observation,
measurement, evidence owner, effect port, or Stop/cancellation owner.
`PlotterEpisodeRuntimeTests` is the sole current consumer; its focused recording
suite contains 36 adversarial tests, including deterministic cross-process CAS
handshakes and bounded/non-cooperative timeout proofs. The removed
`StartupFrameRecorder` and its sole high-level test had no production caller;
there is no compatibility recorder or current app camera-sample writer.

The same internal target now owns the unbound `PlotterEpisodeReplayService`.
Its sealed `PlotterEpisodeReplayExecutableDescriptor` is instantiated only by
the private `PlotterEpisodeReplayExecutableAdapter`; the replay API accepts no
caller-supplied descriptor or executable revision labels. That concrete adapter
owns the domain, evaluator, reducer, state/event/journal-schema, build,
and canonical-digest revision facts and declares that this executable does not
consume the deterministic seed. It compares the corresponding sealed executable
facts with manifest domain/evaluator/reducer/schema/build pins, and its
canonical-digest literal is additionally pinned to
`PlotterEpisodeCanonicalDigestV1.revision` before any prefix
reduction. Definition identity and revision are separately checked against the
supplied typed definition. Caller metadata therefore cannot manufacture
executable agreement.

`PlotterEpisodeRecordedEffectRevision` is a separate recording-side identity
fact with explicit `recordedIdentityOnlyNoExecutorValidation` authority. It
must cover emitted effects exactly once and is used to match full
episode/request/intent/effect-revision/correlation/environment identity across
progress, result, provenance, and first-terminal ordering. Because replay has
no executor, that value does not certify an effect-executor revision.

The service reduces every recorded journal prefix through the production
reducer and private adapter, independently verifies state with
`PlotterEpisodeCanonicalDigestV1`, and checks each committed decision against
caller-supplied recorded candidate intents and capability facts. Manifest,
revision, sequence, stored-digest, independent-digest, effect-identity, or
decision disagreement is a typed refusal. Effect-lifecycle-invalid prefixes
fail closed and are not published as accepted replay prefixes. Effects remain inert values: replay
executes none, restores no permit, and gives each prefix a never-resume
disposition. Started-unsettled progress, controller invocation, or camera
lifecycle evidence is conservatively reported as a possible physical effect
without claiming that one occurred.

Recording reconstruction keeps controller, camera, `RunLedger`, and global
completeness distinct and requires exact episode/request/intent/effect,
correlation, and environment provenance for recorded starts. Start attribution
requires exactly one complete available operation-bound provenance tuple;
absent, partial, foreign, or ambiguous tuples remain unattributed. Preserved source
entries keep controller transcript completeness, byte/order integrity, and
operation provenance independently inspectable. Missing or corrupt camera bytes
remain typed incompleteness. A `RunLedger` reference remains diagnostic-only
metadata; replay does not open, decode, mutate, or promote it.

Controller replay operates on typed transcript invocations, completions, and
results. It provides exact unperturbed transcript replay. The only admitted
perturbations are causality-preserving legal read fragmentation, completion
delay, timeout, and cancellation, with recorded source bytes, availability,
deadlines, ordering, writes, and operation provenance preserved. Exact replay
refuses nil or empty controller source. The service validates the complete
source schedule before applying any transform, refuses fragmentation when read
traffic is absent, and refuses completion delay for a non-read invocation.
Delay combined with timeout or
cancellation for one invocation is refused independent of declaration order.
Delay enforces the timed-read deadline for successful and failed completions;
completion delay retimes the completion and causal suffix, including embedded
read chunks, with checked overflow. Terminal replacement preserves its exact
boundary and retimes that causal suffix and chunks with checked underflow.
After every candidate transformation, `controllerReplayScheduleViolation`
validates the complete schedule across all outstanding invocations: source and
replay ordering, invocation-before-chunk/completion, unique completion,
operation/result shape, partial counts, maximum bytes, and each timed-read
deadline. A transform targeting invocation A therefore cannot push overlapping
invocation B beyond B's deadline or move B's traffic before B's invocation;
`invalidTransformedSchedule` refuses the complete scenario and returns the
unchanged source schedule. Invalid fragmentation, mismatched invocation or
completion, conflicting terminal perturbations, overflow/underflow, non-read or
unsuccessful-read terminal traffic, and all other causal violations are refused.
This service is not a `MachineLink`. The execution plan's `ReplayMachineLink`
remains a target seam; no current package has installed that conformance or a
production replay owner. No product or application caller depends on this
service, and no current effect, controller, camera, operation, Stop, recording,
or app authority moves to it. Installing the target seam would require separate
named-package authority rather than inference from this Foundation service.

The same internal target now also owns one pure, unbound
`PlotterIncidentPackageAssembler`. Its caller supplies a typed
`PlotterIncidentPackageSource`; the service does not discover or open current
state. That source binds one manifest, semantic journal, source-reported
recording snapshot, observations, measurements, evidence decisions, outcomes,
assessments, runtime state, UI projection, all declared current-owner domains,
exact artifact-status facts, sensitive-frame identities, and unresolved
ambiguities. The package embeds the snapshot as `sourceReportedRecording` and
always emits `sourceSnapshotNotRevalidated` in `recordingSourceFacts`. It also
records source-reported open state, durability uncertainty, completeness issues,
and missing optional episode or environment provenance as diagnostic facts.

Assembly validates cross-source episode/manifest/revision identity, exact
journal semantic values, independent runtime-state digest truth, package-level
evidence/outcome/assessment closure, artifact-reference/status closure, complete
current-owner domain coverage, and ambiguity identity. It refuses an explicit
foreign episode ID in any recording entry while retaining missing optional
provenance as diagnostic truth. Assessment evidence is restricted to evidence
accepted by its referenced outcome. Accepted observation evidence requires an
`inputEnvironment` equal to its referenced observation environment; accepted
measurement evidence requires that environment to equal every source
observation environment. This preserves LIVE/SIMULATED evidence truth without
moving evidence-acceptance authority. Every `possibleInk` or `unclear`
measurement requires one exact typed linked unresolved possible-ink ambiguity;
missing, duplicate, foreign, and spurious links are refused.

The assembler never certifies or revalidates recording format, controller,
camera, lifecycle, frame descriptors, frame layout, frame hashes, frame paths,
duplicate store records, `RunLedger`, or store completeness truth. Recording,
frame, artifact, runtime/UI, and possible-ink incompleteness stays typed and
visible. It cannot become proof of availability, physical effect, observed ink,
or store-owned recording integrity.

`PlotterIncidentPackageBudget` bounds each collection, total items, embedded
recording bytes, referenced-frame bytes, and encoded payload bytes with checked
arithmetic. `maximumReferencedFrameByteCount` independently bounds checked
referenced-frame bytes. Limit excess refuses instead of truncating. Frame bytes
are never embedded. The package checks only incident-package sensitive-ID
linkage, checked referenced-byte accounting, and the independent limit. Frame
references, descriptors, availability diagnostics, and byte/count facts remain
source-reported rather than frame-store validation; their disposition is
reference-only or sensitive-reference-only. A successful export is deterministic format-versioned
sorted-key canonical JSON with exact byte count and SHA-256. Canonical envelope
verification returns `envelopeIntegrityConfirmed` only after the envelope and
canonical encoding, bounds, digest, decoded package version, and exact
deterministic reassembly agree. The outcome proves only deterministic versioned
byte integrity and canonical reassembly, not recording or domain completeness.

The assembler returns bytes to its caller and owns no artifact store, export
destination, filesystem adapter, redaction workflow, UI, application ingress,
device port, effect execution, operation/permit/Stop owner, recording or replay
owner, semantic journal owner, evidence acceptance, or product authority.
The focused incident suite contains 23 tests of the lower assembler.

EA-09 adds one nominal actor `PlotterIncidentPackageUIService` around that sole
assembler; it does not add another/source assembler. A real assembly request
must carry the complete exact `PlotterIncidentPackageUISourceIdentity`, and its
provider must return a matching complete source. The request owns one
explicitly bounded newest-value stream; its terminal update binds the exact
request, source identity, and completed/refused result so held progress cannot
create an unbounded subscriber map or detach terminal identity. The values-only
result exposes format version, canonical encoding, exact byte count and SHA-256,
typed refusal/remedy, the deliberately limited `canonicalEnvelopeOnly`
integrity scope, and `physicalEvidenceClaimed == false`. It exposes no package
bytes and stores or exports nothing.

Production has no complete incident-source provider or source-identity owner.
The App therefore binds only the distinct ID-only `startUnavailable` lifecycle,
whose bounded request stream terminates with typed
`.noCompleteSourceProvider`/`.provideCompleteSource`. It never supplies a dummy
manifest/build/digest identity, invokes assembly, fabricates source
completeness, or claims physical evidence. The App reference is presentation
composition only; the lower assembler remains unbound and the service owns no
backend, device, recording, evidence, or domain authority.

`PlotterEpisodeModel` depends only on `EpisodeCore` and `PlotterModel` and is
not a package product. Its production bindings include the point-selection and
manual-motion runtimes plus the values-only `PlotterUI` compiler boundary; UI
dependency moves no runtime or effect authority. It binds concrete Plotter
definition/manifest revisions, seven exhaustive semantic intent families,
decision-relevant state, events, typed effects and results, observations,
measurements, evidence, outcomes, assessments, versioned capability facts,
immutable availability/projections, and pure scoped evaluator/reducer behavior.
Committed progress values carry episode/request/intent/effect identity, effect
revision, environment, typed lane and owning subsystem, phase, attributable
timestamps and deadline, awaited result, and cancellation state. Only their
committed event updates active progress; a committed result clears it and leaves
the typed terminal result and disposition available in state and projection.
Observation IDs carried by that result remain references: only a separately
committed `observationRecorded` event establishes observation membership and
semantic admission.

`PlotterEpisodeModel` also owns `PlotterEpisodeCanonicalDigestV1`. It computes
one sorted-key canonical digest over replay-relevant state while excluding the
stored `canonicalDigest` field itself, preventing a copied stored value from
self-validating. The digest is model truth for deterministic replay comparison;
it does not execute an effect or confer persistence, device, evidence, or
application authority.

It contains no runtime or device adapter/port, persistence, UI, application
composition, effect permit, runtime operation or lane owner, task, actor, or
asynchronous escape hatch. `PlotterModel` retains geometry and planning authority, while the
current `PlotterRuntime`, controller, camera, Vision, artifact persistence, and
simulator owners remain unchanged. EA-04 transfers only typed point-selection
state, intent decisions, accepted observations/evidence, and Learning-mode
cancellation into this model/runtime path.

## Runtime owners

`MachineController` is the only selected serial owner. It parses GRBL, admits
typed requests, serializes commands, proves settlement, and latches sticky
ambiguity. It also owns the explicit typed alarm-clear operation: admission
requires current typed Alarm status with no X/Y/Z `Pn` input asserted, then
rechecks realtime status immediately before any `$X` write. A physical limit or
unknown current input state refuses without unlock transmission. `$X`
acknowledgement is recorded separately from motion outcomes, and Motion
authorization remains inactive. `RunInterpreter` serializes alarm clearing with
every other logical operation. `OperatorWorkspace` projects limit-input evidence
and alarm-unlock readiness separately, then follows an acknowledged clear with a
fresh full passive probe before projecting a responsive session; Connect never
clears an alarm implicitly.

The sole `MachineLink` transport contract now returns a
`MachineLinkOpenReceipt`, `MachineLinkDiscardReceipt`,
`MachineLinkWriteReceipt`, or `MachineLinkReadReceipt` from each successful
operation, while `close()` can report failure. Open facts use the
transport-discriminated `MachineLinkAppliedConfiguration`: a BSD link reports
the exact endpoint, input/output baud, data bits, stop bits, parity, flow
control, local-mode, and receiver settings read back after application through
`MachineLinkBSDSerialAppliedConfiguration`; a simulated link reports only its
simulated identity and never fabricates serial settings. Discard and write
receipts report exact byte counts. A read receipt owns the exact returned bytes
and the link-boundary `receivedAtMonotonicNanoseconds: UInt64` sampled from that
link's `RuntimeClock`.

`MachineLinkError.discardFailed`, `.writeFailed`, and `.readFailed` retain
operation-specific partial progress and a `MachineLinkTransferFailureReason`
instead of inferring zero transfer after failure. Existing specific write
timeout and cancellation errors retain their exact written/total counts.
The production-used `BSDPendingInputDiscarder` observes one pending-input byte
count and must drain that complete snapshot before success. Its read size and
`EINTR` retries are bounded; every zero-progress or partial failure retains the
exact discarded count and observed total, while only snapshot acquisition
failure has an unknown total. BSD applied-configuration and discard regression
tests exercise the production termios mapper and discard core directly.
`BSDSerialLink`, `SimulatedGRBLLink`, `BlockingMachineLink`, and controller/test
forwarders preserve these receipts and failures through the same protocol; no
sibling port or default protocol implementation exists. These transport facts
do not admit motion, prove settlement, create a controller transcript, or move
`MachineController`/`RunInterpreter` safety and operation authority. EA-06 now
installs one transparent `RecordingMachineLink` around the sole production BSD
link at `PersistentMachineSession` composition; the decorator reports exact
transport facts only to the currently attached operation-bound recorder and
returns the native receipts and failures unchanged.

`CameraCapture` owns device discovery, authorization, selection, capture
sessions, exact stamped frames, and scoped preview publication holds. A hold
does not stop raw capture. Exact workflow capture materializes the newest raw
frame with `.returnOnly`; that private value does not enter preview or automatic
analysis until its owning workflow explicitly publishes the validated selection.
Publication is active-generation checked and idempotent. `VisionWorker` owns
bounded inference and returns measurements; it never supplies motion or click
authority.

`CameraSourceSession` owns automatic-analysis configuration and exclusive Vision
leases. Reapplying identical cadence/features, analysis region, or cap color is
a no-op; it does not restart the pipeline or its frame subscription. Semantic
pipeline revisions are pushed to `OperatorWorkspace`. Video Settings counters
and lifecycle statistics are pull-only diagnostics and do not invalidate the
Learning presentation. One caller-supplied exact workflow batch owns one lease
from preview hold through automatic-analysis restoration, including failure or
cancellation settlement.

`NativeSpeechAnnouncer` owns AVFoundation speech synthesis, identity-bound
queueing, bounded timeout/completion, and shutdown cancellation. It is
output-only: `OperatorWorkspace.announcementActions` currently invokes it for
advisory Learning cues, records the typed result, and proceeds through the
button/controller authority even when speech fails. The target plan dispositions
that application-level effect path in `EA-10G` while retaining native synthesis
below the episode runtime.

`OverlayPreferenceState` contains only the persistent operator selections
`penCap` and `armatureEnvelope`. `SceneFeatureSet` expands the armature dependency
to pen-cap computation and requests no unrelated kernel. Typed
`OverlayLayerStatus` values keep run state, reason, cadence, region, frame, and
age out of preference. `OverlayResultChannels` owns independent scene, workflow,
and simulation results. `OverlayPresentationComposer` is pure and renders only
source/configuration/frame-exact geometry, so one producer cannot clear another.
If the displayed frame still matches the completed scene result, the composer
retains that geometry and its completed typed status while the next frame is
analyzing, and swaps only after a new completed exact-frame result is installed.

`OperatorWorkspace` maps the selected scene features to one newest-only
automatic-analysis request and one selected cadence. Video Settings may lock the
current zoomed/panned camera-pixel rectangle as the generic scene-analysis
region. `CameraSourceSession` passes that region into
`PlotterSceneAnalysisPipeline`; `VisionWorker` scans only requested pen-cap
pixels and derives the armature envelope from an accepted cap. Full-frame lock
is canonicalized to default analysis, and cap component size is evaluated against
whole-frame policy. Specialized calibration and observed-trial exact-frame
measurements retain independent typed regions.

`ActionSurfaceViewportState` owns the current exact presentation pixel
rectangle. `ActionSurfaceViewportContext.fittedRegion` is only a target for an
explicit Fit or zoom action. Compatible context reconciliation snapshots and
retains the effective rectangle even when Exercise 1.3 replaces the fitted target.
`VideoAnalysisRegionLock` is a separate policy copy owned by
`OperatorWorkspace`; Exercise 1.3 does not rewrite it. Source or camera-
configuration incompatibility remains the viewport reset seam.

`PenCapAppearanceSelection` is the only persisted LIVE recognition input. The
first Exercise 1.1 action freezes an exact frame and issues a
`penCapAppearance` point-selection request. Runtime
`PlotterPenCapPointSampler` maps the
operator's cap-body click to a clipped 9 x 9 RGBA/BGRA neighborhood, filters out
gray, white, dark, and otherwise insufficiently chromatic pixels, then records
the channel-wise median RGB color. The stored selection binds that color to the
click point, frame ID and hash, source, camera configuration, dimensions, pixel
format, sample counts, and sampler revision. `CameraSourceSession` applies the
accepted color to both newest-only scene analysis and exclusive Exercise 1.3
inspection. There is no `ColorPicker` owner or mutable color preference seam.

`ExactWorkflowVisionOwner` is the typed app-level identity for the one active
exact inspection: pen-cap appearance, camera calibration, sparse-tip
calibration, observed Drawing Trial, or Drawing Studio. It is projected
separately from automatic overlay analysis. Supervised Pen-Up travel does not
acquire an exact Vision lease and therefore never claims that Vision owns
processing or that preview is held merely because motion is active.

`OperatorWorkspace` is the single `@Observable` application owner. It composes
controller/camera actors through typed actions, owns Learning Path attempts,
commits the retained artifact dependency graph, routes view intent, and reads
current copied state into `PlotterUICompilerInput` and publishes one immutable
`PlotterUIProjection`. For EA-04 it owns a
reference to `PlotterPointSelectionRuntime`, copies its immutable
`PlotterEpisodeProjection` for presentation, and adapts an accepted pen-cap
sample plus its runtime-returned exact `DisplayedFrame` to the existing
`PenCapAppearanceSelection` and camera/Vision
reconfiguration owners. It does not own a second point-selection state machine,
accepted-evidence path, Learning-mode toggle closure, or continuation task. Its
Learning presentation is an immutable projection of copied facts, not a
decision or mutation boundary. SwiftUI semantic actions submit only through the
current aggregate projection and production `PlotterUIIntentSink`; there is no
remaining direct `UI.learningModePresentation` mutation route.
The deleted `PointSelectionPresentationContext` cannot copy a request or
re-decide admission. `frozenPointSelectionFrame` holds pixels for UI
presentation only, and `pendingToolContactEvidence` remains adapter data for
the retained sparse-tip calibration fit. The app cancellation helper is async
and awaits the runtime owner; the old Task-returning helper is absent.
The deleted `submitCurrentPenCapPoint` and `OperatorWorkspace.awaitPenCapAcceptedClickTransition` helpers cannot recreate semantic ingress or test-only transition authority; focused tests use generic submissions and bounded observable-state waits.
The deleted `awaitContinuationSettlement` task-owner/polling helper has no replacement helper, poll, sleep, or state.

For EA-06, `OperatorWorkspace` holds one `PlotterManualMotionRuntime` reference
and one copied `PlotterManualMotionRuntimeSnapshot`; it does not own manual
semantic admission, an active manual operation, a cancellation task, a mode-
specific executor, or a second terminal result. `manualMotionEpisodePresentation`
derives active intent, exact Stop capability, actionable remedies, Pen/mode text,
and recording diagnostics from that snapshot plus current controller/simulator
facts. The editable `ManualMotionDraft` and
`manualMotionDraftUnavailableReason` validate only unsubmitted numeric UI input.
`submitManualJog`, `submitManualPen`, and `requestManualMotionStop` are typed app
adapters into the runtime; they do not re-decide controller or Learning policy.
`motionRequestStatusPresentation` reads the snapshot's exact active manual
operation, so an episode-owned effect cannot be omitted by retired workspace
request flags.

`PlotterManualMotionRuntime` is the single actor owner for its
`EpisodeStore<PlotterEpisodeReducer,
EpisodeJournalPersistenceAdapter<PlotterEpisodeEventPayload>>`,
`PlotterIntentGateway`, machine-lane `PlotterOperationRegistry`, active operation
identity, public `PlotterManualMotionStopCapabilityID`, and copied projection.
Production creates the journal directory as required authority and fails
closed before app composition if that durable journal cannot be initialized;
the optional controller-recording store may instead fail open with a visible
diagnostic. Runtime snapshots expose the exact loaded journal, its file URL and
digest-bearing `EpisodeArtifactReference`, the optional recording snapshot, and
one typed `PlotterIncidentSourceArtifactReferences` value carrying recording
durability/completeness separately from journal truth.

One FIFO mutation/publication boundary surrounds each admission or cancellation
journal commit, its pre-state read and failure snapshot, terminal
observation/result publication, and snapshot read. The boundary is deliberately
not held across controller cancellation or settlement suspension. While the
exact active owner remains, `submit` refuses a concurrent manual request as
transiently busy from the transaction-complete snapshot before
`PlotterIntentGateway` evaluation. It writes no successor refusal event, effect,
or revision that could terminalize or clear the active owner.

A Stop capability names only the active jog that issued it. The first caller
installs one exact public transaction. Before the first journal suspension,
`PlotterOperationRegistry.beginStop` latches the original nominal
`ManualMotionOperationHandle`; the runtime commits `requested`, and
`observeStop` atomically marks the same transaction `issuingCancellation`
before invoking cancellation exactly once. The runtime then commits `observed`,
calls `beginStopSettlement`, commits `settling`, and only then calls
`finishStop` to await that same handle. Duplicates join continuations and all
receive the same transaction result and post-terminal snapshot only after
`publishTerminalIfCurrent` completes.

If the requested append fails before `observeStop`, registry shutdown closes
admission and atomically takes over that same staged owner and retained handle.
It marks the transaction `issuingCancellation`, invokes cancellation exactly
once, advances the same owner through observed and settling, and awaits and
settles the original handle. An already issuing, observed, settling, or
awaiting transaction is joined rather than cancelled again. The takeover has no
journal prerequisite and creates no second cancellation, settlement, or
publication authority.

If shutdown closes admission after registry ownership exists but before native
start, `ManualMotionOperationHandle` records one identity-bound
`cancelledBeforeStart` result, retires that exact owner, and makes the later
`start()` inert. The LIVE and SIMULATED adapters therefore receive zero native
start or cancellation invocations. At the observed or settling Stop phases,
registry shutdown instead completes the same staged transaction as
`settledByShutdown`; the original public Stop transaction remains the only
journal/recovery publisher, duplicate callers stay joined, and cancellation and
settlement each happen exactly once.

Operator-authorized Option A closes the remaining post-progress/pre-activation
race inside `PlotterManualMotionRuntime`. `shutdown()` synchronously sets its
runtime-owned `shutdownIsLatched` before the sole `registry.shutdown()` await
and publishes completion to waiters only after retaining every registry
terminal. After `recordProgress` accepts the exact identity and before assigning
`active`, `submit` rechecks the latch, awaits that same shutdown completion,
consumes the retained exact terminal disposition, and calls
`publishPrestartTerminalSubmission`. Its early return precedes both runtime
active-owner installation and `ManualMotionOperationHandle.start()`, so the
result is one typed cancelled effect publication with no native start/cancel and
no residual registry or runtime owner.

`PendingManualMotionStop` retains the typed registry transaction, exact public
capability, publication-recovery capability, and current stage. A failed
Stop-stage append returns `publicationPending` without advancing that stage.
`PendingManualMotionTerminalPublication` similarly retains the normalized
owner result, exact observations, result payload, and
`nextObservationIndex`; append failure leaves the exact owner active and emits
a `PlotterManualMotionTerminalPublicationIssue` with typed stage and recovery
capability. `recoverTerminalPublication` resumes only that retained cursor. It
cannot choose an outcome, cancel, settle, publish twice, or grant authority.
When shutdown settles an owner while the journal is still unavailable, it
reuses the pending Stop recovery capability for that same owner and terminal
publication cursor; the capability remains actionable after shutdown.
The transaction-complete result is cached only after terminal publication and
only until successor admission clears it before launch, so the predecessor is
then stale and cannot stop the successor. A mismatched capability never joins.
Drawing Stop settles only with controller Idle and Pen Up; unresolved
settlement remains ambiguous with possible ink. Manual Pen effects have no Stop
capability.

`manualMotionPublicationRecoveryPresentation` projects the issue's exact
`PlotterManualMotionPublicationRecoveryCapabilityID` with a jog-, drawing-, Pen
Up-, or Pen Down-specific title and remedy. While it exists, every manual effect
control receives that remedy, `stopAction` is absent, and
`motionRequestStatusPresentation` reports needs-attention. Submission and Stop
adapters refuse to issue work; `recoverManualMotionPublication` rejects a stale
capability and passes only the matching value to `recoverTerminalPublication`.
Installing the returned snapshot clears `machineError` only when it still
equals the matching publication remedy. Recovery cannot re-admit, cancel,
settle, or reissue a native command, and availability returns only from the
recovered runtime projection.

`manualMotionEpisodePresentation` derives availability from the actual runtime
phase. When the terminal result is ambiguous,
`PlotterManualMotionEvidenceDispositionAction` binds the exact effect ID,
environment, observation ID, and possible-ink versus other-ambiguity
disposition. Every manual effect stays disabled until the exact current action
records explicit operator evidence; stale or mismatched actions are rejected.
That evidence mutation neither retries nor redraws, and it never reissues,
cancels, or settles controller work.

The package-only typed Stop-publication gate can pause deterministically after
registry settlement and before episode publication, and signals when a
duplicate joins. It cannot choose an outcome, cancel, publish, or grant
authority, and its tests require no sleeps or polling.

`PlotterManualMotionComposition` supplies the LIVE adapter and creates one
`PlotterManualMotionRuntimeComposition` containing the manual runtime, lower
simulator runtime, and shared `PlotterCausalSimulatorEffectAdapter` for
`.simulated`. `OperatorWorkspace` receives that composition and retained
workflows use the exact same adapter authority as the manual runtime. LIVE converts typed manual requests to the existing native
`RelativeJogRequest`, `DrawingStrokeRequest`, Pen actuation, cancellation, and
fresh `RunInterpreterSnapshot` boundaries, so `MachineController` and
`RunInterpreter` retain connection, alarm, Motion, serialization, safety,
settlement, and ambiguity authority. The causal adapter uses
`SimulatedLearningRuntime` as nonphysical plant/truth storage and publishes only
`.simulated` observations; any episode-attributed typed effect result is also
`.simulated`, while retained work has nil `effectResult`. It cannot promote
simulator state to LIVE evidence. The composition's neutral
`beginNativeRelativeMotion` and `settleNativePenCommand` functions merely
centralize lower controller calls still used by retained Learning, Drawing, and
supervised-travel owners. They admit no manual episode intent and reserve no
EA-07, EA-08, EA-10, or controller-session authority.

`PlotterCausalSimulatorEffectAdapter` is the sole effect-capable simulator seam.
Its public effect APIs are `admitManualJog`,
`admitRetainedWorkflowBoundary`, `admitRetainedWorkflowDrawing`,
`admitRetainedWorkflowTravel`, and `executeRetainedWorkflowPen`. Manual jog
binds typed episode intent/effect attribution. Retained work requires an exact
`EpisodeAuthorityID`, carries `.retainedWorkflow(owner:)`, returns nil
`effectResult`, and creates no fabricated intent, effect, or plan revision. The
adapter retains the raw `SimulatedLearningOperationID` as the immutable
Stop/cancel/shutdown and settlement identity.

Manual and retained Pen ingress enters the same adapter actor and observes the
same `activeOperation` reservation. If a predecessor is reserved, Pen ingress
returns `.operationAlreadyActive(predecessor.id)` with the current lower causal
truth before calling the lower Pen mutator; retained attribution has nil
`effectResult`, and lower Pen/truth is unchanged. With no active adapter
operation, package-only `SimulatedLearningRuntime.setPenPoseWithCausalTruth`
performs the admitted Pen mutation and captures `SimulatedLearningCausalTruth`
in one lower-runtime actor turn. The adapter therefore cannot pair a Pen
response with a separately sampled later plant/Pen/ink/frame state.

The adapter keeps that active owner reserved after lower-runtime settlement
until one actor-isolated `publishTerminalOutcome` atomically caches the
operation identity, disposition, observation, typed result when applicable,
final plant position, completed Boundary count, and immutable separated truth
snapshot. A successor refuses until that publication completes; it cannot
contaminate the predecessor's MPos, Pen, ink, or frame snapshot. The package-only
`PlotterCausalSimulatorTerminalPublicationGate` can pause exactly after lower
settlement and before publication for deterministic regression tests, but
cannot choose or alter an operation or outcome. A settled predecessor is
idempotent for its own ID and cannot cancel a successor. Mutable execution
pacing is a lock-backed suspension policy snapshotted before execution, not
effect authority.

`SimulatedLearningRuntime` has no public `beginManualJog`, `beginBoundary`, or
`beginDrawing` effect API. Its one package-scoped `admitCausalOperation` is
called only by the adapter; runtime execution, fault injection, plant mutation,
frame rendering, and raw operation settlement remain below the typed
environment seam. `OperatorWorkspace.executeSimulatedBoundaryMotion` and the
former App-local simulated adapter are absent. Retained Boundary, Drawing,
supervised-travel, sparse-tip, and Drawing Border owners invoke the production
adapter instead of an App-owned closure path until their later semantic
packages land.

The registry retains the nominal `ManualMotionOperationHandle`, which wraps the
adapter's typed operation and validates the exact owner-returned identity on
settlement; neither the registry nor the episode runtime stores an arbitrary
effect closure, replacement cancellation task, or `@unchecked Sendable`
escape. Native direct Pen admission returns an async nominal
`PenActuationOperation` from `RunInterpreter` with its owner-minted ID and
eventual `PenOutcome`. `LiveManualMotionOperation` retains and awaits that
handle, while its cancellation switch deliberately issues no Stop for Pen.

`PlotterIntentGateway` passes the selected environment into the evaluator.
Connection, Motion, pose, and `PlotterManualControllerFact` values are
environment-bound; missing or cross-environment facts fail closed. The manual
controller fact also binds current Pen/routing, active-operation, and
Pen-profile revision truth, while native owners still recheck fresh safety
immediately before I/O.

For LIVE recording, the runtime creates one
`PlotterManualMotionControllerRecorder` carrying the exact episode, intent,
effect, and environment provenance. `LiveManualMotionAdapter` attaches it to the
single `ManualMotionControllerRecordingRouter` before native launch, retains the
lease through natural or exact Stop/cancellation settlement, and detaches only
after terminal settlement. `PersistentMachineSession` creates the one canonical
BSD link through `MachineController.bsdSerialLink`, decorates it once with
`RecordingMachineLink`, and initializes the unchanged `MachineController` with
that link. There is no sibling controller, link, semantic ingress, retry owner,
or settlement path.

`RecordingMachineLink` maps successful open, discard, write, and read receipts,
receive-boundary timestamps, close failure, and exact partial discard/write/read
failure progress into the existing EA-05A controller transcript types. An
unsupported applied configuration or failed open without an applied receipt is
diagnostic-only, as are clock-origin and store-append failures; the adapter
never invents settings, counts, timestamps, or a completion. The decorator is
otherwise transparent. SIMULATED receives no controller recorder and therefore
cannot emit or claim LIVE controller traffic or physical behavior.
`controllerOpenParameters` also requires both applied BSD
`localModeEnabled` and `receiverEnabled` to be true. If either is false, the
decorator returns the native receipt unchanged, emits the lossless-mapping
diagnostic, and records neither a successful open invocation nor completion;
the true/true mapping remains unchanged.
`EpisodeRecordingStore` and `PlotterEpisodeReplayService` deliberately share
the same failure validator: discard accepts truthful nonnegative partial byte
progress but no read chunks, open/close require zero progress, writes remain
bounded by the invocation payload, and reads retain exact chunk/count rules.

The retained
LIVE/SIMULATED session accessor uses read/modify accessors, and related session
writes are batched into one semantic publication instead of copying and
reassigning the complete `LearningSessionState` for each field. It cannot
replace controller settlement or exact-frame provenance with UI state.
Restored-pose revalidation is admission policy for coordinate-dependent
Learning and Drawing actions only. Operator-authored manual jog and manual Pen
actions bypass Learning admission and use the Motion toggle plus the
controller's native connection, alarm, readiness, safety, and serialization
checks. The evaluator supplies an intent-specific Motion remedy: movement for a
jog and Pen actuation for a direct Pen request.

`PlotterUILearningFacts` and `PlotterUILearningActionabilityFacts` are
values-only. They contain copied milestones, retained Runtime state, current/
recovery inputs, availability facts, Stop identity, Pen/direction inputs, and
reset presence, not controller or camera actors, persistence capabilities, task
handles, mutating closures, or authority-changing methods.
`PlotterUILearningActionabilityCompiler` is the sole bounded owner of current
Learning owner, item status, action/Stop strips, availability, Pen adjustment,
direction selection, and reset reachability. Its immutable
`PlotterUILearningActionabilityProjection` is then consumed by
`PlotterUICompiler` with the complete bounded candidate set to form one
`PlotterUIProjection`. Identical copied inputs produce identical Learning
actionability, semantic actions, incident presentation, and diagnostics.

The compiler has explicit maxima for candidate visits, emitted actions,
Learning milestones, runtime revisions, diagnostics, and text. Reachability is
evaluated before emission; duplicate IDs and unsatisfied requirements become
bounded diagnostics or unavailable actions rather than an implicit dispatch
route. The aggregate projection enumerates every rendered semantic Learning,
point-selection, manual-motion, Stop/recovery/evidence, Drawing Draft/Run,
retained Learning/reset, Comparison review, and incident action. Each action
binds one `PlotterUIActionID`, exact `PlotterUIIntent`, current availability,
`PlotterUIRevision`, and relevant `PlotterUIRuntimeRevision` values.

SwiftUI can create a `PlotterUIRequest` only by selecting that exact available
member from the current projection. The production sink revalidates current
membership, bound intent equality, availability, UI revision, and all bound
runtime revisions before routing to the retained semantic owner. Arbitrary
action IDs, reconstructed action/intent pairs, unavailable actions, and stale
revisions receive typed refusal/remedy and perform no semantic mutation. This
presentation compiler cannot mutate a session, admit motion, persist, perform
I/O, accept an artifact, execute Stop, or replace controller/camera/Vision/
evidence authority.

The App's nominal `PlotterLearningActionabilityFactAdapter` only translates
retained Runtime facts and identities into copied PlotterUI facts and maps
canonical decisions to retained nominal action values. It does not choose
current owner, status, availability, action/Stop membership, Pen adjustment,
direction, or reset reachability. `PlotterLearningDetailedPresentationNormalizer`
receives the canonical actionability projection and renders summaries, labels,
and existing detailed presentation values cosmetically. `OperatorWorkspace`
uses the canonical action decisions both when constructing the aggregate
projection and when resolving the exact action before retained-owner dispatch.
The deleted App-owned status/completion/action-strip/Stop/sparse compilers and
raw-fact-to-retained-candidate/reachability builders have no compatibility
shadow. The EA-09 cutover checker enforces both exact App-wide zero literals and
a behavior/topology rule that refuses renamed or split App decision mappers
while allowing fact translation and cosmetic rendering.

`WorkbenchLayoutState` owns window-local pane visibility and Video Settings
presentation as one value. A permitted Show computes protected-pane collapse
and commits the complete next layout in one synchronous main-actor assignment;
there is no pending Show or `Task.yield()` phase. The same cached action-strip
projection supplies Exercise-pane protection, so a pane containing the active
Stop remains visible without performing another Learning projection.

LIVE and SIMULATED each retain one `LearningSessionState` value for later
Learning/run authority under that shared contract. Within each value,
compiler-enforced substates prevent invalid
cross-field combinations: one exercise-attempt lifecycle owns attempt identity,
item owner, and mode; the episode projection now owns staged point requests,
selected points, undo, clear, and accepted batches, while retained Learning
session state references the resulting calibration workflow; one Drawing Trial state owns
the complete trial payload, history, rollback, and rewind transitions. A
`PlotterDrawingDraftRuntime` now owns Drawing Studio catalog selection,
placement, immutable plan, preview, and paper assertion outside that aggregate.
One `PlotterDrawingRunRuntime` owns the separate EA-08B run projection,
exclusive admission, exact Stop, terminal/no-redraw truth, evidence publication,
and retained exact-frame review. It receives one immutable EA-08A plan and uses
nominal adapters without absorbing draft, MachineController, RunInterpreter,
camera, Vision, or archive internals.
Supervised
Learning Path travel and settlement carry typed `LearningMotionAction` identity;
display text is derived only by the presentation boundary.

`RunLedger` and workflow telemetry record diagnostics only. They do not replay
commands, restore owners, or promote artifacts. The existing persistent machine-
session owner retains at most 10 complete SQLite session groups and 50 MiB;
unknown files are not deleted. Camera startup records no PNG samples. Production
point selection creates one UUID recording directory at Application Support
`AdaptivePlotter/EpisodeRecordings/<recording UUID>` and opens the optional
episode store with a 64-unique-frame, 512 MiB bound. Startup and per-stage
recording failures are visible nonblocking diagnostics. That writer does not
change camera lifecycle or evidence acceptance, and recording diagnostics
cannot substitute for a committed episode observation or accepted evidence.
For accepted LIVE manual jog/drawing effects, `OperatorWorkspace` records
legacy-compatible accepted and terminal diagnostic telemetry under the typed
`EpisodeEffectID`. Its settlement observer reads the runtime projection and
does not admit, cancel, settle, or reinterpret the effect; typed runtime results
and native controller settlement remain authoritative.
Production manual motion instead opens EA-05A at the exact topology
`AdaptivePlotter/EpisodeArtifacts/<episode UUID>/controller-recording` with
schema `adaptive-plotter-manual-motion-v1`; opening failure and later recorder
failure remain visible in the manual projection without blocking safe manual
admission. The point-selection `EpisodeRecordings/<recording UUID>` path above
is a separate topology and is not reused for manual motion.
The runtime's episode journal records its typed effect lifecycle. The
operation-bound router forwards only exact MachineLink invocation/completion
pairs observed while that LIVE effect owns the lease; traffic before attachment
or after terminal detach remains unattributed, and a missing pair is never
reconstructed from a terminal observation. SIMULATED emits no LIVE controller
record. The resulting transcript is diagnostic provenance, not controller
authorization, independent settlement proof, or attended physical evidence.

Exercise 1.4 workflow telemetry schema v2 records one ordered semantic sequence:
batch admission, one completion event for each whole 16-chord circle, reveal,
and terminal disposition. Individual chords emit no workflow telemetry.
`RunInterpreter` forwards these non-authoritative facts to
`MachineController`'s existing ordered ledger-write tail. Enqueue is non-blocking
with respect to workflow progression; disconnect drains the tail, and encoding
or storage failure is reported diagnostically rather than becoming admission or
evidence authority.

`DrawingProgramCatalog` produces deterministic field-space geometry. A
`DrawingPlacement` is the only field-to-machine transform, and `DrawingPlanner`
is the only producer of content-addressed `ExecutionPlanRevision` values.
`DrawingRegionContainmentPolicy` owns axis-aligned closed-Boundary containment
under revision `acceptedBoundaryNumericalEpsilonV1`; its 1e-9 mm epsilon absorbs
floating-point residue without admitting physically meaningful geometry beyond
the accepted Boundary. `MachinePositionAcceptancePolicy` separately owns
revision `controllerQuantizedEuclideanV1`, the Euclidean residual metric, and
the 0.5 mm requested-pose settlement tolerance. Planning refuses geometry
outside its own epsilon and neither App nor Runtime clips it.
`RunInterpreter` owns a whole plan as one `RunOperation`, with
subordinate Pen-Up travel, pen actuation, finite drawing segments, Stop, and one
checkpoint per logical stroke. `PlannedDrawingObservation` operates only after
execution and returns exact-frame observed/residual evidence or a typed
rejection; it has no motion, resend, or promotion capability.

## Exercise 1.1 and manual controls

`OperatorWorkspace` starts Exercise 1.1 with **Identify Pen Cap** by staging a
typed `PlotterPointSelectionRequest` in `PlotterPointSelectionRuntime`.
`ActionSurface` sends only its inverse-transformed click submission through the click-only `PlotterPointSelectionIntentSink`; exact frame, source/configuration, pixel
layout, presentation revision, bounds, and capacity are rechecked by the
runtime gateway. Until the exact-frame cap-body click is accepted and its
observation plus operator-assertion evidence are committed, no pen-position
question is opened and no pen request is issued. Refusal leaves the typed
request pending with its remedy. Cap identification itself does not require a controller
session or Motion. After acceptance, the first question remains active; its
**Confirm Pen Up** action and servo slider are dependency-blocked until connection and
Motion exist, while the external controller toolbar remains operable. The
exercise's Up and Down sliders then issue typed value-bearing pen requests;
**Confirm Pen Up** or **Confirm Pen Down** retains the displayed value in the current setting and the existing
attempt evidence. `MachineController`
serializes the requested value and settlement under its existing pen-operation
ownership. There is no parallel servo-calibration owner, checkpoint, or
artifact graph.

On an automatic Pen Down or Pen Up, `DiscoveryTransaction` applies the settled
controller outcome and presents the immediately following question as one
validated transaction transition. `OperatorWorkspace` publishes the resulting
transaction and command evidence in one session mutation and one semantic
revision, so the next action strip is not delayed behind an intermediate
post-settlement projection.

`PlotterUICompiler` derives current Learning progression from copied milestone
facts and the first unmet dependency. Recovery selection is presentation state
for the owning review row; it does not redirect progression. The persisted
`PenCapAppearanceSelection` is loaded by `OperatorWorkspace`; its color is then
applied by `CameraSourceSession`. Before it exists, LIVE Pen cap and Armature
envelope statuses are Unavailable while their operator-owned overlay
preferences remain unchanged. An accepted replacement clears stale scene
geometry and admits only newly analyzed frames without becoming calibration
authority.

The workbench presents Learning mode as copied values from
`PlotterLearningIntentRules.modeAvailability`. The button stays invokable when
that rule predicts refusal, displays its remedy, and submits every click through
`PlotterLearningModeIntentSink`; there is no local guard or silent no-op. The
runtime commits the accepted or refused event. The FIFO-held runtime latches the
exact selection/attempt owner, awaits registry settlement, privately clears its
continuation handle, and reevaluates a fresh activity fact against the unchanged
continuing episode state. Accepted Off clears selection atomically; successor
or unrelated work publishes inactive continuation plus final refusal behind the
same boundary. `OperatorWorkspace` captures no pre-Task activity fact and
rechecks the exact owner before post-runtime cancellation. Retained accepted Pen
discovery and sparse calibration states expose no cancellable owner. Camera capture,
`CameraSourceSession`, Vision configuration, persisted appearance artifacts,
controller/device operations, and calibration acceptance retain their existing
owners.

Manual X distance, Y distance, and feed fields initialize to 50 mm, 50 mm, and
500 mm/min while remaining editable as `ManualMotionDraft`. On submission the
app constructs `PlotterJogRequest` or `PlotterPenActuationRequest` and sends one
`PlotterManualMotionIntent` through the runtime gateway with current LIVE or
SIMULATED capability facts. Manual direction routing depends on the current
controller-commanded Pen state, not Learning Path completion or restored-pose
applicability. Known Down selects `.drawingStroke`, known Up selects
`.relativeTravel`, and unknown selects `.possibleInk`; unknown pose is therefore
preserved as possible-ink truth rather than treated as Pen Up. A restored
durable session may leave coordinate-dependent Learning and Drawing gated until
fresh cap revalidation, but it does not gate operator-authored manual motion or
manual Pen commands. Controller-native Motion, connection, alarm, safety,
serialization, and settlement remain mandatory at effect execution.

## Sparse calibration data flow

Exercise 1.3 builds `CurrentCameraCalibrationPlan` from current Drawing Boundary aggregates
and center arrival. `MachineCameraRegistration` retains five machine/cap
correspondences: `C`, `X−`, and `Y+` fit the initial affine map; `X+` and `Y−`
are independent holdouts; acceptance follows the all-five refit. Publishing the
accepted registration also publishes learned fitted presentation bounds, but
that target change does not change the current exact viewport rectangle, camera
evidence, or a compatible `VideoAnalysisRegionLock`.

For each LIVE correspondence, `OperatorWorkspace.captureStableWorkflowCap`
acquires exactly three strictly newer exact `inspectWorkflowScene` results after
a preliminary frame boundary. `FixedCameraOpticalSettlingPolicy` requires one
source/configuration, exact measurement/frame identity, an accepted unambiguous
cap in every frame, and maximum pairwise component-centroid spread of at most 2 px.
It returns the newest third inspection unchanged; no centroid, bounds, or
confidence is averaged. The preliminary frame is freshness control, not accepted
cap evidence. All three strictly newer samples are materialized `.returnOnly`
inside one exclusive `CameraSourceSession` lease. Only the selected newest stable
sample is explicitly published, once; failure or cancellation publishes none,
settles that same lease, and restores the requested automatic-analysis stream.
SIMULATED causal geometry is source-separated nonphysical evidence and cannot
establish live optical stability.

Exercise 1.4 is split across four owners:

- `SparseTipCalibrationCoordinator` owns the compact batch state machine, one
  attempt/operation identity, four canonical corner evidence slots,
  one shared final frozen frame, unordered click collection, immutable accepted
  observations, possible-ink terminal state, proposal review, and acceptance.
- `SparseTipBatchMarkPlan` derives the four mark centers from the accepted
  Drawing Boundary envelope with one canonical 10 mm inset, drawing no center
  mark. Its
  2 mm-radius outlines therefore retain 8 mm of adjacent-edge clearance. Its
  corner-center rectangle is the proposed tip-map
  applicability rectangle, and its final reveal pose is the rectangle center.
- `OperatorWorkspace` composes that plan as one typed batch. It performs one
  initial Pen-Up normalization, preserves that batch-scoped Pen-Up authorization
  across approach/start/reveal travel, and consumes four Pen Down plus four
  post-circle Pen Up settlements. The complete batch therefore has five Pen Up
  settlements, 64 typed chord outcomes, four pre-mark controller-context probes,
  one reveal probe, and one final machine snapshot. Per-chord progress remains
  controller typed for Stop and possible-ink handling but does not rebuild a
  Learning projection or fetch another workspace machine snapshot. The existing
  camera presentation renders the accepted Drawing Boundary separately from the
  inset proposed/accepted Drawing Border; Exercise 2.1 later draws that physical
  connecting Border. Exercise 1.3 retains its center plus four
  ±24 mm positions.
- `TipCalibrationAuthority` owns validated evidence types, four-corner affine-first
  construction, constant construction fallback, diagnostic residual/covariance/
  uncertainty, applicability decisions, rebase derivations, and checkpoints.

The sparse-tip flow stages one four-point `PlotterPointSelectionRequest` with
the shared frozen `ExactTipCalibrationFrame` and presentation-transform
revision. `ActionSurface` maps each view click back through the exact inverse
presentation transform and submits it through
`PlotterPointSelectionIntentSink`; the episode projection supplies click count
and all markers. Retained `OperatorWorkspace` action adapters invoke the same runtime/store authority for undo, clear, and cancel; those actions do not originate in `ActionSurface` or the click-only sink protocol.
`PlotterPointSelectionRuntime` owns same-frame undo, clear,
capacity enforcement, and accepted four-point batch evidence without motion,
ink, capture, zoom, or pan. `SparseTipCalibrationCoordinator` retains the
machine-position association, fit, calibration acceptance, and artifact graph.
Tip-map acceptance installs the outer-center applicability rectangle without
changing viewport state.

After click four, the app projects all four corner machine positions through
current `MachineCameraRegistration`, centers projected and clicked sets to
remove their common cap-to-tip translation, evaluates all 4! assignments, and selects the
minimum total squared pixel distance with canonical-position exact-tie breaking.
There is no distance or ambiguity gate. The four associated observations feed
direct affine construction first; constant correction is constructed only when
affine construction throws. Residuals, RMS, covariance, and uncertainty are
diagnostic and never block progression.

The accepted graph shape is:

```text
current MachineCameraRegistration
  -> four corner ToolContactObservation revisions
  -> current TipCameraRegistration
```

A new paper instance on an explicitly unchanged contact plane consumes no new
contact observation and retains tip authority. A changed contact plane
invalidates the tip registration and requires the normal four-observation
Exercise 1.4 graph. Stage 2 Drawing Border plans and local baselines consume the exact current
tip revision; later frame/post-frame/ink/residual nodes retain that dependency
transitively.

## Chronology and possible ink

Live Pen Down and Pen Up timestamps are taken only after the corresponding
settled controller outcomes. Reveal settlement is timestamped after final MPos
acceptance and before a newer exact frame is captured. The reveal cites the
refreshed controller-context baseline returned with that capture.

The no-redraw key is `BlacklistedToolContactLocation`: calibration role, circle
center/radius, and replaceable paper-instance revision. `OperatorWorkspace` retains
that set across attempt cancel, restart, and Learning Path reset. The coordinator
re-enters a terminal possible-ink state on the same sheet. Explicit sheet
replacement rotates instance identity and clears that sheet-specific recovery;
it rotates contact-plane identity only when support, stock, or contact height
changed. Numerical model construction cannot request paper replacement or a
no-redraw recovery route.

## Learning Path checkpoint and semantic identity

`AcceptedLearningPathCheckpoint` is the single atomic production envelope for
the accepted LIVE prefix. It composes the accepted Exercise 1.1 record,
`AcceptedMachineArtifactCheckpoint`, Exercise 1.3 registration/revision,
`AcceptedTipCalibrationCheckpoint`, accepted pen-cap appearance, one bounded
reference frame, and the Exercise 2.1 drawing-evidence reference.
The inner types retain their domain validation and provenance; the envelope
owns cross-stage semantic identity and atomic storage.

Production semantic identities are composed from stable persisted revisions for
machine geometry, tool assembly, pen-contact profile, paper instance, paper
contact plane, camera mount, and camera reframing. Capture-session and camera-configuration IDs remain
ephemeral operational provenance; they are not substituted for mount/reframing
identity.

Loading produces one exhaustive saved-package candidate and mutates no
`LearningDependencyGraph` or registration owner. `OperatorWorkspace` projects
compatible saved geometry and uses the package's one bounded reference frame to
produce an advisory integer-shift/background-MAD report. **Use Saved Learning**
calls the checkpoint-owned exact graph reconstruction once, stages all fallible
decoding locally, then assigns the complete accepted prefix atomically. **Start
New Learning** retains the package but applies no values. Neither action restores
Motion authorization, Pen state, controller pose trust, frames, operation
owners, or Stop capabilities, and neither issues motion.

Explicit changed-coordinate recovery may still construct fresh
`TipCalibrationRevalidationEvidence` and rebase the machine checkpoint,
`MachineCameraRegistration`, and `TipCameraRegistration` under one new
coordinate revision when a pure translation is actually proven. Direct manual
controls remain independent. Replacing only the
paper instance retains that authority; changing the contact plane invalidates
it and requires the full four-mark calibration. The revalidation evidence is
durable. Reset clears the affected durable machine and/or tip checkpoint before
clearing in-memory authority.

Process restart does not rotate persisted semantic identities. Unknown physical
changes still cannot be inferred from a UUID: after an unrecorded camera bump,
machine reset, remount, or assembly change, the operator must use the owning
reset rather than accepting unchanged restoration. Explicit operator-facing
revision controls remain a roadmap item.

## Stage 2 ownership

Stage 2 does not reuse a Stage 1 target, baseline, or reveal pose.
`DrawingBorderPlan` creates one closed polyline through the four accepted
10 mm-inset circle centers, with four orthogonal edges and right-angle turns.
`OperatorWorkspace` supplies the accepted Drawing Boundary—not that inset
Drawing Border—as the plan's `DrawableMachineRegion`. The region admits exact
Boundary geometry and only its separately versioned 1e-9 mm numerical epsilon;
it never imports or equals controller-position settlement tolerance.
The visible 2.1 row owns one attempt from **Draw and Validate Drawing Border** through normal comparison; its
six typed phases update activity and subsystem presentation but do not create
six UI action owners. It stores:

- the exact tip registration revision;
- a trial-local pre-frame exact frame and reveal MPos;
- Drawing-Border-start settlement and one canonical drawing-plan owner;
- a Pen-Up return to the same reveal MPos;
- a strictly newer post-frame exact frame;
- bounded generic black/new-ink observation, residual, and assessment.

Before motion, `OperatorWorkspace` projects the stored closed machine path through
the exact current `TipCameraRegistration`. `ActionSurfacePresentation` binds the
planned polyline to each currently displayed frame/configuration, so the cyan
prediction remains visible over live video without freezing preview or treating
planned geometry as measured pixels. The post-frame observer replaces that
preview with exact-frame intended, measured-ink, and residual overlays.

The typed `ExactWorkflowVisionOwner.observedDrawingTrial` is projected separately
from background scene-analysis state. While planned-drawing comparison is in
flight, Learning reports **Trial ink analysis · active** and names Vision as the
processing owner.
Normal observed-ink success commits the typed comparison in the same exercise
attempt. Only a failure, ambiguity, possible-ink recovery, rejected observation,
or atomic-commit error ends the automatic chain early.

Planned observation uses alignment revision
`bounded-subsampled-finalist-background-mad-v2`: it scores the complete bounded
integer-shift envelope on a deterministic two-pixel lattice, then evaluates at
most three finalists at full resolution. Coarse scores never become acceptance
evidence. Alignment, new-ink extraction, and path association expose bounded
cancellation checkpoints; cancellation returns typed `computationCancelled`,
publishes no partial observation, and settles the one exclusive Vision lease.
Successful evidence records exact work counters and algorithm revisions as
diagnostics. Intended overlays retain planned provenance, observed ink retains
measured provenance, and residuals retain diagnostic provenance on the exact
post-frame.

The intended Drawing Border, observed ink, and residual are contextual Stage 2 results,
not global overlay preferences. The implemented curriculum ends at this one
attributable validation. Its post frame and overlays remain explicitly
reviewable, and its typed comparison is adapted into an evaluation-holdout
`DrawingRunEvidenceRecord`. No Stage 2 result automatically changes accepted
calibration or establishes a generally trained adaptive model.

## Drawing Studio ownership

`PlotterDrawingDraftRuntime` is the single source-indexed draft owner. Each
`PlotterDrawingDraftSubmission` binds a `PlotterDrawingDraftRequestID`, one
immutable `PlotterDrawingDraftRevision`, the complete
`PlotterDrawingDraftExternalFactRevisions`, and a typed
`PlotterDrawingDraftIntent`. It refuses stale draft or fact projections before
mutation and returns the exact request, compared revisions,
`EpisodeAuthorityID`, `PlotterDrawingDraftRefusalReason`, and remedy. SwiftUI
receives immutable `PlotterDrawingDraftSnapshot` values and submits only through
`PlotterDrawingDraftIntentSink`; the deleted combined action enum, direct
open/close/paper-confirm methods, local rebuild helper, and App-local mutable
draft have no authority.

`PlotterDrawingPlanningAdapter` is the sole upper-layer route into the retained
lower pure `DrawingPlanner`. The draft route produces deterministic catalog,
program, placement, and content-addressed `ExecutionPlanRevision` identity.
Its package-only `planRetainedDrawingBorder` route lets the explicitly retained
EA-10E Border workflow reuse the same pure planner without granting draft
authority or moving Border sequencing, motion, evidence, or outcome semantics.
Planning clips nothing: one outside-region point refuses the complete plan.

The runtime derives the drawable region from the accepted Drawing Boundary and
projects it through a typed diagnostic affine value, including the area between
the inset applicability rectangle and Boundary, alongside the predicted current
tip point. This does not enlarge recorded tip-calibration applicability.
`TipApplicabilityEvidencePolicy` is the sole constructor of observer-bound
intended geometry: it uses `TipCameraRegistration.tipPixel(at:)` for every plan
point and returns an unforgeable all-or-nothing projection token. One outside
point keeps the Boundary-valid plan executable but prevents Vision invocation
and records a completed, non-attributable run with zero verified strokes. Only
a separately accepted registration revision whose recorded rectangle contains
the same plan can make it camera/ink evidence eligible.

Preview binds the exact displayed frame, program content hash, and plan revision.
Registration/configuration mismatch is unavailable; outside-region planning
shows no clipped strokes; outside-applicability projection is diagnostic-only.
None is camera/ink or physical evidence.

`PaperCoverageObservation` is a separate paper-instance assertion.
`PlotterDrawingDraftPaperPersistence` is the sole draft persistence seam, and
production `PaperCoverageComposition` injects one nominal
`UserDefaultsDrawingDraftPaperPersistence`. A LIVE save completes before the
accepted snapshot is published; failure returns a typed refusal without
installing the assertion. The operator supplies paper-coverage authority; the
displayed diagnostic Boundary polygon supplies no tip-map or camera/ink evidence
authority. Its polygon is shown only on its exact frame. Currentness is a
separate `PaperCoverageValidationContext` decision: newer same-context frames
remain current, while paper, source, camera configuration, or contact-plane
changes invalidate the assertion. It never expands the accepted Drawing
Boundary. SIMULATED assertions remain nonphysical.

Drawing Studio views consume immutable catalog, placement, target-preview,
parameter, and run-state presentations. A video click carries its exact frame
reference and is inverted through the current registration into a machine
anchor; scale or rotation creates a new placement and replans. Draft mutation
refuses while the immutable `PlotterDrawingRunSnapshot` reports an active owner
or a terminal still requires its exact new-run handoff. Once an exact RunID
handoff clears that terminal, `.beginNewPlan` changes only immutable draft
identity. No draft action invokes machine motion, Stop, camera, Vision, run
evidence, or another physical effect, and no view or workspace loop emits
individual controller segments.

`PlotterDrawingRunRuntime` is the single source-indexed EA-08B run owner. A
`PlotterDrawingRunSubmission` binds one request ID, the immutable run revision,
environment, exact `PlotterDrawingRunPlanIdentity`, and one typed intent: start,
exact-capability Stop, exact-RunID review pin/unpin, new-run handoff, or exact
publication recovery. Stale projections and changed plan/fact identity return
typed owner/reason/remedy refusal. SwiftUI receives immutable
`PlotterDrawingRunSnapshot` values and sends only through
the async `PlotterDrawingRunIntentSink`; App composition awaits runtime
submission directly and owns no stored submission or shutdown-join Task.
`PlotterDrawingRunRuntime.beginShutdown` closes admission, requests the exact
`.shutdown` Stop when a run is active, and awaits that run's terminal
publication before returning. The runtime therefore owns both admitted-run
lifetime and shutdown quiescence without duplicating controller, interpreter,
camera, Vision, or evidence authority.

The runtime refreshes complete facts and revalidates the exact EA-08A plan,
paper, Learning, environment, and lower readiness around every effect boundary.
Its admitted LIVE chain normalizes Pen Up, performs supervised observation-pose
travel when needed, captures the exact local baseline, delegates the immutable
plan to `RunInterpreter`, verifies exact final MPos, captures a strictly newer
same-source post frame, and requests Vision only when the intended projection is
inside tip applicability. Outside applicability is executable but published as
`.nonAttributable` with no Vision-derived ink claim.

`PlotterDrawingRunFactSource`, `PlotterDrawingRunInterpreterPort`,
`PlotterDrawingRunCameraPort`, `PlotterDrawingRunVisionPort`, and
`PlotterDrawingRunEvidencePort` are nominal bridges to retained owners. The
checksummed `DrawingRunEvidenceStore` must append the exact immutable record
before successful terminal publication. A failed append leaves
`publicationIncomplete` plus one exact recovery capability; it cannot look
successful. Possible-ink/no-redraw truth is independent of persistence and
blocks the exact plan until a new immutable plan is handed off. Refusal,
cancellation, ambiguity, Vision rejection, or storage failure never authorizes
redraw or resend. Review pinning is RunID-bound, and archive load/append cannot
restore runtime ownership or replay a plan.

SIMULATED start is a typed nonphysical refusal and invokes no LIVE interpreter,
camera, Vision, or evidence port. `OverlayResultChannels` retains Drawing Studio
workflow results independently of scene overlays and Stage 2.
`DrawingReadinessAssessment` remains a Model presentation capability statement;
construction bypasses none of the complete typed requirements.

## Simulator boundary

`SimulatedLearningRuntime` owns a nonphysical controller session, Motion flag,
MPos, pen pose, Boundary motion, large nonzero cap-to-tip truth, paper instance,
16-segment circular marks, line ink, and causal frames. Its frame clock can advance
past an asserted settlement boundary so simulated exact-frame chronology stays
causal. It owns plant and rendered-scene truth, not public effect admission.

`PlotterCausalSimulatorEffectAdapter` owns causal-simulator command attribution,
admission, exact raw operation identity, natural execution, first-winning
Stop/cancel/shutdown disposition, original-owner waiting, and one atomic
terminal outcome/truth publication. Typed episode work receives
`PlotterEffectResult` settlement; explicitly attributed retained work receives
nil `effectResult` and no fabricated semantic revision.
`PlotterCausalSimulatorTruthSnapshot` keeps controller-command attribution
distinct from plant MPos/Pen, paper/ink, camera publication, Vision, and
evidence truth. The adapter declares
`PlotterCausalSimulatorVisionTruth.notComputedBySimulator`, names
`VisionWorker` as the measurement authority, reports `.simulatedCausal`, sets
`physicalEvidenceClaimed` false, and emits `.notPhysicalEvidence` on every
admission refusal and outcome.

The simulator uses the same public workspace actions and artifact graph but
never calls production machine actions. The removed
`SimulatedWorkspaceHarness`, `makeSimulatedHarness`, and `performPublicAction`
cannot bypass the workspace composition; App tests retain only a read-only
causal snapshot plus explicit fault-injection probe. Every simulator surface is labeled
`SIMULATED — NOT PHYSICAL EVIDENCE`. An annotation is presentation-only and
cannot alter canonical pixels or hashes.

The focused causal-environment suite contains fifteen tests, including a
package-gated no-sleep/no-poll successor-versus-terminal-publication regression
that holds the predecessor while proving both retained Pen refusal with no
lower mutation and retained drawing refusal, then releases it and proves
drawing successor isolation plus unchanged cached predecessor truth.
The focused workspace authority suite's 24/24 correction evidence includes the
regression proving manual runtime and retained workflows occupy one shared
production adapter authority.

`OperatorWorkspace` owns two independent `LearningSessionState` values,
one LIVE and one SIMULATED, under one structural contract. Session state owns
the graph, artifact payloads and proposals, attempt histories, accepted-attempt
sequence, quarantine status, paper identity, possible-ink blacklist, drawing
trial state, and learning errors. The active frame source selects which value
all learning projections and mutations address. Camera/controller owners,
operation tasks, Stop capabilities, and other runtime lifetimes remain outside
the session values. One `ActiveStoppableOperation` binds the exact owner task,
contextual Stop target, latched disposition, and cancellation-request phase;
those facts are not independently mutable. Drawing execution likewise carries
typed not-admitted, possible-ink, and naturally-completed state so no-redraw
recovery is independent of presentation wording.

Workflow failures retain typed kind and recovery separately from actionable
presentation text. Boundary disposition, attempt disposition, sparse-mark
blacklisting, current-camera phases, and telemetry failure codes consume those
typed identities through exhaustive switches; rendered text is never parsed to
recover workflow meaning.

The durable Learning Path checkpoint port is a capability of the LIVE session
only. SIMULATED receives no active durable checkpoint capability, so its public
actions cannot load, save, clear, replace, or otherwise mutate physical durable
authority. Entering SIMULATED replaces only its previous nonphysical session;
the LIVE session remains stored independently and is selected unchanged on
return.

## Validation structure

Swift Testing suites cover evidence constructors, affine-first construction and
constant construction fallback, checkpoint quarantine and revalidation, graph
dependency shapes, shared-frame unordered clicks, physical-location blacklist
persistence, ActionSurface projection, four-mark batch acceptance, checkpoint
restart/paper recovery, and Stage 2 causal ink, plus drawing catalog/planning,
plan execution, planned-ink observation, paper evidence, and append-only run
evidence. `make quick-test` excludes the explicitly retained journeys;
`make journey-test` runs the current sparse/Stage 2 routes sequentially; and
`make strict-check` applies complete concurrency checking and warnings as
errors in addition to bundle, launcher, full-test, contract, and diff gates.

No automated architecture result is physical validation.
