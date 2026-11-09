"""Create openable per-component Blender scenes in a separate background process."""
import bpy,json,hashlib,os
from pathlib import Path
from mathutils import Vector
R=Path('D:/projects/sea');D=R/'art_source/scenes/bld_20261109_a/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'bld_20261109_a/v001';S=D/'bld_20261109_a.blend'
assert bpy.app.background
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
source_before=sha(S);cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'));plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));pal=R/plan['palette'];palsha=sha(pal)
for e in cat['components']:
 path=R/e['component_source'];path.parent.mkdir(parents=True,exist_ok=True)
 bpy.ops.wm.read_factory_settings(use_empty=True)
 with bpy.data.libraries.load(str(S),link=False) as (a,b):b.collections=[e['collection']]
 sc=bpy.context.scene;sc.name='BLDA_PACKAGE_'+e['key'];sc.unit_settings.system='METRIC';sc.collection.children.link(b.collections[0]);sc['asset_id']=e['asset_id'];sc['building_class']=e['building_class'] or 'not_applicable'
 for im in bpy.data.images:
  if im.source=='FILE':im.filepath=str(pal)
 for area in bpy.context.screen.areas if bpy.context.screen else []:
  if area.type=='VIEW_3D':
   area.spaces.active.shading.type='MATERIAL';area.spaces.active.region_3d.view_distance=max(e['bounds_size'])*2;area.spaces.active.region_3d.view_location=Vector((0,0,e['bounds_size'][2]/2))
 bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
 e.update(source_sha256=sha(path),palette=plan['palette'],palette_sha256=palsha,stage='source_packaged_validation_pending',manifest=path.with_name('asset_manifest.json').relative_to(R).as_posix())
 (path.parent/'asset_manifest.json').write_text(json.dumps(e,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print('BLDA_PACKAGE_SAVED',e['key'],e['source_sha256'],flush=True)
assert sha(S)==source_before and sha(pal)==palsha
(D/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(W/'package_creation.json').write_text(json.dumps({'passed':True,'packages':len(cat['components']),'source_sha256':source_before,'palette_sha256':palsha,'source_unchanged':True},indent=2)+'\n',encoding='utf-8')
print('BLDA_PACKAGES_CREATED',len(cat['components']),flush=True)
