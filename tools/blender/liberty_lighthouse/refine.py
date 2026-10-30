import bpy,json
from pathlib import Path
from mathutils import Vector
R=Path(r'D:/projects/sea');D=R/'art_source/scenes/liberty_lighthouse/v001';W=R/'sea-work/liberty_lighthouse'
sc=bpy.data.scenes['巨手灯塔_参考装配'];bpy.context.window.scene=sc
rows=json.loads((D/'component_instances.json').read_text())['instances']
for row in rows:
 o=bpy.data.objects[row['name']]
 pts=[]
 for m in o.instance_collection.objects:
  if m.type=='MESH':pts += [o.matrix_world@m.matrix_local@v.co for v in m.data.vertices]
 if row['key'] in ['arm','column','finger','thumb','platform','barge','shop_shell']:
  print(row['name'],[round(min(v[i] for v in pts),3) for i in range(3)],[round(max(v[i] for v in pts),3) for i in range(3)])
print('collections',len([c for c in bpy.data.collections if c.name.startswith('SEA-SCENE-LHL-')]))
print('images',[(i.name,i.filepath) for i in bpy.data.images if i.source=='FILE'])
