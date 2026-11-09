import bpy,json,hashlib,sys
from pathlib import Path
R=Path('D:/projects/sea');D=R/'art_source/scenes/bld_20261109_a/v004_lowpoly';W=R.parent/'sea-work/bld_20261109_a/v004_lowpoly';S=D/'bld_20261109_a_v004_lowpoly.blend';cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components'];inst=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))['instances'];errors=[];package_results=[]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
source_sha=sha(S)
for e in cat:
 p=R/e['component_source']
 if not p.is_file():errors.append('missing '+str(p));continue
 try:
  bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.wm.open_mainfile(filepath=str(p),load_ui=False)
  sc=bpy.context.scene
  obs=[o for o in bpy.data.collections[0].all_objects if o.type=='MESH'] if bpy.data.collections else []
  tris=polys=0
  for o in obs:o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles);polys+=len(o.data.polygons)
  ok=(tris==e['triangles'] and polys==e['polygons'] and sc.get('source_version')=='v004_lowpoly' and sc.get('lowpoly') is True)
  if not ok:errors.append(f"package {e['key']} count/meta mismatch {tris}/{polys}")
  package_results.append({'key':e['key'],'path':str(p),'sha256':sha(p),'triangles':tris,'polygons':polys,'passed':ok})
 except Exception as ex:errors.append(f"package {e['key']} {type(ex).__name__}: {ex}")
# Reopen source and count every component collection and weighted instances.
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.wm.open_mainfile(filepath=str(S),load_ui=False)
master_tri=master_poly=0;rows=[]
for e in cat:
 c=bpy.data.collections.get(e['collection'])
 if c is None:errors.append('source missing '+e['collection']);continue
 tris=polys=0
 for o in c.all_objects:
  if o.type!='MESH':continue
  o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles);polys+=len(o.data.polygons)
 if tris!=e['triangles'] or polys!=e['polygons']:errors.append(f"catalog mismatch {e['key']} {tris}/{polys} vs {e['triangles']}/{e['polygons']}")
 master_tri+=tris;master_poly+=polys;rows.append({'key':e['key'],'triangles':tris,'polygons':polys})
weighted=sum(next(x['triangles'] for x in rows if x['key']==i['key']) for i in inst);weighted_poly=sum(next(x['polygons'] for x in rows if x['key']==i['key']) for i in inst)
result={'passed':not errors and weighted<=11000 and weighted>=8500,'source_sha256':source_sha,'components':len(cat),'instances':len(inst),'packages_reopened':len(package_results),'package_passed':sum(x['passed'] for x in package_results),'master_triangles':master_tri,'master_polygons':master_poly,'expanded_triangles':weighted,'expanded_polygons':weighted_poly,'budget_range':[8500,11000],'errors':errors,'package_results':package_results,'note':'derivative candidate; not registered as replacement and not Godot integrated'}
(W/'lowpoly_verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps({k:result[k] for k in ['passed','source_sha256','components','instances','packages_reopened','package_passed','master_triangles','expanded_triangles','expanded_polygons','errors']},ensure_ascii=False));sys.exit(0 if result['passed'] else 2)
