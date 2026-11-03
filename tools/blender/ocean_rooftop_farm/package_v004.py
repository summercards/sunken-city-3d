import bpy,json,hashlib
from pathlib import Path
from mathutils import Vector
D=Path('D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v004');W=Path('D:/projects/sea-work/ocean_rooftop_farm/v004');s=bpy.context.scene
# Authorized orphan from cleared crop zone, not utility pipe against left shed.
orphans=[]
for o in list(s.objects):
 if o.instance_type=='COLLECTION' and o.get('component_id')=='SEA-SCENE-ORF2-PIPE' and o.location.x>0:
  orphans.append(o.name);bpy.data.objects.remove(o,do_unlink=True)
if orphans:
 data=json.loads((D/'upgrade_states.json').read_text(encoding='utf-8'));data['removed_orphan_irrigation']=orphans;(D/'upgrade_states.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
# Same independently validated component packaging procedure; path version only changes.
code=Path('D:/projects/sea/tools/blender/ocean_rooftop_farm/package_v003.py').read_text(encoding='utf-8').replace('/v003','/v004').replace("'version':'v003'","'version':'v004'").replace('farm_v003.blend','farm_v004.blend')
exec(compile(code,'package_v004_components','exec'))
# Build a base-only standalone collection/scene with geometry references but NO upgrade asset dependency.
base=bpy.data.scenes.new('基础楼体_普通草皮_不含升级件');bc=bpy.data.collections.new('02_游戏输出_基础楼体');base.collection.children.link(bc)
state_ids={'SEA-SCENE-ORF2-'+k.upper() for k in ['greenhouse_unbuilt','greenhouse_complete','water_tower_unbuilt','water_tower_complete']}
originals=[o for o in s.objects if o.instance_type=='COLLECTION' and o.get('component_id') not in state_ids]
pts=[]
for o in originals:
 for meshob in o.instance_collection.objects:
  if meshob.type=='MESH':pts.extend(o.matrix_world@meshob.matrix_world@Vector(v) for v in meshob.bound_box)
low=Vector([min(v[i] for v in pts) for i in range(3)]);high=Vector([max(v[i] for v in pts) for i in range(3)]);origin=Vector(((low.x+high.x)/2,(low.y+high.y)/2,low.z))
for o in originals:
 no=o.copy();no.name='BASE_'+o.name;no.location=o.location-origin;bc.objects.link(no)
# shared palette relative remap on write, no copied texture
imgs={n.image for o in originals for ob in o.instance_collection.objects if ob.type=='MESH' for m in ob.data.materials for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image}
for im in imgs:im.filepath='D:/projects/sea/art_source/shared/palettes/sea_cabin_timber_8x8_512.png'
file=D/'base_building.blend';bpy.data.libraries.write(str(file),{base},path_remap='RELATIVE_ALL',fake_user=True,compress=True)
meta={'schema':'sea.scene.base_assembly','asset_id':'SEA-SCENE-ORF2-BASE-BUILDING','name':'楼顶农场_普通草皮基础楼体','source':str(file.relative_to(Path('D:/projects/sea'))).replace('\\','/'),'source_sha256':hashlib.sha256(file.read_bytes()).hexdigest(),'version':'v004','origin':'bottom_center','origin_world_reference':list(origin),'bounds_size_m':list(high-low),'instances':len(originals),'excluded_upgrade_asset_ids':sorted(state_ids),'contains_upgrade_states':False,'runtime_status':'pending_no_Godot_import','palette':'art_source/shared/palettes/sea_cabin_timber_8x8_512.png'}
(D/'base_building_asset_manifest.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
for ob in list(base.objects):bpy.data.objects.remove(ob,do_unlink=True)
bpy.data.scenes.remove(base);bpy.data.collections.remove(bc)
for im in imgs:im.filepath='//../../../shared/palettes/sea_cabin_timber_8x8_512.png'
# Source default is before upgrade, all data and switch manifest stay available.
up=json.loads((D/'upgrade_states.json').read_text(encoding='utf-8'));up['base_building_source']='base_building.blend';up['base_origin_world_reference']=list(origin)
for pair in up['pairs']:
 pair['socket_local_to_base_blender']=list(Vector(pair['socket_world_blender'])-origin)
 for state,e in pair['states'].items():
  e['source']=next(x['component_source'] for x in json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'] if x['key']==e['component_key'])
(D/'upgrade_states.json').write_text(json.dumps(up,ensure_ascii=False,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(D/'ocean_rooftop_farm_v004.blend'),compress=True)
print(json.dumps({'base_building':str(file),'base_instances':len(originals),'base_origin':list(origin),'state_assets':4,'removed_orphan_irrigation':orphans,'source':bpy.data.filepath},ensure_ascii=False))
