import bpy,json
SRC='D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v005/ocean_rooftop_farm_v005.blend'
removed=[]
for o in list(bpy.data.objects):
 if o.name.startswith('ORF5_柱体崩口内里_'):
  removed.append(o.name);bpy.data.objects.remove(o,do_unlink=True)
scene=bpy.context.scene
scene['ORF5_MATERIAL_FIX']='boolean_faces_only_no_inner_overlap_zfight'
scene['ORF5_INNER_BACKING_REMOVED']=len(removed)
bpy.ops.wm.save_as_mainfile(filepath=SRC)
print(json.dumps({'removed':removed,'count':len(removed)},ensure_ascii=False))
