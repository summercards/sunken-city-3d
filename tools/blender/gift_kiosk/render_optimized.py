"""Fixed reference cameras for the saved optimized Blender source."""
import bpy,json,os
from pathlib import Path
from mathutils import Vector
R=Path('D:/projects/sea');W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'gift_kiosk/v001'
sc=bpy.data.scenes['海上礼品商亭_v001'];bpy.context.window_manager.windows[0].scene=sc
views=[('hero',(25,-32,17.4),(0,0,2.7),27.6),('front',(0,-36,6),(0,0,2.9),24),('back',(0,36,6),(0,0,2.9),24),('right',(36,0,6),(0,0,2.9),24)]
for name,p,t,scale in views:
 sc.camera.location=p;sc.camera.rotation_euler=(Vector(t)-sc.camera.location).to_track_quat('-Z','Y').to_euler();sc.camera.data.ortho_scale=scale
 sc.render.resolution_x=1400;sc.render.resolution_y=1200;sc.render.filepath=str(W/('optimized_'+name+'.png'));bpy.ops.render.render(write_still=True);print('OPT_RENDER',name,flush=True)
