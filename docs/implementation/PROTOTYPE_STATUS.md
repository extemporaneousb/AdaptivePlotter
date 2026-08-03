# Prototype Status

Status date: 2026-08-02  
Authority: software evidence only; no physical execution authority

## Bottom line

The repository now has a coherent native Swift software prototype spanning the
Phase 2 foundations, core Phase 3 domain contracts, and narrow offline pieces
needed for the Phase 4/5 path. It builds as one SwiftPM executable process. Its
operator workspace can replay deterministic recorded facts, discover serial
devices, and request exactly one fixed passive controller probe through a
durable SQLite ledger.

It is not yet a physical drawing prototype. Motion and pen arms are
unavailable/off in the public runtime types and UI. There is no arbitrary
G-code surface. There is no live camera capture, `RunInterpreter` drawing-plan
loop, pen-down execution, physical clearance proof, or accepted ink/model
evidence.

The current `make check` receipt on the recorded host passes the strict Swift 6
build, all 110 tests, repository forbidden-surface scan, seven-fixture manifest
validation, Swift package description, and `git diff --check`. It does not
include a GUI launch or any attached device.

## Recorded host and toolchain

Read-only inspection on 2026-08-02 found:

| Fact | Recorded value | Meaning |
| --- | --- | --- |
| Host | `x86_64` MacBook Pro (`MacBookPro15,1`, 8-core Core i9, 16 GiB) | This is the only supported host. |
| macOS | 15.7.8, build 24G824 | Current local operating system. |
| Swift | Apple Swift 6.1.2, target `x86_64-apple-macosx15.0` | Sufficient for the current Swift 6 language mode and strict-concurrency build. |
| Developer directory | `/Library/Developer/CommandLineTools` | Supported local compiler and SDK source. |
| Camera inventory | FaceTime HD Camera (Built-in) | Device presence only; no app capture or TCC claim. |
| Serial inventory | `/dev/cu.BLTH`, `/dev/cu.Bluetooth-Incoming-Port` only | No apparent plotter/controller serial device was connected. |
| SQLite | System SQLite library builds; `/usr/bin/sqlite3` 3.43.2 is present | The ledger compiles and can be inspected locally. |
| `pkg-config` | Not installed | Not required by the successful local SDK-backed build, despite being an optional package-provider path. |

No cross-machine generalization is required. This receipt still does not prove
camera access, USB serial access, or actual controller behavior on this host.

## Delivered and software-verified

### Model boundary

- Typed `FieldSpace`, `MachineSpace`, `CameraPixelSpace`, `CameraPlaneSpace`,
  and `ToolSpace` geometry with finite-value and bounds checks.
- Versioned canonical encoding and SHA-256 identities for retained domain
  values.
- Immutable polyline `DrawingProgram`, affine `FieldRegistration` with
  independent held-out points, immutable affine `AdaptiveDrawingModel`, a
  distinct `ModelCandidate`, and forward-checked affine inversion.
- Closed `ExecutionInstruction` vocabulary and finite `ExecutionPlan`
  validation, including baseline-before-draw and lift/clear/fresh-frame/inspect
  ordering.
- Literal commanded, controller-completed, ink-disposition, and ambiguity
  facts; typed authority, blockers, checkpoint decisions, and recorded replay.
- Phase-4 clearance values and pure camera-space intersection validation for an
  observation region, conservative armature envelope, clear pose, and bounded
  path. These are geometry contracts, not measured clearance evidence.

### Runtime boundary

- A grbl/grblHAL-tolerant line parser retaining raw bytes and unknown fields.
- Simulated and transcript-replay links plus IOKit `/dev/cu.*` discovery and a
  BSD `termios` link fixed at 115200 baud.
- `MachineController` exposes only the closed passive sequence `$I`, `$G`, `?`,
  `$$`, `$#`; it stops at the first timeout, transport/storage failure,
  controller error, alarm, missing query-specific report, or bounded-response
  overflow. Each query has a two-second absolute deadline and a 64 KiB/256-chunk
  receive budget.
- `RunLedger` records ordered events and prepare/write/outcome command
  lifecycles in SQLite WAL mode with `synchronous=FULL`, hashes payloads, checks
  integrity, and can produce a consistent database backup. Probe start/finish,
  parsed outcomes/blockers, and interpreter authority transitions are versioned
  ledger events; raw TX/RX bytes remain authoritative.
- A narrow `RunInterpreter` shell serializes the passive transition, rejects
  stale transition results, blocks on unresolved prepared/written command
  intent after reopen, and performs recorded replay. It cannot execute motion,
  pen, or drawing plans.
- Immutable owned frame bytes, exact frame/configuration identities, a pure
  fresh/stable recorded-frame selector, and a narrow exact-frame `VisionWorker`
  for statistics, green-pixel, and dark-pixel measurements.

The frame and pixel-measurement code is an offline/runtime primitive only. Its
thresholds are not physically validated ink or occlusion algorithms.

### Application boundary

- One SwiftUI operator workspace renders a deterministic offline recorded
  replay, literal execution frontiers, authority blockers, and simulated
  logical/predicted/observed/residual overlays.
- The canvas labels simulated observations as simulated and never grants
  physical authority.
- Serial-device refresh and explicit device selection are visible. Requesting a
  passive probe creates a unique ledger under
  `~/Library/Application Support/AdaptivePlotter/PassiveRuns/`, constructs the
  native BSD controller, routes the fixed sequence through `RunInterpreter`,
  returns the interpreter authority-at-completion receipt and exact ledger path,
  then immediately disconnects and closes the ledger. The receipt is historical,
  not current connection authority.
- Each app process permits one passive attempt; refresh and selection freeze
  when it starts, stale results are cleared, and a new attempt requires an explicit
  app restart/new operator session.
- Before a new ledger or serial link is created, the app read-only scans prior
  passive ledgers. Empty, corrupt, malformed, unfinished, unresolved, unreadable,
  or unsafe evidence blocks visibly; the scanner neither replays nor mutates a
  prior command intent.
- The product surface contains no motion, pen, unlock, home, settings-write, or
  reset action.

## Compiled but physically unverified

The following code exists and compiles, but has not touched the actual machine:

- IOKit serial discovery against a controller USB device;
- raw 115200 BSD serial open/read/write behavior and permissions;
- parsing of the actual controller's current replies;
- exact passive-query timing, termination, timeout, and disconnect behavior;
- app-owned persistence of a real passive session;
- controller identity, firmware, settings, pins, alarm state, coordinate
  offsets, travel, or homing configuration.

Historical fixtures exercise parser and failure behavior but cannot establish
any of these physical facts.

## Deliberately absent or physically unverified

- A stable local `.app` wrapper, which is needed only if a local macOS API
  demonstrates that the SwiftPM executable lacks sufficient bundle identity.
- AVFoundation `CameraCapture`, camera TCC permission, live frame retention, or
  camera/configuration invalidation.
- Physical `FieldRegistration`, armature silhouette measurement, verified
  `ClearancePose`, or executed `ClearancePath`.
- Motion and pen arming, jog/travel, feed hold, reset, unlock, home, firmware
  setting changes, servo commands, or pen-state verification.
- A live `RunInterpreter` executing motion, pen, or drawing plans.
- Physical pen profile, pen-down authority, actual ink observation,
  correspondence, topology/coverage acceptance, drawing tolerance, adaptive
  model fitting/acceptance/promotion, or automatic replanning.
- A local live-camera/TCC receipt or an actual-controller serial receipt.

The next physical action is therefore the passive-only session in
[First Hardware Session](FIRST_HARDWARE_SESSION.md) when the controller is
connected and placed in the documented harmless state. No missing release or
toolchain infrastructure blocks software work. Phase 4 clearance/viewability is
the first motion-authority check. Pen-down remains forbidden until that check
passes and Phase 5 separately grants one bounded isolated-training-probe
authority.
