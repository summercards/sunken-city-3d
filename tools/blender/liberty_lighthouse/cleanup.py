import bpy,hashlib,json,math
from pathlib import Path
from mathutils import Vector
R=Path(r'D:/projects/sea');D=R/'art_source/scenes/liberty_lighthouse/v001';pal=R/'art_source/shared/palettes/sea_cozy_8x8_512.png'
sc=bpy.data.scenes['巨手灯塔_制作与装配_v001'];bpy.context.window.scene=sc
roles={n:bpy.data.materials.get(n) for n in ['SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission']}
for n,m in roles.items():
 assert m is not None,n
 for node in m.node_tree.nodes:
  if node.type=='TEX_IMAGE':node.image.filepath=str(pal);node.image.reload()
for c in bpy.data.collections:
 if not c.name.startswith('SEA-SCENE-LHL-'):continue
 root=next(o for o in c.objects if o.type=='EMPTY')
 for o in c.objects:
  if o.type!='MESH':continue
  for uv in list(o.data.uv_layers):
   if uv.name!='PaletteUV':o.data.uv_layers.remove(uv)
  o.data.uv_layers.active_index=0;o.data.uv_layers[0].active_render=True
  slots=[roles.get(m.name.split('.')[0],roles['SEA_Matte']) if m else roles['SEA_Matte'] for m in o.data.materials]
  if not slots:slots=[roles['SEA_Matte']]
  indices=[min(p.material_index,len(slots)-1) for p in o.data.polygons];o.data.materials.clear()
  for m in slots:o.data.materials.append(m)
  for p,ix in zip(o.data.polygons,indices):p.material_index=ix
# Match 2.2m tower diameter and 1.8m lantern.
for key,fac in [('tower_body',.89),('lantern',.95)]:
 c=bpy.data.collections['SEA-SCENE-LHL-'+key.upper().replace('_','-')]
 for o in c.objects:
  if o.type=='MESH':
   o.location.x*=fac;o.location.y*=fac;o.scale.x*=fac;o.scale.y*=fac
# Move the rear slope to meet the front canopy; retain the reference's 2.4m clear valance.
# Normalize the canopy to local bottom-center; its assembly owns the 3.5m valance elevation.
col=bpy.data.collections['SEA-SCENE-LHL-AWNING'];bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
points=[o.matrix_world@v.co for o in col.objects if o.type=='MESH' for v in o.evaluated_get(deps).data.vertices]
delta=-min(v.z for v in points)
for o in col.objects:
 if o.type=='MESH':o.location.z+=delta
bpy.data.scenes['巨手灯塔_制作与装配_v001'].objects['awning_01'].location.z=3.5
layout_path=D/'component_instances.json';layout=json.loads(layout_path.read_text(encoding='utf-8'))
for instance in layout['instances']:
 if instance['name']=='awning_01':instance['position'][2]=3.5
layout_path.write_text(json.dumps(layout,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Add visible weathering, attached to the proper component. Idempotent replacement.
for o in list(bpy.data.objects):
 if o.name.startswith(('柱身红褐锈斑','铜像铜锈磨痕','平台红褐锈斑')):bpy.data.objects.remove(o,do_unlink=True)
colors=json.loads((pal.with_suffix('.json')).read_text())['cells'];cd={x['name']:x for x in colors}
def patch(colname,name,loc,size,rot=(0,0,0)):
 col=bpy.data.collections[colname];root=next(o for o in col.objects if o.type=='EMPTY');bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.dimensions=size;o.rotation_euler=rot;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 for c in list(o.users_collection):c.objects.unlink(o)
 col.objects.link(o);o.parent=root;o.data.materials.clear();o.data.materials.append(roles['SEA_Matte'])
 for old in list(o.data.uv_layers):o.data.uv_layers.remove(old)
 uv=o.data.uv_layers.new(name='PaletteUV');c=cd['wood_mid'];u=c['column']/8;v=1-(c['row']+1)/8
 for f in o.data.polygons:
  for j,li in enumerate(f.loop_indices):uv.data[li].uv=(u+[.28,.72,.72,.28][j]/8,v+[.28,.28,.72,.72][j]/8)
 o.data.uv_layers.active=uv;uv.active_render=True
for i in range(9):patch('SEA-SCENE-LHL-COLUMN','柱身红褐锈斑',(-.75+i*.18,-.79,1.4+(i%4)*.55),(.13+(i%3)*.04,.035,.23+(i%2)*.17),(0,0,(-.75+i*.18)*.5))
for i in range(5):patch('SEA-SCENE-LHL-ARM','铜像铜锈磨痕',(-.5+i*.22,-.77,3.7+(i%3)*.5),(.12,.03,.20+(i%2)*.18),(0,.1,0))
for i in range(8):
 a=i*math.tau/8;patch('SEA-SCENE-LHL-PLATFORM','平台红褐锈斑',(math.sin(a)*2.85,math.cos(a)*2.85,.24),(.34,.06,.15),(0,0,-a))
# Update catalog after weathering and diameter refinements.
cat=json.loads((D/'catalog.json').read_text())
for e in cat['components']:
 c=bpy.data.collections[e['collection']];pts=[o.matrix_world@v.co for o in c.objects if o.type=='MESH' for v in o.data.vertices];lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)];e['bounds_size']=[hi[i]-lo[i] for i in range(3)]
 geom=';'.join(o.name+':'+','.join(str(round(x,4)) for v in o.data.vertices for x in v.co) for o in c.objects if o.type=='MESH');e['geometry_fingerprint']=hashlib.sha256(geom.encode()).hexdigest()
(D/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n')
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(D/'liberty_lighthouse.blend'),compress=True)
print(json.dumps({'material_roles':[m.name for m in roles.values()],'collections':len(cat['components']),'palette':str(pal)},ensure_ascii=False))
