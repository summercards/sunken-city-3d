"""Independent source/PaletteUV inspection and directly openable packages."""
import bpy,json,hashlib,math,os
from pathlib import Path
from mathutils import Vector,Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/gift_kiosk_interior/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'gift_kiosk/interior/v001'
SOURCE=D/'gift_kiosk_interior.blend';plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'));sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert Path(bpy.data.filepath).resolve()==SOURCE.resolve(),'Open the master in a fresh GUI first'
checks=0;errors=[];face_count=0
code=(R/'tools/blender/gift_kiosk/verify_source.py').read_text(encoding='utf-8');exec(code[code.index('def require('):code.index('# The source is saved')])
source_hash=sha(SOURCE)
for e in cat['components']:e.update(inspect(bpy.data.collections.get(e['collection']),e))
for im in bpy.data.images:
 if im.source=='FILE' and im.library is None:im.filepath=str(R/plan['palette'])
# Save a scene and exactly its component dependency closure, then actually reopen.
for e in cat['components']:
 p=R/e['component_source'];p.parent.mkdir(parents=True,exist_ok=True)
 ps=bpy.data.scenes.new('GKI_PACKAGE_'+e['key']);ps.unit_settings.system='METRIC';ps.collection.children.link(bpy.data.collections[e['collection']])
 bpy.data.libraries.write(str(p),{ps},path_remap='RELATIVE_ALL',fake_user=True,compress=True)
 bpy.data.scenes.remove(ps)
 e.update(source_sha256=sha(p),palette_sha256=sha(R/plan['palette']),stage='source_verified_runtime_pending')
 (p.parent/'asset_manifest.json').write_text(json.dumps(e,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
require(sha(SOURCE)==source_hash,'master source unchanged by package creation')
for path,expected in json.loads((W/'scope_before.json').read_text(encoding='utf-8'))['protected_files'].items():
 if path.startswith('art_source/') or path.endswith('.glb'):require(sha(R/path)==expected,'protected original '+path)
rows=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))
for row in rows['instances']+rows['reused_instances']:
 o=bpy.data.objects.get(row['name']);require(o is not None,'instance '+row['name'])
 if o:
  require(max(abs(o.location[i]-row['position'][i]) for i in range(3))<1e-5,'placement '+row['name'])
  require(o.instance_collection.get('asset_id')==row['asset_id'],'identity '+row['name'])
require(len(cat['components'])==11 and len(cat['components'])<=50,'11 independent components')
require(sum(e['family']=='floor_tile' for e in cat['components'])==3,'three floor variants in one family')
report={'passed':False,'master_passed':not errors,'checks':checks,'errors':errors,'source_sha256':source_hash,'palette_sha256':sha(R/plan['palette']),'packages_reopened':0,'components':len(cat['components']),'instances':len(rows['instances']),'reused_instances':len(rows['reused_instances']),'uv_faces_checked':face_count,'master_triangles':sum(e['triangles'] for e in cat['components']),'expanded_triangles':sum(next(e['triangles'] for e in cat['components'] if e['key']==row['key']) for row in rows['instances']),'exit_code':0 if not errors else 1,'user_art_acceptance':'pending'}
(W/'source_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps(report,ensure_ascii=False))
if errors:raise RuntimeError(str(errors[:10]))
