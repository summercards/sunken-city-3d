#!/usr/bin/env python3
"""生成水面岸线轮廓 assets/baked/shore.json（仅为离线兜底，不是正式阻挡源）。

正式阻挡已改为「每个组件自带的 BlockerSet」（见 src/world/blocker_set.gd，
校验 godot/tools/verify_blockers.gd）。本脚本生成的文件只在场景没有实例化时兜底，
不要再往里加新形状 —— 那正是 2026-10-26 修掉的那类空阻挡。

正式数据请用 `tools/capture_shore.cjs` 从网页版直接抓 —— 网页版用的是 zone.regions，
和 zones.json 的 walk.rects 不是同一份数据（圆楼那块差得最多），本脚本只能近似。

来源（与网页版 shoreOutline() 一致）：
  1. 区块可站立地块（zones.json 的 walk.rects）——甲板与水面相接的地方；
  2. 水街区的地标与外围废墟塔——数值抄自 sea/water-district.js：
       towers    specs = [x, z, w, d, top, type]
       landmarks round(-54,12) / residence(-30,40) / low(12,29)
     烘焙数据是按材质合并的，反推不出单栋楼，所以这里直接用原始定义。

改区块或水街区后重跑本脚本。
用法：python3 tools/make_shore.py
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BAKED = os.path.join(ROOT, "assets", "baked")
EDGE = 0.55          # 地块矩形比甲板略小，水线要落在外侧水里才看得见

zones = json.load(open(os.path.join(BAKED, "..", "data", "zones.json")))
water = 1.12

shapes = []

# 1) 区块地块
for z in zones:
    # zones.json 的 walk.rects 已经是世界坐标（zones.js 在运行时才加 origin）。
    # 这里再加一次 origin 会让水纹整套平移一个区块，波纹就漂在空水域上。
    for w in z.get("walk", []):
        for r in w["rects"]:
            cx = (r[0] + r[1]) * 0.5
            cz = (r[2] + r[3]) * 0.5
            hx = (r[1] - r[0]) * 0.5 + EDGE
            hz = (r[3] - r[2]) * 0.5 + EDGE
            shapes.append({"x": round(cx, 3), "z": round(cz, 3),
                           "hx": round(hx, 3), "hz": round(hz, 3), "round": False})

# 2) 外围废墟塔（water-district.js 的 specs，方塔）
for x, z, w, d, _top, _type in [
    [-19, -51, 6.4, 5.0, 4.4, 0],
    [31, -22, 5.8, 5.2, 5.4, 1],
    [39, 12, 5.2, 4.8, 3.4, 2],
    [-40, 21, 5.2, 4.4, 3.0, 3],
    [20, 43, 5.5, 4.5, 2.5, 1],
]:
    shapes.append({"x": float(x), "z": float(z),
                   "hx": w * 0.5, "hz": d * 0.5, "round": False})

# 3) 水街区地标
shapes.append({"x": -54.0, "z": 12.0, "hx": 5.35, "hz": 4.65, "round": True})   # 圆弧玻璃大厦
shapes.append({"x": -30.0, "z": 40.0, "hx": 3.70, "hz": 3.10, "round": False})  # 阳台住宅
shapes.append({"x": 12.0, "z": 29.0, "hx": 3.60, "hz": 3.20, "round": False})   # 沉没中庭

json.dump({"waterLevel": water, "shapes": shapes},
          open(os.path.join(BAKED, "shore.json"), "w"), ensure_ascii=False, indent=1)
print("shapes:", len(shapes))
