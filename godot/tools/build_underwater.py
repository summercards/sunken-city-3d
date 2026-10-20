#!/usr/bin/env python3
"""把烘焙好的水下世界切成独立区块模型（glb），并生成区块场景。

输入：assets/baked/underwater/（tools/export_underwater.cjs 产出，批次带 region 标签）
输出：assets/models/underwater/<region>/
        <region>.glb            整区总装
        units/<unit>.glb        可单独替换的单元（一栋楼 / 一组道具）
        manifest.json
      scenes/underwater/region_<region>.tscn

区块划分（按内容，不按坐标）：
   basin         岩盆 / 岩层 / 沙堆 / 珊瑚台地
   neighborhood  沉没街区（12 栋民宅 / 断桥 / 路灯 / 车辆）
   reef          珊瑚与海草
   trench        北境海沟（海床 / 断崖 / 阶梯 / 海盗船）

单元划分：一栋楼一个 glb；成组的零散件（路灯、车辆）合成一个；珊瑚按序号每 32 丛一个。

用法：
  python3 tools/build_underwater.py
  python3 tools/build_underwater.py --region trench
"""
import argparse
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib_bake import Bake, f32_bytes  # noqa: E402
from lib_glb import Glb  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BAKED = os.path.join(ROOT, "assets", "baked", "underwater")
MODELS = os.path.join(ROOT, "assets", "models", "underwater")
SCENES = os.path.join(ROOT, "scenes", "underwater")

REGIONS = ["basin", "neighborhood", "reef", "trench"]

REGION_LABEL = {
    "basin": "礁盆与台地",
    "neighborhood": "沉没街区",
    "reef": "珊瑚礁与海草",
    "trench": "北境海沟",
}

# 珊瑚 246 丛、海草 55 株：单丛一个文件太碎，按序号分组。
CORAL_PER_UNIT = 32
KELP_PER_UNIT = 28


def unit_of(name: str) -> str:
    """具名组 → 单元 id。没有名字的挂到所在区块的 shell。"""
    if name.startswith("submerged-residence-"):
        return "house_%02d" % int(name.rsplit("-", 1)[1])
    if name.startswith("submerged-streetlamp"):
        return "lamps"
    if name.startswith("submerged-car") or name.startswith("submerged-delivery-van"):
        return "vehicles"
    if name.startswith("collapsed-bridge") or name.startswith("fallen-bridge-deck"):
        return "bridge"
    if name.startswith("reef-coral"):
        idx = int(name.rsplit("-", 1)[1]) if name.rsplit("-", 1)[1].isdigit() else 0
        return "coral_%02d" % (idx // CORAL_PER_UNIT)
    if name.startswith("ribbon-kelp"):
        idx = int(name.rsplit("-", 1)[1]) if name.rsplit("-", 1)[1].isdigit() else 0
        return "kelp_%02d" % (idx // KELP_PER_UNIT)
    if name.startswith("trench-descent-remnant"):
        return "trench_stairs"
    if name.startswith("tilted-pirate-brig") or name.startswith("tattered-brig-sail"):
        return "brig"
    if name.startswith("giant-trench-coral"):
        return "trench_shell"
    if name.startswith("north-trench") or name.startswith("trench-attached-stratum"):
        return "trench_shell"
    if name.startswith("reef-terrace"):
        return "terraces"
    if name.startswith("continuous-tapered-rock-basin"):
        return "shell"
    return "shell"


def load_region(bake, region):
    """返回 [{off, geom, name, color, batch}]。"""
    items = []
    for bi, b in enumerate(bake.scene["batches"]):
        if b.get("region") != region:
            continue
        for k in range(b["count"]):
            off = (b["instOff"] + k) * 16
            items.append({"off": off, "geom": b["geom"], "batch": b})
    return items


def load_named(bake, region):
    """把每个实例归到单元：靠 bake.json 里的 unit 字段（导出时写入）。"""
    items = []
    for bi, b in enumerate(bake.scene["batches"]):
        if b.get("region") != region:
            continue
        unit = b.get("unit", "shell")
        for k in range(b["count"]):
            off = (b["instOff"] + k) * 16
            items.append({"off": off, "geom": b["geom"], "batch": b, "unit": unit})
    return items


def instance_aabb(bake, geom_index, off):
    g = bake.geom_stats[geom_index]
    m = bake.inst_matrix(off)
    lo = [1e18] * 3
    hi = [-1e18] * 3
    for cx in (g["min"][0], g["max"][0]):
        for cy in (g["min"][1], g["max"][1]):
            for cz in (g["min"][2], g["max"][2]):
                for i in range(3):
                    v = m[0][i] * cx + m[1][i] * cy + m[2][i] * cz + m[3][i]
                    lo[i] = min(lo[i], v)
                    hi[i] = max(hi[i], v)
    return lo, hi


def geom_attr(bake, geom, key, comps, vcount):
    off = int(geom.get(key, -1))
    if off < 0:
        return None
    a = np.asarray(bake.geo[off:off + vcount * comps], dtype=np.float64)
    return a.reshape(vcount, comps)


def slot_key(b):
    def col(v):
        return tuple(round(float(x), 3) for x in (v or [0, 0, 0]))
    em = b.get("emissive") or []
    return (
        int(b.get("tex", -1)),
        bool(b.get("unlit", False)),
        bool(b.get("alpha", False)),
        bool(b.get("doubleSide", False)),
        bool(b.get("flat", False)),
        col(b.get("color")),
        round(float(b.get("opacity", 1.0)), 3),
        col(em[:3]) if em else (0.0, 0.0, 0.0),
        round(float(em[3]), 3) if em else 0.0,
        bool(b.get("vertexColors", False)),
    )


def build_unit_primitives(bake, items):
    """合并一个单元里所有实例，按材质槽分组。返回 [(slot, pos, nrm, col, idx)]。"""
    slots = {}
    for it in items:
        slots.setdefault(slot_key(it["batch"]), []).append(it)

    out = []
    for key in sorted(slots.keys(), key=lambda k: str(k)):
        pos_parts, nrm_parts, col_parts, idx_parts = [], [], [], []
        base = 0
        flat = key[4]
        for it in slots[key]:
            gi = it["geom"]
            geom = bake.scene["geoms"][gi]
            vc = geom["vcount"]
            p = geom_attr(bake, geom, "pOff", 3, vc)
            n = geom_attr(bake, geom, "nOff", 3, vc)
            idx = np.asarray(bake.geom_indices(gi), dtype=np.int64)

            m = bake.inst_matrix(it["off"])
            basis = np.array([m[0], m[1], m[2]], dtype=np.float64)
            origin = np.array(m[3], dtype=np.float64)
            world = p @ basis.T + origin

            if n is None:
                nrm = np.tile([0.0, 1.0, 0.0], (vc, 1))
            else:
                inv = np.linalg.inv(basis)
                nrm = n @ inv
                ln = np.linalg.norm(nrm, axis=1, keepdims=True)
                ln[ln < 1e-9] = 1.0
                nrm = nrm / ln

            vcol = None
            if key[9]:
                c = geom_attr(bake, geom, "cOff", 3, vc)
                if c is not None:
                    inst_c = np.array(bake.inst_color(it["off"])[:3], dtype=np.float64)
                    vcol = c * inst_c

            if flat:
                # 平面着色：three 的 flatShading 是渲染期用导数算面法线，
                # 顶点法线本来就是平滑的。烘成静态网格必须自己拆三角形。
                tri = idx.reshape(-1, 3)
                wp = world[tri]                     # (T,3,3)
                fn = np.cross(wp[:, 1] - wp[:, 0], wp[:, 2] - wp[:, 0])
                ln = np.linalg.norm(fn, axis=1, keepdims=True)
                ln[ln < 1e-9] = 1.0
                fn = fn / ln
                pos_parts.append(wp.reshape(-1, 3))
                nrm_parts.append(np.repeat(fn, 3, axis=0))
                if vcol is not None:
                    col_parts.append(vcol[tri].reshape(-1, 3))
                else:
                    col_parts.append(np.ones((tri.shape[0] * 3, 3)))
                idx_parts.append(np.arange(tri.shape[0] * 3, dtype=np.int64) + base)
                base += tri.shape[0] * 3
            else:
                pos_parts.append(world)
                nrm_parts.append(nrm)
                col_parts.append(vcol if vcol is not None else np.ones((vc, 3)))
                idx_parts.append(idx + base)
                base += vc

        if not pos_parts:
            continue
        out.append((
            key,
            np.concatenate(pos_parts),
            np.concatenate(nrm_parts),
            np.concatenate(col_parts),
            np.concatenate(idx_parts),
        ))
    return out


def export_unit(path, prims, origin, name):
    glb = Glb(generator="sea-underwater-bake")
    mesh_prims = []
    slot_meta = []
    for key, pos, nrm, col, idx in prims:
        local = pos - np.array(origin, dtype=np.float64)
        (tex, unlit, alpha, double_side, flat, color, opacity, emis, emis_i,
         vcolors) = key
        mat = glb.add_material(
            "%s_%d" % (name, len(slot_meta)),
            unlit=unlit, alpha=alpha, double_sided=double_side,
            color=color, opacity=opacity, emissive=emis, emissive_strength=emis_i,
        )
        a_pos = glb.add_floats(local.reshape(-1).tolist(), "VEC3")
        glb.doc["accessors"][a_pos]["min"] = [float(v) for v in local.min(axis=0)]
        glb.doc["accessors"][a_pos]["max"] = [float(v) for v in local.max(axis=0)]
        a_nrm = glb.add_floats(nrm.reshape(-1).tolist(), "VEC3")
        attrs = {"POSITION": a_pos, "NORMAL": a_nrm}
        if vcolors:
            # glTF 的 COLOR_0 是线性值，和 three 的 vertexColors 语义一致。
            attrs["COLOR_0"] = glb.add_floats(col.reshape(-1).tolist(), "VEC3")
        a_idx = glb.add_indices(idx.tolist())
        mesh_prims.append({
            "attributes": attrs,
            "indices": a_idx,
            "material": mat,
        })
        slot_meta.append({
            "color": [round(c, 3) for c in color],
            "opacity": opacity,
            "emissive": [round(c, 3) for c in emis],
            "emissive_strength": emis_i,
            "flat": flat,
            "double_side": double_side,
            "alpha": alpha,
            "unlit": unlit,
            "vertex_color": vcolors,
            "instances": 0,
            "vertices": int(len(local)),
            "triangles": int(len(idx) // 3),
        })
    mi = glb.add_mesh(name, mesh_prims)
    glb.attach_mesh(mi, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    size = glb.save(path)
    return {"slots": slot_meta, "bytes": size,
            "vertices": int(sum(s["vertices"] for s in slot_meta)),
            "triangles": int(sum(s["triangles"] for s in slot_meta))}


def export_region(bake, region):
    items = load_named(bake, region)
    if not items:
        print("%-13s 没有实例，跳过" % region)
        return None

    by_unit = {}
    for it in items:
        by_unit.setdefault(it["unit"], []).append(it)

    # 单元包围盒（决定枢轴与摆放）
    boxes = {}
    for uid, group in by_unit.items():
        lo = [min(instance_aabb(bake, i["geom"], i["off"])[0][k] for i in group) for k in range(3)]
        hi = [max(instance_aabb(bake, i["geom"], i["off"])[1][k] for i in group) for k in range(3)]
        boxes[uid] = (lo, hi)

    out_dir = os.path.join(MODELS, region)
    units_dir = os.path.join(out_dir, "units")
    os.makedirs(units_dir, exist_ok=True)

    # 整区枢轴 = 全部单元的 AABB 中心
    all_lo = [min(boxes[u][0][k] for u in boxes) for k in range(3)]
    all_hi = [max(boxes[u][1][k] for u in boxes) for k in range(3)]
    whole_origin = [(all_lo[k] + all_hi[k]) * 0.5 for k in range(3)]

    prims = build_unit_primitives(bake, items)
    whole = export_unit(os.path.join(out_dir, "%s.glb" % region), prims, whole_origin, region)

    manifest = {
        "region": region,
        "label": REGION_LABEL.get(region, region),
        "origin": [round(v, 3) for v in whole_origin],
        "bounds": {
            "min": [round(v, 3) for v in all_lo],
            "max": [round(v, 3) for v in all_hi],
            "size": [round(all_hi[k] - all_lo[k], 3) for k in range(3)],
        },
        "instance_count": len(items),
        "whole": whole,
        "units": [],
    }

    for uid in sorted(by_unit):
        group = by_unit[uid]
        lo, hi = boxes[uid]
        origin = [(lo[k] + hi[k]) * 0.5 for k in range(3)]
        uprims = build_unit_primitives(bake, group)
        info = export_unit(os.path.join(units_dir, "%s.glb" % uid), uprims, origin, uid)
        manifest["units"].append({
            "id": uid,
            "file": "units/%s.glb" % uid,
            "origin": [round(v, 3) for v in origin],
            "bounds": {
                "min": [round(v, 3) for v in lo],
                "max": [round(v, 3) for v in hi],
                "size": [round(hi[k] - lo[k], 3) for k in range(3)],
            },
            "instance_count": len(group),
            "slots": info["slots"],
            "vertices": info["vertices"],
            "triangles": info["triangles"],
            "bytes": info["bytes"],
        })

    manifest["vertices"] = int(sum(u["vertices"] for u in manifest["units"]))
    manifest["triangles"] = int(sum(u["triangles"] for u in manifest["units"]))

    with open(os.path.join(out_dir, "manifest.json"), "w") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    return manifest


def write_region_scene(manifest):
    region = manifest["region"]
    node = "Underwater" + region.capitalize()
    lines = ["[gd_scene load_steps=3 format=3]", ""]
    lines.append('[ext_resource type="Script" path="res://scripts/world/underwater_region.gd" id="1_region"]')
    lines.append("")
    lines.append('[node name="%s" type="Node3D"]' % node)
    lines.append('script = ExtResource("1_region")')
    lines.append('region = "%s"' % region)
    lines.append('region_label = "%s"' % manifest.get("label", region))
    lines.append('manifest_path = "res://assets/models/underwater/%s/manifest.json"' % region)
    lines.append("")
    path = os.path.join(SCENES, "region_%s.tscn" % region)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write("\n".join(lines))


def write_world_scene(regions):
    """生成 scenes/underwater/underwater_world.tscn：四个区块 + 动态层 + 相机。"""
    lines = ["[gd_scene load_steps=%d format=3]" % (len(regions) + 3), ""]
    lines.append('[ext_resource type="Script" path="res://scripts/world/underwater_world.gd" id="1_world"]')
    for i, r in enumerate(regions):
        lines.append('[ext_resource type="PackedScene" path="res://scenes/underwater/region_%s.tscn" id="%d_%s"]'
                     % (r, i + 2, r))
    lines.append('[ext_resource type="Script" path="res://scripts/world/uw_deco.gd" id="%d_deco"]'
                 % (len(regions) + 2))
    lines.append("")
    lines.append('[node name="UnderwaterWorld" type="Node3D"]')
    lines.append('script = ExtResource("1_world")')
    lines.append("")
    lines.append('[node name="Regions" type="Node3D" parent="."]')
    lines.append("")
    for i, r in enumerate(regions):
        lines.append('[node name="Underwater%s" parent="Regions" instance=ExtResource("%d_%s")]'
                     % (r.capitalize(), i + 2, r))
        lines.append("")
    lines.append('[node name="Deco" type="Node3D" parent="."]')
    lines.append('script = ExtResource("%d_deco")' % (len(regions) + 2))
    lines.append("")
    lines.append('[node name="Chests" type="Node3D" parent="."]')
    lines.append("")
    lines.append('[node name="DiveCamera" type="Camera3D" parent="."]')
    lines.append("fov = 55.0")
    lines.append("near = 0.12")
    lines.append("far = 420.0")
    lines.append("")
    path = os.path.join(SCENES, "underwater_world.tscn")
    os.makedirs(SCENES, exist_ok=True)
    open(path, "w").write("\n".join(lines))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--region", default="")
    args = ap.parse_args()

    bake = Bake(BAKED)
    regions = [args.region] if args.region else REGIONS
    done = []
    for region in regions:
        m = export_region(bake, region)
        if m is None:
            continue
        write_region_scene(m)
        done.append(region)
        print("%-13s 单元 %2d  实例 %5d  %7.1f 万面  %6.1f MB"
              % (region, len(m["units"]), m["instance_count"],
                 m["triangles"] / 1e4, m["whole"]["bytes"] / 1e6))

    if not args.region:
        write_world_scene([r for r in REGIONS if r in done])
        print("世界场景：scenes/underwater/underwater_world.tscn")


if __name__ == "__main__":
    main()
