"""Independently fit latest-rule taper in saved pre-joint checkpoint.
Checkpoint bounds have not been welded/boolean changed, so vertex IDs are stable.
"""
import bpy,json,hashlib,math
from pathlib import Path
from mathutils import Vector
R=Path('D:/projects/sea');W=Path('D:/projects/sea-work/bld_20261109_a/v003');path=W/'pre_joint_geometry.blend';ops=json.loads((W/'fixed_layout_operations.json').read_text(encoding='utf-8'));assert bpy.app.background;assert hashlib.sha256(path.read_bytes()).hexdigest()==ops['pre_joint_geometry_sha256'];bpy.ops.wm.open_mainfile(filepath=str(path),load_ui=False,use_scripts=False);records=[];errors=[]
for w in ops['taper_witnesses']:
 o=bpy.data.objects.get(w['object']);rec={'key':w['key'],'object':w['object'],'passed':False}
 if not o:errors.append('missing '+w['object']);records.append(rec);continue
 ai=w['axis'];ctr=Vector(w['center']);num=den=0;maxaxis=0
 for s in w['samples']:
  if s['i']>=len(o.data.vertices):errors.append('bad index '+o.name);continue
  before=Vector(s['before']);after=o.data.vertices[s['i']].co;maxaxis=max(maxaxis,abs(before[ai]-after[ai]))
  for j in range(3):
   if j==ai:continue
   d=s['t']*(before[j]-ctr[j]);num+=d*(before[j]-after[j]);den+=d*d
 fit=num/den if den else None;passed=fit is not None and abs(fit-w['rho'])<1e-4 and .01-1e-6<=abs(fit)<=.10+1e-6 and maxaxis<1e-5 and ai==max(range(3),key=lambda i:w['extent'][i]);rec.update(passed=passed,requested_rho=w['rho'],fitted_rho=fit,taper_along='xyz'[ai],max_longitudinal_error_m=maxaxis)
 if not passed:errors.append('fit fail '+o.name)
 records.append(rec)
report={'passed':not errors,'pre_joint_geometry_sha256':ops['pre_joint_geometry_sha256'],'final_source_sha256':ops['source_sha256'],'checkpoint':'before_exact_mesh_joints','checked_meshes':len(records),'errors':errors,'records':records,'post_boolean_final_surface_regression':'requires section projection; do not reuse old vertex IDs'}
(W/'fixed_form_regression.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('FIXED_FORM_FIT',report['passed'],len(records),len(errors))
