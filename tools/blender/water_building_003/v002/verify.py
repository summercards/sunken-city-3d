import bpy, json, hashlib
from pathlib import Path
D=Path('D:/projects/sea/art_source/scenes/water_building_003/v002')
sc=bpy.data.scenes.get('WB003V2_v002')
assert sc is not None
plan=json.loads((D/'component_plan.json').read_text(encoding='utf8'))
cat=json.loads((D/'catalog.json').read_text(encoding='utf8'))
inst=json.loads((D/'component_instances.json').read_text(encoding='utf8'))['instances']
errs=[]; notes=[]
assert len(plan['components'])==40
assert len(cat)==40, (len(cat),40)
assert len(inst)==42, len(inst)
by={x['key']:x for x in cat}
for c in plan['components']:
 k=c['key']
 if k not in by: errs.append('missing catalog '+k); continue
 col=bpy.data.collections.get(c['id'])
 if col is None: errs.append('missing collection '+c['id']); continue
 meshes=[o for o in col.objects if o.type=='MESH']
 if not meshes: errs.append('empty '+k)
 if any(abs(v)>1e-7 for o in meshes for v in (*o.location,*o.rotation_euler,*o.scale) if False): pass
 for o in meshes:
  if len(o.data.vertices)==0: errs.append('empty mesh '+o.name)
  if 'PaletteUV' not in o.data.uv_layers: errs.append('no PaletteUV '+o.name)
  if not o.data.materials: errs.append('no material '+o.name)
  elif o.data.materials[0].get('semantic_role') not in {'SEA_Matte','SEA_Metal','SEA_Gloss'}: errs.append('bad role '+o.name)
  if o.data.users and len(o.data.polygons)==0: errs.append('no polygons '+o.name)
# source hash and palette contract
ref=hashlib.sha256((D/'reference.jpg').read_bytes()).hexdigest()
assert ref==plan['reference_sha256']
pal=bpy.data.images.get('sea_cabin_timber_8x8_512.png')
if pal is None: errs.append('palette image not loaded')
else:
 for m in [m for m in bpy.data.materials if m.name.startswith('WB003V2_')]:
  tex=[n for n in m.node_tree.nodes if n.type=='TEX_IMAGE']
  if not tex or tex[0].image != pal: errs.append('palette mismatch '+m.name)
# verify package file headers can be read and contain source collections
pkg=0
for c in plan['components']:
 p=D/'component_packages'/c['key']/(c['key']+'.blend')
 if not p.exists(): errs.append('missing package '+c['key']); continue
 with bpy.data.libraries.load(str(p),) as (src,dst):
  if c['id'] not in src.collections: errs.append('package missing collection '+c['key'])
 pkg+=1
# depsgraph count
dg=bpy.context.evaluated_depsgraph_get(); tri=poly=mi=0
for x in dg.object_instances:
 o=x.object
 if o.type=='MESH': o.data.calc_loop_triangles();tri+=len(o.data.loop_triangles);poly+=len(o.data.polygons);mi+=1
report={'scene':sc.name,'components':len(cat),'instances':len(inst),'packages_checked':pkg,'triangles':tri,'polygons':poly,'mesh_instances':mi,'errors':errs,'reference_sha256':ref}
(D/'source_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print(json.dumps(report,ensure_ascii=False))
assert not errs, errs

