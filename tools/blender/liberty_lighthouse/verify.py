"""Reopen and validate this source-only kit, export standalone packages and render views."""
import bpy,json,hashlib,math,os
from pathlib import Path
from mathutils import Vector
R=Path(r'D:/projects/sea');D=R/'art_source/scenes/liberty_lighthouse/v001';W=R/'sea-work/liberty_lighthouse';pal=R/'art_source/shared/palettes/sea_cozy_8x8_512.png'
source=D/'liberty_lighthouse.blend';plan=json.loads((D/'component_plan.json').read_text());cat=json.loads((D/'catalog.json').read_text());entries=cat['components'];errors=[];uv_faces=0
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def req(x,s):
 if not x:errors.append(s)
def identity(m):return max(abs(m[i][j]-(1 if i==j else 0)) for i in range(4) for j in range(4))<1e-5

def inspect(e,count=False):
 global uv_faces
 c=bpy.data.collections.get(e['collection']);req(c is not None,e['key']+' collection missing')
 if not c:return
 req(tuple(c.instance_offset)==(0,0,0),e['key']+' offset')
 root=bpy.data.objects.get(e['root']);req(root is not None and identity(root.matrix_world),e['key']+' root')
 pts=[];tris=0
 for o in c.objects:
  if o.type!='MESH':continue
  req(o.parent==root,e['key']+' parent '+o.name);o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles)
  ev=o.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();pts += [o.matrix_world@v.co for v in me.vertices];ev.to_mesh_clear()
  uv=o.data.uv_layers.get('PaletteUV');req(uv is not None,o.name+' uv missing')
  if not uv:continue
  req(len(o.data.uv_layers)==1 and o.data.uv_layers.active==uv and uv.active_render,o.name+' active uv')
  for f in o.data.polygons:
   p=[uv.data[i].uv for i in f.loop_indices];area=abs(sum(a.x*b.y-b.x*a.y for a,b in zip(p,p[1:]+p[:1])))/2
   req(area>1e-9,o.name+' uv point');req(len({(int(v.x*8),int(v.y*8)) for v in p})==1,o.name+' uv crosses');req(all(.125-1e-5<=(v[k]*8)%1<=.875+1e-5 for v in p for k in [0,1]),o.name+' uv margin')
   if count:uv_faces+=1
  for m in o.data.materials:
   req(m.name in {'SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission'},o.name+' role')
   tx=[n for n in m.node_tree.nodes if n.type=='TEX_IMAGE'];req(len(tx)==1,m.name+' image')
   for n in tx:
    req(n.interpolation=='Closest' and n.image and not n.image.packed_file,m.name+' packed/interpolation');req(Path(bpy.path.abspath(n.image.filepath)).resolve()==pal.resolve(),m.name+' palette');req(n.inputs['Vector'].links[0].from_node.uv_map=='PaletteUV',m.name+' uv input')
 if not pts:req(False,e['key']+' empty');return
 lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
 req(abs(lo[2])<1e-5 and abs(lo[0]+hi[0])<1e-5 and abs(lo[1]+hi[1])<1e-5,e['key']+' origin '+str(lo)+str(hi))
 for i in range(3):req(abs(hi[i]-lo[i]-e['bounds_size'][i])<.025,e['key']+' bounds '+str([hi[j]-lo[j] for j in range(3)]))
 e['triangles']=tris

bpy.ops.wm.open_mainfile(filepath=str(source));sc=bpy.data.scenes['巨手灯塔_制作与装配_v001'];bpy.context.window.scene=sc
req(len(entries)==30 and len(entries)<=50,'component count');req(sha(D/'reference.png')==plan['reference_sha256'],'reference hash')
layout=json.loads((D/'component_instances.json').read_text())['instances'];actual={o.name:o for o in sc.objects if o.instance_type=='COLLECTION'}
req(len(actual)==len(layout),'instance count')
for i in layout:
 o=actual.get(i['name']);req(o is not None,i['name'])
 if o:
  req(o.instance_collection.name=='SEA-SCENE-LHL-'+i['key'].upper().replace('_','-'),i['name']+' asset')
  for k,n in [('position','location'),('rotation_euler_xyz','rotation_euler'),('scale','scale')]:req(max(abs(getattr(o,n)[j]-i[k][j]) for j in range(3))<1e-5,i['name']+' '+k)
for e in entries:inspect(e,True)
# Actual instanced geometry and critical dimension assertions.
deps=bpy.context.evaluated_depsgraph_get();polys=triangles=0
for inst in deps.object_instances:
 o=inst.object
 if o.type=='MESH' and not o.hide_render and o.name!='展示海面':
  me=o.to_mesh();me.calc_loop_triangles();polys+=len(me.polygons);triangles+=len(me.loop_triangles);o.to_mesh_clear()
key_bounds={}
for i in layout:
 o=actual[i['name']];pts=[]
 for m in o.instance_collection.objects:
  if m.type!='MESH':continue
  ev=m.evaluated_get(deps);me=ev.to_mesh();pts += [o.matrix_world@m.matrix_local@v.co for v in me.vertices];ev.to_mesh_clear()
 key_bounds[i['key']]=[min(v[i] for v in pts) for i in range(3)]+[max(v[i] for v in pts) for i in range(3)]
req(abs(key_bounds['barge'][3]-key_bounds['barge'][0]-8)<.01,'barge length');req(abs(key_bounds['barge'][4]-key_bounds['barge'][1]-6)<.1,'barge width');req(abs(key_bounds['platform'][3]-key_bounds['platform'][0]-6)<.1,'platform diameter')
req(abs(key_bounds['column'][5]-key_bounds['column'][2]-5)<.1,'column 5m');req(abs(key_bounds['tower_body'][5]-key_bounds['tower_body'][2]-2.5)<.03,'tower body 2.5m');req(abs(key_bounds['lantern'][5]-key_bounds['lantern'][2]-2)<.03,'lantern 2m');req(abs(key_bounds['antenna_mast'][5]-key_bounds['antenna_mast'][2]-3.5)<.03,'mast 3.5m')
req(key_bounds['column'][2]<key_bounds['finger'][5] and key_bounds['column'][2]<11,'column inserted in grip')
req(abs(key_bounds['awning'][2]-3.5)<.03,'awning valance world elevation 3.5m; about 2.26m above deck crown')
metrics={'components':len(entries),'instances':len(layout),'uv_faces_checked':uv_faces,'expanded_polygons':polys,'expanded_triangles':triangles,'overall_height_m':max(v[5] for v in key_bounds.values())}
# Standalone, individually reopenable source packages.
for e in entries:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 with bpy.data.libraries.load(str(source),link=False) as (a,b):b.collections=[e['collection']]
 c=b.collections[0];bpy.context.scene.collection.children.link(c);bpy.context.scene.name=e['name'];bpy.context.scene.unit_settings.system='METRIC'
 p=R/e['component_source'];p.parent.mkdir(parents=True,exist_ok=True)
 for im in bpy.data.images:
  if im.source=='FILE':im.filepath=bpy.path.relpath(str(pal),start=str(p.parent))
 bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(p),compress=True)
 e['source_sha256']=sha(p);e['palette']=str(pal.relative_to(R));e['version']='v001';e['stage']='source_verified_runtime_pending';e['license']='pending_user_reference_rights_review';e['asset_ledger']='assets/registry/ledgers/scenes.json#'+e['asset_id']
 (p.parent/'asset_manifest.json').write_text(json.dumps(e,ensure_ascii=False,indent=2)+'\n')
 bpy.ops.wm.open_mainfile(filepath=str(p));inspect(e)
 print('REOPENED',e['key'],flush=True)
report={'schema':'sea.scene.source_verification','passed':not errors,'errors':sorted(set(errors)),'source_sha256':sha(source),'palette_sha256':sha(pal),'reference_sha256':sha(D/'reference.png'),'metrics':metrics,'standalone_packages_reopened':len(entries),'key_bounds':key_bounds,'source_only':True,'not_executed':['Godot import/runtime/collision/navigation','reference commercial rights verification'],'views':[]}
(W/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
if errors:raise RuntimeError('\n'.join(sorted(set(errors))))
(D/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n')
bpy.ops.wm.open_mainfile(filepath=str(source));sc=bpy.data.scenes['巨手灯塔_制作与装配_v001'];bpy.context.window.scene=sc;cam=sc.camera
for name,pos,target,size,res in [('beauty',(17,-38,22),(0,0,12.3),29.8,(1000,1400)),('detail',(11,-20,12),(0,0,10),12.2,(1200,1200)),('shop_detail',(10,-16,8),(0,0,3.5),10.8,(1200,1000)),('top',(0,-.01,35),(0,0,12),12,(1200,1200))]:
 cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=size;sc.render.resolution_x=res[0];sc.render.resolution_y=res[1];sc.render.filepath=str(W/(name+'.png'));bpy.ops.render.render(write_still=True);report['views'].append({'name':name,'path':sc.render.filepath})
(W/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('SOURCE_VERIFIED',json.dumps(report['metrics']),flush=True)
