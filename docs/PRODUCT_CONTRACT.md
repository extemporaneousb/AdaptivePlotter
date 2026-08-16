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
- sparse operator-selected contact evidence and explicit model acceptance;
- one attributable observed drawing trial;
- causal simulator parity without physical authority.

Out of scope:

- a web server, Python bridge, remote backend, or second product process;
- arbitrary G-code or natural-language-to-motion translation;
- homing, controller reset, or firmware/configuration writes;
- entered bounds treated as measured workspace authority;
- automatic resend, resume, retap, continuation, or redraw after ambiguity;
- Learning Path completion or model confidence as a general motion gate;
- selectable Adaptive Drawing, online model learning, or model-mismatch UI in
  the current curriculum;
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

The rendered `visibleRect` and generic-analysis ROI are different facts.
Unlocked zoom and pan affect rendering only; generic scene analysis remains
full-frame. Lock atomically copies the current visible camera-pixel rectangle
into the analysis policy, and the lock fact, displayed rectangle, and backend
consume that same value. Unlock clears only the ROI and preserves view geometry.
The region does not crop or mutate the stamped frame, change exact-frame
identity, alter whole-frame cap-size acceptance thresholds, or constrain
specialized workflow measurements with their own typed regions. A camera source
or configuration replacement clears geometry and lock only; cadence and the two
operator overlay choices persist.

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
`LearningPathProjector` purely derives the tree rows and one compact exercise:
numbered title, actor-tagged script, optional question, typed actions, and
invalidation preview. Activity, subsystem facts, provenance, metrics, and
failures are projected once into Diagnostics. Neither projection nor navigation
selection can replace controller, camera, persistence, or evidence authority.

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
The implemented curriculum ends at **4.6 Compare Intended and Observed
Geometry**. Adaptive Drawing is roadmap-only and has no selectable current row.

The operator may turn Learning off when no Learning attempt owns work. This
hides Learning navigation and prevents new Learning actions without clearing
accepted artifacts, disconnecting the controller, disabling Motion, stopping
the camera, or blocking direct manual controls. An active Learning attempt must
finish or use its existing Cancel/Stop contract before Learning can be turned
off.

After current 3.2 and before Stage 4 there are exactly two exercises:

- **3.3 Calibrate Camera and Visible Cap**;
- **3.4 Calibrate Pen Contact from Sparse Marks**.

Tree selection is presentation-only. Learning steps, fitted learned bounds,
frozen frames, sparse-mark selection, and inspector changes never mutate the
operator's zoom, pan, or locked ROI. A workflow may publish a focus suggestion,
but only an explicit operator action may apply it. A camera source/configuration
replacement resets geometry and lock. These presentation operations remain
non-evidence and never change exact pixels, provenance, artifact validity, or
completion state.

Before accepted tip authority exists, the UI states **Tip not calibrated**.
During each mark selection, the predicted tip point is hidden until the operator
clicks. After the click, the asserted point and uncertainty, predicted point,
and residual are displayed.

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
alter surface-exposure, no-redraw, Stop, or accepted-fallback behavior.

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

The contextual capability names one exact active owner. Repeated, stale, and
losing actions are inert. Active Boundary exposes three actions carrying that
same capability: green **Stop & Accept**, red **Stop**, and red **Cancel**. They
share one mechanical Jog Cancel but not one semantic outcome. Stop & Accept may
commit only after fresh attributable Idle/final MPos passes atomic validation.
Stop records a distinct non-success result and operational final-MPos provenance
but no learning artifact; clean settlement exposes Restart. Cancel abandons the
attempt; clean settlement exposes a new Start. Ambiguity exposes neither and
preserves any prior accepted fallback. Escape invokes red Stop, never acceptance.

Boundary side identity is the operator's typed X−, X+, Y−, or Y+ direction plus
settled controller evidence accepted by Stop & Accept. Boundary uses one bounded
controller request with no Camera or Vision adviser. Natural request completion
is Needs Attention with no side evidence and no automatic renewal. A longer
horizon requires fresh attributable signed remaining-travel authority and
attended stop-latency/overshoot validation; neither is inferred from controller
feed ceilings or nominal travel settings.

Before any LIVE Pen Down, the complete circle geometry and paper-plane identity
must be conservatively reserved in the single surface-exposure ledger and saved
through its checksummed atomic store. A save failure or rejected/corrupt load
blocks contact; absence alone means an empty store. Any ambiguous circle-chord
motion, Pen Down, Pen Up, rejected post-lower drawing admission, or process exit
therefore leaves the reservation applicable across cancel, restart, invalidation,
and relaunch. No automatic retry, resend, retap, redraw, or continuation is
permitted. A wrong click may be replaced only on its same frozen exact frame and
causes no mechanical action. SIMULATED entries share the ledger model but are
explicitly nonphysical and never enter the LIVE store. Explicit paper replacement
is the only corrupt-store recovery: archive the rejected bytes, atomically start
a fresh ledger bound to the replacement paper, then clear the contact blocker.

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

Stage 3.4 uses the same positions in order `C`, `X−`, `Y+`, `X+`, `Y−`. At each
position it draws one closed 2 mm-radius circle centered on the model sample.
The pen uses the current Down value accepted by Pen Interaction (`S760`
initially) plus the configured settlement, and returns using the current Up
value (`S40` initially). Those values may change when the existing Pen
Interaction exercise is repeated; a mark retains the exact values it actually
consumed. The circle uses 16 finite typed drawing chords capped at 100 mm/min,
keeping the chord approximation error below 0.05 mm, followed by one explicit
Pen Up.
This controller evidence does not prove physical pressure or observed ink.

After every circle, reveal travel goes Pen Up to the learned X+ Boundary limit
minus the 10 mm safety inset and toward machine Y=0, clamped to the safe Y
interval. This far reveal pose is visibility-only and is not a model sample.
After settlement and cap-map revalidation, the exact frame freezes without
changing the operator's viewport or locked ROI. The predicted tip remains hidden
before the click; the operator may explicitly zoom or pan without changing exact
camera-pixel evidence.

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
- exact post-reveal frame, settled reveal pose, and cap-map revalidation;
- clicked camera point with role `assertedCenter`, pointing uncertainty,
  timestamp, and presentation-transform revision;
- disposition and all consumed artifact/algorithm revisions;
- content-addressed locators only when exact bytes were actually archived.

The click is an assertion, not a seed for an automatic detector.

The first three accepted observations fit candidates. `X+` and `Y−` remain
holdouts. Model selection tries the smallest form first:

1. constant camera-pixel correction on the accepted cap map;
2. direct affine machine-to-tip map only when the constant candidate fails
   coherently at both holdouts.

One bad holdout does not justify a larger model. Both holdouts must pass the
selected candidate. The chosen form is refit over all five observations and
staged with residuals, uncertainty, applicability, and consumed evidence.
Explicit **Accept Tip Calibration** atomically creates `TipCameraRegistration`.

`TipCameraRegistration` maps machine coordinates directly to paper-contact
pixels. It retains the affine transform, model form, covariance/uncertainty,
applicability rectangle, sealed selection evidence, five observation hashes and
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
- paper/contact-plane change: quarantine until contact-plane revalidation;
- LIVE/SIMULATED source change: invalidate cross-source optical authority;
- raw observations: retain as immutable history under every change.

`LearningAuthorityManifest` is the single checksummed durable authority store.
One generation atomically contains optional `AcceptedMachineArtifactCheckpoint`
and `AcceptedTipCalibrationCheckpoint` payloads. Every accepted-authority save,
and each invalidation whose causal closure removes either durable payload, is an
exact generation/digest compare-and-commit of the complete manifest. A
nondurable graph-only invalidation does not load or mutate the manifest. A crash
or stale durable preview therefore cannot expose mixed machine/tip generations. The tip
payload contains the accepted registration, its acceptance event, and complete
consumed evidence. Loading
returns quarantined evidence. It cannot restore workflow state, a graph
revision, Motion authorization, operation ownership, a Stop capability, a
pending command, or a continuation. Fresh identity-compatible controller and
cap evidence is required before authority may be restored; paper-plane changes
also require one current accepted circle-center observation within policy.
Same-paper restart restoration performs no contact mark. Both paths create a new
accepted revision and retain their fresh revalidation evidence.

## Stage 4 dependency boundary

Observed Drawing Trials require accepted Boundary/coordinate evidence and one
exact current `TipCameraRegistration` revision.

Stage 4 chooses a 5 mm path inside the applicability rectangle that clears all
retained calibration-circle and line exposure by the declared ink-clearance margin.
If no such path exists, it blocks and requires a larger clean calibration area;
it never crosses old circle ink and weakens attribution. It projects its
intended local path through the tip registration. Its six leaves own exactly one
current subject/payload each: immutable line plan; atomic baseline/reveal
context; line-start arrival; line execution; atomic post-line observation
(return settlement, newer exact frame, observed geometry, and required
residual); and comparison. Each subject cites its exact causal predecessors and
the applicable source/group identities.

Intended geometry, observed ink, and residuals are required contextual Stage 4
evidence and have no global visibility toggles. An attributable observed line
may be retained as future refinement evidence. It cannot silently change an
accepted calibration. Before LIVE Pen Down, the full planned line is
conservatively reserved and persisted in the same current-paper
surface-exposure ledger as calibration circles. The reservation survives every
later outcome, invalidation, and process restart. Only explicit paper replacement
rotates applicability; it does not erase the ledger. Possible ink or ambiguous
motion never triggers automatic redraw or resend.

## Attempts, dependencies, invalidation, and simulation

Every repeatable exercise has an immutable attempt identity, typed disposition,
accepted artifact slot, and explicit dependencies.

Redo stages a replacement. Only a successful atomic commit changes the accepted
slot and invalidates named transitive dependents. Failure, refusal,
cancellation, or ambiguity preserves the prior accepted artifact and its
dependents. Record Another Attempt adds only compatible successful evidence.

The direct causal spine is:

```text
pen-cap appearance -> Pen Interaction
four Boundary aggregates -> estimated center/local frame -> center arrival
pen-cap appearance + center arrival -> five-cap MachineCameraRegistration
-> five ToolContactObservation revisions -> TipCameraRegistration
-> line plan -> local baseline/reveal context -> line-start arrival
-> line execution -> atomic post-line observation -> comparison
```

Invalidation is causal, not chronological. A leaf roots only its current
subject(s); a branch roots every descendant-owned current subject; the dependency
graph removes true transitive consumers. The immutable preview binds source,
subject/revision and payload versions, accepted sequence, and exact manifest
revision only when the scope removes a durable payload, and rejects stale
authority. Retained sparse exposure prevents same-paper 3.4 Redo. Any reserved
Stage 4 line exposure makes 4.1–4.4 replacement abandon that group and return to
a fresh 4.1 plan; no later leaf may become a false post-ink baseline.
Invalidation never performs motion, changes pen
state, cancels, resends, redraws, clears possible-ink or exposure history, or
claims to erase physical ink. LIVE and SIMULATED authority invalidate
independently. Redo remains the separate successful atomic-replacement seam.

LIVE and SIMULATED learning are independent `LearningSessionState` values
governed by the same state contract and selected by the active source. A source
switch never copies one source into the other. Leaving either source retains its
session; returning to an unchanged SIMULATED paper therefore retains both its
generated ink and its matching nonphysical surface-exposure ledger.

SIMULATED uses the same public action seams and dependency graph with causal
frames, persistent black ink, and a real nonzero cap-to-tip truth. It has no
capability to load or compare-and-commit the LIVE durable authority manifest. It
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

One exhaustive action-effect mapping owns button chrome: commit, accept, start,
go, and Stop & Accept are green; Stop, Cancel, reject, discard, and invalidate
are red; same-stage value/click/direction input is blue; view/navigation utility
is medium gray. A disabled action keeps its semantic role but renders dark and
is noninteractive. Passive status colors and required values are content, not
button roles or disabled-button stand-ins.

Physical work uses the signed bundle and single-instance launcher. The launcher
may activate the exact existing bundle or launch it through LaunchServices. It
must refuse wrong-path or competing raw processes without terminating them.
