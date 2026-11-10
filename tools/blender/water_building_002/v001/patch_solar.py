import bpy,json,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/water_building_002/v001';W=R.parent/'sea-work/water_building_002/v001';S=D/'water_building_002_v001.blend'
bpy.ops.wm.open_mainfile(filepath=str(S),load_ui=False)
col=next(c for c in bpy.data.collections if c.name.endswith('SOLAR-PANEL'))
# Lift the panels above the roof so the key reference cue reads in the camera.
for o in col.all_objects:
    if o.type=='MESH':
        o.data.transform(Matrix.Translation(Vector((0,0,.28))))
        o['roof_clearance_m']=.28
col['solar_panel_cue']='raised_above_roof;dark_blue_palette_cell;lowpoly_no_dense_grid'
# Update catalog geometry signature and plan evidence without changing instance layout.
cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components']
for e in cat:
    if e['key']!='solar_panel':continue
    h=hashlib.sha256();tris=polys=0
    for o in col.all_objects:
        if o.type!='MESH':continue
        o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles);polys+=len(o.data.polygons)
        for v in o.data.vertices:h.update((','.join(format(float(x),'.6f') for x in v.co)+';').encode())
    e['triangles']=tris;e['polygons']=polys;e['geometry_fingerprint']=h.hexdigest();e['roof_clearance_m']=.28
(D/'catalog.json').write_text(json.dumps({'schema':'sea.component_catalog','components':cat},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
sc=bpy.context.scene;sc.render.filepath=str(W/'hero_002.png');bpy.ops.wm.save_as_mainfile(filepath=str(S),compress=True);bpy.ops.render.render(write_still=True);print(json.dumps({'solar_raised':True,'source_sha256':hashlib.sha256(S.read_bytes()).hexdigest()},ensure_ascii=False))
