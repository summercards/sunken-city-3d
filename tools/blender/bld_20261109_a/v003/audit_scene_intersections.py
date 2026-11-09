"""Read-only broadphase + triangle audit of all visible source mesh occurrences.
Scope deliberately includes within-component contacts. Coplanar/containment proof
is not implied by a negative surface intersection result.
"""
import bpy,json,hashlib,os,time
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
R=Path('D:/projects/sea');D=R/'art_source/scenes/bld_20261109_a/v003';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'bld_20261109_a/v003';S=D/'bld_20261109_a_v003.blend'
assert bpy.app.background;before=hashlib.sha256(S.read_bytes()).hexdigest();bpy.ops.wm.open_mainfile(filepath=str(S),load_ui=False,use_scripts=False);sc=bpy.context.scene;cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components'];bycol={e['collection']:e['key'] for e in cat}
occ=[];trees={};intersections=[];candidates=0;excluded=0;start=time.perf_counter()
for inst in sc.objects:
 if inst.instance_type!='COLLECTION' or inst.hide_render or not inst.instance_collection or inst.instance_collection.name not in bycol:continue
 for ob in inst.instance_collection.objects:
  if ob.type!='MESH' or ob.hide_render:continue
  mat=inst.matrix_world@ob.matrix_world;pts=[mat@v.co for v in ob.data.vertices];lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
  occ.append({'instance':inst.name,'key':bycol[inst.instance_collection.name],'object':ob.name,'matrix':mat,'ob':ob,'lo':lo,'hi':hi})
def tree(i):
 if i not in trees:
  x=occ[i];me=x['ob'].data;me.calc_loop_triangles();vs=[x['matrix']@v.co for v in me.vertices];fs=[tuple(t.vertices) for t in me.loop_triangles];trees[i]=BVHTree.FromPolygons(vs,fs,all_triangles=True,epsilon=0)
 return trees[i]
for i,a in enumerate(occ):
 for j in range(i+1,len(occ)):
  b=occ[j];depth=[min(a['hi'][k],b['hi'][k])-max(a['lo'][k],b['lo'][k]) for k in range(3)]
  # Reject separated bounds. Include nearly coplanar candidates, but label uncertainty.
  if min(depth)<-1e-6:continue
  candidates+=1;hits=tree(i).overlap(tree(j))
  if hits:
   intersections.append({'a':{'instance':a['instance'],'key':a['key'],'object':a['object']},'b':{'instance':b['instance'],'key':b['key'],'object':b['object']},'triangle_pair_count':len(hits),'aabb_overlap_depth_m':depth,'within_same_component_instance':a['instance']==b['instance']})
from collections import Counter
categories=Counter(tuple(sorted((x['a']['key'],x['b']['key']))) for x in intersections)
report={'passed':not intersections,'source_sha256':before,'mesh_occurrences':len(occ),'total_pairs':len(occ)*(len(occ)-1)//2,'broadphase_candidates':candidates,'intersecting_mesh_pairs':len(intersections),'triangle_intersection_pairs':sum(x['triangle_pair_count'] for x in intersections),'by_component_pair':[{'keys':list(k),'pairs':v} for k,v in categories.most_common()],'intersections':intersections,'scope':'all_visible_mesh_occurrence_pairs_including_internal_component_pairs','containment_and_exact_coplanar_all_pairs':'not_proven','elapsed_s':time.perf_counter()-start,'conclusion':'known_surface_intersections_remaining' if intersections else 'surface_intersection_audit_clear_containment_coplanarity_pending'}
assert hashlib.sha256(S.read_bytes()).hexdigest()==before
(W/'scene_intersections.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('ALL_SCENE_INTERSECTION_AUDIT',json.dumps({k:report[k] for k in ['passed','mesh_occurrences','total_pairs','broadphase_candidates','intersecting_mesh_pairs','elapsed_s']},ensure_ascii=False),flush=True)
