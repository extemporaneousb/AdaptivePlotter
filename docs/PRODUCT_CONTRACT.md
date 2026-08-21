# AdaptivePlotter Product Contract

Status: current product authority

This document owns durable product semantics, authority, safety, evidence, and
artifact applicability. The operating sequence belongs to
[Discovery and Observed-Trial Protocol](DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md),
package ownership to [Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md),
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
- sparse operator-selected contact evidence and an atomic software-committed tip map;
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
the cap dependency that made the armature unavailable. Suspension says that
exclusive calibration Vision owns the exact frame while the selection remains
On. An available armature says it was inferred from the cap and not independently
segmented. Before Pen Interaction has accepted a LIVE pen-cap appearance, the
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
The implemented curriculum ends at the single visible **4.1 Run Predicted
Isolated Line Trial** exercise. Its six phases are runtime activity, not six
operator approvals or selectable Learning Path rows. Its exact comparison
remains reviewable after completion. Drawing Studio is a direct workbench
capability unlocked by that attributable validation; it is not another
Learning Path row and does not imply adaptive-model readiness.

Every accepted LIVE exercise is also a durable prefix checkpoint. Restart does
not reopen accepted Pen Interaction, Boundary, Stage 3.3, Stage 3.4, or the
attributable Stage 4 result merely because process-local owners disappeared.
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

After current 3.2 and before Stage 4 there are exactly two exercises:

- **3.3 Calibrate Camera and Visible Cap**;
- **3.4 Calibrate Pen Contact from Sparse Marks**.

Navigator selection is presentation-only. Presentation zoom, pan, and fitted
learned bounds do not change exact pixels, frame provenance, artifact validity,
or completion state. Explicitly locking the current viewport copies its
camera-pixel rectangle into the generic scene-analysis policy; the preceding
presentation operations remain non-evidence. Entering or leaving Learning and
compatible presentation-context revisions preserve the exact effective visible
camera-pixel rectangle, not merely the numeric zoom and pan values. This
continuity holds through Stage 3.3 proposal review; acceptance publishes learned
fitted bounds as a presentation target but never auto-focuses the viewport or
rewrites a locked analysis region. A camera source/configuration change resets
the viewport. Explicit operator Full, Fit, zoom, and pan actions may replace it.
Stage 3.4 never changes zoom, pan, fitted region, preferred zoom, or viewport
focus automatically.

Before accepted tip authority exists, the UI states **Tip not calibrated**.
Stage 3.4 displays all clicks on its one frozen exact frame and reports their
count. Diagnostic residual and uncertainty presentation has no authority over
model construction, proposal creation, or acceptance.

Pen-cap appearance is learned only through the first **Identify Pen Cap** action
of Pen Interaction; there is no editable color picker or parallel color-setting
surface. Before any Pen Interaction question or pen request, the operator clicks
the visibly colored cap body, not the tip, on one frozen exact frame. The app
maps the click to exact camera pixels and takes a clipped 9 x 9 neighborhood.
It rejects stale provenance, unsupported pixel format, insufficient chromatic
pixels, and a gray, white, or dark representative color with a concrete reason.

An accepted selection persists median RGB color together with the click point,
frame ID and content hash, source, camera configuration, dimensions, pixel
format, usable and total sample counts, and algorithm revision. It therefore
supports arbitrary visibly colored caps, including blue, rather than assuming
green. The learned color feeds both feature-selective generic scene analysis
and every Stage 3.3 exact-frame inspection. One five-sample proposal accepts
only cap-anchor evidence carrying the same appearance-specific estimator
revision. The click is an operator assertion and recognition input; it does not
by itself prove cap segmentation, calibration accuracy, physical pen state, or
ink.

### 3.1 Pen Interaction

Pen Interaction retains its existing exercise identity and attempt history. Its
first action is **Identify Pen Cap**, followed by the existing Up → Down → Up
sequence. Identification must be accepted before the first question or any pen
actuation request. A stale or rejected click keeps identification pending and
performs no machine action.

The Up and Down steps each expose a servo-value slider, displaying the
corresponding current setting. A fresh session is seeded at `S40` and `S760`; a
repeated attempt starts from the values already current. Moving a slider
commands its displayed value in the current step; **Next** remains available
and accepts that value for the corresponding current setting.

The accepted Up and Down values are mutable operating settings, not a promise
of one constant actuator position across the run. Repeating Pen Interaction at
a different machine position may accept different values. The existing attempt
and actuation evidence retains each actual value and the available MPos,
controller outcome, and timestamp so later learning can observe positional
variation. Refusal, ambiguity, or unavailable evidence remains explicit and
does not disable **Next**. No separate servo-
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

## Stage 3.3 machine-to-cap authority

Stage 3.3 derives a calibration rectangle inside the accepted Boundary envelope
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

## Stage 3.4 contact authority

One supervised **Draw Five 2 mm Circles** action owns one exercise attempt and
one stoppable operation. One mark is at the accepted Boundary envelope's
geometric center. The four outer mark centers are its maximum drawable corners:
`minX + 2 mm`, `minY + 2 mm`, `maxX − 2 mm`, and `maxY − 2 mm`. The full 2 mm-
radius paths therefore remain within the accepted Boundary envelope while the
outer centers bound essentially the complete drawable region. The retained
`C`, `X−`, `Y+`, `X+`, `Y−` values are canonical evidence-slot identities, not
fixed axis-only physical offsets. Stage 3.3 retains its separate existing ±24 mm
camera-calibration spacing and holdout authority. Operator-visible motion text
names the actual minimum/maximum-axis corner rather than the retained slot value.

At every Stage 3.4 position the operation travels and settles Pen Up, retains
that circle's pre-mark exact frame, cap, controller, and settled-position
evidence, moves Pen Up to the circle start, lowers and settles using the current
Pen Interaction profile, and draws one closed 2 mm-radius circle as 16 finite
typed chords capped at 100 mm/min. It then raises and settles Pen Up before any
travel to the next circle. The five circles therefore contain exactly 80 circle
chords and no connecting Pen-Down stroke. The accepted calibrated drawable-
region overlay is the bounding box through the four outer circle centers; the
plotter does not spend additional Pen-Down motion drawing a physical perimeter.
Each observation retains its own physical operation evidence. Command completion
is not proof of physical pressure, contact, or observed ink.

After the fifth circle only, the operation returns Pen Up to the outer
rectangle's geometric center, requires existing Pen-Up, Idle, and settlement
evidence, captures one newer exact frame, and revalidates current camera/cap
applicability once. All five observations share that final frozen reveal frame.
Acceptance installs the rectangle through the four outer circle centers as the
`TipCameraRegistration` applicability rectangle and Drawing Studio drawable
region. Stage 3.4 never changes zoom, pan, preferred zoom, or viewport focus
automatically. The boundary-corner estimator has a new revision: a previously
accepted fixed-offset registration remains truthful only within its recorded
smaller applicability rectangle and is never widened or reinterpreted as corner
evidence without a fresh physical batch.

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

Every Stage 3.4 comparison of continuous machine-space values uses the shared
named nonzero position tolerance, including intended targets, commanded mark
centers, controller-settled positions, applicability bounds, and tip-projection
queries. Exact equality remains for discrete identity and immutable provenance;
it is never an admission gate for a continuous physical or computed numeric
value.

The click is an assertion, not a seed for an automatic detector. Click order
does not identify a calibration position. After click five, the app projects
the five known machine positions through current `MachineCameraRegistration`,
centers projected and clicked sets to remove their unknown common cap-to-tip
translation, evaluates all 5! one-to-one assignments, and selects the minimum
total squared pixel distance. Exact numerical ties resolve by canonical
calibration-position order. No distance or ambiguity threshold may reject or
block that association. The earlier cap-map residual at each corner is retained
as diagnostic evidence, not used as an admission gate outside the Stage 3.3
bootstrap rectangle. **Undo Last Click** or **Clear Clicks on This Frame**
changes only clicks on the same frame and performs no motion, ink, redraw,
capture, zoom, or pan. The fifth click atomically creates the five accepted
observations and constructs a reviewable tip-map proposal. The exact frozen
frame, click markers, proposed map, model form, residuals, RMS, covariance, and
uncertainty remain visible. **Accept Tip Map** commits the registration.
**Reject Tip Map**, **Undo Last Click**, or **Clear Clicks on This Frame**
returns to same-frame selection without motion, ink, redraw, or capture. A
failed atomic acceptance exposes a commit retry.

Model construction first fits one direct affine machine-to-tip map from all
five observations. Constant camera-pixel correction on the accepted cap map is
used only when affine construction itself throws. Stage 3.4 has no holdouts,
model-quality thresholds, residual thresholds, confidence thresholds, or
numerical failure route. All-five residuals, RMS, covariance, and uncertainty
are diagnostic evidence only; their magnitude cannot reject either model or
block progression. Numerical fitting cannot request paper replacement or route
to **No Automatic Redraw**. Only explicit acceptance creates
`TipCameraRegistration` and makes Stage 4 current. The next operator-owned
physical authorization is **Go** for the observed-line trial.

Paper replacement is recorded only when paper was actually replaced or through
the existing possible-ink recovery. It is never a numerical model outcome.

`TipCameraRegistration` maps machine coordinates directly to paper-contact
pixels. It retains the affine transform, model form, covariance/uncertainty,
diagnostic residuals, applicability rectangle, five observation hashes and
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
- capture restart with proven identical semantic optics: require explicit
  revalidation;
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
  plane identity and invalidate tip authority before a new Stage 3.4 batch;
- LIVE/SIMULATED source change: invalidate cross-source optical authority;
- raw observations: retain as immutable history under every change.

`AcceptedLearningPathCheckpoint` is the one atomic durable accepted-prefix
envelope. It contains optional accepted Pen Interaction, machine-only Boundary
and center artifacts, Stage 3.3 machine/cap registration, the accepted Stage 3.4
tip checkpoint, and a Stage 4 evidence-record reference. Production migrates
the former machine-only and tip-only files into this envelope and deletes the
legacy files after successful save.

Loading restores accepted values only. It cannot restore Motion authorization,
current Pen pose, workflow state, operation ownership, a Stop capability, a
pending command, a camera frame, or a continuation. Fresh passive controller
identity evidence restores the learned machine envelope, but reported MPos
distance is diagnostic rather than physical-pose proof. Coordinate-dependent
Learning and Drawing remain blocked until a fresh exact cap frame revalidates
pose; manual jog and manual Pen controls remain independent under Motion
authorization and controller-native admission. Under unchanged machine geometry
and semantic camera-mount/optical identity, a displaced cap may establish one
known coordinate translation; accepted boundaries, the machine/cap fit, and the
tip fit are rebased into one new coordinate-frame revision. This does not
estimate rotation or scale. Unknown camera, geometry, or assembly change
invalidates instead. Same-paper restoration performs no contact mark.

## Stage 4 dependency boundary

Observed Drawing Trials require accepted Boundary/coordinate evidence and one
exact current `TipCameraRegistration` revision.

Stage 4 chooses a 5 mm path inside the applicability rectangle that clears all
retained 2 mm-radius calibration circles by the declared ink-clearance margin.
If no such path exists, it blocks and requires a larger clean calibration area;
it never crosses old circle ink and weakens attribution. It projects its
intended local path through the tip registration. It owns
its own local pre-line baseline, Pen-Up reveal MPos, line-start travel, one
drawing owner, return to the same reveal pose, strictly newer post-line frame,
and generic black/new-ink observation. Its request and result cite the exact tip
revision.

One **Go** starts all normal Stage 4 phases. The app chooses the first clear
signed-axis plan deterministically, renders the model-predicted paper-contact
line in cyan on the live current frame before motion, captures the baseline,
moves and draws, returns to reveal, runs isolated-ink Vision, and records the
normal typed comparison without further approval. Motion retains one
capability-bound **Stop**. A refusal, ambiguity, possible-ink outcome, rejected
Vision result, or failed atomic commit stops at a truthful recovery state and
never authorizes redraw.

Intended geometry, observed ink, and residuals are required contextual Stage 4
evidence and have no global visibility toggles. An attributable observed line
is retained in the append-only drawing-run archive as an evaluation holdout and
may be reviewed after the Learning Path finishes. It cannot silently change an
accepted calibration. Possible ink or
ambiguous motion never triggers automatic redraw or resend.

Stage 3.4 means **map ready** within its recorded applicability and semantic
identities. One successful Stage 4.1 trial means **one attributable validation
complete**. Neither state means a generally trained adaptive drawing model;
that claim requires the repeated coverage, reserved holdouts, candidate/prior
comparison, shape evaluation, and typed readiness work defined in the Roadmap.

## Direct Drawing Studio boundary

One attributable Stage 4.1 validation establishes **Interactive learning
complete · one validation**. It permits direct bounded drawing with the accepted
map; it does not establish **Adaptive drawing ready**. Paper readiness remains a
separate operator assertion and is never inferred from the tip map.

The built-in catalog is a set of deterministic `DrawingProgram` producers, not
precomputed machine commands. Placement is one immutable field-to-machine
transform. `DrawingPlanner` clips nothing: every planned stroke must fit inside
the effective `DrawableMachineRegion`, or planning is refused. The resulting
`ExecutionPlanRevision` is content-addressed and binds program, placement,
region, calibration/model provenance, ordered strokes, and one checkpoint per
logical stroke. The video preview projects that exact plan through the current
tip registration on one matching frame.

Run eligibility additionally requires LIVE mode, a connected authorized idle
controller with Pen Up, current paper-coverage evidence, and the exact reviewed
plan. `RunInterpreter` is the only execution owner for all Pen-Up travel, pen
actuation, finite segments, Stop, and checkpoints. Controller completion is not
ink verification. After clean completion, the camera observer compares a
strictly newer same-pose frame against the local baseline and associates new ink
with the planned polylines. Exact-frame intended, observed, and residual
geometry remains reviewable. Refusal, cancellation, ambiguity, possible ink,
Vision rejection, or evidence-store failure cannot authorize resend or redraw.

Every immutable `DrawingRunEvidenceRecord` fixes its role before the outcome is
known and cites request/execution frontiers, program/placement/plan hashes,
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
-> five ToolContactObservation revisions -> TipCameraRegistration
-> local line plan + local pre-line baseline
-> line execution + post-line frame -> ink observation -> residual -> comparison
```

Reset From This Step is a deliberate chronological rewind, distinct from causal
Redo. It previews the exact suffix and rejects a stale summary. Reset All
Learning is the stable destructive command in the Learning Path menu. It first
cancels and settles any current Learning-owned operation through that operation's
typed owner, then atomically clears the current source's complete Learning Path
and saved accepted checkpoint and returns progression to 3.1 Pen Interaction.
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
