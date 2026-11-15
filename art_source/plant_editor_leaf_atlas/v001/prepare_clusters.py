"""Derive a 512px leaf-cluster atlas from the Image 2.6 single-leaf source.
No synthesized replacement leaves: all RGBA leaves come from the original image.
"""
from pathlib import Path
import hashlib, json, math
from PIL import Image, ImageEnhance, ImageFilter
ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "image26_leaf_atlas_source.png"
OUTPUT = ROOT.parents[2] / "godot/assets/textures/vegetation/workshop_leaf_clusters_512.png"
source = Image.open(SOURCE).convert("RGBA")
atlas = Image.new("RGBA", (512, 512))
# Stem positions and rotations make a small fan, not a rectangular clump.
layout = [(-63, 300, 220, 0.80), (63, 300, 220, 0.84),
          (-42, 280, 250, 0.91), (42, 280, 250, 0.94),
          (-22, 260, 280, 1.00), (22, 260, 280, 1.05),
          (-52, 350, 210, 0.92), (52, 350, 210, 0.96),
          (0, 340, 300, 1.06)]
rows = []
for tile, species in enumerate(["camphor", "maple", "birch", "vine"]):
    quadrant = source.crop((tile % 2 * 512, tile // 2 * 512, tile % 2 * 512 + 512, tile // 2 * 512 + 512))
    box = quadrant.getchannel("A").point(lambda x: 255 if x >= 108 else 0).getbbox()
    leaf = quadrant.crop(box)
    canvas = Image.new("RGBA", (768, 768))
    for angle, base_y, length, shade in layout:
        width = max(20, round(length * leaf.width / leaf.height))
        blade = leaf.convert("RGBa").resize((width, length), Image.Resampling.LANCZOS).convert("RGBA")
        alpha = blade.getchannel("A")
        blade = ImageEnhance.Brightness(blade.convert("RGB")).enhance(shade).convert("RGBA")
        blade.putalpha(alpha)
        patch = Image.new("RGBA", (768, 768))
        # Rotate around the lower stem, then place all leaves into their shared cluster.
        patch.paste(blade, (384 - width // 2, 450 - length))
        patch = patch.rotate(angle, Image.Resampling.BICUBIC, center=(384, 450))
        dx = round(math.copysign((abs(angle) / 63) * 18, -angle)) if angle else 0
        shifted = Image.new("RGBA", (768, 768))
        shifted.alpha_composite(patch, (dx, base_y - 340 + 50))
        canvas.alpha_composite(shifted)
    bounds = canvas.getchannel("A").point(lambda x: 255 if x >= 108 else 0).getbbox()
    compact = canvas.crop(bounds).convert("RGBa").resize((240,240), Image.Resampling.LANCZOS).convert("RGBA")
    for _ in range(3):
        box = compact.getchannel("A").point(lambda x: 255 if x >= 108 else 0).getbbox()
        if box == (0,0,240,240): break
        compact = compact.crop(box).convert("RGBa").resize((240,240),Image.Resampling.LANCZOS).convert("RGBA")
    result = Image.new("RGBA", (256,256))
    result.paste(compact,(8,8))
    alpha = result.getchannel("A")
    rgb = result.convert("RGB")
    valid = alpha.point(lambda x: 255 if x > 0 else 0)
    for _ in range(8):
        rgb = Image.composite(rgb, rgb.filter(ImageFilter.MaxFilter(3)), valid)
        valid = valid.filter(ImageFilter.MaxFilter(3))
    result = rgb.convert("RGBA"); result.putalpha(alpha)
    assert alpha.point(lambda x: 255 if x >=108 else 0).getbbox() == (8,8,248,248)
    atlas.paste(result, (tile%2*256,tile//2*256))
    rows.append({"species":species,"leaves_per_cluster":len(layout),"alpha_coverage":sum(x>=108 for x in alpha.get_flattened_data())/65536,"source_cluster_bounds":bounds})
atlas.save(OUTPUT,optimize=True)
report={"source":str(SOURCE),"source_sha256":hashlib.sha256(SOURCE.read_bytes()).hexdigest(),"runtime":str(OUTPUT),"runtime_sha256":hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),"size":[512,512],"bytes":OUTPUT.stat().st_size,"process":"9 transformed source leaves composited per tile, premultiplied Lanczos downsample, alpha retained, 8px RGB dilation","tiles":rows}
(ROOT/"clusters_preparation.json").write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report,ensure_ascii=False,indent=2))
