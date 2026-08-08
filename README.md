# AdaptivePlotter

AdaptivePlotter is a native macOS Swift application for a short
controller-camera-draw-observe loop on one attached plotter. It keeps controller
authority, camera evidence, human observation, inferred geometry, and observed
ink separate.

The product is intentionally local and narrow:

- one signed application bundle and one native process;
- one persistent controller owner and one camera owner;
- a camera-first workbench with typed, bounded actions;
- exact frame and camera-configuration provenance;
- no arbitrary controller text, remote backend, second process, or hidden
  compatibility workflow;
- no automatic resend, resume, or redraw after an uncertain physical outcome.

## Operator journey

The persistent **Learning Path** organizes the current work:

1. **Connect**
2. **Enable Motion**
3. **Human-Guided Discovery**
4. **Observed Drawing Trials**
5. **Adaptive Drawing**

This numbering is ergonomic presentation, not a machine-authority ladder.
Connect and Enable Motion are current-session mechanical prerequisites. Learning
status never becomes a global motion gate, and ordinary manual jogs do not
depend on learning completion. Each operation requires only the direct facts and
evidence it consumes.

Human-Guided Discovery is ordered as:

1. **3.1 Pen Interaction** — observe Up, authorize and observe Down, retract,
   and finish with an explicit human confirmation of Up.
2. **3.2 Boundary Discovery** — choose a direction, start one bounded jog, use
   the contextual Stop, settle at controller Idle with final MPos, capture a
   strictly newer exact frame, and update that side observation.
3. **3.3 Clear-View Discovery** — label an exact frame Blocked, Partial, or
   Clear and accept one repeatable Clear pose.

Pen Interaction plus one relevant boundary is sufficient to advance to
Clear-View Discovery. The other directions remain optional observations.

Observed Drawing Trials are ordered as:

1. **4.1 Capture Clean Reference**
2. **4.2 Choose Line Start**
3. **4.3 Create Anchor Mark**
4. **4.4 Draw Isolated Line**
5. **4.5 Clear Tool and Observe Ink**
6. **4.6 Compare Intended and Observed Geometry**

Only observed ink proves that a mark exists. Adaptive Drawing remains visibly
Future until multi-stroke observation and checkpoint learning are implemented.

Buttons are authoritative for questions, labels, progression, assessment, and
Stop. Spoken movement announcements are output-only and advisory. They are
serialized and completion-aware; a bounded speech-output failure never grants
authority and never makes the visible buttons unusable. No audio-input or
speech-recognition subsystem is part of the product.

## Direct mechanical authority

The internal runtime retains its precise `MotionGuard` type, but the operator
surface says **Enable Motion**, **Motion Enabled**, or **Motion Disabled**.
There is no second arming control.

Typed motion continues to require the applicable direct facts:

- one explicitly selected, responsive controller session;
- current internal motion authorization;
- recognized non-alarm controller state and Idle admission;
- no relevant asserted X/Y limit pin;
- known MPos where the requested operation requires it;
- controller-reported feed capability;
- the appropriate commanded pen state;
- one-operation ownership;
- no sticky ambiguity.

Disconnect and shutdown invalidate current authorization. The application does
not home, clear alarms, unlock, reset, write firmware settings, accept entered
workspace bounds, or use learned geometry or model confidence to admit manual
motion.

Controller `ok` means acceptance, not completion. A jog completes only after
bounded polling reaches fresh Idle with final MPos. An uncertain outcome becomes
sticky and is never automatically resent.

## Stop semantics

The workbench toolbar owns one visible contextual **Stop** while a typed software
operation is cancellable. It is not a physical emergency stop; the physical
power cutoff remains the operator's safety boundary.

During Boundary Discovery, Stop has one deterministic order:

1. record the contextual operator Stop event;
2. emit exactly one GRBL Jog Cancel byte;
3. await the original jog owner through Idle and final MPos;
4. capture a strictly newer exact camera frame;
5. measure and update the relevant boundary observation;
6. advance the visible sequence.

The same toolbar surface cancels a manual jog without creating boundary
evidence. Drawing cancellation retains the controller owner's Pen Up behavior;
an ambiguous outcome causes no follow-on command.

## Travel feed selection

Successful passive controller inspection exposes the reported X and Y maximum
feeds as read-only runtime facts. Non-drawing, Pen Up discovery and travel select:

- the X ceiling for X-only motion;
- the Y ceiling for Y-only motion;
- the minimum participating-axis ceiling for multi-axis motion.

If that capability is unavailable, the existing positive request feed remains
the fallback; its absence does not create a new learning prerequisite. The app
does not write firmware settings. Pen Down drawing feed remains an ink-quality
choice and is not automatically increased.

## Camera and evidence

`CameraCapture` owns AVFoundation discovery, selection, authorization, capture,
and shutdown. `latestLiveCameraFrame` is the live heartbeat; it is deliberately
separate from an analyzed or held display frame. `StampedFrame`, `FrameID`, and
`CameraConfigurationID` bind pixels, measurements, and overlays to exact
provenance.

The evidence boundaries are explicit:

- controller acceptance proves only that the command was accepted;
- Idle and final MPos prove controller-side settlement;
- a camera frame proves captured pixels at its recorded provenance;
- vision geometry is an inference from those pixels;
- a button label records a human observation;
- observed ink is the only proof of a drawn mark.

SIMULATED frames share the renderer but are labeled nonphysical and cannot reach
machine actions or satisfy physical evidence.

## Build, test, and launch

Requirements: macOS 14 or later and Swift 6.1 or later.

```sh
make build
make test
make check
make strict-check
```

For supported local application launch:

```sh
make run-app
```

`make run-app` builds the current `.app`, prefers the stable
`AdaptivePlotter Local Development` signing identity (or the explicit
`ADAPTIVEPLOTTER_CODESIGN_IDENTITY`), validates the bundle and camera-only
privacy declaration, then launches through LaunchServices.

The launcher accepts only `com.bullard.AdaptivePlotter` at the expected bundle
path. It activates one already-running exact bundled instance instead of
creating another and reports its PID. It refuses a same-name raw SwiftPM
executable or any conflicting instance with PID and path, and never kills a
user-owned process. A rebuilt bundle does not replace the bits already loaded by
an existing process.

Do not use `swift run AdaptivePlotter` for camera, controller, or physical
validation. Direct executable launch gives the wrong application identity and
can create competing camera/serial owners.

## Documentation map

- [Binding amendments](docs/FEASIBILITY_REVIEW_AND_BINDING_AMENDMENTS.md)
  define the non-negotiable authority and evidence rules.
- [Project scope and model learning](docs/PROJECT_SCOPE_AND_MODEL_TRAINING.md)
  defines the five-stage product scope and technically precise model terms.
- [Architecture](docs/SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md) defines module and
  owner boundaries.
- [Direct implementation plan](docs/SWIFT_ADAPTIVE_PLOTTER_SEQUENTIAL_REBUILD.md)
  records implemented and remaining delivery order.
- [Current implementation status](docs/implementation/CURRENT_IMPLEMENTATION_STATUS.md)
  separates automated, camera, controller, and physical evidence.
- [Physical session procedure](docs/implementation/FIRST_HARDWARE_SESSION.md)
  is the operator checklist for the next attended hardware pass.

## Development contract

Use the repository-local AdaptivePlotter skill and the Blackdog workflow in
`AGENTS.md`. Implementation belongs in the task workspace returned by
`blackdog task begin`; the recorded target branch is authoritative.

Normal integrated validation is:

```sh
make build
make test
make check
make strict-check
git diff --check
```

Physical claims require an attended physical run with the cutoff reachable.
Builds, tests, simulator output, controller `ok`, Idle, UI state, or camera
preview must never be reported as physical movement or ink proof.

The legacy `/Users/bullard/Projects/Plotter` repository is forensic product
evidence only. Do not port its bridges, routes, DTOs, lifecycle ceremonies,
compatibility layers, or tests.
