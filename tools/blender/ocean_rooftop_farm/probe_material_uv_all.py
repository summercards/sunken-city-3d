import bpy
seen=set()
for o in bpy.data.objects:
 if o.type!='MESH': continue
 mats=[m for m in o.data.materials if m]
 if not mats: continue
 for m in mats:
  if any(x in m.name for x in ['Matte','Metal']):
   u=o.data.uv_layers.get('PaletteUV')
   if not u: continue
   key=m.name
   if key in seen: continue
   seen.add(key)
   print('MAT',key,'OBJ',o.name,'UV',[(round(x.uv.x,4),round(x.uv.y,4)) for x in u.data[:12]])
