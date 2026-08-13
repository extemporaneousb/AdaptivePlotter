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
- one camera-first operator workbench;
- current-session discovery and observed drawing trials;
- sparse operator-selected contact evidence and explicit model acceptance;
- conservative model learning from attributable evidence;
- causal simulator parity without physical authority.

Out of scope:

- a web server, Python bridge, remote backend, or second product process;
- arbitrary G-code or natural-language-to-motion translation;
- homing, unlock, alarm clear, controller reset, or firmware writes;
- entered bounds treated as measured workspace authority;
- automatic resend, resume, retap, continuation, or redraw after ambiguity;
- Learning Path completion or model confidence as a general motion gate;
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
analysis region. The lock constrains which camera pixels generic cap, frame-side,
drawing-frame, and armature scans may consume. It does not crop or mutate the
stamped frame, change exact-frame identity, or constrain specialized workflow
measurements that already carry their own typed regions. Changing camera source
or configuration clears the lock.

`VisionWorker` and analysis pipelines produce measurements and diagnostics.
They do not decide controller eligibility, machine direction, operator click,
or artifact acceptance.

`OperatorWorkspace` is the single observable app owner. It projects current
facts and routes typed intent without replacing controller, camera, or evidence
authority.

`RunLedger` records ordered diagnostic facts. Raw controller events and typed
workflow events remain distinct. Ledger facts cannot replay work, restore a
capability, or promote an artifact.

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
Next, Future, and Needs Attention are presentation states, not an authorization
ladder.

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
presentation operations remain non-evidence.

Before accepted tip authority exists, the UI states **Tip not calibrated**.
During each mark selection, the predicted tip point is hidden until the operator
clicks. After the click, the asserted point and uncertainty, predicted point,
and residual are displayed.

## Motion, Stop, and ambiguity

Every controller action has one typed intent, one owner, and a bounded terminal
contract. `ok` proves acceptance only. Completion requires fresh Idle and final
MPos when the operation consumes position.

Failure kind, attempt disposition, recovery, and possible-ink meaning are typed
facts. Human-readable descriptions are projections only; wording changes cannot
alter blacklist, no-redraw, Stop, or accepted-fallback behavior.

The manual direction controls select their typed intent from the current
controller-commanded pen state. Pen Up uses an ordinary `RelativeJogRequest`;
Pen Down uses a bounded `DrawingStrokeRequest` and remains Pen Down after clean
completion so consecutive sides can form one manual shape. Unknown pen state
refuses motion. A stopped manual drawing stroke retains the drawing owner's
single typed Pen Up cancellation result. Learning state and camera availability
do not participate in either manual-motion admission path.

All production requested-pose comparisons use fresh attributable controller
evidence, compatible context, and at most 0.05 mm Euclidean residual. “Exact
pose” names that quantization-aware policy; it does not mean zero mathematical
residual at an unrepresentable stepper position.

The contextual Stop capability names one exact active owner. Repeated or stale
capabilities are inert. While physical movement owns an exercise, its Stop is
the only movement-ending exercise action. Cancel becomes available only after
movement settles.

Boundary side identity is the operator's typed X−, X+, Y−, or Y+ direction plus
settled controller evidence. Camera analysis may advise bounded renewal length
but cannot identify or veto a side. Missing or stale camera advice cannot weaken
direct controller authority.

Any ambiguous circle-chord motion, Pen Down, or Pen Up outcome after possible
contact creates possible ink. The circle center/radius plus paper-plane identity
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

The artifact retains all five exact-frame correspondences, roles, holdout
residuals, uncertainty, applicability rectangle and derivation, semantic optical
identity, machine geometry identity, controller session, coordinate revision,
and estimator revision. It maps machine position to the visible cap landmark.
It does not locate the paper-contact point.

## Stage 3.4 contact authority

Stage 3.4 uses the same positions in order `C`, `X−`, `Y+`, `X+`, `Y−`. At each
position it draws one closed 2 mm-radius circle centered on the model sample.
The pen uses the complete fixed local lower profile (`M3 S760` plus 0.3 s
settlement); the product exposes no separate pressure control and never
overdrives that profile. The circle uses 16 finite typed drawing chords capped
at 100 mm/min, keeping the chord approximation error below 0.05 mm, followed by
one explicit Pen Up.
This controller evidence does not prove physical pressure or observed ink.

After every circle, reveal travel goes Pen Up to the learned X+ Boundary limit
minus the 10 mm safety inset and toward machine Y=0, clamped to the safe Y
interval. This far reveal pose is visibility-only and is not a model sample.
After settlement and cap-map revalidation, the exact frame opens at a
one-third-frame presentation focus around the pre-mark cap anchor. That zoom is
view-only and does not expose the predicted tip before the click.

Each accepted `ToolContactObservation` is immutable raw evidence for one
commanded circular mark and asserted circle center. It retains:

- attempt and operation identities;
- intended mark position and settled MPos;
- machine geometry, controller session, coordinate-frame revision, and
  controller-context evidence;
- the 2 mm-radius/16-chord/100 mm/min-capped commanded geometry, fixed actuation-profile
  revision, and Pen Down/Up outcomes/timestamps;
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

`AcceptedMachineArtifactCheckpoint` remains machine-only.
`AcceptedTipCalibrationCheckpoint` is separate and contains the accepted tip
registration plus its acceptance event and complete consumed evidence. Loading
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
retained 2 mm-radius calibration circles by the declared ink-clearance margin.
If no such path exists, it blocks and requires a larger clean calibration area;
it never crosses old circle ink and weakens attribution. It projects its
intended local path through the tip registration. It owns
its own local pre-line baseline, Pen-Up reveal MPos, line-start travel, one
drawing owner, return to the same reveal pose, strictly newer post-line frame,
and generic black/new-ink observation. Its request and result cite the exact tip
revision.

An attributable observed line may be retained as future candidate refinement
evidence. It cannot silently change the accepted model. Possible ink or
ambiguous motion never triggers automatic redraw or resend.

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
Redo. It previews the exact suffix, rejects a stale summary, and never performs
motion, changes pen state, or erases physical ink. LIVE and SIMULATED authority
reset independently.

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

## Model-learning direction

Adaptive Drawing remains valid future scope. Candidate fitting, dataset splits,
holdouts, residuals, and bounded experiment proposals may exist when they remain
typed and attributable.

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
