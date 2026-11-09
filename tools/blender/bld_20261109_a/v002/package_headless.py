import bpy,json,hashlib,os
from pathlib import Path
from mathutils import Vector
R=Path('D:/projects/sea');D=R/'art_source/scenes/bld_20261109_a/v002';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'bld_20261109_a/v002';S=D/'bld_20261109_a_v002.blend';assert S.is_file();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'));plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));pal=R/plan['palette'];before=sha(S);palsha=sha(pal)
for e in cat['components']:
 path=R/e['component_source'];path.parent.mkdir(parents=True,exist_ok=True);bpy.ops.wm.read_factory_settings(use_empty=True)
 with bpy.data.libraries.load(str(S),link=False) as (a,b):b.collections=[e['collection']]
 sc=bpy.context.scene;sc.name='BLDA_V002_PACKAGE_'+e['key'];sc.unit_settings.system='METRIC';sc.collection.children.link(b.collections[0]);sc['asset_id']=e['asset_id'];sc['building_class']=e['building_class'] or 'not_applicable'
 for im in bpy.data.images:
  if im.source=='FILE':im.filepath=str(pal)
 bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True);e['source_sha256']=sha(path);e['palette_sha256']=palsha;e['manifest']=path.parent.joinpath('asset_manifest.json').relative_to(R).as_posix();(path.parent/'asset_manifest.json').write_text(json.dumps(e,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('PACKAGE',e['key'],flush=True)
assert sha(S)==before and sha(pal)==palsha;(D/'catalog.json').write_text(json.dumps({'schema':'sea.component_catalog','components':cat},ensure_ascii=False,indent=2)+'\n',encoding='utf-8');(W/'package_creation.json').write_text(json.dumps({'passed':True,'components':len(cat['components']),'source_sha256':before,'palette_sha256':palsha,'source_unchanged':True},indent=2)+'\n',encoding='utf-8');print('V002_PACKAGES',len(cat['components']),flush=True)
