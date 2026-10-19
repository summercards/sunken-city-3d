import bpy
BASE='/Users/summercards/WorkBuddy/sea/outputs/tower_district';s=bpy.context.scene
for side,power in [('L',600),('R',280)]:
 data=bpy.data.objects['TD_Steam_fill_'+side].data;data.energy=power
 if hasattr(data,'specular_factor'):data.specular_factor=0
s.camera=bpy.data.objects['TD_Reference_Camera'];s.frame_set(1)
s.render.resolution_x=1920;s.render.resolution_y=810;s.render.resolution_percentage=100;s.render.filepath=BASE+'/previews/tower_district_final.png'
bpy.ops.wm.save_as_mainfile(filepath=BASE+'/source/tower_district_v007.blend')
