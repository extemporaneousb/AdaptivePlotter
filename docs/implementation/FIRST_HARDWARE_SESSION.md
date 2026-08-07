# First Hardware Session

Status: powered 1 mm X/Y round trips and stationary green-dot contact verified
Scope: camera analysis, repeatable passive interrogation, typed pen control, and 1 mm round trips

## Purpose

Use the native app to confirm that this Mac can show and analyze the plotter
camera, open the actual controller, parse its current
identity/status/settings/offsets, command the proven pen mechanism, and complete
deliberately bounded 1 mm pen-up round trips.

The passive probe sends only:

```text
$I
$G
?
$$
$#
```

The machine-affecting surfaces are a closed typed relative GRBL jog and typed
Pen Up/Pen Down. The pen profile is fixed to the commands proven on this
mechanism: `M3 S40` up, `M3 S760` down, and `G4 P0.3` settle. No UI field can
supply raw G-code or servo values. Pen operations require a fresh recognized
Idle/non-alarm state, explicit Motion Guard activation, and clear X/Y end-stop
pins. Jog remains unavailable until Pen Up was acknowledged and settled. These
are controller-commanded states, not camera proof of servo pose.

## Before connecting

1. Run:

   ```bash
   make check
   make app
   ```

2. Close other serial terminals or legacy Plotter processes.
3. Put the mechanism in a harmless boot condition. Prefer motor/pen power
   isolated if the controller can enumerate without it. Otherwise remove or
   restrain the pen and keep the physical power cutoff reachable.

That is the complete local prerequisite list. Full Xcode, Developer ID,
distribution signing, entitlements, archival storage preparation, prior-run
inspection, and evidence packaging are not required. `make app` prefers a valid
`AdaptivePlotter Local Development` identity and reports its signing mode. This
Mac currently has no valid identity: the automated self-signed import reached
macOS's interactive trust approval and the incomplete key was removed. The
current fallback is ad-hoc, so its designated requirement contains the changing
executable CDHash until that one-time approval is completed with the operator.

## Run the probe

1. Record the before state:

   ```bash
   ls -l /dev/cu.*
   ```

2. Connect controller USB and apply only the power needed for enumeration.
   Unexpected mechanism or servo movement means remove power and inspect the
   hardware setup.
3. Run `ls -l /dev/cu.*` again and identify the new controller path. Do not use
   an unrelated Bluetooth path.
4. Launch:

   ```bash
   make run-app
   ```

   This compiles the checked-in AppKit launcher and uses `NSWorkspace` to ask
   LaunchServices for a new instance of the exact
   `.build/AdaptivePlotter.app` bundle. The launcher waits for activation to
   succeed or fail, then exits while the application remains running. It does
   not invoke `/usr/bin/open` or the macOS `open` command. LaunchServices makes
   the prompt attributable to the locally signed
   `com.bullard.AdaptivePlotter` application instead of naming the terminal or
   Codex process that invoked `make`. The bound Info.plist supplies the camera
   usage description. In current ad-hoc mode a rebuild changes the CDHash and
   may trigger another decision. Do not execute `.build/debug/AdaptivePlotter` or the app's
   `Contents/MacOS/AdaptivePlotter` binary directly for camera acceptance.

5. Choose **Refresh Serial Devices**, select the controller path, and choose
   **Connect & Inspect Controller**. Once connected, the same action is labeled
   **Refresh Controller State**.
6. Confirm that the UI reports the five exchanges or gives a concrete error.
7. Repeat the probe in the same app launch if useful. A failed probe is not a
   one-shot event and old journal files do not block retry.

## Verify the camera

1. When repeating first-permission acceptance, reset only AdaptivePlotter's
   camera decision before launch:

   ```bash
   tccutil reset Camera com.bullard.AdaptivePlotter
   ```

   Do not reset or grant camera access for ChatGPT or Codex. The permission
   prompt must name **AdaptivePlotter**. If it names another responsible
   application, deny it, stop the exact AdaptivePlotter process, and diagnose
   the launch path before continuing.
2. Leave the action surface in **LIVE** mode. At startup the app discovers
   cameras, prefers **HD Pro Webcam C920**, and starts it when that choice is
   unambiguous. Manual refresh/select/start remains available.
3. Allow the prompt only when it names **AdaptivePlotter**. A pending prompt
   produces no frames and no sample directory; that is an external permission
   boundary, not camera evidence.
4. Confirm that frame sequence advances and frame age remains current.
5. Use the compact top bar to open **Camera** and **Overlays**. Confirm they dock
   on the right, reserve space, and leave the complete camera surface visible.
   Collapse, close, and restore them; **Hide All** must return the full content
   width to the camera.
6. Choose **Analyze Frame**. Confirm preview holds one exact frame and shows one
   cap box/centroid, blue measured top/right side lines, a dashed inferred
   drawing frame, and a dashed inferred armature envelope. Toggle Pen cap,
   Measured frame sides, Drawing frame estimate, and Armature independently. The
   panel reports support, residual, confidence, and evidence source rather than
   a mm scale. Choose **Resume Preview**.
7. Enable **Auto Analyze** first at 2 Hz and then 5 Hz. Confirm frame sequence
   advances, analyzed count rises, frame age stays current, and superseded count
   may rise without an unbounded backlog. Record the displayed delivery,
   preview/exact, analyzed/superseded, and latency values; do not claim a usable
   10 Hz rate until it is observed on this Mac.
8. Choose **Save Snapshot** and confirm the UI reports a new PNG/manifest
   directory under `CameraSamples`.
9. Stop and restart capture; confirm a new camera configuration is used and
   frames resume.
10. Switch to **SIMULATED**. Toggle **PRIOR MISMATCH** and **ACCEPTED TRAINING**;
   confirm predicted/observed residuals collapse for the accepted affine model,
   and that the surface remains labeled not physical evidence. Switch back to
   **LIVE** and confirm source labels are exact
   and no overlay from the other source/configuration remains visible.
11. Open **Learning** and confirm it is a direct current-session diagnostic, not
    a sequence or readiness flow. With **Record Jog Observations** off, ordinary
    LIVE jogging must remain camera-independent. With it on, select the fixed
    training/holdout membership for the next jog and confirm the panel reports
    the exact paired result, sample counts, response matrix, and separate
    residuals under `DIAGNOSTIC — NOT MOTION AUTHORITY`. **Clear Samples** must
    discard only the current diagnostic set. SIMULATED mode must not issue a
    physical jog or pen command.
12. Confirm that the first successful live start created three PNGs plus
   `manifest.json` beneath:

   ```text
   ~/Library/Application Support/AdaptivePlotter/CameraSamples/
   ```

   The manifest binds camera identity, configuration, frame sequence/time,
   dimensions, pixel layout, and raw-frame SHA-256. Treat the PNGs as offline
   vision-development samples only. They are not calibration or observed-ink
   evidence.

The first accepted set was recorded at 1920x1080 from the C920. All three PNGs
reconstruct the manifest's exact BGRA SHA-256. The green cap is a stable dominant
connected component near camera pixel (1094.05, 375.76), while a small green
controller light is a separate distractor. The blue-taped top and right paper
edges are strong line priors; the attached rulers, their markings, magnets, and
machine shadows are distractors rather than scale evidence. See
[Prototype Status](PROTOTYPE_STATUS.md#current-c920-scene-priors) for the measured
single-scene priors.

## Current local priors and observed controller facts

- Operator description: about 250 mm usable X by 100 mm usable Y, with the
  controller-reported zero near physical center. One millimetre is the intended
  smallest routine UI move. These are priors, not proven limits.
- The passive probe reports distinct scale settings: `$100=40.18235` X
  steps/mm and `$101=45.09100` Y steps/mm.
- It also reports `$110=$111=500` mm/min and `$120=$121=10` mm/s^2. The
  firmware `$130/$131` travel values do not agree with the operator's physical
  estimate and must not be promoted to local safety bounds.
- The current motion panel starts at independent 1 mm X/Y steps and 100 mm/min.
  The earlier per-command cap and operator-entered X/Y envelope have been
  removed; Motion Preflight now establishes boundary and pen evidence.
- Completed physical tests included 0.1 mm and 1 mm X jogs, 10 mm X jogs at 60
  mm/min, two -5 mm Y jogs at 60 mm/min, and -10 mm X at 400 mm/min.
- A following +10 mm X request at 900 mm/min timed out while the controller
  still reported `Jog` and physical X had advanced. The runtime correctly made
  that outcome sticky-ambiguous. That running build's deadline ignored the
  controller's 500 mm/min cap and 10 mm/s^2 acceleration. Current source parses
  those settings and applies triangular/trapezoidal motion timing without using
  firmware travel as a bound. The fresh verification below supersedes that
  ambiguous session for new bounded operations; it does not reinterpret or
  clear the earlier command outcome.

### 2026-08-05 powered deadline recheck

- The signed app opened `/dev/cu.usbserial-A10OF67O` in a new session. The
  passive probe reported Idle, no asserted X/Y pins, and MPos X 29.192 /
  Y -10.002.
- The operator directly confirmed the pen was physically up. The app then sent
  the fixed typed Pen Up command and settle dwell once; both were acknowledged
  and the app recorded commanded state Up. Because the pen began up, this proves
  a clean command path, not observable servo travel from a lowered pose.
- Applied local limits were X 27.692...30.692, Y -11.502...-8.502, a 1 mm
  per-command cap, and 100 mm/min maximum feed.
- The X request completed Idle at X 30.212 / Y -10.002. The 1.020 mm reported
  delta is one-step quantization at the probed `$100=40.18235` steps/mm. The
  explicit inverse completed at the exact starting MPos.
- The Y request completed Idle at X 29.192 / Y -9.004. The 0.998 mm reported
  delta matches quantization at `$101=45.09100` steps/mm. Its explicit inverse
  completed at X 29.192 / Y -10.002.
- All four jogs were accepted, reached observed Idle before their current
  controller-aware deadlines, and ended non-ambiguous with no alarm, asserted
  limit, Hold, disconnect, or automatic resend.
- Pen Down was not issued. It remains a separate physical step requiring
  explicit operator authorization over replaceable paper.

### 2026-08-05 controller-evidence and camera-displacement recheck

- A fresh passive probe again reported Idle, no asserted X/Y pins, and MPos
  X 29.192 / Y -10.002. The operator again directly confirmed the pen was up.
- Conservative session-local bounds were only ±2 mm around that MPos, with a
  1 mm per-command cap and 30 mm/min maximum feed.
- X completed at 30.212 / -10.002 (+1.020 mm) and returned exactly to
  29.192 / -10.002 (-1.020 mm). Y then completed at 29.192 / -9.004
  (+0.998 mm) and returned exactly to 29.192 / -10.002 (-0.998 mm).
- All four operations used the production typed controller path, included exact
  controller-owned start/final MPos and monotonic sample times, reached Idle,
  and produced no alarm, asserted limit, Hold, disconnect, ambiguity, or resend.
- Separately bracketed C920 PNG samples processed by the production cap detector
  showed displacement and return on both axes. The camera was restarted between
  those samples, so their configuration IDs intentionally prevent them from
  being admitted as one integrated physical-observation episode.
- The camera cannot see or prove the pen-up/pen-down servo transition from this
  view. Pen state in this check came from direct operator confirmation plus the
  acknowledged typed Pen Up command; Pen Down was not issued.

### 2026-08-06 motor-power observability check

- The operator switched only the plotter/motor supply off while leaving USB
  attached. The exact AdaptivePlotter process holding the serial device was
  resolved and terminated before the coordinator reclaimed the port.
- The identical passive query set still completed without blockers. The device
  identified as the same grblHAL BlackBox X32 and reported `Idle`, MPos
  X 0.000 / Y 0.000, no asserted X/Y pins, `Bf:100,1023`, `FS:0,0`, and `H:0`.
- Those controller-observable facts matched the powered baseline. USB response,
  `Idle`, MPos, and `H:0` do not establish that motor supply current is present.
- AdaptivePlotter therefore reports controller-link responsiveness and
  motion-command permission separately, and says motor power is not reported
  by the controller. No motion or pen command was sent during this comparison.

### 2026-08-06 stationary pen-contact check

- With power restored, the passive query set reported the same BlackBox X32,
  recognized `Idle`, MPos X 0.000 / Y 0.000, and no asserted X/Y pins.
- The typed `M3 S40` raise plus `G4 P0.3` completed first, establishing a fresh
  controller-commanded Up state without ambiguity.
- A stationary typed down at the historical `S720` value moved the mechanism,
  but direct operator inspection after raising found no green dot on the white
  paper. Controller acknowledgement was correctly not treated as ink evidence.
- One explicit conservative local adjustment changed the closed down value to
  `S760`; there was no automatic sweep or operator-supplied G-code surface.
- The stationary `M3 S760` command completed within conservative ±1 mm local
  bounds without any X/Y command. After the immediate `M3 S40` raise, the
  operator inspected the paper and confirmed a green contact dot.
- Every actuation and settle was acknowledged with no alarm, asserted limit,
  disconnect, sticky ambiguity, or automatic resend. The final commanded state
  was Up. Physical contact came from direct observation; this camera view still
  cannot observe pen height.

## Verify one bounded jog

1. Use the passive probe to confirm the attached controller supports the closed
   `$J=G91 G21 ...` jog form, is Idle/non-alarm, has no asserted X/Y limit, and
   reports current MPos.
2. Press **Activate Motion** for the connected session. Do not enter coordinates,
   a travel envelope, or a maximum-jog value; those controls do not exist.
3. Keep the physical cutoff reachable and choose **COMMAND PEN UP**. Confirm the
   controller acknowledges both the fixed up command and settle dwell, and
   directly observe that the pen is clear. Stop if command and mechanism disagree.
4. Send a 1 mm X jog at 100 mm/min. Wait for `ok` acceptance followed
   by observed Idle completion and the expected final MPos.
5. Send the exact inverse X jog and verify return. Then repeat the same 1 mm
   round trip on Y only if X was unambiguous.

Stop immediately on unexpected motion, alarm, asserted limit, disconnect, Hold,
unexpected controller state, or ambiguous outcome. Do not Home, unlock/clear an
alarm, reset, write settings, or Resume.

## Verify stationary pen actuation

Do this only after both 1 mm round trips return unambiguously and the tool is in
a harmless camera-visible location over replaceable paper.

1. Choose **COMMAND PEN DOWN** once. Directly observe whether the pen reaches paper after
   the acknowledged 0.3 s settle. Controller acknowledgement alone is not proof.
2. Choose **COMMAND PEN UP** once. Directly observe clearance.
3. Stop after that down/up pair. Do not jog while down and do not repeat a command
   after any timeout, disconnect, reset greeting, rejection, or physical mismatch.

This session establishes actuator behavior only. A stationary dot is ink
evidence if visible, but it is not an XY model observation or drawing success.

Each query has a two-second absolute deadline and bounded input size. Those
limits prevent a stuck or noisy serial connection; they are not a broader
development gate.

## What to look at

For a successful probe, inspect:

- selected BSD device path;
- controller identity/build response;
- parser state;
- current `<...>` status, alarm, and pin fields;
- settings and coordinate-offset replies;
- exact error when any query fails.

When local storage is available, the app creates a small SQLite session log
under:

```text
~/Library/Application Support/AdaptivePlotter/MachineSessions/
```

One file follows the selected-device machine session and may contain repeated
probes plus jog diagnostics. The log is optional current-session data. A
logging failure does not stop a probe or jog. Manual SQLite verification,
database hashing, WAL export, immutable evidence packages, and preservation of
every old run are not required.

## Stop this attempt when

- the controller path is absent or genuinely ambiguous;
- another process owns the port;
- the controller reports an alarm or asserted limit that makes the physical
  state unclear;
- the serial link disconnects or returns an unknown command outcome;
- the mechanism moves unexpectedly during this passive procedure.

Correct the concrete issue and retry. Do not unlock, home, reset, or write
settings merely to force the passive probe to pass.

## Next hardware step

After camera analysis, both jog round trips, and the stationary pen down/up pair
pass, establish one camera-visible observation region and one pen-up clear pose.
The next implementation/physical slice is one bounded isolated line: Pen Up,
travel to the start, Pen Down, draw one short segment with one pinned accepted
model, Pen Up, clear the tool, capture a fresh exact frame, detect actual ink,
and show intended/predicted/observed residuals. Do not accept cap motion,
controller `ok`, or the simulator as ink authority.
