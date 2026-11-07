"""Independent read-only geometry validation and normal startup-file packaging.
No new geometry is authored here. Avoid repeated GUI library-file reloads.
"""
import bpy,json,math,hashlib,os
from pathlib import Path
from mathutils import Vector,Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/gift_kiosk_interior/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'gift_kiosk/interior/v001';plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'));sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
checks=0;errors=[];face_count=0
code=(R/'tools/blender/gift_kiosk/verify_source.py').read_text(encoding='utf-8');exec(code[code.index('def require('):code.index('# The source is saved')])
for e in cat['components']:
 p=R/e['component_source'];bpy.ops.wm.open_mainfile(filepath=str(p))
 require(bpy.context.scene.name=='GKI_PACKAGE_'+e['key'],e['key']+' actual startup scene')
 require(len(bpy.context.scene.objects)==e['meshes'] and len(bpy.data.scenes)==1,e['key']+' only own geometry')
 inspect(bpy.data.collections.get(e['collection']),e)
 for im in bpy.data.images:
  if im.source=='FILE':im.filepath=bpy.path.relpath(str(R/plan['palette']),start=str(p.parent))
 bpy.context.preferences.filepaths.save_version=0
 bpy.ops.wm.save_as_mainfile(filepath=str(p),compress=True,relative_remap=False)
 bpy.ops.wm.open_mainfile(filepath=str(p));inspect(bpy.data.collections.get(e['collection']),e)
 e['source_sha256']=sha(p)
 (p.parent/'asset_manifest.json').write_text(json.dumps(e,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
report=json.loads((W/'source_verification.json').read_text(encoding='utf-8'));report['checks']+=checks;report['uv_faces_checked']+=face_count;report['errors']+=errors;report['packages_reopened']=len(cat['components']);report['passed']=report['master_passed'] and not report['errors'];report['exit_code']=0 if report['passed'] else 1
(W/'source_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('GKI_PACKAGES',json.dumps(report))
if not report['passed']:raise RuntimeError(str(report['errors'][:10]))
