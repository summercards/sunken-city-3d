import bpy,json,os
BASE='/Users/summercards/WorkBuddy/sea/outputs/tower_district/component_migration_v008'
files=[('before','/Users/summercards/WorkBuddy/sea/outputs/tower_district/source/tower_district_v007.blend'),('after','/Users/summercards/WorkBuddy/sea/art_source/environments/tower_zones/tower_district/source/common_components/v008/tower_district_components_v008.blend')]
for label,path in files:
 bpy.ops.wm.open_mainfile(filepath=path);s=bpy.context.scene;s.eevee.shadow_pool_size='1024';s.eevee.shadow_resolution_scale=.5;s.frame_set(1);s.render.resolution_percentage=60;s.render.filepath=BASE+'/qa/'+label+'_reorganization.png';bpy.ops.render.render(write_still=True);print('COMPARE_RENDER_DONE '+label,flush=True)
