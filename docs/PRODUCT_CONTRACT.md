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
plotter with one camera. It owns the short controller-camera-draw-observe loop
directly.

In scope:

- one persistent controller owner and one persistent camera owner;
- typed controller requests and typed observations;
- explicit operator-owned alarm inspection and alarm-lock clearing;
- one camera-first operator workbench;
- current-session discovery and observed drawing trials;
- sparse operator-selected contact evidence and an atomic accepted pen-tip calibration;
- one attributable observed drawing trial;
- direct placement, preview, execution, and observation of bounded vector drawing programs;
- append-only drawing-run evidence with predeclared ordinary/training/holdout roles;
- causal simulator parity without physical authority.

Out of scope:

- a web server, Python bridge, remote backend, or second product process;
- arbitrary G-code or natural-language-to-motion translation;
- homing, controller reset, or firmware/configuration writes;
- entered bounds treated as measured workspace authority;
- automatic resend, resume, retap, continuation, or redraw after ambiguity;
- Learning Path completion or model confidence as a general motion gate;
- automatic trial selection, online model promotion, or model-mismatch policy
  in the current curriculum;
- simulator state as physical evidence.

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
preview when the final matching hold settles.

The operator may lock the current presentation viewport as a generic scene-
analysis region. The lock constrains which camera pixels requested pen-cap
analysis may scan; an armature-envelope request expands its declared dependency
to pen-cap analysis. Full-frame lock is canonicalized to unlocked/default
analysis. The region does not crop or mutate the stamped frame, change exact-
frame identity, alter whole-frame cap-size acceptance thresholds, or constrain
specialized workflow measurements with their own typed regions. Changing camera
source or configuration clears the lock.

Exactly two persistent global scene-overlay choices exist: **Pen cap** and
**Armature envelope**. The envelope is derived from the cap and must be labeled
as inferred, not independently segmented. Preference, requested computation,
typed run status, and exact-frame geometry are separate state. Only an operator
action or persistence load may mutate preference. Scene, workflow, and simulator
result channels have separate owners; one producer cannot erase another's
result. Pure presentation composition renders geometry only when frame identity,
camera configuration, and source all match. While a newer frame is analyzing,
the last completed geometry remains renderable only over its still-displayed
exact source frame; result completion replaces the displayed-frame/geometry pair
atomically. Analysis activity alone never removes matching completed geometry
or replaces its completed typed status with a transient one.

The visible run-state vocabulary is Off, Waiting, Analyzing, Found/Available,
Not found/Unavailable, Candidate rejected, Ambiguous, Failed, Suspended, and
Stale. Reasons must name zero threshold pixels, rejected component counts and
leading rejection reason, ambiguous candidate sizes, source/frame mismatch, or
the cap dependency that made the armature unavailable. Suspension names the
typed exact-workflow Vision owner of the exact frame while the selection remains
On; supervised travel alone is not a Vision owner or preview hold. An available
armature says it was inferred from the cap and not independently segmented.
Before Exercise 1.1 has accepted a LIVE pen-cap appearance, the
Pen cap and Armature envelope layers report Unavailable without changing their
persisted operator selections or rendering LIVE geometry.

`VisionWorker` and analysis pipelines produce measurements and diagnostics.
They do not decide controller eligibility, machine direction, operator click,
or artifact acceptance.

`OperatorWorkspace` is the single observable app owner and typed-intent router.
It copies current facts into an immutable values-only snapshot;
`LearningPathProjector` purely derives Learning Path rows, review detail,
actions, activity, subsystem status, and reset presentation. Neither projection
nor navigator selection can replace controller, camera, persistence, or
evidence authority.

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

For every migrated effect-bearing or domain-authority-changing action:

- one typed semantic ingress evaluates current state and versioned facts;
- copied presentation availability is never authorization;
- the reducer is the sole producer of typed external effects;
- the runtime owns exact effect identity, lane, cancellation, and terminal
  disposition, while existing device owners repeat fresh physical safety;
- the superseded action, state, guard, task, effect, and fixture path is removed
  in the same landing.

Observability is required product behavior. Every refused action names its typed
failed requirement, authoritative owner, compared revisions, and exact remedy.
Every active effect exposes its episode/action/effect identity, lane, owner,
phase, start and last attributable progress times, current wait, cancellation
state, and terminal disposition. Progress must be an attributable event rather
than a fabricated heartbeat. Every reachable nonterminal state provides an
admissible action, an explicitly owned wait/progress state, an exact remedy, or
owner-bound Stop/cancel.

Runtime and UI projection revisions must be independently visible so a stale or
starved UI can be distinguished from a controller, camera, Vision, persistence,
or workflow wait. The episode journal, controller transcript, camera lifecycle,
and structured diagnostics remain inspectable outside `MainActor`, and the
operator can export one bounded incident package. Recording failure is visible
but cannot authorize work, manufacture evidence, alter physical safety, or delay
Stop/shutdown.

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
| five-position machine/cap result | **camera calibration** |
| four-corner machine/contact-pixel result | **pen-tip calibration** |
| closed four-edge plan and ink comparison | **drawing-frame validation** |
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
the Frame** exercise. Its six phases are runtime activity, not six
operator approvals or selectable Learning Path rows. Its exact comparison
remains reviewable after completion. Drawing Studio is a direct workbench
capability unlocked by that attributable validation; it is not another
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
operator-authored manual jog or manual Pen controls. Those direct controls are
admitted by the Motion toggle plus controller-native connection, alarm,
readiness, safety, and command-serialization requirements; Learning progression
is not an additional manual-motion authorization layer.

The operator may turn Learning off when no Learning attempt owns work. This
hides Learning navigation and prevents new Learning actions without clearing
accepted artifacts, disconnecting the controller, disabling Motion, stopping
the camera, or blocking direct manual controls. An active Learning attempt must
finish or use its existing Cancel/Stop contract before Learning can be turned
off.

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
Exercise 1.4 displays all clicks on its one frozen exact frame and reports their
count. Diagnostic residual and uncertainty presentation has no authority over
model construction, proposal creation, or acceptance.

Pen-cap appearance is learned only through the first **Identify Pen Cap** action
of Exercise 1.1; there is no editable color picker or parallel color-setting
surface. Before any pen-position question or pen request, the operator clicks
the visibly colored cap body, not the tip, on one frozen exact frame. The app
maps the click to exact camera pixels and takes a clipped 9 x 9 neighborhood.
It rejects stale provenance, unsupported pixel format, insufficient chromatic
pixels, and a gray, white, or dark representative color with a concrete reason.

An accepted selection persists median RGB color together with the click point,
frame ID and content hash, source, camera configuration, dimensions, pixel
format, usable and total sample counts, and algorithm revision. It therefore
supports arbitrary visibly colored caps, including blue, rather than assuming
green. The learned color feeds both feature-selective generic scene analysis
and every Exercise 1.3 exact-frame inspection. One five-sample proposal accepts
only cap-anchor evidence carrying the same appearance-specific estimator
revision. The click is an operator assertion and recognition input; it does not
by itself prove cap segmentation, calibration accuracy, physical pen state, or
ink.

### 1.1 Identify and Calibrate the Pen

Exercise 1.1 retains its existing exercise identity and attempt history. Its
first action is **Identify Pen Cap**, followed by the existing Up → Down → Up
sequence. Identification must be accepted before the first question or any pen
actuation request. A stale or rejected click keeps identification pending and
performs no machine action.

**Identify Pen Cap** requires a current exact frame but does not require a
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
commands its displayed value in the current step; **Confirm Pen Up** or
**Confirm Pen Down** accepts that value for the corresponding current setting
once current operational dependencies permit the request.

The accepted Up and Down values are mutable operating settings, not a promise
of one constant actuator position across the run. Repeating Exercise 1.1 at
a different machine position may accept different values. The existing attempt
and actuation evidence retains each actual value and the available MPos,
controller outcome, and timestamp so later learning can observe positional
variation. Refusal, ambiguity, unavailable evidence, and any current admission
blocker remain explicit; none creates a separate forward or acceptance step.
No separate servo-
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

The manual direction controls select their typed intent from the current
controller-commanded pen state. Pen Down uses a bounded `DrawingStrokeRequest`
and remains Pen Down after clean completion so consecutive sides can form one
manual shape. Otherwise, including when commanded pen state is unknown, the
operator's bounded request uses an ordinary `RelativeJogRequest`; its evidence
retains that the pen pose was unknown and ink may have been produced. A stopped
manual drawing stroke retains the drawing owner's single typed Pen Up
cancellation result.

After Motion is enabled, manual direction controls do not depend on camera,
Vision, Learning state, Learning Path position, current-camera calibration, or
a visually confirmed pen pose. Their X distance, Y distance, and feed inputs
remain editable and initialize to 50 mm, 50 mm, and 500 mm/min. Existing direct
controller ownership facts still apply; this paragraph adds no optical or
workflow admission condition.

All production requested-pose comparisons use fresh attributable controller
evidence, compatible context, and at most 0.05 mm Euclidean residual. “Exact
pose” names that quantization-aware policy; it does not mean zero mathematical
residual at an unrepresentable stepper position.

The contextual Stop capability names one exact active owner. Repeated or stale
capabilities are inert. While physical movement owns an exercise, its Stop is
the only movement-ending exercise action. Cancel becomes available only after
movement settles.

Boundary side identity is the operator's typed X−, X+, Y−, or Y+ direction plus
settled controller evidence. Boundary uses controller-owned fixed 50 mm renewal
segments at 500 mm/min with no Camera or Vision adviser. Operator Stop, fresh
Idle, and final MPos remain the acceptance authority; camera availability cannot
alter direction, renewal, Stop, or side acceptance.

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
contain one accepted unambiguous cap candidate, and maximum pairwise cap-centroid
spread must be at most 2 px. The newest third exact frame and its measured
centroid, bounds, and confidence are retained without averaging; the preliminary
frame is not accepted cap evidence. SIMULATED causal geometry remains separate
nonphysical evidence and cannot prove live optical stability.

The artifact retains all five exact-frame correspondences, roles, holdout
residuals, uncertainty, applicability rectangle and derivation, semantic optical
identity, machine geometry identity, controller session, coordinate revision,
and estimator revision. It maps machine position to the visible cap landmark.
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
and reveal travel. At every mark it retains the circle's pre-mark exact frame,
cap, controller, and settled-position evidence; lowers and settles using the
current Exercise 1.1 profile; draws one closed 2 mm-radius circle as 16 finite
typed chords capped at 100 mm/min; then raises and settles before any next travel.
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
Acceptance installs the rectangle through the four circle centers as the
`TipCameraRegistration` applicability rectangle and Drawing Studio drawable
region. Exercise 1.4 never changes zoom, pan, preferred zoom, or viewport focus
automatically. During proposal review, the camera view separately labels the
accepted Drawing Boundary projection and renders the proposed inset four-point frame
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
- the 2 mm-radius/16-chord/100 mm/min-capped commanded geometry, actual current
  Down/Up actuation values, and Pen Down/Up outcomes/timestamps;
- tool assembly, contact profile, and paper-plane revisions;
- exact pre-mark frame and cap estimate;
- the shared exact final-reveal frame, settled reveal pose, and cap-map
  revalidation;
- clicked camera point with role `assertedCenter`, pointing uncertainty,
  timestamp, and presentation-transform revision;
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
capture, zoom, or pan. The fourth click atomically creates the four accepted
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
physical authorization is **Draw and Validate Frame**.

Paper replacement is recorded only when paper was actually replaced or through
the existing possible-ink recovery. It is never a numerical model outcome.

`TipCameraRegistration` maps machine coordinates directly to paper-contact
pixels. It retains the affine transform, model form, covariance/uncertainty,
diagnostic residuals, applicability rectangle, four observation hashes and
revisions, semantic applicability identities, capture sessions, accepted
revision, estimator, timestamp, and derivation.

A cap-to-tip difference at one pose is diagnostic only. It is not a durable
camera-independent tool vector because the cap landmark and paper lie in
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
  proven identical semantic optics: retain authority;
- unknown device, source, crop, mirror, orientation, capture zoom, mount,
  lens/focus, or optical change: invalidate;
- known machine-coordinate rebase: rebase intercept and domain;
- unknown origin or machine geometry/steps/direction/kinematics change:
  invalidate;
- tool, holder, armature, cap landmark, nib, contact profile, or remount change:
  invalidate;
- new sheet explicitly on the unchanged support/stock/contact plane: rotate the
  paper instance, clear sheet coverage and ink-specific state, retain tip authority;
- changed support, stock thickness, contact height, or contact plane: rotate the
  plane identity and invalidate tip authority before a new Exercise 1.4 batch;
- LIVE/SIMULATED source change: invalidate cross-source optical authority;
- raw observations: retain as immutable history under every change.

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
the app projects compatible saved frame/tip/cap/drawing geometry onto the
current frame and reports bounded integer shift plus background mean absolute
difference when a compatible saved reference exists. That report is advisory;
it has no threshold and cannot accept or reject the package.

The startup candidate exposes exactly **Use Saved Learning** and **Start New
Learning**. Use Saved Learning atomically rebuilds the process-local dependency
index with the exact stored revisions and installs the accepted values without
motion, Pen-pose restoration, or command replay. Start New Learning applies no
saved value and retains the last complete package until a newer dependency-
complete package can replace it atomically. The operator owns this decision.
Binary replacement, process restart, and capture-session restart perform no cap
capture, click, mark, paper replacement, or Learning Path replay.

An actual controller-coordinate reset, camera move/remount/reframe, tool or
contact-profile change, or paper-contact-plane change is a physical semantic
change, not a software restart. A detectable context or optical mismatch keeps
authority unavailable or invalidates it. A known coordinate translation may be
explicitly recovered and rebased; unknown rotation, scale, geometry, or
assembly change invalidates. Unobservable physical changes require the operator
to declare the relevant reset rather than relying on process lifetime as a
proxy.

## Stage 2 dependency boundary

Drawing Validation requires accepted Drawing Boundary/coordinate evidence and one
exact current `TipCameraRegistration` revision.

Exercise 2.1 constructs one immutable closed polyline through the four accepted
circle centers: minimum/minimum, minimum/maximum, maximum/maximum,
maximum/minimum, and back to minimum/minimum. It therefore has four orthogonal
edges and right-angle turns. It projects that exact plan through the tip
registration. It owns its own local pre-frame baseline, Pen-Up reveal MPos,
frame-start travel, one canonical drawing-plan owner, return to the same reveal
pose, strictly newer post-frame, and generic planned-drawing ink observation.
Its request and result cite the exact tip revision.

One **Draw and Validate Frame** click starts all normal Exercise 2.1 phases. The app chooses the closed frame
plan deterministically, renders the model-predicted paper-contact frame in cyan
on the live current frame before motion, captures the baseline, moves and draws
all four edges, returns to reveal, runs planned-drawing Vision, and records the
normal comparison without further approval. Motion retains one
capability-bound **Stop**. A refusal, ambiguity, possible-ink outcome, rejected
Vision result, or failed atomic commit stops at a truthful recovery state and
never authorizes redraw.

Intended geometry, observed ink, and residuals are required contextual Stage 2
evidence and have no global visibility toggles. An attributable observed frame
is retained in the append-only drawing-run archive as an evaluation holdout and
may be reviewed after the Learning Path finishes. It cannot silently change an
accepted calibration. Possible ink or
ambiguous motion never triggers automatic redraw or resend.

Exercise 1.4 means **pen-tip calibration ready** within its recorded applicability
and semantic identities. One successful Exercise 2.1 run means **one attributable validation
complete**. Neither state means a generally trained adaptive drawing model;
that claim requires the repeated coverage, reserved holdouts, candidate/prior
comparison, shape evaluation, and typed readiness work defined in the Roadmap.

## Direct Drawing Studio boundary

One attributable Exercise 2.1 validation establishes **Drawing validation
complete**. It permits direct bounded drawing with the accepted pen-tip
calibration; it does not establish **Adaptive drawing ready**. Paper readiness
remains a separate operator assertion and is never inferred from that calibration.

The built-in catalog is a set of deterministic `DrawingProgram` producers, not
precomputed machine commands. Placement is one immutable field-to-machine
transform. `DrawingPlanner` clips nothing: every planned stroke must fit inside
the effective `DrawableMachineRegion`, or planning is refused. The resulting
`ExecutionPlanRevision` is content-addressed and binds program, placement,
region, calibration/model provenance, ordered strokes, and one checkpoint per
logical stroke. The video preview projects that exact plan through the current
tip registration on one matching frame.

Run eligibility additionally requires LIVE mode, a connected authorized idle
controller, current paper-coverage evidence, and the exact reviewed plan.
Every travel owner issues an idempotent Pen Up normalization; it does not trust
process-local command knowledge. `RunInterpreter` is the only execution owner for all Pen-Up travel, pen
actuation, finite segments, Stop, and checkpoints. Controller completion is not
ink verification. After clean completion, the camera observer compares a
strictly newer same-pose frame against the local baseline and associates new ink
with the planned polylines. Exact-frame intended, observed, and residual
geometry remains reviewable. Refusal, cancellation, ambiguity, possible ink,
Vision rejection, or evidence-store failure cannot authorize resend or redraw.

Every immutable `DrawingRunEvidenceRecord` fixes its role before the outcome is
known and cites request/execution frontiers, program/placement/plan hashes plus
the complete immutable execution-plan geometry for new records,
tip-calibration and paper provenance, terminal execution disposition, and exact
observation outcome. The checksummed archive is append-only. Records can be
inputs to later training and evaluation; they cannot replay motion, restore a
capability, promote calibration, or accept a model. `DrawingReadinessAssessment`
is a typed schema only until all declared coverage, untouched holdout,
candidate-versus-prior, and shape-holdout requirements have attributable
evidence.

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
-> closed drawing-frame plan + local pre-frame baseline
-> frame execution + post-frame -> planned ink observation -> residual -> comparison
```

Reset From This Step is a deliberate chronological rewind, distinct from causal
Redo. It previews the exact suffix and rejects a stale summary. Reset All
Learning is the stable destructive command in the Learning Path menu. It first
cancels and settles any current Learning-owned operation through that operation's
typed owner, then atomically clears the current source's complete Learning Path
and saved accepted checkpoint and returns progression to 1.1 Identify and
Calibrate the Pen.
The reset does not admit new motion, change the pen merely to reset state, erase
physical ink, disconnect the controller, revoke Motion authorization, or change
the selected camera. LIVE and SIMULATED authority reset independently.

LIVE and SIMULATED learning are independent `LearningSessionState` values
governed by the same state contract and selected by the active source. A source
switch never copies or parks one source inside the other. Entering SIMULATED
creates a fresh nonphysical session; leaving it selects the unchanged LIVE
session, and later re-entry starts another fresh SIMULATED session.

SIMULATED uses the same public action seams and dependency graph with causal
frames, persistent black ink, and a real nonzero cap-to-tip truth. It has no
capability to load, save, or clear LIVE durable machine or tip checkpoints. It
cannot invoke physical `MachineActions`, satisfy physical artifacts, or become
observed physical ink evidence.

## Future adaptive direction

Adaptive Drawing remains unapplied roadmap scope. Candidate fitting, dataset
splits, holdouts, and bounded experiment proposals are not implemented or
selectable in the current application. The former speculative online-learning
and model-mismatch simulator code is intentionally absent.

Model candidates are diagnostic until explicitly accepted against reserved
physical observations. Fast state and slow parameters remain separate. Slow
model changes require identifiability, candidate-versus-prior comparison,
whole-stroke holdouts, applicability bounds, and improved held-out performance.
No model changes during a Pen Down stroke or chooses hidden motion.

## Input, output, and launch

Buttons are authoritative for choices, progression, Cancel, and Stop. Speech is
output-only advisory guidance; failure leaves buttons usable.

Enabled affirmative transitions are green, enabled negative/Cancel/Stop
transitions are red, enabled neutral actions are medium gray, and disabled
actions are dark gray and noninteractive. Disabled appearance and hit testing
consume the same Boolean fact. Passive status and required values are content,
not disabled-button stand-ins.

Physical work uses the signed bundle and single-instance launcher. The launcher
may activate the exact existing bundle or launch it through LaunchServices. It
must refuse wrong-path or competing raw processes without terminating them.
