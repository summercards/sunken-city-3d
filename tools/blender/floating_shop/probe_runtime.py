"""Read-only probe of the floating shop v002 assembly: scenes, collections, instances, bounds."""
import bpy, json, math
from pathlib import Path
R = Path('D:/projects/sea')
SRC = R / 'art_source/scenes/floating_shop/v002/floating_shop.blend'
bpy.ops.wm.open_mainfile(filepath=str(SRC))
report = {'file': str(SRC), 'scenes': [s.name for s in bpy.data.scenes],
          'collections': [c.name for c in bpy.data.collections]}
sc = bpy.data.scenes.get('海上悬浮商铺_v002') or bpy.data.scenes[0]
report['scene'] = sc.name
rows = []
lo = [1e9] * 3
hi = [-1e9] * 3
for ob in sc.objects:
    if ob.type not in {'MESH', 'EMPTY'}:
        rows.append({'name': ob.name, 'type': ob.type, 'instance_of': None})
        continue
    first = True
    if ob.instance_type == 'COLLECTION' and ob.instance_collection:
        meshes = [m for m in ob.instance_collection.all_objects if m.type == 'MESH']
        for m in meshes:
            for v in m.data.vertices:
                p = ob.matrix_world @ m.matrix_world @ v.co
                for i in range(3):
                    lo[i] = min(lo[i], p[i]); hi[i] = max(hi[i], p[i])
    elif ob.type == 'MESH':
        for v in ob.data.vertices:
            p = ob.matrix_world @ v.co
            for i in range(3):
                lo[i] = min(lo[i], p[i]); hi[i] = max(hi[i], p[i])
    rows.append({'name': ob.name, 'type': ob.type,
                 'instance_of': ob.instance_collection.name if ob.instance_collection else None,
                 'loc': [round(x, 4) for x in ob.matrix_world.to_translation()]})
report['objects'] = rows
report['object_count'] = len(rows)
report['instances'] = sum(1 for r in rows if r.get('instance_of'))
report['bounds'] = {'min': [round(x, 4) for x in lo], 'max': [round(x, 4) for x in hi],
                    'size': [round(hi[i] - lo[i], 4) for i in range(3)]}
# Which collections hold what: instance parents per collection.
report['collections_detail'] = {c.name: [o.name for o in c.objects][:8] for c in bpy.data.collections}
Path('D:/projects/sea-work/floating_shop/v002').mkdir(parents=True, exist_ok=True)
Path('D:/projects/sea-work/floating_shop/v002/runtime_probe.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print('PROBE_WRITTEN')
