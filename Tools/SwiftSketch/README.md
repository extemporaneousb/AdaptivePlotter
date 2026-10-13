# Local SwiftSketch CPU adapter

This code runs one pinned pretrained request in a separate Python process. It
does not bundle upstream code, model weights, a Python environment, segmentation
models, or training code. SwiftSketch is an optional artist; native renderers
remain independent of this runtime. Model inference success does not establish
portrait quality, machine readiness or ink evidence.

The pin is `6f9fa8654711b9a5d3022b08a59835f0dda08f40`; exact diffusion, refinement,
their `args.json` and CLIP RN101 hashes are in `model-pins.json`. Root SwiftSketch
code and checkpoint redistribution permission was not established at that pin.
These files stay externally fetched on the user's machine. CLIP's upstream
subtree declares MIT. The stock BRIA RMBG segmentation model is not used. Current native face preparation
uses the operating system's Vision person segmentation, retaining its exact mask;
this adapter still performs no segmentation.

Create a fresh Python 3.9 environment at its final external path and install
`requirements-cpu.txt`. Intel macOS uses PyTorch 2.2.2 and torchvision 0.17.2.
`acquire.py --directory ABSOLUTE_EXTERNAL_ASSET_DIRECTORY --upstream-root
ABSOLUTE_EXTERNAL_SOURCE_DIRECTORY` fetches the public pinned sources and checks
all learned model/configuration hashes against trusted adapter constants. The
acquisition pin file's exact bytes are also checked; a caller-updated manifest is
not authority to change model identity. It extracts inference checkpoints only.
Existing source trees, manifests and attempts are preserved.

The worker accepts `--request request.json --manifest manifest.json --output
NEW_ATTEMPT_DIRECTORY`. The version-one request has `schema_version:1`, UUID
`request_id`, absolute local `input_path`, exact `input_sha256`, paired `seed:42`,
`preprocessing` (`unchanged`, `gamma08` or `contrast115`), and
`mask_policy:"fixed-input-no-segmentation-v1"`. Input is one bounded square PNG;
the caller owns source photo, EXIF orientation, deliberate crop or full-photo
padding, color conversion and a frozen mask. No remote image or executable input
is supported. No network access is needed for inference.

`prepare.py` documents the first milestone's historical full-photo policy: apply EXIF orientation,
composite alpha over white, convert a supplied ICC profile to sRGB (record the
assumption for an unprofiled input), retain the full oriented photo and center it
on an opaque white square. It performs no face crop or background segmentation.
The same fixed prepared input is used in every preprocessing arm. Gamma is
`u**0.8`; contrast is `clamp((u-0.5)*1.15+0.5,0,1)`, each applied in encoded sRGB
and rounded to 8 bits. The upstream CLIP 224-pixel resize and normalization then
produce the RN101 feature-list index 3 (1024 by 14 by 14).

The adapter imports the upstream tensor sampler and model, uses explicit CPU
devices, two threads, eval and inference mode, and excludes unused raster,
training and segmentation dependencies. Every process reloads the diffusion,
refinement and CLIP models. Repeated launches can benefit from filesystem cache;
they are not measurements of an in-memory warm model. Stage timings, effective
settings, packages, hashes and peak RSS are retained.

Terminal `response.json` reports succeeded, failed or unavailable and file hashes.
Atomic partial provenance is recorded before model import and at observed phases,
including expected/declared/observed asset hashes, runtime inventory and version
observations, explicit unknown states, input hash and terminal failure phase.
Timeout and cancellation can retain the last complete partial provenance file.
Success retains exact `artist-input.png`, `raw-curves.json` (both normalized
diffusion and refinement tensors plus refined 224-pixel control points),
`preview.png` (448 by 448), and `provenance.json`. Each of the 32 strokes is one
ordered open cubic with four xy control points. Failed and cancelled attempts
are review evidence and cannot become drawings through this protocol.

Use `run_bounded.py --python ABSOLUTE_PYTHON --worker ABSOLUTE_WORKER --request
ABSOLUTE_REQUEST --manifest ABSOLUTE_MANIFEST --output NEW_OUTPUT` for a measured
external request: at most 600 seconds, two CPU threads, 6 GiB observed RSS and an
8 MiB log. It terminates and reaps on a bound. `prove.py` accepts those same flags
plus `--proof NEW_PROOF_PATH`; it writes availability only after a real success
whose identity and output hashes match. The native client requires a matching
worker/manifest proof and present assets/source files for cheap availability.
This presence check does not certify unchanged bytes or runtime versions; every
generation checks all five official asset hashes and runtime versions again.
The client keeps one request active, runs blocking work away from the
main actor, enforces the same bounds, reaps cancellation and suppresses late results.

`SwiftSketchConverter` uniformly fits the square canvas into the declared mm
field, centers padding and flips y. It retains stroke order and open endpoints,
uses deterministic subdivision with tolerance `min(0.05 mm, penWidth/4)` and
bounded depth/points, and rejects unsupported, nonfinite or out-of-field curves.
It never silently clamps, closes or merges a stroke. Its settings receipt freezes
the affine and tolerance. A valid immutable result enters the existing
`DrawingPackage` and canonical `SavedDrawing` import path; review failures remain
separate records. Physical plotting still belongs to the main plotter app.

`pilot.py plan` freezes six distinct retained originals before any output, selects
evenly spaced positions in retained metadata order, records the source/capture/
acquisition identities and exact preparation, and leaves human subject/session
groups unassigned. Metadata order is not claimed to be actual capture chronology.
`pilot.py run` attempts the 18 paired arms once within a ten-minute total budget,
counts failures, preserves partial results, skips remaining arms after the budget,
and never substitutes images or tunes settings. This pilot measures feasibility
and preprocessing evidence; it does not supply human quality labels or training.

Protocol tests run without weights using `python3 -m unittest discover -s
Tools/SwiftSketch -p 'test_*.py'`. Pillow-only cases skip when unavailable. Swift
tests cover real physical flattening error, uniform fit and subprocess cancellation,
timeouts, stale identity and asset tamper fixtures. Those fixtures are not model
inference receipts.

## Shared native face pilot

`face_pilot.py plan` selects ten distinct retained originals before outputs, copies
their exact source/capture receipts from a read-only library and snapshots the first
pilot's file hashes. It performs no image preparation. The opt-in Swift harness
`PortraitStudioFacePilotTests` uses the production
`PortraitStudioArtistInput.prepare` to produce the fixed face frame, framed source,
foreground mask and final 1024-square input. The fixed frame uniformly scales the
face to 52% target height, center (50%, 54%) from the top left; aspect is preserved.
A missing or ambiguous face or unusable mask is retained as a refusal. Any explicit
visual box declaration is frozen before model outputs and never labels a subject.

Run the harness in `prepare`, inspect inputs, then run `freeze` before invoking
`face_pilot.py run --expected-manifest-sha256 ACCEPTED_SHA256`. Environment variables
are `PORTRAIT_FACE_PILOT_ROOT`,
`PORTRAIT_FACE_PILOT_PHASE` and optional `PORTRAIT_FACE_PILOT_PREPARATION_PASS`
(`prepared-v1` by default). New preparation passes preserve earlier refusals and
bytes. Freeze binds every actual native input/mask/metadata hash and artist setting.
The runner checks those frozen bytes and records exact worker/model identity and
supervisor admission clocks before each launch; internal worker start time remains
explicitly unknown. Only unchanged preprocessing, seed 42 is
scheduled: at most ten requests including unsupported/skipped/failed outcomes and
600 seconds total model wall budget. No replacement or automatic retry is allowed.
Worker `mask_policy:"fixed-input-no-segmentation-v1"` truthfully means the worker
receives a caller-masked fixed PNG and applies no additional segmentation.

The Swift `ingest` phase reads outputs without another model job and records all
forty scheduled outcomes (ten model, thirty native) in the canonical journal. All
four artists consume the same retained masked PNG. Fixed native defaults disable
secondary crop/background removal/head transform. Common geometry is 100mm square,
nominal 0.4mm pen. Only valid matched origins create comparisons, at most thirty;
failures reduce the count rather than being replaced. The fresh library/export starts
with zero human labels and unknown groups. It retains source, preparation, mask,
framed input, external request/manifest, raw/model output, canonical program, settings
and status evidence. Its external frozen manifest does not broaden the original
typed six-source/eighteen-job pilot API. `face_pilot.py preserve --root ABSOLUTE_ROOT`
rechecks the first pilot's complete source/library file inventory.
