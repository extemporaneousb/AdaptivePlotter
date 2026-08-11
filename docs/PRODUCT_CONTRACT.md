# AdaptivePlotter Product Contract

Status: current product authority

This document owns durable product boundaries and invariants. It does not own
the detailed operator sequence, package topology, validation ledger, or roadmap.

## Product boundary

AdaptivePlotter is one native, signed macOS application operating one local
plotter with one camera. The application owns the short
controller-camera-draw-observe loop directly.

In scope:

- one persistent controller owner and one persistent camera owner;
- typed controller requests and typed observations;
- a camera-first operator workbench;
- current-session discovery and observed drawing trials;
- conservative model learning from attributable evidence;
- simulator parity without physical authority.

Out of scope:

- a web server, Python bridge, remote backend, or second product process;
- arbitrary G-code or natural-language-to-motion translation;
- homing, unlock, alarm clear, controller reset, or firmware writes;
- entered bounds treated as measured workspace authority;
- automatic resend, resume, or redraw after ambiguity;
- learning-stage completion as a general motion gate;
- simulator state as physical evidence.

## Authority map

`MachineController` exclusively owns the selected controller connection,
protocol parsing, direct admission checks, command serialization, settlement,
and sticky ambiguity.

`RunInterpreter` owns the single current logical operation and delegates its
mechanical execution to `MachineController`.

`CameraCapture` exclusively owns camera discovery, authorization, selection,
capture lifetime, exact-frame materialization, and capability-scoped preview
publication holds. A hold never stops raw capture or changes camera identity;
it retains only the newest raw buffer and publishes at most one newest preview
when every matching hold settles.

`VisionWorker` and the analysis pipeline produce measurements and diagnostics.
They do not decide controller eligibility, machine direction, or model
acceptance.

Expensive Vision runs against one immutable exact frame off the main actor.
Automatic analysis defaults to 2 Hz, pauses preview publication while active,
and measures its cadence recovery interval from completion rather than start so
slow analysis cannot become an uninterrupted CPU loop. Explicit inspection
cancels cooperative background analysis before acquiring its frame and restores
the prior cadence only after preview and computation ownership settle.

Foreground visibility observation has one owner published before suspension.
It searches only bounded target-local support, reports honest phases, refuses
competing mutations, and exposes one capability-bound Cancel Vision action.
Cancellation preserves target, baseline, ROI, and active attempt; stale
generations cannot commit.

`OperatorWorkspace` projects current facts and routes typed UI intent. It is the
single observable app owner, not a replacement controller or camera authority.

`RunLedger` records ordered diagnostic facts. It does not replay work, decide
readiness, or promote learning artifacts.

## Learning Path semantics

The five visible stages are ergonomic navigation. Complete, Current, Next,
Future, and Needs Attention are presentation states. They do not form an
authorization ladder.

Connect and Enable Motion expose direct current-session facts. Each later
operation consumes only its declared mechanical and evidence dependencies.
Manual Pen Up motion does not require completed discovery or a learned model.

Navigator selection is presentation-only. Browsing a completed or future row
cannot change runtime current state, accepted evidence, or command eligibility.
When the protocol determines the next Boundary direction, the workbench shows
it as required noninteractive content. A disabled choice control must not imply
that the operator has another selection to make.

## Motion and Stop invariants

Every controller action has one typed intent, one owner, and a bounded terminal
contract. `ok` is acceptance only. Completion requires fresh Idle and final
MPos where the operation consumes position.

The contextual Stop capability identifies one exact active owner. Boundary,
manual jog, and drawing Stop may share the same mechanical Jog Cancel primitive,
but their semantic outcomes remain distinct. Repeated or stale capabilities are
inert.

Boundary motion may renew finite controller segments only while the same owner
remains active and the prior segment completed unambiguously. Segment completion
is not boundary evidence. Operator Stop, a real limit/alarm/disconnect, or a
typed fault ends the owner. Ambiguous motion never renews or resends.

Boundary renewal length may use fresh exact-frame vision as advice only. The
first wire request is 10 mm. Later requests are restricted to 40, 20, 10, 5,
or 2 mm, retain the admitted direction and controller-derived feed, and become
non-increasing after the first valid projection. Missing, stale, incompatible,
or low-confidence observations fall back to 10 mm or less. Stop is rechecked
on both sides of the asynchronous advisory wait.

For a LIVE Boundary owner, automatic background analysis pauses after the Stop
capability is published and before renewal begins. Explicit renewal inspections
then use the camera/Vision pipeline without competing background requests. The
previous automatic cadence is restored only after the same Boundary owner has
settled, regardless of success, Stop, refusal, or failure. This scheduling rule
does not promote camera advice into Boundary acceptance authority.

The physical power cutoff remains the emergency boundary. The software Stop is
not represented as a hardware emergency stop.

While a physical movement owner is active, its capability-bound Stop is the
only movement-ending exercise action presented. Cancel becomes available after
movement settles. A stale or programmatic Cancel cannot end the active owner.

The V2 visibility mark is one 4 mm regular octagon traced forward and then
reverse over the same perimeter under one compound owner and Pen Down interval.
The executed plan revision flows from controller progress into execution and
observation evidence.

## Evidence discipline

Evidence classes are reported separately:

1. automated build and test evidence;
2. deterministic simulator evidence;
3. controller acceptance and settlement evidence;
4. exact camera-frame evidence;
5. vision-derived measurement;
6. explicit human observation;
7. observed physical ink.

No lower class is silently promoted to a higher claim. In particular, a
controller transcript does not prove motion, a frame does not prove an inferred
shape, and simulation does not prove camera, controller, pen, or ink behavior.

Every frame-derived fact cites exact `FrameID`, pixels, source, capture time,
and `CameraConfigurationID`. Overlays are presentation and must match that
identity. A camera change invalidates optical dependents, not current compatible
machine-space boundary aggregates.

## Discovery authority

Pen Interaction records explicit Up/Down observations and ends with human
confirmation of Up.

Boundary side identity comes from the operator's typed X−, X+, Y−, or Y+
selection. A successful side attempt retains controller session/revision, final
settled MPos, Stop owner, and Stop disposition. It does not capture or require a
camera frame, cap/contact centroid, confidence, or Vision result. Camera edge
classification and generic drawing-frame geometry are advisory approach-planning
or diagnostic facts only and cannot identify or veto the selected machine side.

Compatible successful side attempts form one per-direction machine-space
aggregate. The four current aggregates derive estimated center and learned local
coordinates. Local coordinates are presentation evidence; they do not rewrite
controller MPos, configure an offset, clamp motion, or admit commands.

Center arrival accepts an exact controller-reported final MPos whose Euclidean
residual from the derived target is at most 0.05 mm. A stopped or
out-of-tolerance center move preserves all four accepted aggregates, center, and
local frame. Recovery is **Retry Center Arrival**, which requests only the
remaining delta; whole-Boundary Restart is not a valid recovery for this case.

All production comparisons between a requested controller pose and settled
MPos share this quantization-aware 0.05 mm Euclidean policy. An exact pose
requires fresh attributable controller MPos and compatible controller context;
it does not require mathematically zero residual when the requested coordinate
is not representable at the configured steps/mm.

Machine-camera registration separately consumes compatible exact machine/contact
samples. It never averages frames into new provenance.

Stage 3.3 exposes one public capture-and-build action. It records the target
MPos and exact frame, runs the bounded three-sample Pen Up calibration when
compatible samples are insufficient, returns to the recorded target under the
shared pose policy, and stages a reviewable non-authoritative proposal. Proposal
construction has no preceding generic Start or separate public capture step and
never accepts geometry; explicit operator acceptance or rejection remains a
separate action.

## Durable accepted artifacts

Current accepted LIVE machine-space Boundary evidence, aggregates, paired
progress, derived center/local frame, optional center arrival, and their current
dependency revisions may be checkpointed durably by atomic file replacement.
The file is quarantined on launch until a fresh passive controller probe matches
device/build, parser state, settings, coordinate offsets, and current MPos within
0.05 mm.

Checkpoint reuse is a convenience, not a requirement to preserve Boundary
coordinates across software schema changes. An incompatible checkpoint may be
discarded and the four fast Boundary stops repeated; no compatibility migration
may reintroduce Camera or Vision as machine-boundary authority.

The durable schema contains no active transaction, current question, Motion
authorization, operation owner, live Stop capability, pending command,
ambiguity recovery, resend, redraw, or workflow continuation. Historical owner
and Stop identifiers inside immutable accepted evidence are provenance only and
cannot be reinstalled as capabilities. A mismatch causes no machine action and
leaves the file non-authoritative.

## Attempts and dependencies

Every repeatable exercise has an immutable attempt identity, typed disposition,
accepted artifact slot, and explicit dependencies.

Redo stages a replacement. Success atomically swaps the accepted artifact and
invalidates only named transitive dependents. Failure, refusal, cancellation, or
ambiguity preserves the previous accepted artifact and its current dependents.

Record Another Attempt adds a compatible successful sample and recomputes the
typed aggregate. Aggregates report sample count, estimator, compatibility, and
uncertainty. Unsuccessful evidence remains attributable but cannot contribute a
successful value.

Review navigation is always presentation-only. **Reset From This Step** is the
separate chronological reset: it shows the selected exercise and every later
affected Learning Path exercise in a compact summary with one Reset button. It
does not require phrase entry. The reset rejects a stale summary and is unavailable
while an attempt, motion, foreground-Vision, camera, or controller operation is
active. **Reset All Learning** is the same guarded operation anchored at Pen
Interaction. It never changes Connect/Disconnect or Enable Motion.

LIVE and SIMULATED learning reset independently. Resetting LIVE Pen or Boundary
learning removes the durable accepted-machine-artifact checkpoint before changing
in-memory authority; failure to remove it aborts the reset. Invalidated revision
identity may remain provenance, but old attempt values do not remain active
aggregate inputs. Software invalidation never claims to remove physical ink or
undo motion. A drawn visibility target remains an unusable physical scene until
the operator explicitly registers another area or records paper replacement.

No compatibility alias, generic evidence bag, or second workflow store is
permitted to outlive the typed contract it replaced.

## Simulator isolation

SIMULATED uses the same Learning Path and public action seams with a causal
runtime, causal frames, exact annotations, and persistent simulated ink. It
cannot invoke physical `MachineActions` or satisfy physical artifacts.

Simulator truth, auto-fit viewport, annotations, learned sides, model state,
and simulated ink are never controller bounds, camera registration, motion
permission, or observed physical ink. Leaving SIMULATED restores parked LIVE
authority unchanged.

## Model-learning direction

Future Adaptive Drawing is valid product scope. Typed drawing programs,
transforms, residuals, model observations, candidate fitting, holdout evaluation,
and online dataset accumulation may exist before the final UI when they remain
coherent with this contract and have deterministic tests.

The word **training** is reserved for an actual dataset partition or fitting
operation. Human-Guided Discovery and Observed Drawing Trials collect evidence;
their stage names do not claim model fitting.

Model candidates remain diagnostic until explicitly accepted against reserved
physical observations. Fast state and slow parameters remain distinct. Slow
geometry changes require identifiability, candidate-versus-prior comparison,
whole-stroke holdouts, applicability bounds, and improved held-out performance.
No accepted model changes during a Pen Down stroke.

Model selection may propose a future bounded experiment. It never bypasses
direct controller authority, causes hidden motion, or permits automatic redraw.

## Input, output, and launch

Buttons are authoritative for choices, progression, Cancel, and Stop. Speech is
output-only and advisory; failure leaves visible controls usable.

Physical work uses the signed bundle and single-instance launcher. The launcher
may activate the exact existing bundle or launch it through LaunchServices. It
must refuse wrong-path or competing raw processes without terminating them.
