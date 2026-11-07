"""Fixed views for source vs optimized fidelity, in a fresh GUI each stage."""
import bpy,os
from pathlib import Path
from mathutils import Vector
R=Path('D:/projects/sea');W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'gift_kiosk/interior/v001'
sc=bpy.context.scene
label='optimized' if 'optimized' in bpy.data.filepath else 'source'
sc.render.resolution_x=1100;sc.render.resolution_y=1000;sc.render.resolution_percentage=100;sc.cycles.samples=16;sc.cycles.seed=0
try:
 p=bpy.context.preferences.addons['cycles'].preferences;p.compute_device_type='OPTIX';p.get_devices()
 for dev in p.devices:dev.use=dev.type!='CPU'
 sc.cycles.device='GPU'
except Exception:pass
for name,eye,scale in [('game',(14,-18,21),18.5),('front',(0,-20,12),18),('rear',(0,20,13),18),('side',(20,0,14),18),('top',(0,-.01,25),18)]:
 sc.camera.location=eye;sc.camera.rotation_euler=(Vector((0,0,1))-sc.camera.location).to_track_quat('-Z','Y').to_euler();sc.camera.data.ortho_scale=scale
 sc.render.filepath=str(W/(label+'-'+name+'.png'));bpy.ops.render.render(write_still=True)
 print('GKI_RENDER',label,name,flush=True)
