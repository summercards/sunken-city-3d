"""Recover the first interrupted live build without rebuilding any authored geometry."""
import bpy
import hashlib
import json
import math
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v001';W=R.parent/'sea-work/sunken_city/v001'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'))
S=bpy.data.scenes['沉没旧城_完整参考布局_v001'];MASTER=bpy.data.scenes['01_组件母版_独立编辑']
STAGE=bpy.data.collections['90_展示与验收_不导出']
assert len(P['components'])==42
# Safety checkpoint of the recovered geometry, before finishing presentation and metadata.
safe=W/'recovered_geometry.blend'
if not safe.exists():bpy.ops.wm.save_as_mainfile(filepath=str(safe),copy=True,compress=True)
CAT=[]
for c in P['components']:
    col=next(co for co in bpy.data.collections if any(o.get('asset_id')==c['component_id'] and o.type=='MESH' for o in co.objects))
    mesh=next(o for o in col.objects if o.type=='MESH');mesh.data.calc_loop_triangles()
    lo=Vector(tuple(min(v.co[i] for v in mesh.data.vertices) for i in range(3)))
    hi=Vector(tuple(max(v.co[i] for v in mesh.data.vertices) for i in range(3)))
    root=next(o for o in col.objects if o.type=='EMPTY')
    row=dict(c,collection=col.name,root_object=root.name,objects=[root.name,mesh.name],bounds_size_m=list(hi-lo),
        local_origin=[0,0,0],triangles=len(mesh.data.loop_triangles),polygons=len(mesh.data.polygons),
        material_roles=sorted({mesh.data.materials[f.material_index].name for f in mesh.data.polygons}),
        component_blend=f'art_source/scenes/sunken_city/v001/component_packages/{c["key"]}/{c["key"]}.blend',
        palette=P['palette'],version='v001',source_stage='source_authored_verification_pending',collision_owner='none_pure_scenery',dependencies=[])
    CAT.append(row)
INST=[dict(a,component_id=next(c['component_id'] for c in CAT if c['key']==a['key']),source_object=a['instance_id']) for a in P['instances']]
# Reuse the corrected tail only; never call the full build or factory reset during recovery.
code=Path(__file__).with_name('build.py').read_text(encoding='utf-8')
tail=code[code.index("world=bpy.data.worlds.new("):]
exec(compile(tail,'sunken_city_recovered_tail','exec'),globals())
