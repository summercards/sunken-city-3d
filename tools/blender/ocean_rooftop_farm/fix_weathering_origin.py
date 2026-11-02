import bpy,json,hashlib
from pathlib import Path
from mathutils import Vector
D=Path(r'D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v001')
bpy.ops.wm.open_mainfile(filepath=str(D/'ocean_rooftop_farm.blend'))
sc=bpy.data.scenes['海上屋顶农场_制作与装配_v001']
if bpy.context.window:bpy.context.window.scene=sc
col=bpy.data.collections['SEA-SCENE-ORF-FACADE-WEATHERING'];root=next(o for o in col.objects if o.type=='EMPTY')
bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get();pts=[]
for o in col.objects:
 if o.type=='MESH':
  ev=o.evaluated_get(deps);me=ev.to_mesh();pts.extend(o.matrix_world@v.co for v in me.vertices);ev.to_mesh_clear()
lo=Vector([min(v[i] for v in pts) for i in range(3)]);hi=Vector([max(v[i] for v in pts) for i in range(3)])
delta=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
for o in col.objects:
 if o.type=='MESH':o.location-=delta
col.instance_offset=(0,0,0)
bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
cat_path=D/'component_catalog.json';cat=json.loads(cat_path.read_text(encoding='utf-8'));e=next(x for x in cat['components'] if x['key']=='facade_weathering');pts=[]
for o in col.objects:
 if o.type=='MESH':
  ev=o.evaluated_get(deps);me=ev.to_mesh();pts.extend(o.matrix_world@v.co for v in me.vertices);ev.to_mesh_clear()
lo=Vector([min(v[i] for v in pts) for i in range(3)]);hi=Vector([max(v[i] for v in pts) for i in range(3)])
e['bounds_size']=list(hi-lo)
geom=';'.join(o.name+':'+','.join(str(round(c,4)) for v in o.data.vertices for c in v.co) for o in col.objects if o.type=='MESH');e['geometry_fingerprint']=hashlib.sha256(geom.encode()).hexdigest()
cat_path.write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(D/'ocean_rooftop_farm.blend'),compress=True)
print(json.dumps({'delta':list(delta),'bounds':e['bounds_size'],'min':list(lo),'max':list(hi)},ensure_ascii=False))
