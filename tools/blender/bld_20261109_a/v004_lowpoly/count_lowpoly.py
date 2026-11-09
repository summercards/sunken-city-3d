import bpy,json,hashlib
from pathlib import Path
from collections import Counter
R=Path('D:/projects/sea'); D=R/'art_source/scenes/bld_20261109_a/v004_lowpoly'; S=D/'bld_20261109_a_v004_lowpoly.blend'; V3=R/'art_source/scenes/bld_20261109_a/v003'
bpy.ops.wm.open_mainfile(filepath=str(S),load_ui=False)
plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'))
cat=[]
c3=json.loads((V3/'catalog.json').read_text(encoding='utf-8'))['components']
for e in c3:
    c=bpy.data.collections.get(e['collection'])
    if c is None: raise RuntimeError('missing collection '+e['collection'])
    obs=[o for o in c.all_objects if o.type=='MESH']
    tris=polys=verts=0
    for o in obs:
        o.data.calc_loop_triangles(); tris+=len(o.data.loop_triangles); polys+=len(o.data.polygons); verts+=len(o.data.vertices)
    cat.append({'collection':c.name,'key':e['key'],'objects':len(obs),'triangles':tris,'polygons':polys,'vertices':verts,'hide_render':c.hide_render})
inst=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))['instances']
lookup={x['collection']:x for x in cat}
key_by_col={x['collection']:x['key'] for x in c3}
weighted=[]
for x in inst:
    col='SEA-SCENE-B1109A-'+key_by_col.get(next((q['collection'] for q in c3 if q['key']==x['key']),''),'').upper().replace('_','-')
    # actual component collection is stable asset_id, map by key directly
    e=next(q for q in c3 if q['key']==x['key']); row=next((q for q in cat if q['collection']==e['collection']),None)
    if row: weighted.append({'name':x['name'],'key':x['key'],'triangles':row['triangles'],'polygons':row['polygons']})
result={'source_sha256':hashlib.sha256(S.read_bytes()).hexdigest(),'components':len(cat),'instances':len(inst),'master_triangles':sum(x['triangles'] for x in cat),'master_polygons':sum(x['polygons'] for x in cat),'expanded_triangles':sum(x['triangles'] for x in weighted),'expanded_polygons':sum(x['polygons'] for x in weighted),'expanded_vertices':sum(next(q['vertices'] for q in cat if q['collection']==next(e['collection'] for e in c3 if e['key']==x['key'])) for x in inst),'component_rows':cat,'weighted':weighted}
(D/'lowpoly_face_count.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:result[k] for k in ['source_sha256','components','instances','master_triangles','master_polygons','expanded_triangles','expanded_polygons','expanded_vertices']},ensure_ascii=False,indent=2))
