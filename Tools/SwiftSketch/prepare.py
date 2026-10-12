"""Freeze original bytes and the one explicit, full-photo square input policy."""
import hashlib
import io
import json
from pathlib import Path

POLICY = "full-photo-oriented-srgb-white-square-pad-no-segmentation-v1"


def prepare(source, destination):
    from PIL import Image, ImageCms, ImageOps
    source = Path(source)
    data = source.read_bytes()
    if not 0 < len(data) <= 32 * 1024 * 1024:
        raise ValueError("source bytes exceed bound")
    Image.MAX_IMAGE_PIXELS = 32 * 1024 * 1024
    with Image.open(io.BytesIO(data)) as original:
        if original.width > 8192 or original.height > 8192:
            raise ValueError("source dimensions exceed bound")
        orientation = original.getexif().get(274, 1)
        profile = original.info.get("icc_profile")
        oriented = ImageOps.exif_transpose(original)
        rgba = oriented.convert("RGBA")
        flat = Image.new("RGBA", rgba.size, "white")
        flat.alpha_composite(rgba)
        rgb = flat.convert("RGB")
        if profile:
            rgb = ImageCms.profileToProfile(rgb, ImageCms.ImageCmsProfile(io.BytesIO(profile)),
                ImageCms.createProfile("sRGB"), outputMode="RGB")
        side = max(rgb.size)
        offset = ((side-rgb.width)//2, (side-rgb.height)//2)
        square = Image.new("RGB", (side, side), "white")
        square.paste(rgb, offset)
        square.save(destination, format="PNG")
        return {"policy": POLICY, "source_sha256": hashlib.sha256(data).hexdigest(),
            "original_dimensions": [original.width, original.height], "original_encoding": original.format,
            "original_exif_orientation": orientation, "orientation_operation": "Pillow.ImageOps.exif_transpose",
            "original_icc_sha256": hashlib.sha256(profile).hexdigest() if profile else None,
            "color_operation": "ICC-to-sRGB" if profile else "unprofiled-input-assumed-sRGB",
            "alpha_operation": "composite-over-opaque-white-before-RGB",
            "oriented_dimensions": list(rgb.size), "oriented_crop_xywh": [0, 0, rgb.width, rgb.height],
            "square_dimensions": [side, side], "pad_offset_xy": list(offset),
            "fixed_mask": "opaque-all-ones-no-segmentation", "resize": "none-before-upstream-CLIP224",
            "input_sha256": hashlib.sha256(Path(destination).read_bytes()).hexdigest()}
