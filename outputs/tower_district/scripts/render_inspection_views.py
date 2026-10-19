import bpy,json
BASE='/Users/summercards/WorkBuddy/sea/outputs/tower_district';s=bpy.context.scene
original=(s.camera,s.render.engine,s.render.resolution_x,s.render.resolution_y,s.render.resolution_percentage,s.render.filepath)
s.camera=bpy.data.objects['TD_Detail_Camera'];s.render.resolution_x=1400;s.render.resolution_y=800;s.render.resolution_percentage=100;s.render.filepath=BASE+'/previews/mechanical_detail.png'
bpy.ops.render.render(write_still=True)
s.camera=bpy.data.objects['TD_Top_Camera'];s.render.engine='BLENDER_WORKBENCH';s.render.resolution_x=1200;s.render.resolution_y=1200;s.render.filepath=BASE+'/previews/structure_top.png'
s.display.shading.light='STUDIO';s.display.shading.color_type='MATERIAL';s.display.shading.show_shadows=True;s.display.shading.show_cavity=True;s.display.shading.cavity_type='BOTH';s.display.shading.background_type='WORLD';s.world.color=(.065,.075,.085)
for o in s.objects:
 if o.type=='MESH' and o.name.startswith('TD_Volume_'):o.hide_render=True
bpy.ops.render.render(write_still=True)
for o in s.objects:
 if o.type=='MESH' and o.name.startswith('TD_Volume_'):o.hide_render=False
s.camera,s.render.engine,s.render.resolution_x,s.render.resolution_y,s.render.resolution_percentage,s.render.filepath=original
s.frame_set(1)
print('INSPECTION_RENDERS_COMPLETE')
