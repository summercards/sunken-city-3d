import bpy,os,time,json
BASE='/Users/summercards/WorkBuddy/sea/outputs/tower_district'
s=bpy.context.scene
s.render.resolution_x=960;s.render.resolution_y=406;s.render.resolution_percentage=100
s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGB'
s.eevee.taa_render_samples=24
os.makedirs(BASE+'/previews/animation_frames',exist_ok=True)
t=time.time()
for i,f in enumerate(range(1,241,2)):
 s.frame_set(f);s.render.filepath=BASE+'/previews/animation_frames/%04d.png'%i
 bpy.ops.render.render(write_still=True)
 print('MOTION_PROGRESS '+json.dumps({'frame':f,'done':i+1,'total':120,'seconds':round(time.time()-t,1)}),flush=True)
print('MOTION_COMPLETE',flush=True)
