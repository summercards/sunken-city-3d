import bpy,json,hashlib,math
from pathlib import Path
from mathutils import Matrix,Vector
R=Path('D:/projects/sea');old=R/'art_source/scenes/floating_shop/v001';D=old.parent/'v002';W=Path('D:/projects/sea-work/floating_shop/v002')
bpy.ops.wm.save_as_mainfile(filepath=str(W/'session_before.blend'),copy=True)
bpy.ops.wm.open_mainfile(filepath=str(old/'floating_shop.blend'))
sc=bpy.data.scenes['海上悬浮商铺_v001'];bpy.context.window_manager.windows[0].scene=sc;sc.name='海上悬浮商铺_v002'
catalog=json.loads((D/'catalog.json').read_text(encoding='utf-8'));layout=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))
# Change actual component vertices; roots/meshes stay identity and PaletteUV is retained.
deck=bpy.data.collections['SEA-SCENE-FSH-DECK']
for o in deck.objects:
 if o.type=='MESH':
  for v in o.data.vertices:v.co.x*=1.25;v.co.y*=1.25
  o.data.update()
rail=bpy.data.collections['SEA-SCENE-FSH-RAIL-ARC']
for o in rail.objects:
 if o.type=='MESH':
  for v in o.data.vertices:v.co.x*=8.8/7;v.co.y*=8.8/7
  o.data.update()
removed=['rail_arc_001','rail_post_001']
for n in removed:bpy.data.objects.remove(bpy.data.objects[n],do_unlink=True)
layout['instances']=[i for i in layout['instances'] if i['name'] not in removed]
for row in layout['instances']:
 o=sc.objects[row['name']];k=row['key']
 if k in ['rail_post','rail_arc']:o.location.x*=8.8/7;o.location.y*=8.8/7
 if k=='tire':o.location.x*=9.1/7.3;o.location.y*=9.1/7.3
 if k=='counterweight':o.location.x*=8.65/6.7;o.location.y*=8.65/6.7
 if k=='ladder':o.location.x*=8.7/6.94;o.location.y*=8.7/6.94
 if o.name=='mailbox_001':o.location=(-1.65,-6.40,2.5)
 if o.name=='vending_001':o.location=(1.60,-6.38,2.5)
 row['position']=list(o.location);row['rotation_euler_xyz']=list(o.rotation_euler);row['scale']=list(o.scale)
# Renormalize geometry packages after horizontal enlargement, keeping zero offsets.
for e in catalog['components']:
 col=bpy.data.collections[e['collection']];pts=[v.co for o in col.objects if o.type=='MESH' for v in o.data.vertices]
 lo=Vector([min(v[i] for v in pts) for i in range(3)]);hi=Vector([max(v[i] for v in pts) for i in range(3)]);shift=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 # Full circles/rails were already centred before scaling, so this is roundoff only.
 assert shift.length<1e-4,(e['key'],list(shift))
 e['bounds_size']=list(hi-lo);e['component_source']=e['component_source'].replace('/v001/','/v002/');e['version']='v002';e['instances']=sum(x['key']==e['key'] for x in layout['instances'])
 geom=b''.join(str(tuple(round(x,5) for x in v.co)).encode() for o in col.objects if o.type=='MESH' for v in o.data.vertices);e['geometry_fingerprint']=hashlib.sha256(geom).hexdigest()
 for k in ['source_sha256','stage']:e.pop(k,None)
layout['revision']={'removed_front_rail_instances':removed,'outer_radius_m':9,'walkway_width_m':3,'entry_opening_width_m':2*8.8*math.sin(math.pi/16)}
(D/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');(D/'component_instances.json').write_text(json.dumps(layout,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
pal=R/'art_source/shared/palettes/sea_cozy_8x8_512.png'
for im in bpy.data.images:
 if im.source=='FILE' and 'sea_cozy' in im.filepath:im.filepath=bpy.path.relpath(str(pal),start=str(D))
cam=sc.camera;cam.location=(5,-28,12);cam.rotation_euler=(Vector((0,0,3.7))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=21
sc.render.resolution_x=1500;sc.render.resolution_y=1150;sc.render.resolution_percentage=100
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(D/'floating_shop.blend'),compress=True)
print(json.dumps({'version':'v002','walkway_width_m':3,'enlargement_ratio':2.5,'entry_width_m':layout['revision']['entry_opening_width_m'],'instances':len(layout['instances'])}))
