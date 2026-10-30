"""Remove the studio horizon from the four orthographic reference views."""
import bpy,json
from pathlib import Path
from mathutils import Vector
W=Path('D:/projects/sea-work/floating_shop');sc=bpy.context.scene;cam=sc.camera
bpy.data.objects['展示背景地面'].hide_render=True;sc.cycles.samples=48;sc.render.resolution_percentage=100;sc.render.resolution_x=1400;sc.render.resolution_y=1000;cam.data.ortho_scale=16.3
prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
for dev in prefs.devices:dev.use=dev.type!='CPU'
sc.cycles.device='GPU' if any(d.use for d in prefs.devices) else 'CPU'
for name,pos in [('front',(0,-28,4)),('back',(0,28,4)),('left',(-28,0,4)),('right',(28,0,4))]:
 cam.location=pos;cam.rotation_euler=(Vector((0,0,3.8))-cam.location).to_track_quat('-Z','Y').to_euler();sc.render.filepath=str(W/(name+'.png'));bpy.ops.render.render(write_still=True)
bpy.ops.wm.open_mainfile(filepath='D:/projects/sea/art_source/scenes/floating_shop/v001/floating_shop.blend')
print('ORTHO_BACKGROUND_CLEANED')
