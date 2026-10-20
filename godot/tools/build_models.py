#!/usr/bin/env python3
"""反向烘焙：把网页版烘焙出来的实例几何，还原成可替换的 glb 模型资产。

输入：assets/baked/（scene.json + geoms*.bin + instances.bin + textures/）
输出：assets/models/

为什么叫「反向」：
  网页版本身是运行时程序化建场景，没有可编辑的模型文件。烘焙只留下了
  「几何原型 + 实例矩阵」。这个脚本把它反推回标准 glTF 2.0：
  每个实例的变换烘进顶点，再按语义单元切成独立模型，原点落在单元底部中心。
  于是任何 DCC（Blender / Maya / Godot 自带导入）打开都能直接改。

产出结构：
  assets/models/zones/<zone_key>/manifest.json      单元清单（摆放 + 材质槽 + 来源）
  assets/models/zones/<zone_key>/<zone_key>.glb     整区总装（整体替换用）
  assets/models/zones/<zone_key>/units/unit_NN.glb  语义单元（单栋建筑/构件）
  assets/models/world/environment/*.glb             外围沉没街区（按空间分块）

用法：
  python3 tools/build_models.py              # 五个区块
  python3 tools/build_models.py --env        # 连外围环境一起
  python3 tools/build_models.py --zone zone1
"""
import argparse
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib_bake import BAKED, Bake, assign_zone  # noqa: E402
from lib_glb import Glb  # noqa: E402
import naming  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(ROOT, "assets", "models")

# ---------------------------------------------------------------- 单元划分参数
# 种子 = 体量足够大的实例（建筑主体）。种子之间至少隔 SEED_GAP，
# 其余实例按「到最近种子的水平距离」归组，超过 UNIT_RADIUS 的归到 detail。
SEED_MIN_FOOTPRINT = 2.8
SEED_MIN_HEIGHT = 1.2
SEED_GAP = 4.0
UNIT_RADIUS = 7.0
DETAIL_MAX_VERTS = 180000   # 杂项单元超过这个顶点数才按网格再切

ENV_CELL = 48.0          # 外围环境分块尺寸（900 万顶点，整块会到 400MB）
ENV_MAX_VERTS = 400000


# ---------------------------------------------------------------- 数据准备
def load_zone_items(bake, zones, zone_id):
    items = []
    for bi, _k, off in bake.instances():
        x, _y, z = bake.inst_pos(off)
        if assign_zone(x, z, zones) != zone_id:
            continue
        gi = bake.scene["batches"][bi]["geom"]
        lo, hi = _instance_aabb(bake, gi, off)
        items.append(
            {
                "bi": bi,
                "off": off,
                "geom": gi,
                "lo": lo,
                "hi": hi,
                "color": bake.inst_color(off),
            }
        )
    return items


def load_env_items(bake, zones, zone_ids):
    items = []
    for bi, _k, off in bake.instances():
        x, _y, z = bake.inst_pos(off)
        if assign_zone(x, z, zones) in zone_ids:
            continue
        gi = bake.scene["batches"][bi]["geom"]
        lo, hi = _instance_aabb(bake, gi, off)
        items.append({"bi": bi, "off": off, "geom": gi, "lo": lo, "hi": hi,
                      "color": bake.inst_color(off)})
    return items


def _instance_aabb(bake, gi, off):
    g = bake.geom_stats[gi]
    m = bake.inst_matrix(off)
    lo = [1e18] * 3
    hi = [-1e18] * 3
    for cx in (g["min"][0], g["max"][0]):
        for cy in (g["min"][1], g["max"][1]):
            for cz in (g["min"][2], g["max"][2]):
                p = (
                    m[0][0] * cx + m[1][0] * cy + m[2][0] * cz + m[3][0],
                    m[0][1] * cx + m[1][1] * cy + m[2][1] * cz + m[3][1],
                    m[0][2] * cx + m[1][2] * cy + m[2][2] * cz + m[3][2],
                )
                for i in range(3):
                    lo[i] = min(lo[i], p[i])
                    hi[i] = max(hi[i], p[i])
    return lo, hi


def _center_2d(item):
    return ((item["lo"][0] + item["hi"][0]) * 0.5, (item["lo"][2] + item["hi"][2]) * 0.5)


def _size(item):
    return [item["hi"][i] - item["lo"][i] for i in range(3)]


# ---------------------------------------------------------------- 单元划分
def _geom_verts(bake_ref, item):
    return bake_ref.geom_stats[item["geom"]]["vcount"]


def load_unit_plan(path):
    """读取人工编辑过的划分表：{units:[{id, anchor:[x,z], radius:7}]}。"""
    if not os.path.exists(path):
        return None
    data = json.load(open(path))
    units = data.get("units") if isinstance(data, dict) else None
    if not units:
        return None
    return units




def load_unit_plan(path):
    """读取人工编辑过的划分表：{units:[{id, anchor:[x,z], radius:7}]}。"""
    if not os.path.exists(path):
        return None
    data = json.load(open(path))
    units = data.get("units") if isinstance(data, dict) else None
    if not units:
        return None
    return units




def apply_unit_plan(items, units):
    """按人工锚点分单元。

    `detail` 既可以作为锚点参与分配，也吸收所有落在锚点外的零散件。
    两种情况必须合并成 **同一个** detail —— 否则会生成两个同名 glb，
    后写的把前一个覆盖掉，manifest 与文件从此对不上（踩过一次）。
    """
    groups = {}
    rest = []
    for it in items:
        c = _center_2d(it)
        best = None
        best_d = 1e9
        for u in units:
            d = math.dist(c, (float(u["anchor"][0]), float(u["anchor"][1])))
            if d <= float(u.get("radius", UNIT_RADIUS)) and d < best_d:
                best_d = d
                best = str(u["id"])
        if best:
            groups.setdefault(best, []).append(it)
        else:
            rest.append(it)
    if rest:
        groups.setdefault("detail", []).extend(rest)
    return [(uid, groups[uid]) for uid in sorted(groups)]


def plan_units(items, bake_ref=None):
    """返回 [(unit_id, items)]。划分结果写进 manifest，之后可以人工微调。"""
    if not items:
        return []
    seeds = []
    cand = []
    for it in items:
        s = _size(it)
        if max(s[0], s[2]) >= SEED_MIN_FOOTPRINT and s[1] >= SEED_MIN_HEIGHT:
            cand.append((s[0] * s[1] * s[2], it))
    cand.sort(key=lambda t: -t[0])
    for _vol, it in cand:
        c = _center_2d(it)
        if all(math.dist(c, _center_2d(s)) >= SEED_GAP for s in seeds):
            seeds.append(it)

    groups = {"unit_%02d" % (i + 1): [] for i in range(len(seeds))}
    rest = []
    for it in items:
        c = _center_2d(it)
        if seeds:
            dists = [(math.dist(c, _center_2d(s)), i) for i, s in enumerate(seeds)]
            d, idx = min(dists)
        else:
            d, idx = 1e9, -1
        if idx >= 0 and d <= UNIT_RADIUS:
            groups["unit_%02d" % (idx + 1)].append(it)
        else:
            rest.append(it)

    out = []
    if not seeds:
        # 没有达到建筑体量的区块（如浅水养殖台），整区就是一个单元。
        return [("unit_01", items)]
    for uid, group in groups.items():
        if group:
            out.append((uid, group))

    # 零散件合成一个 detail 单元：拆成几十个几 KB 的文件既难替换也难管理。
    if rest:
        verts = sum(_geom_verts(bake_ref, it) for it in rest)
        if verts <= DETAIL_MAX_VERTS:
            out.append(("detail", rest))
        else:
            cells = {}
            for it in rest:
                c = _center_2d(it)
                key = (int(math.floor(c[0] / 12.0)), int(math.floor(c[1] / 12.0)))
                cells.setdefault(key, []).append(it)
            for (row, col), group in sorted(cells.items()):
                out.append(("detail_%02d_%02d" % (row, col), group))
    # 按单元中心排序，编号稳定可 diff
    def order(entry):
        g = entry[1]
        cx = sum(_center_2d(i)[0] for i in g) / len(g)
        cz = sum(_center_2d(i)[1] for i in g) / len(g)
        return (round(cz, 1), round(cx, 1))

    return sorted(out, key=order)


# ---------------------------------------------------------------- 网格合并
def prims_bounds(prims):
    """单元网格的**真实顶点**包围盒。

    不能用实例原型 AABB 求和：细长斜管（缆绳、斜梁）的原型 AABB 远大于
    实际顶点分布，会把清单的尺寸撑大一倍，和 glb 内容对不上。
    """
    lo = np.array([1e30, 1e30, 1e30])
    hi = np.array([-1e30, -1e30, -1e30])
    for prim in prims:
        pos = prim["pos"]
        if len(pos) == 0:
            continue
        lo = np.minimum(lo, pos.min(axis=0))
        hi = np.maximum(hi, pos.max(axis=0))
    return [float(v) for v in lo], [float(v) for v in hi]


def build_unit_mesh(bake, items):
    """把单元内所有实例合并成一组按材质分槽的网格（世界坐标）。"""
    # 按材质 key 聚合，和网页版合批口径一致
    slots = {}
    for it in items:
        b = bake.scene["batches"][it["bi"]]
        key = (int(b["tex"]), bool(b["tint"]), bool(b["unlit"]),
               bool(b["alpha"]), bool(b["doubleSide"]))
        slots.setdefault(key, []).append(it)

    primitives = []
    for key in sorted(slots.keys(), key=lambda k: (k[0], k[1], k[2], k[3], k[4])):
        batch_items = slots[key]
        pos_parts = []
        nrm_parts = []
        uv_parts = []
        col_parts = []
        idx_parts = []
        base = 0
        for it in batch_items:
            gi = it["geom"]
            geom = bake.scene["geoms"][gi]
            vc = geom["vcount"]
            p = _geom_attr(bake, geom, "pOff", 3, vc)
            n = _geom_attr(bake, geom, "nOff", 3, vc)
            t = _geom_attr(bake, geom, "tOff", 2, vc)
            c = _geom_attr(bake, geom, "cOff", 3, vc)

            m = bake.inst_matrix(it["off"])
            basis = np.array([m[0], m[1], m[2]], dtype=np.float64)  # 列 = 基向量
            origin = np.array(m[3], dtype=np.float64)

            world = p @ basis.T + origin
            if n is not None:
                inv = np.linalg.inv(basis)
                nrm = n @ inv  # (M^-1)^T 作用在法线上的等价写法（n 按行）
                ln = np.linalg.norm(nrm, axis=1, keepdims=True)
                ln[ln < 1e-9] = 1.0
                nrm = nrm / ln
            else:
                nrm = np.tile([0.0, 1.0, 0.0], (vc, 1))

            col = np.tile(np.array(it["color"][:3], dtype=np.float64), (vc, 1))
            if c is not None:
                col = col * c

            idx = bake.geom_indices(gi)
            idx_parts.append(np.asarray(idx, dtype=np.int64) + base)

            pos_parts.append(world)
            nrm_parts.append(nrm)
            uv_parts.append(t if t is not None else np.zeros((vc, 2)))
            col_parts.append(col)
            base += vc

        if not pos_parts:
            continue
        primitives.append(
            {
                "slot": key,
                "pos": np.concatenate(pos_parts),
                "nrm": np.concatenate(nrm_parts),
                "uv": np.concatenate(uv_parts),
                "col": np.concatenate(col_parts),
                "idx": np.concatenate(idx_parts),
                "instances": len(batch_items),
            }
        )
    return primitives


def _geom_attr(bake, geom, key, comps, vcount):
    off = int(geom.get(key, -1))
    if off < 0:
        return None
    a = np.asarray(bake.geo[off:off + vcount * comps], dtype=np.float64)
    return a.reshape(vcount, comps)


def export_glb(path, primitives, origin, name, bake):
    glb = Glb()
    mesh_prims = []
    slot_meta = []
    for prim in primitives:
        pos = prim["pos"] - np.array(origin, dtype=np.float64)
        tex, _tint, unlit, alpha, double_side = prim["slot"]
        tex_index = None
        if tex >= 0:
            png = open(os.path.join(BAKED, bake.scene["textures"][tex]), "rb").read()
            tex_index = glb.add_image(png, "tex_%d" % tex)
        mat = glb.add_material(
            "%s_%d" % (name, len(slot_meta)),
            tex=tex_index, unlit=unlit, alpha=alpha, double_sided=double_side,
        )
        a_pos = glb.add_floats(pos.reshape(-1).tolist(), "VEC3")
        a_nrm = glb.add_floats(prim["nrm"].reshape(-1).tolist(), "VEC3")
        a_uv = glb.add_floats(prim["uv"].reshape(-1).tolist(), "VEC2")
        a_col = glb.add_floats(prim["col"].reshape(-1).tolist(), "VEC3")
        a_idx = glb.add_indices(prim["idx"].tolist())
        # POSITION 的 min/max 是规范硬要求
        mn = pos.min(axis=0)
        mx = pos.max(axis=0)
        glb.doc["accessors"][a_pos]["min"] = [float(v) for v in mn]
        glb.doc["accessors"][a_pos]["max"] = [float(v) for v in mx]
        mesh_prims.append(
            {
                "attributes": {
                    "POSITION": a_pos,
                    "NORMAL": a_nrm,
                    "TEXCOORD_0": a_uv,
                    "COLOR_0": a_col,
                },
                "indices": a_idx,
                "material": mat,
            }
        )
        slot_meta.append(
            {
                "tex": tex,
                "tint": bool(prim["slot"][1]),
                "unlit": unlit,
                "alpha": alpha,
                "double_side": double_side,
                "instances": prim["instances"],
                "vertices": int(len(pos)),
                "triangles": int(len(prim["idx"]) // 3),
            }
        )
    mi = glb.add_mesh(name, mesh_prims)
    glb.attach_mesh(mi, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    size = glb.save(path)
    return {"slots": slot_meta, "bytes": size,
            "vertices": int(sum(s["vertices"] for s in slot_meta)),
            "triangles": int(sum(s["triangles"] for s in slot_meta))}


# ---------------------------------------------------------------- 导出入口
def export_group(bake, items, out_dir, name, split_units, label_of=None,
                 unit_plan_path=None):
    """导出一个逻辑组（区块 / 环境块）：整组 glb + 可选单元 glb + manifest。"""
    os.makedirs(out_dir, exist_ok=True)
    lo = [min(i["lo"][k] for i in items) for k in range(3)]
    hi = [max(i["hi"][k] for i in items) for k in range(3)]
    prims = build_unit_mesh(bake, items)
    # 包围盒按真实顶点算，不用实例原型 AABB 累加。
    lo, hi = prims_bounds(prims)
    # 枢轴统一落在世界 y=0（水面基准）+ 单元水平中心。
    # 用 AABB 底部会让水下基座把枢轴压到 -30m，DCC 里完全没法编辑。
    origin = [(lo[0] + hi[0]) * 0.5, 0.0, (lo[2] + hi[2]) * 0.5]
    whole = export_glb(os.path.join(out_dir, name + ".glb"), prims, origin, name, bake)

    manifest = {
        "name": name,
        "origin": [round(v, 3) for v in origin],
        "bounds": {
            "min": [round(v, 3) for v in lo],
            "max": [round(v, 3) for v in hi],
            "size": [round(hi[i] - lo[i], 3) for i in range(3)],
        },
        "instance_count": len(items),
        "whole": whole,
        "units": [],
    }

    if split_units:
        units_dir = os.path.join(out_dir, "units")
        os.makedirs(units_dir, exist_ok=True)
        plan_file = os.path.join(out_dir, "units.json")
        manual = load_unit_plan(plan_file)
        if manual is not None:
            plan = apply_unit_plan(items, manual)
        else:
            plan = plan_units(items, bake)
        # id 必须唯一：同名会让两个 glb 互相覆盖，manifest 与文件从此对不上。
        _seen = set()
        _unique = []
        for uid, group in plan:
            name = uid
            n = 1
            while name in _seen:
                n += 1
                name = "%s_%d" % (uid, n)
            if name != uid:
                print("  [warn] 单元 id 重复，改为 %s" % name)
            _seen.add(name)
            _unique.append((name, group))
        plan = _unique

        for uid, group in plan:
            uprims = build_unit_mesh(bake, group)
            ulo, uhi = prims_bounds(uprims)
            u_origin = [(ulo[0] + uhi[0]) * 0.5, 0.0, (ulo[2] + uhi[2]) * 0.5]
            info = export_glb(os.path.join(units_dir, uid + ".glb"),
                              uprims, u_origin, uid, bake)
            manifest["units"].append(
                {
                    "id": uid,
                    "file": "units/%s.glb" % uid,
                    "label": label_of(u_origin) if label_of else uid,
                    "origin": [round(v, 3) for v in u_origin],
                    "bounds": {
                        "min": [round(v, 3) for v in ulo],
                        "max": [round(v, 3) for v in uhi],
                        "size": [round(uhi[i] - ulo[i], 3) for i in range(3)],
                    },
                    "instance_count": len(group),
                    "slots": info["slots"],
                    "vertices": info["vertices"],
                    "triangles": info["triangles"],
                    "bytes": info["bytes"],
                }
            )
        if manual is None:
            draft = {"units": []}
            for u in manifest["units"]:
                draft["units"].append({
                    "id": u["id"],
                    "label": u["label"],
                    "anchor": [round(u["origin"][0], 2), round(u["origin"][2], 2)],
                    "radius": UNIT_RADIUS,
                    "instance_count": u["instance_count"],
                })
            with open(plan_file, "w") as f:
                json.dump(draft, f, ensure_ascii=False, indent=1)

        # 清理上一次遗留、这次没生成的单元文件
        keep = {u["id"] + ".glb" for u in manifest["units"]}
        for f in os.listdir(units_dir):
            if f.endswith(".glb") and f not in keep:
                os.remove(os.path.join(units_dir, f))

    with open(os.path.join(out_dir, "manifest.json"), "w") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    return manifest


def labeler(zone):
    """给单元起个可读名：最近的上岸点 / 地标。"""
    marks = []
    for l in zone.get("landings", []):
        marks.append((l["name"], l["landStand"]))
    for h in zone.get("harbor", []):
        marks.append((h["label"], h["point"]))
    if zone.get("hover"):
        marks.append(("岛心", zone["hover"]))

    def pick(origin):
        if not marks:
            return "未命名"
        best = min(marks, key=lambda m: math.dist((origin[0], origin[2]), (m[1][0], m[1][2])))
        d = math.dist((origin[0], origin[2]), (best[1][0], best[1][2]))
        return "%s·%.0fm" % (best[0], d)

    return pick


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zone", default="", help="只导某个区块，如 zone1")
    ap.add_argument("--env", action="store_true", help="连外围环境一起导")
    ap.add_argument("--no-units", action="store_true", help="只导整区总装")
    args = ap.parse_args()

    bake = Bake(BAKED)
    zones = json.load(open(os.path.join(ROOT, "assets", "data", "zones.json")))
    zone_ids = [args.zone] if args.zone else naming.ZONE_ORDER

    for zid in zone_ids:
        zone = next(z for z in zones if z["id"] == zid)
        items = load_zone_items(bake, zones, zid)
        if not items:
            print("%-6s 没有实例，跳过" % zid)
            continue
        key = naming.zone_key(zid)
        m = export_group(bake, items, os.path.join(MODELS, "zones", key), key,
                         split_units=not args.no_units, label_of=labeler(zone))
        print("%-6s %-24s 实例 %5d  单元 %2d  整区 %.1f MB"
              % (zid, m["name"], m["instance_count"], len(m["units"]),
                 m["whole"]["bytes"] / 1e6))
        for u in m["units"]:
            print("         %-14s %-18s 实例 %4d  %6.0f 三角形  %5.1f MB"
                  % (u["id"], u["label"], u["instance_count"], u["triangles"],
                     u["bytes"] / 1e6))

    if args.env:
        items = load_env_items(bake, zones, set(naming.ZONE_ORDER))
        # 按 32m 网格分块，避免单个 glb 过大
        cells = {}
        for it in items:
            c = _center_2d(it)
            cells.setdefault((int(math.floor(c[0] / ENV_CELL)),
                              int(math.floor(c[1] / ENV_CELL))), []).append(it)
        out_root = os.path.join(MODELS, "world", "environment")
        os.makedirs(out_root, exist_ok=True)
        manifest = {"name": "environment", "cell": ENV_CELL, "blocks": []}
        for (row, col), group in sorted(cells.items()):
            name = "env_%02d_%02d" % (row, col)
            m = export_group(bake, group, os.path.join(out_root, name), name,
                             split_units=False)
            manifest["blocks"].append(
                {"name": name, "file": name + "/" + name + ".glb",
                 "origin": m["origin"], "bounds": m["bounds"],
                 "instance_count": m["instance_count"], "bytes": m["whole"]["bytes"]}
            )
        with open(os.path.join(out_root, "manifest.json"), "w") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=1)
        print("env     %d 块，实例 %d" % (len(cells), len(items)))


if __name__ == "__main__":
    main()
