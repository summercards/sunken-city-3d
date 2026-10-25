# -*- coding: utf-8 -*-
"""Separate the existing winch salvage platform into an independent facility."""
import bpy,bmesh,json,hashlib,os
from pathlib import Path
from collections import defaultdict
import numpy as np
from mathutils import Vector,Matrix
R=Path(__file__).resolve().parents[3];OLD=R/'art_source/scenes/runtime_building_reference/v002';D=OLD.parent/'v003';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'runtime_building_reference_v0.3'
CAT=json.loads((OLD/'catalog.json').read_text());C=np.array([[1,0,0],[0,0,-1],[0,1,0]],float)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
def measure(objects):
 area=0;tri=0;points=[]
 for o in objects:
  if o.type!='MESH':continue
  o.data.calc_loop_triangles();tri+=len(o.data.loop_triangles)
  for p in o.data.polygons:
   v=[o.matrix_world@o.data.vertices[i].co for i in p.vertices];area+=sum((v[j]-v[0]).cross(v[j+1]-v[0]).length*.5 for j in range(1,len(v)-1))
  points.extend(tuple(o.matrix_world@v.co) for v in o.data.vertices)
 a=np.array(points);return dict(area=area,triangles=tri,bounds=dict(min=a.min(0).tolist(),max=a.max(0).tolist()))
def init():
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0;bpy.context.scene.unit_settings.system='METRIC'
def setup_ui(bounds):
 a=Vector(bounds['min']);b=Vector(bounds['max'])
 for screen in bpy.data.screens:
  for ar in screen.areas:
   if ar.type=='VIEW_3D':ar.spaces.active.region_3d.view_location=(a+b)*.5;ar.spaces.active.region_3d.view_distance=max(b-a)*1.7;ar.spaces.active.clip_end=3000;ar.spaces.active.shading.type='MATERIAL'
def save(row):
 sc=bpy.context.scene;sc.name=row['name'];sc['资产编号']=row['asset_id'];sc['资产英文名']=row['asset_key'];sc['账本中文名']=row['name'];sc['版本']='0.3'
 for t in list(bpy.data.texts):bpy.data.texts.remove(t)
 bpy.data.texts.new('资产说明').write(json.dumps(row,ensure_ascii=False,indent=2));bpy.ops.file.pack_all()
 p=R/row['source'];p.parent.mkdir(parents=True,exist_ok=True);bpy.ops.wm.save_as_mainfile(filepath=str(p),compress=True);row['source_sha256']=sha(p)
 row['manifest']=str((p.parent/(row['asset_key']+'_manifest.json')).relative_to(R));row['asset_ledger']='assets/registry/ledgers/scenes.json#'+row['asset_id'];write(R/row['manifest'],row)
def subset(original,selected,wanted):
 bm=bmesh.new();bm.from_mesh(original.data);bm.verts.ensure_lookup_table();bm.faces.ensure_lookup_table()
 remove=[v for v in bm.verts if (v.index in selected)!=wanted]
 bmesh.ops.delete(bm,geom=remove,context='VERTS')
 if not bm.verts:bm.free();return None
 me=original.data.copy();bm.to_mesh(me);bm.free();me.update();copy=original.copy();copy.data=me;copy.parent=None;copy.matrix_world=original.matrix_world.copy();return copy
assert not (D/'catalog.json').exists(),'Existing version: do not overwrite'
D.mkdir(parents=True,exist_ok=True);W.mkdir(parents=True,exist_ok=True)
source=next(e for e in CAT['items'] if e['asset_key']=='solar_cabin_harbor_surroundings');assert sha(R/source['source'])==source['source_sha256']
bpy.ops.wm.open_mainfile(filepath=str(R/source['source']));bpy.context.view_layer.update()
objects=[o for o in bpy.context.scene.objects if o.type=='MESH'];before=measure(objects);origin=np.array(source['origin_godot'])@C.T
salvage_origin=np.array([-12.,0.,13.])@C.T;selection={};island_rows=[]
for ob in objects:
 n=len(ob.data.vertices);parents=list(range(n))
 def find(i):
  while parents[i]!=i:parents[i]=parents[parents[i]];i=parents[i]
  return i
 def union(a,b):
  a,b=find(a),find(b)
  if a!=b:parents[b]=a
 # glTF duplicates vertices at UV/normal seams; weld only the ownership graph.
 positions={}
 for v in ob.data.vertices:
  key=tuple(round(x,5) for x in v.co)
  if key in positions:union(v.index,positions[key])
  else:positions[key]=v.index
 for edge in ob.data.edges:union(*edge.vertices)
 components=defaultdict(list)
 for i in range(n):components[find(i)].append(i)
 chosen=set()
 for vertices in components.values():
  p=np.array([tuple(ob.matrix_world@ob.data.vertices[i].co) for i in vertices])+origin
  center=(p.min(0)+p.max(0))*.5;x=center[0];gz=-center[1]
  # Isolated platform is centred at (-12,13), with a 6.5 x 5.5 m deck.
  # Margin includes the complete winch arms, support poles and nearby greenery.
  owned=(-16.7<=x<=-7.1 and 9.0<=gz<=17.2)
  if owned:chosen.update(vertices)
  island_rows.append(dict(object=ob.name,vertices=len(vertices),owner='salvage_station' if owned else 'solar_cabin',center_blender_world=center.tolist()))
 selection[ob.name]=chosen
assert sum(len(v) for v in selection.values())>1000
parts={}
for wanted,key,cn,aid in [
 (False,'solar_cabin_harbor_surroundings','太阳能木屋',source['asset_id']),
 (True,'salvage_station','绞盘打捞台','SEA-REF-FACILITY-SALVAGE-STATION')]:
 parent=bpy.data.collections.new('拆分_'+key);bpy.context.scene.collection.children.link(parent)
 for region in ['海上区域','海下基座']:
  col=bpy.data.collections.new('拆分_'+cn+'-'+region);parent.children.link(col)
  for i,ob in enumerate(objects):
   if ob['区域']!=region:continue
   copy=subset(ob,selection[ob.name],wanted)
   if copy:
    copy.name=cn+'-'+region+'-'+str(i+1).zfill(2);copy['资产编号']=aid;copy['asset_key']=key;copy['区域']=region
    if wanted:copy.matrix_world=Matrix.Translation(Vector(origin-salvage_origin))@copy.matrix_world
    col.objects.link(copy)
 parts[key]=parent
after_remaining=measure(list(parts['solar_cabin_harbor_surroundings'].all_objects));after_salvage=measure(list(parts['salvage_station'].all_objects))
area_error=abs(after_remaining['area']+after_salvage['area']-before['area'])/max(before['area'],1)
assert area_error<1e-6 and after_remaining['triangles']+after_salvage['triangles']==before['triangles']
# Save the two independent source packages from one verified partition.
changed=[];staged=W/'partition_staging.blend';bpy.ops.wm.save_as_mainfile(filepath=str(staged),compress=True)
for key,cn in [('solar_cabin_harbor_surroundings','太阳能木屋'),('salvage_station','绞盘打捞台')]:
 bpy.ops.wm.open_mainfile(filepath=str(staged));bpy.context.preferences.filepaths.save_version=0
 parent=bpy.data.collections['拆分_'+key]
 keep=set(parent.all_objects)
 for ob in list(bpy.context.scene.objects):
  if ob not in keep:bpy.data.objects.remove(ob,do_unlink=True)
 for col in list(bpy.context.scene.collection.children):
  if col!=parent:bpy.data.collections.remove(col)
 for col in list(bpy.data.collections):
  if col!=parent and col not in list(parent.children):bpy.data.collections.remove(col)
 parent.name=cn if key=='salvage_station' else '太阳能木屋-港湾周边'
 for col in parent.children:col.name=col.name.removeprefix('拆分_')
 if key=='salvage_station':
  row=dict(asset_id='SEA-REF-FACILITY-SALVAGE-STATION',asset_key=key,key=key,name=cn,facility_key=key,facility_name=cn,category='playable_facility_assembly',scope_label='海面可玩区·独立设施',origin_godot=[-12,0,13],runtime_source=source['runtime_source'],runtime_scene=source['runtime_scene'],runtime_node=source['runtime_node'],runtime_landing_id='salvage',boundary_status='whole_connected_island_partition_from_runtime_unit')
 else:row=dict(source)
 row.update(version='0.3',source=str((D/('facilities/salvage_station/salvage_station_v0.3.blend' if key=='salvage_station' else 'playable/solar_cabin/solar_cabin_harbor_surroundings/solar_cabin_harbor_surroundings_v0.3.blend')).relative_to(R)),collection=parent.name,region_collections={r:cn+'-'+r for r in ['海上区域','海下基座']},stage='runtime_reference_verified',runtime_status='reference_only_no_replacement',split_from_asset=source['asset_id'])
 row['organized_metrics']=measure(list(bpy.context.scene.objects));setup_ui(row['organized_metrics']['bounds']);save(row);changed.append(row)
 print('SPLIT_SAVED',row['name'],flush=True)
remaining,salvage=changed
def instance(col,row,source_collection,location,name):
 with bpy.data.libraries.load(str(R/row['source']),link=True) as (a,b):
  assert source_collection in a.collections,(row['asset_key'],source_collection)
  b.collections=[source_collection]
 ob=bpy.data.objects.new(name,None);col.objects.link(ob);ob.instance_type='COLLECTION';ob.instance_collection=b.collections[0];ob.location=location;ob['资产编号']=row['asset_id'];ob['asset_key']=row['asset_key']
solar_old=next(e for e in CAT['facilities'] if e['asset_key']=='solar_cabin');solar=dict(solar_old);solar.update(version='0.3',source=str((D/'facilities/solar_cabin/solar_cabin_v0.3.blend').relative_to(R)))
init();parent=bpy.data.collections.new('太阳能木屋');bpy.context.scene.collection.children.link(parent)
for region in ['海上区域','海下基座']:
 col=bpy.data.collections.new('太阳能木屋-'+region);parent.children.link(col)
 for row in CAT['items']:
  if row.get('facility_key')!='solar_cabin':continue
  if row['asset_key']==remaining['asset_key']:row=remaining
  instance(col,row,row['region_collections'][region],np.array(row['origin_godot'])@C.T,row['name']+'-'+region)
setup_ui(dict(min=[-20,-20,-31],max=[20,10,12]));save(solar);changed.append(solar)
facilities=[solar if e['asset_key']=='solar_cabin' else e for e in CAT['facilities']]+[salvage]
init()
for row in facilities:
 col=bpy.data.collections.new(row['name']);bpy.context.scene.collection.children.link(col)
 for region in ['海上区域','海下基座']:
  sub=bpy.data.collections.new(row['name']+'-'+region);col.children.link(sub)
  location=np.array(row['origin_godot'])@C.T if row['asset_key']=='salvage_station' else [0,0,0]
  instance(sub,row,row['region_collections'][region],location,row['name']+'-'+region)
overview=dict(next(e for e in CAT['overviews'] if e['asset_key']=='sea_playable_facilities'));overview.update(version='0.3',source=str((D/'sea_playable_facilities_v0.3.blend').relative_to(R)))
setup_ui(dict(min=[-40,-20,-31],max=[45,45,12]));save(overview);changed.append(overview)
items=[remaining if e['asset_key']==remaining['asset_key'] else e for e in CAT['items']]
overviews=[overview if e['asset_key']==overview['asset_key'] else e for e in CAT['overviews']]
for e in items+facilities+overviews:e['relative_blend']=os.path.relpath(R/e['source'],D)
write(D/'catalog.json',dict(version='0.3',items=items,facilities=facilities,overviews=overviews,input_hashes=CAT['input_hashes'],previous_version='v002',change='绞盘打捞台从太阳能木屋拆分为独立设施，其余源复用 v0.2'))
write(W/'split_checks.json',dict(before=before,remaining=after_remaining,salvage=after_salvage,area_relative_error=area_error,changed_assets=changed,island_assignments=island_rows,original_source_preserved=sha(R/source['source'])==source['source_sha256']))
print('SPLIT_COMPLETE',len(facilities),'facilities',flush=True)
