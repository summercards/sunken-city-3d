#!/usr/bin/env python3
"""把烘焙场景拆成「每区块一个场景 + 一个环境场景 + 一个主场景」。

产出：
  assets/zones/<zone_key>/{bake.json, instances.bin}
  assets/world/environment/{bake.json, instances.bin}
  scenes/zones/<zone_key>.tscn
  scenes/world/environment.tscn
  scenes/main.tscn

几何走共享的 assets/baked/geoms.bin（五份复制没意义），区块只存自己的实例。
区块内的坐标一律相对区块 origin（y 仍是绝对高度），搬区块只改 origin。

用法：python3 tools/build_zones.py
"""
import json
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import naming
from lib_bake import (BAKED, ROOT, Bake, assign_zone, f32_bytes)

PAD = 6.0


def main():
    bake = Bake(BAKED)
    zones = json.load(open(os.path.join(ROOT, "assets", "data", "zones.json")))
    claim_path = os.path.join(ROOT, "assets", "data", "plant_claim.json")
    claimed = set()
    if os.path.exists(claim_path):
        for bi, k in json.load(open(claim_path)):
            claimed.add((bi, k))
    print("已由植物接管的实例：", len(claimed))

    # ---- 1. 逐实例分派 ----
    buckets = defaultdict(lambda: defaultdict(list))   # zone_id|env -> batch -> [offsets]
    counts = defaultdict(int)
    for bi, k, off in bake.instances():
        if (bi, k) in claimed:
            continue
        x, y, z = bake.inst_pos(off)
        zid = assign_zone(x, z, zones, pad=PAD)
        key = zid if zid else "environment"
        origin = (0.0, 0.0) if zid is None else (
            next(zz for zz in zones if zz["id"] == zid)["origin"][0],
            next(zz for zz in zones if zz["id"] == zid)["origin"][2],
        )
        row = list(bake.inst[off:off + 16])
        row[3] -= origin[0]
        row[11] -= origin[1]
        buckets[key][bi].append(row)
        counts[key] += 1

    for key in sorted(counts, key=lambda k: -counts[k]):
        print("  %-14s %6d 实例" % (key, counts[key]))

    # ---- 2. 线框：按质心归属 ----
    lines_by = defaultdict(list)
    for line in bake.scene.get("lines", []):
        pos = line["pos"]
        n = len(pos) // 3
        cx = sum(pos[i * 3] for i in range(n)) / max(1, n)
        cz = sum(pos[i * 3 + 2] for i in range(n)) / max(1, n)
        zid = assign_zone(cx, cz, zones, pad=PAD)
        key = zid if zid else "environment"
        origin = (0.0, 0.0) if zid is None else (
            next(zz for zz in zones if zz["id"] == zid)["origin"][0],
            next(zz for zz in zones if zz["id"] == zid)["origin"][2],
        )
        newpos = []
        for i in range(n):
            newpos.append(round(pos[i * 3] - origin[0], 3))
            newpos.append(round(pos[i * 3 + 1], 3))
            newpos.append(round(pos[i * 3 + 2] - origin[1], 3))
        lines_by[key].append({"color": line["color"], "alpha": line["alpha"], "pos": newpos})

    # ---- 3. 写区块 / 环境资产 ----
    def write_asset(key, out_dir):
        os.makedirs(out_dir, exist_ok=True)
        batch_meta = []
        flat = []
        for bi in sorted(buckets[key].keys()):
            rows = buckets[key][bi]
            src = bake.scene["batches"][bi]
            batch_meta.append({
                "geom": src["geom"],
                "tex": src["tex"],
                "tint": src["tint"],
                "unlit": src["unlit"],
                "alpha": src["alpha"],
                "doubleSide": src["doubleSide"],
                "count": len(rows),
                "instOff": len(flat) // 16,
            })
            for r in rows:
                flat.extend(r)
        # 同一几何批次合并相邻同属性项，减少 draw call 的批次数
        batch_meta = merge_batches(batch_meta)
        open(os.path.join(out_dir, "instances.bin"), "wb").write(f32_bytes(flat))
        meta = {
            "key": key,
            "instance_count": len(flat) // 16,
            "batches": batch_meta,
            "lines": lines_by.get(key, []),
        }
        json.dump(meta, open(os.path.join(out_dir, "bake.json"), "w"), ensure_ascii=False)
        return meta

    assets = {}
    for z in zones:
        zid = z["id"]
        zkey = naming.zone_key(zid)
        assets[zid] = write_asset(zid, os.path.join(ROOT, "assets", "zones", zkey))
    assets["environment"] = write_asset("environment", os.path.join(ROOT, "assets", "world", "environment"))

    # ---- 4. 场景文件 ----
    for z in zones:
        write_zone_scene(z, assets[z["id"]])
    write_environment_scene(assets["environment"])
    write_main_scene(zones)
    print("场景已生成：", len(zones), "个区块 + 环境 + 主场景")


def merge_batches(batches):
    """相邻且属性相同的批次可以并成一条（实例数据本来就连续）。"""
    out = []
    for b in batches:
        if out:
            last = out[-1]
            same = all(last[k] == b[k] for k in ("geom", "tex", "tint", "unlit", "alpha", "doubleSide"))
            if same and last["instOff"] + last["count"] == b["instOff"]:
                last["count"] += b["count"]
                continue
        out.append(dict(b))
    return out


def rect2_literal(x0, z0, x1, z1):
    return "Rect2(%.3f, %.3f, %.3f, %.3f)" % (x0, z0, x1 - x0, z1 - z0)


def write_zone_scene(zone, asset):
    zid = zone["id"]
    zkey = naming.zone_key(zid)
    node = naming.zone_node(zid)
    ox, oz = zone["origin"][0], zone["origin"][2]

    lines = ["[gd_scene load_steps=5 format=3]", ""]
    lines.append('[ext_resource type="Script" path="res://scripts/world/zone_scene.gd" id="1_zone"]')
    lines.append('[ext_resource type="Script" path="res://scripts/world/zone_batch.gd" id="2_batch"]')
    lines.append('[ext_resource type="Script" path="res://scripts/world/walk_area.gd" id="3_walk"]')
    lines.append('[ext_resource type="Script" path="res://scripts/plants/plant_field.gd" id="4_plants"]')
    lines.append("")
    lines.append('[node name="%s" type="Node3D"]' % node)
    lines.append("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.3f, 0, %.3f)" % (ox, oz))
    lines.append('script = ExtResource("1_zone")')
    lines.append('zone_id = "%s"' % zid)
    lines.append('zone_label = "%s"' % naming.zone_label(zid))
    lines.append('geometry_source = "scene"')
    lines.append("")
    lines.append('[node name="StaticBatch" type="Node3D" parent="."]')
    lines.append('script = ExtResource("2_batch")')
    lines.append('bake_dir = "res://assets/zones/%s"' % zkey)
    lines.append("")
    # 建筑几何不在这里写：由 tools/build_zone_scenes.gd 把 glb 单元落成实体节点。

    # 可行动区域：一个 walk 区块一个节点，rects 是区块内相对坐标
    lines.append('[node name="WalkAreas" type="Node3D" parent="."]')
    lines.append("")
    for i, w in enumerate(zone.get("walk", [])):
        rects = ", ".join(rect2_literal(r[0] - ox, r[2] - oz, r[1] - ox, r[3] - oz) for r in w["rects"])
        span = w.get("span", [w["y"] - 0.4, w["y"] + 0.6])
        lines.append('[node name="Walk_%s" type="Node3D" parent="WalkAreas"]' % w["id"])
        lines.append('script = ExtResource("3_walk")')
        lines.append('area_id = "%s"' % w["id"])
        lines.append('zone_id = "%s"' % zid)
        lines.append('surface_y = %.3f' % float(w["y"]))
        lines.append('span_min = %.3f' % float(span[0]))
        lines.append('span_max = %.3f' % float(span[1]))
        lines.append("rects = [%s]" % rects)
        lines.append("")

    lines.append('[node name="Landings" type="Node3D" parent="."]')
    lines.append("")
    lines.append('[node name="Plants" type="Node3D" parent="."]')
    lines.append('script = ExtResource("4_plants")')
    lines.append('zone_id = "%s"' % zid)
    lines.append('placement_path = "res://assets/data/plants_%s.json"' % zkey)
    lines.append("")

    path = os.path.join(ROOT, "scenes", "zones", zkey + ".tscn")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write("\n".join(lines))


def write_environment_scene(asset):
    lines = ["[gd_scene load_steps=3 format=3]", ""]
    lines.append('[ext_resource type="Script" path="res://scripts/world/zone_batch.gd" id="1_batch"]')
    lines.append("")
    lines.append('[node name="Environment" type="Node3D"]')
    lines.append("")
    lines.append('[node name="StaticBatch" type="Node3D" parent="."]')
    lines.append('script = ExtResource("1_batch")')
    lines.append('bake_dir = "res://assets/world/environment"')
    lines.append("")
    path = os.path.join(ROOT, "scenes", "world", "environment.tscn")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write("\n".join(lines))


def write_main_scene(zones):
    lines = ["[gd_scene load_steps=%d format=3]" % (2 + len(zones)), ""]
    lines.append('[ext_resource type="Script" path="res://scripts/main.gd" id="1_main"]')
    lines.append('[ext_resource type="PackedScene" path="res://scenes/world/environment.tscn" id="2_env"]')
    for i, z in enumerate(zones):
        lines.append('[ext_resource type="PackedScene" path="res://scenes/zones/%s.tscn" id="%d_%s"]'
                     % (naming.zone_key(z["id"]), 10 + i, z["id"]))
    lines.append("")
    lines.append('[node name="Main" type="Node3D"]')
    lines.append('script = ExtResource("1_main")')
    lines.append("")
    lines.append('[node name="World" type="Node3D" parent="."]')
    lines.append("")
    lines.append('[node name="Environment" parent="World" instance=ExtResource("2_env")]')
    lines.append("")
    lines.append('[node name="Zones" type="Node3D" parent="World"]')
    lines.append("")
    for i, z in enumerate(zones):
        lines.append('[node name="%s" parent="World/Zones" instance=ExtResource("%d_%s")]'
                     % (naming.zone_node(z["id"]), 10 + i, z["id"]))
        lines.append("")
    path = os.path.join(ROOT, "scenes", "main.tscn")
    open(path, "w").write("\n".join(lines))


if __name__ == "__main__":
    main()
