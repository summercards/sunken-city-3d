import bpy,json
SRC='D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v005/ocean_rooftop_farm_v005.blend'
o=bpy.data.objects.get('ORF3_厚实混凝土结构柱_0');assert o and o.type=='MESH'
me=o.data
# Canonical concrete cell used by the authored pier: 8x8 grid cell (5,0),
# with a safe 8px interior band. Remove the old UVMap so import cannot choose it.
for layer in list(me.uv_layers):
    if layer.name!='PaletteUV': me.uv_layers.remove(layer)
pal=me.uv_layers.get('PaletteUV') or me.uv_layers.new(name='PaletteUV')
# Every boolean-generated and authored loop gets a small-area island in the same cell.
# Use object-space x/z for gentle variation but keep all coordinates inside one cell.
for poly in me.polygons:
    for li in poly.loop_indices:
        v=me.vertices[me.loops[li].vertex_index].co
        u=0.65625 + (abs(float(v.x))*0.0125)%0.05
        w=0.0375 + (abs(float(v.z))*0.0125)%0.05
        pal.data[li].uv=(u,w)
me.uv_layers.active=pal;me.uv_layers.active_index=me.uv_layers.find('PaletteUV')
o.data.materials.clear();o.data.materials.append(bpy.data.materials.get('ORF2_FINAL_SEA_Matte'))
for poly in me.polygons: poly.material_index=0
bpy.ops.wm.save_as_mainfile(filepath=SRC)
print(json.dumps({'saved':SRC,'layers':[x.name for x in me.uv_layers],'faces':len(me.polygons)},ensure_ascii=False))
