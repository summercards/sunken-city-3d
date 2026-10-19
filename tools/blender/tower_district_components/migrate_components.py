import bpy,math,json,hashlib,os,shutil,re,time
from collections import defaultdict,Counter
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path('/Users/summercards/WorkBuddy/sea')
BASE=ROOT/'outputs/tower_district/component_migration_v008'
LIB=ROOT/'art_source/environments/tower_zones/tower_district/source/common_components/v008'
LIB.mkdir(parents=True,exist_ok=True)
SOURCE=ROOT/'outputs/tower_district/source/tower_district_v007.blend'
SOURCE_SHA=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
s=bpy.context.scene;s.frame_set(1);source_objects=list(s.objects)
source_meshes={o.name:o for o in s.objects if o.type=='MESH' and not any(o.name.startswith('TD_'+x) for x in ['Rain_layer_','Wind_paper_','Volume_'])}
assert len(source_meshes)==66,len(source_meshes)
# In this standalone reference scene the original asphalt foundation is the footprint contract.
# It is measured before any component geometry is created; decoration never determines ROOM_FRAME.
floor=source_meshes['TD_Wet_asphalt_foundation'];fvv=[floor.matrix_world@v.co for v in floor.data.vertices]
flo=[min(v[i] for v in fvv) for i in range(3)];fhi=[max(v[i] for v in fvv) for i in range(3)]
room_origin=Vector(((flo[0]+fhi[0])/2,(flo[1]+fhi[1])/2,fhi[2]));ROOM=Matrix.Translation(room_origin)
coord={'source_space':'blender_room_local','origin_mode':'source_foundation_bounds_center_at_measured_walk_plane','room_frame_world_translation_m':list(room_origin),'room_frame_world_rotation_z_deg':0,'source_bounds_xy_m':[flo[:2],fhi[:2]],'walk_plane_z_m':fhi[2],'footprint_source_object':floor.name,'footprint_authority':'existing standalone reference-scene asphalt foundation; no gameplay whitebox supplied','blender_plane':'XY','blender_up':'+Z','rotation_y_deg_semantics':'rotation_about_blender_Z','godot_mapping':'(bx, by, bz) -> (bx, bz, -by)','scope':'standalone_reference_scene','block_id':'tower_district','level_id':None}
(LIB/'coordinate_contract.json').write_text(json.dumps(coord,indent=2,ensure_ascii=False))
# Recipe definitions only: no geometry writes before the complete plan is frozen.
recipes=[]
def part(name,indices=None):
 if not name.startswith('TD_'):name='TD_'+name
 ob=source_meshes[name];n=len(ob.data.vertices)//8
 return {'object':name,'boxes':list(range(n)) if indices is None else list(indices)}
def inst(*parts):return {'parts':list(parts)}
def add(slug,zh,category,instances,family=None,**kw):
 r={'slug':slug,'name_zh':zh,'category':category,'component_family':family or slug,'instances':instances,'variant_axis':None,'variant_value':None,'variant_reason':None};r.update(kw);recipes.append(r)
def whole(slug,zh,category,*names,**kw):add(slug,zh,category,[inst(*[part(n) for n in names])],**kw)
whole('city_backdrop','远景楼群背景','environment','Skyline_silhouettes')
whole('service_duct_tower','楼顶矩形风道塔','environment','Upper_left_rooftop_infrastructure')
# One reusable letter box and one complete typography artwork; glyphs are not arbitrary >5 variants.
marquees=sorted(n for n in source_meshes if re.match(r'TD_Marquee_\d+_',n))
add('marquee_panel','灯牌框体','fitting',[inst(part(n,range(15))) for n in marquees])
add('district_marquee_artwork','街区灯栅字图','decoration',[inst(*[part(n,range(15,len(source_meshes[n].data.vertices)//8)) for n in marquees])])
whole('marquee_mounting_rail','灯牌支撑轨','environment','Marquee_mounts_and_pipework')
# 21 cuboids per pillar, the remaining deck and weathering belong to the fascia host.
bridge='Bridge_deck_and_piers';n=len(source_meshes['TD_'+bridge].data.vertices)//8
add('bridge_pier','高架桥墩','structure',[inst(part(bridge,range(5,26))),inst(part(bridge,range(26,47)))])
add('bridge_fascia','高架桥面檐口','structure',[inst(part(bridge,list(range(5))+list(range(47,n))))])
whole('service_conduit_network','跨设施矩形管网','environment','Continuous_rectangular_conduits','Facade_micro_paneling','Electrical_meter_plates_and_hazard_labels')
add('cooling_fan_unit','方格风扇机组','fitting',[inst(part('Cooling_unit_%02d'%i)) for i in [0,2,4]])
add('cooling_louver_unit','百叶冷却机组','fitting',[inst(part('Cooling_unit_%02d'%i)) for i in [1,3,5]])
add('warning_light_bank','四格警示灯组','fitting',[inst(part('Red_warning_bank_%d'%i)) for i in [0,1]])
whole('tunnel_structure','下穿通道结构','structure','Underpass_architecture')
add('tunnel_lantern','通道壁灯','fitting',[inst(part('Tunnel_entrance_lantern_-7.0')),inst(part('Tunnel_entrance_lantern_10.6'))])
whole('convenience_facade','便利店外立面','structure','Left_shop_architecture','Left_recessed_shop_annex','Storefront_tile_face_detail')
whole('liquor_sign','酒类竖向灯牌','fitting','LIQUOR_vertical_marquee')
# Poster groups are appended as 5-cuboid strips after the ATM, according to source geometry.
atm=source_meshes['TD_ATM_and_posters'];nb=len(atm.data.vertices)//8
# Poster carrier rectangles have y=1.02 and thickness .02, followed by four text strokes.
poster_start=None
for i in range(nb):
 vv=[v.co for v in atm.data.vertices[i*8:i*8+8]]
 cy=sum(v.y for v in vv)/8;dy=max(v.y for v in vv)-min(v.y for v in vv)
 if abs(cy-1.02)<1e-4 and abs(dy-.02)<1e-4:poster_start=i;break
assert poster_start is not None
add('cash_machine','提款机及附属灯牌','fitting',[inst(part('ATM_and_posters',range(poster_start)))])
add('notice_poster_set','墙面张贴物组','decoration',[inst(part('ATM_and_posters',range(poster_start,nb)))])
whole('information_terminal','街头信息终端','fitting','Information_terminal')
whole('service_shop_facade','设备店外立面','structure','Right_shop_walls')
# Semantic separation: road information sign / shop wordmark / window lamps.
ob=source_meshes['TD_Right_signs_and_small_adverts'];sets=defaultdict(list)
for i in range(len(ob.data.vertices)//8):
 vv=[v.co for v in ob.data.vertices[i*8:i*8+8]];cx=sum(v.x for v in vv)/8;cz=sum(v.z for v in vv)/8
 sets['sector_wordmark' if cz>7 else 'window_indicator_strip' if cx>16 else 'loading_information_sign'].append(i)
for slug,zh in [('sector_wordmark','店铺发光字牌'),('window_indicator_strip','门厅方灯组'),('loading_information_sign','装卸说明牌')]:add(slug,zh,'fitting',[inst(part(ob.name,sets[slug]))])
# Four independent advert assets with host frames and fixed braces.
ob=source_meshes['TD_Rooftop_advertisements'];ads=[[],[],[],[]]
for i in range(len(ob.data.vertices)//8):
 if i<28:k=i//7
 else:
  vv=[v.co for v in ob.data.vertices[i*8:i*8+8]];cx=sum(v.x for v in vv)/8
  k=0 if cx<12.4 else 1 if cx<14.1 else 2 if cx<17 else 3
 ads[k].append(i)
for k,(slug,zh) in enumerate([('audio_advert','音响广告牌'),('food_advert','食品广告牌'),('rush_advert','RUSH广告牌'),('vinyl_advert','唱片竖广告牌')]):add(slug,zh,'fitting',[inst(part(ob.name,ads[k]))])
for side,slug,zh in [(-1,'traffic_standard_inverted','反向悬臂交通杆'),(1,'traffic_standard_standard','标准悬臂交通杆')]:
 add(slug,zh,'fitting',[inst(part('Traffic_standard_%d'%side))],family='traffic_standard',variant_axis='structure_state',variant_value='inverted_cantilever' if side<0 else 'standard_cantilever',variant_reason='悬臂偏置与可见灯面关系不同，不能靠绕Z旋转互换。')
whole('asphalt_foundation','沥青基础面','structure','Wet_asphalt_foundation')
whole('wet_road_surface','湿路面颗粒与标线','decoration','Road_pixel_surface_and_puddles')
# The source batch has two equal halves: 1 base +1320 tiles +72 curb stones +1300 scatter +24 drain cuboids.
SW='Sidewalk_tiles_and_curb';nn=len(source_meshes['TD_'+SW].data.vertices)//8;assert nn==5434
bases=[];tiles=[];curbs=[];scatter=[];drains=[]
for start in [0,2717]:
 bases.append(inst(part(SW,[start])))
 tiles.extend(inst(part(SW,[j])) for j in range(start+1,start+1321))
 curbs.extend(inst(part(SW,[j])) for j in range(start+1321,start+1393))
 scatter.extend(range(start+1393,start+2693))
 drains.extend(inst(part(SW,range(start+2693+j*8,start+2693+(j+1)*8))) for j in range(3))
add('pavement_foundation','人行道基础','structure',bases)
add('pavement_tile','人行道砖','structure',tiles)
add('curbstone','路缘石','structure',curbs)
add('pavement_scatter','路沿碎屑散布层','decoration',[inst(part(SW,scatter))])
add('drain_grate','排水格栅','fitting',drains)
add('road_barrier','道路护栏段','fitting',[inst(part('Foreground_road_divider',range(i*7,(i+1)*7))) for i in range(12)])
# Five bins (10 cuboids), four bollards (2 cuboids), and residual street scatter.
ST='Street_curbstone_litter_and_bollards'
add('street_bin','街头箱体','fitting',[inst(part(ST,range(i*10,(i+1)*10))) for i in range(5)])
add('bollard','路桩','fitting',[inst(part(ST,range(50+i*2,52+i*2))) for i in range(4)])
add('street_litter','街面碎屑散布层','decoration',[inst(part(ST,range(58,238)))])
cars=[n for n in source_meshes if n.startswith('TD_Car_') or n.startswith('TD_Tunnel_vehicle_')]
add('sedan','方块轿车','fitting',[inst(part(n)) for n in cars],material_variation='palette_uv_shift')
whole('drone_hull','巡逻无人机机身','fitting','Drone_hull')
add('drone_rotor_guard','方粒旋翼护圈','fitting',[inst(part('Drone_rotor_guard_%d'%i)) for i in range(4)])
add('drone_rotor_blades','直条旋翼叶片','fitting',[inst(part('Rotor_blades_%d'%i)) for i in range(4)])
assert len(recipes)<=50,len(recipes)
# Source cuboids must be covered exactly once, even when a legacy batch contains many logical assets.
cover=Counter((p['object'],b) for r in recipes for item in r['instances'] for p in item['parts'] for b in p['boxes'])
expected={(n,b) for n,o in source_meshes.items() for b in range(len(o.data.vertices)//8)}
assert set(cover)==expected,(len(cover),len(expected),list(expected-set(cover))[:5])
assert max(cover.values())==1

# Geometry extraction is read-only here. Plan fingerprints are frozen before creation of any output mesh.
def extract(item):
 # Multi-source host attachments are baked into the common source world frame.
 parents={source_meshes[p['object']].parent for p in item['parts']}
 if len(item['parts'])>1:assert parents=={None},parents
 ob=source_meshes[item['parts'][0]['object']];matrix=ob.matrix_world.copy();parent=ob.parent;local=ob.matrix_local.copy()
 verts=[];faces=[];uvs=[];mats=[];provenance=[]
 for p in item['parts']:
  src=source_meshes[p['object']];me=src.data;uv=me.uv_layers['PaletteUV'];xf=Matrix.Identity(4) if src==ob else matrix.inverted()@src.matrix_world
  for bi in p['boxes']:
   vi=len(verts);verts.extend([xf@me.vertices[bi*8+j].co for j in range(8)])
   for poly in me.polygons[bi*6:bi*6+6]:
    faces.append(tuple(vi+(j-bi*8) for j in poly.vertices));mats.append(me.materials[poly.material_index])
    uvs.append([tuple(uv.data[j].uv) for j in poly.loop_indices])
   provenance.append([src.name,bi])
 low=Vector([min(v[j] for v in verts) for j in range(3)]);high=Vector([max(v[j] for v in verts) for j in range(3)])
 anchor=Vector(((low.x+high.x)/2,(low.y+high.y)/2,low.z));vv=[v-anchor for v in verts]
 fp=hashlib.sha256(json.dumps(sorted([tuple(round(x,4) for x in v) for v in vv]),separators=(',',':')).encode()).hexdigest()
 return {'verts':vv,'faces':faces,'uvs':uvs,'materials':mats,'anchor':anchor,'size':high-low,'fingerprint':fp,'world':matrix@Matrix.Translation(anchor),'local':local@Matrix.Translation(anchor),'parent':parent,'source':provenance,'palette_shift':[0,0,0]}
plan_groups=[]
for r in recipes:
 data=[extract(i) for i in r['instances']];r['_data']=data;base=data[0]
 for d in data:
  assert len(d['verts'])==len(base['verts']) and len(d['faces'])==len(base['faces']),(r['slug'],'topology mismatch')
  assert max((a-b).length for a,b in zip(d['verts'],base['verts']))<1e-4,(r['slug'],'geometry mismatch')
  assert [m.name for m in d['materials']]==[m.name for m in base['materials']],(r['slug'],'role mismatch')
  assert d['fingerprint']==base['fingerprint'],(r['slug'],'fingerprint mismatch')
 # Find UV color changes without duplicating geometry or the four shared material roles.
 mask=[0.0]*len(base['faces'])
 for d in data:
  shifts=[]
  for fi,(a,b) in enumerate(zip(base['uvs'],d['uvs'])):
   delta=[b[0][j]-a[0][j] for j in range(2)]
   assert all(abs((bb[j]-aa[j])-delta[j])<1e-6 for aa,bb in zip(a,b) for j in range(2))
   if max(abs(x) for x in delta)>1e-6:mask[fi]=1;shifts.append(delta)
  if shifts:
   assert all(max(abs(x-y) for x,y in zip(delta,shifts[0]))<1e-6 for delta in shifts),(r['slug'],'multiple nonuniform palette shifts')
   d['palette_shift']=[*shifts[0],0]
 # Every instance's UV must be reproducible using the union mask and one instancer attribute.
 for d in data:
  for fi,(a,b) in enumerate(zip(base['uvs'],d['uvs'])):
   assert all(abs(bb[j]-aa[j]-mask[fi]*d['palette_shift'][j])<1e-6 for aa,bb in zip(a,b) for j in range(2)),(r['slug'],'palette reconstruction')
 r['_mask']=mask
 cid='ENV-TOWER-DISTRICT-'+r['slug'].replace('_','-').upper();r['component_id']=cid;r['asset_id']=cid
 roles=sorted({m.name for m in base['materials']});r['geometry_fingerprint']=base['fingerprint']
 group={k:v for k,v in r.items() if not k.startswith('_') and k!='instances'}
 group.update({'axis':'structure' if r['category']=='structure' else 'fitting','instance_count':len(data),'bounds_size_m':list(base['size']),'front_axis':'-Y','allowed_rotations_y_deg':[0,90,180,270],'local_origin':[0,0,0],'material_roles':roles,'source_object_fragments':r['instances'],'serves_room_types':['TOWER_DISTRICT_REFERENCE'],'scope':'room_type_local','room_owned_geometry':False,'merge_key':{'bounds_size_m':[round(x,4) for x in base['size']],'interface':{'origin':'bottom_xy_center','front_axis':'-Y','allowed_rotations_y_deg':[0,90,180,270]},'material_roles':roles,'geometry_fingerprint':base['fingerprint']},'material_variants':sorted({tuple(round(x,6) for x in d['palette_shift']) for d in data})})
 plan_groups.append(group)
plan={'schema':'shellstorm2.battle.component_plan','schema_version':1,'library':'v008','block_id':'tower_district','level_id':None,'source_room_type':'TOWER_DISTRICT_REFERENCE','migration_scope':'existing standalone Blender scene; modelling hierarchy and exact-geometry reuse only','source_blend':str(SOURCE),'source_blend_sha256':SOURCE_SHA,'legacy_source_mesh_count':66,'source_object_count':sum(len(r['instances']) for r in recipes),'source_object_count_semantics':'semantic source fragments after splitting legacy batched meshes; original 66 mesh objects tracked separately','source_cuboid_count':len(expected),'component_budget':{'limit':50,'planned':len(recipes),'remaining':50-len(recipes)},'structure_frozen_before_fittings':True,'structure_component_ids':[g['component_id'] for g in plan_groups if g['category']=='structure'],'coordinate_contract':coord,'groups':plan_groups,'validation':{'instance_coverage_ok':True,'source_cuboid_coverage_ok':True,'source_cuboid_duplicate_count':0,'duplicate_merge_key_count':0,'naming_violations':[],'interop_ratio':None,'interop_status':'not_applicable_single_standalone_reference_type; no invented room consumers','godot_status':'not_requested_no_Godot_project'}}
assert len(plan['structure_component_ids'])<=9
keys=[json.dumps(g['merge_key'],sort_keys=True) for g in plan_groups];assert len(set(keys))==len(keys)
frozen=time.time();plan['frozen_unix_time']=frozen
(LIB/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2))
print('COMPONENT_PLAN_FROZEN',json.dumps(plan['component_budget']),flush=True)
# Capture baseline positions, UVs, roles and animation at five frames for conservation checks.
frame_probes={}
for f in [1,61,121,181,241]:
 s.frame_set(f);bpy.context.evaluated_depsgraph_get().update()
 frame_probes[f]={o.name:o.matrix_world.copy() for o in source_meshes.values()}
s.frame_set(1)

# New hierarchy. Models are authored once; layout contains only collection-instance empties.
old_collections=list(s.collection.children)
def collection(name,parent):
 co=bpy.data.collections.new(name);parent.children.link(co);return co
masters=collection('01_制作组件_按组件拆分',s.collection)
outputs=collection('02_游戏输出_独立资产包_v008',s.collection)
controls=collection('03_动画控制与坐标契约',s.collection)
env=collection('90_展示环境_灯光相机与动态',s.collection)
fx=collection('91_环境动态_雨丝飘纸体积',env)
lightcol=collection('92_灯光与相机',env)
root=bpy.data.objects.new('ROOM_FRAME',None);controls.objects.link(root);root.matrix_world=ROOM;root['coordinate_contract']=json.dumps(coord,ensure_ascii=False)
for ob in source_objects:
 if ob.name not in source_meshes:
  target=fx if ob.type=='MESH' else lightcol if ob.type in ['LIGHT','CAMERA'] else controls
  target.objects.link(ob)
  for co in list(ob.users_collection):
   if co!=target:co.objects.unlink(ob)
# Keep the original procedural atmosphere and animation outside the static component library.
# Four material roles keep their original color/roughness/emission settings.
used_materials={m for o in source_meshes.values() for m in o.data.materials}
palette_path=ROOT/'assets/art/shared/palette/tower_district_palette.png';palette_path.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/'outputs/tower_district/source/tower_palette.png',palette_path)
for mat in used_materials:
 nt=mat.node_tree
 for tex in [n for n in nt.nodes if n.bl_idname=='ShaderNodeTexImage']:
  image=tex.image
  if image:
   if image.packed_file:image.unpack(method='REMOVE')
   image.filepath=str(palette_path);tex.interpolation='Closest'
  old=tex.inputs['Vector'].links[0].from_socket
  attr=nt.nodes.new('ShaderNodeAttribute');attr.attribute_type='INSTANCER';attr.attribute_name='palette_shift';attr.label='每实例色盘偏移 / no geometry duplication'
  mask=nt.nodes.new('ShaderNodeAttribute');mask.attribute_name='PaletteVariantMask'
  mult=nt.nodes.new('ShaderNodeVectorMath');mult.operation='SCALE';nt.links.new(attr.outputs['Vector'],mult.inputs[0]);nt.links.new(mask.outputs['Fac'],mult.inputs[3])
  plus=nt.nodes.new('ShaderNodeVectorMath');plus.operation='ADD';nt.links.new(old,plus.inputs[0]);nt.links.new(mult.outputs['Vector'],plus.inputs[1]);nt.links.new(plus.outputs['Vector'],tex.inputs['Vector'])
 # Diagnostic role, shared by all components; colorways live on instancers.
 mat['material_role']=mat.name.replace('TD_','')

category_names={'structure':'01_建筑结构','fitting':'02_设施与装置','decoration':'03_宿主装饰与表面','environment':'04_跨设施环境支持'}
mastercats={k:collection(v,masters) for k,v in category_names.items()}
outcats={k:collection(v+'_实例',outputs) for k,v in category_names.items()}
records=[];catalog=[];source_map=defaultdict(list);master_cols=[]
for r,g in zip(recipes,plan_groups):
 slug=r['slug'];cid=r['component_id'];base=r['_data'][0]
 co=collection('Component_'+slug,mastercats[r['category']]);co.instance_offset=(0,0,0);co['component_id']=cid;co['geometry_fingerprint']=base['fingerprint'];master_cols.append(co)
 rt=bpy.data.objects.new('ROOT_'+slug,None);co.objects.link(rt);rt['component_id']=cid
 # Baked vertices in local coordinates; ROOT, meshes and collection offset are all identity/zero.
 for is_emissive,label in [(False,'主体'),(True,'自发光')]:
  indices=[i for i,m in enumerate(base['materials']) if ('Emission' in m.name)==is_emissive]
  if not indices:continue
  orig_v=sorted({j for fi in indices for j in base['faces'][fi]});vmap={j:i for i,j in enumerate(orig_v)}
  me=bpy.data.meshes.new(slug+'_'+label);me.from_pydata([base['verts'][j] for j in orig_v],[],[tuple(vmap[j] for j in base['faces'][fi]) for fi in indices])
  slotmats=[]
  for fi in indices:
   if base['materials'][fi] not in slotmats:slotmats.append(base['materials'][fi])
  for mat in slotmats:me.materials.append(mat)
  me.polygons.foreach_set('material_index',[slotmats.index(base['materials'][fi]) for fi in indices])
  uv=me.uv_layers.new(name='PaletteUV');uv.data.foreach_set('uv',[x for fi in indices for pair in base['uvs'][fi] for x in pair]);uv.active_render=True
  mask=me.attributes.new('PaletteVariantMask','FLOAT','FACE');mask.data.foreach_set('value',[r['_mask'][fi] for fi in indices])
  ob=bpy.data.objects.new(slug+'_'+label,me);co.objects.link(ob);ob.parent=rt;ob['component_id']=cid;ob['geometry_owner']='component_master';ob['source_geometry_preserved']=True
 instcol=collection(slug+'_'+r['name_zh'],outcats[r['category']])
 for idx,d in enumerate(r['_data']):
  ob=bpy.data.objects.new('Instance_'+slug+'_%04d'%(idx+1),None);instcol.objects.link(ob);ob.instance_type='COLLECTION';ob.instance_collection=co;ob['component_id']=cid;ob['palette_shift']=d['palette_shift'];ob['room_owned_geometry']=False
  if d['parent']:
   ob.parent=d['parent'];ob.matrix_parent_inverse=Matrix.Identity(4);ob.matrix_basis=d['local']
  else:ob.parent=root;ob.matrix_parent_inverse=Matrix.Identity(4);ob.matrix_basis=ROOM.inverted()@d['world']
  ob['source_fragments']=json.dumps(r['instances'][idx]['parts'],ensure_ascii=False)
  roomlocal=ROOM.inverted()@d['world'];pos,quat,scale=roomlocal.decompose();eul=quat.to_euler('XYZ')
  rec={'component_id':cid,'instance_id':ob.name,'position_m':list(pos),'rotation_y_deg':math.degrees(eul.z),'rotation_euler_xyz_deg':[math.degrees(x) for x in eul],'scale':list(scale),'source_object':r['instances'][idx]['parts'][0]['object'],'source_fragments':r['instances'][idx]['parts'],'source_world_origin_m':list(d['world'].translation),'matrix_room_local':[list(row) for row in roomlocal],'matrix_parent_local':[list(row) for row in (d['local'] if d['parent'] else ROOM.inverted()@d['world'])],'animation_parent':d['parent'].name if d['parent'] else None,'palette_shift':d['palette_shift'],'historical_uniform_presentation_scale':list(scale) if max(abs(x-1) for x in scale)>1e-6 else None}
  records.append(rec);d['_instance']=ob
  for src,bi in d['source']:source_map[src].append({'cuboid':bi,'instance_id':ob.name,'component_id':cid})
 manifest={k:v for k,v in g.items() if k not in ['source_object_fragments','merge_key']}
 manifest.update({'room_type':'TOWER_DISTRICT_REFERENCE','collection':co.name,'root_object':rt.name,'component_blend':str(LIB/'component_packages'/cid/(slug+'.blend')),'source_room_type_blend':str(SOURCE),'source_room_type_sha256':SOURCE_SHA,'collision_owner':'godot_wrapper_if_future_import','collision_status':'not_authored_this_Blender_structure_task','palette_uv_layer':'PaletteUV','shared_palette_path':str(palette_path),'asset_ledger':None,'asset_ledger_status':'standalone_asset_not_registered_in_ShellStorm2','geometry_source_created_after_plan_frozen':True,'supports_palette_shift_attribute':any(r['_mask']),'asset_id':cid,'authoritative_library':str(LIB/'tower_district_components_v008.blend'),'component_blend_role':'versioned_standalone_snapshot_of_authoritative_master','component_family':r['component_family'],'root_transform_identity':True,'mesh_transform_identity':True,'collection_instance_offset':[0,0,0],'standalone_scene':'Component_'+slug})
 pack=LIB/'component_packages'/cid;pack.mkdir(parents=True,exist_ok=True);(pack/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
 catalog.append(manifest)
# No original static meshes remain in the layout; their source file is preserved byte-for-byte.
for o in source_meshes.values():bpy.data.objects.remove(o,do_unlink=True)
for co in old_collections:
 if co.name in bpy.data.collections:bpy.data.collections.remove(co)
# Exclude authoring masters from direct drawing; collection instances still render them.
bpy.context.view_layer.layer_collection.children[masters.name].exclude=True
s.name='TD_组件实例街区_v008';s['Version']='v008';s['ComponentLibrary']=str(LIB);s['room_owned_geometry']=False
s['Readme']=str(LIB/'README.md');s['Source_SHA256']=SOURCE_SHA
s.frame_set(1);bpy.context.evaluated_depsgraph_get().update()
# Full geometry conservation across animation states, not merely object-count agreement.
checks=[];max_error=0.0
for f in [1,61,121,181,241]:
 s.frame_set(f);bpy.context.evaluated_depsgraph_get().update();frame_max=0.0
 for r in recipes:
  base=r['_data'][0]
  for d,item in zip(r['_data'],r['instances']):
   ins=d['_instance'];new_world=ins.matrix_world
   # Every original vertex can be compared via the normalized reference part transform.
   srcmatrix=frame_probes[f][item['parts'][0]['object']]
   anchorworld=srcmatrix@Matrix.Translation(d['anchor'])
   for p in [Vector((0,0,0)),*base['verts'][::max(1,len(base['verts'])//24)]]:
    err=(new_world@p-anchorworld@p).length;frame_max=max(frame_max,err)
 max_error=max(max_error,frame_max);checks.append({'frame':f,'max_vertex_position_error_m':frame_max})
assert max_error<1e-4,max_error
s.frame_set(1)
# Additional hierarchy declarations needed for exact scene playback of dynamic props.
s.view_layers[0].update()
rigs=[]
for o in controls.objects:
 if o==root:continue
 rigs.append({'name':o.name,'parent':o.parent.name if o.parent else None,'matrix_parent_local':[list(row) for row in o.matrix_local],'rotation_mode':o.rotation_mode,'drivers':[{'data_path':f.data_path,'array_index':f.array_index,'expression':f.driver.expression} for f in o.animation_data.drivers] if o.animation_data else []})
instance_doc={'schema':'shellstorm2.battle.component_instances','schema_version':1,'library':'v008','source_room_type_blend':str(SOURCE),'source_room_type_sha256':SOURCE_SHA,'coordinate_contract':coord,'instances':records,'animation_rigs':rigs,'validation':{'source_object_count':len(records),'source_object_count_semantics':'semantic source fragments; original batched mesh count = 66','legacy_source_mesh_count':66,'instance_count':len(records),'coverage_ok':True,'source_cuboid_coverage_ok':True,'source_cuboid_count':len(expected),'position_max_error_m':max_error,'animation_frame_checks':checks,'historical_presentation_scales_retained':True,'godot_replay':'not_requested'}}
(LIB/'component_instances.json').write_text(json.dumps(instance_doc,ensure_ascii=False,indent=2))
(LIB/'component_catalog.json').write_text(json.dumps({'schema':'tower_district.component_catalog','library':'v008','components':catalog},ensure_ascii=False,indent=2))
(BASE/'qa/source_to_component_map.json').write_text(json.dumps(source_map,ensure_ascii=False))
print('STRUCTURE_AND_ANIMATION_CONSERVATION_OK',max_error,flush=True)
# Independent component files are saved in an isolated Blender pass to avoid scene-copy bugs.
# A separate gallery uses instances as well, so editing the master updates every view.
gallery=bpy.data.scenes.new('TD_组件母版画廊_v008');gallery.world=s.world;gallery.render.engine='BLENDER_EEVEE';gallery.render.resolution_x=1600;gallery.render.resolution_y=1000
cg=bpy.data.collections.new('组件母版画廊_实例');gallery.collection.children.link(cg)
x=0;y=0;rowdepth=0
for co,meta in zip(master_cols,catalog):
 dx,dy,dz=meta['bounds_size_m']
 if x+dx>130:x=0;y+=rowdepth+5;rowdepth=0
 ob=bpy.data.objects.new('Gallery_'+meta['slug'],None);cg.objects.link(ob);ob.instance_type='COLLECTION';ob.instance_collection=co;ob.location=(x+dx/2,y+dy/2,0);ob['palette_shift']=[0.,0.,0.];x+=dx+5;rowdepth=max(rowdepth,dy)
# Diagnostic gallery camera.
camd=bpy.data.cameras.new('组件画廊相机');cam=bpy.data.objects.new('组件画廊相机',camd);gallery.collection.objects.link(cam);cam.location=(65,-80,180);t=Vector((65,(y+rowdepth)/2,0));cam.rotation_euler=(t-cam.location).to_track_quat('-Z','Y').to_euler();camd.type='ORTHO';camd.ortho_scale=max(160,y+rowdepth);camd.clip_end=2000;gallery.camera=cam
# Source signature check is repeated after migration and independent package writes.
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==SOURCE_SHA
s.frame_set(1);s.eevee.shadow_pool_size='1024';s.eevee.shadow_resolution_scale=.5;s.render.filepath=str(BASE/'qa/after_reorganization.png')
bpy.context.window.scene=s
for a in bpy.context.screen.areas:
 if a.type=='VIEW_3D':a.spaces.active.shading.type='MATERIAL';a.spaces.active.region_3d.view_perspective='CAMERA';a.spaces.active.overlay.show_overlays=False
s.render.resolution_percentage=100
OUT=LIB/'tower_district_components_v008.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT))
summary={'library':str(OUT),'component_count':len(catalog),'instance_count':len(records),'legacy_static_mesh_count':66,'source_cuboids_covered':len(expected),'max_position_error_m':max_error,'source_sha256_unchanged':True,'four_surface_roles':sorted(m.name for m in used_materials),'render_preserved_pending_visual_review':True,'godot_verification':'not_requested_no_Godot_project','interop_gate':'not_applicable_single_standalone_reference_type'}
(BASE/'qa/migration_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2))
lines=['TOWER DISTRICT v008','├─ 01_制作组件_按组件拆分（母版；主视图排除直接绘制）']
for meta in catalog:lines.append('│  ├─ '+meta['slug']+' / '+meta['name_zh']+' / '+str(meta['instance_count'])+' 实例')
lines+=['├─ 02_游戏输出_独立资产包_v008（只有集合实例）','├─ 03_动画控制与坐标契约','└─ 90_展示环境_灯光相机与动态']
(LIB/'component_tree.txt').write_text('\n'.join(lines))
print('MIGRATION_COMPLETE '+json.dumps(summary,ensure_ascii=False),flush=True)
