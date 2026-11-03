import bpy,json
SRC='D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v005/ocean_rooftop_farm_v005.blend'
# Damage geometry belongs to the pier component local origin, not the whole-rooftop world layout.
# Reposition the six large void blocks around one reusable 3.1m pier.
locs={
 'p0':(-1.05,-0.78,12.0),
 'p1':(0.92,-0.78,23.0),
 'p2':(-0.82,-0.78,35.0),
 'p3':(1.05,-0.78,46.0),
 'p4':(-0.92,0.78,18.0),
 'p5':(0.78,0.78,40.0),
}
for key,loc in locs.items():
 a=bpy.data.objects.get('ORF5_柱体大块崩缺_'+key)
 b=bpy.data.objects.get('ORF5_柱体崩口内里_'+key)
 if a: a.location=loc
 if b: b.location=(loc[0],loc[1]-0.035,loc[2])
# Ensure PaletteUV exists and points at valid inner cells copied by semantic role.
for o in [x for x in bpy.data.objects if x.name.startswith('ORF5_柱体') and x.type=='MESH']:
 me=o.data; src=me.uv_layers.get('UV贴图') or (me.uv_layers[0] if me.uv_layers else None)
 pal=me.uv_layers.get('PaletteUV') or me.uv_layers.new(name='PaletteUV')
 metal=any(m and 'Metal' in m.name for m in me.materials)
 x0,x1=(0.4375,0.4625) if not metal else (0.5625,0.5875)
 y0,y1=(0.5375,0.5625) if not metal else (0.7875,0.8125)
 if src:
  for poly in me.polygons:
   for li in poly.loop_indices:
    uv=src.data[li].uv;pal.data[li].uv=(x0+(float(uv.x)%1.0)*(x1-x0),y0+(float(uv.y)%1.0)*(y1-y0))
 me.uv_layers.active=pal;me.uv_layers.active_index=me.uv_layers.find('PaletteUV')
# Assert local coordinate contract
print('LOCAL_DAMAGE',[(o.name,tuple(round(v,3) for v in o.location)) for o in bpy.data.objects if o.name.startswith('ORF5_柱体大块')])
bpy.ops.wm.save_as_mainfile(filepath=SRC)
