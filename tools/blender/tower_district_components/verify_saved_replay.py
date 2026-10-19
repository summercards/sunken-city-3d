import bpy,json
from pathlib import Path
from mathutils import Vector
ROOT=Path('/Users/summercards/WorkBuddy/sea');LIB=ROOT/'art_source/environments/tower_zones/tower_district/source/common_components/v008';QA=ROOT/'outputs/tower_district/component_migration_v008/qa'
doc=json.loads((LIB/'component_instances.json').read_text());report=json.loads((QA/'library_verification.json').read_text())
a=bpy.data.scenes['TD_组件实例街区_v008'];b=bpy.data.scenes['TD_JSON重放验收_v008']
frames=[];bb={}
for frame in [1,61,121,181,241]:
 matrices=[]
 for sc,prefix in [(a,''),(b,'JSON_')]:
  bpy.context.window.scene=sc;sc.frame_set(frame);bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get();dg.update()
  mats={r['instance_id']:bpy.data.objects[prefix+r['instance_id']].evaluated_get(dg).matrix_world.copy() for r in doc['instances']};matrices.append(mats)
  if frame==1:
   lo=[float('inf')]*3;hi=[float('-inf')]*3
   for r in doc['instances']:
    ob=bpy.data.objects[prefix+r['instance_id']]
    for child in ob.instance_collection.objects:
     if child.type!='MESH':continue
     for p in child.bound_box:
      v=mats[r['instance_id']]@child.matrix_local@Vector(p)
      for i in range(3):lo[i]=min(lo[i],v[i]);hi[i]=max(hi[i],v[i])
   bb[sc.name]=[lo,hi]
 err=max(abs(matrices[0][n][i][j]-matrices[1][n][i][j]) for n in matrices[0] for i in range(4) for j in range(4));frames.append({'frame':frame,'matrix_max_error':err})
report['json_replay_frames']=frames;report['bbox_original_layout']=bb[a.name];report['bbox_json_replay']=bb[b.name];report['bbox_max_error_m']=max(abs(bb[a.name][i][j]-bb[b.name][i][j]) for i in range(2) for j in range(3));report['independent_reopen_for_replay_verification']=True
report['issues']=[x for x in report['issues'] if x not in ['JSON replay transform error','JSON replay bbox mismatch']]
if max(f['matrix_max_error'] for f in frames)>1e-4:report['issues'].append('JSON replay transform error')
if report['bbox_max_error_m']>1e-4:report['issues'].append('JSON replay bbox mismatch')
report['pass']=not report['issues'];(QA/'library_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print('INDEPENDENT_REPLAY_CHECK '+json.dumps({'pass':report['pass'],'frames':frames,'bbox_error':report['bbox_max_error_m'],'issues':report['issues']},ensure_ascii=False),flush=True)
assert report['pass']
