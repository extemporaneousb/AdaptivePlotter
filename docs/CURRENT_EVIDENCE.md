# AdaptivePlotter Current Evidence

Status: current evidence ledger; software, simulator, controller, and attended
physical claims are recorded separately

This document records what was actually verified. Product meaning belongs to
[Product Contract](PRODUCT_CONTRACT.md), package ownership to
[Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md), and the physical
procedure to [Attended Hardware Runbook](ATTENDED_HARDWARE_RUNBOOK.md).

## Episode manual-motion cutover candidate

Operator-authorized Option A candidate after critic RETASK #6, 2026-08-28, in Blackdog task
`TASK-FE9C9CB3`. Before this documentation delta, the shared tracked diff had
SHA-256
`c17cddb971f6df9e0ddefb0fd98991f94fad1deec2cf72a9f02992182211fd7b`
and its NUL-delimited status had SHA-256
`5dbe44431fe5f955ec336b5f769281635ca638e8add5564e6ed78b6d5cbf1310`.
Those two identities do not bind untracked file contents, which are therefore
bound separately:
`PlotterManualMotionComposition.swift`
`707a30cdb8a540e28a5a02176c77bb751503a8845218947b6527fbe697806ff6`,
`PlotterManualMotionRuntime.swift`
`7c78ec2edd4f4beb9e8e2098570127bd127eac9e91e744780b290514de7028ab`,
and `PlotterManualMotionEpisodeTests.swift`
`975d1dc9feb49e4488634824a12315c3da063dd825eed61f82b959ffc58c66e2`.
Every previously recorded package-wide green sequence remains historical
evidence for its exact earlier tree only. Critic RETASK #6 was material, not
acceptance: it found pre-start shutdown ownership, observed/settling Stop
handoff, manual ambiguity projection, and production recording-topology gaps.
The accepted source correction and same-critic delta closure are recorded
below. This exact five-bound tree passed all seven package gates serially, as
recorded below. Per operator policy, no new or full critic was commissioned and
no further critic is required or allowed. EA-06 is complete in the task-local
candidate delivered by `TASK-FE9C9CB3`, attempt
`TASK-FE9C9CB3-54834fa90e36`; migration remains incomplete. Blackdog
landing/cleanup and successor-capsule creation are the only remaining steps.

The coordinator accepted the bounded runtime/model slice comprising the typed
manual intent and capability facts, pure evaluator and reducer integration,
effect/event grammar, `PlotterManualMotionRuntime`, its journal persistence and
machine-lane registry ownership, and focused runtime/model tests. The runtime
owns one FIFO mutation/publication boundary, exact active operation identity,
successor-isolated `PlotterManualMotionStopCapabilityID`, typed terminal
observations/results, and distinct LIVE/SIMULATED effect-adapter selection. A
first matching exact Stop creates one public transaction and synchronously
latches the registry's original nominal handle. On the ordinary Stop path it
then durably publishes `requested`; the registry atomically marks the same
transaction `issuingCancellation` before suspension and invokes cancellation
once; the runtime durably publishes `observed`, enters settlement, durably
publishes `settling`, and only then awaits that same owner. Duplicate callers
join it and receive the identical result plus post-terminal snapshot only after
typed episode publication. Append failure retains the exact owner, stage/result
cursor, and typed recovery capability; no successor can be admitted until
publication completes. The complete transaction result remains idempotent only
until successor admission clears it, so the predecessor becomes stale and
cannot cancel the successor.

Fresh critic RETASK #5 found two material authority defects. First, a staged
Stop could latch its requested cancellation owner, fail the requested journal
append before issuing cancellation, and then leave shutdown waiting forever on
an attempt that nobody owned to advance. Second, cancellation publication was
outside the runtime FIFO boundary, so a concurrent gateway refusal could
terminalize the model request and clear the still-active owner.

The accepted correction gives the registry a nominal `issuingCancellation`
phase that is installed atomically before any cancellation suspension. If
shutdown sees the same transaction still at requested, it closes admission and
takes over that exact owner and handle, invokes cancellation exactly once,
advances the same registry owner through observed and settling, and settles the
original handle. An already issuing or settling transaction is joined; there is
no journal dependency, duplicate cancel, settlement, or publication authority.
If the journal remains unavailable after shutdown settlement, the pending Stop
recovery capability survives with the exact terminal-publication cursor.

Each cancellation journal commit, its pre-state read, and its failure snapshot
now owns the FIFO mutation/publication boundary, which is released across
controller cancellation and settlement awaits. While the exact active owner
remains, a concurrent submission is refused transiently as busy from the
transaction-complete snapshot before gateway evaluation. It records no
successor refusal event, effect, or revision collision and cannot terminalize
or clear the active owner.

Critic RETASK #6 found four material gaps in that later candidate. First,
shutdown could race a registered operation before native start without one
terminal owner-retirement path. Second, shutdown joining a Stop already at
observed or settling needed an explicit ownership handoff without displacing
the public Stop's journal cursor. Third, the app needed to derive manual
availability and possible-ink/ambiguity disposition from the actual runtime
phase and exact typed terminal evidence. Fourth, the canonical documents named
the point-selection recording root instead of the production manual recording
topology.

The accepted correction settles a pre-start owner once as the identity-bound
`cancelledBeforeStart` result, retires that exact owner, and makes any later
start inert. LIVE and SIMULATED therefore perform zero native start or
cancellation invocation. At observed or settling, registry shutdown hands the
same transaction to `settledByShutdown`; the original public Stop cursor remains
the sole journal and recovery publisher, duplicate Stop callers remain joined,
and cancellation and settlement occur exactly once.

Operator-authorized Option A closes the remaining
accepted-progress/pre-activation race with one runtime-owned shutdown latch. In
`PlotterManualMotionRuntime.swift:1329-1356`, shutdown sets
`shutdownIsLatched` synchronously before the sole `registry.shutdown()`
suspension, retains every exact registry terminal, and only then releases the
same-shutdown completion waiters. In
`PlotterManualMotionRuntime.swift:1101-1123`, submission rechecks that latch
after accepted `recordProgress` and before `active` installation, waits for the
same shutdown completion, consumes the retained exact pre-start terminal, and
returns through `publishPrestartTerminalSubmission`. The active-install and
native-start lines are below that return and are not reached.

Manual availability now comes from the actual runtime phase. A terminal
ambiguity exposes one typed disposition bound to the exact effect ID,
environment, and observation ID and distinguishes possible ink from other
ambiguity. All manual effects stay disabled while it is unresolved; stale or
mismatched actions are rejected, and only explicit operator evidence for that
matching action advances the episode. This path never retries, redraws,
reissues, cancels, or settles controller work.

The accepted app-integration slice composes that runtime with production
EA-05A store opening/diagnostics, a LIVE native-controller adapter, a
causal-simulator adapter, current capability-fact projection, SwiftUI manual
presentation, and typed jog, Pen, and Stop ingress. `OperatorWorkspace` retains
only copied runtime projection/adaptation and the UI-local `ManualMotionDraft`;
it no longer owns the deleted manual semantic guards, manual
operation/cancellation task, or LIVE/SIMULATED manual executor. Neutral lower
calls in
`PlotterManualMotionComposition` remain only for the existing Learning,
Drawing, and supervised-travel semantic owners scheduled in later packages.
They neither admit manual intents nor transfer EA-07, EA-08, EA-10, or
controller-session authority.

The typed evaluator now derives the Motion-disabled remedy from the submitted
manual intent: jog says to enable Motion before requesting movement, while
direct Pen says to enable Motion before actuating the pen. Workbench busy
projection reads the exact active episode operation instead of the retired
workspace task booleans. For accepted LIVE manual jog/drawing effects,
`OperatorWorkspace` emits legacy-compatible diagnostic accepted and terminal
workflow telemetry keyed by the typed `EpisodeEffectID`. That telemetry admits,
cancels, settles, and authorizes nothing; the episode runtime and native
controller owners remain authoritative.

The accepted recording-integration slice makes one operation-bound
`PlotterManualMotionControllerRecorder` only for a LIVE effect with an available
EA-05A store. `LiveManualMotionAdapter` attaches that recorder through exactly
one `ManualMotionControllerRecordingRouter` before native launch, retains the
lease through natural or exact Stop/cancellation settlement, and detaches only
at terminal settlement. `PersistentMachineSession` constructs the one canonical
BSD `MachineLink` through `MachineController.bsdSerialLink`, wraps it once in a
transparent `RecordingMachineLink`, and gives that decorated link back to the
unchanged `MachineController`/`RunInterpreter` ownership stack. There is no
sibling transport or semantic effect path.

The decorator translates only exact FIX-02 facts already returned by the sole
link: applied BSD open configuration; successful discard/write byte counts;
exact read bytes with the receive-boundary monotonic timestamp; observable close
failure; and discard/write/read failure progress, including timestamped partial
read chunks. A configuration that cannot be represented losslessly and a failed
open without an applied configuration produce diagnostics only; they do not
fabricate settings, counts, or a successful transcript pair. EA-05A persistence
failure is also diagnostic-only and does not change controller safety,
settlement, or the native return value. `EpisodeRecordingStore` now accepts
truthful nonnegative partial discard progress with no partial read chunks while
retaining the open/close zero-progress and write/read bounds. SIMULATED receives
no controller recorder and proves no physical behavior.

Fresh critic RETASK #4 found that applied BSD `localModeEnabled=false` or
`receiverEnabled=false` could not be represented by the EA-05A open parameters
and therefore could not be recorded as a successful pair. The corrected
FIX-02 mapper refuses either false flag, returns the native receipt unchanged,
records no successful open invocation or completion, and exposes the existing
lossless-mapping diagnostic. The true/true mapping is unchanged.

The same RETASK required the already typed terminal-publication recovery to be
operator-actionable without granting new effect authority. The app now projects
only the exact `PlotterManualMotionPublicationRecoveryCapabilityID` with an
intent-specific manual jog, drawing, Pen Up, or Pen Down remedy. While recovery
is pending it disables every manual effect, hides stale Stop, and refuses stale
recovery capabilities. The exact current capability calls only
`recoverTerminalPublication`, clears only its matching publication diagnostic,
and restores availability from the returned snapshot. It cannot re-admit the
intent or reissue, cancel, or settle controller work.

The source RETASK applies that partial-discard rule identically in
`EpisodeRecordingStore` and deterministic replay, so persisted traffic cannot
be accepted and later rejected solely because discard reported partial byte
progress. The registry retains `ManualMotionOperationHandle`, not an erased
closure or replacement cancellation task, and the episode model/runtime add no
`@unchecked Sendable` authority escape. The lower `MachineActions` closure
facade remains only for unmigrated controller-session owners scheduled in
EA-11A; it does not own EA-06 admission, Stop, or settlement.

Direct LIVE Pen now admits through the nominal async
`PenActuationOperation` returned by `RunInterpreter`, retaining the exact
owner-minted ID and eventual outcome. `LiveManualMotionOperation` awaits that
handle; neither the registry nor the public manual projection creates a Pen
Stop token. Jog/drawing handles retain their existing exact native identities
and cancellation owners.

Capability provenance now fails closed: connection, Motion, pose, and
`PlotterManualControllerFact` values are bound to the submitted LIVE or
SIMULATED environment. The manual-controller fact also binds current operation,
Pen state/routing, and Pen-profile revision. Missing or cross-environment facts
refuse admission; they cannot be repaired by UI projection or by facts from the
other adapter.

Production requires its UUID-scoped `EpisodeJournalPersistenceAdapter` journal
and does not compose the app without it. Controller-recording open failure
remains diagnostic-only. Every runtime snapshot exposes the exact loaded
`EpisodeJournal`, its file URL and digest-bearing artifact reference, the
optional recording snapshot and completeness issues, and typed
`PlotterIncidentSourceArtifactReferences`. Recording completeness cannot stand
in for journal durability, and neither artifact class establishes physical
behavior.

Operator-authored manual jog and Pen actions still bypass Learning progression
and restored-pose revalidation. The typed runtime nevertheless requires current
Motion/controller capability facts, and the LIVE adapter retains native
controller connection, alarm, safety, serialization, cancellation, fresh
settlement, and ambiguity authority. Known Pen Down routes as a drawing stroke,
known Pen Up as relative travel, and unknown Pen state as explicit possible
ink. Exact manual Stop cannot affect a successor; drawing Stop requires
controller settlement with Pen Up, otherwise the result remains ambiguous and
possible ink. Refusals and recording failures remain actionable projection
diagnostics rather than silent disabled controls.

Production opens the exact manual recording topology
`AdaptivePlotter/EpisodeArtifacts/<episode UUID>/controller-recording` with
schema `adaptive-plotter-manual-motion-v1`. This is distinct from the retained
point-selection `EpisodeRecordings/<recording UUID>` topology. Opening or append
failure is visible but does not change safety or evidence. The store records only exact entries
supplied from the operation-bound MachineLink boundary and never reconstructs a
missing transcript from terminal observations. Recording remains diagnostic
provenance, not authorization, independent settlement evidence, or physical
validation. LIVE controller observations and SIMULATED causal-simulator
observations remain distinct and cannot establish each other's evidence class.

Accepted-slice history now records six coordinator `RETASK` decisions: the
first after the original frozen package validation; the second after the exact
Stop publication race appeared in the affected QUICK rerun; the third fresh
critic after the later five-bound full pass; the fourth fresh critic for the
unrepresentable applied-open and terminal-publication UI-recovery gaps; and the
fifth fresh critic for the requested-Stop shutdown deadlock and FIFO publication
race. The sixth critic RETASK found the pre-start shutdown, observed/settling
handoff, typed ambiguity projection, and recording-topology gaps above. None was
an acceptance verdict. RETASK #3 required Store/Replay
partial-discard consistency;
nominal typed handle ownership without closure or unchecked-sendability escape;
durably staged Stop progress and retained-owner cursor recovery after append
failure; async owner-identified direct Pen without Stop; fail-closed
LIVE/SIMULATED capability provenance; and required journal plus typed
recording/incident-source truth. RETASK #4 added the lossless applied-open and
typed UI-recovery corrections. Its focused development evidence was 4/4 new
tests plus 3/3 retained tests; two intermediate compile/test nonpasses were
corrected before those accepted focused results.

Focused development evidence for RETASK #5 only, not package gates: the
requested-owner shutdown takeover test passed 1/1; the FIFO publication test
passed 1/1 after two truthful development nonpasses; related regression groups
passed 6/6 and 4/4; deterministic repeats passed 50/50; the owned suites passed
29/29; and the focused source diff check was clean.

Focused development evidence for RETASK #6 only, not package gates: the runtime
group passed 14/14, ambiguity UI passed 3/3, retained recovery passed 3/3,
deterministic race repeats passed 60/60, and the focused source diff check was
clean. Development nonpasses encountered while compiling/testing the correction
were corrected before those accepted focused results; they are development
history, not package-gate or critic pass evidence.

Focused Option A evidence only, not package gates: the new deterministic filter
passed 1/1, the complete manual suite passed 15/15, and shutdown remained
bounded for both LIVE and SIMULATED. After shutdown, neither registry nor
runtime retained an active owner; the exact effect produced one typed cancelled
`effectResult`; native start and cancellation counts were both zero; and the
focused source diff check was clean. The assertions at
`PlotterManualMotionEpisodeTests.swift:74-136` bind those conclusions to the
same effect ID in both environments.

The same critic returned the exact delta verdict `CITED_RACE_CLOSED`. Its
line-level conclusions were that runtime lines 1329-1356 synchronously latch
shutdown before the sole registry await and publish completion only after exact
terminal retention; runtime lines 1101-1123 recheck after accepted progress,
join that same shutdown, publish the retained terminal, and return before active
installation/start; and test lines 74-136 deterministically prove bounded
LIVE/SIMULATED retirement, zero remaining owners, exactly one typed cancelled
result, and zero native start/cancel calls. All earlier passed critic dimensions
remained closed. Per operator policy, no new or full critic was commissioned;
no further critic is required or allowed.

These focused results and the delta verdict accept the Option A source
correction but do not by themselves satisfy any package gate. The exact
five-bound tree identified at the start of this section then completed this
serial package-gate sequence:

| Current serial validation on the exact Option A tree | Result | Exact log SHA-256 |
| --- | --- | --- |
| `MOTION` | passed — `swift test --filter PlotterManualMotionEpisodeTests`; 15/15 tests passed | `9aaa0b87c20d05ae3d98d3c5c9c50a79d00942547e3fafd2e7f93f637fdc873f` |
| `DELETE` | passed — `sh Scripts/check_episode_cutover.sh EA-06`; all 26 exact scans had zero matches | `b841daa4968ac8fa3bb03058663abc9e8fbcab9fd5d65487b6fb2aa786afb04e` |
| `DOC` | passed — `make docs-check`; both documentation contracts plus 29/29 documentation/checker tests passed | `8986b9a8dc4091c34c32da507c6a29c0ebb54685067335f5641007868c26ce8d` |
| `DIFF` | passed — `git diff --check`; clean with no output | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `QUICK` | passed — `make quick-test`; 699/699 tests passed with exactly 10 configured exclusions | `6d9cc817581951b1ec9e024f9522e43337f81a6ff06bc4a90973efd7998c1794` |
| `JOURNEY` | passed — `make journey-test`; 10/10 filter-selected tests passed | `a4370968c633e28fbdb6685017c4c200f68eb5dd66be1efa876b378ad9fcc27c` |
| `STRICT` | passed — `make strict-check`; strict-concurrency/warnings-as-errors, 709/709 tests with no exclusions, both documentation contracts, and 29/29 documentation/checker tests passed | `06c6f7c1a5aef895850bedc4c502c8a0acf60aa7836d754e69225dd7c564f06a` |

These results are current evidence for the exact frozen source tree and
pre-evidence-doc tracked identity above. This final evidence/checker delta
affects `DOC`, `DIFF`, `QUICK`, and `STRICT`; the landing coordinator must
refresh those four gates on the final candidate before recording landed
evidence. `MOTION`, `DELETE`, and `JOURNEY` are source-sensitive and remain
bound to the unchanged frozen tree. No Blackdog landing or canonical-main
result is claimed here.

The coordinator had previously approved two bounded
integration expansions after inventory exposed required seams:
`MachineController` plus `PersistentMachineSession` gained the decorator
composition seam, and `EpisodeRecordingStore` gained truthful partial-discard
validation. Two compile-only development failures were corrected before the
accepted focused checks. They are development history, not failed package gates
or critic results.

The first frozen candidate was identified by diff SHA-256
`ef61b0f24251708c24d8fcf00a155377c5869eae92c3dbcc146dc87f66893c16`
and status SHA-256
`a1aa2e57d97b9e0cba44030fdb1bff0c27157a7887a53a66d2f70c0b58e0ceec`.
Its historical validation sequence recorded `MOTION` 5/5 passed, `DELETE`
26/26 exact zero-match scans passed, `DOC` 29/29 passed, and `DIFF` clean.
`QUICK` then failed with exit 2 after 676 tests and reported 7 issues across
four named failures. Its output was truncated, so exhaustive warning status is
unevidenced. `JOURNEY` and `STRICT` were not started. This entire sequence is
superseded `RETASK`/nonpass history, never current passed gate evidence.

The first RETASK's four root causes were exact: direct Pen refusal reused the jog-specific
Motion remedy; workbench busy projection omitted the episode-owned active
manual operation; retired manual diagnostic telemetry had no episode-terminal
replacement; and a duplicate exact Stop arriving during or after terminal
publication could be misclassified stale under load. That first accepted source
correction supplied the intent-specific Pen remedy, read busy state from the
exact active episode operation, emitted diagnostic-only accepted/terminal manual
telemetry keyed by typed effect ID, and retained only the just-settled public Stop
capability as idempotent until successor admission clears it. The later second
RETASK superseded that Stop-cache shape with the transaction recorded below.

The first-RETASK corrected-source identities were:

- `PlotterIntentEvaluator.swift`: `6183d29c055e1d686fb15267b172d4b2c6f6857fd009a7e78d794b97936738a9`;
- `PlotterManualMotionRuntime.swift`: `5ca6ec7ea37299cc76757db7c1ce6f09a2988e05f2ef467520c1cf0e56cdeee3`;
- `OperatorWorkspace.swift`: `3ec2ac439e1d5a43049f8bbd8e0c4a7f3a1f725e751e18674d73300cfc584e34`;
- `PlotterManualMotionEpisodeTests.swift`: `13dd31759fef587206aaf37116925f4cee54ab10e9d578791d2420e68a4cd2d2`;
- `PlotterEpisodeModelContractTests.swift`: `8289be44304ec49c41970456f73ccbe649bf5a044a7d4a1d10eb63b154f149c5`.

Retained focused software evidence for this package tree:

- development-only `PlotterRecordingStoreTests`: 37/37 passed;
- development-only `liveManualMotionReceiptRecording`: 1/1 passed;
- development-only `liveManualMotionFailureReceiptRecording`: 1/1 passed;
- development-only `PlotterManualMotionEpisodeTests`: 5/5 passed;
- development-only `liveManualMotionStopReceiptRecording`: 1/1 passed;
- the three parallel `liveManualMotion` focused tests: 3/3 passed.

Retask-focused development evidence, also not package gates:

- the original four failures reproduced independently;
- the corrected workspace trio passed 3/3 in parallel;
- the corrected `PlotterManualMotionEpisodeTests` suite passed 5/5;
- `exactStop` passed 20/20 across ten repeated parallel runs;
- the final combined parallel filters passed 6/6;
- new `directPenMotionRemedy` passed 1/1.

One attempted `--num-workers` invocation was rejected before any test ran
because that option is XCTest-only; the intended focused test was rerun with the
correct invocation. The rejected command is development history, not test or
gate evidence.

Those retained focused results accept the source slices described above. They
do not satisfy or replace the ordered package gates. The corrected frozen tree
then completed this full package validation:

| Historical validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; exit 0; both documentation contracts and 29/29 documentation/checker tests passed with no exclusions, warnings, or errors; real 9.65, user 6.42, sys 3.11 seconds | canonical documentation, checker constants, ledger/evidence consistency, and capsule fixtures on the frozen tree |
| `DIFF` | passed — `git diff --check`; exit 0 with no output or errors; real 0.03, user 0.02, sys 0.01 seconds | whitespace and patch-shape validation on the frozen tree |
| `QUICK` | passed — `make quick-test`; exit 0; 677/677 tests passed with exactly 10 configured exclusions (3 sparse-tip, 4 `OperatorWorkspace`, 3 `SimulatedLearningRuntime`) and no warnings or errors; real 14.48, user 19.95, sys 3.08 seconds; complete mode-0600 external log SHA-256 `f83bedda24f7252f55fbf2ebdc26d4a3f21fd308484926c203922f28584ec59a`, then removed | repository quick suite and its exact configured exclusions |
| `JOURNEY` | passed — `make journey-test`; exit 0; 10/10 filter-selected tests passed with no explicit exclusions, warnings, or errors; real 6.16, user 5.92, sys 0.24 seconds; external success-log SHA-256 `701035fde2219b4c8c508b3130d87493434a025eacd1e5ee6527f13adcb2149e`, then removed | retained serial controller/operator journeys |
| `STRICT` | passed — `make strict-check`; exit 0; strict-concurrency and warnings-as-errors build, 687/687 tests with no exclusions, both documentation contracts, and 29/29 documentation/checker tests passed with no warnings or errors; real 109.31, user 570.99, sys 69.44 seconds; external success-log SHA-256 `4234b7805fb5bd382d6d24c64454952c783777e1ebba033d9df2dfa3a71b32ab`, then removed | full strict source and documentation validation; a read-only progress inspection at about 74 seconds showed active compiler workers and advancing build step 48/77, and did not interrupt the command |
| `MOTION` | passed — `swift test --filter PlotterManualMotionEpisodeTests`; exit 0; 5/5 tests passed with no exclusions, warnings, or errors; real 1.42, user 1.12, sys 0.23 seconds | typed manual runtime, LIVE/SIMULATED separation, direct Pen, operation-bound recording, refusal, and exact Stop behavior |
| `DELETE` | passed — `sh Scripts/check_episode_cutover.sh EA-06`; exit 0; all 26 exact scans had zero matches with no warnings or errors; real 0.34, user 0.30, sys 0.03 seconds | same-landing deletion of old manual ingress, guards, state, mode branches, ports, and fixture authority |

That table remains exact historical evidence for frozen diff
`d21660321c1aa15594bea246a7e4a1b140020eeeab6c501d534ba9347f66d393`,
but its current-pass claim was superseded by the second affected-gate tree. On
tracked diff `e0edfb9145bc52396fdc754aed7f492ddc14aa7050f489ca7f6e1ad3cbe78e74`
and status `a1aa2e57d97b9e0cba44030fdb1bff0c27157a7887a53a66d2f70c0b58e0ceec`,
`DOC` passed 29/29, `DIFF` was clean, and `QUICK` failed with exit 2 after
677 executed, 676 passed, 1 failed, and 2 issues, with 10 configured exclusions
and no warning or compiler-error lines. Timing was real 79.91, user 578.63, sys
61.29 seconds. `STRICT` was not started. This is second-`RETASK` nonpass
evidence, not a passed gate sequence.

The sole failure was the exact concurrent Stop test: one caller received
`.settled` with a pre-terminal snapshot whose `lastTerminalEffect` was nil, then
the typed cancellation settlement was missing at test lines 66 and 70. The
complete mode-0600 failed log remains outside the repository at
`/tmp/adaptiveplotter-ea06-final-quick.jrV95l`; it is 154880 bytes with SHA-256
`5924c5e19282dfff13d56aeeaaedfc7172cbe1780d82f287d70fd36d426cb21b`.
That retained artifact is failed evidence, not a pass. The root cause was that
the prior settled-capability cache became visible before
`publishTerminalIfCurrent` completed.

The accepted correction replaces that cache with one exact public Stop
transaction installed before the first registry await. The first caller alone
invokes registry Stop; duplicates join continuations; every joined caller
receives the identical result and snapshot only after terminal publication.
The transaction-complete result remains cached only until successor admission
clears it, and a mismatched old capability remains stale. It introduces no
second cancel, settlement, or publication authority.

A package-only typed Stop-publication gate deterministically pauses after
registry settlement and before episode publication, and signals a duplicate
join. It cannot choose an outcome, cancel, publish, or grant authority, and uses
no sleeps or polling. That later frozen tree bound tracked diff
`7f2823a78b8a1c7be75f9b7e4caadc1deca70949166bd23226c4712a9fa30181`
and status
`a1aa2e57d97b9e0cba44030fdb1bff0c27157a7887a53a66d2f70c0b58e0ceec`.
Because Git diff/status did not bind untracked contents, its remaining three
identities were explicit:

- `PlotterManualMotionRuntime.swift`: `daaa90de14158ef42bf928fc1e781275461111c731fddf5a437ac158e70f86d0`;
- `PlotterManualMotionEpisodeTests.swift`: `8641f3228e3cdf87b9af94d07ee22e1800669dab2482305d30be9df7c1066858`;
- `PlotterManualMotionComposition.swift`: `998c6acb5d30c7302e1c829cf9b29134f3e5c41dde2b5f8fc1ce1b1c5233930d`.

Focused correction evidence only, not package gates: the publication test
passed 1/1; the manual suite passed 6/6 in parallel; 50 repeated paired
`exactStop`/publication runs passed 150/150; and the final visible filters
passed 3/3. Those focused results remained development evidence only; the
following complete sequence supplied the package-gate evidence for the exact
five-bound historical identity set above:

| Historical validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; exit 0; both documentation contracts plus 29/29 documentation/checker tests passed with no exclusions, warnings, or errors; real 9.80, user 6.55, sys 3.11 seconds | canonical documentation, checker constants, ledger/evidence consistency, and capsule fixtures on the five-bound tree |
| `DIFF` | passed — `git diff --check`; exit 0 with no output or errors; real 0.03, user 0.02, sys 0.01 seconds | whitespace and patch-shape validation on the five-bound tree |
| `QUICK` | passed — `make quick-test`; exit 0; 678/678 tests passed with exactly 10 configured exclusions (3 sparse-tip, 4 `OperatorWorkspace`, 3 `SimulatedLearningRuntime`) and no warnings or errors; real 14.09, user 19.90, sys 2.86 seconds; complete mode-0600 external success-log SHA-256 `4b3097d66504b648d8ac4ae4d449b06265086dd9895f90268ff42fd363cc3519`, then removed | repository quick suite and its exact configured exclusions |
| `JOURNEY` | passed — `make journey-test`; exit 0; 10/10 filter-selected tests passed with no explicit exclusions, warnings, or errors; real 6.15, user 5.90, sys 0.24 seconds; external success-log SHA-256 `58e8f8552b3454097039227e02c99b39c2dcecd12cfabc6981dd66b714ce5a8c`, then removed | retained serial controller/operator journeys |
| `STRICT` | passed — `make strict-check`; exit 0; strict-concurrency and warnings-as-errors build, 688/688 tests with no exclusions, both documentation contracts, and 29/29 documentation/checker tests passed with no warnings or errors; real 114.36, user 577.86, sys 68.63 seconds; external success-log SHA-256 `4693c18feeacfc7b70288253f4be3225bdcdd03daba7c2067d997a890b914bf6`, then removed | full strict source and documentation validation; a read-only progress inspection showed active compilation and did not interrupt the command |
| `MOTION` | passed — `swift test --filter PlotterManualMotionEpisodeTests`; exit 0; 6/6 tests passed with no exclusions, warnings, or errors; real 1.43, user 1.15, sys 0.24 seconds | typed manual runtime, LIVE/SIMULATED separation, direct Pen, operation-bound recording, refusal, exact Stop, and deterministic duplicate-join publication behavior |
| `DELETE` | passed — `sh Scripts/check_episode_cutover.sh EA-06`; exit 0; all 26 exact scans had zero matches with no warnings or errors; real 0.35, user 0.30, sys 0.03 seconds | same-landing deletion of old manual ingress, guards, state, mode branches, ports, and fixture authority |

That full pass remains exact for its historical five-bound identity set. The complete
QUICK, JOURNEY, and STRICT success logs had the recorded hashes and were then
removed; the retained failed QUICK log above remains distinct nonpass history.
The next fresh critic RETASK and completed source correction superseded it at
that time. Before RETASK #4, the corrected frozen five-bound candidate
bound tracked diff
`3e9dad0f8957f913d7a3c3077f47bb6033b3cbc7bdb1f0c515cd5f665c23a68a`,
NUL-delimited status
`5dbe44431fe5f955ec336b5f769281635ca638e8add5564e6ed78b6d5cbf1310`,
and untracked composition/runtime/tests hashes
`66250a0edb70827b2afcc450c02ed47278f755faacc00d6d5129440bfbdc7b69`,
`11b4277578448a692e7c969eacdb42f63146716ab59a13cb13f409182866b5bd`,
and `0b31a505069c5b89fbe4b92e21195e0904a4deb31801ada72d4ab720456da7df`.
That exact earlier tree completed this serial package-gate sequence:

| Historical validation after RETASK #3 | Result | Exact log SHA-256 |
| --- | --- | --- |
| `MOTION` | passed — `swift test --filter PlotterManualMotionEpisodeTests`; 9/9 tests passed | `79c1a3cb24ffe3b1b68cb44dcf733029cabde976f0be8f88899f369e9cccfa60` |
| `DELETE` | passed — `sh Scripts/check_episode_cutover.sh EA-06`; all 26 exact scans had zero matches | `b841daa4968ac8fa3bb03058663abc9e8fbcab9fd5d65487b6fb2aa786afb04e` |
| `DOC` | passed — `make docs-check`; both documentation contracts plus 29/29 documentation/checker tests passed | `e9c69abd7637c66d18f6569db229df29c58d4fd1b67d981ab888164b1abc5e2e` |
| `DIFF` | passed — `git diff --check`; clean with no output | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `QUICK` | passed — `make quick-test`; 685/685 tests passed with exactly 10 configured exclusions | `fcd13343eb389a6f4aafc79bf2dbd04c377285d8deb8980916d3791f078e43fe` |
| `JOURNEY` | passed — `make journey-test`; 10/10 filter-selected tests passed | `900a61fc976464b2c3566e63655357dbb04b2aab130c372e1dc21bb9b9dc8981` |
| `STRICT` | passed — `make strict-check`; strict-concurrency/warnings-as-errors, 695/695 tests with no exclusions, both documentation contracts, and 29/29 documentation/checker tests passed | `05b8de2e979b9fb2993e3c181997e939ea475f83feb1acbeee28682960b0e6a1` |

That full pass is historical evidence only for its exact earlier identity set.
RETask #4 and its accepted source correction superseded it at that time. The
retained failed QUICK log remains explicit second-RETASK nonpass history and is
not promoted by either later pass. The RETASK #4 five-bound candidate bound
tracked diff
`3c18f0cdd7cee68d20ba567e0a14485a939110eec99c634e06c51fe6c889bd08`,
NUL-delimited status
`5dbe44431fe5f955ec336b5f769281635ca638e8add5564e6ed78b6d5cbf1310`,
and untracked composition/runtime/tests hashes
`707a30cdb8a540e28a5a02176c77bb751503a8845218947b6527fbe697806ff6`,
`11b4277578448a692e7c969eacdb42f63146716ab59a13cb13f409182866b5bd`,
and `0b31a505069c5b89fbe4b92e21195e0904a4deb31801ada72d4ab720456da7df`.
It then completed this exact serial package-gate sequence:

| Historical validation after RETASK #4 | Result | Exact log SHA-256 |
| --- | --- | --- |
| `MOTION` | passed — `swift test --filter PlotterManualMotionEpisodeTests`; 9/9 tests passed | `46e903c4887afccb8a923bc24c1d15a25580f4d49e092af9cb833970bc2d2668` |
| `DELETE` | passed — `sh Scripts/check_episode_cutover.sh EA-06`; all 26 exact scans had zero matches | `b841daa4968ac8fa3bb03058663abc9e8fbcab9fd5d65487b6fb2aa786afb04e` |
| `DOC` | passed — `make docs-check`; both documentation contracts plus 29/29 documentation/checker tests passed | `165e67df305197f32573dda575d5a962b652e2994000adde1435ae64db1f2f4a` |
| `DIFF` | passed — `git diff --check`; clean with no output | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `QUICK` | passed — `make quick-test`; 689/689 tests passed with exactly 10 configured exclusions | `b76e6eb98482633fce2b8e5fa7e77ccb0ca0f8377e9a3937c7cdf4caf5a760c7` |
| `JOURNEY` | passed — `make journey-test`; 10/10 filter-selected tests passed | `a67d2ebf0cc79d60b0ab7a04fa36514154f0eb8e0488ab76b3db664b2843fb46` |
| `STRICT` | passed — `make strict-check`; strict-concurrency/warnings-as-errors, 699/699 tests with no exclusions, both documentation contracts, and 29/29 documentation/checker tests passed | `91fbd693409017c51d64e347766297b9a19fd6f5bab08a88b54b5d53db7172c0` |

This full pass is historical evidence only for the exact RETASK #4 identity set
above. RETASK #5 and its accepted source correction superseded it at that time.
The exact RETASK #5 five-bound candidate identified by tracked diff
`0b2b2c477f8a9e0d66a25fcdd9472cfb56a71d69da21eef33a93c14131d4eda4`,
the same NUL-delimited status, and the composition/runtime/test hashes
`707a30cdb8a540e28a5a02176c77bb751503a8845218947b6527fbe697806ff6`,
`07231e76f5a228598c99ffefc8726c80d1c0e4f7df0f35db5cec0ade1c88c6f0`,
and `9928d135f9c226280a82f51c7bfc701f0d3433e683692deee7c46239cebc071c`
completed this serial package-gate sequence:

| Historical validation after RETASK #5 | Result | Exact log SHA-256 |
| --- | --- | --- |
| `MOTION` | passed — `swift test --filter PlotterManualMotionEpisodeTests`; 11/11 tests passed | `67616011ecfe0439498f8249acc831768036ecc9c9181c2f4e9d8ae8a8e8ff9b` |
| `DELETE` | passed — `sh Scripts/check_episode_cutover.sh EA-06`; all 26 exact scans had zero matches | `b841daa4968ac8fa3bb03058663abc9e8fbcab9fd5d65487b6fb2aa786afb04e` |
| `DOC` | passed — `make docs-check`; both documentation contracts plus 29/29 documentation/checker tests passed | `75442517166490b5410f0bafa1cf6f532341a2e85915c46b87ba0b3f2da776d5` |
| `DIFF` | passed — `git diff --check`; clean with no output | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `QUICK` | passed — `make quick-test`; 692/692 tests passed with exactly 10 configured exclusions | `61334548a852aedd1250a2f408d9453eff0720f3192ee506d748e5da29e28163` |
| `JOURNEY` | passed — `make journey-test`; 10/10 filter-selected tests passed | `ea66db8f0d68d7dff76df5e99c98733bcc3a2aed541ed8e9fd6fb88e8a6cc7da` |
| `STRICT` | passed — `make strict-check`; strict-concurrency/warnings-as-errors, 702/702 tests with no exclusions, both documentation contracts, and 29/29 documentation/checker tests passed | `7a5b7dddad8258595c4783328cd5badcb9715bb7b065588d791ea5785af5bd0d` |

This full pass is historical evidence only for that exact RETASK #5 identity
set. RETASK #6, Option A, and the current seven-gate sequence above supersede
it. The same critic's delta-only cited-findings recheck is closed with
`CITED_RACE_CLOSED`; no new or full critic was commissioned and no further
critic is required or allowed. Blackdog landing, canonical-`main` cleanup
verification, and successor-capsule creation remain pending. No attended
controller, camera, motion, Pen, paper, operator-click, or observed-ink
validation occurred, and no physical evidence is claimed.

The task-local ledger/checker/capsule fixture mechanically projects EA-07 as
the post-landing frontier because EA-06 is staged complete and EA-07 depends
only on EA-06. EA-07 becomes eligible only after all seven gates pass on the
exact Option A candidate, the final evidence delta's affected gates are
refreshed, EA-06 lands through Blackdog, canonical `main` is verified clean, and
the successor capsule is generated there. The same-critic delta closure is
already recorded; no further critic is required or allowed. This task does not
select or dispatch EA-07.

| Candidate package | Blackdog task | Current gate state | Landing boundary |
| --- | --- | --- | --- |
| EA-06 | `TASK-FE9C9CB3` | `DOC`=rerun-required, `DIFF`=rerun-required, `QUICK`=rerun-required, `JOURNEY`=passed, `STRICT`=rerun-required, `MOTION`=passed, `DELETE`=passed | The exact frozen tree passed all seven gates. Refresh affected `DOC`, `DIFF`, `QUICK`, and `STRICT` on this final evidence candidate as part of Blackdog landing, then replace this staged candidate with ordinary passed evidence after canonical `main` is verified clean; `CITED_RACE_CLOSED` already closes the critic boundary and no further critic is required or allowed. |

Canonical routed-document review dispositions for the EA-06 evidence integration:

- Affected task documents across the accepted EA-06 slice: Product Contract,
  Episode Architecture Execution Plan, Current Evidence, and Swift
  Architecture. RETASK #6 changes all four plus the executable contract checker:
  it records pre-start `cancelledBeforeStart`, observed/settling
  `settledByShutdown`, runtime-phase ambiguity disposition, the exact manual
  recording topology, Option A's shutdown latch, and the pending gate/closed-
  critic boundary. RETASK #4's
  lossless applied-open and capability-only terminal-publication recovery and
  RETASK #5's requested-owner shutdown takeover/FIFO correction remain accepted
  historical slices, while all prior package-wide green evidence is superseded.
  This final-gate integration changes the Execution Plan, Current Evidence, and
  executable contract checker. Product Contract and Swift Architecture were
  reviewed unchanged because their Option A ownership/topology text remains
  accurate.
  The plan still retires historical INT-004, INT-005, GRD-004, and UI-003 authority,
  preserves the exact EA-06 zero-match scan set, and routes current draft,
  controller-safety, Learning-travel/Pen, and typed UI seams to their later
  owners.
- Reviewed no change — `README.md` and Document Routing (`docs/INDEX.md`): the
  camera-first orientation and routing authority remain accurate.
- Reviewed no change — Discovery and Observed-Trial Protocol and Learning Path
  Button Transitions: EA-06 changes workbench manual controls, not the current
  Learning sequence, button vocabulary, exercise Cancel, or contextual Stop
  ownership.
- Reviewed no change — Episode Architecture Vocabulary: `Cutover`, typed
  intent, exact owner, Stop capability, LIVE/SIMULATED, and possible-ink target
  definitions did not change.
- Reviewed no change — Attended Hardware Runbook: no physical procedure or
  attended evidence changed or was executed.
- Reviewed no change — Roadmap: the existing migration milestone structure and
  unfinished physical boundary remain accurate.
- Reviewed no change — `AGENTS.md`, `blackdog.toml`, `.gitignore`, the
  AdaptivePlotter and run-multi-agent-wave skills, their episode-migration and
  wave-coordination references, and conditional validation/generator scripts:
  EA-06 changes no repository routing, lifecycle, selection, lease, validation,
  landing, cleanup, ignore, authorization, or generation contract.
- Affected executable contract surface: `Scripts/check_episode_contract.py`
  requires the current source-retask identities and semantics, all six RETASK
  histories, the retained failed QUICK log, historical-only prior green
  sequences, the exact current seven-gate pass, the four affected reruns,
  `CITED_RACE_CLOSED`, and the staged candidate boundary with landing still
  pending and no further critic required or allowed.
- Reviewed no change — `Scripts/test_episode_wave_capsule.py`:
  its retained task edit still advances only the post-landing fixture to EA-07
  without dispatching it.
- Reviewed no change — `Scripts/check_episode_inventory.py`: its existing
  completed-package retirement rule and exact live guard/UI equality checks are
  sufficient for the completed ledger row.
- Reviewed no change — `Scripts/check_episode_cutover.sh`: the wrapper remains
  generic; the package-specific EA-06 scans live only in the execution-plan
  manifest.
- Reviewed no change — `Scripts/episode_wave_capsule.py`: its literal-order
  frontier calculation already derives EA-07 from the staged ledger and cannot
  authorize dispatch before a clean landed capsule is created and consumed.

## Work package gate evidence

This table is machine-checked against every landed `complete` row in the
canonical execution-plan ledger. Gate names must match that package's required
gates exactly, and every recorded result must be `passed`. The sole temporary
exception is the explicitly named staged EA-06 candidate above: all seven gates
passed on the exact frozen Option A tree, while `DOC`, `DIFF`, `QUICK`, and
`STRICT` require refresh after this evidence delta. The same-critic delta is
closed; landing and clean-main verification remain pending. Detailed scope and
limitations remain in the named evidence section.

| Package | Blackdog task | Gate results | Evidence section |
| --- | --- | --- | --- |
| DOC-00 | `TASK-C86132F1` | `ARCHIVED=passed` | Historical: initial canonical episode migration documentation |
| DOC-01 | `TASK-F2387A9A` | `DOC=passed`, `DIFF=passed`, `CRITIC=passed` | Episode migration execution readiness |
| EA-01 | `TASK-513DC8A7` | `DOC=passed`, `DIFF=passed`, `INVENTORY=passed` | Episode current-source inventory |
| FIX-00 | `TASK-1B5992CF` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `STRICT=passed`, `FIX-CONTAINMENT=passed` | Coordinate settlement and containment split |
| FIX-01 | `TASK-05D1DCBD` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `STRICT=passed`, `FIX-APPLICABILITY=passed` | Tip applicability evidence authority |
| DOC-02 | `TASK-24BD26E8` | `DOC=passed`, `DIFF=passed` | Operator-accepted pre-migration checkpoint and development frontier |
| EA-02A | `TASK-55097CA4` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `CORE=passed` | EpisodeCore domain-generic foundation |
| EA-02B | `TASK-B6E16E08` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `PLOTTER-MODEL=passed` | Plotter episode model foundation |
| EA-03A | `TASK-439EDDB1` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `STRICT=passed`, `STORE=passed` | EpisodeStore foundation |
| EA-03B | `TASK-39BC99B5` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `STRICT=passed`, `RUNTIME=passed` | Episode operation registry foundation |
| EA-05A | `TASK-57FE4C62` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `STRICT=passed`, `RECORDING=passed` | Episode recording store foundation |
| EA-05B | `TASK-32F536F4` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `STRICT=passed`, `REPLAY=passed` | Episode deterministic replay foundation |
| EA-05C | `TASK-1DDBA6F2` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `STRICT=passed`, `INCIDENT=passed` | Episode incident package foundation |
| EA-04 | `TASK-A5FF364B` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `STRICT=passed`, `POINT=passed`, `DELETE=passed` | Episode point-selection cutover |
| FIX-02 | `TASK-30357281` | `LINK-OBS=passed`, `LINK-SAFETY=passed`, `RUNTIME=passed`, `JOURNEY=passed`, `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `STRICT=passed` | Machine-link transcript observability correction |

## Wave admission blockers

This is the sole machine-readable list of Current Evidence conditions that stop
an otherwise dependency-ready pending ordinary package from launching. A row
must name the exact package, the observed blocker, and the required user input
or canonical correction. The selector stops at that first eligible row; it
never skips ahead to later work. The empty table means Current Evidence adds no
admission blocker beyond the canonical ledger and live Blackdog claims.

| Package | Blocker | Required input or canonical correction |
| --- | --- | --- |

## Machine-link transcript observability correction

Delivered 2026-08-28 in Blackdog task `TASK-30357281`. FIX-02 corrects the
canonical transport-observability prerequisite before EA-06 without moving
product authority or installing the later recorder/adapter binding.

That landed correction changed the sole existing `MachineLink` protocol rather
than adding a sibling recording or observability port. Successful open returns
`MachineLinkOpenReceipt` with a transport-discriminated
`MachineLinkAppliedConfiguration`. `BSDSerialLink` reports the exact endpoint,
input/output baud, data bits, stop bits, `MachineLinkParity`,
`MachineLinkFlowControl`, local-mode state, and receiver state read back after
application in `MachineLinkBSDSerialAppliedConfiguration`. `SimulatedGRBLLink`
reports only `.simulated(identifier:)`; it does not manufacture baud, parity,
flow-control, or other serial facts.

Successful discard and write return `MachineLinkDiscardReceipt` and
`MachineLinkWriteReceipt` with exact byte counts. Successful read returns
`MachineLinkReadReceipt` with the exact bytes and the link-boundary
`receivedAtMonotonicNanoseconds: UInt64` sampled from that link's
`RuntimeClock`. `close()` is throwing, so close failure is no longer silently
discarded by the canonical contract. `MachineLinkError.discardFailed`,
`.writeFailed`, and `.readFailed` preserve operation-specific partial counts or
timestamped partial read receipts together with
`MachineLinkTransferFailureReason`; the contract does not infer zero progress
after a partial failure. The existing specific write timeout and cancellation
cases continue to preserve written and total byte counts.

The production-used `BSDPendingInputDiscarder` first observes the pending-input
snapshot, then drains that complete observed byte count through bounded reads.
It returns success only after every observed byte is discarded. A would-block,
disconnect, invalid read count, operating-system error, or exhausted bounded
`EINTR` retry budget instead returns exact `MachineLinkError.discardFailed`
progress, including zero or partial discarded counts and the observed total.
Only snapshot acquisition failure leaves the total unknown. The same production
termios mapper and discard core are exercised by applied-configuration and
discard regression tests rather than re-derived test-only logic.

`BSDSerialLink`, `SimulatedGRBLLink`, `BlockingMachineLink`, and all retained
controller/application/test conformers use the one revised protocol and forward
its receipts and errors. At the FIX-02 landing, there was no protocol default
implementation, alternate effect path, new semantic ingress, or installed
`RecordingMachineLink`.
`MachineController` still owns selected serial state, GRBL parsing, admission,
command serialization, settlement, and sticky ambiguity; `RunInterpreter`
still owns the current logical operation. Transport receipts are diagnostic
facts available to EA-06, not authorization, settlement, transcript-completeness,
or physical-effect evidence.

The completed frozen-tree gates are:

| Validation | Result | Scope |
| --- | --- | --- |
| `LINK-OBS` | passed — `swift test --filter MachineLinkTranscriptObservabilityTests`; 10/10 tests passed, 0 failed, with no warnings or errors | production-derived applied configuration and complete observed-snapshot discard, exact discard/write/read receipts, link-boundary monotonic receive time, forwarding, partial failures, and close failure |
| `LINK-SAFETY` | passed — `swift test --filter MachineLinkSafetyTests`; 12/12 tests passed, 0 failed, with no warnings or errors | machine-link write safety, close propagation, exact zero/partial discard failure, bounded interruption, partial transfer derivation, and transcript-observability integration |
| `RUNTIME` | passed — `swift test --filter EpisodeRuntimeTests`; 88/88 tests passed across 4 suites, 0 failed, with no warnings or errors | canonical EpisodeRuntime operation, store, recording, replay, and MachineLink integration coverage |
| `JOURNEY` | passed — `make journey-test`; 10/10 tests passed across 3 suites, 0 failed, with no warnings or errors | retained serial controller/operator journey behavior |
| `DOC` | passed — `make docs-check`; documentation and architecture contracts plus 29/29 documentation/checker tests passed, 0 failed, with no warnings or errors | ledger, evidence, architecture, checker, and capsule fixtures |
| `DIFF` | passed — `git diff --check`; exit 0, no output | complete FIX-02 diff |
| `QUICK` | passed — `make quick-test`; 665/665 tests passed with the 10 JOURNEY tests explicitly excluded, 0 failed, with no warnings or errors | repository quick suite and its declared JOURNEY exclusion |
| `STRICT` | passed — `make strict-check`; 675/675 Swift tests passed with no exclusions and 0 failed; strict-concurrency warnings-as-errors, app signing, launcher logic and validation, negative bundle, and documentation 29/29 passed with no warnings or errors | strict build, complete tests, signing, launcher, bundle, and documentation contracts |

The prior fresh read-only critic returned `RETASK`, not pass. Dimensions 1, 2,
3, 6, 7, and 10 passed; dimensions 4, 5, 8, and 9 failed. Dimension 4 found
swallowed close failures, dimension 5 found zero-progress and partial-transfer
derivation gaps, dimension 8 required production-derived observability tests,
and dimension 9 rejected the provisional canonical documentation. Those
source, test, and documentation findings were corrected and revalidated. The
first RETASK remains a nonpass historical verdict.

A second fresh read-only critic also returned `RETASK`, not pass. Dimensions 2,
3, 6, 8, and 10 passed; dimensions 1, 4, 5, 7, and 9 failed. It found that BSD
discard could report success without draining the complete observed snapshot,
zero-progress and partial discard failures were not exact, `EINTR` retry was
unbounded, production-derived applied-configuration and discard coverage was
deficient, and the resulting canonical evidence overclaimed completion. The
accepted source retask installs the production-used bounded
`BSDPendingInputDiscarder`, exact zero/partial/unknown-total failure semantics,
bounded interruption handling, and production-derived termios-mapper/discard
regression tests described above. The second RETASK remains nonpass history.

The second critic's source, test, and evidence findings were corrected, and all
eight gates above were rerun against the integrated frozen tree.

A later landing critic returned `RETASK`, not pass. Dimension 9 failed because
the execution plan described the pre-FIX-02 transport deficiency in present
tense while the as-built architecture, typed receipts, and complete ledger
correctly described the landed correction. That historical/current
contradiction was corrected by binding the deficiency to the EA-06 inspection
and describing FIX-02 as the current landed contract. This RETASK remains
nonpass history.

After that correction, the preceding fresh context-isolated critic returned
`ACCEPT`: all 10/10 dimensions passed with no material findings. Its permitted
`make docs-check` passed both contracts and 29/29 documentation/checker tests,
and `git diff --check` was clean. The critic performed no Swift test, build,
hardware, remote-Git, or lifecycle action and ended exactly `UNANIMOUS PASS — no
material disagreement`. This recorded verdict predates this critic-verdict
integration. A new final critic after this integration remains required; no
post-edit critic pass is claimed.

Canonical routed-document review dispositions for this correction:

- Affected: Episode Architecture Execution Plan, Current Evidence, Swift
  Architecture, executable episode contract checker, and capsule fixtures.
- Reviewed no change — Product Contract: its existing runtime-authority and
  controller-transcript inspectability requirements already own the durable
  product meaning; FIX-02 implements transport facts without changing it.
- Reviewed no change — README and Document Routing: contributor orientation and
  document ownership do not change.
- Reviewed no change — Discovery and Observed-Trial Protocol and Learning Path
  Button Transitions: no operator sequence, control, Stop, or recovery behavior
  changes.
- Reviewed no change — Episode Architecture Vocabulary: the receipt/error values
  are current transport types, not alternate target episode terms.
- Reviewed no change — Attended Hardware Runbook and Roadmap: no attended
  procedure, milestone structure, or physical evidence changes.
- Reviewed no change — `AGENTS.md`, `blackdog.toml`, `.gitignore`, the
  AdaptivePlotter and run-multi-agent-wave skills, and their execution and
  coordination protocols: lifecycle, routing, selection, authorization, lease,
  landing, and cleanup rules remain unchanged.
- Reviewed no change — executable inventory, documentation-shell, cutover,
  pilot, final-gate, and capsule-generation scripts: no EA-01 inventory/cutover
  assignment, canonical-document inventory, final predicate, or generic capsule
  algorithm changes.

After this landing, `EA-06` is the first eligible ordinary WorkPackage. Its
dependencies `EA-04`, `EA-05C`, and `FIX-02` are complete, and Current Evidence
records no admission blocker. This statement selects or dispatches no work. No
attended controller, camera, motion, Pen, paper, operator-click, or observed ink
validation occurred, and no physical or remote-Git evidence is claimed.

`package FIX-02 complete; migration remains incomplete` is the completion
statement for this landing, substantiated by the exact gate evidence above.

## Episode point-selection cutover

Delivered 2026-08-27 in Blackdog task `TASK-A5FF364B`. EA-04 replaces the
application-owned point-selection state, view closures, and continuation tasks
with one production episode composition. It does not create a parallel path.

`PlotterIntentGateway` is the stateless typed decision boundary.
`PlotterPointSelectionRuntime` is the single actor owner for its
`EpisodeStore<PlotterEpisodeReducer, PointSelectionJournalPersistence>`,
`PlotterOperationRegistry`, exact staged-frame map, optional
`EpisodeRecordingStore`, active pen-cap continuation, and copied
`PlotterEpisodeProjection`. One FIFO mutation/publication boundary surrounds
every mutation and projection read. Concurrent submissions therefore
re-evaluate the state serialized by the preceding mutation instead of acting on
one copied admission decision. Staging cancels the superseded request, records
the exact camera frame when recording is available, commits the frame
observation, and stages the typed `PlotterPointSelectionRequest`.

`PointSelectionJournalPersistence` retains the `plotter-point-selection-journal-v1` schema and uses a macOS-14-compatible `OSAllocatedUnfairLock` compare-and-swap commit.
The episode model and runtime contain no `@unchecked Sendable` escape hatch. Production creates a recording UUID under Application Support at
`AdaptivePlotter/EpisodeRecordings/<recording UUID>` and opens the EA-05A store
with a 64-unique-frame, 512 MiB retention policy.
Store startup failure and per-stage archival failure remain visible nonblocking diagnostics.
Recording is never safety, evidence, or exact-frame authority; acceptance remains
available with a diagnostic when bytes could not be archived.

Submission fails closed before mutation when request identity, source, camera
configuration, frame identity/hash/layout, presentation revision/bounds, or
request capacity is stale.
The production ActionSurface click path uses `ExactFramePointSubmissionBuilder.submission`: point geometry comes from the current viewport, while authority identity comes from the staged request's exact `request.presentationTransformRevision`; the builder owns no admission authority.
The current request admits and a replaced request typed-refuses at the runtime boundary.
One accepted selection becomes publicly visible only after the select event, point observation, and accepted `PlotterEvidence` with class `.operatorAssertion` have all committed.
Projection reads use the same FIFO boundary, so no caller can observe a partially committed accepted selection.
Pen-cap sampling is owned by runtime `PlotterPenCapPointSampler`; its accepted result carries the exact `DisplayedFrame` used for sampling to the app adapter. Sparse-tip selection uses the same runtime for staged points,
undo, clear, four-point capacity, and the accepted batch.
`SparseTipCalibrationCoordinator` retains machine-position association,
calibration fitting and acceptance. No accepted point is inferred from a
camera, simulator, or recording diagnostic.

The pen-cap continuation is registered in the exact-workflow lane with its full
operation identity, start attribution, move-only permit, Stop capability, and
operation-bound completion.
`PlotterLearningIntentRules.modeAvailability` is the one pure availability rule
used by both the evaluator and immutable
workspace presentation. `submitLearningModeChange` has no local guard: every
operator click is sent through `PlotterLearningModeIntentSink`, and the
runtime commits either its typed acceptance or typed refusal with a visible remedy.
The button remains invokable when refusal is predicted, displays that remedy, and has no local guard or silent no-op.
`PlotterPointSelectionRuntime.setLearningEnabled` accepts a typed `PlotterLearningActivityFactProviding`, obtains a fresh fact inside the FIFO boundary for initial evaluation, and reacquires a fresh fact after exact continuation cancellation before reevaluation.
`OperatorWorkspace` passes that provider through the Task hop instead of capturing an activity fact before the hop.
`PlotterPointSelectionActivityOwner(selectionID: PlotterPointSelectionID, exerciseAttemptID: UUID)` binds the exact owner used by both the initial and post-suspension fresh-fact evaluations.
The same item and selection with a successor exercise-attempt token typed-refuses, and the workspace rechecks that exact attempt identity before post-runtime attempt cancellation.
Learning Off is admitted only as the one typed accepted click that owns EA-04 exact selection/pen-cap continuation.
For a latched continuation, the FIFO boundary remains held while the runtime latches that exact owner, awaits `registry.stop`, and privately clears the runtime continuation handle without publishing episode-state mutation.
It then reacquires a fresh typed activity fact, and the gateway reevaluates the bound exact owner against the still-private `.continuing` plus `continuationIsActive` state.
An admitted Off commit clears the selection. A successor or unrelated refusal first publishes inactive continuation and then the final typed refusal behind the same FIFO boundary, so no caller sees partial state and later settlement cannot revive the continuation.
For that continuation path, `setLearningEnabled` returns only after registry settlement and final publication; there is no replacement settlement helper, poll, sleep, or state variable.
Focused tests assert the immutable returned/current projection plus observable continuation-port state.
`PlotterLearningIntentRules.modeAvailability` independently admits the exact exception only for `.collecting` or for `.continuing` with `continuationIsActive`; `OperatorWorkspace` emits a point-selection activity owner only for those same phases.
Retained `.accepted` Pen first-question/discovery and sparse batch/calibration attempts typed-refuse even when a caller supplies a matching owner.
Unrelated calibration, exploration, motion, or exercise-attempt work instead typed-refuses through the sole pure `PlotterLearningIntentRules.modeAvailability` rule.
`ActionSurface` sends only inverse-transformed click submissions through the click-only `PlotterPointSelectionIntentSink`.
Retained `OperatorWorkspace` undo, clear, and cancel action adapters invoke the same runtime/store authority; those actions do not originate in `ActionSurface` or the sink protocol.
`OperatorWorkspace` retains only the
projection/adaptation boundary: it copies `PlotterEpisodeProjection`, converts
an accepted cap sample into the existing `PenCapAppearanceSelection`, and hands
it to the retained camera/Vision reconfiguration path. Its
`learningModePresentation` is projection-only. The remaining direct SwiftUI
`UI.learningModePresentation` consumer is retained under inventory item UI-008
for the future EA-09 presentation cutover and owns no semantic or guard
authority.

`PointSelectionPresentationContext`, its copied request/admission comparison, and the Task-returning app cancellation helper are deleted.
`submitCurrentPenCapPoint` and `OperatorWorkspace.awaitPenCapAcceptedClickTransition` are also deleted; focused tests use generic point submissions and bounded observable-state waits.
The app's
`frozenPointSelectionFrame` bytes remain presentation-only, while
`pendingToolContactEvidence` remains adapter data for the retained sparse-tip calibration fit. Neither is point-selection admission or accepted-evidence
authority; the app cancellation helper is now async and awaits the runtime owner directly.

`CameraCapture` still owns device discovery, capture, and exact stamped frames;
`CameraSourceSession` and the
existing Vision owner retain analysis configuration; the artifact stores retain
persistence; `MachineController` and `RunInterpreter` retain device, motion,
Pen, safety, and settlement; and the calibration coordinators retain fitting
and artifact acceptance. The episode cutover does not promote recording or
simulation to LIVE evidence and does not move any physical authorization.

The focused `PlotterPointSelectionEpisodeTests` suite discovered and passed 11/11 tests, exit 0,
with a 0.23-second build, 0 failed, suite 0.206 seconds, run 0.206 seconds, and no warnings or errors. It
covers exact identity/source/configuration/presentation/bounds/capacity
refusals; production-ingress staged-revision identity; accepted observation, operator-assertion evidence, and projection;
exact pen-cap frame recording; Learning-Off cancellation and non-revival;
fresh exact-owner Learning activity reacquisition, successor-attempt refusal, and retained `.accepted` refusal across private continuation settlement;
sparse-tip undo, clear, and four-point acceptance;
concurrent FIFO re-evaluation; transaction-complete public projection; and strict
LIVE/SIMULATED provenance separation, checked journal synchronization, and the scoped absence of unchecked Sendable conformance.
The app-level direct-authority test deterministically holds camera reconfiguration until projection is `.continuing` with `continuationIsActive`, then proves Learning Off cancels the exact attempt without changing machine authorization or accepted artifacts.
Settled accepted-request refusal remains separate focused coverage.

Static inspection found 29 capsule/checker test methods. The untracked focused file contains eleven `@Test` methods.
EA-04 adds eleven net Swift tests to the preceding 644/654 baselines, producing final `QUICK` 655/655 and `STRICT` 665/665 measurements.
The DELETE gate proves all 36 exact EA-04 cutover scans have zero matches,
including the removed request/state types, selection and Learning closures,
presentation context/admission comparison, Task-returning cancellation helper,
continuation tasks/identities/helpers, stale guards, `submitCurrentPenCapPoint`,
`OperatorWorkspace.awaitPenCapAcceptedClickTransition`, the high-level
`submitPenCapClick` fixture seam, and the scoped `@unchecked Sendable` prohibition across the episode model and runtime.
The task-owner/polling semantic-deletion scan also proves `awaitContinuationSettlement` is absent from the episode runtime and tests.

The prior fresh read-only critic returned `RETASK` with 2/10 dimensions passing; it was not a pass or final verdict. Its source findings were corrected before the frozen evidence above.
A later fresh read-only critic returned `RETASK` with 5/10 dimensions passing (4, 5, 7, 8, and 10); its failures required source, UI, runtime, and canonical-document corrections.
A subsequent fresh read-only critic also returned `RETASK` with 5/10 dimensions passing (3, 4, 5, 8, and 10); its exact-owner, semantic-deletion, synchronization, and canonical-document findings were corrected in this candidate.
A fourth fresh read-only critic returned `RETASK` with 8/10 dimensions passing (1, 2, 3, 4, 5, 6, 8, and 10); failures in dimensions 7 and 9 required the waiter deletion and canonical corrections recorded here.
Those four pre-`ACCEPT` `RETASK` results remain nonpasses and accepted/retasked slice evidence; none is rewritten as a pass or final verdict.
An earlier fresh read-only critic returned `ACCEPT`: all 10/10 dimensions passed.
Its permitted `make docs-check` passed the documentation and architecture contracts plus 29/29 documentation/checker tests, and `git diff --check` was clean.
It did not rerun SwiftPM and ended exactly `UNANIMOUS PASS — no material disagreement`.
The preceding final-tree critic returned `RETASK` with 9/10 dimensions passing (1, 2, 3, 4, 5, 6, 7, 8, and 10); dimension 9 failed on the canonical Product Contract contradiction.
The earlier 10/10 `ACCEPT` is preserved as history but superseded as the final landing verdict by that later contradiction.
The latest fresh critic returned `RETASK` with 7/10 dimensions passing (1, 2, 4, 5, 7, 8, and 10); dimensions 3, 6, and 9 failed on the settled-owner runtime and canonical-description mismatch.
After the settled-owner and Product Contract corrections, the current final fresh critic returned `ACCEPT`: all 10/10 dimensions passed.
For this current verdict, permitted `make docs-check` passed the documentation and architecture contracts plus 29/29 documentation/checker tests, and `git diff --check` was clean.
The critic did not rerun SwiftPM and ended exactly `UNANIMOUS PASS — no material disagreement`.
No transient critic report, including the current final report, is checked in.

After this landing, `EA-06` is the first eligible ordinary WorkPackage. Its
dependencies `EA-04` and `EA-05C` are complete, it is the first
dependency-ready pending ordinary row in canonical ledger order, and Current
Evidence records no admission blocker. This statement selects or dispatches no
successor work.

Canonical routed-document review dispositions:

- Affected: Product Contract, Episode Architecture Execution Plan, Current Evidence, Swift Architecture, the executable episode contract checker, executable inventory checker, and capsule fixtures.
  `Scripts/check_episode_inventory.py` adds completed-package retirement behavior while retaining pending DELETE and every retain/adapt obligation as live, and admits the scoped `forbidden-conformance` scan class.
  `Scripts/test_episode_wave_capsule.py` advances the frontier fixture from `EA-04` to `EA-06`; the static capsule/checker method count remains 29.
- Reviewed no change — `README.md` and Document Routing (`docs/INDEX.md`): the
  existing camera-first contributor orientation and document ownership remain
  accurate.
- Reviewed no change — Discovery and Observed-Trial Protocol and Learning Path Button Transitions: bounded inspection found no conflicting global Learning-Off admission statement; both retain button-owned Cancel/Stop and the existing exercise flow without weakening operator authority.
- Reviewed no change — Episode Architecture Vocabulary: the exact-owner
  exception uses existing canonical terms and adds no parallel semantic owner.
- Reviewed no change — Attended Hardware Runbook and Roadmap: no physical
  procedure or milestone structure changed, and no attended controller, camera,
  motion, Pen, paper, operator-click, or ink evidence was produced.
- Reviewed no change — `AGENTS.md`, `blackdog.toml`, `.gitignore`, the
  AdaptivePlotter and run-multi-agent-wave skills, episode-migration and
  wave-coordination protocols, and conditional validation/generator scripts:
  EA-04 changes no routing, lifecycle, selection, lease, validation, landing,
  cleanup, ignore, or generation contract.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; documentation and architecture contracts plus 29/29 documentation/checker tests passed with no warnings | ledger, evidence, architecture, inventory retirement behavior, checker, and capsule fixtures |
| `DIFF` | passed — `git diff --check`; exit 0, no output | complete package diff |
| `QUICK` | passed — `make quick-test`; 655/655 tests passed with exactly 10 configured exclusions and no warnings | repository quick suite and declared exclusions |
| `STRICT` | passed — `make strict-check`; 665/665 Swift tests plus 29/29 documentation/checker tests passed with zero exclusions or warnings; warning-as-errors build, signing, launcher, negative-bundle, and documentation checks passed | strict build, complete tests, signing, launcher, bundle, and documentation contracts |
| `POINT` | passed — `swift test --filter PlotterPointSelectionEpisodeTests`; exit 0; build 0.23 seconds; 11/11 discovered and passed; 0 failed; suite 0.206 seconds; run 0.206 seconds; no warnings or errors | production-ingress staged-revision identity/refusal, FIFO-held private continuation settlement, deterministic app continuation cancellation, retained-accepted refusal, semantic deletion, scoped Sendable safety, sparse selection, and environment separation |
| `DELETE` | passed — all 36 exact EA-04 source and fixture scans returned zero matches | removed point-selection state, presentation/admission copies, Task-returning cancellation, closures, tasks, guards, helper ingress/wait/poll seams, fixture seam, and scoped unchecked conformance |

`package EA-04 complete; migration remains incomplete` is the completion
statement for this landing, substantiated by the exact frozen-tree results
above. No attended physical or remote-Git action occurred, and no physical
evidence is claimed.

## Episode incident package foundation

Delivered 2026-08-26 in Blackdog task `TASK-1DDBA6F2`. The frozen-tree gate set passed as recorded below, and the package is complete on this landing. Every
row names the exact command and reproduced result; disagreement with that frozen
evidence invalidates the row rather than changing the measurement.

The internal `PlotterEpisodeRuntime` target now contains one pure, unbound
`PlotterIncidentPackageAssembler`. A caller supplies one typed
`PlotterIncidentPackageSource` containing the manifest, semantic journal,
source-reported recording snapshot, observations, measurements, evidence
decisions, outcomes, assessments, runtime state, UI projection, current-owner
facts, artifact-status facts, sensitive-frame identities, and unresolved
ambiguities. The package embeds that snapshot as `sourceReportedRecording` and
records `sourceSnapshotNotRevalidated` in `recordingSourceFacts`. The assembler
also records source-reported open state, durability uncertainty, completeness
issues, and missing optional episode or environment provenance as diagnostic
facts. It returns a value envelope to that caller. It does not locate, read,
write, retain, delete, redact, or materialize any artifact and does not own an
export destination.

Assembly fails closed on cross-episode or cross-manifest identity, including an
explicit foreign episode ID in any recording entry; invalid or duplicate typed
identities; journal/semantic-value disagreement; runtime revision or independent
canonical-digest disagreement; missing or extraneous exact artifact-availability
facts; incomplete evidence/outcome/assessment
relationships; incomplete current-owner-domain coverage; and foreign or
malformed ambiguity facts. Assessment evidence is restricted to evidence accepted by its referenced outcome.
Accepted observation evidence `inputEnvironment` must equal the referenced observation environment.
Accepted measurement evidence `inputEnvironment` must equal every source observation environment.
This package-level referential closure preserves LIVE/SIMULATED truth without moving evidence-acceptance authority.
Every `possibleInk` or `unclear`
measurement requires one exact typed linked unresolved possible-ink ambiguity;
missing, duplicate, foreign, and spurious links are refused.

The assembler never certifies or revalidates recording format, controller, camera, lifecycle, frame descriptors, frame layout, frame hashes, frame paths, duplicate store records, `RunLedger`, or store completeness truth.
Recording, artifact, controller, camera, runtime/UI, and
possible-ink incompleteness remains typed diagnostic truth; it is never promoted
to completeness or physical evidence.

The standard budget bounds every section, total included items, embedded
recording bytes, referenced-frame bytes, and encoded export bytes.
`maximumReferencedFrameByteCount` independently bounds checked referenced-frame
bytes. Count and byte arithmetic is checked. Limit excess refuses rather than
truncating, so the accepted package records identical source/included counts and
`isTruncated` false. Exact frame bytes are never embedded.
The package checks only incident-package sensitive-ID linkage, checked referenced-byte accounting,
and the independent referenced-byte limit. Frame references, descriptors,
availability diagnostics, and byte/count facts remain source-reported and are not frame-store validation; their disposition is `referenceOnly` or
`sensitiveReferenceOnly`.

Successful assembly emits deterministic sorted-key `canonicalJSONV1` payload
bytes in format version 1 with exact byte count and SHA-256. Canonical envelope
verification returns `envelopeIntegrityConfirmed` only after the envelope
version, encoding, bound, byte count, digest, decodability, canonical encoding,
package version, and exact deterministic reassembly agree. It
proves only deterministic versioned byte integrity and canonical reassembly; it does not
certify or revalidate the source recording's store-owned truth.

This Foundation service has no product or application caller and is not a
package product. It adds no UI, app ingress, artifact store, filesystem adapter,
device port, `MachineLink`, controller/camera/Vision operation, effect execution,
permit, Stop/cancellation owner, recording owner, replay owner, journal owner,
evidence acceptance owner, or current-authority transfer. In particular, it
does not implement the later EA-09 UI request/progress/result presentation and
does not prove that referenced bytes exist or that any controller, camera,
motion, Pen, paper, click, or ink event occurred.

The accepted source and focused-test slice passed
`swift test --filter PlotterIncidentPackageTests`: 23/23 tests passed, exit 0,
build 95.98 seconds, test execution 0.155 seconds, with no warnings. The suite
covers deterministic envelope integrity, tamper refusal, explicit foreign
episode and duplicate identity refusal, non-authoritative recording diagnostics,
accepted-evidence environment closure, outcome-scoped assessment evidence, exact
artifact closure, sensitive-ID linkage, source-reported frame diagnostics,
runtime/UI revision diagnosis, independent count/byte and integer-overflow
refusal, exact possible-ink ambiguity linkage, and the forbidden-authority
boundary.

Static inspection found 29 capsule/checker test methods. Starting from the
landed EA-05B measurements, the 23 added Swift tests produced the final
`QUICK` 644/644 and `STRICT` 654/654 measurements; the documentation result is
29/29. The completed frozen-tree commands reproduced every count, exclusion,
warning, component, and exit result recorded below.

After this landing, `EA-04` is the first eligible ordinary WorkPackage.
Its dependencies `EA-03B` and `EA-05B` are complete, it is the first
dependency-ready pending ordinary row in canonical ledger order, and Current
Evidence records no admission blocker. This statement selects or dispatches no
successor work. The wave generates the successor capsule only after verifying
the landing on canonical `main`; that lifecycle step does not qualify EA-05C's
recorded package completion.

Canonical routed-document review dispositions:

- Affected: Episode Architecture Execution Plan, Current Evidence, Swift
  Architecture, the executable episode contract checker, and the capsule
  fixtures whose selected package/frontier assertions advance to `EA-04`.
- Reviewed no change — `README.md` and Document Routing (`docs/INDEX.md`): the
  unbound internal value service changes neither operator/contributor
  orientation nor document responsibility/routing.
- Reviewed no change — Product Contract and Episode Architecture Vocabulary:
  the existing bounded incident-package and `EpisodeTrace` target semantics
  already cover this Foundation implementation; it adds no target term or
  product authority.
- Reviewed no change — Roadmap, Discovery and Observed-Trial Protocol, and
  Learning Path Button Transitions: there is no product caller, operator action,
  current workflow, UI control, or state-transition change.
- Reviewed no change — Attended Hardware Runbook: no physical procedure changed
  and no attended controller, camera, motion, Pen, paper, click, or ink evidence
  was produced.
- Reviewed no change — `AGENTS.md`, the AdaptivePlotter skill,
  episode-migration protocol, run-multi-agent-wave skill, and wave-coordination
  protocol: the package changes no Blackdog lifecycle, package-selection, lease,
  validation, critic, landing, or cleanup mechanics.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; documentation and architecture contracts plus 29/29 documentation/checker tests passed with no warnings | ledger, evidence, architecture, checker, and capsule fixtures |
| `DIFF` | passed — `git diff --check`; exit 0, no output | complete package diff |
| `QUICK` | passed — `make quick-test`; 644/644 tests passed with exactly 10 configured exclusions and no warnings | repository quick suite and declared exclusions |
| `STRICT` | passed — `make strict-check`; 654/654 Swift tests plus 29/29 documentation/checker tests passed with zero exclusions or warnings; warning-as-errors build, signing, launcher, negative-bundle, and documentation checks passed | strict build, complete tests, signing, launcher, bundle, and documentation contracts |
| `INCIDENT` | passed — `swift test --filter PlotterIncidentPackageTests`; exit 0; 23/23 passed; build 95.98 seconds; test execution 0.155 seconds; no warnings | deterministic bounded incident assembly/envelope verification, fail-closed package relationships, environment and ambiguity closure, non-authoritative recording/frame diagnostics, and forbidden authority |

`package EA-05C complete; migration remains incomplete` is the completion
statement for this landing, substantiated by the exact frozen-tree results
above. No attended physical or remote-Git action occurred, and no physical
evidence is claimed.

## Episode deterministic replay foundation

Implemented 2026-08-26 in Blackdog task `TASK-32F536F4`.

The internal `PlotterEpisodeModel` target now owns
`PlotterEpisodeCanonicalDigestV1`, an independent sorted-key canonical digest
over the replay-relevant Plotter episode state. It deliberately excludes the
state's stored digest field, so a copied or self-consistent forged stored digest
cannot validate itself. This remains compile-only model authority with no
runtime, persistence, device, UI, application, or effect-execution owner.

The internal `PlotterEpisodeRuntime` target now contains one unbound
`PlotterEpisodeReplayService`. Its sealed
`PlotterEpisodeReplayExecutableDescriptor` is instantiated by the private
`PlotterEpisodeReplayExecutableAdapter`; no replay entry point accepts either
the descriptor or executable revision labels from a caller. The concrete
executable therefore owns its domain, evaluator, reducer, state/event/journal
schema, and build revision facts plus its canonical-digest revision. It also
declares that this concrete executable does not consume the deterministic seed.
Replay compares the corresponding sealed executable facts with the manifest
domain/evaluator/reducer/schema/build pins. The descriptor's canonical-digest
literal is additionally pinned to `PlotterEpisodeCanonicalDigestV1.revision`
before any prefix reduction. It separately
compares the manifest definition ID and revision with the supplied typed
definition. Caller metadata cannot spoof executable agreement.

Caller-supplied `PlotterEpisodeRecordedEffectRevision` values are recorded identity only; their typed authority is
`recordedIdentityOnlyNoExecutorValidation`. They must cover each emitted effect
exactly once and bind progress/result identity plus first-terminal ordering, but
they do not claim that the replay build supports an effect-executor revision.
Replay has no effect executor. It also refuses journal identity, revision,
sequence, or stored-digest disagreement, independent canonical-digest
disagreement, and a committed decision that does not match caller-supplied
recorded candidate intents and capability facts. It reduces every journal prefix from zero through the complete journal twice through the production
`PlotterEpisodeReducer`, verifies deterministic equality and independent
canonical state truth at each prefix, and retains emitted effects only as inert
typed values. Invalid effect-lifecycle prefixes fail closed and are not
published as accepted replay prefixes.

Effect inspection preserves the complete episode, intent request, typed intent,
effect ID and revision, correlation, and environment identity. It requires
first-terminal ordering and rejects a stale revision, identity disagreement,
duplicate or conflicting terminal evidence, and an unattributed start. A
journal progress record, controller invocation, or camera lifecycle request can
establish that an effect may have started. A started but unsettled effect is
classified as a possible physical effect and every prefix receives an explicit
never-resume disposition. Replay executes no effect, mints or restores no
permit, and cannot turn that conservative classification into proof that a
physical effect occurred.

Recording inspection reconstructs the durable `EpisodeRecordingStore` snapshot
without changing it and keeps controller, camera, `RunLedger`, and global
completeness separate. Preserved source entries and refusal checks expose
controller transcript completeness, byte/order integrity, and operation
provenance without conflating them. Recorded start attribution requires exactly
one complete available operation-bound provenance tuple; absent, partial,
foreign, or ambiguous matches remain unattributed. Missing, truncated, byte-count-mismatched, or hash-mismatched camera bytes remain typed incompleteness. Those conditions
cannot be presented as reconstructed image truth.
A `RunLedger` reference remains diagnostic-only sequence-range, integrity, and
completeness metadata; replay neither opens nor mutates the ledger and cannot
promote it into episode or physical authority.

Controller replay is a typed transcript-layer service, not a `MachineLink` and
not a production replay adapter. It provides exact unperturbed transcript replay
and accepts only the declared causality-preserving perturbations: legal read
fragmentation, completion delay, timeout, and cancellation. It preserves source
bytes, invocation/completion ordering, writes, operation provenance, and bytes
observed before a terminal boundary. Exact replay refuses a nil or empty
controller source. Scenario admission rejects completion delay combined with
timeout or cancellation for the same invocation independent of declaration
order. Timed-read delay checks the recorded deadline for both successful and
failed completions. Timeout and cancellation preserve the declared terminal
boundary and downstream source ordering. The source schedule is validated
before any transform; fragmentation refuses absent read traffic, and delay
refuses a non-read invocation. Completion delay retimes the completion and its
causal suffix, including embedded read chunks, with checked overflow. Terminal
replacement retimes that same causal suffix and chunks with checked underflow.
After every candidate transform,
global transformed-schedule causal validation checks the complete schedule
across all outstanding invocations. A transform for invocation A cannot push an
overlapping invocation B beyond B's timed-read deadline or move B's read traffic
before B's invocation. Any invalid complete schedule receives the typed
`invalidTransformedSchedule` refusal and publishes the unchanged source steps.
Replay also refuses invalid fragmentation, unknown or mismatched invocation or
completion, multiple terminal overrides, overflow or underflow, non-read or
unsuccessful-read terminal traffic, and perturbations that violate recorded
availability, deadlines, or causal ordering. The retained FIX-010 controller fixtures remain deterministic transcript consumers; they are not replaced or
promoted into production authority.

The source review initially found and retasked four material contract gaps:
manifest-to-executable revision binding;
full effect identity and first-terminal ordering;
causal controller timing and missing-source refusals; and
exact operation-bound recording provenance. The corrected accepted source slice
then passed its focused replay suite before the later critic retasks.

An earlier fresh source critic returned `RETASK`, not pass. It found that
executable facts were caller-asserted; failed-read completion delay could exceed
the timed-read deadline; declaration order could change the result of terminal
override plus delay; and nil or empty controller input could be accepted as
exact replay. The corrected source seals executable facts behind the private
adapter, rejects delay plus timeout/cancellation for one invocation
order-independently, enforces successful and failed timed-read deadlines,
preserves the exact terminal boundary and downstream ordering, and refuses nil or empty exact replay.

The replacement fresh source critic also returned `RETASK`, not pass. It found
that per-target transformation checks did not validate causal truth for the complete schedule when multiple controller invocations overlap. The corrected
source now validates every complete transformed schedule: delaying or
terminally replacing invocation A cannot push overlapping invocation B past B's
deadline or move B traffic before B's invocation. Adversarial overlapping-read coverage proves both typed `invalidTransformedSchedule` refusals and unchanged
source steps.

A later invocation then edited only the replay source and focused tests before
resolving the active owner. The owning coordinator invalidated all overlapping
validation, stopped further foreign action, performed read-only attribution,
classified the delta `RETASK`, and reconciled it non-destructively through the
original lease. The foreign edits were not accepted wholesale. The retained
strengthening pins the sealed descriptor's digest literal to
`PlotterEpisodeCanonicalDigestV1.revision`, prevents lifecycle-invalid prefix
publication, requires exactly one complete available operation-bound provenance
tuple for start attribution, prevalidates the source schedule, refuses absent
read traffic and non-read delay, and restores authoritative causal suffix and
chunk retiming with checked overflow and underflow. Both the overlapping
B-deadline and pre-invocation schedules typed-refuse and return unchanged source.

Corrected replay source
`8cedf8cd0826e8339aa8ad42cd16254cef58fd809ee5c4dc57e650df15dc18bb`
and focused tests
`19fd93508e55cc64ad9af0be8fc0febf856dd3747b93b04cb953515f047fb15e`
passed 14/14 replay tests with no warnings. The earlier critic `RETASK`
dispositions are historical checkpoints; this record does not preclaim a later
fresh-critic verdict. A fresh pass remains required before landing.

The package adds no effect executor, permit restoration, device port, current
controller/camera/operation/Stop authority, `MachineLink` conformance,
application composition, product caller, or app caller. `PlotterApp` does not
depend on either episode target.

The completed post-integration ordered gate set passed: focused replay 14/14
with no warnings; documentation and architecture contracts plus 29/29
documentation/checker tests; diff-check exit 0 with no output; quick 621/621
with exactly 10 configured exclusions and no warnings; and strict 631/631 plus
29/29 with zero exclusions or warnings. The warning-as-errors build, signing,
launcher, negative-bundle, and documentation checks also passed. Earlier on the pre-incident 630-test
source, one strict run completed its build but reported five unidentified issues.
A subsequent rerun had no retained output adequate to establish a result.
That intermittent validation-observability history is retained as a
nonfinal risk; it is not erased by the later captured clean current-source
strict measurement and establishes no physical evidence.
This record does not preclaim a fresh-critic verdict; a fresh pass remains
required before landing.

`package EA-05B complete; migration remains incomplete`.

At the EA-05B landing, `EA-05C` became the first eligible ordinary WorkPackage.
Its sole dependency `EA-05B` was complete, and it was then the first
dependency-ready pending ordinary row in canonical ledger order with no Current
Evidence admission blocker. This historical statement selected or dispatched no
successor work.

Canonical routed-document review dispositions:

- Affected: Episode Architecture Execution Plan, Current Evidence, Swift
  Architecture, and the executable episode contract checker.
- Reviewed no change — `README.md` and Document Routing (`docs/INDEX.md`): the
  unbound internal service changes neither operator/contributor orientation nor
  document ownership or routing.
- Reviewed no change — Product Contract and Episode Architecture Vocabulary:
  the package preserves existing replay/evidence invariants and promotes no new
  canonical target vocabulary; its descriptor names are as-built implementation
  facts.
- Reviewed no change — Roadmap, Discovery and Observed-Trial Protocol, and
  Learning Path Button Transitions: there is no app caller, product workflow,
  current operator sequence, UI control, or state-transition change.
- Reviewed no change — Attended Hardware Runbook: no controller, camera,
  motion, Pen, paper, click, ink, or other attended physical procedure or
  evidence class changed.
- Reviewed no change — `AGENTS.md`, the AdaptivePlotter skill, episode-migration
  protocol, run-multi-agent-wave skill, and wave-coordination protocol: the
  package changes no Blackdog lifecycle, package-selection, lease, validation,
  critic, landing, or cleanup mechanics.
- Reviewed no change at that landing — capsule fixture: its exact selected-row
  pointer count, parsed selected package-ID column `EA-05C`, completed-package
  evidence rejection, and admission-blocker assertions proved that historical
  frontier contract.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; documentation and architecture contracts plus 29/29 documentation/checker tests passed with no warnings | integrated ledger, package evidence, architecture, frontier, checker, and capsule contracts |
| `DIFF` | passed — `git diff --check`; exit 0, no output | complete documentation-integrated global-schedule candidate diff |
| `QUICK` | passed — `make quick-test`; 621/621 tests passed with exactly 10 declared exclusions and no warnings | repository quick suite with its declared exclusions |
| `STRICT` | passed — `make strict-check`; 631/631 Swift tests plus 29/29 documentation/checker tests passed with zero exclusions or warnings; warning-as-errors build, signing, launcher, and negative bundle checks passed | strict build, tests, signing, launcher, bundle, and documentation contracts |
| `REPLAY` | passed — `swift test --filter PlotterRecordingReplayTests`; 14/14 passed with no warnings or exclusions | sealed executable facts, every-prefix reduction, fail-closed lifecycle publication, recording-only effect revision identity, global transformed-schedule causal validation, causal retiming, overlapping-read refusals, inert effects, and exact provenance |

These are the completed ordered source, replay, build, test, and repository
measurements. A fresh critic pass remains required before landing. No attended controller, camera, Motion,
Pen, paper, operator click, observed ink, hardware,
or remote-Git activity was performed, and none of those evidence classes is
established by this package. No final fresh-critic pass verdict is recorded here.

## Episode recording store foundation

Implemented 2026-08-26 in Blackdog task `TASK-57FE4C62`.

The current internal SwiftPM target `PlotterEpisodeRuntime` depends directly on
`EpisodeCore`, `EpisodeRuntime`, `PlotterEpisodeModel`, and `PlotterRuntime`, is
not a package product, and has no production or application caller. EA-05A
established the recording service over the latter three dependencies; EA-05B
later added the direct `EpisodeCore` dependency for replay. Its unbound
`EpisodeRecordingStore` actor owns one typed recording document with contiguous
sequence allocation and nonregressing attributable monotonic offsets. It does
not register with or have a caller from `PlotterOperationRegistry`, execute an
effect, call a device, append an `EpisodeJournal`, or interpret a record as an
observation, measurement, evidence value, semantic event, progress, or physical
result.

Controller traffic preserves invocation and completion as separate typed
records for open, close, input discard, raw write, and timed read. Open and read
parameters, exact written bytes and returned chunks, typed failures, partial byte
counts, chunk offsets, timeout disposition, and operation matching remain
explicit. Duplicate or unmatched identities, mismatched completion kinds,
impossible partial results, invalid chunks, and regressing time are refused
before a document commit.

Camera lifecycle recording is a distinct typed channel for requested and
completed start, reconfiguration, and stop plus terminal failure. An exact frame
reference is accepted only while its source and configuration are the active
stream, and retains frame identity, sequence, capture time, dimensions, row
layout, and pixel format. Lifecycle failure does not manufacture a successful
transition, and closing does not fill an unfinished start, reconfiguration, or
stop.

Exact frame bytes are SHA-256 addressed under the admitted recording directory.
The relative path and byte count are digest-bound, equal bytes deduplicate
idempotently, and conflicting content cannot claim the same reference. The
store writes and synchronizes bytes before publishing their ordered reference,
then re-reads them. Missing, truncated, extra-length, hash-mismatched,
unreadable, symbolic-link, owner-mismatched, and externally hard-linked
artifacts remain distinct typed errors or completeness issues; reopen neither
repairs them nor treats them as Vision-replay support.

Persistence is anchored to an owner-matching open directory descriptor and its
device/inode identity. Replacing the pathname after admission therefore cannot
split later manifest, lock, and frame writes into another directory. A durable
initialization marker pins recording ID, schema revision, and the explicit
maximum unique-frame count and total-byte retention limits. A deterministic
sorted-key `Codable` envelope pins format version and payload checksum. Reopen
validates those values, document ordering, controller pairing, camera lifecycle,
frame references, retention, and the presence of an initialized manifest; it
does not silently accept an empty replacement for lost or corrupt recording
state.

Manifest creation and compare-and-swap commits use one in-process lock per
pinned directory plus a kernel `fcntl` writer lock. Inside that exclusion the
store compares the durable document with the expected base. For a frame commit
it then accounts the complete artifact inventory, durably installs and verifies
the frame bytes, and only afterward writes the mode-0600 same-directory manifest
temporary through partial-write and `EINTR` handling, performs `F_FULLFSYNC`,
atomically renames, and synchronizes the directory. A compare-and-swap loser
therefore installs no artifact, while a later definite manifest failure may
leave the already durable frame as a charged orphan without publishing its
reference. Actor serialization gives concurrent callers one contiguous order;
independent stores and a separate process cannot overwrite a successor committed
from the same base. The deterministic cross-process proof has the child acquire
the kernel lock and publish a ready handshake, then waits for the store's
immediately-before-lock commit-boundary handshake before installing its checked
successor. The bounded child-process and commit-attempt wait helpers terminate
or kill an overdue helper and return or time out without awaiting an unbounded
loser; a separate non-cooperative attempt proves the timeout path itself remains
bounded even when task cancellation cannot make that loser cooperate.

A failure before replacement leaves the prior document authoritative. A
post-rename directory-synchronization uncertainty is typed, records whether the
candidate was observed, and prevents every later mutation until reopen. The
same rule applies to close: close ends admission only if durably installed or
observably uncertain, while completeness remains independently inspectable.
Unmatched controller invocations, unfinished camera lifetimes, missing or
corrupt frame bytes, and incomplete or unverified low-level ledger ranges remain
visible instead of being filled or hidden.

Each entry may carry typed optional episode, intent-request, effect,
correlation, and LIVE/SIMULATED environment identities. Those fields are
diagnostic correlation only. A separate typed `RunLedgerDiagnosticReference`
records one existing ledger run and sequence range with explicit integrity and
complete or missing-range disposition. `EpisodeRecordingStore` never opens,
reads, writes, or promotes that `RunLedger`; the current SQLite diagnostic owner
and its ordered nonblocking `MachineController.ledgerWriteTail` remain unchanged.

The frame retention policy is explicit and pinned by the durable marker and
manifest. Admission accounts from the complete durable artifact inventory, not
only manifest references: every directory entry consumes one count and its
nonnegative filesystem byte length, including valid unreferenced artifacts and
unrecognized, unreadable, unsafe, hash-mismatched, or otherwise orphaned
artifacts. A manifest append failure can therefore leave a visible orphan that
continues to consume quota. Nothing automatically deletes an artifact.

Count increments and aggregate/proposed byte totals use checked fail-closed
arithmetic. An unrepresentable inventory total refuses every frame mutation,
including an apparent duplicate, with typed
`frameRetentionAccountingOverflow`; it publishes neither a manifest successor
nor a new artifact. Snapshot inspection maps the same condition to typed
`frameRetentionAccountingOverflow` incompleteness. A checksum-valid manifest
whose referenced-byte accounting overflows is corrupt recording state and is
refused on reopen rather than exposed as a usable snapshot. This is bounded
retention admission, not cleanup, automatic deletion, or evidence promotion.

The package deletes `StartupFrameRecorder`, its nested `Manifest`, and the sole
`manualCameraSnapshotPreservesExactFrame` high-level test. Source/test inventory
proved that recorder had no production or other remaining consumer, and the
completed source has zero source/test matches for all three assigned symbols. No
compatibility alias, second recorder, app camera-sample writer, or shadow durable
writer remains.

`MachineController` remains the selected serial, parsing, command-serialization,
safety, settlement, ambiguity, and `ledgerWriteTail` owner. `RunInterpreter`
remains the current logical operation owner. `CameraCapture` remains the current
camera discovery, authorization, selection, lifecycle, exact-frame, and preview-
hold owner. Existing `WorkflowTelemetryActions.record`,
`WorkflowTelemetryFixture`, `MachineSessionRetentionPolicy`, Vision, planning,
evidence, simulator, `OperatorWorkspace`, operation, Stop, and cancellation
authority are preserved and are not wired to the new service.

`PlotterRecordingStoreTests` now contains 36 focused adversarial tests. They cover
typed controller ordering and mismatch refusal; camera lifecycle and exact
stream binding; content-addressed deduplication, size admission, confinement,
missing/truncated/corrupt bytes, complete-artifact retention accounting, orphan
charging, checked arithmetic overflow, and bounded retention; descriptor-
anchored path replacement; serialized initialization; initialized-manifest
loss; deterministic provenance; typed `RunLedger` completeness; actor,
independent-store, and cross-process compare-and-swap; post-rename append and
close uncertainty; truthful close completeness; and envelope/checksum
corruption; deterministic cross-process lock/commit-boundary handshakes; bounded
helper and attempt completion; and non-cooperative timeout behavior. The accepted
final focused measurement passed all 36/36 tests with no warnings or exclusions.

`package EA-05A complete; migration remains incomplete`.

At the `EA-05A` landing, `EA-05B` became the first eligible ordinary
WorkPackage because dependencies `EA-03A` and `EA-05A` were complete. This
historical statement selected or dispatched no successor work.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; both contracts plus 14/14 documentation tests passed in 3.071s | canonical ledger, Current Evidence, architecture, frontier checker, and capsule contract |
| `DIFF` | passed — `git diff --check`; exit 0, no output | complete bounded package diff |
| `QUICK` | passed — `make quick-test`; 602/602 tests passed with exactly 10 intentional exclusions (3 `OperatorWorkspaceSparseTipCalibrationTests`, 4 `OperatorWorkspaceTests`, 3 `SimulatedLearningRuntimeTests`); no warnings | repository quick suite with configured exclusions |
| `STRICT` | passed — `make strict-check`; warnings-as-errors build, stable-local signing, launcher logic and validation, app-bundle validation, 612/612 tests, and documentation checks passed with no warnings | strict build, tests, signing, launcher, bundle, and documentation contracts |
| `RECORDING` | passed — `swift test --filter PlotterRecordingStoreTests`; 36/36 passed with no warnings or exclusions | typed recording, durable persistence, content-addressed frames, retention, concurrency, corruption, and completeness contracts |

All five required gates passed on the completed source-identical tree. This is
final source, focused-test, and repository evidence only. No
attended controller, camera, Motion, Pen, paper, operator click, observed ink,
hardware, or remote-Git activity was performed, and none of those evidence
classes is established by this package.

## Episode operation registry foundation

The original EA-03B implementation lineage is Blackdog task `TASK-9D49AAE0`.
The canonical contract correction was delivered 2026-08-26 by Blackdog task
`TASK-39BC99B5`.

The internal SwiftPM target `EpisodeRuntime` remains Foundation-only, depends
only on `EpisodeCore`, is not a package product, and has no production caller.
Its generic `PlotterOperationRegistry` actor owns one canonical operation
identity containing the episode ID, intent-request ID, typed intent identity,
effect ID, effect revision, and typed environment. Intent and environment
values are not duplicated in `PlotterOperationContext`; that context supplies
their associated types but stores only the owning subsystem and typed result
currently awaited.

Registration retains the supplied original typed operation handle and one typed
lane. The fixed lane roles are exclusive machine, exclusive exact-workflow
capture/Vision, bounded background analysis, and serialized durable append;
distinct typed lane configuration and capacity are enforced at admission.
Successful registration privately mints a structurally noncopyable one-shot
`EffectPermit`, an optional exact `StopCapability`, and an operation-bound
`CompletionCapability`. The noncopyable registration exposes the permit only
through consuming `takePermit()`, and start consumes it. No remint, copyable
effect-authority wrapper, or UI-state copy exists.

Start and progress require typed `PlotterOperationEventAttribution` containing
the exact canonical identity, `EpisodeEventID`, event sequence, pre- and
post-state revisions, and timestamp. Identity mismatch, repeated event ID,
invalid one-step revision, sequence or state regression, and timestamp
regression are typed refusals that leave the snapshot and lane unchanged.
Recoverable start refusal returns the same move-only permit for one corrected
retry. The registry validates reference identity and local ordering only; later
composition must supply the reference only after `EpisodeStore` commits the
event. The registry does not prove or perform that commit.

Start checks admission before any recoverable identity or attribution
acceptance. After shutdown closes admission, a retained unstarted permit cannot
authorize external work: start returns the typed `.admissionClosed` refusal,
retires the permit, and leaves start, progress, and attribution state unchanged.
The active operation remains observably unstarted, and a later correct shutdown
settlement can terminalize it without fabricating execution or progress.

Direct settlement requires the operation-bound `CompletionCapability` and a
typed `PlotterOperationResult` carrying the exact identity, typed disposition,
and settlement time. Capability and result identity, started state,
cancellation ownership, duplicate equality, and terminal conflict are checked
before any terminal mutation. A foreign or conflicting result returns a typed
`PlotterOperationResultRefusal`; it does not release the lane or retire the
active operation. Reusing the exact capability with the exact already accepted
result produces a deterministic duplicate classification, while the capability
cannot settle a foreign active operation.

Stop validates the exact `StopCapability`, latches one cancellation-attempt
owner before suspension, requests cancellation once on the original typed
handle, and awaits that same handle's result. Shutdown closes admission,
latches all otherwise unowned active operations before suspension, issues all
new requests before awaiting any result, and shares a concurrent Stop attempt.
Concurrent and repeated Stop/shutdown observers therefore share one
cancellation request and one original-owner await.

If a cancellation attempt receives a mismatched typed result, the same refusal
is delivered to every waiting Stop/shutdown observer. The attempt latch is
released, but the operation stays recoverably active with its lane, original
handle, direct-completion capability, and Stop capability intact. Its revisioned
active snapshot durably retains the cancellation reason, `.refused` phase, and
last cancellation-result refusal for registry-lifetime observability. A later
correct direct settlement or a new cancellation attempt can recover;
the mismatch never becomes a terminal mutation.

Accepted direct, Stop, and shutdown settlement all produce the same full
terminal record. It retains the typed result and full canonical identity,
disposition and settlement time, typed lane and lane role, context plus owning
subsystem and awaited result, terminal phase, admission/start/last-progress
times, deadline, last accepted event attribution, cancellation availability,
phase and reason, and the last cancellation-result refusal. Active and terminal
snapshots also retain a monotonically revisioned registry timestamp.

`EpisodeRuntimeTests` depends only on `EpisodeCore` and `EpisodeRuntime`. The
successful RUNTIME measurement passed 51/51 `EpisodeRuntimeTests` with no
warnings, including 15 registry tests.
Those registry tests cover typed lane configuration and capacity; exact
six-field identity; one-shot permit ownership and corrected attribution retry;
post-closure unstarted-permit retirement without progress mutation;
terminalization without fabricated execution; operation-bound direct
completion and foreign-capability refusal; original-handle Stop;
stale-successor immunity; typed mismatch, duplicate, and conflict
classification before mutation; recoverable Stop and shutdown refusal; shared
concurrent cancellation attempts; shutdown closure and priority; exact event
attribution; and complete active/terminal observability.

The latest accepted fresh source critic returned `ACCEPT`; no findings; static
only. It inspected the accepted source and tests without running a gate.
`CRITIC` is not an EA-03B package gate and is not added to the gate table.

This Foundation service remains intentionally unbound. It has no journal store,
effect runner, device adapter, application composition or caller, current
Plotter workflow registration, or durable persistence owner. It transfers no
current `OperatorWorkspace`, controller, camera, Vision, evidence, persistence,
simulator, UI, operation, Stop, shutdown, or cancellation authority. Existing
owners remain authoritative until their named cutover packages land.

`package EA-03B complete; migration remains incomplete`.

After `EA-05A` later completed, `EA-05B` became the first eligible ordinary
WorkPackage because dependencies `EA-03A` and `EA-05A` were complete. This
historical statement selected or dispatched no successor work.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; exit 0; both contracts and the checker suite passed | canonical ledger, Current Evidence, architecture, frontier, and contract checker |
| `DIFF` | passed — `git diff --check`; exit 0, no output | complete bounded correction diff |
| `QUICK` | passed — `make quick-test`; exit 0; 607/607 passed with exactly 10 intentional exclusions (3 `OperatorWorkspaceSparseTipCalibrationTests`, 4 `OperatorWorkspaceTests`, 3 `SimulatedLearningRuntimeTests`) and no warnings | repository quick suite with configured exclusions |
| `STRICT` | passed — `make strict-check`; exit 0; warnings-as-errors build, stable-local signing, launcher and app-bundle validations, 617/617 tests, both documentation contracts, and the checker suite passed with no warnings | strict build, tests, signing, launcher, bundle, and documentation contracts |
| `RUNTIME` | passed — `swift test --filter EpisodeRuntimeTests`; exit 0; 51/51 passed, including 15 registry tests; no warnings | identity, permit, post-closure refusal, completion, refusal recovery, cancellation sharing, and full terminal-record contracts |

All five required gates passed on the source-identical tree. This is final
source, build, test, repository, and static-source-critic evidence only. No
attended controller, camera, Motion, Pen, paper, operator-click, observed ink,
hardware, or remote-Git activity was performed, and none of those evidence
classes is established by this correction.

## EpisodeStore foundation

Implemented 2026-08-26 in Blackdog task `TASK-439EDDB1`.

The internal SwiftPM target `EpisodeRuntime` depends only on `EpisodeCore`, is
not a package product, and has no production caller. Its `EpisodeStore` actor is
the serial authority for one in-memory state and its one durable event journal.
Opening a store loads that journal or creates an empty one, validates its
manifest, episode, and initial-state revision, then reconstructs state by
applying the supplied typed reducer to every committed event in order. During
reconstruction, reducer-output effects are deliberately ignored: historical
effects are never executed, queued, or retained.

For an append, the actor constructs and validates the candidate journal,
reduces and validates the event against episode identity, revision, and
canonical state digest, then asks its sole typed persistence adapter to commit
before publishing either journal or state. A successful append returns the
reducer output, including its effects, as typed committed data to the caller;
the store does not execute, queue, or retain those effects. This package adds no
effect lane, operation registry or owner, device adapter, UI, application
composition, or caller.

`EpisodeJournalPersistenceAdapter` owns one versioned file envelope containing
the format version, journal-schema revision, encoded journal payload, and
payload checksum. The checksum detects adapter-payload corruption; it is not
episode-state semantic authority. Independently initialized adapters for the
same canonical file path share an in-process lock, while a kernel `fcntl`
sidecar lock supplies cross-process writer exclusion. Within that exclusive
region, commit compares the durable journal with the expected base, refuses a
concurrent-writer conflict, and begins one durable replacement only for a valid
append. The destination parent must already exist and be a directory; the
adapter returns typed `destinationDirectoryMissing` or
`destinationParentIsNotDirectory` refusal without creating any ancestry. Its
crash-durability guarantee therefore begins only inside an already provisioned
storage directory whose existence and directory entry are outside this
adapter's and package's authority.

Replacement creates a same-directory mode-0600 temporary file with `O_EXCL`,
completes every byte through a partial-write/`EINTR` loop, performs macOS
`F_FULLFSYNC`, closes the file, atomically renames it over the destination, and
then `fsync`s the destination parent directory. Commit reports success only
after those file and directory durability barriers complete.

Any failure before rename removes the temporary file and preserves the prior
durable journal. A parent-directory open or synchronization failure after rename
instead throws the typed
`postRenameDirectorySynchronizationUncertain` disposition: the candidate may
already be installed, so `EpisodeStore` publishes neither the candidate journal
nor state and the caller must reopen the store to reconcile durable truth. The
adapter and its corruption fixtures use the typed `Codable` envelope directly;
no `Any` or `JSONSerialization` path remains.

Focused adversarial coverage verifies ordered append and reopen reconstruction;
event episode, sequence, and revision refusals before persistence; reducer
episode, revision, and digest refusals; failed-commit nonpublication; schema,
format, checksum, and typed-envelope corruption refusal; pre-rename failure
preservation; missing-directory refusal without ancestry creation; a real
non-writable-directory failure whose exact mode is restored and whose refused
successor leaves prior durable bytes, journal, and actor state unchanged;
post-rename durability-uncertainty nonpublication and reopen reconciliation;
duplicate-event refusal; and simultaneous-store compare-and-swap behavior in
which exactly one successor of one journal base commits. `EpisodeStoreTests`
depends only on `EpisodeCore` and `EpisodeRuntime`.

This Foundation package is intentionally unbound. It does not transfer or
duplicate any current Plotter workflow, runtime, controller, camera, Vision,
evidence, persistence, simulator, UI, or `OperatorWorkspace` authority. The
adapter is a single-host file boundary, its checksum is integrity detection
rather than authentication, and storage-directory provisioning remains an
external composition responsibility. This package establishes no effect
execution, application integration, distributed-writer, or physical behavior
claim.

`EA-03B` is now the first eligible ordinary WorkPackage because `EA-03A` is complete. It is the first dependency-ready pending ordinary row in canonical ledger order, subject to no live claim or Current Evidence admission blocker. This statement selects or dispatches no successor work.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; both contracts and 14/14 documentation tests passed, 0 warnings | episode documentation and architecture contracts |
| `DIFF` | passed — `git diff --check`; exit 0, no diagnostics | candidate diff had no whitespace diagnostics |
| `QUICK` | passed — `make quick-test`; 557/557 passed, 10 configured exclusions, 0 warnings | repository quick suite with configured exclusions |
| `STRICT` | passed — `make strict-check`; strict build, signing, and launcher passed; 567/567 strict tests plus both documentation contracts and 14/14 capsule tests passed, 0 warnings | repository strict build, tests, signing, launcher, and documentation contracts |
| `STORE` | passed — `swift test --filter EpisodeStoreTests`; 10/10 passed, 0 failed, 0 warnings | actor serialization, append validation, pre-provisioned-directory refusal, real pre-rename preservation, durable atomic publication, post-rename uncertainty reconciliation, typed envelope integrity, reconstruction, duplicate refusal, and concurrent-writer exclusion |

This is source, build, test, and repository evidence only. No attended
controller, camera, Motion, Pen, paper, operator click, observed ink, hardware,
or remote-Git activity was performed, and none of those evidence classes is
established by this package.

## Plotter episode model foundation

Implemented 2026-08-25 in Blackdog task `TASK-B6E16E08`.

The internal SwiftPM target `PlotterEpisodeModel` depends inward only on
`EpisodeCore` and `PlotterModel`. It binds the generic definition and manifest
contracts to Plotter drawing, execution-plan, calibration, paper, environment,
camera-configuration, and drawing-model revisions. Its compile-only value
surface contains the exhaustive session, observation, point-selection,
manual-motion, drawing, Learning, and evidence intent families; episode state,
events, typed effects and results; source- and revision-bound observations and
measurements; evidence decisions, outcomes, and assessments; versioned
capability facts; immutable availability and presentation projections; and pure
scoped intent evaluation and event reduction.

Committed attributable effect-progress values bind episode, request, intent,
and effect identity; effect revision; LIVE or SIMULATED environment; typed lane
and owning subsystem; waiting, progressing, cancelling, settling, or suspected-
stall phase; start and last-attributable-progress timestamps; optional deadline;
the typed result currently awaited; and typed cancellation availability and
phase. Only a committed progress event updates that active value. Result
settlement clears active progress and retains the typed terminal result and
disposition in state and its immutable projection for inspection.

Typed observation IDs carried by an effect result remain references only. They
do not enter episode observation membership or satisfy point-selection
admission; only a separately committed `observationRecorded` event establishes
that authority.

`PlotterEpisodeModel` is not a package product. No production target depends on
it, and `PlotterEpisodeModelContractTests` is its only new consumer. The package
contains no runtime, device adapter or port, persistence, UI, application caller,
effect permit, runtime operation or lane owner, actor, task, or asynchronous
escape hatch.
`PlotterModel` retains geometry and planning authority; existing runtime,
controller, camera, Vision, evidence, persistence, simulator, UI, and
`OperatorWorkspace` owners remain unchanged. This Foundation package therefore
moves no product authority and migrates no intent.

At the `EA-02B` landing, `EA-03A` became the first eligible ordinary WorkPackage because its sole dependency `EA-02B` was complete.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; exit 0, 14 tests total | episode documentation and architecture contracts passed |
| `DIFF` | passed — `git diff --check`; exit 0, no output | candidate diff had no whitespace diagnostics |
| `QUICK` | passed — `make quick-test`; exit 0, 547 passed, 0 failed | repository quick suite with its configured exclusions |
| `PLOTTER-MODEL` | passed — `swift test --filter PlotterEpisodeModelContractTests`; exit 0, 17 passed, 0 failed | warning-free Plotter bindings, exhaustive intent families, evaluator/reducer purity, committed attributable progress and retained terminal projection, result-reference versus committed-observation authority, refusal provenance, evidence-class boundaries, package topology, and absence of executable authority |

This is source, build, test, and repository evidence only. No attended
controller, camera, Motion, Pen, paper, operator click, observed ink, hardware,
or remote-Git activity was performed, and none of those evidence classes is
established by this package.

## EpisodeCore domain-generic foundation

Implemented 2026-08-25 in Blackdog task `TASK-55097CA4`.

The internal SwiftPM target `EpisodeCore` contains Foundation-only,
domain-generic episode identities, goals, definitions, manifests, capability
facts, intent decisions, events, pure evaluator/reducer contracts, and validated
journal schemas. It has no declared package dependency and is not exposed as a
product. `EpisodeCoreTests` depends only on `EpisodeCore`. No production target
depends on either target, so this package transfers no Plotter, device,
persistence, effect, evidence, or UI authority and adds no application caller.

This is source, build, and test evidence only. No attended controller, camera,
Motion, Pen, paper, operator-click, or observed-ink activity was performed, and
none of those physical evidence classes is established by this package.

At the EA-02A landing, `EA-02B` became the first eligible ordinary WorkPackage because its sole dependency `EA-02A` was complete.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; 2 contracts passed | episode documentation and architecture contracts |
| `DIFF` | passed — `git diff --check`; exit 0 | candidate diff had no whitespace diagnostics |
| `QUICK` | passed — `make quick-test`; 530 passed, 0 failed | repository quick suite with its configured exclusions |
| `CORE` | passed — `swift test --filter EpisodeCoreTests`; 15 passed, 0 failed | domain-generic value, evaluator, reducer, event, and journal contracts |

## Operator-accepted pre-migration checkpoint and development frontier

Implemented 2026-08-25 in Blackdog task `TASK-24BD26E8` against clean `main`
commit `256b2a65f4059b6cf0e5c07f5f5305043254fb71`.

The operator explicitly accepted that commit as the rollback point for beginning
episode development. Local annotated tag
`adaptiveplotter-pre-episode-migration-20260825` resolves to the accepted commit;
its annotation states that the physical baseline remains incomplete. The tag
was not pushed, no branch was published, and no remote ref was changed.

The BASE-01/BASE-02/BASE-03 campaign and its `PHYSICAL-BASE`, `PUBLISH-MAIN`,
and `TAG` gates were removed from the active migration ledger. Their failure is
not relabeled as success: the exact 2026-08-24 reveal-pose occlusion, controller,
camera, operator, possible-ink, skipped-step, and no-redraw evidence remains in
the historical section below. The obsolete remote baseline publisher and its
disposable-repository test were deleted after all retained callers were removed.
`VAL-01` and `PHYSICAL-FINAL` still require attended evidence on the exact final
migrated build.

At the DOC-02 landing, `EA-02A` depended on completed `DOC-02` and became the
first eligible ordinary WorkPackage. This package changed repository policy,
evidence, routing, and deterministic checks only. It changed no application Swift source, runtime,
simulator, controller, camera, Motion, Pen, paper, operator-click, or physical-
ink behavior.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check` | active ledger, development frontier, protocol, roadmap, retained physical evidence, and deleted publisher contract |
| `DIFF` | passed — `git diff --check` | canonical documents, focused protocol, checker, and obsolete script deletion |

## Guarded automatic wave coordination

Implemented 2026-08-24 in Blackdog task `TASK-3960797E`, targeting `main` from
base `f3d2436211dd2da024e479daffb5725c9210cece`.

The repo-local `$run-multi-agent-wave` skill now selects the first eligible
pending `repository`, `software`, or `gate` WorkPackage in canonical ledger
order. Selection requires every dependency to be landed complete, every gate to
resolve exactly, and no contradictory blocker in Current Evidence. It cannot
authorize attended physical work, observed-ink claims, branch publication, tag
creation, or a remote push. At that package's landing the then-current ledger
therefore reported the blocked `BASE-01` frontier. `DOC-02` later retired that
baseline campaign as a migration prerequisite; the same selector now chooses
eligible `EA-02A` first without changing its package boundary.

An existing Blackdog claim is resolved before selection. Verified recoverable
ordinary-package work follows only Blackdog's exact structured action; an active
coordinator may grant one explicit bounded offload through available task/thread
messaging. The selector never declares a claim stale, cancels it, replaces it,
or starts a competing task.

One selected WorkPackage is one coordinator-owned Blackdog task worktree.
Workers receive exclusive file and semantic-authority leases, may not mutate Git
or Blackdog lifecycle, and return a compact evidence schema. Concurrent writes
to one file are prohibited; shared manifests, canonical documents, checkers,
test support, and `OperatorWorkspace.swift` use one serial integrator. Editing
quiesces before serial validation, accepted slices are checked against every
later diff, and a fresh read-only critic precedes landing. Only Blackdog's exact
stale-recovery action may rebase a stale candidate.

Repository-maintenance task `TASK-B9E71BFC` replaced the model-driven full-plan
startup read with a deterministic mode-0600 launch capsule. The capsule binds
the exact primary `main` HEAD, empty Git state, `main...origin/main` relation,
canonical authority-file and section hashes, complete ledger/evidence
reconciliation, expanded gates, package-specific line pointers, and a bounded
projection of live repository-wide Blackdog claims. Consumption recomputes every
binding and rejects stale HEADs, dirty authority, changed claims, payload/schema
tampering, insecure permissions, symlinks, or unbounded output. It never caches
a Blackdog `next_action` and does not reserve work.

Follow-up repository-maintenance task `TASK-D61F784A` prevents the capsule's
dynamic contract-checker import from emitting Python bytecode into the source
tree. Capsule creation therefore preserves the clean-primary-workspace
precondition required by immediate consumption.

The wave now permits at most four active agents total: the invoking coordinator
and no more than three workers or critics. Every wave assigns one serial
documentation integrator; its package landing always updates the execution-plan
ledger row plus Current Evidence gate/detail records, conditionally updates every
affected canonical document, and records reviewed/no-change dispositions for the
rest. Completion verifies the landed commit as current clean `main` with no
unfinished wave task or disposable worktree, then mechanically generates the
successor capsule. No successor reconnaissance agent is used.

This is repository policy and deterministic contract-check evidence only. It
does not execute an episode package and establishes no application, simulator,
controller, camera, motion, Pen, paper, operator-click, or observed-ink claim.

Forward scenarios are fixed by the checked contract:

| Scenario | Required disposition |
| --- | --- |
| Next verified clean ledger | The exact frozen Option A tree passed all seven package gates. The final evidence delta requires affected `DOC`, `DIFF`, `QUICK`, and `STRICT` refresh during Blackdog landing. The same critic's delta-only cited-findings recheck closed with `CITED_RACE_CLOSED`; no new or full critic was commissioned and no further critic is required or allowed. Only after landing, cleanup verification on canonical `main`, and successor-capsule creation does `EA-07` become the conditional first eligible ordinary row, subject to no live claim or admission blocker; this evidence record does not select or dispatch it, and no software package may claim or repair the retained failed physical evidence. |
| Active owner holds the claim | Start no task; request one bounded non-overlapping offload with explicit worktree and leases, or stop if it is unavailable. |
| Failed/interrupted ordinary package is recoverable | Verify prompt replay and dependencies, then follow only Blackdog's exact recovery action as coordinator. |
| Multiple later ordinary rows appear dependency-ready | Select only the first in literal ledger order; parallelism stays inside that one WorkPackage and one task worktree. |

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check` | routing, policy removal, exact selector classes/order, then-current blocked frontier, worker merge guards, and existing episode contracts |
| `DIFF` | passed — `git diff --check` | skill, policy, evidence, routing, and executable checker patch |
| `SKILL` | passed — skill-creator `quick_validate.py` with isolated PyYAML | frontmatter, name, description, and repo-local skill structure |
| `CAPSULE` | passed — `make wave-capsule-test`; 14 tests | fresh consumption, bytecode-clean dynamic import, exact package/authority pointers, Current Evidence blocker admission, active claims, HEAD/document staleness, tamper/schema/permission/symlink rejection, bounded output, and physical authorization boundary |

## Historical: attended baseline blocked by reveal-pose occlusion

Attempted 2026-08-24 in Blackdog task `TASK-EC17BA6C` against clean `main`
commit `96cf4f1a35155853650163b51683971046519580`. This attempt did not
satisfy its then-required `PHYSICAL-BASE` gate, did not complete `BASE-01`, and
recorded no tested-baseline marker. No branch or tag was pushed. `DOC-02` later
removed that campaign from the active migration ledger without changing these
facts or upgrading any evidence class.

The signed application used for the attended run was
`/Users/bullard/Projects/AdaptivePlotter/.build/AdaptivePlotter.app`, identifier
`com.bullard.AdaptivePlotter`, signing authority
`AdaptivePlotter Local Development`, with executable SHA-256
`dec7fad2ccf8962eeff4c2a7996ca4ef86fa1c6a540e1a5c6e72bd33ab412a2a`.
Its executable inode was the inode retained by running process `74788`; the
process started after the bundle build from the unchanged candidate. The task-
workspace `make app` and `make validate-app` preconditions also passed. The host
was macOS 15.7.9 build 24G830 with Apple Swift 6.1.2.

The attended operator was the interactive `bullard` user. The app selected
controller `/dev/cu.usbserial-A10OF67O`; the visible toolbar reported Plotter
Connected and Motion Enabled. The LIVE camera supplied exact 1920 x 1080 frames.
The run retained camera-mount revision
`d04a6b17-4a97-49f0-adc5-fa634f67a903`, camera-reframing revision
`0b1c15bd-2569-44f6-9495-41fb6838de7f`, machine-geometry revision
`ed5336c4-c0e2-4bc2-95a5-361139c8661c`, tool-assembly revision
`bd027bcb-96e6-4d23-8778-ce8c4348c64f`, pen-contact-profile revision
`0fd727d3-0145-4c79-91af-f97b9d6f48c0`, paper-instance revision
`0a299e7f-9e10-4855-aa8d-d280576175fd`, and paper-contact-plane revision
`a4e7ebd9-1aa0-4d5e-928f-de71d5f44e11`. The camera model/device label, exact
controller settings digest, servo values, and complete controller transcript
were not transcribed into this evidence record.

Runbook section dispositions:

- Section 1 — `passed` by the attending operator with the app showing Exercises
  1.1 and 1.2 Complete. The later evidence capture confirmed the intended
  controller remained connected, Motion remained enabled, and the accepted
  Drawing Boundary was visible. The exact initial passive-probe fields, Pen
  values, directional Stop chronology, and center MPos were not independently
  copied into this record.
- Section 2 — `passed` by the attending operator with Exercise 1.3 displayed
  Complete and the accepted live camera projection visible. The five exact
  correspondence frames, rectangles, holdout residuals, and proposal review
  values were not independently copied into this record.
- Section 3 — `passed` by the attending operator with Exercise 1.4 displayed
  Complete and `Tip calibration accepted` visible. The four-click order,
  reject-then-accept check, individual circle-contact observations, and
  64-chord chronology were not independently copied into this record, so this
  attempt does not upgrade those details beyond the app's accepted result and
  the operator's attendance.
- Section 4 — `skipped`. The unchanged-restart Saved Learning choice, changed-
  dependency reset, new-sheet/same-plane branch, and changed-contact-plane
  branch were not executed as separately recorded attended cases.
- Section 5 — `failed`. The controller-owned operation visibly progressed
  through phase 4 of 6 with its exact Stop available, then settled to Idle with
  no active motion. The attending operator directly observed one closed,
  correctly drawn rectangular Border with one faint segment. This establishes
  an observed physical-ink claim with that limitation, not an attributable
  camera/Vision comparison.

During section 5 the app entered `Trial ink analysis - active` on a strictly
newer exact post frame, then stopped with
`inkRejected("correspondenceUnavailable")`, `Ink may exist`, and no redraw
requested. It did not produce the required observed-white/residual-orange
comparison or `Drawing validation complete`. An initial observation recovery
captured a frame while the operator's hand and marker occluded the paper and was
also rejected. A later clean recovery still returned the carriage to the stored
local reveal pose. The attending operator established that the armature at that
pose physically occludes one Drawing Border edge. Moving the armature aside and
choosing **Resume Drawing Border Observation** returned it to the same occluding
center pose before capture. Repeated observation therefore could not make the
complete Border visible, and no safe observation-only recovery could satisfy
the comparison. No redraw was requested or performed.

The evidence classes remain separate: the app and controller report a settled
closed-plan operation; the operator directly reports a correct physical Border
with one faint segment; exact camera frames show the fixed reveal-pose
occlusion; Vision reports correspondence unavailable and accepts no ink
geometry. The retired `PHYSICAL-BASE` result is `failed`, while `DOC`, `DIFF`, and `STRICT` are
`passed` on this evidence-only candidate: `make docs-check`, `git diff --check`,
and `make strict-check` completed successfully, with 525 software tests passing
under the strict gate. If this historical baseline procedure is revisited, it
still requires ownership for an unobstructed same-pose post-drawing observation
and a new attended run on disposable paper. The existing possibly inked Border
must not be redrawn.

## Tip applicability evidence authority

Implemented 2026-08-24 in Blackdog task `TASK-05D1DCBD`.

Drawing Studio still admits plans against the accepted Drawing Boundary, and a
typed diagnostic affine projection keeps Boundary-band placement, preview,
accepted-Boundary overlays, saved-plan overlays, and the operator-attested paper
polygon visible. `TipApplicabilityEvidencePolicy` now owns the separate
camera/ink evidence projection. Its unforgeable result requires every plan point
to pass the recorded `TipCameraRegistration.tipPixel(at:)` domain and gates the
only Drawing Studio observer call.

If any point is outside the recorded applicability rectangle, controller
execution remains eligible but Vision is not invoked. The terminal record uses
the typed `projectionOutsideTipApplicability` reason and `nonAttributable`
disposition, verifies zero strokes, survives post-execution fallback errors, and
cannot be mistaken for a reviewable observation or post frame. A distinct newly
accepted registration revision can make the same geometry attributable only
when its own recorded applicability contains the complete plan. The former
`inferredDrawingStudioPixel` bypass was deleted with zero source or test matches.

Durable drawing-run evidence advanced from schema 2 to 3 and drawing-readiness
assessment from schema 1 to 2 for the new typed disposition. Readers retain
explicit legacy decode for drawing-run schemas 1 and 2 and readiness schema 1;
new non-attributable values are refused when mislabeled as an older schema.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check` | canonical documents, ledger/evidence agreement, vocabulary, and repository contract |
| `DIFF` | passed — `git diff --check` | source, tests, documentation, and contract update |
| `QUICK` | passed — `make quick-test` | nonphysical unit/component partition |
| `STRICT` | passed — `make strict-check` | strict concurrency, warnings as errors, signed bundle, launcher, full software suite, documentation contract, and diff integrity |
| `FIX-APPLICABILITY` | passed — `swift test --filter TipApplicabilityEvidencePolicyTests` | five focused cases covering diagnostic projection, all-or-nothing observer gating, distinct expanded revision, durable typed non-attribution, schema truth, and truthful review availability |

Focused drawing-readiness and drawing-run schema suites passed 11 tests; the
Drawing Studio presentation suite passed 8 tests; and the retained Boundary-band
preview lifecycle regression passed. These are source, build, signing,
deterministic software, and simulator results only. No attended controller,
camera, motion, Pen, paper, operator click, or observed-ink validation was
performed.

## Coordinate settlement and containment split

Implemented 2026-08-24 in Blackdog task `TASK-1B5992CF`.

Controller-pose settlement and drawing-region containment now have different
typed owners, metrics, revisions, and values. PlotterRuntime's
`MachinePositionAcceptancePolicy` retains the quantization-aware Euclidean
residual policy under `controllerQuantizedEuclideanV1`: 0.5 mm is accepted and
0.501 mm is refused. PlotterModel's `DrawingRegionContainmentPolicy` owns
axis-aligned accepted-Boundary containment under
`acceptedBoundaryNumericalEpsilonV1`. Its 1e-9 mm epsilon admits floating-point
residue but refuses commanded geometry a meaningful distance outside the
Boundary.

`DrawableMachineRegion`, `DrawingPlanner`, and sparse circle-footprint
admission consume the drawing policy. Tip-registration construction now checks
the intended calibration target against its exact applicability rectangle and
checks reported/commanded position residuals separately; tip projection no
longer obtains a 0.5 mm domain expansion through the controller-settlement
policy. `ContinuousMachineCoordinateTolerance`, the old bounds API, and tests
asserting a shared bounds tolerance were deleted with zero remaining source or
test matches. Existing plan encoding/schema, Boundary versus Drawing Border
meaning, controller ownership, and durable overlay decoding were preserved.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check` | canonical documents, ledger/evidence agreement, vocabulary, and repository contract |
| `DIFF` | passed — `git diff --check` | source, tests, documentation, and contract update |
| `QUICK` | passed — `make quick-test` | nonphysical unit/component partition |
| `STRICT` | passed — `make strict-check` | strict concurrency, warnings as errors, signed bundle, launcher, full software suite, documentation contract, and diff integrity |
| `FIX-CONTAINMENT` | passed — `swift test --filter CoordinateAcceptancePolicyTests` | three focused cases covering typed separation, 0.5/0.501 mm Euclidean settlement, exact/epsilon Boundary admission, and outside-Boundary refusal |

Affected planning, calibration, and settlement suites also passed 43 focused
tests. These are source, build, signing, deterministic software, and simulator
results only. No attended controller, camera, motion, Pen, paper, operator
click, or observed-ink validation was performed.

## Episode current-source inventory

Prepared 2026-08-24 in Blackdog task `TASK-513DC8A7`.

The canonical execution plan now assigns 109 stable current-source entries
across semantic intent, guard, authority owner, direct port, environment branch,
task/cancel owner, persistence path, UI consumer, and high-level fixture
categories. Every entry records one current owner and behavior, one
retain/adapt/delete disposition, one cutover package, and that package's fixed
focused command. Seventy-nine exact zero-match scans cover all 16 cutover
packages and distinguish deleted symbols, forbidden imports, direct ports,
duplicate ingress, task owners, fixtures, and environment branches.

The inventory check requires exact set equality for every case in the four
current action enums, every named `OperatorWorkspace` unavailable-reason guard,
every injected action port, every declared application/runtime `Task` owner in
the named source owners, and every direct SwiftUI
`workspace`/`actionWorkspace` consumer. It also proves every recorded source
seam is present and every cutover has a closed scan set. The package added only
the canonical inventory, deterministic repository checks, completion evidence,
and ledger/contract updates. No application or test Swift source changed.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check` | canonical document, vocabulary, ledger, completion-evidence, and package-contract checks |
| `DIFF` | passed — `git diff --check` | documentation and deterministic repository-check scripts |
| `INVENTORY` | passed — `sh Scripts/check_episode_inventory.sh` | 109 stable assignments and 79 exact cutover scans, including mechanical closed-family coverage |

No Swift suite or attended physical procedure is a required EA-01 gate. The
package did not execute or validate controller, camera, motion, Pen, paper,
operator-click, physical-ink, or application-runtime behavior.

## Episode migration execution readiness

Prepared 2026-08-24 in Blackdog task `TASK-F2387A9A`.

The repository now has one target vocabulary authority and one target execution
plan. The plan defines incremental single ingress per `PlotterIntent`, a thin
`PlotterIntentGateway`, one `PlotterOperationRegistry`, exact completion levels,
fully named atomic authority packages, named validation/deletion gates, and
separate execution classes for repository/software, attended physical, and
remote Git work. The
old broad `BASE-00`, `EA-10`, and `EA-11` rows are gone. Source-read-only
repository package `EA-01` changes the canonical inventory and its check data
but no application source; it no longer depends on physical work. Application
migration still depends on the corrective and explicitly attended/tagged
baseline packages. Controller-session readiness, observation-environment
configuration, and final application composition are separate `EA-11A`,
`EA-11B`, and `EA-11C` cutovers; no generic remainder package can absorb an
unidentified authority transfer. Generic core contracts, Plotter bindings,
event storage, operation runtime, environment recording, deterministic replay,
and incident assembly are separate one-module-or-service Foundation packages.
Advisory speech has its own `EA-10G` cutover rather than remaining as an
undispositioned workspace effect.

At that landing, the AdaptivePlotter skill separated read-only audit,
named-package prompt compilation, and named-package execution and did not infer
a package. The later guarded wave policy above supersedes that selection rule;
it still cannot select physical work, change branches, start a task during
audit/compile, or treat a failed/skipped gate as completion. A deterministic
documentation contract closes the tracked document inventory, verifies every
canonical target name, rejects competing synonyms and implicit continuation,
and checks current versus historical terminology. Blackdog's configured landing
validations now include that contract and the non-journey software partition
rather than whitespace alone.

The abandoned `TASK-BEB9AF9B` patch and its untracked guard/journey/map drafts
were not landed or copied; its task worktree and branch were removed through
Blackdog. The current `bab0900` evidence-applicability bypass and shared
settlement/containment tolerance are recorded as as-built defects assigned to
`FIX-01` and `FIX-00`, respectively, before physical baseline. Earlier Current
Evidence entries again state only the terms and behavior true at their own
landing, with later supersession explicit.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check` | closed document inventory, canonical vocabulary, explicit execution modes, forbidden synonyms, historical wording, repository capability contract, and disposable-repository BASE-03 publication fixture |
| `make quick-test` | passed — 505 tests | nonphysical unit/component partition on the unchanged application source |
| `DIFF` | passed — `git diff --check` | documentation, skill, script, Makefile, and Blackdog configuration patch |
| `CRITIC` | passed — 10/10; `UNANIMOUS PASS — no material disagreement` | fresh-context, read-only review of the actual candidate tree against the fixed readiness rubric |

No application source or simulator behavior was changed. `make quick-test`
software-tested the unchanged app/model/runtime and deterministic simulator
paths; it did not validate an attended controller, camera, motion, pen, paper,
operator click, physical ink, or accepted evidence artifact. The BASE-03 fixture
used only disposable local repositories; it did not read or mutate a production
tag, branch, or remote ref.

## Historical: initial canonical episode migration documentation

Documented 2026-08-23 in Blackdog task `TASK-C86132F1`, landed at `d33d4ff`.

The repository now has one
[Episode Architecture Execution Plan](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md).
It owns the accepted target packages, centralized semantic ingress, operation
registry, event/replay and simulation boundaries, non-negotiable observability,
same-landing deletion rules, work-package dependencies, pilot gate, and landed
status ledger. Product Contract owns the corresponding durable authority and
observability requirements; Swift Architecture remains explicitly as-built;
Roadmap points to the plan rather than restating it.

[Document Routing](INDEX.md) now inventories every current document and states
whether it owns product meaning, as-built architecture, target migration,
current interaction, evidence, physical procedure, roadmap scope, or repository
workflow. The Learning Path Mermaid remains because it is the exact current
button transition contract. Clearly labeled historical Current Evidence remains
because it is evidence chronology. Neither is an alternate target architecture.

No competing episode architecture, execution-plan comparison, or coordinator
prompt was present in the tracked repository. The three temporary research and
planning drafts used to reach the canonical result were removed after their
accepted decisions were integrated. At that landing, the repo-local
AdaptivePlotter skill routed `continue episode migration` through one focused
continuation protocol and the canonical work ledger. `TASK-F2387A9A` later
replaced that unscoped continuation with separate read-only audit,
named-package compile, and named-package execute modes.

This task changes documentation and the repo-local skill only. It implements no
episode runtime, changes no application behavior, and supplies no physical
validation.

| Validation | Result | Scope |
| --- | --- | --- |
| `ARCHIVED` | passed — `git merge-base --is-ancestor d33d4ff HEAD` | canonical DOC-00 landing remains in current history |
| local Markdown-link check | passed — 13 files | `README.md`, `AGENTS.md`, all `docs/**/*.md`, and the AdaptivePlotter skill and focused references |
| vestigial review/alternate-plan scan | passed — zero matches | superseded-review terminology, deleted temporary draft names, and competing-architecture wording across current documentation and the repo-local skill |
| skill contract validation | passed — manual equivalent | frontmatter format, allowed keys, name and description constraints, unfinished placeholders, and the focused-reference target |
| upstream `quick_validate.py` | skipped — its Python environment lacks PyYAML | no package or tool environment was mutated for this documentation task |
| `git diff --check` | passed | documentation and repo-local skill changes |
| application tests and attended physical validation | skipped | no application source, simulator, controller, camera, motion, Pen, paper, click, or ink behavior changed |

## Historical software evidence by landing

Every task section below records what its stated landing implemented and
verified. Later sections above may supersede its terminology or behavior; these
entries do not retroactively change.

### Boundary admission, relative Drawing Border geometry, and coordinate tolerance

Implemented 2026-08-23 in Blackdog task `TASK-12704A6B`.

Continuous machine-coordinate comparison now has one PlotterModel-owned minimum
tolerance of 0.5 mm, consumed by runtime position settlement and drawing-plan
containment. The change preserves `ExecutionPlanRevision` and
`DrawingReadinessAssessment` schema 1 plus the existing canonical region encoding,
so persisted drawing evidence does not acquire a parallel tolerance field or a
different plan hash. A point exactly 0.5 mm beyond a numeric edge is accepted;
0.501 mm is outside.

The accepted **Drawing Boundary** is the spatial admission region for Exercise 2.1
and Drawing Studio. The **Drawing Border** remains target geometry exactly 10 mm
inside the current v7 Boundary and is never reused as the admission region. One
`drawingBorderBounds` derivation owns the inset, and `DrawingBorderPlan` derives
both its machine vertices and relative field-space program from that same rectangle.
The removed exact point-array comparison can no longer reject equivalent continuous
geometry.

Drawing Studio preview, paper-coverage projection, post-run intended geometry, and
saved-plan overlays use one named inferred affine projection for Boundary-admitted
points between the Border and Boundary. This does not enlarge the recorded inset
tip-calibration applicability. A regression places a small Drawing Studio plan in
that band and requires a ready preview. Existing overlay archives retain the durable
`calibratedDrawableRegion` wire value while current presentation uses **Drawing
Border** terminology.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused coordinate, planning, persistence, overlay, sparse-workspace, and lifecycle suites | passed — 45 tests | 0.500/0.501 mm behavior, schema-1 embedded plans, overlay wire compatibility, one-source relative Border geometry, Boundary admission, and between-Border-and-Boundary preview |
| `make quick-test` | passed — 505 tests | fast unit/component partition |
| `make journey-test` | passed — 10 tests | retained end-to-end software journeys |
| `make strict-check` | passed — 515 tests | strict concurrency, warnings as errors, signed bundle, launcher checks, full suite, repository contract, and diff check |
| scoped critic review | passed — no remaining requested-scope issues | correctness, completeness, code quality, residual Border/Boundary consistency, and persistence compatibility |

These are source, deterministic, simulator, build, signing, and repository-gate
results. No attended camera, controller, physical motion, Pen, paper, operator
click, or observed-ink validation was performed by this task. The app was not
launched for physical verification.

An independent 2026-08-23 follow-up audit found that this landing also created
two incorrect cross-owner assumptions: outside-applicability affine projection
can feed attributable run evidence, and the same 0.5 mm value answers both
Euclidean pose settlement and axis-expanded planning containment. The canonical
episode plan assigns the containment/settlement split to `FIX-00` and the
evidence-applicability correction to `FIX-01` before the attended baseline.
The passed software tests above prove the landed behavior; they do not make
those two semantics acceptable evidence or target architecture.

### Historical landing snapshot: Stage 1/2 Learning Path numbering and operator terminology

Implemented 2026-08-23 in Blackdog task `TASK-ED2EEC92`.

The visible curriculum now starts at **1 Plotter Calibration**, with Exercises
1.1 through 1.4, and ends at **2 Drawing Validation**, with Exercise 2.1. Connect
and Enable Motion remain external workbench controls rather than curriculum
steps. When an exercise requires either state, its action remains visible and
names the exact external remedy; Motion authorization still depends on a
connected controller session.

Learning Path stage, exercise, action, and evidence terms now come from one
shared end-user vocabulary. Generic **Start**, **Next**, and **Go** labels were
removed from Learning Path actions in favor of the effect of each click. Status
and failure copy no longer exposes implementation terms such as admission,
owner, typed state, workflow coordinator, accepted-artifact checkpoint, or tip
model. Saved state is consistently **Saved Learning**, the accepted work area is
the **Drawing Boundary**, and the final physical check is **drawing-frame
validation**.

The copy audit also corrected behavioral drift: pen-tip calibration reports
four accepted corner observations rather than five; Exercise 2.1 describes one
closed frame through the four calibration-circle centers rather than an
isolated 5 mm line; and frame evidence is described as drawing-frame validation.
The exact button-to-state diagram is recorded in
[Learning Path Button Transitions](LEARNING_PATH_BUTTON_TRANSITIONS.md).
Persisted schema and internal enum/algorithm identifiers were not renamed.

This is the terminology verified by `TASK-ED2EEC92`. Later
`TASK-12704A6B` introduced **Drawing Border** as the visible name for the inset
target without changing this earlier landing's evidence claim.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused Learning Path, overlay, capability, discovery, Boundary, and pen-cap suites | passed — 95 tests | numbering, canonical vocabulary, exact action labels, four-corner evidence, frame workflow, blocked dependencies, and redundant-gate exclusion |
| `make quick-test` | passed — 502 tests | fast unit/component partition |
| `make journey-test` | passed — 10 tests | retained end-to-end software journeys |
| `make strict-check` | passed — 512 tests | strict concurrency, warnings as errors, signed bundle, launcher checks, full suite, repository contract, and diff check |
| obsolete-numbering and action-label scans | passed — zero current-source/current-doc matches | Stage 3/4 labels, Exercise 3.x/4.1 labels, generic Start/Next/Go buttons, retired tip-map actions, and isolated-line copy |

These are source, deterministic, simulator, build, signing, and repository-gate
results. No attended camera, controller, physical motion, Pen, paper, operator
click, or observed-ink validation was performed by this task. The app was not
launched for physical verification.

### Historical as landed: Ten-millimeter Boundary inset and final picture-frame context

Implemented 2026-08-22 in Blackdog task `TASK-83E5E3C9`.

The then-current Stage 3.4 estimator placed each of the four 2 mm-radius
calibration-circle centers exactly 10 mm inside its two adjacent accepted 3.2
Boundary edges.
The commanded circle outlines therefore retain 8 mm of edge clearance. The
resulting four-center rectangle remains the exact `TipCameraRegistration`
applicability and, at that landing, the Drawing Studio region; Stage 4.1
constructed its one closed four-edge `DrawingPlan` from that same recorded
rectangle and remained the final required Learning Path exercise.

The camera view at that landing rendered two distinct geometries. An orange
dashed **ACCEPTED 3.2 BOUNDARY** came from the accepted Boundary aggregates and was projected as
an explicitly inferred 10 mm extrapolation of the proposed or accepted contact
map. The inner four-point rectangle came from the registration applicability:
it was cyan planned geometry during Stage 3.4 proposal review and a labeled
10 mm-inset calibrated frame after acceptance. Stage 4.1 overlaid and physically
drew that same inner frame after the operator pressed its existing one-Go motion
authorization. The v6 edge-touching estimator remains decodable only within its
recorded domain; new evidence uses v7.

This section records only `TASK-83E5E3C9`. The later numbering task renamed the
visible stages, and `TASK-12704A6B` later made the accepted Drawing Boundary the
Drawing Studio planning region and named the inset target **Drawing Border**.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused planning, overlay, persistence, projector, and sparse-workspace suites | passed — 45 tests | 10 mm centers, 8 mm outline clearance, collapsed-axis refusal, v6 restore decoding, semantic overlay style, proposed/accepted dual rectangles, exact-revision Stage 4 frame execution, and one-Go endpoint |
| `make quick-test` | passed — 500 tests | fast unit/component partition with retained journeys excluded |
| `make journey-test` | passed — 10 tests | full four-circle acceptance, checkpoint revalidation, exact tip revision, closed-frame drawing, reset, Boundary, and simulator journeys |
| `make strict-check` | passed — 510 tests | strict concurrency, warnings as errors, signed bundle, launcher checks, full suite, repository contract, and diff check |

These are source, deterministic, simulator, build, signing, and repository-gate
results. No attended camera, controller, physical motion, Pen, paper, operator
click, or observed-ink validation was performed by this task. The app was not
launched for physical verification.

### Bounded exercise-path computation and responsive operator presentation

Implemented 2026-08-22 in Blackdog task `TASK-9D85A716`.

Learning presentation now has one immutable base projection keyed by its
semantic revision and one selection cache. The root workbench shares that
projection and its cached action surface with child views; diagnostic-only
updates do not rebuild either, and the 64 Stage 3.4 drawing chords do not each
trigger a Learning projection. Video Settings uses one atomic, window-local
layout transition instead of a pending show task, so deterministic held-motion
tests expose the panel without waiting for motion settlement while retaining
the stable Stop control. A protected narrow layout still refuses the panel
truthfully instead of queuing it.

The Vision pipeline now publishes semantic phase/result/error changes while
diagnostic counters are pull-only, and identical lifecycle requests are no-ops.
Exact workflow capture separates return-only materialization from explicit
preview publication. Stable cap capture inspects three strictly newer frames,
validates the set once, and publishes the selected newest frame under one
exclusive lease rather than three pause/release/resume cycles.

Automatic Pen transitions batch the settled actuation, evidence, and next
question into one semantic update. The four-corner Stage 3.4 fixture executes
64 chord outcomes without per-chord snapshots or passive probes: the complete
batch records 5 Pen Up actuations, 4 Pen Down actuations, 5 passive probes, and
1 full snapshot, ending Idle and Pen Up without redraw. Workflow telemetry is
enqueued on one ordered nonblocking tail; teardown closes admission before
awaiting the accepted prefix, so later events are rejected rather than racing
the drain.

Planned-observation alignment evaluates all 49 offsets at stride 2, performs
full-resolution verification only for the best three supported candidates, and
checks cancellation through alignment, extraction, and association. The
instrumented deterministic fixture reduced pixel evaluations from 226,580 to
70,102 (69.06%). That number and finalist equivalence are fixture evidence, not
a claim of global mathematical equivalence for arbitrary images.

| Validation | Result | Scope |
| --- | --- | --- |
| `make quick-test` | passed — 499 tests | fast unit/component partition with retained journeys excluded |
| `make journey-test` | passed — 10 tests | retained end-to-end software journeys |
| `make strict-check` | passed — 509 tests | Swift 6 concurrency, warnings as errors, formatting, full tests, and repository gates |
| obsolete-symbol scan | passed — zero matches | queued Video Settings state, fake motion-scoped Vision lease, obsolete sparse-tip chord action, and superseded projection helpers |
| `git diff --check` | passed | whitespace and conflict markers |

These are source, deterministic fixture, simulator, build, and repository-gate
results. No attended camera, controller, motion, Pen, operator click, paper, or
observed-ink validation was performed by this task. The application was not
used to establish physical runtime behavior.

### Exercise-only Learning Path and external runtime blockers

Implemented 2026-08-21 in Blackdog task `TASK-8D0B646D`.

The Learning Path navigator now contains only curriculum stages 3 and 4 and
their exercises. **Connect** and **Enable Motion** remain workbench-toolbar
controls. Projected Motion authorization is false unless the controller session
is established, and motion-dependent exercise actions remain in place with an
exact connection or Motion blocker instead of becoming separate path steps.

**Identify Pen Cap** remains exact-frame-only. After the accepted cap click, the
first Pen question and slider remain visible; when needed they are disabled by
the external controller/Motion blocker. Controller selection, **Connect**, and
**Enable Motion** remain available without losing the click or restarting Pen
Interaction. Stage 3.3 begins directly with **Capture Five Cap Samples**. Stage
3.4 begins directly with **Draw Four Corner Circles** and no longer projects a
generic no-op **Start**. The complete button and destination inventory is
[Learning Path Button Transitions](LEARNING_PATH_BUTTON_TRANSITIONS.md).

| Validation | Result | Scope |
| --- | --- | --- |
| Focused projector, Pen-cap, controller-dependency, sparse-calibration, reset, and lifecycle regressions | passed | exercise-only navigation, `motion => connected`, cap-before-controller setup, disabled `Next`/slider, preserved slider coalescing, exact Boundary blockers, and direct Stage 3.4 entry |
| `make quick-test` | passed — 460 tests | unit/component partition with retained journeys excluded |
| `make journey-test` | passed — 10 tests | sparse calibration, checkpoint revalidation, exact tip revision, reset, Boundary, drawing, and Stop journeys |
| `make strict-check` | passed — 470 tests | strict concurrency, warnings as errors, signed bundle, launcher checks, full test suite, repository contract, and diff check |
| removed-stage and obsolete-button scan | passed — zero matches | Learning Path Connect/Enable Motion enum cases and rows, plus Stage 3.4 test callers of the deleted generic Start |
| `git diff --check` | passed | whitespace and conflict markers |

No attended camera, controller, motion, Pen, click, paper, or ink validation was
performed by this task.

### Historical: four extreme-corner marks and closed picture-frame trial

Implemented 2026-08-21 in Blackdog task `TASK-A8E60A2E`.

Stage 3.4 now draws four 2 mm-radius calibration circles only. There is no
center circle. Each corner center is inset by exactly the 2 mm circle radius,
so its footprint reaches both selected Boundary extremes without commanding
motion outside the accepted envelope. The batch contains 64 circle chords,
returns Pen Up to the rectangle center only for the reveal, freezes one exact
frame, and accepts four clicks using deterministic 4! association. Fresh
authority uses a new four-corner estimator revision; previously persisted five-
point revisions remain decodable within their recorded applicability.

Stage 4.1 no longer constructs or observes an isolated 5 mm line. One **Go**
previews and executes a closed `DrawingProgram` through the four accepted
circle centers using the canonical drawing-plan runner: four orthogonal edges,
four right-angle turns, and a return to the start. It observes that immutable
plan with the generic planned-drawing observer. The isolated-line observer,
evidence adapter, test fixture, and dedicated tests were deleted.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused geometry, authority, presentation, workspace, and planned-observation suites | passed — 115 tests in two non-overlapping runs | four-corner placement, 64 chords, 4! association, four-observation authority, exact revision, frame planning, generic observation, Stop, and no-redraw |
| `make quick-test` | passed — 456 tests | fast unit/component partition with retained journeys excluded |
| `make journey-test` | passed — 10 tests | full four-corner acceptance, coordinate revalidation, closed-frame observation, reset, Boundary, and Stop journeys |
| `make strict-check` | passed — 466 tests | strict concurrency, warnings as errors, signed bundle, launcher checks, full suite, repository contract, and diff check |
| superseded-path/current-wording scan | passed — zero matches | isolated observer/plan APIs, five-mark action, fifth-click flow, 7.5% current inset, 5! current association, and 80-chord current batch |
| `git diff --check` | passed | whitespace and conflict markers |

No attended camera, controller, motion, Pen, click, paper, or ink validation was
performed by this task.

### Historical: operator-decided saved Learning and Stage 3.4 v5 picture frame

Implemented 2026-08-20 in Blackdog task `TASK-00CC519D`.

`AcceptedLearningPathCheckpoint` is the single durable saved-training package,
including exact dependency revisions, learned cap appearance, one bounded
reference frame, and attributable drawing records whose v2 form embeds the full
immutable execution-plan geometry. A restart loads that package for presentation
only. It projects compatible saved frames, cap/tip facts, and prior drawing paths
and computes a bounded advisory alignment/MAD report. Exactly two choices are
shown: **Use Saved Training** atomically installs the exact saved dependency
graph without motion or pose restoration; **Start New Learning** applies nothing
and retains the last complete package until a complete replacement is saved.

Stage 3.4 v5 places four outer mark centers at a 7.5% inset on each Boundary
axis, subject to the 2.25 mm radius-plus-clearance minimum, plus one center mark.
The ordinary picture region is another 2.25 mm inside those outer centers, so
calibration ink remains outside ordinary picture content. Existing v3/v4
registrations retain their recorded geometry. Automatic startup PNG capture is
removed; explicit snapshots remain. Machine-session diagnostics retain at most
10 complete session groups and 50 MiB. Motion paths redundantly ensure Pen Up
through the central typed actuation path before travel.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused restart/controller/reset/persistence suites | passed — 49 tests, then 12 reset tests after the final persistence guard | preview/decline nonmutation, exact two actions, atomic explicit apply, cap migration, retained package, and no empty shutdown package |
| `make quick-test` | passed — 460 tests | fast unit/component partition with retained journeys excluded |
| `make journey-test` | passed — 10 tests | v5 inner picture region, sparse calibration, exact tip revision, reset, Boundary, drawing, and Stop journeys |
| `make strict-check` | passed — 470 tests | strict concurrency, warnings as errors, signed bundle, launcher checks, full test suite, and repository checks |
| superseded-symbol/policy scan | passed — zero matches | removed startup recorder path, old optional-cluster names, old automatic-restore helper, and stale v3 current-plan wording |
| `git diff --check` | passed | whitespace and conflict markers |

No attended camera, controller, motion, Pen, click, paper, or ink validation was
performed by this task.

### Historical: Boundary-corner Stage 3.4 drawable region

This records the earlier v4 implementation and is superseded by the v5 picture
frame and current validation above.

Implemented and validated 2026-08-20 in Blackdog task `TASK-6EE9676C`,
targeting `main` from base `8661167bd78f93d85f3b868cd52433d9eb928b64`.

The former Stage 3.4 batch drew one center circle and four cardinal circles at
fixed ±30 mm offsets, returned to an X-max/Y-zero-biased reveal pose, and copied
the smaller Stage 3.3 bootstrap rectangle into the accepted tip map. It therefore
could not frame a substantially larger accepted Boundary envelope or expose that
envelope as Drawing Studio's drawable region.

`SparseTipBatchMarkPlan` now owns one center and four maximum drawable corner
centers, with each edge inset exactly by the 2 mm circle radius so all 80 physical
circle chords remain inside the accepted Boundary envelope. The operation keeps
Pen Up between marks and returns Pen Up to the rectangle center for the one
shared frozen reveal. The four outer centers become the accepted
`TipCameraRegistration` applicability rectangle and Drawing Studio region; the
existing calibrated-region overlay renders their bounding box without adding a
slow physical perimeter stroke. Per-mark cap-map extrapolation residual is
retained as diagnostic evidence instead of gating a corner outside the smaller
Stage 3.3 bootstrap rectangle. The final center reveal retains the existing
camera/cap revalidation. Motion telemetry names the actual minimum/maximum-axis
corner rather than exposing the retained legacy evidence-slot raw value. The v4
estimator prevents an older fixed-offset checkpoint from being reconstructed as
corner evidence; an older accepted map remains bounded by its recorded smaller
applicability until a fresh physical batch supplies new observations.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused planning, tip-authority, and sparse-workspace suites | passed — 34 tests | Boundary-derived corner centers, circle containment, 80 chords, center reveal MPos, diagnostic cap residual, full-region applicability, bounding overlay, arbitrary click order, checkpoint reconstruction, and Stage 4 consumption |
| `make quick-test` | passed — 449 tests | fast unit/component partition with retained journeys excluded |
| `make journey-test` | passed — 10 tests | sparse calibration, checkpoint revalidation, exact tip revision, reset, Boundary, drawing, and Stop journeys |
| `make strict-check` | passed — 459 tests | strict concurrency, warnings as errors, signed bundle, launcher checks, full test suite, and repository checks |
| superseded fixed-offset/reveal/estimator scan | passed — zero current source, test, and authority-doc matches | old ±30 mm Stage 3.4 plan, X-max/Y-zero reveal, planner offset symbol, and v3 estimator/workspace revisions |
| `git diff --check` | passed | whitespace and conflict markers |

These are source, deterministic fixture, simulator, build, signed-bundle, and
repository-contract results. The new binary was not launched for an attended
camera workflow. No physical controller, motion, Pen Down/Up, camera capture,
operator click, circle visibility, paper coverage, bounding-overlay visibility,
or observed-ink validation was performed.

### Stage 3.3 exact viewport and analysis-lock continuity

Implemented and validated 2026-08-17 in Blackdog task `TASK-B1EB11D5`,
targeting `main` from base `4b78432d619c31fb76947a7dd9aaa12799ab3d97`.

Stage 3.3 acceptance previously preserved only the numeric zoom and pan values.
Acceptance also changed the viewport fitted target from the pre-registration
fallback to learned plotter bounds, so those same numbers produced a different
effective camera-pixel rectangle. A locked analysis region remained the old
rectangle, leaving the displayed view inconsistent with the still-active lock.

`ActionSurfaceViewportState` now snapshots the exact effective visible
camera-pixel rectangle before a compatible source/configuration context replaces
its fitted target. Stage 3.3 acceptance and later compatible fitted-bound
replacements retain that rectangle and leave `VideoAnalysisRegionLock`
unchanged. An explicit Full, Fit, slider, or pan action remains authoritative;
source or camera-configuration incompatibility still resets the viewport.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused viewport suite | passed — 10 tests | real Stage 3.3 `nil`-to-learned fit transition, replacement fit, exact visible rectangle, locked analysis-region continuity, explicit controls, pan, clipping, and incompatible-camera reset |
| `make quick-test` | passed — 448 tests | fast unit/component partition with retained journeys excluded |
| `make journey-test` | passed — 10 tests | sparse calibration, checkpoint revalidation, exact tip revision, reset, Boundary, drawing, and Stop journeys |
| `make strict-check` | passed — 458 tests | strict concurrency, warnings as errors, signed bundle, launcher checks, full tests, repository contract, and diff check |
| `git diff --check` | passed | whitespace and conflict markers |

These are source, deterministic fixture, simulator, build, signed-bundle, and
repository-contract results. The new binary was not launched for an attended
camera workflow. No physical camera, controller, motion, Pen, operator-click,
or observed-ink validation was performed.

### Historical: durable prefix with restart pose revalidation

This records the 2026-08-17 implementation and is superseded by **Software
restart preserves accepted Learning authority** above.

Implemented and validated 2026-08-17 in Blackdog task `TASK-69EC31D1`,
targeting `main`.

One integrity-checked atomic checkpoint now retains the accepted LIVE Learning
Path prefix: Pen Interaction, Boundary and center artifacts, the Stage 3.3
machine-to-cap registration, the accepted Stage 3.4 tip registration, and the
Stage 4 evidence-record reference. Production migrates the former separate
machine and tip checkpoint files when possible. Because those legacy files did
not contain Pen Interaction, Stage 3.3, or Stage 4 payloads, they cannot
manufacture the missing historical stages; future acceptance under this build
records the complete prefix.

Restart loads learned values but never restores Motion authorization, current
Pen pose, active ownership, Stop capabilities, camera frames, or pending
commands. A fresh passive controller-identity probe restores parked machine and
Stage 3.3 authority. Reported MPos displacement is diagnostic and leaves
coordinate-dependent Learning and Drawing Studio blocked until one fresh exact
cap frame revalidates pose. It is not authority over direct manual controls:
manual jog and manual Pen commands remain gated by Motion authorization and the
controller's current connection, alarm, readiness, safety, and serialization
facts. Under unchanged machine, camera-mount, optical, tool, and paper-plane
identities, the fresh cap may establish a pure coordinate translation; accepted
Boundary, machine-camera, and tip geometry then move together under a new
coordinate revision. Rotation, scale, and uncertain identity are not inferred.

The Stage 3.4 click set now produces a reviewable frozen-frame proposal.
**Accept Tip Map** is the explicit durable commit. Reject, undo, and clear retain
the same frozen frame and perform no redraw or motion. **Reset From This Step**
writes or clears the retained durable prefix before changing in-memory learning;
a storage failure leaves the current learning state intact. Stage 4 completion
is accepted only against the exact saved tip revision. Paper coverage wording
now identifies **Assert Sheet Covers Outline** as an operator assertion rather
than measured paper-edge evidence.

A read-only direct serial probe was also performed while the application was
closed on `/dev/cu.usbserial-A10OF67O` at 115200 baud. Only `?`, `$G`, `$#`, and
`$I` were transmitted. The controller reported Idle, `MPos:277.560,-39.875,0`,
zero G54 offsets, and grblHAL BlackBox X32 identity. No jog, Pen command, alarm
clear, reset, or other motion-capable command was transmitted. This proves a
responsive controller and reported state only; it does not prove physical pose
after unpowered carriage movement.

| Validation | Result | Scope |
| --- | --- | --- |
| Restart/reset focused suites | passed — 8 tests | atomic store integrity, saved Boundary restore, no-mark tip revalidation, and reset-prefix atomicity |
| `make quick-test` | passed — 437 tests | fast unit/component partition with retained journeys excluded |
| `make journey-test` | passed — 10 tests | sparse calibration, checkpoint revalidation, exact tip revision, reset, Boundary, drawing, and Stop journeys |
| `make strict-check` | passed — 447 tests | complete strict concurrency, warnings as errors, signed bundle, launcher checks, full tests, repository contract, and diff check |
| `git diff --check` | passed | whitespace and conflict markers |

These results are source, deterministic fixture, simulator, build, signed
bundle, repository-contract, and read-only controller-query evidence. The new
binary was not launched for an attended camera workflow. No physical motion,
Pen Down/Up, operator click, paper placement, cap revalidation, or observed ink
was exercised by this task.

### Retained comparison, paper lineage, and placed-vector Drawing Studio

Implemented and validated 2026-08-17 in Blackdog task `TASK-FF3A5E6A`,
targeting `main`.

Stage 4 now finishes with a retained exact post-frame comparison of the cyan
predicted line, measured ink, and residuals. The workbench reports **Map ready**,
**Interactive learning complete**, or the separately scoped **Adaptive drawing
ready** state without treating one isolated line as model-training completion.
Entering Drawing Studio releases the retained Stage 4 frame and projects its
target only onto the currently displayed exact frame.

Paper identity is split into replaceable sheet instance and calibrated contact
plane. Declaring a new sheet on the same contact plane preserves the accepted
tip map, rotates ink-specific identity, and requires fresh explicit coverage.
Declaring a changed contact plane invalidates the tip map. Paper coverage,
drawable-region, and predicted-tip overlays retain exact frame/configuration
provenance. Both paper identities, coverage evidence, accepted tip checkpoints,
and drawing-run evidence survive restart through separate typed stores.

Drawing Studio consumes the canonical Model `DrawingProgram` path. Its fixed
catalog contains line, polyline, rectangle, square, triangle, regular polygon,
circle, ellipse, star, pyramid, and elephant programs. Placement produces a
content-addressed machine execution plan inside the learned drawable region;
the Runtime owns ordered Pen-Up travel, Pen Down, logical strokes, Pen Up, and
per-stroke checkpoints. The generic observer compares all planned polylines
with new ink on an exact same-pose frame pair. The append-only run record pins
program, placement, plan, model, registration, paper, request and execution
frontiers, terminal disposition, observation, and evidence role.

Audit corrections keep paper management and draft mutation unavailable while a
run owns execution or evidence capture, expose Stop only while a motion owner
exists, retain an execution-only record when post-run frame evidence is
unavailable, and block an already-commanded plan from redraw. Those exact plan
hashes are reconstructed from the durable archive after restart; a new sheet
clears only the prior sheet's ink-specific block. **New Run** retains archived
evidence and requires a distinct safe placement before a possibly inked plan
can execute again.

The deterministic catalog, trial roles, evidence archive, and typed readiness
schema are foundations for later active learning. No coverage selector,
candidate residual model, model promotion coordinator, or emitted adaptive-ready
assessment is implemented by this task.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused Model suites | passed — 19 tests | catalog determinism, curve tessellation, placement, planning, content identity, and typed readiness |
| Focused Runtime/evidence suites | passed — 25 tests | paper semantics, coverage, multi-stroke ownership, exact execution frontiers, no resend, planned-ink observation, archive integrity, and frame-unavailable evidence |
| Focused App/workspace suites | passed — 21 tests | retained comparison, exact-frame Studio projection, truthful capability/paper state, immutable editing states, processing without Stop, and new-run review controls |
| `make quick-test` | passed — 432 tests | fast unit/component partition with retained journeys excluded |
| `make journey-test` | passed — 10 tests | sparse calibration, checkpoint revalidation, exact tip revision, one-Go/reset, Boundary, drawing, and Stop journeys |
| `make strict-check` | passed — 442 tests | strict concurrency, warnings as errors, signed bundle, launcher validation, full suite, repository contract, and diff check |
| `git diff --check` | passed | whitespace and conflict markers |

These results are software, deterministic fixture, simulator, build, signed
bundle, and repository-contract evidence. No attended hardware, live camera,
physical motion, physical Pen Down/Up, operator click, paper placement, or
observed physical ink was exercised by this task.

### One-Go predicted isolated-line validation

Implemented 2026-08-16 in Blackdog task `TASK-ED0800E2`, targeting `main`.

The visible Stage 4 surface is now one 4.1 exercise. One **Go** chooses the first
clear signed-axis 5 mm plan, renders its model-predicted cyan line on the current
video before motion, then owns baseline capture, Pen-Up travel, the single
stroke, same-pose reveal, strictly newer frame capture, isolated-ink Vision, and
the normal typed comparison. Motion retains **Stop**. Foreground trial Vision is
named as the active operation owner. Possible ink, rejected Vision evidence, or
ambiguous controller outcomes stop without automatic redraw.

The fifth valid Stage 3.4 click now atomically constructs and commits the
`TipCameraRegistration`; only an actual commit failure exposes a retry. The UI
distinguishes **Map ready** after Stage 3.4 and **One attributable validation
complete** after Stage 4.1 from a future scoped **Trained/Ready** assessment.
Repeated coverage, reserved holdouts, candidate/prior comparison, shape
holdouts, and typed readiness remain roadmap work.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused Stage 3.4/4.1 suites | passed — 49 tests | one-Go ownership, predicted preview before motion, foreground Vision status, automatic comparison, fifth-click commit, Stop/no-redraw recovery, and atomic reset |
| `make quick-test` | passed — 384 tests | fast unit/component partition with retained journeys excluded |
| `make journey-test` | passed — 10 tests | sparse calibration, checkpoint, exact tip revision, one-Go reset, Boundary, drawing, and Stop journeys |
| `make strict-check` | passed — 394 tests | strict concurrency, warnings as errors, signed bundle, launcher validation, complete suite, repository contract, and diff check |
| `git diff --check` | passed | whitespace and conflict markers |

These results are software, deterministic fixture, simulator, build, and bundle
evidence. Attended hardware, camera, physical motion, Pen Down/Up,
operator-click, and observed-ink validation were not performed by this change.

### Stage 3.4 five-circle batch and affine-first authority

Implemented and landed locally 2026-08-16 in Blackdog task `TASK-0D8990BE` as
commit `b93e49fb3cf4fc39704f8b3da299b6affff537c3` on its recorded target branch,
`main`.

The implementation replaces per-circle progression with one supervised action
that draws five separated 2 mm-radius circles at Stage 3.4 offsets of ±30 mm,
settles Pen Up between circles, performs one final reveal, and freezes one exact
frame for five arbitrary-order clicks. Centered projected/clicked point sets and
an exhaustive deterministic 5! assignment associate clicks without a distance
or ambiguity threshold. All five observations enter affine construction first;
constant correction is only the construction fallback. Residuals, RMS,
covariance, and uncertainty are diagnostic only. Stage 3.4 has no holdouts or
numerical route to paper replacement, does not change viewport state, and makes
Stage 4 current only after explicit tip-registration acceptance. Stage 3.3
retains its separate ±24 mm camera calibration and holdout authority.

Focused software validation passed: 11 TipCalibrationAuthority tests, 3 sparse
coordinator tests, 12 calibration-planning tests, 7 sparse workspace tests, 18
ActionSurface/viewport tests, and 11 Learning Path projector tests.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused Stage 3.4 suites | passed — 62 tests | affine-first authority, batch planning and coordination, shared frozen frame, arbitrary-order association, viewport continuity, and Stage 4 progression |
| `make quick-test` | passed — 377 tests | fast unit/component partition |
| `make journey-test` | passed — 10 tests | sparse calibration, reset, Boundary, drawing, and Stop journeys |
| `make strict-check` | passed — 387 tests | strict concurrency, warnings as errors, signed bundle, launcher validation, and full test suite |
| `git diff --check` | passed | whitespace and conflict markers |

Attended hardware, camera, motion, Pen Down/Up, operator-click, and observed-ink
validation were skipped and remain unproven.

### Stable exact-frame overlays and Learning viewport continuity

Validated 2026-08-15 in Blackdog task `TASK-912F3060`, targeting `main`
from base `6846f0b880622e24a78b3d5c5e85e30d9a934a44`.

Automatic scene analysis now retains the last completed Pen cap and inferred
Armature envelope geometry while the next frame is analyzing, but only while
that completed result still matches the displayed exact frame. Its completed
typed status also remains stable instead of oscillating through Analyzing. A
stale frame or camera configuration still renders no scene geometry. Re-entering Identify Pen
Cap with a valid LIVE appearance analyzes the newly frozen frame itself before
presenting overlays; a first unlearned appearance still requires its exact-frame
operator click before LIVE recognition can run.

Action-surface zoom and pan now survive entering or leaving Learning and other
compatible presentation-context revisions. Camera source/configuration changes
still reset the viewport. Its former sparse-mark automatic focus was historical
behavior and is superseded by the Stage 3.4 batch above.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused overlay, viewport, and Identify Pen Cap tests | passed — 46 tests | analyze-cycle retention and stale refusal, Learning visibility, compatible zoom/pan continuity, source/configuration reset, superseded sparse viewport behavior, and frozen-frame overlay identity |
| `make quick-test` | passed — 377 tests | fast unit/component partition |
| `make journey-test` | passed — 10 tests | sparse calibration, reset, Boundary, drawing, and Stop journeys |
| `make strict-check` | passed — 387 tests | strict concurrency, warnings as errors, signed bundle, launcher validation, full test suite, and repository checks |
| `git diff --check` | passed | whitespace and conflict markers |

These results are software and deterministic fixture/simulator evidence. No
attended camera, controller, motion, pen, operator-click, or observed-ink
validation was performed, and the changed app was not launched against physical
hardware.

### Limit-aware manual alarm unlock

Validated 2026-08-14 in Blackdog task `TASK-01E545BB`, targeting `main`
from base `b609c4103099ede12775be0f1dd26545ada10576`.

The Motion panel now projects the sampled X/Y/Z axis-limit inputs separately
from the latched controller alarm and labels manual alarm unlock as armed,
blocked, or not armed. A current Alarm report with no asserted axis-limit input
arms **Clear Alarm**. An asserted `Pn:X`, `Pn:Y`, or `Pn:Z` disables it and tells
the operator to release the physical switch and Connect again. Missing current
limit evidence remains unarmed.

`MachineController` also performs a second realtime status query immediately
before `$X`. If any axis limit became asserted after Connect, current status is
unavailable, or the controller is no longer in Alarm, it records a typed refusal
without transmitting `$X`. A historical alarm with currently clear axis inputs
remains an explicit operator-owned unlock; Connect remains passive and Motion
authorization remains inactive.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused controller and UI selection | passed — 64 tests | XYZ limit sampling, visible armed/blocked state, fresh pre-write race, no `$X` on asserted Z, acknowledged unlock, and fresh reprobe |
| `make quick-test` | passed — 345 tests | fast unit/component partition |
| `make strict-check` | passed — 355 tests | strict concurrency, warnings as errors, signed bundle, launcher validation, full test suite, and repository checks |
| `git diff --check` | passed | whitespace and conflict markers |

These are software and deterministic transcript results. No attended controller
connection, physical switch assertion/release, alarm unlock, homing, motion,
pen, camera, or ink validation was performed.

### Controller alarm visibility and explicit clearing

Validated 2026-08-14 in Blackdog task `TASK-415B504F`, targeting `main`
from base `34de05332cd5d4c0154c402c4609d881b20b9687`.

A failed Connect probe now preserves and projects its exact typed controller
alarm, controller error, timeout, invalid-reply, or transport blocker instead
of collapsing the workbench to generic Disconnected status. The Motion panel
shows the current controller alert. A reported alarm exposes one explicit
**Clear Alarm** action with an in-context warning that unlock is not homing,
position recovery, limit clearing, Motion authorization, or proof of safe
movement.

The runtime admits `$X` only from current alarm evidence for the selected
controller, serializes it against every other controller operation, records raw
I/O plus a typed alarm-clear outcome, and never sends it during Connect. An
acknowledged unlock clears no evidence authority by itself: the same operator
action runs a fresh complete passive probe, leaves Motion inactive, and requires
the operator to press **Enable Motion** separately. Rejection or transport
uncertainty closes the link, remains visible, and is never retried
automatically.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused controller and UI selection | passed — 62 tests | alarm retention, no implicit unlock, typed clear admission/refusal/acknowledgement/rejection, fresh reprobe, UI status, and Motion remaining disabled |
| `make quick-test` | passed — 343 tests | fast unit/component partition including typed alarm-clear ledger evidence |
| `make strict-check` | passed — 353 tests | complete concurrency, warnings-as-errors, signed bundle and launcher validation, full test suite, repository checks |
| `git diff --check` | passed | whitespace/conflict markers |

These are software and deterministic transcript results. The already-running
app and physical controller were inspected read-only before implementation,
but this change was not launched into that app. No alarm was cleared, and no
attended controller connection, physical limit inspection, homing, reset,
Motion enablement, physical movement, pen action, camera validation, or ink
validation was performed.

### Pen-Down manual motion and Learning Off

Validated 2026-08-12 in Blackdog task `TASK-F782C7D6`, targeting `main`
from base `57406224cb5556cfa54df3332988c877148bff9c`.

The four manual direction controls now route a known commanded Pen Up state to
ordinary relative travel and a known commanded Pen Down state to the existing
bounded drawing-stroke owner. Consecutive clean Pen-Down moves retain Pen Down,
so the operator can request all four sides of a square. The drawing path has its
own typed telemetry and capability-bound Stop; a clean Stop waits for Idle and
retains the drawing owner's one Pen Up outcome. Unknown pen state remains a
pre-request refusal.

The workbench also exposes explicit **Turn Learning Off** and **Turn Learning
On** actions. Off hides the Learning Path and Exercise panes and refuses new
Learning actions without clearing accepted learning, disconnecting, disabling
Motion, stopping video, or gating direct manual control. An active Learning
attempt must settle through its existing Cancel/Stop action first.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused manual/Learning tests | passed — 5 tests | four-side Pen-Down square, drawing Stop/Pen Up, Learning Off authority preservation, active-attempt interlock, causal simulator drawing with zero machine actions |
| `make quick-test` | passed — 329 tests | fast unit/component partition |
| `make journey-test` | passed — 10 tests | retained sparse, checkpoint, Stage 4, Boundary, reset, and simulator journeys |
| `make strict-check` | passed — 339 tests | complete concurrency, warnings-as-errors, signed bundle and launcher validation, full test suite, repository checks |
| `git diff --check` | passed | whitespace/conflict markers |

These are software and simulator results. The app was not launched for this
change. No controller connection, physical pen actuation, physical motion,
manual square, camera observation, or observed ink validation was performed.

### Learning recovery progression and pen-cap color transport

Validated 2026-08-15 in Blackdog task `TASK-51E90720`, targeting `main` from
base `cce86f38150b2b83e9cb44e89148920c4a578a46`.

`LearningPathProjector` derives the current exercise from the active owner and
unmet dependency chain; a settled restartable attempt remains a selectable
needs-attention row with its own **Restart** action and cannot replace the
current exercise action strip. This historical change also established RGB
color propagation through continuous bounded analysis and exclusive Stage 3.3
inspections, with color-specific estimator revisions preventing one five-sample
proposal from mixing recognition settings. Its editable Video Settings color
well was later removed. The later exact-frame selection contract is the
**Identify Pen Cap** action recorded below.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused projector, Vision, and workspace tests | passed — 19 tests | recovery/current-action separation, green-to-magenta component selection, camera-owner propagation |
| `make quick-test` | passed — 355 tests | fast unit/component partition |
| `make journey-test` | passed — 10 tests | retained causal simulator journeys |
| `make strict-check` | passed — 365 tests | strict concurrency, warnings-as-errors, signed app bundle and launcher, full tests, repository checks |
| `git diff --check` | passed | whitespace/conflict markers |

These are software and deterministic simulator claims. The application UI was
not launched. No attended camera, controller, motion, pen, operator color
selection, calibration click, or observed-ink validation was performed, so the
results do not establish physical color tolerance or cap-recognition reliability.

### Earlier historical implementation snapshots

Every section below this boundary describes the repository at its stated
commit/date. Present-tense wording is local to that historical landing and is
not current product or architecture authority. Later entries above supersede
stage numbering, workflow shape, terminology, and implementation owners.

### Pure Learning Path projection

Validated 2026-08-13 in Blackdog task `TASK-F6773B41`, targeting `main`
from base `0a04af61581552f7613faf53b8968c5ef8f5c030`.

One values-only `LearningPathProjectionSnapshot` now feeds the pure
`LearningPathProjector`. The projector owns current-item and navigator status,
review detail, action strips, exact Stop capability presentation, typed failure
rendering, evidence, timeline/activity/subsystem rows, sparse-calibration and
Drawing Trial presentation, and reset surfaces. `OperatorWorkspace` retains
controller/camera/persistence ownership, operational policy and admission,
artifact acceptance, reset execution and stale-plan guards, and typed intent
routing. SwiftUI consumes one aggregate projection per Learning Path render.

The extraction deleted the parallel workspace presentation path.
`OperatorWorkspace.swift` fell from 10,197 to 8,905 lines and from 226 to 202
function declarations by the repository's source inventory. Direct projector
tests cover deterministic repeated projection, every row/state, LIVE/SIMULATED
parity, Stop ownership, typed failures, reset/vacate presentation, sparse
phases, Drawing Trial progression, and immutable review selection. Existing
workspace integration tests continue to cover routed actions and authority.

Validation results are recorded by the Blackdog landing result. These are
software and deterministic simulator claims only. No application launch,
controller, attended camera, physical motion, Pen Down, click, or observed-ink
validation was performed.

### Cohesive Learning Path state and typed transitions

Validated 2026-08-13 in Blackdog task `TASK-40195892`, targeting `main`
from base `57406224cb5556cfa54df3332988c877148bff9c`.

An independent cumulative re-audit after the source-session and workflow-
lifecycle landings found four remaining synchronized-field clusters. The
exercise attempt is now one idle/active lifecycle; sparse frozen-point
selection is one idle/awaiting-click/selected lifecycle; Drawing Trial payload,
history, rollback, and rewind are one cohesive value; and supervised motion
plus settlement use exhaustive typed action identity. The unused raw camera-
proposal UUID sentinel and the former manual Drawing Trial snapshot copy are
deleted.

Focused tests cover duplicate-start rejection, typed motion identity, sparse
re-click frame/point consistency, source isolation, invalidation/reset, atomic
fallback, ambiguous/lost terminal cleanup, checkpoint recovery, and no-redraw
behavior. Full validation is recorded by the Blackdog landing result. No app
launch, controller, camera, motion, pen, click, or physical ink validation was
performed.

### Source-indexed learning sessions

Validated 2026-08-12 in Blackdog task `TASK-3E783DB1`, targeting `main`
from base `adcf90f9095ac40c395178366ee79f7fe1a7060c`.

`OperatorWorkspace` now holds independent LIVE and SIMULATED
`LearningSessionState` values governed by one structural contract. Source
switching selects the active value instead of snapshotting and restoring a
shared authority surface. Entering SIMULATED creates a fresh nonphysical
session; returning to LIVE selects the unchanged LIVE value. Durable machine
and tip checkpoint capabilities are LIVE-only, and the full simulated sparse
calibration journey proves no additional durable loads and zero saves or clears.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused workspace and sparse-tip suites | passed — 36 tests | source switching, independent resets, checkpoint isolation and revalidation, Boundary, Stage 4, possible ink |
| `make quick-test` | passed — 322 tests | fast unit/component partition |
| `make journey-test` | passed — 10 tests | retained sparse, checkpoint, Stage 4, Boundary, reset, and simulator journeys |
| `make strict-check` | passed — 332 tests | complete concurrency, warnings-as-errors, signed bundle and launcher validation, full test suite, repository checks |
| obsolete snapshot-symbol scan | passed — zero source/test matches | former snapshot type and parked/capture/restore/reset compatibility paths |
| `git diff --check` | passed | whitespace/conflict markers |

These are software and simulated-workflow results. No app launch, controller
connection, physical motion, camera capture, Pen Down observation, or observed
physical ink validation was performed.

The source at that landing contained exactly two post-Boundary calibration
exercises:

- 3.3 five-cap machine-to-visible-cap registration with three fit samples and
  two sealed holdouts. Each LIVE sample requires three strictly newer compatible
  exact inspections, refuses any non-accepted or ambiguous cap and more than
  2 px maximum pairwise cap-centroid spread, and retains the newest third exact
  frame/measurement without averaging;
- 3.4 one supervised four-circle batch with no center mark, four 2 mm-radius/
  16-chord marks whose centers are 10 mm inside the accepted Boundary, independent Down/Up
  evidence, settled Pen Up before every inter-circle travel, one final center
  reveal, one shared frozen exact frame, arbitrary-order clicks with
  deterministic 4! assignment, a 10 mm-inset corner-center applicability rectangle,
  affine-first construction, constant construction fallback, diagnostic-only
  residuals and uncertainty, stable operator viewport state, and atomic tip-map
  commit.

`TipCameraRegistration` maps machine coordinates directly to contact pixels.
Stage 4 consumes its exact revision and owns one closed Drawing Border plan
through the four circle centers, its local baseline and reveal MPos, canonical
drawing-plan execution, newer post-frame, and planned ink observation.
The camera view separately projects the accepted 3.2 Boundary and the inset
Drawing Border; during proposal review the latter is a cyan planned overlay,
and after acceptance it is the exact Stage 4.1 drawing domain.

The single Learning package loads as a presentation-only candidate. It projects
compatible saved geometry and reports advisory optical shift/background MAD;
only **Use Saved Training** applies its exact revisions. **Start New Learning**
retains the last complete package. An actual paper replacement rotates paper
identity and requires current calibration on that paper. Possible ink is keyed
by machine position plus mark radius plus paper identity and survives cancel,
restart, and reset on that paper; it never triggers automatic redraw.

The former multi-step target/region workflow, its runtime protocol, simulator
fixtures, exclusive tests, actions, artifacts, and detector composition are
deleted rather than retained as compatibility code.

### Stable preview during automatic overlay analysis

Validated 2026-08-12 in Blackdog task `TASK-D2BD0315`, targeting `main` from
base `d191045ef20026626437a3d92943cd0d80e7c167`.

Automatic overlay analysis no longer changes ActionSurface opacity, presents an
analysis badge, or owns a preview-publication pause token. Its subsystem status
is stable across individual analysis start/completion transitions. The separate
exclusive preview lease remains for explicit exact-frame operations such as
calibration and isolated-ink observation.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused ActionSurface, workspace, and scene-pipeline tests | passed - 32 tests | canonical rendering, overlay lifecycle, region/cadence propagation, scoped Vision settlement, bounded pipeline behavior |
| `make quick-test` | passed - 322 tests | fast unit/component partition |
| `make strict-check` | passed - 332 tests | complete concurrency, warnings-as-errors, signed bundle and launcher validation, full test suite, repository checks |
| obsolete-state scan | passed | no ActionSurface analysis-active state, analyzing badge, dimming rule, automatic preview gate, or oscillating overlay-analysis status remains |
| `git diff --check` | passed | whitespace/conflict markers |

These are software and simulated-workflow results. The app was not launched for
this correction. No attended camera, controller, motion, pen, pen-cap,
armature, preview-fluidity, or observed-ink validation was performed.

### Overlay ownership and implemented curriculum endpoint

The implementation at that landing exposed exactly two persistent global controls:
**Pen cap** and **Armature envelope**. The envelope is explicitly inferred from
the cap and is not independently segmented. Operator/persistence-owned
preference is separate from requested features, typed status, and exact-frame
geometry. Scene, workflow, and simulation results have independent owners and
compose only for the exact displayed source, camera configuration, and frame.

The first Pen Interaction action is **Identify Pen Cap**. Before any question
or pen request, the operator clicks the colored cap body, not the tip, on one
frozen exact frame. The implementation samples a clipped 9 x 9 neighborhood,
rejects stale or unsupported evidence and gray, white, dark, or insufficiently
chromatic pixels, and persists the accepted median RGB color with exact frame,
source, camera configuration, click, sample-count, pixel-format, and algorithm
provenance. It supports arbitrary visibly colored caps, including blue. There
is no editable `ColorPicker`. Without an accepted LIVE appearance, the two
overlay preferences remain unchanged while LIVE cap and inferred-armature
statuses are Unavailable and no LIVE geometry is rendered.

Generic ROI is independent from workflow ROI, full-frame lock is canonicalized
to default analysis, and ROI does not change whole-frame cap-size eligibility.
Frame-side/drawing-frame analysis and the optional Boundary Vision adviser are
absent; fixed bounded Boundary renewal, Stop, Idle/MPos settlement, and fallback
authority remain. Stage 4 intended geometry, observed ink, and residuals are
contextual evidence with no global toggles.

The visible Learning Path at that landing ended at the one-Go 4.1 observed-line
validation. The former
selectable future stage, speculative online model-learning dataset, policy/reward
episode scaffolding, model-mismatch renderer, and model-prediction overlay kind
are deleted. Adaptive requirements remain roadmap-only.

During signed LIVE inspection the C920 camera was live and a blue cap was
visibly present, but **Identify Pen Cap** was not clicked: reaching Pen
Interaction requires the preceding controller/Motion curriculum, which was
outside the authorization for this inspection. The controller stayed
disconnected, Motion stayed disabled, and no operation was admitted. No
Connect, Start, Enable Motion, manual-motion, pen, or calibration action was
used. The reported physical pen position remains ambiguous and therefore
possible ink; no motion or pen action occurred.

Blue-cap detection reliability, click ergonomics, cap-inferred armature
usefulness, preview fluidity, attended calibration, controller behavior, motion,
pen behavior, and observed ink remain skipped and unproven. Seeing the cap in a
live preview and verifying the UI layout does not establish any of those claims.

### Stage 3.4 circular-mark visibility correction

Validated 2026-08-12 in Blackdog task `TASK-BAD20882`, targeting `main` from
base `3a025e489c6f1115faaa2b107c7eb33a8db4ba09`.

| Validation | Result | Scope |
| --- | --- | --- |
| Focused Stage 3.4 and checkpoint tests | passed — 83 tests | 2 mm/16-chord/100 mm/min geometry, far reveal, full configured Down outcome, superseded frozen-frame viewport behavior, Stop blacklist, checkpoint reconstruction, Stage 4 clearance, rebased numerical-zero travel, scoped overlay retention |
| `make quick-test` | passed — 321 tests | fast unit/component partition |
| `make journey-test` | passed — 10 tests | retained sparse-circle, checkpoint, Stage 4, Boundary, reset, and simulator journeys |
| `make strict-check` | passed — 331 tests | complete concurrency, warnings-as-errors, signed bundle and launcher validation, full test suite, repository checks |
| `git diff --check` | passed | whitespace/conflict markers |

These are software and simulated-workflow results. No app launch, controller
connection, physical motion, camera capture, Pen Down observation, or observed
ink validation was performed for this correction.

### Phase 4 automated evidence

Validated 2026-08-12 in Blackdog task `TASK-2AF7445C`, targeting `main` from
base `02f8431ad5af762f0a293912435fa7f6834181b9`.

The integrated validation matrix is populated from the landing run. Commands
are executed in the Blackdog task worktree and are software evidence only.

| Validation | Result | Scope |
| --- | --- | --- |
| Independent architecture/deletion review | passed with fixes | chronology, checkpoint restore, post-click drawing, blacklist/reset lifecycle, journey routing, stale symbols |
| Focused sparse authority and ActionSurface tests | passed — 72 tests | model/evidence constructors, checkpoint, frozen click, review geometry, planning, simulator |
| Checkpoint restart and paper-plane journey | passed within focused/journey gates | same-paper no-mark restore; legacy changed-paper contact-plane route now superseded by full recalibration |
| LIVE reset durable-tip test | passed | quarantined tip store is cleared by affected Reset All plan |
| `git diff --check` | passed | whitespace/conflict markers |
| `make quick-test` | passed — 312 tests | unit/component partition with retained journeys excluded |
| `make journey-test` | passed — 11 tests | retained sparse, checkpoint, Stage 4, Boundary, reset, and simulator journeys |
| `make strict-check` | passed — 323 tests | signed bundle, launcher, full tests, repository contract, strict concurrency, warnings-as-errors, diff check |
| Deleted-symbol search | passed — zero matches | removed workflow types/actions/labels across source, tests, current docs, and Makefile |
| Blackdog configured validation (`git diff --check`) | passed | repository-configured landing validation |

The pre-landing patch touches 48 paths: 7,077 added lines and 12,317 deleted
lines, net −5,240. This is strongly net-negative even with all five new
untracked implementation/test files counted. The primary checkout remained
clean at the same base commit during validation. The landed commit and cleanup
state are recorded in the external phase coordination ledger because a commit
cannot truthfully contain its own hash.

A passing row means only that exact command and scope passed in this task
worktree.

## Simulator evidence

The causal simulator retains a large nonzero cap-to-tip truth, persistent black
16-segment circular marks, closed frame ink, paper identity, and exact causal frames. It
traverses the same public actions and dependency graph without calling physical
machine actions. It validates workflow structure and provenance plumbing only.

Every simulator claim is labeled `SIMULATED — NOT PHYSICAL EVIDENCE`.

## Physical-validation boundary

For this replacement run, all of the following were deliberately skipped:

- physical camera capture and optical-identity validation;
- physical controller connection, command acceptance, Idle/MPos settlement, or
  motion observation;
- physical full Pen Down/Up, 2 mm-radius circle motion, and contact behavior;
- a human operator clicking real observed marks;
- physical paper/contact-plane checkpoint revalidation;
- observed physical black marks or Stage 4 line ink.

Therefore this run does **not** establish physical calibration accuracy,
physical contact safety, camera quality, controller behavior, pen behavior,
operator-click usability, or observed-ink performance. Use the attended
runbook to create those evidence classes.

## Known limitation

Machine/tool/contact/mount/reframing semantic revisions are stable across app
restarts, and paper replacement has an explicit revision rotation. The current
UI does not yet provide dedicated revision-rotation controls for every other
physical assembly change. An attended operator must refuse checkpoint
revalidation after any unrecorded remount or assembly change and perform a full
reset/recalibration. Dedicated controls remain roadmap work.

Frame hashes and metadata remain provenance. The Learning package now stores
exactly one bounded (16 MiB maximum) reference frame for advisory optical
comparison; it is not a general frame archive and is never physical proof.
