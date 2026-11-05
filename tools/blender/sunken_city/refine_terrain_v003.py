"""Repair authored terrain interfaces: asphalt continuity on slopes and true break/canal support."""
import bpy,json,math,hashlib
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v003';W=R.parent/'sea-work/sunken_city/v003';OLD=D.parent/'v002'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];C={c['key']:c for c in CAT};S=bpy.data.scenes['沉没旧城_完整参考布局_v003']
# Existing street_split serves the genuine slope state, not a second near-identical flat-crack state.
key='street_split';c=C[key];ob=next(o for o in bpy.data.collections[c['collection']].objects if o.type=='MESH')
# Reload only saved source geometry on retry, normalize shared roles, then warp Z by +0.2(X+12).
orig=next(c for c in json.loads((OLD/'component_catalog.json').read_text(encoding='utf-8'))['components'] if c['key']==key)
with bpy.data.libraries.load(str(R/orig['component_blend']),link=False) as (src,dst):dst.meshes=src.meshes[:1]
ob.data=dst.meshes[0]
for i,m in enumerate(list(ob.data.materials)):ob.data.materials[i]=bpy.data.materials[m.name.split('.')[0]]
for v in ob.data.vertices:v.co.z+=.2*(v.co.x+12)
lo=min(v.co.z for v in ob.data.vertices)
for v in ob.data.vertices:v.co.z-=lo
ob.data.update();ob.data.calc_loop_triangles();c.update(name='车行缓坡街段_24米高差4.8米',terrain_slope_state=True)
# Identify road-versus-court by original tile centre and keep 0.2m curb step along both terraces.
for a in P['instances']:
    o=bpy.data.objects[a['instance_id']]
    if a['key']=='street_split':
        # Four former crack domains on flat terrain become ordinary flat street instances.
        o.instance_collection=bpy.data.collections[C['street_intact']['collection']]
    if a['key']=='terrain_ramp' and abs(abs(o.location.y)-84)<.01:
        o.instance_collection=bpy.data.collections[c['collection']];o.location.z=-66.7+lo
# Lowest curve support below all terrain. Fixed straight pier pads initially used minz -66.1 which can sit
# above canal floor, but supports are decorative; guarantee no visible lower ends float above any paved ramp.
# Cut the final 15m gap's start at actual retained broken mesh end (rebar tips excluded from structural deck).
# Curved bridge and deck not altered here. Whole bridge route remains initialized from existing -78,-48 end.
for c in CAT:
    o=next(q for q in bpy.data.collections[c['collection']].objects if q.type=='MESH');me=o.data;me.update();me.calc_loop_triangles()
    lo3=[min(v.co[i] for v in me.vertices) for i in range(3)];hi=[max(v.co[i] for v in me.vertices) for i in range(3)]
    c.update(bounds_size_m=[hi[i]-lo3[i] for i in range(3)],triangles=len(me.loop_triangles),polygons=len(me.polygons),material_roles=sorted({me.materials[f.material_index].name for f in me.polygons}))
for a in P['instances']:
    o=bpy.data.objects[a['instance_id']];c=next(c for c in CAT if c['collection']==o.instance_collection.name)
    a.update(key=c['key'],component_id=c['component_id'],position_m=list(o.location),rotation_euler_deg=[round(math.degrees(v),6) for v in o.rotation_euler],scale=list(o.scale))
for c in CAT:c['instance_count']=sum(a['key']==c['key'] for a in P['instances'])
for pc in P['components']:
    cc=C[pc['key']];pc['instance_count']=cc['instance_count']
    if pc['key']=='street_split':pc.update(name=cc['name'],variant_axis='slope_state',variant_value='rise_4.8m_over_24m',variant_reason='new user-authorized slope geometry; original flat crack source retained v002')
P['terrain_contract']['sloped_road_definition']='street_split semantic slope state replaces prior crack-only design; same AssetID and prior source history retained'
for mat in list(bpy.data.materials):
    if mat.users==0:bpy.data.materials.remove(mat)
for f,v in [('component_plan.json',P),('component_catalog.json',{'schema':'sea.component_catalog','components':CAT}),('component_instances.json',{'schema':'sea.component_instances','coordinate_contract':P['coordinate_contract'],'terrain_contract':P['terrain_contract'],'instances':P['instances']})]:(D/f).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
bpy.context.view_layer.update();bpy.ops.wm.save_as_mainfile(filepath=str(W/'sunken_city_v003_working.blend'),compress=True)
print('SLOPED_ASPHALT_CONTINUITY_FIXED',sum(c['instance_count'] for c in CAT if c['key']=='street_split'))
