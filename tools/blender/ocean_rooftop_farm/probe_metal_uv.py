import bpy
for o in bpy.data.objects:
 if o.type=='MESH' and any(m and 'Metal' in m.name for m in o.data.materials):
  u=o.data.uv_layers.get('PaletteUV')
  if u: print(o.name,[(round(x.uv.x,3),round(x.uv.y,3)) for x in u.data[:8]])
