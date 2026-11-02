"""阳光房（sunny_bloom_retreat）尺寸与倒角只读探针。

用法：
  blender --background art_source/scenes/sunny_bloom_retreat/v008/sunny_bloom_retreat.blend \
    --python tools/blender/sunny_bloom_retreat/probe_bevel_metrics.py -- <out.json>

做三件事，全部只读、不保存源文件：
1. 逐 mesh 记录源尺寸、三角面、面数。
2. 对 188 三角的单体（单个立方体 + 三段实体倒角）用同尺寸立方体重建，
   先匹配三角数确定段数，再按面宽中位数线性反推倒角宽度。
3. 统计开放边界环，判定墙体是否存在真实洞口。

结论口径：源单位是 Blender 米，未乘实例分轴 basis；
运行时米制必须从 Godot 侧实例变换另取，不能按统一倍率换算。
"""
import json
import math
import sys
from collections import Counter

import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[-1:]
out_path = argv[0] if argv else "probe_bevel_metrics.json"

SINGLE_CUBE_TRIS = 188
PROBE_W = 0.02


def measure(obj, dg):
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    mw = ev.matrix_world
    pts = [mw @ v.co for v in me.vertices]
    widths = []
    for p in me.polygons:
        vs = list(p.vertices)
        co = [pts[i] for i in vs]
        max_e = max((co[i] - co[(i + 1) % len(vs)]).length for i in range(len(vs)))
        if max_e < 1e-9:
            continue
        w = p.area / max_e
        if 0.0005 < w < 0.5:
            widths.append(w)
    widths.sort()
    result = {
        "verts": len(me.vertices),
        "polys": len(me.polygons),
        "tris": len(me.loop_triangles),
        "dims": [round(v, 6) for v in obj.dimensions],
        "median_width_m": widths[len(widths) // 2] if widths else None,
        "p25_width_m": widths[len(widths) // 4] if widths else None,
        "p75_width_m": widths[3 * len(widths) // 4] if widths else None,
        "bevel_modifiers": [m.name for m in obj.modifiers if m.type == 'BEVEL'],
    }
    ev.to_mesh_clear()
    return result


def recover_bevel(dims, real_median_m, real_tris):
    """重建同尺寸立方体，先匹配三角数，再线性反推倒角宽度。"""
    probes = []
    for seg in (1, 2, 3, 4):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
        o = bpy.context.object
        o.scale = dims
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        mod = o.modifiers.new("probe", "BEVEL")
        mod.width = PROBE_W
        mod.segments = seg
        mod.limit_method = 'NONE'
        dg = bpy.context.evaluated_depsgraph_get()
        m = measure(o, dg)
        med = m["median_width_m"]
        probes.append({
            "segments": seg,
            "tris": m["tris"],
            "implied_width_m": round(PROBE_W * (real_median_m / med), 6) if med else None,
        })
        bpy.data.objects.remove(o, do_unlink=True)
    hit = [p for p in probes if p["tris"] == real_tris]
    return {"segments": hit[0]["segments"] if hit else None,
            "width_m": hit[0]["implied_width_m"] if hit else None,
            "probes": probes}


def open_loops(obj, dg):
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    mw = ev.matrix_world
    edge_count = {}
    for p in me.polygons:
        vs = list(p.vertices)
        for i in range(len(vs)):
            a, b = vs[i], vs[(i + 1) % len(vs)]
            k = (a, b) if a < b else (b, a)
            edge_count[k] = edge_count.get(k, 0) + 1
    n = sum(1 for c in edge_count.values() if c == 1)
    ev.to_mesh_clear()
    return n


dg = bpy.context.evaluated_depsgraph_get()
objects = {}
for obj in bpy.data.objects:
    if obj.type != 'MESH':
        continue
    rec = measure(obj, dg)
    objects[obj.name] = rec

single = {k: v for k, v in objects.items()
          if v["tris"] == SINGLE_CUBE_TRIS and v["bevel_modifiers"] == []}
recovered = {}
for name, rec in single.items():
    recovered[name] = recover_bevel(rec["dims"], rec["median_width_m"], rec["tris"])

closure = {}
for name in ("house_mesh", "entry_mesh", "door_mesh",
             "tall_window_mesh", "narrow_window_mesh", "small_window_mesh"):
    obj = bpy.data.objects.get(name)
    if obj:
        closure[name] = {"open_boundary_edges": open_loops(obj, dg)}

width_hist = Counter(round(v["width_m"], 4) for v in recovered.values() if v["width_m"])

report = {
    "source": bpy.data.filepath,
    "blender": bpy.app.version_string,
    "note": "源单位=Blender 米，未乘实例 basis；运行时米制见 building_scale.json",
    "object_count": len(objects),
    "bevel_modifier_count": sum(len(v["bevel_modifiers"]) for v in objects.values()),
    "single_cube_objects": len(single),
    "recovered_bevel_width_histogram_m": dict(sorted(width_hist.items())),
    "recovered_bevels": {k: {"dims": single[k]["dims"],
                             "segments": v["segments"],
                             "width_m": v["width_m"]}
                         for k, v in sorted(recovered.items())},
    "recovery_detail": recovered,
    "open_boundary_check": closure,
    "objects": objects,
}

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=1)

print("MESH", len(objects), "SINGLE_CUBE", len(single), "BEVEL_MODS", report["bevel_modifier_count"])
for k, v in report["recovered_bevels"].items():
    print(f"  {k:24s} seg={v['segments']} width={v['width_m']}  dims={v['dims']}")
print("WROTE", out_path)
