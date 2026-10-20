#!/usr/bin/env python3
"""生成采集点摆放表 assets/data/gather_spots.json。

为什么需要脚本而不是手写坐标：
  行走矩形（zones.json 的 walk[].rects）覆盖的是「可站立面」，屋顶、室内、甲板
  常常在同一个矩形里。手写坐标很容易把采集点埋进建筑内部——第一版就是这样。

做法：
  1. 取区块所有行走矩形的世界坐标；
  2. 从烘焙实例算出每栋建筑的 AABB，标出「站在甲板上会撞到东西」的格子；
  3. 在矩形内按 0.35m 网格采样，要求离矩形边缘 ≥0.6m、离建筑 ≥0.55m；
  4. 按「离建筑越远越好 + 彼此分散」挑点。

用法：python3 tools/build_gather_spots.py
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib_bake import Bake, BAKED  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ZONES_JSON = os.path.join(ROOT, "assets", "data", "zones.json")
MODELS = os.path.join(ROOT, "assets", "models", "zones")
OUT = os.path.join(ROOT, "assets", "data", "gather_spots.json")

GRID = 0.35
EDGE_MARGIN = 0.60
CLEARANCE = 0.55
SPOT_GAP = 1.8

# 每个区块要摆什么：kind / 数量 / 额外字段
PLAN = {
    "zone1": [
        {"kind": "shell", "amount": 2, "priority": 2},
        {"kind": "rope", "amount": 1},
        {"kind": "wood", "amount": 2},
    ],
    "zone2": [
        {"kind": "parts", "amount": 1},
        {"kind": "glass", "amount": 1,
         "requires_site": "yokohama_station", "requires_level": 2},
    ],
    "zone3": [
        {"kind": "seed", "amount": 2},
        {"kind": "wood", "amount": 1},
    ],
    "zone4": [
        {"kind": "shell", "amount": 2},
    ],
    "zone5": [
        {"kind": "fish", "amount": 1},
        {"kind": "seed", "amount": 1},
    ],
}

ZONE_KEY = {
    "zone1": "zone1_home_harbor",
    "zone2": "zone2_yokohama_station",
    "zone3": "zone3_arc_farm",
    "zone4": "zone4_far_shore",
    "zone5": "zone5_aqua_platform",
}


def rect_distance(px, pz, rect):
    x0, x1, z0, z1 = rect
    dx = max(0.0, max(x0 - px, px - x1))
    dz = max(0.0, max(z0 - pz, pz - z1))
    return math.hypot(dx, dz)


def load_boxes(bake, zones):
    """所有实例的世界 AABB（只保留区块范围内的，省时间）。"""
    xs = [r[0] for z in zones for w in z.get("walk", []) for r in w["rects"]]
    xe = [r[1] for z in zones for w in z.get("walk", []) for r in w["rects"]]
    zs = [r[2] for z in zones for w in z.get("walk", []) for r in w["rects"]]
    ze = [r[3] for z in zones for w in z.get("walk", []) for r in w["rects"]]
    lo_x, hi_x = min(xs) - 6, max(xe) + 6
    lo_z, hi_z = min(zs) - 6, max(ze) + 6

    boxes = []
    for bi, _k, off in bake.instances():
        g = bake.geom_stats[bake.scene["batches"][bi]["geom"]]
        m = bake.inst_matrix(off)
        ox, oy, oz = m[3]
        if not (lo_x <= ox <= hi_x and lo_z <= oz <= hi_z):
            continue
        mn = [1e9, 1e9, 1e9]
        mx = [-1e9, -1e9, -1e9]
        for cx in (g["min"][0], g["max"][0]):
            for cy in (g["min"][1], g["max"][1]):
                for cz in (g["min"][2], g["max"][2]):
                    wx = m[0][0] * cx + m[1][0] * cy + m[2][0] * cz + m[3][0]
                    wy = m[0][1] * cx + m[1][1] * cy + m[2][1] * cz + m[3][1]
                    wz = m[0][2] * cx + m[1][2] * cy + m[2][2] * cz + m[3][2]
                    for i, v in enumerate((wx, wy, wz)):
                        mn[i] = min(mn[i], v)
                        mx[i] = max(mx[i], v)
        boxes.append((mn[0], mn[2], mx[0], mx[2], mn[1], mx[1]))
    return boxes


def blocked(px, pz, deck_y, boxes):
    """站在甲板上时，这个点上方 0.3~2.4m 是否有建筑占据。"""
    for (x0, z0, x1, z1, y0, y1) in boxes:
        if px < x0 - 0.02 or px > x1 + 0.02 or pz < z0 - 0.02 or pz > z1 + 0.02:
            continue
        if y1 > deck_y + 0.30 and y0 < deck_y + 2.4:
            return True
    return False


def clearance(px, pz, deck_y, boxes):
    best = 9.0
    for (x0, z0, x1, z1, y0, y1) in boxes:
        if y1 <= deck_y + 0.30 or y0 >= deck_y + 2.4:
            continue
        d = rect_distance(px, pz, (x0, x1, z0, z1))
        best = min(best, d)
    return best


def pick_zone(zone, boxes, jobs):
    # 一个区块可能有多个行走面（主甲板 y=2.15、打捞台 y=1.33），
    # 高度必须跟着各自的 walk.y 走，否则采集点会悬在另一层甲板上方。
    rects = []
    for w in zone.get("walk", []):
        y = float(w["y"])
        for r in w["rects"]:
            rects.append(((float(r[0]), float(r[1]), float(r[2]), float(r[3])), y))
    if not rects:
        return []

    candidates = []
    for ridx, (rect, y) in enumerate(rects):
        x0, x1, z0, z1 = rect
        x = x0 + EDGE_MARGIN
        while x <= x1 - EDGE_MARGIN:
            z = z0 + EDGE_MARGIN
            while z <= z1 - EDGE_MARGIN:
                if not blocked(x, z, y, boxes):
                    c = clearance(x, z, y, boxes)
                    if c >= CLEARANCE:
                        candidates.append((x, z, c, ridx, y))
                z += GRID
            x += GRID
    if not candidates:
        return []

    chosen = []
    used_rects = set()
    for job in jobs:
        # 优先换一块甲板：几个采集点挤在同一条窄边上既难看也难走位。
        order = [i for i in range(len(rects)) if i not in used_rects]
        order += [i for i in range(len(rects)) if i in used_rects]
        best = None
        for ridx in order:
            for (x, z, c, cr, y) in candidates:
                if cr != ridx:
                    continue
                if any(math.hypot(x - cx, z - cz) < SPOT_GAP for cx, cz, *_ in chosen):
                    continue
                if best is None or c > best[2]:
                    best = (x, z, c, ridx, y)
            if best is not None:
                break
        if best is None:
            continue
        chosen.append((best[0], best[1], best[2], best[4]))
        used_rects.add(best[3])
    rows = []
    for i, (x, z, _s, y) in enumerate(chosen):
        job = jobs[i]
        row = {
            "id": "%s_%s" % (zone["id"], job["kind"]),
            "zone": zone["id"],
            "kind": job["kind"],
            "amount": job["amount"],
            "x": round(x, 2),
            "y": round(y, 2),
            "z": round(z, 2),
        }
        if "priority" in job:
            row["priority"] = job["priority"]
        if "requires_site" in job:
            row["requires_site"] = job["requires_site"]
            row["requires_level"] = job["requires_level"]
        rows.append(row)
    return rows


def main():
    zones = json.load(open(ZONES_JSON))
    bake = Bake(BAKED)
    boxes = load_boxes(bake, zones)
    out = []
    for zone in zones:
        jobs = PLAN.get(zone["id"], [])
        if not jobs:
            continue
        rows = pick_zone(zone, boxes, jobs)
        print("%s: %d 个候选点 -> %d 个采集点" % (zone["id"], len(rows), len(rows)))
        for r in rows:
            print("   %-18s (%6.2f, %5.2f, %6.2f)" % (r["id"], r["x"], r["y"], r["z"]))
        out.extend(rows)

    # id 去重（同一区块同一种资源可能排两个，加序号）
    seen = {}
    for r in out:
        base = r["id"]
        if base in seen:
            seen[base] += 1
            r["id"] = "%s_%d" % (base, seen[base])
        else:
            seen[base] = 1

    doc = {
        "_note": "由 tools/build_gather_spots.py 生成：世界坐标，已避开建筑与水面边缘。",
        "spots": out,
    }
    json.dump(doc, open(OUT, "w"), ensure_ascii=False, indent=1)
    print("-> %s（%d 个）" % (OUT, len(out)))


if __name__ == "__main__":
    main()
