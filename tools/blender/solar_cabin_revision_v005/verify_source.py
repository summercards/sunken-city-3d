"""Create standalone packages, reopen every file, verify source invariants and render views.
Blender source-only check; game execution requires scripts/run_verification.py.
"""
import bpy,json,hashlib,math,os,sys
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v005';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'sunny_bloom_retreat_v005'
source=D/'sunny_bloom_retreat.blend';pal=R/'art_source/shared/palettes/sea_cozy_8x8_512.png'
plan=json.loads((D/'component_plan.json').read_text());cat=json.loads((D/'catalog.json').read_text());entries=cat['components'];layout=json.loads((D/'component_instances.json').read_text())['instances'];errors=[];uv_faces=0
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def require(flag,msg):
 if not flag:errors.append(msg)
def identity(matrix):return max(abs(matrix[i][j]-(1 if i==j else 0)) for i in range(4) for j in range(4))<1e-6

def inspect(item,count=False):
 global uv_faces
 col=bpy.data.collections.get(item['collection']);require(col is not None,item['key']+' collection absent')
 if not col:return
 require(tuple(col.instance_offset)==(0,0,0),item['key']+' nonzero collection offset')
 root=bpy.data.objects.get(item['root']);require(root is not None and identity(root.matrix_local),item['key']+' root transform')
 meshes=[o for o in col.objects if o.type=='MESH'];require(bool(meshes),item['key']+' empty');coords=[];tris=0
 for o in meshes:
  require(o.parent==root and identity(o.matrix_local),o.name+' mesh transform/parent');coords.extend(v.co for v in o.data.vertices);o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles)
  uv=o.data.uv_layers.get('PaletteUV');require(uv is not None,o.name+' missing PaletteUV')
  if not uv:continue
  require(len(o.data.uv_layers)==1 and o.data.uv_layers.active==uv and uv.active_render,o.name+' active UV')
  for f in o.data.polygons:
   points=[uv.data[l].uv for l in f.loop_indices];area=abs(sum(a.x*b.y-b.x*a.y for a,b in zip(points,points[1:]+points[:1])))/2
   require(area>1e-9,o.name+' UV zero area '+str(f.index));require(len({(int(v.x*8),int(v.y*8)) for v in points})==1,o.name+' UV crosses cells')
   require(all(.125-1e-5<=(v[i]*8)%1<=.875+1e-5 for v in points for i in [0,1]),o.name+' UV safety margin')
   if count:uv_faces+=1
  for mat in o.data.materials:
   require(mat.name in {'SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission'},o.name+' role '+mat.name)
   if mat.name=='SEA_Emission':require('emissive' in o.name,o.name+' luminous geometry not separate')
   nodes=mat.node_tree.nodes;tx=[n for n in nodes if n.type=='TEX_IMAGE'];require(len(tx)==1,mat.name+' image nodes')
   for n in tx:
    require(n.interpolation=='Closest' and n.image.packed_file is None,mat.name+' filtering/packed');require(Path(bpy.path.abspath(n.image.filepath)).resolve()==pal.resolve(),mat.name+' wrong palette path');require(bool(n.inputs['Vector'].links) and n.inputs['Vector'].links[0].from_node.type=='UVMAP' and n.inputs['Vector'].links[0].from_node.uv_map=='PaletteUV',mat.name+' UV input')
 if coords:
  lo=[min(v[i] for v in coords) for i in range(3)];hi=[max(v[i] for v in coords) for i in range(3)];require(abs(lo[2])<1e-5 and abs(lo[0]+hi[0])<1e-5 and abs(lo[1]+hi[1])<1e-5,item['key']+' bottom center');require(all(abs(hi[i]-lo[i]-item['bounds_size'][i])<1e-5 for i in range(3)),item['key']+' bounds mismatch')
 require(tris<=item['triangle_budget'],item['key']+' component triangle budget '+str(tris))
 item['triangles']=tris

from mathutils import Matrix
W=R.parent/'sea-work/solar_cabin_revision_v005'
bpy.ops.wm.open_mainfile(filepath=str(source));bpy.context.preferences.filepaths.save_version=0
for e in entries:inspect(e,True)
scene=bpy.context.scene;actual=[o for o in scene.objects if o.instance_type=='COLLECTION'];require(len(actual)==len(layout),'instance count')
keys={e['asset_id']:e['key'] for e in entries};instances={k:[o for o in actual if keys[o.instance_collection.name]==k] for k in keys.values()}
require(not {'foundation','pier','vine','palm','deck_tile'}&set(instances),'removed components present')
require(len(instances['platform_board'])==6 and len(instances['dock_board'])==8,'full transverse boards')
require('03 前方可行动平台-酒红' in bpy.data.collections and '04 栈桥-暖木' in bpy.data.collections,'separate platform/bridge')
def bounds(o):
 vs=[o.matrix_world@v.co for m in o.instance_collection.objects if m.type=='MESH' for v in m.data.vertices];return ([min(v[i] for v in vs) for i in range(3)],[max(v[i] for v in vs) for i in range(3)])
hlo,hhi=bounds(instances['house'][0]);require(abs(hhi[0]-hlo[0]-7.5)<.001,'house enlarged 50 percent');nlo,nhi=bounds(instances['narrow_window'][0]);require(nhi[0]-nlo[0]>1.5,'front window wide')
for o in instances['platform_board']+instances['dock_board']+[o for o in instances['concrete_slab'] if o.location.z<1]:require(abs(bounds(o)[1][2]-.68)<.0001,'continuous deck datum '+o.name)
# Ground apron below the solar doorway must have no furniture or potted plants.
for o in actual:
 if o.get('module') in ['front_platform','bridge'] and keys[o.instance_collection.name] not in {'platform_board','dock_board','bollard','bridge_rope','hanging_tire'}:
  lo,hi=bounds(o);require(not (lo[0]<-.72 and hi[0]>-3.3 and lo[1]<-4.5 and hi[1]>-9.4),'bridge approach clutter '+o.name)
# Actual separation between ladder rails and shifted side wall, not metadata.
ladlo,ladhi=bounds(instances['ladder'][0]);leftwall=min(instances['porch_side'],key=lambda o:o.location.x);walllo,wallhi=bounds(leftwall)
require(walllo[0]-ladhi[0]>.55,'ladder-sidewall clearance')
posts=instances['canopy_post'];require(len(posts)==3,'three upper remnant columns')
front=min(posts,key=lambda o:o.location.y);rear=[o for o in posts if o!=front]
require(all(bounds(r)[1][2]-bounds(front)[1][2]>.55 for r in rear),'front column lower than both rear columns')
for post in posts:
 require(any(abs(post.location.x-p.location.x)<.001 and abs(post.location.y-p.location.y)<.001 for p in instances['wall_pier'] if p.location.z<1),'bearing column axes align')
require(len(instances['hanging_tire'])==4 and len(instances['bridge_rope'])==2,'four hanging tires and two edge ropes')
for o in instances['platform_board']+instances['dock_board']:
 lo,hi=bounds(o);require(abs(hi[2]-lo[2]-.60)<.001,'plump 0.60m source deck thickness')
for e in entries:
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
 with bpy.data.libraries.load(str(source),link=False) as (a,b):b.collections=[e['collection']]
 bpy.context.scene.collection.children.link(b.collections[0]);bpy.context.scene.name=e['name'];p=R/e['component_source'];p.parent.mkdir(parents=True,exist_ok=True)
 for im in bpy.data.images:
  if im.source=='FILE':im.filepath=str(pal)
 bpy.ops.wm.save_as_mainfile(filepath=str(p),compress=True)
 for im in bpy.data.images:
  if im.source=='FILE':im.filepath=bpy.path.relpath(str(pal))
 bpy.ops.wm.save_as_mainfile(filepath=str(p),compress=True);bpy.ops.wm.open_mainfile(filepath=str(p));inspect(e)
 e.update(source_sha256=sha(p),version='v005',palette=str(pal.relative_to(R)),stage='source_verified_runtime_pending',license='pending_user_reference_rights_review');(p.parent/'asset_manifest.json').write_text(json.dumps(e,ensure_ascii=False,indent=2)+'\n')
 print('REOPENED',e['key'],flush=True)
(D/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n')
# Each semantic part is also independently openable as a linked assembly, with
# its own collections and Chinese names (four modules, not whole-house GLBs).
for module,name in [('rear_building','后部方形建筑'),('solar_room','前部倾斜太阳能房'),('front_platform','前方可行动平台-酒红'),('bridge','栈桥-暖木')]:
 bpy.ops.wm.read_factory_settings(use_empty=True);sc=bpy.context.scene;sc.name='太阳能木屋-'+name
 selected=[e for e in layout if e['module']==module];ids={e['asset_id'] for e in selected}
 with bpy.data.libraries.load(str(source),link=True) as (a,b):b.collections=list(ids)
 cols={c.name:c for c in b.collections};root=bpy.data.collections.new(sc.name);sc.collection.children.link(root)
 for e in selected:
  o=bpy.data.objects.new(e['name'],None);root.objects.link(o);o.instance_type='COLLECTION';o.instance_collection=cols[e['asset_id']];o.location=e['position'];o.rotation_euler=e['rotation_euler_xyz'];o.scale=e['scale']
 path=D/'modules'/module/(module+'.blend');path.parent.mkdir(parents=True,exist_ok=True);bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True);bpy.ops.wm.open_mainfile(filepath=str(path));require(len(bpy.context.scene.objects)==len(selected),module+' reopen instance count')
# Preserve original input and palette hashes.
protected=json.loads((W/'protected_sources.json').read_text());require(all(sha(R/p)==h for p,h in protected.items()),'protected sources changed')
report=dict(passed=not errors,errors=sorted(set(errors)),components=len(entries),instances=len(layout),uv_faces_checked=uv_faces,packages_reopened=len(entries),modules_reopened=4,source_sha256=sha(source),source_only=True)
(W/'source_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
if errors:raise RuntimeError(str(sorted(set(errors))))
bpy.ops.wm.open_mainfile(filepath=str(source));sc=bpy.context.scene;sc.cycles.samples=24;sc.render.resolution_x=900;sc.render.resolution_y=900;cam=sc.camera
for name,offset,ortho,hide in [('building_only',(-18,-28,19),22.5,True),('top',(0,-4.8,40),27,False),('rear',(19,24,19),22.5,True),('detail',(-14,-22,13),15,False)]:
 bpy.data.collections['花朵与植物-独立'].hide_render=hide;target=Vector((-.15,-2.7,4.3)) if name!='detail' else Vector((.2,-4.5,3.9));cam.location=offset;cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=ortho;sc.render.filepath=str(W/'previews'/(name+'.png'));bpy.ops.render.render(write_still=True)
print('SOURCE_VERIFIED',report,flush=True)
