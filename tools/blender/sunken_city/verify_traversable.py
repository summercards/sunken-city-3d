"""判定建筑是否"可进入"——按玩家实际体积，而不是零宽射线。

检具：把玩家看成半径 PLAYER_RADIUS 的圆柱（与 sunroom_region_collision.gd 对齐，
VIEWER_RADIUS = 0.35）。从外部朝中轴打一束平行射线，横向偏移覆盖整个人身宽度；
只有整束射线都能无阻到达中轴，才算这个方向"钻得进去"。

三条水平线：基面 +0.5 / +1.1 / +1.7 米（蹲、胸、头）。

用法：blender -b --python verify_traversable.py -- <blend> [...]
输出每栋的：最大可通行缝隙（估算）、可通行方向数、封闭判定。
"""
import bpy
import bmesh
import json
import math
import sys
from mathutils import Vector
from mathutils.bvhtree import BVHTree

PLAYER_RADIUS = 0.35
PLAYER_HEIGHT = 1.6
BUNDLE = 7          # 横向 7 条射线覆盖 2×0.35 m 人身宽

argv = sys.argv[sys.argv.index('--') + 1:]
paths = []
skip = False
for a in argv:
    if skip:
        skip = False
        continue
    if a == '--out':
        skip = True
        continue
    paths.append(a)
args = paths
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
    cx, cy = (mn.x + mx.x) / 2, (mn.y + mx.y) / 2
    reach = max(mx.x - mn.x, mx.y - mn.y) / 2 + 5.0

    feet = mn.z
    levels = [feet + 0.5, feet + 1.1, feet + min(1.7, (mx.z - mn.z) * 0.9)]

    traversable = []
    tested = 0
    for z in levels:
        for i in range(16):
            a = math.tau * i / 16
            outward = Vector((math.cos(a), math.sin(a), 0))
            lateral = Vector((-math.sin(a), math.cos(a), 0))
            origin_axis = Vector((cx + outward.x * reach, cy + outward.y * reach, z))
            target = Vector((cx, cy, z))
            d = (target - origin_axis).normalized()
            span = (target - origin_axis).length + 0.001
            # 整束：横向偏移覆盖 ±PLAYER_RADIUS，竖直也覆盖 ±0.5 m 体会
            blocked_any = False
            clear_count = 0
            for k in range(BUNDLE):
                off_l = -PLAYER_RADIUS + 2 * PLAYER_RADIUS * k / (BUNDLE - 1)
                for off_z in (-0.45, 0.0, 0.45):
                    o = origin_axis + lateral * off_l + Vector((0, 0, off_z))
                    loc, nor, idx, dist = bvh.ray_cast(o, d, span)
                    if loc is None:
                        clear_count += 1
                    else:
                        blocked_any = True
            tested += 1
            if clear_count == BUNDLE * 3:
                traversable.append({'angle_deg': round(math.degrees(a)),
                                    'z_offset': round(z - feet, 2)})

    boundary = sum(1 for e in bm.edges if len(e.link_faces) == 1)
    nonman = sum(1 for e in bm.edges if len(e.link_faces) > 2)
    bm.free()
    rows.append({
        'file': path.replace('\\', '/').split('/')[-1],
        'boundary_edges': boundary,
        'nonmanifold_edges': nonman,
        'directions_tested': tested,
        'traversable_directions': len(traversable),
        'traversable_samples': traversable[:8],
        'player_can_enter': len(traversable) > 0,
    })
print('TRAV' + json.dumps(rows, ensure_ascii=False))
if '--out' in sys.argv:
    import pathlib
    out = sys.argv[sys.argv.index('--out') + 1]
    pathlib.Path(out).write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('TRAV_WRITTEN', out)
