# Portrait Studio

Status: current standalone operator and exchange-format guide. Product authority
remains in [Product Contract](PRODUCT_CONTRACT.md); module ownership is in
[Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md#package-topology). Unfinished
experiments, human evaluation and learning belong to [Roadmap](ROADMAP.md).

## Build and start

```sh
make portrait-studio-app
make validate-portrait-studio-app
```

These commands build and sign `.build/PortraitStudio.app` without launching it.
Use `APP_CONFIGURATION=release` for an optimized build. The bundle identifier is
`com.bullard.PortraitStudio`, version 0.1.0; it requires macOS 14 or later. Its
Info.plist contains a camera usage description and no microphone or speech
permission. Open this bundle explicitly when ready to use the app. Running the
bare SwiftPM executable does not provide that application permission identity.
Local signing uses `PORTRAITSTUDIO_CODESIGN_IDENTITY` (defaulting to the existing
AdaptivePlotter local development certificate when available) and optional
`PORTRAITSTUDIO_CODESIGN_KEYCHAIN`; otherwise the bundle is signed ad hoc. Bundle
verification establishes local packaging integrity, not notarization or native
camera operation.

The bundle script also accepts a second, absolute output path ending in
`/PortraitStudio.app`, for retaining a verified build outside a disposable task
workspace. It refuses to replace a running or symbolic-link output bundle. The
AdaptivePlotter bundle and running session are independent.

## Author, retain and hand off

1. In **Studio**, import a photo or choose a camera and use **Capture Photo**.
   Startup discovers cameras without beginning capture. Capture starts the selected
   device and retains one quality-selected frame from the short burst. Camera
   availability and permission are reported by the shared capture model.
2. Choose **Flow Edge**, **Contour** or **Sketch**. Their native controls, framing,
   saved styles, Previous/Next and cancellation use the same code as embedded
   Studio. There is one drawing canvas. The nominal standalone pen width is
   0.4 mm for authoring; it is not measured material evidence or physical placement.
3. **Save Drawing** retains the exact native result. Promising/rejected feedback
   applies to an exact native attempt; a saved style is a recipe, not a preference
   vote. The Library's Photos and Drawings lists load metadata pages and selected
   payloads. **Edit in Studio** is offered for retained native candidates.
4. **Export Drawing** writes a JSON Drawing Package, conventionally named
   `Drawing.portraitdrawing.json`. In AdaptivePlotter, open **Drawing Exchange**,
   choose **Import Drawing**, inspect the source and program, then choose **Send
   to Drawing**. Continue through Drawing placement, material/paper setup and the
   existing Draw controls. Import or export performs
   no motion. Later Studio edits do not alter an exported or placed program.
5. For a retained run of an imported drawing, select that drawing in AdaptivePlotter's
   **Drawing Exchange**, then **Export Plot Result**. In Studio, **Import Plot
   Attachment** retains that evidence. Library **Plots**
   browses retained attachments in metadata pages of at most 100; **More Plots**
   explicitly loads the next page. This includes attachments whose drawing has not
   yet been imported. Selecting one displays its origin, recorded execution/observation
   status and available before/progress/after original frames. Controller completion
   alone does not prove visible ink or an unobstructed final photograph.

**Import Drawing** admits a validated package into the private library without
rerendering it. Its source, artist identifier/revision/settings and exact program
remain read-only. Unknown artists can be inspected and their supported exact
programs transferred; they do not acquire native editing controls. Explicit import
can restore an exactly matching transferred drawing that was deliberately deleted;
automatic/delayed paths cannot. Broader source-deletion tombstones remain effective.
Conflicting identities or corrupt assets are refused with an explanation.

The embedded workspace remains available in AdaptivePlotter, with **Send to
Drawing** retaining its direct handoff and existing telemetry. Standalone Studio
has no connection, calibration, motion, paper-clearance or Learning controls.
Quit cancels file/browser work, stops camera/rendering and awaits pending durable
library writes before the process exits.

## Storage ownership

Standalone data lives under:

```text
~/Library/Application Support/PortraitStudio/PortraitLibrary/
```

This is a fresh private store, with `library-v1.sqlite` metadata and immutable
payload/assets managed by the shared `PortraitLibrary` owner. It never uses
AdaptivePlotter's default store or its production DrawingEvidence root. Each app
owns one writer; do not point them at the same writable SQLite database. No live
library clone or production migration is performed by this separation. Import
photos or Drawing Packages to populate Studio. Preserve the whole private store
when backing it up with the app closed, not just a live SQLite file.

The reusable in-process record remains `SavedDrawing`. Native records retain
`PortraitCandidate` source/raster/recipe and native identity. Imported records hold
the immutable `DrawingPackage` and its origin; they are not invented candidates or
parallel mutable history objects. Native capture UUIDs distinguish occurrences even
when image bytes and rendered candidate hashes are equal. Returned attachments
link to that exact occurrence; an unrelated selected photo is never substituted.

## Version-one exchange

Both files are self-contained, versioned JSON envelopes. Embedded `Data` is encoded
as base64. Assets carry their media type, exact bytes and SHA-256, with dimensions
for images. There are no external file paths to resolve and no shared database
connection. Import validates the envelope, bounds and identity before durable
publication; duplicate identical imports are idempotent.

Version one requires `DrawingPackage.program.source.kind == "portrait"`.
External artists must construct that program kind with their retained source and
result provenance. Import never relabels a program or rewrites its hash to satisfy
admission; unsupported program kinds are refused. This preserves the existing
portrait-provenance requirement at Drawing handoff.

| Value | Retained content |
| --- | --- |
| `DrawingOriginReference` | Producer library UUID, capture-occurrence UUID, artist/native result ID, result-record SHA-256, and exact `DrawingProgram.contentHash`. |
| `DrawingPackage` schema 1 | Origin, exact `DrawingProgram`, created-at/title, original result-record JSON, authoring source image, artist input, artist identifier/revision/settings, preview, and optional legacy candidate JSON. |
| `PlotAttachment` schema 1 | Origin, producer evidence-archive UUID, run UUID, terminal record UUID, exact record JSON/hash, and original referenced media assets. |
| `SavedDrawing` | Canonical local record used by browsing and Drawing handoff, containing either native authoring provenance or the immutable transferred package. |

The program hash includes IDs, provenance, styles, stroke order and point order as
well as coordinates. Transfer preserves the exact current authoring source bytes.
The existing photo importer may scale and reencode a JPEG as PNG; transfer does
not claim to recover the original camera/JPEG file. Artist input is retained
separately from the source and can be structured raster data. Preview images are
presentation only and cannot replace the exact program or source.

Drawing files are capped at 128 MiB encoded and 64 MiB embedded, with source/input/
preview caps of 32/16/8 MiB, at most 10,000 strokes and 250,000 points. Images are
limited to 8,192 pixels per dimension and 33,554,432 pixels total. Plot files are capped
at 384 MiB encoded and 256 MiB media, with at most 128 originals and 64 MiB per
original. UI file reads check size before allocation and remain bounded if a file
grows during reading; codecs independently enforce their limits.

Plot media originals are pixel buffers interpreted using the exact retained frame
reference: dimensions, row stride, pixel format, frame/camera identity, capture
time and byte hash. They are not assumed to be PNG/JPEG. Missing original media is
reported according to the retained record's coverage; no current camera image is
substituted. An attachment can precede its drawing and link later by exact identity.
It remains inspection data and cannot resume a run, admit motion, accept Learning,
or clear possible-ink/no-redraw state in the plotter's raw evidence owner.

## Reproducibility and limits

The annotated local tag `portrait-studio-baseline-2026-10-11` names the pre-extraction
baseline. Keep the frozen counts and hashes in the
[README baseline procedure](../README.md#portrait-studio-development-baseline).
`make portrait-baseline-check` compares all three existing artists against those
values; `PORTRAIT_BASELINE_OUTPUT` writes observed exports without rewriting the
reference. A deliberate renderer change needs its own reviewed comparison and
new version/reference, not an automatic expected-hash refresh.

## Local experimental SwiftSketch

**Artists** keeps Flow Edge, Contour and Sketch available with their own native
Studio controls and adds an explicit experimental SwiftSketch choice. The local
worker runs one request at a time, with two CPU threads, a 600-second timeout and
6 GiB memory cap. Each generation reloads its models; the measured subprocess time
is not a native click-to-paint measurement or a resident-worker latency claim.
**Cancel** settles the worker before replacement work. Changing/deleting the
selected source invalidates its admission token synchronously. A committed drawing
retains its truthful job outcome after late cancellation; only stale presentation
is suppressed. Every scheduled status remains in the experiment journal, including
failed, cancelled and unsupported outcomes. Conversion refusals retain raw curves
and worker bytes and do not create a drawing.

The app discovers an explicitly installed local runtime under
`~/Library/Application Support/PortraitStudio/SwiftSketchRuntime/`, containing
`venv/bin/python`, `adapter/worker.py`, `manifest.json` and `proof.json`. Availability
requires a successful local inference receipt matching the exact worker and model
manifest hashes, plus present bounded local assets and required upstream files.
Missing assets or a mismatched worker/manifest receipt disable availability. This
cheap readiness check does not certify unchanged weight bytes or runtime versions;
each generation verifies all official asset hashes and supported versions before
inference. The app performs no network fetch. The runtime and pretrained assets stay external to the repository
and app bundle. Upstream code and model redistribution are not granted by this
integration. A different local installation can be selected using absolute
`PORTRAIT_SWIFTSKETCH_PYTHON`, `PORTRAIT_SWIFTSKETCH_WORKER`,
`PORTRAIT_SWIFTSKETCH_MANIFEST` and `PORTRAIT_SWIFTSKETCH_PROOF` environment paths;
`PORTRAIT_SWIFTSKETCH_ATTEMPTS` optionally chooses a separate retained attempt root.
A partially declared override is unavailable rather than silently completed.

Select a retained photo in **Studio**, then choose **Artists** → **SwiftSketch**.
Declare nominal field/pen dimensions and optional human subject/photographic-session
identities with provenance before **Generate SwiftSketch**. Blank identities remain
unknown and unassigned. The source/capture/hash/revision, settings, paired seed 42,
derived input and conversion context are frozen for that request. Native preparation
uses the full EXIF-oriented retained source, an explicit sRGB conversion, white alpha
composition and uniform 1024-square fit/pad. The fixed mask policy is no segmentation.
The three options are unchanged, gamma 0.8 and contrast 1.15 about 0.5 on encoded
sRGB channels. Generation success does not establish likeness or mask usefulness.

Accepted ordered open cubics retain their raw representation and compile uniformly
with an explicit image-to-field affine, no stretch, clipping, closure, merging or
reordering. Physical flattening tolerance is min(0.05 mm, nominal pen width / 4),
with bounded depth/point counts and deterministic geometry IDs. The exact package
enters the canonical drawing library before **View in Library** or **Export Drawing**.
The canonical producer library UUID persists across results; capture occurrence is
preserved. Future edits never modify that saved program.

## Immutable review and experiment export

1. In **Library**, select a retained native or imported drawing and choose **Use as
   First Drawing**. Select another result from the same capture and exact source,
   with the same nominal pen-width set, then **Compare with First Drawing**.
2. **Review** keeps the original visible and presents randomized A/B sides. Their
   common-scale display PNGs are frozen from the exact programs with one scale,
   declared common field/pen and no stretching. Package thumbnails are retained
   separately. Each side shows its stroke/point budgets and nominal dimensions;
   unknown pen qualification remains unknown.
3. Choose **Overall preference** first, using **A**, **B**, **Tie**, **Neither** or
   **Skip**. Other judgment dimensions are optional explicit observations. Unanswered
   dimensions remain absent. Skip is distinct from rejection; no age score is inferred.
   Reviewer identity is optional and blank remains unknown. Reopening a comparison
   restores its exact A/B order and append-only label head.
4. The Library's **Evaluation groups** records human subject and photographic-session
   identifiers with declaration provenance and a fixed split. Acquisition UUIDs do
   not supply those meanings. Unknown groups stay unassigned; connected subject,
   session, source, capture and ancestry groups cannot cross assigned splits.
   Declarations are immutable once saved and do not prove photographic independence.
5. **Export Dataset** writes a new folder of content-addressed assets plus a manifest.
   It includes exact source/derived/raw/program/package/preview bytes, comparison
   transforms/hashes, worker requests/environments/statuses, explicit ratings and
   plot-origin links. The exporter checks identities/integrity and refuses an existing
   destination or a destination inside the live library. It does not overwrite prior
   snapshots. This is retained-byte replay, not deterministic regeneration or training.

## Retained feasibility pilot

The October 12 feasibility evidence is retained under
`~/Documents/PortraitStudio-Milestone-2026-10-12/`. Its original `pilot-v1` tree
preserves the frozen Python manifest, selected source snapshot, all 18 requests,
supervisor receipts and outputs. The coordinator selected six distinct retained
sources by evenly spaced positions in ordered metadata before outputs, excluding
two smoke sources. Subject/session groups and actual capture times remain unknown;
selection does not establish independent subjects or a quality-based split. Read-only
inspection found distance/angle/backlight variation, an occluded face/hand and a
multiple-face frame. Those are descriptive input difficulties; the full-frame
no-segmentation pipeline has no designated-subject proof.

The pilot's Pillow revision preserves the full oriented source and pads it to the
maximum original source dimension without resizing before CLIP224. That exact input
is distinct from native authoring's CoreGraphics 1024-square preparation. Exact
retained PNG replay does not claim those two preparations regenerate equal bytes.
Native ingestion of the original external outputs is explicitly retrospective:
original absolute request clocks remain unknown, original manifest/request bytes
are retained, and physical conversion/comparison dimensions are declared at ingestion.
Controlled native baselines use the same retained padded square input, 100 × 100 mm
field and nominal 0.4 mm pen, with fixed native defaults, face crop/background removal
off and no head transform. Those are controlled comparisons, not tuned ordinary
Studio framing or a quality conclusion. Artist comparisons and paired preprocessing
comparisons remain separate.

Open the retained disposable `PilotLibrary` explicitly to make human judgments:

```sh
open -n "$HOME/Documents/PortraitStudio-Milestone-2026-10-12/PortraitStudio.app" --args \
  --review-library "$HOME/Documents/PortraitStudio-Milestone-2026-10-12/PilotLibrary"
```

Review-library mode starts in **Review**, discovers cameras without capture and
uses an exclusive local writer lease. It rejects production/evidence roots,
default Studio-library aliases, linked SQLite/WAL/SHM files and another writer of the same review library;
a refusal never falls back to a writable default. Normal launch still uses the
normal private Studio store. This option opens a nominated existing disposable
library; it does not clone or migrate production data.

The opt-in software integration test reads retained outputs without running another
model job, creates exact canonical packages and unlabeled comparison pairs, reopens
and exchanges them, and exports a new dataset. `PORTRAIT_REAL_PILOT_ROOT` selects its
retained evidence root. Default test runs skip it. Its report and dataset preserve
all worker/conversion failures. Human evaluation must still supply the actual
preference labels; zero ratings support no likeness/preprocessing improvement,
learned preprocessor, held-out quality or subject-generalization claim.

The retained corrected snapshot has 36 exact drawings, 12 paired preprocessing
comparisons and 18 native-versus-SwiftSketch comparisons, with no human ratings.
The earlier inverted common-preview snapshot is explicitly archived as
`v1-inverted-preview`; it is not a human evaluation set. The corrected display
revision preserves all exact authored program hashes and ordinary package previews.
The independent `FailureDataset` contains a retained post-input fault-injection
receipt, with mock inference explicitly declared and no drawing package. It is
failure-retention evidence, separate from the 18 real successful model jobs.

Current receipts in [Current Evidence](CURRENT_EVIDENCE.md) distinguish protocol,
software round trips, real CPU inference and bundle verification from native
interaction/camera and attended physical evidence. No software receipt establishes
ink quality, actual pen dimensions, an unobstructed final photograph or camera
availability. Training, tuning, permanent independent held-out human evaluation and
physical acceptance remain unfinished [Roadmap](ROADMAP.md) work.
