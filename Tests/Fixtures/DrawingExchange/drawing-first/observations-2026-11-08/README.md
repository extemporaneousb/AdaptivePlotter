# Drawing-first software observations, 2026-11-08

Task `task-89f7fee3b6c847e9ae9acebb9b901347`, attempt
`attempt-b1cb6006515749688e7dd18c9e3ffd93`, base
`707212cb5f193f6fd7fa1faba4eab1de74a3a33a`. Immutable outcome definition:
`25095331357c9051e35bed33241e22aabf3cd4c00fc9a43f2dc5a62d637b2259`.
These are scoped software observations, not configured validation, task acceptance,
canonical adoption, a signed application trial or physical plotter evidence.

`receipt-index.json` maps original observation files to retained bytes and original
SHA-256. Input manifests are deduplicated and losslessly gzip-compressed;
external SwiftPM descriptions are also compressed. Decompress before checking the
original digest. `manifest.json` seals every retained file except itself.
No build scratch, executable, virtual environment or production data is included.

## Executed observations

| Observation | Actual result | Scope |
| --- | --- | --- |
| Common target build | exit 0, 76.598 s | Fresh common/Core/Model compilation only |
| Initial all-products build, third attempt | exit 0, 97.461 s | Both executable products linked; no launch |
| All-test compilation, second attempt | exit 0, 72.375 s | Compilation only, prior pinned tree |
| Focused storage/current authoring retry | 89 passes, 1 helper skip, 0 failure/error; 165.783 s | 90 parent XML cases; includes 72 actual publication-kill children, 4 restore and 3 fresh-root restore cases |
| Studio/offscreen-layout/pure-ML run | 68 passes, 4 skips, 9 failed cases; 519.384 s | A failed run, including successful 178.027 s actual Portrait route and 121.919 s native-model suite; opt-in real-data and AX checks skipped |
| Affected Studio retry after fixes | 38 passes, no skips/failures/errors; 140.962 s | All nine previously failed cases plus new invalid-source/repeated-bound-reference regressions; long unchanged native-render and ML suites not repeated |
| Current metadata benchmark | 1 pass, no skips/failures/errors; 7.605 s | 100 versus 10,000 synthetic named metadata rows; one publicly retained drawing at each scale |
| Final dependency-isolated public client | exit 0, 9.885 s | Actual concrete public API assertions, cached product rebuild; reachable dependency closure Client/Common/Core/Model/CSQLite |

Every row retains its own command, time, raw output and source pins. Counts overlap
and must not be added. Earlier results apply to their recorded trees; no aggregate
current-tree full-suite or configured-gate result is asserted. The final client and
benchmark each recorded 773 unchanged inputs. The final affected Studio run
recorded 771 unchanged inputs; the additional two resources are present in the
broader final-run manifest, not intervening edits.

Final client description SHA-256:
`610905b0b1b3d0b99a66690434ff2c3fd9e1a3aed5203cea7589ee2360943bd3`.
Only DrawingLibrary, PortraitCore, PlotterModel and client Swift modules were
emitted. Available but unreachable package targets are retained in the full raw
SwiftPM description; closure was computed from the client, not by filtering names.

## Current metadata measurements

All operations ran in debug configuration on the recorded host/toolchain. Each
operation has five warmups and 30 retained raw samples; percentiles use nearest
rank. A real keyset page walk established the deep cursor outside timing. Rename
trials followed page trials so changed generations could not invalidate measured
cursors. All rows have named JSON metadata and retention reasons. One owner seeded
synthetic SQL metadata; this is not 10,000 admitted programs or a historical-format
comparison.

| Metadata rows | First page p95 ms | Deep page p95 ms | Rename p95 ms | Clear title p95 ms | Lifetime peak RSS bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| 100 | 3.573402 | 3.644773 | 2.830122 | 2.852691 | 37,548,032 |
| 10,000 | 3.548321 | 6.255042 | 3.697290 | 4.106348 | 57,438,208 |

Pages contain 30 entries. The artwork directory was physically unavailable for
all timed operations; metadata succeeded and selected artwork loading refused.
This proves no artwork dependency for those operations, not an instrumented zero
filesystem-open/hash/decode count. RSS is Darwin process-lifetime high-water,
including startup, fixture setup and the preceding scale, not operation-local
memory. Database sizes were 339,968 and 18,317,312 bytes. No Dojo CPU, native paint,
old-baseline speedup or production-data claim is made.

Raw report SHA-256:
`43b5a438f8a7093c8a562caa75794d4b91c00b7a626f416fd25b5b4e1d18bc4a`.

## Failure history and resolution boundary

- Early external-client runtime failures exposed verified-carrier root containment
  and `/var` versus `/private/var` relative-path handling. The Core containment
  guard remained strict; the selected staging layout and canonical component
  paths were corrected. The read-only Foundation path probe and failed receipts
  remain. The successful client also exercises record-only commits.
- Initial full builds exposed ambiguous StrokeStyle and missing/removed caller
  imports. Initial all-test compilation exposed retired test ABI and stale neutral
  storage names. They remain failed build receipts, not executed test passes.
- The first focused test run failed ten cases: stale marker/table/asset fixture
  paths; fault-reset helpers accidentally recovering before clearing the injector;
  missing exposure-window progress/actionable camera failure; and conflicting
  JSON asset descriptor encoding on native choice. Current descriptor guards
  remained strict. The focused retry passed all 89 executable cases.
- The broader Studio run exposed repeated unbound-to-bound intent reuse, repeated
  already-retained child intent reuse, incorrect Core-error recovery classification,
  incomplete duplicate-choice coalescing, and test fixture defects in native PNG
  output, mask contrast, and next-pair Rank expectations. Exact references are
  reused; record-only updates do not reuse drawing-retention intents. Invalid
  source admission is rejected before graph mutation. The 38-case retry preserves
  failure/recovery, changed-offered-set and fresh-next-pair obligations.
- One final-client observation wrapper did not start Swift because of a Python
  namespace error. The next manifest evaluation failed because its required
  repository-path environment variable had been cleared. Both are retained as
  orchestration failures; no Common target/runtime failure is attributed to them.
  The final run restores only the known repository path after clearing opt-ins.

## Limits and retirement

`retirement-map.json` records actual deleted paths, current caller ownership and
zero active code matches for retired package/store/String-identity routes.
`frozen-benchmark-exclusions.json` proves all five inert old-ABI benchmark sources
remain byte-identical to the adopted base; the originals and golden data were not
regenerated. `implementation-pins.json` pins the final-client Sources/Package
inputs independently of later evidence/documentation additions.

Historical authoring files were neither opened nor converted; import is deferred
and nonblocking. No new user width/declaration field is required. Fresh producer
receipts keep declared nominal width distinct from unknown/measured physical facts.
The default app validator registry does not semantically revalidate arbitrary
persisted Flow receipts: retained Flow bytes are preserved and known program
preview/plot/edit remain supported, while generic regeneration/training is not
advertised. Current Dojo training/material adaptation use exact domain capsules
and references. This does not close a future generic producer-proof gate.

No signed/native application launch, real camera session, attended motion,
production-library operation, historical import, deployment/model promotion,
remote Git action or episode/physical-authority change occurred in these probes.
