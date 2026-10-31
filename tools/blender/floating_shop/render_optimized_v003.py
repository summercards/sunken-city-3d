import bpy,json,os
from pathlib import Path
from mathutils import Vector
R=Path('D:/projects/sea');D=R/'art_source/scenes/floating_shop/v003';E=D/'export/v001';W=Path(os.environ.get('SEA_WORK_ROOT','D:/projects/sea-work'))/'floating_shop/v003';sc=bpy.data.scenes['海上悬浮商铺_v003'];bpy.context.window_manager.windows[0].scene=sc;cam=sc.camera
q=json.loads((E/'optimization_manifest.json').read_text());cat=json.loads((D/'catalog.json').read_text())['components'];q['fidelity_views']=[]
for e in cat:
 col=bpy.data.collections[e['collection']];pts=[v.co for o in col.objects if o.type=='MESH' for v in o.data.vertices];size=[max(p[j] for p in pts)-min(p[j] for p in pts) for j in range(3)];row=next(x for x in q['components'] if x['key']==e['key']);row['bounds_before_m']=e['bounds_size'];row['bounds_after_m']=size;row['max_bounds_change_m']=max(abs(size[j]-e['bounds_size'][j]) for j in range(3))
prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
for dev in prefs.devices:dev.use=dev.type!='CPU'
sc.cycles.device='GPU' if any(d.use for d in prefs.devices) else 'CPU';sc.cycles.samples=40;sc.render.resolution_percentage=100
for name,pos,size,res in [('beauty',(19,-28,20),27,(1600,1200)),('front',(0,-32,8),23,(1500,1050)),('back',(0,32,8),23,(1500,1050)),('side',(32,0,9),20,(1400,1050))]:
 bpy.data.objects['展示背景地面'].hide_render=name!='beauty';cam.location=pos;cam.rotation_euler=(Vector((0,0,3.6))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=size;sc.render.resolution_x=res[0];sc.render.resolution_y=res[1];sc.render.filepath=str(W/('optimized_'+name+'.png'));bpy.ops.render.render(write_still=True,scene=sc.name);q['fidelity_views'].append({'source':str(W/(name+'.png')),'optimized':sc.render.filepath,'camera_lighting_material_scale_identical':True})
q['fidelity_status']='rendered_pending_visual_review';(E/'optimization_manifest.json').write_text(json.dumps(q,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('OPTIMIZED_VIEWS_READY','max bounds delta',max(x['max_bounds_change_m'] for x in q['components']))
