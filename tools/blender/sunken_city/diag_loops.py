"""诊断：统计每个建筑组件的边界环面积分布，看大洞口是否被切碎。

用法：blender -b --python diag_loops.py -- <blend> [...]
"""
import bpy
import bmesh
import json
import math
import sys
from mathutils import Vector

args = sys.argv[sys.argv.index('--') + 1:]


def plane_basis(n):
    n = n.normalized()
    ref = Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))
    u = n.cross(ref).normalized()
    return u, n.cross(u).normalized()


def poly_area(pts):
    a = 0.0
    for i in range(len(pts)):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % len(pts)]
        a += x1 * y2 - x2 * y1
    return abs(a) / 2.0


def loops_by_degree(bm):
    """按顶点边界度数切链：度=2 的顶点只做续接，度≠2 视为断点。"""
    boundary = [e for e in bm.edges if len(e.link_faces) == 1]
    deg = {}
    for e in boundary:
        for v in e.verts:
            deg[v.index] = deg.get(v.index, 0) + 1
    adj = {}
    for e in boundary:
        for v in e.verts:
            adj.setdefault(v.index, []).append(e)
    used = set()
    chains = []
    # 先从断点出发走开放链
    starts = [v for v, d in deg.items() if d != 2]
    for v0 in starts:
        for e0 in adj[v0]:
            if e0.index in used:
                continue
            chain = []
            verts = []
            e, v = e0, v0
            while True:
                used.add(e.index)
                chain.append(e)
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
                chains.append((verts, chain))
    # 余下的是纯闭环
    for e0 in boundary:
        if e0.index in used:
            continue
        chain = []
        verts = []
        e, v = e0, e0.verts[0]
        while True:
            used.add(e.index)
            chain.append(e)
            verts.append(v)
            nv = e.other_vert(v)
            nxt = [x for x in adj[nv.index] if x.index not in used]
            if not nxt:
                break
            e, v = nxt[0], nv
        verts.pop()  # 闭环末端与起点重合
        if len(verts) >= 3:
            chains.append((verts, chain))
    return chains, boundary


rows = []
for path in args:
    bpy.ops.wm.open_mainfile(filepath=path, load_ui=False, use_scripts=False)
    mesh = next(o for o in bpy.data.objects if o.type == 'MESH')
    bm = bmesh.new()
    bm.from_mesh(mesh.data)
    bm.transform(mesh.matrix_world)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    bm.normal_update()
    chains, boundary = loops_by_degree(bm)
    areas = []
    for verts, chain in chains:
        pts = [v.co.copy() for v in verts]
        n = Vector((0, 0, 0))
        for e in chain:
            f = e.link_faces[0]
            n += f.normal * f.calc_area()
        if n.length < 1e-9:
            continue
        u, v = plane_basis(n)
        o = pts[0]
        poly = [((p - o).dot(u), (p - o).dot(v)) for p in pts]
        areas.append(round(poly_area(poly), 3))
    areas.sort(reverse=True)
    bm.free()
    rows.append({'file': path.replace('\\', '/').split('/')[-1], 'n_boundary_edges': len(boundary),
                 'n_chains': len(areas), 'top_areas': areas[:10],
                 'n_over_0_6': sum(1 for a in areas if a >= 0.6),
                 'n_over_2': sum(1 for a in areas if a >= 2.0),
                 'total_area': round(sum(areas), 1)})
print('DIAG' + json.dumps(rows, ensure_ascii=False))
