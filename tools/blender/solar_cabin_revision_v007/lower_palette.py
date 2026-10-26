"""Material-only lower-building revision; verify and reuse unchanged optimized geometry."""
import bpy,json,hashlib
from pathlib import Path
R=Path(__file__).resolve().parents[3];OLD=R/'art_source/scenes/bloom_lower_building/v001';D=OLD.parent/'v002';PAL=R/'art_source/shared/palettes/sea_cabin_muted_8x8_512.png';D.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def save(path):
 path.parent.mkdir(parents=True,exist_ok=True)
 for im in bpy.data.images:
  if im.source=='FILE':im.filepath=str(PAL);im.reload();im.filepath=bpy.path.relpath(str(PAL),start=str(path.parent))
 bpy.context.preferences.filepaths.save_version=0
 for s in bpy.data.scenes:
  if s.render.engine=='BLENDER_EEVEE':s.render.engine='BLENDER_EEVEE_NEXT'
 bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
source=D/'bloom_lower_building.blend';bpy.ops.wm.open_mainfile(filepath=str(OLD/source.name));save(source)
cat=json.loads((OLD/'catalog.json').read_text())
for e in cat['components']:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 with bpy.data.libraries.load(str(source),link=False) as (a,b):b.collections=[e['collection']]
 bpy.context.scene.collection.children.link(b.collections[0]);p=D/'components'/e['key']/(e['key']+'.blend');save(p);bpy.ops.wm.open_mainfile(filepath=str(p));e.update(component_source=p.relative_to(R).as_posix(),source_sha256=sha(p),version='v002')
 (p.parent/'asset_manifest.json').write_text(json.dumps(e,ensure_ascii=False,indent=2),encoding='utf-8')
(D/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2),encoding='utf-8')
for f in ['component_instances.json','component_plan.json']:(D/f).write_bytes((OLD/f).read_bytes())
report=json.loads((OLD/'export/v001/export_manifest.json').read_text());old_opt=R/report['optimized_source'];assert sha(old_opt)==report['optimized_sha256']
for e in report['components']:assert sha(R/e['glb'])==e['glb_sha256']
bpy.ops.wm.open_mainfile(filepath=str(old_opt));opt=D/'export/v001/bloom_lower_building_optimized_v001.blend';save(opt);bpy.ops.wm.open_mainfile(filepath=str(opt))
bykey={e['key']:e for e in cat['components']}
for e in report['components']:
 e.update(source=bykey[e['key']]['component_source'],source_sha256=bykey[e['key']]['source_sha256'],reuse_reason='Geometry and PaletteUV unchanged; prior optimized GLB SHA-256 verified. Only the external palette binding changes.')
report.update(source=source.relative_to(R).as_posix(),source_sha256=sha(source),optimized_source=opt.relative_to(R).as_posix(),optimized_sha256=sha(opt),palette_source=PAL.relative_to(R).as_posix(),palette_sha256=sha(PAL),reuse_from=(OLD/'export/v001/export_manifest.json').relative_to(R).as_posix())
(opt.parent/'export_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('LOWER_PALETTE_REUSE_VERIFIED',len(report['components']),flush=True)
