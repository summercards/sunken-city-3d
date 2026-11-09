import bpy,json
from pathlib import Path
S=Path('D:/projects/sea/art_source/scenes/bld_20261109_a/v004_lowpoly/bld_20261109_a_v004_lowpoly.blend')
bpy.ops.wm.open_mainfile(filepath=str(S),load_ui=False)
dg=bpy.context.evaluated_depsgraph_get();dg.update();rows=[]; seen=set()
for oi in dg.object_instances:
    o=oi.object
    if o.type!='MESH': continue
    key=(o.original.name, tuple(round(v,5) for v in oi.matrix_world.translation))
    if key in seen: continue
    seen.add(key)
    rows.append({'name':o.name,'original':o.original.name,'instance':oi.is_instance,'parent':oi.parent.name if oi.parent else None,'loc':list(oi.matrix_world.translation),'tris':(o.evaluated_get(dg).to_mesh().calc_loop_triangles() if False else len(o.evaluated_get(dg).to_mesh().loop_triangles))})
print(json.dumps({'objects':len(bpy.data.objects),'rows':len(rows),'rows_head':rows[:20],'total_tris':sum(x['tris'] for x in rows)},ensure_ascii=False))
