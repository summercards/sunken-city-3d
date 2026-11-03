import bpy,json
SRC='D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v005/ocean_rooftop_farm_v005.blend'
pillar=bpy.data.objects.get('ORF3_厚实混凝土结构柱_0')
assert pillar and pillar.type=='MESH'
matte=bpy.data.materials.get('ORF2_FINAL_SEA_Matte');metal=bpy.data.materials.get('ORF2_FINAL_SEA_Metal')
assert matte and metal
# Replace every pillar material slot with the canonical concrete matte slot and
# force all boolean-generated faces to that slot. No generic/default Material remains.
me=pillar.data
me.materials.clear();me.materials.append(matte)
for poly in me.polygons: poly.material_index=0
# Inner backing stays a separate clean metal object with only PaletteUV.
for o in bpy.data.objects:
 if o.name.startswith('ORF5_柱体崩口内里_') and o.type=='MESH':
  o.data.materials.clear();o.data.materials.append(metal)
  for poly in o.data.polygons: poly.material_index=0
  for layer in list(o.data.uv_layers):
   if layer.name!='PaletteUV': o.data.uv_layers.remove(layer)
  pal=o.data.uv_layers.get('PaletteUV')
  assert pal, o.name
  o.data.uv_layers.active=pal;o.data.uv_layers.active_index=o.data.uv_layers.find('PaletteUV')
# Remove generic material data block if it has no users and report remaining names.
for m in list(bpy.data.materials):
 if m.name=='Material' and m.users==0: bpy.data.materials.remove(m)
bpy.context.scene['ORF5_MATERIAL_FIX']='boolean_faces_forced_to_SEA_Matte; inner_backing_SEA_Metal; default_Material_removed'
bpy.ops.wm.save_as_mainfile(filepath=SRC)
print(json.dumps({'pillar_materials':[m.name for m in me.materials],'inner_materials':[[m.name for m in o.data.materials] for o in bpy.data.objects if o.name.startswith('ORF5_柱体崩口内里_')]},ensure_ascii=False))
