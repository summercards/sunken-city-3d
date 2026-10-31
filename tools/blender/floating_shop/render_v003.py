import bpy,json,os
from pathlib import Path
from mathutils import Vector
R=Path('D:/projects/sea');D=R/'art_source/scenes/floating_shop/v003';W=Path(os.environ.get('SEA_WORK_ROOT','D:/projects/sea-work'))/'floating_shop/v003';source=D/'floating_shop.blend'
bpy.ops.wm.open_mainfile(filepath=str(source));sc=bpy.data.scenes['海上悬浮商铺_v003'];bpy.context.window_manager.windows[0].scene=sc;cam=sc.camera
prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
for d in prefs.devices:d.use=d.type!='CPU'
sc.cycles.device='GPU' if any(d.use for d in prefs.devices) else 'CPU';sc.cycles.samples=40;sc.render.resolution_percentage=100;q=json.loads((W/'verification.json').read_text());q['views']=[]
for name,pos,target,size,res in [('beauty',(19,-28,20),(0,0,3.6),27,(1600,1200)),('front',(0,-32,8),(0,0,3.6),23,(1500,1050)),('back',(0,32,8),(0,0,3.6),23,(1500,1050)),('side',(32,0,9),(0,0,3.6),20,(1400,1050)),('top',(0,-.001,35),(0,0,3.5),24,(1600,1400)),('detail',(8,-19,11),(0,-5,4),15,(1500,1150)),('building_only',(19,-28,20),(0,0,3.6),27,(1600,1200))]:
 sc.collection.children['FSH_植物附件'].hide_render=name=='building_only';bpy.data.objects['展示背景地面'].hide_render=name in ['front','back','side'];cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=size;sc.render.resolution_x=res[0];sc.render.resolution_y=res[1];sc.render.filepath=str(W/(name+'.png'));bpy.ops.render.render(write_still=True);q['views'].append({'name':name,'path':sc.render.filepath,'actual_render':True})
q['exit_codes']['render_views']=0;(W/'verification.json').write_text(json.dumps(q,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');bpy.ops.wm.open_mainfile(filepath=str(source));print('V003_RENDERED',len(q['views']))
