"""Reopen saved source and every package, validate palette/anchors/instance transforms.
Blender --background --python verify_source.py [-- --render]
Writes QA outside the repository. Does not touch runtime resources or user data.
"""
import bpy,json,math,hashlib,os,sys
from pathlib import Path
from mathutils import Vector,Matrix
R=Path(__file__).resolve().parents[3]
version=sys.argv[sys.argv.index('--version')+1] if '--version' in sys.argv else 'v001'
assert version in ['v001','v002','v003']
D=R/'art_source/scenes/solar_flower_house'/version;W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/('solar_flower_house' if version=='v001' else 'solar_flower_house_'+version)
if R==W or R in W.parents:raise RuntimeError('Output must be outside repository')
plan=json.loads((D/'component_plan.json').read_text());catalog=json.loads((D/'component_catalog.json').read_text())['components'];instances=json.loads((D/'component_instances.json').read_text())['instances']
errors=[];checks={};metrics={'components':len(catalog),'instances':len(instances),'polygons':0,'vertices':0,'faces_uv_checked':0}
def require(ok,msg):
 if not ok:errors.append(msg)
def identity(m):return max(abs(m[i][j]-(1 if i==j else 0)) for i in range(4) for j in range(4))<1e-6
def inspect(col,item,count_metrics=False):
 require(tuple(col.instance_offset)==(0,0,0),item['slug']+': offset')
 root=bpy.data.objects.get(item['root_object']);require(root is not None and identity(root.matrix_local),item['slug']+': root transform')
 meshes=[o for o in col.objects if o.type=='MESH'];require(bool(meshes),item['slug']+': empty')
 xyz=[]
 for o in meshes:
  require(identity(o.matrix_local),o.name+': mesh transform')
  require(o.parent==root,o.name+': parent')
  xyz.extend(v.co for v in o.data.vertices)
  if count_metrics:metrics['polygons']+=len(o.data.polygons);metrics['vertices']+=len(o.data.vertices)
  uv=o.data.uv_layers.get('PaletteUV');require(uv is not None,o.name+': UV absent')
  if not uv:continue
  require(o.data.uv_layers.active==uv and uv.active_render,o.name+': active UV')
  require(len(o.data.uv_layers)==1,o.name+': extra UV layers')
  for p in o.data.polygons:
   coords=[uv.data[i].uv for i in p.loop_indices]
   area=abs(sum(a.x*b.y-b.x*a.y for a,b in zip(coords,coords[1:]+coords[:1])))/2
   cell={(math.floor(a.x*8),math.floor(a.y*8)) for a in coords}
   require(area>1e-8 and len(cell)==1,o.name+': degenerate/straddling UV face '+str(p.index))
   require(all(.124<=((a.x*8)%1)<=.876 and .124<=((a.y*8)%1)<=.876 for a in coords),o.name+': unsafe UV margin')
   if count_metrics:metrics['faces_uv_checked']+=1
  for m in o.data.materials:
   require(m.name in ['SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission'],o.name+': material '+m.name)
   if m.name=='SEA_Emission':require('emissive' in o.name,o.name+': emissive not separated')
   tex=[n for n in m.node_tree.nodes if n.type=='TEX_IMAGE'];require(len(tex)==1,m.name+': image count')
   for n in tex:
    require(n.interpolation=='Closest',m.name+': filtering')
    require(n.image.packed_file is None,m.name+': packed palette')
    p=Path(bpy.path.abspath(n.image.filepath)).resolve();require(p==R/'art_source/shared/palettes/sea_cozy_8x8_512.png' and p.is_file(),m.name+': palette path '+str(p))
   require(any(n.type=='UVMAP' and n.uv_map=='PaletteUV' for n in m.node_tree.nodes),m.name+': UV node')
 if xyz:
  lo=[min(v[i] for v in xyz) for i in range(3)];hi=[max(v[i] for v in xyz) for i in range(3)]
  require(abs(lo[2])<1e-5 and abs(lo[0]+hi[0])<1e-5 and abs(lo[1]+hi[1])<1e-5,item['slug']+': origin/bounds')
  require(max(abs((hi[i]-lo[i])-item['bounds_size_m'][i]) for i in range(3))<1e-4,item['slug']+': recorded bounds')
bpy.ops.wm.open_mainfile(filepath=str(D/'solar_flower_house.blend'))
require(len(catalog)==len(plan['components'])<=50,'budget')
family={}
for c in plan['components']:family.setdefault(c['component_family'],[]).append(c)
for f,items in family.items():require(len(items)<=3 or (len(items)<=5 and all(x['variant_axis'] and x['variant_reason'] for x in items)),f+': variants')
main=bpy.data.scenes['太阳能花屋_参考装配'];bpy.context.window.scene=main
actual={o.name:o for o in main.objects if o.instance_type=='COLLECTION'}
require(len(actual)==len(instances),'instance count')
for entry in instances:
 o=actual.get(entry['instance_id']);require(o is not None,entry['instance_id']+': absent')
 if o:
  require(o.instance_collection.name==entry['component_id'],o.name+': component')
  require(max(abs(o.location[i]-entry['position_m'][i]) for i in range(3))<1e-6,o.name+': position')
  require(max(abs(o.rotation_euler[i]-entry['rotation_euler_xyz_rad'][i]) for i in range(3))<1e-6,o.name+': rotation')
  require(max(abs(o.scale[i]-entry['scale'][i]) for i in range(3))<1e-6,o.name+': scale')
  group='花草_实例' if next(c for c in catalog if c['component_id']==entry['component_id'])['category']=='flora' else '建筑_实例'
  require(o in bpy.data.collections[group].objects.values(),o.name+': category')
for item in catalog:inspect(bpy.data.collections[item['collection']],item,True)
if 'geometry_budget' in plan:
 # Count evaluated instances from the actual saved scene, independently of the manifest.
 deps=bpy.context.evaluated_depsgraph_get();expanded_triangles=0;expanded_polygons=0;expanded_meshes=0
 for entry in deps.object_instances:
  ob=entry.object
  if ob.type!='MESH' or ob.hide_render:continue
  me=ob.to_mesh();me.calc_loop_triangles();expanded_triangles+=len(me.loop_triangles);expanded_polygons+=len(me.polygons);expanded_meshes+=1;ob.to_mesh_clear()
 metrics.update(expanded_triangles=expanded_triangles,expanded_polygons=expanded_polygons,expanded_meshes=expanded_meshes)
 require(expanded_triangles<=plan['geometry_budget']['maximum_expanded_triangles'],'expanded evaluated triangle budget exceeded')
 recorded=json.loads((D/'geometry_budget.json').read_text());require(expanded_triangles==recorded['expanded_triangles'],'manifest triangle count differs from evaluated scene')
 # A conservative footprint clearance check at deck/character-body height.
 clear=plan['dimensions_assumption'].get('clear_front_corridor');obstructions=[]
 if clear:
  for ob in actual.values():
   slug=next(c['slug'] for c in catalog if c['component_id']==ob['component_id'])
   if slug in ['foundation','deck_plank','pier','rug']:continue
   points=[ob.matrix_world@mesh.matrix_world@v.co for mesh in ob.instance_collection.objects if mesh.type=='MESH' for v in mesh.data.vertices]
   if not points:continue
   lo=[min(v[i] for v in points) for i in range(3)];hi=[max(v[i] for v in points) for i in range(3)]
   if all(hi[i]>clear['min_m'][i]+1e-5 and lo[i]<clear['max_m'][i]-1e-5 for i in range(3)):obstructions.append(ob.name)
  checks['front_corridor_obstructions']=obstructions;require(not obstructions,'front walking corridor intersects prop bounds')
if version=='v003':
 lock=json.loads((D/'scope_lock.json').read_text())
 require(hashlib.sha256((D.parent/'v001/solar_flower_house.blend').read_bytes()).hexdigest()==lock['base_sha256'],'v001 base source changed')
 require(hashlib.sha256((R/'art_source/shared/palettes/sea_cozy_8x8_512.png').read_bytes()).hexdigest()==lock['palette_sha256'],'shared palette changed')
 base_instances={x['instance_id']:x for x in json.loads((D.parent/'v001/component_instances.json').read_text())['instances']}
 for item in catalog:
  if item['slug'] not in lock['locked_fingerprints']:continue
  col=bpy.data.collections[item['collection']]
  meshes=[o for o in col.objects if o.type=='MESH']
  geo=[{'vertices':[[round(float(v),5) for v in p.co] for p in o.data.vertices],'polygons':[list(p.vertices) for p in o.data.polygons]} for o in meshes]
  require(hashlib.sha256(json.dumps(geo,sort_keys=True).encode()).hexdigest()==lock['locked_fingerprints'][item['slug']],item['slug']+': locked geometry changed')
  for row in instances:
   if row['component_id']!=item['component_id']:continue
   require(all(row[k]==base_instances[row['instance_id']][k] for k in ['position_m','rotation_euler_xyz_rad','scale']),row['instance_id']+': locked placement changed')
 checks['v001_locked_geometry_components']=len(lock['locked_fingerprints'])
 deps=bpy.context.evaluated_depsgraph_get();tri=0;poly=0
 for entry in deps.object_instances:
  ob=entry.object
  if ob.type!='MESH' or ob.hide_render:continue
  me=ob.to_mesh();me.calc_loop_triangles();tri+=len(me.loop_triangles);poly+=len(me.polygons);ob.to_mesh_clear()
 metrics.update(expanded_triangles=tri,expanded_polygons=poly,triangle_target_status='style_iteration_on_v001; 3000 optimization deferred')
checks['assembled_source']=not errors
for item in catalog:
 p=R/item['component_blend'];require(hashlib.sha256(p.read_bytes()).hexdigest()==item['source_sha256'],item['slug']+': source hash')
 bpy.ops.wm.open_mainfile(filepath=str(p));require(any(o.type=='MESH' for o in bpy.context.scene.objects),item['slug']+': standalone active scene empty');inspect(bpy.data.collections[item['collection']],item)
checks['standalone_packages_reopened']=len(catalog)
report={'schema':'sea.scene.source_verification','source_only':True,'checks':checks,'metrics':metrics,'errors':list(dict.fromkeys(errors)),'passed':not errors,'expected_faults':[],'not_executed':['Godot import','runtime collision/navigation','game performance','reference commercial rights review'],'runtime_status':'pending'}
(W/'source_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('SEA_SOURCE_VERIFICATION',json.dumps(report,ensure_ascii=False),flush=True)
if errors:raise RuntimeError('source verification failed')
if '--render' in sys.argv:
 bpy.ops.wm.open_mainfile(filepath=str(D/'solar_flower_house.blend'));scene=bpy.context.scene;scene.cycles.samples=32
 if '--no-denoise' in sys.argv:
  scene.cycles.use_denoising=False;scene.cycles.samples=64
 cam=scene.camera
 def aim(point):cam.rotation_euler=(Vector(point)-cam.location).to_track_quat('-Z','Y').to_euler()
 bpy.data.collections['花草_实例'].hide_render=True
 scene.render.filepath=str(W/'previews/building_only.png');bpy.ops.render.render(write_still=True)
 bpy.data.collections['花草_实例'].hide_render=False
 cam.location=(-7,-10,6.8);aim((-.1,-.65,3.3));cam.data.ortho_scale=7.5
 scene.render.filepath=str(W/'previews/detail.png');bpy.ops.render.render(write_still=True)
 cam.location=(0,0,18);aim((0,0,0));cam.data.ortho_scale=11.8 if version=='v002' else 10.6
 scene.render.filepath=str(W/'previews/top.png');bpy.ops.render.render(write_still=True)
print('SEA_SOURCE_QA_COMPLETE',flush=True)
