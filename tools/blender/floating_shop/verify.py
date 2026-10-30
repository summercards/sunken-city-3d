"""Independent saved-source inspection, standalone reopen checks, real GUI renders."""
import bpy,json,hashlib,math,os
from pathlib import Path
from mathutils import Vector
R=Path('D:/projects/sea');D=R/'art_source/scenes/floating_shop/v001';W=Path(os.environ.get('SEA_WORK_ROOT','D:/projects/sea-work'))/'floating_shop'
pal=R/'art_source/shared/palettes/sea_cozy_8x8_512.png';source=D/'floating_shop.blend'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
plan=json.loads((D/'component_plan.json').read_text());cat=json.loads((D/'catalog.json').read_text());layout=json.loads((D/'component_instances.json').read_text())['instances']
errors=[];uvfaces=0;meshes=0
def req(v,msg):
 if not v:errors.append(msg)
def ident(m):return max(abs(m[i][j]-(1 if i==j else 0)) for i in range(4) for j in range(4))<1e-5
def inspect(e,count=False):
 global uvfaces,meshes
 col=bpy.data.collections.get(e['collection']);req(col is not None,e['key']+' collection')
 if col is None:return
 root=bpy.data.objects.get(e['root']);req(root is not None and ident(root.matrix_world),e['key']+' root identity');req(tuple(col.instance_offset)==(0,0,0),e['key']+' collection offset')
 pts=[];polys=tris=0;roles=set()
 for o in col.objects:
  if o.type!='MESH':continue
  if count:meshes+=1
  req(o.parent==root and ident(o.matrix_basis),o.name+' mesh transform')
  req(len(o.modifiers)==0,o.name+' unapplied modifier')
  pts.extend(v.co for v in o.data.vertices);polys+=len(o.data.polygons);o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles)
  uv=o.data.uv_layers.get('PaletteUV');req(uv is not None and len(o.data.uv_layers)==1 and uv.active_render and o.data.uv_layers.active==uv,o.name+' UV0')
  if not uv:continue
  for f in o.data.polygons:
   coords=[uv.data[i].uv for i in f.loop_indices];area=abs(sum(a.x*b.y-b.x*a.y for a,b in zip(coords,coords[1:]+coords[:1])))/2
   req(area>1e-10,o.name+' zero UV '+str(f.index));req(len({(int(p.x*8),int(p.y*8)) for p in coords})==1,o.name+' crossed cell');req(all(.125-1e-5<=(p[k]*8)%1<=.875+1e-5 for p in coords for k in [0,1]),o.name+' UV margin')
   if count:uvfaces+=1
  for m in o.data.materials:
   req(m.name in ['SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission'],o.name+' material role');roles.add(m.name)
   tex=[n for n in m.node_tree.nodes if n.type=='TEX_IMAGE'];req(len(tex)==1,o.name+' texture')
   for n in tex:
    req(n.image is not None and not n.image.packed_file and Path(bpy.path.abspath(n.image.filepath)).resolve()==pal.resolve(),o.name+' palette external path')
    req(n.interpolation=='Closest' and n.inputs['Vector'].links and n.inputs['Vector'].links[0].from_node.uv_map=='PaletteUV',o.name+' UV node')
 if not pts:req(False,e['key']+' empty');return
 lo=[min(p[i] for p in pts) for i in range(3)];hi=[max(p[i] for p in pts) for i in range(3)]
 req(abs(lo[2])<1e-5 and abs(lo[0]+hi[0])<1e-5 and abs(lo[1]+hi[1])<1e-5,e['key']+' bottom center')
 req(all(abs(hi[i]-lo[i]-e['bounds_size'][i])<1e-4 for i in range(3)),e['key']+' bounds')
 if count:e['polygons']=polys;e['triangles']=tris;e['materials']=sorted(roles)

bpy.ops.wm.open_mainfile(filepath=str(source));sc=bpy.data.scenes['海上悬浮商铺_v001'];bpy.context.window_manager.windows[0].scene=sc
req(len(cat['components'])==len(plan['components'])==39 and len(cat['components'])<=50,'component count')
req(sha(D/'reference.png')==plan['reference_sha256'],'reference hash')
actual={o.name:o for o in sc.objects if o.instance_type=='COLLECTION'};req(len(actual)==len(layout),'instance count')
bounds={};allpts=[]
for i in layout:
 o=actual.get(i['name']);req(o is not None,i['name']+' missing')
 if o is None:continue
 req(o.instance_collection.name=='SEA-SCENE-FSH-'+i['key'].upper().replace('_','-'),i['name']+' asset')
 for k,n in [('position','location'),('rotation_euler_xyz','rotation_euler'),('scale','scale')]:req(max(abs(getattr(o,n)[j]-i[k][j]) for j in range(3))<1e-5,i['name']+' transform')
 pts=[o.matrix_world@m.matrix_world@v.co for m in o.instance_collection.objects if m.type=='MESH' for v in m.data.vertices];allpts.extend(pts)
 bounds[i['name']]=[[min(v[j] for v in pts),max(v[j] for v in pts)] for j in range(3)]
 req((o.users_collection[0].name=='FSH_植物附件')==(i['key'] in ['flowers','foliage']),i['name']+' plant separation')
for e in cat['components']:inspect(e,True)
def size(name,axis):b=bounds[name][axis];return b[1]-b[0]
req(abs(size('entry_001',2)-2.78)<.02,'entry outer height')
# Actual jamb inner faces: +/-1m. Door lintel underside is 2.20m above deck.
entry=bpy.data.collections['SEA-SCENE-FSH-ENTRY'];jambs=[o for o in entry.objects if o.type=='MESH' and o.name.startswith('开放门洞侧框')];lintel=next(o for o in entry.objects if o.type=='MESH' and o.name.startswith('开放门洞横楣'))
jambs.sort(key=lambda o:sum(v.co.x for v in o.data.vertices)/len(o.data.vertices))
doorwidth=min(v.co.x for v in jambs[1].data.vertices)-max(v.co.x for v in jambs[0].data.vertices);doorheight=min(v.co.z for v in lintel.data.vertices)
req(abs(doorwidth-2)<.015 and abs(doorheight-2.2)<.015,'door clear 2 x 2.2m')
req(abs(size('rail_post_001',2)-1.1)<.01,'rail 1.1m');req(1.3<size('tire_001',2)<1.5,'tire with hanging rope')
tire=bpy.data.objects.get('黑色厚轮胎');req(tire and abs(max(v.co.x for v in tire.data.vertices)-min(v.co.x for v in tire.data.vertices)-1)<.01,'tire body diameter1m')
req(sum(i['key']=='tire' for i in layout)==10,'ten tires');req(sum(i['key']=='float_pod' for i in layout)==2,'two floats')
overall=[max(v[j] for v in allpts)-min(v[j] for v in allpts) for j in range(3)];req(abs(overall[2]-7.5)<.08,'overall 7.5m')
dg=bpy.context.evaluated_depsgraph_get();expanded_polys=expanded_tris=0
for i in dg.object_instances:
 if i.is_instance and i.object.type=='MESH':
  me=i.object.to_mesh();me.calc_loop_triangles();expanded_polys+=len(me.polygons);expanded_tris+=len(me.loop_triangles);i.object.to_mesh_clear()
metrics={'components':len(cat['components']),'instances':len(layout),'master_meshes':meshes,'uv_faces_checked':uvfaces,'expanded_polygons':expanded_polys,'expanded_triangles':expanded_tris,'overall_bounds_m':overall,'door_clear_width_m':doorwidth,'door_clear_height_m':doorheight,'rail_height_m':size('rail_post_001',2)}
report={'schema':'sea.scene.source_verification','passed':not errors,'errors':sorted(set(errors)),'source_only':True,'source_sha256':sha(source),'palette_sha256':sha(pal),'reference_sha256':sha(D/'reference.png'),'metrics':metrics,'standalone_packages_reopened':0,'bounds':bounds,'views':[],'not_executed':['Godot import/runtime/collision/navigation/performance','reference commercial rights verification','user final art acceptance'],'exit_codes':{}}
(W/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if errors:raise RuntimeError('\n'.join(sorted(set(errors))))
for e in cat['components']:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 with bpy.data.libraries.load(str(source),link=False) as (a,b):b.collections=[e['collection']]
 c=b.collections[0];bpy.context.scene.collection.children.link(c);bpy.context.scene.name=e['name'];bpy.context.scene.unit_settings.system='METRIC'
 p=R/e['component_source'];p.parent.mkdir(parents=True,exist_ok=True)
 for im in bpy.data.images:
  if im.source=='FILE':im.filepath=bpy.path.relpath(str(pal),start=str(p.parent))
 bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(p),compress=True)
 e['source_sha256']=sha(p);e['palette']='art_source/shared/palettes/sea_cozy_8x8_512.png';e['version']='v001';e['stage']='source_verified_runtime_pending';e['license']='pending_user_reference_rights_review';e['asset_ledger']='assets/registry/ledgers/scenes.json#'+e['asset_id']
 (p.parent/'asset_manifest.json').write_text(json.dumps(e,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 bpy.ops.wm.open_mainfile(filepath=str(p));inspect(e);report['standalone_packages_reopened']+=1
if errors:
 report['passed']=False;report['errors']=sorted(set(errors));(W/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');raise RuntimeError(str(report['errors']))
(D/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
report['exit_codes']['source_validation']=0
(W/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
bpy.ops.wm.open_mainfile(filepath=str(source));print('SOURCE_VERIFIED',json.dumps(metrics))
