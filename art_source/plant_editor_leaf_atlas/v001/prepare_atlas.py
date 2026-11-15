"""Normalize the generated single-leaf atlas to the runtime UV contract.
Requires Pillow; never generates replacement artwork.
"""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageFilter

parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
source = Image.open(args.source).convert("RGBA")
if source.width != source.height or source.width < 1024:
    raise ValueError("Expected square generated source at least 1024 pixels")
if source.getchannel("A").getextrema()[0] == 255:
    raise ValueError("Source has no transparent alpha; inspect and matte before processing")
output = Image.new("RGBA", (512, 512))
metrics = []
for index, species in enumerate(["camphor", "maple", "birch", "vine"]):
    size = source.width // 2
    x, y = index % 2 * size, index // 2 * size
    tile = source.crop((x, y, x + size, y + size))
    mask = tile.getchannel("A").point(lambda a: 255 if a >= 108 else 0)
    bounds = mask.getbbox()
    if not bounds:
        raise ValueError(f"Empty alpha silhouette: {species}")
    # Normalize only non-empty silhouette. Geometry restores species aspect ratio.
    leaf = tile.crop(bounds)
    # Premultiplied resampling avoids dark fringes in transparent edges.
    leaf = leaf.convert("RGBa").resize((240, 240), Image.Resampling.LANCZOS).convert("RGBA")
    for _ in range(3):
        effective = leaf.getchannel("A").point(lambda a: 255 if a >= 108 else 0).getbbox()
        if effective == (0, 0, 240, 240):
            break
        leaf = leaf.crop(effective).convert("RGBa").resize((240, 240), Image.Resampling.LANCZOS).convert("RGBA")
    tile_out = Image.new("RGBA", (256, 256))
    tile_out.paste(leaf, (8, 8))
    # RGB-only dilation into transparent padding, alpha remains unchanged.
    alpha = tile_out.getchannel("A")
    rgb = tile_out.convert("RGB")
    valid = alpha.point(lambda a: 255 if a > 0 else 0)
    for _ in range(8):
        expanded = valid.filter(ImageFilter.MaxFilter(3))
        new_rgb = rgb.filter(ImageFilter.MaxFilter(3))
        rgb = Image.composite(rgb, new_rgb, valid)
        valid = expanded
    tile_out = rgb.convert("RGBA")
    tile_out.putalpha(alpha)
    bounds_out = alpha.point(lambda a: 255 if a >= 108 else 0).getbbox()
    if bounds_out != (8, 8, 248, 248):
        raise ValueError(f"Invalid effective silhouette: {species}: {bounds_out}")
    output.paste(tile_out, (index % 2 * 256, index // 2 * 256))
    metrics.append({"species": species, "source_bounds": bounds, "runtime_bounds": bounds_out,
                    "alpha_test_coverage": sum(a >= 108 for a in alpha.get_flattened_data()) / 65536})
args.output.parent.mkdir(parents=True, exist_ok=True)
output.save(args.output, optimize=True)
report = {"source": str(args.source), "source_size": source.size,
          "source_sha256": hashlib.sha256(args.source.read_bytes()).hexdigest(),
          "runtime": str(args.output), "runtime_size": output.size,
          "runtime_sha256": hashlib.sha256(args.output.read_bytes()).hexdigest(),
          "runtime_file_bytes": args.output.stat().st_size,
          "tiles": metrics, "filter": "premultiplied Lanczos with RGB-only 8px padding dilation",
          "rgba8_base_bytes": 512*512*4, "note": "Texture has transparent alpha; generated GPU mipmaps require import configuration"}
(args.source.parent / "preparation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
print(json.dumps(report, ensure_ascii=False, indent=2))
