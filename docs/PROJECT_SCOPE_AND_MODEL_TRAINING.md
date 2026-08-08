# Project Scope and Learning Architecture

Status: canonical product, interaction, and learning contract
Target: this operator Mac, the attached GRBL/grblHAL plotter, and the attached camera

## Product purpose

AdaptivePlotter is a local embodied-learning application for one physical
drawing machine. It exists to make the shortest useful loop fast enough to use
at the machine:

```text
robot action -> camera and controller observation -> machine assessment
-> short spoken feedback -> human observation -> spoken correction or reward
-> next robot action
```

The application should move early, observe what happened, and learn from the
operator's eyes and voice. It is not a form-driven calibration product, a
general robot platform, or a model-training system detached from the plotter.
Its success condition is progressively more independent drawing: it can turn a
requested path into visible ink, compare intended and observed geometry, choose
useful next experiments, and reduce repeatable error while an operator provides
rapid supervision and interruption.

Actual ink is the drawing result. Controller acceptance, reported position,
cap motion, a simulated image, or a fitted model can support diagnosis and
learning, but none alone proves that a requested mark was drawn.

## Product decisions

The following choices are settled:

1. **Bias for action.** Once the controller is connected and motion is
   activated, experiments proceed without typed coordinate maxima, a travel-
   envelope form, a maximum-jog form, document-reading gates, repeated
   acknowledgements, or model-acceptance ceremony.
2. **Voice is the primary teaching and reflex channel.** It is not an
   accessibility accessory or a substitute label on a button. A started
   exploration keeps listening active so the operator can stop, redirect,
   classify, compare, and reward without looking away from the machine.
3. **The operator accepts bounded machine risk.** This is a replaceable spare-
   parts and 3D-printed machine with physical end stops. Software retains only
   the immediate mechanical guards listed below; it does not attempt to create
   a second virtual machine around the first one.
4. **Vision learns from exact observations.** Any frame used to update a
   drawing-frame estimate, visibility model, geometric model, or reward label is
   immutable and identified with its camera configuration and action context.
5. **Models become more sophisticated only as the loop demands it.** Begin
   with direct observations and simple estimators, then progress through
   supervised fitting, active experiment selection, preference learning, and
   bounded reinforcement learning. Each rung has a concrete objective.
6. **One local Swift process owns live authority.** Voice, camera, vision,
   controller, learning context, and UI communicate through typed native calls.
   No LLM, speech transcript, plug-in, Python process, or network service owns
   serial bytes.

Distribution, a multi-machine abstraction, archival replay, a history browser,
operator-authored coordinate calibration, and a generalized robotics framework
are not goals.

## Current implementation versus selected direction

| Capability | Implemented now | Selected direction |
| --- | --- | --- |
| Controller and motion | Persistent connection, explicit session activation, relative jog, Jog Cancel, typed pen actuation | Keep the direct typed path and remove no additional motion behind learned bounds or setup forms. |
| Camera and vision | Exact C920 frames, cap/frame-side analysis, inferred drawing frame and armature overlay | Turn observations and human labels into first-class exploration episodes and posterior/model updates. |
| Voice | A Motion Preflight sequence starts and stops its own microphone and accepts exact context-bound phrases | One persistent `ExplorationSession` owns the warm microphone, low-latency reflex intents, teaching labels, and interruptible feedback. |
| Boundary learning | Cancelled boundary jog plus a newer tool observation feeds a heuristic nearest-edge quadrilateral update; final MPos is recorded but not numerically fused | Keep this as the first zero-order learning episode, then replace the heuristic with a per-side image-space posterior whose uncertainty narrows under repeated observations. |
| Jog response | Current-session 2x2 controller-to-camera diagnostic with fixed holdout membership | Use it as local motion evidence, not a general motion blocker. |
| Drawing model | Affine machine-to-`FieldSpace` training primitives and simulator exercise exist; live camera observations have no accepted `FieldRegistration` | Keep the next residual in `CameraPixelSpace`; create a cited current-session camera-to-field registration before admitting physical ink to the existing affine trainer. |
| Armature visibility | Inferred image-space armature overlay exists | Add **Armature Guidance**, using human visibility labels and active pose selection to learn where ink can be seen. |
| Preference and policy learning | Not implemented | Add spoken shape comparison after reliable ink observation, then bounded autonomous experiment selection. |

The current sequence-local microphone and exact `READY`/`STOP` parser are a
safe bootstrap, not the target interaction architecture.

## ExplorationSession

`ExplorationSession` is the first-class runtime and learning boundary. Starting
it once activates listening and establishes the current controller, camera,
tool, model, and interaction context. The microphone remains warm through
Motion Preflight and later learning episodes. It stops only when the operator
ends the exploration, the app shuts down, permission is lost, or a failure
makes continued interpretation unreliable.

There is no separate **Start Listening** mode and no need to restart listening
between sequences. Motion Preflight is the first episode inside this session,
not the owner of microphone lifetime.

Voice has two paths:

- The **reflex path** maps a small contextual grammar directly to closed typed
  intents: `STOP`, continue, keep going, reverse, more/less X or Y, pen up,
  accept, again, skip, and end session. `STOP` may act on a stable partial
  recognition result because a false positive merely cancels the current jog.
  Motion-producing commands require a final or otherwise stable contextual
  result.
- The **teaching path** records flexible observations and preferences such as
  “I can see the last mark clearly,” “partially blocked,” “C is best,” or “B is
  too wide.” It may structure those words into labels, rankings, features, and
  rewards, but it cannot create raw controller commands.

Machine speech is newest-only, brief, and interruptible. Operator speech stops
current text-to-speech immediately. The app should say what happened or what it
needs next, not read instructions that are already visible. Relevant latency is
measured end to end: speech onset/final hypothesis, intent dispatch, controller
write/settlement, next-frame availability, model result, and feedback onset.
Speech cannot beat the electrical latency of a button; it wins by removing gaze
shifts and carrying richer feedback through the complete interaction loop.

## Minimal mechanical guards

A machine-affecting typed intent is refused only when a concrete current fact
makes that intent invalid:

- no selected responsive controller;
- Motion Guard has not been activated for this controller session;
- controller alarm, asserted end stop, disconnect, or unsupported state;
- an earlier transmitted action has an ambiguous outcome;
- another machine operation owns the controller;
- pen state is unknown or wrong for the requested travel/drawing action;
- a requested value is non-finite or its feed exceeds the controller-reported
  axis capability;
- a current camera frame is absent for an operation whose purpose requires
  vision.

The operator corrects the current fact and retries immediately. There is no
operator-entered coordinate envelope, maximum-jog prerequisite, global learned
boundary gate, document gate, trial-count gate, model-confidence gate, or
repeated confirmation. A finite action horizon belongs to a specific typed
experiment; it is not a user-authored workspace limit or general motion lock.

Software `STOP` means the quickest applicable typed cancellation, currently
GRBL Jog Cancel for a jog. It is not a physical emergency stop. The operator
keeps the machine's power cutoff reachable during physical exploration.

## Learning ladder

The ladder is ordered by the evidence each later rung consumes. It is a route
to progressively greater autonomy, not a set of repository landing gates.
Software for a later rung may be built early when it shortens the next physical
experiment.

| Rung | Interaction and objective | Model update | Promotion signal |
| --- | --- | --- | --- |
| 0. Motion Preflight | Use voice to confirm pen interaction and stop boundary-search motion while watching the machine. Minimize repeat error when returning to a taught stop and reduce image-edge uncertainty. | The selected side supplies edge identity. Fuse the exact post-stop centroid into a per-side image-space edge offset with explicit observation variance; repeated evidence narrows uncertainty and corners derive from edge intersections. Final MPos remains provenance/repeatability context until a registration gives it image-space meaning. | The observations exist for the operations that need them. Missing sides do not block unrelated jog or camera work. |
| 1. Armature Guidance | Move the pen/armature while the operator labels the last ink region clear, partial, or blocked and may say which direction to continue. Maximize ink visibility with little clearance travel. | Record labelled poses and one accepted clear-pose fact first. Fit a current-scene visibility/occlusion estimate only after multiple nonduplicate poses, then compare its estimate with human labels to select informative next poses. | One repeatable pen-up clear pose/path supports isolated-line inspection. Incorrect estimates become new labels, not a global motion stop. |
| 2. Isolated ink geometry | Draw a dot or short line, clear the armature, extract actual ink, and compare intended versus observed endpoints/centreline in `CameraPixelSpace`. Minimize geometric residual and unnecessary motion. | First use the current-session machine-delta-to-camera-delta response. Before using the existing machine-to-`FieldSpace` affine trainer, create a provenance-bearing camera-to-field `FieldRegistration` from the accepted frame estimate. Keep training and reserved episodes distinct. | Camera-space residual is attributable; later, real held-out field-space ink error improves and the next stroke can use an accepted snapshot at a pen-up checkpoint. |
| 3. Stroke and shape learning | Draw several line/stroke/shape candidates—such as four hearts—and collect spoken ranking, rating, and feature feedback. | Combine direct geometric loss with a preference model over shape qualities such as closure, width, symmetry, and smoothness. | Predictions agree better with reserved human choices and produce visibly better later candidates. |
| 4. Bounded autonomous exploration | Use a separate acquisition score—expected information gain or model disagreement—to choose informative reversible experiments. Let a drawing policy choose actions that improve externally evaluated drawing outcomes while the operator can redirect or stop by voice. | Keep acquisition score out of product reward. Optimize the policy using held-out geometric/preference quality, motion/time cost, completion, intervention, and ambiguity. | Autonomous batches improve held-out drawing/preference outcome without increasing ambiguous, incomplete, or intervention-heavy actions. |
| 5. Continuous adaptive drawing | Run multi-stroke drawing and learning episodes with passive human supervision and occasional spoken intervention. | Preserve fast per-action state correction separately from slower checkpointed model/policy updates. | The machine completes useful drawings repeatedly and requests help only when observation or execution is genuinely unclear. |

Motion Preflight may contain two or more setup sequences for a particular
operation. That dependency is local: for example, a frame-relative drawing can
require relevant boundary observations, but ordinary pen-up jogging does not.

On the first observation for one machine-side label, associate its centroid
with the nearest candidate edge in the current camera-frame estimate only when
the distance margin makes that choice unique. Persist that machine-side-to-
camera-edge association for the camera configuration. Initialize orientation
from the candidate edge and offset with an explicit broad prior variance. Reject
an ambiguous association as a learning observation without blocking motion;
reassociate after a camera-configuration change.

An accepted clear pose is current-context evidence. Controller coordinate
reset/reconnect, camera-configuration change, observation-region change, or a
tool/paper change invalidates automated return to that pose. It does not disable
manual motion or erase the historical labelled observation.

The next isolated-line slice ends in `CameraPixelSpace`. Physical observations
cannot enter the existing machine-to-`FieldSpace` affine trainer until one
accepted, provenance-bearing current-session `FieldRegistration` maps the exact
camera configuration and drawing-frame estimate into `FieldSpace`. That
registration is learning context, not calibration ceremony or motion authority.

## Learning episode and provenance contract

Every observation admitted to learning is an `ExplorationEpisode`, not an
unstructured transcript or screenshot. The smallest useful episode records:

```text
session and episode identity, live/simulated source, and termination state
interaction context and active learning rung
speech utterance identity, partial/final timing, transcript, and parsed intent/label
episode-level training/reserved split assigned before action
candidate action set, policy/model version, and selection propensity when applicable
typed action request and model/policy snapshot used to choose it
controller start/final MPos, sample/settlement times, outcome, and ambiguity
exact selected before/after frame IDs, raw hashes, capture times, and camera configuration
vision algorithm revision
vision estimate, human observation, residual/reward, and reward provenance
```

All endpoints, centreline samples, frames, and labels from one physical line
share that line episode's split. They may not be divided across training and
reserved data. A post-clear frame is valid only after the clear-pose return has
settled, not merely because its frame sequence is newer than the baseline.

Only frames selected for a learning episode need durable exact bytes. This is a
compact training dataset, not continuous video recording or a general replay
archive. Simulation episodes use the same schema but remain explicitly
non-physical and cannot satisfy hardware observations. Their operator input may
come from deterministic injected speech or, when **Practice with Voice** is
enabled, the real microphone so the human can rehearse timing and phrases; that
input choice does not change simulation authority. A human label may be ground
truth for current-scene visibility or preference without being promoted to a
claim the camera itself proved.

The existing camera owner exports those deliberately admitted frames through
the `CameraSamples` PNG/manifest path; no second artifact owner is introduced.
An export failure cannot block motion or immediate assessment, but that episode
is incomplete for durable training until its selected exact frames exist.

## Losses, rewards, and experiment selection

A loss can be a reward: minimizing drawing mismatch is equivalent to maximizing
its negative. The distinction is about the learning problem, not the scalar's
name.

- Use supervised fitting when an action yields an attributable input/output
  pair and the goal is to estimate geometry.
- Use active learning when the model chooses the next pose or mark primarily to
  reduce uncertainty or resolve disagreement with the operator. This uses an
  acquisition score, not product reward.
- Use preference learning when the operator ranks hearts, strokes, or other
  candidates more naturally than assigning an absolute score.
- Use reinforcement learning when a policy must choose a sequence of actions
  whose external value includes future drawing/preference quality, motion cost,
  time, completion, intervention, and failure/ambiguity risk.

No special “RL reward sensor” is required. Negative line residual, number of
moves, human visibility labels, pairwise shape choices, completion time, and
ambiguous outcomes can all contribute to reward. Information gain remains the
experiment-selector score and cannot make a drawing policy appear better merely
by seeking uncertainty. What is required before policy optimization is an
attributable transition: the system must know which action produced which
controller, camera, ink, and human outcome.

## Immediate physical training procedure

The next physical slice is intentionally small and action-heavy:

1. Launch the signed app, select/connect the remembered controller, activate
   Motion Guard, select the C920, and start one ExplorationSession.
2. Prove the session-owned microphone, barge-in, partial-result `STOP`, concise
   feedback, and typed-intent dispatch first in the simulator and then with one
   conservative physical jog.
3. Run physical Pen Up confirmation, then one relevant boundary Motion
   Preflight episode. Update the selected
   image edge from the exact observation and show the result; do not ask for
   coordinates or stop other useful motion because every side is not yet taught.
4. Run one Armature Guidance episode. Move pen-up, ask the operator whether the
   last-mark region is clear/partial/blocked, compare that with the vision
   estimate, and identify one repeatable clear pose.
5. If the current session has no machine-delta-to-camera-delta projection,
   record two linearly independent accepted observed pen-up jogs, preferably by
   admitting useful Armature Guidance moves that already satisfy the evidence
   contract. This supplies a residual reference; it does not authorize or
   otherwise gate motion.
6. Capture a clean frame at the clear pose. Choose the line-start MPos, transact
   physical Pen Down confirmation followed by Pen Up, return clear, and capture
   an exact anchor frame. The new dot identifies the pen-tip start in camera
   pixels; that anchor frame becomes the line baseline. This is local first-mark
   evidence, not a manual-motion gate.
7. Return pen-up to the recorded start, draw one short isolated line, raise the
   pen, move to the clear pose, wait for unambiguous return settlement, capture
   a newer exact frame, extract the ink, and show the intended-versus-observed
   `CameraPixelSpace` residual anchored at the dot.
8. Record the complete episode and immediately repeat or adjust only when the
   previous action is unambiguous. Never automatically redraw an uncertain
   mark.

The physical session stops for a controller alarm/asserted limit, disconnect,
unexpected actuation, unavailable physical cutoff, or sticky ambiguity. A
recognition miss, model error, missing visual label, or failed ink extraction
is a debugging observation and should lead to correction or a different
bounded experiment, not abandonment of the slice.

## Training goals

The project is training toward:

- a useful posterior over the drawing frame rather than operator-entered bounds;
- reliable voice-to-action and voice-to-label latency at the machine;
- an armature visibility model that finds clear observation poses;
- a controller/camera/ink model that predicts where an intended segment will
  actually appear;
- lower held-out endpoint, centreline, and shape residuals;
- a preference model that predicts the operator's comparative drawing choices;
- an exploration policy that selects informative, low-cost physical trials;
- multi-stroke execution that improves at pen-up checkpoints and runs with
  passive human supervision.

The next goal is not to prove a general autonomous artist. It is to make one
real voice-mediated exploration session produce one clear, attributable ink
observation and make the next action more informed than the previous one.
