"""Reopen authored master and every standalone component; independently audit mesh facts."""
import bpy,json,math,hashlib,os,sys
from pathlib import Path
from mathutils import Matrix,Vector
version=os.environ.get('NGQ_VERSION','v001')
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/neon_garden_quarter'/version;W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'neon_garden_quarter'/version
P=json.loads((D/'component_plan.json').read_text(encoding='utf8'));C=json.loads((D/'component_catalog.json').read_text(encoding='utf8'))['components'];MAIN=D/'neon_garden_quarter.blend'
ATLAS=R/P['poster_source'] if 'poster_source' in P else D/'textures/poster_atlas.png'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def dump(p,x):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
fail=[];checks=0;facecount=0;poster_faces=0
def check(c,msg):
 global checks
 checks+=1
 if not c:fail.append(msg)
def audit(col,label):
 global facecount,poster_faces
 meshes=[o for o in col.all_objects if o.type=='MESH'];check(bool(meshes),label+': nonempty');vs=[];polys=0;tri=0;roles=set()
 for o in meshes:
  check(all(abs(o.matrix_local[i][j]-(1 if i==j else 0))<1e-6 for i in range(4) for j in range(4)),label+'/'+o.name+': identity')
  check(len(o.users_collection)==1,label+'/'+o.name+': unique package owner')
  me=o.data;vs.extend(v.co[:] for v in me.vertices);me.calc_loop_triangles();tri+=len(me.loop_triangles);polys+=len(me.polygons)
  check(len(me.vertices)>0 and len(me.polygons)>0,label+': geometry')
  check(all(f.area>1e-10 for f in me.polygons),label+'/'+o.name+': nonzero face geometry')
  check(me.uv_layers.active and me.uv_layers.active.name=='PaletteUV',label+'/'+o.name+': active PaletteUV')
  check(next((u.name for u in me.uv_layers if u.active_render),None)=='PaletteUV',label+'/'+o.name+': render PaletteUV')
  check(set(u.name for u in me.uv_layers)<=({'PaletteUV','PosterUV'} if 'poster_tile' in o else {'PaletteUV'}),label+': documented UV only')
  uv=me.uv_layers.get('PaletteUV');bad=0
  if uv:
   for f in me.polygons:
    pts=[uv.data[li].uv for li in f.loop_indices];cell={(int(p.x*8),int(p.y*8)) for p in pts}
    area=abs(sum(pts[k].x*pts[(k+1)%len(pts)].y-pts[(k+1)%len(pts)].x*pts[k].y for k in range(len(pts))))/2
    safe=all(.125<=p.x*8-int(p.x*8)<=.875 and .125<=p.y*8-int(p.y*8)<=.875 for p in pts)
    bad+=int(len(cell)!=1 or area<1e-8 or not safe);facecount+=1
   check(bad==0,label+'/'+o.name+f': {bad} invalid UV faces')
  if 'poster_tile' in o:
   poster_faces+=len(me.polygons);check('PosterMask' in me.attributes and all(abs(x.value-1)<1e-6 for x in me.attributes['PosterMask'].data),label+': poster mask')
   check('PosterUV' in me.uv_layers,label+': print UV')
  for mat in me.materials:
   roles.add(mat.name);check(mat.name in ['SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission'],label+': four roles')
   if mat.name=='SEA_Emission':check(o.name.startswith('EM_'),label+'/'+o.name+': emission separate')
 lo=[min(v[k] for v in vs) for k in range(3)];hi=[max(v[k] for v in vs) for k in range(3)]
 check(abs(lo[2])<1e-5 and abs(lo[0]+hi[0])<1e-5 and abs(lo[1]+hi[1])<1e-5,label+': bottom-center')
 check(col.instance_offset.length<1e-8,label+': zero collection offset')
 return dict(key=label,polygons=polys,triangles=tri,mesh_objects=len(meshes),bounds_min=lo,bounds_max=hi,material_roles=sorted(roles))
def textures():
 for img in bpy.data.images:
  if img.source=='FILE':
   path=Path(bpy.path.abspath(img.filepath)).resolve();check(path.exists(),'external image exists '+str(path));check(not img.packed_file,'image remains external '+img.name)
   check(path in [(R/P['palette']).resolve(),ATLAS.resolve()],'only shared palette and print atlas')
 for m in bpy.data.materials:
  if not m.use_nodes:continue
  for node in m.node_tree.nodes:
   if node.type=='TEX_IMAGE' and node.image and node.image.name.startswith('SEA_'):
    check(node.interpolation=='Closest','palette nearest');check(node.inputs['Vector'].is_linked and node.inputs['Vector'].links[0].from_node.uv_map=='PaletteUV','explicit palette UV')
bpy.ops.wm.open_mainfile(filepath=str(MAIN));bpy.context.window.scene=bpy.data.scenes['霓虹花园街区_完整装配'];textures()
results=[]
for item in C:
 r=audit(bpy.data.collections[item['collection']],item['key']);check(r['triangles']<=item['triangle_budget'],item['key']+': budget');results.append(r)
layout=bpy.context.scene;deps=bpy.context.evaluated_depsgraph_get();worldpoly=0;worldtri=0;allvs=[]
for instance in deps.object_instances:
 if instance.object.type=='MESH':
  me=instance.object.data;me.calc_loop_triangles();worldpoly+=len(me.polygons);worldtri+=len(me.loop_triangles);allvs.extend(instance.matrix_world@v.co for v in me.vertices)
instance_count=sum(o.instance_type=='COLLECTION' for o in layout.objects)
check(instance_count==len(json.loads((D/'component_instances.json').read_text(encoding='utf8'))['instances']),'instance count consistent')
check(set(x['key'] for x in C)==set(x['key'] for x in P['components']),'catalog covers frozen plan')
check(len(C)<=50,'component limit');check(all(o.type in ['MESH','EMPTY','LIGHT','CAMERA'] for o in bpy.data.objects),'no leftover font objects / creatures')
source_counts=dict(polygons=worldpoly,triangles=worldtri,visible_instances=instance_count,bounds_min=[min(v[i] for v in allvs) for i in range(3)],bounds_max=[max(v[i] for v in allvs) for i in range(3)])
source_faces=facecount;source_checks=checks
for item in C:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 with bpy.data.libraries.load(str(MAIN),link=False) as (src,dst):dst.collections=[item['collection']]
 col=dst.collections[0];bpy.context.scene.collection.children.link(col);bpy.context.scene.name=item['name'];bpy.context.scene.unit_settings.system='METRIC'
 for img in bpy.data.images:
  if img.source=='FILE':img.filepath=str(R/P['palette']) if img.name.startswith('SEA_') else str(ATLAS)
 for f in list(bpy.data.fonts):
  if not f.users:bpy.data.fonts.remove(f)
 target=R/item['source'];target.parent.mkdir(parents=True,exist_ok=True)
 for img in bpy.data.images:
  if img.source=='FILE':img.filepath=bpy.path.relpath(img.filepath,start=str(target.parent))
 for screen in bpy.data.screens:
  for a in screen.areas:
   if a.type=='VIEW_3D':a.spaces.active.shading.type='MATERIAL';a.spaces.active.region_3d.view_location=(0,0,item['bounds_size_m'][2]/2);a.spaces.active.region_3d.view_distance=max(item['bounds_size_m'])*2.1
 bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(target),compress=True)
 bpy.ops.wm.open_mainfile(filepath=str(target));textures();audit(bpy.data.collections[item['collection']],item['key']+'/reopened')
 item['source_sha256']=sha(target);item['source_stage']='source_verified_runtime_pending';item['asset_ledger']='assets/registry/ledgers/scenes.json#'+item['asset_id']
 fingerprint=hashlib.sha256()
 for ob in sorted(bpy.data.collections[item['collection']].objects,key=lambda ob:ob.name):
  fingerprint.update(json.dumps(dict(vertices=[[round(v,6) for v in q.co] for q in ob.data.vertices],faces=[list(q.vertices) for q in ob.data.polygons]),separators=(',',':')).encode())
 item['geometry_fingerprint']=fingerprint.hexdigest();item['verification']=str(W/'source_verification.json')
 dump(R/item['manifest'],item);print('NGQ_PACKAGE_REOPENED',item['key'],flush=True)
report=dict(schema='sea.source_verification',suite=P['suite'],source=MAIN.relative_to(R).as_posix(),source_sha256=sha(MAIN),blender_version=bpy.app.version_string,passed=not fail,checks=checks,failures=fail,source_checks=source_checks,source_palette_faces=source_faces,total_audited_faces=facecount,poster_faces=poster_faces,components=results,assembly=source_counts,standalone_packages_reopened=len(C),reference_sha256=P['reference_sha256'],palette_sha256=sha(R/P['palette']),poster_sha256=sha(ATLAS),runtime_validation='not_executed_not_in_scope',visual_validation='separate_render_review')
dump(D/'component_catalog.json',dict(schema='sea.component_catalog',components=C));dump(W/'source_verification.json',report)
print('NGQ_VERIFY_RESULT',json.dumps(dict(passed=not fail,checks=checks,failures=fail,assembly=source_counts),ensure_ascii=False),flush=True)
if fail:raise RuntimeError(f'{len(fail)} verification failures')
