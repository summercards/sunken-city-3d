import bpy,json,math
from pathlib import Path
from mathutils import Vector
R=Path('D:/projects/sea');D=R/'art_source/scenes/floating_shop/v002';W=Path('D:/projects/sea-work/floating_shop/v002')
bpy.ops.wm.open_mainfile(filepath=str(D/'floating_shop.blend'));sc=bpy.data.scenes['海上悬浮商铺_v002'];bpy.context.window_manager.windows[0].scene=sc;cam=sc.camera
prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
for d in prefs.devices:d.use=d.type!='CPU'
sc.cycles.device='GPU' if any(d.use for d in prefs.devices) else 'CPU';sc.cycles.samples=40;sc.render.resolution_percentage=100
q=json.loads((W/'verification.json').read_text());q['views']=[]
for name,pos,target,size,res in [('beauty',(5,-28,12),(0,0,3.7),21,(1500,1150)),('front',(0,-30,6.8),(0,0,3.8),20.5,(1500,1050)),('top',(0,-.001,32),(0,0,3.5),20.5,(1400,1400)),('entry',(4,-19,10),(0,-6.8,3),11.5,(1500,1150)),('building_only',(5,-28,12),(0,0,3.7),21,(1500,1150))]:
 sc.collection.children['FSH_植物附件'].hide_render=name=='building_only';bpy.data.objects['展示背景地面'].hide_render=name=='front';cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=size;sc.render.resolution_x=res[0];sc.render.resolution_y=res[1];sc.render.filepath=str(W/(name+'.png'));bpy.ops.render.render(write_still=True);q['views'].append({'name':name,'path':sc.render.filepath,'actual_render':True})
q['exit_codes']['render_views']=0;(W/'verification.json').write_text(json.dumps(q,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
bpy.ops.wm.open_mainfile(filepath=str(D/'floating_shop.blend'));print('V002_RENDERED',len(q['views']))
