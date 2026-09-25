# AdaptivePlotter Product Contract

Status: current product authority

This document owns durable product semantics, authority, safety, evidence, and
artifact applicability. The operating sequence belongs to
[Discovery and Observed-Trial Protocol](DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md),
package ownership to [Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md),
the target episode migration to
[Episode Architecture Execution Plan](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md),
and verified status to [Current Evidence](CURRENT_EVIDENCE.md).

## Product boundary

AdaptivePlotter is one native, signed macOS application operating one local
plotter with one selected camera at a time. It owns the short controller-camera-draw-observe loop
directly.

In scope:

- one persistent controller owner and one persistent camera owner;
- typed controller requests and typed observations;
- explicit operator-owned alarm inspection, alarm-lock clearing, and independently measured X/Y steps calibration;
- one camera-first operator workbench;
- current-session discovery and observed drawing trials;
- sparse operator-selected contact evidence and an atomic accepted pen-tip calibration;
- one attributable observed drawing trial;
- direct placement, preview, execution, and observation of bounded vector drawing programs;
- append-only drawing-run evidence with immutable acquisition roles and later residual selection;
- causal simulator parity without physical authority.

Out of scope:

- a web server, Python bridge, remote backend, or second product process;
- arbitrary G-code or natural-language-to-motion translation;
- homing, controller reset, or arbitrary firmware/configuration writes;
- entered bounds treated as measured workspace authority;
- automatic resend, resume, retap, continuation, or redraw after ambiguity;
- Learning Path completion or model confidence as a general motion gate;
- automatic trial selection, online model promotion, or model-mismatch policy
  in the current curriculum;
- simulator state as physical evidence.

## Independent axis metric

The Learning frame measurement form retains exact completed Border geometry,
controller completion, the historical full controller configuration and accepted
Learning checkpoint, independent ruler readings for each signed edge, explicit
uncertainty, instrument/method and operator axis association. Planned spans are
not serial-transmission receipts. Their separate nominal encoding allowance is
0.001 mm; neither that allowance nor the camera affine measures actual travel.
Partial readings are durable. Only confirmed, compatible opposite-edge intervals
on both axes can produce a reviewed proposal. Source photographs and overlays do
not establish physical millimetres or orthogonality.

Apply Axis Calibration is an explicit typed controller action. Each proposed
steps/mm value is historical steps/mm divided by independently measured physical
length per planned controller length, rounded to the displayed three-decimal
setting. Under its existing exclusive lane the controller verifies fresh Idle
and the complete historical context before durable preparation and either write.
It writes each exact setting once, preserving actual transfer counts, received
bytes, acknowledgements and full readback. A failed second write retains the first
acknowledgement; cancellation and shutdown join the admitted operation. Ambiguity
never causes a retry or hardware rollback. Readback confirms reported settings,
not physical proportions.

Before any setting may change, the existing drawing archive retains the proposal
and old complete Learning package. The existing reset/persistence transaction
reserves Boundary reset, saves a new semantic machine-geometry identity and
Pen-only prefix, then commits dependent invalidation. Boundary, camera/cap, tip
and Border must be reacquired; old registrations are never rescaled. Startup
reconciles interrupted preparation from durable evidence before exposing Saved
Learning, without replaying firmware writes. Terminal persistence can be retried
independently of hardware. Historical portraits, training checkpoints and physical
images remain immutable. Possible ink under old geometry cannot be relocated by
new controller coordinates: the existing drawing owner requires a recorded new
sheet for that marked paper, rather than treating a moved target as clean.
Independent holdout lengths, angles, locations and material measurements remain
separate attended acceptance. This calibration cannot repair skew or slipping.

## Runtime authority

`MachineController` exclusively owns the selected connection, GRBL parsing,
direct admission checks, command serialization, settlement, and sticky
ambiguity.

`RunInterpreter` owns the single current logical operation and delegates
mechanical execution to `MachineController`.

`CameraCapture` exclusively owns camera discovery, authorization, selection,
capture lifetime, exact-frame materialization, and capability-scoped preview
publication holds. A hold does not stop raw capture or change semantic optical
identity. It retains only the newest raw buffer and publishes at most one newest
preview when the final matching hold settles. Preview age never selects another
canvas source. During an exact Vision hold, the workbench retains the current
camera image and labels it held for the owning calibration. If ordinary delivery
becomes stale, the same image remains labeled as the last camera frame; it does
not satisfy fresh-frame admission. Simulation fallback applies only when no image
is available for the selected camera role. Interactive LIVE capture requests
an upstream 10 FPS device-delivery limit and independently bounds ordinary
full-frame preview materialization to the same rate. The diagnostics state
whether the device accepted that limit. An unsupported device limit is visible
as unapplied; a device-format or configuration-lock refusal does not fail an
otherwise valid capture session and is never reported as a cap. Ordinary
preview owns the immutable pixels needed for display and performs no implicit
full-frame evidence hashing. Automatic analysis deliberately seals a frame once
at its analysis boundary; Vision results and overlay matching reuse that cached
digest. An explicit exact-frame request likewise seals once when analysis has
not already done so, or reuses the same digest when it has. Diagnostics count
the actual sole SHA-256 computation path rather than inferring work from frame
or request counts.

An unsealed passive frame may drive video presentation, but it is not an exact
frame fact. Drawing Draft currentness/preview, point selection, placement,
saved-Learning reference construction, and saved-Learning comparison must
project unavailable or nonmatching until analysis or an explicit exact capture
seals the digest. Merely rebuilding presentation or currentness state must not
promote or hash the passive frame.

The supported local signed application uses a debug build by default to reduce
development build latency. Optimized app builds require explicit
`APP_CONFIGURATION=release`. Bundles and performance reports identify their build
configuration. Developer `make build` and ordinary Swift tests also default to
debug builds. Timing of image kernels in a debug build must not be presented as
optimized application performance.

Ordinary preview publication is a video-local presentation event. It may
invalidate only the shared Video camera/overlay leaf, but it must
not invalidate the aggregate semantic UI projection, Learning or sibling
panels, or Drawing Draft. Frozen point-selection and pinned comparison frames
remain exact evidence rather than ambient preview. Saved-Learning optical
comparison runs once per typed checkpoint/camera-configuration identity and
may publish UI state only when its comparison state changes. The signed-app
performance gate must demonstrate advancing LIVE preview, zero ambient semantic
and Drawing-Draft deltas, bounded native event-to-handler-to-visible-acknowledgment latency, and the
declared CPU ceilings.

Camera diagnostic counters alone do not invalidate the workbench. An overlay-
only change refreshes the video presentation while retaining current semantic
control requests; changed point-selection admission still recompiles controls.
LIVE pen-cap recognition matches the operator-selected visual reference off the
main actor, with a bounded sample grid and cooperative cancellation.

Analysis results and pull-only Vision diagnostics use the existing
`ActionSurfacePreviewModel` to invalidate video-local consumers. The root must
not observe per-result snapshots even when its compiler cache can return early.
Only analysis phase/error changes publish semantic revisions. Reading camera
freshness is pure and cannot schedule draft planning. A local toolbar clock
refreshes the one-second delivery check; a running session with late frames is
labeled **Camera delayed**, without interpreting scene vibration as camera loss.
Fresh delivery compares against the camera state last projected to controls;
expiry of the previous frame alone does not invent another semantic transition.
An older frame from the same camera configuration cannot replace newer live
camera authority, matching the video leaf's existing monotonic presentation.
The signed-app gate supports `PREVIEW_PERFORMANCE_SCENARIO=learned-portrait`.
It must require complete accepted Learning including the retained Drawing Border
outcome, a dense portrait/plan, sustained active analysis and a session of at
least 60 seconds. Relevant native control inputs must run during camera/render
activity, including at least 20 settled source switches. Per-control submitted,
delivered, handled and visibly acknowledged input counts are separate facts.
An empty panel, incomplete accepted prefix, accessibility-tree membership alone,
or one analysis completion cannot satisfy this workload. MainActor scheduling
probes remain diagnostics and are not click responsiveness evidence.

The separate native workbench scenario must inspect the actual Video canvas
inside its panel and containing clips at every declared placement and width.
Settings visibility cannot replace that proof. A nested-scroll claim requires
movement of an identified overflowing inner clip caused by its correlated native
wheel event; programmatic reveal remains setup only. Resize input must have a
feasible endpoint under the actual window minimum and screen geometry. This
scenario uses simulated startup, so its native event receipts confer no real
camera, controller, motion or ink evidence.

The separate explicitly selected `physical-portrait` harness composes existing
native controls and owners under prior operator authorization. Its review
markers are bound to the exact run, candidate, stage and plan, and only stage
the test; ordinary action admission remains authoritative. A physical review
requiring fresh MPos must use the existing controller query owner and retain
its exchange provenance. Export timestamps cannot make cached controller facts
new observations. It retains the first
record and exact frame pair before a second nonoverlapping plan, never redraws
a possible-ink result automatically, and leaves the app and artifacts available
on timeout or failure. Contract tests for this harness do not establish physical
motion, camera, ink, or attended Learning evidence.

The operator may lock the current presentation viewport as a generic scene-
analysis region. The lock constrains which camera pixels requested pen-cap
analysis may scan; an armature-envelope request expands its declared dependency
to pen-cap analysis. Full-frame lock is canonicalized to unlocked/default
analysis. The region does not crop or mutate the stamped frame, change exact-
frame identity or constrain specialized workflow measurements. Unlocked analysis
and exact workflow acquisition inspect the declared search region. Sampled caps
retain immutable chromatic evidence, or fixed foreground/background contrast for
compact neutral black, gray or white caps. Detection retains the original
component size/visibility requirements. A compatible mapped controller position
bounds association to observed candidates near that position; otherwise the
clicked or last observed same-camera position supplies the neighborhood. Losing
pixels does not expire that neighborhood into a distant competitor. Competing
candidates within it remain ambiguous. Without a position prior, acquisition
requires a unique compatible component.

The retained legacy visual-template mode uses normalized per-channel correlation
with pattern structure, including
black and colored surfaces. A motion prediction seeds local refinement while the
coarse search still scores the entire declared region; the prediction never
excludes pixels or resolves a competing match. The global correlation pass is
vectorized without reducing the search region. Bounded affine refinement permits
0.8–1.25 axis scale, up to 10 degrees rotation and 0.12 shear. A match requires
score at least 0.82 and a 0.06 lead over a spatially separate competitor. Short
capture intervals also reject implausible anchor jumps; gaps over two seconds
use global reacquisition. Weak, ambiguous, clipped or incompatible observations
report tracking lost and publish no cap geometry. Refusals retain the best
candidate bounds and anchor, score against the 0.82 threshold, spatially separate
competitor margin against 0.06, and prediction residual when a prediction exists.
A same-anchor operator confirmation can retain the current appearance and at most
two prior compatible appearances. Each keeps its own rectangle and anchor; crops
are never averaged and a match never updates the reference. These are software
policy bounds, not physical accuracy
claims. Changing camera source or configuration clears the analysis lock.


Exactly two persistent global scene-overlay choices exist: **Pen cap** and
**Armature envelope**. The envelope is derived from the cap and must be labeled
as inferred, not independently segmented. Preference, requested computation,
typed run status, and exact-frame geometry are separate state. Only an operator
action or persistence load may mutate preference. Scene, workflow, and simulator
result channels have separate owners; one producer cannot erase another's
result. Exact-frame presentation admits geometry only when frame identity,
camera configuration, and source all match. Frozen review retains the exact
source frame and geometry atomically. The moving ambient preview may show the
last compatible measured scene with its original frame provenance and a caption
identifying the displayed measurement. Passive LIVE pen-cap and armature
geometry uses an 8-screen-point display deadband against the last displayed
scene, not the preceding sample. Crossing that threshold updates the scene
group together. Metadata-only changes do not redraw identical geometry.
Source/configuration, viewport, topology, removal, exact-frame interactions,
and operator/planned geometry update immediately. This rendering tolerance
never changes measurement values, evidence matching, or click coordinates.
Analysis activity alone never removes matching completed geometry or replaces
its completed typed status with a transient one.

The visible run-state vocabulary is Off, Waiting, Analyzing, Found/Available,
Not found/Unavailable, Ambiguous, Failed, Suspended, and
Stale. Reasons must name zero color-matching pixels, ambiguous candidate sizes,
source/frame mismatch, or the cap dependency that made the armature unavailable. Suspension names the
typed exact-workflow Vision owner of the exact frame while the selection remains
On; supervised travel alone is not a Vision owner or preview hold. An available
armature says it was inferred from the cap and not independently segmented.
Before Exercise 1.1 has accepted a LIVE pen-cap appearance, the
Pen cap and Armature envelope layers report Unavailable without changing their
persisted operator selections or rendering LIVE geometry.

`VisionWorker` and analysis pipelines produce measurements and diagnostics.
They do not decide controller eligibility, machine direction, operator click,
or artifact acceptance.

`PlotterUI -> PlotterEpisodeModel` is the sole package dependency for immutable
episode presentation. `PlotterUICompiler` consumes copied, bounded candidate and
Learning reachability facts and emits one bounded `PlotterUIProjection` that
enumerates every rendered semantic action. Each action binds its exact ID,
`PlotterUIIntent`, availability, UI revision, and relevant runtime revisions.
SwiftUI may submit only a request derived from an available member of that
projection; the production sink revalidates exact membership, bound intent,
availability, UI revision, and runtime revisions before routing to the retained
semantic owner. An arbitrary ID, reconstructed action/intent pair, unavailable
action, or stale projection is a typed refusal with remedy and performs no
semantic mutation.

Within that boundary, `PlotterUILearningActionabilityCompiler` is the sole
owner of bounded current-owner, item-status, action/Stop-strip, availability,
Pen-adjustment, direction-selection, and reset-reachability decisions over
copied Learning facts. The App may translate Runtime facts through
`PlotterLearningActionabilityFactAdapter` and cosmetically render the canonical
projection through `PlotterLearningDetailedPresentationNormalizer`; neither may
re-decide those semantics. `PlotterApplicationRuntime` consumes canonical
actionability when building the aggregate projection and carries each exact
canonical request unchanged to retained-owner dispatch. App-owned or renamed/split
status, completion, action-strip, Stop, sparse-action, availability,
retained-candidate, or reachability compilers are forbidden compatibility
shadows.

The completed EA-12 model/UI consolidation makes every rendered Learning action
model-owned end to end. The root is not a second UI compiler or semantic policy
owner. EA-04 point selection, EA-06 manual
motion, EA-07 causal simulation, EA-08A draft, and EA-08B run effects remain
owned by their typed runtimes and lower device/evidence authorities. Pane,
window, viewport, selection, and unsubmitted manual text are UI-local reducers;
they cannot replace controller, camera, Vision, persistence, Stop, or evidence
authority. The App must not extend `PlotterUICompiler`, fabricate action/intent
pairs, or retain direct Learning point/reset/workspace dispatch for a rendered
semantic action.

EA-07 routes every causal-simulator effect through the production
`PlotterCausalSimulatorEffectAdapter`; the workspace owns no second simulated
manual adapter, Boundary executor, or test-only effect closure bag. Retained
simulator workflows use the exact same adapter instance as the manual runtime,
with explicit retained-workflow owner attribution, nil `effectResult`, and no
fabricated episode intent, effect, or plan revision.

`RunLedger` records ordered diagnostic facts. Raw controller events and typed
workflow events remain distinct. Ledger facts cannot replay work, restore a
capability, or promote an artifact.

### Episode migration and observability requirements

The episode migration is a replacement of application workflow authority, not
a second product or hardware stack. The current `MachineController`,
`RunInterpreter`, `CameraCapture`, Vision, planning, and evidence authorities
remain authoritative unless one named execution-plan package explicitly moves a
responsibility without creating a parallel owner. The complete target and work
ledger are owned only by
[Episode Architecture Execution Plan](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md).
Target type definitions and relationships are owned only by
[Episode Architecture Vocabulary](EPISODE_ARCHITECTURE_VOCABULARY.md).

For every migrated effect-bearing or domain-authority-changing `PlotterIntent`:

- one typed semantic ingress evaluates current state and versioned facts;
- copied presentation availability is never authorization;
- the reducer is the sole producer of typed external effects;
- the runtime owns exact effect identity, lane, cancellation, and terminal
  disposition, while existing device owners repeat fresh physical safety;
- the superseded action, state, guard, task, effect, and fixture path is removed
  in the same landing;
- model-owned typed item, action, request identity, and current availability
  survive projection and submission without an App-owned semantic side
  registry or recompilation from a display ID;
- an enabled effect-bearing control contains its exact current projected
  request and cannot silently return because a request, registry entry, or
  availability is nil.

Global application exclusivity is a topology rule, not permission to merge
feature authorities. The production `PlotterApplicationRuntime` is the one
public `PlotterUIIntentSink` conformer and accepts only an exact member of an
immutable projection with matching UI/runtime revisions before delegating to
the owning typed feature runtime. Internal `PlotterIntentGateway` evaluators
remain inside the point-selection and manual-motion runtimes; the root does not
reevaluate the accepted request through a redundant gateway. Named feature
runtimes retain their typed rules, tasks, handles, Stop capabilities, and
terminal truth.

The UI/App boundary may use stable display identity, but display identity is
not semantic authority. Opaque `applicationAction`, `retainedLearningAction`,
or `retainedLearningReset`-style cases whose meaning exists only in an App
dictionary are forbidden. So are reflected/string action identity,
ID-to-semantic recovery, duplicate App translations that merely restate model
meaning, replacement closure bags, type erasure, and a second public sink.
Every enabled default Learning, calibration, Drawing Placement, completed-
comparison, Drawing Studio, and other effect-bearing control must submit its
exact current model request or expose the owning refusal/remedy. Silent nil
dispatch is a product defect, not a harmless stale-click outcome.
Slider values and Boundary directions are not reconstructed from owner, number,
title, or display identity: immutable actionability contains one exact typed
request for each supported value or option, and an absent or unavailable
candidate is disabled or refused without a lower effect.

Drawing Studio and completed-comparison buttons latch at submission and show
pending feedback with elapsed time until their sink returns. Size and rotation
sliders keep their drag value locally and submit the final value on release.
The workbench displays the current computation phase from existing Vision,
calibration, Border, and drawing-run owners; its elapsed clock is local to that
displayed phase and does not estimate percent complete or change admission.
The canonical UI sink emits unified-log request receipt, accepted/refused
outcome, and duration under `com.adaptiveplotter.app` / `ui-actions`. Those
metadata logs supplement existing records; they are not a new event store and
do not claim to capture every native mouse or keyboard event.

`PlotterLearningEpisodeRecord` is the one model-owned bounded Learning episode
record. It mints one stable `PlotterLearningEpisodeID` for its lifetime and an
ordered `PlotterLearningTransitionID` for each reservation. Every transition
records its exact typed `PlotterLearningRecordRequest` action/reset union and
source, pre-state revision, typed accepted/refused result/remedy, and one bounded
immutable post-transition projection after owner settlement. The root may retain an
asynchronous Learning task only when lower work requires cancel/join; that task
is keyed by the exact transition and owns no semantic latch, admission rule, or
second journal. `PlotterOperationRegistry` and the distinct runtime-specific
coordination remain authoritative inside manual motion, point selection, Pen,
Boundary, calibration, Drawing, controller-session, observation, speech, and
artifact owners.

Residual application state is one `PlotterApplicationState` whose
`PlotterApplicationEnvironmentState` values are indexed by typed source. A
named feature runtime's mutable workflow snapshot cannot also be stored and
edited in that residual state; the runtime publishes immutable facts/results
instead. `PlotterBorderValidationRuntime` is therefore the sole source-indexed
mutable Border Validation state, operation, task, result, review, reset, and
shutdown owner; App supplies lower effects and immutable projection only. The
root uses nominal typed effect and
`PlotterApplicationStatePersistencePort` boundaries; accepted residual state
is durably persisted before the matching projection or successful terminal is
published. Shutdown synchronously closes the root MainActor admission latch
before its first await, cancels the exact transition-keyed retained Learning
task, then closes/cancels/joins every named feature owner. Every Border step,
accept, and reject effect is retained by `PlotterBorderValidationRuntime`; its
late result is admitted only for the exact current operation, and root shutdown
joins both LIVE and SIMULATED Border runtimes before persistence/settlement. A deadline, waiter cancellation, persistence error,
or remaining nonterminal owner must expose its exact owner/progress/recovery
state and cannot be reported as application termination or quiescence.

Observability is required product behavior. Every refused intent names its typed
failed requirement, authoritative owner, compared revisions, and exact remedy.
Every active effect exposes its episode/intent/effect identity, lane, owner,
phase, start and last attributable progress times, current wait, cancellation
state, and terminal disposition. Progress must be an attributable event rather
than a fabricated heartbeat. Every reachable nonterminal state provides an
admissible intent, an explicitly owned wait/progress state, an exact remedy, or
owner-bound Stop/cancel.

Runtime and UI projection revisions must be independently visible so a stale or
starved UI can be distinguished from a controller, camera, Vision, persistence,
or workflow wait. The episode journal, controller transcript, camera lifecycle,
and structured diagnostics remain inspectable outside `MainActor`, and the
operator can export a bounded diagnostic snapshot of existing records and current
owner projections. A complete replay archive is optional future work, not a
Learning admission dependency. On-demand camera export resolves the same frozen
selection frame as the canvas and includes a structured selection-owner snapshot
(selection, attempt, phase, continuation and frame identities); it must not export
a different ambient frame while presenting a frozen selection.
Bounded workflow tracking diagnostics retain exact analyzed raw pixels with the
immutable reference bank, candidate scores/anchors, rejection gates, search hint,
algorithm options and capture provenance. At most twelve acquisition folders and
128 MiB are retained; representative stable successes and acquisition failures are
captured, not ambient video. Missing controller pose or pen-state evidence stays
explicitly unknown. These diagnostic copies are never accepted Learning or motion
authority and are separate from incident-package assembly.
Recording failure is visible
but cannot authorize work, manufacture evidence, alter physical safety, or delay
Stop/shutdown.

Incident-package presentation wraps the sole existing
`PlotterIncidentPackageAssembler`; it may not add a recorder, source/second
assembler, artifact store, filesystem/export backend, device port, or physical
evidence claim. Real assembly requires one exact complete source identity and a
matching complete provider result. When production has no such provider or
identity owner, the App must use the distinct request-ID-only unavailable
lifecycle and publish typed `.noCompleteSourceProvider` refusal/remedy without
dummy manifest, build, or digest facts. Progress/result delivery is
request-owned and explicitly bounded, and the terminal update retains exact
request/result identity. Values-only UI facts may show format version, exact
byte count and SHA-256, typed refusal/remedy, explicit
`canonicalEnvelopeOnly` integrity scope, and
`physicalEvidenceClaimed == false`; package bytes are neither exposed, stored,
nor exported by this presentation service.

The no-source canonical archive action is absent from the workbench. The
**Diagnostics** toolbar tool captures current runtime/UI revisions, requests and
refusals, camera/Vision errors, and the existing bounded Learning record on demand,
including Border phase, outcome, and retained terminal details. Only the immutable
capture occurs on MainActor. Transition formatting, JSON encoding and atomic file
writing run on a background worker. Files go to
`~/Library/Logs/AdaptivePlotter/Diagnostics/` with timestamp and request identity;
completion exposes the file location and errors remain visible. Repeated clicks
while writing do not enqueue another export. No large JSON sheet is rendered.
The file explicitly lists omitted raw recordings and in-flight or older transitions.
Learning checkpoints and completed Border outcomes are retained automatically;
there is no operator Save Snapshot step.
It creates no event stream, journal, evidence authority, or new Learning guard.
Full canonical archive integration remains deferred until a concrete learning
continuity or replay/debugging requirement justifies it.

### Controller alarm recovery

**Connect** is passive: it opens the selected serial link and runs the complete
controller probe. It never sends unlock, homing, reset, motion, pen, or firmware
commands. A failed probe retains its typed alarm, controller error, timeout,
invalid-reply, or transport blocker for the workbench even though the serial
link is closed.

The Motion panel presents the sampled X/Y/Z axis-limit state separately from the
latched controller alarm. **Clear Alarm** is armed only when the latest probe
from the selected controller contains typed Alarm status and its `Pn` field has
none of X, Y, or Z asserted. If an axis limit is asserted, the operator must physically
release that switch and press **Connect** again to resample it. Unknown limit
state is not armed. A historical alarm whose physical input is no longer
asserted remains manually clearable; Connect never clears it automatically.

The explicit action opens the selected link, discards pending input, and checks
realtime status again immediately before transmission. It sends one `$X`
alarm-lock override under `MachineController` serialization only if that fresh
status still reports Alarm with no X/Y/Z axis limit asserted. A newly asserted
limit, missing status, or non-Alarm state refuses before `$X`. It does not home,
recover position, clear a physically asserted limit input, reset the controller,
or enable Motion. Acknowledgement proves only that the controller accepted the
unlock request. The same operator action then runs a fresh complete passive
probe. An alarm, controller error, timeout, invalid reply, or transport failure
keeps the session disconnected or blocked.

Motion authorization is inactive throughout alarm recovery. After a clean
fresh probe, the operator must separately press **Enable Motion**, and every
later machine-affecting request still requires fresh controller admission. An
unconfirmed or rejected alarm-clear request is recorded and never retried
automatically.

## Evidence discipline

Evidence classes are reported separately:

1. automated build and test evidence;
2. deterministic simulator evidence;
3. controller acceptance and settlement evidence;
4. exact camera-frame evidence;
5. vision-derived measurement;
6. explicit operator observation or point assertion;
7. observed physical ink.

No lower class is promoted to a higher claim. Controller `ok` is not settlement;
Idle/MPos is not observed motion; a frame is not an inferred shape; a click is
not proof that ink exists; simulation is not camera, controller, pen, or ink
evidence.

Every frame-derived fact cites exact frame identity, SHA-256, source, capture
time, capture-session identity, semantic optical identity, dimensions, pixel
format, and the operational camera-configuration revision where applicable.
A hash plus metadata is provenance, not a promise that frame bytes can be
reprocessed. Reprocessing requires a content-addressed locator for archived
bytes.

## Learning Path semantics

The visible stages and exercises are ergonomic navigation. Complete, Current,
Next, and Needs Attention are presentation states, not an authorization ladder.
The navigator contains only curriculum stages 1 and 2 and their exercises.
**Connect** and **Enable Motion** remain workbench-toolbar controls; they are
never Learning Path rows or transitions. Motion authorization implies a current
connected controller session. When an exercise action lacks connection, Motion,
camera, pose, or another runtime dependency, that same action remains visible
and disabled with the exact external remedy. Satisfying the dependency enables
the action in place and never inserts a generic initiation, forward, or
acceptance gate.

### End-user terminology

Learning Path copy uses one vocabulary across navigation, buttons, activity,
errors, overlays, speech, capability status, and documentation:

| Concept | Required visible term |
| --- | --- |
| accepted four-side machine extent | **Drawing Boundary** |
| closed target 10 mm inside the Drawing Boundary | **Drawing Border** |
| five-position machine/cap result | **camera calibration** |
| four-corner machine/contact-pixel result | **pen-tip calibration** |
| Drawing Border plan and ink comparison | **Drawing Border validation** |
| persisted accepted Learning Path prefix | **Saved Learning** |
| controller and Motion conditions outside the curriculum | **workbench prerequisites** |

Stage titles are nouns. Exercise titles state the operator goal. Button labels
state the effect of the click, including physical motion when applicable. The
generic action labels **Start**, **Next**, and **Go** are not used by Learning
Path buttons. Runtime phases may be displayed as activity, but they are not
exercises or approvals.

Implementation terms such as *admission*, *logical owner*, *typed*, *runtime*,
*workflow coordinator*, internal revision identifiers, and Stop-capability UUIDs
must not substitute for an operator-facing action or remedy. **Accepted** is
reserved for a result that has passed its evidence commit. **Observed ink** is
reserved for attributable camera evidence and is never inferred from controller
settlement.

The implemented curriculum ends at the single visible **2.1 Draw and Validate
the Drawing Border** exercise. Its six phases are runtime activity, not six
operator approvals or selectable Learning Path rows. Its exact comparison
remains reviewable after completion. Direct drawing is a workbench
capability unlocked by that completed trial and recorded observation outcome; it is not another
Learning Path row and does not imply adaptive-model readiness.

Every accepted LIVE exercise is also a durable prefix checkpoint. Restart does
not reopen accepted pen calibration, Drawing Boundary, Exercise 1.3, Exercise
1.4, or the attributable Exercise 2.1 result merely because process-local
owners disappeared.
Loaded values are learning authority, not operational authority: Motion,
current Pen pose, controller ownership, exact frames, and Stop capabilities are
never restored from disk.

A restored Learning pose that still requires visual revalidation gates only
coordinate-dependent Learning and Drawing actions. It never gates the
operator-authored manual jog or manual Pen controls. Those controls submit one
typed manual intent to `PlotterManualMotionRuntime`; the runtime evaluates fresh
Motion/controller capability facts and its LIVE adapter still delegates
connection, alarm, readiness, safety, command serialization, and settlement to
the native controller owners. Learning progression is not an additional
manual-motion authorization layer. A Motion-disabled refusal derives its remedy
from that typed intent: jog directs the operator to enable Motion before
requesting movement, while direct Pen directs the operator to enable Motion
before actuating the pen.

The operator may turn Learning off when no Learning attempt owns work. This
hides Learning navigation and prevents new Learning actions without clearing
accepted artifacts, disconnecting the controller, disabling Motion, stopping
the camera, or blocking direct manual controls. Guided Learning retains its
current On/Off state and the existing projected mode action while navigation is
hidden, so Turn Learning On remains reachable. This is independent of portrait
acquisition, drawing, and later residual selection. The sole active-work exception
is EA-04 point selection: Learning Off may itself typed-cancel only the exact
point-selection/pen-cap continuation owner bound by both its selection ID and
exercise-attempt token. It awaits that same owner to settlement and re-evaluates
the exact owner after suspension before committing Off. A successor attempt
token, another selection, or unrelated Learning, calibration, exploration,
motion, or attempt work typed-refuses with the existing Cancel/Stop remedy.
This exception does not authorize Learning Off to cancel physical motion or any
other owner and does not weaken operator or safety authority. Every other active
Learning attempt must finish or use its existing Cancel/Stop contract before
Learning can be turned off.

After current Exercise 1.2 and before Stage 2 there are exactly two exercises:

- **1.3 Calibrate Camera from Pen Cap Positions**;
- **1.4 Calibrate Pen Tip from Corner Marks**.

Navigator selection is presentation-only. Presentation zoom, pan, and fitted
learned bounds do not change exact pixels, frame provenance, artifact validity,
or completion state. Explicitly locking the current viewport copies its
camera-pixel rectangle into the generic scene-analysis policy; the preceding
presentation operations remain non-evidence. Entering or leaving Learning and
compatible presentation-context revisions preserve the exact effective visible
camera-pixel rectangle, not merely the numeric zoom and pan values. This
continuity holds through Exercise 1.3 proposal review; acceptance publishes learned
fitted bounds as a presentation target but never auto-focuses the viewport or
rewrites a locked analysis region. A camera source/configuration change resets
the viewport. Explicit operator Full, Fit, zoom, and pan actions may replace it.
Exercise 1.4 never changes zoom, pan, fitted region, preferred zoom, or viewport
focus automatically.

Before accepted tip authority exists, the UI states **Pen tip not calibrated**.
Exercise 1.4 displays all clicks on one current frozen exact click frame and
reports their count. The first such frame is the cap-bearing final reveal. With
zero retained clicks, **Capture New Click Frame** may atomically supersede that
request with one strictly newer exact frame after the operator clears the
armature; camera preview refresh alone never changes the request. Diagnostic
residual and uncertainty presentation has no authority over model construction,
proposal creation, or acceptance.

Every valid exact-frame camera click is itself the operator submission. The
Action Surface may retain the clicked value only long enough for the aggregate
projection to bind the matching `PlotterUIRequest`, then submits that request
through the existing `PlotterUIIntentSink`. There is no **Apply Learning Point**
button or second user confirmation. A stale or refused click remains governed
by the existing point-selection owner and never becomes an automatic retry.

**Capture Pen Cap** freezes the current exact frame; the operator clicks the
visible pen cap or the tape attached to it. No permanent holder feature or
rectangle is required. For a new appearance the detected component center is the tracking point;
the click selects the component rather than defining an arbitrary pixel offset.
Recapturing a saved template preserves its stored geometry and independent anchor
with one click, so historical calibration is not silently converted to a centroid.
The cap may change color or appearance when the operator changes pens. Capture
is recognition input, not proof of physical pen state, calibration accuracy or
ink.

The cap control sits beside Guided Learning, remains available after accepted Pen
Learning when Learning is off, and becomes **Cancel Pen Cap Capture** while a
capture is pending. First-time setup exposes the same **Capture Pen Cap** action
in Exercise 1.1 before the Up → Down → Up sequence. There is no separate Locate
or Replace choice. Capturing another appearance does not repeat accepted Pen
actuation, Boundary measurement, center estimation or center arrival, move the
machine, actuate the pen, or clear possible-ink history. Active physical work and
incompatible camera/controller context remain explicit blockers.

The accepted appearance retains exact-frame provenance, sampled appearance,
component geometry, measured tracking point, selection point and optical
configuration. The detector uses image evidence near a compatible predicted
position when one exists; the prediction is a search prior, never a synthetic
observation. Ambiguity within that neighborhood remains a refusal. Without a
usable position prior, acquisition requires a distinctive image component.
Older appearance formats remain readable without erasing accepted mechanical
Learning. New appearance uses the current detector; recaptured templates preserve their
historical estimator and anchor identities.

Changing appearance and changing geometric calibration are separate decisions.
A compatible same-anchor capture can retain accepted camera, tip and drawing
calibration. With a map and settled Idle/Pen-Up, the capture records its residual
to the predicted cap position. The compatibility limit is eight pixels, including
outside the accepted domain; such an observation is explicitly extrapolated and
cannot extend the map or grant motion authority. A new capture with a displaced
anchor, or a stable captured optical context that differs from the old map,
retains Pen and Boundary Learning while requiring dependent optical calibration.
Camera/controller/coordinate context changing during capture is refused, as is
missing settled Idle/Pen-Up proof for a mapped capture. The new appearance must
save successfully before dependent authority changes.
During a suspended completed four-mark batch, an incompatible capture is refused
and the original frame, clicks and attempt are restored instead of invalidated.
Cancellation, stale capture, or save failure retains the prior in-memory package;
failed save rollback reports uncertain durability if restoration also fails.
The capture itself never raises a Down or unknown pen.

Transient cap absence or competing detections during an exact workflow keep the
existing owner at its settled pose and continue looking on newer frames. Samples
from before a gap do not count toward the next stable observation. Explicit
Stop/Cancel remains available. Tracking loss does not invalidate accepted Pen,
Boundary or camera calibration. A completed four-mark batch retains its exact
frame, mark evidence and clicks independently of ambient cap detection; fitting
those four clicks does not request a new cap observation. Replacing paper clears
only that sheet's transients and coverage. It does not reset mechanical Learning
or compatible contact-plane calibration.

Every admitted point-selection command is owned through its terminal result.
Publishing an accepted selection or removing its canvas action must not cancel
its fitting or cap-save continuation. The view may clear its pending input while
the runtime settles; explicit cancellation remains distinct from view updates.
Exact clicks take priority over editable drawing placement, and refusals appear
on the frozen selection canvas. Source or optics changes remain genuine
compatibility changes; LIVE and SIMULATED evidence never cross.

Video Settings offers exactly `0.05`, `1`, `2`, `2.58`, `3`, `4`, and `5`
frames per second for generic automatic scene analysis. The selected cadence
changes analysis scheduling only; it does not alter exact workflow capture,
point-selection frame identity, motion, or evidence authority.

### 1.1 Identify and Calibrate the Pen

Exercise 1.1 retains its existing exercise identity while one
`PlotterPenInteractionRuntime` owns its mutable attempt history and the
Up → Down → Up sequence after cap selection. Every request is a typed
`PlotterPenInteractionIntent` inside a `PlotterPenInteractionSubmission` that
binds the exact request, projection revision, environment, and active operation.
The active runtime projection carries the exact cancellation capability; a
stale revision, foreign operation or capability, changed environment, wrong
phase, missing prerequisite, or closed admission receives one typed refusal and
remedy and invokes no lower effect.

The first action remains **Capture Pen Cap**. EA-04 exact-frame point selection
owns that click, frame provenance, sampling, and accepted cap evidence;
`PlotterPenInteractionRuntime` neither captures a frame nor manufactures camera
or Vision evidence. Identification must be accepted before the first question
or any pen actuation request. A stale or rejected click keeps identification
pending and performs no machine action.

**Capture Pen Cap** requires a current exact frame but does not require a
controller session or Motion authorization. A valid cap-body click opens the
first Up question and remains accepted. If controller connection or Motion is
then missing, **Confirm Pen Up** and the current servo slider stay visible but disabled
with the exact workbench-toolbar remedy; controller selection, **Connect**, and
**Enable Motion** remain available outside the Learning Path. Establishing those
dependencies enables the existing question without asking for another cap
click or inserting a continuation step.

The Up and Down steps each expose a servo-value slider, displaying the
corresponding current setting. A fresh session is seeded at `S40` and `S760`; a
repeated attempt starts from the values already current. Moving a slider
submits that exact displayed value against the current runtime revision. The
runtime owns one latest-only drain: while an earlier accepted setpoint settles,
newer admitted values replace the pending value, so an intermediate superseded
value is never sent after it has been replaced. **Confirm Pen Up** or
**Confirm Pen Down** first validates the exact current prompt, then immediately
publishes a new `.confirming` revision that removes the predecessor green
confirmation action before any suspension. It waits for the exact drain and
terminal publication only after that admission is visible, then accepts only
the current displayed value for the corresponding setting. A second click
against the predecessor revision is refused and invokes no duplicate
confirmation or actuation. No view, workspace task, or test fixture may bypass
admission or advance the drain.

If exact Stop or application shutdown displaces a published `.confirming`
request, that request returns typed superseded truth. It records no accepted
Pen evidence and the surrounding discovery transaction cannot advance to a
successor. Root shutdown closes the Pen runtime before joining retained UI
work, so a suspended Confirm cannot commit after shutdown has claimed the
owner.

Pen work already admitted by this runtime is not reflected back as a workspace
busy prerequisite; only genuinely foreign lower-operation ownership may block
a fresh Pen request. Before the first actor-reentrancy await, the runtime
synchronously claims its sole drain and publishes the explicit
`.drainingSetpoint` phase. A runtime-owned weak projection sink publishes
immutable admitted, draining, settling, cancelling, and terminal snapshots
without a workspace observer Task, latch, retry, or effect authority. Every
installed snapshot invalidates the semantic action surface so its exact runtime
revision and cancellation capability bind the rendered request.

During `.drainingSetpoint`, canonical actionability permits only a newer
exact-revision setpoint replacement plus the exact capability-bound Stop;
confirmation is absent. Lower execution transitions to settling, where only
exact Stop remains, and confirmation returns only after terminal publication
reaches awaitingConfirmation. An active operation without its matching capability fails
closed as an invariant, and lower refusal or possible physical change remains
visible needs-attention truth rather than submission success. Normal progression
returns only after the operation clears.

If the operator invokes the exact Pen Stop while the accepted cap click still
has an admitted EA-04 continuation, the application settles that exact
point-selection continuation before the Pen runtime publishes terminal state.
The continuation cannot recreate a missing Learning attempt. This ordering adds
no generic Cancel fallback, second Pen Stop owner, command, or evidence claim.

The accepted Up and Down values are mutable operating settings, not a promise
of one constant actuator position across the run. Repeating Exercise 1.1 at
a different machine position may accept different values. The existing attempt
and actuation evidence retains each actual value and the available MPos,
controller outcome, and timestamp so later learning can observe positional
variation. Refusal, ambiguity, unavailable evidence, and any current admission
blocker remain explicit; none creates a separate forward or acceptance step.
Controller refusal and ambiguous delivery remain distinct terminal truth.
Cancellation latches before the runtime awaits an in-flight lower command;
settlement after cancellation remains possible physical change and never
authorizes automatic resend. Shutdown closes both LIVE and SIMULATED admission,
drains the accepted pending value, awaits the exact lower task and terminal
publication, and then retires the active operation. One nominal actuation port
adapts LIVE to the retained controller/`RunInterpreter` Pen owner and SIMULATED
to the sole causal simulator adapter. LIVE and SIMULATED profiles, revisions,
history, operations, and settlements remain independent. Simulator truth is
nonphysical, and controller settlement is not operator-observed Pen position,
camera evidence, or ink evidence.

Each admitted transition into a fresh SIMULATED Learning session resets only
the simulated Pen environment and preserves LIVE Pen state. The Learning reset
projection preserves the current Pen Interaction snapshot rather than silently
replacing it with stale prompt facts.

Accepted evidence is immutable and retains the exact values, available MPos,
controller outcomes, and timestamps for the confirmed sequence. It claims no
attended physical observation. The package-only scheduling gates can hold an
admitted setpoint before its runtime-owned drain or hold a returned lower result
before terminal publication for deterministic tests; neither gate can admit,
choose, cancel, dispatch, settle, or publish an effect. No separate servo-
calibration exercise, artifact, checkpoint, or authority type is introduced.

A settled recovery opportunity never owns Learning Path progression. The next
unmet dependency owns the current action strip. The failed or cancelled
exercise remains explicitly selectable with its own **Restart** action and
needs-attention status.

## Motion, Stop, and ambiguity

Every controller action has one typed intent, one owner, and a bounded terminal
contract. `ok` proves acceptance only. Completion requires fresh Idle and final
MPos when the operation consumes position.

Failure kind, attempt disposition, recovery, and possible-ink meaning are typed
facts. Human-readable descriptions are projections only; wording changes cannot
alter blacklist, no-redraw, Stop, or accepted-fallback behavior.

The manual direction controls submit one `PlotterManualMotionIntent.jog` whose
`PlotterJogRequest.routing` is derived from the current controller-commanded Pen
state. Pen Down uses `.drawingStroke` and the LIVE adapter maps it to a bounded
`DrawingStrokeRequest`; clean completion leaves Pen Down so consecutive sides
can form one manual shape. Pen Up uses `.relativeTravel`. Unknown uses
`.possibleInk` and the LIVE adapter maps it to a bounded `RelativeJogRequest`
that permits unknown Pen state only as explicit possible-ink truth. A stopped
manual drawing stroke settles only through the native drawing owner's Pen Up
cancellation result.

After Motion is enabled, manual direction controls do not depend on camera,
Vision, Learning state, Learning Path position, current-camera calibration, or
a visually confirmed Pen pose. Their X distance, Y distance, and feed inputs
remain editable and initialize to 50 mm, 50 mm, and 500 mm/min; numeric draft
validation is UI-local and cannot accept controller work. Existing native
controller ownership facts still apply; this paragraph adds no optical or
workflow admission condition.

The workbench's busy state reads the exact active operation projected by
`PlotterManualMotionRuntime`; retired workspace request booleans cannot hide an
episode-owned manual effect. For an accepted LIVE manual jog or drawing effect,
the workspace may emit legacy-compatible diagnostic accepted and terminal
workflow-telemetry events keyed by the typed effect ID. Those events own no
admission, cancellation, settlement, authorization, result, or evidence
authority.

Manual episode recording is diagnostic and lossless only for entries the exact
effect boundary supplies. For LIVE work, the operation-bound recorder attaches
before native launch to one transparent decorator around the sole production
BSD `MachineLink`, remains attached through natural or exact Stop/cancellation
settlement, and detaches only at terminal settlement. The decorator forwards
the native result unchanged while recording only FIX-02 applied configuration,
exact discard/write/read receipts, receive-boundary timestamps, close failure,
and operation-specific partial progress. Unsupported applied configuration,
failed open without applied settings, timestamp mismatch, and persistence
failure are diagnostic-only; they never fabricate settings, counts, timestamps,
or a successful transcript pair. SIMULATED receives no controller recorder.
In particular, an applied BSD open receipt whose `localModeEnabled` or
`receiverEnabled` value is false is not representable by the EA-05A open
parameters. The decorator returns that native receipt unchanged, exposes the
lossless-mapping diagnostic, and records no successful open invocation or
completion. The ordinary true/true BSD mapping remains unchanged.

`EpisodeRecordingStore` and deterministic replay apply the same partial-result
contract: discard failure may report truthful nonnegative discarded-byte
progress but no partial read chunks; open/close retain zero progress, writes
remain bounded by submitted bytes, and reads retain their chunk/count rules.

The episode runtime owns the exact nominal operation handle retained by
`PlotterOperationRegistry`; it does not replace that owner with an arbitrary
effect closure, cancellation task, or unchecked-sendability escape. For direct
Pen, `RunInterpreter` returns an async `PenActuationOperation` carrying its
owner-minted operation identity and eventual outcome. The episode adapter
awaits that handle without creating a Stop token or cancellation authority;
manual Pen therefore exposes no Stop capability.

Manual admission fails closed on capability provenance. Connection, Motion,
pose, and manual-controller facts must describe the submitted LIVE or SIMULATED
environment, and the manual-controller fact must carry current operation, Pen
state/routing, and Pen-profile revision truth. Missing or environment-mismatched
facts refuse the typed intent; UI projection cannot convert facts from the
other environment into authority.

Production manual motion requires a durable `EpisodeJournalPersistenceAdapter`
journal and does not launch with an unavailable journal directory or store. Its
runtime snapshot exposes the exact loaded journal, durable file reference and
digest, plus typed incident-source references. The optional EA-05A recording
snapshot contributes its own durability and completeness issues to those
references. Failure to open that recording remains a visible diagnostic and
does not weaken the required journal, block otherwise-safe admission, or create
recording completeness. The production recording topology is exactly
`AdaptivePlotter/EpisodeArtifacts/<episode UUID>/controller-recording`; it is
not the point-selection `EpisodeRecordings/<recording UUID>` topology.

Recording unavailable or incomplete never changes admission, controller
settlement, possible-ink classification, operator remedies, or no-redraw
disposition. A missing transcript cannot be inferred from terminal observations.
A LIVE adapter result must carry LIVE controller observation context; a
SIMULATED adapter result must carry SIMULATED causal-simulator context. Neither
recording nor simulation is attended controller, camera, Pen, paper, click, or
observed-ink evidence.

All production requested-pose comparisons use fresh attributable controller
evidence, compatible context, and at most 1 mm Euclidean residual. “Exact
pose” names that quantization-aware policy; it does not mean zero mathematical
residual at an unrepresentable stepper position.

Each Stop capability names one exact active owner. The manual runtime issues a
`PlotterManualMotionStopCapabilityID` only for its active jog. The first matching
caller creates one public Stop transaction; before the first journal await,
`PlotterOperationRegistry.beginStop` latches the exact original handle without
invoking cancellation. On the ordinary Stop path, the runtime durably publishes
cancellation `requested`; the registry then marks that same transaction
`issuingCancellation` atomically before the cancellation suspension, invokes
the handle once, and the runtime durably publishes `observed`, enters
settlement, and durably publishes `settling` before awaiting the owner-returned
result. Concurrent duplicates join the same transaction and receive its
identical result and snapshot only after typed terminal publication completes.

If the requested-stage journal append fails before Stop issues cancellation,
shutdown closes admission and atomically takes over that same requested owner
and handle. It marks the transaction `issuingCancellation`, invokes
cancellation exactly once, advances the same registry owner through observed
and settling, and settles the original handle. An already issuing, observed,
settling, or awaiting transaction is joined rather than reissued. Journal
availability is not a prerequisite for shutdown cancellation, and this takeover
creates no second cancellation, settlement, or publication authority.

Shutdown before native start retires the exact registered owner with one
identity-bound `cancelledBeforeStart` settlement. The retained handle makes a
later start inert, so neither LIVE nor SIMULATED invokes its native operation,
and no second owner or cancellation authority is created. When shutdown instead
joins the original public Stop at observed or settling, the registry marks that
same transaction `settledByShutdown`; duplicate Stop callers still join it, and
the original public Stop cursor remains the sole journal and recovery publisher.
Cancellation and settlement each occur exactly once.

For the post-progress/pre-activation boundary, operator-authorized Option A
gives the runtime one shutdown latch set synchronously before its sole
`registry.shutdown()` suspension. After accepted `recordProgress` and before
installing the runtime-active owner, submission rechecks that latch, waits for
that same shutdown's registry settlement, consumes the retained exact pre-start
terminal result, and publishes it through `publishPrestartTerminalSubmission`.
That path returns before active installation or native start; it creates one
typed cancelled `effectResult` and leaves no registry or runtime active owner.

Each cancellation journal commit, its pre-state read, and its failure snapshot
owns the runtime FIFO mutation/publication boundary. The boundary is released
before cancellation or settlement suspension. While the exact active owner
remains, a concurrent manual submission is transiently refused as busy from the
current transaction-complete snapshot before gateway evaluation; it commits no
successor refusal event, effect, or revision that could terminalize or clear the
active owner.

If any Stop-stage, observation, or terminal-result append fails, the runtime
retains the exact active owner and the uncommitted observation/result cursor,
reports `publicationPending` with a typed stage and recovery capability, and
admits no successor. Explicit recovery resumes only that cursor; it cannot
choose an outcome, issue a second cancellation, fabricate settlement, or grant
new Stop authority. If shutdown settles the owner while persistence remains
unavailable, the same publication-recovery capability survives with the exact
terminal cursor until durable publication can resume. The complete result
becomes idempotently cached only after terminal publication and remains so only
until successor admission clears it before launch, after which the predecessor
capability is stale and cannot stop the successor. A mismatched capability is
always stale. Drawing Stop requires controller-settled Pen Up and retains
possible-ink truth; unresolved settlement is ambiguous.

While terminal publication is incomplete, the app projects only the runtime's
typed recovery capability with an intent-specific manual jog, drawing, Pen Up,
or Pen Down remedy. It disables every manual effect control, hides the stale
Stop action, and rejects a stale recovery capability. Invoking the exact current
capability calls only `recoverTerminalPublication`; it does not re-admit the
intent, reissue controller work, cancel, or settle. Successful recovery clears
only the matching publication diagnostic and restores availability from the
new runtime snapshot.

Manual availability is derived from the runtime's actual episode phase, not
workspace request flags. A terminal ambiguity projects one typed disposition
bound to its exact effect ID, environment, and observation ID and distinguishes
possible ink from other ambiguity. While that disposition remains unresolved,
all manual effects are disabled and stale disposition actions are rejected.
Only explicit operator evidence for the matching typed action advances the
episode. It never retries, redraws, reissues, cancels, or settles controller
work.

Other contextual exercise Stop capabilities retain their existing owners.
While physical movement owns an exercise, its Stop is
the only movement-ending exercise action. Cancel becomes available only after
movement settles.

Boundary side identity is the operator's typed X−, X+, Y−, or Y+ direction plus
settled controller evidence. Boundary uses controller-owned fixed 50 mm renewal
segments at 500 mm/min with no Camera or Vision adviser. Operator Stop, fresh
Idle, and final MPos remain the acceptance authority; camera availability cannot
alter direction, renewal, Stop, or side acceptance.

One source-indexed actor `PlotterBoundaryRuntime` owns Boundary direction,
normal/replacement/additional side acquisition, center travel, exact attempt and
operation identity, cancellation capability, terminal truth, and immutable
accepted Boundary facts. Every request is a `PlotterBoundarySubmission` bound
to the displayed `PlotterBoundaryProjectionReference` and one value-bearing
`PlotterBoundaryIntent`; stale projection, changed effect facts, foreign Stop,
active ownership, invalid direction, publication recovery, or closed admission
returns a typed refusal and remedy before lower work. LIVE and SIMULATED have
independent revisions, attempts, operations, accepted facts, and terminal truth.

Admission synchronously installs the exact operation, cancellation capability,
runtime-owned task, and one-shot reservation-publication latch before the first
suspension. The task cannot enter a package admission gate, acquire facts, or
prepare any lower effect until the genuinely async projection sink has returned
from publishing the non-effecting `.reserving` phase; only then does the runtime
release its latch. A fact or admission refusal settles that same minted owner
into one terminal refusal and invokes no lower effect. One runtime-owned task
drives retained Pen Up normalization before every side acquisition and center
travel, then fixed-segment side motion or retained center travel, exact lower
settlement, and publication.
Operator Stop/cancel/shutdown target only the matching cancellation capability.
Natural completion, lower refusal, travel limit, mismatched Stop, cancellation,
shutdown, ambiguity, or save failure never replaces a previously accepted
Boundary. LIVE acceptance still requires the retained controller owner's fresh
Idle/final MPos truth. SIMULATED uses the retained EA-07 causal simulator seam,
is explicitly nonphysical, invokes no LIVE persistence or effect, and claims no
attended evidence.

Accepted LIVE Boundary and center facts are saved before publication when the
existing retained-package policy permits replacing the disk prefix. Construction
uses the current accepted Pen/machine prefix, never
inactive saved camera/tip descendants. When Start New Learning retains an older
complete package, the app verifies that exact disk package and keeps an incomplete
replacement session-only until the existing completeness policy permits replacement.
Otherwise the staged prefix is saved before publication. A failed save or retained
package identity check retains an identity-bound publication-recovery capability; recovery retries
only that staged save and never resends Pen or motion. A runtime-owned weak
Sendable projection sink publishes immutable admitted, moving, cancelling,
recovery, and terminal state without a workspace task, latch, retry, unchecked
relay, or second semantic owner.
While publication is incomplete, canonical UI exposes only the exact
`.recoverPublication(capability)` request and suppresses new side acquisition or
center travel. Learning vacate/reset blocks pending publication and settles an
active Boundary through its exact capability. It then reserves a non-destructive,
capability-bound reset that closes new Boundary admission while retaining the
current projection, aggregates, graph/checkpoint, session, and recovery truth.
The workspace persists the Learning prefix before submitting the exact commit;
only an applied commit permits downstream local cleanup. Persistence refusal
submits the exact abort and leaves the retained Boundary and local authority
unchanged. Stale or foreign commit/abort capabilities refuse, and shutdown does
not erase an unresolved exact reset reservation.
Camera, Vision, checkpoint encoding, replay, incident assembly, controller
transport/safety, RunInterpreter renewal/Stop, and later calibration/artifact
semantics retain their existing owners. The retained
`AcceptedMachineArtifactCheckpoint.boundarySideAggregates` is durable lower
artifact data, not workspace Boundary authority.

After one accepted side, the selected direction remains unchanged only when it
is still allowed; otherwise the runtime selects the first remaining allowed
direction. An empty allowed set is completion, not another acquisition. The
first move to an accepted four-side center is not a retry. Retry becomes true
only when retained terminal truth belongs to a failed, stopped, or ambiguous
center-arrival attempt while center authority remains and arrival is absent.
The runtime refuses a submitted retry bit that differs from that published
derived truth, and refuses every further center admission after accepted
arrival; neither mismatch fabricates a default or invokes a lower effect.
Before LIVE side motion begins, the composition submits the retained Discovery
announcement through `PlotterSpeechEffectRuntime`, whose terminal result remains
advisory. Boundary preserves output-before-motion ordering and awaits that
bounded result, then rechecks exact cancellation/shutdown and reacquires the
complete external effect identity immediately before lower motion admission.
The Pen Up/Down cues have a different dependency: their speech request is
admitted before the corresponding Pen command, but synthesis completion does
not gate that command or the next physical-confirmation prompt. Shutdown closes
speech admission, cancels retained synthesis, and joins it independently.
SIMULATED motion remains nonphysical and unchanged.

When a retained center-arrival terminal is recoverable and no operation is
active, the exact typed retry is presented before generic needs-attention; this
does not authorize automatic resend. The visible activity is derived from that
center terminal rather than a legacy exploration-failure field. Restore and
staging failures publish their typed localized detail, including the finite
center residual and the current machine-position acceptance tolerance. Before
Camera Calibration accepts a reference, it acquires a fresh settled machine
observation and requires that exact position to match the accepted Boundary
center under the same policy; neither stale MPos nor a copied Boundary center is
accepted as current controller truth.

If the current pose is off center, Camera presents **Return Pen Up to Accepted
Center** before a new run. This explicit action uses the accepted geometry without
replacing Boundary or camera artifacts. It requires fresh unambiguous Idle/Pen-Up
truth, compatible controller context and current pose authority; both endpoints
lie within the accepted Boundary. After Pen-Up normalization and before XY
admission it rechecks cancellation and the exact attempt, operation, source,
controller, coordinate, pose and Boundary authority. Stop uses the exact travel
capability; only settled, freshly confirmed arrival enables the next run.
Historical Saved Boundary evidence remains immutable and is usable only after
current visual position revalidation and compatible fresh controller context.
Camera failure instructions retain their actual cause; a position refusal does
not prescribe replacing the cap reference.

That exact fresh `MachinePosition` is sample zero of the calibration plan. The
planner must retain it directly rather than reconstructing an equivalent point
through normalized-coordinate arithmetic; subsequent physical settling checks
use `MachinePositionAcceptancePolicy`, while reference identity checks remain
exact.

Shutdown is also revalidated on both sides of any suspended retained Pen
admission. An admission that resumes after shutdown cannot create even an empty
Discovery transaction, revive an accepted click, or continue toward a lower
effect. This remains the retained Pen owner's concurrency rule; Boundary does
not acquire Pen semantic authority.

Any ambiguous circle-chord motion, Pen Down, or Pen Up outcome after possible
contact creates possible ink. The circle center/radius plus replaceable paper-instance identity
is blacklisted across cancel, restart, and reset, and the workflow stops for
explicit recovery. No automatic retry, resend, retap, redraw, or continuation
is permitted. A wrong click may be replaced only on its same frozen exact frame
and causes no mechanical action.

## Exercise 1.3 camera calibration authority

Exercise 1.3 derives a calibration rectangle inside the accepted Drawing Boundary
with the existing 10 mm safety margin. Boundary discovery proves machine space,
not paper coverage or camera visibility. Without separate coverage evidence, the
bootstrap rectangle is reduced symmetrically around `C`; it must preserve at
least 10 mm usable span on each axis. The rectangle and derivation are evidence.

The unique normalized positions are:

- `C` — 50% X, 50% Y;
- `X−` — 10% X, 50% Y;
- `X+` — 90% X, 50% Y;
- `Y−` — 50% X, 10% Y;
- `Y+` — 50% X, 90% Y.

Pen-Up cap anchors at `C`, `X−`, and `Y+` fit the initial affine map. `X+` and
`Y−` are sealed independent holdouts. Both holdouts must pass the declared pixel
residual policy before a weighted all-five refit can be staged. Explicit
acceptance atomically creates the current `MachineCameraRegistration`.

Each LIVE cap anchor requires exactly three strictly newer compatible exact
inspection frames after a preliminary freshness boundary. Every frame must
contain one observed unambiguous cap candidate. Maximum pairwise cap-centroid
spread is diagnostic and does not veto acquisition. The newest third exact frame and its measured
centroid, bounds, and confidence are retained without averaging; the preliminary
frame is not accepted cap evidence. SIMULATED causal geometry remains separate
nonphysical evidence and cannot prove live optical stability.

The artifact retains all five exact-frame correspondences, roles, holdout
residuals, uncertainty, applicability rectangle and derivation, semantic optical
identity, machine geometry identity, controller session, coordinate revision,
and estimator revision. It maps machine position to the visible pen cap.
It does not locate the paper-contact point.

## Exercise 1.4 pen-tip calibration authority

One supervised **Draw Four Calibration Circles** action owns one exercise attempt
and one stoppable operation. It draws no center mark. The four 2 mm-radius mark
centers are inset 10 mm from their adjacent accepted Boundary edges:
`minX + 10 mm`, `minY + 10 mm`, `maxX − 10 mm`, and `maxY − 10 mm`. The full
2 mm-radius paths therefore retain 8 mm of clearance to those edges. The
retained corner
values are canonical evidence-slot identities, not fixed axis-only physical
offsets. Exercise 1.3 retains its separate center plus four ±24 mm camera-
calibration positions and holdout authority. Operator-visible motion text names
the actual minimum/maximum-axis corner.

The Exercise 1.4 batch first commands and settles one idempotent Pen Up, then retains
that batch-scoped Pen-Up authorization for approach, circle-start, inter-circle,
and reveal travel. The action may start with current Pen Unknown or Down, including
after Use Saved Learning; it does not require a separate manual Pen Up. A failed
initial raise permits no travel. Connection, explicit Motion authorization,
controller readiness, camera and accepted-calibration prerequisites still apply.
Camera calibration and capture-only checkpoint revalidation retain their existing
settled-Pen-Up prerequisite. At every mark it retains the circle's pre-mark exact frame,
cap, controller, and settled-position evidence; lowers and settles using the
current Exercise 1.1 profile; draws one closed 2 mm-radius circle as 16 finite
typed chords at the canonical 500 mm/min app-owned XY feed, reduced only by the
existing controller-reported applicable axis ceiling; then raises and settles
before any next travel.
The four circles therefore contain exactly 64 typed chord outcomes, four Pen Down
settlements, five Pen Up settlements including the initial normalization, and no
connecting Pen-Down stroke during calibration. This batching removes duplicate
raise commands before already-authorized Pen-Up travel; it does not relax Pen-Up,
Idle/final-MPos, Stop, or possible-ink requirements. Exercise 2.1 then draws the
physical perimeter through the four centers as one closed plan with four
right-angle turns.
Each observation retains its own physical operation evidence. Command completion
is not proof of physical pressure, contact, or observed ink.

The batch performs four pre-mark controller-context probes and one final reveal
probe, then publishes one final machine snapshot. Individual chord settlement
does not trigger another workspace snapshot, Learning projection, or workflow-
telemetry record; the controller outcome remains typed and authoritative.

After the fourth circle only, the operation returns Pen Up to the corner
rectangle's geometric center, requires existing Pen-Up, Idle, and settlement
evidence, captures one newer exact frame, and revalidates current camera/cap
applicability once. All four observations share that final frozen reveal frame.
That reveal remains immutable physical/cap evidence. While its point-selection
request is current and contains zero clicks, the operator may use **Capture New
Click Frame** after clearing the armature. The tip-calibration runtime admits
the typed transition; the point-selection runtime atomically replaces the old
request only after the lower adapter reacquires current connected Idle, Pen Up,
no active controller operation, no sticky ambiguity, unchanged exercise and
paper identities, unchanged camera source and semantic optical identity, and a
strictly newer exact frame. It issues no motion, Pen command, redraw, or
automatic retry. One or more retained clicks disable replacement until the
operator explicitly clears them.
Acceptance installs the rectangle through the four circle centers as the
`TipCameraRegistration` applicability rectangle. The accepted Drawing Boundary,
not that inset rectangle, is the Drawing Studio drawable region. Preview and paper-
coverage projection between the Border and Boundary use the registration's inferred
affine projection and do not enlarge the recorded calibration applicability.
That extrapolation is diagnostic presentation only: it cannot by itself support
attributable camera/ink evidence. When an operator accepts a paper-coverage
polygon, the operator assertion supplies paper-coverage authority; the projected
polygon remains diagnostic and supplies no tip-map or camera/ink evidence.
Exercise
1.4 never changes zoom, pan, preferred zoom, or viewport focus
automatically. During proposal review, the camera view separately labels the
accepted Drawing Boundary projection and renders the proposed Drawing Border
in cyan. The Boundary projection is an inferred 10 mm extrapolation from the
proposed contact map, not measured boundary ink. The 10 mm-inset estimator has a
new revision: previously accepted fixed-offset, v6 edge-touching, and five-mark
registrations remain truthful only within their recorded applicability rectangles
and are never widened or reinterpreted without a fresh physical batch.

Each accepted `ToolContactObservation` is immutable raw evidence for one
commanded circular mark and asserted circle center. It retains:

- attempt and operation identities;
- intended mark position and settled MPos;
- machine geometry, controller session, coordinate-frame revision, and
  controller-context evidence;
- the 2 mm-radius/16-chord/500 mm/min requested commanded geometry, actual current
  Down/Up actuation values, and Pen Down/Up outcomes/timestamps;
- tool assembly, contact profile, and paper-plane revisions;
- exact pre-mark frame and cap estimate;
- the shared exact final-reveal frame, settled reveal pose, observed cap, and
  diagnostic cap-map residual; prediction error does not reject acquisition;
- clicked camera point with role `assertedCenter`, pointing uncertainty,
  timestamp, presentation-transform revision, and its separately exact click
  frame when the operator replaced the reveal request; legacy observations
  without that field use their original reveal frame;
- disposition and all consumed artifact/algorithm revisions;
- content-addressed locators only when exact bytes were actually archived.

Every Exercise 1.4 comparison of continuous machine-space values uses the shared
named nonzero position tolerance, including intended targets, commanded mark
centers, controller-settled positions, applicability bounds, and tip-projection
queries. Exact equality remains for discrete identity and immutable provenance;
it is never an admission gate for a continuous physical or computed numeric
value.

The click is an assertion, not a seed for an automatic detector. Click order
does not identify a calibration position. After click four, the app projects
the four known corner machine positions through current `MachineCameraRegistration`,
centers projected and clicked sets to remove their unknown common cap-to-tip
translation, evaluates all 4! one-to-one assignments, and selects the minimum
total squared pixel distance. Exact numerical ties resolve by canonical
calibration-position order. No distance or ambiguity threshold may reject or
block that association. The earlier cap-map residual at each corner is retained
as diagnostic evidence, not used as an admission gate outside the Exercise 1.3
bootstrap rectangle. **Undo Last Click** or **Clear Clicks on This Frame**
changes only clicks on the same frame and performs no motion, ink, redraw,
capture, zoom, or pan. **Capture New Click Frame** is available only at count
zero and replaces the exact request without changing the preserved reveal
evidence. The fourth click atomically creates the four accepted
observations and constructs a reviewable pen-tip-calibration proposal. The exact frozen
frame, click markers, proposed map, model form, residuals, RMS, covariance, and
uncertainty remain visible. **Accept Pen-Tip Calibration** commits the registration.
**Reject Pen-Tip Calibration**, **Undo Last Click**, or **Clear Clicks on This Frame**
returns to same-frame selection without motion, ink, redraw, or capture. A
failed atomic acceptance exposes a commit retry.

Model construction first fits one direct affine pen-tip calibration from all
four observations. Constant camera-pixel correction on the accepted cap map is
used only when affine construction itself throws. Exercise 1.4 has no holdouts,
model-quality thresholds, residual thresholds, confidence thresholds, or
numerical failure route. All-corner residuals, RMS, covariance, and uncertainty
are diagnostic evidence only; their magnitude cannot reject either model or
block progression. Numerical fitting cannot request paper replacement or route
to **No Automatic Redraw**. Only explicit acceptance creates
`TipCameraRegistration` and makes Stage 2 current. The next operator-owned
physical authorization is **Draw and Validate Drawing Border**.

Paper replacement is recorded only when paper was actually replaced or through
the existing possible-ink recovery. It is never a numerical model outcome.

`TipCameraRegistration` maps machine coordinates directly to paper-contact
pixels. It retains the affine transform, model form, covariance/uncertainty,
diagnostic residuals, applicability rectangle, four observation hashes and
revisions, semantic applicability identities, capture sessions, accepted
revision, estimator, timestamp, and derivation.

A cap-to-tip difference at one pose is diagnostic only. It is not a durable
camera-independent tool vector because the pen cap and paper lie in
different planes.

## Applicability and durable checkpoints

Tip applicability separates:

- ephemeral `CameraCaptureSessionID`;
- semantic `CameraOpticalConfigurationIdentity`;
- `MachineGeometryIdentity`;
- `MachineCoordinateFrameRevision`;
- `ToolAssemblyRevision`;
- `PenContactProfileRevision`;
- replaceable, ink-specific `PaperInstanceRevision`;
- `PaperContactPlaneRevision`.

Changes apply as follows:

- presentation zoom/pan: retain authority;
- proven crop/resample transform: derive a rebased projection and covariance;
- binary, process, or capture-session restart with the same camera device and
  proven identical semantic optics: retain accepted calibration; restored physical
  position remains a separate visual-verification prerequisite;
- unknown device, source, crop, mirror, orientation, capture zoom, mount,
  lens/focus, or optical change: invalidate;
- known machine-coordinate rebase: rebase intercept and domain;
- unknown origin or machine geometry/steps/direction/kinematics change:
  invalidate;
- tool, holder, armature, pen cap, nib, contact profile, or remount change:
  invalidate;
- new sheet explicitly on the unchanged support/stock/contact plane: rotate the
  paper instance, clear sheet coverage and ink-specific state, retain tip authority;
- changed support, stock thickness, contact height, or contact plane: rotate the
  plane identity and invalidate tip authority before a new Exercise 1.4 batch;
- LIVE/SIMULATED source change: invalidate cross-source optical authority;
- raw observations: retain as immutable history under every change.

Same-plane replacement retains accepted pen settings, machine boundaries,
machine/camera and tip calibration, and completed Learning. It clears only the
previous sheet's coverage, transient captures/proposals, sheet-specific exclusions,
and settled current-run state through the existing lifecycle. Persistence must
complete before the new identity is published; failure leaves active and durable
state coherent. A partial checkpoint-save failure restores the exact preceding
checkpoint and paper context. Once durable replacement commits, shutdown joins
its final owner handoff and projection rather than abandoning half-published
state. Active execution or evidence publication refuses replacement.
After durable new-sheet publication, the existing Drawing Run owner rebuilds
its possible-ink plan index for the current paper. Records on the prior sheet
remain immutable, and the same-sheet no-redraw rejection remains in force.
Prior calibration and drawing records keep their original identities. Blank
paper has no ink yet; that is not missing calibration. The compatible current
camera immediately displays the calibrated outline. Confirming coverage binds
the actual visible preview frame at the operator action. Only that explicit
assertion seals the frame's content identity; passive video does no hashing.
An older completed analysis cannot replace a newer exact selected frame.
Draft and Run consume the coherent selected frame after confirmation.

If a prior same-plane reset lost only active tip authority, **Use Saved Learning**
can recover the compatible retained accepted package even after its startup
choice was applied. Existing checkpoint identity, source, session, and dependency
validation still decides applicability. Recovery neither replays drawing nor
silently accepts a changed contact plane, tool, camera, or coordinate context.

`AcceptedLearningPathCheckpoint` is the one atomic durable accepted-prefix
envelope. It contains optional accepted pen calibration, machine-only Drawing
Boundary and center artifacts, Exercise 1.3 machine/cap registration, the
accepted Exercise 1.4 pen-tip checkpoint, the accepted pen-cap appearance, one
bounded reference frame, and an Exercise 2.1 evidence-record reference. Production migrates
the former machine-only and tip-only files into this envelope and deletes the
legacy files after successful save.

Loading creates one presentation-only Saved Learning candidate. It cannot restore Motion authorization,
current Pen pose, workflow state, operation ownership, a Stop capability, a
pending command, a current camera frame, or a continuation. Before any choice,
the app projects compatible saved calibrated Boundary, Border and cap geometry onto the
current frame and reports bounded integer shift plus background mean absolute
difference when a compatible saved reference exists. That report is advisory;
it has no threshold and cannot accept or reject the package. Archived drawing
paths are never automatically projected onto live video, even when paper and
calibration applicability match. Records retain their original placement and
evidence context for review and ink protection; they do not select the current
target. The calibrated Boundary and Border remain visible.

The startup candidate exposes exactly **Use Saved Learning** and **Start New
Learning**. Use Saved Learning atomically rebuilds the process-local dependency
index with the exact stored revisions and installs the accepted values without
motion, Pen-pose restoration, or command replay. Start New Learning applies no
saved value and retains the last complete package until a newer dependency-
complete package can replace it atomically. The operator owns this decision.
Incomplete replacement progress remains session-only during this preservation;
the one saved slot does not retain both packages across restart. Fresh Boundary
acceptance cannot implicitly apply the inactive package's camera or tip calibration.
Binary/process restoration and controller continuity loss cannot prove current
physical carriage position. The unpowered armature can move under gravity while
controller MPos remains unchanged. A restored machine/cap map therefore
retains accepted Learning and overlays but requires **Re-establish Position from
Camera** before coordinate-dependent automatic Learning or drawing. A saved
cap-map prefix without tip calibration uses the same recovery before new
calibration marks. A Boundary-only package has no retained map for this visual
recovery; it retains accepted Pen Learning and reports the specific Boundary/
Camera recovery needed before derived travel.
The existing recovery owner acquires fresh exact-frame learned-cap evidence at a settled Pen-Up
controller position; it issues no motion, click, mark, paper replacement, or
Learning Path replay. Controller settings, offsets and MPos are necessary context,
not physical-position evidence. Recovery uses the existing unique stable cap
acquisition policy; confidence remains diagnostic rather than introducing a
new numerical cutoff. A current verified session retains position
applicability through ordinary known motion and same-plane sheet replacement.

Accepted Learning completion depends on the retained accepted artifacts and
outcomes, not the current Pen pose. A compatible complete checkpoint restores
the same completed milestones as finishing those exercises in this process.
Unknown or down Pen pose is an execution-readiness fact. Explicit **Enable Motion
& Raise Pen** first establishes authorization, then commands and awaits one Pen Up
through the existing manual owner and current learned profile. Already-Up skips
that command; Connect, passive probe and Disable Motion do not actuate the pen.
Failure leaves the actual pen outcome visible and dependent recovery unavailable.
**Raise Pen** beside **Re-establish Position from Camera** provides the same typed
manual operation without opening Motion or reopening Pen Interaction. A held
finite servo operation retains its existing noncancellable settlement policy; the
UI does not invent a Stop capability. Settled Pen Up still requires separate
current camera verification before physical position is accepted. Loading Saved
Learning never actuates the pen. If its accepted profile differs from the profile
that established the current Up/Down state, the existing lower owner marks that
state Unknown; adjacent Raise Pen must settle the accepted settings before camera
recovery. An identical profile retains the already-settled state. A busy lower
owner refuses reconciliation before accepted Learning is published. Actual incompatible controller, optical, tool, or contact-plane
dependencies retain their precise existing remedy. The implementation correction
and its proof are tracked in the execution plan's
[workbench and portrait completion correction](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md#workbench-and-portrait-completion-correction-2026-09-08).

Checkpoint revalidation can issue a new tip-registration revision while retaining
the original accepted calibration lineage. An existing Drawing Border record
continues to cite the revision it actually evaluated. Both completion restoration
and aggregate-checkpoint validation recognize the retained original acceptance;
a revalidation revision change alone must not discard that Border result or
prevent saving it again.

An actual controller-coordinate reset, camera move/remount/reframe, tool or
contact-profile change, or paper-contact-plane change is a physical semantic
change, not a software restart. A detectable context or optical mismatch keeps
authority unavailable or invalidates it. A known coordinate translation may be
explicitly recovered and rebased; unknown rotation, scale, geometry, or
assembly change invalidates. A fresh observed cap can establish a pure
carriage-coordinate translation against the retained camera map. Recovery must publish the translated machine
Boundary, camera map and tip calibration coherently under one coordinate
revision, preserving their accepted lineage and original drawing evidence.
Stale, ambiguous, unavailable or mismatched observations cannot authorize motion;
cancellation or failed durable publication leaves preceding accepted authority
intact and position unverified. Camera/assembly changes that cannot be explained
by that supported translation still require the owning reset. Restoration never
uses unchanged MPos as proof that an unpowered carriage stayed physically still.

## Stage 2 dependency boundary

Drawing Validation requires accepted Drawing Boundary/coordinate evidence and one
exact current `TipCameraRegistration` revision.

Exercise 2.1 constructs one immutable closed polyline through the four accepted
circle centers: minimum/minimum, minimum/maximum, maximum/maximum,
maximum/minimum, and back to minimum/minimum. It therefore has four orthogonal
edges and right-angle turns. For the current calibration, those centers define
the Drawing Border exactly 10 mm inside every accepted Drawing Boundary edge.
The planner admits that border against the accepted Drawing Boundary using the
planning-containment policy: no commanded ink geometry may lie outside the
Boundary, except for a separately versioned numerical epsilon that cannot equal
or reuse machine-position settlement tolerance. The Drawing Border is target
geometry; it is never reused as its own spatial admission region. The plan is
projected through the tip registration. It owns its own local pre-frame baseline,
Pen-Up reveal MPos, Drawing-Border-start travel, one canonical drawing-plan owner, return to the same reveal
pose, strictly newer post-frame, and generic planned-drawing ink observation.
Its request and result cite the exact tip revision.

One **Draw and Validate Drawing Border** click starts all normal Exercise 2.1 phases. The app chooses the closed Drawing Border
deterministically, renders the model-predicted paper-contact border in cyan
on the live current frame before motion, captures the baseline, moves and draws
all four edges, returns to reveal, runs planned-drawing Vision, and records the
normal comparison without further approval. Motion retains one
capability-bound **Stop**. A refusal, ambiguity, possible-ink outcome, or failed
atomic commit stops at a truthful recovery state and never authorizes redraw.
A rejected Vision result after naturally completed drawing is retained as an
inconclusive observation and completes the trial without another operator action.

Planned-drawing observation measures departure from the prediction. A detected
pixel's distance from the planned path must contribute to the measurement, not
veto the entire observation through a maximum correspondence distance. The
observer compares newly darkened pixels in the recorded region with the nearest
planned path and retains the sampled geometry and residual. A common translated
reference may resolve correspondence within the observed region; it must never
replace measured coordinates or be confused with background camera alignment.
Search and final association share the same work budget. Pixels tied between
paths are excluded individually; every planned path must still supply enough
unique support for a sampled centerline. Isolated crossings do not veto otherwise
supported paths. Duplicate or underresolved paths remain rejected with zero
verified strokes and no retrospective fitting contribution. The original
association work budget counts actual search and projection work; optimization
must preserve exhaustive distance/tie semantics and cancellation bounds. This remains a
before/after difference measurement, not proof that every edge is visible or
that every changed pixel is ink. Rejections retain the detected pixel count when
extraction ran; zero detected pixels and inability to form a sampled path are
distinct diagnostics.

Intended geometry, observed ink, and residuals are required contextual Stage 2
evidence and have no global visibility toggles. An attributable observed frame
is retained in the append-only drawing-run archive as an evaluation holdout and
may be reviewed after the Learning Path finishes. It cannot silently change an
accepted calibration. Possible ink or
ambiguous motion never triggers automatic redraw or resend.

Exercise 1.4 means **pen-tip calibration ready** within its recorded applicability
and semantic identities. A controller-completed Exercise 2.1 trial means
**Learning complete** once its observation outcome is recorded. Attributable
ink comparison and inconclusive Vision are distinct retained outcomes; rejected
Vision records zero verified ink strokes and creates no successful comparison
artifact. Neither completion state means a generally trained adaptive drawing model;
that claim requires the repeated coverage, reserved holdouts, candidate/prior
comparison, shape evaluation, and typed readiness work defined in the Roadmap.

## Direct Drawing Studio boundary

Drawing's **Test Target** menu selects an exact 40 x 40 unit square with two
separate diagonals or a 40 x 20 unit rectangle. The explicit **100%** placement
action sets uniform scale to one through the ordinary Draft request; selection
preserves the prior scale and rotation, so neither the name nor selection alone
asserts physical size. Rotate explicitly to 0 or 90 degrees and verify the current
plan. Use **Show Target** in that menu when the overlay is hidden. Selection
preserves overlay visibility, creates an ordinary drawing revision
and sends no motion. Fit changes size and is inappropriate for an unchanged
40 mm holdout. Existing containment, current Learning, paper and Draw admission
remain authoritative. Physical millimetres require independently accepted metric
evidence; these deterministic targets prepare that measurement.

Ordinary drawings expose **Draw border**, defaulting off for each new drawing.
Edits retain the current drawing's explicit choice; **New Drawing** or a new-sheet
plan handoff resets it off. This draft choice controls physical ink only: accepted Learning and the displayed calibrated
outline remain available regardless. The border is the existing calibrated
Drawing Border (10 mm inside the accepted Boundary for current calibration),
not a repeat of Exercise 2.1. When selected, it precedes the artwork in one immutable
`DrawingProgram` and plan, so an interrupted portrait can still have its frame.
Previously retained plans keep their original order. Its geometry participates in preview, identity,
containment, checkpoints/progress, cancellation, possible-ink handling, and the
ordinary drawing's evidence. Initial Learning validation keeps its original
exercise and evidence meaning. A replacement sheet needs new coverage, not
another Learning border exercise.


The workbench keeps its video/portrait/simulation canvas permanently in the main
window. The canvas has no close control or View-menu visibility command. Five
optional control panes are Guided Learning, Video Settings, Motion, Active
Learning, and Portrait Studio. Native View-menu Show/Hide commands and
Command-Option-1 through Command-Option-5 control their visibility. Opening fills
right, left, lower-right, then lower-left. A side with one pane uses its full
height; two panes share that side through a native draggable divider. Closing a
pane preserves sibling slots; an empty side returns its space to the canvas.
A fifth opening replaces the oldest visible pane while retaining its workflow
state. Layout preferences migrate from the former dock model, and native split
views save divider sizes. There is no full-width bottom area, position menu,
move icon, automatic workflow reset, or closable Video panel.

The session toolbar owns controller selection, amber Connect/Disconnect and
Enable/Disable Motion actions, the diagnostic export tool, and the far-right
red Achtung! control. Existing typed Stop requests and Escape routing are
preserved; passive status badges and the separate command strip are removed.
The existing diagnostic export copies the exact displayed camera pixels, their
source/configuration/capture identity and digest, visible camera region, selected
program, admitted draft plan, sealed run plan, current tip registration, progress
and terminal detail. A retained plan must match that registration before its
camera projection can be compared. Raw
pixels and an unoverlaid PNG accompany the JSON, published last on a background
worker. Process identity distinguishes multiple running builds. Export never
starts a camera, moves hardware, refreshes stale evidence or turns a screenshot
into a raw frame. A retained/frozen frame remains explicitly timestamped.
The application-owned Voice control gates both listening and spoken output.
Voice off drains queued/active cues; Voice on permits the existing Pen-only Stop
route during an advisory cue. Hiding a pane does not own microphone lifetime.

Motion displays the existing controller owner's latest report in an isolated
readout, refreshing while visible at about 5 Hz. Controller state, MPos, and limit
inputs come from one report with its actual receipt time and sequence. Re-reading
an unchanged sample does not refresh its age; a newly received identical report
does. Values older than two seconds are labeled stale; missing and disconnected
data are explicit. Commanded pen state and historical outcomes are labeled
separately from reported values. Hiding Motion stops only its display refresh;
controller monitoring, fault handling, and command availability continue. Opening
it refreshes immediately, without a checkbox or independent serial reader.

Video Settings contains source choice, zoom, overlays, analysis cadence,
region controls, and Review Comparison for the retained Drawing Border result.
The comparison box appears on the canvas only during exact-frame review. Its
close control resumes live preview and removes the box; it does not discard the
comparison, accepted Learning, or drawing evidence. Video Settings can reopen
the same retained frame. Showing or hiding control panes does not select a camera;
explicit camera controls and workflow-title actions retain projected requests.
The permanent canvas uses the existing frame/overlay leaf and portrait renderer.
With no available image it displays an identified simulator preview, without
switching execution environment, consuming simulator faults, publishing an
observation, or altering Learning. Explicit frozen evidence and available
portrait photos remain displayable. These presentation changes never establish
camera or physical ink evidence.

Only the selected camera captures and analyzes. Explicit portrait camera selection displays the
face camera in the permanent canvas and suspends plotter acquisition/analysis.
**Send to Drawing** retains portrait controls, images, and program, settles
face capture, and returns the canvas to the plotter camera. Restarting the
same physical plotter optics preserves accepted Learning; ephemeral capture
identity is not optical change. Video processing must not update panel text or
layout. Changing frame counts, ages, measurement summaries, and detector chatter
belong in existing on-demand Diagnostics; stable operator prompts, real operation
transitions, and actionable errors remain visible.

One completed Exercise 2.1 trial establishes **Learning complete** and permits direct bounded drawing with the accepted pen-tip
calibration; it does not establish **Adaptive drawing ready**. Paper readiness
remains a separate operator assertion and is never inferred from that calibration.

Portrait authoring and Active Learning navigation are available before Learning completion.
Authoring retains an immutable program without requiring a registration or
Drawing Boundary; placement and planning still require those current artifacts,
and physical running retains its existing Learning, paper, and motion admission.
A missing calibration must remove the plan, not erase the authored program.
An unavailable run archive prevents running; it does not require a New Drawing
handoff or prevent authoring. Actual retained terminals and possible-ink state
continue to require their existing handoff.

Drawing Studio draft edits are revision-bound requests, not direct workspace
mutations. Target show/hide, catalog selection, exact-frame placement,
scale, rotation, centering, fitting, new-plan, paper assertion, retained-record
selection, and retrospective analysis are typed
`PlotterDrawingDraftIntent` values. Ordinary authored choices bind the environment
and authored draft revision; the owner derives their plan against current facts,
including facts whose publication follows Apply Saved. Target visibility belongs to the
draft presentation and does not alter execution identity. Panel visibility is
separate window state and never submits target show/hide.
**Hide Drawing** is directly available on the video while a target preview is
visible, and **Show Drawing** / **Hide Drawing** is available in Video Settings.
Hiding clears the preview and any staged drag, retaining the program, placement,
paper assertion, Learning and ink protection. It works while disconnected and
requires no paper replacement. Startup begins with the authoring target hidden.
Video drags pan by default; **Move Drawing** explicitly stages a placement
until the operator chooses **Pan Video** or starts exact point selection. Panning
retains fractional camera-pixel movement across pointer events and clamps at the
frame edge without accumulating hidden excess movement.
Exact-frame placement and paper assertion require the complete projected draft
and external-fact identity, including the displayed frame. Experiment selection
also binds its relevant Learning, geometry, and evidence facts. The sheet control
prepares that exact reference when the operator clicks, because ambient analysis
does not refresh the cached controls. A context change during preparation still
refuses confirmation. Creative authoring, previews, ratings, galleries and training
precede projection. When the plotter camera is selected, placement and material
setup follow, then paper confirmation and Draw at the bottom. Active drawing, evidence-processing and retained terminal status remain outside
the scroll area alongside the global Stop path. Failed and interrupted outcomes
retain their exact execution reason behind the existing question-mark help. The
existing RunID-bound **Prepare Next Drawing** handoff acknowledges the result;
hiding a pane, exporting diagnostics or reviewing images does not clear it.
An unresolved durable attempt also remains visible, without inventing a recovery
capability or permitting a new-run handoff. A stale authored
revision or environment refuses the edit; fresh Learning, registration, region,
paper, camera or run facts are not by themselves a stale-authoring refusal.
Those current facts still determine whether a plan can be derived, whether an
active run permits editing, and whether a retained terminal requires its existing
handoff. Refusals retain the exact owner/reason/remedy. The UI renders the
returned immutable snapshot; it does not decide admission or rebuild a plan.

Draft derivation reuses unchanged program, placement, registration, region,
tool, paper, optical configuration, and experiment/coverage inputs across
frame and control-status changes. Predicted geometry may be rebound to a newer
matching frame; measured overlays and exact-frame actions retain their own
identity checks. Missing or changed authority still removes or rebuilds the
plan. Size and rotation use continuous native sliders with rounded values and
submit at release (or on keyboard/accessibility edits), without hundreds of
native tick marks or planning every pointer movement.

The built-in catalog and Portrait Studio produce immutable `DrawingProgram`
values through the existing draft, placement, planner and drawing runtime.
Portrait Studio is a full workspace, independent of the plotter control docks.
Opening and closing it preserves those dock placements. The shared Drawing panel
owns placement, pen/material setup, paper coverage, Draw, Stop and result review.
Studio authoring remains available with an imported photo while disconnected.

Portrait Studio presents the current imagination and two alternatives beside a
large selected-drawing preview. Each alternative retains the source, framing,
algorithm and material context. Selection installs its exact recipe and immutable
program. Back restores the previous offered candidates and internal exploration
state without rerendering. Explicit framing or parameter edits establish a new
starting point and invalidate exploration history.

Variation is internal. Accepted parameter directions guide a bounded continuation
proposal and a complementary proposal; repeated aligned choices can increase the
step and reversals can decrease it. Screen positions are not parameter axes.
Bounded retries reject empty, failed, duplicate and visually negligible results.
Proposals account for material-imposed spacing and minimum-length floors before
spending render work, and retries change the parameter direction. The additive
Flow support and placement controls participate in the same preference space;
an evidence-scale change is inactive while both support amounts are zero.
Parameter-only probes avoid already attempted effective settings, and recovery
varies with the round seed and failed settings within the render-work bound. Exhausted
similar options are distinct from rendering failures. A compatible, visibly distinct
candidate from recent history may remain available as a labeled Previous option
when the bounded search finds no useful new candidate. Keeping Current while
alternatives are pending leaves their generation running; it cannot turn unfinished
work into failed choices. The current drawing and Back remain usable while
alternatives are pending. Stored choices are provenance and session
search state, not a trained aesthetic or likeness model. Legacy nine-slot traces
remain readable under their original policy revision.

The compact Source control keeps the original photo accessible. Detailed Framing
and Style controls are collapsed by default. Styles offers three rendered
algorithms: Flow Edge (the default), Tonal contours and Sketch. Hatch, Crosshatch
and Sketch + hatch remain decodable for historical candidates but are not
generated as authoring alternatives. Selecting
an algorithm installs its exact completed candidate. The existing renderer and one
cancel-and-join work drain own center, exploration and algorithm-comparison work.
Selected candidates remain usable while a new neighborhood is pending; stale source,
configuration, round or tile identities cannot replace a later choice. Algorithm
comparisons remain lazy. The three style tiles are fixed starting drawings for
the current photo, framing, pen and material. Their baseline tuning and lineage
are frozen when that context is established; trajectory selection, Current, Back
and ordinary vector adjustments do not regenerate or replace them. Selecting a
tile installs that exact displayed candidate. A source, framing, pen or material
change establishes a new baseline. Folding Styles stops unfinished reference work
while retaining completed tiles. Reference-job identity is independent of the
selected-drawing revision, and stale reference work cannot select a newer drawing.
Proposals reuse analyzed rasters and bounded caches.
Flow preparation reuses source evidence, structural curves and orientation fields
in source-specific bounded workspaces. The render worker also constructs the
candidate and preview footprint off the main actor; promoted candidates reuse
their footprint.
Crop to face, head margin and background removal belong to Framing; line/tone
controls and detail presets belong to Style.

Capture Photo stays in the toolbar. With a configured device, one click asks
the existing observation owner to activate that portrait camera, awaits readiness,
and takes a 0.8-second still-subject burst including exposure settling. One quality-selected
frame becomes the new source photo; the burst does not create a pose gallery.
Selection uses image sharpness and exposure evidence. It does not fuse unregistered
frames, reconstruct depth or establish improved optical focus. Camera selection
lives in the capture popover; pose and capture-duration controls are absent.
Cancel/Escape and acquisition settlement dismiss the white screen illumination;
no display brightness setting changes. Recent sources remain individually
selectable and deletable, bounded to 24 photos / 32 MiB; saved candidates own
independent source bytes. Deleting sources cannot revive them through late work.

Ordinary Studio has no continuous parameter pad, Big Head, preference-rating,
manual Variation or named-training controls. Historical candidate formats and
required source, raster, label and checkpoint interpretation remain compatible.
Existing fitted checkpoints are not loaded or consulted by normal Studio generation.
Save Imagination retains the exact candidate and bounded offered-set/choice trace
through the existing candidate archive without switching the editor into another
selection mode. Session Back retains exact candidates; its history is bounded and
does not promise an unlimited or restart-persistent undo stack. Browsing Imaginations belongs to Drawing Reviewer and does not
change the Studio edit. Source photos and vectors shown together come from the same
candidate, including retained candidates.

Flow Edge separates structural evidence from tonal stroke density. Its higher
resolution analysis supports detailed curves; coherence guides smooth line flow
without applying the legacy global tonal blur to structural detection. Tonal
streamlines use local density, separation and structural barriers. Material
adaptation sets spacing at the explicitly selected drawing height; a digital
preview or nominal spacing is not proof of separated deposited ink. Flow Edge
still produces the same immutable `DrawingProgram` consumed by ordinary Drawing.
Its Line form control offers Organic, Mixed and Rectilinear shading. Rectilinear
strokes choose a horizontal or vertical direction once and retain long straight
runs as endpoint pairs. Mixed shading distributes seeds between the two generators
and reserves them through the same structural and tonal spacing constraints;
it does not independently overlay two complete drawings. Feature curves remain
image-derived and do not claim a semantic face prior or reconstructed depth.

Four additive Flow parameters retain the existing drawing at zero: Tone support
varies the image evidence required for shading; Contour persistence varies
structural support across scales without replacing retained curves with blurred
geometry; Evidence scale shifts support between finer and broader neighborhoods;
Seed irregularity varies regular placement using deterministic within-cell offsets.
Tone and structural support are independent controls; changing structural barriers
can also change where tonal paths fit. Evidence scale is retained in the recipe
but is inactive when both support amounts are zero. Support preparation is lazy
and bounded per source, and all line forms retain shared material clearance.
Detail presets preserve these controls. They extend the common recipe; the three
algorithms still have different rendering semantics. This is not a unified learned
style model or temporal-motion synthesis. Current short capture retains one
selected source frame, not registered inter-frame motion evidence.

Pen & material displays the current applicable marker width and whether its origin
is estimated or independently measured. It is an input to drawing appearance, not
a calibration slider. Material selection and measurement belong to shared Drawing
setup. Measure Ink inspects frozen existing images before estimating deposited
width. Adapt Detail explicitly produces a new portrait candidate with final-scale
spacing suited to the selected material; it never rewrites an old candidate or
changes physical calibration. Check Detail at This Size diagnoses short strokes
and crowded parallel segments without measuring ink, changing the program or
establishing physical drawing quality. Explanatory and provenance text is behind
accessible question-mark popovers; the default interface retains control labels,
concise progress and actionable error states.

The same `PortraitPlaneProgramPreview` renders Studio, algorithm tiles and retained
vector previews. Planned presentation uses only an exact candidate/program/region
match to the admitted artwork plan; otherwise the view is explicitly a reference
preview. Reference presentation does not invent physical size. The legacy thumbnail
renderer is no longer a production UI path. **Send to Drawing** explicitly installs
a selected immutable program through the existing draft intent sink and initially
fits it. Re-showing the same admitted program preserves its current placement.
A successful handoff saves the exact candidate and reveals shared Drawing controls;
**Save Imagination** is optional library storage, not a prerequisite. The workflow is
Studio → Send to Drawing → placement/material/paper setup → Draw. Sending invokes
no motion. Later Studio edits do not mutate the placed program until another
explicit handoff. The existing Drawing panel keeps the exact admitted plan visible above its
scrolling controls in its region frame, including rotation, clipping and optional border. While a run
or terminal is retained it uses that sealed run plan; it never substitutes a later
Studio candidate. Without an admitted plan, an authored preview is labeled reference.

Drawing Reviewer lists every valid saved digital candidate as **Imaginations** and
ordinary/portrait physical executions as **Drawing results**. Opening the reviewer
loads the existing shared saved-library owner even if Portrait Studio has never
mounted. Loading and persistence failures are visible and retryable; concurrent
Studio/reviewer loads join the same owner. There is no gallery retention limit.
**Delete Imagination** changes library retention, not physical execution history.
Identifiers, hashes, recipes, programs, assets and execution links keep their
existing persisted formats.

Historical Drawing results prefer their retained execution-plan geometry, including
placement, clipping and optional border. If only the source program remains, it is
explicitly a source reference; absent geometry is explained. Retained paths do not
prove observed ink or controller completion. Historical records without photograph
references say so; missing stage photographs and unreadable retained photographs
have distinct explanations. No substitute photograph or current plan is invented.

The reviewer uses the existing evidence archive. It provides Fit/100% images, Close, explicit program
handoff and deletion without ratings. Delete Result stores a durable tombstone in
that archive, removes the result from review and future residual fitting, and
rejects normal image/rating access to it. Required immutable execution provenance,
possible-ink/no-redraw facts and shared raw media remain retained. It does not mark
the sheet clear or erase material evidence. Deleted review identities cannot be
resurrected by a delayed archive load. Candidate/source deletion continues to use
the qualified portrait archive's existing tombstones.

Fit retains the authored rotation and selects a valid uniform scale and centre.
The same fitting calculation supplies scale limits; rotating ordinary artwork
retains the current scale and clips at the accepted region. Center moves the
transformed, un-clipped ink bounds midpoint to the region midpoint without changing
scale or rotation; it does not center empty margins of the authored field. Planned
geometry remains visible across advancing compatible frames and changes with
program, placement, registration, Drawing Boundary, or optics. Measured ink and
exact-frame point selections keep their exact identity requirements. The displayed
target and executed plan share one program, placement, and plan identity.

Draw availability and the refusal/remedy presented beside it derive from the
existing Drawing Run owner. A second UI implementation of run admission must
not claim readiness when that owner will refuse. Accepted Guided Learning remains
the existing prerequisite for physical drawing; this correction adds no new
guard, interlock, or confirmation step.

Portrait drawing has one acquisition/execution/evidence path and no operator
choice between training and ordinary drawing before the run. Each archived run
retains the intended plan, execution outcome, baseline/post observations,
residuals or exact measurement rejection, and provenance. Later analysis can
select retained ordinary and portrait runs and reference their immutable records
through existing evidence/model owners; it
does not repeat acquisition or mutate the original run. Active Learning assigns
its predeclared experimental roles internally. A model may use only identifiable,
attributable residual components, and must report unsupported components. An
ordinary record used retrospectively for fitting cannot become untouched
holdout evidence. No second archive, recorder, dataset authority, or automatic
model application is introduced. The current retrospective analysis fits only
a constant machine-space X/Y translation from attributable stroke-normal
constraints when the selected geometry spans both axes. It reports fit and
prior RMS; tangent, spatial and direction-dependent corrections are unestimated.
Reserved and evaluation holdouts cannot be selected as fitting evidence through
this ordinary-drawing path. The candidate does not change the active model.

Portrait proportions derive from the actual cropped source pixel dimensions, not
from clamped or rounded analyzed-raster dimensions. New render identity includes
that source metric; previously accepted programs remain immutable. Fit preserves
the authored rotation and leaves unused area as needed. Rotation remains explicit
in the placement controls.

Ordinary artwork uses the accepted Guided Learning command-to-camera affine to
preserve proportions in the plotter image. Unequal axis response and shear are
compensated in one immutable `DrawingPlacement`, before planning every stroke.
This first increment retains initial Guided Learning, requires no ruler inputs or
controller calibration, and does not update the mapping from later drawing grades.
Camera foreshortening is accepted as part of this camera-relative drawing objective;
physical ratios, orthogonality, and millimeters remain independently unverified.
The Size multiplier preserves nominal command area; Fit uses the corrected rotated
field bounds. Explicit metric square/rectangle targets, coverage experiments and
Guided Learning marks retain their authored controller-distance geometry. Camera
square/circle targets exercise the same compensated placement as portraits. `DrawingPlanner` remains the single planner. Ordinary artwork explicitly opts
into clipping at the effective `DrawableMachineRegion`; exits and re-entries split
into deterministic separate strokes and checkpoints, with no pen-down bridge.
Fully excluded artwork produces no runnable plan. Strict containment remains the
default for calibration, explicit metric targets and coverage experiments. The resulting
`ExecutionPlanRevision` is content-addressed and binds program, placement,
region, calibration/model provenance, ordered strokes, and one checkpoint per
logical stroke. The video preview projects that exact plan through the current
tip registration on compatible current frames. The plan records whether every projected
point is inside that registration's applicability. A plan may use extrapolation
for diagnostic preview, but its camera/ink result is non-attributable unless all
evidence points are applicable or a newly validated registration revision
explicitly expands the applicable region.

One planning adapter is the only upper route to that pure planner. It preserves
deterministic program, placement, and content-addressed plan identity. The
retained Drawing Border workflow may use its package-only planning entry for
EA-10E, but that reuse does not move Border sequencing, execution, observation,
or evidence semantics into Drawing Studio draft authority.

Paper assertion persistence is nominal authority, not a presentation cache. In
LIVE, save must succeed before an accepted assertion is published; failure
leaves the prior assertion unchanged and returns an operator remedy. The paper
polygon is displayable only on the exact accepted frame. Currentness is
independent of display. For assertions with recorded optical and region context,
newer frames and restarted capture remain current when paper, source, physical
optics, recorded drawable region, and contact plane are unchanged. Changes to
those facts invalidate currentness. Legacy assertions retain capture-configuration
identity when optical context is unavailable. The diagnostic polygon never
measures paper edges or establishes tip-map, camera/ink, or physical evidence.

One `PlotterDrawingRunRuntime` authorizes the new-plan handoff after terminal
review. Program, placement, paper assertion, and experiment edits refuse during
an active run or while a retained terminal requires its exact RunID handoff.
Target show/hide and retrospective record selection/analysis remain available;
they change neither execution identity nor immutable archived records. After
handoff, plan authoring publishes an immutable plan only. Draft actions invoke
no controller motion, Pen, Stop, camera, Vision, or drawing-run archive write.
Retrospective analysis reads existing immutable evidence through its retained
owner; paper assertion uses its separate save-before-publication seam.
SIMULATED draft and paper results remain
**SIMULATED — NOT PHYSICAL EVIDENCE**.

Run actions are typed `PlotterDrawingRunIntent` submissions against the displayed
immutable run revision, environment, and exact plan identity. The runtime owns
exclusive start admission, one exact Stop capability, settlement, RunID-bound
review pin/unpin and new-run handoff, publication recovery, and no-redraw truth.
A stale projection or changed plan/fact returns the exact authority, reason, and
operator remedy; the UI cannot decide admission or issue lower effects itself.

Run eligibility requires LIVE mode, a connected authorized idle controller,
current paper-coverage evidence, and the exact reviewed EA-08A plan. The runtime
refreshes those complete facts and revalidates that exact identity around every
physical boundary. It issues idempotent Pen Up normalization, supervised travel
to the observation pose when required, and an exact baseline capture before
delegating the whole immutable plan to `RunInterpreter`. The lower interpreter
remains the execution owner for Pen actuation, finite segments, Stop, and
checkpoints. Before lower drawing execution actuates the pen, `RunInterpreter`
derives one per-stroke schedule by rounding cumulative displacement to the existing
three-decimal controller format and subtracting successive distinct rounded
positions. Wire-zero source edges coalesce; residuals carry forward within that
stroke. Interior component error is at most 0.0005 controller units. At a non-grid
boundary the nearest contained command is chosen inward, with error below 0.001
units. Neither bound accumulates with segment count; the admitted region is not
enlarged for rounding. Wholly unrepresentable strokes are explicit
preflight refusals, not silent success or pen taps. Intended plan hashes and source
segment indices remain retained; submitted/completed counts describe actual wire
requests. This is serialization precision, not measured physical accuracy.
New general Drawing attempts capture a versioned `DrawingMotionRecipe` before
durable dispatch. Its independent digest binds the exact existing plan revision
and content hash to authored ordering/direction, required stroke/pen/checkpoint
barriers, unchanged drawing/travel feeds and pen settings, captured controller
limits, and execution-strategy revision. Plan and program identities remain
unchanged. Historical attempts without a recipe remain explicitly unknown;
no-recipe callers, including retained Learning Drawing Border trials, preserve
isolated-segment execution. A changed captured controller-limit context refuses
before the first lower-plan pen effect.

With a continuous-within-stroke recipe, the controller sends one ordinary `$J`
command, waits for its acceptance ACK, then refills without an intervening Idle
drain. The host has at most one unacknowledged motion command; the firmware's
finite planner supplies backpressure. This preserves geometry, feed, source
mapping and stroke order while making connected segments available for look-ahead.
Short segments or transport delays may still starve the planner; uninterrupted
physical velocity and speed benefit require attended measurement.

ACK never advances the controller-completed frontier. An ordinary-response fence
precedes the terminal status query; the full receipt is checked for fatal lines
before fresh Idle and final-position evidence complete a stroke. Successful Pen Up
then permits checkpoint commit. Pen transitions and required barriers remain explicit. Stop suppresses further refill,
sends Jog Cancel through the same serialized writer, fences remaining ordinary
responses, and settles before pen cleanup. Partial writes, accepted-prefix
rejection, timeout, disconnect and reset preserve uncertainty and no-replay truth.
Best-effort cancellation after a usable-link failure does not certify settlement
or authorize pen actuation.

Retained attempt evidence includes lower-plan execution frontiers, source-to-wire
mapping and attributed drawing, travel, Pen Up and Pen Down spans with monotonic
boundaries and completed/refused/cancelled/ambiguous dispositions. These are
controller-operation elapsed durations including protocol waits, not direct
physical-motion or ink measurements. They exclude baseline/post-observation work
and do not represent end-to-end run latency. Missing legacy timing remains absent.

App-generated travel and Pen-Down drawing both request the canonical
500 mm/min XY feed; the existing controller-reported feed ceiling remains the
lower admission authority. Controller completion is not ink verification. After clean
completion, the runtime requires exact final MPos and a strictly newer
same-source post frame before applicability-aware observation. The runtime also
automatically retains a strictly newer photograph from the run's camera/configuration
before optional Pen-Up reveal travel. Retaining this photograph does not require matched-pose
coverage or Vision success and does not claim unobstructed visibility or verified
ink. Matched observation still requires its own settled pose and fresh frame.
Existing sheet/camera applicability depends on stream and optical identity, not
whether a current preview has already computed its evidence hash. Exact-frame
assertions and measurements still require sealed pixels.

For plans of at least four strokes, the same interpreter pauses at up to three
existing settled Pen-Up checkpoints near 25%, 50%, and 75% of the stroke count.
It acquires a strictly newer same-camera/configuration progress photograph, seals
the original pixels, and persists the exact completed-stroke/checkpoint frontier
before continuing. These captures introduce no intermediate reveal travel and
never split a stroke. Short plans retain baseline and final photos. A single long
stroke has no intermediate settled checkpoint. Capture/save failures remain
explicit; retained exact bytes can be retried without recapture or motion.

Progress photos survive interruption through the staged attempt archive. The
reviewer exposes them even when an interrupted run has no terminal record, with
completion unknown and possible-ink/no-redraw facts preserved. Stage photos carry
controller pose and capture freshness, not unobstructed-visibility or measured-ink
claims. They support later stage-aware inspection/learning; capturing them does
not fit or accept a model automatically. Stop while acquisition is in flight may
retain that returned frame, but prevents subsequent strokes and captures.

The Drawing Reviewer defaults to the newest retained result photograph and
shows a capture/coverage failure reason directly. A completed run with no retained
result photo says so in the active status. Completion-photo acquisition is part
of the run, without a later operator action. Stop, failure and ambiguity retain
only an already available frame and never initiate capture or reveal travel.

Geometry outside tip applicability remains executable but is explicitly
non-attributable and invokes no Vision ink measurement. An immutable evidence
record must append to the checksummed archive before successful terminal
publication. Append failure exposes exact recovery and cannot appear successful;
possible-ink/no-redraw truth remains even when persistence fails. Exact-frame
intended, observed, and residual geometry remains reviewable. Refusal,
cancellation, ambiguity, possible ink, Vision rejection, or evidence-store
failure cannot authorize resend or redraw. SIMULATED start is a typed
nonphysical refusal and invokes zero LIVE controller, camera, Vision, or archive
effects.

Every immutable `DrawingRunEvidenceRecord` fixes its acquisition role before the
outcome is known: ordinary portrait drawing uses the ordinary role automatically,
and Active Learning supplies its predeclared training/holdout role. Retrospective
selection references an ordinary record without rewriting that original role or
claiming it was a reserved holdout. The record cites request/execution frontiers, program/placement/plan hashes plus
the complete immutable execution-plan geometry for new records,
tip-calibration and paper provenance, terminal execution disposition, and exact
observation outcome. The checksummed archive is append-only. Records can be
inputs to coverage candidate fitting and evaluation; they cannot replay motion, restore a
capability, promote calibration, or accept a model. `DrawingReadinessAssessment`
is a typed schema only until all declared coverage, untouched holdout,
candidate-versus-prior, and shape-holdout requirements have attributable
evidence.

The four-circle placement guides project the canonical `SparseTipBatchMarkPlan`:
Boundary envelope, inset frame, four centers and all four circle paths. They are
planned geometry with a separate calibration-guide semantic identity and visual
grammar, separate from artwork intended paths, measured ink and exact-frame
selections. Hide Drawing hides artwork only; compatible calibration guides remain.
A guide never supplies an ordinary border/artwork preview or changes the exact
frame of its prediction. Compatible
tip registration is used when available; projection outside the circle centers
remains labeled extrapolation. Before tip acceptance, the machine-camera
cap map is explicitly approximate: unknown tip offset and extrapolation remain
visible qualifications. Same-plane paper replacement and ordinary navigation retain
compatible guides; machine geometry/coordinates, tool/contact profile, plane and
optical dependencies still apply.

Before accepted tip calibration, **Accept Sheet Placement** records a separate
session-local operator assertion against that displayed guide. It binds the current
sheet/contact plane, tool, exact displayed frame, optical context, camera-map
revision and projected region/geometry. It never supplies accepted tip calibration,
calibrated paper coverage, drawing readiness or replay permission. With compatible
tip registration, **Sheet Covers Target** keeps the calibrated coverage contract.
Button availability and refusal explanations reflect current admission; stale
context is refused. New-sheet recording clears previous-sheet assertions and
coverage while retaining compatible calibration.

## Attempts, dependencies, reset, and simulation

Every repeatable exercise has an immutable attempt identity, typed disposition,
accepted artifact slot, and explicit dependencies.

Redo stages a replacement. Only a successful atomic commit changes the accepted
slot and invalidates named transitive dependents. Failure, refusal,
cancellation, or ambiguity preserves the prior accepted artifact and its
dependents. Record Another Attempt adds only compatible successful evidence.

The dependency spine is:

```text
four Boundary aggregates -> estimated center -> center arrival
-> five-cap MachineCameraRegistration
-> four ToolContactObservation revisions -> TipCameraRegistration
-> closed Drawing Border plan + local pre-frame baseline
-> Drawing Border execution + post-frame -> planned ink observation -> residual -> comparison
```

Reset From This Step is a deliberate chronological rewind, distinct from causal
Redo. It previews the exact suffix and rejects a stale summary. Reset All
Learning is the stable destructive command in the Learning Path menu. It first
cancels and settles any current Learning-owned operation through that operation's
typed owner, then atomically clears the current source's complete Learning Path
and saved accepted checkpoint and returns progression to 1.1 Identify and
Calibrate the Pen.
Settling camera calibration for reset cancels only its current operation and
keeps runtime admission reusable; only application shutdown closes camera-
calibration admission permanently. A reset must therefore never leave a green
camera action whose runtime can only return cancellation.
The Learning menu exposes **Reset Selected Step…** whenever the selected suffix
contains accepted or transient state, including an unaccepted completed circle
batch awaiting clicks. Its disclosure includes calibration marks. Controls belong
to the selected exercise; a distinct active owner's Stop remains visible. Saved
position revalidation does not hide a completed exercise's Redo.

A scoped suffix reset that retains accepted Pen Learning also retains the exact
compatible cap-appearance selection and reference frame in the surviving accepted
checkpoint. Compatibility checks include tool, camera mount/reframing and available
current optical/source/frame-format context. The prefix does not borrow a newly
captured frame or depend on a legacy appearance preference to survive reload.
Resetting Pen itself clears that appearance and package authority.

For camera calibration, Redo and Restart explicitly prepare the existing owner for
a fresh proposal while retaining the previous accepted map as fallback. Preparation
starts no acquisition or movement. An off-center attempt first offers **Return
Pen Up to Accepted Center**; once centered, **Run Five-Position Camera Calibration**
starts the acquisition and sample travel.
Cancel/Stop settle that owner and discard unaccepted proposal/reference/failure
state. Restart cannot revive an abandoned Accept/Reject proposal. Failed or rejected
replacement preserves accepted calibration; successful Accept installs the reviewed
replacement through the existing dependency commit. Scoped reset deliberately
invalidates the disclosed suffix, and shutdown cannot be reopened by preparation.

Selecting another exercise shows only that exercise's instructions and controls.
An unavailable future exercise cannot borrow the current exercise's buttons. An
active owner's required Stop remains in a separate, explicitly named exercise row.
Review navigation neither starts work nor changes the active owner.

A settled Boundary cancellation or refusal retains its historical diagnosis but
uses the Boundary owner's current admission assessment for explicit retry.
Repairing a transient prerequisite can therefore re-enable the next side or center
attempt without discarding accepted sides. A settled refused/cancelled first-side
attempt is sufficient for selected-step reset even when no side was accepted.
Pending publication/reset and active operations retain their exact
recovery/cancellation controls. An owner-issued center-arrival retry after a
settled position miss remains center-only and subject to current physical-position
and ambiguity admission. Ambiguous side terminals and shutdown do not become
ordinary retry actions. No transition retries motion automatically.

For four-circle tip-calibration recovery, Cancel and Stop settle the existing owner
and clear transient selection and proposal state. Restart/Redo prepare a new
attempt explicitly; none starts marks automatically. A failed replacement retains the prior accepted calibration where
the replacement contract applies. Scoped reset deliberately invalidates only its
selected suffix. Completed and possibly contacted circle locations remain excluded
on the same sheet after cancellation/reset. New-sheet recording clears current-sheet
restrictions without erasing earlier execution history. Reusable cancellation and
paper recovery never reopen terminal shutdown admission.

The reset does not admit new motion, change the pen merely to reset state, erase
physical ink, disconnect the controller, revoke Motion authorization, or change
the selected camera. LIVE and SIMULATED authority reset independently.

LIVE and SIMULATED Learning facts are independently indexed by the active
source in `PlotterApplicationState.environmentStates`; the deleted generic
`LearningSessionState` owns nothing. Named feature runtimes retain their own
source-indexed state/effect/Stop authority. A source switch never copies one
environment's accepted Learning facts into the other. Entering SIMULATED
creates fresh nonphysical Learning state; leaving it selects unchanged LIVE
facts, and later re-entry starts another fresh SIMULATED state.

SIMULATED uses the same public action seams and dependency graph with causal
frames, persistent black ink, and a real nonzero cap-to-tip truth. It has no
capability to load, save, or clear LIVE durable machine or tip checkpoints. It
cannot invoke physical `MachineActions`, satisfy physical artifacts, or become
observed physical ink evidence.

`PlotterCausalSimulatorEffectAdapter` is the sole effect-capable SIMULATED
environment boundary. Where a semantic package exists it uses the shared
`PlotterIntent`, `PlotterEffect`, and `PlotterEffectResult` grammar; later
workflow commands use `admitRetainedWorkflowBoundary`,
`admitRetainedWorkflowDrawing`, `admitRetainedWorkflowTravel`, or
`executeRetainedWorkflowPen`, carry an explicit retained owner, return nil
`effectResult`, and cannot fabricate typed episode attribution or a plan
revision. `admitManualJog` remains the typed episode-attributed path. One
immutable raw simulator operation ID owns admission, natural execution,
original-owner waiting, and the first Stop, cancel, or shutdown settlement.

Manual and retained Pen ingress participates in that same adapter occupancy.
While a predecessor is reserved, Pen ingress refuses with
`.operationAlreadyActive(predecessor.id)` before lower Pen mutation; retained
attribution returns nil `effectResult`, and lower Pen/truth remains unchanged.
When admission is free, package-only
`SimulatedLearningRuntime.setPenPoseWithCausalTruth` returns the admitted Pen
mutation response and complete causal truth from one lower-runtime actor turn.
The adapter cannot combine a Pen result with a later, separately sampled plant,
Pen, ink, or frame state.

The active adapter owner remains reserved after lower-runtime settlement until
one atomic terminal publication binds the exact operation ID, disposition,
observation, typed result when applicable, final MPos, completed Boundary
count, and immutable plant/Pen/paper/ink/camera/frame truth snapshot. A
successor refuses until that bundle is cached and cannot contaminate the
predecessor snapshot. A settled ID is idempotent only for its own result and
cannot stop a successor. The package-only deterministic terminal-publication
gate can hold that exact boundary for tests but cannot choose admission,
settlement, truth, or effect authority.

Simulator command attribution, plant MPos and Pen pose, paper identity and ink,
camera configuration/viewport/frame publication, Vision measurement, and
evidence classification are separate truth layers. Simulator frames are
causal observations, not Vision measurements; only `VisionWorker` may derive a
measurement. Every simulator observation and typed result has `.simulated`
provenance, `physicalEvidenceClaimed` is false, and every surface remains
`SIMULATED — NOT PHYSICAL EVIDENCE`.

`SimulatedLearningRuntime` owns the nonphysical plant, Pen, paper/ink, camera,
fault, and raw settlement state below that boundary. It exposes no public
`beginManualJog`, `beginBoundary`, or `beginDrawing` authority; its sole raw
operation admission is package-scoped to the production adapter. Execution
pacing can change future suspension policy for deterministic tests but cannot
admit, Stop, cancel, settle, or reattribute an effect.

## Active coverage experiments and residual candidates

The Active Learning panel exposes **Prepare Coverage Experiment**, **Next Experiment Trial**,
and **Leave Experiment** through the existing draft intent owner. Preparing or
selecting a trial creates an immutable program and preview only. The operator
reviews and runs each line through the existing Run/Stop owner, reviews its
terminal, and uses New Drawing before selecting the next trial. Automatic batch
execution is not implemented. The former speculative online-learning and
model-mismatch simulator code remains absent.

The versioned design reserves 32 training lines and 16 holdout lines across four
quadrants and X+, X−, Y+, Y− before any result exists. Lines occupy distinct
cells within the intersection of the accepted Drawing Boundary and tip-map
applicability, inset by 2 mm. The design needs at least 72 × 54 mm after the inset;
planned lines are 4–12 mm long with at least 5 mm separation. A clear sheet is an
operator prerequisite. Known ordinary-drawing ink or another coverage experiment
on the same paper identity prevents a fresh experiment on that sheet. Archive
availability is required before LIVE preparation. Geometry, placement, and roles
are sealed while the experiment is selected. Selection balances uncovered
region/direction pairs, spatial separation, and estimated mean uncertainty;
results cannot change the split or create extra locations.

The existing program source provenance carries the complete experiment definition
and trial index into the checksummed drawing archive. Preparing again reconstructs
the same experiment from that archive. There is no second dataset, recorder, or
model-acceptance authority. Failed, ambiguous, possible-ink, cancelled, incomplete,
wrong-role, duplicate, stale-provenance, or geometrically mismatched trials halt
selection and remain diagnostic records. Recorded locations are never proposed
for another run. A changed map, tool, machine, camera semantic identity, region,
or paper invalidates the experiment. A holdout observed before all 32 training
trials is a protocol violation, not fitting data.

The first candidate estimates **mean cross-track** machine-space error only.
Horizontal lines measure Y error; vertical lines measure X error. The signed
centreline is interpolated across the central 60% of each line. Each line supplies
one equally weighted measurement; image pixels are not independent trials.
Separate X/Y least-squares fits estimate an intercept, normalized X/Y spatial
slopes, and a signed travel-direction term. Rank-deficient fits refuse. The sum
of absolute coefficients bounds predictions to 2 mm throughout the declared
rectangle. This model does not identify along-track backlash or validate corners,
curves, or speed-dependent behaviour.

All training must complete before reserved holdouts are selected. The candidate
then stays fixed. The predeclared comparison requires at least 0.05 mm and 10%
improvement in held-out trial-mean RMS, with no regression in any quadrant,
direction, or quadrant/direction pair; 1e-9 mm absorbs arithmetic residue only.
Training error, fit standard error, held-out error, applicability, and each group
comparison are shown separately. These are prediction comparisons on ink executed
with the affine prior, not proof of corrected physical execution. A failed or
inconclusive comparison leaves the prior current. Even a passing comparison does
not apply coefficients or emit Adaptive drawing ready.

Model candidates are diagnostic until explicitly accepted against reserved
physical observations. Fast state and slow parameters remain separate. Slow
model changes require identifiability, candidate-versus-prior comparison,
whole-stroke holdouts, applicability bounds, and improved held-out performance.
No model changes during a Pen Down stroke or chooses hidden motion.

## Input, output, and launch

Buttons and contextual Voice responses submit the same current projected
requests for choices, progression, Cancel, and Stop. One application-owned Voice
switch controls both output and input: off means no talking and no listening;
on enables both. Output starts disabled before the first workflow request. Turning
off invalidates recognition immediately, closes speech admission, cancels queued
and active speech and joins its exact requests. Re-enabling never replays cancelled
cues. Native view reconstruction does not reset the switch or create another
controller. Voice is opt-in and offers short replies for unique current actions: Start for the offered motion or
exercise, Confirmed for affirmative observation or acceptance, Cancel for ending
the attempt, and Stop for active motion. No remains a negative observation;
Reject remains an explicit proposal rejection. Ambiguous or unavailable aliases
cannot select an action. The Voice view displays the current replies, and spoken
prompts and retry prompts name those replies rather than requiring long button
labels. Full button labels and contextual yes/no remain accepted.

Stop dispatches the first matching partial through the current typed request
sink before microphone teardown, without waiting for a final transcript or a
silence timer. Duplicate partial/final Stop callbacks cannot submit again while
that Stop is pending. Spoken Boundary Start suppresses advisory playback before motion
admission and retains recognition into the Stop-only phase; an accumulated
"Start Stop" transcript consumes Start once and dispatches the remaining Stop.
Unrelated speech during motion advances only the consumed transcript prefix
after 900 ms of unchanged recognition, using recognition-ingress timestamps so
UI scheduling cannot erase the utterance boundary. The microphone stays open. A normally
ended recognition request reopens immediately; service errors retry after 500 ms.
Recognized events cannot be evicted by microphone-meter events.

During a Pen phase whose only current action is the exact Pen Stop, enabled Voice
keeps the raise/lower advisory cue audible and accepts only that Stop during
playback. Repeat and affirmative input cannot consume the cue as an answer. This
exception does not authorize physical confirmation or change finite Pen settlement.
Boundary movement keeps its existing uninterrupted Stop-listening priority.
Outside that Pen Stop exception, microphone input is suspended during speech
playback, and stale recognition callbacks cannot answer a successor question. Exact short replies
endpoint after 350 ms of unchanged recognition; other responses use 900 ms. The
current prompt can be repeated. These are application timing rules, not a bound
on Apple's recognition latency or mechanical stopping time. Microphone level and
recognized text stay local to the Voice view. Apple Speech
uses on-device recognition when supported and may otherwise use Apple's service;
macOS requests microphone and speech permissions when Voice is enabled. No audio
recording is retained. Speech remains advisory and failure leaves buttons usable.

Enabled affirmative transitions are green, enabled negative/Cancel/Stop
transitions are red, enabled neutral actions are medium gray, and disabled
actions are dark gray and noninteractive. Disabled appearance and hit testing
consume the same Boolean fact. Passive status and required values are content,
not disabled-button stand-ins. Connect/Disconnect title, color, help, and lower
dispatch derive from one semantic connection action: every Connect is green and
every Disconnect is red, including open connecting/probing states that have not
yet established a valid session. Enable Motion is green only when it is actually
admissible; an unavailable Enable Motion remains gray and exposes its blocker as
visible status as well as help text.

Physical work uses the signed bundle and single-instance launcher. The launcher
may activate the exact existing bundle or launch it through LaunchServices. It
must refuse wrong-path or competing raw processes without terminating them.
