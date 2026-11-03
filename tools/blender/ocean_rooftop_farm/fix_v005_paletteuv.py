import bpy, json
from mathutils import Vector
SRC='D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v005/ocean_rooftop_farm_v005.blend'
for name in ['ORF5_柱体大块崩缺_p0','ORF5_柱体大块崩缺_p1','ORF5_柱体大块崩缺_p2','ORF5_柱体大块崩缺_p3','ORF5_柱体大块崩缺_p4','ORF5_柱体大块崩缺_p5','ORF5_柱体崩口内里_p0','ORF5_柱体崩口内里_p1','ORF5_柱体崩口内里_p2','ORF5_柱体崩口内里_p3','ORF5_柱体崩口内里_p4','ORF5_柱体崩口内里_p5']:
 o=bpy.data.objects.get(name)
 if not o or o.type!='MESH': continue
 me=o.data
 src=me.uv_layers.get('UV贴图') or (me.uv_layers[0] if me.uv_layers else None)
 pal=me.uv_layers.get('PaletteUV') or me.uv_layers.new(name='PaletteUV')
 # Put each face's UV island in a safe inner band of one shared palette cell.
 # Concrete uses the same cell as the authored pier; exposed inner material uses a cool dark cell.
 metal=any(m and 'Metal' in m.name for m in me.materials)
 x0,x1=(0.65625,0.71875) if not metal else (0.28125,0.34375)
 y0,y1=(0.03125,0.09375)
 if src:
  for poly in me.polygons:
   for li in poly.loop_indices:
    uv=src.data[li].uv
    u=x0+(float(uv.x)%1.0)*(x1-x0)
    v=y0+(float(uv.y)%1.0)*(y1-y0)
    pal.data[li].uv=(u,v)
 me.uv_layers.active=pal
 me.uv_layers.active_index=me.uv_layers.find('PaletteUV')
 me.uv_layers[me.uv_layers.active_index].name='PaletteUV'
print(json.dumps({'fixed':12,'objects':[o.name for o in bpy.data.objects if o.name.startswith('ORF5_柱体')]} ,ensure_ascii=False))
bpy.ops.wm.save_as_mainfile(filepath=SRC)
