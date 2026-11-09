import bpy, json
from pathlib import Path
S=Path('D:/projects/sea/art_source/scenes/bld_20261109_a/v003/bld_20261109_a_v003.blend')
bpy.ops.wm.open_mainfile(filepath=str(S), load_ui=False)
sc=bpy.context.scene
rows=[]
for c in bpy.data.collections:
    if c.name.startswith('SEA-SCENE-B1109A'):
        obs=[o for o in c.all_objects if o.type=='MESH']
        rows.append({'name':c.name,'objects':len(obs),'tris':sum((o.data.calc_loop_triangles() or len(o.data.loop_triangles)) for o in obs),'linked_to_scene':any(c in root.children_recursive for root in bpy.data.scenes[0].collection.children)})
print(json.dumps({'file':bpy.data.filepath,'scene':sc.name,'objects':len(bpy.data.objects),'collections':rows,'top':[c.name for c in sc.collection.children]},ensure_ascii=False,indent=2))
