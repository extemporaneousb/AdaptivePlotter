# Phase 1 Forensic Baseline

Status: complete software-only baseline; all physical facts remain unverified  
Inspection time: 2026-08-02T21:44:10Z  
Legacy repository: `/Users/bullard/Projects/Plotter`

## Boundary and evidence status

The legacy repository was inspected read-only on clean `main` at
`482bc8d1d0093bca29702492da4bf7fe5acb4b05`. This commit identifies the source
tree used for the audit. It does not authenticate ignored files under
`artifacts/`; each curated artifact therefore has its own source path, source
hash, retained-fixture hash, and historical/non-authoritative label in
`Fixtures/LegacyEvidence/manifest.json`.

The scan found no running `PlotterVision`, `plotter_vision`, launcher, or bridge
process and no apparent controller serial device. Only `/dev/cu.BLTH` and
`/dev/cu.Bluetooth-Incoming-Port` were present. Nothing in this report or fixture
corpus describes current live machine state.

The legacy ignored artifact tree was about 1.5 GiB with 341,050 files, including
265,158 `bridge_transcripts` files. It was not copied. Seven small records were
selected because their origin and bytes can be checked; mutable latest-pointer
JSON, logs, PID files, bridge routes, application state, calibration sessions,
and Blackdog state were excluded.

## Source and test inventory

| Evidence | Observed value |
| --- | --- |
| Tracked files | 120 |
| Python product modules under `plotter_vision` | 38 files, 19,509 lines |
| Swift product sources | 28 files, 18,802 lines |
| Python test modules | 31 |
| Pytest collection | 323 tests |

The primary concentrations are not sensible porting units:

- `plotter_vision/bridge/server.py`: 8,206 lines;
- `plotter_vision/calibration/drawing_model.py`: 1,640 lines;
- `plotter_vision/cli.py`: 1,357 lines;
- `PlotterBridgeModel.swift`: 3,966 lines;
- `ContentView.swift`: 3,595 lines;
- `PlotterBridgeClient.swift`: 1,892 lines;
- `CameraModel.swift`: 1,245 lines.

The collected suite includes useful controller/parser/safety/geometry cases, but
also many bridge-route, wizard-string, compatibility, readiness, capability,
shape, and portrait-surface contracts. Phase 2 should rewrite only the durable
parser, transaction, safety, geometry, simulator, and failure invariants.

## Live launch paths and duplicated authority

Every live path depends on the legacy source checkout, Python environment, or
localhost bridge and is outside the new product boundary.

| Legacy surface | File evidence | Disposition |
| --- | --- | --- |
| Normal app launch | `Makefile:131-132` routes `make launch` through the smart launcher; `scripts/plotter_launcher.sh:243-253` opens the app-owned path. | Do not migrate. One locally built native process becomes the only live process. |
| App-owned Python child | `AppMain.swift:10-16` installs `BridgeProcessSupervisor`; `BridgeProcessSupervisor.swift:31-45` requires the source checkout, virtual environment, mutable artifacts, and localhost URL; `:165-184` starts `plotterctl bridge-server`. | Delete at the separately authorized legacy cutover; no supervisor or child in AdaptivePlotter. |
| Launcher compatibility modes | `scripts/plotter_launcher.sh:34-50` and `:261+` expose smart/standby/preview/live/app/stop modes; installed shortcuts call the same script. | Do not migrate modes, PID/port discovery, or compatibility behavior. |
| Direct Make bridge processes | `Makefile:213-228`, `:298-310`, and `:374-403` start standby, mock preview, and armed live bridge variants on localhost. | Do not migrate. Retain only safety observations as requirements. |
| Direct CLI bridge | `plotter_vision/cli.py:108-145` exposes `bridge-server`, serial selection, dry-run/live, and four arms. | Do not migrate the CLI or HTTP boundary. Rebuild passive serial and typed safety natively. |

Authority is duplicated across the two processes and within each process:

- Python `bridge/server.py` owns routes, machine action, workflow synthesis,
  artifact pointers, planning, execution, and `ready_to_draw` (`:6079-6323`).
- Python `calibration/readiness.py:285-324` separately defines
  `visual_ready_to_plot`; `drawing/pipeline.py:16` has another execution-authority
  vocabulary; `config.py:79-88` persists `homing_trusted` and
  `axis_model_trusted` flags.
- Swift `OperatorWorkspaceState.swift:3-44` owns cameras, wizard state, field
  geometry, cap state, visual motion samples/model, windows, portrait state, and
  operator log, well beyond presentation state.
- Swift `Models.swift:685-772` fits and inverts `VisualMotionModel` while Python
  also fits/uses a motion authority. `ContentView.swift:850` and `:1957-2000`
  mutate the Swift copy.
- `PlotterBridgeClient.swift:1598-1646` and `PlotterBridgeModel.swift` mirror the
  Python state through localhost DTOs. Camera acquisition and some inspection
  also coexist inside `CameraModel.swift`.

None of these readiness facts is drawing evidence. Bridge online, controller
Idle, cap confirmation, field registration, cap-motion fit, preview, commanded
pen state, and `ok` remain separate historical observations and cannot grant
future `ExecutionAuthority`.

## Retain, redesign, delete, or physically verify

| Existing evidence or surface | Disposition | Concrete Phase 1 decision |
| --- | --- | --- |
| Selected raw controller/status records | **Retain as fixture** | Keep only the hashed corpus in `Fixtures/LegacyEvidence`; treat all records as historical. |
| Parser behavior for greeting, build fields, unknown fields, status, pins, alarm, `ok` | **Retain as test cases** | Re-express as native parser goldens and simulator inputs. Missing error/timeout/disconnect/hold cases are explicit manifest gaps. |
| Dry-run default, separate arms, bounded feed/distance/workspace checks | **Redesign** | Preserve the safety invariants in typed Swift; do not preserve flags, CLI options, routes, or UI layout. |
| AVFoundation device/frame/pan/zoom techniques | **Retain as reference; redesign ownership** | Queue-confined `CameraCapture` produces exact immutable frames; measurement and authority move to their named owners. |
| Expected/predicted/observed/cap/residual overlays and provenance IDs | **Retain as concepts** | Render from immutable runtime projections and stable identities. |
| Ink-inspection and deterministic geometry examples | **Retain as challenge evidence** | Rewrite algorithms and thresholds; no legacy threshold is accepted. |
| Python bridge/server/controller/live calibration/planning/execution | **Delete at legacy cutover** | No live Python or source-checkout dependency enters this repository. Actual legacy deletion requires separate user authorization. |
| Swift HTTP client, DTO mirrors, process supervisor, launcher compatibility | **Delete at legacy cutover** | No compatibility bridge or dormant alternate execution path. |
| Wizard, route families, capability/shape/portrait surfaces and their string/route tests | **Delete/defer** | Reintroduce only delivered capabilities through `DrawingProgram` after the adaptive ink slice. |
| Duplicate Swift/Python motion models, trust flags, mutable latest-pointer calibration files | **Delete as authority** | Use immutable model versions, frontiers, checkpoint decisions, and one runtime authority. |
| Controller identity, baud, travel, pins, homing, pen commands, settle time, feed limits | **Physically verify** | Native passive probe first, then separately armed bounded trials. No historical value becomes a default. |
| Camera configuration, marker need, registration model, ink thresholds, armature clearance | **Physically verify** | Resolve through the controlled trial ladder; cap motion never establishes ink authority. |

## Configuration hypotheses

These values exist to drive experiments, not initialization:

- Historical controller snapshot: OpenBuilds BlackBox X32, grblHAL
  `1.1f.20240402`, ESP32 driver `240330`.
- Serial baud: 115200 in `Makefile:4` and
  `controller/serial_transport.py:10`.
- Later application/runbook travel: X 533.4 mm and Y 215.9 mm
  (`Makefile:35-36`, `docs/RUNBOOK.md:291-298`). The retained earlier controller
  snapshot reports `$130=$131=$132=200.000`; the contradiction is unresolved.
- Historical snapshot: `$21=1`, `$22=1`, `$23=0`, `$27=1.000`, with `Pn=Z` and
  an `H` extension appearing in retained status records. Later runbook evidence
  describes altered XY/Z pin configuration. Switch semantics must be observed
  one switch at a time before homing.
- Historical pen commands: `M3 S720` down and `M3 S40` up; legacy code supplies
  0.3 seconds settle. Controller acknowledgement is not proof of physical pen
  position or ink.
- Fixed motion limits conflict: the historical controller reports 500 mm/min
  axis maximums while legacy code defaults to 1200 mm/min and ignored mutable
  configuration has other values. Derive a conservative policy only after the
  controller/configuration evidence is current.

The machine-readable copies, contradictions, and required verification method
are in the manifest.

## Curated evidence corpus

| Fixture | Historical behavior retained |
| --- | --- |
| `controller_snapshot_curated.jsonl` | Passive `$I`, `$G`, `?`, selected `$$`, `$#`; build/config/status extensions. Network identifiers and unrelated settings were omitted; retained records remain exact and ordered. |
| `status_passive.jsonl` | Passive status query and Idle report. |
| `jog_x_round_trip.jsonl` | Historical modal setup, relative 1 mm round trip, acknowledgements, dwell, and final status. It does not authorize motion. |
| `alarm_status_excerpt.jsonl` | Exact first 15 source records showing repeated Alarm status. |
| `status_after_home_timeout.jsonl` | Repeated status and an `H` extension. The bytes do not independently prove the filename's timeout claim. |
| `soft_reset.jsonl` | Historical Ctrl-X request, greeting, and post-reset status. It does not authorize reset. |
| `pen_cycle.jsonl` | Historical down/up commands and acknowledgements. It does not verify pen position or ink. |

No small physical `error:`, transport timeout/disconnect, or feed-hold transcript
with equally defensible provenance was selected. The manifest makes these gaps
machine-readable so Phase 2 cannot silently claim complete physical coverage.

## Planned `RuntimeSnapshot` fields

The future snapshot is one immutable projection from `RunInterpreter`. It must
expose facts without recreating authority in SwiftUI:

- schema, snapshot, build/source, run, and monotonic/wall-time identities;
- live/recorded-replay/algorithm-re-evaluation mode;
- controller connection, selected BSD path/device identity, parser/config IDs,
  reported state, pins, alarm/hold, raw evidence age, outstanding command;
- separate motion and pen arms with expiry and exact fixed-safety policy;
- camera device/configuration/frame IDs, timestamp, age, stability, drops,
  interruption, and exact retained evidence hash;
- program ID/hash, plan ID/revision/hash, current instruction/block, pinned
  model/state/registration/machine/tool/pen/safety/compiler identities;
- commanded, controller-completed, and ink-verified frontiers plus ambiguous
  stroke/block set;
- current alignment state/covariance and active/candidate model identity,
  applicability, uncertainty, evidence coverage, and validation disposition;
- observation identity/disposition, coverage, topology, covariance, goal
  residual, model innovation, and missing/extra ink facts;
- `ExecutionAuthority` operation, allowed flag, limits, evidence dependencies,
  blockers, affected scopes, and permitted recovery intents;
- checkpoint/decision identity, successor-plan lineage, unresolved/excluded work;
- ledger transaction/storage health, quota/free space, bundle completeness, and
  replay/recovery status.

The snapshot must not contain `calibrated: Bool`, a duplicate readiness state,
or UI-derived remaining-work/authority decisions.

## Hash verification

Portable fixture verification:

```bash
Scripts/validate_evidence_manifest.sh
```

When the legacy source archive is mounted at its recorded path, verify both
retained files and their current source hashes/derivations:

```bash
Scripts/validate_evidence_manifest.sh --verify-source
```

`LEGACY_PLOTTER_ROOT` may point the second command at a relocated read-only copy.
The validator checks manifest schema/status, fixture path containment, sizes,
SHA-256 values, JSONL shape, explicit historical authority status, source
SHA-256 values, exact copies, the alarm line extraction, and ordered curated
snapshot records.

## Phase 1 exit and remaining physical evidence

Phase 1 establishes a no-copy replacement boundary, source/test disposition,
configuration hypotheses, a small hash-verifiable corpus, and a future snapshot
contract. AdaptivePlotter has no dependency edge to the old live product.

It does not establish current controller behavior, safety dimensions, camera
access, registration, motion, pen behavior, ink detection, or drawing authority.
Phase 2 must retain motion and pen as unreachable until a native passive probe
records current `$I`, `$G`, `?`, `$$`, and `$#` evidence. This blocks powered
motion only, not software development. Phase 4 supplies the first moving
authority evidence; Phase 5 supplies the first pen-down authority evidence.
