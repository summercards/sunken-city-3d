import bpy,json
from pathlib import Path
from mathutils import Vector
D=Path(r'D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v001')
sc=bpy.data.scenes['海上屋顶农场_制作与装配_v001']
deps=bpy.context.evaluated_depsgraph_get()
for key in ['roof_deck_01','water_tank_01','facade_weathering_01']:
 o=sc.objects[key];pts=[]
 for m in o.instance_collection.objects:
  if m.type=='MESH':
   ev=m.evaluated_get(deps);me=ev.to_mesh();pts.extend(o.matrix_world@m.matrix_local@v.co for v in me.vertices);ev.to_mesh_clear()
 print(key,'bounds',[min(v[i] for v in pts) for i in range(3)]+[max(v[i] for v in pts) for i in range(3)],'scale',list(o.scale))
 for m in o.instance_collection.objects:
  if m.type=='MESH':
   ps=[m.matrix_world@v.co for v in m.data.vertices]
   print(' PART',m.name,[min(v[i] for v in ps) for i in range(3)]+[max(v[i] for v in ps) for i in range(3)],'loc',list(m.location))
print('COUNTS',json.dumps({k:sum(i['key']==k for i in json.loads((D/'component_instances.json').read_text())['instances']) for k in ['facade_window','broken_window','balcony','floor_slab']}))
