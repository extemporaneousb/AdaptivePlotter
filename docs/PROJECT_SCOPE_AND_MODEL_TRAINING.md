# Project Scope and Model Training

Status: canonical product and learning assessment
Target: this operator Mac, the attached GRBL/grblHAL plotter, and the attached camera

## Product purpose

AdaptivePlotter is a native macOS control-and-observation application for one
physical drawing machine. Its purpose is to close this loop:

```text
connect -> establish a voice-mediated preflight -> draw a vector path
-> move the tool clear -> observe the actual ink -> measure error
-> improve later, still-unexecuted strokes when the evidence supports it
```

The result is not a general robot-control platform and not a model-training
product detached from the plotter. The app is successful when it can repeatedly
turn a requested path into visible ink, show the difference between requested
and observed geometry, and reduce repeatable error without hiding uncertain
machine outcomes.

Actual ink is the drawing result. Controller acceptance, controller position,
cap motion, a simulated image, or a fitted model may support diagnosis, but none
of them alone proves that the requested mark was drawn.

## Product goals

1. Keep controller, camera, voice, vision, and drawing coordination in one local
   Swift process with typed boundaries and no arbitrary G-code surface.
2. Make initial physical setup observable and low-friction through discrete
   Motion Preflight sequences, without operator-entered coordinates, travel
   envelopes, or maximum-jog values.
3. Draw one isolated line, then a small multi-stroke `DrawingProgram`, while
   preserving one in-flight command owner and never automatically resending an
   ambiguous result.
4. Bind every visual measurement used for learning to the exact immutable frame
   and camera configuration that produced it.
5. Learn only corrections that improve held-out error, and apply a new model
   only between strokes while the pen is up.
6. Stop adding model complexity when a simple affine mapping produces acceptable
   observed drawings.

Distribution, a multi-machine abstraction, archival replay, a history browser,
continuous pen-down adaptation, generalized reinforcement learning, and an
operator-authored coordinate calibration are not project goals.

## What the repository is currently set up to do

| Capability | Current status | Authority boundary |
| --- | --- | --- |
| Controller connection and inspection | Implemented and physically exercised | A green connection means the selected controller completed the passive inspection; it does not prove motor power. |
| Relative jog and pen actuation | Implemented; 1 mm X/Y round trips and the local pen profile were physically exercised | Motion requires current-session activation, controller eligibility, and known Pen Up for travel. No typed coordinate limits are required. |
| Live C920 capture and feature measurement | Implemented and exercised | Measurements cite exact frame bytes, frame identity, camera configuration, and algorithm revision. |
| Motion Preflight | Implemented with typed voice transactions and simulator rehearsal; physical boundary-sequence validation remains pending | Rehearsal grants no physical readiness. A boundary is evidence only after Jog Cancel settles at Idle with final MPos and a newer visual observation. |
| Current-session jog-response learning | Wired into the live app and physically exercised | Diagnostic only; it has no inverse-command, acceptance, persistence, or motion-authority API. |
| Affine drawing-model training | Implemented as domain/runtime primitives, tests, and a deterministic simulator demonstration | The live app does not yet own an ink-backed accepted-model training loop. |
| Isolated-line drawing and ink residual | Not implemented | This is the next product slice and the missing source of drawing-quality labels. |
| Multi-stroke adaptation | Domain rules exist; execution is not implemented | A model must remain pinned throughout every pen-down stroke. |

## Three distinct learning layers

### 1. Motion Preflight: geometric setup, not model training

Motion Preflight establishes the current physical context through closed
voice-mediated transactions. The four boundary sequences associate a
controller-reported cancellation position and a strictly newer camera
observation with the selected visual side. That evidence adjusts the current
drawing-frame posterior. Pen Up and Pen Down sequences record explicit human
physical confirmation alongside a current frame without claiming that this
camera view can infer pen height.

This is zero-order setup: it estimates where drawing can occur and establishes
the pen interaction needed to begin. It does not fit the affine drawing model,
does not teach scale from a ruler, and does not convert an operator-entered size
into motion authority.

### 2. Jog-response diagnostic: currently wired physical learning

When `Record Jog Observations` is enabled, one accepted jog produces one
`PhysicalJogObservation`:

```text
exact live frame and cap centroid
+ controller-owned start MPos
+ exactly one completed jog
+ controller-owned final MPos
+ strictly newer frame and cap centroid from the same camera configuration
```

Split membership is fixed as training or holdout before the observation is
recorded. At least two linearly independent training motions are required. The
fit is a through-origin 2x2 response matrix:

```text
cameraPixelDelta = responseMatrix * actualMachineDelta
```

Training and holdout RMS/maximum pixel residuals are reported separately. The
goal is to verify axis direction, local scale, cross-axis coupling, camera
provenance, and the end-to-end observation path. The matrix deliberately cannot
issue a command, invert itself for motion, replace a drawing model, persist, or
grant readiness.

### 3. Affine drawing model: implemented core, physical training still to wire

The drawing model predicts a field point from a machine point:

```text
predictedFieldPoint = affine(machinePoint) + fixedConstantToolCorrection
```

The repository has an immutable accepted snapshot, supervised point
observations, deterministic candidate fitting, explicit training/holdout
evaluation, threshold-based acceptance, versioned replacement, and a
checkpoint-only online accumulator. These contracts are covered by tests and
shown by the simulator. Physical jog observations can be converted through one
identified `FieldRegistration` into sealed physical training observations, but
the live app does not yet collect observed ink into an accepted drawing-model
workflow.

## Physical model-training procedure

The intended first physical training procedure is:

1. Complete the relevant Motion Preflight sequences for the unchanged camera,
   tool, paper, and controller session. This establishes the drawing-frame
   posterior and Pen Up/Pen Down interaction; it does not train the model.
2. Create an immutable accepted affine prior for that registered field.
3. Choose training and holdout locations before observing their outcomes.
   Membership never changes after collection.
4. At each location, execute one bounded, attributable action and collect exact
   controller position plus exact post-action visual evidence. For drawing-model
   labels, the observed target must come from the resulting ink, not merely the
   visible cap.
5. Convert the cited camera measurement to `FieldSpace` through the exact
   `FieldRegistration` identified by the evidence.
6. Fit the six affine coefficients using only training observations. The fitter
   requires at least three non-degenerate training points and at least one
   holdout point. It keeps the existing constant tool correction fixed.
7. Evaluate both the accepted baseline and candidate on training and holdout
   sets using RMS and maximum field-space error.
8. Reject the candidate unless it meets the configured maximum holdout RMS,
   maximum holdout error, and minimum positive holdout-RMS improvement.
9. If accepted, create a new monotonically increasing immutable version with
   the training IDs, holdout IDs, parent version, and an acceptance note.
10. Apply the new version only at a pen-up-between-strokes or run-complete
    checkpoint. Pin that version for the entire next pen-down stroke.
11. Continue collecting attributable outcomes from later strokes, preserving
    holdout isolation. Never refit or change the command mapping during an
    irreversible stroke.

The affine translation and a constant cap-to-tip or ink offset are not
separately identifiable from the same point pairs. That offset must remain fixed
until independent cap-versus-tip/ink evidence exists. Adding a spline, neural
model, backlash learner, or reinforcement-learning policy is justified only
after real held-out ink residuals show a repeatable error the affine model cannot
represent.

## Model-training goals

The immediate goals are measurable and deliberately narrow:

- establish that controller deltas and camera deltas are paired correctly;
- estimate axis orientation, local scale, and cross-axis coupling;
- predict observed ink position from commanded machine position;
- reduce held-out RMS and maximum drawing error for later strokes;
- preserve provenance and split isolation so apparent improvement is not data
  leakage;
- keep model changes outside pen-down execution and outside controller ownership;
- expose enough state that an operator can distinguish measured, inferred,
  simulated, accepted, and unimplemented claims.

The training goal is not autonomous exploration. The first useful learner is a
supervised geometric correction fitted from bounded actions whose outcomes are
visible and attributable. Continuous passive supervision becomes credible only
after isolated-line observation, ink extraction, and multi-stroke execution are
working on the attached machine.

## Immediate engineering target

The project is ready for physical preflight testing and for continued
controller/camera diagnostics. It is not yet ready to claim autonomous drawing
training. The next coherent slice is one camera-visible clear pose and one
bounded isolated line, followed by tool clear, exact-frame ink extraction, and
an intended-versus-observed residual. That slice supplies the first valid label
for drawing-model training and should precede portrait input or a more complex
model.
