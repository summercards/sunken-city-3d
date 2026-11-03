import bpy, json
from mathutils import Vector
SRC='D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v005/ocean_rooftop_farm_v005.blend'
COL=bpy.data.collections.get('ORF2_组件_pier.001')
assert COL
pillar=bpy.data.objects.get('ORF3_厚实混凝土结构柱_0')
assert pillar and pillar.type=='MESH'
# The source keeps production collections hidden from the active ViewLayer.
# Link the authored pillar temporarily so Boolean modifiers can be applied on the
# real mesh; the saved collection ownership remains unchanged for output packaging.
if pillar.name not in bpy.context.view_layer.objects:
    bpy.context.scene.collection.objects.link(pillar)
pillar.hide_set(False)
matte=bpy.data.materials.get('ORF2_FINAL_SEA_Matte')
metal=bpy.data.materials.get('ORF2_FINAL_SEA_Metal')
assert matte and metal
# Remove old front overlay chunks and inner blocks; the pillar itself will carry the cut.
for o in list(bpy.data.objects):
    if o.name.startswith('ORF5_柱体大块崩缺_') or o.name.startswith('ORF5_柱体崩口内里_'):
        bpy.data.objects.remove(o, do_unlink=True)
# Pier local geometry is a 3.1 x 1.558 x 59.8 column, centered in X/Y and bottom at Z=0.
# Cutters are deliberately large: 0.75-1.4m wide, 1.5-3.5m tall, and only bite through the front face.
specs=[
 ('p0',(-1.03,-0.68,12.0),(0.92,0.42,3.10),(0.0,0.0,0.12)),
 ('p1',(0.90,-0.68,23.0),(1.25,0.42,2.20),(0.0,0.0,-0.18)),
 ('p2',(-0.78,-0.68,35.0),(0.96,0.42,4.20),(0.0,0.0,0.24)),
 ('p3',(1.03,-0.68,46.0),(1.36,0.42,2.60),(0.0,0.0,-0.10)),
 ('p4',(-0.88,-0.68,18.0),(1.05,0.42,3.50),(0.0,0.0,0.20)),
 ('p5',(0.76,-0.68,40.0),(1.18,0.42,2.70),(0.0,0.0,-0.22)),
]
cutters=[]
for key,loc,sc,rot in specs:
    bpy.ops.mesh.primitive_cube_add(location=loc, rotation=rot)
    c=bpy.context.object; c.name='ORF5_CUTTER_'+key; c.scale=(sc[0]/2,sc[1]/2,sc[2]/2)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    cutters.append(c)
    mod=pillar.modifiers.new('ORF5_BOOLEAN_'+key,'BOOLEAN'); mod.operation='DIFFERENCE'; mod.solver='EXACT'; mod.object=c
    bpy.context.view_layer.objects.active=pillar
    bpy.ops.object.modifier_apply(modifier=mod.name)
# Remove cutters after boolean.
for c in cutters:
    bpy.data.objects.remove(c, do_unlink=True)
# Create dark inner aggregate planes/boxes just behind each cut, with proper PaletteUV.
def add_inner(key,loc,sc,rot):
    bpy.ops.mesh.primitive_cube_add(location=loc, rotation=rot)
    o=bpy.context.object; o.name='ORF5_柱体崩口内里_'+key; o.scale=(sc[0]/2,0.055,sc[2]/2)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(metal)
    uv=o.data.uv_layers.get('UVMap') or (o.data.uv_layers[0] if o.data.uv_layers else None)
    pal=o.data.uv_layers.get('PaletteUV') or o.data.uv_layers.new(name='PaletteUV')
    x0,x1=0.5625,0.5875; y0,y1=0.7875,0.8125
    for poly in o.data.polygons:
        corners=[(x0,y0),(x1,y0),(x1,y1),(x0,y1)]
        for j,li in enumerate(poly.loop_indices): pal.data[li].uv=corners[j%4]
    o.data.uv_layers.active=pal; o.data.uv_layers.active_index=o.data.uv_layers.find('PaletteUV')
    COL.objects.link(o)
for key,loc,sc,rot in specs:
    # behind front cut, still inside the column
    add_inner(key,(loc[0],-0.47,loc[2]),sc,rot)
# Ensure pillar remains palette/active layer intact.
if pillar.data.uv_layers.get('PaletteUV'):
    pillar.data.uv_layers.active=pillar.data.uv_layers.get('PaletteUV')
# Metadata
bpy.context.scene['ORF5_DAMAGE_MODE']='boolean_large_structural_pier_voids'
bpy.context.scene['ORF5_DAMAGE_COUNT']=6
bpy.context.scene['ORF5_NOTES']='Six large boolean voids cut into the pillar mesh; dark inner faces use PaletteUV and SEA_Metal.'
bpy.ops.wm.save_as_mainfile(filepath=SRC)
print(json.dumps({'saved':SRC,'pillar_vertices':len(pillar.data.vertices),'pillar_faces':len(pillar.data.polygons),'inner_count':len([o for o in bpy.data.objects if o.name.startswith('ORF5_柱体崩口内里_')])},ensure_ascii=False))
