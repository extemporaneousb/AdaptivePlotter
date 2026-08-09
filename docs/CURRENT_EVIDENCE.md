# AdaptivePlotter Current Evidence

Status: current evidence ledger

This document records what has actually been verified. Behavioral authority
lives in [Product Contract](PRODUCT_CONTRACT.md), architecture in
[Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md), and the operator
sequence in
[Discovery and Observed-Trial Protocol](DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md).

## Current software baseline

The current source implements:

- one signed local Swift application and singleton operator window;
- direct controller and camera ownership;
- one-window Learning Path with presentation-only navigation;
- typed Connect, Enable Motion, Start, choices, Cancel, contextual Stop,
  Restart, Redo, and Record Another Attempt;
- operator-selected Boundary directions, exact post-settlement evidence,
  per-side machine-space aggregates, atomic replacement, estimated center, and
  learned local coordinates;
- explicit current-camera registration evidence collection;
- visibility target, Clear pose, and one isolated-line observed trial;
- causal, nonphysical simulator parity;
- dependency-scoped artifact replacement and compatible aggregation;
- output-only announcements;
- signed-bundle construction, validation, and single-instance launch refusal.
- atomic durable accepted-Boundary checkpoints that remain quarantined until
  matching fresh controller context and MPos evidence is available;
- Stop-only exercise presentation while physical movement owns the operation.
- bounded camera-advised Boundary renewal tiers (40/20/10/5/2 mm) after an
  initial 10 mm probe, with conservative fallback and Stop-race suppression;

Adaptive Drawing remains Future. Future-facing drawing/model primitives are
present and tested, but no current app route promotes a model or performs
model-selected drawing.

## Automated evidence

The cleanup rebased onto commit 38fe494 has passed:

- make check — signed app construction and validation, launcher logic and
  validation, negative bundle validation, repository-contract checks, diff
  checks, and 313 tests;
- make strict-check — the same gate with complete Swift concurrency checking
  and warnings as errors, including 313 tests;
- focused merged-tree tests for controlled supervised-travel Stop, reproduced
  quantized center arrival, and out-of-tolerance center-only retry;
- three earlier consecutive controlled runs of the supervised-travel Stop test;
- Scripts/check_repository_contract.sh;
- git diff --check.

The accepted-artifact increment additionally passed a strict Swift build, three
focused checkpoint store/compatibility tests, one focused relaunch restoration
test, focused active Stop and Boundary Cancel tests, repository-contract checks,
and git diff checks. The long journey suite was skipped at the operator's
request; physical relaunch recovery remains unverified.

The camera-advised Boundary approach increment passed ordinary and strict Swift
builds, three focused tier/bounds/fallback tests, the focused Stop-during-planning
wire-suppression test, repository-contract checks, and git diff checks. Long
journey suites were not run. Live camera/controller timing remains unverified.

Automated and simulator evidence prove software behavior only.

## Recorded local environment

| Fact | Recorded value |
| --- | --- |
| Host | x86_64 MacBook Pro (MacBookPro15,1) |
| macOS | 15.7.8 |
| Swift | Apple Swift 6.1.2 from Command Line Tools |
| Camera | HD Pro Webcam C920 and built-in FaceTime camera; C920 observed at 1920×1080 |
| Controller | /dev/cu.usbserial-A10OF67O; grblHAL 1.1f on BlackBox X32 |
| Controller settings | X 40.18235 steps/mm, Y 45.09100 steps/mm; recorded X/Y maximum feed 500 mm/min; acceleration 10 mm/s² |
| Local signing | AdaptivePlotter Local Development available in the login keychain |

These are observations from this machine, not portable safety limits.

## Earlier attended physical evidence

Prior attended sessions recorded:

- passive controller exchanges in powered and unpowered comparisons; grblHAL
  did not expose motor-supply state;
- bounded X/Y jogs with Idle/final MPos and inverse returns;
- eight integrated 1 mm observations at 100 mm/min, split into four fitting and
  four reserved camera-displacement episodes with cap confidence 1.000;
- a diagnostic through-origin response matrix
  [[-1.6907, 0.1585], [-0.1581, -1.2680]] pixels/mm, with fitting RMS/max
  0.164/0.205 px and reserved RMS/max 0.337/0.551 px;
- three 1920×1080 C920 frames with exact manifest provenance;
- physically observed Pen Up and Pen Down; S760 produced a green contact dot,
  and final S40 left commanded state Up;
- one attended pre-fix Stage 3.2 run accepted four typed Boundary sides and
  derived center X -51.975 / Y -73.684. The controller settled at X -51.963 /
  Y -73.673, then retries alternated Y between -73.673 and -73.695 while X
  remained -51.963. The approximately 0.016 mm diagonal residual reproduced
  the former unreachable 0.010 mm arrival loop. No Stage 3.3 motion or ink
  followed.

These facts are bounded to their recorded sessions. They do not validate the
current integrated Learning Path or the newly landed Boundary aggregate and
simulator behavior.

## Not yet physically verified

The current integrated build still lacks attended verification of:

- existing-bundle activation and foreground/Dock behavior;
- output announcement completion before movement;
- absence of audio-input permission prompts in a clean interactive run;
- the full Pen Interaction sequence;
- one-cancel behavior and exact post-stop frames on the current build;
- the revised 0.05 mm center-arrival acceptance, center-only Retry Center
  Arrival presentation, and progression into Stage 3.3 on live hardware;
- durable accepted-Boundary restoration across a signed software relaunch;
- attended timing and stopping behavior of camera-advised coarse-to-fine
  Boundary renewal on live hardware;
- coarse-to-fine Clear search and repeatability;
- physical target contact/ROI, blank baseline, octagonal target, two-frame
  target observation, isolated line, new-ink observation, and comparison;
- Adaptive Drawing, which is intentionally unavailable.

## Next attended action

Inspect current processes, close any raw executable manually, run make run-app,
keep the cutoff reachable, and follow
[Attended Hardware Runbook](ATTENDED_HARDWARE_RUNBOOK.md). Report automated,
controller/camera, human-observed, and ink-observed evidence separately.
