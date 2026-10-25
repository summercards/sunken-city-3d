# -*- coding: utf-8 -*-
import bpy,json,hashlib,os
from pathlib import Path
import numpy as np
from mathutils import Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/runtime_building_reference/v002';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'runtime_building_reference_v0.2'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
cat=json.loads((D/'catalog.json').read_text());checks=json.loads((W/'organization_checks.json').read_text());assert checks['source_files_preserved']
results=[]
for row in cat['items']+cat['facilities']+cat['overviews']:
 p=R/row['source'];assert p.stem==row['asset_key']+'_v0.2';assert sha(p)==row['source_sha256']
 bpy.ops.wm.open_mainfile(filepath=str(p));bpy.context.view_layer.update();scene=bpy.context.scene
 assert scene.name==row['name'] and scene['资产英文名']==row['asset_key'] and scene['账本中文名']==row['name']
 assert any('\u4e00'<=c<='\u9fff' for c in row['name']) and 'zone1_' not in row['name']
 for lib in bpy.data.libraries:assert Path(bpy.path.abspath(lib.filepath)).is_file()
 for im in bpy.data.images:
  if im.source=='FILE':assert im.packed_file or Path(bpy.path.abspath(im.filepath)).is_file()
 for region,name in row.get('region_collections',{}).items():
  col=bpy.data.collections[name];assert name==row['facility_name']+'-'+region
  if row in cat['items']:
   for ob in col.all_objects:
    if ob.type!='MESH':continue
    zz=[(ob.matrix_world@v.co).z for v in ob.data.vertices]
    if region=='海上区域':assert min(zz,default=1.12)>1.1199,(row['asset_key'],min(zz))
    else:assert max(zz,default=1.12)<1.1201,(row['asset_key'],max(zz))
 if row in cat['items']:
  a=[];area=0
  for ob in scene.objects:
   if ob.type!='MESH':continue
   for poly in ob.data.polygons:
    v=[ob.matrix_world@ob.data.vertices[i].co for i in poly.vertices];area+=sum((v[j]-v[0]).cross(v[j+1]-v[0]).length*.5 for j in range(1,len(v)-1))
   a.extend(tuple(ob.matrix_world@v.co) for v in ob.data.vertices)
  saved=row['organized_metrics'];assert abs(area-saved['area'])/max(area,1)<1e-6
  a=np.array(a);assert np.max(abs(a.min(0)-saved['bounds']['min']))<1e-5;assert np.max(abs(a.max(0)-saved['bounds']['max']))<1e-5
 results.append(dict(asset_id=row['asset_id'],asset_key=row['asset_key'],name=row['name'],source=row['source'],source_sha256=sha(p),regions=row.get('region_collections',{})))
 print('VERIFIED',row['name'],flush=True)
assert all(sha(R/p)==h for p,h in cat['input_hashes'].items())
hierarchy={}
for overview in cat['overviews']:
 bpy.ops.wm.open_mainfile(filepath=str(R/overview['source']));scene=bpy.context.scene
 hierarchy[overview['asset_key']]={c.name:[s.name for s in c.children] for c in scene.collection.children}
 if overview['category']=='playable_reference_assembly':assert len(scene.collection.children)==5
 scene.render.engine='BLENDER_WORKBENCH';scene.display.shading.light='STUDIO';scene.display.shading.color_type='VERTEX';scene.display.shading.show_shadows=True;scene.display.shading.show_cavity=True
 if not scene.world:scene.world=bpy.data.worlds.new('PreviewWorld')
 scene.world.color=(.08,.1,.13);scene.display.shading.background_type='WORLD'
 cam=bpy.data.objects.new('展示相机',bpy.data.cameras.new('展示相机'));scene.collection.objects.link(cam)
 if overview['category']=='playable_reference_assembly':center=Vector((3,10,-6));offset=Vector((65,-85,80));scale=125
 else:center=Vector((14,10,-5));offset=Vector((48,-62,48));scale=78
 cam.location=center+offset;cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=scale;cam.data.clip_end=3000;scene.camera=cam
 scene.render.resolution_x=1400;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.render.filepath=str(W/(overview['asset_key']+'.png'));bpy.ops.render.render(write_still=True)
write(W/'verification.json',dict(passed=True,reopened=len(results),assets=results,hierarchy=hierarchy,geometry_checks=checks['geometry_checks'],old_sources_preserved=True,runtime_inputs_unchanged=True,split_height_godot=1.12,game_runtime='not_run_reference_organization_only',process_exit_code=0))
print('ORGANIZATION_VERIFIED',len(results),flush=True)
