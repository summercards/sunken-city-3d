# -*- coding: utf-8 -*-
"""Organize existing references by facility and above/below-water region."""
import bpy,bmesh,json,hashlib,os,re,math
import numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
R=Path(__file__).resolve().parents[3];OLD=R/'art_source/scenes/runtime_building_reference/v001';D=OLD.parent/'v002';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'runtime_building_reference_v0.2'
CAT=json.loads((OLD/'catalog.json').read_text());C=np.array([[1,0,0],[0,0,-1],[0,1,0]],float)
FACILITIES={
 'zone1_home_harbor':('solar_cabin','太阳能木屋',{'detail':('harbor_surroundings','港湾周边'),'unit_01':('front_deck','前侧平台'),'unit_02':('rear_tower','后侧楼体'),'unit_03':('core','木屋主体')}),
 'zone2_yokohama_station':('yokohama_station','横滨沉没铁道',{'detail':('connections','周边连接设施'),'unit_01':('platform','站台结构'),'unit_02':('east_facilities','东侧设施'),'unit_03':('west_facilities','西侧设施')}),
 'zone3_arc_farm':('arc_rooftop_farm','圆弧屋顶农场',{'detail':('outer_structure','外围结构'),'unit_01':('core','农场主体')}),
 'zone4_far_shore':('far_shore_settlement','远海街町',{'detail':('water_marker','水面标记'),'unit_01':('main_building','主楼结构'),'unit_02':('annex','附属设施'),'unit_03':('rooftop_facilities','屋顶设施'),'unit_04':('side_wall','侧墙结构')}),
 'zone5_aqua_platform':('aquaculture_platform','浅水养殖台',{'detail':('outer_supports','外围支撑'),'unit_01':('core','养殖台主体')})}
BG_NAMES=[('balcony_residence','阳台住宅楼'),('broken_roof_frame','破顶围墙楼'),('balcony_frame_a','阳台框架楼甲型'),('broken_slab_frame','破损楼板楼'),('stair_frame','阶梯框架楼'),('balcony_frame_b','阳台框架楼乙型')]
def write(p,x):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def init():
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0;bpy.context.scene.unit_settings.system='METRIC'
def measure(objects):
 area=0;tri=0;bounds=[];edges=0
 for o in objects:
  if o.type!='MESH':continue
  me=o.data;me.calc_loop_triangles();tri+=len(me.loop_triangles);edges+=len(me.edges)
  for p in me.polygons:
   vv=[o.matrix_world@me.vertices[i].co for i in p.vertices]
   area+=sum((vv[j]-vv[0]).cross(vv[j+1]-vv[0]).length*.5 for j in range(1,len(vv)-1))
  if me.vertices:
   a=np.array([tuple(o.matrix_world@v.co) for v in me.vertices]);bounds.extend([a.min(0),a.max(0)])
 if not bounds:return dict(area=0,triangles=0,edges=0,bounds=None)
 a=np.array(bounds);return dict(area=area,triangles=tri,edges=edges,bounds=dict(min=a.min(0).tolist(),max=a.max(0).tolist()))
def split(ob,z,upper):
 bm=bmesh.new();bm.from_mesh(ob.data);inv=ob.matrix_world.inverted();p=inv@Vector((0,0,z));n=ob.matrix_world.to_3x3().transposed()@Vector((0,0,1));n.normalize()
 edge_layer=bm.edges.layers.int.new('source_loose_edge')
 for e in bm.edges:e[edge_layer]=int(not e.link_faces)
 bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-7,plane_co=p,plane_no=n,clear_inner=False,clear_outer=False)
 def wrong(h):return h<z-1e-7 if upper else h>=z-1e-7
 remove=[f for f in bm.faces if wrong((ob.matrix_world@f.calc_center_median()).z)]
 if remove:bmesh.ops.delete(bm,geom=remove,context='FACES_ONLY')
 isolated=[e for e in bm.edges if not e.link_faces and (not e[edge_layer] or wrong((ob.matrix_world@((e.verts[0].co+e.verts[1].co)*.5)).z))]
 if isolated:bmesh.ops.delete(bm,geom=isolated,context='EDGES_FACES')
 isolated=[v for v in bm.verts if not v.link_edges and wrong((ob.matrix_world@v.co).z)]
 if isolated:bmesh.ops.delete(bm,geom=isolated,context='VERTS')
 if not bm.verts:bm.free();return None
 me=ob.data.copy();bm.to_mesh(me);bm.free();me.update();copy=ob.copy();copy.data=me;copy.parent=None;copy.matrix_world=ob.matrix_world.copy();return copy
def ui(bounds):
 if not bounds:return
 a=Vector(bounds['min']);b=Vector(bounds['max'])
 for screen in bpy.data.screens:
  for ar in screen.areas:
   if ar.type=='VIEW_3D':ar.spaces.active.region_3d.view_location=(a+b)*.5;ar.spaces.active.region_3d.view_distance=max(b-a)*1.7;ar.spaces.active.clip_end=3000;ar.spaces.active.shading.type='MATERIAL'
def save(row):
 p=D/row['relative_blend'];p.parent.mkdir(parents=True,exist_ok=True);bpy.context.scene.name=row['name'];bpy.context.scene['资产编号']=row['asset_id'];bpy.context.scene['资产英文名']=row['asset_key'];bpy.context.scene['账本中文名']=row['name'];bpy.context.scene['版本']='0.2'
 txt=bpy.data.texts.new('资产说明');txt.write(json.dumps(row,ensure_ascii=False,indent=2));bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(p),compress=True)
 row['source']=str(p.relative_to(R));row['source_sha256']=sha(p);row['asset_ledger']='assets/registry/ledgers/scenes.json#'+row['asset_id'];write(p.parent/'asset_manifest.json',row)
assert not (D/'catalog.json').exists(),'Already organized; use a new version'
D.mkdir(parents=True,exist_ok=True);W.mkdir(parents=True,exist_ok=True)
rows=[];checks=[]
for old in CAT['items']:
 row=dict(old);row.update(version='0.2',previous_source=old['source'],previous_source_sha256=old['source_sha256'])
 bpy.ops.wm.open_mainfile(filepath=str(R/old['source']));bpy.context.preferences.filepaths.save_version=0;bpy.context.view_layer.update()
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];before=measure(meshes)
 if old['category']=='playable_surface':
  zone,unit=old['key'].split('__');facility,cn,parts=FACILITIES[zone];suffix,label=parts[unit];key=facility+'_'+suffix;display=cn+'-'+label;row.update(facility_key=facility,facility_name=cn,part_name=label)
 elif old['category']=='background_building_component':
  suffix,cn=BG_NAMES[old['source_type']];facility='background_'+suffix;key=facility;display='远景-'+cn;row.update(facility_key=facility,facility_name=cn)
 else:
  facility='background_shared_parts';cn='远景公共构件';num=int(old['key'].split('_')[-1]);key=f'background_shared_part_{num:03d}';display=f'远景公共构件-{num:03d}';row.update(facility_key=facility,facility_name=cn)
 row.update(legacy_key=old['key'],key=key,asset_key=key,name=display,relative_blend=f'{"playable" if old["category"]=="playable_surface" else "background_components"}/{facility}/{key}/{key}_v0.2.blend')
 parent=bpy.data.collections.new(display);bpy.context.scene.collection.children.link(parent)
 if old['category']!='background_detail_component':
  collections=[]
  for upper,region in [(True,'海上区域'),(False,'海下基座')]:
   col=bpy.data.collections.new(cn+'-'+region);parent.children.link(col);collections.append(col)
   for i,ob in enumerate(meshes):
    copy=split(ob,1.12,upper)
    if copy:
     copy.name=f'{display}-{region}-{i+1:02d}';copy.data.name=key+('_surface_' if upper else '_submerged_')+str(i+1);copy['asset_key']=key;copy['资产编号']=row['asset_id'];copy['区域']=region;col.objects.link(copy)
   col['asset_key']=key;col['区域']=region
  row['region_collections']={'海上区域':collections[0].name,'海下基座':collections[1].name};row['split_world_height_godot']=1.12;row['split_method']='plane_bisect_no_caps_preserve_combined_surface'
 else:
  col=bpy.data.collections.new(display+'-组件母版');parent.children.link(col)
  for ob in meshes:
   copy=ob.copy();copy.data=ob.data.copy();copy.parent=None;copy.matrix_world=ob.matrix_world.copy();copy.name=display+'-几何';col.objects.link(copy)
  row['placement_region_policy']='归属随实例高度变化；公共母版不绑定水面高度'
 for ob in list(bpy.context.scene.objects):
  if ob in meshes or ob.type!='MESH':bpy.data.objects.remove(ob,do_unlink=True)
 for col in list(bpy.data.collections):
  if col!=parent and col not in list(parent.children):bpy.data.collections.remove(col)
 bpy.context.view_layer.update();after=measure(list(bpy.context.scene.objects));print('BOUNDS',key,before['bounds'],after['bounds'],flush=True);err=abs(before['area']-after['area'])/max(before['area'],1e-12)
 assert err<1e-5,(key,'area',err)
 if before['bounds']:
  assert np.max(abs(np.array(before['bounds']['min'])-after['bounds']['min']))<1e-4
  assert np.max(abs(np.array(before['bounds']['max'])-after['bounds']['max']))<1e-4
 row['collection']=parent.name;row['organized_metrics']=after;checks.append(dict(asset_id=row['asset_id'],asset_key=key,area_relative_error=err,before=before,after=after));ui(after['bounds']);save(row);rows.append(row)
 print('ORGANIZED',display,flush=True)

def instance(col,row,source_collection,location,name):
 with bpy.data.libraries.load(str(R/row['source']),link=True) as (a,b):b.collections=[source_collection]
 ob=bpy.data.objects.new(name,None);col.objects.link(ob);ob.instance_type='COLLECTION';ob.instance_collection=b.collections[0];ob.location=location;ob['资产编号']=row['asset_id'];ob['asset_key']=row['asset_key'];return ob
facility_rows=[]
for zone,(facility,cn,_) in FACILITIES.items():
 init();parent=bpy.data.collections.new(cn);bpy.context.scene.collection.children.link(parent)
 for region in ['海上区域','海下基座']:
  col=bpy.data.collections.new(cn+'-'+region);parent.children.link(col)
  for row in rows:
   if row['category']!='playable_surface' or row['facility_key']!=facility:continue
   instance(col,row,row['region_collections'][region],np.array(row['origin_godot'])@C.T,row['name']+'-'+region)
 row=dict(asset_id='SEA-REF-FACILITY-'+facility.upper().replace('_','-'),asset_key=facility,key=facility,name=cn,facility_name=cn,facility_key=facility,version='0.2',category='playable_facility_assembly',scope_label='海面可玩区·设施总成',runtime_scene=f'godot/scenes/zones/{zone}.tscn',runtime_source=f'godot/scenes/zones/{zone}.tscn',relative_blend=f'facilities/{facility}/{facility}_v0.2.blend',collection=parent.name,region_collections={'海上区域':cn+'-海上区域','海下基座':cn+'-海下基座'})
 ui(dict(min=[-40,-20,-30],max=[45,45,12]));save(row);facility_rows.append(row)
init()
for row in facility_rows:
 col=bpy.data.collections.new(row['name']);bpy.context.scene.collection.children.link(col)
 for region in ['海上区域','海下基座']:
  sub=bpy.data.collections.new(row['name']+'-'+region);col.children.link(sub);instance(sub,row,row['region_collections'][region],[0,0,0],row['name']+'-'+region)
overall=dict(asset_id='SEA-REF-01-PLAYABLE-OVERVIEW',asset_key='sea_playable_facilities',key='sea_playable_facilities',name='海面可玩设施总览',version='0.2',category='playable_reference_assembly',scope_label='海面可玩区',relative_blend='sea_playable_facilities_v0.2.blend',runtime_source='godot/scenes/main.tscn',runtime_scene='godot/scenes/main.tscn')
ui(dict(min=[-40,-20,-30],max=[45,45,12]));save(overall)
init()
for i,row in enumerate(r for r in rows if r['category']=='background_building_component'):
 col=bpy.data.collections.new(row['name']);bpy.context.scene.collection.children.link(col)
 for region in ['海上区域','海下基座']:
  sub=bpy.data.collections.new(row['facility_name']+'-'+region);col.children.link(sub);instance(sub,row,row['region_collections'][region],[i%3*14,i//3*20,0],row['facility_name']+'-'+region)
background=dict(asset_id='SEA-REF-01-BACKGROUND-BUILDING-LIBRARY',asset_key='background_building_components',key='background_building_components',name='远景建筑组件总览',version='0.2',category='background_reference_assembly',scope_label='远景背景',relative_blend='background_building_components_v0.2.blend',runtime_source='godot/scenes/world/environment.tscn',runtime_scene='godot/scenes/world/environment.tscn')
ui(dict(min=[-5,-5,-25],max=[35,25,15]));save(background)
write(D/'catalog.json',dict(version='0.2',items=rows,facilities=facility_rows,overviews=[overall,background],input_hashes=CAT['input_hashes'],previous_version='v001',naming='中文账本名、英文asset_key和文件名；Blender按设施名-海上区域/海下基座管理'))
write(W/'organization_checks.json',dict(geometry_checks=checks,source_files_preserved=all(sha(R/r['source'])==r['source_sha256'] for r in CAT['items']),independent_files=len(rows),facility_assemblies=len(facility_rows)))
print('ORGANIZE_COMPLETE',len(rows),len(facility_rows),flush=True)
