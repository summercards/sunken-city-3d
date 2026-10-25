#!/usr/bin/env python3
"""Compare water colour between the Forward+ and gl_compatibility renders.

Usage:
    SEA_SHOT_DIR=new/fp  Godot --path godot --resolution 1440x900 \
        --script res://tools/capture_water_gain_probe.gd
    SEA_SHOT_DIR=new/gl  Godot --path godot --rendering-driver opengl3 \
        --resolution 1440x900 --script res://tools/capture_water_gain_probe.gd
    python3 scripts/measure_water_backend_parity.py new/fp new/gl

The Forward+ directory is the reference. Water pixels are picked from that
reference only (blue-dominant, low red, UI bands excluded) and the same mask is
applied to every gl_compatibility image, so the two sides measure the same
screen area even when the colour differs a lot.

Prints one row per gl image: mean colour plus mean absolute error against the
reference. The row with the smallest error is the coefficient to put into
RenderFlagsLib.water_emission_gain().
"""

import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image
except ImportError as exc:  # pragma: no cover - environment guard
    sys.exit("需要 numpy 与 pillow: %s" % exc)

# UI 会盖在水面上，按画面比例排掉左侧参数面板、顶部按钮带与底部按钮带。
UI_EXCLUDE = [
    (0.00, 0.18, 0.00, 0.64),   # 左侧面板
    (0.00, 1.00, 0.00, 0.10),   # 顶部
    (0.00, 1.00, 0.89, 1.00),   # 底部
    (0.26, 0.65, 0.00, 0.15),   # 顶部按钮
]


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)


def water_mask(ref):
    h, w, _ = ref.shape
    yy, xx = np.mgrid[0:h, 0:w]
    mask = (ref[:, :, 2] > ref[:, :, 0] + 40) & (ref[:, :, 0] < 40) & (ref[:, :, 1] > 60)
    for x0, x1, y0, y1 in UI_EXCLUDE:
        mask &= ~((xx >= x0 * w) & (xx < x1 * w) & (yy >= y0 * h) & (yy < y1 * h))
    return mask


def mean_of(img, mask):
    return np.array([img[:, :, i][mask].mean() for i in range(3)])


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    ref_dir, cand_dir = Path(argv[1]), Path(argv[2])
    ref_path = ref_dir / "gain-1.0.png"
    if not ref_path.exists():
        sys.exit("参考图不存在: %s" % ref_path)

    ref = load(ref_path)
    mask = water_mask(ref)
    if mask.sum() < 1000:
        sys.exit("参考图里认不出水面，检查机位或阈值")
    target = mean_of(ref, mask)
    print("参考 Forward+ : %s  水面像素 %d (%.1f%%)" % (
        target.round(1), mask.sum(), mask.sum() / mask.size * 100))

    rows = []
    for path in sorted(cand_dir.glob("gain-*.png")):
        label = path.stem[5:]
        measured = mean_of(load(path), mask)
        err = float(np.abs(measured - target).mean())
        rows.append((err, label, measured))
        print("  gl gain=%-14s %s  误差=%.2f" % (label, measured.round(1), err))

    if not rows:
        sys.exit("候选目录里没有 gain-*.png: %s" % cand_dir)
    err, gain, measured = min(rows)
    parts = gain.split("_")
    if len(parts) == 3:
        vec = "Vector3(%s, %s, %s)" % tuple(parts)
    else:
        vec = "Vector3(%s, %s, %s)" % (gain, gain, gain)
    print("\n最接近: gain=%s 水色=%s 误差=%.2f" % (gain, measured.round(1), err))
    print("即 RenderFlagsLib.water_emission_gain() 在 gl_compatibility 上返回 %s" % vec)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
