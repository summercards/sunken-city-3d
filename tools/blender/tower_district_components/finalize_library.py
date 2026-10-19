import bpy,json,hashlib
from pathlib import Path
ROOT=Path('/Users/summercards/WorkBuddy/sea');LIB=ROOT/'art_source/environments/tower_zones/tower_district/source/common_components/v008';QA=ROOT/'outputs/tower_district/component_migration_v008/qa'
s=bpy.data.scenes['TD_组件实例街区_v008'];bpy.context.window.scene=s;s.frame_set(1);s.eevee.shadow_pool_size='1024';s.eevee.shadow_resolution_scale=.5;s.render.resolution_percentage=100;s.render.filepath=str(QA/'after_reorganization_full.png')
for old in list(bpy.data.scenes):
 if old.name=='Scene':bpy.data.scenes.remove(old)
bpy.data.orphans_purge(do_local_ids=True,do_linked_ids=False,do_recursive=True)
for a in bpy.context.screen.areas:
 if a.type=='VIEW_3D':a.spaces.active.region_3d.view_perspective='CAMERA';a.spaces.active.shading.type='MATERIAL';a.spaces.active.overlay.show_overlays=False
s['Readme']=str(LIB/'README.md');s['Verification']=str(QA/'library_verification.json');s['ComponentCount']=43;s['InstanceCount']=2883
bpy.ops.wm.save_as_mainfile(filepath=str(LIB/'tower_district_components_v008.blend'))
bpy.ops.render.render(write_still=True)
print('FINAL_LIBRARY_RENDERED',flush=True)
