import bpy,json
from pathlib import Path
P=Path('D:/projects/sea/godot/assets/models/facilities/water_building_001/water_building_001.glb')
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(P))
obs=[o for o in bpy.context.scene.objects if o.type=='MESH'];mats={}
for o in obs:
 for m in o.data.materials:
  if m: mats[m.name]=list(m.diffuse_color)
print(json.dumps({'objects':len(obs),'tris':sum((o.data.calc_loop_triangles() or len(o.data.loop_triangles)) for o in obs),'materials':mats,'images':len(bpy.data.images)},ensure_ascii=False,indent=2))
