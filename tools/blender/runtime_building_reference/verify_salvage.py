# -*- coding: utf-8 -*-
import bpy,json,hashlib,os
from pathlib import Path
from mathutils import Vector
import numpy as np
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/runtime_building_reference/v003';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'runtime_building_reference_v0.3'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
cat=json.loads((D/'catalog.json').read_text());qa=json.loads((W/'split_checks.json').read_text());assert qa['original_source_preserved'] and qa['area_relative_error']<1e-6
results=[]
for row in qa['changed_assets']:
 p=R/row['source'];assert sha(p)==row['source_sha256'];bpy.ops.wm.open_mainfile(filepath=str(p));bpy.context.view_layer.update()
 assert bpy.context.scene.name==row['name'] and bpy.context.scene['资产英文名']==row['asset_key']
 for lib in bpy.data.libraries:assert Path(bpy.path.abspath(lib.filepath)).is_file()
 for ob in bpy.context.scene.objects:
  if ob.instance_type=='COLLECTION':assert ob.instance_collection is not None
 for name in row.get('region_collections',{}).values():assert name in bpy.data.collections
 if row['asset_key']=='salvage_station':
  assert {c.name for c in bpy.context.scene.collection.children}=={'绞盘打捞台'}
  assert row['origin_godot']==[-12,0,13]
  for region,name in row['region_collections'].items():
   objects=list(bpy.data.collections[name].all_objects);assert any(o.type=='MESH' for o in objects)
   for ob in objects:
    if ob.type!='MESH':continue
    zz=[(ob.matrix_world@v.co).z for v in ob.data.vertices]
    assert min(zz,default=1.12)>1.1199 if region=='海上区域' else max(zz,default=1.12)<1.1201
 if row['asset_key']=='sea_playable_facilities':
  hierarchy={c.name:[x.name for x in c.children] for c in bpy.context.scene.collection.children};assert len(hierarchy)==6 and '绞盘打捞台' in hierarchy and '太阳能木屋' in hierarchy
 results.append(dict(asset_id=row['asset_id'],source=row['source'],source_sha256=sha(p)))
assert all(sha(R/p)==h for p,h in cat['input_hashes'].items())
# Check every old v0.2 source remains byte-identical.
old=json.loads((D.parent/'v002/catalog.json').read_text());assert all(sha(R/e['source'])==e['source_sha256'] for e in old['items']+old['facilities']+old['overviews'])
salvage=next(e for e in cat['facilities'] if e['asset_key']=='salvage_station');bpy.ops.wm.open_mainfile(filepath=str(R/salvage['source']));scene=bpy.context.scene
scene.render.engine='BLENDER_WORKBENCH';scene.display.shading.light='STUDIO';scene.display.shading.color_type='VERTEX';scene.display.shading.show_shadows=True;scene.display.shading.show_cavity=True
if not scene.world:scene.world=bpy.data.worlds.new('展示环境')
scene.world.color=(.1,.13,.17);scene.display.shading.background_type='WORLD'
bb=salvage['organized_metrics']['bounds'];center=Vector((np.array(bb['min'])+np.array(bb['max']))*.5);size=max(np.array(bb['max'])-np.array(bb['min']))
cam=bpy.data.objects.new('展示相机',bpy.data.cameras.new('展示相机'));scene.collection.objects.link(cam);cam.location=center+Vector((28,-38,28));cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=size*1.25;cam.data.clip_end=1000;scene.camera=cam;scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.render.filepath=str(W/'salvage_station_full.png');bpy.ops.render.render(write_still=True)
cam.location=Vector((0,0,2.8))+Vector((14,-18,16));cam.rotation_euler=(Vector((0,0,2.8))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=13;scene.render.filepath=str(W/'salvage_station_surface.png');bpy.ops.render.render(write_still=True)
write(W/'verification.json',dict(passed=True,changed_assets_reopened=len(results),assets=results,hierarchy=hierarchy,partition_geometry_area_relative_error=qa['area_relative_error'],triangles_before=qa['before']['triangles'],triangles_after=qa['remaining']['triangles']+qa['salvage']['triangles'],old_sources_unchanged=True,runtime_inputs_unchanged=True,game_runtime='not_run_reference_facility_partition_only',process_exit_code=0))
print('SALVAGE_VERIFIED',flush=True)
