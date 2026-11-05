import bpy,sys,os,json
from pathlib import Path
version=os.environ.get('NGQ_VERSION','v001')
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/neon_garden_quarter'/version;W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'neon_garden_quarter'/version
bpy.ops.wm.open_mainfile(filepath=str(D/'neon_garden_quarter.blend'))
S=bpy.data.scenes['霓虹花园街区_完整装配'];bpy.context.window.scene=S
optimized=os.environ.get('NGQ_RENDER_OPTIMIZED')=='1'
if optimized:
 catalog=json.loads((D/'component_catalog.json').read_text(encoding='utf8'))['components']
 export=json.loads((D/'export'/version/'export_manifest.json').read_text(encoding='utf8'))['components']
 derived={entry['key']:entry['optimized_source'] for entry in export}
 source_mats={name:bpy.data.materials[name] for name in ['SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission']}
 printed=source_mats['SEA_Matte'].copy();printed.name='Review_Print_Atlas'
 nodes=printed.node_tree.nodes;links=printed.node_tree.links
 image=next(n for n in nodes if n.type=='TEX_IMAGE' and 'image2' in n.image.name)
 image.inputs['Vector'].links[0].from_node.uv_map='UVMap'
 bsdf=next(n for n in nodes if n.type=='BSDF_PRINCIPLED');links.new(image.outputs['Color'],bsdf.inputs['Base Color'])
 for entry in catalog:
  old=bpy.data.collections[entry['collection']];instances=[o for o in S.objects if o.instance_collection==old]
  with bpy.data.libraries.load(str(R/derived[entry['key']]),link=False) as (src,dst):dst.collections=[entry['collection']]
  new=dst.collections[0]
  for o in new.objects:
   role=o.name.split('Surface_')[-1].split('.')[0]
   material=printed if role=='SEA_Poster' else source_mats[role]
   if role!='SEA_Poster':o.data.uv_layers[0].name='PaletteUV'
   o.data.materials.clear();o.data.materials.append(material)
  for instance in instances:instance.instance_collection=new
 out=W/'optimized_renders';out.mkdir(exist_ok=True)
else:out=W/'renders'
prefs=bpy.context.preferences.addons['cycles'].preferences
try:
 prefs.compute_device_type='OPTIX';prefs.get_devices()
 for dev in prefs.devices:dev.use=dev.type!='CPU'
 if any(d.use for d in prefs.devices):S.cycles.device='GPU'
except Exception as e:print('CPU_RENDER',e)
views={'hero':'全景_完整建筑群','reference':'参考镜头_街巷','garden':'近景_屋顶菜园','top':'俯视_空间布局','rear':'补全_背面屋顶','signs':'近景_招牌厚字','architecture':'全景_完整建筑群'}
if version in ['v002','v003']:views.update(curved='专项_弧楼全高',bridge='专项_桥下连接',ground='专项_地面坠落')
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else list(views)
for key in args:
 S.camera=bpy.data.objects[views[key]];S.render.resolution_x=1300;S.render.resolution_y=1500 if key=='reference' else 1300
 if key=='reference':S.render.resolution_x=1000
 plants=bpy.data.collections.get('04_独立植物')
 if plants is not None:plants.hide_render=key=='architecture'
 if version=='v004':
  for collection in bpy.data.collections:
   if collection.get('ngq_category')=='plants':collection.hide_render=key=='architecture'
 S.render.filepath=str(out/f'{key}.png');S.cycles.samples=40;bpy.ops.render.render(write_still=True);print('NGQ_RENDER',key,flush=True)
