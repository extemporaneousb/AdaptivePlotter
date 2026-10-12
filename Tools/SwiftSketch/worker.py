#!/usr/bin/env python3
"""One request, local-only CPU SwiftSketch adapter. No weights or upstream code bundled."""
import argparse
import hashlib
import importlib.metadata
import json
import math
import os
from pathlib import Path
import platform
import resource
import subprocess
import sys
import time
import types

REVISION = "swiftsketch-cpu-adapter-v2-pinned-failure-context"
UPSTREAM_COMMIT = "6f9fa8654711b9a5d3022b08a59835f0dda08f40"
# Trusted adapter constants. The external manifest declares paths, never pin authority.
OFFICIAL_ASSET_SHA256 = {
    "diffusion": "a0bbd4a767fcbd74669d7fbd505d924b7dc02be0fb68ac8163fef2d08be88803",
    "diffusion_args": "ec7f3f4b921950347f7e091dc50083fdac94efa5bd0de5e3372b8e614d8b3e48",
    "refinement": "200a61bbaebac8eb8678125a7915c2ad1a5b5dea14be0bf5c3c446751d09b1a1",
    "refinement_args": "9fa16fcfc578fe827a576eb5ad6e8367aa248a666c8990bf4076f126721898e7",
    "clip": "8fa8567bab74a42d41c5915025a8e4538c3bdbe8804a470a72f30b0d94fab599",
}
OFFICIAL_PIN_FILE_SHA256 = "97dce1f20581530cd0dfbd83f6ea21c7a86155cebbbccc6bb8cdb5fd0f2816c4"
RUNTIME_VERSIONS = {"torch": "2.2.2", "torchvision": "0.17.2", "numpy": "1.26.4", "Pillow": "10.4.0"}
MAX_IMAGE_BYTES = 16 * 1024 * 1024
MAX_RESPONSE_BYTES = 2 * 1024 * 1024
VARIANTS = ("unchanged", "gamma08", "contrast115")


def digest(path):
    value = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def write_json(path, value):
    data = json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    if len(data) > MAX_RESPONSE_BYTES:
        raise ValueError("metadata exceeds protocol bound")
    destination = Path(path)
    pending = destination.with_name(destination.name+".pending")
    pending.write_bytes(data)
    pending.replace(destination)


class FailureContext(dict):
    def __init__(self, value, destination=None):
        super().__init__(value)
        self.destination = destination


def checkpoint_context(provenance, phase=None):
    if provenance is None:
        return
    if phase:
        provenance["phase"] = phase
    destination = getattr(provenance, "destination", None)
    if destination is not None:
        write_json(destination, provenance)


def validate_request(request):
    if request.get("schema_version") != 1:
        raise ValueError("unsupported request version")
    import uuid
    uuid.UUID(request["request_id"])
    if request.get("preprocessing") not in VARIANTS:
        raise ValueError("unsupported preprocessing")
    if request.get("mask_policy") != "fixed-input-no-segmentation-v1":
        raise ValueError("unsupported mask policy: supply a frozen masked input PNG")
    if request.get("seed") != 42:
        raise ValueError("pilot seed must be 42")
    path = Path(request["input_path"])
    if not path.is_absolute() or not path.is_file() or path.stat().st_size > MAX_IMAGE_BYTES:
        raise ValueError("input must be a bounded absolute local PNG path")
    if digest(path) != request["input_sha256"]:
        raise ValueError("input hash mismatch")


def initial_provenance(destination=None):
    versions = {}
    for package, expected in RUNTIME_VERSIONS.items():
        try:
            observed = importlib.metadata.version(package)
            observation = "observed"
        except importlib.metadata.PackageNotFoundError:
            observed = None
            observation = "missing"
        versions[package] = {"expected": expected, "observed": observed, "observation": observation}
    packages = sorted({distribution.metadata.get("Name", "unknown")+"=="+distribution.version
                       for distribution in importlib.metadata.distributions()})
    return FailureContext({"schema_version": 1, "adapter_revision": REVISION,
        "adapter_sha256": digest(__file__), "upstream_commit": UPSTREAM_COMMIT,
        "pin_authority": "trusted-adapter-constants", "official_asset_sha256": OFFICIAL_ASSET_SHA256,
        "phase": "request-read", "status": "in-progress", "failure": None,
        "request": {}, "request_validation": "unknown", "model_manifest": None,
        "model_manifest_observation": "unknown", "upstream_head": None,
        "upstream_head_observation": "unknown", "upstream_source_hashes": {},
        "upstream_source_observation": "unknown", "effective_settings": None,
        "effective_settings_observation": "unknown",
        "preprocessing_equations": {"gamma08": "round(255*(u**0.8))", "contrast115": "round(255*clamp((u-0.5)*1.15+0.5,0,1))"},
        "input_policy": "Caller-frozen square crop/pad and fixed mask. No segmentation or remote code; encoded sRGB LUT then upstream CLIP224 resize/normalization.",
        "adapter_changes": ["torch.device(cpu),2threads,eval+inference_mode", "tensor-only sampling excludes raster/training dependencies", "local pinned CLIP layer3 feature map equals upstream feature-list index3", "retain both raw tensors before deterministic conversion"],
        "model_assets": {key: {"expected_sha256": value, "declared_sha256": None,
            "observed_sha256": None, "path": None, "observation": "unknown"}
            for key, value in OFFICIAL_ASSET_SHA256.items()},
        "environment": {"python": sys.version, "platform": platform.platform(),
            "packages": packages, "distribution_versions": versions,
            "runtime_import_versions": {"observation": "unknown", "versions": None}},
        "outputs": {}}, destination)


def validate_manifest(manifest, provenance=None):
    if manifest.get("schema_version") != 1 or manifest.get("upstream_commit") != UPSTREAM_COMMIT:
        raise ValueError("unsupported model manifest")
    # Inspect every expected asset even when an earlier asset is unavailable/mismatched.
    failures = []
    for key, expected in OFFICIAL_ASSET_SHA256.items():
        observation = {"expected_sha256": expected, "declared_sha256": None,
                       "observed_sha256": None, "path": None, "observation": "unknown"}
        try:
            asset = manifest["assets"][key]
            observation.update(declared_sha256=asset.get("sha256"), path=asset.get("path"))
            path = Path(asset["path"])
            if not path.is_absolute() or path.is_symlink() or not path.is_file():
                observation["observation"] = "missing-or-unsupported"
                raise FileNotFoundError("missing or unsupported local model asset: " + key)
            maximum = 64*1024 if key.endswith("_args") else 512*1024*1024
            if not 0 < path.stat().st_size <= maximum:
                observation["observation"] = "outside-size-bound"
                raise ValueError("model asset size exceeds bound: " + key)
            observed = digest(path)
            observation.update(observed_sha256=observed, observation="observed")
            if asset.get("sha256") != expected:
                observation["observation"] = "declared-pin-mismatch"
                raise ValueError("official pretrained pin mismatch: " + key)
            if observed != expected:
                observation["observation"] = "actual-byte-mismatch"
                raise ValueError("official pretrained bytes mismatch: " + key)
            observation["observation"] = "verified"
        except (KeyError, TypeError, ValueError, FileNotFoundError) as error:
            failures.append(error)
        if provenance is not None:
            provenance["model_assets"][key] = observation
            checkpoint_context(provenance)
    if failures:
        raise failures[0]
    root = Path(manifest["upstream_root"])
    if not root.is_absolute():
        raise ValueError("upstream root must be absolute")
    head = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    if provenance is not None:
        provenance.update(upstream_head=head, upstream_head_observation="observed")
        checkpoint_context(provenance)
    if head != UPSTREAM_COMMIT:
        raise ValueError("upstream pin mismatch")
    if subprocess.check_output(["git", "-C", str(root), "status", "--porcelain", "--untracked-files=no"], text=True).strip():
        raise ValueError("upstream tracked source is modified")
    if provenance is not None:
        files = subprocess.check_output(["git", "-C", str(root), "ls-files", "*.py"], text=True).splitlines()
        provenance["upstream_source_hashes"] = {name: digest(root/name) for name in files}
        provenance["upstream_source_observation"] = "verified-pinned-tracked-source"
        checkpoint_context(provenance)
    return root


def prepare_input(request, destination):
    from PIL import Image, ImageOps
    Image.MAX_IMAGE_PIXELS = 32 * 1024 * 1024
    with Image.open(request["input_path"]) as original:
        if original.format != "PNG" or original.width > 8192 or original.height > 8192 or original.width*original.height > 32*1024*1024:
            raise ValueError("input encoding or dimensions unsupported")
        oriented = ImageOps.exif_transpose(original)
        rgba = oriented.convert("RGBA")
        image = Image.new("RGBA", rgba.size, "white")
        image.alpha_composite(rgba)
        image = image.convert("RGB")
        if image.width != image.height:
            raise ValueError("input must be a frozen square crop or padded square")
        variant = request["preprocessing"]
        if variant == "gamma08":
            lut = [round(255 * ((i / 255) ** 0.8)) for i in range(256)]
        elif variant == "contrast115":
            lut = [round(255 * min(1, max(0, (i / 255 - 0.5) * 1.15 + 0.5))) for i in range(256)]
        else:
            lut = list(range(256))
        if variant != "unchanged":
            image = image.point(lut * 3)
        # This exact RGB PNG is retained before CLIP's fixed resize+normalization.
        image.save(destination, format="PNG")
        return image


def inference_shims():
    """Exclude raster/training dependencies; fail if inference unexpectedly calls them."""
    def unsupported(*args, **kwargs):
        raise RuntimeError("unexpected upstream raster/training call in tensor-only adapter")
    shim = types.ModuleType("utils.sketch_utils")
    def get_features_dim(kind):
        if kind != "CLIPMiddle_layer4":
            raise ValueError("only checkpoint CLIP layer4 features supported")
        return (1024, 14)
    shim.get_features_dim = get_features_dim
    for name in ("rander_image_from_points", "render_image_from_norm_points", "log_model_prediction", "log_diffusion_process_to_wandb"):
        setattr(shim, name, unsupported)
    sys.modules[shim.__name__] = shim
    loss = types.ModuleType("diffusion.Loss_computation")
    loss.Loss = unsupported
    sys.modules[loss.__name__] = loss


def effective_args(path):
    from argparse import Namespace
    settings = json.loads(Path(path).read_text())
    defaults = {"arch": "trans_dec", "emb_trans_dec": 0, "normalize_model_output": 1,
                "layers": 8, "heads": 4, "latent_dim": 512, "cond_mask_prob": 0.1,
                "unconstrained": False, "image_features_type": "CLIPMiddle_layer4",
                "scaling_factor": 2.0, "num_paths": 32, "canvas_width": 224,
                "canvas_height": 224, "noise_schedule": "cosine", "cos_power": 0.4,
                "diffusion_steps": 50, "sigma_small": True, "model_mean_type": "start_x"}
    defaults.update(settings)
    defaults.update(generate=True, use_wandb=0, device="cpu")
    if defaults["num_paths"] != 32 or defaults["canvas_width"] != 224 or defaults["canvas_height"] != 224:
        raise ValueError("unsupported checkpoint stroke/canvas shape")
    if defaults["image_features_type"] != "CLIPMiddle_layer4" or defaults["unconstrained"]:
        raise ValueError("unsupported conditioning checkpoint")
    return Namespace(**defaults)


def validate_runtime_versions(versions, provenance=None):
    if provenance is not None:
        provenance["environment"]["runtime_import_versions"] = {"observation": "observed", "versions": versions}
        checkpoint_context(provenance)
    if any(versions.get(name, "").split("+")[0] != expected for name, expected in RUNTIME_VERSIONS.items()):
        raise ValueError("CPU runtime versions differ from pinned torch2.2.2/torchvision0.17.2/numpy1.26.4/Pillow10.4.0")


def run_inference(manifest, image, provenance=None):
    started = time.monotonic()
    checkpoint_context(provenance, "runtime-import")
    import numpy as np
    import torch
    import torchvision
    import PIL
    from torchvision import transforms
    validate_runtime_versions({"torch": torch.__version__, "torchvision": torchvision.__version__,
        "numpy": np.__version__, "Pillow": PIL.__version__}, provenance)
    torch.set_num_threads(2)
    torch.set_num_interop_threads(2)
    torch.manual_seed(42)
    np.random.seed(42)
    import random
    random.seed(42)
    root = Path(manifest["upstream_root"])
    sys.path.insert(0, str(root / "SwiftSketch"))
    inference_shims()
    checkpoint_context(provenance, "upstream-import")
    from utils.model_util import create_model_and_diffusion, create_model, load_model_wo_clip
    from model.cfg_sampler import ClassifierFreeSampleModel
    import CLIP_.clip as clip
    stages = {"cold_process_import_seconds": time.monotonic()-started}
    device = torch.device("cpu")
    assets = manifest["assets"]
    args = effective_args(assets["diffusion_args"]["path"])
    refine_args = effective_args(assets["refinement_args"]["path"])
    if provenance is not None:
        provenance.update(phase="checkpoint-load", effective_settings={"diffusion": vars(args), "refinement": vars(refine_args)},
            effective_settings_observation="observed")
        checkpoint_context(provenance)
    model, diffusion = create_model_and_diffusion(args)
    load_model_wo_clip(model, torch.load(assets["diffusion"]["path"], map_location=device, weights_only=True))
    model.to(device).eval()
    refine = create_model(refine_args)
    load_model_wo_clip(refine, torch.load(assets["refinement"]["path"], map_location=device, weights_only=True))
    refine.to(device).eval()
    feature_model, clip_preprocess = clip.load(assets["clip"]["path"], device=device, jit=False)
    stages["model_load_seconds"] = time.monotonic()-started-stages["cold_process_import_seconds"]
    feature_model.eval()
    visual = feature_model.visual
    transform = transforms.Compose([transforms.Resize((224, 224)), transforms.ToTensor()])
    normalization = transforms.Compose([clip_preprocess.transforms[0], clip_preprocess.transforms[1], clip_preprocess.transforms[-1]])
    guidance = 2.5 if args.cond_mask_prob else 1.0
    if guidance != 1:
        model = ClassifierFreeSampleModel(model)
    with torch.inference_mode():
        checkpoint_context(provenance, "feature-extraction")
        feature_started = time.monotonic()
        x = normalization(transform(image)).unsqueeze(0).to(device).type(visual.conv1.weight.dtype)
        for conv, bn in ((visual.conv1, visual.bn1), (visual.conv2, visual.bn2), (visual.conv3, visual.bn3)):
            x = visual.relu(bn(conv(x)))
        x = visual.avgpool(x)
        features = visual.layer3(visual.layer2(visual.layer1(x))).float()
        stages["feature_extraction_seconds"] = time.monotonic()-feature_started
        del feature_model, visual, x
        scale = torch.ones(1, device=device) * guidance if guidance != 1 else None
        diffusion_started = time.monotonic()
        checkpoint_context(provenance, "diffusion-inference")
        sampled = diffusion.p_sample_loop(model, (1, 32, 4, 2), noise=None,
            clip_denoised=False, image_features=features, scale=scale,
            progress=False, skip_timesteps=0, init_image=None, dump_steps=None, const_noise=False)
        stages["diffusion_inference_seconds"] = time.monotonic()-diffusion_started
        refine_started = time.monotonic()
        checkpoint_context(provenance, "refinement")
        refined = refine(x=sampled, timesteps=torch.zeros(1, dtype=torch.long, device=device), image_features=features)
        stages["refinement_seconds"] = time.monotonic()-refine_started
        raw_diffusion = sampled[0].tolist()
        raw_refined = refined[0].tolist()
        denormalized = ((refined[0] / args.scaling_factor + 1) / 2 * 224).tolist()
    if not all(math.isfinite(v) for curves in (raw_diffusion, raw_refined, denormalized) for curve in curves for point in curve for v in point):
        raise ValueError("nonfinite model output")
    return {"schema_version": 1, "canvas_width": 224, "canvas_height": 224,
            "coordinate_space": "image-pixels-y-down", "curve_kind": "ordered-open-cubic",
            "diffusion_normalized": raw_diffusion, "refined_normalized": raw_refined,
            "refined": denormalized}, {"diffusion": vars(args), "refinement": vars(refine_args), "guidance": guidance,
            "stage_timings": stages,
            "cache_policy": "One request subprocess reloads every model; repeated launches may use OS filesystem cache. No in-memory warm reuse.",
            "versions": {"torch": torch.__version__, "torchvision": torchvision.__version__, "numpy": np.__version__}}


def preview(raw, path):
    from PIL import Image, ImageDraw
    canvas = Image.new("RGB", (448, 448), "white")
    draw = ImageDraw.Draw(canvas)
    for curve in raw["refined"]:
        points = []
        for step in range(257):
            t = step / 256
            u = 1 - t
            points.append(tuple(2 * (u**3 * curve[0][axis] + 3*u*u*t*curve[1][axis] + 3*u*t*t*curve[2][axis] + t**3*curve[3][axis]) for axis in (0, 1)))
        draw.line(points, fill="black", width=2)
    canvas.save(path, format="PNG")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    output = Path(args.output).resolve()
    if output.exists():
        raise SystemExit("output directory already exists; preserve existing attempt")
    output.mkdir(parents=True)
    started = time.monotonic()
    request = {}
    status = "failed"
    provenance = initial_provenance(output / "provenance.json")
    checkpoint_context(provenance)
    try:
        if Path(args.request).stat().st_size > 64 * 1024:
            raise ValueError("request exceeds protocol bound")
        request = json.loads(Path(args.request).read_text())
        provenance.update(request=request, phase="request-validation")
        checkpoint_context(provenance)
        validate_request(request)
        provenance.update(request_validation="verified", phase="manifest-read")
        checkpoint_context(provenance)
        if Path(args.manifest).stat().st_size > 64 * 1024:
            raise ValueError("manifest exceeds protocol bound")
        manifest = json.loads(Path(args.manifest).read_text())
        provenance.update(model_manifest=manifest, model_manifest_observation="observed", phase="pin-validation")
        checkpoint_context(provenance)
        root = validate_manifest(manifest, provenance)
        write_json(output / "provenance.json", provenance)
        checkpoint_context(provenance, "input-preparation")
        input_started = time.monotonic()
        image = prepare_input(request, output / "artist-input.png")
        input_seconds = time.monotonic()-input_started
        provenance["outputs"]["artist-input.png"] = digest(output / "artist-input.png")
        write_json(output / "provenance.json", provenance)
        raw, effective = run_inference(manifest, image, provenance)
        effective["stage_timings"]["input_preparation_seconds"] = input_seconds
        write_json(output / "raw-curves.json", raw)
        checkpoint_context(provenance, "preview-render")
        preview(raw, output / "preview.png")
        provenance.update({"effective_settings": effective, "effective_settings_observation": "observed",
            "outputs": {name: digest(output/name) for name in ("artist-input.png", "raw-curves.json", "preview.png")}})
        status = "succeeded"
        provenance["phase"] = "complete"
        reason = None
    except (FileNotFoundError, ModuleNotFoundError) as error:
        status = "unavailable"
        reason = str(error)
    except Exception as error:
        reason = type(error).__name__ + ": " + str(error)
    provenance.update(status=status, elapsed_seconds=time.monotonic()-started,
        peak_rss_bytes=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss if sys.platform == "darwin" else resource.getrusage(resource.RUSAGE_SELF).ru_maxrss*1024)
    if status != "succeeded":
        provenance["failure"] = {"phase": provenance["phase"], "reason": reason, "status": status}
        if provenance["phase"] == "request-validation":
            provenance["request_validation"] = "rejected"
    write_json(output / "provenance.json", provenance)
    response = {"schema_version": 1, "request_id": request.get("request_id"), "status": status,
        "reason": reason, "elapsed_seconds": time.monotonic()-started,
        "peak_rss_bytes": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss if sys.platform == "darwin" else resource.getrusage(resource.RUSAGE_SELF).ru_maxrss*1024,
        "files": {name: digest(output/name) for name in ("artist-input.png", "raw-curves.json", "preview.png", "provenance.json") if (output/name).is_file()}}
    write_json(output / "response.json", response)
    print(json.dumps(response, sort_keys=True), flush=True)
    return 0 if status == "succeeded" else 2


if __name__ == "__main__":
    sys.exit(main())
