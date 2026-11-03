import bpy
print('FILE',bpy.data.filepath)
for c in bpy.data.collections:
 if 'pier' in c.name.lower() or c.name.startswith('02_游戏输出'):
  print('COL',c.name,'objs',[(o.name,o.type,tuple(round(x,2) for x in o.dimensions)) for o in c.objects], 'children',[x.name for x in c.children])
