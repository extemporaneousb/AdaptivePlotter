# First Hardware Session

Status: ready for live-camera and bounded-jog verification
Scope: direct camera capture, repeatable passive interrogation, and one pen-up round trip

## Purpose

Use the native app to confirm that this Mac can show the plotter camera, open the
actual controller, parse its current identity/status/settings/offsets, and
complete one deliberately bounded low-speed pen-up round trip.

The passive probe sends only:

```text
$I
$G
?
$$
$#
```

The only machine-affecting command is a closed typed relative GRBL jog. It is
unavailable until the controller reports recognized Idle state and MPos, X/Y
limits are clear, explicit local bounds/feed/distance limits are applied, and
the operator directly confirms that the pen is physically up. There is no pen
actuation command.

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

That is the complete local prerequisite list. Full Xcode, Developer ID or
distribution signing, entitlements, archival storage preparation, prior-run
inspection, and evidence packaging are not required. `make app` applies the
ad-hoc signature needed to bind the bundle's Info.plist and make the permission
prompt name AdaptivePlotter. It does not provide stable TCC identity across
rebuilds: the designated requirement contains the executable CDHash, and this
Mac currently has no valid code-signing identity.

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
   the prompt attributable to the ad-hoc-signed
   `com.bullard.AdaptivePlotter` application instead of naming the terminal or
   Codex process that invoked `make`. The bound Info.plist supplies the camera
   usage description. A rebuild changes the CDHash and may trigger another
   decision. Do not execute `.build/debug/AdaptivePlotter` or the app's
   `Contents/MacOS/AdaptivePlotter` binary directly for camera acceptance.

5. Choose **Refresh Serial Devices**, select the controller path, and choose
   **Request Passive Probe**.
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
5. Stop and restart capture; confirm a new camera configuration is used and
   frames resume.
6. Switch to **SIMULATED** and back to **LIVE**; confirm source labels are exact
   and no overlay from the other source/configuration remains visible.
7. Confirm that the first successful live start created three PNGs plus
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
- The motion panel therefore starts at independent 1 mm X/Y steps, 100 mm/min,
  a 5 mm per-command cap, and an explicitly reviewable X -100...100 / Y
  -40...40 envelope around the observed session-start zero.
- Completed physical tests included 0.1 mm and 1 mm X jogs, 10 mm X jogs at 60
  mm/min, two -5 mm Y jogs at 60 mm/min, and -10 mm X at 400 mm/min.
- A following +10 mm X request at 900 mm/min timed out while the controller
  still reported `Jog` and physical X had advanced. The runtime correctly made
  that outcome sticky-ambiguous. That running build's deadline ignored the
  controller's 500 mm/min cap and 10 mm/s^2 acceleration. Current source parses
  those settings and applies triangular/trapezoidal motion timing without using
  firmware travel as a bound. Establish a fresh session and physically
  re-verify the correction; do not continue motion from the ambiguous session.

## Verify one bounded jog

1. Use the passive probe to confirm the attached controller supports the closed
   `$J=G91 G21 ...` jog form, is Idle/non-alarm, has no asserted X/Y limit, and
   reports current MPos.
2. Enter a conservative local X/Y envelope around that MPos, plus a very small
   maximum distance and low maximum feed, then apply the typed limits.
3. Directly inspect the mechanism and choose **Confirm Pen Is Up** only when the
   pen is physically clear. Camera appearance alone is not that confirmation.
4. Send the smallest configured X or Y jog. Wait for `ok` acceptance followed
   by observed Idle completion and the expected final MPos.
5. Send the exact inverse jog and verify return. Try the other axis only if the
   first round trip was unambiguous.

Stop immediately on unexpected motion, alarm, asserted limit, disconnect, Hold,
unexpected controller state, or ambiguous outcome. Do not Home, unlock/clear an
alarm, reset, write settings, Resume, or lower the pen.

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

After the camera and jog round trips pass, add direct Pen Up/Pen Down control and
establish one camera-visible observation region plus one known pen-up clear pose.
Then run the isolated-line procedure in the direct implementation plan.
