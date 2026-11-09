"""Independent read-only tests of actual saved socket residuals and mating gaps."""
import bpy,json,hashlib,math,os
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
R=Path('D:/projects/sea');D=R/'art_source/scenes/bld_20261109_a/v003';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'bld_20261109_a/v003';S=D/'bld_20261109_a_v003.blend';assert bpy.app.background
sha=hashlib.sha256(S.read_bytes()).hexdigest();w=json.loads((W/'geometry_witness.json').read_text(encoding='utf-8'));assert w['source_sha256']==sha
bpy.ops.wm.open_mainfile(filepath=str(S),load_ui=False,use_scripts=False)
sc=bpy.context.scene;cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components'];byobj={x['object']:x for x in w['objects']};trees={};triangles={};tests=0;errors=[];records=[]
def tree(o):
 if o.name not in trees:
  me=o.data;me.calc_loop_triangles();vs=[v.co.copy() for v in me.vertices];fs=[tuple(t.vertices) for t in me.loop_triangles];trees[o.name]=BVHTree.FromPolygons(vs,fs,all_triangles=True,epsilon=1e-7)
 return trees[o.name]
def inside(tr,p):
 # Non-axis ray with deterministic jitter avoids edge/vertex double hits.
 direction=Vector((1.0,.371390676,.5298911)).normalized();origin=p.copy();hits=0
 for _ in range(80):
  q,n,i,d=tr.ray_cast(origin,direction,10000)
  if q is None:break
  hits+=1;origin=q+direction*.00001
 return hits%2==1
for ix,cut in enumerate(w['cuts']):
 o=bpy.data.objects.get(cut['host_object']);rec={'cut_index':ix,'host_object':cut['host_object'],'samples':0,'inside_failures':0}
 if o is None:errors.append('missing cut host '+cut['host_object']);continue
 if o.name not in byobj:errors.append('missing rebase witness '+o.name);continue
 shift=Vector(byobj[o.name]['rebase']);lo=Vector(cut['bounds_min'])-shift;hi=Vector(cut['bounds_max'])-shift;tr=tree(o)
 for tx in [.2,.5,.8]:
  for ty in [.2,.5,.8]:
   for tz in [.2,.5,.8]:
    p=Vector([lo[j]+(hi[j]-lo[j])*t for j,t in enumerate((tx,ty,tz))]);tests+=1;rec['samples']+=1
    if inside(tr,p):rec['inside_failures']+=1
 if rec['inside_failures']:
  # Open/non-manifold remnants can give odd ray parity even when the cutter
  # intersection is empty. Resolve ambiguity using exact mesh intersection volume.
  import bmesh
  scratch=bpy.data.collections.get('SLOT_PROBE_SCRATCH')
  if scratch is None:scratch=bpy.data.collections.new('SLOT_PROBE_SCRATCH');sc.collection.children.link(scratch)
  cp=bpy.data.objects.new('probe_intersection_host',o.data.copy());scratch.objects.link(cp)
  x,y,z=(lo+hi)/2;dx,dy,dz=(hi-lo)/2;vs=[(x+a*dx,y+b*dy,z+c*dz) for a,b,c in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
  me=bpy.data.meshes.new('probe_box');me.from_pydata(vs,[],[(3,2,1,0),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]);me.update();cu=bpy.data.objects.new('probe_box',me);scratch.objects.link(cu)
  mo=cp.modifiers.new('probe_exact','BOOLEAN');mo.operation='INTERSECT';mo.solver='EXACT';mo.object=cu
  dg=bpy.context.evaluated_depsgraph_get();dg.update();evalob=cp.evaluated_get(dg);ev=evalob.to_mesh();bm=bmesh.new();bm.from_mesh(ev);iv=abs(bm.calc_volume(signed=True));bm.free();evalob.to_mesh_clear();rec['exact_intersection_volume_m3']=iv;rec['ray_parity_ambiguity_resolved']=iv<1e-8
  if iv>=1e-8:errors.append('actual solid residue '+str(ix)+' '+o.name+' volume='+str(iv))
  bpy.data.objects.remove(cp,do_unlink=True);bpy.data.objects.remove(cu,do_unlink=True)
 records.append(rec)
# All actual attached instance pairs get a triangle-intersection test, in addition
# to the projected clearance test. This scope is explicit: not every global pair.
world_cache={}
def world_tree(inst):
 if inst.name not in world_cache:
  verts=[];faces=[]
  for o in inst.instance_collection.objects:
   me=o.data;me.calc_loop_triangles();offset=len(verts);verts.extend(inst.matrix_world@v.co for v in me.vertices);faces.extend(tuple(offset+i for i in t.vertices) for t in me.loop_triangles)
  world_cache[inst.name]=BVHTree.FromPolygons(verts,faces,all_triangles=True,epsilon=0)
 return world_cache[inst.name]
def bounds(inst):
 pts=[inst.matrix_world@v.co for o in inst.instance_collection.objects for v in o.data.vertices];return Vector([min(v[j] for v in pts) for j in range(3)]),Vector([max(v[j] for v in pts) for j in range(3)])
contact_results=[]
for c in w['contacts']:
 a=sc.objects[c['child_instance']];b=sc.objects[c['host_instance']];overlaps=world_tree(a).overlap(world_tree(b));rec={'a':a.name,'b':b.name,'relation':c['relation'],'triangle_intersection_pairs':len(overlaps)}
 if overlaps:errors.append('attached triangles intersect '+a.name+' '+b.name+' '+str(len(overlaps)))
 if c['relation']=='clearance':
  al,ah=bounds(a);bl,bh=bounds(b);i=c['axis'];gap=al[i]-bh[i] if c['direction']>0 else bl[i]-ah[i];rec['actual_gap_m']=gap;tests+=1
  if not (.002-1e-5<=gap<=.020+1e-5 and abs(gap-c['gap_m'])<1e-5):errors.append('gap mismatch '+a.name+' '+str(gap))
 contact_results.append(rec)
report={'passed':not errors,'source_sha256':sha,'checked_cutters':len(w['cuts']),'slot_interior_samples':tests,'errors':errors,'cuts':records,'contacts':contact_results,'scope':'saved_mesh_cutters_and_all_declared_attached_instance_pairs','all_scene_intersections_exhaustive':False,'global_unregistered_contacts':'pending'}
assert hashlib.sha256(S.read_bytes()).hexdigest()==sha
(W/'slot_probe_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('SLOT_PROBE',json.dumps({k:report[k] for k in ['passed','checked_cutters','slot_interior_samples','errors']},ensure_ascii=False),flush=True)
raise SystemExit(0 if report['passed'] else 1)
