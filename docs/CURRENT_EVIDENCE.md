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
- operator-selected signed-axis 50 or 10 mm Pen-Up moves for Clear-pose search
  and new-target-area relocation;
- visibility target, Clear pose, and one isolated-line observed trial;
- causal, nonphysical simulator parity;
- dependency-scoped artifact replacement and compatible aggregation;
- simple Reset From This Step and Reset All Learning controls with a compact
  affected-step summary and one Reset button; the underlying chronological
  reset retains stale-summary rejection, LIVE/SIMULATED isolation, and durable
  Boundary-checkpoint removal;
- output-only announcements;
- signed-bundle construction, validation, and single-instance launch refusal.
- atomic durable accepted-Boundary checkpoints that remain quarantined until
  matching fresh controller context and MPos evidence is available;
- Stop-only exercise presentation while physical movement owns the operation.
- software-validated V2 double-trace target planning and exclusive,
  cancellable, circular target-local foreground Vision with exact-frame
  magnification;
- a magenta search circle centred directly on the exact target-pose cap anchor
  with radius equal to half the frame's shorter dimension, circular Vision
  masking, and accepted cap-to-tip translation from the two-frame target
  centroid;
- color-independent paired-frame ink darkening for both the target and Stage 4,
  plus black simulated ink and a nonzero resolution-normalized simulated cap-to-
  tip truth exercised end to end;
- compact-target shape/ambiguity rejection, thick and optically collapsed black
  target fixtures, and full-HD one-pixel wobble recovery from circle-aware local
  background support;
- independently reset camera-advised Boundary renewal tiers (50/20/10/5/2 mm)
  for every direction after an initial 20 mm probe, with recoverable baseline
  establishment, conservative fallback, and Stop-race suppression;
- camera start/restart/source selection that leaves scene analysis stopped, plus
  newest-only 2 Hz analysis scoped to supervised Pen-Up Learning Path movement
  and stopped at owner settlement;
- capability-scoped preview publication holds for every expensive Vision path:
  raw capture continues, only the newest buffer survives, and finite explicit
  inspection releases both preview and computation ownership on settlement;
- fixed-camera optical alignment that searches 3 px and accepts at most 2 px of
  global translation for mount wobble, with new algorithm revisions and no
  change to controller MPos settlement authority;
- camera-frame observation isolated to the preview and 4 Hz camera heartbeat;
  settled Plotter, Motion, command, and Camera-panel text no longer inherit the
  per-frame refresh path;
- one quantization-aware 0.05 mm Euclidean controller-pose settlement policy
  shared by production pose comparisons;
- one Stage 3.3 public action that captures the exact target pose, runs bounded
  camera calibration when required, and builds a reviewable proposal while
  preserving separate explicit accept/reject authority;
- operation-scoped Stage 3.3 controller context with field-level semantic
  comparison, exact passive-probe IDs, typed failure/recovery presentation, and
  durable workflow telemetry alongside serialized raw machine-ledger facts;
- ordinary manual jog telemetry that records signed X/Y distance and feed under
  a `manualJog` operation rather than leaving later diagnosis to infer whether
  the movement belonged to calibration;
- required noninteractive presentation for a protocol-forced Boundary
  direction;

Adaptive Drawing remains Future. Future-facing drawing/model primitives are
present and tested, but no current app route promotes a model or performs
model-selected drawing.

## Automated evidence

The current software baseline has passed:

- make quick-test — 363 unit and component tests in an 11.763-second test run;
- make journey-test — 18 retained causal journey tests in a 39.535-second test
  run;
- make strict-check — signed app construction and validation, launcher logic and
  validation, negative bundle validation, all 381 tests, repository-contract
  checks, and diff checks under complete Swift concurrency checking with warnings
  as errors. The confirming full test run completed in 19.996 seconds;
- all retained causal journey cases ran inside the full parallel strict check,
  and standalone sequential make journey-test was also rerun for this change;
- Scripts/check_repository_contract.sh;
- git diff --check.

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
  followed;
- an attended 2026-08-09 pre-fix Stage 3.2 controller ledger recorded every
  Boundary jog at the controller maximum F500. X+ used mostly 10 mm renewals
  with one 40 mm renewal, while Y+ sustained multiple 40 mm renewals. This
  proves the requested feed and renewal pattern, not achieved physical speed;
- that 2026-08-09 run accepted all four typed sides, reached 3.3, and repeatedly
  failed camera calibration at exact sample 2. The requested X was -36.620 and
  final controller X was -36.633: a 0.013 mm residual rejected by the former
  0.010 mm threshold even though the configured X resolution is approximately
  0.0249 mm/step. The controller ended Idle and Pen Up, and the UI offered
  **Return to Captured Target Pose**. No observed-ink evidence was recorded.
- an attended 2026-08-11 diagnostic session reached Stage 3.3 with four accepted
  Boundary sides and center arrival still current. Automatic camera calibration
  repeatedly rejected a stale whole-context comparison: the earlier cached
  passive probe reported `M5/S0`, while fresh probes consistently reported the
  app-commanded Pen Up state `M3/S40`; build information, settings, offsets,
  controller state, and fresh MPos remained stable. The controller was Idle and
  Pen Up. The operator separately identified the recorded X− 100 mm Pen-Up jog
  as an intentional manual move to clear paper, not an automatic calibration
  leg. No new ink was attempted after the calibration failure.

These facts are bounded to their recorded sessions. The 2026-08-09 run is
attended controller/app evidence for the pre-fix build only; it does not
physically validate the shared 0.05 mm policy, the combined 3.3 action, or the
Boundary analysis scheduling changes.

## Not yet physically verified

The current integrated build still lacks attended verification of:

- the V2 double trace, ROI observation latency/cancellation, magnified live
  target presentation, and complete foreground-Vision interlock matrix;

- existing-bundle activation and foreground/Dock behavior;
- output announcement completion before movement, including word-based positive
  and negative X/Y Boundary wording;
- absence of audio-input permission prompts in a clean interactive run;
- the full Pen Interaction sequence;
- one-cancel behavior and exact post-stop frames on the current build;
- the shared 0.05 mm pose policy across center arrival, camera-calibration
  samples, captured/registered-pose returns, and every other production pose
  comparison on live hardware;
- the combined Stage 3.3 capture/calibrate/build action and separate proposal
  accept/reject presentation on live hardware;
- live confirmation that application-owned parser changes advance the new
  operation-scoped Stage 3.3 baseline, that true coordinate changes show the
  field-level recovery, and that the correlated workflow events are present in
  the durable session ledger;
- durable accepted-Boundary restoration across a signed software relaunch;
- post-fix attended timing and stopping behavior of camera-advised 20-to-50 mm
  coarse-to-fine Boundary renewal, including settled advisory cancellation and
  absence of stopped-state background analysis, on live hardware;
- attended UI latency, raw-capture continuity, and newest-frame preview resume
  while motion-scoped or finite explicit Vision holds preview publication;
- coarse-to-fine Clear search and repeatability;
- physical cap anchor/search circle, blank baseline, octagonal target, two-frame
  target observation, cap-to-tip translation, isolated line, new-ink
  observation, and comparison;
- Adaptive Drawing, which is intentionally unavailable.

## Next attended action

Inspect current processes, close any raw executable manually, run make run-app,
keep the cutoff reachable, and follow
[Attended Hardware Runbook](ATTENDED_HARDWARE_RUNBOOK.md). Report automated,
controller/camera, human-observed, and ink-observed evidence separately.
