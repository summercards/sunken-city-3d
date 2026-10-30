import bpy
from pathlib import Path
D=Path(r'D:/projects/sea/art_source/scenes/liberty_lighthouse/v001')
for o in bpy.data.objects:
 if o.type=='MESH' and o.name=='商铺后墙':
  print('mesh',o.name,[(u.name,u.active_render) for u in o.data.uv_layers],o.data.uv_layers.active.name,o.data.uv_layers.active==o.data.uv_layers.get('PaletteUV'))
