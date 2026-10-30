"""Surgical polish and independently openable component scenes; no scene regeneration."""
import bpy,json,math,os,sys
from pathlib import Path
from mathutils import Vector,Matrix
sys.path.insert(0,str(Path(__file__).resolve().parent))
from export_component import export_component, normalize_palette_uv
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/ocean_building_kit/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'building_kit_v001'
bpy.ops.wm.open_mainfile(filepath=str(D/'building_kit.blend'));bpy.context.preferences.filepaths.save_version=0
cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'));S=bpy.context.scene
if not S.get('kit_polished_v1'):
 for entry in cat['components']:
  if entry['id'] not in ['windmill','roof_slope']: continue
  col=bpy.data.collections[entry['collection']]
  for o in col.objects:
   if entry['id']=='windmill' and o.name.startswith(('rotor_1','rotor_3')): rotation=Matrix.Rotation(math.pi/2,4,'Y')
   elif entry['id']=='roof_slope' and o.name.startswith('roof_tile'): rotation=Matrix.Rotation(math.atan(.25),4,'X')
   else: continue
   pivot=sum((v.co for v in o.data.vertices),Vector())/len(o.data.vertices);o.data.transform(Matrix.Translation(pivot)@rotation@Matrix.Translation(-pivot))
  S.collection.children.link(col)
  bpy.context.view_layer.update()
  bpy.ops.object.select_all(action='DESELECT')
  for o in col.objects:o.select_set(True)
  target=R/'godot/assets/models/building_kit'/entry['id']/(entry['id']+'.glb')
  export_component(col,target)
  S.collection.children.unlink(col)
 S['kit_polished_v1']=True
if not S.get('kit_stair_direction_v1'):
 col=bpy.data.collections['SEA-KIT-STAIRS']
 for o in col.objects: o.data.transform(Matrix.Rotation(math.pi,4,'Z'))
 S.collection.children.link(col);bpy.context.view_layer.update();bpy.ops.object.select_all(action='DESELECT')
 for o in col.objects:o.select_set(True)
 export_component(col,R/'godot/assets/models/building_kit/stairs/stairs.glb')
 S.collection.children.unlink(col);S['kit_stair_direction_v1']=True
S.camera.location=(35,-35,32);S.camera.rotation_euler=(Vector((12,7,1))-S.camera.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.wm.save_as_mainfile(filepath=str(D/'building_kit.blend'),compress=True)
for entry in cat['components']:
 col=bpy.data.collections[entry['collection']];normalize_palette_uv(col);scene=bpy.data.scenes.new('独立组件_'+entry['name']);scene.collection.children.link(col);scene.world=S.world
 path=D/'component_packages'/entry['id']/(entry['id']+'.blend')
 bpy.data.libraries.write(str(path),{scene},fake_user=True,compress=True);bpy.data.scenes.remove(scene)
 with bpy.data.libraries.load(str(path)) as (data,_):assert len(data.scenes)==1 and entry['collection'] in data.collections
 # UV islands must have nonzero area and stay inside a single palette tile.
 for o in col.objects:
  uv=o.data.uv_layers['PaletteUV']
  for face in o.data.polygons:
   pts=[uv.data[i].uv for i in face.loop_indices]
   assert max(p.x for p in pts)-min(p.x for p in pts)>.001
   assert max(p.y for p in pts)-min(p.y for p in pts)>.001
   assert len({(int(p.x*8),int(p.y*8)) for p in pts})==1
 verts=[o.matrix_world@v.co for o in col.objects for v in o.data.vertices]
 entry['bounds']={'min':[min(v[k] for v in verts) for k in range(3)],'max':[max(v[k] for v in verts) for k in range(3)]}
(D/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for label,loc in [('front',(35,-35,32)),('back',(-12,35,30)),('top',(12,7,55)),('side',(47,7,14))]:
 S.camera.location=loc;S.camera.rotation_euler=(Vector((12,7,1))-S.camera.location).to_track_quat('-Z','Y').to_euler();S.render.filepath=str(W/(label+'.png'));bpy.ops.render.render(write_still=True)
print('KIT_REOPEN_UV_PACKAGE_PASS',len(cat['components']),flush=True)
