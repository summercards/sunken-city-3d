import bpy,json,hashlib,os
from pathlib import Path
from mathutils import Vector
R=Path('D:/projects/sea');D=R/'art_source/scenes/floating_shop/v003';E=D/'export/v001';W=Path(os.environ.get('SEA_WORK_ROOT','D:/projects/sea-work'))/'floating_shop/v003';OPT=E/'floating_shop_optimized_v001.blend';OUT=R/'godot/assets/models/facilities/floating_shop/floating_shop.glb'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();assert Path(bpy.data.filepath)==OPT
q=json.loads((E/'optimization_manifest.json').read_text(encoding='utf-8'));assert sha(D/'floating_shop.blend')==q['source_sha256_before'] and sha(OPT)==q['optimized_sha256']
sc=bpy.data.scenes['海上悬浮商铺_v003'];data={r:{'vertices':[],'faces':[],'uv':[],'smooth':[]} for r in ['SEA_Emission','SEA_Gloss','SEA_Matte','SEA_Metal']};instances=0
for o in sc.objects:
 if o.instance_type!='COLLECTION':continue
 instances+=1
 for m in o.instance_collection.objects:
  if m.type!='MESH':continue
  assert not m.modifiers
  me=m.data;role=me.materials[0].name;d=data[role];offset=len(d['vertices']);xf=o.matrix_world@m.matrix_world;d['vertices'].extend(tuple(xf@v.co) for v in me.vertices)
  for f in me.polygons:
   d['faces'].append(tuple(offset+i for i in f.vertices));d['smooth'].append(f.use_smooth);d['uv'].extend(tuple(me.uv_layers['PaletteUV'].data[li].uv) for li in f.loop_indices)
ex=bpy.data.scenes.new('FSH_RUNTIME_V003');bpy.context.window_manager.windows[0].scene=ex;ex.unit_settings.system='METRIC';bounds=[];surfaces=[]
for role,d in data.items():
 assert d['faces'],role
 me=bpy.data.meshes.new('FSH_'+role);me.from_pydata(d['vertices'],[],d['faces']);me.update();me.materials.append(bpy.data.materials[role]);uv=me.uv_layers.new(name='PaletteUV')
 for li,co in enumerate(d['uv']):uv.data[li].uv=co
 for p,smooth in zip(me.polygons,d['smooth']):p.use_smooth=smooth
 uv.active_render=True;ob=bpy.data.objects.new('FSH_'+role,me);ex.collection.objects.link(ob);ob.select_set(True);me.calc_loop_triangles();surfaces.append({'role':role,'node':ob.name,'triangles':len(me.loop_triangles),'vertices':len(me.vertices)});bounds.extend(d['vertices'])
before=sha(OUT);backup=W/'runtime_before_v003.glb'
if not backup.exists():
 import shutil;shutil.copy2(OUT,backup)
candidate=W/'floating_shop_candidate.glb'
with bpy.context.temp_override(window=bpy.context.window_manager.windows[0],scene=ex,view_layer=ex.view_layers[0]):
 bpy.ops.export_scene.gltf(filepath=str(candidate),export_format='GLB',use_active_scene=True,use_selection=True,export_yup=True,export_materials='EXPORT',export_image_format='NONE',export_texcoords=True,export_normals=True,export_cameras=False,export_lights=False,export_extras=True,export_apply=False)
import struct
blob=candidate.read_bytes();assert blob[:4]==b'glTF';length=struct.unpack_from('<I',blob,12)[0];gltf=json.loads(blob[20:20+length]);assert not gltf.get('images') and len(gltf['meshes'])==4
os.replace(candidate,OUT)
assert sha(D/'floating_shop.blend')==q['source_sha256_before'] and sha(OPT)==q['optimized_sha256']
manifest={'schema':'sea.scene.runtime_export','asset_id':'SEA-SCENE-FSH-ASSEMBLY','version':'v003','source':q['source'],'source_sha256':q['source_sha256_before'],'optimized':q['optimized'],'optimized_sha256':q['optimized_sha256'],'optimization_manifest':'optimization_manifest.json','runtime_path':OUT.relative_to(R).as_posix(),'runtime_sha256':sha(OUT),'previous_runtime_sha256':before,'runtime_bytes':OUT.stat().st_size,'instances_baked':instances,'surfaces':surfaces,'triangles':sum(s['triangles'] for s in surfaces),'bounds_blender':{'min':[min(v[j] for v in bounds) for j in range(3)],'max':[max(v[j] for v in bounds) for j in range(3)]},'mapping':'Blender(x,y,z)->Godot(x,z,-y)','textures':'no embedded images; stable prefab overrides four roles','display_support_excluded':True,'source_hash_unchanged':True}
(E/'export_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('EXPORTED',json.dumps({'bytes':manifest['runtime_bytes'],'triangles':manifest['triangles'],'nodes':[s['node'] for s in surfaces]}))
