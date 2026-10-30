"""Per-component world bounds of the floating shop v002 assembly (display support excluded)."""
import bpy, json
from pathlib import Path
R = Path('D:/projects/sea')
SRC = R / 'art_source/scenes/floating_shop/v002/floating_shop.blend'
bpy.ops.wm.open_mainfile(filepath=str(SRC))
sc = bpy.data.scenes['海上悬浮商铺_v002']
ALLOW = {'FSH_建筑与固定设施', 'FSH_植物附件'}
rows = []
g_lo = [1e9] * 3
g_hi = [-1e9] * 3
for ob in sc.objects:
    if ob.type != 'EMPTY' or ob.instance_type != 'COLLECTION' or not ob.instance_collection:
        continue
    if not any(c.name in ALLOW for c in ob.users_collection):
        continue
    lo = [1e9] * 3
    hi = [-1e9] * 3
    tris = 0
    for m in ob.instance_collection.all_objects:
        if m.type != 'MESH':
            continue
        m.data.calc_loop_triangles()
        tris += len(m.data.loop_triangles)
        for v in m.data.vertices:
            p = ob.matrix_world @ m.matrix_world @ v.co
            for i in range(3):
                lo[i] = min(lo[i], p[i]); hi[i] = max(hi[i], p[i])
    if lo[0] > 1e8:
        continue
    for i in range(3):
        g_lo[i] = min(g_lo[i], lo[i]); g_hi[i] = max(g_hi[i], hi[i])
    rows.append({'name': ob.name, 'collection': ob.instance_collection.name,
                 'tris': tris,
                 'lo': [round(x, 3) for x in lo], 'hi': [round(x, 3) for x in hi]})
out = {'bounds': {'min': [round(x, 3) for x in g_lo], 'max': [round(x, 3) for x in g_hi],
                  'size': [round(g_hi[i] - g_lo[i], 3) for i in range(3)]},
       'total_tris': sum(r['tris'] for r in rows),
       'instances': len(rows), 'components': rows}
p = Path('D:/projects/sea-work/floating_shop/v002/component_bounds.json')
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding='utf-8')
print('BOUNDS', json.dumps(out['bounds']), 'TRIS', out['total_tris'], 'INST', out['instances'])
