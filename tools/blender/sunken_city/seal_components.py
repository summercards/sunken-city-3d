"""封闭沉没旧城建筑组件的破口：把真正的开口补成向内凹陷的封盖面。

背景：组件是空壳，门口/破洞/缺楼板处可以直接游进楼体内部。
本脚本对每个"真正的开口"建一个扇形封盖，中心沿环平均法线向内收 `inset` 米，
既封住开口，又保留原破损轮廓的边缘阴影（不会变成长满的墙）。

关键判据：不是所有边界环都是开口。
- 组件里有大量**单面薄板**（招牌、玻璃、碎屑、楼板片），它们的边界环包住的
  正好是自己那片面 —— 补起来只是给薄板加背面，白涨三角面且毫无遮挡意义。
  判据：线段环内有相邻面的重心 → 这片"洞"被自己盖住了，跳过。
- 真正的开口（门口、破窗、缺楼板）环内是空的，相邻面都在环外 → 补盖。

源文件不改写，输出到新版本目录；PaletteUV 与材质槽沿用相邻面，不新增材质。

用法（headless）：
  blender -b --python seal_components.py -- --version v005 --out-version v006 \
      --runtime godot/assets/models/scenery/sunken_city [--slug X] [--dry-run]
"""
import bpy
import bmesh
import hashlib
import json
import math
import struct
import sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

REPO = Path(__file__).resolve().parents[3]


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def argval(name, default=None):
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    if name in argv:
        return argv[argv.index(name) + 1]
    return default


def has_flag(name):
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    return name in argv


def boundary_loops(bm):
    boundary = [e for e in bm.edges if len(e.link_faces) == 1]
    if not boundary:
        return []
    adj = {}
    for e in boundary:
        for v in e.verts:
            adj.setdefault(v.index, []).append(e)
    used = set()
    loops = []
    for e0 in boundary:
        if e0.index in used:
            continue
        loop_edges = []
        verts = []
        e = e0
        v = e.verts[0]
        while True:
            used.add(e.index)
            loop_edges.append(e)
            verts.append(v)
            nxt = e.other_vert(v)
            cand = [x for x in adj[nxt.index] if x.index not in used]
            if not cand:
                break
            e = cand[0]
            v = nxt
        if len(verts) >= 3:
            loops.append((verts, loop_edges))
    return loops


def plane_basis(n):
    n = n.normalized()
    ref = Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))
    u = n.cross(ref).normalized()
    v = n.cross(u).normalized()
    return u, v


def point_inside(bvh, p, max_hits=64):
    """射线奇偶判定点是否在实体内部。"""
    d = Vector((0.5113, 0.3217, 0.7961)).normalized()
    q = p.copy()
    hits = 0
    for _ in range(max_hits):
        loc, nor, idx, dist = bvh.ray_cast(q, d)
        if loc is None:
            break
        hits += 1
        q = loc + d * 1e-4
    return hits % 2 == 1


def point_in_bbox(p, mn, mx, eps=1e-3):
    return all(mn[i] - eps <= p[i] <= mx[i] + eps for i in range(3))


def poly_area_2d(pts):
    a = 0.0
    for i in range(len(pts)):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % len(pts)]
        a += x1 * y2 - x2 * y1
    return abs(a) / 2.0


def point_in_poly(pt, pts):
    x, y = pt
    inside = False
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            xin = (x2 - x1) * (y - y1) / (y2 - y1 + 1e-12) + x1
            if x < xin:
                inside = not inside
    return inside


def seal_mesh(obj, inset, min_area, max_growth, plate_loop_threshold=400):
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    uv = bm.loops.layers.uv.get('PaletteUV')
    if uv is None:
        raise RuntimeError('missing PaletteUV')

    before_boundary = sum(1 for e in bm.edges if len(e.link_faces) == 1)
    before_faces = len(bm.faces)
    bvh = BVHTree.FromBMesh(bm)
    _pts = [v.co for v in bm.verts]
    bbox_min = Vector([min(p[i] for p in _pts) for i in range(3)])
    bbox_max = Vector([max(p[i] for p in _pts) for i in range(3)])
    loops = boundary_loops(bm)

    # 环数少的组件（正常楼体）把小缝也补上，追求水密；碎块类组件环数上万，
    # 只补有实际遮挡意义的大洞，避免三角面爆炸。
    effective_min_area = min_area if len(loops) > plate_loop_threshold else 1e-4

    patched = []
    capped_loops = 0
    skipped_plate = 0
    skipped_small = 0
    capped_area = 0.0
    cap_limit = int(before_faces * max_growth)

    for verts, edges in loops:
        pts = [v.co.copy() for v in verts]
        n = Vector((0, 0, 0))
        src_face = None
        for e in edges:
            f = e.link_faces[0]
            src_face = src_face or f
            n += f.normal * f.calc_area()
        if n.length < 1e-9:
            skipped_small += 1
            continue
        n.normalize()
        u, v = plane_basis(n)
        origin = pts[0]
        poly = [((p - origin).dot(u), (p - origin).dot(v)) for p in pts]
        area = poly_area_2d(poly)
        if area < effective_min_area:
            skipped_small += 1
            continue

        # 薄板判据：某张相邻面的边界环就是这条环本身（面只有这一圈边）→ 这片"洞"
        # 其实是那张单面薄板的轮廓，补起来只是加背面，白涨面。
        # 用"面的边集合 == 环的边集合"精确判定，不用面积比较（面积比较会误杀窗洞）。
        loop_edge_ids = {e.index for e in edges}
        covered = False
        for e in edges:
            f = e.link_faces[0]
            if len(f.edges) == len(edges) and {x.index for x in f.edges} == loop_edge_ids:
                covered = True
                break
        if covered:
            skipped_plate += 1
            continue

        if len(patched) >= cap_limit:
            raise RuntimeError('cap face budget exceeded for %s' % obj.name)

        span = max((max(p[i] for p in pts) - min(p[i] for p in pts)) for i in range(3))
        depth = min(inset, 0.12 + 0.25 * span)
        centre = sum(pts, Vector()) / len(pts)
        # 封盖顶点必须落在实体内部：±法线各试一次，取真正在体内的方向，
        # 不能让补面把包围盒撑大（那会改变组件实际占地）。
        tip = None
        for sign in (1.0, -1.0):
            cand = centre - n * (depth * sign)
            if point_inside(bvh, cand):
                tip = cand
                break
        if tip is None:
            tip = centre
        if not point_in_bbox(tip, bbox_min, bbox_max):
            tip = centre
        tip = bm.verts.new(tip)

        loop0 = src_face.loops[0]
        uvc = loop0[uv].uv.copy()
        cx = (math.floor(uvc.x * 8) + 0.5) / 8
        cy = (math.floor(uvc.y * 8) + 0.5) / 8
        mat = src_face.material_index

        for i in range(len(verts)):
            a = verts[i]
            b = verts[(i + 1) % len(verts)]
            if a is b:
                continue
            try:
                f = bm.faces.new((a, b, tip))
            except ValueError:
                continue
            f.material_index = mat
            if f.normal.dot(src_face.normal) < 0:
                f.normal_flip()
            f.smooth = False
            for j, lp in enumerate(f.loops):
                ang = math.tau * j / 3.0
                lp[uv].uv = (cx + 0.023 * math.cos(ang), cy + 0.023 * math.sin(ang))
            patched.append(f)
        capped_loops += 1
        capped_area += area

    after_boundary = sum(1 for e in bm.edges if len(e.link_faces) == 1)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.update()
    return {
        'boundary_before': before_boundary,
        'boundary_after': after_boundary,
        'loops_total': len(loops),
        'openings_capped': capped_loops,
        'skipped_plate_loops': skipped_plate,
        'skipped_small_loops': skipped_small,
        'faces_before': before_faces,
        'faces_after': len(me.polygons),
        'patched_faces': len(patched),
        'capped_area_m2': round(capped_area, 2),
    }


def find_mesh_and_root(catalog_row):
    col = bpy.data.collections[catalog_row['collection']]
    objs = list(col.all_objects)
    mesh = next(o for o in objs if o.type == 'MESH')
    root = next(o for o in objs if o.type == 'EMPTY')
    return col, mesh, root


def export_glb(col, mesh, root, key, target):
    for o in list(bpy.context.scene.objects):
        if o.type in ('CAMERA', 'LIGHT'):
            bpy.data.objects.remove(o, do_unlink=True)
    root.name = 'Root_' + key
    mesh.name = 'Mesh_' + key
    mesh.data.name = 'Geometry_' + key
    bpy.context.scene.name = 'Component_' + key
    bpy.ops.object.select_all(action='DESELECT')
    for o in col.all_objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = mesh
    target.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(target), export_format='GLB', use_selection=True, export_yup=True,
        export_image_format='NONE', export_materials='EXPORT', export_animations=False,
        export_cameras=False, export_lights=False, export_texcoords=True,
        export_normals=True, export_tangents=False, export_attributes=False, export_extras=True)
    raw = target.read_bytes()
    size = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20 + size])
    assert not doc.get('images') and not doc.get('textures'), 'glb embeds textures'
    tris = 0
    for m in doc['meshes']:
        for p in m['primitives']:
            tris += doc['accessors'][p['indices']]['count'] // 3
    nodes = [n['name'] for n in doc.get('nodes', []) if 'mesh' in n]
    return {'glb': str(target.relative_to(REPO)).replace('\\', '/'), 'glb_sha256': sha(target),
            'glb_bytes': len(raw), 'exported_triangles': tris, 'mesh_nodes': nodes,
            'materials': [m.get('name') for m in doc.get('materials', [])],
            'surface_count': max((len(m['primitives']) for m in doc['meshes']), default=0)}


def main():
    version = argval('--version', 'v005')
    out_version = argval('--out-version', 'v006')
    runtime = argval('--runtime', 'godot/assets/models/scenery/sunken_city')
    inset = float(argval('--inset', '0.35'))
    min_area = float(argval('--min-area', '0.6'))
    max_growth = float(argval('--max-growth', '0.35'))
    plate_threshold = int(argval('--plate-threshold', '400'))
    only = argval('--slug')
    dry = has_flag('--dry-run')

    src_dir = REPO / 'art_source/scenes/sunken_city' / version
    out_dir = REPO / 'art_source/scenes/sunken_city' / out_version
    run_dir = REPO / runtime
    catalog = json.loads((src_dir / 'component_catalog.json').read_text(encoding='utf-8'))['components']
    rows = [c for c in catalog if c['category'] == 'architecture']
    if only:
        rows = [c for c in rows if c['slug'] == only]
    assert rows, 'no architecture components'

    records = []
    failures = []
    for c in rows:
        key = c['slug']
        source = REPO / c['component_blend']
        assert source.exists(), source
        src_hash = sha(source)
        try:
            bpy.ops.wm.open_mainfile(filepath=str(source), load_ui=False, use_scripts=False)
            bpy.context.preferences.filepaths.save_version = 0
            col, mesh, root = find_mesh_and_root(c)
            stats = seal_mesh(mesh, inset, min_area, max_growth, plate_threshold)

            record = dict(key=key, name=c['name'], source=c['component_blend'],
                          source_sha256=src_hash, **stats)

            if not dry:
                pkg_dir = out_dir / 'component_packages' / key
                pkg_dir.mkdir(parents=True, exist_ok=True)
                blend_out = pkg_dir / (key + '.blend')
                bpy.ops.wm.save_as_mainfile(filepath=str(blend_out), compress=True, relative_remap=False)
                record['sealed_blend'] = str(blend_out.relative_to(REPO)).replace('\\', '/')
                record['sealed_sha256'] = sha(blend_out)
                target = run_dir / key / (key + '.glb')
                record.update(export_glb(col, mesh, root, key, target))
                record['runtime_path'] = record['glb']
            records.append(record)
            print('SEAL', key, 'loops', stats['loops_total'],
                  'plate', stats['skipped_plate_loops'], 'small', stats['skipped_small_loops'],
                  'faces', stats['faces_before'], '->', stats['faces_after'],
                  'boundary', stats['boundary_before'], '->', stats['boundary_after'], flush=True)
        except Exception as exc:
            failures.append({'key': key, 'error': '%s: %s' % (type(exc).__name__, exc)})
            print('SEAL_FAIL', key, type(exc).__name__, exc, flush=True)

    report = {'suite': 'sunken_city', 'source_version': version, 'sealed_version': out_version,
              'inset_m': inset, 'min_loop_area_m2': min_area, 'max_face_growth': max_growth,
              'plate_loop_threshold': plate_threshold,
              'components': records, 'failures': failures,
              'total_faces_before': sum(r['faces_before'] for r in records),
              'total_faces_after': sum(r['faces_after'] for r in records),
              'total_patched_faces': sum(r['patched_faces'] for r in records)}
    if not dry:
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / 'seal_report.json').write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('SEAL_COMPLETE', len(records), 'failed', len(failures), 'faces',
          report['total_faces_before'], '->', report['total_faces_after'], flush=True)


main()
