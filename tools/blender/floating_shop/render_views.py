"""Render the seven reference directions plus source QA detail/separation views."""
import bpy,json,os,math
from pathlib import Path
from mathutils import Vector
R=Path('D:/projects/sea');D=R/'art_source/scenes/floating_shop/v001';W=Path(os.environ.get('SEA_WORK_ROOT','D:/projects/sea-work'))/'floating_shop'
bpy.ops.wm.open_mainfile(filepath=str(D/'floating_shop.blend'));sc=bpy.data.scenes['海上悬浮商铺_v001'];bpy.context.window_manager.windows[0].scene=sc;cam=sc.camera
report=json.loads((W/'verification.json').read_text());report['views']=[];sc.cycles.samples=48;sc.render.resolution_percentage=100
try:
 prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
 for dev in prefs.devices:dev.use=dev.type!='CPU'
 sc.cycles.device='GPU' if any(d.use for d in prefs.devices) else 'CPU'
except Exception:sc.cycles.device='CPU'
views=[('beauty',(5,-25,9),(0,0,3.7),17,(1500,1150)),('front',(0,-28,4),(0,0,3.8),16.3,(1400,1000)),('back',(0,28,4),(0,0,3.8),16.3,(1400,1000)),('left',(-28,0,4),(0,0,3.8),16.3,(1400,1000)),('right',(28,0,4),(0,0,3.8),16.3,(1400,1000)),('top45',(12,-18,23),(0,0,3.5),17.5,(1400,1400)),('top',(0,-.001,30),(0,0,3.5),16,(1400,1400)),('bottom',(8,-10,-16),(0,0,2.2),16,(1400,1400)),('detail',(5,-16,7),(0,-4.6,3.9),9.2,(1500,1200)),('building_only',(5,-25,9),(0,0,3.7),17,(1500,1150))]
for name,pos,target,size,res in views:
 sc.collection.children['FSH_植物附件'].hide_render=name=='building_only'
 floor=bpy.data.objects['展示背景地面'];floor.hide_render=name in ['bottom','front','back','left','right']
 cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=size
 sc.render.resolution_x=res[0];sc.render.resolution_y=res[1];sc.render.filepath=str(W/(name+'.png'));bpy.ops.render.render(write_still=True)
 report['views'].append({'name':name,'path':sc.render.filepath,'actual_render':True});(W/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
report['exit_codes']['render_views']=0;(W/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Leave the saved assembly open in Blender; no verification settings overwrite it.
bpy.ops.wm.open_mainfile(filepath=str(D/'floating_shop.blend'))
print('RENDERED',len(report['views']))
