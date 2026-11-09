"""Independent read-only QA for fixed-reference-layout candidate. Never soft-pass failures."""
import bpy,json,hashlib,math,os
from pathlib import Path
from mathutils import Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/bld_20261109_a/v003';V1=R/'art_source/scenes/bld_20261109_a/v001';W=Path('D:/projects/sea-work/bld_20261109_a/v003');S=D/'bld_20261109_a_v003.blend'
assert bpy.app.background
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
before=sha(S);p=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components'];ops=json.loads((W/'fixed_layout_operations.json').read_text(encoding='utf-8'));reference=json.loads((V1/'component_instances.json').read_text(encoding='utf-8'))['instances'];oldcat=json.loads((V1/'catalog.json').read_text(encoding='utf-8'))['components']
bpy.ops.wm.open_mainfile(filepath=str(S),load_ui=False,use_scripts=False);sc=bpy.context.scene;errors=[];checks=0;uvfaces=0;stats=[];origin=[]
def need(ok,msg):
 global checks
 checks+=1
 if not ok:errors.append(msg)
need(ops['source_sha256']==before,'operations source sha mismatch');need(len(cat)==49,'49 definitions');need(len(reference)==92,'92 reference instances')
for row in reference:
 o=sc.objects.get(row['name']);need(o is not None,row['name']+' exists')
 if o:
  for field,actual in [('position',o.location),('rotation_euler_xyz',o.rotation_euler),('scale',o.scale)]:need(max(abs(actual[i]-row[field][i]) for i in range(3))<1e-6,row['name']+' fixed '+field)
for e in cat:
 col=bpy.data.collections.get(e['collection']);need(col is not None,e['key']+' col exists')
 if not col:continue
 need(col.instance_offset.length<1e-7,e['key']+' collection offset')
 pts=[];tr=po=0
 for o in col.objects:
  need(o.type=='MESH',o.name+' mesh')
  if o.type!='MESH':continue
  need(max(abs(o.matrix_world[i][j]-Matrix.Identity(4)[i][j]) for i in range(4) for j in range(4))<1e-6,o.name+' identity')
  me=o.data;pts.extend(v.co for v in me.vertices);me.calc_loop_triangles();tr+=len(me.loop_triangles);po+=len(me.polygons)
  need(len(me.vertices)>0 and len(me.polygons)>0,o.name+' nonempty')
  uv=me.uv_layers.get('PaletteUV');need(len(me.uv_layers)==1 and me.uv_layers.active==uv and uv.active_render,o.name+' UV active render')
  if not uv:continue
  for f in me.polygons:
   uvfaces+=1;xy=[uv.data[i].uv for i in f.loop_indices];area=abs(sum(a.x*b.y-a.y*b.x for a,b in zip(xy,xy[1:]+xy[:1])))*.5;need(area>1e-9,o.name+' uv area '+str(f.index));cells={(int(v.x*8),int(v.y*8)) for v in xy};need(len(cells)==1,o.name+' one swatch '+str(f.index));need(all(.015625-1e-6<=v.x%.125<=.109375+1e-6 and .015625-1e-6<=v.y%.125<=.109375+1e-6 for v in xy),o.name+' 8px '+str(f.index))
  for mat in me.materials:
   need(mat.get('semantic_role') in {'SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission'},o.name+' role')
   for n in mat.node_tree.nodes:
    if n.type=='TEX_IMAGE':need(n.interpolation=='Closest' and n.image.packed_file is None and Path(bpy.path.abspath(n.image.filepath)).resolve()==(R/p['palette']).resolve(),o.name+' shared palette')
 lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)];res=max(abs(lo[2]),abs(lo[0]+hi[0]),abs(lo[1]+hi[1]));need(res<2e-5,e['key']+' bottom centre origin')
 if res>=2e-5:origin.append({'key':e['key'],'residual_m':res,'min':lo,'max':hi})
 need(tr==e['triangles'] and po==e['polygons'],e['key']+' exact stats');stats.append({'key':e['key'],'triangles':tr,'polygons':po,'bounds':[hi[i]-lo[i] for i in range(3)]})
expanded_tr=sum(e['triangles']*e['instance_count'] for e in cat);expanded_po=sum(e['polygons']*e['instance_count'] for e in cat)
need(sha(S)==before,'source unchanged')
report={'passed':not errors,'checks':checks,'errors':errors,'source_sha256':before,'instances_reference_locked':True,'components':len(cat),'instances':92,'uv_faces_checked':uvfaces,'expanded_triangles':expanded_tr,'expanded_polygons':expanded_po,'origin_issues':origin,'components_stats':stats,'boolean_failures':ops['failures'],'full_latest_contract':'not_passed_unless_all_errors_resolved_and_intersection_report_passed','candidate_only':True}
(W/'fixed_layout_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('FIXED_LAYOUT_QA',json.dumps({k:report[k] for k in ['passed','checks','components','instances','uv_faces_checked','expanded_triangles','expanded_polygons']},ensure_ascii=False),flush=True)
