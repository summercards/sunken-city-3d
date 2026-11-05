"""Render fixed camera comparisons in the active Blender session; no delivery source overwritten."""
import bpy
import os
from pathlib import Path
R=Path(__file__).resolve().parents[3]
VERSION=globals().get('VERSION',os.environ.get('SEA_SUNKEN_VERSION','v001'))
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'sunken_city'/VERSION
S=bpy.data.scenes['沉没旧城_完整参考布局_'+VERSION]
if bpy.context.window:bpy.context.window.scene=S
try:
    prefs=bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type='OPTIX';prefs.get_devices()
    gpu=False
    for d in prefs.devices:
        d.use=d.type!='CPU';gpu=gpu or d.use
    if gpu:S.cycles.device='GPU'
except Exception as e:print('GPU_CONFIG',str(e))
S.render.engine='CYCLES';S.cycles.samples=24;S.cycles.use_denoising=True
views=globals().get('VIEWS',['overview','coffee'])
cameras={'overview':'相机_全景_固定','top':'相机_俯视_范围','street':'相机_电车街近景','coffee':'相机_咖啡楼近景','canal':'相机_运河街近景','architecture':'相机_建筑分离','detail':'相机_补景_红框全景','wreck':'相机_补景_道路横卧','utilities':'相机_补景_中央设施','service':'相机_补景_服务街','terrain':'相机_坡地断桥_全景','bridge':'相机_坡地断桥_近景','profile':'相机_坡地_剖向'}
for key in views:
    S.camera=bpy.data.objects[cameras[key]]
    S.render.resolution_x=1600 if key=='overview' else 1400
    S.render.resolution_y=1400 if key=='overview' else 1400
    S.render.resolution_percentage=100
    hidden=[]
    if key=='architecture':
        for name in ('街道_逐段拼接实例','设施车辆_独立实例','海藻青苔_独立可隐藏'):
            col=bpy.data.collections[name];hidden.append((col,col.hide_render));col.hide_render=True
    S.render.filepath=str(W/(key+'.png'))
    bpy.ops.render.render(write_still=True,scene=S.name)
    for col,v in hidden:col.hide_render=v
    print('RENDERED',key,flush=True)
S.camera=bpy.data.objects['相机_全景_固定']
