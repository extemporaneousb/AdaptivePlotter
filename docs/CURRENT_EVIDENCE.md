# AdaptivePlotter Current Evidence

Status: current evidence ledger; software, simulator, controller, and attended
physical claims are recorded separately

This document records what was actually verified. Product meaning belongs to
[Product Contract](PRODUCT_CONTRACT.md), package ownership to
[Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md), and the physical
procedure to [Attended Hardware Runbook](ATTENDED_HARDWARE_RUNBOOK.md).

## Draw startup persistence, 2026-10-03

Task `task-fe80703bfcfc4b5ea9da58a26a443b50` removes accumulated-history JSON
encoding and media hashing from warm Draw admission. `PortraitCandidateStore`
now commits changed retention/attempt metadata and a compact checksummed index
referencing immutable candidate geometry, thumbnails and labels. The existing
`DrawingRunEvidenceStore` commits changed attempt/terminal/calibration components
and its compact manifest. The retained owners, admission policy, baseline capture,
possible-ink marker and synchronous durability requirement remain authoritative.
Verified bytes are reused only while their device, inode, size and nanosecond
modification/change timestamps match; changed or missing selected files are
reverified or refused. Healthy legacy archives upgrade during their existing full
asynchronous load. Catalog-only and synchronous Saved Learning reads remain
read-only; orphan component files never create execution or portrait history.

The final focused selection passed 70 tests in 6.843 seconds, including restart,
legacy upgrade, exact no-redraw truth, corrupt committed components, same-size
asset corruption with restored modification time, original-source retention,
explicit deletion/reimport and calibration evidence. The initial configured suite
failed; a retained diagnostic rerun found a stale verification identity after
explicit source deletion, preventing an
identical reimport from persisting. After compact-index commit, caches now retain
only selected records and assets; deleted values/file identities are released,
while missing still-selected assets continue to refuse replacement. The existing
deletion/reimport test and new warm missing-asset assertions pass.
The final configured docs-check, sequential quick-test and diff-check passed;
quick-test took 631.044 seconds. Its machine receipt did not retain test output,
so no full-suite count is asserted. The later ledger-only edit records the
external process exit observed during final inspection; runtime sources and the
signed executable remain identical to the validated build.
Opt-in benchmarks passed
against disposable APFS copies of the operator's actual archives. The final portrait
benchmark was repeated after the cache cleanup. With 3,099
portrait candidates, warm physical-attempt retention took 1.033 seconds and encoded
zero historical geometry bytes or verified historical asset bytes. With 34 Drawing
records and 15 attempts, a new small fixture's intent, baseline and possible-ink
commits took 0.065 seconds, encoding 22,225 component bytes and verifying only its
307,200-byte baseline. The marker did not hash that baseline again. These timings
include durable file/index publication in the debug build. The Drawing benchmark
ran with the existing app active; the final portrait benchmark ran after its
recorded SIGTERM exit. Neither measures camera acquisition, travel or first physical ink.

Cold verification/materialization plus legacy conversion took 513.592 seconds for
the portrait copy and 204.870 seconds for the Drawing copy. This is a substantial
first-upgrade cost and is not included in the warm timings. Cold archive integrity
checks remain required on later launches too. The new portrait index was 1,059,464
bytes after conversion; its immutable geometry and historical thumbnails were
preserved in referenced components. No production archive was converted by this
agent, and no history was pruned to obtain these measurements.

The strict-verified stable-local signed debug app is staged at
`.build/DrawStartup-fe80/AdaptivePlotter.app` with executable SHA-256
`d6c17cc92d23bb2b059c1edc3d640c3ea3a73b2a40f0dc536e6166d37ffa5731`.
It was not launched. The original executable still has its baseline SHA-256
`788131edad02cae52378d7d773643d7bfa05572375ceaaade8bfdd78467489c5`.
App PID 84511 was present during implementation but absent at final inspection.
Unified logs record signal-15 termination at 2026-10-03 01:11:33 PDT; the initiating
actor is unidentified. The agent issued no application stop/restart or replacement;
unbroken live-session continuity is not claimed. The earlier disk-write resource
diagnostic explicitly records no action taken. Native interaction, camera/controller behavior and physical
first-stroke latency remain unverified. Receipts are retained under
`.build/DrawStartup-fe80/evidence` in the primary checkout.


## Guided Learning and durable storage audit, 2026-10-01

Task `task-ce79e71f7e614cdf8005ff02b080a163` audited production Guided Learning
load/accept/retry/reset/paper/shutdown persistence, source acquisition and archive
publication, Drawing evidence/media ownership, and production path construction.
`AdaptivePlotterStoragePaths` now supplies the canonical existing paths to every
production composition/default store and diagnostic output. Accepted Learning and
Drawing evidence no longer silently substitute temporary storage. Current paths,
writer ownership, provenance, retention and historical directories are documented
in the canonical Swift Architecture storage map; this is no data relocation or
new competing persistence owner.

The existing checkpoint store now verifies and synchronizes content-addressed
copies of previous envelope bytes in `AcceptedArtifacts/History` before canonical
replacement or clear. History failure prevents the mutation; rejected bytes are
preserved for diagnosis too. History never supplies automatic live authority or
startup fallback. After Start New Learning, newly accepted prefixes are durable
instead of remaining session-only behind the old completeness threshold. The
former complete package remains archived. Boundary publication detects changed
or missing expected canonical predecessors and uses its existing recovery without
new motion. Inactive camera/tip descendants are not applied to the new session.

The existing portrait archive now independently commits each selected acquired
source with UUID/session/frame/time/selection metadata and verified source bytes,
even when rendering fails or is cancelled. It shares the existing asset namespace
with generated candidates; cache eviction and digital-candidate deletion preserve
committed standalone sources. Explicit source tombstones remove the dependent
associations before unreferenced cleanup, including aliases and late callbacks.
Missing standalone assets block destructive archive replacement. Bulk record
schema 2 prevents older readers from silently discarding this added metadata;
legacy bulk schema 1 remains readable. No operator archive was migrated by this
agent or by the staged application.

The initial focused selection passed 59 tests in 49.654 seconds. After the final
history/predecessor guards, 11 checkpoint/Boundary tests passed in 8.744 seconds,
including unchanged, foreign and missing canonical files. The final 34 photo/
archive tests passed in 5.844 seconds, including held-render cancellation,
provenance round trip, restart/cache eviction, source deletion and missing-media
write blocking. The configured docs, sequential quick-test and diff checks all
passed; quick-test took 714.293 seconds with `SWIFT_FLAGS=--no-parallel`. The
Blackdog command receipt did not retain output, so no full-suite count is claimed.
The subsequent evidence-only edit was checked again with docs-check/diff-check.

A read-only audit of the operator's current manifest verified its checksum and
687,920,028-byte referenced bulk record, 13 styles, and all 290 content-addressed
assets including 75 PNG sources. The current manifest is 14,120 bytes, schema 2.
The checkpoint, manifest, Drawing evidence and running executable hashes match
the task's baseline. App PID 68893 remained running with executable SHA-256
`e5a16843bf10f017a566cb0b21d2f6cf4494bd9456cc78888ca07fba85309aba`.
No debugger attachment, application replacement/restart, Learning application/
reset, machine command, controller/camera reconfiguration, archive pruning or
remote Git action was performed.

The strict-verified stable-local signed debug build is staged at
`.build/StudioTestApps/AdaptivePlotter-storage-ce79.app` with executable SHA-256
`543fdc5cfb43d62800c9180bb982875506020762791f00789a77471c24a57e86`.
It was not launched; these storage changes take effect in that new build rather
than the preserved running session. Native interaction, physical retraining,
controller behavior, cap reacquisition and new ink remain unverified. Receipts
are retained under `.build/StorageAudit-ce79/evidence` in the primary checkout.

## Portrait source visibility and pending Saved Learning preservation, 2026-10-01

Task `task-3490c8a646c440cdb659d37ca1c3bfe9` addresses missing visible source
photos and paper replacement before applying Saved Learning. The selected source
and its thumbnail browser now stay visible in the Portrait Studio inspector;
there is still one large drawing canvas and the existing Photos inspection popover.
The user's original archive checksum and all 72 original source PNG checksums
were verified. Its 2,278 candidates, 13 styles and zero tombstones remain intact;
this task did not rewrite or prune the archive.

The user confirmed replacing paper before accepting Saved Learning. The canonical
checkpoint directory was empty. The paper transaction previously cleared the
checkpoint whenever the live Learning graph was empty, including a valid package
awaiting operator acceptance. It now validates the frozen predecessor against the
persisted package and current semantic identity, rotates paper identity, and
preserves pending or declined state without applying Learning. Same-plane paper
retains all accepted components; a changed contact plane removes only tip and
Border suffixes. An incompatible or concurrently changed predecessor refuses the
transaction through the existing rollback path.

A retained older package was recovered with the production checksum, schema,
evidence and dependency-graph checks. Pen interaction, four Boundary sides and
center, pen cap appearance and the original reference frame were retained under
the current same-plane sheet identity. Camera registration, tip calibration and
Border were absent from that backup and remain unrecovered. The restored package
has seven graph revisions and is installed as pending Saved Learning, without
application or motion. Original backup bytes remain preserved under
`~/Library/Application Support/AdaptivePlotterRecovery/2026-10-01-photos-learning`.
Production read-back checkpoint equality passed; unordered-set serialization makes
the newly encoded staged and installed envelopes byte-different. This is partial
recovery, not restoration of the deleted latest full package.

The attempted LLDB memory read failed to JIT a Swift import, and the originally
running PID 64581 exited before recovery completed. This agent disrupted that
session; preservation of the original running session is not claimed. The exact
latest package was not recovered from memory. Persisted-state backups were taken,
and no motion, Learning reset or fabricated calibration was issued.

The focused selection passed nine tests in 44.420 seconds, including four pending/
declined and same-plane/changed-plane paper combinations, full saved-package
restoration, atomic persistence failure and hosted layout coverage. The eight
1000/1280-pixel layouts passed; a small-window source/thumbnail layout was visually
inspected. Their synthetic photo fixture proves layout only. The configured docs,
quick-test and diff checks passed with `SWIFT_FLAGS=--no-parallel`; quick-test took
730.623 seconds. Blackdog retained the command result but not its output, so no
full-suite count is asserted. The evidence-only ledger edit was checked again
with docs-check and diff-check.

The stable-local signed debug app passed strict signature and launcher bundle
validation. The previous executable was preserved in
`.build/PhotoLearningFix-3490/AdaptivePlotter-before-fix.app`, and the fixed app was
installed at `.build/AdaptivePlotter.app`. Its running PID 68893 has executable
SHA-256 `e5a16843bf10f017a566cb0b21d2f6cf4494bd9456cc78888ca07fba85309aba`.
The initial launcher wait exceeded 30 seconds; a bounded process sample identified
startup decoding of the 148 MB Drawing evidence archive. The app subsequently
reported finished launching. Activation and native capture could not be verified
because the macOS desktop was locked. The failed/blocked native receipts and
software receipts remain in `.build/PhotoLearningFix-3490/evidence`. No Saved
Learning acceptance, controller connection, camera reacquisition, physical motion
or new ink was exercised by this task.

## Portrait archive cold loading and trainable parameter policy, 2026-10-01

Task `task-f2fdf01ec6224ffd8be9ceff2822b998` addresses the first-open saved-style
failure beyond the earlier layout fix. The serialized archive owner publishes a verified
recipe catalog before bulk candidate materialization. The native menu is replaced by an
observable chooser with loaded count, loading/failure states and retry. Version-two index
manifests hold recipes plus the checksum of immutable bulk records under the same store;
normal successful saves upgrade legacy embedded indexes. Reads never migrate them.
Missing bulk geometry preserves committed recipe access and still blocks destructive
archive replacement. Source/raster reads are deduplicated and startup byte accounting
uses actual committed payload sizes rather than re-encoding all candidate geometry.

`PortraitParameterPreference` implements a bounded regularized binary model over shared
Detail/Tone/Smoothness/Minimum line coordinates. Only latest explicit promising/rejected
feedback supplies labels; an explicit unknown revision withdraws a duplicate proposal's
older vote. Renderer/producer, pose, pen/size/material, analysis and regional/advanced
context remain fixed. Flow evidence must carry the current sealed renderer revision.
Connected source/session/ancestry groups are separated for evaluation; class coverage,
minimum data and improvement over a prevalence baseline gate use. Parameter proposals
stay inside training-coordinate support and one in four requests retains baseline
exploration. The existing serial Next worker and two-render/novelty/material/cancellation
contracts remain authoritative. Successful learned attempts retain model/evaluation and
feedback/candidate identity receipts. This is parameter preference learning within
existing kernels, not a new stroke generator, physical-quality model or aesthetic proof.

A read-only inspection of the user's archive verified its checksum and found 2,278
candidates across 72 source groups, 13 styles, no rating labels and only one promising
attempt (2,277 unknown, no rejected attempts). The index is 812,057,076 bytes, about
774 MiB. The opt-in cold catalog test retrieved all thirteen recipes in 5.922 seconds;
size and modification time stayed unchanged. That legacy first-read cost remains until
an ordinary save commits the compact format. The actual archive was not migrated,
pruned or rewritten for this task. Its current feedback cannot activate the learner.

The expanded focused run passed 66 tests in 99.565 seconds, including existing archive,
exploration, legacy dataset/ordinal/checkpoint and hosted layout contracts. After the
withdrawal and renderer-revision guards, the final policy run passed five tests in
7.718 seconds, including actual Studio Next/worker integration and real vector paths in
both kernels. Tests cover independent holdout success/failure, sparse/related-source
fallback, observed-coordinate support, immutable recipe inputs, catalog access without
bulk records, corrupt-manifest retry and byte-exact legacy reads/upgrades. Offscreen
1000/1280-pixel workspace snapshots were inspected; their synthetic raster is layout
verification only. The initial configured validation passed docs and failed the default
parallel quick-test without retaining its output; that failed receipt remains recorded.
The first complete sequential selection caught one actual archive regression: absent
saved styles became an empty list. The manifest now preserves that optional encoding;
the corrected archive/policy/campaign selection passed 39 tests in 20.472 seconds.
The final configured command selection, using the supported `SWIFT_FLAGS=--no-parallel`
override, passed docs, quick-test and diff checks. Its 1,690-test selection passed in
677.311 seconds with twenty opt-in skips. Both failures and the final passing receipt
are retained; the default parallel gate is not reported as passing. The subsequent
evidence-only documentation edit was checked with docs-check and diff-check again.

Primary research was refreshed from APDrawingGAN, Chan et al., DiffVG, CLIPasso,
PortraVec v2, SwiftSketch and 2026 single-line optimization. The canonical Roadmap owns
the comparison and selected fixed-width curve experiment, including data, latency,
identity/age and material limitations. No research weights/datasets or external photo
upload were used. A stable-local signed debug test bundle is staged at
`.build/StudioTestApps/AdaptivePlotter-portrait-learning-f2fd.app`. It was not launched;
user-native interaction, real-photo aesthetic acceptance and physical plotting remain
unverified. Application sessions, camera, calibration, Learning and Drawing authority
were not reset or replaced.

## Portrait Studio parameter consolidation and saved-style cancellation, 2026-09-30

Task `task-8f1b66277d0946a99c83d337816cbb2e` keeps one portrait canvas with
separate parameter and navigation control sets. The persistent Parameters inspector
owns renderer selection, Saved styles/Save Style, facial feature scope, framing and
tuning. Saved styles have an explicit empty/loading state. Cancel keeps a fixed place
in navigation, and canceling a Next request or dismissing Save Style does not remove
saved recipes. The crowded, dynamically reflowing style/navigation row is removed.

New recipes carry versioned shared Detail, Tone, Smoothness and minimum-line values.
One resolver maps those values into both kernels using actual raster height before
material floors; cached Flow layers and direct vectorization use the same resolver.
Style switching retains common coordinates and regional edits. Next varies the same
coordinates; regional Next freezes global intent. Historical recipes retain exact
bytes and interpretation until explicitly edited. Retained legacy training rejects
shared recipes rather than reading inactive low-level fields. Obsolete per-renderer
preset helpers now live only in legacy test fixtures. The native performance probe
uses shared Detail/presets rather than the removed inspector toggle.

The final serial focused selection passed 61 tests in 91.895 seconds. It covers
actual path changes in both kernels, cached/direct Flow equality, resolution scaling,
recipe round trips, cancellation with held/late completion, retained navigation,
regional sampling and legacy training/checkpoint behavior. Production and isolated
hosted layouts passed at 1000×550 and 1280×650; small-window snapshots with saved
styles and whole/feature controls were visually inspected. These are offscreen test
hosts, not attended pointer/keyboard or signed-app interaction evidence. The exact
configured quick selection passed sequentially: 1,681 tests in 668.705 seconds,
with 19 opt-in skips. The recorded configured run failed at the parallel quick gate;
a retained parallel rerun completed the same 1,681 tests with 14 issues in seven
untouched recording, speech, telemetry and Drawing-recovery tests. One eight-second
watchdog took 44.572 seconds. All seven then passed together in parallel in 1.540
seconds without the full workload, and also passed in the complete sequential run.
No deadlines or those subsystems were changed. The full parallel gate remains a
contention-sensitive validation limitation; it is not reported as passing. The
Blackdog receipt and retained logs record that distinction.

Read-only inspection of the default archive verified its envelope checksum and found
13 saved styles (8 Contour, 5 Flow Edge), 1,851 attempts across 69 source groups,
no rating labels and one promising attempt. Its index occupies roughly 642 MiB.
Those are recipe seeds and mostly unlabeled examples, not a validated preference
dataset. The Roadmap records matched-budget recipe comparisons, attributable choices,
source-grouped evaluation and compact metadata/asset-index work as conditional future
work. Existing archive files were not migrated, pruned or rewritten.

The final debug executable was packaged with the local development identity, its
bundle validated, and its staged copy passed strict signature verification at
`.build/StudioTestApps/AdaptivePlotter-portrait-controls-8f1b.app` in the primary
checkout. No live app launch/restart, camera/controller interaction or physical
drawing was performed. Real-photo likeness, actual age/expression, pen separation,
native click-to-paint performance and physical quality remain unverified.

## Selected paper working region and visible placement controls, 2026-09-26

**Edit Drawing Region** in the existing Exercise 1.4 preview stages a paper
working rectangle inside the learned machine Boundary. It retains the displayed
frame for body movement and independent corner resizing. **Default** stages the
full Boundary; **Smaller** reduces each span by 20% about the center, stopping at
25 mm. Apply/Cancel settles the edit without adding Learning. Four 2 mm-radius
circles have centers 10 mm inside the selected extent, leaving 8 mm edge clearance
and at least 1 mm between adjacent circles at the minimum size. The cap-only
projection explicitly remains approximate while the tip offset is unknown.

Video Settings separates **Reference frames** from Vision and simulator
diagnostics. **Machine Boundary** and **Drawing Region** independently default
on; simulator diagnostics default off. The v2 preference migration retains
previous cap/armature choices. The normal region outline represents the full
admitted paper working extent, or the historical drawable extent for older
registrations. It does not stack artwork, paper-coverage and persistent inset
calibration rectangles. Actual circles remain in the relevant calibration
preparation/review, and the actual Border plan and evidence remain retained.
Reference-frame visibility requests no Vision work and changes no geometry,
plan, accepted coverage or ink authority.

**Position Drawing** remains discoverable with a concise unavailable reason.
It temporarily replaces the paper-extent outline with the artwork frame and
**Artwork positioning · frozen video** caption on a retained exact frame. Body drag moves artwork;
corner drag uniformly resizes about its fixed center. Apply/Cancel restores the
full paper outline plus independently placed artwork strokes. Fit and the Size
limit now use full geometric containment without an implicit 90% margin;
unplaced Portrait reference padding and calibration sample locations remain
separate. **Fit Machine Boundary** and **Show Full Video** use the existing
viewport state, respect edit/frame/context locks and never run automatically.

New sheet confirmation requires the full admitted region to be visible and no
pending region/artwork edit or reopened Exercise 1.4 preparation; the owner also
refuses cached submissions after
visibility changes. Hiding a guide preserves existing coverage and does not
independently block Drawing. Paper attestation is still bound to the current
sheet, exact displayed frame and compatible registration. The smaller artwork
frame is never silently substituted for a larger invisible coverage target.

The existing tip owner admits one immutable region/plan for preview and marking.
Stale context, active marking, retained clicks/review and possible ink prevent
replacement or automatic redraw. The explicit v8 estimator recovers its selected
outer extent from the accepted observed-center domain; later Border v3 uses that
exact domain. Historical v3-v7 registration geometry and planning interpretation
remain unchanged. The full machine Boundary is still travel authority; the
working extent bounds paper/artwork, and its outer 10 mm band does not expand
observed tip applicability or permit attributable camera/ink evidence.

Low-reasoning research preceded delegated source/test and documentation/evidence
work. The coordinator independently reviewed the final owners, geometry,
compatibility, presentation and paper-assertion guards. The user-authorized base
integration retained the landed Boundary session fix and its evidence entry.
The broader sequential focused selection passed 84 tests in 61.217 seconds,
including four gated render skips. The final presentation/admission/render
selection passed 39 tests in 10.163 seconds; a subsequent test-only retained-frame
render correction passed its single test in 2.365 seconds. Coverage includes
visibility migration, independent toggles, current/cached paper refusal, preserved
plan and coverage identities, full Fit/Size, context-bound viewport focus,
selected-region geometry, restoration and affected Saved Learning lifecycle cases.
Settings, normal/hidden reference layers, artwork positioning and calibration
PNGs were visually inspected. Backed labels remain legible on white paper;
hiding both guides retains the exact photographed ink/cap and planned artwork.
The positioning PNG is a production overlay composite, not a native gesture.
The episode architecture contract check passed.

The combined-tree configured serial run exposed one computation regression:
Exercise 1.4 rebuilt the Learning projection 22 times where its unchanged test
requires two. Cheap registration/active-owner guards now short-circuit before the
heavy projection getter; geometry, admission semantics and test expectations were
unchanged. The computation diagnostics, frame-reference presentation and working-
region selection passed 30 tests in 12.033 seconds, including three gated render
skips, with the original two-build assertion passing. The failed full-run receipt
and raw output remain retained separately from the subsequent verification.

A stable-local signed debug app was built; its bundle validator and negative
bundle-validation tests passed without launch. Configured verification runs
`make docs-check`, `make quick-test` with `SWIFT_FLAGS=--no-parallel`, and
`git diff --check` in an exclusive Swift window. Retained machine receipts bind
those outcomes to the combined source tree, and raw Swift logs retain names,
skips and failures. External bundle provenance records executable/signature
identity. Replacement of the primary app bundle is a separate delivery action
whose installed identity is verified outside this tracked ledger.

The agent did not launch the app, reset Learning or perform live camera/controller
operation. Offscreen rendering, owner tests and build receipts do not establish
native pointer behavior on live video, physical paper coverage, pen travel or ink.
Installing the new UI does not retrofit a smaller extent into saved v7 Learning.

## Boundary session mismatch and operator diagnostics, 2026-09-26

A reported Y+ repeat attempted to pool a new controller session into a retained
Boundary history from another session, at the same coordinate revision. Read-only
capture preserved the integrity-checked four-side Saved Learning checkpoint and
controller recordings. The recorded jog ended with Idle/final MPos; the subsequent
history compatibility exception had been mislabeled as motion ambiguity, blocking
Learning reset and exposing a nested internal error in the operator surface.

Side admission now checks the complete retained Boundary prefix's controller
session and coordinate revision before Pen Up or motion. A mismatch retains all
accepted artifacts and returns an explicit reset remedy. A side result rejected
during aggregate/checkpoint construction after verified Stop is a settled refusal;
actual lower ambiguity, center-position uncertainty and incomplete publication
keep their existing guards. No automatic replay, evidence relabeling or Learning
step was added. Boundary presentation uses concise operator messages while exact
typed refusals and terminal diagnostic details remain retained.

The 55-test sequential Boundary/checkpoint/presentation selection passed, including
normal/replacement/additional context mismatch, unchanged same-context repeat,
invalid-geometry rejection after verified Stop, production Saved Learning to
Reset All, and suppression of long diagnostics in instructions and button help.
A genuine lower ambiguity still refused Reset All with concise text. Documentation
checks passed. The first configured run caught a missing-map guidance regression;
the corrected code retains the specific physical-position recovery instruction.
A separate Saved Learning test passed for both Unknown and Down pen states. Nineteen
tests that failed during a parallel run while another checkout compiled all
passed in an isolated serialized rerun; the failed receipt remains retained.
An exclusive parallel rerun reproduced seven of those failures, so concurrent
compilation does not explain them by itself. Final configured validation uses
serialized Swift tests and is retained in the task machine receipts alongside
the failed parallel attempts.
A stable-local signed debug app was built without launch. The running application,
Learning files and hardware were not reset or actuated by the agent; native
interaction and a new attended physical Boundary pass were not performed.

## Movable artwork frame within the learned Boundary, 2026-09-26

Ordinary Drawing now derives an artwork frame from the program's authored field
extent and existing `DrawingPlacement`. **Edit Frame** retains the displayed video
frame, exposes body movement and four corner handles, and stages a uniform resize
about the fixed center. Apply submits the existing exact-frame Draft intent.
Shared geometry constrains the complete rectangle to the learned machine Boundary;
Fit can use that full Boundary. Center includes authored margins. The optional
**Draw frame** composes this placed rectangle before artwork in the same plan.
The fixed 10 mm calibration Drawing Border, Learning sequence, full-Boundary paper
assertion, tip applicability and no-redraw authority remain unchanged.

Low-reasoning research established the existing owners and border geometry before
implementation. Sources/tests and canonical docs/evidence had separate delegated
owners, and a separate read-only review accepted the final geometry/runtime and
presentation-session changes. No new Learning step or paper-region workflow was
introduced. Frame editing only retains already-displayed pixels; unique session,
lifetime and context guards prevent cancelled or superseded asynchronous starts
from restoring stale video. It neither captures a new camera frame nor changes
authored placement before the existing projected Apply request. Pending or staged
frame edits exclude Draw through existing application projection and ingress;
cached starts are refused, and pending/active Draw excludes an edit start. This
keeps a staged preview from executing an older applied placement and retains the
existing Stop path. The final guard received separate read-only review, and its
59-test sequential Draft/presentation/workbench selection passed, including the
pending/staged/Apply/Cancel/active-run regression and exact-frame cancellation.

The focused sequential selection passed 98 tests, covering rotated and sheared
camera responses, all-corner containment, offset-preserving body drag, each resize
handle, whole-Boundary Fit, asymmetric authored margins, frame-first composition,
strict invalid-placement refusal, exact-frame Apply from unsealed advancing video,
unchanged paper coverage and existing execution/no-redraw behavior. A subsequent
pending-start cancellation regression passed independently. All 10 retained
Learning/Boundary/drawing journeys passed. The production overlay rendered offscreen
with four correctly projected handles and a separated caption; that dedicated test
passed and its PNG was visually inspected. Configured validation is recorded in
the task's machine receipts on the final source tree.

The larger frame exposed two existing observation limits in full-suite fixtures.
Artwork or its optional inked frame fitted to the complete machine Boundary can
execute successfully while remaining outside retained tip applicability and
producing a non-attributable result. The full-resolution dense-crosshatch fixture at full fit detected 52,522
pixels across 191 segments and reached the unchanged 5,000,000-evaluation observer
budget, retaining `association-budget-exceeded` rather than attributable ink.
These limits do not change the machine Boundary or add Learning. Calibration
applicability and observer budgets are preserved; the raster fixture retains its
positive observation workload at an explicit smaller Size. A 12-test follow-up
passed the full-fit preview, two-sheet execution/non-attribution, unchanged-budget
rejection and smaller dense-raster positive cases.

A stable-local signed debug bundle was built and its signature/bundle contract
validated without launch. The running user app, camera, controller and physical
session were preserved. Gesture-helper, runtime-owner and offscreen-overlay checks
are software evidence; native pointer interaction against live video, physical
placement accuracy, pen travel and resulting ink were not exercised. Existing
outside-tip-applicability limitations remain explicit even for Boundary-valid plans.

## Drawing progress and completion presentation, 2026-09-26

Drawing publishes every settled stroke independently of the quarter-run photo
schedule and displays a determinate completed/total-stroke bar. The run snapshot
exposes its retained execution disposition while evidence is appending, so Drawing
done remains distinct from move-clear positioning, capture and durable publication.
A read-only inspection of the current run's retained final photo showed its vertical
carriage still covering the portrait: the nearest-tip-clearing pose was above the
drawing. New versioned observation plans park at the lower accepted Y boundary and
the X boundary with greater lateral clearance. Historical plans retain v1 validation.
The existing Pen-Up run and evidence owners retain motion and capture authority. A durable post-positioning photograph displays Final photo saved;
a fallback completion photograph, failed repositioning/capture, Stop and failed
publication remain distinct visible outcomes.

The focused sequential debug selection passed 60 tests. Coverage includes versioned
legacy-plan validation, bounded corner parking and clearance shortfalls, progress
publication on a non-photo final checkpoint, done-before-photo-save presentation,
execute/fallback-photo/travel/post-photo/append ordering, changed-fact refusal,
Stop during acquisition, and exact-byte publication-only recovery. Documentation
and diff checks passed. A stable-local signed debug bundle was built and validated,
then staged without launch. The existing live app and physical run were preserved;
native interaction and physical clearance at the new park target were not validated.
The full configured suite passed before the parking adjustment; final parking
validation is scoped to the planner, archive, run, capture and presentation paths.

## Shared portrait exploration controls, 2026-09-26

Removed Contour/Explorer mode state. Both kernels now expose Previous/Next and
feature selection; Contour and Flow Edge buttons reset canonical recipe parameters
while retaining source framing and material. Advanced edits the same regional fields
as sampling. Either end of retained navigation can request a fresh sample; navigation
within retained history remains exact and render-free. One serial owner and at most
two renders per request remain. Ordinary authored upper bounds no longer masquerade
as material floors. Regional requests replace that scope's settings, use fresh seeds,
and compare visible geometry within retained landmark support. Old stacked recipes
keep their original interpretation until a scope is edited; point and material
constraints remain enforced. The two rendering kernels are still discrete.

The focused debug selection passed 25 tests, including actual-kernel sequences,
parameter corners, canonical resets, exact navigation, cancellation, historical
recipe geometry and hosted layouts. On a retained analytic landmark fixture, 24
successive eye/face requests accepted 23/21 changes for Contour and 24/24 for Flow
Edge. The last twelve requests accepted 12/11 and 12/12 respectively; each recipe
retained one regional entry. Unique stroke geometries were 19/21 and 24/24. Mean
request times were 560/654 ms and 313/516 ms in DEBUG, excluding native painting.
A separate 24-step whole-portrait analytic workload accepted 24 Contour, 20 Flow
Edge and 23 Sketch changes; late halves accepted 12, 10 and 11. Preparation ran
once per session, and retained back/forward navigation performed no rendering.
This second selection and the updated hosted-layout checks passed.

Hosted snapshots were inspected at 1000×550 with Advanced closed/open; layout
assertions also cover 1280×650 and feature controls. These are analytic software
and offscreen-host observations, not before/after speedup, real-photo aesthetic,
live-session or physical drawing evidence. The running app and hardware were not
restarted or exercised. Configured release validation is recorded separately in
the task's machine receipts.

## Portrait Studio sampling cleanup, 2026-09-26

Removed the unused style-comparison queue/context, grid slots/rounds, adaptive
preference direction, previous-option fallback, live offered-set traces and
production prototype selector. One serial queue now owns current rendering and
one explicit Next request with at most two attempts. Back/Forward retain bounded
exact candidate stacks. Historical exploration receipts remain validated and
preserved through archive load, retention and save. Prototype recipes remain only
as renderer test fixtures; saved recipe values keep their existing interpretation.
Ordinary authoring no longer computes a sampling footprint. Next compares geometry
off the main actor. The native performance harness now targets existing adjustment
presets instead of deleted algorithm tiles; that live harness was not run.

The focused serial SwiftPM selection passed 265 tests, including source replacement,
late cancellation, pending Back, deletion, exact rejection suppression, frozen
region scope, archive preservation, material adaptation and immutable Drawing
handoff. Full validation passed 1,627 tests serially. Parallel runs hit timing failures
in untouched speech, recording and telemetry tests; those passed serially. External-photo
and opt-in native checks were skipped. The task receipt retains the validation evidence.

The analytic 480×640 fixture in DEBUG measured cold first renders of 1.15–1.84 s
and twelve warm Next requests of 0.31–1.47 s across Flow Edge, Contour and Sketch.
Each Next used at most two renderer calls; source analysis ran once per style
session. Back plus Forward installed exact geometry in 0.14–0.28 ms without
rendering. These are model/worker timings, not a controlled before/after comparison,
real-photo quality or native click-to-paint measurements. No live app launch,
camera/controller interaction or physical drawing was performed.

## Single-canvas Portrait Studio, 2026-09-26

Studio now shows one portrait, with Contour and Explorer modes, an optional
adjustment inspector, and separate Photos/History popovers. The three-choice grid,
large duplicate preview, permanent thumbnail rail, rendered style comparison and
prototype row are removed. Contour is the starting renderer. Explorer preserves
the selected renderer and requests one useful variation per Next action, with at
most two render attempts. It stops after selection; opening Studio, changing modes,
and navigating retained results do not start another batch. Failed single-step
similarity probes are transient. Existing archived attempts remain unchanged.
History is a virtualized text list filtered to the current source, with All photos
and Kept only filters. Back/Forward install exact retained payloads synchronously.

Targeted browser checks passed for idle mode entry, bounded Next demand, exact
Back/Forward, cancellation against late completion, exhausted search, transient
similarity probes and edit-driven branch invalidation. The five-test fixture run
measured roughly 0.15 ms average retained navigation installation per step, excluding
painting; it proves neither real-photo rendering latency nor native click-to-paint
performance. The existing 20-test exploration selection and 17-test comparison
cancellation selection passed. Hosted production and isolated workspace layout
checks passed at 1000×550 and 1280×650, in both modes with optional adjustments;
small-window snapshots were visually inspected. Strict AX interaction tests were
not enabled in this host. Full configured validation is retained in the Blackdog
task receipt.

The existing running app (PID 44173) was identified as a debug build. Its unified
log from 09:04:20–09:08:05 PDT contained 96 completed renders: mean total latency
1,136 ms, median 802 ms and maximum 3,168 ms. The 110 render starts had median
queue wait 296 ms and maximum 2,661 ms. Publication averaged 8 ms; 42 retained
history selections installed in median 0.51 ms, maximum 1.04 ms. These are observed
pre-change timings, not a controlled comparison or click-to-paint measurement.
They support removing unsolicited render demand without attributing all delay to
main-actor selection. The running app was left running. No
camera, controller, paper, calibration or physical drawing check was performed.
Renderer aesthetics are unchanged; likeness, perceptual usefulness and new-variation
latency remain unverified with real portraits. An optimized signed build is a
software artifact, not evidence that the operator's running session was updated.

## Portrait Studio redundant-work cleanup, 2026-09-25

Archive saves validate every candidate, but install/verify each shared asset once
per save and return the committed byte count instead of re-encoding the archive
for accounting. Label ancestry checks use ID lookups. Studio selection, history,
feedback and preview composition avoid repeated scans and temporary collections;
the unused pose-slot accessor and unreachable photo-preview branch are removed.
Sketch thinning counts neighbors without filtered temporary arrays. Drawing
scale/rotation commits skip unchanged values.

The focused serial SwiftPM selection passed 57 tests, covering archive corruption
and deletion recovery, exact retained byte counts, shared-asset re-verification,
authoring cancellation, browsing/history and retained-plan preview ownership.
The external-reference-photo test was not enabled. These are software receipts,
not measured native speedup, aesthetic quality or physical plotting evidence.
The user-owned running app was not replaced or restarted.

## Persistent Studio attempts and regional prototypes, 2026-09-25

The coordinated implementation adds reusable source preparation, durable attempt
history and three regional prototype recipes under the existing Studio and Drawing
owners. Prepared sources retain oriented decoded pixels, source-coordinate landmarks,
full-frame person-mask outcomes and multiscale luminance. Crops reuse that preparation;
area-integrated sampling has explicit preprocessing v2 provenance, with historical v1
rasters still readable. Source and crop-specific Flow retention have independent
payload byte/count bounds. Worker results expose source/crop/Flow/vector timings.

Applicable completed candidates retain exact source/raster/recipe/program data and a
thumbnail through the existing archive. History selection is neutral and installs
retained geometry without rendering. Plus/minus revisions mark individual attempts;
rejected proposal identity is specific to source/pose/recipe/material. Save Style
retains a reusable recipe and Save Imagination remains separate library qualification.
Session Back remains bounded and is not a restart-persistent undo promise. Existing
retained frames, including older saved sources, are available through Source/Photos,
and each finished alternative can be published before the pair completes.

Sparse structure, Angular comic and Measured eye exaggeration compose measured facial
supports, selective stroke removal/retention, angular contours, fixed-width shadow
or contour construction and bounded 2D expansion around measured eye centers. The
third prototype uses disjoint compact supports without inferred pose or forehead;
legacy semantic-head pose requirements remain unchanged. Missing reliable
landmarks preserve base strokes with an unavailable reason. Skin and jaw support do
not claim hair/clothing segmentation or reconstructed depth. Stroke counts and
normalized path length expose geometric burden without inventing physical duration.

The coordinator independently inspected source/cache/provenance and archive/selection
diffs, returned anti-aliasing and deletion defects for correction, and rejected an
initial cramped hosted layout despite its assertions passing. The corrected 1000 × 550
workspace retains equal useful comparison previews and visible history with Styles
and Adjustments expanded; source browsing lives in the Source/Photos popover.

| Receipt | Result and scope |
|---|---|
| Source/cache, browser and compatibility selection | 62-test run passed; includes all 9 reusable-source tests for cross-crop/resolution reuse, unavailable analysis, area filtering, coordinate mapping, byte eviction, failed-render reuse and cancellation |
| Earlier browser/history, regional/eye and archive selection | 57-test run passed, including 14 history regressions and legacy archive goldens |
| Retained-photo prototypes, hosted layout/routing and exploration performance | 7-test run passed in 107.477 seconds; two opt-in AX/input cases were skipped |
| Retained-photo eye-deformation proof | Two measured supports applied at amount 0.3; identical recipe with that modifier absent has different actual geometry; 5,065 baseline versus 5,079 resulting points |
| Corrected benchmark oracle and retained-photo proof | 2-test run passed in 43.339 seconds; the three prototype program hashes match the accepted visual receipt |
| Corrective browser/material and compatibility selection | 40 tests passed in 29.412 seconds after the full-suite diagnostic identified four failing cases; includes all four cases, 14 history regressions, modifier round-trip and semantic archive checks |

The corrective review restored ordinary rendering's existing `headScale = 1` and
`semanticHead = nil` behavior while retaining the separate eye modifier. Updated
integration assertions distinguish automatic unknown attempts from saved rows and
verify selected-work priority with cancelled/reconstructed reference work. The original
failed required-check receipts and diagnostic assertions remain in the delivery
manifest; the final full configured result is recorded there against its source tree.

These selections overlap and are not a unique test-total claim. The retained reference
source SHA-256 is `d66e8251b20ca9cbedf6d3a200c281276089f518de19182da1a65902828f457c`.
The three DEBUG renders contain respectively 359, 394 and 360 strokes, with normalized
path lengths 22.06, 27.57 and 23.42 drawing heights. The coordinator observed distinct
stroke treatments and a modest eye change; this establishes digital operation, not
operator approval of likeness, age/identity, usefulness or physical execution. Earlier
legacy semantic-head attempts on two retained photos lacked measured pitch and retained
the explicit refusal. The new measured-eye capability leaves that guard unchanged.

The corrected DEBUG Flow Edge benchmark uses the same retained photo at 316 × 320
analysis pixels, with 24 provenance aliases of its full source/raster/program preloaded
(328 strokes, 10,049 points) and 38 attempts retained by the end. Across 24 exact history
installs, model time was 0.063–1.517 ms; feedback mutation took 0.197–0.706 ms and Back
0.405 ms. Navigation required no rendering. Four warm rounds published their first
alternative in 495–2,012 ms and pair in 1,251–2,319 ms, with at most one worker and
one cold analysis call. The cold selected drawing took 3.483 seconds. These are
software model/publication timings, not native click-to-paint measurements. The
roughly 0.5-second first-alternative and 2-second pair targets are not consistently met.

The corrected MainActor heartbeat maximum was 15.681 ms. Earlier 323–336 ms peaks
included a heavy benchmark geometry oracle on MainActor; those superseded receipts
are retained, and moving that test-only oracle off MainActor did not alter product
code. No receipt captures or explains the reported minute-long interaction. Native
click-to-paint against the <100 ms target, AX/input interaction, real-portrait
usefulness and attended ink/time evidence remain unverified.

Full configured validation results and delivered-bundle identity are recorded in
Blackdog task `task-dae292fbd4974396a585eab73c40ad3c` and its preserved delivery manifest;
this chapter reports the focused, hosted-visual and measurement receipts above.
The running user app, cameras and plotter have not been restarted or exercised by
this implementation. A packaged build is not native interaction or physical proof.

## Pen-cap capture lifetime and Guided Learning preservation, 2026-09-24

Read-only inspection of the user's DEBUG app (PID 77543), native screenshot,
diagnostic exports, SQLite trace copy and twelve exact raw acquisitions is retained
privately at `/Users/bullard/Projects/AdaptivePlotter/.build/PenCapCleanup-f69b3683/`.
`retention-manifest.json` binds copied files to their original paths and hashes.
The failed acquisition shows the user's hand covering the cap; the visible tape
in the other eleven frames satisfies the existing size and complete-visibility
checks. Offline replay preserves those eleven detections and the occluded refusal.
This evidence does not justify weakening detection or calling a predicted position
an observed cap.

The event trace contains both a one-circle tracking failure and a later completed
four-circle batch. The latter reached fourth-click fitting, then reported
`cancelled`. The currently stranded cap recapture had accepted its click while
retaining its owner and frozen frame. Source review identified the shared cause:
the SwiftUI selection `.task(id:)` could cancel its own downstream submission when
accepting the click changed that task's identity. This defect predates the visual
reference redesign; reverting that redesign alone would retain it.

Point submissions now have application lifetime with explicit cancellation and
deduplication. Capture Pen Cap is one independent action, including with Learning
off. Capturing while a completed four-dot batch awaits clicks or review suspends
and restores that batch, its exact frame, accepted clicks and original owner.
Each cap capture also receives its own production image-recording store; cancelled
and refused selections remain inspectable without mixing the original batch's
recording stream or event offsets.
Compatible cap appearance replacement retains mechanical learning and optical
calibration; incompatible anchor or optical context invalidates only the optical
suffix outside such a suspended batch. An incompatible capture inside the batch
is refused without destroying it. Same-plane paper replacement preserves learning.
A physically different pen can still change tip offset or contact depth; a cap
click alone is not evidence that those physical relationships are unchanged.

During settled cap acquisition, missing or ambiguous observations clear the
consecutive-sample window and continue searching newer frames under the same
cancellable Vision lease. Three new consecutive actual observations are required
before continuation. Stop remains explicit; camera stalls, changed optical context
and unavailable analysis still terminate. Marker association uses the mapped
expected position when available, otherwise the last compatible observed or clicked
position. A distant similar object cannot take over after an occlusion. Compact
neutral markers with strong local background contrast are also supported; these
are synthetic image-fixture results, not physical validation of arbitrary pens.
Before camera calibration, a small marker moving beyond its bounded neighborhood
may still need recapture.

The running app and hardware were preserved throughout investigation and delivery.
Post-change native interaction, physical movement, contact depth and ink remain
unverified until an attended run of the new build.

## Sampled-marker recovery and tracking latency diagnosis, 2026-09-24

The user-reported slow Locate session ran DEBUG code (PID 52189). Stale Locate
prose remained over an active sparse-tip attempt; this does not establish an
infinite Locate deadlock. Read-only
native/process evidence and a bounded copy of seven exact raw acquisitions plus
reference/options/controller-context metadata are retained privately at
`/Users/bullard/Projects/AdaptivePlotter/.build/MarkerRecovery-70ef7fc5/`.
`retention-manifest.json` binds the copied files to original `/tmp/plotter-locate-active`
and `/tmp/plotter-color-reassessment` paths and SHA-256 hashes. Six retained
Camera acquisitions succeeded; the sparse-mark acquisition rejected template
score 0.748 against 0.820, despite a 0.168 competing-match margin and a 5.63-pixel
prediction residual. These are actual template diagnostics, not proof that an
operator click or every possible marker was invalid.

The reference was 23×98 pixels, sampled to 8×32. The template's scan stride was
one pixel and its prediction did not reduce full-frame search. A smaller patch
therefore does not automatically imply less computation. Retained successful
records put the cached caller-context timestamp 4.666–5.187 seconds before the
selected raw frame; these intervals include acquisition/workflow work and are
not isolated matcher durations. Detector execution timing was not present in
those older manifests. Cached controller position/pen state is not an independent
frame-synchronized physical measurement.

The user explicitly requested DEBUG compilation to avoid optimized-build cost.
App and packaging defaults remain DEBUG; any new timing comparisons must identify
that build configuration. The investigation prioritizes algorithmic work and
bounded acquisition rather than substituting a release build for a code fix.

The integrated DEBUG focused run passed 52 tests, including sampled-marker
selection, legacy/marker recovery and reload, actual camera-generation binding,
exact-frame diagnostics and bounded recording. A final profile-directed scan-loop
change passed 20 marker/replay/legacy-vision tests without changing classification.
The raw corpus accepted all seven frames for each of three analyst-selected
interior seeds, including the previously failed lower-frame BB9 acquisition.
Multiplying raw RGB by 0.7 and 1.3 shifted its centroid by 0.184 and 0.110 pixels;
these synthetic gain changes do not cover arbitrary lighting or physical poses.

Final DEBUG marker analysis on the seven retained 1080p frames measured
0.326–0.425 seconds, median 0.388. The earlier same-frame unchanged single-template
baseline measured 3.243–3.403 seconds, median 3.371; its six successful detections
and one failure are preserved. This is approximately an 8.7× median computation
improvement, not camera FPS or end-to-end workflow latency. The template baseline
had one appearance per frame; a two-view live bank was not benchmarked. Detector
sampling and full-frame competing-component checks remain intact. Scalar policy
equivalence tests cover the hot-loop rewrite; no release compiler flags were used.

Controller raw-I/O association, retained in `frame-controller-association.json`,
places each frame after an Idle/MPos report without intervening movement commands.
BB9's report is `(798.759, -92.014)` only 89.161 ms before capture, unlike its stale
cached context. This supports offline reported-position comparisons, not independent
physical ground truth. The existing user app remains running; a fresh inspection
found the console locked, so post-change native/hardware behavior is unverified.

A subsequent lifecycle regression exposed a separate bootstrap defect: live raw
preview was available while the analyzed `displayedFrame` was nil, so deriving
tracking optics from analyzed output could prevent the first admitted analysis.
The app now derives optical identity from the admitted latest live camera frame
under the existing selected-camera, plotter and LIVE-source guards. First-frame
and source/configuration/layout changes refresh optical binding directly; only
an invalidated ROI performs full analysis reconfiguration. Ordinary frames add
neither operation. The final integrated targeted run passed 122 tests, including saved-marker
first-frame automatic-analysis bootstrap after a real session restart, newest-frame
and stop races, recovery, overlays, and success/failure/cancellation settlement.
The ten retained causal journeys also passed. After making the diagnostics
fixture wait for startup synchronization before resetting its baseline, all 67
diagnostics/startup targeted tests passed with their original cache invariants.
The pipeline owns the retained
latest submitted raw frame and retries it when optics become available only if
no newer frame has been admitted under the new configuration; stop clears it.
A repeated two-test probe also reproduced duplicate initial configuration and
subscription creation (`subscriptions=2`, `configurations=2`), rather than slow
scheduling. The optical-only refresh above removes that extra full configuration.
All 47 diagnostics/recovery/pipeline/lifecycle tests and twenty fresh-process
repetitions of both affected methods passed afterward, without widening budgets.
This finding is software evidence, not a diagnosis of the preserved user session. Full-suite fixture failures and their
corrections are retained in the private delivery report without changing gates.

## Holder tracking and native reidentification diagnosis, 2026-09-23

Pre-change native evidence is under `/tmp/plotter-cap-20260923-dedup/` and
`/tmp/plotter-cap-repro-{baseline,after-cancel,after-reidentify,final}/`. These
private host artifacts are copied with original paths and SHA-256 into
`/Users/bullard/Projects/AdaptivePlotter/.build/HolderRecovery-4becf32a/`;
`retention-manifest.json` records the copy provenance. They are not committed
test fixtures. Process
37172's fresh diagnostic export matched its process identity and verified raw
BGRA bytes; the first raw SHA-256 is
`9e0e150ec6910d02de90e95c9016b5584a58aa203d4bbc19dbef06349845732c`.
The original inspector saw distinct parent/child Export Diagnostics AX wrappers
and refused to export. A disposable inspector selected the unique deepest
matching button for this capture. Production traversal now keeps leaf matches,
deduplicates identical AX references, and refuses independent matching leaves or
truncated traversal; it does not select a globally deepest unrelated button.

The authorized native reproduction accepted Cancel (transition 32), Reidentify
(33), then Cancel (34). Reidentify displayed its anchor instruction, but the
Learning panel still said Exercise 1.1 Complete with a disabled, checked Accepted
button; Draw Reference/Reset View were obscured by the drawing overlay text.
The exported camera frame changed between the immediate and three-second samples
while selection was active. Final cancellation returned to Exercise 1.4 with
Reidentify enabled. Machine ledger sequence remained 7820 throughout; the last
controller operation had completed Idle and Stop was disabled. No anchor was
submitted, no calibration was replaced, and no new motion or ink occurred.
This reproduction establishes the old UI/export failure, not physical accuracy
of a newly selected fixed holder.

`/tmp/plotter-cap-20260923-corpus/manifest.json` retains eight hash-verified
1920×1080 BGRA point-selection frames and an extracted current persisted visual
reference. The manifest does not assert that this reference was active at every
frame, and frame records lack controller-pose and pen-state ground truth. This
corpus and the older cross-pose corpus are offline regression inputs, not proof
of robustness across all pen colors, dense blue ink, or Pen-Up/Down poses.

The retained analysis-only crop experiment is in
`HolderRecovery-4becf32a/holder-tracker-experiment/findings.md`. A compact holder
corner crop accepted the seven other current-session frames while the whole
crosshead crop rejected five. Analyst-selected anchors/crops are not operator
ground truth; original failed acquisitions and Pen-Up/Down labels remain missing.
No claim of universal crop robustness or physical calibration follows from this.
Three optimized replay runs of copied current production matcher/coarse sources
with attributed DEBUG dependency objects retained the same scores. Across the
eight-frame corpus, compact-crop time had median 0.238 seconds (0.212–0.256),
while the broad crop had median 0.075 seconds (0.073–0.078). This isolates the
optimized matcher; it is not release-app end-to-end latency or camera cadence.
Source/object/compiler attribution and per-frame timing are retained under
`HolderRecovery-4becf32a/plotter-holder-optimized-probe/`.

The implementation adds explicit rigid-holder reference purpose and a separate
current-capture binding that preserves original acquisition provenance. It adds
bounded exact acquisition diagnostics and resolves
on-demand exports from the actual frozen-or-ambient canvas. Numeric candidate
scores, immutable reference bank, priors, search hint and raw analyzed pixels
remain paired for subsequent failures; unavailable pose/pen facts remain unknown.
No post-change attended physical validation is claimed in this entry.

## Off-center Camera recovery and cross-pose cap audit, 2026-09-22

Evidence is retained privately under
`/Users/bullard/Projects/AdaptivePlotter/.build/CapDoomloop-013f5b/`.
`initial-investigation-manifest.json` and `matcher-retention-manifest.json` bind
copied inputs to their original paths and hashes. The live application PID 26672
was inspected read-only and left untouched. Its on-disk executable hash differs
from the prior staged build; that alone does not identify the mapped process's
source revision.

The controller trace ends at the Camera sample-five pose, Y -14.903, while
the accepted center is Y 9.093; the user reported cap loss. No original cap-failure
diagnostics were retained, and no camera map was accepted.
The old retry requires fresh MPos at that center, while completed Boundary refuses
a second center-acceptance operation. Its generic Camera error then incorrectly
prescribes cap reidentification. The earlier recovery regression prepared Camera
Redo but did not execute the subsequent off-center calibration run, so it did not
establish a complete recovery path.

The unchanged matcher was rebuilt in DEBUG and replayed directly against five
retained raw 1920×1080 BGRA frames using the current 33×79 reference and independent
clicked anchor. Three earlier upper-pose frames scored 0.81129–0.81438, below the
unchanged 0.82 gate; two lower-pose frames scored 0.99518 and 0.99982 and were found.
An approximate visual hint produced the same rejected upper-pose candidates. The
reference's spatial contrast is about 56/255, well above the reference 8/255 and
candidate 4/255 contrast gates. The visual-reference branch does not apply the
legacy HSV color-support gates or an absolute brightness cutoff. Global ambiguity still
requires a 0.06 margin; prediction is a refinement seed, not a search boundary.

`matcher/findings.md`, the original build/source attribution, raw input manifest,
replay logs and crop comparison preserve the full analysis. The upper/lower crops
show changing relative projected geometry of the blue cap and red holder; a tall
whole-region match can favor the holder and displace the clicked anchor. This
supports retaining independently confirmed views before the first map. It does
not justify lowering thresholds, narrowing global search, or calling the current
reference universally robust. A local diagnostic ROI found higher-scoring but
visually displaced anchors, reinforcing that a passing score alone is inadequate.
The previous operator reference and exact originally rejected acquisition were
not retained together, so this is cross-pose evidence for the current reference,
not reproduction of that original detector decision. Single-run DEBUG replay
costs of 2.27–2.44 seconds per frame are not a repeated performance benchmark.

The subsequent coarse-correlation optimization removes repeated accumulator
copying and iterator overhead while preserving candidate order, scores and gates.
Three-run DEBUG medians for one, two and three reference entries changed from
2.465/4.854/7.199 seconds to 1.441/2.798/4.185 seconds, about a 42% reduction.
The additional entries are constructed duplicate views for cost measurement,
not physical multiview recovery evidence. Complete results match across all nine
paired bank runs and all five raw frames with and without a hint. A three-entry
match still takes about 4.19 seconds; this does not establish real-time tracking.
Original and optimized source/build attribution and result hashes remain separate
in `matcher/` and `matcher-optimization/`. The final strict focused matcher run
passed 17 tests (`matcher-optimization/matcher-after-tests.log`).

The strict workflow regression run passed 30 cases without failures or skips
(`recovery/focused-run4.*`). Its production request/controller fixtures execute
the first-camera sample-five loss, reidentify without motion, published Return
Pen Up to Accepted Center, five-sample Run and acceptance. They also cover stale
cached position, historical pose proof, Stop and authority changes during Pen-Up
normalization. These are software/controller-fixture results; they do not prove
physical recovery or native interaction with the new controls.

No live camera capture, controller command, physical movement, user-store write or
new ink was used for this audit. Workflow fixtures and final validation/bundle
receipts belong to this task's durable evidence directory; claims from the prior
recovery task below retain their original scope.

## Pen-cap recovery, search cost, and retained camera canvas, 2026-09-22

The evidence directory is
`/Users/bullard/Projects/AdaptivePlotter/.build/CapRecovery-b457429d/`.
All artifact names below refer to that durable local directory. Private retained
camera inputs are in its ignored `replay-inputs/` subdirectory; the source tree
contains no copied private camera images. `retained-evidence-manifest.json` maps
original paths to copied artifact hashes without relabeling benchmark inputs.

The camera canvas selected its simulation fallback whenever the ordinary camera
frame exceeded the one-second freshness limit. Exact calibration deliberately
holds preview publication, but the application's camera snapshot need not receive
the hold diagnostics before that age expires. The corrected presentation keeps
the exact same camera source and image while showing the owning operation's hold
status, or a last-frame qualification for ordinary stale delivery. Freshness
admission and exact-frame leases are unchanged.

Redo and Record Another now propagate preparation refusal/failure instead of
reporting a prepared attempt after a silent early return. Point-selection
submission awaits its sampling/save result, and awaited start/restart retains
shutdown cancellation precedence. Same-anchor Reidentify offers one
click with the previous rectangle offset, validates settled Idle/Pen-Up and
current context, and can retain compatible accepted calibration and observation
lineage. Residuals within the map domain have an eight-pixel compatibility gate;
outside it, operator-confirmed recovery records an extrapolated/advisory residual
while preserving the original map/domain and granting no new motion authority.
This distinction is necessary for the retained incident: the failed tip pose
(857.267, 118.383) lies outside its local camera-map rectangle
(x 743.698–803.698, y -43.24–16.76). Those coordinates are recorded controller
units, not independently measured physical millimetres. Replace Pen Cap Reference
is the explicit optical replacement path. Settled possible-ink failure permits
observation recovery while retaining mark exclusions and the no-redraw boundary.

The template matcher now uses vectorized coarse correlation over the same global
search grid and accepts a predicted position as a refinement seed. Prediction
never excludes a global competitor or resolves ambiguity. Weak and ambiguous
results retain candidate bounds/anchors, threshold score, competitor margin and
prediction residual. Same-anchor operator confirmation can retain the current
appearance and two prior compatible examples, each with its own anchor/crop;
there is no adaptive update or pixel averaging.

Saved-frame DEBUG replay measured the selected-frame median at 7.121 seconds
before and 1.373 seconds after; the calibration-frame median changed from 6.899
to 1.395 seconds. A final repeat measured 1.208 and 1.253 seconds respectively.
The observed one-reference range is approximately 1.2–1.4 seconds versus about
seven seconds, with identical unhinted anchors and scores on the retained inputs.
Prediction-seeded replay changed the calibration anchor slightly (about 0.29
pixels from the retained expected anchor versus about 0.14 pixels unhinted);
both passed the declared 0.75-pixel replay tolerance. Hint seeding is not an
exact-baseline-equivalence claim. A maximum three-reference bank measured
medians of 3.586 and 3.608 seconds for those two frames. Independent examples retain the global ambiguity checks and
require additional work; this is not real-time tracking performance.

These are three-sample local DEBUG comparisons, retained in
`cap-matcher-baseline-replay.log`, `cap-matcher-after-replay.log`,
`cap-matcher-after-final-replay.log` and `cap-matcher-bank-replay.log`.
The input/source hash manifest is `cap-matcher-replay-manifest.json`.
The focused matcher/reference/replay/pose tests passed 16 tests in 20.1 seconds
(`cap-matcher-tests.log`). The comparisons establish reduced matching cost
in this build, not release performance or end-to-end responsiveness. A final
clipped-reference diagnostics correction passed 14 focused tests in 3.501 seconds
(`cap-matcher-clipping-tests.log`). Both single-reference and confirmed-example
searches retain an explicit clipped-support rejection reason even when score and
margin pass. `cap-matcher-final-diagnostic-source-snapshot.json` records this later
diagnostics-only source change separately from the benchmark source hashes. The
rejected frame from the attended loss was not persisted, so this replay does
not reproduce that visual failure or prove shadow robustness.

The final focused recovery run passed 50 DEBUG tests in 38.807 seconds
(`adaptiveplotter-recovery-final50.log`). Its causal LIVE-mode fixture loses
the cap after two circle requests, preserves exactly two excluded mark locations,
releases operation/Stop ownership, and exercises capture, cancellation and the
successful one-click same-anchor recovery without further motion. It preserves
the original camera-map domain and visibly qualifies extrapolated residuals;
a nine-pixel residual outside that domain is accepted as operator evidence,
whereas the same residual inside the domain refuses calibration preservation.
The suite also covers malformed scope rejection, historical-map revalidation
and reload, settled Pen-Up requirements, truthful competing-action refusal, and
successful/failed new Camera acceptance superseding/retaining recovery lineage.
These are production-path software fixtures with fake controller boundaries.
An expanded strict focused run passed all 56 tests in 49.510 seconds
(`recovery-regression-strict.log`), including shutdown cancellation and a valid
projection-bound direct click that verifies accepted reference and actual Pen
workflow continuation. The broader run exposed both integration cases; the
corrections preserve truthful awaited results and the original cancellation
assertion, rather than returning success before sampling completes.
A subsequent strict run passed all 35 selected UI/episode/recovery tests in
3.679 seconds (`pen-ui-scheduling-strict.log`); all 20 Pen episode tests then
passed three serial repetitions in 1.420, 1.459 and 1.517 seconds. A diagnostic
had identified a fixture submitting a captured request after controller and
observation runtime revisions changed, then waiting indefinitely for admission.
The test now renders and submits on one MainActor turn, polls bounded read-only
test-gate state, and verifies that stale refusal produces no admission or motion.
This preserves the production freshness guard; it does not claim that native
clicks can never receive a stale-request refusal. Diagnostic and repeat event
streams are retained beside their logs.

The focused camera-composition/canvas run passed all 11 DEBUG tests in 1.002
seconds (`cap-recovery-preview-tests-3.log`). It exercises the production
CameraCapture → CameraSourceSession → application stable-cap path through
success, failure and cancellation while a deliberately expired camera clock
and an unrefreshed pause snapshot reproduce the original presentation trigger.
The source, frame identity and no-fresh-admission qualification remain intact;
all leases settle and ordinary video resumes. Hosted native WorkbenchCameraCanvas
renders in all three cases also assert that the CGImage provider bytes equal the
held stamped frame. The three `cap-recovery-canvas-*.png` snapshots contain the
same fixture image and a legible camera-calibration hold caption; no simulation
surface appears. This is native view rendering with a synthetic camera driver,
not an attended live camera or pointer-interaction test. The initial helper
compile error and a subsequent concurrent-source-edit build invalidation were
resolved before this passing frozen-source run.

The final source builds as DEBUG with complete Swift concurrency checking and
warnings treated as errors. `make validate-app` passed stable-local signing,
launcher logic/refusal checks and app-bundle negative validation
(`cap-recovery-strict-app-final4.log`). The separately staged `AdaptivePlotter.app`
passes strict code-signature verification and remains unlaunched. Its executable
SHA-256 is `3fffb14c311b4188d142d853ea691059840fd4b497fb92f6b78457ef06f8d71d`.
The prior primary `.build/AdaptivePlotter.app` was not replaced. The initial
configured strict test compile rejected a pre-existing unnecessary `await` in a
cancellation test. Removing that test-only await preserved all concurrency gates;
all test targets then compiled strictly and all 14 focused tip-episode tests passed
(`strict-tip-focused.log`). The failed first receipt and compiler diagnosis remain
retained separately. Final configured validation receipts, full-suite counts and
the final source manifest are retained in the same evidence directory so their
recorded tree can remain unchanged.

The previous running application PID was absent during inspection; no live stall
profile was collected. The user's camera/controller session and Learning stores
were not altered, and the app was not launched or replaced for these checks.
Software fixtures and retained images do not establish physical reacquisition,
shadow robustness, optical accuracy, or attended calibration success.

## Pen reference input and video navigation, 2026-09-22

Ordinary bugfix in `task-e982e07ef715452187f0218d88b9c2b8`.
An editable Drawing preview previously admitted the reference-rectangle drag but
silently blocked the following cap click. LIVE sampling failures were stored in
`discoveryError` but omitted from the main actionable-error surface. Reference
selection also consumed every video drag, and integer rounding discarded small
pan deltas at high magnification. These are source-supported defects; the retained
live camera recording does not identify which particular pointer event failed.

Exact point selection now takes priority over Drawing placement. After drawing
the reference, drags pan without changing its camera-pixel coordinates;
**Redraw Reference** returns to rectangle editing. **Pan Video** is available
before selection, and Drawing movement requires **Move Drawing**. Invalid clicks
and the active runtime's rejection appear beside the video prompt. Fractional
pan displacement accumulates until visible, with excess motion discarded at
frame edges. Existing analysis locks, exact-frame identity, reference detail
requirements and physical authority remain in force.

All 47 focused DEBUG tests passed. Coverage includes cap selection with an
editable Drawing preview, pan between rectangle and anchor, slow fractional
drags, edge reversal, a LIVE-mode application fixture surfacing reference
rejection without motion, dark-blue RGBA/BGRA capture and translated reference
tracking, and a low-detail rejection followed by successful same-frame retry.
Blue/dark pixels do not require green in the reference path; sufficient spatial
detail is still required. An independent source review found no blocker.

The user-owned running application, camera/controller session, Learning and
recordings were left intact. Synthetic frames and application fixtures are
software evidence; actual mouse arbitration, this physical blue cap and attended
tracking were not tested. The corrected app is built in DEBUG for separate staging.

## Stable style references and additive Flow support, 2026-09-22

Ordinary maintenance and style-space extension in
`task-05f881eb38504b0288017ad24706c867`; all measurements use unoptimized DEBUG.

The Styles panel now freezes its three exact candidates for a source context
(photo, pose, framing/background analysis, material and pen), independently of
trajectory selections and vector edits. The context exists before the disclosure
first opens. Completed tiles and in-flight reference work survive neighbor,
Current, Back and manual tuning; source-context changes invalidate them. Selecting
a tile installs its displayed candidate. Reference completion cannot replace
newer authoring intent with the same render key but different lineage. Global
Cancel explicitly revokes publication/reuse while the single worker settles.

Four optional normalized Flow parameters extend the common recipe: tonal evidence
support, structural persistence, evidence scale and deterministic seed irregularity.
Absent/zero values preserve prior recipe bytes, provenance and geometry. Scale
remains saved while inactive. Structural persistence filters original detailed
curves using broad support with a strong fine-feature exception; tone support
separately gates shading and trims unsupported tails. Neither infers facial anatomy.
Spacing constraints remain shared by organic, mixed and rectilinear strokes.

Evidence uses three fixed spatial scales, individually prepared only when needed.
Exact-scale requests build one level; intermediate scales use two; at most three
levels remain per source. Raw structural curves have a separate two-entry cache,
so support and scale changes can reuse extraction. Kernel border indices and
bilinear coordinates are reused without changing arithmetic order. Both real-photo
six-variant comparisons retain exact program hashes and all three reference-sheet
PNG byte sequences before/after these optimizations. The front legacy five-recipe
sheet also exactly matches the preceding task's retained PNG.

On the front/profile photos, first support activation fell from 1434/1756 ms to
559/777 ms. Its evidence preparation fell from 1270/1496 ms to 399/497 ms. A
structural-support edit fell from 404/543 ms to 236/377 ms. Warm combined support
was 165/270 ms. A previously unused scale still incurs preparation once (the
scale-1 edits measured 634/856 ms); this is deferred work, not zero-cost scaling.
No release compilation or optimization flags were used.

Policy v4 adds the new active dimensions, excludes dormant scale from effective
comparisons, and probes distinct parameter configurations before rendering. It
retains two attempts per alternative, at most four actual renders per round;
there is no elapsed-time cutoff. Versions v1–v3 remain readable. Different
parameters can still produce similar geometry and fall back to labeled history.
Both 48-operation real-photo walks retained two usable alternatives, one cold
analysis and one worker. Excluding five Back actions, front/profile generation
medians were 1072/1113 ms; 19/43 and 2/43 rounds offered no fresh proposal.
These traces do not demonstrate improved fresh-option yield or end-to-end speed
relative to v3. Program-hash novelty includes parameter provenance and is not
perceptual novelty. Avoided style-panel renders are verified independently by
stable-tile identity and renderer-call tests.

Visual review shows reduced weak hair/clothing texture at stronger structural
support, with prominent facial edges retained. The structural layer still
dominates these photos; sparse controlled variations are not evidence that
likeness or aesthetic exploration is solved. Temporal motion remains unimplemented:
the short burst retains one selected image, not registered multiple frames.

The initial 120-test focused run passed, followed by 17 ownership/hosted-layout
tests, 54 renderer/ownership/Drawing checks and 34 final lazy-renderer checks.
Both final local-photo workloads passed. Coverage includes old recipe-byte
compatibility, exact candidate round trips, independent support layers, bounded
lazy caches, material spacing, tiny images, cancellation/restart, stale-context
rejection and same-key lineage ownership. Hosted layouts and scrolled support
controls were inspected at 1000×550 and 1280×650. Configured repository results
are recorded in this task's machine validation receipts using the same DEBUG
build with `--no-parallel --skip-build`.

The signed DEBUG app is staged without launching it; bundle and launcher
validation receipts are retained with the evidence. No source archive, running
app, camera, plotter or physical ink was changed/exercised. Artifacts are retained
in the primary checkout under `.build/PortraitParameterEvidence/task-05f881eb/`.
Native pointer/keyboard interaction and physical acceptance remain untested.

## Debug Flow performance, resilient preferences and line forms, 2026-09-22

Ordinary maintenance and bounded style extension in task
`task-b279ed48af90465b94f7e6b81a4c91f9`. All production and test measurements in
this entry use the default debug configuration, without optimization flags.

Clicking Current during pending exploration previously canceled generation and
turned unfinished slots into Unavailable. That action now preserves the pending
work. Proposals account for material floors and quantized parameter effects before
rendering; bounded recovery changes direction and responds to empty geometry.
Similarity exhaustion and renderer failure have separate labels. Compatible,
visibly distinct history candidates can fill exhausted slots as Previous option;
they are never represented as newly generated alternatives. Back, source changes
and cancellation retain exact candidate ownership. Policy revision v3 still reads
v1/v2 records.

Flow caches bounded source evidence, structural paths and orientation fields.
Fixed kernels preserve arithmetic order while reducing allocation/index overhead;
structural graph links use fixed bitmasks. Preview comparisons use bounded bitsets
with tests against the old Set semantics. Candidate construction, hashing and
preview preparation now run on the tracked worker, including cached restoration.
There is still at most one render worker. No speculative precomputation was added.

On the same retained front portrait, the original four-round interaction workload
fell from 3180–6376 ms (median 3341 ms) to 698–984 ms (median 912 ms). Search
proposals differ under v3, so this measures the same interaction sequence rather
than identical candidate recipes. A controlled renderer comparison used the exact
original five recipes: density edits fell from about 1500 ms to 180–201 ms, and
coherence edits to 533–552 ms. The five-panel comparison PNG has exactly the same
SHA-256 before/after, as do its stroke/point counts. Cold analysis plus the initial
candidate fell from 3019 ms to 2226 ms; initial Vision analysis remains substantial.
Contour and Sketch did not show comparable round-speed improvements.

The 48-step front-photo walk retained Current and at least one alternative on
every step, with one cold analysis and at most three renderer calls per step.
Its median was 519 ms, maximum 1508 ms, including exact Back/cache actions; the
worker-path heartbeat maximum was 13.3 ms. Of 94 offered alternatives, 58 were
labeled history fallbacks and 36 were proposals. Fifteen alternative program hashes
were first seen in this walk; hash novelty is not perceptual or aesthetic novelty.
The four-round harness also performs expensive comparison assertions on MainActor,
so its heartbeat gaps are not clean live-application responsiveness evidence.
The second retained photo completed another 48-step walk with Current and at
least one alternative on every step: 387 ms median, 1611 ms maximum, nine history
fallbacks among 95 offered alternatives, and a 15.5 ms worker-path heartbeat
maximum. Its four-round Flow median was 738 ms. Both photo workload suites passed;
there is no second-photo before/after speedup claim.

Flow Line form now offers Organic, Mixed and Rectilinear. Mixed deterministically
assigns seeds to organic or axis-aligned generators within one shared structural
and tonal occupancy budget. Straight runs emit two endpoints while reserving their
entire interior clearance. Existing organic geometry and default recipe encoding
retain their prior interpretation. Visual review of retained-photo contact sheets
shows that dense structural texture still dominates facial features: line-form
differences are stronger in open tonal regions. This is a limited new rendering
mode, not evidence that aesthetic variety, semantic face priors or likeness are
solved.

The first targeted debug run passed 59 tests. A broader 220-test portrait/Drawing
integration run found only three old cache tests (seven assertions) assuming
synchronous restoration; after adapting them to the asynchronous contract, all
13 cache/browsing/capture tests passed. Coverage includes pending Current, stale
cached preparation, material floors, bounded retries, exact history restoration,
archive compatibility, line-interior barriers, tiny raster kernel bounds and
bitset decision parity. Hosted workspace snapshots were inspected at 1000×550 and
1280×650 with the Line form control visible. These are hosted software checks,
not pointer/keyboard interaction in the staged application.

The debug executable was packaged with the stable local development signing
identity. Launcher logic, launcher validation, strict bundle validation and
negative bundle checks passed without launching the application. The configured
repository suite uses this source-matched debug test build with
`SWIFT_FLAGS='--no-parallel --skip-build'`; machine receipts record its result.

Source photos stayed local and their archive files were not modified. No running
app was replaced or restarted, and no camera, controller motion, pen contact or
observed ink was exercised. Physical separation and plot duration remain attended
acceptance work. Required validation and landing receipts belong to this task;
retained artifacts live under `.build/PortraitFollowupEvidence/task-b279ed48/`
in the primary checkout.

## Flow Edge, short capture and three choices, 2026-09-21–22

Ordinary product extension in task `task-d28e7ad4af6345129394abcc61fb2b91`.
The September 21 request supersedes the manual-Variation nine-image interface.
New authoring defaults to Flow Edge, with current plus two preference alternatives
and an internal bounded step. Hatch variants remain available only to reproduce
historical work, including explicit material adaptation; new source acquisition
returns a retired style to Flow Edge while retaining its material context.

Flow Edge uses 320-pixel maximum-dimension analysis, independent structural edge
evidence, constrained subpixel curve fairing, and a smoothed structure-tensor line
field for tonal streamlines. Tone changes local spacing instead of applying a
global gamma transform to the structural image. Nearby parallel structural paths
are suppressed in evidence order; tonal paths reserve structural and nonlocal
self-clearance. Structural junctions/crossings are deliberately allowed. The
renderer revision is `flow-edge-v1`; old renderer and candidate identities retain
their original interpretation.

Capture now lasts 0.8 seconds including 0.25 seconds of exposure settling. At most
eight bounded thumbnails are scored for sharpness, exposure and clipping; one
original sample is retained with selection provenance. The process does not fuse
frames, reconstruct depth, change camera focus, or prove exposure has settled on
an actual device. Pose, duration and burst-frame navigation are absent from Studio.

The strict-concurrency debug portrait/integration run passed 195 tests in 252.814
seconds. Coverage includes exact structural survival across tone/coherence,
detailed smooth boundary retention, broad-material parallel suppression, tonal
self-clearance, quality selection and cancellation, one-result burst ownership,
legacy nine-slot receipts, old candidate/checkpoint compatibility, exact Back and
handoff, stale-source cancellation, and bounded visibly distinct alternatives.
The initial warnings-as-errors test build was blocked by an existing redundant
`await` in `PlotterTipCalibrationEpisodeTests.swift:229`; the passing run retained
strict concurrency without promoting that unrelated warning to an error.

Two local retained sources were rendered through the production analysis/vector
path for contact sheets with a fixed display stroke width: the measured facial
structure remains identical across density and coherence variants; some fine skin
texture remains visually busy. This is
digital review evidence, not operator aesthetic acceptance. Source bytes stayed
local and archive files were not modified. Evidence artifacts are retained under
`.build/FlowEdgeEvidence/task-d28e7ad4/` in the primary checkout.

The final optimized Flow/layout/workload selection passed 14 tests in 40.653
seconds; the second-photo workload/reference run passed both tests in 4.197 seconds.
The hosted workspace was inspected at 1000×550 and 1280×650 with Styles and
Adjustments folded/expanded. All three choices now occupy one horizontal row;
AX actions cover promotion, Current and exact Back. Pointer/keyboard operation in
the staged app was not exercised.

On those two real photos, eight optimized Flow preference rounds took
132.77–281.00 ms (median 174.61 ms), including candidate preparation and distinctness
checks. Each reused the analyzed raster and executed one to four renderer calls.
Five rounds provided two visibly distinct alternatives; three provided one after
bounded attempts. First analysis plus center preparation took 0.92–1.08 seconds.
Back took 0.18–0.27 ms without rendering. Maximum sampled MainActor scheduling
gaps during rounds were 7.98 and 10.42 ms. These are local model/worker timings,
not live-camera or end-to-end native interaction measurements, and are not a
like-for-like speedup claim against the old renderer. Required repository checks
and landing receipts are recorded by the associated Blackdog task.

The optimized executable was packaged with the stable local development identity.
Launcher logic, launcher validation, bundle validation and negative bundle checks
passed without launching the app. The full configured suite uses the completed
optimized test bundle with `--no-parallel -c release --skip-build`; production and
test sources are unchanged from the successful optimized build.

No running app was replaced or launched, and no live camera, controller motion,
pen contact or observed ink was exercised. Real capture settling, likeness,
plot duration and deposited-ink separation remain attended acceptance work.

## Cap-only reidentification retains mechanical Learning, 2026-09-21

Ordinary recovery fix in task `task-707f71f49c3d40f9a7d184b248d3c94f`.
**Learning Path Actions → Reidentify Pen Cap** stages a new exact-frame reference
without restarting the Pen Interaction motion sequence or replacing its accepted
actuation revision. Successful persistence retains the exact mechanical prefix
(pen actuation, X/Y sides, center and arrival) and replaces only optical authority:
the old camera/cap map and downstream tip/drawing calibration are invalidated.
Motion authorization is not required for this capture-only action. Full step redo
and explicit reset retain their existing semantics.

`swift test --jobs 4 --no-parallel --filter
'SavedLearningPenUpTests/(reidentifyCap|unsuccessfulCap)'` passed both tests in
6.162 seconds, including all four unsuccessful-operation variants. The production
UI request path retained exact mechanical revisions and controller pose facts,
issued no pen or travel commands, and saved/reloaded the new reference without
restoring obsolete camera/tip descendants. Cancellation, stale input, capture
failure and injected save failure retained the original cap, calibration, graph
and durable package. The first run exposed fixture-input mistakes (blank-paper
selection and comparison against pre-revalidation evidence); corrected tests use
the generated armature and the active accepted evidence.
The first full diagnostic run found an obsolete assertion for the removed
Reset All recovery text and later stalled with an idle test-process main loop;
that test process was stopped after a stack sample. The assertion now requires
cap-only recovery and boundary retention. Required validation is rerun with
unbuffered output; the interrupted run is not passing evidence.

Required full-suite and landing receipts belong to this Blackdog task. Native
menu/rectangle interaction, real-camera tracking and attended hardware behavior
remain unverified. The existing app session is preserved.

## Pen-cap visual reference and independent anchor, 2026-09-21

Ordinary product extension in task `task-7ff2d1a6fc0e48d6af1cca20c8a5dd5e`.
Exercise 1.1 now stages a rectangle around the cap/co-moving holder and submits
it with a separate cap point on the same frozen exact frame. All colors,
including black and gray, remain in a bounded RGB reference. Source-pixel
geometry is independent of UI zoom. A cap point near a rectangle edge remains
that point through tracking and all three LIVE calibration/revalidation paths;
the rectangle center and bottom edge no longer replace it.

The detector globally proposes candidates, refines translation and bounded
affine deformation using bilinear image sampling, and rejects weak, competing,
clipped, incompatible or discontinuous matches. It never updates the reference
from a detection. Overlay status labels the matched reference and cap anchor
rather than reporting the template's sample count as segmented cap area.
The accepted Learning package retains the reference and exact provenance;
old color-only records stay readable and require reidentification for LIVE
tracking. Existing reset/cancellation and source separation remain the owners.

Focused software validation: `swift test --skip-build --no-parallel --filter
'PenCapVisualReferenceTests|PenCapAppearanceSelectionTests|PlotterPointSelectionEpisodeTests|PenCapReferenceSelectionTests'`
passed 37 tests in 7.291 seconds after the updated debug build. Cases cover
rectangle mapping under zoom/reverse dragging, exact-frame rejection and
continuation cancellation, reference transport/persistence, the independent
calibration anchor, dark multicolor and achromatic structure, translation/scale,
missing/duplicate/oversized patterns, incompatible configuration and jump recovery.
The synthetic 1920×1080 full-frame search with an 84×72 reference measured
2.609 seconds in that debug run; this is diagnostic software timing, not native
preview responsiveness or an optimized-performance claim. Repository-wide
validation and artifact receipts belong to the associated Blackdog task.
The full parallel diagnostic run encountered existing recording/paper-load timing
limits under contention and was stopped after becoming idle. The production Pen
Interaction test ingress was updated to submit the rectangle as well as the cap
point and fail immediately on a setup refusal. Its suite plus the recording-store
timeout regression passed 20/20 serially in 1.599 seconds. Required validation is
run with `SWIFT_FLAGS=--no-parallel`; this is serialized software evidence.
The first full serial run exposed aggregate-checkpoint reconstruction omitting
its reference and the complete-Learning fixture expecting the obsolete color
identity. Both were corrected. The sampling regression now saves and reloads
the complete Learning package, not just the appearance value.

No running app was replaced or restarted during development. Native operator
drag/click interaction, real-camera tracking, controller motion, pen contact
and observed ink were not exercised; synthetic matches do not establish those.

## Manual-Variation imagination grid, 2026-09-20–21

Ordinary product extension in task `task-c409393921a74a8ea3b75c67fa503868`,
attempt `attempt-2286c457d3a74a9b851ea8f06ef189f9`. This explicitly reauthorizes a
bounded 3×3 selection interface after the September 18 Studio simplification;
it does not restore semantic Big Head, training, automatic cooling or fitting.

The center is the exact completed candidate. Eight alternatives preserve source,
crop, style and material context while a deterministic seeded fixed-mixture policy
varies applicable renderer parameters. Manual Variation scales that spread and
persists through choices. Neighbor selection installs the offered candidate;
center selection resamples. Exact Back snapshots retain prior offers and Variation,
independent of render-cache eviction. Source/framing/manual edits reset the branch.
The large source pane is replaced by the grid, compact Source access remains,
and the selected drawing stays large. Detailed adjustments are collapsed by default.

The existing serial render drain owns all work. Round IDs, source/configuration
identity and cancellation settlement reject stale results. A pending neighborhood
retains the usable selected drawing. Each neighbor has at most three attempts;
a round has a 200,000-point geometry budget. Session Back retains at most 12
previous rounds within a 400,000-point current/history budget. Empty, duplicate
or failed proposals produce explicit unavailable slots after bounded work, including
zero Variation without fabricating alternatives. The current candidate survives
those failures.

Explicit Save Imagination or successful Send to Drawing retains the exact source,
raster, recipe/version/program and up to 64 offered-set/action receipts through
`PortraitSketchCollection` and the existing checksummed archive. Receipts contain
offered recipes/identities, seed, Variation and choices; they are provenance, not
labels or a trained model. Session identity and monotonic sequence preserve newer
saved receipts when an earlier asynchronous handoff completes after trace trimming.
Candidate/source deletion removes its trace with the same archive entry. Legacy
entries without the optional trace remain readable. Back is session-local and
bounded, not a restart-persistent or unlimited undo stack.

The reproducible performance fixture is a synthetic 480×640 analytic portrait-like
grayscale image (`analytic-portrait-480x640-v1`, SHA-256
`92bd74a28263a071fb48b32a8339999927830886243715246d90247708b55390`). Real image analysis
produces a 120×160 raster. Measurements separate empty model-cache analysis plus
center rendering from cached-raster rounds; process and Vision framework warmup
are not controlled. The balanced preset workload covers Variation 0.35, 0.08,
0.9 and three neighbor selections holding 0.9. A separate current default-vector
probe covers 0.08, 0.35 and 0.9. Parameter-distance measurements are normalized
Euclidean distances across applicable contour controls, not perceptual scores.

Final optimized evidence on macOS 15.7.9 / Swift 6.1.2 / x86_64:
`swift test -c release --no-parallel --filter PortraitExplorationPerformanceTests`
passed both tests in 2.163 seconds after the first optimized build (778.64 seconds).
The balanced fixture supplied eight distinct neighbors in all six rounds, with
8–9 renderer calls per round and exactly one cold source analysis. Source analysis
plus center took 102.35 ms; cached rounds had a 200.85 ms median and
149.73–225.54 ms range. Back took 0.57 ms with zero renderer calls. The largest
sampled main-actor heartbeat gap was 10.21 ms. This measures model generation,
not end-to-end live SwiftUI presentation latency.

The current default-vector low/default/high probe also supplied eight distinct
neighbors each. Mean normalized recipe distances for the balanced workload were
0.152 / 0.032 / 0.335 at Variation 0.35 / 0.08 / 0.9, then
0.384 / 0.376 / 0.351 across three selections while Variation remained 0.9.
Realized distance varies with the seed and reflected parameter bounds; the policy
has no click-count or elapsed-time input and does not change the manual value.
Distinct geometry is not proof that every alternative is aesthetically useful.
An earlier debug run before the final slot permutation had a 3653.1 ms median;
it is diagnostic evidence, not a paired speedup benchmark.

Final policy/model/native verification after seeded slot shuffling succeeded in a
27-test run (50.102 seconds); two opt-in AX cases were skipped in that default run.
The tests cover exact promotion/resampling/Back, fixed Variation, stale tile/source
publication, bounded retries/history, source replacement/deletion, manual edits,
expanded algorithm comparisons, hiding/reopening, saving during pending work,
archive compatibility/deletion and both delayed-handoff provenance orders.
The preceding 26-test integrated run also covered all 40 combinations of two
workspace sizes, five styles and folded/expanded Styles and Adjustments. Final
production-route native snapshots were regenerated after the slot shuffle;
coordinator and UI worker independently inspected folded/expanded evidence.

The separate opt-in exploration AX probe failed its host prerequisite: a known
standalone SwiftUI control was absent before and after `finishLaunching`, and the
host exposed only AXWindow/AXGroup without the grid slot. No assertion was weakened.
Native pointer/keyboard/slider input is therefore unverified; offscreen hosted
geometry and model actions are separate passing evidence. Source popover activation
and signed-app launch were not exercised.

A first cold compilation was invalidated by a concurrent final source edit and
was rerun from a frozen tree; that invalidated compile is not a product-test failure.
The existing user app/session and hardware remain outside this task's validation.
The release executable produced by the passing optimized test build was packaged
with `sh Scripts/build_local_app.sh release` and independently checked with
`sh Scripts/validate_local_app_bundle.sh .build/AdaptivePlotter.app`; both passed.
The bundle uses the stable local `AdaptivePlotter Local Development` signing
identity. A redundant `make app` compile was cancelled before relinking; the
existing optimized executable's SHA-256 and modification time were unchanged.
No completed `make app` invocation is claimed. The signed bundle is staged
separately and remains unlaunched; source-input hashes support comparison with
the landed commit. The configured Blackdog validation receipt records the
repository's three commands (`make docs-check`, `make quick-test`,
`git diff --check`), with `SWIFT_FLAGS=--no-parallel` preserving the complete
quick-test selection under serialized scheduling.

Operator aesthetic convergence, actual Source popover/camera capture interaction,
and attended pen/paper/ink quality require separate evidence. The operator evaluation
path is recorded in Roadmap.

## Sparse retained Drawing progress photos, 2026-09-20

Ordinary product extension in task `task-d062bc481d7342ae92298d652d6f4b21`,
attempt `attempt-e41814fa75464c9f99056cb122c8fde2`, based on `096cd9c`.
Read-only archive inspection confirmed earlier ordinary runs retained
baseline/result pairs but no intermediate-stage sequence. The latest interrupted
observation still has only its baseline; no missing photo was reconstructed.

The existing Run owner now requests at most three fresh progress photos near
quarter-completion of the stroke count, for plans of at least four strokes.
`RunInterpreter` awaits the read-only observer only at an already settled Pen-Up
checkpoint, retaining its one plan owner and checking Stop before another stroke.
There is no intermediate reveal movement. The existing completion photo and
bounded final observation poses remain. Short/single-stroke plans retain baseline
and final photos rather than inventing an intermediate settled checkpoint.

Every retained stage binds original pixels, source/configuration, fresh capture
boundary, controller pose, plan/request identity, and committed stroke/checkpoint
frontier. The evidence store persists each stage with its staged attempt before
continuation, so reopening does not require a terminal record. Failures remain
visible, prior stages survive, and exact byte/reference publication retries
neither recapture nor dispatch motion. Legacy archives decode with no fabricated
stages; malformed chronology/frontiers and missing original bytes are rejected.

The four-panel reviewer offers labeled stage selection, defaults to the newest
retained frame, and shows the selected stage's planned stroke prefix. Unfinished
attempts with saved stages remain browseable after restart, without manufacturing
completion or changing no-redraw authority. Raw photos are available for later
stage-aware inspection and learning; no automatic fitting/model acceptance,
matched-pose analysis, unobstructed arm visibility, or ink success is inferred.

The final focused selection passed 100 tests in 18.059 seconds, including actual
interpreter ownership/Stop while the observer is held, per-stage acquisition,
stale/wrong-camera rejection, before-terminal persistence/reopen, original-media
corruption, old-schema decode, exact-media recovery, stage preview selection,
and existing Drawing/result-photo/archive tests. The first pass caught a final
visibility message overwriting an earlier stage-capture failure; the retained
reason now includes both. Configured repository validation is recorded in the
Blackdog receipts. Signed build and logs are staged separately under
`.build/ProgressCaptureApps` and `.build/drawing-progress-d062bc48-evidence` in
the primary checkout. The running app and hardware were not operated or replaced;
post-change native interaction and attended camera-to-ink validation remain open.

## Automatic Drawing result photographs, 2026-09-20

Ordinary product repair in task `task-d3075a47953b44d9b803c4cdce69feb3`,
attempt `attempt-2629a20fd24248a6a288cc0a7837aaf4`, based on `5c586ef0dfaf`.

Read-only incident inspection found run `D61DB42E-8DD3-49B9-924D-5503146E7ADC`
completed 122/122 strokes at 17:07:55 PDT with no terminal frames. The archive
reported `Controller or run facts changed before observation travel.` Only its
15:55 baseline pixels were retained. Controller history ended with settled Pen Up;
there was no later reveal travel. Native inspection of PID 38196 showed
`Drawing finished`, without a missing-photo indication. Diagnostic export was
unavailable because no enabled export button was present; no export was fabricated.
The old diagnostic did not identify the individual rejected fact. Code and
regression evidence reproduce the failure through unsealed preview frames:
Draft discarded their stream identity, optical metadata depended on an evidence
hash, and paper applicability/Run plan disappeared before result positioning.

Optical metadata and accepted paper applicability now survive an unsealed
preview without manufacturing exact-frame evidence. After clean completion, the
existing Run owner captures and installs a fresh same-source/configuration photo
before optional reveal travel. Its independent completion acquisition boundary
retains freshness without a controller-pose or ink claim. Matched observation
keeps its existing movement/admission checks. Stop/failure/ambiguity may seal
already available pixels but initiate neither capture nor photo travel. Missing
capture and changed-fact reasons remain explicit. Media failure retains original
bytes for publication-only retry.

The four-panel reviewer defaults to the newest retained image, exposes capture
and coverage reasons, and distinguishes a fresh result from an available image
that may predate completion. The active terminal status flags a missing result
photo. Existing archives decode without inventing completion freshness.

The final focused SwiftPM selection passed 106 tests in 23.776 seconds, including
unsealed preview applicability, unavailable-context completion capture, stale and
wrong-camera rejection, Stop during acquisition, durable reload, exact media-save
recovery, reviewer selection/status, and the existing Drawing suites. A pre-existing
camera-calibration test compile error required `await` when constructing its
MainActor probe; its cancellation regression passed. Older capture fixtures,
including the raster-observation integration, were updated for the extra retained
completion photograph without changing their Vision/residual assertions. The
Boundary recovery test now awaits the settled refusal before preserving its exact
historical identity; the previous wait could capture a provisional projection.
The affected Boundary/raster recheck passed all 4 tests in 133.195 seconds,
including every full-resolution raster workload and its unchanged measurement
assertions. The signed debug bundle
passed local bundle validation with the stable development identity. Configured
repository validation is recorded in this task's Blackdog receipts.

Evidence and the separately staged app are retained under
`.build/drawing-result-d3075a47-evidence` and
`.build/ResultCaptureApps/AdaptivePlotter-ResultCapture-d3075a47.app` in the main
checkout. The user-owned running app was preserved. No live drawing, camera
reconfiguration, hardware motion, post-change native interaction, or physical
camera-to-ink validation was performed. The missing historical result cannot be
reconstructed from its retained baseline or planned paths.

## Partial Guided Learning recovery, 2026-09-20

Ordinary product correction in task `task-1931347a34e9462c9550b5e98d92e216`,
attempt `attempt-6079cfb9422b469a8618ad26aad78b94`, based on `2c8f19d2bc23`.
One lifecycle executor owns workspace integration and local delivery; bounded
workers own runtime recovery and UI/presentation, with coordinator acceptance.
This is not an episode-migration package.

Settled Boundary refusal/cancellation retains historical detail but uses the
existing owner's current admission assessment for explicit retry. Active work,
unpublished/reset authority, unknown position, sticky ambiguity and terminal
shutdown remain guarded; owner-issued retry after a settled center-position miss
remains center-only and subject to current admission.
Selecting an unavailable future exercise no longer places another exercise's
controls beneath its instructions; a necessary active-owner Stop is separately
named. Camera Redo prepares a fresh proposal with accepted-map fallback, and
Cancel/Stop discard unaccepted proposals so Restart cannot revive them. A scoped
reset's surviving Pen prefix preserves its exact compatible cap appearance and
reference frame without legacy preference dependence or substitute imagery.

The final focused run passed 109 tests in 25.697 seconds (`focused-final.log`),
covering owner-scoped controls, camera replacement/cancellation, Boundary retry and
reset, center-only recovery, and disk reload of the retained Pen prefix. An earlier
fixture compile error passed `Data` where `OwnedFrameBytes` was required; after
that repair, a 108-test run exposed five issues. Repairs restored the existing
owner-issued center retry and corrected fixture settlement/baseline expectations.
Those unsuccessful receipts remain `focused-recovery.log` and
`focused-recovery-repaired.log` in `.build/guided-recovery-1931347a-evidence/`.
Strict signed-app validation passed (`signed-app-validation.log`): stable-local
deep/strict signature verification, launcher logic/refusal checks and bundle
negative checks. The candidate was not launched. Final configured-check results
are retained in [the Blackdog validation receipt](../.build/guided-recovery-1931347a-evidence/blackdog-validation.json).
The exact landed source, build-input match, signed artifact path and hashes belong
to `artifact-receipt.json` in the same evidence directory.

The investigation was code-based. No app was running at its start; the latest
saved trace predates the previous release's unlaunched signed build. This is not a
native reproduction of that old trace. During the first isolated compile, a new
canonical app process (PID 38196) appeared and the live checkpoint progressed.
The task build was interrupted before any tests executed; its log had no test-run
markers. Read-only inspection found isolated fixture persistence and concurrent
canonical app/build activity whose actor is unknown, not evidence of a test leaking
into live storage. This task performs no app launch/restart, hardware operation,
controller-setting change, live Learning reset or sheet acceptance. Software/build
evidence does not establish physical redraw, speed, placement accuracy or ink
quality. Validation and exact-source delivery receipts
belong in `.build/guided-recovery-1931347a-evidence/`.

## Learning recovery, paper placement and Imaginations, 2026-09-20

Ordinary product correction in Blackdog task
`task-1f57c44c47fa4c0db5b3a3e4dfcdf494`, attempt
`attempt-ccbaf2cae1ac4f1a8edf0ab1bb2776e9`, with one lifecycle executor and delegated
recovery, guide/paper and reviewer implementation; the coordinator independently
accepts the integrated change. This work selects no episode-migration package.

The selected-step reset and selected-exercise controls are restored. Tip recovery
settles its existing owner, clears transient selections and preserves accepted
replacement fallback, history and same-sheet possible-ink exclusions. Shutdown
remains terminal. The canonical four-circle plan now supplies persistent planned
video frame/center/path guides with a separate calibration-guide semantic kind.
Artwork Hide and ordinary border preview retain their independent identities and
exact-frame selection. Cap-map placement remains explicitly approximate;
pre-tip sheet placement is a separate qualified assertion and never calibrated
Drawing readiness. Calibrated sheet coverage retains registration checks.

Drawing Reviewer loads the existing shared library without requiring Studio to
mount, shows loading/failure/retry, and lists **Imaginations** separately from
**Drawing results**. Retained execution plans supply historical geometry before
source-reference fallback. Missing photographs and genuinely absent geometry are
explained without substituting evidence. Persisted schemas, identifiers and hashes
are unchanged.

Read-only live-library inspection found 13 saved entries, zero tombstones and 23
unique source/raster assets; every asset's SHA-256 matched its reference and the
index payload checksum matched. This verifies retained bytes, not rendered native
interaction. The repaired combined focused run passed 158 tests, including direct
reviewer startup with 16 saved candidates and concurrent Studio/reviewer loads,
40-entry persistence, historical plan/reference/media limits, Learning controls and
reset transitions, causal sparse-tip recovery and qualified Draft sheet acceptance.
Its receipt is `.build/recovery-1f57c44c-evidence/focused-repaired.log`.
A subsequent targeted 14-test tip-runtime run passed after the concurrent-cancel
admission repair (`tip-concurrency-repaired.log` in the same evidence directory).
The broader strict run exposed six failing tests (14 issues) among 1,410 tests
with six skips; its receipt remains `blackdog-validation-before-preview-repair.json`.
After separating calibration guides from artwork predictions and repairing preview
frame isolation, the strict focused selection passed 80 tests in 15.606 seconds
(`preview-guide-repair-focused.log`). Final configured-check results belong to
[the Blackdog validation receipt](../.build/recovery-1f57c44c-evidence/blackdog-validation.json).
Strict concurrency/warnings-as-errors debug build and signed-app validation passed:
stable-local `AdaptivePlotter Local Development` signature, strict bundle/signature
checks, launcher logic and negative refusal tests, and negative bundle tests
(`signed-app-validation-final.log`, refreshed after the preview repairs). No signed
bundle was launched. Local delivery and
the separate exact-landed-source signed artifact are recorded by `landing.json`
and `artifact-receipt.json` in `.build/recovery-1f57c44c-evidence/`; the artifact
receipt supplies its source commit, hashes and immutable app path.
Documentation/architecture contracts and the documentation check's
13, 9 and 39 Python tests passed. This task issued no application launch, restart,
replacement, live Learning reset, sheet acceptance, controller setting change or
hardware operation. Its builds/tests ran only in the returned task workspace.
However, the read-only preservation recheck found the original PID 87466 absent,
no current app process, and a changed canonical `.build/AdaptivePlotter.app`
executable. The cause is unattributed; the original session cannot be claimed
preserved. The observed identities are retained in
`.build/recovery-1f57c44c-evidence/preservation-recheck.json`.
No physical redraw, speed, placement-accuracy or ink-quality validation was
performed. A separate signed build is not a native-interaction or attended
physical receipt.

## Drawing motion recipe and continuous polylines, 2026-09-20

Task `task-03f601ada61e46cbb669c233688b59b9`, attempt
`attempt-e2e4152e039d4f039ff978d725a85de2`, began from `0e5aa714` with target
`main`. Workers own the policy/retention implementation, controller/interpreter
implementation, and documentation/validation/delivery; the coordinator retains
independent acceptance and landing authorization. This selects the ordinary
Drawing motion backlog, not an episode migration or attended physical package.

New general Drawing attempts retain an independent versioned recipe bound to the
exact intended plan; existing plan/program hashes, authored geometry, stroke order,
feed and pen settings remain unchanged. Legacy missing policy stays unknown and
no-recipe Learning/calibration callers keep isolated execution. Controller settings
are captured without firmware writes and checked before lower-plan effects.

Continuous strokes now use one unacknowledged `$J` command with ACK-driven refill,
finite firmware-planner backpressure, no intermediate Idle drain, and explicit
stroke/pen/checkpoint barriers. Normal `$G` and cancellation `$$` response fences
protect terminal status attribution. ACK is not completion. Stop, partial write,
accepted-prefix rejection, disconnect, timeout, reset and coalesced fatal status
retain uncertainty/no-replay truth. Transcript evidence establishes host sequencing,
not uninterrupted physical velocity or immunity to transport starvation.

The existing attempt archive retains wire-source mappings, distinct submitted,
acknowledged and controller-completed frontiers, and attributed drawing/travel/pen
operation spans. Timing covers only lower-plan execution, includes protocol waits,
and excludes baseline/post-observation and total end-to-end latency. Completion and
missing legacy evidence remain qualified; these are not direct physical-motion or
ink measurements. Pure motion-cost estimates retain separate isolated/ideal
continuous assumptions and conservative Runtime timeout ownership.

The final strict sequential focused suite passed 212 tests in 12.571 seconds.
Coverage includes recipe identity/round trips and legacy omission, controller-context
changes, archive tampering, unchanged wire geometry/source ranges, required barriers,
ACK/completion distinction, cancellation write/ACK/fence races, stale Idle, partial
write, rejection, disconnect, timeout, reset and fatal lines coalesced with Idle.
Earlier failed receipts remain in the preserved logs; the final run includes their
repairs without weakened runtime/archive guards or geometry assertions.

Receipts are retained under `.build/motion-03f601ad-evidence/`. Strict signed debug bundle, launcher identity/logic and negative-bundle validation
passed using the stable local development identity. The unlaunched candidate is
staged separately as
`.build/StudioTestApps/AdaptivePlotter-Motion-stage-03f601ad.app`; `stage.json`
and `build-inputs.json` retain its binary/signature and source-input identity.
Configured documentation, strict sequential full quick-test and whitespace checks
passed. The final landed-source identity, input-equality check and commit-qualified
artifact path are supplied by `.build/motion-03f601ad-evidence/release.json`; the
earlier stage receipt establishes only the tested candidate identity. No app
launch, live-session replacement, physical controller/camera/pen/paper/ink operation,
remote Git operation, physical speedup or ink-quality equivalence is claimed.
Attended matched baseline/continuous comparison remains pending.

## Drawing precision, retained outcomes and inspection, 2026-09-18

Task `task-87b9fefb7ac94c54a13362a568f81a7f` began from `80abee3c` with
target `main`. This is the corrective follow-up to the Studio control audit,
not selection of an episode migration or attended-physical package. Three
existing subagents implemented bounded runtime/geometry/UI portions; the
coordinator owns integration, validation and delivery.

Read-only incident inspection found run `1EA98CC1-E0F5-4BBF-B400-B5E10EF9A7F7`
stopped after 1,026 completed segments. Its next intended displacement
(0.0003610523, 0.0002440407) serialized to zero on both controller axes. The
trace records Pen Up cleanup and no controller alarm. The border was last of
83 strokes, explaining its absence before this failure. Reconstructing the
archived placement after removing the single camera correction recovered an
authored rotation of approximately -39 degrees; the reason for that operator
selection is not established. The visible-patch camera comparison suggested
translation, but neither its physical cause nor physical registration is fixed
or proven by this task. Incident artifacts remain in
`.build/live-inspection-51360-evidence/`.

`RunInterpreter` now derives a controller schedule from cumulative positions
within each immutable stroke, retaining displacement residue, source segment
mapping and checkpoint boundaries. It preflights all strokes before lower pen
actuation, refuses wholly unrepresentable strokes, and constrains rounding to
the admitted region. Ordinary artwork uses clipping in the existing planner;
metric/calibration targets retain strict containment. Center uses transformed
un-clipped ink bounds. New selected borders run first. The no-redraw comparison
now tolerates stroke reordering and regenerated identifiers while preserving
one-to-one path multiplicity and existing coordinate-frame restrictions.

The existing Drawing panel pins the exact plan above its scrolling controls;
an active or retained run owns that preview instead of a later authoring draft.
Global run status retains the terminal reason until the existing RunID-bound
Prepare Next Drawing handoff. Incomplete durable publication remains visible
without an invented recovery or handoff capability. Styles starts folded and
renders only the selected algorithm; expanding it requests missing alternatives
through the existing render drain. Send to Drawing saves, hands off the exact
candidate and opens Drawing. Save Drawing is optional; only Draw requests motion.

The existing diagnostic export now includes process identity, selected and
retained plans, current registration, progress, terminal reason, and the exact
displayed camera pixels with capture identity and digest. Raw bytes and an
unoverlaid PNG are written before the JSON manifest on a background worker.
The inspection scripts combine this export with a matched native window/AX
snapshot and a read-only SQLite backup including committed WAL state. Sampled
frames retain independent timestamps and may be frozen; they are not continuous
video, an automatic final-image mosaic, or proof of newly deposited ink.

Cross-review found and repaired boundary rounding outside non-grid limits,
floating-point clipping joins that split a small tail, order/ID-sensitive
no-redraw matching, and a hidden unresolved-publication outcome. The final
focused strict sequential selection passed 174 tests in 71.117 seconds, with
two opt-in reference/native tests skipped. Coverage includes the incident delta,
3,000 accumulated small moves, reversal and boundary containment, Stop,
clipped rotations and Center, retained run preview identity, result handoff,
render cancellation and exact diagnostic pixels. Twenty style/size/folded-state
hosted combinations and production Studio at 1000 x 550 / 1280 x 650 fit without
vertical scrolling. Drawing previews remain fixed while controls scroll at
300/390/600 points. Coordinator/worker bitmap inspection uses synthetic fixtures,
not a live camera or physical portrait likeness receipt.

A final ownership review also repaired unresolved terminal-record construction:
only the matching staged intent can supply its retained plan, including diagnostic
run ID/hash, while editing and new-run handoff remain blocked. The 61-test strict
retention/preview/diagnostic selection passed in 16.605 seconds after that repair.
Inspector fixtures passed 19 tests; requested export failure or incomplete sample
sequences now produce a nonzero result while preserving partial artifacts.

Earlier receipts are retained: one source-review-interrupted build, one missing
exhaustive test case, one optional-unwrapping test compilation error, and a
174-test run with 14 issues from three fixture assumptions (displayed Stop text,
exact floating-point Center equality, and delayed previous-host disappearance
resetting Styles). Production behavior and layout assertions were not weakened
to clear those fixture issues. One broad run was interrupted for the final
ownership review. The next 1,376-test run completed in 418.094 seconds with seven
issues in two obsolete fixtures: eager rendering of all styles and selection of
the last stroke as border. The fixtures now check chosen-style cache behavior and
all five ordered points of the first border stroke, using the existing numerical
geometry tolerance. The documentation checker was also updated from its obsolete
blanket no-clipping phrase to require ordinary-art clipping, excluded-art refusal,
and strict metric/calibration containment.

The coordinator launched only the staged signed build in simulation (PID 15940),
after confirming no AdaptivePlotter process was running. Native inspection found
Screen Recording and Accessibility authorized but the macOS console locked, with
loginwindow foreground. Window capture failed and AX supplied no window geometry.
The helper now identifies that exact condition through the read-only active-console
lock flag, skips unusable capture/export, and reports the unlock remedy. Two final
locked-session samples retained the correct process identity and explicit failure;
there was no AX export action. The owned simulation process then terminated
gracefully, and its exit was verified. The inspector's final 20 fixture tests pass. A
positive unlocked-window/raw-export integration receipt remains pending; these
locked-session checks do not establish that result. No physical camera, controller,
pen/paper/ink operation or calibration change was performed.

The final strict sequential quick-test selection passed 1,376 tests in 412.972
seconds, with six opt-in native/reference/performance tests skipped. All ten
retained causal journeys passed in 3.150 seconds. Source/test/build-script hashes
were unchanged throughout this final validation. Stable local signing, strict
bundle validation, launcher identity/logic checks and negative-bundle checks
passed. Documentation and diff checks pass; the final ledger is checked again
before landing.

The immutable signed debug bundle is
`.build/StudioTestApps/AdaptivePlotter-Drawing-87b9fefb.app`; release identity,
input hashes, complete/failed receipts, hosted images and locked-session evidence
are retained in `.build/drawing-repair-87b9fefb-evidence/`. The bundle's executable
SHA-256 is `a72dd5cd804625d360fa52693ecb667dba236f4ad436da5b7d661626834a7fb9`.
A future unlocked native inspection can use the documented one-command collector;
no automatic image reconstruction or physical alignment correction is claimed.

## Deterministic Portrait Studio and generic review, 2026-09-18

Task `task-9e64f2ffa4544ecea34e9867f8b5944c` began from `11bbb5b` with target
`main`. The accepted control audit is recorded in the
[execution plan](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md#control-audit-and-final-disposition).
Studio now has persistent burst capture, paired photo/drawing frames, five rendered
algorithm choices and their relevant adjustments, with framing in the same bounded
workspace. Pen & Material identifies marker width and its provenance. The generic
Drawing panel owns placement/material/paper/run controls; Drawing Reviewer owns
local browsing and deletion of saved drawings and ordinary physical results.
Explanations use question-mark popovers. Random/exploration/history, ratings,
training generation and normal Big Head authoring owners are removed; historical
candidate, preference and checkpoint decoding/integrity checks remain.

The final targeted strict SwiftPM run passed 27 tests in 23.471 seconds. It covers
exact handoff with border on/off, review deletion/reload and unchanged no-redraw
truth, physical candidate association, hosted layouts and native-report validation.
Ten style/size combinations fit at 1000 × 550 and 1280 × 650 without vertical
scrolling. Production Studio panel bindings, Drawing at 300/390/600 points and
empty/saved/result reviewer states also passed hosted checks. Opaque, settled
bitmaps were inspected by the coordinator and UI worker; no blocking clipping was
found. These use synthetic images and fixture ports, not the operator's camera.

Two existing workers each reviewed one portion they did not author from frozen
patch `6a601b3547129ad61bab1a5114c03a0b0466ce2cb43162fbd8ababe4add31181`.
The agent limit prevented a fresh fourth critic. Three findings were repaired:
border composition could cause repeated handoff to reset placement; some Studio
exit routes retained the portrait camera role; reused image state could display
the prior selected record. The coordinator owns the repairs and validation;
there was no second critic pass. The exact shell native-workbench validator also
passed four fixture tests covering three valid modes and 18 negative mutations.

Earlier failed receipts remain retained: an initial build raced a source edit;
the first focused compilation found a test snapshot-access typo; a broad focused
run completed 307 tests with 14 issues in redundant fixture actions, exact floating
point scale assumptions, obsolete mandatory-scroll expectations, and an outdated
report schema assertion. The fixtures now use admitted actions and discrete scale
values; layout checks require actual wheel movement only for overflowing content
and otherwise require the complete Draw control/body to fit. These are not relaxed
native event identity or clipping checks. The final targeted run above passed.

Review deletion is a durable archive tombstone, excluded from review and future
drawing assessment. Raw execution records, attempts and shared media remain
immutable so deletion cannot clear possible-ink/no-redraw protection or silently
erase calibration evidence. Archive schema 4 continues to read schemas 1–4.

The complete strict sequential quick-test selection passed 1,346 tests in 414.931
seconds, with six opt-in native/reference/performance tests skipped. All ten retained
journey tests passed in 3.186 seconds. Stable local signing, strict bundle validation,
launcher identity/logic checks and negative-bundle validation passed. Documentation
and diff checks passed; final ledger edits are checked again before landing.

The immutable debug bundle is staged as
`.build/StudioTestApps/AdaptivePlotter-Portrait-9e64f2.app`; logs, bitmaps, frozen
review, source/test input hashes and release identity are retained under
`.build/portrait-refresh-9e64f2-evidence/`. No app launch/restart, live camera capture,
native input gate or plotter/pen/paper/ink operation was performed. The signed native
workbench gate was deliberately not run because production View transitions may
activate a real camera even after simulated startup. Hosted geometry and report
fixture tests do not substitute for native event or attended physical proof.

## Drawing overlay restart and visibility repair, 2026-09-16

Task `task-4b6387a818c942d8958ab043292ab569` began from `835e65e` with target
`main`. Read-only inspection of the operator's 13-record drawing archive found
four plans accepted by the previous automatic overlay filter. Two were portraits:
the cancelled `18D9D6AA` plan projects to camera X 1688–2059, partly beyond the
1920-pixel frame, while `94E2198F` projects to X 981–1230. The code projected every
matching saved plan through the selected registration independently of Draft
target visibility. These calculated bounds explain the screenshot's separated
copies; they are not physical alignment measurements.

The automatic archive-to-video loop and its obsolete filter are removed.
Saved Learning retains calibrated Boundary/Border guides. The current Draft
preview has a direct **Hide Drawing** control on the video and a **Show Drawing** /
**Hide Drawing** control in Video Settings. Both use existing typed Draft
requests; hiding also clears an unapplied canvas drag. Programs, placements,
paper assertions, Learning, archived evidence and possible-ink protection retain
their existing owners. Restart begins with no selected drawing overlay.

The focused strict SwiftPM selection passed 62 tests. The strengthened production
fixture additionally verifies hiding/showing after a stopped possible-ink run
while disconnected, including unchanged plan, paper, archive and ink protection.
The initial parallel quick-test run reported timing failures in recording,
speech, voice and photo-shutdown fixtures and was stopped before completion for
sequential verification. No production code in those areas was changed.
The final strict sequential quick-test selection passed 1,362 tests in 428.426
seconds, with six opt-in native/reference/performance tests skipped. Every
previously failing test passed in that run. Documentation and diff checks passed.

The signed debug bundle passes strict signature/bundle validation and is staged
as `.build/StudioTestApps/AdaptivePlotter-Overlay-4b6387.app`; receipts are retained
under `.build/drawing-overlay-4b6387-evidence/`. The user-owned running application
is preserved. Native button/drag interaction, camera alignment and physical ink
behavior remain unverified; no LIVE app restart or hardware action was performed.

## Camera-proportioned drawing placement, 2026-09-15

Task `task-e4ee383c033e45ff85f827daef18e4e2` began from `c1b769b` with target
`main`. Ordinary artwork now uses the accepted Guided Learning command-to-image
response to compensate unequal axis travel and shear in its canonical placement.
The implementation uses no ruler inputs and writes no controller settings.
Initial Guided Learning is retained; normal-drawing feedback does not yet update
the motion model. Camera foreshortening is part of the accepted camera-relative
objective, and physical metric accuracy remains independently unverified.

The strict focused SwiftPM run passed 82 tests in 12.531 seconds. Coverage includes
anisotropy, shear, reflection, authored rotation, corrected Fit bounds, unchanged
controller metric targets, canonical plan compatibility, border composition and
candidate identity, saved camera preview replay, conservative material spacing,
and the complete portrait projection/material/Draw/persistence journey. These are
software and synthetic execution checks, not attended camera or ink evidence.

Three medium-reasoning subagents reviewed the implementation. Their two findings
were stale material freshness comparisons and direction-dependent physical-rating
height metadata. Both were repaired. Coordinator tracing also found the border
candidate matcher's similarity assumption; camera compositions now verify one
affine across every source/target point while legacy compositions keep their old
contract. A bounded repair review found no remaining concrete defect. Focused
failure receipts include test compilation corrections and two floating-point
exact-equality assumptions; the final focused run above passed.

The complete strict quick-test selection passed 1,361 tests sequentially in
405.977 seconds, with six opt-in native/reference-input/performance tests skipped. Its
first parallel run completed with two unrelated speech/cancellation timeouts;
both affected suites then passed all 17 tests in isolation in 0.011 seconds.
No production speech code was changed. Stable local signing, bundle validation,
launcher logic/identity checks and negative-bundle validation passed. The final
documentation and diff gates are recorded alongside these receipts.

Validation receipts and the immutable signed test app are staged under
`.build/camera-proportions-e4ee383c-evidence/` and `.build/StudioTestApps/`.
The running application is preserved. Native acceptance, the next Guided Learning
run, and actual face/ink quality remain pending the operator's attended test.

## Pen-cap failure feedback and Learning reset recovery, 2026-09-15

Task `task-a4da8fb0915c4a03a706e08ac9d8ea33` began from `3f6c1ca` with target
`main`. Read-only inspection used machine session
`fc532bfb-72dd-4bd8-b739-4f92f873e6ca` and the app's UI-action log. The last
five-position calibration ran from 21:40:38 to 21:41:58 PDT: all four sampling
moves and the return completed, ending Idle at X 247.770, Y -25.881 with no
controller alarm/error lines during the attempt. The UI then reported the
calibration request refused. The timing and runtime sequence place the failure
after return, in fit/holdout validation; the retained log does not establish the
exact rejection detail or prove that zero matching cap pixels caused it.
Cancel, Restart, Cancel and Reset All Learning were subsequently accepted.

The Learning presentation omitted the retained camera failure, and its reset
sheet completion could overwrite newly published progression with a captured
pre-reset exercise. Both are corrected. Resetting from Exercise 1.1 also clears
the current source's cap appearance and stops its old automatic color analysis.
A new calibration attempt reacquires its reference frame and current pose.
Video settings expose frame-qualified detector diagnostics; a zero-match frame
reports **No pen cap detected**. Older diagnostic text never authorizes stale
geometry. Existing holdout, exact-frame, settlement and no-redraw checks remain.

The 64-test focused SwiftPM run passed, covering reset completion in either
publication order, clearing a selected LIVE cap, missing-cap failure and lease
release, diagnostic camera identity, visible failure detail, and fresh-reference
retry. Validation receipts are retained under `.build/cap-recovery-a4da8f-evidence/`.
The first cold compilation was interrupted by an additional source fix; the
stable-source rebuild and focused tests passed. No hardware commands, live app
restart, or attended physical cap/reset validation were performed by this task.

## Portrait drawing-plane correction, 2026-09-13

Task `task-d53998adea1f4068b350adbddd8d93ae` began from clean primary main
`f2a26618ede6dc4f33195166a3460d8b00ec8495` and recorded target main. The relayed
operator request identified that the main viewer's independent height/ink sliders
were display estimates rather than actual placement. They are removed. The current
region controls viewer aspect ratio; the exact selected candidate's matching
admitted artwork plan supplies placement and intrinsic dimensions. Draft exposes
its already computed artwork plan before optional border composition, guarded by
the current execution-plan hash. No extra plan or execution owner is introduced.

Missing/mismatched placement remains an explicit reference preview, preserving
screen ratings and training. New labels retain validated optional display evidence;
legacy labels, thumbnail rendering and training feature semantics remain unchanged.
Applicable active material supplies marker width, otherwise an identified program
nominal estimate. Actual size/profile changes retain the existing readaptation gate.
The coordinator owns contracts/integration; bounded workers own Studio controls,
label compatibility and pure/production-fixture regressions. Validation and review
receipts are retained in `.build/studio-plane-d53998-evidence/`.

The one-shot critic reviewed immutable patch
`b5d3e5bd538ea7ae893d328280b6a058a57d06ab9698e96335a3b36b68f2b3d5` and found
one P2 compilation issue: ambiguous CGFloat/Double infinity in a new test. The
coordinator qualified CGFloat directly. No additional production defect was found;
there was no repair recheck or repeat aggregate review. The first compiled focused
run passed the new preview tests but the existing full journey refused material
adaptation, causing downstream assertion failures. The original assertion did not
retain the refusal string. Isolated diagnostic and full diagnostic reruns passed;
therefore the initial refusal's exact cause is not claimed as proven. The fixture
had no explicit join between material selection and its queued Draft update. It
now joins that existing task and requires the plan's material hash before returning;
the journey also stops and records the actual refusal if adaptation fails.

The strict diagnostic run passed 76 tests in 33.177 seconds, with the existing
opt-in native AX test skipped. After the fixture change, all 8 final plane and
complete campaign integration tests passed in 12.227 seconds. These exercise
real planner points at 0/90/37 degrees, translated non-square regions, uniform
line width, exact source/region mismatch handling, border composition, stale
material applicability, reference rating persistence, historical display stability,
legacy bytes and operational training/activation/update/rollback through the
existing production journey. Failed and passing receipts are retained. The strict
signed-app build, launcher checks and negative-bundle validation passed. Final
ledger edits are checked by the documentation and diff gates before landing.
Exact landed commit, build-input binding, signature and binary hash are recorded
in `release.json`; the immutable `AdaptivePlotter-Plane-d53998.app` and
`PLANE-TEST.md` provide the staged native test increment.

The previously repaired native app remains running as PID 81462 during this task.
The new preview artifact will be staged without launch or session replacement.
Native acceptance of this viewer, independent physical dimensions, material/ink
outcomes and real human learning quality remain pending.

## DS-09 native startup failure and split delegate repair, 2026-09-13

The operator explicitly authorized closing the live session and launching the
immutable DS09 app at `69551f0092aaaf543bd7aa1c05f4f122ac763d47`. PID 56095 completed
a normal application quit. The launcher verified the exact signed bundle and
executable as PID 77465, with regular activation policy and foreground activation.
The subsequent native accessibility read exposed the Studio controls and two
retained drawings, but the process crashed before any test control action ran.
The crash report records `EXC_BAD_ACCESS / SIGSEGV` on the main thread, with
repeated `NSSplitView(NSSplitViewSidebar) respondsToSelector:` frames: a stack
overflow. Startup/launch success does not satisfy native acceptance.

`WorkbenchNativeSplit.NativeView` assigned itself as its delegate. AppKit's
optional sidebar-selector forwarding could therefore return to the same split.
Repair task `task-b3361e346e9e469a9251a0112e34a5b4` began from clean primary main
at the DS09 commit and recorded target main. A separate retained NSObject delegate
now forwards resize and divider constraints to its weakly referenced split owner;
membership, host identity, autosave and layout calculations remain with that owner.
The coordinator owns production and lifecycle; one bounded worker owns the native
split regressions. A bounded windowless reproduction distinguishes the selector:
an unknown selector returns normally on the old self-delegate, while querying
`toggleSidebar:` terminates that subprocess with SIGILL before returning. The
same sidebar query returns false normally with a separate NSObject delegate.
The retained reproducer crash report has the same recursive NSSplitViewSidebar
stack as the actual app. The first strict focused run passed all 15 tests in
20.031 seconds, including the complete production campaign journey, hosted Studio
and workbench layout, delegate lifetime, nested resizing and divider constraints.
The coordinator then added the exact fatal `toggleSidebar:` query to both split
regressions. All 15 final strict focused tests passed in 18.957 seconds; signed-app,
launcher and negative-bundle checks passed. The fresh one-shot repair critic
accepted frozen patch `ed14029b9d55ccf0a30f1e1068867d6ad0341beaf70f367507cf2cf5dca400c5`
with no findings. It reviewed only the new split repair and affected consumers;
the final aggregate campaign review was not repeated. Documentation and diff
checks passed; the final receipt update is verified by the same documentation gate.
Exact landing, source-input binding, signature and binary identity for the retained
`AdaptivePlotter-Native-b3361e.app` are recorded in the repair `release.json`.
The exact repaired commit `f2a26618ede6dc4f33195166a3460d8b00ec8495` was then
launched as PID 81462. Native accessibility actions selected the retained Tonal
contour drawing (42 strokes), created More Like This (34 strokes), and used Parent
to restore the exact original. The retained archive remained two drawings / 3.3 MB.
The actual 1680 × 932 window and responsive controls were recorded. This is partial
native acceptance; it does not cover the complete G08 sequence or human quality.

Exact launch, accessibility and crash receipts are retained in
`.build/studio-ds09-99b539-evidence/native-acceptance/`; new repair receipts belong
in `.build/studio-native-b3361e-evidence/`, including `native-acceptance/` for any
subsequent exact-release native checks. No physical drawing, controller settings,
camera selection, rating or training action was issued. The original immutable
DS09 app remains unchanged. Full native interaction, physical metric/material/ink and
real human learning-quality acceptance remain open.

## DS-09 integrated campaign acceptance, 2026-09-13

Task `task-99b539b9170e46b3b15ff5610768739e` began from clean primary main
`3e1f353109a4fd26820d1b8131204824650fa19e`, recorded target main. The coordinator
owns the complete production journey, worker acceptance, one final cross-feature
critic, repairs and landing. Bounded workers own the existing view-action extraction
and fixture plumbing, paired material pixels through the current registration, and
the attended runbook. The projection/material handlers move to the application owner
so the UI and integration test use the same typed actions and final-scale checks.
No alternate renderer, planner, machine owner or evidence archive is introduced.

Runbook preparation found a concrete target gap: the old square and rectangle do
not express the predeclared 40 mm holdouts and the catalog had no visible source
selector. Exact square-with-diagonals and 40 x 20 rectangle entries, a Test Target
menu and explicit 100% action now prepare those plans through ordinary Draft
intents. Selection does not dispatch motion or bypass containment/paper/Draw.
The first strict compile rejected coordinator test comparisons against a
non-Equatable candidate; tests now compare complete serialized payloads. The first
journey requested a scale between the UI's 0.01 steps; it now submits an actual
available step. The complete journey then passed in 8.689 seconds (two journey
tests in 9.925 seconds). Broader affected-consumer validation exposed the
coordinator's visibility regression: catalog edits must preserve a hidden target.
That behavior is restored, with a separate existing Show Target intent in the menu.
These are coordinator repairs before the single aggregate critic, not repeat reviews.
All 65 focused tests now pass in 29.463 seconds, including the complete journey,
actual typed target preparation, existing hidden-target behavior, and affected
catalog/Draft/material/training/native-hosted consumers. The optional
`journey-verified/` receipt retains the synthetic authoring/training/material and
drawing stores, exact plan and terminal record, checkpoint/dataset/candidate IDs,
scoped label and original-frame hashes, and explicit unobserved coverage. These
are software fixture artifacts, not physical ink or human quality evidence.
The single aggregate critic reviewed R01-R36 against frozen patch SHA256
`ff9880e77fded36e575ea7e691bb6ef4963e655b4ba7200ea928379b811c57a9` and the retained
journey. It returned one P2 documentation finding, F1/R35: DS-02 and DS-05 still
listed delivered DS-06 software associations as open. The coordinator corrected
both canonical rows to acknowledge pre-dispatch candidate association and measured
material/raw-media integration through DS-09, while retaining all native/attended
limits. Direct receipt/row comparison verifies the repair; no critic recheck or
replacement review is performed. The critic found no actionable production
integration defect and explicitly retained the zero-covered-pixel and bounded-width
limitations. Final validation passed all 1337 strict serial quick tests in 392.765
seconds with six explicit skips, all ten journeys in 3.232 seconds, and the signed
app, launcher, negative-bundle, documentation and diff gates. The post-review
repair changes documentation only; reviewed production source is unchanged.
The immutable unlaunched DS09-99b539 app's exact landed commit, source-input binding,
binary digest and signature are recorded in `release.json`; its short procedure is
`DS09-TEST.md`. Receipts belong in
`.build/studio-ds09-99b539-evidence/`.

The canonical R01-R36 register remains in the campaign plan. This evidence map
binds its software claims to delivered slices and the final journey; it does not
promote any pending native, real-label or attended result. Existing slice receipts
below remain authoritative for their respective runs. DS-09 references are
verified by the final focused and serial runs recorded above.

| Requirement | Software evidence path | Remaining non-software acceptance |
| --- | --- | --- |
| R01 | DS-01 transform trace; PortraitGeometryTests; DS-09 per-segment actual-plan checks | Physical transform trace |
| R02 | DS-01 proportional placement/catalog tests; DS-09 segment lengths at 0/90 degrees | Independent physical proportions |
| R03 | PortraitGeometryTests extreme/minimum raster sampling cases | None for sampling contract |
| R04 | DS-01 explicit rotation/hash invalidation; DS-09 exact target placement | Native rotation interaction and ink |
| R05 | ControllerAxisMetric/Store/Calibration tests; AxisMetric production/startup tests; exact targets | Axis association, uncertainty, real firmware and independent holdouts |
| R06 | PortraitPreferenceCollection/CandidateStore tests; DS-09 transient branch then rating/projection/attempt | Native qualifying interactions |
| R07 | PortraitCandidateStore/AnalysisEvidence tests; DS-09 exact source/raster/program reload | Actual capture provenance |
| R08 | PortraitPreferenceDataset/Collection tests; DS-09 label revisions and candidate lineage | Real labeled dataset |
| R09 | CandidateStore/CheckpointStore/MaterialPersistence tests; DS-09 durable reload and raw assets | Native restart/recovery interaction |
| R10 | DS-02 no-FIFO/persistence failure tests; DS-08 retained-size UI | Native storage feedback |
| R11 | PortraitProposalPolicyTests declared family distribution | Human contour/style balance |
| R12 | PortraitExplorationHistory/Integration tests; DS-09 exact parent/branch recovery | Native branch navigation |
| R13 | PortraitBrowsing/ExplorationHistory and DS-08 composition | Native photo/style distinction |
| R14 | PortraitSemanticHeadGeometry/Integration tests | Blind human likeness and supported-feature review |
| R15 | SemanticHeadGeometry/Compatibility and FaceLandmarkAnalysis tests | Real pose/landmark/warp evaluation |
| R16 | PortraitSemanticTrainingProduction and TrainingProduction tests; DS-09 named scope | Real Big Head/scoped labels |
| R17 | TrainingProduction/CheckpointStore; DS-09 reload, revised labels, full-refit child, activate/compare/rollback | Native lifecycle and human quality |
| R18 | PortraitPreferenceDataset source/session/ancestry grouping; immutable checkpoint manifests | Frozen real source-grouped holdouts |
| R19 | OrdinalTraining/CheckpointStore/TrainingProduction failure and cancellation cases | Native recovery feedback |
| R20 | PreferenceCollection; DS-09 distinct screen and physical presentation contexts | Actual displayed/physical ratings |
| R21 | DS-06 attempt context; DS-09 adapted candidate/program/plan/material linkage | Attended physical run |
| R22 | DrawingRun evidence/episode tests; DS-09 pre-dispatch staged attempt | Real partial/Stop outcome |
| R23 | DS-06 media tests; DS-09 paired material and realization raw-byte reload | Actual before/after images |
| R24 | DS-06 observation-pose planning and capture-boundary tests | Physical reachable clear pose |
| R25 | DS-06 bounded coverage/mask/provenance tests | Actual observed coverage |
| R26 | DS-06 cancellation/ambiguity no-reposition/no-redraw tests | Attended Stop behavior |
| R27 | DrawingMaterialContract/Library tests; DS-09 current applicability binding | Actual tool/mount/paper/feed |
| R28 | DrawingMaterialMeasurement tests; DS-09 actual estimator on paired pixels | Independent width measurement |
| R29 | Measurement filled-hole/pooling/occlusion/resolution cases | Real exclusion/uncertainty review |
| R30 | MaterialFeasibility/PortraitMaterialIntegration; DS-09 current-plan-scale adaptation | Actual gaps/detail/deposited width |
| R31 | Immutable candidate/checkpoint/plan tests; DS-09 original/parent/child retained bytes | Native edit expectations |
| R32 | DS-08 layout; DS-09 shared production projection/material actions | Actual native control sequence |
| R33 | DS-06 physical gallery; DS-09 retained candidate, record, originals and rating reload | Native gallery/image interaction |
| R34 | DrawingWorkbenchComposition camera locality/held Stop; DS-08 hosted layout; DS-09 held Draw Stop | Keyboard/scroll/resize and live camera workload |
| R35 | Exact slice releases; DS-09 complete journey and final critic F1 directly repaired | Full native and attended acceptance |
| R36 | Separate release receipts and pending columns; DS-10 predeclared runbook | Real-label/physical evidence remains pending |

### DS-10 attended acceptance remains pending

Software implementation and target preparation are delivered. No native keyboard,
scroll/resize, live-camera workload, independently measured geometry/material,
attended drawing or real source-grouped likeness/learning-quality result is claimed.
The current live session and transient captures have not been replaced by the
coordinator. Replacing/restarting that session requires the operator's authorization
for the exact retained app; physical settings/motion require their own reviewed
attended action. Previously reported two border lengths still lack confirmed exact
axis/sample association, opposite-side measurements and uncertainty.

The next dependent action is authorized native acceptance on the exact release,
followed by the campaign section of the Attended Hardware Runbook: retain measured
frame edges, review any resulting settings proposal, reacquire dependent Learning
if applied, and evaluate distinct 40 mm/diagonal/40 x 20 mm holdouts. Collect actual
material/image/likeness evidence with frozen IDs, methods and tolerances. The
operator supplies attendance and independent measurements; the coordinator binds
receipts, diagnoses actual failures and implements any resulting correction. These
external evidence gaps remain open R05/G08/G10 and real-quality acceptance, rather
than being relabeled complete from synthetic software checks.

## R05 independent axis metric implementation, 2026-09-13

Task `task-9935a6df0be84c4bb2d9a07ffbcf49ac` began from clean primary main
`a13f2160fdab819efc4825fc2be4e144ea8c64e7`, recorded target main. The coordinator
owns contract acceptance, drawing-evidence persistence, typed controller admission,
geometry transition, startup reconciliation and integration. Bounded workers own
metric value contracts, the existing lower controller/interpreter capability, and
the measurement editor/identity composition. No settings have been written and no
reported physical lengths have been accepted. Independent axis association,
measurement uncertainty, held-out geometry and attended behavior remain pending.
The strict focused suite passes all 78 tests in 32.179 seconds. Integration exposed
and repaired an existing reset mismatch: Boundary-forward rewind persisted a
Stage-Four-free prefix but retained its active checkpoint. The same reset owner
now clears that active suffix. Production tests exercise passive measurement save,
durable preparation/reset before a partial settings write, zero writes on prefix
save failure, shutdown joining and exact evidence-only retry. Lower tests cover
exclusive fresh-context admission, byte/ack receipts, readback and ambiguous failure;
startup tests cover interrupted transitions without firmware replay.
The one-shot critic accepted frozen patch SHA256
`94dfc3fb23ac5e6e22e8d1838d1c087f4d384f562425d2be1fb71e7f9290fd48` with no actionable
findings; no recheck was performed. The first full run completed 1331 tests with
one existing jog-cancel fixture assertion failure: the link write counter was
observed before the controller resumed and published its retained transmitted
state. The coordinator synchronized that test with the owner publication while
keeping Idle held; production code was unchanged after review. All 43 focused
controller/calibration tests passed in 7.443 seconds. Final strict serial validation
passed all 1331 quick tests in 380.954 seconds with six explicit skips, all ten
journeys in 3.291 seconds, and signed-app/launcher/negative-bundle, documentation
and diff gates. Native operator interaction, actual firmware transfer, independently
measured metric and attended drawing remain unverified. All ten prior test apps
were checked read-only: source commit, binary digest, signature and write protection
remain intact. The increment landed as `3e1f353109a4fd26820d1b8131204824650fa19e`.
Its immutable signed unlaunched app is
`.build/StudioTestApps/AdaptivePlotter-Metric-9935a6.app`; all 376 build inputs match
that exact commit. Binary SHA256:
`92a4f733b9d93240b31328872cb022a594ba85bc063ec56d0ae8af6738d79ece`.
Receipts are retained in `.build/studio-metric-9935a6-evidence/`.

## Unified Voice feedback repair, 2026-09-13

Task `task-aca1b29ebb094d6eaf06580766c72db1` began from clean primary main
`05a360f3261e6c4d7efd8c415f1403bf05a8ec7a`, recorded target main. The user clarified
that Voice off must stop both talking and listening, while Voice on must retain
consistent Pen raise/lower cues. One bounded worker owns native/shared speech
cancellation, another owns Voice interaction and view lifetime; the coordinator
owns application composition, production Pen consumers, review and validation.
The implementation uses one application-owned controller and one existing speech
lane. Output starts disabled, mute drains active/queued work, and Pen-only Stop
allows its exact Stop during advisory playback. Coordinator acceptance found and
repaired an obsolete-enable race before compilation: each enable checks its exact
transition identity after prior drains, while every disable still executes. The
bounded internal invocation counter is diagnostic only, not action authority or UI.
All 58 focused tests pass under strict concurrency in 4.584 seconds, including the
actual production Pen runtime entering cancellation while its cue and lower
actuation remain held. Silent native queue seams cover creation/admission races,
queued cancellation and late callbacks. Documentation checks passed. The one-shot
critic accepted frozen patch SHA256
`915eda33c9c413c58b235ed859ec9ddbec8dd5478f27a40ffdb0b1e7a572a5d8` with no actionable
findings. No recheck was performed. The final source passed all 1293 strict serial
quick tests in 358.102 seconds, with six explicit skips, and all 10 journeys in
3.247 seconds. Strict signed-app, launcher, negative-bundle, documentation and
diff checks passed. No microphone, audio, controller action or live-session
replacement has been performed. Receipts are retained in
`.build/studio-voice-aca1b2-evidence/`. The repair landed as
`a13f2160fdab819efc4825fc2be4e144ea8c64e7`; its immutable signed, unlaunched app is
`.build/StudioTestApps/AdaptivePlotter-Voice-aca1b2.app`. All 366 build inputs match
that commit. Binary SHA256:
`682378986ff4d26362abb5b340caf7f5202924b2a6f6a90753f4b26224a09188`.

## Boundary replacement checkpoint repair, 2026-09-13

Task `task-33f1006713d949a9b9102709fa11ccfa` began from clean primary main
`1ced9c31e740766f653f33a4766bd23e6a21c69d`, recorded target main. This is the
reported campaign feedback repair, not a historical migration selection. The
coordinator owns staged checkpoint construction, retained-package policy and
post-publication Saved Learning reconciliation; a bounded worker owns the new
production regression tests.

Boundary persistence now constructs its staged machine checkpoint with the current
accepted Pen prefix. Changed Boundary revisions exclude dependent camera/tip/Stage
Four fields; inactive disk descendants are never borrowed. The shared retention
policy verifies the complete stored package before preserving it or replacing it
at the existing completeness threshold. An incomplete replacement is accepted for
this session while the old complete package remains durable. This single-package
policy does not claim that both packages survive restart. Exact persistence/retry
and reset reservation ordering stay in the existing Boundary owner. The saved-state
projection is reconciled only after an accepted terminal and an exact match to the
persisted machine artifacts. All 43 focused Boundary/checkpoint tests pass under
strict concurrency in 9.465 seconds. Initial fixture failures are retained: the
historical package now uses coherent machine/camera/tip rebasing so its coordinate
revision actually differs, and reset assertions retain invalidated graph history.
Additional cases cover a changed retained disk package, restoration and exact retry
without repeated motion, and staging-only descendant pruning without publication.

The one-shot critic accepted frozen patch SHA256
`e05b43709477560773b0ca551e4e98b4b930869828e80e7d432688a73dc68861` with no actionable
findings. No critic recheck is requested. The first full serial run executed 1277
tests in 382.971 seconds with only two assertions failing in an existing Pen
preparation fixture. The lower Pen hold begins before `submit` returns its admission
snapshot to the application; the fixture now waits for both owned observations
before asserting UI state. All duplicate-operation/cancellation/settlement checks
remain intact. The coordinator directly verified the repair with 12 focused tests
in 19.381 seconds. The final frozen source passed all 1277 strict serial quick
tests in 380.188 seconds, with six explicit skips, and all 10 journeys in 3.371
seconds. Strict signed-app, launcher, negative-bundle, documentation and diff checks
passed. The reviewed production patch is unchanged; the coordinator's additional
change only synchronizes the Pen fixture with its existing admission publication.
No critic recheck was performed. The repair landed as
`05a360f3261e6c4d7efd8c415f1403bf05a8ec7a`; its immutable signed app is
`.build/StudioTestApps/AdaptivePlotter-Boundary-33f100.app`, with all 365 build inputs
matching that exact commit. Binary SHA256:
`7278a8a53fa272bb3c6eaf4d126e557e4e1312928848aa6c47f997875e8be9db`.
Exact landing/source/signature receipts remain in `.build/studio-boundary-33f100-evidence/`.
The test app remains unlaunched and the live session is unchanged.

Remaining work is DS-09 final software acceptance and DS-10 native/attended acceptance.
R05 software is delivered; native recovery, independent physical dimensions and
realized ink remain unverified.

### Physical metric feedback retained for the R05 correction

The operator reports physical border sides X 159.5 mm and Y 177 mm, with axis and
sample association awaiting explicit confirmation. A separate read-only diagnostic
task reports border record `6C9814D1-1942-47A3-BB94-0E0D941021A8` and actual
transmitted controller spans X 159.133 and Y 225.991 mm in session
`47eac855-9a89-4db5-ab8e-2658ef3a9642` (2026-09-13 21:46:36 UTC onward).
These imply provisional actual/controller scale factors 1.00230625 and 0.78321703.
The camera fit alone does not establish physical millimetres. Reported firmware
steps/mm already differ by axis; the missing product contract is independent
measured travel scale, not a hard-coded equal-step count.

Evidence ingress must identify the exact drawn frame and commanded axis spans,
retain independent measured lengths and uncertainty, and apply correction in one
canonical machine geometry owner. Opposite sides and a second length distinguish
consistent scale from backlash or slipping; two lengths do not prove orthogonality.
No factors are accepted from this report, no controller settings are written, and
no motion or live-app restart is authorized by it. Source evidence is retained at
`/tmp/adaptiveplotter-camera-metric-20260913-181418/`. The coordinator independently
verified the saved checkpoint and drawing-record envelopes and their SHA256 values,
then read the existing machine-session SQLite database in read-only mode. Four
hash-valid raw transmissions at sequences 11038, 11946, 12596 and 13504 contain
Y+225.991, X+159.133, Y-225.991 and X-159.133 respectively, consistent with the
saved frame. No matching run/program UUID was present in the bounded event range;
this is span consistency, not an independently proven wire-to-record identity.
The checkpoint retains $100=40.18235 and $101=45.09100. Exact ruler association,
opposite-side observations and measurement uncertainty still require the operator.
Read-only extracts are retained as `reported-border-wire-readonly.json` and
`reported-border-record-readonly.json` in the metric task evidence directory.
R05 independent physical acceptance remains open; its software correction is delivered.

## DS-08 integrated Studio workflow, 2026-09-13

Task `task-67ebf411bd1f4f56b784700168f26799` began from clean primary `main`
at `73b27535bcfb368d72e565d75ecda697c2591758`, recorded target `main`.
The coordinator owns application composition, material/paper presentation and
acceptance. Bounded workers own authoring/gallery/training layout, drawing
presentation/status, and actual hosted native-panel tests. The composition now
places creative work and galleries before projection, then placement/material,
paper and bottom Draw. The global Stop path remains in the toolbar. A quiet
Equatable run-status leaf receives only existing semantic run state outside the
scrolling panels. Generic content slots preserve the existing local drawing and
authoring state owners; all actions continue through their existing callbacks.
Initial strict compilation found a Swift Testing key-path macro issue and a
private hosted-panel test seam; both were corrected. The focused run executed 46
tests in 25.447 seconds, with one new native fixture failing because it omitted
the pending program required to project a typed selection request. All adjacent
tests passed. After that fixture repair, the hosted native test reached the panel
but its accessibility traversal exposed no section nodes. The host first shrank
to 128 x 0 after controller attachment; disabling host sizing and setting the
requested content size repaired that fixture. A separate known SwiftUI button
still exposed no accessibility identifier in this process, even after local
AppKit finishLaunching. Thus native AX workflow acceptance remains pending;
hosted geometry/selection and optional bitmaps are separate software checks.
All 47 focused tests now pass in 27.759 seconds, including actual hosted geometry,
retained selection and programmatic scrolling at 300, 390 and 600 points. The
strict AX workflow is explicitly opt-in (`PORTRAIT_NATIVE_AX_CHECK=1`) and skipped
by default; it is not a passed native receipt. Optional viewport/full-document
bitmaps exist at all three widths, but cacheDisplay omits some native button label
rendering, so those are not complete visual interaction evidence. Failed receipts
remain in `.build/studio-ds08-67ebf4-evidence/`. Documentation
checks passed. Offscreen native layout/AX evidence supplements rather than
replaces attended resizing, keyboard, capture, training and drawing interaction.
The one-shot critic accepted frozen patch SHA256
`f3cc2f3a89dc13f5db8c0709908203173d87b401fa1611e51ff6d4fff041b4cb` with no actionable
findings. Its coverage limits remain explicit: default geometry checks cover
retained selection rather than complete current-edit, keyboard, expanded training
comparison or physical-image-sheet interaction. The frozen source passed 1274
strict serial quick tests in 424.783 seconds, with six explicit skips including
the AX prerequisite, plus all 10 retained journeys in 3.543 seconds. Strict signed
app, launcher, negative-bundle, documentation and diff checks passed. No critic
recheck was performed. DS-08 landed as
`1ced9c31e740766f653f33a4766bd23e6a21c69d`. Its immutable signed, unlaunched
bundle is `.build/StudioTestApps/AdaptivePlotter-DS08-67ebf4.app`; all 364 build
inputs match the landed commit. Binary SHA256:
`766c82b5cc86cd1a877e00825ac9d4b85a28cc5d518c85272050a20d6f34ee2b`.
Exact source/signature/Blackdog receipts remain in `.build/studio-ds08-67ebf4-evidence/`.
The live app/session and previous signed test apps remain preserved.

### Reported live feedback retained for separate repair increments

Read-only triage on main `73b27535bcfb368d72e565d75ecda697c2591758` confirms
the Boundary persistence adapter combines a fresh machine candidate with inactive
saved camera/tip artifacts. Checkpoint dependency validation rejects the merge;
publication retry repeats it and reset correctly remains blocked while publication
is pending. Incident `/tmp/adaptiveplotter-boundary-reset-20260913-141958/` retains
the intact complete package `AE50D319-8A2B-4954-A07D-E371A5CF174A`, coordinate
revision 2. The rejected fresh revision remains unverified. Repair belongs in
staged checkpoint construction and existing retained-package policy, preserving
persist-before-publication and exact retry ownership. A later successful restart
does not establish a fix.

The user also requires one Voice switch: off means no talking or listening; on
means both. The current window-local controller disables input but does not gate
all shared workflow speech. A separate projected Pen Stop-only transition may
cancel enabled Pen cues; that overlap needs a production-consumer regression.
These code paths predate the campaign; the running binary and exact introducing
commit have not been established. Both feedback repairs remain outstanding and
must preserve the live session, advisory speech and physical authority boundaries.

## DS-07 operational named-style training, 2026-09-13

Task `task-2754912f55f24764920aa06ddc61cde3` began from clean primary `main`
at `9e13d4b5bd8f91e52b6f9836818344ce502d1d83`, recorded target `main`.
The coordinator owns C4, production proposal integration and lifecycle; bounded
workers own features/dataset/ordinal fitting, checkpoint storage, and the quiet
training controls. Checkpoints contain exact immutable label revisions, grouped
source/session/ancestry splits, fixed normalization, configuration and model state.
The cumulative-logit fit uses four ordered thresholds, regularization, finite
bounds and cancellable optimization/evaluation. Continued fitting is explicitly a
deterministic full refit with reset optimizer and exact compatible completed parent.

The production renderer creates a seeded pool of eight actual candidates. Fitted
utility, bounded diversity and 20 percent exploration choose the result. Ordinary
local exploration freezes source/crop/family/head; semantic training varies only
head amplitudes in the selected branch. Generation captures the checkpoint before
asynchronous rendering; activation cannot relabel existing candidates or projected
programs. Installation never activates a checkpoint automatically. Durable named
scopes, activation, prior/current comparison, update and rollback use the same
candidate and training owners. Historical manifests expose missing candidate assets.
Screen appearance and photographed physical-attempt objectives remain distinct.

Validation is in progress. Initial compile receipts retain repaired Swift type
inference and test-comment issues. The first executing focused suite ran 38 tests
in 25.876 seconds: ordinary and semantic production learning, changed rankings and
paths, grouped held-out evaluation, continued fitting, cancellation, captured
checkpoint identity and rollback passed. Three checks in a forged-index fixture
used JSONSerialization instead of the store's typed canonical encoding, so the
checksum rejected the input before the intended semantic association checks.
The typed canonical fixture repair preserves those exact rejection assertions.
All 38 focused tests now pass in 25.598 seconds. Documentation checks passed.
The reviewed tree passed 1269 strict serial quick tests in 361.108 seconds,
10 retained journeys and strict signed-app/launcher/negative-bundle gates. The
one-shot critic reviewed frozen patch SHA256
`a2df24a352ad7d59267b9e22d61a17af85380bdb1c028444310bc83a0d38788a`. Two P2 findings were
accepted: default-scope fitting was disabled despite its supported initialization
path, and an incompatible active ordinary checkpoint rejected local Big Head
branching after clearing the preview. The coordinator repaired both directly:
existing default-scope label identity is preserved, and incompatible local
requests use explicit renderer-prior provenance while retaining the exact head.
Both regressions and 35 adjacent training/browsing/branch tests passed in
30.037 seconds. The repaired tree passed 1271 strict serial tests in 364.894 seconds and
strict signed-app/launcher/negative-bundle gates. No critic recheck was performed.
A subsequent coordinator consumer check found rapid Random could bypass the active
checkpoint while a render temporarily cleared its completed candidate. Superseding
proposals now reuse the exact same-source history and retain their captured model;
an initial unavailable source analysis reports pending instead of silently changing
policy. The held-renderer regression and all 19 affected production, semantic,
browsing and branching tests passed in 22.944 seconds. The full-suite receipt
above precedes only this localized supersession repair; its final focused and
strict signed-app receipts identify the release tree. Receipts remain in `.build/studio-ds07-275491-evidence/`.
DS-07 landed as `73b27535bcfb368d72e565d75ecda697c2591758`. Its immutable
signed unlaunched app is `.build/StudioTestApps/AdaptivePlotter-DS07-275491.app`;
all 362 build inputs match the landed commit. Binary SHA256:
`33799f41c2d0af98b11e5a194faa962c88abfecb18a264d2da98378a7f59dc7a`.
Release receipts and the test procedure are in `.build/studio-ds07-275491-evidence/`.
Synthetic preference fitting, native operation, real held-out learning quality and
attended physical outcomes remain separate gates.

## DS-06 durable physical attempts and original images, 2026-09-13

Task `task-1807468af632464ba4628a3817c9b6c2` began from clean primary `main`
at `be5a772659dd21f8cb48548c55f890e3c2201601`, targeting `main`. Three bounded
workers owned evidence storage, drawing execution, and observation geometry/coverage;
the coordinator owns projection identity, material plan provenance, gallery/label
consumers and integration. The initial 146-test strict focused suite and signed
app/launcher/negative-bundle/documentation checks passed. The broad strict serial
run completed 1239 tests with 16 issues confined to eight portrait-raster fixtures
that omitted accepted movement bounds. Those receipts remain retained.

New attempts stage the full immutable executed plan/program, original projected
candidate program, reconstructable registration and material/actual conditions.
Candidate retention is joined before motion; original baseline pixels and a
monotonic possible-dispatch marker precede ink dispatch. Terminal records seal raw
result frames and comparison provenance. Restart distinguishes preparation from
possible ink and never dispatches motion. Stop remains latched through lower
completion, result capture and terminal publication; failed/ambiguous/cancelled runs
cannot begin photo travel. Shutdown joins the exact owned publication.

A bounded observation plan prefers geometric clearance inside accepted movement
bounds; up to three matched poses are possible when clearance falls short. Raw
frames and exact source/pose associations remain owned even when comparison fails.
Coverage uses bounded existing alignment and explicit visible/occluded/unknown masks,
with transparent unknown pixels and retained per-pixel original provenance. The
store verifies composite pixels against actual content-addressed original bytes.
Production armature visibility remains unknown; pose choice is not a visibility proof.

Physical gallery images are recovered from the existing archive and image store.
Their ratings name the exact physical attempt, terminal record and result-image
hashes under a separate objective. Material inspection now installs its actual raw
images through the same store before retaining a measured revision. A material
revision changes exact plan provenance while preserving artwork/placement. New
registration hashes canonicalize capture-session Set order. Old candidate and nil
material-plan encodings remain unchanged.

No test app from this increment has been launched and no live session was replaced.
Native interactions, physical image coverage, marker accuracy, geometry and likeness
remain pending. The R05 independent metric and DS-10 attended gates remain open.
The one-shot critic reported three accepted issues: possible-ink geometry across
provenance/restart, post-settlement image freshness, and recoverable failed writes
of available originals. All three repairs passed direct verification in the 170-test strict serial
focused suite (171.711 seconds), including the eight repaired raster workloads.
The critic did not recheck. A subsequent 1247-test strict serial run found six fixture-clock issues: its
synthetic camera/UI clock was mixed with the run owner system clock. Explicit
composition clock injection preserves the production default and fixes that
fixture without relaxing assertions. All 51 affected consumer tests passed
in 32.585 seconds. Final gates passed: 1247 strict serial tests in 334.436 seconds (five existing
skips), 10 retained journeys in 3.321 seconds, and the strict signed debug app,
launcher and negative bundle validation. Final documentation/whitespace receipts
accompany landing. Frozen review patch SHA256 is
`97bde386c20d4fbf15f5c076950eeee4498b65db4badf3cfdf6011d39b5ca601`, with
receipts in `.build/studio-ds06-180746-evidence/`. Landed commit
`9e13d4b5bd8f91e52b6f9836818344ce502d1d83`; immutable signed unlaunched app
`.build/StudioTestApps/AdaptivePlotter-DS06-180746.app`.

## DS-05 material measurement and placed-scale adaptation, 2026-09-13

Task `task-e8792f04a5ad4066bd8375db8831128d` began from clean primary `main`
at `29a45a3e51d395b7112076502c040349a396e30e`, with recorded target `main`.
The coordinator owns C3, production composition and candidate/draft integration;
bounded workers delivered measurement, durable library/controls and placement
feasibility, then exact-image inspection, archive validation and preview context.

The material library owns immutable revisions and active selection in an atomic,
checksummed Application Support store, including rejected/corrupt-save visibility,
retry and deletion identity preservation. Material selection does not change
machine geometry, accepted tool contact or controller authority. Applying a
material creates a new exact-raster candidate at the actual placed height and
preserves placement; material and scale changes expire its adaptation. Its profile,
width qualification, measurement limitations and height are frozen in recipe and
program provenance. Preview and screen ratings use those defaults, with explicit
unmeasured overrides. Placement feasibility reports clear-gap/useful-length policy,
short strokes and close parallel pairs with bounded work and incomplete status.

The estimator measures two observed edges in controller coordinates, projecting
inverse-mapped separation onto each actual path normal. It includes all affine
covariance terms, residual, pixel and blur uncertainty. Drawing Border uses its
existing matched-pose pair; calibration marks use a distinct one-image local-paper
mode with no fabricated baseline or deposition attribution. The exact 2 mm-radius,
16-chord geometry is retained. Occlusion, crossings, pooling, short segments,
multiple/unresolved bands, contrast failure and inadequate resolution are explicit
exclusions. Broad marks cannot yield isolated interiors on the short ring chords.

Production inspection shows frozen actual images before an exact-frame visibility
assertion. Original material/paper/feed/actuation conditions are operator-declared,
not recovered from missing drawing requests. Sample centres remain in the accepted
mark-centre hull. Edges may extend at most 2 mm for diagnostic affine inference;
per-sample Euclidean extrapolation forces conditional bounded qualification and
retains the unquantified out-of-domain model error. This does not expand motion
or calibration authority. Sampling thresholds, scan cap and budget are retained.
No independent physical-width accuracy is established. Raw image ownership remains
DS-06 work; frame references alone are explicitly insufficient.

The focused strict run passed 50 tests, including actual hull-edge Border geometry,
sheared/directional widths, ring/filled-centre exclusions, cancellation, material
storage/reload/failure/deletion, malformed evidence, exact candidate branching,
actual-height adaptation, preview/rating context and literal legacy recipe hashes.
Earlier compile receipts retain coordinator repairs for a private hash helper,
Swift tuple inference, and equality assertions over intentionally non-Equatable
archive values. Two archive round-trip failures exposed an incorrect validation
assumption: the aligner's evaluated-pixel count sums candidate shifts, rather than
unique image coverage. The validator now uses the declared bounded workload.

The one-shot critic identified two P2 defects: the enclosing record digest also
needed capture-session set normalization, and production shutdown bypassed the
material flush. The coordinator repaired both without critic recheck. The added
regressions verify measured-record hashing in separate processes (32578 and 32593
retained the same digest), a deliberately held material write during production
observation shutdown, and revision allocation after deletion. Successful projection
retention now completes before the independent feasibility assessment.

The repaired focused run passed 54 tests, including unchanged capture timing tests.
The complete strict quick-test set passed all 1202 tests with five explicit skips
when run serially (243.971 seconds). Two unrestricted parallel runs are retained:
the first hit two existing capture entry deadlines, and the second passed those
but hit the existing 250 ms Stop acknowledgement assertion at 427.719 ms. This is
an unresolved full-suite-load timing limitation; no timeout was enlarged and no
native responsiveness claim is made. All three assertions passed unchanged in
the serial run. Native controls, independent deposited widths and attended physical
behavior remain pending. No live application/session was replaced or restarted.

Receipts: `.build/studio-ds05-e8792f-evidence/`, including frozen review patch,
finding dispositions, failed and passed logs, process restart evidence and the
signed-build release receipt. The strict signed debug app, launcher, and negative
bundle validations passed. Documentation and whitespace receipts accompany release.

## DS-04 semantic Big Head, 2026-09-13

Task `task-8037d07cff77461cae9104933de40a3a` began from clean primary `main`
at `b868effb80a383b81da042c9331a950a70a61278`, with recorded target `main`.
Bounded workers delivered semantic geometry, retained Vision analysis and literal
legacy archive fixtures; the coordinator integrated schemas, producer, candidate
integrity, model ownership and controls.

New analysis retains revision-3/76-point Vision regions in exact decoded top-left
pixels, optional observed pose, confidence and raw precision/classification.
Semantic geometry uses original crop metric and orthonormal eye/nose axes, compact
C2 fields with per-step derivative norm at most 0.2, fixed lower-face/boundary
regions and conservative analytic displacement/Jacobian bounds. Forehead anchors
are estimates; ears have no observed support. Unsupported profiles, unknown pose,
missing parts, low confidence or insufficient support preserve base geometry with
a reason. The manifest owns analysis digest, anchors, basis, kernel coefficients
and bounds; v4 program provenance and candidate integrity bind its exact digest.

Raster schema 3 retains original encoded schema versions on legacy decode. Optional
semantic fields remain absent from older recipes/candidates. Literal DS-02/DS-03
encoder goldens and exact archive reload tests guard existing identities. Explicit
new semantic generation refreshes a legacy raster lacking face analysis; local
proposals use the exact parent raster and freeze head settings. Legacy head-transform
local exploration is refused with explicit new-generation guidance; archived exact
vectors remain usable.

Initial strict compilation exposed a Vision adapter type error: raw precision values
are Swift Float values, not NSNumber. The coordinator supplied the optional compactMap
result type and converted with Double, preserving both failed build receipts.
The first corrected portrait run completed 120 tests with one coordinator fixture
failure: a flat image requested contours and legitimately produced no candidate.
The fixture now requests hatching. A production supported-warp/candidate roundtrip
was added; its initial Swift argument-order compile error was corrected before
execution. Final strict integration passed 25 tests (`integration-corrected.log`),
including actual warped program provenance and exact manifest/raster/candidate
roundtrips, semantic source reuse, pose/feature/Jacobian fixtures and archive goldens.
The broad strict gate passed 1,155 tests with five intentional opt-in skips (`quick.log`).
The fresh one-shot critic accepted the frozen diff without findings (`review.txt`);
no recheck occurred. Stable-local signed debug bundle, launcher and negative bundle
checks passed (`validate-app.log`). Final documentation and whitespace checks passed
(`docs-final.log`, `diff-check.log`). No native pass is asserted.
The signed immutable test app is staged after landing at
`/Users/bullard/Projects/AdaptivePlotter/.build/StudioTestApps/AdaptivePlotter-DS04-8037d0.app`;
`release.json` records exact landed commit, input equality, binary hash and signature.
Receipts: `/Users/bullard/Projects/AdaptivePlotter/.build/studio-ds04-8037d0-evidence/`.

Software geometry/identity tests are distinct from blind paired human likeness
assessment, native interactions and physical evidence, all still pending. No app
was launched or user session replaced. Material and run-media work remain DS-05/DS-06.

## DS-03 balanced exploration and exact branches, 2026-09-13

Task `task-d79ffc73deea418696794d53d641c57b` began from clean primary `main`
at `0edc1df68c44a88a7d27dcadea024e52016110c7`, with recorded target `main`.
Landed commit `b868effb80a383b81da042c9331a950a70a61278`, tree
`8374382746e7c9baddc6b86354db00207239450d`.
Disjoint policy, transient-history and UI workers implemented frozen interfaces;
the coordinator integrated source ownership, additive candidate serialization and
asynchronous proposal/restoration behavior.

Broad policy `portrait-proposal-v1` declares weights 30/30/30/4/3/3 for contour,
tonal contour, clean line, hatch, crosshatch and sketch-plus-hatch. A 10,000-seed
fixture produced counts 2970/3031/2944/430/341/284. Local proposals preserve exact
source/raster/crop/mask, analysis, family and head settings while varying relevant
bounded line/tone controls. Requests pin parent/proposal/checkpoint metadata before
awaiting rendering. More Like This supersedes a held import without concurrent
workers or stale source publication.

The independent transient history preserves exact available programs/rasters through
parent/back/forward/child navigation, including archived sources after photo eviction.
Payload and visit bounds report unavailable expired/oversize history; they do not
evict qualified archive records. Generation/navigation alone do not retain candidates.
A qualified child owns its payload and parent metadata, not full unqualified ancestors.
Additive pose/proposal metadata preserve DS-02 IDs when absent, and existing v3
programs retain their exact legacy pose token. A configuration callback after restore
or local submission does not replace the candidate with a global-pen rerender.

Initial strict-concurrency/warnings-as-errors focused validation passed 60 tests
(`focused.log`), with the supplied-photo opt-in test skipped. Final integration/policy
validation passed 24 tests (`integration.log`), including archived-parent Back and
held-import supersession. One fresh critic accepted the frozen diff with no findings
(`review.txt`); no recheck occurred. Stable-local signed debug bundle, launcher and
negative bundle checks passed (`validate-app.log`). The first broad run completed
1,135 tests with one timing failure outside the changed code: the recording-store
non-cooperative timeout check took 8.262 seconds against its unchanged 8-second
limit (`quick.log`). The isolated unchanged test passed in 0.034 seconds
(`isolated-timeout.log`). The unchanged full retry passed all 1,135 tests with five
intentional opt-in skips (`quick-retry.log`). No timing assertion was relaxed.
Final documentation and whitespace checks passed (`docs-final.log`, `diff-check.log`).

Receipts are in
`/Users/bullard/Projects/AdaptivePlotter/.build/studio-ds03-d79ffc-evidence/`.
The immutable test app is staged after landing at
`/Users/bullard/Projects/AdaptivePlotter/.build/StudioTestApps/AdaptivePlotter-DS03-d79ffc.app`;
`release.json` binds its exact landed commit, source-input equality, executable hash
and signature. Prior signed apps and sessions remain preserved.

This increment covers G03 software and applicable R06/R08/R11–R13/R31 behavior.
Native interactions and aesthetic/held-out quality remain unverified. Big Head still
uses its preceding geometry pending DS-04 semantic landmarks; measured material and
physical attempt imagery await DS-05/DS-06. No hardware/camera/motion was started.

## DS-02 durable qualified candidates, 2026-09-13

Task `task-1eef1162fd8d4694b578aa756b79c61d` began from primary clean `main`
at `251d3546a2417ebad046a7e66bb849c404cd4325`, with recorded target `main`.
It landed as `0edc1df68c44a88a7d27dcadea024e52016110c7`
(source tree `781df21c25b11ca9dfd6c8c297e98948872a20d5`).
The persistence, exact-analysis and UI workers had bounded disjoint leases;
the coordinator integrated immutable render snapshots and projection acceptance.

Source and analyzed-raster blobs are content-addressed and verified before atomic
checksummed index association. The retained renderer-source bytes are normalized
image bytes, paired with original oriented dimensions; no discarded original import
file is claimed as an owned asset. Exact crop/sampling/contrast and applied mask
alpha are retained. Capture sessions, recipes, full vectors, lineage metadata and
producer/checkpoint identities survive serialization. Generation alone stays
transient; shortlist, any 1–5 rating and complete successful projection acceptance
retain the exact candidate. The fourth reason, physical attempt, has a tested typed
storage seam; its production runtime association remains DS-06 work.

Qualified retention has no FIFO count/byte eviction. The gallery survives recent-photo
eviction; labels preserve immutable presentation/scope revisions. Explicit deletion
keeps historical identities while excluding old labels, even if identical content is
retained again. Failed saves preserve queued current work. Corrupt assets/index are
reported without replacing the damaged index. Interrupted asset installation is
identified; committed deletion cleanup resumes on load and reports retryable failures.

Strict concurrency/warnings-as-errors validation passed 82 portrait tests in the
initial frozen tree (`focused.log`). One fresh critic returned one P2 finding:
interrupted deletion cleanup could be reported saved after restart (`review.txt`).
The coordinator accepted and repaired it, then passed 29 focused checks including
committed-deletion restart and injected deletion failure/retry (`repair-focused.log`).
`finding-dispositions.json` records the disposition. No critic recheck occurred.
The final broad strict suite passed 1,118 tests with five intentional opt-in skips
(`quick.log`). Stable-local signed debug bundle validation, launcher checks and
negative bundle/signature checks passed (`validate-app.log`). Final documentation
and diff checks are recorded in `final-docs-check.log` and the landing receipt.

Receipts are retained at
`/Users/bullard/Projects/AdaptivePlotter/.build/studio-ds02-1eef11-evidence/`.
The reviewed patch, final build-input manifest, finding disposition and release
receipt distinguish the reviewed tree, coordinator repair and exact landed binary.
The immutable test app is staged after landing at
`/Users/bullard/Projects/AdaptivePlotter/.build/StudioTestApps/AdaptivePlotter-DS02-1eef11.app`;
`release.json` binds its landed commit, executable hash and signature after staging.

This increment establishes C2 and the applicable G02/R06–R10/R20/R31/R33 software
paths. Semantic landmarks (DS-04), physical-attempt/media integration (DS-06),
operational fitting (DS-07) and final integrated layout (DS-08) remain separate work.
Native interaction, learning quality and attended physical evidence are unverified.
No existing test build, running app/session, camera, controller or accepted Learning
was replaced or started.

## DS-01 proportional geometry correction, 2026-09-13

Implementation task `task-34dc69ed47f94ed695a7e7da85632890` starts from primary
`main` at `8d9b68a4b707f788e2383fbb03002dd1e9f54984`; Blackdog records target
`main`. Landed commit `251d3546a2417ebad046a7e66bb849c404cd4325`
(source tree `61ff80d03c04a66c501feaf99917ceaf61e75c25`). This first increment corrects source metric loss across bounded image
sampling and removes implicit Fit rotation. It does not close DS-01's physical
metric requirement or the rest of the campaign.

The reproduced failure is concrete: a 4000 x 100 source previously became a
160 x 8 raster whose sample intervals defined a 159/7 = 22.714 aspect rather than
40. An earlier 1200-pixel thumbnail reduction could also round source proportions.
The corrected acquisition contract carries original oriented dimensions beside
bounded normalized bytes; crop extents use original pixel coordinates and the
vectorizer maps sample centers through that metric. New v3 program identities bind
the metric/sampling convention. Existing accepted programs are immutable. Fit uses
one uniform scale at the explicitly selected rotation. A stable pre-correction
runtime test reproduced the old 90-degree automatic rotation instead of 0 degrees.

Strict-concurrency/warnings-as-errors focused geometry, capture, portrait and draft
validation passed 84 tests (`focused.log`). `make docs-check` passed. The first
broad strict run exposed one obsolete assertion in the dense portrait observation
fixture that expected automatic 90-degree Fit. Its setup now explicitly authors
90 degrees before fitting, preserving the same rotated observation workload and
all existing outcome assertions. This is a changed-contract fixture correction;
the final broad rerun passed 1,102 tests with five intentional opt-in skips
(`quick.log`). Strict retained journeys passed 10 tests (`journey.log`).
`make validate-app` passed with the stable local signing identity, including
launcher identity/logic and negative signature/plist checks (`validate-app.log`).
One fresh critic accepted the frozen diff with no repair findings (`review.txt`);
its scope excludes native, physical and subsequent campaign claims. The coordinator
verified the unchanged production source after review and owns final staging.

The reviewed patch SHA-256 is
`e3d433911ecc986d748c351da1fbe87308248bef59e569f5696e64094e6d9274`.
`build-inputs.json` binds every build/test input and Swift version. The final
immutable signed test bundle is staged after landing at
`/Users/bullard/Projects/AdaptivePlotter/.build/StudioTestApps/AdaptivePlotter-DS01-34dc69.app`;
`release.json` in the evidence directory binds the exact landed commit, executable
hash, bundle signature and source-tree equality. This is a separate unlaunched
bundle; the Git landing does not update a running binary.

Retained validation/fixture directory:
`/Users/bullard/Projects/AdaptivePlotter/.build/studio-ds01-34dc69-evidence/`.
`reproduced-fit-failure.log` records that expected failure. The earlier
`invalidated-initial-build.log` records a coordinator scheduling error: source
changes overlapped compilation. That run is invalid validation evidence; subsequent
checks use frozen source. Exact source PNGs, analyzed rasters, programs, plans and
registration/projection payloads from the geometry fixtures are software evidence.

Read-only inspection of
`/Users/bullard/Library/Application Support/AdaptivePlotter/AcceptedArtifacts/accepted-learning-path-v1.json`
(SHA-256 `4a4cc8bc690ed243b1e8a7e28fa38dd586ee104ce3ecb260c38c28b4e6295808`)
found camera basis lengths 1.69740775884 and 1.34708846321 pixels per nominal
controller unit, ratio 1.26005663711, and included angle 91.10027544913 degrees.
These establish camera projection anisotropy, not physical axis distortion.
`DrawingPlacement` and `DrawingPlanner` preserve controller-coordinate similarity;
`RunInterpreter` emits plan deltas through `MachineController`'s nominal G21 units
and three-decimal wire quantization. The exact-plan camera projection and uniform
view aspect-fit are downstream presentation. No independent physical length or
orthogonality evidence was found, and no inverse-camera axis correction is applied.
The canonical DS-01/DS-10 protocol records the required independent measurement.

R01/R02/R03/R04 software geometry, C1 identity and R31 immutable plan behavior are
this increment's scope. R05, physical R02/R30, and the reported physical stretch
remain open. Measured material/final-size behavior awaits DS-05. Native interaction,
attended drawing, physical alignment and likeness are unverified. No running app,
existing test bundle, camera, controller or stored Learning was replaced or started.

## Trainable Drawing Studio planning, 2026-09-13

Task `task-2cc60c7340414b9ebcbec83e275333ec` records the coordinator-ready
[Trainable Drawing Studio campaign](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md#trainable-drawing-studio-campaign-2026-09-13).
Assessed source base: `69ba9df7b752516780d98c051bc966316f970f13`.
This is planning-only work: the coordinator and three workers assessed current
source, geometry, authoring/training choices, persistence, realization evidence,
material measurement and UI integration. The canonical plan contains requirements,
dependencies, worker ownership and separate software/native/attended gates. It
did not implement or validate those future behaviors. At the planning snapshot all
campaign tasks were pending; current implementation states are in the campaign ledger.

The operator supplied a screenshot showing a sideways portrait planned overlay and
visible ink, reporting material X-axis stretch. A local evidence copy is retained at
`/Users/bullard/Projects/AdaptivePlotter/.build/trainable-studio-plan-2cc60c-evidence/user-reported-aspect-stretch.png`.
SHA-256: `0c23d4a79a4a676c754d2e5a75b3234b7ee18b5328d37f83f6b8cb54d9cdeecb`.
The screenshot is not bound to an exact original source, execution plan,
calibration or running build. No root cause or calibrated physical distortion
measurement is claimed from it. Uniform source/placement scaling does not establish
the physical metric; the plan requires tracing the full transform chain and an
independent attended check.

The selected first learning approach is planned native style-scoped ordinal fitting
and proposal/reranking over deterministic drawing and semantic-warp parameters.
Actual training, checkpoint activation, changed production generation, grouped
held-out evaluation and restart/rollback remain implementation requirements, not
results of this assessment. Retention is planned only for shortlist, any 1–5
rating, successful projection or physical attempt; generated/browsed candidates
remain transient. Full source/analysis/presentation context, run media and measured
material evidence have explicit future acceptance requirements.

No application source, runtime, hardware, camera session, physical plan or active
user app was changed or restarted by this planning task. No future implementation
test, native interaction, learning-quality or attended physical pass is asserted.

The initial frozen documentation candidate passed `make docs-check` and
`git diff --check`. Independent review identified three targeted plan corrections:
reuse the full placement already retained inside the execution plan, require
continued scoped fitting after checkpoint reload with explicit update/retry
semantics, and permit controlled native software checks under campaign execution
authorization while preserving the live user session. Those corrections are now
incorporated. The repaired candidate passed `make docs-check` and
`git diff --check`; the independent critic verified all three repairs and reported
no residual findings. Exact candidate hashes, validation logs and review closure
are retained under
`/Users/bullard/Projects/AdaptivePlotter/.build/trainable-studio-plan-2cc60c-evidence/`
in `final-planning-validation.json`, `final-planning-docs-check.log` and
`planning-review.md`. The coordinator's final receipt-only documentation check is
recorded separately in `landing-planning-validation.json` and
`landing-planning-docs-check.log` in that directory.
These documentation checks do not validate any planned application behavior.

Planning amendment `task-b415385e38224b0387c119542362f4cc` requires incremental delivery
to local `main`, with the reviewed, software-validated aspect-ratio correction as
the first user-testable release. Each user-facing increment must provide an
immutable signed test bundle and exact source/build receipts while later tasks
continue. Aggregate, native and attended completion remain separate from an early
software landing. The amendment changes the delivery plan only; it does not deliver
an aspect-ratio fix, build a test app, or replace the running user session.
The operator's follow-up also bounds reviews: each fresh critic gets one shot to
label findings within its assigned scope, without an arbitrary time limit.
There is no critic recheck. The coordinator owns triage,
worker retasking and direct repair verification. Existing receipts are reused, and
unresolved blockers remain explicit instead of starting another critic loop.

## Portrait style browsing and preference examples, 2026-09-12

Task `task-80e406d077854bc9959e49aa04e5b21d` builds on the studio capture work
without changing Learning, camera-role authority, Draw admission, or controller
execution. A host-display white window replaces canvas-only illumination; named
and seeded recipe browsing separates source-frame navigation from style navigation.
Angled hatch and face-anchored head emphasis add geometry beyond the previous
sliders. Exact source/configuration/pen cache keys support render reuse. Saved and
current candidates use one source-bound grading path, with bounded local examples
and explicit JSON export. No learned generator or automatic preference fitting runs.

The implementation review corrected saved-rating/export divergence, Random then
Previous returning an unrelated catalog item, same-thumbnail selection leaving a
saved drawing displayed, and reimported-photo metadata in saved-sketch deduplication.
The vector review found no remaining blocking geometry/provenance defect. These
are software reviews, not proof of likeness or physical line quality.

Verified against the final sources:

- Strict-concurrency/warnings-as-errors focused studio validation: 45 tests passed.
  The initial broader portrait run exposed one obsolete cache test that signaled
  analysis changes without changing options. It now changes actual options and
  verifies exact reuse when returning to the original configuration.
- Strict-concurrency/warnings-as-errors final `make quick-test`: 1,091 tests passed,
  five intentional skips. The last layout adjustment is included in this pass.
- The opt-in reference-photo render passed. Native offscreen 320- and 760-point
  editor snapshots and a six-recipe comparison were inspected. The reference is
  the same pinned APDrawingGAN tutorial image used by the prior studio work; no
  user photos were uploaded or checked into the repository.
- `make docs-check`, strict `make validate-app`, copied-bundle deep/strict signature
  verification, and `git diff --check` passed.

The signed debug app is staged, unlaunched, at
`/Users/bullard/Projects/AdaptivePlotter/.build/AdaptivePlotter-studio-style-80e4.app`.
Executable SHA256:
`a7263360a1e17374ad5d5b9ef500bb12eee1e044ee4d9d1c6874cee9f05c8a1a`.
Logs, reference renders, source hashes and verification metadata are retained in
`/Users/bullard/Projects/AdaptivePlotter/.build/drawing-studio-style-80e4-evidence/`.
These debug/offscreen results do not prove native browsing latency or physical
portrait quality. No user app instance, live camera, or plotter run was started.
Attended full-display lighting, native keyboard interaction, and ink quality remain
unverified.

## Pen readiness beside position recovery, 2026-09-12

Task `task-d431b9891cb949d28072588618977a00` addresses the operator having to open
Motion and raise the pen before camera position recovery becomes available.
The bounded correction composes explicit **Enable Motion & Raise Pen** with the
existing manual Pen Up owner and exposes the same typed **Raise Pen** retry and
plain prerequisite beside position recovery in both Learning and Drawing Studio.
Already-Up skips the command; Connect, passive probe and Disable Motion never
actuate the pen. Finite pen settlement retains its existing noncancellable owner
policy, with visible Raising Pen activity and no fabricated Stop capability.
Pen settlement remains separate from accepted Learning and physical-position
evidence. A cancelled enable caller still publishes a completed matching-session
authorization result, then prevents the automatic Pen Up successor.

The initial cold default warnings-as-errors build passed in 347.179665 seconds;
the cancellation-order build passed in 63.370773 seconds. Initial documentation
checks passed in 44.053550 seconds, including contracts and Python suites of 13,
9 and 39 tests. The first focused strict run failed compilation after 412.950613
seconds because a test did not explicitly discard a newly returned optional owner
result; zero tests ran. Its explicit discard preserves all publication/recovery
assertions. The next focused compilation failed after 118.816079 seconds on an
ambiguous overloaded test-helper argument; explicit `PenCommand.raise` resolves
that diagnostic without changing the typed slider behavior. Zero tests ran.

Inspection then found an order-sensitive profile gap: enabling before loading
different saved settings could leave Up attributed to the old profile. Restore
now reconciles the existing lower profile without motion, invalidates mismatched
Up/Down, and refuses while busy. That default build passed in 86.073523 seconds.
The first executed focused suite ran 21 tests with one issue in 17.953 seconds
tests / 59.394933 seconds wall: cancelling the enable caller returned before the
retained finite Pen owner published settlement. The production observer now joins
that exact effect through terminal publication before reporting caller cancellation;
no local Stop or second motion runner was added. The existing terminal assertion
remains unchanged. The final default warnings-as-errors build passed in 55.086435
seconds, and the focused strict suite passed all 21 tests in 17.883 seconds tests /
80.255001 seconds wall. The full strict quick suite then ran 1050 tests with
22 issues in 108.763 seconds tests / 111.553264 seconds wall, all in two retained
apply-before-connect regressions. Restore had published a lower snapshot before
the application owned a selected controller; the following selection retired that
apparent old session and erased restored Learning. The source now refreshes only
an already-owned application snapshot. Both original tests and their ordering are
retained, with explicit no-session-before-Connect assertions. The updated default
warnings-as-errors build passed in 46.907745 seconds. The pre-integration full
strict quick suite then passed all 1050 tests in 113.655 seconds tests /
115.785651 seconds wall, with five existing opt-in skips. The target branch
independently advanced to `19bb6a68b955c249c88e0a173027038add221db5`, adding the
portrait correction recorded below. The combined source passed default
warnings-as-errors compilation in 78.775467 seconds, strict quick validation with
1067 tests in 99.827 seconds tests / 226.811656 seconds wall (five existing opt-in
skips), and strict journey validation with 10 tests in 3.744 seconds tests /
5.231462 seconds wall. Combined-source strict signed-debug `make validate-app`
passed in 13.966002 seconds. The separately staged candidate is
`/Users/bullard/Projects/AdaptivePlotter/.build/AdaptivePlotter-pen-readiness-d431b989-reviewed.app`,
executable SHA-256
`a954fa16f4f6e05fc39ee71e92bc062f00b6734ab77011ff75049c074d60c30b`.
All 180 source/build input hashes match, and stable-local signing plus deep/strict
signature verification passed. `candidate-artifact.json` records provenance. The
bundle remains unlaunched. One full independent nonauthor assessment passed with
no actionable P0–P3 finding or residual issue. The assessor verified all 74 register
items against the integrated tree `28b2674d`, all 180 source/build inputs and the
signed a954fa16 candidate. No repair pass or delta verification was needed.
Final integrated documentation checks passed in 36.016895 seconds, including
contracts and Python suites of 13, 9 and 39 tests. Local Blackdog landing remains
the coordinator's next step; the authoritative target, commit and cleanup receipt
belong to task history and the final delivery report.

The earlier signed debug validation passed in 13.983225 seconds and staged
`/Users/bullard/Projects/AdaptivePlotter/.build/AdaptivePlotter-pen-readiness-d431b989.app`
with executable SHA-256
`57b8a9f6ebd2eb0a66c7c55907471355255a17c97c29d676380cd835e1857e45`.
Its 176 source inputs and deep/strict signature passed at that build. The finite
settlement correction supersedes this unlaunched artifact before assessment; it
is historical build evidence, not the final delivery candidate.

The baseline user app was not controlled or replaced by this campaign. During
source-only compilation, before any tests, its accepted-Learning package hash
changed; the other three monitored saved-state hashes matched. The external
`user-state-during-build.json` preserves both hashes and modification time.
At 22:37:25, a later read-only observation found baseline PID 80042 had exited
and no application process was running; this campaign did not request the exit
and its cause is not established. The original app binary still matched its
baseline hash, and all four immediate pre-test saved-state hashes matched.
`live-during-validation.json` records that observation. A subsequent observation
found a newly running primary-build portrait app at PID 88952, executable SHA-256
`20d00491a4a96dc617a69a7f4fbc40bb73a97fcbdd696ad4eb752e15c59d4834`, recorded in
`live-new-process.json`. That process does not contain this pen-readiness patch;
this campaign did not launch or control it. The 22:52:45 pre-landing observation
still found PID 88952 with the same 20d00491 binary. Three monitored authority/
archive hashes matched their immediate pre-test values; preferences had changed.
Together with the earlier initial-baseline package change, these observations
preclude an all-state-unchanged claim. No agent wrote that saved state or controlled
the running app. Native/performance and attended physical validation remain
unperformed; software results cannot establish physical pen lift or alignment.

## Drawing Studio burst capture and coarse portrait styles, 2026-09-12

Task `task-e5239da72d3642b49ef3697b3967ec12` changes only portrait authoring,
its permanent-canvas presentation, tests, and owning documentation. The existing
DrawingProgram handoff, Draw admission, Learning, controller, and paper owners
are unchanged. New behavior includes 3–5 second screen-lit portrait bursts,
independent camera cadence, bounded recent-frame selection/removal, adjustable
contour/hatch density and head framing, centerline Sketch styles, marker-width
preview, and bounded rated vector comparisons.

The settled focused strict-concurrency/warnings-as-errors run reported 46 tests
passed in 10.562 seconds, with the reference-photo opt-in skipped. It covers
capture retention, distinct post-settling frames, delete/cancel races, serial
worker settlement, illumination expiry during held encoding, raster reuse,
vector controls, camera-role ownership, and existing Drawing Studio readiness.
The separately enabled reference-photo test passed in 30.708 seconds. Its input
was the attributed [APDrawingGAN preprocessing example](https://github.com/yiranran/APDrawingGAN/blob/38f4319f8e724f6bef5a32c348a8c0967baad773/preprocess/readme.md),
retained outside the repository for internal software evaluation. Face crop and
person masking succeeded. Offscreen native views were inspected at 320 and 760
point widths, and the actual vectorizer produced a 15-variant style/preset grid.
At a displayed estimate of 1.5 mm ink and 180 mm drawing height, the sample's
crosshatch changed from 539 Fine strokes to 85 Broad marker strokes. This is
software geometry/display evidence, not observed physical pen width or likeness
acceptance.

The strict serial quick suite passed all 1,056 tests in 355.928 seconds, with five
existing opt-in skips, using `make quick-test` with
`SWIFT_FLAGS="--no-parallel -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors"`.
The independent strict `make validate-app` passed bundle, stable local signature,
and launcher validation. The separately staged, unlaunched debug candidate is
`/Users/bullard/Projects/AdaptivePlotter/.build/AdaptivePlotter-studio-e523.app`,
with executable SHA-256
`7d205c9c8f504fe9fd9acd01bb886615defa7e90affc00fb5b6e71b5c37c15ac`.
Its copied signature passed deep/strict verification. Validation logs, source-input
hashes, and inspected screenshots are retained under
`.build/drawing-studio-e523-evidence/` in the primary checkout. The final strict
parallel repeat of `make quick-test` also passed all 1,056 tests in 122.981 seconds
with five existing opt-in skips. Both complete suite modes now pass; earlier
nonpasses remain historical evidence rather than the final validation result.

Earlier nonpasses remain explicit: the first build rejected a test file edited
during compilation; the combined visual/lifecycle run had seven issues from
fixture wait timeouts and an offscreen host lacking the real pane's scroll wrapper.
Fixture vector creation now runs off the MainActor, visual evaluation runs separately,
and the offscreen host matches the actual scrolling pane. A subsequent parallel
quick-suite run reported 1,056 tests with 14 timeout issues across portrait,
camera-role, and voice fixtures. The legacy capture fixture now supplies a continuing
fake camera stream instead of one wall-time-scheduled post-exposure frame. No
production timeout, Learning behavior, or run lock was changed to accommodate tests.

Independent static review closed its findings on style-specific controls, explicit
saved-sketch selection, memory-limit feedback, and narrow capture-row layout.
Real face-camera cadence/exposure, attended native interaction, paper placement,
physical ink, and festival-portrait likeness remain unverified. The running user
application and its in-memory captures are preserved. The research-backed roadmap
distinguishes this local DoG centerline implementation from learned portrait models,
multi-view reconstruction, and unregistered frame averaging.

## Saved Learning physical-position correction, 2026-09-12

Task `task-c94d61ea72b34c8e9e1500d25f97900a` follows the operator's screenshot
showing physical drawing displacement and explanation that the unpowered
armature moves under gravity. The retained controller trace used relative
millimeter jogs with zero work offsets; 23 completed endpoints matched the
archived plan within 0.025519 mm. This controller-coordinate evidence did not
establish physical tip alignment or resolve the reported displacement.

The correction retains accepted Learning while requiring fresh camera/cap
position evidence before derived travel. Production typed requests cover coherent
rebase, exact-frame/source/context rejection, cancellation and failed persistence,
and immutable ink exclusion across repeated border-off/border-on runs. Old numeric
archive strokes are not projected through a newly rebased map; current calibrated
Boundary/Border and fresh program previews remain available. Boundary admission
and its effect identity carry physical applicability, including continuity loss
during Pen Up preparation. Direct manual controls remain independent.

A production placement defect was also corrected: embedding the full exact frame
in an action ID exceeded the UI compiler's 512-character bound. A compact placement
kind identity now survives compilation, while full reached frame/point intent and
current revisions remain checked. The regression requires altered-point refusal
and successful actual placement away from a possibly inked drawing.

Before the final prefix correction, the integrated strict quick suite passed
1035 tests in 90.650 seconds tests / 102.424 seconds wall, with five existing
opt-in skips. The strict journey suite passed 10 tests in 3.363 seconds tests /
4.615 seconds wall. Exact commands were `make quick-test` and `make journey-test`,
each with `SWIFT_FLAGS="-Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors"`.
The default warnings-as-errors build passed in 60.987 seconds. `make validate-app`
with those strict flags passed in 13.152 seconds. That pre-correction signed debug
artifact remains separately staged at
`/Users/bullard/Projects/AdaptivePlotter/.build/AdaptivePlotter-vision-c94d61ea.app`,
with executable SHA-256
`e4620ced5815be45397ee16720900826934b436381f4bfead25d10ea343944b5`.
Its stable local signature and 176 production/build inputs matched at that build.
It was not launched and is superseded for delivery by the final prefix correction.

Before independent assessment began, source review found that a contact-plane
change while pose was unverified cleared the tip owner's recovery availability
despite retaining the machine/cap map. The existing reset helper now rederives
that availability from the retained map only while visual verification is required.
Its production regression requires changed-plane invalidation, actionable and
successful camera recovery, tip and StageFour remaining invalid, retained Pen/map
and immutable archive, no lower motion effects, and available tip recalibration.
The reviewed-candidate command `swift build --scratch-path .build-default-warning-check
-Xswiftc -warnings-as-errors` passed in 205.178 seconds. The reviewed-candidate strict
quick suite passed 1036 tests in 88.577 seconds tests / 153.901 seconds wall,
with five existing opt-in skips; the new changed-plane regression passed in
6.539 seconds. The reviewed-candidate strict journey suite passed 10 tests in 3.343
seconds tests / 4.596 seconds wall. Reviewed-candidate strict `make validate-app`
passed in 12.636 seconds. The separately staged final signed debug candidate is
`/Users/bullard/Projects/AdaptivePlotter/.build/AdaptivePlotter-vision-c94d61ea-final.app`,
with executable SHA-256
`c58e163d441df0c918503c8404fc9fd8699aa46504d3c368deb904345a3d8715`.
Its stable local signature and all 176 production/build inputs matched
`plane-recovery-source-inputs.json` at assessment. It remains unlaunched and now
requires the consolidated assessment repair before delivery.

The sole full independent assessment reviewed tree
`43f908299c4aff10362b8c386ec2d604db54658e` and found two actionable issues:
F-01/P2 misclassified connected moving/actuating-Pen states as physical continuity
loss; F-02/P3 replaced the recovery owner's precise blocker with generic Pen Up/
camera copy. No P0 or P1 was found. Both findings require correction; this is not
an assessment pass. The one consolidated repair preserves busy connected states
while retaining real disconnect invalidation, and renders the actual recovery
owner reason through the existing button. New production tests hold manual Jog
and Pen operations in their actual lower busy states, cover transport loss while
moving, and inspect the actual recovery button for disconnected/in-progress/
available states. The repaired default warnings-as-errors build passed in 26.599
seconds. Repaired strict `make validate-app` passed in 12.247 seconds. Its new
separate signed debug artifact supersedes the c58e reviewed base for delivery:
`/Users/bullard/Projects/AdaptivePlotter/.build/AdaptivePlotter-vision-c94d61ea-reviewed.app`,
executable SHA-256
`bb0025909cf3afce163ce9eab0e2ffd1a0f8b3c4e3c1990c756763e3e84c6ce9`.
Deep/strict signature verification passed and all 176 inputs match
`repair-source-inputs.json`; the candidate remains unlaunched. The first repaired
focused run compiled but deadlocked in new test sequencing and was terminated
after 237.180 seconds, a nonpass. The corrected run passed both F-01 tests but
failed the F-02 test's capture-hold wait (three tests, one issue, 5.734 seconds
tests / 22.773 seconds wall). The test now binds the actual button request after
asynchronous fixture setup and reports early refusal rather than discarding it;
that earlier request result was not captured, so the timeout's exact cause is
unproven. The next run reached successful recovery but failed an obsolete
expectation that the recovery action would remain visible (three tests, one issue,
2.841 seconds tests / 14.603 seconds wall). The existing owner consumes that action after success;
the test now requires its absence and retains exact blocker/availability checks.
The final focused repair run passed all three tests in 2.957 seconds tests /
14.341 seconds wall. The repaired integrated strict quick suite passed 1039 tests
in 91.237 seconds tests / 92.974 seconds wall, with the same five existing opt-in
skips. The repaired strict journey suite passed 10 tests in 3.369 seconds tests /
4.644 seconds wall. All repaired Swift gates passed together on this candidate.
The same independent assessor completed the sole bounded delta after the one full
assessment and consolidated repair. F-01/P2 and F-02/P3 are closed; no residual
finding or new serious defect remains. The assessor independently verified repair
tree `ffaac914b6172463509e14f51bf6888b1fee670f`, all 176 source/build inputs, the
staged bb002590 executable and signature, and unchanged live-session state.

Complete documentation checks passed in 32.3758, 42.356, 30.795 and 31.076
seconds. Repaired documentation checks passed in 31.203834 seconds, including
contracts and Python suites of 13, 9 and 39 tests; working and staged whitespace
checks also passed. Earlier
failed runs remain historical in the task's external validation ledger and logs:
source/test compilation failures, the 71-test/58-issue fixture/contract run, the
mixed-build-cache link failure, the 72-test/6-issue and 72-test/2-issue runs,
narrow no-redraw failures, the 1033-test/four-issue Boundary admission run, the
42-test/two-issue asynchronous owner-test run, and the 1035-test/one-issue canvas
bootstrap run. The canvas fixture now joins its existing Draft/Run initialization
chain and retains all original full snapshot/action/Learning/revision assertions.
These failures are not passes and do not establish physical alignment.

The user's application (PID 60994) and saved state remain protected. The staged
candidate is not running in that session. Native/performance and attended
camera/pen/paper/ink validation were skipped; no hardware action was performed.
Voice stays parked, including its independently documented workflow speech path.
The validated correction has no remaining implementation, validation or assessment
blocker. The authoritative target branch, landed commit and cleanup receipt belong
to this Blackdog task's history and the coordinator's final delivery report.

## Default-build Motion reader warning, 2026-09-12

Task `task-c996a0e8390246288358802d786158d8` follows the operator's compiler-warning
report. A cold default build with Swift 6.1.2 in Swift language mode 5 reproduced
one unique warning, emitted four times, at `AdaptivePlotterApp.swift:315`:
converting the stored Motion reader to a MainActor/Sendable async closure may
introduce data races. The build completed in 278.65 seconds. Both stored reader
aliases already carried their concurrency annotations; the diagnostic arose at
the SwiftUI ViewBuilder forwarding boundary, not from a missing property annotation.

The preceding campaign's strict-concurrency/warnings-as-errors logs contain no
warning and remain valid evidence for that compiler configuration. They did not
establish warning-free compilation in the default mode, which this cold build
now demonstrates still warned. Logs and diagnosis are retained in the directory
pointed to by `/tmp/adaptive-warnings-current`.

The correction adds one explicit `@MainActor` annotation to `MotionPanel`,
preserving the existing annotated reader and behavior without a forwarding
adapter. A bounded SwiftUI reproduction confirms the original default mode
warns, original complete-strict mode is clean, and explicit actor isolation
makes default mode clean (`paper-warning-repair.md` and its probe logs).
The clean production default-mode command
`swift build -Xswiftc -warnings-as-errors` passed with **zero warnings** in
257.075 seconds wall (255.36 seconds compiler).
The first strict quick run compiled without warnings but stalled in the existing
production Stop/held-Confirm test. The coordinator interrupted it after 390.168
seconds; no test assertion was reported, and this is a nonpass. A sample showed
the owned helper idle; it does not establish the cause or attribute the stall to
the annotation. Without source/test changes, focused strict Motion readout,
status-receipt and Pen Interaction coverage passed **25 tests** in 1.592 seconds,
including held Confirm in 0.174 seconds. The full same-candidate strict quick
rerun then passed **1021 tests** in 110.866 seconds tests / 112.724 seconds wall,
with five existing opt-in skips. No source or test changed between these runs.
The interrupted attempt remains unexplained: read-only triage found that the
stalled test does not instantiate MotionPanel, but did not prove its exact
blocked await. No test repair or causal link to the annotation is claimed.
Strict signed-debug `make validate-app` passed in 14.672 seconds. The separately
staged bundle is
`/Users/bullard/Projects/AdaptivePlotter/.build/AdaptivePlotter-warning-c996a0e8.app`,
with executable SHA-256
`f252e4b5743fc21aae65bef9d9846d9f31c612b8f463f2e62bb52a571b0937f1`.
Stable-local deep/strict signature and task/staged byte identity verified;
`artifact.json` and the 283-input `source-manifest.json` retain its provenance.
Bounded independent review passed with no findings (`assessment.md`), verifying
the source boundary, default/strict results, all 283 inputs, executable hash and
deep/strict signature. The earlier interrupted quick run remains an unexplained
test-run limitation, not something the annotation is claimed to fix.
The user's app remains running as PID 60994 with its binary unchanged, and all
four saved-state hashes are unchanged. The candidate was not launched; native
input, performance and physical operation were not tested. Local landing and
finalization receipts belong to this task's history and the final delivery
report; this entry does not preclaim landing.

## Bounded paper, border, and Motion correction, 2026-09-12

Task `task-cceb274a51cd443696f191f1233ab3e4` implements the explicitly requested
correction on the Blackdog task workspace based on `da92596`. The prior four
corrections (`b08c136`, `9028087`, `dbe38f8`, `da92596`) are ancestors of this
candidate; they were not reset or blindly reapplied.

Production inspection identified an unconditional tip-runtime paper reset after
the same-plane declaration. That cleared accepted registration/checkpoint even
though the durable package and earlier successful Border record survived.
The candidate separates sheet-transient cleanup from contact-plane invalidation,
retains completed compatible Learning, and admits bounded reapplication of an
already-applied saved package through existing validation. The user's reported
first physical drawing remains a user report; inspecting retained records does
not independently establish that physical outcome.

Ordinary **Draw border** defaults off for each new drawing and uses the calibrated border owner;
selected geometry joins one immutable program/plan and ordinary run evidence.
Motion now reads the controller owner's actual receipt-stamped coherent report
through a visible 5 Hz observable leaf. Re-reading cached data does not refresh
its receipt. No new serial reader or UI query stream was introduced.

The integrated correction also refreshes the existing Drawing Run no-redraw
index for the newly committed paper through `restoreNoRedrawTruth`. Old records
remain intact, and same-sheet rejection remains enforced. Coverage confirmation
seals the actual visible frame only at the operator action, with no passive
hashing. The final paper handoff synchronizes after coverage cleanup and remains
joined through shutdown; partial checkpoint-save failure restores the exact
predecessor.

Integrated software validation on the candidate frozen for full assessment:

- Focused strict Swift run: **144 tests passed**, 12.752 seconds tests,
  14.307 seconds wall (`focused-final.log`).
- `make quick-test SWIFT_FLAGS="-Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors"`:
  **1021 tests passed**, 82.159 seconds tests, 92.616 seconds wall, with five
  existing opt-in skips (`quick-strict-final.log`).
- `make journey-test SWIFT_FLAGS="-Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors"`:
  **10 tests passed**, 3.149 seconds tests, 4.315 seconds wall (`journey-strict.log`).
- `make validate-app SWIFT_FLAGS="-Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors"`:
  passed in 12.697 seconds wall. The log confirms debug compilation, stable-local
  signing, launcher logic/validation and negative bundle validation (`signed-debug.log`).
- `make -n app` and `make -n app APP_CONFIGURATION=release`: passed and selected
  debug by default and explicit release respectively. These are configuration
  checks, not release performance measurements.
- `make docs-check`: final assessment-candidate contracts and **13, 9 and 39
  Python tests passed**, 28.691 seconds wall (`docs-final-candidate.log`).
  `git diff --check` also passed (`diff-final-candidate.log`).

The exact focused command was:

```sh
swift test --filter 'SavedLearningCompletionTests|PlotterArtifactResetEpisodeTests|PlotterDrawingDraftEpisodeTests|PlotterDrawingRunEpisodeTests|DrawingStudioPresentationTests|MachineControllerTests|ControllerStatusReceiptTests|MotionReadoutTests' -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

Commands, elapsed times and logs are retained in
`/var/folders/c0/zjcj7q3d0mzf06v_qmdjk3vm0000gn/T/adaptive-correction-b5e22xdx/validation.jsonl`.
Earlier runs did fail. Their unchanged logs retain compilation/fixture failures,
feedback-context self-dismissal, coverage-frame mismatch, paper-handoff/no-redraw
failures and Motion-isolation fixture synchronization issues. The final results
above supersede those candidates; they do not rewrite those failures as passes.

The signed debug candidate assessed before F-01 repair is separately staged at
`/Users/bullard/Projects/AdaptivePlotter/.build/AdaptivePlotter-correction-cceb274a.app`.
Its executable SHA-256 is
`6a73e6bc38bb35084ca45f0e6c1b976728a82e1b527284e3c5ff7fe13852496f`;
the task and staged executables matched at that build. The staged bundle validator and deep,
strict codesign verification passed with **AdaptivePlotter Local Development**.
Metadata for that initial artifact is retained as `candidate-artifact-pre-repair.json` beside the validation logs.
All four recorded user-state baseline hashes remain unchanged.

One full independent assessment by a subagent who authored none of the changes
reviewed the complete 51-item register, integrated diff, production owners,
test/deletion classification, actual logs and candidate artifacts. It independently
verified the frozen Git tree `5302ff142d4c843eee3d0d653593ef4edb0eeab5`, all 283
source/build/test manifest entries, the staged executable hash/signature, unchanged
user-state hashes, and absence of a running app.

The assessment found **one actionable P2, F-01**, affecting D-01, D-02, E-03 and
V-03: a failed typed Paper-menu transaction preserved/rolled back calibration
correctly but returned `.accepted`, suppressing the existing visible refusal
channel when Guided Learning was hidden. The bounded remedy is to return the
operation-specific transaction result through the existing typed refusal path,
preserving rollback and successful-retry clearing, with production typed-Paper
failure/retry tests. There were no P0, P1, other P2 or P3 findings. The full report
is retained as `assessment-full.md` beside the validation logs.

The consolidated F-01 repair is implemented: the existing paper transaction
returns its operation-specific result through the typed refusal channel.
`swift test --filter SavedLearningCompletionTests -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`
passed **7 tests** in 15.516 seconds tests (`repair-paper-strict.log`), including
metadata/checkpoint/coverage failure followed by successful retry for both
same-plane and changed-plane declarations (six combinations).

The first repaired full quick run still failed an existing computation-isolation
test (`repair-quick-strict.log`): one extra semantic projection build, outside
the passing Paper cases. Source inspection found that the test awaited Draft
facts while its existing Draft-to-Run publication could still be pending.
`OperatorWorkspaceComputationDiagnosticsTests.swift` now joins that existing
synchronization before measuring. All no-rebuild assertions remain, and runtime
revision equality is added. The failing log did not capture the specific
publication token, so this is source-grounded diagnosis rather than proof of
that exact historical token. The initial diagnostics filter selected **zero
tests** due to a filename/type-name mismatch; its corrected narrow filter ran
one passing test but did not close the full-run failure. The complete
`PlotterApplicationRuntimeComputationDiagnosticsTests` strict filter then passed
**14 tests** in 2.193 seconds tests (`repair-diagnostics-strict.log`).

Final repaired broad validation passed with the same complete strict-concurrency
and warnings-as-errors flags:

- `make quick-test SWIFT_FLAGS="-Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors"`:
  **1021 tests passed**, 80.716 seconds tests, 82.336 seconds wall, with the same
  five opt-in skips (`repair-quick-strict-final.log`).
- `make journey-test SWIFT_FLAGS="-Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors"`:
  **10 tests passed**, 3.117 seconds tests, 4.288 seconds wall
  (`repair-journey-strict.log`).

F-01 implementation and the diagnostics test adaptation are covered by those
repaired broad passes. The final repaired
`make validate-app SWIFT_FLAGS="-Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors"`
passed in **11.645 seconds wall**. The final signed debug bundle is separately
staged at
`/Users/bullard/Projects/AdaptivePlotter/.build/AdaptivePlotter-correction-cceb274a-final.app`.
Its executable SHA-256 is
`760750e2ad5046fe3b59d67a7e8009366f47bb725707774ad4ecb821b713ce55`.
Task/staged bytes match; deep/strict stable-local signature and bundle validation
passed. The 283 source/build/test manifest inputs are unchanged from the repaired
freeze. `candidate-artifact.json` records the final artifact, while
`candidate-artifact-pre-repair.json` preserves the initial one. All four user-state
hashes remain unchanged, no app was launched, and none is running.

The same independent nonauthor completed the sole bounded delta verification
against repaired tree `1415c4e7e586554d577cb3dc542ce9a2171e10bf`.
**F-01 (P2) is closed.** The delta verified operation-specific typed refusal,
all six failure/retry combinations, preserved atomicity and successful-retry
clearing, and the justified diagnostics synchronization adaptation. It found no
residual P0/P1/P2/P3 finding or newly introduced serious defect. It independently
rechecked all 283 input hashes, final staged executable/signature, four unchanged
user-state hashes and absence of a running app. The report is retained as
`assessment-delta.md`; this completed one full assessment, one consolidated repair
and one same-assessor delta, without another full review cycle.

`make docs-check` on the repaired candidate passed contracts and **13/9/39
Python tests** in 28.830 seconds (`repair-docs-final.log`); staged
`git diff --cached --check` also passed. There are no remaining implementation,
validation or assessment blockers. The coordinator's local Blackdog landing,
finalization and clean-target verification receipts belong to
`task-cceb274a51cd443696f191f1233ab3e4` history and the final delivery report;
this validated-correction entry does not assert that landing already occurred.
Pre-repair passes/hash remain historical evidence for that earlier candidate.
Earlier sections below remain historical validation for their own candidates.

No AdaptivePlotter process was running at the campaign baseline. No user app was
launched, stopped, restarted, or replaced, and user calibration/preferences/
captures were not edited. Native input, sustained preview performance and
attended camera/pen/paper/ink validation are not established by this campaign's
software work. The signed debug candidate is staged separately; staging does not
mean the user is running the corrected build. Voice behavior is unchanged,
including the separately documented workflow speech path for “Drawing the
four-edge Drawing Border.”

## Closable retained comparison review, 2026-09-12

Task `task-fac81af1e0674ca2bcf00ef65eff23bc` removes the permanent
"Comparison frame … is retained" canvas notification. The comparison box now
appears only during exact-frame review, and its **×** submits the existing
return-to-live request. Closing removes the box and restores live preview.
**Review Comparison** remains available in Video Settings to reopen the retained
frame; no separate dismissal store or evidence mutation was introduced.

The focused strict-concurrency, warnings-as-errors Swift run passed **59 tests**.
The production lifecycle regression closes and reopens through projected UI
requests, verifies the same exact frame and comparison data remain available,
and checks that Learning revisions and simulator position do not change on
close. Presentation state, semantic control parity, ambient preview isolation
and overlay tolerance checks also passed. Documentation and whitespace checks
passed. The default debug app build and strict stable-signature checks passed,
including validation of the staged copy.

The candidate is staged at `.build/AdaptivePlotter-comparison-fac81af1.app`
in the canonical checkout; executable SHA-256 is
`b7b0e6b6f75ff3b05a659ce0d5466d0e2b658b2aa5fec891a0184207d9ebaf46`.
Logs are retained under `.build/evidence/comparison-close-20260912/`.
This build includes the earlier Saved Learning Pen Up and Achtung title fixes.
The user's active app was not replaced or restarted. Native input, sustained
preview performance and attended physical behavior were not tested in this task.

## Saved Learning circle-action Pen Up admission, 2026-09-12

Task `task-a544918a8a2f4b36a97b7231fe1f865c` removes the redundant current-Pen-Up
availability condition from **Draw Four Calibration Circles**. The existing
stoppable batch already commands and settles Pen Up before its first travel.
An applied Saved Learning prefix through camera calibration can now start that
batch with current Pen Unknown or Down. Connection, Motion authorization,
controller readiness, camera, pose applicability and calibration prerequisites
remain in force. Capture-only checkpoint revalidation and camera calibration
retain their prior pen-pose checks. Applying Saved Learning itself issues no
motion or pen command. The instruction names the automatic raise, and the
toolbar's visible Stop title is now **Achtung!**, preserving its typed request,
Escape routing and accessible Stop description.

The focused strict Swift run passed four test functions, including parameterized
saved-prefix restoration with Unknown/Down pen states and settled/refused initial
raises. A held lower pen command admits no travel or strokes. Successful
settlement precedes the first travel; Stop during that approach leaves no ink.
A refused raise performs no travel. The retained Motion and LIVE-camera blockers,
complete saved-Learning restoration and existing four-circle outcome/recomputation
regression also passed. The full strict-concurrency, warnings-as-errors
`make quick-test` run passed its **1001-test suite** in 95.637 seconds with five
existing opt-in skips. Documentation and whitespace checks passed. The default
debug app build and stable local signature validation passed.

The verified candidate is staged at `.build/AdaptivePlotter-penup-a544918a.app`
in the canonical checkout; executable SHA-256 is
`907f1c53c602bc0bf93f2643a6ff1020e89a780f6cb2f701105858638999297f`.
Logs are retained under `.build/evidence/saved-learning-penup-20260912/`.
The user's active app was not replaced or restarted. All new motion verification
used software fixtures; no attended hardware or native-input gate was run.

The reported late "Drawing the four-edge Drawing Border." announcement was
traced to an unconditional workflow speech call, separate from the window Voice
toggle. Its source is recorded in the Roadmap's parked voice issue. Voice code
was not changed and the reported toggle state/audio sequence was not verified.

## Debug local app build default, 2026-09-12

Task `task-be6862cec7fb424b821476305412f401` changes both the Makefile app
configuration and the packaging script's no-argument fallback to `debug` at the
operator's request. This supersedes the release default recorded on 2026-09-07.
Explicit `APP_CONFIGURATION=release` remains available and is documented for
optimized performance measurements. The native-workbench runbook now describes
the landed v2 gate's four slots and permanent canvas.

The clean default app build passed with complete strict concurrency and
warnings-as-errors in 233.69 seconds. Recorded PlotterApp compiler arguments
contain `-Onone` and `-DDEBUG`. The signed bundle passed validation, including
after invoking the packaging script without a configuration argument. Default
and explicit-release Makefile dry runs resolve to the expected compiler and
packager arguments. Documentation, packaging shell syntax and whitespace checks
passed. No Swift application source changed in this task; the preceding
workbench suite remains the software evidence below. Native interaction,
sustained preview performance and attended hardware were not reclassified.

The verified debug candidate is retained in the canonical checkout at
`.build/AdaptivePlotter-debug-be6862ce.app`; its executable SHA-256 is
`7a169b374323da1de89a104f0eb8f6ee0ae74a4ce51090acbde8b2a91f03391a`.
Build, documentation and default-packaging logs are retained under
`.build/evidence/native-workbench-20260912/`.

## Permanent canvas and native control panes, 2026-09-12

Task `task-274de148854247b3b90195212b3f47ee` implements the
[approved presentation correction](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md#permanent-canvas-and-native-control-panes-2026-09-12),
integrated with `63890f6`'s observed-cap correction. The main canvas remains
mounted independently of control visibility. Native View commands fill right,
left, lower-right, lower-left; the fifth control replaces the oldest. Native
split views preserve the canvas host, resize columns and paired controls, enforce
minimum dimensions and restore saved divider positions. Badges, move menus and
the separate command strip are removed. The toolbar contains amber connection
and motion actions, diagnostic export, and the existing typed Stop in red.
Video Settings contains source/zoom/overlay controls. Imported/captured portraits
can occupy the main canvas; absent camera imagery uses an identified return-only
simulator preview without publishing evidence or changing execution environment.
Voice code and preferences are unchanged; the independent input/output controls
are parked in the Roadmap.

The strict-concurrency, warnings-as-errors `make quick-test` run passed its
**999-test suite** in 80.577 seconds. Five pre-existing opt-in rendering, supplied
photo and cost-matrix tests were skipped by their environment conditions. The
suite includes native offscreen geometry at 1000/1600 points, canvas-host identity
through every opening/closing, saved-divider restoration before initial window
sizing, native divider constraints, legacy preference migration, oldest-control
replacement, passive simulator state preservation, background diagnostic success
and failure, held-writer MainActor responsiveness, typed Stop and voice tests.
These native geometry tests inspect actual AppKit views; they do not establish
CGEvent menu/close/drag interaction or physical operation. The focused native
geometry/computation rerun passed 16 tests. Existing ambient-preview and analysis
isolation regressions passed in the full suite.

The first broad run exposed saved-divider initialization overwriting the saved
position; the corrected initial-size regression now passes. That run also hit
one extra projection build in the existing held-Pen-Up analysis-traffic test;
its semantic revision/actions remained equal. The test passed unchanged in the
focused and final broad reruns. The Drawing Run ordering fixture now reads the
other environment before capturing its LIVE publication, removing an await that
could admit a newer LIVE publication during a synchronous replay assertion.
Production Drawing Run publication and Stop admission are unchanged.

Diagnostics copies the same bounded existing-owner snapshot and writes formatted
JSON off MainActor to `~/Library/Logs/AdaptivePlotter/Diagnostics/`. No new event
stream, recorder, motion authority or learning requirement is introduced.
Documentation and whitespace checks passed. Evidence logs are retained under
`.build/evidence/native-workbench-20260912/` in the canonical checkout.

The release build completed with strict concurrency and warnings-as-errors,
and stable local signing verified. The byte-matched signed candidate is staged
at `.build/AdaptivePlotter-workbench-274de148.app` in the canonical checkout;
its executable SHA-256 is
`f84d049bcfde9ba8414f77d67aae33c970b444baa68d0adeadaf683003db2bde`.
Final release attempts of `make preview-performance-gate` (PID 36453) and
`native-workbench` (PID 36512) both stopped at exact-process activation before
measurement. They are **skipped native/performance evidence**, not passing gates
or failed performance measurements. Their full logs and native attempt artifacts
are retained with the release and software-check logs in the evidence directory.

The debug signed-app `native-workbench` attempt stopped before measurement:
macOS rejected activation of the exact spawned PID while the desktop was locked.
A separate diagnostic render attempt also failed the active/key/main-window
precondition. Neither is passing native interaction evidence. No attended camera,
controller, motion, pen, paper, click or ink validation was performed.

## Observed cap acquisition and calibration failure feedback, 2026-09-11

Live PID `24991` completed one calibration circle on each of three Exercise 1.4
attempts, then reached controller Idle and failed pen-cap measurement with
37, 17, and 4 component pixels against a fixed 51-pixel minimum. The minimum
was `1920 * 1080 / 40000`; the fixed C920 search crop began at image Y=151.
The accepted camera map predicted the second-corner cap anchor near Y=135.
That prediction was diagnostic; it did not select the old crop. No controller
alarm/error appeared in the inspected session. The Learning panel showed its
generic drawing instructions and Record Paper Replacement, hiding the original
failure reason. The live session database is
`~/Library/Application Support/AdaptivePlotter/MachineSessions/session-6580acfb-4f9c-496f-949d-319789848d78.sqlite`.

The correction searches the whole frame unless the operator explicitly locks a
generic scene region. Exact workflow acquisition ignores that generic lock. An
optional model prediction centers scan order and cannot exclude pixels, select
a candidate, or veto a measured location. Components are ranked by squared mean
similarity to the identified cap color times square-root pixel support. Fixed
component area, aspect, fill, confidence, near-equality-ratio, and inter-frame
centroid-spread rejection gates were removed. The final reveal also no longer
rejects fresh observations against the old 8-pixel map-residual limit. Residual,
spread, and component properties remain diagnostics. Revalidation before reuse
of a saved calibration remains separate from collecting new observations. Exact source/configuration/frame identity, fresh controller
settlement, cancellation, explicit motion authorization, and possible-ink
no-redraw behavior remain enforced. The sparse-tip failure prompt now preserves
the runtime's actual reason and explains marked-sheet recovery.

The captured window image `/tmp/adaptiveplotter-live-region-20260911.png` exposed
why largest-component selection alone was insufficient: an 8035-pixel pale
reflection beat the actual 2091-pixel cap. With color-support ranking, the cap
at window-image centroid `(2193.589, 768.371)` wins with score 18.483 versus
12.166 for the reflection. No prediction and an off-image `(-10000, -10000)`
prediction return identical measured cap geometry. This is offline window-image
replay, not exact camera evidence or attended physical validation. The result
is `/tmp/adaptiveplotter-cap-replay-verified.log`.

The detector serial quick suite reports **997 tests passed** in 136.842 seconds;
five opt-in tests were skipped. Regression coverage includes the cap outside
the old 1080p crop, a 16-pixel edge cap, wrong/off-image predictions, a larger
pale distractor, observed centroid variation, exact provenance/configuration
refusal, camera-lease cancellation, and failure copy with paper recovery.
The log is `/tmp/adaptiveplotter-cap-quick-serial.log`. The preceding parallel
run exposed an obsolete two-pixel-rejection expectation and a portrait-renderer
five-second setup timeout under load; the expectation was corrected and the
serial run passed without changing portrait behavior. Documentation and diff
checks passed. Final-reveal regression, release performance, and signed-app
evidence follow separately. Two subsequent serial runs exposed the existing
manual-motion publication test reading an asynchronously delivered workspace
snapshot before publication. Its assertion now waits for that snapshot;
production manual-motion behavior was not changed. Those logs are
`/tmp/adaptiveplotter-cap-quick-serial-final.log` and
`/tmp/adaptiveplotter-cap-quick-serial-confirmed.log`.

The strict-concurrency, warnings-as-errors release detector benchmark passed.
At 1920 by 1080, full-frame cap detection measured a 17.993 ms median and
18.244 ms maximum over eight iterations; cap plus armature measured 17.922 ms
median. This synthetic kernel measurement excludes content hashing, camera
delivery, UI rendering, and physical acquisition. The detector source was
unchanged by the subsequent final-reveal correction. The log is
`/tmp/adaptiveplotter-cap-release-cost.log`.

Final focused validation passed **56 tests** in 8.339 seconds, including
full-frame detection, exact camera acquisition, Learning failure presentation,
100-pixel mark and reveal prediction residuals, and Workbench Stop. The log is
`/tmp/adaptiveplotter-cap-targeted-final.log`. The final full serial run reported
997 tests with one Drawing Run publication-ordering failure in
`verifyDrawingRunPublicationOrdering` after a simulated/live switch; that test
passed in the focused rerun without a production change. This intermittent
full-suite failure remains recorded rather than claiming a clean final suite.
Its log is `/tmp/adaptiveplotter-cap-quick-serial-verified.log`.

The final strict-concurrency, warnings-as-errors release app build passed in
264.80 seconds and stable local signing verified. The signed executable SHA-256
is `e74273c92fb426f60fd6148a994fbe5f0cde95436d90543ba4877933c8e19ca0`.
A byte-matched candidate is staged at
`.build/candidates/cap-acquisition-20260912/AdaptivePlotter.app` in the canonical
checkout. Source hashes and copied logs are retained under
`.build/evidence/cap-acquisition-20260912/`. The first native preview attempt
found another native-workbench gate already running. After it exited, the
preview attempt launched its own exact process but macOS rejected activation;
no native performance measurements were produced. The log is
`/tmp/adaptiveplotter-cap-preview-final.log`. Attended camera/controller/cap/ink
calibration and resulting drawing-region alignment remain unverified; this task
issued no physical motion, pen, paper, or calibration commands.

## Camera freshness churn and portrait sheet confirmation, 2026-09-10

Live PID `14435` owned the canonical release bundle and plotter serial session.
The visible Draw refusal was **Confirm that the current sheet covers the drawing
area**; Drawing Border was accepted with an inconclusive background-residual
Vision comparison. No portrait Draw request had been submitted. With Diagnostics
closed, CPU exceeded one core and a two-second sample spent 1023 of 1367 main-thread
samples in AttributeGraph updates. The sample reached camera-frame receipt's
freshness-triggered semantic invalidation and full workbench projection rebuilds.
The diagnostic inputs are retained in `/tmp/adaptiveplotter-14435-main-20260910.sample.txt`,
`/tmp/adaptiveplotter-current-diagnostics-20260910.json`, and
`/tmp/adaptiveplotter-draw-controls-settled-20260910.png`.

The correction compares camera delivery with the last projected freshness state,
rejects older same-configuration frames, and preserves the one-second freshness
predicate. Explicit sheet confirmation prepares the current exact Draft reference
at the click; a context change during preparation still refuses it. Sheet and run
controls precede portrait preparation, and existing Diagnostics now includes the
Drawing Run refusal and Draft planning/submission refusals.

The new delayed-frame regression first failed with ten extra semantic/Draft
synchronizations and nine full UI rebuilds. It passes with zero extra counts,
while explicitly displayed stale-camera recovery still updates controls. A
production-composition regression also first failed when sheet confirmation
followed a newer exact analysis frame. It now retains that frame in the paper
assertion, reaches Draw readiness and exercises the existing held drawing and
retrospective evidence path. **48 focused tests passed**, covering computation
isolation, Draft admission, Drawing Studio presentation, production drawing
composition and diagnostic snapshots. Logs are `/tmp/adaptiveplotter-debug-focused.log`,
`/tmp/adaptiveplotter-debug-regression-before.log`, and
`/tmp/adaptiveplotter-debug-paper-analysis-before.log`. Documentation and diff
checks passed. These are software regressions; the live session has not been
restarted and no physical drawing, paper assertion, or motion was performed by
this debugging task. Updated signed-app performance and attended drawing remain
unverified until the current session can be restarted without discarding its
unsaved portrait captures.

The strict-concurrency, warnings-as-errors release build and stable local signing
passed. The byte-matched, signature-verified candidate is staged at
`.build/AdaptivePlotter-f9cea8b9.app` in the canonical checkout (executable SHA-256
`51516738da95e1ac99b7fcd96d7cad2b585ea07c6ef7552458fd2ad8a508491d`).
`make preview-performance-gate` stopped at its existing already-running-app
precondition, before measurement. This is **skipped native performance evidence**,
not a passing gate or a failed performance measurement. The release, gate, and
delivery receipts are `/tmp/adaptiveplotter-debug-release.log`,
`/tmp/adaptiveplotter-debug-preview-gate.log`, and
`/tmp/adaptiveplotter-debug-delivery-20260910.json`.

## Workbench and portrait correction, 2026-09-09

Task `task-26f65c0e4e7b4a3b9d445b26c59c86f0` implements five persisted dockable
panels, one selected camera in Video, quiet controls, retained portrait
preparation, upright/sideways fitting, complete saved Learning restoration,
canonical Draw readiness, and retrospective ordinary-run analysis.
[The execution plan](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md#workbench-and-portrait-completion-correction-2026-09-08)
owns the sole acceptance matrix.

**Software accepted and tested app delivered.** Full `make strict-check` run 31
exited zero. [Independent critic 9](/Users/bullard/Projects/AdaptivePlotter/.build/workbench-portrait-task-26f65c0-evidence/adaptiveplotter-task-26f65c0-independent-critic9-report.md)
found no remaining blocking software issues. Native camera/UI and physical
acceptance remain unverified because the desktop is locked. This record does
not claim Git landing or attended Learning/drawing success.

| Evidence | Executed result and limit |
| --- | --- |
| [Strict run 31](/Users/bullard/Projects/AdaptivePlotter/.build/workbench-portrait-task-26f65c0-evidence/adaptiveplotter-task-26f65c0-strict-31.log), [terminal receipt](/Users/bullard/Projects/AdaptivePlotter/.build/workbench-portrait-task-26f65c0-evidence/adaptiveplotter-task-26f65c0-strict-31-result.json) | **997 Swift functions passed, five opt-in skips, zero failures**, 82.031 s. Strict release compilation passed in 104.99 s and incremental debug compilation in 2.64 s. Signing, launcher, bundle, shell/architecture documentation, 13 pilot, nine metrics, 39 capsule, repository and final diff checks passed. |
| [Independent critic 9](/Users/bullard/Projects/AdaptivePlotter/.build/workbench-portrait-task-26f65c0-evidence/adaptiveplotter-task-26f65c0-independent-critic9-report.md) | Immutable 276-file review found no blocking software issue and closed the camera-role ordering finding. Held-source tests preserve newer role requests, exact publication and maximum one active capture. The Task-enqueue boundary has static proof, not a claimed deterministic reproduction. |
| [Delivery receipt](/Users/bullard/Projects/AdaptivePlotter/.build/workbench-portrait-task-26f65c0-evidence/adaptiveplotter-task-26f65c0-final-delivery-31.json) | At 11:10:17 UTC, the exact tested bundle replaced canonical app20 through verified staging. All bundle files and strict signatures matched. The prior app was retained; the launcher was already byte-identical. No app launch or native/hardware action occurred. |
| [Final inventory](/Users/bullard/Projects/AdaptivePlotter/.build/workbench-portrait-task-26f65c0-evidence/adaptiveplotter-task-26f65c0-pre-delivery-inventory-31.json) | At 11:06:55 UTC, the desktop still reported locked with `loginwindow` foreground; no AdaptivePlotter process or plotter serial owner was present. Learning/archive bytes and modification times matched the retained baseline. Delivery rechecked process ownership and unchanged store hashes. |

The tested [source manifest](/Users/bullard/Projects/AdaptivePlotter/.build/workbench-portrait-task-26f65c0-evidence/adaptiveplotter-task-26f65c0-candidate-31.manifest)
contains 274 entries, SHA-256
`8ab08f6a66084dfc4bebbdc702c71a801107cc4a49b8c5ebd174b46d40d6cc93`.
The 14-entry [build/document manifest](/Users/bullard/Projects/AdaptivePlotter/.build/workbench-portrait-task-26f65c0-evidence/adaptiveplotter-task-26f65c0-candidate-31-build-doc-inputs.manifest)
has SHA-256 `5f6004acdcf9e6259c8a63446dac09a0f9f8f9fe52d343fe82cd4df1ad799b39`.
Both had no drift during strict31. Final progress updates include prose and two
current-architecture expectations in `Scripts/check_episode_contract.py`; their
documentation/diff validation is separate from strict31. Production Sources/Tests
and app build/launcher inputs remain unchanged, as does the delivered binary.
The five skips are the 1080p kernel cost matrix, supplied reference photo,
minimum-width native Learning rendering, noisy native Canvas and dense native
Action Surface rendering. They are not passing native evidence.

The delivered [AdaptivePlotter app](/Users/bullard/Projects/AdaptivePlotter/.build/AdaptivePlotter.app)
has executable SHA-256
`95feb954cad2512872039459edd93597ae0c72d43203df46fb49bb647a3244a0`,
UUID `F3E60893-F5A2-3B3F-860F-064F4898D55C`, and local-development signature
CDHash `69a5fa38e5719bfa47ae7eba57e36d5d1c816592`.
The delivery receipt retains exact bundle/launcher identities and backup paths.

Software proof includes immediate production Show/fit/adjust/Draw with matching
program/plan identities, all accepted saved milestones with Unknown/Down Pen
pose, canonical refusal/remedy, 120 ambient and 30 post-drawing acknowledged
frames with unchanged semantic/root/draft counts, and held cancellation,
publication and shutdown settlement. Held-Draw Stop acknowledges before lower
release and publishes one exact terminal; it is software ingress proof, not a
native click or actual-controller Stop.

Synthetic raster/archive/residual tests pass the +0.60/−0.40 mm contour case
within 0.1 mm tolerance and all 191 finite-width hatch paths under the unchanged
five-million observation budget. Alias, shifted-ROI, cancellation and crosshatch
cases also pass. Iteration-limit, rank-loss and competing-basin gaps are explicit
coverage limits, not demonstrated defects. These synthetic observations do not
establish physical ink accuracy. The [retained evidence index](/Users/bullard/Projects/AdaptivePlotter/.build/workbench-portrait-task-26f65c0-evidence/INDEX.md)
links earlier diagnostics;
run-11/12 contour timings used a smaller displacement and cannot support an
unchanged-workload speed comparison.

**Unverified native and physical work:** Native20/22 reached zero controls or
inputs. The normal macOS lock began at 00:10:16 PDT, before those attempts and
native14–16; the latter failures cannot be attributed exclusively to SwiftPM
hosting. Normal unlock has been requested, with no successful retry recorded.
No lock or permission bypass was attempted. Actual acceptance still requires:

- All 15 panel/dock combinations at 1000/1600 points, visible canvas/body controls,
  native scrolling/resize/hide/On-Off/Stop, and six workbench images.
- The 20-switch, 90-second learned camera workload with actual analysis,
  quiet-text and native latency receipts.
- Fresh controller/camera/Pen/paper observations, inkless native jog/Stop, and two
  distinct physical portraits with exact frame pairs and ordinary residual records.

The retained archive has no eligible real ordinary/training record for the
retrospective native prerequisite; holdouts remain unchanged and cannot be
relabeled. The physical scenario preserves app/evidence on failure and never
redraws automatically. Gate schemas, software fixtures and controller-query
receipts cannot stand in for observed motion, pen contact, paper or ink.

Historical evidence below remains unchanged and does not describe the new
panel/camera contract or current observer where behavior differs.

## Canvas geometry deadband and trigger audit, 2026-09-08

Blackdog task `task-a942cd2f248b4cd29c9e2dfeef29109e` follows the redraw-isolation
change below. The Canvas had still compared full measurement identity, so a new
frame ID or tiny measured-coordinate change could invalidate identical or nearly
identical drawing. Its exact visual equality now compares only drawn geometry,
style, labels, admitted target visibility, source/configuration, and viewport.

Passive LIVE cap and armature rendering now uses an **8-screen-point deadband**
against the last displayed scene. Retained geometry preserves its original
measurement frame and both visible/accessibility captions identify that frame.
Motion beyond the threshold refreshes the coherent scene group, including when
many small moves cumulatively exceed it. Zoom changes the camera-pixel threshold
so the tolerance stays fixed in screen points. Viewport changes, geometry
removal/topology, source/configuration changes, exact-frame interaction, and
operator/planned geometry bypass the deadband. Canonical measurement values,
frame matching, and click transforms remain exact.

Strict focused/native tests passed **18/18**. After the initial exact-to-ambient
caption/layout transition settled, an `NSHostingView` running the production
Action Surface accepted 30 new measured frames with up to **4.8 screen points**
of jitter and produced **zero Canvas view builds and zero actual redraws**.
A **9.6-point** move and entry into exact review redrew immediately. The separate
2,001-point overlay test also retained its Canvas over 30 advancing frames;
resize and camera-configuration changes redrew it. Deterministic tests cover
8.0/8.01-point thresholds, cumulative drift, zoom scale, diagonal distance,
armature vertices, coherent scene replacement, detector revision changes,
shape/topology, removal, and exact review. The initial native test included the
caption startup transition and observed one extra redraw; the final probe warms
that transition before measuring steady traffic, matching the existing dense
geometry probe.

Strict quick tests passed **935/935**, with optional native/camera probes
skipped in that suite; native probes were run separately with
`ACTION_SURFACE_RENDER_TEST=1`. Documentation checks and `git diff --check`
passed. Retained causal journeys were not repeated for this rendering-only
change.

A user-owned canonical application (PID 75586) started during validation. The
signed-app performance gate's precondition refused another instance; the live
benchmark was skipped and the running app was left intact. A read-only 3-second
sample resolved current release Swift symbols and showed SwiftUI update/layout
and Core Animation image preparation work. Compilation was concurrent and the
operator's live activity was uncontrolled, so that sample is not comparative
CPU or latency evidence. The earlier task's signed-app measurements remain
historical; this follow-up claims measured redraw elimination for synthetic
jitter, not a newly measured live-workload speedup. No controller or physical
motion was exercised.

## Camera overlay redraw isolation, 2026-09-08

Blackdog task `task-1bc9d779b5664cf388f681443aea3cc7` audited the current
optimized application and removed remaining frame-driven overlay drawing.
No user-owned AdaptivePlotter process was running at diagnosis. The supported
app already used release configuration; current compiler commands retained
`-O`, `-g`, and a SwiftPM-generated dSYM. A release process sample resolved Swift
function names and source locations. Application diagnostics and unified
logging are not conditional on `DEBUG`; optimized local-variable inspection and
stepping retain the normal compiler-optimization limitations. The final release
Studio instance (PID 73194) emitted readable received/accepted Open Drawing
Studio events through `com.adaptiveplotter.app` / `ui-actions`.

`ActionSurfaceOverlayCanvas` now receives only already-admitted geometry and
the shared camera-to-view transform. SwiftUI equality reuses its drawing across
ordinary video frames. New measurements, exact-frame eligibility changes,
annotations, zoom, pan, and resize still invalidate the drawing immediately.
The frame image and frame-counter labels continue advancing independently.
The native image host skips Core Animation transactions for identical image
identity and viewport. Canonical frame bytes, evidence matching, control
requests, image colors/resolution, and analysis cadence remain unchanged.

The preview owner's observation-ignored counters distinguish Canvas view builds
from actual renderer invocations. The signed-app gate exports both deltas and
the video-presentation revision delta. It enforces the application invalidation
bound and reports raw draws, including framework repaints.
A deterministic 2,001-point regression retained overlay inputs over 120 frames;
source/configuration loss, missing frames, clicks, and viewport changes
invalidated the inputs. Exact Drawing Studio targets disappeared on a different
frame. An opt-in native `NSHostingView` test exercised the production Action
Surface with the same dense geometry: after native startup settled, 30 advancing
frames caused zero Canvas redraws; resize and configuration changes redrew it.

Strict focused/native tests passed **12/12**. Strict quick tests passed
**926/926**, with optional probes skipped, and all **10 retained journeys**
passed. The native rendering probe was
run separately with `ACTION_SURFACE_RENDER_TEST=1`.

The original performance probe cleared presentation caches after warmup when
resetting counters; that manufactured one overlay rebuild at measurement start.
The probe now takes cumulative before/after counter snapshots without mutating
warmed caches. Both final signed release camera scenarios passed all **15**
checks. Before/after runs used the same preferred camera and 12-second window:

| Scenario | Median CPU before / after | p95 CPU before / after | p95 MainActor probe before / after |
| --- | --- | --- | --- |
| LIVE preview | 39.55% / 35.75% | 49.5% / 39.0% | 27.349 / 25.449 ms |
| LIVE preview with empty Studio open | 37.45% / 35.45% | 46.0% / 39.0% | 25.870 / 24.939 ms |

Every run advanced 98 frames with stable camera configuration and zero
semantic/root/draft deltas. Both final runs had zero overlay-presentation,
Canvas-view-build, and actual Canvas-draw deltas. Final maximum scheduling
probe delays were 28.599 ms in preview and 30.463 ms with Studio open. These
short runs show a modest CPU reduction, not a large learned-session speedup.
All four reports declared no drawing plan and no active automatic analysis.

A separate owned baseline process sample (PID 71563) showed substantial Core
Animation image preparation/copying and CoreGraphics/vImage color conversion.
That sample ran during compilation and perturbed the app, so its gate timing
was rejected as comparative performance evidence. The sample still exposed
symbolized call paths; it does not quantify a learned-session bottleneck.

No Saved Learning was applied and no controller, motion, pen, or drawing-run
intent was submitted. Native synthetic geometry and live camera preview do not
prove responsiveness during the user's learned drawing workload, attended
mechanical Stop, or physical ink.

## Optimized application builds and measured scene-analysis cost, 2026-09-07

Blackdog task `task-77d1d5bb6bc1435abfd97181c7728757` separated pen/armature
analysis cost from video rendering and the preceding SwiftUI observation fix.
The normal packaging script selected `.build/debug/AdaptivePlotter`; SwiftPM's
recorded compiler arguments confirmed `-Onone`. `make app` now defaults to
`APP_CONFIGURATION=release`, and explicit debug app builds remain available.
The signed bundle labels its configuration, the running performance report
records the compile-time configuration, and the gate verifies that they match.
The ordinary developer `make build` remains unchanged.

The armature envelope is already cap-anchored inferred geometry. Its diagnostic
pixel count is zero; enabling it with the pen cap does not run another image
scan. The cap detector performs HSV thresholding and connected components over
the configured search region (740,512 pixels in the default 1920x1080 case).
Automatic analysis already waits at least 500 ms after completion at the default
two-Hz setting, with one active scan and only the newest pending frame retained.
It does not segment the armature or analyze every camera frame.

A standalone probe linked against the current debug modules measured about
**490 ms** per scan on a synthetic 1920x1080 BGRA frame, about **487 ms** with the
armature envelope, and **30 ms** with a 200x200 region. The same probe linked
against optimized modules measured about **4.5 ms**, **4.5 ms**, and **0.55 ms**.
This is an approximately 100-fold detector-kernel difference, not a claim of a
100-fold application speedup. Each case retained the same 600-pixel cap.
Frame construction and hashing were outside the timed region.

The reproducible opt-in `FrameVisionTests/sceneKernelCost` benchmark then passed
against the release test build: **4.450 ms** pen-only median, **4.473 ms** with
armature, and **0.478 ms** for the restricted region. It uses one warmup and eight
timed scans per case, reports build configuration and inspected pixels, and
checks the cap result and zero armature pixel scans. Normal tests skip this
timing probe. No tracking heuristic, measurement threshold, or analysis cadence
changed; predicted-position search remains a possible later optimization.

Strict release quick tests passed **924 tests** in 16.375 seconds, with optional
image/native-render/timing probes skipped. The opt-in timing test passed
separately in 0.120 seconds. All **10 retained release journeys** passed in
1.422 seconds. The standalone release app passed stable local signing, launcher
logic/instance handling, and negative bundle checks including invalid build
configuration. Build/package selection was checked for both release and debug;
an invalid configuration was rejected before packaging. Documentation checks,
shell syntax checks, and `git diff --check` passed.

Both signed release camera gates passed all **14** checks:

| Scenario | Median / p95 CPU | p95 / maximum MainActor probe | Frames / 12 seconds |
| --- | --- | --- | --- |
| LIVE preview | 36.4% / 38.0% | 24.979 / 31.030 ms | 98 |
| LIVE preview with Studio open | 36.1% / 38.3% | 25.420 / 28.486 ms | 98 |

Both explicitly reported release, stable camera configuration, no active
analysis or drawing plan, and zero semantic/root/draft deltas. These empty-
Studio measurements are similar to the prior debug preview baseline. They do
not measure the additional cost of analysis in a learned live drawing session.
A separate three-second sample of an owned release profiling instance
(PID 63020) showed substantial Core Animation image preparation/copy and
CoreGraphics/vImage color conversion, with the main thread otherwise often
waiting. Pen detection and drawing planning were not hot paths in that sample.
Its counters retained zero root/draft deltas. Profiling perturbs timing, so that
run is not a performance-gate result. The helper terminated its own process
after the runtime report was written and its exit grace period elapsed.

No user application was running when diagnosis began. The gates and profile
used owned camera-preview instances; they did not apply Saved Learning or submit
controller, motion, pen, or drawing execution intent. The original user's
flashing, learned drawing workload, physical ink, and spoken mechanical Stop
remain unverified by these software and preview measurements.

## Drawing Studio analysis isolation and plan reuse, 2026-09-07

Blackdog task `task-02974c49731d45e49e6ece1c9dd67808` addressed excessive
Studio CPU and a flashing camera indicator. No user-owned AdaptivePlotter
process was running during this investigation, so the reported learned-drawing
workload and flashing were not sampled or reproduced. The camera indicator's
code uses a one-second frame-delivery check, not a camera-vibration tolerance.

The earlier root compiler cache did not prevent SwiftUI from subscribing to
per-result analysis and overlay properties during a cold render. Analysis
snapshots, overlay channels, last measurements, and pull-only Vision diagnostics
now remain outside root Observation. The existing video preview owner invalidates
Action Surface and Video Settings locally. Analysis phase and error changes
still publish semantic state. Reading stale camera presentation no longer
publishes semantic changes or schedules draft synchronization. A small toolbar
clock refreshes camera health locally and labels a running but late stream
**Camera delayed**.

Draft derivation caches exact artwork, placement, registration, boundary, tool,
paper, optical, and coverage inputs. Advancing frames and control-status changes
reuse the plan and projected prediction. Measured overlays retain exact-frame
matching. Changed or missing authority rebuilds or removes the plan, and an
experiment refusal invalidates cleared cached derivation for later recovery.
Continuous native sliders retain rounded size/rotation values and commit on
release or keyboard/accessibility edits without the prior discrete tick arrays.

Regression evidence: a cold root Observation subscription with Studio open
receives **100 actual analysis results** plus a diagnostics refresh, with zero
root invalidations, semantic changes, or draft synchronizations while video
and overlay state advance. A **2,001-point drawing** survives **120 frame changes**
and Learning/run-status changes without another derivation; placement changes
rebuild, missing authority removes the plan, and restored authority recovers it.
Strict focused tests passed **46/46** in 4.200 seconds. Final strict quick tests
passed **923/923** in 19.842 seconds, and retained causal journeys passed
**10/10** in 5.536 seconds. Documentation checks and `git diff --check` passed.

The strict signed application passed all **13** checks in both camera gates:

| Scenario | Median / p95 CPU | p95 / maximum MainActor probe | Frames / 12 seconds |
| --- | --- | --- | --- |
| LIVE preview | 37.0% / 40.3% | 23.699 / 33.985 ms | 98 |
| LIVE preview with Studio open | 37.6% / 39.4% | 24.581 / 27.998 ms | 98 |

Both had stable camera configuration and zero semantic, root-compiler, and
draft-synchronization deltas. The Studio scenario before these changes was
40.0% median / 44.5% p95 CPU; this small difference is not evidence of the
reported learned-workload speedup. Both final reports explicitly record
`drawingPlanWasAvailable=false` and `automaticAnalysisWasRunning=false`.
The gate opens the panel only; it does not apply Saved Learning or authorize
motion, pen, or drawing execution. These measurements verify preview/empty-
Studio response. The software traffic regressions verify analysis isolation
and plan reuse. Neither proves attended interaction with a learned drawing,
physical ink, spoken Stop latency, or the cause of the user's observed flashing.

## Drawing Studio interaction and computation feedback, 2026-09-07

Blackdog task `task-9e77d810d58341708ce48083c287b1a7` addressed repeated
Drawing Studio refusals and slow interaction after Learning completion.
A read-only sample of the user's application (PID 43417, before these changes)
showed 188.3% CPU, SwiftUI/AttributeGraph layout and root projection work while
an AppKit menu was open, and background pen-cap matching repeatedly converting
the same selected color to HSV for each pixel. This is a workload sample, not
a controlled before/after speed comparison.

Opening and closing Studio now check the draft revision, environment, and
current eligibility without requiring old camera or Learning facts to remain
unchanged for panel visibility. Non-pixel authoring accepts advancing frames
within the same camera context while retaining semantic fact checks.
Placement clicks and paper assertions still require exact frame identity.
The production regression completes Drawing Border, pins its comparison,
opens Studio through the canonical UI sink, and verifies the review is unpinned.
A separate 120-frame regression opens from a request displayed before the next
preview frame arrives.

Overlay-only presentation changes retain semantic control requests and refresh
only the video part of the cached projection; point-selection admission is
still compared. Camera diagnostic counters no longer invalidate the aggregate
workbench. Pen-cap matching computes the selected color's HSV once per scan
with unchanged matching arithmetic. Size and rotation sliders submit on release.
Studio and comparison buttons use the existing synchronous pending latch and
show elapsed request time. A workbench status strip displays existing operation
phases and elapsed time in the displayed phase, without fabricated percentages.
The canonical UI sink emits received, accepted/refused, and duration metadata to
unified logging under `com.adaptiveplotter.app` / `ui-actions`; the test process
produced readable Open Drawing Studio, Use Portrait, and refusal events.
These are submitted application actions, not every native click or key event.

Validation: strict focused tests passed **42/42** in 2.833 seconds; strict quick
tests passed **920/920** in 21.199 seconds; retained causal journeys passed
**10/10** in 6.082 seconds. Documentation checks and `git diff --check` passed.
The task-local application built with strict concurrency and warnings as errors
and passed stable local signing/bundle validation.

After the user's application had exited, the signed-app preferred-camera
performance gate passed all twelve checks: **98 preview frames in 12 seconds**,
**39.05% median / 62.9% p95 CPU**, **26.577 ms p95 / 31.274 ms maximum**
MainActor probe latency, stable camera configuration, and **zero semantic,
root-projection, and Drawing-Draft synchronization deltas**.
This verifies normal LIVE preview and software response; it does not measure
the earlier retained-comparison workload, attended mouse interaction, physical
ink, or spoken mechanical Stop latency. The benchmark submitted no workflow
intent and terminated its own application instance.

## Short Voice replies and Boundary Stop dispatch, 2026-09-07

Blackdog task `task-bb47a2f387b5493e88e16679813eeb93` addressed the operator's
report of unreliable spoken Boundary Stop. The running app emitted repeated
Apple local Speech service errors (kAFAssistantErrorDomain 1101); controller
records alone cannot identify the microphone, recognition, or physical stopping
latency. The existing partial-Stop path already bypassed its 900 ms endpoint,
but synchronously stopped AVAudioEngine before scheduling the typed Stop sink.
Boundary Start also closed recognition, and a subsequent movement cue could
close the reopened microphone again.

Voice now advertises unique short replies from the current typed actions:
Start, Confirmed, Cancel, and Stop. No preserves a negative observation, and
Reject preserves explicit proposal rejection. Boundary prompts speak the offered
direction and ask for Start; retry prompts and visible hints use the same short
replies. Stop enters the existing request sink before audio teardown. Spoken
Boundary Start suppresses advisory speech before admission and retains input into the
Stop-only phase, including accumulated Start Stop recognition. Duplicate Stop
callbacks cannot submit again while cancellation is pending. No control or
motion authority was moved out of its existing owner. A reproduced accumulating
background-transcript failure is corrected by advancing only the consumed text
prefix after the quiet interval; microphone capture stays open for the next Stop.
A full parallel run exposed a delayed UI-timer race in that segmentation. It now
uses timestamps captured at recognition ingress, including callbacks queued
together behind UI work. Changed response choices also invalidate the spoken
prompt cache even when the original exercise instructions are unchanged.

Native recognition retains its recognizer for the session, reports an error
that accompanies a nonfinal result, and explicitly reports normal recognition
completion. Meter updates no longer evict recognized transcripts from a bounded
queue. The current physical application's process and bundle were left intact;
these changes require a later build/relaunch to take effect in that application.
Apple Speech service recovery and attended mechanical Stop latency remain
unverified; synthetic speech callbacks and test controllers are software evidence.

Validation: focused strict Voice, speech-owner, and production Boundary request
regressions passed **19/19** in 2.259 seconds. Strict quick tests passed
**918/918** in 21.038 seconds; retained causal journeys passed **10/10** in
6.470 seconds. Tests assert Stop sink entry before audio teardown, no duplicate
pending Stop, current request identity, uninterrupted spoken Start-to-Stop input,
background transcript segmentation, short-answer ambiguity, recognition restart,
and the actual application-to-test-controller cancellation path. Documentation
checks and `git diff --check` passed. The strict task-local signed application
build and `codesign --verify --deep --strict` passed without launching the bundle.

## Active coverage selection and bounded cross-track fitting, 2026-09-07

Blackdog task `task-901bb5e0446f4b7eb3748bb20e6a8be1` added a usable Active
Learning workflow to Drawing Studio. Prepare Coverage Experiment seals 32
training and 16 reserved-holdout lines across four quadrants and four signed
axis directions. Next Experiment Trial balances coverage, spatial distance, and
estimated mean uncertainty. The existing draft/planning/run/Stop/review path owns
each operator-stepped trial; the generic run owner and controller were not
replaced. Immutable program source provenance carries the design and fixed role
into the existing checksummed archive, which reconstructs the experiment after
reopening. LIVE preparation requires a known archive; known occupied sheets,
failed trials, duplicate attempts, wrong roles, reused frames, geometry mismatch,
and changed semantic provenance stop selection. A failed resume cannot leave a
runnable default drawing behind.

The candidate fits independent, equally weighted central-span line means in
machine coordinates: intercept, X/Y spatial slopes, and signed travel-direction
terms for each cross-track axis. Rank checks and a rectangle-wide 2 mm bound
reject unsupported fits. After all training completes, the fixed candidate is
compared against 16 untouched holdouts using predeclared overall, quadrant,
direction, and quadrant/direction RMS checks. The UI separately displays
applicability, coefficients, fit standard errors, training error, holdout error,
and group comparisons. No candidate changes the accepted affine map or emits
Adaptive drawing ready. Along-track backlash, automatic batch execution,
corrected-execution holdouts, explicit model acceptance, and shape validation
remain unfinished.

Offscreen native UI inspection exposed an existing axis-line preview failure:
zero width or height caused `invalidBounds`, preventing a usable target preview.
Preview bounds now receive at least one display pixel on a collapsed axis;
exact projected paths, plans, and applicability are unchanged. The rendered
coverage trial now reports Target preview ready. Minimum experiment-area and
central-span endpoint checks absorb only arithmetic residue through the existing
numerical epsilon, with exact digital identity comparisons retained.

Validation on the final implementation: strict quick tests passed **913/913** in
19.915 seconds; all **10/10** retained journeys passed in 5.517 seconds. Fourteen
new test declarations include known-coefficient recovery, holdout leakage,
local-regression rejection, rank/bound refusal, fractional area boundaries,
48-trial canonical planning and archive reopening, failed-resume and archive-load
admission, exact-span sampling, editor/provenance invalidation, and production UI
requests with zero simulated ink effects. The native Drawing Studio rendering
was inspected offscreen at 390 points wide. The strict signed application build
passed with the stable local development identity. Documentation checks and
`git diff --check` passed. Synthetic records, simulated calibration, and native
UI rendering are software evidence only. No physical controller, camera, pen,
paper, ink, corrected drawing, or attended model acceptance was validated.

## Drawing Studio access and numerical drawing corrections, 2026-09-07

Blackdog task `task-85a511b20c7d45deac3810d46d117e12` confirmed that portrait
authoring was already implemented but hidden behind completed Border validation.
Drawing Studio now has an always-visible workbench entry and remains in View.
It opens before Learning completion, and Create Portrait/Use Portrait retain the
immutable program without a camera registration or Drawing Boundary. Planning
resumes against that same program when calibration becomes available. Missing
calibration clears the plan, not the artwork. An unavailable run archive no
longer masquerades as an executed-drawing terminal that blocks authoring.
Actual terminals and possible-ink state retain their existing handoff; Run still
requires current Learning, calibration, paper, archive, and controller admission.
Diagnostic-only preview status no longer precedes those readiness checks.

Three numeric regressions were reproduced before correction. A translated valid
10 mm camera-calibration span became `9.999999999999998` and failed planning;
its check now uses the existing DrawingRegionContainmentPolicy numerical epsilon.
The generic runner skipped a 0.4 mm Pen-Up move between hatch strokes because
it used the 1 mm settlement policy to decide whether travel existed. Only a
move that rounds to zero through MachineController's existing wire encoder is
now omitted. Tests cover signed gaps, 0.001 mm wire resolution, the 1 mm policy
boundary, and sub-wire residue. Finally, selecting wide artwork could clamp
scale to a valid fractional maximum absent from the UI's hundredth-step request
catalog. Exact range endpoints are now present, slider rounding stays within the
range, and a currently oversized draft can still be resized. Digital program,
frame, request, revision, Stop, and no-redraw identities retain exact checks.

Validation: focused strict tests passed 70/70 in 2.634 seconds, strict quick
tests passed 899/899 in 18.336 seconds, and serial strict journeys passed 10/10
in 5.558 seconds. Regressions exercise the production UI request path from initial
startup through portrait selection, program preservation across calibration loss
and restoration, fractional scale submission, and effect-free run refusal for
missing Learning/paper. Existing corrupt-archive, exact-frame, Stop, possible-ink,
saved-checkpoint, automatic Border-graduation, and 120-frame preview-isolation
tests passed. Documentation and whitespace checks passed; the stable-local signed
application bundle built and validated. Offscreen native rendering was inspected with Create Portrait
enabled before calibration. Initial test integration failures were corrected
before these final passes. Active trial selection, residual-model fitting, and
adaptive readiness emission remain unfinished. No attended camera/controller,
motion, pen, paper, click, or ink validation occurred.

## Boundary measurement and workbench interaction fixes, 2026-09-06

Blackdog task `TASK-77F69619` inspected the running signed `f4f12da` app
(PID 21805), captured its window read-only, and inspected the saved Learning
checkpoint. The visible failure was **Reveal Drawing: outsideDomain**, before
ink detection. Its recorded Y maximum was `85.917`; the FieldSpace-to-machine
round trip produced `85.91700000000002`, outside an exact containment test by
`1.4210854715202004e-14` mm. The existing DrawingRegionContainmentPolicy already
handles numerical boundary residue, but tip projection bypassed it.

The comparison audit covered App, Runtime, EpisodeRuntime, and Model position,
coordinate, bounds, residual, and result comparisons. Tip projection, tip
observation domain validation, diagnostic/evidence applicability, and the
calibration-center envelope now use the existing DrawingRegionContainmentPolicy.
Boundary cancellation also compared two controller-position payloads by exact
equality; it now uses MachinePositionAcceptancePolicy. The shared physical
settlement value is 1 mm Euclidean under `controllerQuantizedEuclideanV2`.
Digital request/frame/revision identities and numerical matrix checks retain
their existing meaning. No parallel coordinate policy was introduced.

Voice gives microphone input priority while Stop is the sole response, cancels
advisory speech through its existing owner, and reconnects ended recognition.
Refreshing a Stop capability does not restart recognition; UI/telemetry revision
churn does not veto a still-reached, capability-bound Stop. The runtime continues
to reject foreign cancellation capabilities. Tests cover two successive Boundary
legs, held speech, partial Stop, stale UI/runtime revisions, and recognition
reconnection. Superseded voice tasks cannot reapply an old playback preference.

One Learning Path panel now contains an Exercise picker, prompt, and current
actions. Its X and checked View menu entry change only presentation. The old
Exercise visibility/protection projection was deleted; Stop stays in the command
bar and Voice stays in the window when Learning is hidden. Operator buttons use
neutral system chrome, distinct Stop styling, depressed press feedback, and
pending/result feedback. Servo dragging is local until release and the slider no
longer draws hundreds of ticks. Confirm remains visible during setpoint drain.
The ambient pink contact-point marker was removed: it projected controller MPos
through the tip model and did not track a camera observation. Planned drawing
and residual comparison overlays retain their own predictions.

Validation: strict quick tests passed 892/892 in 17.831 seconds; serial strict
journeys passed 10/10 in 5.889 seconds. Focused interaction/rendering tests passed
26/26, with offscreen AppKit inspection of the combined panel in light and dark
appearance. The quick suite includes the 120-frame preview-isolation regression
and automatic Border graduation. Documentation checks and diff whitespace checks
passed. The signed live-camera performance gate and attended microphone/controller/
pen/paper validation were not run; read-only inspection of the failing old app
is not physical validation of this patch. No controller command or app restart
was issued during verification.

## Portrait authoring through the current drawing path, 2026-09-06

Blackdog task `TASK-D03058E2`, attempt `TASK-D03058E2-669670521eb3`, follows
inspection of current Learning persistence and the historical Plotter portrait
renderer. Current Learning saves one aggregate accepted-prefix package; raw
run evidence remains separate, and completed Border validation does not train
an adaptive drawing policy. The previous face renderer had not been integrated.
Its useful face-crop and tonal-vectorization ideas now enter Drawing Studio as
another DrawingProgram producer, without the legacy bridge or controller path.

Create Portrait accepts an imported image or an exact capture from a separate
camera owner, retains labeled left/front/right photos within the editor, and
previews Contour, Hatch, and Crosshatch styles. Face localization and optional
Vision person/background masking are separate operations; a missing detection
retains the image and reports what was unavailable. This is not facial-part
segmentation or 3D multi-view reconstruction. Heavy analysis runs on worker tasks
and changing style reuses the analyzed raster. Only the portrait preview child
reads its camera frames. The selected observation camera is excluded from the
portrait camera choices.

Use Portrait submits the immutable generated program to the existing Drawing
Draft owner. The shared planner consumes that program, preserves its identity
through placement changes, and the normal Drawing Run path executes, observes,
and appends its evidence. The existing evidence reference now also retains
optional generator provenance; older hash-only references still decode. No new
Learning guard, recorder, event stream, or execution loop was added. Raw portrait
photos are not automatically written into the Learning package or run archive.

Focused strict validation passed 42 tests, covering image/FieldSpace orientation,
closed contour continuity, deterministic style geometry and JSON round trips,
pose switching, independent camera ownership, generic draft placement, and
ordinary run/evidence integration. The run test includes pen-up travel to the
portrait's first point. The default strict quick suite passed 887/887 in 17.474
seconds; the serial strict journeys passed 10/10 in 5.347 seconds. The optional
external-photo test used scikit-image's public-domain
[NASA astronaut reference](https://scikit-image.org/docs/stable/api/skimage.data.html#skimage.data.astronaut),
kept outside the repository. Face cropping, person masking, and all three styles
took about 1.37 seconds together on this host, yielding 191, 221, and 384 strokes.
The generated style previews were inspected visually. Native controls were
checked in an offscreen AppKit host, including the populated vector preview.
`make docs-check` and `git diff --check` passed. These are software/image results; no
attended two-camera, microphone, controller, motion, or physical ink validation
was performed. Profile-face quality and physical portrait quality remain open.

## Completed Learning checkpoint continuity, 2026-09-06

Blackdog task `TASK-7C1CB34C`, attempt `TASK-7C1CB34C-2e9db9e44a5f`, traces
the user's request to finish setup and reuse it after restart. Accepted values
are saved automatically; unchanged startup still offers Use Saved Learning.
The Drawing Studio catalog and run-evidence roles are implemented, while active
experiment selection and residual-model fitting remain the Roadmap's unfinished
work. Completing Border validation does not mint an adaptively trained model.

Inspection found an inconsistent revision rule: completion restoration already
recognized the original acceptance retained by checkpoint revalidation, but
aggregate checkpoint validation required the Border's tip revision to equal the
newly issued tip revision. A new regression reproduced
`invalidStageFourReference` when saving completed Learning after revalidation.

The existing lineage predicate now belongs to `TipCameraRegistration` and is
shared by completion restoration and checkpoint validation. Revalidation retains
the original Border record/reference through subsequent saves without requiring
another draw. No new event stream, model fit, startup action, or learning-path
guard was added. The regression performs an initial save/load and two subsequent
revalidation/save/load cycles, preserves the exact original Border reference,
and confirms that unrelated calibration revisions remain unrelated.

Validation passed with strict concurrency and warnings as errors: 26 focused
checks in 2.464 seconds, `make quick-test` 875/875 in 19.172 seconds, and serial
`make journey-test` 10/10 in 6.565 seconds. `make docs-check` and
`git diff --check` passed. Existing unchanged-restart, no-new-mark recovery, and
automatic Border-completion checks passed. These are software and causal
simulation results, not an attended physical restart/drawing claim. The user's
saved package was inspected read-only; no persisted operator data was changed
and no hardware command or app restart was initiated.

## Drawing Border residual censorship correction, 2026-09-05

Blackdog task `TASK-574A84BC`, attempt `TASK-574A84BC-3ad89a0fd063`, follows
the user's challenge that clear Border ink should produce a residual rather
than a detection failure. The earlier completion correction did not change
the detector. Source inspection found that the observer first extracted new
darkened pixels, then rejected the entire observation if any candidate was more
than four pixels from every predicted path. That `correspondenceUnavailable`
result occurred before residual construction. It did not mean no ink pixels
were detected.

Two deterministic camera-image regressions reproduced that rejection on the
unchanged observer: a closed rectangle translated six pixels on each axis,
and an exact rectangle with one distant changed pixel. Both now produce sampled
geometry and residual evidence. The arbitrary maximum association distance and
its all-pixels veto are removed; the two production callers record the shared
`nearest-polyline-residual-v2` observer revision. No motion, calibration,
completion, or model-promotion semantics changed.

Existing rejection evidence now optionally retains the detected pixel count.
Zero detected pixels remains `inkMissing`; detected pixels that cannot form a
sampled path report `correspondenceUnavailable` with their count. Legacy records
without counts still decode. Border diagnostics retain the reason code plus its
explanation, or the measured pixel count and RMS/maximum residual on success.
There is no new stream or archive. This observer still uses same-pose frame
subtraction within the requested region: it does not establish complete edge
visibility or distinguish every shadow change from ink.

Validation passed with strict concurrency and warnings as errors: 34 focused
observer/evidence/Border tests in 8.766 seconds, `make quick-test` 874/874 in
17.924 seconds, and serial `make journey-test` 10/10 in 5.834 seconds. The first
focused run passed the detector regressions but exposed two diagnostic assertions
because the explanation had replaced the reason code; the final presentation
retains both. `make docs-check` and `git diff --check` passed.

The existing process and saved files were inspected read-only. The latest saved
operator diagnostic still omits the precise live rejection, and the drawing
archive predates that run. These reproductions establish the software defect,
not the exact cause of the latest physical incident. No hardware commands,
redraw, or app restart were performed; no new attended physical claim is made.

## Voice, live overlays, and automatic Border graduation correction

Blackdog task `TASK-C1E95129`, attempt `TASK-C1E95129-484a914e4e9d`, follows
the user's attended feedback on `dc20a6f65e7597cccf01e1f2b8a0f4d472935b1b`.
This request explicitly changes Border completion: controller-completed drawing
must finish Learning even when its Vision comparison is inconclusive. It does
not change the preceding calibration sequence or add admission rules.

The running app and the operator's saved diagnostic were inspected read-only.
The diagnostic showed accepted calibration and a dispatched Border start, but
omitted the failure behind the visible Retry action. Its action-ingress
acceptance is not proof of successful drawing or observed ink. The current
accepted calibration checkpoint was already retained automatically. No claim
is made about the omitted failure's exact cause, and no current physical result
was retroactively promoted.

- Voice recognizes contextual Boundary “move”/“go” and axis/sign variations,
  including Apple Speech's “why” for Y. Stop dispatches a matching partial
  transcript immediately. Revision-only updates keep the microphone open and
  use the newest request; a changed question still replaces the context. Voice
  uses the actual pinned strip, and its native switch makes enablement explicit.
- Ambient preview retains the last measured cap/armature geometry without
  changing its frame identity. The display labels its measurement frame;
  exact-frame evidence and point selection retain their exact matching. Source
  or camera-configuration changes discard the preview geometry. The redundant
  calibration-status banner is removed, and simulated ink segments no longer
  each print a label over the drawing.
- One checked **View** menu contains the panel nouns, including Video Settings
  and available Drawing Studio. Diagnostics is a secondary menu item. The
  operator Save Snapshot action is removed; Copy Diagnostics includes Border
  phase, step, drawing outcome, ink status, and retained terminal details.
- Border `.begin` now runs through comparison and completion automatically.
  Attributable observation creates the existing comparison artifacts. Rejected
  Vision after naturally completed drawing records `visionUnclear`, zero
  verified ink strokes, and the exact rejection, without creating a successful
  ink/residual comparison artifact. Both outcomes use the existing drawing
  archive and accepted Learning checkpoint. Cancelled or uncertain execution
  remains distinct. No new event journal or archive format was introduced.
- The simulator now retains the aggregate outcome of its naturally completed
  Border segments. The source-indexed simulated result remains nonphysical.
  Completion marks Exercise 2.1 complete, fills the graduation cap, exposes
  Drawing Studio in View, and resumes live preview; exact comparison remains
  available for later review.
- The root projection cache also keys on Drawing Draft's complete projection
  reference, including external facts. A fixed 20 ms setup delay in the preview
  isolation test was replaced with a wait for the actual synchronized facts.

The focused interaction/completion suite passed 43/43. A temporary offscreen
AppKit/SwiftUI host rendered the production workbench with injected causal
simulation; the completed rows, filled cap, View menu, camera/geometry, and Voice
switch were inspected. The temporary render test was removed after capture.
The first full strict run passed the new behavior tests but exposed the preview
test's setup race (three assertions in that test); the synchronization and cache
reference correction followed that evidence. The final isolation/Voice/completion
suite passed 19/19, including zero semantic/root/Learning/Drawing changes over
120 preview frames.

Final validation passed: `make strict-check` ran 880/880 Swift tests in 19.586
seconds, signed-app/bundle checks, documentation/architecture checks, and all 61
Python contract tests. `make quick-test` passed 870/870 in 19.075 seconds and the
serial `make journey-test` passed 10/10 in 5.946 seconds, both with strict
concurrency and warnings as errors. `git diff --check` passed.

A final Voice-only refinement, task `TASK-4E89A571`, attempt
`TASK-4E89A571-2483f06060a6`, follows landed `58b1b3b`. An explicit spoken Stop
now takes precedence over a trailing explanation such as “that is not right”;
polite prefixes use the same normalization as movement. “Please do not stop”
is still distinct from a Stop request. All 8 focused Voice tests passed with
strict concurrency and warnings as errors in 0.977 seconds, including immediate
partial dispatch and unchanged-question microphone continuity. Documentation
and architecture checks plus `git diff --check` passed. The full-suite counts
above refer to the preceding UI/completion change.

The existing live app was left running. No controller command, physical redraw,
or microphone session was initiated for verification. The signed live-camera
performance gate was not run because it requires stopping the current app;
this work makes no new measured CPU or attended hardware claim.

## FIX-10 operator diagnostics and interaction correction complete

Blackdog task `TASK-128DF0C7`, attempt `TASK-128DF0C7-93f0fac9a2b1`, implements
the user's revised scope against `6429ceb3ea0437045792b151b4a78f3f589dfd9c`.
The recent Blackdog requests for FIX-09, model/UI consolidation, and Exercise
simplification were inspected directly from their retained request artifacts.
The intended direction remains one model-owned Learning path, useful evidence,
and responsive human interaction; no Learning sequence or admission rule was
added or changed.

- Camera pixels now render through `CameraFrameLayerView` and Core Animation;
  Canvas renders only overlays using the same `CameraPixelToViewTransform`.
  A fresh signed baseline measured 67.3% median CPU, 74.8% p95, and 98 preview
  updates in 12 seconds. Sampling identified Canvas/RenderBox full-frame alpha
  conversion as a hot path. The initial corrected run measured 37.25% median,
  57.9% p95, and 104 updates. Semantic, root, and Drawing synchronization deltas
  were zero; MainActor p95 was essentially unchanged (26.38 to 26.53 ms).
  Source resolution, camera configuration, evidence bytes, and cadence were
  preserved. A stale pre-existing app bundle was rejected as a source baseline.
- A later camera measurement exposed two root projection rebuilds with no
  semantic change; that run failed isolation despite improved CPU. A repeat
  passed, but the unconditional root compiler still made native view
  reevaluation unnecessarily expensive. A single-entry projection cache now
  compares exact typed semantic/runtime revisions and window inputs before
  rebuilding. The regression covers repeated redraws, invalid manual input,
  viewport changes, an accepted Learning-mode request, and continued freshness.
  The final signed candidate passed two consecutive live-camera runs: median
  CPU 36.9% and 36.7% (about 45% below the 67.3% baseline), p95 CPU 72.6% and
  72.9%, and 98 preview updates in each 12-second window. Both had zero
  semantic/root/Drawing deltas and stable live camera configuration. MainActor
  p95 was 26.86 and 25.37 ms; maxima were 34.18 and 30.96 ms. Peak CPU and
  interaction latency were not materially improved; sustained preview CPU was.
- Native sidebar rows replace custom navigator cards; a full-width utility bar
  replaces the crowded camera-column strip. The current prompt and pinned
  controls are adjacent, Motion starts collapsed, the minimum window width is
  1,320 points, and the unused status timer is removed. Actual signed-app
  screenshots were inspected in SIMULATED mode; controls and overlays render
  with the camera layer. Stop remains outside the prompt's scrolling area.
- Opt-in contextual Voice reads the current prompt, listens for current button
  labels or contextual yes/no answers, displays input level and transcript,
  endpoints settled partials, and supports repeat/retry. It submits the exact
  captured `PlotterUIRequest` through the existing sink. Playback, Voice off,
  and context replacement release microphone input. The native speech queue
  now shares concurrent first initialization and can cancel one superseded
  prompt without canceling unrelated workflow cues. Apple Speech prefers
  on-device recognition when supported; no audio recording is retained.
- Diagnostics copies or atomically saves JSON from the existing bounded
  Learning record and current source, UI/runtime revisions, actions/refusals,
  and camera/Vision errors. The snapshot explicitly omits raw controller,
  camera, audio, older, and in-flight records. It creates no event stream and
  does not claim canonical replay completeness or physical evidence. FIX-10's
  former complete-source/archive prerequisite is superseded by this practical
  diagnostic export; archival integration is deferred in Roadmap.
- The obsolete repository-wide prohibition on microphone/speech input is
  removed. App privacy declarations and their existing validation now describe
  the implemented opt-in input workflow. No new product guard or interlock is
  introduced.

Focused speech, Voice, diagnostics, and layout checks passed 25/25; the final
computation/cache suite passed 11/11. The final `make strict-check` passed
876/876 tests in 18.643 seconds, along with signed-app,
launcher, documentation/architecture contracts, and 61 Python contract tests.
The earlier serial full pass found one fixture that assumed Motion started
open; its toggle expectation was corrected. The initial strict build found a
Binding method-reference sendability warning; an explicitly isolated closure
corrected it before the final strict pass.

| Validation | Result | Scope |
| --- | --- | --- |
| `BUILD` | passed — signed application built and bundle/launcher validation completed | Current production sources under strict concurrency and warnings as errors |
| `INCIDENT-APP` | passed — 2/2 WorkbenchDiagnosticsTests | Existing ordered Learning record, current refusal/revisions, declared omissions, and export without mutation |
| `UI` | passed — 25/25 focused Voice, speech, diagnostics, and layout tests plus actual signed-app screenshot inspection | Native pane arrangement, contextual exact-request submission, microphone lifecycle through injected input, and camera/overlay rendering |
| `DOC` | passed — canonical documentation and architecture checks plus 61 Python contract tests | Revised FIX-10 scope and completed software frontier |
| `DIFF` | passed — git diff --check | Task source, tests, scripts, and documentation |
| `QUICK` | passed — 866/866 tests in 17.052 seconds | Unit and component suite under strict concurrency and warnings as errors |
| `JOURNEY` | passed — 10/10 tests in 5.644 seconds | Sequential retained causal journeys under strict concurrency and warnings as errors |
| `STRICT` | passed — 876/876 tests in 18.643 seconds and full make strict-check | Signed app, launcher, complete Swift suite, and repository contracts |

`FIX-10` is complete as software/repository evidence. No attended camera click,
controller, motion, Stop, paper, or observed-ink validation was performed by this
task. Microphone permissions, physical recognition accuracy, and human turn-taking
remain unverified on the operator's device; automated Voice uses injected input.
The revised diagnostic snapshot does not satisfy those physical observations.

## Calibration-reference fidelity and preview-isolation correction

Blackdog task `TASK-6E2FA6AE`, attempt
`TASK-6E2FA6AE-resume-3f5448c12ff2`, corrects two bounded application defects
against base revision `79dee1716a03377318f3d40c320fa84358794025`:

- `CurrentCameraCalibrationPlan` retains the fresh controller-observed
  `targetPosition` directly as sample zero. It no longer reconstructs that
  reference through rectangle midpoint arithmetic. The fractional `(0.1,
  -0.2)` planner regression and the projection-bound production route through
  `PlotterUIIntentSink` both preserve the exact first fit correspondence.
  Digital identity remains exact; physical settlement and center-arrival
  equivalence use the one typed `MachinePositionAcceptancePolicy`.
- Ordinary preview publication is owned by the video-local
  `ActionSurfacePreviewModel`, outside the aggregate semantic observation
  graph. A persisted-Saved-Learning regression publishes 120 sequential frames
  with zero semantic-revision, root-projection, Learning-projection, and
  Drawing-Draft-synchronization deltas, then proves one explicit semantic
  transition produces exactly one of each rebuild. Saved optical comparison is
  deduplicated by typed checkpoint/camera-configuration identity and publishes
  only an actual state change.
- Exercise detail now renders only its question, instruction, effect-bearing
  controls, inline refusal, and required Stop/cancel/close protection. Its
  progress, feed, activity, subsystem-status, evidence, and logging/output
  presentation types and producers are deleted; runtime evidence, the
  navigator, exact requests, and Reset All remain authoritative.

The pristine signed app at the base revision measured 139.1% median CPU and
145.2% p95 over 15 one-second live-camera samples. The corrected signed-app
preferred-camera gate advanced 97 preview frames over 12 seconds with 66.85%
median CPU and 70.9% p95, a 51.9% and 51.2% reduction respectively. Semantic
revision, root projection, and Drawing Draft synchronization deltas were all
zero. Background-to-MainActor interaction latency measured 25.29 ms p95 and
30.22 ms maximum. The machine-readable receipt is emitted by
`make preview-performance-gate` at
`.build/evidence/preview-performance.json`.

Focused serial integration validation passed 56/56 tests, including the exact
fractional planner/production route, 120-frame persisted-state isolation,
minimal Exercise detail, request/Stop preservation, and gate serialization.
The complete serial Swift package suite then passed 867/867 tests in 45.533
seconds. A second complete pass under strict concurrency and warnings-as-errors
passed the same 867/867 tests in 45.496 seconds.
This is software and actual running-camera performance evidence only. It is
not attended controller, motion, Pen, paper, click, or ink evidence.

## Model/UI consolidation tranche complete

Blackdog task `TASK-34928BFE`, attempt `TASK-34928BFE-a221afbd5d52`, completed
`EA-12A`, `EA-12B`, and `EA-12C` in order as one staged
`TRANCHE-MODEL-UI-CONSOLIDATION` candidate:

- `PlotterBorderValidationRuntime` is now the sole source-indexed mutable Border
  Validation state, operation, task, review, possible-ink, reset, result, and
  shutdown owner. The duplicate `PlotterApplicationEnvironmentState` snapshot,
  root forwarding/copy paths, `replaceSnapshot`, and zero-caller retry intent
  are deleted; `PlotterApplicationRuntime` supplies lower effects and immutable
  projection only. The runtime retains every step/accept/reject effect, rejects
  late results unless the exact operation still owns admitted state, and its
  asynchronous close cancels and joins that exact task. Root shutdown joins
  both LIVE and SIMULATED Border runtimes before persistence/settlement;
- each rendered Learning semantic control carries its exact
  `PlotterLearningActionRequest` from model actionability through immutable
  `PlotterUIProjection`, the sole public `PlotterUIIntentSink`, and the owning
  feature runtime. App semantic registries, opaque retained/application intent
  cases, request-ID recovery/recompilation, and redundant `ExerciseActionKind`
  translation are deleted. Slider values and Boundary directions are projected
  as exact per-value/per-direction candidates; the view never reconstructs
  their semantic request from owner, number, title, or display identity;
- one stable model-owned `PlotterLearningEpisodeID` spans the bounded
  `PlotterLearningEpisodeRecord`. Every ordered `PlotterLearningTransitionID`
  records one exact `PlotterLearningRecordRequest` action/reset union value and
  LIVE/SIMULATED source, pre-state revision, typed accepted/refused result and
  remedy, and one bounded immutable post-transition projection after the owner
  settles. Reset cancellation, durable reset, and resulting state change are
  therefore present in the same ordered record. The
  root's retained asynchronous Learning task is keyed by transition identity
  solely for exact cancel/join; it is not another semantic latch or journal.
  Pen, Boundary, calibration, Border, artifact-reset, Drawing, Manual Motion,
  and Point Selection retain their distinct state/effect/journal authorities;
- **Discard Camera Samples** and the dead action/UI declarations are removed.
  Tip commit retry is absent while commit/revalidation is busy and is rendered
  only for a stable recoverable state. Learning, Drawing Placement,
  completed-comparison, and Drawing Studio controls are enabled only with their
  exact current request; stale or unavailable submission returns typed visible
  refusal instead of a silent nil termination.

The exact slice-boundary validation was: EA-12A `BUILD`, Border 7/7,
composition 6/6, 7 consumer scans, 20 deletion scans, and `DIFF`; EA-12B
`BUILD`, UI-authority 19/19, model 20/20, composition 6/6, UI 20/20,
18 consumer scans, 25 deletion scans, and `DIFF`. After fresh criticism required
exact dynamic candidates, complete action/reset post-transition records, and
Border late-result/cancel/join safety, the focused current candidate passed
`BUILD`, UI-authority 21/21, Border 9/9, model 22/22, composition 8/8, and UI
22/22. Final broad-test repair then published the exact immutable Boundary
runtime snapshot after accepted dispatch so its capability-bound Stop renders
through the canonical Learning request, and invalidated the established Learning
semantic cache after the test bridge installs a runtime-owned recoverable tip
checkpoint. Cumulative production `Sources` changed `+1631/-1600`, net `+31`.
The original net-deletion target did not pass; the coordinator accepted this
narrow correctness exception because the named obsolete parallel authorities
remain deleted and no replacement side registry was introduced.
The repaired candidate's cutover checks passed EA-12A 7 consumer/23 full,
EA-12B 22 consumer/29 full, and EA-12C 12 consumer/26 full scans.

This is software/repository evidence only. It makes no attended hardware,
camera, motion, Pen, paper, click, ink, or measured operator-speed claim and
does not provide the canonical incident source/export. `FIX-10` is the sole
next ordinary software package; `VAL-01` is dependency-ineligible until FIX-10
is complete. Package TRANCHE-MODEL-UI-CONSOLIDATION complete; migration remains
incomplete, subject to this exact task's successful Blackdog landing.

Canonical integration updated the execution plan, Swift architecture, Product
Contract, Button Transitions, Vocabulary, Document Routing, evidence, and
fail-closed checker/capsule fixtures. Reviewed no change:
[Discovery and Observed-Trial Protocol](DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md)
still describes typed review/rejection and stable post-failure retry without
naming the removed orphan control or assigning App semantic authority.

The tranche-level receipts below predate the fresh-critic repairs. They remain
historical receipts, not a claim that DOC, QUICK, JOURNEY, STRICT, or CRITIC was
rerun on the repaired tree; current repaired-tree evidence is the focused build,
tests, cutovers, contract checker, and diff check recorded above.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — canonical tranche documentation and structural contracts agree on the completed slices and FIX-10 frontier | repository documentation |
| `DIFF` | passed — exact repository diff check | repository revision |
| `QUICK` | passed — complete quick software gate | software revision |
| `JOURNEY` | passed — retained operator-journey software gate | software revision |
| `STRICT` | passed — complete strict software/repository gate | software revision |
| `CRITIC` | passed — `UNANIMOUS PASS — no material disagreement` on the bounded stable revision | read-only tranche assessment |

## EA-12A Border runtime sole-owner completion

| Validation | Result | Scope |
| --- | --- | --- |
| `BUILD` | passed — `swift build` | production build |
| `BORDER-VALIDATION` | passed — `PlotterBorderValidationEpisodeTests` 7/7 | typed Border runtime |
| `COMPOSITION` | passed — `PlotterEpisodeCompositionTests` 6/6 | production root composition |
| `AFFECTED-CONSUMERS` | passed — EA-12A consumer-only cutover check, 7 exact scans | updated consumers |
| `DIFF` | passed — `git diff --check` | candidate diff |
| `DELETE` | passed — EA-12A full cutover check, 23 scans | superseded Border/root symbols plus shutdown joins |

## EA-12B exact Learning UI request route completion

| Validation | Result | Scope |
| --- | --- | --- |
| `BUILD` | passed — `swift build` | production build |
| `UI-AUTHORITY` | passed — `PlotterLearningUIAuthorityTests` 19/19 at the slice boundary | rendered semantic controls and exact requests |
| `PLOTTER-MODEL` | passed — `PlotterEpisodeModelContractTests` 20/20 at the slice boundary | typed model requests |
| `COMPOSITION` | passed — `PlotterEpisodeCompositionTests` 6/6 at the slice boundary | sole sink to feature owner |
| `UI` | passed — `PlotterEpisodeUIActionabilityTests` 20/20 at the slice boundary | rendered actionability/remedies |
| `AFFECTED-CONSUMERS` | passed — EA-12B consumer-only cutover check, 22 exact scans | exact-request route |
| `DIFF` | passed — `git diff --check` | candidate diff |
| `DELETE` | passed — EA-12B full cutover check, 29 scans | side registries, opaque intents, dead UI, and reconstruction helpers |

## EA-12C Learning episode record completion

| Validation | Result | Scope |
| --- | --- | --- |
| `BUILD` | passed — `swift build` | production build |
| `UI-AUTHORITY` | passed — `PlotterLearningUIAuthorityTests` 21/21 | exact action/reset and dynamic request/refusal route |
| `BORDER-VALIDATION` | passed — `PlotterBorderValidationEpisodeTests` 9/9 | exact task cancellation/join and late-result rejection |
| `PLOTTER-MODEL` | passed — `PlotterEpisodeModelContractTests` 22/22 | stable episode, action/reset union, and post-transition projection |
| `COMPOSITION` | passed — `PlotterEpisodeCompositionTests` 8/8 | record publication and task cancel/join |
| `UI` | passed — `PlotterEpisodeUIActionabilityTests` 22/22 | rendered semantic controls |
| `AFFECTED-CONSUMERS` | passed — EA-12C consumer-only cutover check, 12 exact scans | model bridge and residual route |
| `DIFF` | passed — `git diff --check` | candidate diff |
| `DELETE` | passed — EA-12C full cutover check, 26 scans | duplicate bridge/identity symbols plus typed record/safety evidence |

## Historical DOC-05 model/UI consolidation audit and plan correction

Blackdog task `TASK-5168D237`, attempt `TASK-5168D237-5c8c54d403c2`, records
the repository-only correction after two independent read-only audits disproved
the post-FIX-09 FIX-10 launch boundary. The source audits found:

- `PlotterBorderValidationRuntime.state` and
  `PlotterApplicationEnvironmentState.borderValidation` are simultaneous mutable
  Border Validation snapshots. Root forwarding setters, `replaceSnapshot`,
  reset, effect, comparison, and projection paths copy or mutate both, so the
  current architecture cannot truthfully call the runtime the sole mutable
  owner;
- the one production `PlotterUIIntentSink` conformer and its stale-projection
  refusal are real, but typed Learning meaning is erased into
  `PlotterApplicationBoundAction`, `currentApplicationActions`,
  `currentPlotterUIResetPlans`, and opaque `applicationAction`,
  `retainedLearningAction`, and `retainedLearningReset` cases, then recovered by
  ID at dispatch. Residual Learning operation identity also uses a fresh UUID
  and reflected action text rather than one model-owned ordered Learning event
  record;
- current rendered-action gaps include **Discard Camera Samples** without a
  sample-owning request, tip commit retry during busy commit/revalidation,
  default-enabled Learning candidates whose resolved request may be nil, and
  **Apply Drawing Placement** presentation that may silently return when its
  exact projection request is absent. Completed-comparison, Drawing Studio, and
  all other effect-bearing controls require the same exact-request audit;
- exact zero-consumer candidates include `ContextualStopActionPresentation`,
  `StableWorkflowCapCaptureRunner`,
  `PlotterSystemSerialDeviceDiscoveryAdapter`,
  `ActionSurfaceOverlayStyleToken`/`styleToken(for:)`, the zero-caller
  `PlotterBorderValidationIntent.retryFrom`, and the dead action IDs
  `controllerProbe`, `observationStop`, and `observationRestart`.

The canonical plan now inserts pending software
`TRANCHE-MODEL-UI-CONSOLIDATION` with ordered authority slices `EA-12A`,
`EA-12B`, and `EA-12C`. It first makes the Border runtime the sole mutable
owner, then carries typed model-owned Learning request/availability end-to-end,
then establishes one truthful Learning episode identity and ordered event/state-
change record without merging the distinct feature journals or feature runtime
owners. `FIX-10` remains narrowly incident-source/export work and now depends
on that tranche. Therefore the sole first eligible ordinary package after
DOC-05 is `TRANCHE-MODEL-UI-CONSOLIDATION`; FIX-10 is not eligible.

This package changes canonical planning, reference, evidence, and fail-closed
checker/fixture contracts only. It claims no product-source deletion or runtime
behavior change, no completed consolidation, no incident source/export, and no
attended controller, camera, motion, Pen, paper, click, ink, or operator-speed
evidence. Package DOC-05 complete; migration remains incomplete.

Reviewed no change: [Attended Hardware Runbook](ATTENDED_HARDWARE_RUNBOOK.md)
already refuses `PHYSICAL-FINAL` until the incident correction has landed;
[Episode Architecture Vocabulary](EPISODE_ARCHITECTURE_VOCABULARY.md) already
owns the correct target terms and treats its deleted-owner wording as migration
history; [Learning Path Operating Protocol](DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md)
already describes rejection as discarding no samples and exposes commit retry
only after an atomic acceptance failure; [Document Routing](INDEX.md) already
assigns one noncompeting authority to each changed document; `blackdog.toml`
already routes this work through `docs/INDEX.md` and needs no new route.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; documentation and architecture contracts plus 13/13, 9/9, and 39/39 checker/capsule tests; canonical authorities agree on DOC-05, the ordered consolidation tranche, current `PlotterApplicationRuntime`/deleted-owner topology, and dependent FIX-10 frontier | repository documentation and deterministic contract checks only |
| `DIFF` | passed — `git diff --check`; no output | documentation and checker candidate only |

## FIX-09 initial Learning responsiveness and truthful controls complete

Blackdog task `TASK-9C229F54`, attempt `TASK-9C229F54-1984133960c1`,
implements the initial-Learning responsiveness and workbench truth correction
through the existing episode, controller-session, camera-capture, and UI owners:

- Confirm publishes `.confirming` before any predecessor wait. An exact held-
  publication regression proves a repeated stale Confirm is refused without a
  second Pen command. Separate held-Confirm regressions prove exact Stop and
  root shutdown return superseded confirmation truth, add no accepted Pen
  evidence, and expose no discovery successor. Root shutdown closes the Pen
  owner before joining the retained UI request;
- held speech playback does not delay the Pen command or next prompt. Pen cue
  playback is advisory after admitted dispatch, while Boundary's existing
  completion-sensitive announcement remains completion-sensitive;
- each camera action publishes a busy runtime/UI revision before its first
  lower suspension. `PlotterCameraCalibrationRuntime` is the sole mutable owner
  of calibration phase, proposal, correspondence evidence, accepted fact,
  failure, and terminal outcome; production projection-bound tests cover both
  Run and Accept;
- Learning Reset cancels and settles only the camera runtime's current
  operation and leaves admission reusable. A projection-bound reset-to-camera
  regression proves the next green five-position action reaches the runtime;
  only application shutdown closes its admission;
- one semantic Connect/Disconnect action determines title, visual role, and
  lower dispatch. Connect is green, Disconnect is red, and unavailable Enable
  Motion remains disabled gray with its blocker exposed beside it;
- interactive capture makes a best-effort 10 FPS device-delivery request and
  records applied versus unapplied reason without failing an otherwise valid
  startup. The independent 10 FPS materialization bound remains in force, and
  passive preview performs zero full-frame hashes. Automatic Vision or an exact
  workflow explicitly promotes the immutable frame once at its named boundary;
  the result, overlays, and later exact requests reuse that cached digest, and
  diagnostics observe the actual sole hash path. Camera preview-processing
  status is no longer presented as Vision processing. A production root
  composition regression delivers passive LIVE preview with analysis stopped
  and proves zero hashes, nil exact Drawing Draft facts, no point-selection
  request, and clean shutdown;
- the Incident Package action is disabled when production has no complete
  canonical incident source. Its exact unavailable remedy is readable multiline
  secondary status instead of clipped yellow text or an enabled action that can
  only refuse.

The package validation entrypoint is `make responsiveness-test`. Focused tests
on the exact source candidate passed for Pen admission and speech dispatch,
camera calibration and projection-bound UI submission, controller semantics,
capture cadence diagnostics, Learning projection, and Incident Package
actionability.

| Validation | Result | Scope |
| --- | --- | --- |
| `BUILD` | passed — `swift build`; build completed in 0.54 seconds, 1.30 seconds process wall time | package and application compilation |
| `RESPONSIVENESS` | passed — `make responsiveness-test`; 153/153 tests in 4.901 seconds | pre-wait Pen/camera publication, held-Confirm Stop/root-shutdown supersession, root-composition cancellation/join ordering, non-gating advisory playback, projection-bound camera actions including Reset All reuse, controller control grammar and visible Motion blocker, best-effort camera delivery plus explicit cached analysis/exact hashing, passive overlay, and passive root-presentation behavior, Incident actionability, and Learning projection |
| `DOC` | passed — `make docs-check`; documentation and architecture contracts plus 13/13, 9/9, and 35/35 checker/capsule tests | current product, architecture, operating, UI-transition, evidence, and execution-plan synchronization |
| `DIFF` | passed — `git diff --check`; no output | exact task candidate |
| `QUICK` | passed — `make quick-test`; 851/851 tests in 15.446 seconds | aggregate software suite excluding retained serialized journeys |
| `JOURNEY` | passed — `make journey-test`; 10/10 tests in 5.117 seconds | serialized causal journeys and reset ownership |
| `STRICT` | passed — `make strict-check`; strict build 37.92 seconds, full test build 47.75 seconds, 861/861 tests in 16.603 seconds, stable-local signing, launcher and negative-bundle validation, both documentation contracts, and 13/13, 9/9, and 35/35 checker/capsule tests | exact final software candidate; no physical claim |

`FIX-09` is complete as software/repository evidence. No attended controller,
camera, motion, Pen, paper, click, ink, application-process CPU, or operator
transition-speed result is claimed. A local
same-resolution 1920x1080 responsiveness run recorded preview
copy/materialization at 2,251,315 ns and exact digest promotion at 21,806,408 ns.
Its five-sample direct-construction medians were 6,240 ns for an unsealed
passive frame versus 16,643,532 ns with eager SHA-256. This is before/after
local software evidence that passive construction removes the hash from that
path; it is not attended app CPU or transition evidence.
The later DOC-05 audit supersedes this section's then-current FIX-10 frontier.
FIX-10 still must add one real canonical incident source and bounded export
coordinator rather than merge unrelated journals or make the UI service a
recorder, but it is dependency-ineligible until
`TRANCHE-MODEL-UI-CONSOLIDATION` completes. `VAL-01` remains dependency-
ineligible until FIX-10 is complete, so attended validation cannot truthfully
pass while Incident Package remains unavailable.

## FIX-08 operator-throughput correction complete

Blackdog task `TASK-EB3E64FA`, attempt `TASK-EB3E64FA-67fdbd7ab2a2`, implements
the operator-authorized throughput change through the existing owners:

- `ActionSurface` no longer renders **Apply Learning Point**. Its camera tap
  retains one exact submission only until `PlotterUIProjection` binds the same
  available request, then submits it once through `PlotterUIIntentSink`;
- `VisionAnalysisCadence` and Video Settings expose exactly `0.05`, `1`, `2`,
  `2.58`, `3`, `4`, and `5` FPS with stable identifiers and cadence intervals;
- `PlotterMotionThroughput.applicationXYFeedMMPerMinute` is the single `500`
  mm/min model value used by app-generated Boundary, baseline, Drawing Studio,
  Drawing Border, and sparse-circle XY requests. The manual default remains
  `500`, supervised travel continues to use current controller limits, and the
  existing lower controller-reported ceiling remains authoritative.

Production source contains neither the green button, a `10 FPS` cadence case,
nor a `100` mm/min feed literal. The change adds no guard, interlock, retry,
redraw, firmware write, or second UI ingress. The initial aggregate QUICK run
exposed one stale test assumption because replacing `10 FPS` with `5 FPS` made
a later `5 FPS` transition a no-op; the fixture now starts at `4 FPS`, its
focused regression passes, and the final complete QUICK run is green.

| Validation | Result | Scope |
| --- | --- | --- |
| `BUILD` | passed — `swift build`; build completed in 0.54 seconds | package and application compilation |
| `THROUGHPUT` | passed — 3/3 tests in 0.370 seconds | exact cadence set, direct projection-bound click submission, and 500 mm/min drawing/calibration requests |
| `DOC` | passed — `make docs-check`; documentation and architecture contracts plus 13/13, 9/9, and 35/35 checker/capsule tests | current product, architecture, operating, UI-transition, ledger, and frontier synchronization |
| `DIFF` | passed — `git diff --check`; no output | exact final task candidate |
| `QUICK` | passed — 830/830 tests in 15.542 seconds | parallel aggregate software suite after the cadence-transition fixture correction |
| `JOURNEY` | passed — 10/10 tests in 5.205 seconds | serialized causal journeys and reset ownership |
| `STRICT` | passed — 840 Swift tests plus strict-concurrency, signing, launcher, negative-bundle, and documentation checks | exact final candidate; no physical claim |

`FIX-08` is complete as software/repository evidence. No attended camera click,
controller, motion, Stop, paper, speed, or observed-ink validation was performed
by this task. No ordinary software or gate package is eligible before `VAL-01`,
which is the attended-physical authorization boundary, not a launchable wave.
`VAL-01` remains pending and requires separate attended-physical authorization;
migration remains incomplete.

## FIX-08 operator-throughput correction requested

On 2026-09-01 the operator explicitly requested removal of the green
**Apply Learning Point** confirmation from the middle of the camera surface,
the exact cadence choices `0.05`, `1`, `2`, `2.58`, `3`, `4`, and `5` frames per
second, and `500` mm/min app-owned XY travel and drawing requests. The operator
also explicitly directed that this change add no new guard or interlock.

The pre-implementation current-source inspection found one existing owner for each behavior. The
Action Surface already derives an exact-frame point submission from the camera
tap but stages it behind the green **Apply Learning Point** confirmation.
`VisionAnalysisCadence` and the existing Video Settings picker expose only `2`,
`5`, and `10` FPS. Manual, Boundary, supervised travel, and Drawing Run baseline
positioning already request `500` mm/min, while Drawing Studio drawing, Drawing
Border drawing, and sparse four-circle calibration still use `100` mm/min. The
known controller top feed is `500` mm/min.

The selected software package `FIX-08` was defined to remove only the redundant point confirmation,
routes the tap through the same projection-bound sink, replaces the cadence
choices, and normalizes every app-owned XY request to `500` mm/min. It preserves
the existing point-selection, observation, drawing-run, controller, and Stop
owners. No new guard, interlock, retry, redraw, or UI ingress is authorized; no
firmware setting changes, controller action, camera action, motion, Pen command,
or physical speed/click result occurs or is claimed by this repository task.

That contract correction is Blackdog task `TASK-275293EA`, attempt
`TASK-275293EA-2397cbccc458`. `FIX-08` is the sole next ordinary software
package at that pre-implementation boundary. `VAL-01` is dependency-ineligible
until FIX-08 is complete and a new signed build exists; migration remains incomplete.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; documentation and architecture contracts plus 13/13, 9/9, and 35/35 checker/capsule tests | final contract, ledger hash, and capsule frontier synchronization |
| `DIFF` | passed — `git diff --check`; no output | repository-only correction |

## VAL-01 Exercise 1.4 click-frame handoff stopped — FIX-07 required

On 2026-09-01 the operator ran the corrected signed application from canonical
commit `d6191d041b70ed7b948e2b73537f47c1a29726cb`; its executable SHA-256 is
`2bc5325e82c311522f8b7693eeb03a4e8e465439d95066502ebf56ccfa7864cd`.
After Exercise 1.4 drew the four corner circles and returned to its center/reveal
pose, the click surface remained on the automatically captured reveal frame.
Moving the armature clear did not update the image on which the four circle
centers had to be selected, and repeated camera refresh attempts did not replace
that click frame. The operator could not obtain a current unobstructed exact
frame and therefore could not complete the four clicks.

This is an incomplete physical attempt, not a `PHYSICAL-FINAL` pass. It records
the operator's visible-frame observation but does not claim a complete runbook
precondition record, controller transcript, Stop case, incident export, accepted
tip calibration, or observed-ink result. No later runbook section is promoted
by this prefix, and `VAL-01` remains pending.

Read-only runtime inspection found process `AdaptivePlotter` running the landed
bundle. Unified AVFoundation logs show the HD Pro Webcam C920 session stopped and
restarted at 17:51:39, posted `AVCaptureSessionDidStartRunningNotification`, and
continued producing timestamped CMIO frames. Those logs prove camera capture
continued; they do not prove what the operator saw. Source inspection found the
actual presentation cause: Exercise 1.4 stages the final reveal frame in
`PlotterPointSelectionRuntime`, assigns it to `frozenPointSelectionFrame`, and
always gives that frozen frame precedence over `displayedFrame`. Camera refresh
can update the lower camera owner but there is no semantic action that replaces
the staged point-selection request. The frozen-frame behavior is intentional
for exact click provenance; the missing operator-admitted replacement transition
is the defect.

`FIX-07` was the sole next ordinary correction package after this stopped
attempt. It had to preserve the
original physical mark/reveal evidence and exact-frame refusal rules while
adding **Capture New Click Frame**: current Idle/Pen Up and unchanged optical
identity are reacquired, zero retained clicks is required, and one strictly
newer exact frame atomically replaces the request. The accepted click evidence
must cite that independently exact frame. The action performs no motion, Pen
command, redraw, or automatic refresh. At this evidence boundary `VAL-01` was
dependency-ineligible until FIX-07 completed and a corrected signed build
existed; migration remained incomplete.

This repository correction is Blackdog task `TASK-6FE05AAC`, attempt
`TASK-6FE05AAC-1f89830e3bb5`; it performs no controller, camera, Pen, motion, or
remote-Git effect and changes no product Source or Swift Test.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check` | failed/incomplete frame-handoff evidence, FIX-07 ledger/dependency insertion, checker hash, and capsule frontier fixtures |
| `DIFF` | passed — `git diff --check`; no output | repository-only correction |

## FIX-07 explicit exact click-frame replacement

Blackdog task `TASK-EA60F469`, attempt `TASK-EA60F469-a83fe1fa0c15`, implements
the missing semantic transition without changing physical operation authority:

- `PlotterTipCalibrationRuntime` owns `captureNewClickFrame(retainedPointCount:)`
  and admits it only from the current awaiting-selection phase at count zero;
- `PlotterPointSelectionRuntime.replace` records the candidate while the old
  request remains current, then one reducer event atomically supersedes the
  request only if the exact identity and empty collecting state still match;
- the App lower adapter reacquires connected Idle, Pen Up, no controller
  operation, no sticky ambiguity, unchanged attempt/paper/source/semantic
  optical identity, and a strictly newer exact frame before replacement;
- `ToolContactClickEvidence.exactFrame` records the click frame independently
  of the immutable cap-bearing reveal; missing legacy fields decode as `nil`
  and the authority validates those clicks against the original reveal frame;
- the sole projected **Capture New Click Frame** action is enabled at zero
  clicks, visibly disabled for partial click sets, and produces no motion, Pen
  command, redraw, automatic retry, or fabricated cap evidence.

The causal-simulator application suite proved that replacement changes request,
frame, and presentation identities while preserving MPos, Pen Up, idle
controller state, the 64 existing circle segments, original reveal evidence,
and zero retained clicks. This is software/simulator evidence only; it does not
prove a live camera refresh, attended click, controller, Stop, paper, contact,
or observed-ink outcome. `VAL-01` remains pending.

| Validation | Result | Scope |
| --- | --- | --- |
| `BUILD` | passed — `swift build` | package and application composition |
| `TIP-CAL` | passed — 8 tests | replacement admission, failure rollback, terminal ownership |
| `POINT` | passed — 12 tests | atomic supersession, partial-click refusal, stale predecessor refusal |
| `UI` | passed — 19 tests | sole projected action, busy state, partial-click remedy |
| `ARTIFACT-RESET` | passed — 12 tests | reset invalidation and retained-artifact boundary |
| `DOC` | passed — `make docs-check` | contract, architecture, checker, and capsule frontier |
| `DIFF` | passed — `git diff --check`; no output | exact final task candidate |
| `QUICK` | passed — 827 tests | aggregate software regression suite |
| `JOURNEY` | passed — 10 tests | serialized causal journeys and reset ownership |
| `STRICT` | passed — 837 Swift tests plus strict-concurrency, signing, launcher, negative-bundle, and documentation checks | exact final candidate; no physical claim |
| focused tip authority | passed — 17 tests | separate click frame, capture-session/configuration change, legacy decode fallback |
| focused sparse App | passed — 8 tests | causal no-motion/no-Pen/no-new-ink replacement and preserved reveal evidence |

`FIX-07` is complete as software/repository evidence. No attended camera click,
controller, motion, Stop, paper, or observed-ink validation was performed by
this task. At that landing no ordinary software or gate package was eligible
before `VAL-01`; the later operator-authorized FIX-08 request supersedes that
frontier without changing the historical FIX-07 evidence.

## VAL-01 attended run stopped in section 1 — PHYSICAL-FINAL failed

The operator-authorized attended run used canonical commit
`36bc02623ba6aae445ac920ac1846365ce8e8fad` and the signed bundle at
`.build/AdaptivePlotter.app`. The executable SHA-256 was
`de0e736fe89ac23d0c87db52316af920d9f4605f9fa7818a07c5e3b8dabf0a1f`,
identifier `com.bullard.AdaptivePlotter`, local signing authority
`AdaptivePlotter Local Development`, and build timestamp
`2026-08-31 21:55:35 -0700`. The host was macOS 15.7.9 build 24G830 with Apple
Swift 6.1.2. The operator remained with the mechanism; this record does not
claim an independently captured operator identity, paper description, pen
description, or cutoff-reachability artifact.

The run stopped under the runbook's unexpected-motion rule. It was not resumed
after the failure for evidence purposes. This documentation correction is
Blackdog task `TASK-34B309FC`, attempt `TASK-34B309FC-cf2854ea5b7f`; it performs
no controller, camera, pen, or motion effect and changes no product Source or
Swift Test.

| Runbook section | Result | Exact attended evidence and limitation |
| --- | --- | --- |
| Preconditions | partial | One intended bundle process, signed executable, live camera, intended serial controller, and Motion-enabled UI were visible. Complete pen, paper, cutoff, and operator identity fields were not captured, so preconditions are not passed evidence. |
| 1. Establish machine-space authority | failed | Initial Exercise 1.1 exact-frame Pen Cap selection repeatedly returned a frame-currentness refusal and became usable only after operator reset/state changes. Four Boundary sides were then operator-stopped and accepted at X- `-77.074`, X+ `99.994`, Y- `-91.415`, and Y+ `58.570` mm, yielding center `(11.460, -16.4225)`. Move to Center issued unsafe motion away from that center; its retry issued another unsafe move. |
| 2. Exercise 1.3 | skipped | Section 1 ambiguity terminated the run. |
| 3. Exercise 1.4 | skipped | Section 1 ambiguity terminated the run; no calibration-circle or observed-ink claim exists. |
| 4. Checkpoint recovery | skipped | Startup did display an unattributed prior execution path, but no complete unchanged/replaced-paper recovery branch was executed. |
| 5. Exercise 2.1 | skipped | No Drawing Border motion or ink was attempted. |
| 6. Drawing Studio | skipped | No physical Drawing Studio plan was executed. |

Controller session database
`MachineSessions/session-3f08d964-9f1f-4ca7-b36c-574fc58a9cd3.sqlite`
contains run `d253d76e-4f39-4186-9145-1fe2468bce17`. Its first center request was
delta `(-38.537, -16.4225)` and settled near `(-115.623, 42.159)`; the retry
sent the identical delta and settled at `(-154.147, 25.726)`. The app then
reported a `170.886 mm` center residual against a `0.500 mm` tolerance. The
delta equals accepted center minus cached presentation MPos `(49.997, 0)`, not
accepted center minus the latest Y+ controller terminal. These controller facts
prove repeated stale-relative-command admission; they do not substitute for the
operator's unexpected-motion observation.

| Evidence class | Result |
| --- | --- |
| Controller acceptance and final Idle/MPos | failed — two accepted relative commands moved away from center; the session transcript contains both exact requests and terminals. |
| Camera/exact frame | failed — the initial cap selection exposed stale exact-frame behavior; later LIVE frames were visible, but the original refusal was not durably exported with complete request/UI revision provenance. |
| Stop | partial — each Boundary side used its exact operator Stop and retained final MPos; center travel completed before intervention and therefore supplied no successful center Stop case. |
| Operator observation | failed — the operator directly reported unexpected motion outside the accepted Boundary and terminated the run. |
| Observed ink | unavailable — no claim is made; later ink-producing sections were skipped. |
| Incident export | failed — the visible request was refused because no complete incident-package source provider was configured, so no bounded incident package was exported. |

Persistence inspection also found two restored Drawing Evidence records for
paper instance `7504B1A4-41F9-4277-8B6F-5046EE31CBD5` being considered beside a
saved candidate for paper instance `0A299E7F-9E10-4855-AA8D-D280576175FD` solely
because both used contact plane `A4E7EBD9-1AA0-4D5E-928F-DE71D5F44E11`.
Source inspection found pending exact-frame UI submissions similarly retained
across request/frame changes. Those are software diagnoses prompted by the
attended observations, not passed physical evidence.

`PHYSICAL-FINAL` is failed and `VAL-01` remains pending. At the failed frontier,
`FIX-06` is the sole next ordinary correction package recorded by this incident;
that correction is now complete in `TASK-4194B778`, attempt
`TASK-4194B778-238b4ef7adb1`. Sections 1 through 6 must be executed from the
start on the corrected exact signed build; this failed prefix cannot be resumed,
combined with simulator evidence, or upgraded to a passed attended run. VAL-01
remains incomplete; migration remains incomplete.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; documentation and architecture contracts passed; Pilot 13/13, Pilot metrics 9/9, and wave-capsule 35/35 | failed attended evidence, FIX-06 ledger/dependency insertion, and exact frontier fixtures |
| `DIFF` | passed — `git diff --check`; no output | documentation/repository correction only; no product Source or Swift Test changed |

## FIX-06 external-fact currentness correction

Prepared 2026-09-01 in Blackdog task `TASK-4194B778`, attempt
`TASK-4194B778-238b4ef7adb1`. The defect was not exercise-mode ownership. The
typed Boundary runtime asked the application fact adapter for MPos, and that
adapter answered from `machineSnapshot`, a presentation cache, while the
controller session and `RunInterpreter` already owned newer settled facts. The
adapter now refreshes the existing controller-session snapshot immediately
before an effect derives a position and again before a terminal Boundary fact
is published. LIVE admission requires connected Idle, no lower operation, no
sticky ambiguity, and a present settled MPos. The runtime and controller retain
their existing safety authority; there is no second MPos owner, automatic retry,
or bypass ingress.

The same audit moved every other position-derived effect in
`OperatorWorkspace` to that fresh lower-owner query: current camera-calibration
sampling, sparse-tip batch admission, local-baseline capture, Drawing Border
start/confirmation, reveal/return, and returned-position verification. Remaining
`machineSnapshot` reads are presentation, readiness, or summary projections and
do not compute a motion target. The computation diagnostic proves a sparse-tip
batch performs exactly one admission read plus one terminal publication read,
not one snapshot per drawing segment.

Exact-frame point selection now exposes a request only when request identity,
frame id/hash/source/configuration/capture sequence/dimensions/row layout/pixel
format, archive binding, and viewport presentation revision all match. Pending
UI submission is cleared when that identity or presentation revision changes;
the semantic action compiler also omits stale submissions. Reset, environment
replacement, a new request, and a new displayed frame therefore invalidate the
old click before dispatch. The point runtime's refusal of a forged stale
submission remains defense in depth.

Restored Drawing Evidence now projects as current only when both paper-instance
identity and contact-plane identity match. Beginning a new exact-frame Learning
request hides the prior saved-path presentation without deleting its durable
checkpoint. This prevents unrelated restored paper from leaking into the new
exercise while preserving the last complete evidence package.

| Validation | Result | Scope |
| --- | --- | --- |
| `BUILD` | passed — `swift build`; application compiled successfully | corrected application source |
| `BOUNDARY` | passed — `swift test --filter PlotterBoundaryEpisodeTests`; 19/19 | stale cached MPos, current settlement, terminal publication, Stop and retry contracts |
| `POINT` | passed — `swift test --filter PlotterPointSelectionEpisodeTests`; 11/11 | exact-frame point runtime plus current-click regression |
| `UI` | passed — `swift test --filter PlotterEpisodeUIActionabilityTests`; 18/18 | stale pending point omitted from semantic UI |
| `ARTIFACT-RESET` | passed — `swift test --filter PlotterArtifactResetEpisodeTests`; 12/12 | reset invalidation and durable-artifact boundary |
| `DRAW-RUN` | passed — `swift test --filter PlotterDrawingRunEpisodeTests`; 14/14 | full paper identity and saved-path presentation currentness |
| `DOC` | passed — `make docs-check` | canonical ledger, evidence, contract hash, and capsule frontier |
| `DIFF` | passed — `git diff --check`; no output | final task candidate |
| `QUICK` | passed — `make quick-test`; 823/823 | aggregate software regression suite |
| `JOURNEY` | passed — `make journey-test`; 10/10 | serial causal journeys |
| `STRICT` | passed — `make strict-check`; strict concurrency/signing suite and 833/833 tests | final candidate; no attended motion or ink claim |

`FIX-06` is complete only as software evidence. No controller, camera, motion,
pen, paper, operator-click, or observed-ink validation was performed by this
task. `PHYSICAL-FINAL` remains failed; `VAL-01` remains the attended-physical
authorization boundary and must rerun sections 1 through 6 from the beginning on
the exact corrected signed build.

## GATE-01 Pilot continuation passed

The prior post-EA-11C repository inspection did not pass `GATE-01`. The one invoked
`sh Scripts/check_episode_pilot_gate.sh` command exited 1 with
`episode Pilot gate failed: missing table: Validation / Result / Scope` because
the Pilot checker did not accept EA-06's canonical alternate detailed-evidence
header. Static inspection also proved that parser repair alone could not pass
the gate because `operator-workspace-adapters` was 7-to-10. That historical
refusal caused FIX-05; that correction satisfies all six source-derived
thresholds. The later exact `sh Scripts/check_episode_pilot_gate.sh` run passed
all 9 predicates, 6 reduction metrics, and 18 cutover scan sets. GATE-01 is now
complete; this continuation decision authorizes no attended physical action.

The exact current source-backed metric facts are:

| Reduction metric | Baseline | Current | Requirement |
| --- | --- | --- | --- |
| independent-admission-sites | 18 | 2 | decreased |
| workspace-task-owners | 9 | 0 | decreased |
| environment-mode-branches | 2 | 0 | decreased |
| direct-effect-calls | 40 | 0 | decreased |
| operator-workspace-policy-state | 6 | 1 | decreased |
| operator-workspace-adapters | 7 | 7 | not-increased |

`PYTHONDONTWRITEBYTECODE=1 ./.VE/bin/python
Scripts/check_episode_pilot_metrics.py` passed against baseline
`96253197a42dc6052ef76ad53c4c94c1c5f745a1` and the frozen candidate, reporting
exactly `independent-admission-sites=18->2, workspace-task-owners=9->0,
environment-mode-branches=2->0, direct-effect-calls=40->0,
operator-workspace-policy-state=6->1, operator-workspace-adapters=7->7`. The
checker pins source identities and literal inclusion/exclusion rules and rejects
identity drift, replacement closure runners, renamed root adapters, legacy
workspace tasks, and public-sink drift; it does not trust this table's counts.

| Pilot predicate | Result | Evidence |
| --- | --- | --- |
| GENERICITY | passed | `EA-02A/CORE`, `EA-02B/PLOTTER-MODEL` |
| REPLAY | passed | `EA-05B/REPLAY` |
| DEVICE-OWNERS | passed | `EA-05A/RECORDING`, `FIX-02/LINK-OBS`, `FIX-02/LINK-SAFETY` |
| ENVIRONMENT-GRAMMAR | passed | `EA-07/SIM`, `EA-09/UI` |
| SAME-SLICE-DELETION | passed | `EA-04/DELETE`, `EA-06/DELETE`, `EA-07/DELETE`, `EA-08A/DELETE`, `EA-08B/DELETE`, `EA-09/DELETE`, `FIX-03/DELETE`, `EA-10A/DELETE`, `EA-10B/DELETE`, `EA-10C/DELETE`, `EA-10D/DELETE`, `EA-10E/DELETE`, `EA-10F/DELETE`, `EA-10G/DELETE`, `EA-11A/DELETE`, `EA-11B/DELETE`, `EA-11C/DELETE`, `FIX-05/DELETE` |
| AUTHORITY-REDUCTION | passed | `EA-01/INVENTORY`, `METRICS/AUTHORITY-REDUCTION` |
| OBSERVABILITY | passed | `EA-05C/INCIDENT`, `EA-06/MOTION`, `EA-09/UI` |
| WORKSPACE-REDUCTION | passed | `METRICS/WORKSPACE-REDUCTION` |
| SAFETY-EVIDENCE | passed | `FIX-02/LINK-SAFETY`, `EA-07/SIM`, `EA-09/UI` |

At the GATE-01 decision, the ordinary software/gate backlog stopped at `VAL-01`,
the explicit attended-physical authorization boundary. `VAL-01` was not selected, started, or
claimed. The older `TASK-D2DFC053` correction and historical `TASK-2F141403`
FIX-04 diagnostic remain terminal history; neither owns current work. No
physical, hardware, motion, observed-ink, or remote-Git action occurred.

## GATE-01 Pilot continuation decision

Executed 2026-08-31 in sole-owner Blackdog task `TASK-5E431BE7`, attempt
`TASK-5E431BE7-59658505ced4`, from landed FIX-05 commit
`52dd2df70d22eed9d741f118961cb4cca521b0ca`. The first exact Pilot invocation
failed because its evidence reader incorrectly required detailed validation
rows to repeat ledger order. EA-08B's complete historical section lists the same
seven exact gates in a different order. The narrow repository repair now
compares exact gate identity and cardinality while retaining duplicate, missing,
nonpass, and unknown-gate failure behavior. Its focused unit suite passed 13/13.

After staging the six previously pending predicate results against their exact
existing evidence tokens, the live checker passed: `episode Pilot gate passed:
9 predicates, 6 reduction metrics, 18 cutover scan sets`. No product Source or
Swift Test changed, no critic was commissioned, and no QUICK, JOURNEY, STRICT,
physical, or remote-Git gate was run for GATE-01.

| Validation | Result | Scope |
| --- | --- | --- |
| `DOC` | passed — `make docs-check`; documentation and architecture contracts, Pilot units 13/13 in 0.126 seconds, metric units 9/9 in 1.447 seconds, capsule 35/35 in 18.373 seconds, and repository contract | GATE-01 completion synchronization |
| `DIFF` | passed — `git diff --check`; clean | repository-only gate delta |
| `PILOT` | passed — `sh Scripts/check_episode_pilot_gate.sh`; 9 predicates, 6 reduction metrics, 18 cutover scan sets | exact landed FIX-05 evidence and source topology |

GATE-01 is a continuation decision only. It moves no authority and does not
substitute software, simulation, or repository evidence for attended controller,
camera, motion, pen, paper, operator-click, or observed-ink evidence. `VAL-01`
remains pending and requires separate attended-physical authorization.

## FIX-05 root authority and Pilot-metric correction

Prepared 2026-08-31 inside the existing sole-owner Blackdog task
`TASK-2BF894FC`, attempt `TASK-2BF894FC-06f14a3e1a5b`. The correction deletes
the application-root stored `drawingRunFactSource`, `drawingRunInterpreterPort`,
and `drawingRunCameraPort`. `PlotterDrawingRunRuntime` now privately retains its
one nominal facts, interpreter, camera, and Vision capabilities; the composition
object is construction-only. Border execution reuses the existing machine
session and observation reuses the existing observation runtime. No wrapper,
type erasure, duplicate authority, new root property, automatic retry/redraw,
or absorbed feature runtime was introduced.

The frozen aggregate Sources identity is
`47e88fc2c40c845cd370f8d635e257c4fa5e707bdb682725ab2be72e11464f45`
and Tests identity is
`776a77a369363f9d472bb37ea5f15feda8bf81b4c05840b3561030cdda9ae6e2`.
The three changed production identities are
`DrawingRunEvidenceComposition.swift`
`7e113ee9d7cce63d4d8f5f1be146381d2f40c57d9ab47b66d315e9e6d8d3e0c9`,
`OperatorWorkspace.swift`
`38025ced236784b0f9165c1b5a09d0bb772940349626e6d80b60540d281c769b`,
and `PlotterObservationConfigurationRuntime.swift`
`590a8ffc4dbf4b5859a5546395b54bb460b9039c85ace9a73db1b3fc62e9266a`.
The metric checker identity is
`bcf868181bcab592301000b3e9130152319580dd8c4fafe09446bf93e1d45935`.

The checker unit suite passed 9/9 and its live source inspection proved all six
literal results: `18->2`, `9->0`, `2->0`, `40->0`, `6->1`, and `7->7` in the
ledger order. The focused inventory/Pilot suites passed 20/20, the canonical
inventory passed 119 entries and 162 scans, and the source-level affected suites
passed Drawing Run 13/13, Boundary 18/18, workspace/controller 21/21, and camera
composition/Vision lifecycle 6/6. There was no FIX-05 critic or critic recheck.

| Validation | Result | Scope |
| --- | --- | --- |
| `BUILD` | passed — `swift build`; build complete in 0.62 seconds | frozen Sources identity |
| `COMPOSITION` | passed — `swift test --filter PlotterEpisodeCompositionTests`; 5/5 in 0.084 seconds | production-root composition and shutdown |
| `PILOT-METRICS` | passed — metric unit suite 9/9 plus live checker `18->2`, `9->0`, `2->0`, `40->0`, `6->1`, `7->7` | pinned EA-01 and frozen candidate source identities |
| `AFFECTED-CONSUMERS` | passed — `sh Scripts/check_episode_cutover.sh FIX-05 --consumer-only`; 3 consumer scans | removed root ports and direct consumers |
| `DELETE` | passed — `sh Scripts/check_episode_cutover.sh FIX-05`; 6 zero-match scans | exact three properties as deleted-symbol and direct-port scans |
| `DOC` | passed — `make docs-check`; documentation and architecture contracts, metric units 9/9 in 1.431 seconds, capsule 35/35 in 18.862 seconds, and repository contract | canonical completion synchronization |
| `DIFF` | passed — `git diff --check`; clean | complete staged worktree diff |
| `QUICK` | passed — `make quick-test`; build 0.65 seconds and 820/820 in 15.150 seconds | frozen Sources and Tests identities |
| `STRICT` | passed — `make strict-check`; strict build 36.79 seconds, strict test build 46.64 seconds, 830/830 in 16.415 seconds, app signing/launcher/bundle validation passed, metric units 9/9 in 1.502 seconds, capsule 35/35 in 17.939 seconds, and both contracts passed | exact FIX-05 candidate |

FIX-05 landed and cleaned through its sole retained task at canonical `main`
commit `52dd2df70d22eed9d741f118961cb4cca521b0ca`. The FIX-05 package itself does
not claim `PILOT`, a GATE-01 pass, attended physical evidence, or remote-Git
action; the separate GATE-01 section above records the later decision.

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
`TRANCHE-FINAL-COMPOSITION` (`EA-11C`). At the time of this policy record, the
Device tranche had landed on canonical `main` at
`3308e1bf2c19159be7b207226280f54b5ebf0662` and the then-current sole-owner task
was executing `TRANCHE-FINAL-COMPOSITION` / `EA-11C` from that base.
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
stale task-local candidates. FIX-03, DOC-03, the later tranches, EA-11C,
FIX-05, GATE-01, FIX-06, FIX-07, FIX-08, and FIX-09 have final completion
evidence. DOC-05 has final repository-only completion evidence. The completed
model/UI consolidation tranche supplies FIX-10's model identity prerequisite.
FIX-10 is complete with the revised operator diagnostics and interaction scope;
`VAL-01` is the remaining attended-physical authorization boundary.
Detailed scope and limitations remain in the named evidence sections.

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
| FIX-05 | `TASK-2BF894FC` | `BUILD=passed`, `COMPOSITION=passed`, `PILOT-METRICS=passed`, `AFFECTED-CONSUMERS=passed`, `DELETE=passed`, `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `STRICT=passed` | FIX-05 root authority and Pilot-metric correction |
| GATE-01 | `TASK-5E431BE7` | `DOC=passed`, `DIFF=passed`, `PILOT=passed` | GATE-01 Pilot continuation decision |
| FIX-06 | `TASK-4194B778` | `BUILD=passed`, `BOUNDARY=passed`, `POINT=passed`, `UI=passed`, `ARTIFACT-RESET=passed`, `DRAW-RUN=passed`, `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `JOURNEY=passed`, `STRICT=passed` | FIX-06 external-fact currentness correction |
| FIX-07 | `TASK-EA60F469` | `BUILD=passed`, `TIP-CAL=passed`, `POINT=passed`, `UI=passed`, `ARTIFACT-RESET=passed`, `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `JOURNEY=passed`, `STRICT=passed` | FIX-07 explicit exact click-frame replacement |
| FIX-08 | `TASK-EB3E64FA` | `BUILD=passed`, `THROUGHPUT=passed`, `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `JOURNEY=passed`, `STRICT=passed` | FIX-08 operator-throughput correction complete |
| FIX-09 | `TASK-9C229F54` | `BUILD=passed`, `RESPONSIVENESS=passed`, `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `JOURNEY=passed`, `STRICT=passed` | FIX-09 initial Learning responsiveness and truthful controls complete |
| FIX-10 | `TASK-128DF0C7` | `BUILD=passed`, `INCIDENT-APP=passed`, `UI=passed`, `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `JOURNEY=passed`, `STRICT=passed` | FIX-10 operator diagnostics and interaction correction complete |
| DOC-05 | `TASK-5168D237` | `DOC=passed`, `DIFF=passed` | Historical DOC-05 model/UI consolidation audit and plan correction |
| TRANCHE-MODEL-UI-CONSOLIDATION | `TASK-34928BFE` | `DOC=passed`, `DIFF=passed`, `QUICK=passed`, `JOURNEY=passed`, `STRICT=passed`, `CRITIC=passed` | Model/UI consolidation tranche complete |
| EA-12A | `TASK-34928BFE` | `BUILD=passed`, `BORDER-VALIDATION=passed`, `COMPOSITION=passed`, `AFFECTED-CONSUMERS=passed`, `DIFF=passed`, `DELETE=passed` | EA-12A Border runtime sole-owner completion |
| EA-12B | `TASK-34928BFE` | `BUILD=passed`, `UI-AUTHORITY=passed`, `PLOTTER-MODEL=passed`, `COMPOSITION=passed`, `UI=passed`, `AFFECTED-CONSUMERS=passed`, `DIFF=passed`, `DELETE=passed` | EA-12B exact Learning UI request route completion |
| EA-12C | `TASK-34928BFE` | `BUILD=passed`, `UI-AUTHORITY=passed`, `BORDER-VALIDATION=passed`, `PLOTTER-MODEL=passed`, `COMPOSITION=passed`, `UI=passed`, `AFFECTED-CONSUMERS=passed`, `DIFF=passed`, `DELETE=passed` | EA-12C Learning episode record completion |

## Wave admission blockers

This is the sole machine-readable list of Current Evidence conditions that stop
an otherwise dependency-ready pending selectable work item from launching. A row
must name the exact package, the observed blocker, and the required user input
or canonical correction. The selector stops at that first eligible row; it
never skips ahead to later work. An empty table means Current Evidence adds no
admission blocker beyond the canonical ledger and live Blackdog claims.

FIX-10 operator diagnostics and interaction correction complete is the current
software outcome. `FIX-10` is complete as software/repository evidence through
`TASK-128DF0C7`, attempt `TASK-128DF0C7-93f0fac9a2b1`. No ordinary software or
gate package is eligible before `VAL-01` within this migration ledger. Ordinary
user-directed product improvements are not blocked by the physical-validation
frontier. The frontier is an attended-physical authorization boundary, not a
launchable wave. `VAL-01` remains pending and requires separate attended-physical
authorization. The full canonical archive is no longer a prerequisite; the
revised runbook verifies the delivered diagnostic snapshot without treating it
as physical evidence. Current Evidence adds no separate ordinary-wave blocker.

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
