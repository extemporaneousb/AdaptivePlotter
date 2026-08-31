# AdaptivePlotter Current Evidence

Status: current evidence ledger; software, simulator, controller, and attended
physical claims are recorded separately

This document records what was actually verified. Product meaning belongs to
[Product Contract](PRODUCT_CONTRACT.md), package ownership to
[Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md), and the physical
procedure to [Attended Hardware Runbook](ATTENDED_HARDWARE_RUNBOOK.md).

## GATE-01 source-derived inspection — continuation refused

The post-EA-11C repository inspection did not pass `GATE-01`. The one invoked
`sh Scripts/check_episode_pilot_gate.sh` command exited 1 with
`episode Pilot gate failed: missing table: Validation / Result / Scope` because
the Pilot checker did not accept EA-06's canonical alternate detailed-evidence
header. Static inspection also proved that parser repair alone cannot pass the
gate: the unchanged `operator-workspace-adapters` 7-to-10 threshold currently
fails.

The exact current source-backed metric facts that already have stable identity
sets are:

| Reduction metric | Baseline | Current | Requirement |
| --- | --- | --- | --- |
| independent-admission-sites | pending | pending | decreased |
| workspace-task-owners | 9 | 0 | decreased |
| environment-mode-branches | pending | pending | decreased |
| direct-effect-calls | pending | pending | decreased |
| operator-workspace-policy-state | 6 | 1 | decreased |
| operator-workspace-adapters | 7 | 10 | not-increased |

The inspection also produced three candidate operational proxies: application-
owned independent admission families measured 18-to-2, duplicate application
environment/effect-owner families measured 2-to-0 while excluding the retained
causal simulator, and arbitrary stored closure-effect member identities measured
40-to-0. Those proxies are not yet the literal metrics and therefore do not fill
the pending cells above. `FIX-05` must install pinned executable EA-01-to-
candidate source-identity manifests for all six rows, reconcile those three
operational units to the literal names, and fail if the reconciliation is not
source-defensible.

| Pilot predicate | Result | Evidence |
| --- | --- | --- |
| GENERICITY | passed | `EA-02A/CORE`, `EA-02B/PLOTTER-MODEL` |
| REPLAY | passed | `EA-05B/REPLAY` |
| DEVICE-OWNERS | passed | `EA-05A/RECORDING`, `FIX-02/LINK-OBS`, `FIX-02/LINK-SAFETY` |
| ENVIRONMENT-GRAMMAR | pending | `EA-07/SIM`, `EA-09/UI` |
| SAME-SLICE-DELETION | pending | `EA-04/DELETE`, `EA-06/DELETE`, `EA-07/DELETE`, `EA-08A/DELETE`, `EA-08B/DELETE`, `EA-09/DELETE`, `FIX-03/DELETE`, `EA-10A/DELETE`, `EA-10B/DELETE`, `EA-10C/DELETE`, `EA-10D/DELETE`, `EA-10E/DELETE`, `EA-10F/DELETE`, `EA-10G/DELETE`, `EA-11A/DELETE`, `EA-11B/DELETE`, `EA-11C/DELETE` |
| AUTHORITY-REDUCTION | pending | `EA-01/INVENTORY`, `METRICS/AUTHORITY-REDUCTION` |
| OBSERVABILITY | pending | `EA-05C/INCIDENT`, `EA-06/MOTION`, `EA-09/UI` |
| WORKSPACE-REDUCTION | pending | `METRICS/WORKSPACE-REDUCTION` |
| SAFETY-EVIDENCE | pending | `FIX-02/LINK-SAFETY`, `EA-07/SIM`, `EA-09/UI` |

The sole next ordinary package is pending software package `FIX-05`; `GATE-01`
now depends on it and remains pending. The historical `TASK-2F141403` FIX-04
diagnostic described a then-removed package and is not a current replay or
completion claim. After terminal cleanup, `TASK-D2DFC053` remains visible as
`GATE-01` terminal history with disposition `dependency-ineligible-package`
while FIX-05 is pending. No physical, hardware, remote-Git, or continuation
decision occurred.

## EA-11C final-composition staged completion transaction

Prepared 2026-08-31 inside the existing sole-owner
`TRANCHE-FINAL-COMPOSITION` task/worktree. The current source contains the
candidate topology: one `PlotterApplicationRuntime`, nested
`PlotterApplicationState.environmentStates` source-indexed by
`OperatorFrameMode`, direct `PlotterApp -> EpisodeRuntime` dependency, one
projection-bound public `PlotterUIIntentSink` conformance, and one
`PlotterApplicationResidualOperationAdapter` backed directly by package
`PlotterOperationRegistry`. The adapter owns only residual root operations;
the point-selection, manual-motion, Pen Interaction, Boundary, calibration,
Drawing, controller-session, observation, speech, and artifact runtimes retain
their distinct typed rules, tasks, registries where applicable, and Stop lanes.

The root uses nominal `PlotterApplicationResidualEffectPort` methods for serial
discovery, monotonic time, and telemetry, plus nominal
`PlotterApplicationStatePersistencePort` methods for accepted-checkpoint and
paper-revision persistence. The obsolete `WorkflowTelemetryActions` and
`AcceptedLearningPathCheckpointActions` closure façades are absent. The public
sink validates exact immutable projection membership and revisions, then
delegates to the typed feature owner; the root does not add a redundant
`PlotterIntentGateway` reevaluator.

The sole bounded tranche critic found one red-line family: root shutdown could
return after cancelling and discarding artifact/reset and tip-calibration task
handles while cancellation-insensitive lower work still settled. The bounded
repair closes admission, cancels, retains, and joins the exact active operation
before root persistence or AppKit termination. No critic recheck was performed
or is allowed. `PlotterArtifactResetEpisodeTests` passed 12/12, including a
suspended durable-persistence join proof; `PlotterTipCalibrationEpisodeTests`
passed 7/7, including a suspended lower-effect join proof;
`PlotterEpisodeCompositionTests` passed 5/5; and `ApplicationLifecycleTests`
passed 9/9. These focused receipts are software-only and do not prove physical
controller/camera/motion/pen/paper/click/ink behavior.

The current frozen identities are Sources
`cb2542b187fdab818346b9f04c6143c5009dabcb6caf12530ce30436061eb895`
and Tests
`776a77a369363f9d472bb37ea5f15feda8bf81b4c05840b3561030cdda9ae6e2`.
The direct feature/runtime identities are artifact reset
`bae21fabde8ed8b133612781436d210e67e956d0fa59f5d25875cf514a2d8fdd`,
tip calibration
`18ba1440b81503eb6981ad0ace7717ec149c8a4cd38a3bbef1023c45a2cf771c`,
application root
`80a37a6ce50ad26c059ced8ee971a61121936b725baf9f4400d4432adea2f377`,
artifact-reset tests
`11451c747a8a6c14ffa048b28ebbf8d9d02f49c0eb2d85e49ce5573785db7cab`,
tip-calibration tests
`676486ca501c037198a47aa9f586a0d9084eec2f84e53f00d1a1727dfe4b0048`,
and composition tests
`ea2bc92fd98b7430a0d43833499d767a0011cdc58972723817a17fe3a838e9ed`.

The staged completion is one common Blackdog task/worktree/landing:
`TASK-FFD5D897`, attempt `TASK-FFD5D897-06c5758ade77`, targeting `main`, for
`TRANCHE-FINAL-COMPOSITION` and `EA-11C`. It becomes canonical only upon
successful Blackdog landing of this exact candidate; no landed commit hash is
asserted before that transaction completes.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; documentation and architecture contracts plus 35/35 in 18.569 seconds | frozen source/test candidate before the final receipt-only sync |
| `DIFF` | passed — `git diff --check`; clean | staged worktree diff |
| `QUICK` | passed — `make quick-test`; build 0.53 seconds and 820/820 in 15.286 seconds with 10 configured exclusions | frozen Sources/Tests identities |
| `JOURNEY` | passed — `make journey-test`; build 0.25 seconds and 10/10 in 5.127 seconds | frozen Sources/Tests identities |
| `STRICT` | passed — `make strict-check`; strict build 37.01 seconds, strict test build 46.06 seconds, 830/830 in 15.992 seconds, docs 35/35 in 18.402 seconds, signing/launcher/negative-bundle passed, no warnings or errors | frozen Sources/Tests identities |
| `CRITIC` | passed — sole bounded critic returned one shutdown-lifetime red-line family; repaired with affected proof and no critic recheck | tranche boundary |
| `BUILD` | passed — `swift build`; 0.48 seconds after the focused repair build | final EA-11C overlay |
| `COMPOSITION` | passed — `swift test --filter PlotterEpisodeCompositionTests`; 5/5 | production-root composition and shutdown contract |
| `AFFECTED-CONSUMERS` | passed — `sh Scripts/check_episode_cutover.sh EA-11C --consumer-only`; 4 exact scans | direct public/root consumers |
| `DELETE` | passed — `sh Scripts/check_episode_cutover.sh EA-11C`; 9 exact zero-match scans | superseded root types, ports, ingress, task, fixture, and mode branch |

The source-derived `TASK-METRIC` also passed: direct `OperatorWorkspace` task
owners decreased from EA-01 9 and FIX-03 9 to current 0, with no added owner.
This is staged semantic completion, not a pre-land Git claim. GATE-01 was not
run in this task and may proceed only after the successful Blackdog landing.
No attended physical or remote-Git evidence occurred or is claimed.

## Sprint tranche-policy correction

Prepared 2026-08-31 in active Blackdog task `TASK-86758196` after EA-10B landed
on canonical `main` at `a388859`. This policy becomes canonical only with that
task's verified landing. The historical EA-10B candidate record below is retained
as evidence history; it is not a live successor blocker in this candidate. The
Learning tranche `TRANCHE-LEARNING` landed as one Blackdog task/worktree and
one landing containing the ordered typed authority slices `EA-10G`, `EA-10C`,
`EA-10D`, `EA-10E`, and `EA-10F`: task `TASK-5C0B3F27`, attempt
`TASK-5C0B3F27-77bbbc6c5a59`, implementation commit
`2d488025a6b8a5fa129023a1a61e98b817106990`, and canonical main target/landing
`a1cfb05ca58f6805a973748958915fdbdd0ec117`. Its successor tranches are
`TRANCHE-DEVICE-ENVIRONMENT` (`EA-11A`, then `EA-11B`) and
`TRANCHE-FINAL-COMPOSITION` (`EA-11C`). The Device tranche landed on canonical
`main` at `3308e1bf2c19159be7b207226280f54b5ebf0662`; the current sole-owner
task is therefore executing `TRANCHE-FINAL-COMPOSITION` / `EA-11C` from that
base.
The canonical contract and capsule reject a completed tranche or
successor selection unless the tranche row and every slice completion row share
one nonempty Blackdog task/landing. Capsule prompt material carries each slice's
current-owner inventory row and exact same-slice deletion scans, so a tranche
cannot be treated as one broad authority cutover.

Every slice still requires build, its exact focused suite, affected-consumer
scan, `DIFF`, and `DELETE` before the next slice. Only a tranche boundary runs
`QUICK`, `JOURNEY`, `STRICT`, batched documentation/evidence synchronization,
and at most one bounded critic with no critic recheck. Non-red-line observations are recorded here as
deferred follow-up without retask. Red-line blockers remain compiler/test
failure, duplicate effect-producing authority, unauthorized motion, a
Stop/shutdown race that can start effects, automatic retry/redraw with possible
ink, destructive persistence ordering, or fabricated evidence. A red-line final-gate
defect may receive one narrow repair and affected validation but never criticism
again. This correction
does not authorize attended physical or remote-Git work, and `GATE-01` remains
unchanged downstream after `TRANCHE-FINAL-COMPOSITION`.

## TRANCHE-DEVICE-ENVIRONMENT staged completion transaction — landed

Blackdog task `TASK-4C16F56F`, attempt
`TASK-4C16F56F-8af99cc51c68`, landed `TRANCHE-DEVICE-ENVIRONMENT`, `EA-11A`,
and `EA-11B` as one task/worktree/landing transaction on canonical `main` at
`3308e1bf2c19159be7b207226280f54b5ebf0662`. Its frozen post-QUICK-repair tree
is
Sources `06a072ec2730f81f6edf2188ce38f75887e318a054a54e8d9888688085fee042`
and Tests
`7314c9bfd15ead6298aeb074bac6f9770b1a3e30106bd8bff73891f9929cb2cb`.

| Order | Slice | Frozen identities | Current typed authority and lower path | Required zero-match deletion proof | Accepted slice evidence |
| --- | --- | --- | --- | --- | --- |
| 1 | `EA-11A` | Sources `fad8bc86f755020696b121c91b55c6848a65d5f48012ea9c5b4afea68255dd6b`; Tests `4fd6378386c707559741e18161478695b5491840f38ebc05cb315c5d14bd6f51` | `PlotterControllerSessionRuntime` admits identity-bound `PlotterControllerSessionIntent` requests through its sink and uses nominal `PlotterMachineSession`/`PersistentMachineSession`; `MachineController` and `RunInterpreter` retain lower safety/effect ownership. | `MachineActions`, `performControllerConnectionAction`, `machineActions.`, `pendingBoundaryStopCapabilities`, `MachineFixture` | `BUILD` 31.26s; `SESSION` 4/4; affected consumers 2 scans; clean `DIFF`; `DELETE` 5 zero-match scans. |
| 2 | `EA-11B` | Sources `06a072ec2730f81f6edf2188ce38f75887e318a054a54e8d9888688085fee042`; Tests `7314c9bfd15ead6298aeb074bac6f9770b1a3e30106bd8bff73891f9929cb2cb` | `PlotterObservationConfigurationRuntime` admits identity-bound `PlotterObservationOperatorIntent` submissions through nominal `PlotterObservationCameraSessionPort`/`CameraSourceSession`; `CameraCapture`, `VisionWorker`, `PlotterSceneAnalysisPipeline`, and exact-frame/evidence applicability retain their distinct lower ownership. | `CameraActions`, `setVisionAnalysisCadence`, `cameraActions.`, `visionUpdateTask`, `CameraFixture` | Earlier accepted receipt: `BUILD` 32.01s; `OBSERVATION-CONFIG` 4/4 in 0.021s after a 28.06s build; affected consumers 2 scans; clean `DIFF`; `DELETE` 5 zero-match scans. The post-QUICK repair evidence below supersedes current-tree claims. |

EA-11A's accepted controller runtime/test identities remained unchanged through
EA-11B. The first focused checker stops were real inventory drift: EA-11A still
required the deleted `MachineActions` closure facade; EA-11B still required the
deleted `CameraActions` facade and a retired frame-mode workspace guard. The
bounded reconciliation removed only those obsolete *current* declarations,
registered the actual typed runtimes/task owner, and retained every same-slice
deletion scan. The controller runtime now centralizes typed serial-selection,
connection, passive-probe, alarm-clear, and Motion-authorisation admission;
the observation runtime centralizes typed source/configuration ordering and
shutdown. The residual workspace source-change reason is only a copied-fact
pre-submission projection, not a competing authority.

The sole bounded critic returned `RETASK` with exactly three red-lines and no
deferrals: controller post-cancel effect start, observation post-close restart,
and fabricated nil-or-mismatched camera-start identity. There was no critic
recheck. The controller repair added effect-boundary cancellation/shutdown
checks before lower work can start; its runtime SHA-256 is
`299c018a39714ce0218631d8efa33ac4c5e339a8e0210a036168359ae02297ab` and its
focused-test SHA-256 is
`750228d965ff27855719d9c4af44d285c590aa4dfab8613ad5f4f11ea1ff8a6b`.
The observation repair closes admission before restart work and binds camera
start to the exact requested and settled lifecycle identity: a nil or
mismatched settled record becomes a typed failure and never `.started`. Its
runtime SHA-256 is
`99b5b4f6ab575c5bd42d9dc8c1d6542e3b99d8cb1a13c6d6681b73e78ff46e55`, its
focused-test SHA-256 is
`958728d2b8bd665626f5aacda075f3ca9af4b98d239c2d008a34c693435a0ece`, and
`CameraComposition` SHA-256 is
`01f571edec38868296e76b30209e0668b4bd177e1415fff709788d8042935542`.

Nonpass history remains material: the first affected build failed because the
controller repair supplied an untyped `nil`; after the minimal source correction
the build passed in 29.02 seconds. The first focused command then failed at
test compilation because the observation mismatch fixture used `String` rather
than `UUID`, so zero tests ran; the test-only correction retained the repaired
source build. Current affected validation is `BUILD` exit 0 in 29.02 seconds
with no warnings/errors; controller 5/5 (9.55-second build, 0.004-second
tests); observation 7/7 (0.25-second build, 0.403-second tests); EA-11A
consumers 2/delete 5; EA-11B consumers 2/delete 5; and clean `DIFF`.

The first boundary `DOC` passed 35/35 in 18.666 seconds (19.61 seconds wall)
and `DIFF` was clean in 0.03 seconds. `QUICK` then failed with exit 2 after 819
tests and 5 issues, with 10 exclusions: build 0.67 seconds, tests 16.367
seconds, 18.75 seconds wall. The surviving exact failures were two
`OperatorWorkspaceComputationDiagnostics` timeouts waiting for post-identification
analysis resubscription (lines 408 and 493) and one
`CameraCompositionVisionLifecycle` `stableCapTimedOut` at line 322. Two other
Camera-lifecycle issue records were truncated; this evidence does not invent
their detail.

The root cause was an incomplete observation cutover: it removed
`CameraSourceSession`'s sole automatic-pipeline frame-ingestion task, so runtime
forwarding missed standalone lower consumers and exact frames during exclusive
Vision leases; nonnil reconfiguration also retained a stale semantic
subscription. The repair restores `CameraSourceSession.automaticInspectionFrameTask`
as the single automatic-ingestion owner, keeps runtime frame-event and semantic
analysis-update observation distinct, and keeps pipeline newest-only
state/progress distinct. Repair SHA-256 values are observation runtime
`518f5aeb0c716e4c4b8f2f6898a615115e39706cb60b21c50e0e1cbf824c2a9b`,
`CameraComposition`
`12e610fbb9663233ca2f5d7075493d72ba0249b9f4d19082b94a2e4318fc9402`, and
observation tests
`d2fde392826a730d2b2ac21b915d0ad96684997d9637ad43ce574fd27c8bda3a`.

Targeted repair validation passed: `BUILD` 28.89 seconds;
`OBSERVATION-CONFIG` 8/8 (17.94-second build, 0.429-second tests);
computation diagnostics 9/9 (0.26-second build, 0.536-second tests); and
camera lifecycle 6/6 (0.27-second build, 0.039-second tests). The consumer
checker then truthfully stopped on missing
`CameraSourceSession.automaticInspectionFrameTask`; full `DELETE` and `DIFF`
have not yet been rerun.

The current identities were mechanically recomputed as SHA-256 over the sorted
per-file SHA-256 manifest of `*.swift` files under `Sources` and `Tests`
respectively: Sources
`06a072ec2730f81f6edf2188ce38f75887e318a054a54e8d9888688085fee042`; Tests
`7314c9bfd15ead6298aeb074bac6f9770b1a3e30106bd8bff73891f9929cb2cb`.
There is no automatic retry or redraw. LIVE, SIMULATED, replay, automated, and
attended physical evidence remain distinct; no hardware, attended physical, or
remote-Git evidence exists. The three original critic red-line repairs remain
the sole critic result and no critic recheck occurred. The final receipts below
supersede the earlier post-QUICK pending-gate state. The executable capsule
frontier is now `TRANCHE-FINAL-COMPOSITION` only after this staged Device-tranche
proof; that does not dispatch `EA-11C`. No successor dispatch is authorized
before the successful Blackdog landing condition is satisfied.

Routed-document review for this candidate: [README](../README.md),
[Product Contract](PRODUCT_CONTRACT.md),
[Learning Path Operating Protocol](DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md),
[Learning Path Button Transitions](LEARNING_PATH_BUTTON_TRANSITIONS.md),
[Episode Architecture Vocabulary](EPISODE_ARCHITECTURE_VOCABULARY.md),
[Document Routing](INDEX.md), and [Roadmap](ROADMAP.md) were reviewed and need
no change: none presents the deleted closure facades or stale workspace seams as
current authority. [Swift Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md)
is updated with the current typed topology. The execution plan retains current
inventory and exact deletion scans while staging the common completion
transaction described here.

## TRANCHE-DEVICE-ENVIRONMENT staged completion transaction

The landed completion is one common Blackdog task/worktree/landing:
`TASK-4C16F56F`, attempt `TASK-4C16F56F-8af99cc51c68`, target `main`, for the
tranche and both authority slices. Its canonical landed commit is
`3308e1bf2c19159be7b207226280f54b5ebf0662`.
The frozen aggregate remains Sources
`06a072ec2730f81f6edf2188ce38f75887e318a054a54e8d9888688085fee042` and
Tests `7314c9bfd15ead6298aeb074bac6f9770b1a3e30106bd8bff73891f9929cb2cb`.
Physical validation remains skipped.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; 35/35 in 19.061 seconds tests and 20.00 seconds wall | final staged Sources/Tests identity |
| `DIFF` | passed — `git diff --check`; clean in 0.03 seconds | final staged worktree diff receipt |
| `QUICK` | passed — `make quick-test`; 820/820 with 10 exclusions, 14.378-second tests and 15.90-second wall | final staged Sources/Tests identity |
| `JOURNEY` | passed — `make journey-test`; 5/5, 4.908-second tests and 6.05-second wall | final staged Sources/Tests identity |
| `STRICT` | passed — `make strict-check`; strict build 39.81 seconds, test build 46.97 seconds, 825/825 in 14.693 seconds, docs 35/35 in 18.098 seconds, 134.32 seconds wall; signing/launcher/negative-bundle passed; no warnings/errors/issues | final staged Sources/Tests identity |
| `CRITIC` | passed — sole bounded critic returned `RETASK` with three red-lines and no deferrals; all repaired without a critic recheck | passed-with-repairs tranche contract record |

## EA-11A staged authority-slice completion

EA-11A shares the exact staged Device-tranche landing transaction above. Its
final accepted overlay is runtime
`299c018a39714ce0218631d8efa33ac4c5e339a8e0210a036168359ae02297ab` and tests
`750228d965ff27855719d9c4af44d285c590aa4dfab8613ad5f4f11ea1ff8a6b`; those
repairs preserve controller post-cancel effect-boundary closure.

| Validation | Result | Scope |
| --- | --- | --- |
| `BUILD` | passed — `swift build`; 29.02 seconds, no warnings/errors | final EA-11A overlay |
| `SESSION` | passed — `swift test --filter PlotterControllerSessionEpisodeTests`; 5/5 | typed controller-session admission, cancellation, and shutdown |
| `AFFECTED-CONSUMERS` | passed — EA-11A consumer gate; 2 exact scans | typed controller sink and surviving lower routes |
| `DIFF` | passed — `git diff --check`; clean | final staged worktree diff receipt |
| `DELETE` | passed — EA-11A delete gate; 5 exact zero-match scans | retired controller closure facade, ingress, task, and fixture |

## EA-11B staged authority-slice completion

EA-11B shares the exact staged Device-tranche landing transaction above. Its
final accepted current tree is runtime
`518f5aeb0c716e4c4b8f2f6898a615115e39706cb60b21c50e0e1cbf824c2a9b`,
`CameraComposition`
`12e610fbb9663233ca2f5d7075493d72ba0249b9f4d19082b94a2e4318fc9402`, and tests
`d2fde392826a730d2b2ac21b915d0ad96684997d9637ad43ce574fd27c8bda3a`.
The final repair retains the lower automatic-ingestion task, current
post-identification diagnostics, and exact workflow lifecycle behavior.

| Validation | Result | Scope |
| --- | --- | --- |
| `BUILD` | passed — `swift build`; 28.89 seconds | final EA-11B current tree |
| `OBSERVATION-CONFIG` | passed — `swift test --filter PlotterObservationConfigurationEpisodeTests`; 8/8 | typed observation admission, source/configuration ordering, and shutdown |
| `AFFECTED-CONSUMERS` | passed — EA-11B consumer gate; 2 exact scans; computation diagnostics 9/9 and camera lifecycle 6/6 passed as affected support | typed observation route plus lower ingestion/lifecycle support |
| `DIFF` | passed — `git diff --check`; clean | final staged worktree diff receipt |
| `DELETE` | passed — EA-11B delete gate; 5 exact zero-match scans | retired camera closure facade, ingress, task, and fixture |

## TRANCHE-LEARNING landed-slice register

All slices below landed in exact execution order inside shared Blackdog task
`TASK-5C0B3F27`. The common landing proof is attempt
`TASK-5C0B3F27-77bbbc6c5a59`, implementation commit
`2d488025a6b8a5fa129023a1a61e98b817106990`, and canonical main target/landing
`a1cfb05ca58f6805a973748958915fdbdd0ec117`. The frozen Source/Test identities
and all five slice-required gates are recorded per row. No physical or
remote-Git evidence is claimed; the post-acceptance repair overlay below
records the current non-red-line deferral separately from these frozen slice
receipts.

| Order | Slice | Shared task | Accepted Sources | Accepted Tests | Required slice-gate evidence |
| --- | --- | --- | --- | --- | --- |
| 1 | `EA-10G` | `TASK-5C0B3F27` | `785c530da7b01836a677cb3b1944e00abc2d6b94f652291ed829986fa7907306` | `764d8572ea8600d8b64e5e3af9d1df30d4f28f82ae96a417cd9e2ab490fa1168` | `BUILD` 0.54s; `SPEECH` 2/2; consumers 2 scans; clean `DIFF`; `DELETE` 4 scans |
| 2 | `EA-10C` | `TASK-5C0B3F27` | `8088364f7129e2b3ef2007f02100c11776779dc57acd9877cdfcda532ee8a8ee` | `8cf81a27eff843ae21fcc382def63fdeaf02172efc37fd6b8b45e2200a92e2de` | `BUILD` 0.53s; `CAMERA-CAL` 2/2; consumers 1 scan; clean `DIFF`; `DELETE` 4 scans |
| 3 | `EA-10D` | `TASK-5C0B3F27` | `c0fdf0705df2e97715e7bbd0678fd6fefbae22c598bc76d8e1d035763f7783b6` | `92a88407783893ae61b16b313af839ea29e099df08733b2e12aa407ea9f0011d` | `BUILD` 29.78s; `TIP-CAL` 7/7; consumers 2 scans; clean `DIFF`; `DELETE` 4 scans |
| 4 | `EA-10E` | `TASK-5C0B3F27` | `768b26e96bdc357ad1a97ea3ae4e8f347e998e7ce77fb0d44daa4142b0157f86` | `40c5144691901b25386ea166954af5021c6303b651a6e78728af778b8a2b23ce` | `BUILD` 0.54s; `BORDER-VALIDATION` 5/5; consumers 1 scan; clean `DIFF`; `DELETE` 10 scans |
| 5 | `EA-10F` | `TASK-5C0B3F27` | `4a96fe8389cc5c8cc3091575c6e24c822650420cfb58f9c6f1777b4fb2860af8` | `a9ba97238089155cc5a33fb462db3f6c3d96b5bde03d1ff485c0ae1b6f56afab` | `BUILD` 0.54s; `ARTIFACT-RESET` 9/9; consumers 2 scans; clean `DIFF`; `DELETE` 7 scans |

## TRANCHE-LEARNING post-acceptance red-line repair — boundary pending

The first boundary `DOC` pass was 35/35 and its `DIFF` was clean. The first
`QUICK` then failed 4 tests with 6 issues at the 799-test tree. This was a
red-line repair, not a non-red-line deferred finding. The repair captured the
tip possible-ink fact before transient Stop-owner clear and retained the
runtime terminal blacklist; preserved Boundary’s specific
incomplete-publication explanation and pending authority across reset; and made
the Border runtime emit MainActor-authoritative transition snapshots, including
possible-ink/no-redraw terminal truth, without workspace authority.

Focused repair evidence passed: exact tip regression 1/1; relevant
Boundary capability/atomic regression 1/1; lost Border outcome 1/1; Border
preview/progress 1/1; `PlotterTipCalibrationEpisodeTests` 7/7;
`PlotterBorderValidationEpisodeTests` 5/5; and
`PlotterArtifactResetEpisodeTests` 9/9. One attempted stale Boundary filter
matched 0 and is not claimed as validation. The final `QUICK` passed 799/799
after a 0.53-second build and 13.337 seconds of tests.

The accepted-slice hashes above remain the frozen evidence for their acceptance
trees. The red-line overlay supersedes stale current-tree claims for affected
EA-10D/EA-10E/EA-10F and binds their delta evidence to final Sources
`6dc363241c4b9f747fb2a791d26533c4f511601d2d32f97314318e2b9458392c` and
Tests `a9ba97238089155cc5a33fb462db3f6c3d96b5bde03d1ff485c0ae1b6f56afab`:
0.52-second delta build; EA-10D consumers 2/delete 4; EA-10E consumers
1/delete 10; EA-10F consumers 2/delete 7; and clean `DIFF`.

This synchronization was docs-only and changed neither final Sources nor Tests,
so the green 799/799 `QUICK` remained valid for this overlay's tree. A later
source/test repair supersedes that identity; its current evidence is recorded
below. No physical or remote-Git evidence exists.

## TRANCHE-LEARNING post-JOURNEY red-line repair — boundary pending

The first `JOURNEY` failed 2 tests with 3 issues: SIM tip acceptance left a
proposal and no Drawing Border overlay, and a changed-coordinate restart lacked
the tip registration. The repair makes `PlotterTipCalibrationRuntime` own the
recoverable accepted-tip checkpoint. Commit and revalidation atomically install
the accepted registration and clear proposal, selection, and recoverable facts;
`OperatorWorkspace` no longer stores a duplicate checkpoint and only projects
typed facts plus lower persistence effects. The nominal SIM restart fixture now
installs the checkpoint after the typed camera prerequisite.

Each exact journey passed 1/1; `PlotterTipCalibrationEpisodeTests` passed 7/7;
legacy migration passed 5/5; sparse workspace coverage passed 8/8; and
`make journey-test` exited 0 with current discovery 5/5. Its Make filter lists
ten names, but only five were discovered and executed, so no 10/10 claim is
made. SIM proof recorded one LIVE-store load with zero saves and zero clears,
nil proposal, accepted/Drawing Border overlays, zero-ink revalidation, and a
new revision restored from the checkpoint. EA-10D consumers 2/delete 4 and
EA-10F consumers 2/delete 7 passed; `DIFF` was clean.

The final repaired tree is Sources
`63ff15afa9716404367d8dbaf3cbdc111cb92e346cf816063ece2e7846f0fbd6` and
Tests `1cc69013a0ed30b74a19ca21daa0a6cf408945e73fadf17e9c37563624731b9e`.
The preceding 799/799 `QUICK` belongs only to the earlier aggregate and is
therefore stale. This `JOURNEY` receipt belonged to this then-final identity;
a later source/test repair supersedes it as well. Current boundary evidence is
recorded below. No physical or remote-Git evidence exists.

## TRANCHE-LEARNING post-critic red-line repair — boundary passed, landing pending

The tranche's one bounded fresh-context critic returned four P1 red-lines:
camera semantic authority could publish false terminal truth; Border review had
to require explicit accept/reject; paper persistence had to commit before the
in-memory projection; and legacy cleanup had to remain reversibly staged. Each
was repaired. There was no critic recheck, in accordance with the tranche rule.

The repaired tree leaves `PlotterCameraCalibrationRuntime` as the semantic and
terminal authority; `PlotterBorderValidationRuntime` as the explicit-review and
accept/reject authority behind the typed
`ExerciseActionKind.borderValidation(PlotterBorderValidationIntent)` adapter;
and `PlotterArtifactResetRuntime` as the persist-before-memory transaction
owner. `AcceptedLearningPathLegacyMigrationAdapter` saves canonical state before
reversible legacy cleanup and retains the legacy bytes on failure. The current
inventory records the typed Border action as a live adapter and the runtime as
the sole semantic owner.

Focused receipts after those repairs are: Border 6/6, projector 19/19,
presentation 16/16, UI 18/18, lifecycle 6/6, sparse-tip 8/8, reset 13/13,
legacy migration 6/6, camera 3/3 plus action 21/21, and artifact reset 11/11
plus injected-paper-failure 1/1. The accepted-slice receipts above remain
historical evidence for their frozen trees.

The current identities were mechanically recomputed as SHA-256 over the sorted
per-file SHA-256 manifest for Swift files: Sources
`18ae4d43717629a3944ced33a6bab7b21f0fdabdcb45baee5704a34e94ebf796` and
Tests `586d3de73b048efab7555332dbc17077c5e9fc3d4e1920084d5c6e0391bbacca`.
The earlier `QUICK` and `JOURNEY` receipts are stale for these identities. The
final frozen-tree receipts are:

| Gate | Result | Frozen-tree scope |
| --- | --- | --- |
| `QUICK` | passed — `make quick-test`; exit 0; 807/807; build 2.63 seconds; tests 14.090 seconds; 0 warnings/errors | final Sources/Tests identities above; log `/tmp/adaptiveplotter-learning-gates.sMErfC/quick.log`, SHA-256 prefix `10504c9e…ba75` |
| `JOURNEY` | passed — `make journey-test`; exit 0; current discovery 5/5 in 5.273 seconds; 0 warnings/errors | final Sources/Tests identities above; canonical filter lists ten names but only five currently exist/discover, so no 10/10 claim; log `/tmp/adaptiveplotter-learning-gates.sMErfC/journey.log`, SHA-256 prefix `5e115d21…3feb` |
| `STRICT` | passed — `make strict-check`; exit 0; strict build 48.90 seconds; full strict build 48.49 seconds; 812/812 in 14.873 seconds; docs/checker 35/35 in 21.517 seconds; signing, launcher, and negative-bundle green; clean `DIFF`; 0 warnings/errors | final Sources/Tests identities above; log `/tmp/adaptiveplotter-learning-gates.sMErfC/strict.log`, SHA-256 prefix `bb8de8aa…b2d8` |

These receipts used the pre-evidence-sync ledger
`4584074782e52b30b5fccfbdfda8525eae5f80fd8ea0d738f5e28b2c5e3009ae` and
supersede the stale prior `QUICK`/`JOURNEY` claims. The one critic has already
occurred; no critic recheck occurred. The docs-only evidence delta changed no
Source/Test identity and reran only `DOC` and `DIFF`. The common landing proof
is task `TASK-5C0B3F27`, attempt `TASK-5C0B3F27-77bbbc6c5a59`, implementation
commit `2d488025a6b8a5fa129023a1a61e98b817106990`, and canonical main
target/landing `a1cfb05ca58f6805a973748958915fdbdd0ec117`.

The non-red-line deferred item is
`PlotterBorderValidationIntent.retryFrom`: the intent and runtime handling
exist, but no production caller constructs it. No stale tip comment was found
in the current Sources. Attended physical validation was not performed; no
physical or remote-Git evidence is claimed.

## TRANCHE-LEARNING landed tranche evidence

The ordered tranche landed in Blackdog task `TASK-5C0B3F27`, attempt
`TASK-5C0B3F27-77bbbc6c5a59`, from implementation commit
`2d488025a6b8a5fa129023a1a61e98b817106990` onto canonical main target/landing
`a1cfb05ca58f6805a973748958915fdbdd0ec117`. Physical validation remains
skipped.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — final canonical docs/checker receipt 35/35 | frozen final Sources/Tests identity |
| `DIFF` | passed — clean | final landing worktree diff check |
| `QUICK` | passed — `make quick-test`; 807/807, 2.63-second build, 14.090-second tests, 0 warnings/errors | frozen final Sources/Tests identity |
| `JOURNEY` | passed — `make journey-test`; current discovery 5/5 in 5.273 seconds, 0 warnings/errors; the canonical filter lists ten names while five currently exist/discover | frozen final Sources/Tests identity |
| `STRICT` | passed — `make strict-check`; strict build 48.90 seconds, full strict build 48.49 seconds, 812/812 in 14.873 seconds, docs/checker 35/35 in 21.517 seconds, signing/launcher/negative-bundle green, 0 warnings/errors | frozen final Sources/Tests identity |
| `CRITIC` | passed — one bounded critic returned four P1 red-lines; all four were repaired without a critic recheck | final critic/red-line repair record |

## EA-10G landed authority-slice evidence

EA-10G landed as the first authority slice in `TRANCHE-LEARNING`. Its common
landing proof is Blackdog task `TASK-5C0B3F27`, attempt
`TASK-5C0B3F27-77bbbc6c5a59`, implementation commit
`2d488025a6b8a5fa129023a1a61e98b817106990`, and canonical main target/landing
`a1cfb05ca58f6805a973748958915fdbdd0ec117`. The accepted Sources aggregate is
`785c530da7b01836a677cb3b1944e00abc2d6b94f652291ed829986fa7907306`; the
accepted Tests aggregate is
`764d8572ea8600d8b64e5e3af9d1df30d4f28f82ae96a417cd9e2ab490fa1168`.

The landed tree routes advisory speech through one typed
`PlotterSpeechEffectRuntime`. The runtime owns application-level admission,
identity-bound active and bounded terminal request tracking, completed/failed/
timed-out/cancelled outcomes, advisory-only outcome handling, and its shutdown
latch. `NativeSpeechAnnouncer` remains the lower AVFoundation synthesis,
identity-queue, and per-utterance-timeout owner. The runtime is shared by the
workspace route and the Boundary composition route; it does not grant physical
permission or establish attended-controller, camera, motion, Pen, paper,
operator-click, or observed-ink evidence.

The landed tree deletes `AnnouncementActions`,
`OperatorWorkspace.announceAdvisory`, `announcementActions?.announce`, and
`AnnouncementFixture`. The canonical EA-01 inventory now names the replacement
runtime, lower native owner, actual lower timeout owner, focused test doubles,
and the two remaining Boundary workspace seams; the four retired names remain
EA-10G zero-match declarations rather than live-source obligations.

| Validation | Result | Scope |
| --- | --- | --- |
| `BUILD` | passed — `swift build`; final 0.54 seconds | landed EA-10G replacement tree |
| `SPEECH` | passed — `swift test --filter PlotterSpeechEffectEpisodeTests`; 2/2 | typed speech-effect terminal and shutdown behavior |
| `AFFECTED-CONSUMERS` | passed — `sh Scripts/check_episode_cutover.sh EA-10G --consumer-only`; 2 exact scans | surviving consumer routes and duplicate ingress |
| `DIFF` | passed — `git diff --check`; clean | landed-tree whitespace/error check |
| `DELETE` | passed — `sh Scripts/check_episode_cutover.sh EA-10G`; 4 exact zero-match scans | retired announcement symbols, direct ingress, and fixture |

No non-red-line finding was recorded. No physical or remote-Git validation
occurred or is claimed.

## EA-10C landed authority-slice evidence

EA-10C landed as the second authority slice in `TRANCHE-LEARNING`. Its common
landing proof is Blackdog task `TASK-5C0B3F27`, attempt
`TASK-5C0B3F27-77bbbc6c5a59`, implementation commit
`2d488025a6b8a5fa129023a1a61e98b817106990`, and canonical main target/landing
`a1cfb05ca58f6805a973748958915fdbdd0ec117`. The accepted Sources aggregate is
`8088364f7129e2b3ef2007f02100c11776779dc57acd9877cdfcda532ee8a8ee`; the
accepted Tests aggregate is
`8cf81a27eff843ae21fcc382def63fdeaf02172efc37fd6b8b45e2200a92e2de`.

The EA-10C red-line semantic repair eliminated the parallel workspace mirror:
`ExerciseActionKind.cameraCalibration(PlotterCameraCalibrationIntent)` routes
to one typed `PlotterCameraCalibrationRuntime`, which owns phase, failure,
reference/correspondence evidence, staged proposal, accepted registration,
active task, bounded terminal history, and shutdown admission.
`OperatorWorkspace` derives/proxies runtime state and supplies only lower
effects plus atomic application. The former explicit run/proposal-accept/
proposal-reject action cases and former workspace task remain exact EA-10C
zero-match deletion authority.

| Validation | Result | Scope |
| --- | --- | --- |
| `BUILD` | passed — `swift build`; final 0.53 seconds | landed EA-10C replacement tree |
| `CAMERA-CAL` | passed — `swift test --filter PlotterCameraCalibrationEpisodeTests`; 2/2 | typed calibration terminal and shutdown behavior |
| `AFFECTED-CONSUMERS` | passed — consumer-only gate; 1 exact scan | surviving typed camera-calibration route |
| `DIFF` | passed — `git diff --check`; clean | landed-tree whitespace/error check |
| `DELETE` | passed — 4 exact zero-match scans | `currentCameraCalibrationPhase`, `runCameraCalibrationAndBuildProposal`, `currentCameraCalibrationTask`, and `stageMachineCameraRegistrationProposal` |

No automatic retry/redraw, deferred finding, physical, or remote-Git evidence
occurred or is claimed.

## EA-10D landed authority-slice evidence

EA-10D landed as the third authority slice in `TRANCHE-LEARNING`. Its common
landing proof is Blackdog task `TASK-5C0B3F27`, attempt
`TASK-5C0B3F27-77bbbc6c5a59`, implementation commit
`2d488025a6b8a5fa129023a1a61e98b817106990`, and canonical main target/landing
`a1cfb05ca58f6805a973748958915fdbdd0ec117`. The accepted Sources aggregate is
`c0fdf0705df2e97715e7bbd0678fd6fefbae22c598bc76d8e1d035763f7783b6`; the
accepted Tests aggregate is
`92a88407783893ae61b16b313af839ea29e099df08733b2e12aa407ea9f0011d`.

The landed tree routes `ExerciseActionKind.tipCalibration` to one typed
`PlotterTipCalibrationRuntime` through its effect-port `execute(_:)` shape. The
runtime owns workflow/task/phase/proposal/commit/revalidate/reject/retry,
terminal-history, and possible-ink blacklist semantics.
`PlotterPointSelectionRuntime` remains the sole click add/undo/clear/four-point
batch owner. `OperatorWorkspace` supplies only lower effects/projection.

`SparseTipCalibrationCoordinator.swift` and its direct test are deleted. The
former `SparseTipCalibrationCoordinator`, `drawFourCornerTipCircles`,
`undoLastSparseTipClick`, and `completeSimulatedSparseTipCalibration` names
remain exact EA-10D zero-match deletion authority.

| Validation | Result | Scope |
| --- | --- | --- |
| `BUILD` | passed — `swift build`; final 29.78 seconds | landed EA-10D replacement tree |
| `TIP-CAL` | passed — `swift test --filter PlotterTipCalibrationEpisodeTests`; 7/7 | typed calibration workflow, terminal, and possible-ink behavior |
| `AFFECTED-CONSUMERS` | passed — consumer-only gate; 2 exact scans | surviving typed tip-calibration and point-correction routes |
| `DIFF` | passed — `git diff --check`; clean | landed-tree whitespace/error check |
| `DELETE` | passed — 4 exact zero-match scans | `SparseTipCalibrationCoordinator`, `drawFourCornerTipCircles`, `undoLastSparseTipClick`, and `completeSimulatedSparseTipCalibration` |

No automatic redraw/retry, deferred semantic finding, physical, or remote-Git
evidence occurred or is claimed.

## EA-10E landed authority-slice evidence

EA-10E landed as the fourth authority slice in `TRANCHE-LEARNING`. Its common
landing proof is Blackdog task `TASK-5C0B3F27`, attempt
`TASK-5C0B3F27-77bbbc6c5a59`, implementation commit
`2d488025a6b8a5fa129023a1a61e98b817106990`, and canonical main target/landing
`a1cfb05ca58f6805a973748958915fdbdd0ec117`. The accepted Sources aggregate is
`768b26e96bdc357ad1a97ea3ae4e8f347e998e7ce77fb0d44daa4142b0157f86`; the
accepted Tests aggregate is
`40c5144691901b25386ea166954af5021c6303b651a6e78728af778b8a2b23ce`.

The landed tree routes canonical `PlotterBorderValidationIntent` actions
through one typed `PlotterBorderValidationRuntime`. The runtime is the sole
workflow/task/phase/terminal/possible-ink/review/shutdown owner.
`OperatorWorkspace` supplies only lower effects/projection; Draft and Run
runtimes remain distinct, and the EA-10D tip dependency is preserved.

No decode adapter or old active label is retained. All ten old-name scans remain
EA-10E zero-match deletion authority only.

| Validation | Result | Scope |
| --- | --- | --- |
| `BUILD` | passed — `swift build`; final 0.54 seconds | landed EA-10E replacement tree |
| `BORDER-VALIDATION` | passed — `swift test --filter PlotterBorderValidationEpisodeTests`; 5/5 | typed Border workflow, terminal, possible-ink, review, and shutdown behavior |
| `AFFECTED-CONSUMERS` | passed — consumer-only gate; 1 exact scan | surviving typed Border route |
| `DIFF` | passed — `git diff --check`; clean | landed-tree whitespace/error check |
| `DELETE` | passed — 10 exact zero-match scans | old Border state/item/ingress/task/fixture/label targets |

No automatic redraw/retry, deferred semantic finding, physical, or remote-Git
evidence occurred or is claimed.

## EA-10F landed authority-slice evidence

EA-10F landed as the fifth authority slice in `TRANCHE-LEARNING`. Its common
landing proof is Blackdog task `TASK-5C0B3F27`, attempt
`TASK-5C0B3F27-77bbbc6c5a59`, implementation commit
`2d488025a6b8a5fa129023a1a61e98b817106990`, and canonical main target/landing
`a1cfb05ca58f6805a973748958915fdbdd0ec117`. The accepted Sources aggregate is
`4a96fe8389cc5c8cc3091575c6e24c822650420cfb58f9c6f1777b4fb2860af8`; the
accepted Tests aggregate is
`a9ba97238089155cc5a33fb462db3f6c3d96b5bde03d1ff485c0ae1b6f56afab`.

`AdaptivePlotterApplicationDelegate` composes `PlotterArtifactResetRuntime`,
injects it into `OperatorWorkspace`, and installs a weak lower
effect/persistence relay. The runtime owns explicit Saved Learning comparison,
apply, retain, reject, redo, additional-attempt, paper-replacement, and reset
intents; admission, one active task, state, bounded terminal history, shutdown,
possible-ink/Stop blocking, and durable-before-projection ordering.
`OperatorWorkspace` routes typed actions, projects runtime facts, and performs
only lower effects and atomic persistence/application. The one-shot
`AcceptedLearningPathLegacyMigrationAdapter` canonical-short-circuits, rejects
corrupt/unsupported legacy bytes explicitly, saves canonical state before
reversible cleanup, and preserves legacy bytes on failure. The two former
legacy stores and their direct tests are deleted; all five former EA-10F
workspace/fixture symbols plus both legacy stores are exact zero-match targets.
This reset repair makes persistence happen before projection and retains the
legacy-byte-preservation migration proof.

| Validation | Result | Scope |
| --- | --- | --- |
| `BUILD` | passed — `swift build`; final 0.54 seconds | landed EA-10F production tree |
| `ARTIFACT-RESET` | passed — `swift test --filter PlotterArtifactResetEpisodeTests`; 9/9 | typed lifecycle, admission, persistence ordering, terminal, and shutdown behavior |
| `AFFECTED-CONSUMERS` | passed — consumer-only gate; 2 exact scans | surviving typed reset routes and lower relay composition |
| `DIFF` | passed — `git diff --check`; clean | landed-tree whitespace/error check |
| `DELETE` | passed — 7 exact zero-match scans | five retired workspace/fixture targets plus both legacy stores |

Focused support evidence also passed: `AcceptedLearningPathLegacyMigrationTests`
5/5; application lifecycle injection/shutdown 1/1; full reset 12/12; the seven
formerly failing reset cases 7/7; and the former Boundary-settlement hang 1/1.
No automatic retry/redraw, deferred semantic finding, physical, or remote-Git
evidence occurred or is claimed.

## Capsule claim-classification correction

Delivered 2026-08-31 in repository task `TASK-A7C0E999`. `DOC-04` adds no
product authority and does not mutate, reopen, cancel, or hide historical
Blackdog tasks. The capsule now blocks on every active attempt, task/workset
claim, retained owner/worktree/branch, required owner finalization, unknown or
unverifiable replay identity, and replay-bound current dependency-ready
recoverable ordinary package. It separately emits hash-bound
`terminal_history` diagnostics for terminal blocked/failed attempts only when
cleanup is complete and their exact replay binds either a removed package or a
currently dependency-ineligible package.

The current diagnostics are `TASK-2F141403` → `FIX-04` →
`removed-package`, and `TASK-D2DFC053` → `GATE-01` →
`dependency-ineligible-package`. They remain visible; they are not claims,
retries, cancellation decisions, or evidence that either historical package
passed. `GATE-01` remains unchanged downstream after
`TRANCHE-FINAL-COMPOSITION`. The Device tranche is staged complete, so the
executable ordinary frontier is `TRANCHE-FINAL-COMPOSITION` only upon
successful Blackdog landing of the exact Device transaction; this evidence
update does not select or claim that successor.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; documentation and architecture contracts passed, capsule tests 35/35 | canonical ledger, evidence, claim classifier, and coordination references |
| `DIFF` | passed — `git diff --check`; exit 0, no output | repository-only correction |

## Drawing Boundary episode cutover completion candidate

Selected 2026-08-30 as software package `EA-10B` in task `TASK-6DAB256F`.
EA-10B is semantically complete as a task-local landing candidate. Blackdog
landing and canonical-main cleanup remain pending, so this is not operational
landing. The frozen production Sources aggregate is
`9abeef29df0364b87029bbcd621a82a4c433588a4de56a54aeaed8c5f400a5c8`;
the frozen Swift Tests aggregate is
`8998beb7745c07c5a261757a0fdb2c572e3f63a715b536854375a6804489c48e`.

One actor-isolated `PlotterBoundaryRuntime` now owns source-indexed LIVE and
SIMULATED Boundary revisions; request, attempt, operation, cancellation, and
publication-recovery identities; direction selection; normal, replacement, and
additional side acquisition; center move/retry; exact Stop/cancel/shutdown;
immutable accepted aggregates, estimated center, center arrival, refusals,
terminal truth, and staged publication state. Every
`PlotterBoundarySubmission` binds the displayed
`PlotterBoundaryProjectionReference` and one typed `PlotterBoundaryIntent`.
Stale projection or effect facts, foreign capability, active ownership, invalid
direction, incomplete accepted prerequisites, or closed admission refuses with
an exact owner and remedy before lower work.

Admission synchronously installs the runtime operation, cancellation capability,
runtime-owned task, and one-shot reservation-publication latch before the first
await. The task cannot enter the package admission gate, acquire facts, or
prepare lower work until the genuinely async `PlotterBoundaryProjectionSink`
returns from publishing `.reserving`; only then does the runtime release its
latch. A fact or admission refusal settles that same minted owner into one
terminal refusal and invokes zero lower effect.
The runtime owns its one environment-local
lower execution/settlement/publication task lane; `OperatorWorkspace` owns no Boundary task, busy latch,
Stop decision, retry, or settlement helper. Exact Stop, cancel, and shutdown
converge on the matching owner. Retained Pen-Up supervision completes before
both side acquisition and center travel in LIVE and SIMULATED. Natural
completion, lower refusal, limit, mismatched Stop, cancellation, shutdown,
ambiguity, or save failure never replaces previously accepted Boundary
authority. The runtime revalidates effect facts before lower execution. LIVE
acceptance still requires fresh retained-controller Idle/final MPos truth.

Accepted LIVE Boundary and center candidates are saved before publication. A
failed save exposes the exact identity-bound recovery capability and retains the
staged candidate; recovery retries publication only and never resends Pen or
motion. A runtime-owned weak `PlotterBoundaryProjectionSink` publishes immutable
admitted, moving, cancelling, recovery, and terminal snapshots without a
workspace observer Task/latch/retry. While publication is incomplete, canonical
actionability exposes only exact `.recoverPublication(capability)` and suppresses
new acquisition and center travel. Learning vacate/reset settles an active
Boundary through its exact capability and blocks pending publication. It then
reserves a non-destructive exact reset capability, which closes new Boundary
admission without clearing projection, aggregates, graph/checkpoint, session, or
recovery truth. The workspace persists the Learning prefix before exact commit;
only an applied commit permits local cleanup. Persistence refusal exact-aborts
the reservation and retains all prior authority unchanged; stale or foreign
commit/abort capabilities refuse. `PlotterBoundaryAdmissionGate` and
`PlotterBoundaryTerminalPublicationGate` hold only the post-reservation/pre-fact
and post-lower/pre-publication scheduling boundaries for deterministic tests;
they grant no admission, effect, cancellation, settlement, persistence, result,
or publication choice and use no sleep, polling, or `Task.yield`.

`PlotterBoundaryComposition` retains lower authority instead of duplicating it.
LIVE uses the nominal `PlotterMachineSession`/`RunInterpreter` fixed 50 mm renewal,
controller Stop, and supervised center travel/Pen seams. SIMULATED uses the sole
EA-07 `PlotterCausalSimulatorEffectAdapter`, invokes zero LIVE effect or
persistence, and remains explicitly nonphysical. Camera, Vision, controller
transport/safety, checkpoint encoding, replay, incident assembly, camera
calibration, sparse-tip calibration, Drawing Border, Saved Learning, and later
package semantics did not move. The retained
`AcceptedMachineArtifactCheckpoint.boundarySideAggregates` is lower durable
checkpoint data, not workspace Boundary authority.

After the same critic accepted correction cycle 2, the final `QUICK` attempt
was nonpass and exited 130. The user authorized one exceptional same-critic
final-gate repair. The runtime now derives a first center move as `retry: false`
and derives retry only from retained failed, stopped, or ambiguous
center-arrival terminal truth while center authority remains and arrival is
absent. Accepted-side installation preserves the selected direction while it
remains allowed and otherwise advances deterministically to the first remaining
allowed direction. LIVE side admission awaits the retained Discovery advisory
through the composition-only `UI.announceBoundaryAdvisory` adapter and existing
`AnnouncementActions` owner before lower Boundary motion. The adapter owns no
announcement, effect, Stop, settlement, evidence, controller, or UI authority;
advisory failure remains non-gating and SIMULATED behavior is unchanged.

The retained operator-path tests migrated obsolete generic `.start` and
contextual Stop requests to exact typed direction selection, acquire, and
capability-bound Boundary Stop.

The same critic then returned `RETASK` for exactly three closure findings:
the runtime derived but did not enforce the submitted center-retry bit, Stop or
shutdown could race lower motion admission while retained speech was suspended,
and generic Boundary fixture ingress remained. The closure adds typed
`.centerRetryMismatch(expected:submitted:)` and
`.centerArrivalAlreadyAccepted` refusals with zero lower effect. The runtime,
not the lower side port, now owns the pre-admission advisory step; after that
await it rechecks exact cancellation/shutdown and reacquires the full external
effect identity immediately before LIVE motion admission. Shutdown closes
Boundary admission without joining, cancels retained speech, and then joins the
exact Boundary owner. Stop or shutdown during suspended speech therefore
settles with zero lower motion admission. SIMULATED ordering and nonphysical
truth are unchanged.

All Boundary test fixtures now use exact rendered typed direction selection,
acquire, and capability-bound Boundary Stop; direct `submitBoundaryIntent`,
generic Boundary `.start`, and the old completion helpers have zero test-source
matches. The center waiter now tracks
`semanticPresentationRevision`, because Boundary snapshot storage is
observation-ignored while snapshot installation advances that canonical
observable revision. Accepted center arrival asserts the actual
controller-reported quantized position rather than fabricating the requested
target.

The downstream `QUICK` repair preserved that accepted Boundary authority while
closing the retained workflows that consume it. A recoverable failed center
terminal now renders exact typed `Retry Center Arrival` before generic
needs-attention, without automatic resend; its activity comes directly from the
exact center-arrival terminal rather than the legacy exploration-failure field.
`PlotterBoundaryRestoreError` supplies actionable localized descriptions,
including the finite residual and the current
`MachinePositionAcceptancePolicy` tolerance, and the accepted-authority staging
path publishes that typed description. Camera Calibration now acquires a fresh
settled machine observation and requires its exact MPos to match the accepted
Boundary center within the existing acceptance policy before installing the
reference. The deterministic SIMULATED sparse-tip fixture installs Boundary
truth that matches its accepted checkpoint, so exact-frame clicks are derived
from one geometry rather than a conflicting simulator default. Point-selection
waiters observe the canonical semantic revision and do not reinterpret repeated
refusal as publication.

The first remaining-gate pass recorded `BOUNDARY` 18/18, `DELETE` 8/8, `DOC`
29/29, clean `DIFF`, and `JOURNEY` 5/5. Its `STRICT` build then failed at two
sites because the MainActor projection sink was not Sendable. The bounded source
repair makes `PlotterBoundaryProjectionSink` Sendable and removes the redundant
relay's `@unchecked Sendable`; the strict production build then passed in 29.97
seconds and focused Boundary remained 18/18. The same critic accepted that
bounded delta.

The post-fix `QUICK` run deterministically failed at 772/773 in
`shutdownDoesNotReviveAcceptedClick`, and the exact isolated failure reproduced.
An asynchronous retained Pen admission could resume after shutdown and create a
zero-step `DiscoveryTransaction`. The retained Pen owner now checks shutdown at
entry and again after the suspension before creating that transaction. The exact
regression passed 1/1 and the full Pen-cap suite passed 17/17; the same critic
accepted this bounded delta as well. The final `QUICK` and `JOURNEY` receipts
below are on the current frozen source/test identities.

The same landing deletes the workspace Boundary state, history, evidence,
aggregates, center/frame/arrival/activity state, pending lower dictionaries,
`boundaryMotionTask`, `BoundaryAtomicCommitFailurePoint`,
`beginPairedBoundarySide`, direct `machineActions.beginBoundaryMotion`, obsolete
center/execution/commit helpers, generic Boundary Stop/reset/shutdown branches,
and five obsolete Boundary `ExerciseActionKind` cases. The high-level
`completeLiveBoundaries` and `completeSimulatedBoundariesAndCenter` fixtures are
deleted rather than recreated under another name. The final deletion gate passed
all eight exact EA-10B scans; the
`boundarySideAggregates` scan is intentionally scoped to
`OperatorWorkspace.swift` so it does not forbid the retained checkpoint field.

| Focused receipt | Result | Scope |
| --- | --- | --- |
| `BUILD` | passed — `swift build`; exit 0; 18.20 seconds | correction-cycle-2 production compile after the async sink witness change |
| `ASYNC-RESERVATION-PUBLICATION` | passed — focused async reservation-publication regression; 1/1 passed; tests 0.007 seconds | the operation task cannot reach facts, gates, or lower preparation until sink publication returns |
| `BOUNDARY` | passed — `swift test --filter PlotterBoundaryEpisodeTests`; exit 0; 18/18 passed; tests 0.125 seconds | exact center-retry enforcement, async reserving publication, two-phase reset, same-owner refusal, supervised center travel and advisory ordering, recovery, LIVE/SIM separation, and exact Stop/cancel/shutdown |
| `JOURNEY-BOUNDARY-REPEAT` | passed — `swift test --filter boundaryRepeatActionsAggregateAndReplaceAcceptedSet`; exit 0; 1/1 passed; tests 0.009 seconds | retained repeat/replace journey regression only; not the `JOURNEY` package gate |
| `JOURNEY-BOUNDARY-ATOMIC` | passed — `swift test --filter boundaryAtomicFailurePreservesAcceptedAuthority`; exit 0; 1/1 passed; tests 0.008 seconds | retained atomic-failure journey regression only; not the `JOURNEY` package gate |
| `RESET-ACTIVE-BOUNDARY` | passed — `swift test --filter resetAllCancelsAndSettlesActiveBoundaryMotion`; exit 0; 1/1 passed; tests 0.030 seconds | Reset All settles the exact active Boundary capability before reset reservation |
| `RECOVERY-RESET-CAPABILITY` | passed — `swift test --filter workspaceRecoveryAndResetAreCapabilityBound`; exit 0; 1/1 passed; tests 0.040 seconds | publication recovery and reset commit/abort remain exact-capability bound |
| `ATOMIC-PERSISTENCE-RESET` | passed — focused atomic persistence/reset regression; 1/1 passed; tests 0.032 seconds | failed prefix persistence exact-aborts the reservation without Boundary or local authority mutation |
| `BOUNDARY-STOP-OPERATOR-PATH` | passed — `swift test --filter boundaryStopCompletesTransaction`; 1/1 passed; tests 0.111 seconds | exact typed acquire, retained announcement-before-motion, and capability-bound Stop |
| `ACTIVE-BOUNDARY-OPERATOR-PATH` | passed — `swift test --filter activeBoundaryHasOnlyStop`; 1/1 passed; tests 0.116 seconds | active Boundary exposes only its exact typed Stop |
| `CENTER-QUANTIZATION-OPERATOR-PATH` | passed — `swift test --filter centerArrivalAcceptsQuantizedSettlement`; 1/1 passed; tests 0.105 seconds | first move is non-retry and accepted arrival retains actual controller position |
| `MIGRATED-BOUNDARY-FILTERS` | passed — migrated Boundary operator-path filters; 13/13 passed | all retained fixtures submit exact rendered typed select/acquire/Stop actions without direct runtime ingress or generic Boundary start |
| `COMPUTATION` | passed — `swift test --filter OperatorWorkspaceComputationDiagnosticsTests`; 9/9 passed | accepted-center Camera Calibration reference ingress and computation diagnostics |
| `SPARSE-TIP` | passed — `swift test --filter OperatorWorkspaceSparseTipCalibrationTests`; 8/8 passed | SIMULATED Boundary truth and exact-frame sparse-tip calibration fixture |
| `DRAW-RUN` | passed — `swift test --filter PlotterDrawingRunEpisodeTests`; 13/13 passed | downstream Drawing Run shared fixture after exact Boundary and sparse-tip publication |
| `CENTER-RETRY` | passed — focused center retry regression; 1/1 passed | exact typed retry action, center-terminal activity, and actionable residual description |
| `PRE-STRICT-QUICK` | passed — `make quick-test`; exit 0; 773/773 passed; tests 13.348 seconds; real 14.76 seconds; log `/var/folders/c0/zjcj7q3d0mzf06v_qmdjk3vm0000gn/T/ea10b-quick.emiGz7dCHp` | successful pre-STRICT broad suite on the preceding source identity; retained as history |
| `INITIAL-DELETE` | passed — `sh Scripts/check_episode_cutover.sh EA-10B`; 8/8 exact scans | initial remaining-gate deletion receipt before the Sendable and shutdown-race source deltas |
| `INITIAL-DOC` | passed — `make docs-check`; 29/29 passed | initial remaining-gate documentation receipt before this evidence-only delta |
| `INITIAL-DIFF` | passed — `git diff --check`; clean | initial remaining-gate diff receipt before this evidence-only delta |
| `INITIAL-JOURNEY` | passed — `make journey-test`; 5/5 passed | initial remaining-gate journey receipt before the Sendable and shutdown-race source deltas |
| `STRICT-PRODUCTION-BUILD` | passed — strict production build; 29.97 seconds | `PlotterBoundaryProjectionSink: Sendable` with redundant relay `@unchecked Sendable` removed |
| `POST-SENDABLE-BOUNDARY` | passed — `swift test --filter PlotterBoundaryEpisodeTests`; 18/18 passed | focused Boundary suite after strict-concurrency correction |
| `SHUTDOWN-CLICK` | passed — `swift test --filter shutdownDoesNotReviveAcceptedClick`; 1/1 passed | async retained Pen admission cannot create a zero-step transaction after shutdown |
| `PEN-CAP` | passed — `swift test --filter PenCapAppearanceSelectionTests`; 17/17 passed | retained Pen-cap suite after entry/post-await shutdown guards |
| `QUICK` | passed — `make quick-test`; exit 0; 773/773 passed; tests 13.957 seconds; real 15.41 seconds; log `/var/folders/c0/zjcj7q3d0mzf06v_qmdjk3vm0000gn/T/ea10b-racefix-quick.6TzUPaxfmJ` | final broad software suite on current frozen Sources and Tests |
| `JOURNEY` | passed — `make journey-test`; 5/5 passed; tests 4.916 seconds; real 6.05 seconds; log `/var/folders/c0/zjcj7q3d0mzf06v_qmdjk3vm0000gn/T/ea10b-racefix-journey.Fs3ODxsqNk` | final journey suite on current frozen Sources and Tests |
| `DOC` | passed — `make docs-check`; contracts plus 29/29 passed; tests 12.694 seconds; real 13.49 seconds; log `/tmp/ea10b-doc-final.jnbNGm` | final documentation and architecture contracts |
| `DIFF` | passed — `git diff --check`; clean; real 0.03 seconds; log `/tmp/ea10b-diff-final.Vcy9oB` | final whitespace/error diff check |
| `STRICT` | passed — `make strict-check`; 778/778 Swift tests in 14.540 seconds plus docs 29/29 in 23.453 seconds; real 64.95 seconds; log `/tmp/ea10b-strict-final-resumable.oonlrS` | final strict-concurrency, signing, launcher, negative-bundle, Swift, and docs gate |
| `DELETE` | passed — `sh Scripts/check_episode_cutover.sh EA-10B`; 8/8 exact scans | final same-landing structural deletion gate |

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; contracts plus 29/29 passed; tests 12.694 seconds; real 13.49 seconds; log `/tmp/ea10b-doc-final.jnbNGm` | final documentation and architecture contracts |
| `DIFF` | passed — `git diff --check`; clean; real 0.03 seconds; log `/tmp/ea10b-diff-final.Vcy9oB` | final whitespace/error diff check |
| `QUICK` | passed — `make quick-test`; exit 0; 773/773 passed; tests 13.957 seconds; real 15.41 seconds; log `/var/folders/c0/zjcj7q3d0mzf06v_qmdjk3vm0000gn/T/ea10b-racefix-quick.6TzUPaxfmJ` | final broad software suite on current frozen Sources and Tests |
| `JOURNEY` | passed — `make journey-test`; 5/5 passed; tests 4.916 seconds; real 6.05 seconds; log `/var/folders/c0/zjcj7q3d0mzf06v_qmdjk3vm0000gn/T/ea10b-racefix-journey.Fs3ODxsqNk` | final journey suite on current frozen Sources and Tests |
| `STRICT` | passed — `make strict-check`; 778/778 Swift tests in 14.540 seconds plus docs 29/29 in 23.453 seconds; real 64.95 seconds; log `/tmp/ea10b-strict-final-resumable.oonlrS` | final strict-concurrency, signing, launcher, negative-bundle, Swift, and docs gate |
| `BOUNDARY` | passed — `swift test --filter PlotterBoundaryEpisodeTests`; exit 0; 18/18 passed; tests 0.125 seconds | focused typed Boundary episode suite |
| `DELETE` | passed — `sh Scripts/check_episode_cutover.sh EA-10B`; 8/8 exact scans | final same-landing structural deletion gate |

The original fresh critic returned `RETASK` for exactly three material blockers.
First, operation/capability reservation occurred only after fact acquisition.
Second, center travel skipped the retained Pen-Up supervision. Third, canonical
UI/reset neither exposed publication recovery nor honored active/pending Boundary
authority. Correction cycle 1 closed center-travel supervision, recovery UI, and
reset gating, but the same critic returned `RETASK` because reserving publication
had no happens-before relationship with the spawned operation task and reset
destructively cleared Boundary authority before durable Learning-prefix
persistence. Correction cycle 2 makes the projection sink genuinely async,
releases the runtime-owned one-shot latch only after sink return, and replaces
destructive reset with exact reserve/commit/abort. The sole same critic
ultimately returned `UNANIMOUS PASS — no material disagreement` for the exact
three closure findings before the downstream final-`QUICK` repairs. At that
point no post-`QUICK` critic had been run, so that verdict did not independently
review the later camera, simulator-fixture, point-selection-wait, center-retry
actionability/activity, or error-description deltas. The later Sendable-sink and
shutdown-race fixes each received the same critic's bounded-delta pass; no new
full critic was commissioned.

The complete nonpass history remains explicit: the first correction-cycle
focused compile failed because a Boolean actionability path omitted its return;
two attempts to hold the synchronous projection sink hung; the first async test
witness failed MainActor protocol conformance; an async suite hung and exited
130 after 149.87 seconds real time; a SwiftPM diagnostic timed out after 90.01
seconds; a direct helper timed out after 45.05 seconds because of a
per-environment recorder bug; and initial atomic fixtures failed because
compatibility migration consumed the injected persistence refusal. These were
test/compiler/scheduling nonpasses, not physical evidence or accepted gates.
The later broad `QUICK` attempts first exited 130 in cascading Boundary operator
flows and later reached an intermediate 771/773 nonpass. Their exceptional-repair
history retains the exact Stop timeout diagnostic, selected-direction trap,
missing announcement-ordering trap, missing center wait, center
waiter/observation/compile/assertion failures, stale-MPos Camera Calibration
ingress, Drawing Run sparse-fixture timeout, simulator Boundary-truth mismatch
and out-of-frame clicks, point-selection repeated-refusal wait issue, generic
center-retry ordering, Boundary activity's legacy-failure dependency,
`LocalizedError` wiring, and compile-only helper defects. The closure run also
retains its zero-span, async terminal/semantic-revision, obsolete-diagnostics,
unrelated-history, and missing-Pen-prerequisite nonpasses. None is reclassified
as a passed gate; the later 773/773 receipt is distinct success evidence.

All seven EA-10B gates passed on the frozen candidate: `BOUNDARY`, `DELETE`,
`QUICK`, `JOURNEY`, `DOC`, `DIFF`, and `STRICT`. The same critic passed both
bounded source deltas; no new full critic was commissioned. EA-10B is
semantically complete as a task-local landing candidate, while Blackdog landing
and canonical-main cleanup remain pending. EA-10C is not selected or
dispatched;
old per-package successor dispatch is prohibited pending the new tranche-policy
correction. GATE-01 remains unchanged and downstream after EA-11C.

Canonical routed-document dispositions for this EA-10B task-local candidate:

- Affected — Product Contract and Swift Architecture: typed Boundary ownership,
  exact Stop/cancel/shutdown, LIVE/SIM separation, save-before-publication,
  recovery without resend, nominal lower-owner composition, and the
  software/simulation/physical boundary.
- Affected — Episode Architecture Execution Plan and Current Evidence: INT-011,
  TSK-004, UI-010, FIX-005, eight EA-10B deletion scans, candidate topology, frozen
  identities, focused receipts, final package gates, and pending landing boundary.
- Affected — `Scripts/check_episode_contract.py`: exact plan scans, candidate
  authority/evidence, ledger fingerprint, and evidence-blocked frontier.
- Affected — `Scripts/test_episode_wave_capsule.py`: the current capsule fixture
  blocks undispatched EA-10C on the new tranche-policy correction rather than
  using the old per-package successor rule.
- Reviewed no change — `Scripts/check_episode_cutover.py` and shell wrapper: the
  generic manifest-driven checker already executes all eight exact scans without
  package-specific executable code.
- Reviewed no change — `Scripts/check_episode_inventory.py`, Document Routing,
  Episode Architecture Vocabulary, Discovery and Observed-Trial Protocol,
  Learning Path Button Transitions, Roadmap, Attended Hardware Runbook, README,
  `AGENTS.md`, `blackdog.toml`, `.gitignore`, repository skills, and conditional
  generation/validation scripts: their retained owners, routing, physical
  procedure, lifecycle, and later-package boundaries remain accurate.

This is automated software and deterministic simulation evidence only. No
attended controller, camera, motion, Pen, paper, operator-click, or observed-ink
validation occurred, and no physical or remote-Git evidence is claimed.

## Pen Interaction episode cutover completion candidate

Selected 2026-08-30 as software package `EA-10A` in Blackdog task
`TASK-539931AC`, attempt `TASK-539931AC-49f2e7307f76`, from protected entry
HEAD `d54fd5195e56e6ac1e2c7b2389507a6636c5e9ce`. This is task-local semantic
completion and a landing candidate, not operational landing. The frozen production Sources aggregate is
`8d089d9d1d0dd446da1ac1d9c04c6a91542bd183f9ca9422c12eda9a2db975dd`;
the frozen Swift Tests aggregate is
`74fe1cfd561fb4f838447e09f9a1bd7ab69562dec31390d4663d422cad986b6d`.

One actor-isolated `PlotterPenInteractionRuntime` now owns Pen Interaction's
source-indexed revision, environment, request, operation and cancellation
identity, attempt mode, mutable Up/Down profile and draft, exact lower actuation
task, cancellation/Stop/settlement/shutdown lifetime, last settlement, and
immutable accepted attempt history. Every `PlotterPenInteractionSubmission`
binds the displayed `PlotterPenInteractionProjectionReference`, current
`PlotterPenInteractionAdmissionFacts`, and one typed
`PlotterPenInteractionIntent`. A stale projection, environment or operation;
wrong phase; missing cap selection, controller session, or Motion; lower-owner
occupancy; sticky ambiguity; invalid value; foreign cancellation capability; or
closed admission returns a typed `PlotterPenInteractionRefusalReason` and
`PlotterPenInteractionRemedy` before lower dispatch.

The Up and Down sliders submit exact value-bearing setpoint intents. One
runtime-owned drain is latest-only: while an earlier value settles, a newer
admitted value replaces the pending value and a superseded intermediate value
is not dispatched. The first accepted setpoint synchronously claims
`setpointDrainInProgress` and publishes `.drainingSetpoint` before the projection
sink, deterministic admission gate, or lower port can suspend. That explicit
phase exposes a newer exact-revision setpoint replacement plus exact Stop but no
confirmation. Lower execution transitions to settling; confirmation returns
only after terminal publication reaches awaiting confirmation. The package-only
`PlotterPenInteractionSetpointAdmissionGate` provides deterministic held and
admission-count observation, while `PlotterPenInteractionTerminalPublicationGate`
holds only the post-lower/pre-publication boundary. Both are inert in production
and grant no admission, effect, cancellation, result, or publication choice.

The original fresh critic returned `RETASK` because workspace busy feedback
made production setpoint coalescing unreachable, exact capability-bound Stop
and lower refusal/possible-change truth were dropped from canonical
actionability, and a fresh SIMULATED Learning session could re-enter with stale
simulated Pen state. Correction cycle 1 removed the workspace-owned busy
feedback and projected exact Stop/refusal/possible-change truth through the
runtime-owned weak sink. The Learning replacingReset path preserves Pen Interaction.
A fresh SIMULATED admission resets only simulated Pen state while preserving
LIVE. The same critic's cycle-1 delta recheck closed the Stop/truth and SIM
blockers but returned `RETASK` on the sole remaining original blocker: the first
setpoint did not claim its drain or leave confirmable state before its first
actor-reentrancy await.

Correction cycle 2 introduces explicit `.drainingSetpoint`, claimed and
published synchronously before that first await. Canonical actionability permits
latest replacement and exact capability-bound Stop there but no confirmation;
settling retains exact Stop for lower execution, and confirmation returns only
after terminal publication. The deterministic production-route regression holds
that pre-await boundary, admits supersession from 55 to 57, proves exact Stop
and absent confirmation, observes only 57 dispatched, then accepts confirmation
after publication. The same critic's correction-cycle-2 final delta recheck
returned exactly `UNANIMOUS PASS — no material disagreement`. Criticism closed
at that point; bounded policy permits no new or post-pass critic.

The final `QUICK` attempt was nonpass at 753/755 with 9 issues: `make quick-test`
executed 755 tests, 753 passed and 2 failed with 9 issues. Both failures first exposed
stale generic Cancel requests after Pen runtime admission; changing them to the
rendered exact capability-bound Pen Stop then exposed the real accepted-click
continuation/restartability race. Exact Pen Stop now settles the already-admitted
EA-04 point-selection continuation before Pen terminal settlement, and Pen
`startDiscoverySequence` no longer recreates a missing canonical attempt. The
regressions submit the rendered typed Stop and verify its exact runtime
capability; no generic Cancel fallback or parallel authority was added. The two
narrow filters now pass 1/1 each: the accepted-click filter built in 9.80 seconds
and completed in 0.051 seconds, while the recovery-transition filter built in
0.28 seconds and completed in 0.078 seconds. An intermediate narrow run after
only the stale request correction remained nonpass with one failed test and two
issues, proving the production race; it remains nonpass history.

The next final retry passed `DOC` 29/29, clean `DIFF`, `QUICK` 755/755, and
`STRICT` 762/762. A separately invoked focused `PEN` run then exposed a distinct
test-synchronization nonpass: after a 74.52-second build, 12/13 passed and
`wrong Stop capability refuses and exact Stop settles the held owner once`
failed because its operation/capability remained active with no cancelled
attempt or settled possible-change truth. Production Stop was not returning
prematurely. The test launched Stop in an unobserved task and released the held
lower port before Stop had captured the current revision; lower settlement
could advance the revision first and make that Stop submission stale.

Test-only `PenInteractionCancellationPublicationProbe` now waits for the real
`.cancelling` projection before releasing the lower port and asserts that exact
Stop returns applied with no operation. It grants no admission, cancellation,
effect, settlement, result, or evidence authority. The exact test passes three
serial repeats: 1/1 with build/test 12.36/0.004 seconds, 1/1 with 0.24/0.005
seconds, and 1/1 with 0.24/0.004 seconds. The full focused `PEN` suite passes
13/13 with build 0.23 seconds and suite 0.763 seconds. No sleep, polling,
`Task.yield`, production change, fabricated possible-change truth, or new critic
was introduced. The definitive final gate sequence below validates the frozen
source/test identities after that test-only synchronization correction.

`PlotterPenInteractionComposition` is a nominal adapter over retained owners.
LIVE routes the exact profile through the existing native Pen settlement seam;
SIMULATED routes explicitly retained nonphysical work through the exact shared
`PlotterCausalSimulatorEffectAdapter`. `MachineController`, `RunInterpreter`,
the causal plant, EA-04 exact-frame cap selection, camera, Vision, checkpoint,
recording/replay/incident, and durable evidence owners remain below or beside
the runtime. LIVE and SIMULATED revisions, profiles, operations, histories, and
settlements remain independent. A lower refusal remains refusal; ambiguous or
cancelled work after a returned command retains possible-physical-change truth
and never authorizes automatic resend. Shutdown closes admission, drains exact
accepted work, awaits lower settlement and terminal publication, and leaves no
runtime operation owner.

Accepted `PenInteractionAttemptEvidence` is immutable and retains the confirmed
values, available MPos, controller outcomes, and timestamps. It does not claim
an attended Pen position, camera observation, or ink. The removed workspace
draft/profile/history/pending-command fields, sequence guard, setpoint task,
begin/complete/finish helpers, and high-level cap/finish fixtures have no renamed
authority. The presentation-only `LearningPathTerminology.identifyPenCap`
constant and canonical PlotterUI setpoint intent remain deliberately retained.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; exit 0; documentation and architecture contracts plus 29/29 checker tests passed in 11.921 seconds, 12.554 seconds wall | canonical routed documents and executable contract |
| `DIFF` | passed — `git diff --check`; exit 0, no output | whitespace/error diff validation |
| `QUICK` | passed — `make quick-test`; exit 0; 755/755 tests passed in 14.270 seconds after a 0.51-second build | broad software regression suite; earlier nonpasses remain history |
| `STRICT` | passed — `make strict-check`; exit 0; observed wall approximately 110.94 seconds; strict-concurrency warnings-as-errors build 39.36 seconds; signing, launcher, and negative-bundle checks passed; full 762/762 tests passed in 16.462 seconds after a 43.16-second build; documentation contracts and 29/29 checker tests passed in 11.414 seconds | strict concurrency, complete tests, signing, launcher, negative bundle, and docs |
| `PEN` | passed — `swift test --filter PlotterPenInteractionEpisodeTests`; exit 0; 13/13 passed; build 71.02 seconds, suite 0.766 seconds; the exact Stop test also passed three serial 1/1 repeats before the final full suite | exact value/evidence, revision and owner refusal, duplicate admission, synchronously claimed latest-only drain, pre-await confirmation exclusion, 55-to-57 supersession, exact Stop admission/publication synchronization, only 57 dispatched, post-publication confirmation, refusal/ambiguity, LIVE/SIM separation, atomic terminal publication, and shutdown quiescence |
| `DELETE` | passed — `sh Scripts/check_episode_cutover.sh EA-10A`; exit 0; all 8 exact scans had zero matches in 0.109 seconds | retired workspace state/ingress/task/guard and high-level fixture paths |

An earlier correction-cycle-2 focused invocation compiled, then ran 13 tests
with 12 passing and one stale phase assertion failing; build 53.97 seconds,
suite 0.784 seconds, and test run 0.785 seconds. That result remains nonpass
history. The assertion was aligned to the new truthful phase before the final
receipt above.

All six EA-10A package gates passed on the frozen candidate. The same critic's
correction-cycle-2 final delta verdict remains exactly `UNANIMOUS PASS — no
material disagreement`; criticism is closed and no new or post-pass critic was
run. EA-10A is semantically complete as a task-local landing candidate. Only
Blackdog landing, canonical-main cleanup verification, and successor-capsule
generation remain pending. EA-10B is not selected or dispatched. GATE-01
remains unchanged and downstream after EA-11C.

Canonical routed-document dispositions for this task-local EA-10A completion candidate:

- Affected — Product Contract and Swift Architecture: typed Pen Interaction
  ownership, value-bearing Up/Down admission, latest-only drain, exact Stop and
  shutdown, nominal retained-owner composition, immutable evidence, and
  software/simulator/physical boundaries.
- Affected — Episode Architecture Execution Plan and Current Evidence: INT-010,
  GRD-008, TSK-001, FIX-004 current seams, eight EA-10A deletion scans, complete
  ledger outcome, task/attempt identity, frozen source/test hashes, final gate
  receipts, and operational landing boundary.
- Affected — `Scripts/check_episode_contract.py`: current topology, plan scans,
  completion evidence/frontier, landing boundary, and mechanically updated
  ledger fingerprint.
- Reviewed no change — `Scripts/check_episode_cutover.py` and its shell wrapper:
  the generic manifest-driven implementation already executes the eight new
  exact scans without package-specific code.
- Reviewed no change — `Scripts/check_episode_inventory.py`: the adapted live
  inventory rows satisfy its existing exact-source checks and preserve the
  immutable EA-01 characterization IDs.
- Affected — `Scripts/test_episode_wave_capsule.py`: mechanically coupled
  completion assertions; EA-10B remains undispatched until operational landing
  and canonical successor-capsule generation.
- Reviewed no change — Document Routing (`docs/INDEX.md`), Episode Architecture
  Vocabulary, Discovery and Observed-Trial Protocol, Learning Path Button
  Transitions, Roadmap, Attended Hardware Runbook, README, `AGENTS.md`,
  `blackdog.toml`, `.gitignore`, both repository skills, and their execution
  references: the existing routing, terminology, operator flow, physical
  procedure, lifecycle, authorization, and future-work boundaries remain
  accurate.

This is automated software and deterministic simulation evidence only. No
attended controller, camera, motion, Pen, paper, operator-click, or observed-ink
validation occurred, and no physical or remote-Git evidence is claimed.

## Pilot dependency-cycle correction

Selected 2026-08-30 as repository package `DOC-03` in Blackdog task
`TASK-B7C9E592`, attempt `TASK-B7C9E592-3408edcef715`. DOC-03 is complete;
migration remains incomplete. It changed only canonical documentation and
executable checker expectations. It moved no product, runtime, device, effect,
Stop, evidence, or physical authority.

The pre-relocation GATE-01 inspection failed two unchanged reduction
requirements. `operator-workspace-policy-state` was 6 to 6, not decreased:
`frameMode`, `liveLearningSession`, `simulatedLearningSession`,
`activeStoppableOperation`, `activeHardwareIntentCount`, and
`intentDrainWaiters` remained. `operator-workspace-adapters` was 7 to 10, not
not-increased: the current set retained five earlier façade properties and
added `drawingRunFactSource`, `drawingRunInterpreterPort`,
`drawingRunCameraPort`, `drawingEvidencePort`, and
`causalSimulatorEffectAdapter`. These are failed pre-relocation measurements,
not passed Pilot evidence.

That failure exposed a dependency cycle rather than a reason to weaken or
reclassify either metric. GATE-01 could not pass until the authority transfers
assigned to EA-10A through EA-11C reduced the remaining policy and adapter
ownership, but those same packages depended on GATE-01. DOC-03 therefore moves
the unchanged pending gate after EA-11C, makes EA-10A depend on DOC-03, and
makes VAL-01 depend on GATE-01. Every Pilot predicate, metric name, and
decrease/not-increase threshold remains unchanged. The eventual Pilot checker
must require completed package evidence through DOC-03, EA-10A through EA-10G,
and EA-11A through EA-11C, including every required same-landing `DELETE` gate.
GATE-01 was not run and is not complete.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; 29/29 passed in 14.014 seconds, 14.770 seconds wall; documentation and architecture contracts passed | canonical dependency order, evidence, and executable checker fixtures |
| `DIFF` | passed — `git diff --check`; exit 0, no output, less than 0.01 seconds wall | whitespace/error diff validation for this documentation-only package |

At DOC-03 completion, EA-10A remained the undispatched successor frontier until
Blackdog landing, clean canonical-main verification, and successor-capsule
generation. That historical frontier statement is superseded by the task-local
EA-10A completion-candidate section above.

Canonical routed-document dispositions for DOC-03:

- Affected — Episode Architecture Execution Plan and Current Evidence: exact
  dependency order, failed pre-relocation measurements, task identity,
  final DOC/DIFF evidence, and undispatched successor frontier.
- Affected — `Scripts/check_episode_contract.py`,
  `Scripts/check_episode_pilot_gate.py`, and their directly coupled fixtures:
  exact ledger shape/frontier and eventual completed-package/deletion evidence.
- Reviewed no change — Document Routing (`docs/INDEX.md`), Swift Architecture,
  Product Contract, Episode Architecture Vocabulary, Discovery and Observed-
  Trial Protocol, Learning Path Button Transitions, Roadmap, Attended Hardware
  Runbook, README, `AGENTS.md`, `blackdog.toml`, `.gitignore`, and both
  repository skills: DOC-03 moves no product, physical, lifecycle, routing,
  vocabulary, or operator authority.
- Reviewed no change — inventory and cutover checker implementations: their
  current source inventory and package-specific zero-match scans remain the
  authority consumed by the relocated Pilot checker.

## Pre-GATE-01 Drawing Run task-owner correction

Selected 2026-08-30 as named software correction `FIX-03` in Blackdog task
`TASK-0A7AB3EE`, attempt `TASK-0A7AB3EE-80f88f4a41d8`. The correction removes
the redundant stored `OperatorWorkspace.drawingRunTask`. The App now awaits
`PlotterDrawingRunRuntime.submit` directly, while runtime shutdown closes
admission, requests the exact `.shutdown` Stop for an admitted run, and does
not return until that run has published a terminal snapshot. The runtime keeps
the existing RunID, Stop, cancellation, possible-ink/no-redraw, publication
recovery, and retained controller/interpreter/camera/Vision/evidence authority.

The source-derived `TASK-METRIC` gate compares the pinned EA-01 source at
`96253197a42dc6052ef76ad53c4c94c1c5f745a1`, the pre-correction EA-09 landing
at `03d8279603c39ad19b49d980fc39aa0144b96148`, and this candidate. Both source
baselines contain nine direct stored `OperatorWorkspace` `Task` owners. The
candidate contains eight; relative to the pre-correction tree, the only removed
owner is `drawingRunTask` and no replacement workspace Task owner was added.
This proves the `workspace-task-owners` reduction without asserting any of the
other still-pending GATE-01 metrics. GATE-01 was not rerun and EA-10A was not
started. No critic, attended physical validation, or remote-Git action was
commissioned or claimed for this bounded correction.

| Validation | Result | Scope |
| --- | --- | --- |
| `DRAW-RUN` | passed — `swift test --filter PlotterDrawingRunEpisodeTests`; 13/13 passed | runtime-owned admission, exact Stop, shutdown quiescence, terminal publication, RunID recovery, and no-redraw behavior |
| `TASK-METRIC` | passed — `PYTHONDONTWRITEBYTECODE=1 python3 Scripts/check_episode_task_metric.py`; source-derived 9 to 8, exactly `drawingRunTask` removed | pinned EA-01 count, pre-FIX-03 owner-set delta, and exact Current Evidence reconciliation |
| `DELETE` | passed — `sh Scripts/check_episode_cutover.sh FIX-03`; exact `drawingRunTask` zero-match scan passed | deleted workspace submission/shutdown join |
| `DOC` | passed — `make docs-check`; canonical documents and executable contracts passed, capsule tests 29/29, repository contract passed | final FIX-03 task candidate |
| `DIFF` | passed — `git diff --check`; clean | final FIX-03 task candidate |
| `QUICK` | passed — `make quick-test`; 751/751 passed | final FIX-03 task candidate |
| `STRICT` | passed — `make strict-check`; warnings-as-errors strict build, 758/758 tests, signing, launcher, negative-bundle, documentation contracts, and capsule tests 29/29 passed | final FIX-03 task candidate |

## Episode UI cutover

Delivered 2026-08-29 by Blackdog task `TASK-D55FD455`, attempt
`TASK-D55FD455-1d0731730d03`, and landed on canonical `main` at
`03d8279603c39ad19b49d980fc39aa0144b96148`. EA-09 is complete; migration
remains incomplete. The separate GATE-01 Pilot decision remains pending. No
attended physical validation or remote-Git action is claimed.

The staged target topology is `PlotterUI -> PlotterEpisodeModel` only.
`PlotterUICompiler` accepts copied values in `PlotterUICompilerInput`, bounds
candidate visits, emitted actions, Learning milestones, diagnostics, text, and
runtime revisions, and emits one immutable `PlotterUIProjection`.
`PlotterUILearningFacts` and `PlotterUILearningProjection` keep Learning
progression in that package-owned value compiler.
`PlotterUILearningActionabilityCompiler` additionally owns the bounded
current-owner, item-status, action/Stop-strip, availability, Pen-adjustment,
direction, and reset-reachability decisions over copied facts. The App's
`PlotterLearningActionabilityFactAdapter` translates retained Runtime facts into
those PlotterUI facts without choosing a decision, and
`PlotterLearningDetailedPresentationNormalizer` renders canonical decisions
cosmetically. `OperatorWorkspace` consumes that canonical actionability and
resolves the exact canonical action before retained-owner dispatch; the deleted
App status/completion/action-strip/Stop/sparse compilers have no replacement
authority. Every rendered semantic action must be a member of the projection
with one exact bound `PlotterUIIntent`, availability result, UI revision, and runtime revision.
`PlotterUIRequest` creation and the production sink fail closed unless all four
facts still match. Pane/window/viewport state and unsubmitted manual text remain
UI-local presentation state; they do not become episode, controller, camera,
Vision, persistence, Stop, or evidence authority.

The App composes those immutable facts and the retained lower owners. It does
not extend the compiler, fabricate action/intent pairs, or bypass the
projection through direct Learning point/reset/workspace dispatch. One App-bound
incident-package presentation route invokes
`PlotterIncidentPackageUIService.startUnavailable` with only a fresh request
ID because no complete production source provider or source-identity owner
exists. Its request-owned stream is explicitly bounded and terminates with
typed `.noCompleteSourceProvider` refusal/remedy. A future real assembly must
instead supply the complete exact `PlotterIncidentPackageUISourceIdentity`.
The service wraps the sole existing `PlotterIncidentPackageAssembler` and may
present format version, exact byte count/digest, typed refusal/remedy,
`canonicalEnvelopeOnly`, and `physicalEvidenceClaimed == false`; it exposes no
bytes and adds no source assembler, recorder, artifact store, filesystem/export
backend, device port, fabricated source completeness, or physical-evidence
claim.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; docs and architecture contracts plus 29/29 documentation/checker tests; final real 14.82 seconds | final task-local documentation/checker candidate |
| `DIFF` | passed — `git diff --check`; clean; real 0.05 seconds | whitespace/error diff validation on the final task-local candidate |
| `QUICK` | passed — `make quick-test`; 750/750 passed after 15.778 seconds; real 18.22 seconds | final broad suite after the authorized exceptional test-only gate repair |
| `JOURNEY` | passed — `make journey-test`; 7/7 passed after 7.347 seconds; real 8.66 seconds | final journey suite |
| `STRICT` | passed — `make strict-check`; warnings-as-errors build 45.90 seconds; signing, launcher, and negative-bundle checks passed; strict build 50.35 seconds; 757/757 passed after 16.581 seconds; docs/checkers 29/29 in 13.314 seconds; real 141.81 seconds | final strict package gate |
| `UI` | passed — `swift test --filter PlotterEpisodeUIActionabilityTests`; 17/17 passed after 0.093 seconds; final real 85.36 seconds | bounded canonical projection, Learning actionability, exact semantic membership/binding/availability, and production sink revision validation |
| `DELETE` | passed — `sh Scripts/check_episode_cutover.sh EA-09`; 16/16 exact zero-match scans plus Learning behavior/topology validation; real 0.45 seconds | deleted/bypass authority and renamed/split compiler rejection |
| `LEARNING-DETAIL` | passed — focused detailed-presentation selection; 18/18 | App fact translation and cosmetic rendering consume canonical decisions without a second compiler |
| `INCIDENT-UI` | passed — focused incident service suites; 24/24 | bounded request-owned progress/result identity, truthful no-source refusal, no fabricated identity, and no backend or physical claim |
| `INVENTORY` | passed — 109 stable entries and 141 exact scans | current source ownership and cutover manifest |
| `EA-09-CUTOVER-CHECKER` | passed — `Scripts/test_episode_cutover.py`; 8/8 | cosmetic renderer and canonical fact translation pass; renamed action/status/availability/retained-candidate/reachability and split mapper fixtures fail closed |
| `PILOT-CHECKER` | passed — 8/8 unit tests | checker mechanics only; GATE-01 remains pending |
| `REPAIR-SUITES` | passed — named repair suites 135/135 | five stale integration-test files now assert absent/unavailable/no effects and a narrowed stale-authority scan; production source was unchanged |
| criticism | passed — initial `RETASK`; correction-cycle-1 `RETASK`; correction-cycle-2 exact `UNANIMOUS PASS — no material disagreement`; exceptional repair-delta exact `UNANIMOUS PASS — no material disagreement` | criticism closed; no new or post-pass critic occurred |

The initial critic returned exactly `RETASK` for three material blockers. The
same critic's correction-cycle-1 recheck returned `RETASK` because a renamed App
Learning compiler remained. Correction-cycle-2 closed the source delta with the
exact verdict `UNANIMOUS PASS — no material disagreement`. QUICK then
failed/hung at 134.84 seconds on stale or invalid integration tests. The user
explicitly authorized one exceptional EA-09 gate-repair cycle; production
source remained unchanged while five test files were repaired to assert
absent/unavailable/no effects and narrow the stale-authority scan. The same
critic's exceptional delta verdict was exactly
`UNANIMOUS PASS — no material disagreement`. The final gates above then passed;
criticism is closed and no new or post-pass critic was commissioned.

The sole fresh critic returned exactly `RETASK` for these three material
blockers:

1. **Bounded immutable UI authority was not actually transferred.** Substantive
   Learning facts/compiler logic remained in `PlotterApp`; `appRequest`
   fabricated arbitrary action/intent pairs; Drawing and Comparison actions
   were absent from `semantic.actions`; the production sink checked revisions
   but not current membership, bound intent, or availability; manual input
   accepted arbitrary action IDs; the focused suite used a fake sink; and the
   diagnostic loop was unbounded. The UI/App and production-coverage leases
   must move one bounded compiler/projection into `PlotterUI`, enumerate every
   rendered semantic action, delete `appRequest`, enforce exact production
   membership/intent/availability/revision checks, bound inputs/diagnostics, and
   test the production sink.
2. **Incident progress delivery was not strictly bounded.** The runtime service
   used a default unbounded `AsyncStream` and an unbounded subscription map, so
   held delivery could accumulate subscribers or lose an independently observed
   terminal identity. The runtime/test lease must use one request-owned stream
   with an explicit small newest-value buffer and a terminal update that binds
   the exact request/result, proved with a held-source continuation and no
   sleeps or polling.
3. **The canonical documentation and structural checker described the previous
   frontier rather than the EA-09 candidate.** Current Evidence still called
   EA-09 undispatched, the architecture denied the new App incident reference,
   the deletion manifest did not scan concrete compiler/action bypasses, and no
   truthful candidate Pilot predicate/reduction table existed. This
   documentation/checker lease must record the selected task/attempt and
   in-progress boundary, current topology and incident limitations, strengthened
   scans, exact pre-correction evidence, pending Pilot claims, and the new
   ledger fingerprint without claiming final completion.

The candidate Pilot table is deliberately non-final. Evidence tokens are the
exact closed set consumed by the Pilot checker, but every predicate whose
GATE-01 reduction or continuation proof is still unmeasured remains `pending`:

| Pilot predicate | Result | Evidence |
| --- | --- | --- |
| GENERICITY | passed | `EA-02A/CORE`, `EA-02B/PLOTTER-MODEL` |
| REPLAY | passed | `EA-05B/REPLAY` |
| DEVICE-OWNERS | passed | `EA-05A/RECORDING`, `FIX-02/LINK-OBS`, `FIX-02/LINK-SAFETY` |
| ENVIRONMENT-GRAMMAR | pending | `EA-07/SIM`, `EA-09/UI` |
| SAME-SLICE-DELETION | pending | `EA-04/DELETE`, `EA-06/DELETE`, `EA-07/DELETE`, `EA-08A/DELETE`, `EA-08B/DELETE`, `EA-09/DELETE`, `FIX-03/DELETE`, `EA-10A/DELETE`, `EA-10B/DELETE`, `EA-10C/DELETE`, `EA-10D/DELETE`, `EA-10E/DELETE`, `EA-10F/DELETE`, `EA-10G/DELETE`, `EA-11A/DELETE`, `EA-11B/DELETE`, `EA-11C/DELETE` |
| AUTHORITY-REDUCTION | pending | `EA-01/INVENTORY`, `METRICS/AUTHORITY-REDUCTION` |
| OBSERVABILITY | pending | `EA-05C/INCIDENT`, `EA-06/MOTION`, `EA-09/UI` |
| WORKSPACE-REDUCTION | pending | `METRICS/WORKSPACE-REDUCTION` |
| SAFETY-EVIDENCE | pending | `FIX-02/LINK-SAFETY`, `EA-07/SIM`, `EA-09/UI` |

FIX-03 supplied the reproducible intermediate source-count comparison for
`workspace-task-owners`: the pinned EA-01 baseline and pre-correction EA-09
landing both contain nine direct stored workspace Task owners, while the FIX-03
tree contains eight. EA-11C's masked all-production-source scan now proves the
legacy `OperatorWorkspace` declaration absent and the current direct stored
owner count is zero. Three still-unmeasured metric names remain `pending`, not
invented numbers or reductions; the 6-to-6 policy-state and 7-to-10 adapter
rows retain their exact failed pre-relocation facts. GATE-01 must replace every
remaining pending cell and remeasure both failed rows from source before it can
pass:

| Reduction metric | Baseline | Current | Requirement |
| --- | --- | --- | --- |
| independent-admission-sites | pending | pending | decreased |
| workspace-task-owners | 9 | 0 | decreased |
| environment-mode-branches | pending | pending | decreased |
| direct-effect-calls | pending | pending | decreased |
| operator-workspace-policy-state | 6 | 6 | decreased |
| operator-workspace-adapters | 7 | 10 | not-increased |

Canonical routed-document dispositions for this task-local complete EA-09 candidate:

- Affected — Episode Architecture Execution Plan, Current Evidence, Swift
  Architecture, and Product Contract: current UI/compiler/sink ownership,
  incident presentation boundary, selected task/attempt, strengthened deletion
  manifest, exact pre-correction evidence, and pending Pilot facts.
- Affected — `Scripts/check_episode_contract.py` and its capsule fixture:
  task-local completion/frontier wording, outcome requirements, structural
  scans, and the ledger fingerprint.
- Reviewed no change — Document Routing (`docs/INDEX.md`): all affected
  canonical documents and executable checkers remain routed by their existing
  entries.
- Reviewed no change — inventory and cutover checker implementations: the
  canonical manifest table supplies their strengthened EA-09 scans.
- Added in the EA-09 candidate — the Pilot checker and its eight-test fail-closed
  unit suite. A passing unit suite proves checker mechanics only; the live
  GATE-01 command remains pending and is expected to refuse the incomplete
  predicate and reduction evidence.

This is software evidence only. No attended controller, camera, motion, Pen,
paper, operator-click, or observed-ink validation occurred. No remote-Git
action or GATE-01 continuation decision is claimed.

## Drawing run episode cutover

Integrated 2026-08-29 in Blackdog task `TASK-51550DB1`, attempt
`TASK-51550DB1-84f1763c31b5`, from canonical `main` base
`f244cf9761c16bcb19b11a0912eb6370168d356c`. EA-08B landed on canonical
`main` at `ccb06859fe7ca00011f71ef30f6a6ade6c7109c4`: its
authority/deletion implementation, corrected focused suite, same-critic
correction-cycle acceptance, and all seven package gates are complete.
Migration remained incomplete; the statement that EA-09 had not been selected
was accurate for the frozen EA-08B acceptance and is superseded by the current
EA-09 section above.

The landed cutover makes one actor-isolated `PlotterDrawingRunRuntime` the
source-indexed Drawing Studio run authority. Every
`PlotterDrawingRunSubmission` binds one `PlotterDrawingRunRequestID`, the
immutable `PlotterDrawingRunRevision`, exact environment and plan identity, and
one typed `PlotterDrawingRunIntent`: start, exact-capability Stop, exact-run
review pin/unpin, new-run handoff, or exact publication recovery. Refusals bind
the request and compared projection to one `EpisodeAuthorityID`, typed
`PlotterDrawingRunRefusalReason`, and operator remedy. SwiftUI consumes immutable
`PlotterDrawingRunSnapshot` values and submits only through
`PlotterDrawingRunIntentSink`.

EA-08A remains the immutable draft/plan owner. Start admission captures the
exact `PlotterDrawingRunPlanIdentity`, then refreshes complete external facts,
including `penActuationProfile`, and revalidates that same plan, paper
assertion, Learning prerequisite, LIVE environment, and controller readiness
around each physical boundary. Pre-effect drift produces an exact typed refusal
with compared requirement, owner, revisions, and remedy and invokes no machine,
Pen, camera, Vision, or archive port. The runtime-owned admission-closed latch
is set before runtime shutdown joins the admitted run, then rechecked after
every suspension and immediately before every lower effect. Admission is FIFO
and exclusive; one active RunID owns progress, exact Stop capability,
settlement, terminal publication, shutdown quiescence, and review handoff.

The admitted LIVE chain is: idempotent Pen Up normalization; supervised travel
to the observation pose when required; an exact local baseline capture; lower
`RunInterpreter` execution of the immutable plan; exact final MPos; a strictly
newer same-source post frame; applicability-aware observation; and append of one
immutable `DrawingRunEvidenceRecord` before successful terminal publication.
`PlotterDrawingRunFactSource`, `PlotterDrawingRunInterpreterPort`,
`PlotterDrawingRunCameraPort`, `PlotterDrawingRunVisionPort`, and
`PlotterDrawingRunEvidencePort` are nominal adapters. They transfer no
MachineController, RunInterpreter, CameraCapture, VisionWorker, or
`DrawingRunEvidenceStore` internals into the episode runtime.

Geometry outside the accepted tip applicability remains executable but is
published as `nonAttributable`, with
`notAttempted(.projectionOutsideTipApplicability)` and no Vision-derived ink
claim. Evidence append must complete before `.succeeded` is published. Failure
retains the exact proposed record as `.publicationIncomplete`, exposes one
identity-bound recovery capability, and cannot appear as successful current
evidence. Publication recovery is an identity-bound in-flight owner: while
`.appending`, new-run, review, paper, and domain mutation refuse; settlement
revalidates the exact recovery capability before publishing success or failure.
A rejected archive load is typed run-unavailable/no-redraw ambiguity and fails
start closed with zero resend or LIVE effect. No-redraw truth is independent of
append success: any possibly
ink-producing plan remains blocked by exact plan identity until the operator
hands off to a new immutable EA-08A plan. No refusal, cancellation, ambiguity,
possible ink, Vision rejection, or storage failure authorizes automatic redraw
or resend.

Review pin/unpin and new-run handoff are RunID-bound. Stop accepts only the
active runtime capability and delegates cancellation settlement to the retained
lower interpreter. SIMULATED start returns typed
`simulatedRunIsNonphysical`/`switchToLiveSource` refusal and performs zero LIVE
interpreter, camera, Vision, or archive effects. The runtime sets
`physicalEvidenceClaimed` only for a LIVE durably published success; that field
does not turn software validation into attended physical evidence.

Production composition injects one exact runtime and the nominal retained-owner
adapters. The App awaits async runtime submission directly and owns no stored
run-lifetime or shutdown-join Task; it projects the runtime's active snapshot
and does not duplicate run admission, Stop, evidence publication, review, or
no-redraw authority. The explicitly retained Drawing Border workflow uses
package-only nominal lower adapters and keeps its later EA-10E sequencing and
evidence semantics.

The cutover deletes `DrawingStudioRunStateStorage`, `DrawingEvidenceActions`,
`PlotterDrawingStudioRunSynchronizationGate`, `runDrawingStudioPlan`,
`performDrawingStudioRunAction`, `performCompletedComparisonReviewAction`,
`DrawingStudioRunAction`, `CompletedComparisonReviewAction`, and the workspace
run latches, duplicate Stop/review/evidence state, direct run guards, and raw UI
handlers. The EA-08B deletion manifest retains five exact scans for
`runDrawingStudioPlan`, `performCompletedComparisonReviewAction`,
`machineActions.beginDrawingPlan`, `cameraActions.observePlannedDrawingInk`, and
the `makeDrawingStudioRunRecord` fixture. `DELETE` passed all 5/5 exact scans in
0.10 seconds.

The frozen accepted source identity is:

- `PlotterDrawingRun.swift`
  `eb190dc6822eab63e99bf6eceafb38c38f5df52983e672ec652baa0204202232`;
- `PlotterDrawingRunRuntime.swift`
  `edc303ee4be20e22d2d781c99b726b4a94ca99342f3b2a049212f2c16fcf6662`;
- `OperatorWorkspace.swift`
  `d77fc0e479f775cc3368cc87cdb72ee3e3eeff22e8ae3fdaa338efe381cda02e`;
- `DrawingStudioPresentation.swift`
  `4ae3e92d0f27113fd59c9ea5875a70d7a7f5f99a1e067a306d011cdc873be1f7`;
- `CompletedComparisonReviewPresentation.swift`
  `421d801b0e753112da2e239fb39abe5c6bd9749384cb38f61bb342896b524203`;
- `ActionSurface.swift`
  `104c5ae8d9c70cd0ac81b82c783be3eb078900348b7649eaa14b7f4546ba9b8b`;
- `AdaptivePlotterApp.swift`
  `291e1280aa0026222cf0a97a8852b4d57336ae5b9b2d39bd693fe30c3bd93934`;
- `DrawingRunEvidenceComposition.swift`
  `3d7115afda564f37dc4dbd2ee936e1f870055b288e4580fc63133da22273c193`;
- `PassiveProbeComposition.swift`
  `ef2e6410c828ef9e7975ed2306bf94254af02c225e73993d90341efac5562275`;
- `CameraComposition.swift`
  `798b357b725b13b61463abe1d5f5fa9da7de4d38ebc3e701ac09481f7c654116`.

The frozen focused-test identity is:

- `PlotterDrawingRunEpisodeTests.swift`
  `b5521a1c2db0a3e981e150e6f805246af1f30be087b3adc984020ad464bc5f6d`;
- `PlotterDrawingRunEpisodeTestSupport.swift`
  `37f696ad128c048f485f5eff57888661e5848841d4aae17ceadebe5f62f06723`;
- `DrawingStudioPresentationTests.swift`
  `ab7791605ebb30409ea4701d2e40d118ec345b0428c52a706decf51bc7fd4164`.

| Validation | Result | Scope |
| --- | --- | --- |
| `DRAW-RUN` | passed — `swift test --filter PlotterDrawingRunEpisodeTests`; 12/12 passed in 0.343 seconds | typed admission/refusal, full-fact/profile freshness, shutdown-before-effect closure, exact Stop, LIVE chain, non-attribution, identity-bound append recovery, rejected-archive ambiguity, no-redraw, review/new-run, and SIMULATED zero-LIVE-effect behavior |
| `DELETE` | passed — `sh Scripts/check_episode_cutover.sh EA-08B`; 5/5 exact scans passed in 0.10 seconds | five exact EA-08B zero-match scans |
| `DOC` | passed — `make docs-check`; 29/29 passed in 11.35 seconds | documentation/checker contract |
| `DIFF` | passed — `git diff --check`; clean | whitespace/error diff check |
| `QUICK` | passed — `make quick-test`; 730/730 passed in 15.19 seconds | repository quick suite |
| `JOURNEY` | passed — `make journey-test`; 7/7 passed in 6.32 seconds | operator journey suite |
| `STRICT` | passed — `make strict-check`; 737/737 strict tests plus 29/29 docs in approximately 112.10 seconds; strict-concurrency warnings-as-errors build 37.85 seconds, strict build 41.47 seconds, strict test duration 13.565 seconds, stable-local signing, launcher logic/validation, and negative bundle all passed | strict-concurrency, complete tests, signing, launcher, negative-bundle, and documentation contracts |
| criticism | passed — original `RETASK`; same critic correction-cycle-1 exact final verdict `UNANIMOUS PASS — no material disagreement` | shutdown/effect-fact closure, identity-bound publication recovery and archive ambiguity, and canonical documentation literal |

Two earlier focused invocations stopped at compiler-only diagnostics and remain
nonpass history; neither is promoted to test evidence. The second correction
unwrapped the optional lower-interpreter snapshot before reading final MPos,
preserving typed disconnected refusal rather than fabricating a position. The
pre-critic frozen source then produced 8/8 in 0.327 seconds. The sole fresh
critic returned `RETASK`; after the bounded corrections, the focused suite
passed 12/12 in 0.343 seconds. No broad or deletion gate result is inferred
from that focused pass. The same critic's correction-cycle-1 exact final
verdict was `UNANIMOUS PASS — no material disagreement`. Criticism is closed;
no new, full, or post-pass critic is required or allowed.

Historical documentation and deletion nonpasses remain nonpass history. One
`DOC` attempt rejected a lowercase canonical literal, and the next rejected
`Cutover candidate:` as a software-outcome prefix. After those exact
corrections, `DOC` passed 29/29 and `DIFF` was clean before this documentation
delta; their final reruns passed 29/29 in 11.35 seconds and clean, respectively.
An earlier `DELETE` invocation
stopped before its scans with `invalid EA-01 manifest: source declaration
missing: DrawingStudioRunAction`; it supplies no deletion-gate evidence and is
superseded only by the later 5/5 pass. No broad or final deletion result is
inferred from the focused or critic pass.

This is software evidence only. No attended controller, camera, motion, Pen,
paper, operator-click, or observed-ink validation occurred. SIMULATED outcomes
remain nonphysical and do not validate LIVE effects. No remote-Git action,
Blackdog landing, or canonical-`main` cleanup is claimed.

Canonical routed-document dispositions for this EA-08B candidate:

- Affected — Episode Architecture Execution Plan and Current Evidence: actual
  runtime ownership, retired App paths, frozen identities, and final gate
  evidence.
- Affected — Swift Architecture and Product Contract: one run runtime/sink/
  snapshot authority, nominal lower-owner adapters, append-before-success,
  exact Stop, no-redraw, review/new-run, and SIMULATED boundaries.
- Affected — `Scripts/check_episode_contract.py`: staged-complete candidate
  wording, corrected identities/evidence, conditional frontier, and ledger
  fingerprint.
- Affected — `Scripts/test_episode_wave_capsule.py`: its EA-08B fixture retains
  the historical conditional-frontier fact while the current evidence now
  records the selected EA-09 task separately.
- Reviewed no change — `Scripts/check_episode_cutover.sh`: the five required
  EA-08B zero-match scans are already exact.
- Reviewed no change — Document Routing (`docs/INDEX.md`), Episode Architecture
  Vocabulary, adaptiveplotter episode protocol, operator button transitions,
  Roadmap, Attended Hardware Runbook, and README: their routing, vocabulary,
  operator policy, physical procedure, and product boundaries remain accurate.

For the frozen EA-08B acceptance, the staged ledger mechanically derived EA-09
only as the conditional post-landing ordinary frontier. All EA-08B gates had
passed, but EA-09 selection still awaited Blackdog landing, clean canonical
`main`, and successor-capsule generation. The current section above supersedes
that historical frontier state with the task-local complete, unlanded EA-09 candidate.

## Drawing draft episode cutover

Integrated 2026-08-28 in Blackdog task `TASK-5700F7F5`, attempt
`TASK-5700F7F5-0ad2465cded1`, from canonical `main` base `ac6a6688`.
EA-08A landed on canonical `main` at
`f244cf9761c16bcb19b11a0912eb6370168d356c`; migration remains incomplete.

The accepted slice makes `PlotterDrawingDraftRuntime` the single source-indexed
Drawing Studio draft authority. A `PlotterDrawingDraftSubmission` binds one
`PlotterDrawingDraftRequestID`, the immutable `PlotterDrawingDraftRevision`, the
complete `PlotterDrawingDraftExternalFactRevisions`, and one typed
`PlotterDrawingDraftIntent`. `submit` compares both draft and external-fact
revisions before mutation. Refusal fixes the exact request, compared facts,
owner, `PlotterDrawingDraftRefusalReason`, and operator remedy; SwiftUI receives
only immutable `PlotterDrawingDraftSnapshot` values and sends revision-bound
submissions through `PlotterDrawingDraftIntentSink`.

Open and close preserve typed Learning, current-run, and retained-terminal
prerequisites. Catalog selection, evidence role, camera placement, scale,
rotation, centering, and new-plan requests rebuild deterministic values from
the current source only. Catalog/program identity is deterministic, placement
identity changes only with a draft placement mutation, and
`ExecutionPlanRevision` stays content-addressed. Invalid scale or rotation,
stale projections, unavailable registration/region, exact-frame mismatch, and
geometry outside the accepted `DrawableMachineRegion` produce typed refusals;
planning never clips a stroke.

`PlotterDrawingPlanningAdapter` is the sole upper-layer route into the retained
pure `DrawingPlanner`. It builds EA-08A drafts and provides one package-only
`planRetainedDrawingBorder` route for the explicitly retained EA-10E Border
workflow. That reuse moves no Border sequencing, motion, evidence, or outcome
authority into the draft runtime.

Preview is a projection, not evidence. It binds the exact displayed frame,
program content hash, and plan revision. Registration/configuration mismatch is
unavailable, outside-region planning is shown without clipped strokes, and
geometry outside tip applicability is explicitly diagnostic-only. It cannot
establish camera/ink attribution or physical evidence.

`PlotterDrawingDraftPaperPersistence` is the sole draft paper-store seam.
Production `PaperCoverageComposition` injects one nominal
`UserDefaultsDrawingDraftPaperPersistence`; an accepted LIVE assertion is not
published until save succeeds, and persistence failure returns an exact refusal
without installing the observation. The accepted paper polygon displays only
on the exact accepted frame. Currentness is separate: a newer frame in the same
paper/source/camera-configuration/contact-plane context remains current, while
paper, source, camera configuration, or contact-plane changes invalidate it.
SIMULATED assertions remain explicitly nonphysical.

The runtime serializes synchronization, revision validation, LIVE paper
persistence, and accepted publication through one FIFO mutation boundary.
Queued same-projection work is re-evaluated after an earlier suspended save
commits, so it receives a stale-projection refusal instead of overwriting the
accepted state. Scale requests outside the published range return
`invalidScale` without changing draft revision, placement, program, or plan.

The retained EA-08B run/evidence boundary still owns execution, Stop, camera,
Vision, archive, review, terminal no-redraw state, and the authorization to
clear that terminal before submitting `.beginNewPlan`. Draft mutation refuses
while that owner is active or terminal handoff is still required. Once handed
off, EA-08A publishes only an immutable plan. Before retained EA-08B can issue
Pen normalization or any later physical effect, it refreshes the complete
external facts and runtime snapshot and revalidates the exact plan again after
each suspension. A stale exact frame publishes the explicit retry remedy with
zero Pen, travel, drawing-plan, camera, Vision, observation, Stop, terminal, or
review effect. EA-08A itself never invokes machine motion, Stop, camera, Vision,
run evidence, or another physical effect.

The cutover deletes the combined `DrawingStudioAction`, direct
`performDrawingStudioAction`, direct open/close/paper-confirm actions,
`drawingStudioDraftMutationIsAvailable`, `rebuildDrawingStudioPlan`, direct App
`DrawingPlanner.plan`, duplicate mutable draft/rebuild authority, and the
`drawingPresentationTestFrame` fixture. Retained run actions now use
`DrawingStudioRunAction`, and later-package workspace fixtures inject the
production draft runtime rather than reconstructing draft authority.

The frozen accepted source identity is:

- `PlotterDrawingDraft.swift`
  `4171ee3d0a0064fb2e1fbcd7de426334395ae6a2415e51cc7421d0940a9e0b52`;
- `PlotterDrawingDraftRuntime.swift`
  `459e3f065ea75e003a5cf6c5ffc8b84477c61744ee396454752dc8263f95a060`;
- `AdaptivePlotterApp.swift`
  `cc5107ff6400b00033ddf2df5e026c9b48598b8321f75f05b1f0401ca22c723d`;
- `PaperCoverageComposition.swift`
  `c454b84edde46b250566d8fe14fd53a63730a6d308dffeb4e17af4729494b4f2`;
- `OperatorWorkspace.swift`
  `eec626a6fe14ddc34bafdf198b8d428e5a99452fd627d07ab46d6a2f570d23fb`;
- `DrawingStudioPresentation.swift`
  `15953c7002c624d2722bb77300e510cde9777a95ccc807983c713da914877c20`;
- `CompletedComparisonReviewPresentation.swift`
  `70f534d5c49fa3e098137cfdcc571708964b72c654c01c41af9d1d98505e1690`;
- `ActionSurface.swift`
  `f59257098e76e0a23cd2269cb8689f09ac91d0f48d8c10b872a69e6880a5e063`.

The frozen accepted test identity is:

- `PlotterDrawingDraftEpisodeTests.swift`
  `b26e2c1297fd1748eeb7a2e7f18882eb3116ab7fb3308844cd69384c699b4d00`;
- `ApplicationLifecycleTests.swift`
  `b77d9ed7102f2eea492ccf505daaa11319570460b2915b5a5e72f6e5f0fe3719`;
- `CompletedComparisonReviewPresentationTests.swift`
  `590e0361f4230c204ec63f9b3a39fb41cc1f695d7eedc8034f7e516bee5a3323`;
- `DrawingStudioPresentationTests.swift`
  `cc99960c7375fc0d5a045335b6e91af694cdb9563a31f11673c733c4da8aa8fc`;
- `OperatorWorkspaceAuthorityTests.swift`
  `e48ea8f3af841a93a630ac4c075f59dbbce1e9b47263415085c662ee81788128`;
- `OperatorWorkspaceComputationDiagnosticsTests.swift`
  `3663fb00ec5627e8369e9476dd0ce35bef5ac435a7fd2fe2eebb57dfdd0caf15`;
- `OperatorWorkspaceControllerAndBoundaryTests.swift`
  `83d14a2354979cb5b51b95f6b425567137a4c77ec7be2a8ec0ef35672c9b0985`;
- `OperatorWorkspaceLifecycleTests.swift`
  `a377b62ad2e38ee8dcb0785cd66b1b09dc7cd2990ec354a2bea6eb16cffdffe9`;
- `OperatorWorkspaceTestSupport.swift`
  `dc5f0ad336dd22d119f426cfa1ff94c786cfbd8f1d62767282177e6e32745ba7`;
- `SimulatorPresentationTests.swift`
  `873279f1f8b3b812dcb0db28761122732636a1e421958a50a6fb688d3e999ede`.

Changed source paths are the eight source files above. Changed test paths are
the ten test files above. Deleted test path:
`Tests/PlotterAppTests/DrawingPresentationTestSupport.swift`.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; 29/29 tests passed | documentation/checker contract |
| `DIFF` | passed — `git diff --check ac6a6688 --`; no output | whitespace/error diff check |
| `QUICK` | passed — `make quick-test`; 720/720 tests passed | repository quick suite; the earlier 718/720 run is retained nonpass history |
| `STRICT` | passed — `make strict-check`; 727/727 tests passed | strict-concurrency warnings-as-errors build, complete tests, stable local signing, launcher, negative-bundle, and documentation contracts; the compile-failing and interrupted earlier runs remain nonpass history |
| `DRAW-DRAFT` | passed — `swift test --filter PlotterDrawingDraftEpisodeTests`; 17/17 passed | typed prerequisites/refusals, revision staleness, deterministic identity, invalid-parameter nonmutation, FIFO paper-persistence isolation, retained Border adapter, preview/currentness, exact stale-run pre-effect revalidation, EA-08B handoff, and zero physical/evidence side effects |
| `DELETE` | passed — `sh Scripts/check_episode_cutover.sh EA-08A`; 4/4 zero-match scans passed | post-cutover exact zero-match scans; the stale-manifest first run remains nonpass history |

The first `DELETE` invocation failed only because the stale inventory still
required the deleted `DrawingStudioAction`; it remains nonpass history.

The sole fresh critic returned `RETASK`, not pass. It found three material
defects: a lost-update window across suspended LIVE paper persistence, retained
run admission from cached rather than freshly synchronized complete facts
before its first machine effect, and silent out-of-range scale clipping. The
correction serializes save/commit publication, rechecks exact facts and plan at
physical-effect boundaries, and refuses invalid scale without mutation. The
focused 17/17 gate includes deterministic regressions for all three findings.
The same sole critic's delta-only recheck ended exactly `UNANIMOUS PASS — no
material disagreement`. That pass closes criticism: all other dimensions stayed
closed, no new/full critic was commissioned, and no post-pass critic is allowed.
The first later `QUICK` run found two bounded presentation-diagnostic failures:
a closed Drawing Studio draft synchronization invalidated the Action Surface
after automatic Pen settlement. The owner now suppresses equal snapshot
installs and closed-to-closed draft invalidation. The affected computation
diagnostics passed 11/11 and `DRAW-DRAFT` passed 17/17 after that correction.
Per the bounded policy, this gate-found local correction did not reopen or
replace the closed critic; its exact delta and the subsequent broad gates are
reported separately. The first `STRICT` run then failed at compile time on two
redundant `#require` calls in the new live-facts test helper; removing only those
redundant unwraps left `DRAW-DRAFT` green at 17/17. A later full strict attempt
was interrupted after more than eight minutes without progress in an existing
manual-Stop test; that same test passed alone under strict flags in 1/1, and the
unchanged complete rerun then passed 727/727. The accepted broad results are
`QUICK` 720/720 and `STRICT` 727/727. No landing or cleanup pass is inferred from
the focused suites, critic pass, or broad gates.

Canonical routed-document dispositions for EA-08A:

- Affected — Episode Architecture Execution Plan and Current Evidence: current
  owners, retired App paths, exact identities, gate state, and staged EA-08B
  frontier.
- Affected — Swift Architecture and Product Contract: one draft runtime/sink/
  snapshot authority, planning/paper/preview boundaries, and retained run
  handoff.
- Reviewed no change — Document Routing (`docs/INDEX.md`): canonical routing
  and authority descriptions remain accurate.
- Affected — `Scripts/check_episode_contract.py` and
  `Scripts/check_episode_inventory.py`: staged completion, canonical seam
  families, candidate evidence, and conditional EA-08B frontier.
- Affected mechanically — `Scripts/test_episode_wave_capsule.py`: advance only
  the hard-coded post-landing frontier fixture from EA-08A to EA-08B. This task
  does not select or dispatch EA-08B.
- Reviewed no change — `Scripts/check_episode_cutover.sh` and other routed
  docs/scripts: their execution and routing contracts did not change.

The staged ledger mechanically derives EA-08B as the conditional post-landing
ordinary frontier because EA-08A is task-locally complete and EA-08B depends
only on EA-08A. EA-08B becomes eligible only after EA-08A lands through
Blackdog, canonical `main` is verified clean, and a
successor capsule is generated there. This task does not select or dispatch
EA-08B.

No attended physical controller, camera, motion, Pen, paper, operator-click, or
observed-ink validation occurred. No remote-Git action occurred. None is
claimed.

## Causal simulator environment cutover

Integrated 2026-08-28 in Blackdog task `TASK-6C2D055B`, attempt
`TASK-6C2D055B-4df3ee7abec3`. EA-07 landed and cleanup was verified on
canonical `main` at `ac6a6688`; package EA-07 is complete while migration
remains incomplete. No physical or remote-Git result is claimed.

The accepted production slice adds the sole effect-capable causal-simulator
environment seam, `PlotterCausalSimulatorEffectAdapter`, in
`PlotterEpisodeRuntime`. `admitManualJog` uses the shared
`PlotterIntent`/`PlotterEffect`/`PlotterEffectResult` grammar. Retained Boundary,
drawing, travel, and Pen work instead keeps its explicit
`EpisodeAuthorityID`, returns nil `effectResult`, and fabricates neither an
episode intent/effect nor a plan revision. The adapter retains the exact raw
simulator operation ID as immutable owner identity and settles natural
execution, exact Stop, cancel, shutdown, and original-owner wait through one
adapter-owned result.

One adapter actor keeps the active owner reserved after lower-runtime terminal
settlement until `publishTerminalOutcome` atomically caches one
`PlotterCausalSimulatorOperationOutcome`. That publication binds the exact
operation ID, observation, disposition, final MPos, completed Boundary count,
typed effect result when episode-attributed, and immutable plant/Pen/paper/ink/
camera/frame truth snapshot before releasing successor admission. A successor
therefore refuses until the predecessor outcome is cached, cannot contaminate
the predecessor snapshot, ink, or frame, and cannot be stopped by the settled
predecessor. The first terminal disposition remains idempotent for its exact
owner.

Pen ingress for manual and retained work uses that same adapter occupancy.
While a predecessor remains reserved through terminal publication, Pen ingress refuses
with `.operationAlreadyActive(predecessor.id)`, returns nil `effectResult` for
retained attribution, and does not call or mutate the lower Pen owner. When no
adapter operation is active, package-only
`SimulatedLearningRuntime.setPenPoseWithCausalTruth` performs the admitted Pen
mutation and captures its complete causal truth in the same lower-runtime actor
turn, so the response cannot be paired with later plant/Pen/ink/frame truth.

`PlotterCausalSimulatorTruthSnapshot` keeps commanded controller attribution,
plant MPos and Pen pose, paper identity and ink, camera configuration/viewport/
frame publication, Vision authority, and evidence classification separate.
Every typed result and observation is explicitly `.simulated`; Vision truth is
`notComputedBySimulator`, physical evidence is false, and the evidence notice
remains `SIMULATED — NOT PHYSICAL EVIDENCE`. Simulation publishes causal frames
but cannot manufacture a Vision measurement or establish attended controller,
camera, Pen, paper, click, ink, or other physical evidence.

The production adapter is the sole admission surface through
`admitManualJog`, `admitRetainedWorkflowBoundary`,
`admitRetainedWorkflowDrawing`, `admitRetainedWorkflowTravel`, and
`executeRetainedWorkflowPen`. `SimulatedLearningRuntime` now exposes only one
package-scoped causal-operation admission to the adapter and retains only lower
causal truth and exact operation settlement. The public effect-capable
`beginManualJog`, `beginBoundary`, and `beginDrawing` surfaces are deleted.
One `PlotterManualMotionRuntimeComposition` owns the manual runtime, lower
simulator runtime, and causal adapter; `OperatorWorkspace` receives that
composition and uses the exact same adapter authority for SIMULATED manual
effects, Boundary, drawing, supervised travel, sparse-tip execution, and
Drawing Border execution. Retained workflows without a target semantic package
carry an explicit retained-workflow owner with nil `effectResult` and no
fabricated plan revision. The adapter's lock-backed pacing authority affects
only future suspension policy and moves no effect identity or settlement
authority.

The same accepted cutover deletes
`OperatorWorkspace.executeSimulatedBoundaryMotion`, the former App-local
simulated manual-motion adapter, `SimulatedWorkspaceHarness`,
`makeSimulatedHarness`, `performPublicAction`, unused simulator helpers, and
tautological fake machine-action logs. App tests now traverse the production
workspace composition. Their `CausalSimulatorProbe` exposes only causal
snapshot, persistent-ink/truth reads, and explicit fault injection; it cannot
admit, execute, Stop, cancel, or settle an effect. The later-package helpers
`completeSimulatedBoundariesAndCenter`,
`completeSimulatedSparseTipCalibration`, and `completeSimulatedStageFour`
remain, with their internals adapted to the production seam.

The original critic returned `RETASK`, not pass. Finding 1 identified
that manual and workspace retained workflows were not proven to share one
production adapter authority; the corrected composition injects one exact
adapter and the focused authority regression exercises occupancy through both
call paths. Finding 2 identified fabricated episode semantics for retained
workflow work; the corrected retained APIs require explicit owners and return
nil `effectResult` without synthetic intent, effect, or plan revision. Finding
3 identified a lower-terminal/pre-publication admission gap; the corrected
adapter retains ownership through atomic outcome/truth publication and a
package-only `PlotterCausalSimulatorTerminalPublicationGate` deterministically
proves predecessor refusal, cached publication, and successor isolation without
sleeps or polling. The source correction also preserves one exact observation
across an adapter admission refusal and its manual-runtime mapping.

The same critic's correction-cycle-1 delta recheck also returned `RETASK`, not
pass: original blocker 2 remained because Pen ingress did not yet prove shared
adapter occupancy and atomic lower Pen/truth capture. Bounded correction cycle
2 addressed only that remaining blocker: the deterministic held-predecessor
regression exercises both a retained Pen refusal with no lower Pen/truth
mutation and the retained drawing refusal/successor path, then proves the
cached predecessor truth stays unchanged after release. The same sole critic's
correction-cycle-2 final verdict was exactly `UNANIMOUS PASS — no material
disagreement`.

The bounded policy permits one critic and at most two correction/delta cycles.
It forbids a post-pass critic, so the exact cycle-2 pass terminates criticism;
the original and correction-cycle-1 RETASK verdicts remain truthful nonpass
history.

The accepted source identity at correction-cycle documentation integration is:

- `AdaptivePlotterApp.swift`
  `9541e1ab283b3974ab0050737cc5a664575b1f144453e45e6acbfd9327c4734e`;
- `PlotterCausalSimulatorEffectAdapter.swift`
  `d1a8362644a6d6436e21e9876fa03e6d4df028f103f130b33f968d9c4e154365`;
- `SimulatedLearningRuntime.swift`
  `e190cb015a87e8970d90ade38112cedad7a3207432b6bc7eead573ca0e749072`;
- `OperatorWorkspace.swift`
  `f3c794b66825040b5aabf2dd26f49f6f2bfe4436edc7ec96f648dcc17f174366`;
- `PlotterManualMotionComposition.swift`
  `552783b72e04077075730f53bc6c5c6564c72f83622cbe83b82d54041db6aa36`.

The accepted test identity is:

- `ActionSurfaceTests.swift`
  `b7308effd860c5904ef61444ec4ae311a044b36c3761b1438e89b5c81fd985d9`;
- `LearningWorkbenchLayoutTests.swift`
  `c3c2bcfef0d14bfd487292aa7879b5b9f5558a3b94d10d7727d0ed3c85e82cee`;
- `OperatorWorkspaceAuthorityTests.swift`
  `9186c0f5815eac88b90c03cab4a0294d04518968a21d8c387a733a62a2e399eb`;
- `OperatorWorkspaceLifecycleTests.swift`
  `1fe1ecec5890283cc6e6d0c1ad5ecad215b42a7bceb63b7c2709f3d899502cfe`;
- `OperatorWorkspaceResetTests.swift`
  `56c7144c0281c99652041141fab0b47762e4b92b168cf7cfe9cb90eec821b01b`;
- `OperatorWorkspaceSparseTipCalibrationTests.swift`
  `d820b1ba921ec44d46c549c84c61369e3626e8e9b5fa95f5fb35c84c61a7dbdb`;
- `OperatorWorkspaceComputationDiagnosticsTests.swift`
  `b013f5eeae9d4ec02a53d24d305672028b20cf5fa0970f7933001bb1c00cf75d`;
- `OperatorWorkspaceTestSupport.swift`
  `d828936b3b73a432f28f563955da78446eeee15804440703e182c7590cddbc41`;
- `SimulatorPresentationTests.swift`
  `6e16a34b1bba95ce23dbd35ac2a8b0930085836c7866a0269eca576b763b7f04`;
- `PlotterCausalEpisodeEnvironmentTests.swift`
  `f5f4ff6a33b082fdd40d6a3d3591e2a4d58370884b7d57ac3904803af8588a61`.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; both contracts plus 29/29 documentation/checker tests passed | canonical documents, ledger/checker constants, routed review dispositions, and capsule contracts on the landed EA-07 tree |
| `DIFF` | passed — `git diff --check`; clean with no output | complete landed EA-07 tree |
| `QUICK` | passed — `make quick-test`; 705/705 passed | repository quick suite |
| `JOURNEY` | passed — `make journey-test`; 7/7 passed | retained simulated Learning journeys |
| `STRICT` | passed — `make strict-check`; 712/712 passed plus warning-as-error strict-concurrency build, signing, launcher, and negative-bundle checks | strict build, complete tests, signing, launcher, bundle, and documentation contracts |
| `SIM` | passed — `swift test --filter PlotterCausalEpisodeEnvironmentTests`; 15/15 passed | shared grammar and `.simulated` provenance, separated truth, exact owner settlement, Stop/cancel/shutdown, stale-owner isolation, retained attribution with nil effect results, atomic admitted Pen mutation/truth, held-predecessor Pen refusal without mutation, drawing successor isolation, paper/ink/camera, and ambiguity |
| `AUTHORITY-FOCUSED` | passed — `swift test --filter OperatorWorkspaceAuthorityTests`; 24/24 passed; correction evidence, not an additional EA-07 package gate | one shared production adapter authority across manual runtime/workspace retained paths, exact-owner occupancy and settlement, and existing workspace authority invariants |
| `DELETE` | passed — `sh Scripts/check_episode_cutover.sh EA-07`; current post-cutover run passed 4/4 | exact EA-07 deleted-symbol, fixture, environment-branch, and adapted-seam scans after staging the completed ledger row |

The first DELETE invocation is retained nonpass integration history, not a
passed gate; it failed only because the pending EA-01 manifest still required
the removed MOD-001 seam. The current post-cutover DELETE run passed 4/4.
All seven required EA-07 gates passed on its frozen integrated candidate before
landing. EA-07 then landed and cleanup was verified on canonical `main` at
`ac6a6688`.

No attended physical controller, camera, motion, Pen, paper, operator-click, or
observed-ink validation occurred. No remote-Git action occurred. None is claimed
by the simulator, software, or critic evidence.

Canonical routed-document review dispositions for EA-07:

- Affected — Episode Architecture Execution Plan and Current Evidence: retain
  the exact seven-gate results, both nonpass RETASK histories, the exact final
  critic verdict, and the verified `ac6a6688` landing/cleanup boundary.
- Reviewed no additional change — Swift Architecture and Product Contract:
  their current shared-adapter, retained-owner, atomic Pen/truth, terminal-
  publication, separated-truth, and nonphysical-evidence contracts already
  describe the accepted correction-cycle-2 source.
- Reviewed no change — Document Routing (`docs/INDEX.md`): its canonical
  authority descriptions and routing remain accurate.
- Affected — `Scripts/check_episode_contract.py`: retain final EA-07 gate/critic
  evidence and record the package as landed rather than a staged candidate.
- Affected mechanically — `Scripts/test_episode_wave_capsule.py`: advance only
  the hard-coded staged ledger/frontier fixtures from EA-07 to EA-08A; selection
  remains literal-order and this task does not dispatch the successor.
- Reviewed no change — `Scripts/check_episode_documentation.sh`: no canonical
  document inventory, vocabulary, routing, or stale-phrase rule changed.

EA-07's successor capsule was generated from clean canonical `main` and EA-08A
was selected in `TASK-5700F7F5`. That later package's task-local candidate is
the current section above.

## Episode manual-motion cutover

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
`TASK-FE9C9CB3-54834fa90e36`, and landed on canonical `main` at
`70057118669a570dd51eb10445b121b933a156da`; migration remains incomplete.

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
`@unchecked Sendable` authority escape. The former `MachineActions` closure
facade was retired by EA-11A; the nominal `PlotterMachineSession` lower port
does not own EA-06 admission, Stop, or settlement.

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
| `DOC` | passed — `make docs-check`; both documentation contracts plus 29/29 documentation/checker tests passed | `8986b9a8dc4091c34c32da507c6a29c0ebb54685067335f5641007868c26ce8d` |
| `DIFF` | passed — `git diff --check`; clean with no output | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `QUICK` | passed — `make quick-test`; 699/699 tests passed with exactly 10 configured exclusions | `6d9cc817581951b1ec9e024f9522e43337f81a6ff06bc4a90973efd7998c1794` |
| `JOURNEY` | passed — `make journey-test`; 10/10 filter-selected tests passed | `a4370968c633e28fbdb6685017c4c200f68eb5dd66be1efa876b378ad9fcc27c` |
| `STRICT` | passed — `make strict-check`; strict-concurrency/warnings-as-errors, 709/709 tests with no exclusions, both documentation contracts, and 29/29 documentation/checker tests passed | `06c6f7c1a5aef895850bedc4c502c8a0acf60aa7836d754e69225dd7c564f06a` |
| `MOTION` | passed — `swift test --filter PlotterManualMotionEpisodeTests`; 15/15 tests passed | `9aaa0b87c20d05ae3d98d3c5c9c50a79d00942547e3fafd2e7f93f637fdc873f` |
| `DELETE` | passed — `sh Scripts/check_episode_cutover.sh EA-06`; all 26 exact scans had zero matches | `b841daa4968ac8fa3bb03058663abc9e8fbcab9fd5d65487b6fb2aa786afb04e` |

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

This table is machine-checked against every `complete` row in the canonical
execution-plan ledger. Gate names match each package's required gates exactly,
and every recorded result is `passed`. EA-06, EA-08A, EA-08B, and EA-09 are
reconciled to their canonical-main landing commits rather than retained as
stale task-local candidates. FIX-03, DOC-03, EA-10A, and the task-local EA-10B
landing candidate have final completion evidence; GATE-01 remains pending after
EA-11C. Detailed scope and limitations remain in the named evidence sections.

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
| EA-06 | `TASK-FE9C9CB3` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `JOURNEY=passed`, `STRICT=passed`, `MOTION=passed`, `DELETE=passed` | Episode manual-motion cutover |
| EA-07 | `TASK-6C2D055B` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `JOURNEY=passed`, `STRICT=passed`, `SIM=passed`, `DELETE=passed` | Causal simulator environment cutover |
| EA-08A | `TASK-5700F7F5` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `STRICT=passed`, `DRAW-DRAFT=passed`, `DELETE=passed` | Drawing draft episode cutover |
| EA-08B | `TASK-51550DB1` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `JOURNEY=passed`, `STRICT=passed`, `DRAW-RUN=passed`, `DELETE=passed` | Drawing run episode cutover |
| EA-09 | `TASK-D55FD455` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `JOURNEY=passed`, `STRICT=passed`, `UI=passed`, `DELETE=passed` | Episode UI cutover |
| FIX-03 | `TASK-0A7AB3EE` | `DRAW-RUN=passed`, `TASK-METRIC=passed`, `DELETE=passed`, `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `STRICT=passed` | Pre-GATE-01 Drawing Run task-owner correction |
| DOC-03 | `TASK-B7C9E592` | `DOC=passed`, `DIFF=passed` | Pilot dependency-cycle correction |
| EA-10A | `TASK-539931AC` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `STRICT=passed`, `PEN=passed`, `DELETE=passed` | Pen Interaction episode cutover completion candidate |
| EA-10B | `TASK-6DAB256F` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `JOURNEY=passed`, `STRICT=passed`, `BOUNDARY=passed`, `DELETE=passed` | Drawing Boundary episode cutover completion candidate |
| DOC-04 | `TASK-A7C0E999` | `DOC=passed`, `DIFF=passed` | Capsule claim-classification correction |
| TRANCHE-LEARNING | `TASK-5C0B3F27` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `JOURNEY=passed`, `STRICT=passed`, `CRITIC=passed` | TRANCHE-LEARNING landed tranche evidence |
| EA-10G | `TASK-5C0B3F27` | `BUILD=passed`, `SPEECH=passed`, `AFFECTED-CONSUMERS=passed`, `DIFF=passed`, `DELETE=passed` | EA-10G landed authority-slice evidence |
| EA-10C | `TASK-5C0B3F27` | `BUILD=passed`, `CAMERA-CAL=passed`, `AFFECTED-CONSUMERS=passed`, `DIFF=passed`, `DELETE=passed` | EA-10C landed authority-slice evidence |
| EA-10D | `TASK-5C0B3F27` | `BUILD=passed`, `TIP-CAL=passed`, `AFFECTED-CONSUMERS=passed`, `DIFF=passed`, `DELETE=passed` | EA-10D landed authority-slice evidence |
| EA-10E | `TASK-5C0B3F27` | `BUILD=passed`, `BORDER-VALIDATION=passed`, `AFFECTED-CONSUMERS=passed`, `DIFF=passed`, `DELETE=passed` | EA-10E landed authority-slice evidence |
| EA-10F | `TASK-5C0B3F27` | `BUILD=passed`, `ARTIFACT-RESET=passed`, `AFFECTED-CONSUMERS=passed`, `DIFF=passed`, `DELETE=passed` | EA-10F landed authority-slice evidence |
| TRANCHE-DEVICE-ENVIRONMENT | `TASK-4C16F56F` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `JOURNEY=passed`, `STRICT=passed`, `CRITIC=passed` | TRANCHE-DEVICE-ENVIRONMENT staged completion transaction |
| EA-11A | `TASK-4C16F56F` | `BUILD=passed`, `SESSION=passed`, `AFFECTED-CONSUMERS=passed`, `DIFF=passed`, `DELETE=passed` | EA-11A staged authority-slice completion |
| EA-11B | `TASK-4C16F56F` | `BUILD=passed`, `OBSERVATION-CONFIG=passed`, `AFFECTED-CONSUMERS=passed`, `DIFF=passed`, `DELETE=passed` | EA-11B staged authority-slice completion |
| TRANCHE-FINAL-COMPOSITION | `TASK-FFD5D897` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `JOURNEY=passed`, `STRICT=passed`, `CRITIC=passed` | EA-11C final-composition staged completion transaction |
| EA-11C | `TASK-FFD5D897` | `BUILD=passed`, `COMPOSITION=passed`, `AFFECTED-CONSUMERS=passed`, `DIFF=passed`, `DELETE=passed` | EA-11C final-composition staged completion transaction |

## Wave admission blockers

This is the sole machine-readable list of Current Evidence conditions that stop
an otherwise dependency-ready pending selectable work item from launching. A row
must name the exact package, the observed blocker, and the required user input
or canonical correction. The selector stops at that first eligible row; it
never skips ahead to later work. An empty table means Current Evidence adds no
admission blocker beyond the canonical ledger and live Blackdog claims. The
former EA-10C standalone blocker was removed by the canonical tranche-policy
correction. `TRANCHE-LEARNING` landed, and
`TRANCHE-DEVICE-ENVIRONMENT` landed through `TASK-4C16F56F`, attempt
`TASK-4C16F56F-8af99cc51c68`, at
`3308e1bf2c19159be7b207226280f54b5ebf0662`, and
`TRANCHE-FINAL-COMPOSITION` subsequently completed through `TASK-FFD5D897`.
The active ordinary frontier is now `FIX-05`; `GATE-01` is dependency-ineligible
until that software correction completes, and no later successor dispatch is
authorized here.

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
undo, clear, four-point capacity, and the accepted batch. Historically for
EA-04, `SparseTipCalibrationCoordinator` retains machine-position association,
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
`UI.learningModePresentation` consumer was retained under inventory item UI-008
for the then-future EA-09 presentation cutover and owned no semantic or guard
authority. The current EA-09 candidate supersedes that direct consumer with the
aggregate `PlotterUIProjection` described above.

`PointSelectionPresentationContext`, its copied request/admission comparison, and the Task-returning app cancellation helper are deleted.
`submitCurrentPenCapPoint` and `OperatorWorkspace.awaitPenCapAcceptedClickTransition` are also deleted; focused tests use generic point submissions and bounded observable-state waits.
The app's
`frozenPointSelectionFrame` bytes remain presentation-only, while historically
for EA-04 `pendingToolContactEvidence` remains adapter data for the retained sparse-tip calibration fit. Neither is point-selection admission or accepted-evidence
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

At the EA-05C landing this Foundation service had no product or application caller
and was not a package product. It added no UI, app ingress, artifact store, filesystem adapter,
device port, `MachineLink`, controller/camera/Vision operation, effect execution,
permit, Stop/cancellation owner, recording owner, replay owner, journal owner,
evidence acceptance owner, or current-authority transfer. In particular, it
did not implement the then-later EA-09 UI request/progress/result presentation and
did not prove that referenced bytes exist or that any controller, camera,
motion, Pen, paper, click, or ink event occurred.

The current EA-09 candidate preserves that unbound assembler while adding the
bounded App presentation wrapper and truthful unavailable-source lifecycle
described in the first section; it still adds no export backend or physical
claim.

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
