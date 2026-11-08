"""量化封闭效果：从模型内部向所有方向发射射线，统计有多少条能逃出实体。

封闭（watertight）后逃逸率必须为 0；未封闭时破口处的射线会直接穿出。
用法：blender -b --python verify_sealed.py -- <blend> [<blend> ...]
"""
import bpy
import bmesh
import json
import math
import sys
from mathutils import Vector
from mathutils.bvhtree import BVHTree

args = sys.argv[sys.argv.index('--') + 1:]
rows = []
for path in args:
    bpy.ops.wm.open_mainfile(filepath=path, load_ui=False, use_scripts=False)
    mesh = next(o for o in bpy.data.objects if o.type == 'MESH')
    bm = bmesh.new()
    bm.from_mesh(mesh.data)
    bm.transform(mesh.matrix_world)
    bm.normal_update()
    bvh = BVHTree.FromBMesh(bm)
    boundary = sum(1 for e in bm.edges if len(e.link_faces) == 1)
    nonman = sum(1 for e in bm.edges if len(e.link_faces) > 2)

    pts = [v.co for v in bm.verts]
    mn = Vector((min(p[i] for p in pts) for i in range(3)))
    mx = Vector((max(p[i] for p in pts) for i in range(3)))
    size = mx - mn

    # 取包围盒内部若干点作为"玩家可能站的位置"
    origins = []
    for fx in (0.3, 0.5, 0.7):
        for fy in (0.3, 0.5, 0.7):
            for fz in (0.2, 0.45, 0.7):
                origins.append(Vector((mn.x + size.x * fx, mn.y + size.y * fy, mn.z + size.z * fz)))

    dirs = []
    for i in range(16):
        a = math.tau * i / 16
        for tilt in (-0.5, 0.0, 0.5):
            dirs.append(Vector((math.cos(a) * math.cos(tilt), math.sin(a) * math.cos(tilt), math.sin(tilt))).normalized())

    # 只统计确实落在实体内部的起点（用向上/向下找面判断）
    escapes = 0
    tested = 0
    for o in origins:
        # 判断点是否在网格内部：向任意方向投射射线，命中次数为奇数则在内部
        hits = 0
        d = Vector((0.53, 0.31, 0.79)).normalized()
        p = o.copy()
        for _ in range(64):
            loc, nor, idx, dist = bvh.ray_cast(p, d)
            if loc is None:
                break
            hits += 1
            p = loc + d * 1e-5
        if hits % 2 == 0:
            continue
        for d in dirs:
            tested += 1
            loc, nor, idx, dist = bvh.ray_cast(o, d)
            if loc is None:
                escapes += 1

    bm.free()
    rows.append({'file': path.replace('\\', '/').split('/')[-1],
                 'boundary_edges': boundary, 'nonmanifold_edges': nonman,
                 'interior_rays_tested': tested, 'rays_escaping': escapes,
                 'escape_ratio': (escapes / tested) if tested else None,
                 'watertight': boundary == 0 and nonman == 0})
print('VERIFY' + json.dumps(rows, ensure_ascii=False))
