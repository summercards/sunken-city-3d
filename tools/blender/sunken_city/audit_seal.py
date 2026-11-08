"""独立重开验收：把源包与封闭包逐项对照，产出 seal_report.json。

不信任生成时的日志，全部现场从磁盘重开量测：
- 面数、边界边数（源 → 封闭）
- 顶点包围盒必须一致（只允许补面，不允许移动原有几何）
- 材质槽数量与名称必须一致
- GLB 三角面数必须等于封闭网格三角面数，且无内嵌贴图
- 记录源/封闭 blend 与 GLB 的 SHA-256

用法：blender -b --python audit_seal.py -- --version v005 --sealed v006 \
        --runtime godot/assets/models/scenery/sunken_city
"""
import bpy
import bmesh
import hashlib
import json
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def argval(name, default=None):
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    return argv[argv.index(name) + 1] if name in argv else default


def measure(path, collection):
    bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False, use_scripts=False)
    col = bpy.data.collections[collection]
    mesh_obj = next(o for o in col.all_objects if o.type == 'MESH')
    me = mesh_obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    pts = [mesh_obj.matrix_world @ v.co for v in bm.verts]
    bbox = [round(min(p[i] for p in pts), 4) for i in range(3)] + \
           [round(max(p[i] for p in pts), 4) for i in range(3)]
    info = {
        'faces': len(bm.faces),
        'boundary_edges': sum(1 for e in bm.edges if len(e.link_faces) == 1),
        'nonmanifold_edges': sum(1 for e in bm.edges if len(e.link_faces) > 2),
        'bbox': bbox,
        'materials': [m.name if m else None for m in me.materials],
        'triangles': sum(len(f.verts) - 2 for f in bm.faces),
    }
    bm.free()
    return info


def glb_info(path):
    raw = Path(path).read_bytes()
    size = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20 + size])
    tris = 0
    for m in doc['meshes']:
        for p in m['primitives']:
            tris += doc['accessors'][p['indices']]['count'] // 3
    return {'triangles': tris, 'embedded_images': len(doc.get('images', [])),
            'materials': [m.get('name') for m in doc.get('materials', [])],
            'surface_count': max((len(m['primitives']) for m in doc['meshes']), default=0),
            'bytes': len(raw)}


def main():
    version = argval('--version', 'v005')
    sealed = argval('--sealed', 'v006')
    runtime = argval('--runtime', 'godot/assets/models/scenery/sunken_city')
    src_dir = REPO / 'art_source/scenes/sunken_city' / version
    out_dir = REPO / 'art_source/scenes/sunken_city' / sealed
    run_dir = REPO / runtime
    catalog = json.loads((src_dir / 'component_catalog.json').read_text(encoding='utf-8'))['components']
    rows = [c for c in catalog if c['category'] == 'architecture']

    records = []
    problems = []
    for c in rows:
        key = c['slug']
        src = REPO / c['component_blend']
        sealed_blend = out_dir / 'component_packages' / key / (key + '.blend')
        glb = run_dir / key / (key + '.glb')
        if not sealed_blend.exists() or not glb.exists():
            problems.append('%s: missing sealed blend or glb' % key)
            continue
        before = measure(src, c['collection'])
        after = measure(sealed_blend, c['collection'])
        g = glb_info(glb)

        if before['bbox'] != after['bbox']:
            problems.append('%s: bbox changed %s -> %s' % (key, before['bbox'], after['bbox']))
        if before['materials'] != after['materials']:
            problems.append('%s: material slots changed' % key)
        if after['faces'] < before['faces']:
            problems.append('%s: faces decreased' % key)
        if g['triangles'] != after['triangles']:
            problems.append('%s: glb tris %d != mesh tris %d' % (key, g['triangles'], after['triangles']))
        if g['embedded_images']:
            problems.append('%s: glb embeds images' % key)

        records.append({
            'key': key, 'name': c['name'],
            'source': c['component_blend'], 'source_sha256': sha(src),
            'sealed_blend': str(sealed_blend.relative_to(REPO)).replace('\\', '/'),
            'sealed_sha256': sha(sealed_blend),
            'runtime_path': str(glb.relative_to(REPO)).replace('\\', '/'),
            'glb_sha256': sha(glb), 'glb_bytes': g['bytes'],
            'faces_before': before['faces'], 'faces_after': after['faces'],
            'patched_faces': after['faces'] - before['faces'],
            'boundary_before': before['boundary_edges'],
            'boundary_after': after['boundary_edges'],
            'nonmanifold_after': after['nonmanifold_edges'],
            'bbox': after['bbox'], 'materials': after['materials'],
            'surface_count': g['surface_count'],
            'triangles': after['triangles'],
        })
        print('AUDIT', key, before['faces'], '->', after['faces'],
              'boundary', before['boundary_edges'], '->', after['boundary_edges'], flush=True)

    report = {
        'suite': 'sunken_city', 'source_version': version, 'sealed_version': sealed,
        'runtime_root': runtime, 'components': records, 'problems': problems,
        'passed': not problems,
        'totals': {
            'components': len(records),
            'faces_before': sum(r['faces_before'] for r in records),
            'faces_after': sum(r['faces_after'] for r in records),
            'patched_faces': sum(r['patched_faces'] for r in records),
            'boundary_before': sum(r['boundary_before'] for r in records),
            'boundary_after': sum(r['boundary_after'] for r in records),
        },
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / 'seal_report.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('AUDIT_COMPLETE passed=%s problems=%d' % (report['passed'], len(problems)), flush=True)
    for p in problems:
        print('PROBLEM', p, flush=True)


main()
