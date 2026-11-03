import bpy,json
from pathlib import Path
s=bpy.context.scene;file=bpy.data.filepath
for prefix,name in [('ORF2_参考图','01_reference_roof.png'),('ORF3_消防梯','03_roof_entry.png')]:
 s.camera=next(o for o in s.objects if o.type=='CAMERA' and o.name.startswith(prefix));s.render.filepath='D:/projects/sea-work/ocean_rooftop_farm/v003/'+name;s.render.resolution_percentage=100;s.cycles.samples=40;bpy.ops.render.render(write_still=True)
# Saved final geometry is reopened so no unsaved render settings remain and source hash stays verified.
bpy.ops.wm.open_mainfile(filepath=file)
s=bpy.context.scene
print(json.dumps({'file':bpy.data.filepath,'scene':s.name,'dirty':bpy.data.is_dirty,'camera':s.camera.name,'instances':sum(o.instance_type=='COLLECTION' for o in s.objects),'final_views_rendered':2},ensure_ascii=False))
