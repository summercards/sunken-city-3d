import bpy
from pathlib import Path
from mathutils import Vector
D=Path(r'D:/projects/sea/art_source/scenes/liberty_lighthouse/v001')
for c in bpy.data.collections:
 if c.name.startswith('SEA-SCENE-LHL-'):
  print(c.name,len(c.objects),[(o.name,o.type,len(o.data.vertices) if o.type=='MESH' else 0) for o in c.objects])
