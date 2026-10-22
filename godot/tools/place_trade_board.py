#!/usr/bin/env python3
"""生成码头订单板的摆放表 assets/data/trade_board.json。

和采集点 / 施工牌一样，**不要手写坐标**：订单板是一块立起来的板子，
手写很容易插进甲板边缘的栏杆或建筑里。做法沿用同一套求解：

  1. 取该区块所有行走矩形（世界坐标）；
  2. 用烘焙实例 AABB 标出「会撞到建筑」的格子；
  3. 0.35m 网格采样，要求离边缘 ≥0.8m、离建筑 ≥0.9m，板子四角都得在空地上；
  4. 离所有已占用的交互目标（采集点 / 施工牌 / 菜箱 / 绞盘）≥2.6m：
     订单板的交互半径是 2.6m，离太近会互相抢焦点；
  5. 在合格点里挑离「交易码头」地标最近的一个——玩家一眼能看到它。

输出：id / name / zone / x / y / z / yaw / clearance。

用法：python3 tools/place_trade_board.py
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib_bake import Bake, BAKED  # noqa: E402
import build_gather_spots as G  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "assets", "data")
OUT = os.path.join(DATA, "trade_board.json")

ZONE = "zone1"
EDGE_MARGIN = 0.80
CLEARANCE = 0.90
GRID = 0.35
## 与已占用目标的间距。订单板焦点半径 2.6m，两个目标不能同时进焦点。
SEPARATION = 2.6


def load_occupied():
    """所有会抢焦点的点位：采集点、施工牌、菜箱，外加打捞台绞盘。"""
    pts = []
    for name, key in (("gather_spots.json", "spots"),
                      ("build_sites.json", "sites"),
                      ("plots.json", "plots")):
        path = os.path.join(DATA, name)
        try:
            data = json.load(open(path))
        except FileNotFoundError:
            continue
        for row in data.get(key, []):
            if str(row.get("zone", "")) != ZONE:
                continue
            pts.append((str(row.get("id", "?")), float(row["x"]), float(row["z"])))
    # 绞盘按 main._salvage_winch_spot 的规则推（打捞台矩形西边缘内缩 0.7m）
    zones = {z["id"]: z for z in json.load(open(os.path.join(DATA, "zones.json")))}
    for w in zones[ZONE].get("walk", []):
        if str(w.get("id", "")) != "zone1_salvage":
            continue
        r = w["rects"][0]
        pts.append(("salvage_winch", float(r[0]) + 0.7, (float(r[2]) + float(r[3])) / 2.0))
    return pts


def trade_anchor(zone):
    """区块里的 harb：kind=dock 的地标。找不到就退回镜头中心。"""
    for h in zone.get("harbor", []):
        if str(h.get("kind", "")) == "dock":
            return h["point"]
    return zone.get("camera", [0, 0, 0])


def pick(boxes, zone, anchor, occupied):
    best = None
    for w in zone.get("walk", []):
        y = float(w["y"])
        for r in w["rects"]:
            x0, x1, z0, z1 = (float(v) for v in r)
            x = x0 + EDGE_MARGIN
            while x <= x1 - EDGE_MARGIN:
                z = z0 + EDGE_MARGIN
                while z <= z1 - EDGE_MARGIN:
                    # 板子 1.1m 宽、0.25m 深，四角都要落在空地上。
                    fits = not any(
                        G.blocked(x + dx, z + dz, y, boxes)
                        for dx in (-0.55, 0.55) for dz in (-0.22, 0.22))
                    if fits:
                        c = G.clearance(x, z, y, boxes)
                        far = all(math.hypot(x - ox, z - oz) >= SEPARATION
                                  for _id, ox, oz in occupied)
                        if c >= CLEARANCE and far:
                            score = math.hypot(x - anchor[0], z - anchor[2]) - c * 0.8
                            if best is None or score < best[0]:
                                best = (score, x, y, z, c)
                    z += GRID
                x += GRID
    return best


def main():
    zones = {z["id"]: z for z in json.load(open(os.path.join(DATA, "zones.json")))}
    zone = zones[ZONE]
    bake = Bake(BAKED)
    boxes = G.load_boxes(bake, list(zones.values()))
    occupied = load_occupied()
    anchor = trade_anchor(zone)
    got = pick(boxes, zone, anchor, occupied)
    if got is None:
        print("[warn] 找不到能立订单板的空地")
        return
    _score, x, y, z, c = got
    nearest = min(occupied, key=lambda p: math.hypot(x - p[1], z - p[2]))
    # 板面朝最近的空处（背对码头），玩家走上来正好正对板子。
    yaw = round(math.atan2(anchor[0] - x, anchor[2] - z), 3)
    row = {
        "id": "dock_orders",
        "name": "码头订单板",
        "zone": ZONE,
        "x": round(x, 2),
        "y": round(y, 2),
        "z": round(z, 2),
        "yaw": yaw,
        "clearance": round(c, 2),
    }
    json.dump({"boards": [row]}, open(OUT, "w"), ensure_ascii=False, indent=1)
    print("%-12s %s (%.2f, %.2f, %.2f) yaw=%.2f 离建筑 %.2fm 最近占用=%s %.2fm" % (
        row["id"], row["zone"], row["x"], row["y"], row["z"], row["yaw"], row["clearance"],
        nearest[0], math.hypot(x - nearest[1], z - nearest[2])))


if __name__ == "__main__":
    main()
