# Portrait Studio

Status: current standalone operator and exchange-format guide. Product authority
remains in [Product Contract](PRODUCT_CONTRACT.md); module ownership is in
[Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md#package-topology). Future
artists, comparisons and learning belong to [Roadmap](ROADMAP.md).

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

Current receipts in [Current Evidence](CURRENT_EVIDENCE.md) distinguish software
round trips, fixtures and bundle verification from native interaction/camera and
attended physical evidence. This separation does not establish improved likeness,
camera quality, click-to-paint performance or ink quality. Generalized A/B/tie/
neither/skip review, SwiftSketch/Python workers, Bézier records, training exports
and learning runs are later extensions through versioned contracts.

For useful comparisons, hold the source, nominal pen width and final drawing size
constant and record changes to artist/settings explicitly. Current +/- feedback
labels exact native attempts. Future ratings must target stable origin/result IDs
and, for physical judgments, the exact run ID and explicit human score; plotting
does not automatically backpropagate a training signal. A future artist worker can
consume retained input/settings and return a versioned package. Dataset export and
training infrastructure remain unbuilt.
