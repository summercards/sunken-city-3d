import bpy, json
SRC='D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v005/ocean_rooftop_farm_v005.blend'
COL=bpy.data.collections.get('ORF2_组件_pier.001'); pillar=bpy.data.objects.get('ORF3_厚实混凝土结构柱_0')
assert COL and pillar and pillar.type=='MESH'
# Extend the existing boolean damage with broad, staggered bites. Each cutter removes
# 40-55% of the 3.1m column width at a different height/orientation.
# Keep the cutouts on the front/side surfaces while leaving a clear load-bearing rim.
for o in list(bpy.data.objects):
    if o.name.startswith('ORF5_CUTTER_FINAL_') or o.name.startswith('ORF5_柱体崩口内里_'):
        bpy.data.objects.remove(o,do_unlink=True)
# local x/y/z, size x/y/z, z rotation
specs=[
 ('A',(-0.74,-0.70,11.8),(1.55,0.85,3.05),0.16),
 ('B',(0.72,-0.70,24.7),(1.72,0.85,2.35),-0.20),
 ('C',(-0.62,-0.70,37.0),(1.40,0.85,3.65),0.24),
 ('D',(0.77,-0.70,48.0),(1.65,0.85,2.45),-0.14),
 ('E',(-0.63,-0.70,17.5),(1.32,0.85,2.10),0.30),
 ('F',(0.65,-0.70,42.0),(1.50,0.85,2.85),-0.28),
]
for key,loc,size,rz in specs:
    bpy.ops.mesh.primitive_cube_add(location=loc,rotation=(0,0,rz))
    c=bpy.context.object;c.name='ORF5_CUTTER_FINAL_'+key;c.scale=(size[0]/2,size[1]/2,size[2]/2)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    # Link to active scene collection for view-layer boolean evaluation.
    if c.name not in bpy.context.view_layer.objects: bpy.context.scene.collection.objects.link(c)
    c.hide_render=True;c.hide_viewport=True
    mod=pillar.modifiers.new('ORF5_BOOLEAN_FINAL_'+key,'BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=c
    if pillar.name not in bpy.context.view_layer.objects: bpy.context.scene.collection.objects.link(pillar)
    pillar.hide_set(False);bpy.context.view_layer.objects.active=pillar
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(c,do_unlink=True)
# Build clean dark aggregate backing faces inside the holes. Use PaletteUV as the only
# UV layer so GLB export maps the solid palette cell to UV0 instead of old UVMap noise.
metal=bpy.data.materials.get('ORF2_FINAL_SEA_Metal');assert metal
for idx,(key,loc,size,rz) in enumerate(specs):
    bpy.ops.mesh.primitive_cube_add(location=(loc[0],-0.38,loc[2]),rotation=(0,0,rz))
    o=bpy.context.object;o.name='ORF5_柱体崩口内里_'+key;o.scale=(size[0]*0.82/2,0.07,size[2]*0.82/2)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(metal)
    # Remove old UVMap and create one canonical PaletteUV.
    for layer in list(o.data.uv_layers): o.data.uv_layers.remove(layer)
    pal=o.data.uv_layers.new(name='PaletteUV')
    x0,x1=0.5625,0.5875;y0,y1=0.7875,0.8125
    for poly in o.data.polygons:
        coords=[(x0,y0),(x1,y0),(x1,y1),(x0,y1)]
        for j,li in enumerate(poly.loop_indices):pal.data[li].uv=coords[j%4]
    o.data.uv_layers.active=pal;o.data.uv_layers.active_index=0
    COL.objects.link(o)
# Keep pillar's authored PaletteUV active.
if pillar.data.uv_layers.get('PaletteUV'):
    pillar.data.uv_layers.active=pillar.data.uv_layers.get('PaletteUV')
# metadata
bpy.context.scene['ORF5_DAMAGE_MODE']='boolean_large_structural_pier_voids_final'
bpy.context.scene['ORF5_DAMAGE_COUNT']=6
bpy.context.scene['ORF5_DAMAGE_SCALE']='0.4-0.55 column width; 2.1-3.65m height'
bpy.context.scene['ORF5_NOTES']='Six broad boolean voids cut from pier mesh; clean PaletteUV-only dark inner backing; no surface overlay chunks.'
bpy.ops.wm.save_as_mainfile(filepath=SRC)
print(json.dumps({'saved':SRC,'pillar_vertices':len(pillar.data.vertices),'pillar_faces':len(pillar.data.polygons),'inner_count':len([o for o in bpy.data.objects if o.name.startswith('ORF5_柱体崩口内里_')])},ensure_ascii=False))
