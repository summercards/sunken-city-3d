"""Create normal standalone .blend files; libraries.write produces library-only files.
Run after build_source.py, before verify_source.py and register_sources.py.
"""
import bpy,json,hashlib,sys
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[3]
version=sys.argv[sys.argv.index('--version')+1] if '--version' in sys.argv else 'v001'
assert version in ['v001','v002','v003']
D=R/'art_source/scenes/solar_flower_house'/version;main=D/'solar_flower_house.blend'
cat=json.loads((D/'component_catalog.json').read_text())
for item in cat['components']:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 with bpy.data.libraries.load(str(main),link=False) as (src,dst):dst.collections=[item['collection']]
 scene=bpy.context.scene;scene.name='Component_'+item['slug'];scene.collection.children.link(dst.collections[0]);scene.unit_settings.system='METRIC'
 scene['component_id']=item['component_id'];scene['source_stage']='source_verified_runtime_pending'
 for img in bpy.data.images:
  if img.source=='FILE':img.filepath=str(R/'art_source/shared/palettes/sea_cozy_8x8_512.png')
 # Frame standalone meshes in the saved solid viewport; no presentation geometry mixed in.
 for screen in bpy.data.screens:
  for area in screen.areas:
   if area.type=='VIEW_3D':
    reg=area.spaces.active.region_3d;reg.view_location=Vector((0,0,item['bounds_size_m'][2]/2));reg.view_distance=max(item['bounds_size_m'])*2.0;area.spaces.active.shading.type='MATERIAL'
 bpy.context.view_layer.update()
 path=R/item['component_blend'];bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
 # save_as_mainfile remaps existing absolute image paths only with relative_remap;
 # explicitly use the shared external path relative to this independent package.
 for img in bpy.data.images:
  if img.source=='FILE':img.filepath=bpy.path.relpath(str(R/'art_source/shared/palettes/sea_cozy_8x8_512.png'))
 bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
 item['source_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
 (path.parent/'asset_manifest.json').write_text(json.dumps(item,ensure_ascii=False,indent=2)+'\n')
 print('PACKAGE_SAVED',item['slug'],flush=True)
(D/'component_catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n')
print('SEA_PACKAGES_COMPLETE',len(cat['components']),flush=True)
