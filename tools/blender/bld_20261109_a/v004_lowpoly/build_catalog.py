import bpy,json,hashlib,os
from pathlib import Path
R=Path('D:/projects/sea'); V3=R/'art_source/scenes/bld_20261109_a/v003'; D=R/'art_source/scenes/bld_20261109_a/v004_lowpoly'; W=R.parent/'sea-work/bld_20261109_a/v004_lowpoly'; S=D/'bld_20261109_a_v004_lowpoly.blend'
bpy.ops.wm.open_mainfile(filepath=str(S),load_ui=False)
old=json.loads((V3/'catalog.json').read_text(encoding='utf-8'))['components']; new=[]
for e in old:
 c=bpy.data.collections.get(e['collection']); assert c is not None,e['collection']
 tris=polys=verts=0; meshes=[]; h=hashlib.sha256()
 for o in c.all_objects:
  if o.type!='MESH':continue
  o.data.calc_loop_triangles(); tris+=len(o.data.loop_triangles);polys+=len(o.data.polygons);verts+=len(o.data.vertices);meshes.append(o.name)
  for v in o.data.vertices:h.update((','.join(format(float(x),'.6f') for x in v.co)+';').encode())
 row=dict(e); row.update({'source_version':'v004_lowpoly','component_source':f'art_source/scenes/bld_20261109_a/v004_lowpoly/component_packages/{e["key"]}/{e["key"]}.blend','triangles':tris,'polygons':polys,'vertices':verts,'meshes':len(meshes),'mesh_names':meshes,'geometry_fingerprint':h.hexdigest(),'fingerprint_algorithm':'ordered_vertices_fixed6_sha256','lowpoly':True})
 new.append(row)
(D/'catalog.json').write_text(json.dumps({'schema':'sea.component_catalog','components':new},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'source_sha256':hashlib.sha256(S.read_bytes()).hexdigest(),'components':len(new),'master_triangles':sum(x['triangles'] for x in new),'master_polygons':sum(x['polygons'] for x in new)},ensure_ascii=False))
