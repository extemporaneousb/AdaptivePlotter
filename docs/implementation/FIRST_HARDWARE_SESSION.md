# First Hardware Session

Status: ready for the controller to be connected
Scope: repeatable passive controller interrogation

## Purpose

Use the native app to confirm that this Mac can open the actual controller and
parse its current identity, status, settings, and offsets.

The current build sends only:

```text
$I
$G
?
$$
$#
```

It has no motion or pen commands, so no separate motion/pen arms or development
admission process is needed.

## Before connecting

1. Run:

   ```bash
   make check
   make build
   ```

2. Close other serial terminals or legacy Plotter processes.
3. Put the mechanism in a harmless boot condition. Prefer motor/pen power
   isolated if the controller can enumerate without it. Otherwise remove or
   restrain the pen and keep the physical power cutoff reachable.

That is the complete local prerequisite list. Full Xcode, signing, entitlements,
archival storage preparation, prior-run inspection, and evidence packaging are
not required.

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
   .build/debug/AdaptivePlotter
   ```

5. Choose **Refresh Serial Devices**, select the controller path, and choose
   **Request Passive Probe**.
6. Confirm that the UI reports the five exchanges or gives a concrete error.
7. Repeat the probe in the same app launch if useful. A failed probe is not a
   one-shot event and old journal files do not block retry.

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
~/Library/Application Support/AdaptivePlotter/PassiveRuns/
```

The log is optional current-run diagnostic data. A logging failure does not stop
the probe. Manual SQLite verification, database hashing, WAL export, immutable
evidence packages, and preservation of every old run are not required.

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

After the passive probe works, implement and try one bounded low-speed pen-up
relative move. At that moment check only:

- current non-alarm controller status;
- configured local bounds, distance limit, and conservative feed;
- pen known up;
- no outstanding ambiguous command.

No camera, registration, model, historical replay, phase completion record, or
separate motion arm is required for that pen-up move.

Before the first pen-down line, add direct Pen Up/Pen Down control and establish
one camera-visible observation region plus one known pen-up clear pose. Then run
the isolated-line procedure in the direct implementation plan.
