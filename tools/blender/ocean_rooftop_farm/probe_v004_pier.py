import bpy
for c in bpy.data.collections:
 if 'pier' in c.name.lower():
  print('COL',c.name)
  for o in c.objects:
   print('OBJ',o.name,o.type,'loc',tuple(round(x,3) for x in o.location),'dim',tuple(round(x,3) for x in o.dimensions),'verts',len(o.data.vertices) if o.type=='MESH' else 0,'hide',o.hide_viewport,o.hide_render)
   if o.type=='MESH':
    print('  bounds',[(round(v,3)) for v in o.dimensions], 'mats',[m.name if m else None for m in o.data.materials])
for c in bpy.data.collections:
 if 'stair_flight' in c.name.lower() or 'landing' in c.name.lower():
  print('STAIRCOL',c.name)
  for o in c.objects: print(' SOBJ',o.name,o.type,'dim',tuple(round(x,3) for x in o.dimensions),'hide',o.hide_viewport,o.hide_render)
