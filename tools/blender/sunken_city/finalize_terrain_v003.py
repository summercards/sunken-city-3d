"""Correct measured pavement boundary steps and synchronize actual final bridge instances."""
import bpy,hashlib,json,math
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v003';W=R.parent/'sea-work/sunken_city/v003'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];C={c['key']:c for c in CAT}
S=bpy.data.scenes['沉没旧城_完整参考布局_v003']
# Existing plaza base was only .5m high at the naked perimeter while its panels top at .6.
# Fill the base to .595, leaving visible .005m joints instead of a .3m accidental step to the curb.
c=C['plaza_tile'];ob=next(o for o in bpy.data.collections[c['collection']].objects if o.type=='MESH')
for v in list(ob.data.vertices)[:8]:
    if v.co.z>.49:v.co.z=.595
ob.data.update();ob['v003_edge_fill']=.095
for c in CAT:
    o=next(q for q in bpy.data.collections[c['collection']].objects if q.type=='MESH');me=o.data;me.update();me.calc_loop_triangles()
    lo=[min(v.co[i] for v in me.vertices) for i in range(3)];hi=[max(v.co[i] for v in me.vertices) for i in range(3)]
    c.update(bounds_size_m=[hi[i]-lo[i] for i in range(3)],triangles=len(me.loop_triangles),polygons=len(me.polygons),material_roles=sorted({me.materials[f.material_index].name for f in me.polygons}))
inst=[]
for o in S.objects:
    if o.instance_type!='COLLECTION' or o.instance_collection is None:continue
    c=next(c for c in CAT if c['collection']==o.instance_collection.name)
    inst.append(dict(instance_id=o.name,key=c['key'],component_id=c['component_id'],position_m=list(o.location),rotation_euler_deg=[round(math.degrees(a),6) for a in o.rotation_euler],scale=list(o.scale),source_object=o.name,urban_role=o.get('urban_role','inherited'),detail_zone=o.get('detail_zone',''),terrain_height_shift_m=o.get('terrain_height_shift_m',0)))
P['instances']=inst
for c in CAT:c['instance_count']=sum(a['key']==c['key'] for a in inst)
for pc in P['components']:pc['instance_count']=C[pc['key']]['instance_count']
for f,v in [('component_plan.json',P),('component_catalog.json',{'schema':'sea.component_catalog','components':CAT}),('component_instances.json',{'schema':'sea.component_instances','coordinate_contract':P['coordinate_contract'],'terrain_contract':P['terrain_contract'],'instances':inst})]:(D/f).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
bpy.context.view_layer.update();bpy.ops.wm.save_as_mainfile(filepath=str(W/'sunken_city_v003_working.blend'),compress=True)
print('PAVEMENT_EDGES_FIXED',len(inst),'instances')
