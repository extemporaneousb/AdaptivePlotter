# First Hardware Session

Status: ready as an operator procedure; not yet executed  
Scope: one powered passive controller interrogation only

## Outcome and authority boundary

The first machine session may send exactly these queries, once and in this
order:

```text
$I
$G
?
$$
$#
```

The current code has no other physical command surface. Motion and pen arms are
unavailable and off. This session must not move, unlock, home, reset, write a
setting, clear an alarm, actuate a servo, or lower the pen. It records current
controller evidence; it does not establish motion safety, physical position,
camera access, ink evidence, or drawing authority.

Do not run this session from a general serial terminal or improvise commands.
Use the app-owned fixed passive probe so preparation, transmitted bytes, raw
replies, parser outcomes, and failures share one ledger.

## Admission gate: current blockers

The 2026-08-02 host inspection found:

- macOS 15.7.8 on Intel `x86_64`;
- Swift 6.1.2 from `/Library/Developer/CommandLineTools`;
- no full Xcode installation selected;
- no valid code-signing identity;
- a built-in FaceTime HD camera, inventory only;
- only `/dev/cu.BLTH` and `/dev/cu.Bluetooth-Incoming-Port`, with no apparent
  controller device.

The command-line tools are enough to build and test the offline SwiftPM
prototype. They do not satisfy the binding product gate for a signed macOS app
with verified device access. The current artifact is a SwiftPM development
executable, not a signed `.app` bundle.

Before powering or connecting the machine, complete all of the following:

1. Install full Xcode with Swift 6 support and a macOS SDK supporting the
   package's macOS 14 deployment floor. Select it with `xcode-select`, accept
   its license, and record `xcodebuild -version`, `swift --version`, and the SDK
   path.
2. Add/build the actual macOS application-bundle target and configure a signing
   team/identity. Record the bundle identifier, signing identity, entitlements,
   build configuration, binary architectures, and source commit.
3. Confirm the selected sandbox policy supports IOKit discovery and BSD
   `/dev/cu.*` access. Do not add broad entitlements merely to make a probe pass.
4. Re-run the repository validation from the exact source revision used for the
   signed build:

   ```bash
   make check
   ```

5. Confirm no other application, terminal, or legacy Plotter process has the
   controller serial port open.
6. Prepare a recoverable evidence destination with enough free space. Do not
   delete or rotate a prior passive-run database to make room.
   The app performs a read-only cross-launch recovery scan before creating a
   new ledger or opening the serial device. Any empty, corrupt, malformed,
   unfinished, unresolved, unreadable, or unsafe prior passive ledger is an
   explicit `RECOVERY BLOCKED` stop; do not rename or delete evidence to bypass it.
7. Put the mechanism in a physically harmless boot condition. If motor and pen
   actuator power can be isolated from controller/USB power, leave them
   isolated. Otherwise remove or restrain the pen so unexpected boot behavior
   cannot mark or collide, keep hands out of the travel envelope, and have the
   verified physical power cutoff/E-stop immediately reachable.

If any item is incomplete, stop before hardware power. The unsigned SwiftPM
executable may still be used with hardware disconnected for offline replay; it
must not be presented as signed-product device evidence.

## Baseline capture with the machine off

From the repository root, retain the current host/toolchain receipt:

```bash
sw_vers
uname -m
swift --version
xcode-select -p
xcodebuild -version
xcrun --sdk macosx --show-sdk-path
security find-identity -v -p codesigning
system_profiler SPCameraDataType
ls -l /dev/cu.*
```

Capture the output in the session notes without publishing machine serial
numbers, hardware UUIDs, account names, or other host identifiers. The serial
listing is the before-power baseline. The two Bluetooth callout devices seen on
2026-08-02 are not controller candidates.

## Powered passive procedure

1. Close the app and every possible serial client. Confirm motion/pen actuator
   power remains isolated when the hardware permits it and the mechanism is in
   the harmless boot condition above.
2. Connect controller USB and apply only the power required to expose the
   controller. Observe the mechanism during boot. Any armature motion or servo
   actuation is an immediate physical stop condition.
3. Run `ls -l /dev/cu.*` again. Identify the newly appeared controller device by
   before/after difference and physical cable association. Do not select a
   Bluetooth device. If no unique new device appears, more than one plausible
   device appears, or a vendor driver appears to be missing, power down and
   resolve discovery before proceeding.
4. Launch the exact signed application build whose receipt was captured. In the
   **PASSIVE DEVICE** pane, choose **Refresh Serial Devices**, then explicitly
   select the one proven controller path. The application must never guess
   among multiple devices.
5. Confirm the persistent red banner states **DRAWING BLOCKED**, both arms show
   **UNAVAILABLE / OFF**, and there is no motion, pen, unlock, home, settings, or
   reset control.
6. Choose **Request Passive Probe** exactly once. The application disables any
   second attempt until it is restarted as a new operator session. It opens the
   selected BSD path in raw mode at
   115200 baud and attempts the following fixed wire payloads:

   | Order | Query | Exact bytes | Completion evidence |
   | --- | --- | --- | --- |
   | 1 | `$I` | `24 49 0A` | Parsed `ok` after retained build/report lines. |
   | 2 | `$G` | `24 47 0A` | Parsed `ok` after retained parser-state lines. |
   | 3 | `?` | `3F` | One parsed `<...>` status report; no `ok` is required. |
   | 4 | `$$` | `24 24 0A` | Parsed `ok` after retaining every settings line. |
   | 5 | `$#` | `24 23 0A` | Parsed `ok` after retaining coordinate/report lines. |

   Every query has a two-second absolute deadline and a total receive ceiling of
   64 KiB or 256 chunks, whichever comes first. Continuous noise cannot extend
   the deadline. Missing query-specific evidence and response-budget overflow
   are blockers even if a bare `ok` appears.

   The controller stops the sequence on the first timeout, transport error,
   storage error, `error:`, or `ALARM:`. It does not continue around a blocker.
7. Observe the mechanism for the entire exchange. Do not touch the carriage,
   switches, armature, or paper and do not answer an unexpected state with
   `$X`, `$H`, Ctrl-X, a setting write, or any `G`/`M` command.
8. When the probe returns, confirm the UI shows five exchanges and zero blockers
   before calling the passive interrogation complete. Confirm the returned
   interpreter completion-authority receipt is `passiveInterrogation` only,
   confirm the UI says the one-shot link has disconnected, and record the exact
   ledger path shown by the UI. Inspect the passive TX/RX timeline's escaped text
   and exact hexadecimal bytes and preserve
   unfamiliar fields, pins, errors, and extensions exactly as received. Do not
   normalize contradictory settings into defaults.
9. Quit the app normally, disconnect controller USB, and power the controller
   down. Do not proceed directly from a successful passive probe into a jog or
   pen test.

## Stop conditions

Stop, remove power through the physical safe path when appropriate, and retain
all evidence if any of the following occurs:

- any carriage, armature, or servo motion during boot or interrogation;
- the pen can contact the surface or the mechanism is not in a harmless state;
- the controller port is absent, ambiguous, changes identity, or is already in
  use;
- the selected path is one of the baseline Bluetooth devices;
- the app does not show drawing blocked and both arms unavailable/off;
- transmitted bytes or ordering differ from the five rows above;
- any timeout, disconnect, storage failure, invalid/missing required reply,
  response-budget overflow, parser failure, `error:`, or `ALARM:`;
- the app or machine crashes, the ledger cannot be located, or raw replies are
  missing;
- controller identity, state, pins, offsets, or settings contradict the
  physical setup or historical hypotheses.

A blocker is evidence, not a prompt to unlock, reset, retry repeatedly, or fall
back to an unledgered terminal. Preserve the failed database and diagnose from
power-off state. A completed passive run also leaves motion and drawing blocked.

## Evidence capture and verification

Each request creates a unique SQLite database under:

```text
~/Library/Application Support/AdaptivePlotter/PassiveRuns/passive-<uuid>.sqlite
```

After the app has quit, list the databases and identify the one whose timestamp
matches the session:

```bash
find "$HOME/Library/Application Support/AdaptivePlotter/PassiveRuns" \
  -type f -name 'passive-*.sqlite' -print
```

Set `passive_db` to that exact absolute path. After a normal app close, inspect
the closed, checkpointed database through SQLite's immutable URI mode so the
inspection itself does not create or modify SQLite side files:

```bash
passive_db="/absolute/path/to/passive-<uuid>.sqlite"
sqlite3 "file:$passive_db?immutable=1" 'PRAGMA integrity_check;'
sqlite3 -header -column "file:$passive_db?immutable=1" \
  'SELECT id, created_wall_time, build_id FROM run;'
sqlite3 -header -column "file:$passive_db?immutable=1" \
  'SELECT sequence, query, hex(wire_bytes) AS wire_hex, lifecycle, outcome FROM command ORDER BY sequence;'
sqlite3 -header -column "file:$passive_db?immutable=1" \
  'SELECT sequence, kind, payload_sha256 FROM event ORDER BY sequence;'
shasum -a 256 "$passive_db"
```

Expected successful command rows are exactly:

```text
buildInfo         24490A
parserState       24470A
status            3F
configuration     24240A
coordinateOffsets 24230A
```

All five lifecycles must be `completed`. The event table must retain TX and RX
payload hashes for each exchange plus the versioned probe-start, probe-finish,
and interpreter-authority transition records. The UI result, database rows, SHA-256,
before/after serial inventory, application build receipt, and operator notes
belong in one immutable session evidence package.

If the app or host crashed before SQLite closed, preserve the database plus any
same-basename `-wal` and `-shm` files together before inspection. Never copy a
WAL database without its WAL and claim the copy is complete. Do not use the
immutable commands above on an uncheckpointed crash set because immutable mode
does not reconcile a live WAL; inspect a working copy with all components
present or add a recovery/export tool first.

Passive success establishes only current controller interrogation through the
native parser and ledger. It does not accept historical travel, pin, homing,
pen, or feed values as safe configuration.

## Phase 4 is the first motion gate

No powered motion is authorized merely because the passive session succeeds.
The first motion work is the Phase 4 armature-clearance/viewability trial, and
it remains pen-up only. Before the motion arm can exist, implementation and
evidence must establish all of the following:

1. A signed application captures exact immutable camera frames through
   AVFoundation with a recorded camera configuration, freshness, stability,
   interruption, and TCC receipt. Built-in camera inventory is insufficient.
2. Independent reference geometry accepts a `FieldRegistration` with redundant
   held-out points. Synthetic registration tests are insufficient.
3. One fixed reserved `ObservationRegion` is projected into camera space.
4. Exact retained frames measure the conservative camera-space silhouette of
   the complete pen, holder, linkage, and actuator/servo assembly at the
   candidate pose. The resulting `ToolOcclusionEnvelope` records camera, tool,
   carriage/cap pose, pen/servo state, uncertainty, and fixed margin identities.
5. The inflated envelope is disjoint from the projected observation region.
   The paper-plane homography must not be applied to the elevated armature as if
   it were coplanar with the paper.
6. One fixed `ClearancePose` and bounded `ClearancePath` stay within the current
   fixed machine-safety envelope, use separately armed low-speed pen-up motion,
   and end at the exact measured pose.
7. A known sufficiently large green reference mark is visible in the reserved
   region without armature occlusion, and a demonstrably newer stable frame
   after the clear move independently confirms that the region remains clear.
8. The trial records controller, path, pose, registration, camera, tool,
   pen/servo state, frame, algorithm, uncertainty, margin, and configuration
   identities. Any relevant configuration change invalidates the evidence.

If the complete armature cannot reach a bounded safe viewable pose, if its
inflated envelope still intersects the observation region, or if fresh-frame
confirmation fails, stop Phase 4 and redesign the tool/camera geometry. Do not
weaken freshness, margin, or clearance to advance the schedule.

Pen-down is categorically forbidden until Phase 4 clearance/viewability passes
with retained physical evidence. Even then, pen-down requires the separate
Phase 5 gate: a verified pen profile, independent motion and pen arms, a clean
reserved region and baseline, current safety/camera/registration/tool evidence,
one bounded `isolatedTrainingProbe` authority, durable command preparation, and
no automatic redraw. The first accepted observation may still fail drawing
tolerance and must not promote a model without sufficient independent holdout
evidence.
