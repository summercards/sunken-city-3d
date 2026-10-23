#!/usr/bin/env python3
"""生成菜箱摆放表 assets/data/plots.json。

规则与采集点/建造牌同源（**不要手写坐标**）：
  1. 取所属区块的行走矩形（世界坐标）；
  2. 用烘焙实例 AABB 标出会撞到建筑的格子；
  3. 0.35m 网格采样，要求离边缘 ≥0.6m、离建筑 ≥0.6m，且 1.3×0.9m 的箱子四角都在空地上；
  4. 尽量靠近对应的建造牌（菜箱是那栋房子的附属物），但至少隔 1.8m，
     否则两个可交互物会同时进半径、按 E 抢焦点；
  5. 与采集点、其他菜箱也各自隔开。

产出字段：id / name / zone / x / y / z / yaw / requires_site / requires_level。
作物定义在 assets/data/crops.json，这里不写死种什么。

用法：python3 tools/build_plots.py
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib_bake import Bake, BAKED  # noqa: E402
import build_gather_spots as G  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ZONES_JSON = os.path.join(ROOT, "assets", "data", "zones.json")
GATHER_JSON = os.path.join(ROOT, "assets", "data", "gather_spots.json")
SITES_JSON = os.path.join(ROOT, "assets", "data", "build_sites.json")
OUT = os.path.join(ROOT, "assets", "data", "plots.json")

GRID = 0.35
EDGE_MARGIN = 0.60
CLEARANCE = 0.60
# 箱子尺寸 1.3 × 0.9（含边框），采样时按四角 + 长边中点检查。
HALF_X = 0.66
HALF_Z = 0.46
NEAR_SIGN = 1.8
AVOID_SPOT = 2.2  # 与采集点/建造牌的净距：交互半径 2.8m，太近会互相抢焦点
PLOT_GAP = 2.0
SEARCH_RADIUS = 6.0

PLAN = [
    {"id": "home_plot", "name": "木屋菜箱", "zone": "zone1", "near": "home_cabin",
     "requires_site": "home_cabin", "requires_level": 2},
    # 屋顶北侧只有这一块空地，而种子采集点就在旁边：1.7m 是能放下的极限，
    # 再远就只能把菜箱塞进建筑里了。
    {"id": "farm_plot_a", "name": "农场菜箱", "zone": "zone3", "near": "rooftop_planter",
     "requires_site": "rooftop_planter", "requires_level": 1, "avoid_spot": 1.7},
    # 圆弧屋顶只有北侧一条空地放得下一只箱子，第二块放到远海的补给浮台：
    # 长航途中也能补种，比在屋顶硬塞两只更合理。
    {"id": "platform_plot", "name": "浮台菜箱", "zone": "zone5", "near": None,
     "requires_site": "", "requires_level": 0},
]


def load_points(path, key, zone_key="zone"):
    out = {}
    try:
        data = json.load(open(path))
    except FileNotFoundError:
        return out
    for row in data.get(key, []):
        out.setdefault(str(row.get(zone_key, "")), []).append(
            (float(row["x"]), float(row["z"])))
    return out


def footprint_free(x, z, y, boxes):
    pts = [(x + dx, z + dz)
           for dx in (-HALF_X, 0.0, HALF_X)
           for dz in (-HALF_Z, 0.0, HALF_Z)]
    return not any(G.blocked(px, pz, y, boxes) for px, pz in pts)


def pick(boxes, zone, anchor, avoid, avoid_spot=AVOID_SPOT):
    best = None
    for w in zone.get("walk", []):
        y = float(w["y"])
        for r in w["rects"]:
            x0, x1, z0, z1 = (float(v) for v in r)
            x = x0 + EDGE_MARGIN
            while x <= x1 - EDGE_MARGIN:
                z = z0 + EDGE_MARGIN
                while z <= z1 - EDGE_MARGIN:
                    dx = x - anchor[0]
                    dz = z - anchor[1]
                    d_anchor = math.hypot(dx, dz)
                    if d_anchor > SEARCH_RADIUS or d_anchor < NEAR_SIGN:
                        z += GRID
                        continue
                    if G.blocked(x, z, y, boxes) or not footprint_free(x, z, y, boxes):
                        z += GRID
                        continue
                    c = G.clearance(x, z, y, boxes)
                    if c < CLEARANCE:
                        z += GRID
                        continue
                    if any(math.hypot(x - ax, z - az) < avoid_spot for ax, az in avoid):
                        z += GRID
                        continue
                    # 越靠近那栋房子越好，同时别贴着水边。
                    score = d_anchor - c * 0.5
                    if best is None or score < best[0]:
                        best = (score, x, y, z, c)
                    z += GRID
                x += GRID
    return best


def main():
    from authored_guard import require_candidate
    require_candidate(__file__)
    zones = {z["id"]: z for z in json.load(open(ZONES_JSON))}
    signs = {s["id"]: s for s in json.load(open(SITES_JSON)).get("sites", [])}
    spots = load_points(GATHER_JSON, "spots")
    bake = Bake(BAKED)
    boxes = G.load_boxes(bake, list(zones.values()))

    taken = {}
    rows = []
    for job in PLAN:
        zone = zones.get(job["zone"])
        sign = signs.get(job["near"]) if job.get("near") else None
        if zone is None:
            print("  [warn] 缺少区块：%s" % job["id"])
            continue
        anchor = (float(sign["x"]), float(sign["z"])) if sign else (
            float(zone.get("camera", [0, 0, 0])[0]), float(zone.get("camera", [0, 0, 0])[2]))
        avoid = list(spots.get(job["zone"], [])) \
            + ([(float(sign["x"]), float(sign["z"]))] if sign else []) \
            + taken.get(job["zone"], [])
        got = pick(boxes, zone, anchor, avoid, float(job.get("avoid_spot", AVOID_SPOT)))
        if got is None:
            print("  [warn] %s 找不到空地" % job["id"])
            continue
        _score, x, y, z, c = got
        taken.setdefault(job["zone"], []).append((x, z))
        rows.append({
            "id": job["id"],
            "name": job["name"],
            "zone": job["zone"],
            "x": round(x, 2),
            "y": round(y, 2),
            "z": round(z, 2),
            "yaw": 0.0,
            "requires_site": job["requires_site"],
            "requires_level": job["requires_level"],
            "clearance": round(c, 2),
        })

    json.dump({"_note": "由 tools/build_plots.py 生成：世界坐标，已避开建筑/采集点/建造牌。",
               "plots": rows}, open(OUT, "w"), ensure_ascii=False, indent=1)
    for r in rows:
        print("%-14s %s  (%6.2f, %5.2f, %6.2f)  离建筑 %.2fm" % (
            r["id"], r["zone"], r["x"], r["y"], r["z"], r["clearance"]))
    print("plots:", len(rows))


if __name__ == "__main__":
    main()
