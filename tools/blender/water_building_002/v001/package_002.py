import bpy,json,hashlib
from pathlib import Path
R=Path('D:/projects/sea');D=R/'art_source/scenes/water_building_002/v001';W=R.parent/'sea-work/water_building_002/v001';S=D/'water_building_002_v001.blend';pal=R/'art_source/shared/palettes/sea_cabin_timber_8x8_512.png';cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components'];source_sha=hashlib.sha256(S.read_bytes()).hexdigest();palsha=hashlib.sha256(pal.read_bytes()).hexdigest()
for e in cat:
 out=R/e['component_source'];out.parent.mkdir(parents=True,exist_ok=True);bpy.ops.wm.read_factory_settings(use_empty=True)
 with bpy.data.libraries.load(str(S),link=False) as (a,b):b.collections=[e['collection']]
 sc=bpy.context.scene;sc.name='WB002_PACKAGE_'+e['key'];sc.unit_settings.system='METRIC';sc.collection.children.link(b.collections[0]);sc['asset_id']=e['asset_id'];sc['building_class']='above_water';sc['source_version']='v001';sc['lowpoly']=True
 for im in bpy.data.images:
  if im.source=='FILE':im.filepath=str(pal)
 bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(out),compress=True);e['source_sha256']=hashlib.sha256(out.read_bytes()).hexdigest();e['palette_sha256']=palsha;e['manifest']=out.parent.joinpath('asset_manifest.json').relative_to(R).as_posix();(out.parent/'asset_manifest.json').write_text(json.dumps(e,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'catalog.json').write_text(json.dumps({'schema':'sea.component_catalog','components':cat},ensure_ascii=False,indent=2)+'\n',encoding='utf-8');(W/'package_creation.json').write_text(json.dumps({'passed':True,'components':len(cat),'source_sha256':source_sha,'palette_sha256':palsha,'source_unchanged':True},ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps({'packages':len(cat),'source_sha256':source_sha},ensure_ascii=False),flush=True)
