"""Fixed-camera before/after optimization renders; read-only sources, never saves original Blend."""
import bpy,hashlib,json,os
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v003';W=R.parent/'sea-work/sunken_city/v003/import';E=json.loads((D/'export/v003/export_manifest.json').read_text(encoding='utf-8'));CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components']
assert bpy.app.background and E['passed']
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
protected={p:sha(R/p) for p in E['protected_sources']}
bpy.ops.wm.open_mainfile(filepath=str(D/'sunken_city_v003.blend'),load_ui=False,use_scripts=False)
S=bpy.data.scenes['沉没旧城_完整参考布局_v003'];bpy.context.window.scene=S
S.render.engine='CYCLES';S.cycles.samples=16;S.cycles.use_denoising=True;S.render.resolution_x=1400;S.render.resolution_y=1200;S.render.resolution_percentage=100
try:
    prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
    for device in prefs.devices:device.use=device.type!='CPU'
    if any(d.use for d in prefs.devices):S.cycles.device='GPU'
except Exception:pass
stage=bpy.data.collections['90_展示与验收_不导出']
cameras=[]
for tag,pos,target in [('game_angle',(205,-250,150),(0,0,-39)),('front',(0,-330,-20),(0,0,-37)),('back',(0,330,-20),(0,0,-37)),('side',(330,0,-20),(0,0,-37))]:
    data=bpy.data.cameras.new('02b_'+tag);camera=bpy.data.objects.new('02b_'+tag,data);stage.objects.link(camera);camera.location=pos;camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler();data.type='ORTHO';data.ortho_scale=365;cameras.append((tag,camera))
for variant in ('source','optimized'):
    if variant=='optimized':
        for c in CAT:
            rec=next(e for e in E['components'] if e['key']==c['key']);path=R/rec['optimized_source'];assert sha(path)==rec['optimized_sha256']
            obj=next(o for o in bpy.data.collections[c['collection']].objects if o.type=='MESH')
            with bpy.data.libraries.load(str(path),link=False) as (src,dst):dst.meshes=src.meshes[:1]
            obj.data=dst.meshes[0]
            for i,mat in enumerate(list(obj.data.materials)):obj.data.materials[i]=bpy.data.materials[mat.name.split('.')[0]]
    for tag,camera in cameras:
        S.camera=camera;S.render.filepath=str(W/f'fidelity_{tag}_{variant}.png');bpy.ops.render.render(write_still=True,scene=S.name)
        print('FIDELITY_RENDER',variant,tag,flush=True)
assert all(sha(R/p)==h for p,h in protected.items())
report={'passed':True,'source_protected':True,'views':['game_angle','front','back','side'],'pixel_comparison':{},'visual_review':'pending_by_parent'}
for tag,_ in cameras:
    a=bpy.data.images.load(str(W/f'fidelity_{tag}_source.png'),check_existing=False);b=bpy.data.images.load(str(W/f'fidelity_{tag}_optimized.png'),check_existing=False)
    pa=list(a.pixels[:]);pb=list(b.pixels[:]);samples=range(0,len(pa),16);delta=[abs(pa[i]-pb[i]) for i in samples]
    report['pixel_comparison'][tag]={'sampled_channel_mae':sum(delta)/max(1,len(delta)),'max_sample_error':max(delta,default=0),'exact_sample_ratio':sum(d<1e-6 for d in delta)/max(1,len(delta))}
    bpy.data.images.remove(a);bpy.data.images.remove(b)
(W/'fidelity_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('FIDELITY_SOURCE_PROTECTED',report['pixel_comparison'])
