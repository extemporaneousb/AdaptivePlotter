# Forensic Baseline

Status: complete historical reference
Legacy repository: `/Users/bullard/Projects/Plotter`
Inspection date: 2026-08-02

## Boundary

The legacy repository was inspected read-only at
`482bc8d1d0093bca29702492da4bf7fe5acb4b05`. It is evidence about the
controller, camera techniques, and failure cases. It is not the architecture or
source layout for AdaptivePlotter.

At inspection time there was no live legacy process and no apparent controller
device. Only `/dev/cu.BLTH` and `/dev/cu.Bluetooth-Incoming-Port` were present,
so no retained artifact describes current machine state.

## Why the legacy product is not being ported

The old product split authority between large Python and Swift surfaces:

| Concentration | Historical size |
| --- | ---: |
| `plotter_vision/bridge/server.py` | 8,206 lines |
| Python drawing calibration | 1,640 lines |
| `PlotterBridgeModel.swift` | 3,966 lines |
| `ContentView.swift` | 3,595 lines |
| `PlotterBridgeClient.swift` | 1,892 lines |
| `CameraModel.swift` | 1,245 lines |

It also carried localhost routes, mirrored DTOs, readiness composition,
workflow/wizard state, launcher modes, compatibility surfaces, and duplicated
motion models. None of those are retained.

## Curated fixtures

Seven small historical records remain under `Fixtures/LegacyEvidence`:

| Fixture | Use |
| --- | --- |
| `controller_snapshot_curated.jsonl` | `$I`, `$G`, `?`, selected `$$`, and `$#` parser cases. |
| `status_passive.jsonl` | Passive status and Idle parsing. |
| `jog_x_round_trip.jsonl` | Historical motion command sequence; not current motion permission. |
| `alarm_status_excerpt.jsonl` | Alarm parsing. |
| `status_after_home_timeout.jsonl` | Repeated status and extension parsing. |
| `soft_reset.jsonl` | Reset/greeting parser evidence; not reset permission. |
| `pen_cycle.jsonl` | Historical servo command syntax; not proof of pen state. |

Validate the curated copies with:

```bash
Scripts/validate_evidence_manifest.sh
```

Use `--verify-source` only when the legacy archive is available and exact
source provenance matters. Fixture verification is not a prerequisite for an
unrelated implementation change.

## Hardware hypotheses to check locally

- Controller family: OpenBuilds BlackBox X32 with grblHAL-compatible firmware.
- Serial baud: 115200.
- Later legacy configuration reported X travel 533.4 mm and Y travel 215.9 mm;
  an earlier controller snapshot reported 200 mm, so current values must come
  from the attached machine.
- Historical pen commands were `M3 S720` down and `M3 S40` up with about
  0.3 seconds settle.
- Historical feed limits conflict across artifacts; start with a deliberately
  low local value and adjust from direct observation.

These are inputs for quick local checks, not reasons to build a configuration
or evidence framework.

## Retain, remove, verify

Retain:

- selected controller transcripts as parser fixtures;
- no arbitrary G-code;
- bounded feed, distance, and workspace checks;
- camera preview and overlay techniques as reference;
- actual observed ink as the drawing result;
- no automatic resend or redraw after an ambiguous command.

Remove or keep removed:

- Python bridge/server/live control;
- Swift HTTP client, DTO mirrors, and process supervisor;
- launcher compatibility modes and wizard/readiness state;
- duplicate Swift/Python motion models;
- mutable latest calibration pointers;
- archival evidence/replay requirements inherited from the earlier design;
- accessibility and advanced-model scope.

Verify on the attached hardware only when the corresponding operation is ready:

- current controller identity/status/settings;
- actual end-stop behavior and controller feed capability;
- pen up/down values and behavior;
- camera selection and observation region;
- one clear tool pose;
- one isolated line and its observed ink.

## Minimal runtime status

The UI needs a current projection, not a comprehensive historical snapshot:

- selected device and connection/controller state;
- current operation and outstanding command;
- current Motion Guard state and controller capability;
- pen state when implemented;
- latest camera frame/time when implemented;
- current stroke and last command outcome;
- intended/observed geometry and simple residual;
- one concise actionable error.

There is no replay mode, algorithm-re-evaluation mode, storage quota state,
model-promotion state, accessibility state, or separate motion/pen arm state.
