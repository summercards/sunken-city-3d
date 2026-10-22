#!/usr/bin/env python3
"""比较 --flicker 拍的两帧，判断「闪动」是深度竞争还是动画位移。

判读规则：
  · z-fighting：差异成片贴在同一个平面上，且跳变幅度大（整块从 A 材质色跳到 B 材质色），
    连通块数量多、面积小、形状碎。
  · 动画元素（鱼/气泡/草/玩家）：差异沿运动方向成条，边缘平滑，连通块大而少。
  · 焦散/雾（随时间平移）：低幅值、大范围，用阈值 >0.06 就能滤掉。

用法（跑在托管 venv 里，那里有 PIL + numpy）：
  ~/.workbuddy/binaries/python/envs/default/bin/python tools/compare_flicker.py
  ... compare_flicker.py outputs/flicker-a.png outputs/flicker-b.png
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "outputs")


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0


def blocks(mask, min_area=6):
    """连通域（4 邻域）面积列表，迭代式栈，避免递归爆栈。"""
    h, w = mask.shape
    seen = np.zeros((h, w), dtype=bool)
    sizes = []
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys, xs):
        if seen[y0, x0]:
            continue
        stack = [(y0, x0)]
        seen[y0, x0] = True
        n = 0
        while stack:
            y, x = stack.pop()
            n += 1
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        if n >= min_area:
            sizes.append(n)
    return sorted(sizes, reverse=True)


def main():
    a_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(OUT, "flicker-a.png")
    b_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(OUT, "flicker-b.png")
    a, b = load(a_path), load(b_path)
    n = min(a.shape[0], b.shape[0])
    m = min(a.shape[1], b.shape[1])
    a, b = a[:n, :m], b[:n, :m]
    d = np.abs(a - b).max(axis=2)

    total = d.size
    soft = d > 0.02
    mid = d > 0.06
    hard = d > 0.18
    print("帧间差异（%d×%d）" % (m, n))
    print("  平均 |Δ|        %.4f" % d.mean())
    print("  >0.02 像素      %.2f%%" % (100.0 * soft.sum() / total))
    print("  >0.06 像素      %.2f%%  ← 焦散/雾不该超过这个量级" % (100.0 * mid.sum() / total))
    print("  >0.18 像素      %.2f%%  ← 硬跳变（材质/深度竞争）" % (100.0 * hard.sum() / total))

    for label, mask in ((">0.06", mid), (">0.18", hard)):
        if mask.sum() == 0:
            print("  %s 连通块：无" % label)
            continue
        sizes = blocks(mask)
        if not sizes:
            print("  %s 连通块：只有 <6px 的碎点" % label)
            continue
        arr = np.array(sizes)
        print("  %s 连通块 %5d 个  最大 %6d px  中位 %5d px  面积合计 %.2f%%" % (
            label, len(sizes), arr.max(), int(np.median(arr)),
            100.0 * arr.sum() / total))

    # 差异图：红色=硬跳变，琥珀=轻微，深底=无变化
    vis = np.zeros((n, m, 3), dtype=np.uint8)
    vis[:, :] = (16, 23, 30)
    vis[soft] = (255, 214, 64)
    vis[hard] = (255, 46, 46)
    Image.fromarray(vis).save(os.path.join(OUT, "flicker-diff.png"))
    print("  差异图 → outputs/flicker-diff.png")


if __name__ == "__main__":
    main()
