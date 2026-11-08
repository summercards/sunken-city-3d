"""检查建筑是否可以"从外面直接走进去"。

对每个组件，在玩家身高的三条水平线上（基面 +0.5 / +1.1 / +1.7 米），
从包围盒外 16 个方向朝中轴打射线。射线能无阻挡到达中轴，就说明这个方向
有可进入的开口。全部 48 条都被挡住才算"封闭"。

用法：blender -b --python verify_enterable.py -- <blend> [...]
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

    pts = [v.co for v in bm.verts]
    mn = Vector([min(p[i] for p in pts) for i in range(3)])
    mx = Vector([max(p[i] for p in pts) for i in range(3)])
    centre = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, 0))
    radius = max(mx.x - mn.x, mx.y - mn.y) / 2
    start = radius + 4.0

    heights = [mn.z + 0.5, mn.z + 1.1, mn.z + 1.7]
    enterable = []
    tested = 0
    for z in heights:
        for i in range(16):
            a = math.tau * i / 16
            origin = Vector((centre.x + math.cos(a) * start, centre.y + math.sin(a) * start, z))
            target = Vector((centre.x, centre.y, z))
            d = (target - origin).normalized()
            span = (target - origin).length
            # 射到中轴前是否被挡
            loc, nor, idx, dist = bvh.ray_cast(origin, d, span + 0.001)
            tested += 1
            if loc is None:
                enterable.append({'angle_deg': round(math.degrees(a)), 'z_offset': round(z - mn.z, 2)})

    boundary = sum(1 for e in bm.edges if len(e.link_faces) == 1)
    nonman = sum(1 for e in bm.edges if len(e.link_faces) > 2)
    bm.free()
    rows.append({
        'file': path.replace('\\', '/').split('/')[-1],
        'boundary_edges': boundary,
        'nonmanifold_edges': nonman,
        'rays_tested': tested,
        'open_directions': len(enterable),
        'open_samples': enterable[:6],
        'closed_to_entry': len(enterable) == 0,
    })
print('ENTER' + json.dumps(rows, ensure_ascii=False))
