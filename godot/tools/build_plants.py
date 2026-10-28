#!/usr/bin/env python3
"""从烘焙场景里把植物抽出来，建成两级植物库。

为什么要抽：网页版的绿植是按建造等级 `scale` 生长的（living-harbor.js），
烘进静态几何后就再也动不了。抽成独立植物节点后，生长 / 摆风 / 区块特效
都能在 Godot 里重新驱动，而形状与位置仍来自真实烘焙数据。

产出：
  assets/plants/common/<id>/{mesh.bin,meta.json}       通用植物（可跨区块复用）
  assets/plants/zones/<zone_key>/<id>/{mesh.bin,meta.json}
  assets/data/plants_<zone_key>.json                   每区块的摆放表
  assets/data/plant_claim.json                         已被植物接管的实例（build_zones 排除）
  scenes/plants/common/<id>.tscn
  scenes/plants/zones/<zone_key>/<id>.tscn

用法：python3 tools/build_plants.py
"""
import json
import math
import os
import struct
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import naming
from lib_bake import (BAKED, LEAF_GEOMS, ROOT, Bake, assign_zone, f32_bytes,
                      read_i32, transform_dir, transform_point)

CLUSTER_RADIUS = 1.15   # 到「种子叶」的距离上限；不做链式传递，否则整面墙的藤会连成一株
MAX_CLUSTER = 14
MIN_CLUSTER = 3          # 少于 3 片叶子的碎株留在静态几何里，避免"单叶漂在半空"
MAX_SPREAD = 2.6         # 一株的包围盒超过这个尺寸就当聚类失败，同样留给静态几何
MIN_CLUSTER = 3          # 少于 3 片叶子的碎株留在静态几何里，避免"单叶漂在半空"
MAX_SPREAD = 2.6         # 一株的包围盒超过这个尺寸就当聚类失败，同样留给静态几何
SIZE_BUCKET = 0.18
COLOR_BUCKET = 0.25


def bucket(v, step):
    return round(v / step) * step if step else v


def color_key(c):
    return (bucket(c[0], COLOR_BUCKET), bucket(c[1], COLOR_BUCKET), bucket(c[2], COLOR_BUCKET))


def main():
    from authored_guard import require_candidate
    require_candidate(__file__)
    bake = Bake(BAKED)
    zones = json.load(open(os.path.join(ROOT, "assets", "data", "zones.json")))

    # ---- 1. 收集区块内的叶片实例 ----
    leaves = []
    for bi, b in enumerate(bake.scene["batches"]):
        gi = b["geom"]
        if gi not in LEAF_GEOMS:
            continue
        for k in range(b["count"]):
            off = (b["instOff"] + k) * 16
            x, y, z = bake.inst_pos(off)
            zid = assign_zone(x, z, zones, pad=7.0)
            if zid is None:
                continue
            leaves.append({"batch": bi, "k": k, "off": off, "pos": (x, y, z), "zone": zid})
    print("区块内叶片实例：", len(leaves))

    # ---- 2. 聚成「株」：离已有簇心 0.72m 内就并进去，超过 14 片另起一株 ----
    clusters = []
    for leaf in leaves:
        best = None
        best_d = CLUSTER_RADIUS
        for c in clusters:
            if c["zone"] != leaf["zone"] or len(c["leaves"]) >= MAX_CLUSTER:
                continue
            seed = c["seed"]
            d = math.dist(leaf["pos"], seed)
            if d < best_d:
                best_d = d
                best = c
        if best is None:
            clusters.append({"zone": leaf["zone"], "leaves": [leaf],
                             "seed": leaf["pos"],
                             "center": (leaf["pos"][0], leaf["pos"][2])})
        else:
            best["leaves"].append(leaf)
            n = len(best["leaves"])
            best["center"] = (
                sum(l["pos"][0] for l in best["leaves"]) / n,
                sum(l["pos"][2] for l in best["leaves"]) / n,
            )
    total_clusters = len(clusters)
    kept = []
    for c in clusters:
        if len(c["leaves"]) < MIN_CLUSTER:
            continue
        xs = [l["pos"][0] for l in c["leaves"]]
        ys = [l["pos"][1] for l in c["leaves"]]
        zs = [l["pos"][2] for l in c["leaves"]]
        spread = max(max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
        if spread > MAX_SPREAD:
            continue
        kept.append(c)
    clusters = kept
    print("聚成植株：", total_clusters, "→ 成形植株", len(clusters),
          "（其余留在静态几何）")

    # ---- 3. 归原型：叶片数 + 尺寸档 + 配色档 ----
    archetypes = {}
    for idx, c in enumerate(clusters):
        pts = [l["pos"] for l in c["leaves"]]
        mn = [min(p[i] for p in pts) for i in range(3)]
        mx = [max(p[i] for p in pts) for i in range(3)]
        size = tuple(bucket(mx[i] - mn[i], SIZE_BUCKET) for i in range(3))
        # 原型只按「叶片数 + 高度档 + 主色」归类：形状细节留给网格本身，
        # 分得太细会让通用库退化成"每株一个原型"，反而没法复用。
        heights = bucket(size[1], 0.35)
        dominant = Counter(color_key(bake.inst_color(l["off"])) for l in c["leaves"]).most_common(1)[0][0]
        key = (len(c["leaves"]), heights, dominant)
        c["key"] = key
        if key not in archetypes:
            archetypes[key] = {"key": key, "clusters": [], "zones": set()}
        archetypes[key]["clusters"].append(c)
        archetypes[key]["zones"].add(c["zone"])

    print("原型数量：", len(archetypes),
          " 跨区块复用：", sum(1 for a in archetypes.values() if len(a["zones"]) > 1))

    # ---- 4. 生成原型网格（用第一株的真实叶片拼成一张 ArrayMesh） ----
    out_plants = os.path.join(ROOT, "assets", "plants")
    scenes_plants = os.path.join(ROOT, "scenes", "plants")
    placements = defaultdict(list)
    claim = []

    for order, (key, arch) in enumerate(sorted(archetypes.items(), key=lambda kv: -len(kv[1]["clusters"]))):
        sample = arch["clusters"][0]
        shared = len(arch["zones"]) > 1
        scope = "common" if shared else "zones/" + naming.zone_key(sorted(arch["zones"])[0])
        pid = "plant_%02d_%dl" % (order, key[0])

        verts, norms, cols, idxs = [], [], [], []
        for leaf in sample["leaves"]:
            m = bake.inst_matrix(leaf["off"])
            col = bake.inst_color(leaf["off"])
            base = len(verts)
            for p, nrm in bake.geom_verts(bake.scene["batches"][leaf["batch"]]["geom"]):
                wp = transform_point(m, p)
                wn = transform_dir(m, nrm)
                verts.append(wp)
                norms.append(wn)
                cols.append((col[0], col[1], col[2]))
            for i in bake.geom_indices(bake.scene["batches"][leaf["batch"]]["geom"]):
                idxs.append(base + i)

        # 以「最低点」为原点，方便按区块落位与生长
        min_y = min(v[1] for v in verts)
        mnx = min(v[0] for v in verts)
        mnz = min(v[2] for v in verts)
        mxx = max(v[0] for v in verts)
        mxz = max(v[2] for v in verts)
        ox = (mnx + mxx) * 0.5
        oz = (mnz + mxz) * 0.5
        verts = [(v[0] - ox, v[1] - min_y, v[2] - oz) for v in verts]

        pdir = os.path.join(out_plants, scope, pid)
        os.makedirs(pdir, exist_ok=True)
        buf = bytearray()
        buf += struct.pack("<II", len(verts), len(idxs))
        buf += f32_bytes([c for v in verts for c in v])
        buf += f32_bytes([c for n in norms for c in n])
        buf += f32_bytes([c for col in cols for c in col])
        buf += struct.pack("<%dI" % len(idxs), *idxs)
        open(os.path.join(pdir, "mesh.bin"), "wb").write(buf)

        meta = {
            "id": pid,
            "scope": scope,
            "leaf_count": len(sample["leaves"]),
            "vcount": len(verts),
            "icount": len(idxs),
            "bounds": [round(mxx - mnx, 3), round(max(v[1] for v in verts), 3), round(mxz - mnz, 3)],
            "zones": sorted(arch["zones"]),
            "instances": sum(len(c["leaves"]) for c in arch["clusters"]),
            "mounts": len(arch["clusters"]),
        }
        json.dump(meta, open(os.path.join(pdir, "meta.json"), "w"), ensure_ascii=False, indent=1)

        # ---- 5. 每株 → 一条摆放记录（区块内相对坐标 + 错峰生长起点） ----
        for ci, c in enumerate(arch["clusters"]):
            zid = c["zone"]
            zkey = naming.zone_key(zid)
            zone = next(z for z in zones if z["id"] == zid)
            ox_z, oz_z = zone["origin"][0], zone["origin"][2]
            miny = min(l["pos"][1] for l in c["leaves"])
            placements[zkey].append({
                "a": pid,
                "scope": scope,
                "p": [round(c["center"][0] - ox_z, 3),
                      round(miny, 3),
                      round(c["center"][1] - oz_z, 3)],
                "g": round(0.10 + (ci % 6) * 0.055, 3),
            })
            for l in c["leaves"]:
                claim.append([l["batch"], l["k"]])

        # ---- 6. 植物场景 ----
        sdir = os.path.join(scenes_plants, scope)
        os.makedirs(sdir, exist_ok=True)
        eff = naming.ZONE_PLANT_EFFECTS[sorted(arch["zones"])[0]] if not shared else None
        write_plant_scene(os.path.join(sdir, pid + ".tscn"), pid, scope, shared, eff, meta)

    # 每个区块都写一份摆放表（没有植物的写空表），避免场景里指向不存在的文件
    for z in naming.ZONES:
        placements.setdefault(naming.zone_key(z), [])

    # 摆放记录按 y 排序，稳定可 diff
    for zkey, rows in placements.items():
        rows.sort(key=lambda r: (r["p"][2], r["p"][0]))
        path = os.path.join(ROOT, "assets", "data", "plants_%s.json" % zkey)
        json.dump({"zone": zkey, "plants": rows}, open(path, "w"), ensure_ascii=False, indent=1)
        print("  %s: %d 株" % (zkey, len(rows)))

    json.dump(claim, open(os.path.join(ROOT, "assets", "data", "plant_claim.json"), "w"))
    print("植物接管实例：", len(claim))
    print("通用原型：", sum(1 for k, a in archetypes.items() if len(a["zones"]) > 1),
          " 专用原型：", sum(1 for k, a in archetypes.items() if len(a["zones"]) == 1))


def write_plant_scene(path, pid, scope, shared, effect, meta):
    lines = ["[gd_scene load_steps=3 format=3]", ""]
    lines.append('[ext_resource type="Script" path="res://src/ambient/plant.gd" id="1_plant"]')
    lines.append("")
    lines.append('[node name="%s" type="Node3D"]' % pid)
    lines.append('script = ExtResource("1_plant")')
    lines.append('plant_id = "%s"' % pid)
    lines.append('mesh_path = "res://assets/plants/%s/%s/mesh.bin"' % (scope, pid))
    lines.append('shared = %s' % ("true" if shared else "false"))
    if effect is not None:
        # effect 为空 = 本区块不发粒子；摆动参数照写，别让撤粒子顺手把摆动也撤了。
        if effect.get("effect"):
            lines.append('effect = "%s"' % effect["effect"])
        lines.append('sway_amplitude = %.4f' % effect["sway"])
        lines.append('wind_strength = %.2f' % effect["wind"])
    lines.append("")
    lines.append('[node name="EffectPoint" type="Marker3D" parent="."]')
    lines.append("position = Vector3(0, %.3f, 0)" % (meta["bounds"][1] * 0.6))
    lines.append("")
    open(path, "w").write("\n".join(lines))


if __name__ == "__main__":
    main()
