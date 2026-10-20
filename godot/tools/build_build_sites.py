#!/usr/bin/env python3
"""生成建造点摆放表 assets/data/build_sites.json。

和采集点一样，**不要手写坐标**：walk.rects 覆盖屋顶与室内，手写很容易把施工牌
塞进墙里。做法与 `build_gather_spots.py` 相同：

  1. 取该区块所有行走矩形（世界坐标）；
  2. 用烘焙实例 AABB 标出「会撞到建筑」的格子；
  3. 0.35m 网格采样，要求离边缘 ≥0.8m、离建筑 ≥0.9m（施工牌比采集物大一圈）；
  4. 在合格点里挑离区块镜头中心最近的——玩家一眼能看到它。

输出字段：id / name / zone / x / y / z / yaw / seconds（施工时长）。
费用仍写在 `scripts/economy.gd` 的 SITES 里，这里只管「牌子立在哪」。

用法：python3 tools/build_build_sites.py
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
OUT = os.path.join(ROOT, "assets", "data", "build_sites.json")
GATHER_JSON = os.path.join(ROOT, "assets", "data", "gather_spots.json")

EDGE_MARGIN = 0.80
CLEARANCE = 0.90
GRID = 0.35

# 每个建造点：先按 id 找区块，镜头中心用来挑「最显眼的空地」。
# seconds = 交付材料后的施工时长，等级越高越久（改这里即可，不用动代码）。
PLAN = [
    {"id": "home_cabin", "name": "太阳能木屋", "zone": "zone1", "seconds": [18.0, 30.0]},
    {"id": "yokohama_station", "name": "横滨沉没铁道", "zone": "zone2", "seconds": [22.0]},
    {"id": "rooftop_planter", "name": "圆弧屋顶农场", "zone": "zone3", "seconds": [20.0, 34.0]},
]


def load_avoid():
    """采集点位置：施工牌不能压在采集物上，否则按 E 会被牌子抢走焦点。"""
    out = {}
    try:
        data = json.load(open(GATHER_JSON))
    except FileNotFoundError:
        return out
    for row in data.get("spots", []):
        out.setdefault(str(row.get("zone", "")), []).append(
            (float(row["x"]), float(row["z"])))
    return out


def pick(boxes, zone, anchor, avoid):
    """先用严格间距找；窄甲板（zone2 只有一条边）退让到采集点的标准。"""
    for margin, clearance in ((EDGE_MARGIN, CLEARANCE), (0.55, 0.45), (0.40, 0.30)):
        got = _pick(boxes, zone, anchor, margin, clearance, avoid)
        if got is not None:
            return got
    return None


def _pick(boxes, zone, anchor, edge_margin, clearance_min, avoid):
    best = None
    for w in zone.get("walk", []):
        y = float(w["y"])
        for r in w["rects"]:
            x0, x1, z0, z1 = (float(v) for v in r)
            x = x0 + edge_margin
            while x <= x1 - edge_margin:
                z = z0 + edge_margin
                while z <= z1 - edge_margin:
                    if not G.blocked(x, z, y, boxes):
                        c = G.clearance(x, z, y, boxes)
                        # 牌子本体有 1m 宽：四个角都得在空地上，否则会插进墙里。
                        fits = not any(
                            G.blocked(x + dx, z + dz, y, boxes)
                            for dx in (-0.5, 0.5) for dz in (-0.3, 0.3))
                        if c >= clearance_min and fits and all(
                                math.hypot(x - ax, z - az) >= 2.2 for ax, az in avoid):
                            # 2.2m 是交互半径 2.8m 的余量：两个目标不能同时进焦点。
                            # 越显眼越好（离镜头中心近），同时别贴着水边。
                            score = math.hypot(x - anchor[0], z - anchor[2]) - c * 1.6
                            if best is None or score < best[0]:
                                best = (score, x, y, z, c)
                    z += GRID
                x += GRID
    return best


def main():
    zones = {z["id"]: z for z in json.load(open(ZONES_JSON))}
    avoid_all = load_avoid()
    bake = Bake(BAKED)
    boxes = G.load_boxes(bake, list(zones.values()))

    rows = []
    for job in PLAN:
        zone = zones.get(job["zone"])
        if zone is None:
            print("  [warn] 没有区块", job["zone"])
            continue
        got = pick(boxes, zone, zone.get("camera", [0, 0, 0]),
                   avoid_all.get(job["zone"], []))
        if got is None:
            print("  [warn] %s 找不到空地" % job["id"])
            continue
        _score, x, y, z, c = got
        rows.append({
            "id": job["id"],
            "name": job["name"],
            "zone": job["zone"],
            "x": round(x, 2),
            "y": round(y, 2),
            "z": round(z, 2),
            "yaw": 0.0,
            "seconds": job["seconds"],
            "clearance": round(c, 2),
        })

    json.dump({"sites": rows}, open(OUT, "w"), ensure_ascii=False, indent=1)
    for r in rows:
        print("%-18s %s  (%.1f, %.1f, %.1f)  离建筑 %.2fm" % (
            r["id"], r["zone"], r["x"], r["y"], r["z"], r["clearance"]))
    print("shapes:", len(rows))


if __name__ == "__main__":
    main()
