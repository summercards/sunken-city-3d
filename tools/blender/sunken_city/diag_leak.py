"""针对单栋：列出每个边界环的面积/包围盒/是否被判为薄板，并定位射线从哪里逃出。

用法：blender -b --python diag_leak.py -- <blend> [angle_deg] [z_offset]
"""
import bpy
import bmesh
import json
import math
import sys
from mathutils import Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index('--') + 1:]
path = argv[0]
angle = float(argv[1]) if len(argv) > 1 else 180.0
zoff = float(argv[2]) if len(argv) > 2 else 1.7

bpy.ops.wm.open_mainfile(filepath=path, load_ui=False, use_scripts=False)
mesh = next(o for o in bpy.data.objects if o.type == 'MESH')
bm = bmesh.new()
bm.from_mesh(mesh.data)
bm.transform(mesh.matrix_world)
bm.verts.ensure_lookup_table()
bm.edges.ensure_lookup_table()
bm.normal_update()
bvh = BVHTree.FromBMesh(bm)

pts = [v.co for v in bm.verts]
mn = Vector([min(p[i] for p in pts) for i in range(3)])
mx = Vector([max(p[i] for p in pts) for i in range(3)])

# 逃逸定位
a = math.radians(angle)
reach = max(mx.x - mn.x, mx.y - mn.y) / 2 + 5
o = Vector((mn.x + (mx.x - mn.x) / 2 + math.cos(a) * reach,
            mn.y + (mx.y - mn.y) / 2 + math.sin(a) * reach, mn.z + zoff))
d = (Vector((mn.x + (mx.x - mn.x) / 2, mn.y + (mx.y - mn.y) / 2, mn.z + zoff)) - o).normalized()
p = o.copy()
hits = []
for _ in range(8):
    loc, nor, idx, dist = bvh.ray_cast(p, d, 200)
    if loc is None:
        break
    hits.append([round(v, 2) for v in loc])
    p = loc + d * 1e-4

# 边界环
boundary = [e for e in bm.edges if len(e.link_faces) == 1]
deg = {}
adj = {}
for e in boundary:
    for v in e.verts:
        deg[v.index] = deg.get(v.index, 0) + 1
        adj.setdefault(v.index, []).append(e)


def plane_basis(n):
    n = n.normalized()
    ref = Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))
    u = n.cross(ref).normalized()
    return u, n.cross(u).normalized()


def poly_area(ps):
    s = 0.0
    for i in range(len(ps)):
        x1, y1 = ps[i]
        x2, y2 = ps[(i + 1) % len(ps)]
        s += x1 * y2 - x2 * y1
    return abs(s) / 2


used = set()
loops = []
idx2v = {v.index: v for v in bm.verts}
starts = [idx2v[i] for i, dg in deg.items() if dg != 2]
for v0 in starts:
    for e0 in adj[v0.index]:
        if e0.index in used:
            continue
        verts = []
        e, v = e0, v0
        while True:
            used.add(e.index)
            verts.append(v)
            nv = e.other_vert(v)
            if deg.get(nv.index, 0) != 2:
                verts.append(nv)
                break
            nxt = [x for x in adj[nv.index] if x.index != e.index]
            if not nxt:
                verts.append(nv)
                break
            e, v = nxt[0], nv
        if len(verts) >= 3:
            loops.append(verts)
out = []
for verts in loops:
    ps = [v.co.copy() for v in verts]
    ring = [round(min(p[i] for p in ps), 2) for i in range(3)] + \
           [round(max(p[i] for p in ps), 2) for i in range(3)]
    out.append({'n': len(ps), 'bbox': ring,
                'size': [round(ring[3] - ring[0], 2), round(ring[4] - ring[1], 2), round(ring[5] - ring[2], 2)]})
out.sort(key=lambda r: -(r['size'][0] * r['size'][1] + r['size'][2] * r['size'][2]))
print('LEAK' + json.dumps({'file': path.replace('\\', '/').split('/')[-1],
                            'escape_hits_along_ray': hits,
                            'n_boundary': len(boundary), 'n_loops': len(loops),
                            'loops_top': out[:12]}, ensure_ascii=False))
bm.free()
