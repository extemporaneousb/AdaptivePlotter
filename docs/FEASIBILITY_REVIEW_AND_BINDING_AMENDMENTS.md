# Feasibility Review and Binding Amendments

Status: binding simplification of the architecture and implementation plan
Scope: this Mac and its attached plotter only

## Precedence

This document overrides any requirement elsewhere in the repository for:

- full Xcode, distribution signing, notarization, sandboxing, release packaging,
  CI, or a supported-machine matrix. The local TCC-attributable app bundle is
  retained;
- mandatory strict Swift concurrency or warnings-as-errors;
- phase-wide development or landing gates;
- separate motion and pen arms, expiring approvals, or a general execution
  authority framework;
- comprehensive durable replay, archival run bundles, content-addressed
  evidence, retention/quota/tombstone policy, or algorithm re-evaluation;
- accessibility work, a complete observability workspace, operator studies, or
  polished diagnostics;
- premature spline fields, generalized model-promotion machinery, bootstrap
  statistics, or factorial physical-trial programs before the learning ladder
  produces a concrete residual they would address.

When older text conflicts with this document, choose the smaller direct local
implementation.

## Feasibility verdict

The product is feasible as one local Swift application. The critical question
is not whether a generalized adaptive-control platform can be built. It is:

> Can this plotter draw a requested vector path while the local camera sees the
> resulting ink well enough to show and, if useful, correct a simple positional
> error?

Take as an initial assumption that a large isolated green mark on clean white
paper can be detected. Do not create a separate vision-research project before
trying the complete loop.

## Action and risk posture

This plotter is a replaceable spare-parts and 3D-printed machine with physical
end stops. Optimize the software for fast, attributable physical experiments,
not for eliminating every possibility of machine wear. Once the controller is
connected and the operator activates Motion Guard, issue the smallest useful
typed operation, observe it, and continue. A model error, missing label, or
incomplete preflight curriculum is data; it is not a reason to disable ordinary
motion.

Keep the power cutoff reachable and retain direct alarm, asserted-end-stop,
disconnect, feed-capability, pen-state, in-flight ownership, and ambiguity
checks. Do not stack readiness workflows, entered bounds, model thresholds, or
repeated confirmations above them.

## Minimum physical loop

The first useful physical result is:

```text
select controller
-> connect and activate Motion Guard
-> start one voice ExplorationSession
-> run the Motion Preflight observation consumed by this trial
-> teach one armature-clear observation pose
-> select one fixed finite test line
-> command pen up and observe clearance
-> capture a clean reference at the clear pose
-> move to and record the line-start MPos
-> create one Pen Down/Pen Up anchor dot
-> return clear and capture the anchored baseline
-> detect the anchor and return pen-up to the recorded start
-> lower pen and draw the line
-> raise pen and move to one known clear pose
-> capture a newer post-line frame after settlement
-> detect the line relative to the anchored baseline
-> display intended line, observed line, and simple error
```

The trial succeeds as an engineering result if the app completes the sequence,
shows what actually happened, and does not repeat an ambiguous command. The
line does not need to meet a premature statistical acceptance program.

That preflight observation is local to this trial. It is not a prerequisite for
ordinary manual motion or unrelated camera/controller work.

## Tool visibility

Before the first ink observation, establish one usable clear pose and one
bounded pen-up path to it. Use the smallest adequate representation:

- one fixed observation region;
- one conservative 2D camera-space outline or bounding box for the complete
  pen/holder/linkage/servo assembly;
- one fixed margin;
- one clear pose and path.

For the first line test, move pen-up to one operator-chosen pose that visibly
clears the fixed observation region. Do not build a polygon envelope, 3D model,
generalized clearance planner, position-dependent occlusion model, or versioned
evidence framework unless that simple pose demonstrably fails.

Failure to find a clear pose stops that drawing attempt. It does not stop camera
work, controller work, UI work, or a different bounded experiment.

## Direct motion eligibility

There is one operator arming action: activate Motion Guard for the connected
controller session. There is no composite readiness workflow. Each typed action
derives eligibility directly from facts it actually consumes: a responsive
selected controller, no current alarm or asserted limit, activation, suitable
pen state, and a working camera only when the action's purpose requires visual
observation.

Do not require completed preflight sequences, independent motion/pen arms,
phase identities, retained evidence IDs, model-promotion state, or repeated
operator acknowledgements before ordinary motion.

Recheck a fact only when something invalidates it: disconnect, controller reset
or alarm, configuration change, manual movement that loses known position,
tool/pen change, or camera change. A transient error should be correctable and
retryable in the same app launch.

Every machine command still receives immediate direct checks for the closed
request type, finite values, controller-reported axis feed capability, current
alarm/end-stop state, pen state, in-flight ownership, and sticky ambiguity. An
unknown command outcome stops the current run and is never automatically
resent. Operator-entered coordinates, travel envelopes, and maximum-jog values
are not prerequisites or motion authority.

## Best-effort session log

SQLite may record ordered controller exchanges and operation summaries for the
current session. It is observability only. Do not commit a command to the
database before sending it, do not maintain a durable command-lifecycle state
machine, and do not refuse hardware work because logging is unavailable.

Do not let old databases block a new launch or a new passive session. Do not
build command recovery from prior files, archival replay, content-addressed
frame storage, export manifests, retention classes, quotas, garbage collection,
tombstones, cross-launch scans, or exact UI reconstruction.

After a process or machine interruption, never automatically resume or resend.
Reconnect, query the controller, inspect the machine, and start a new explicit
operation. Any old session log remains optional diagnostic data only.

## Minimal model

Start each rung of the learning ladder with the simplest model that works:

```text
fieldPoint = affine(machinePoint) + optional constant tool offset
```

Use direct point or line measurements to adjust it manually or by a simple fit.
The repository already contains a deliberately small immutable accepted
snapshot, explicit candidate fit, fixed training/holdout membership, held-out
acceptance decision, and pen-up checkpoint rule. Those primitives are exercised
by tests and the deterministic simulator; they are not a prerequisite for the
first observed line and are not yet a live ink-training workflow. Do not expand
them into generalized promotion UI, history, or experiment infrastructure. No
backlash learner, pen-mark model, spline, bootstrap, covariance program,
factorial trial matrix, or trust-region model evolution is required.

Keep the first isolated-line residual in `CameraPixelSpace`. Physical ink cannot
enter the existing machine-to-`FieldSpace` trainer until a cited current-session
`FieldRegistration` exists; that bridge is learning provenance, not a motion
gate or an operator-entered calibration step.

If drawing quality is acceptable, stop increasing the geometric model. Active
experiment selection, spoken preference learning, and later reinforcement
learning remain product goals because they address which experiment or drawing
action to choose, not because the affine mapping must become complex. Add a
geometric term only after repeated observed ink identifies a specific systematic
error the affine transform cannot represent.

## Minimal observability

Show only what helps operate or debug the current attempt:

- selected port and controller state;
- latest camera frame and its age;
- current operation/stroke;
- last command and controller outcome;
- intended and observed ink geometry;
- simple residual/error;
- one actionable error message.

No accessibility work is required. The current active episode may show its
participants, actions, observations, and next event. No historical semantic
timeline, generalized model inspector, trial browser, replay mode, storage
dashboard, or performance-signpost program is required.

## Local development contract

The installed Command Line Tools, Swift compiler, macOS SDK, and SwiftPM are
sufficient. Normal build/test uses the package's compatibility language mode.
The optional strict check may be used diagnostically but cannot block ordinary
work merely because a stricter compiler mode reports warnings.

Blackdog remains mandatory for retained repository work. Within each Blackdog
task, use focused tests during iteration and land a coherent working increment.
Hardware absence or an unrelated physical failure never blocks landing.

## What remains fixed

- One local Swift application process; no live Python or localhost bridge.
- No arbitrary G-code input.
- No automatic unlock, homing, settings write, alarm clear, reset, or resume.
- One persistent voice `ExplorationSession` is the intended human teaching and
  reflex surface; free-form speech never owns serial bytes.
- Commands use closed finite requests, stay within controller-reported feed
  capability, and stop on current alarm/end-stop/ambiguity facts. Operator-
  entered distance caps and workspace coordinates are not motion prerequisites.
- Controller `ok` is not proof of ink.
- Actual observed ink is the drawing result.
- An ambiguous command is not automatically resent or redrawn.
- Preview/display coordinates never become machine coordinates.
- Add no generalized infrastructure without a concrete current need.
