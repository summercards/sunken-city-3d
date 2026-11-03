import bpy,json
from pathlib import Path
s=bpy.context.scene
w=Path('D:/projects/sea-work/ocean_rooftop_farm/v002');w.mkdir(parents=True,exist_ok=True)
s.camera=next(o for o in s.objects if o.type=='CAMERA' and o.name.startswith('ORF2_参考图'))
s.render.resolution_percentage=75
s.render.filepath=str(w/'01_reference_roof.png')
bpy.ops.render.render(write_still=True)
print(json.dumps({'render':s.render.filepath,'scene':s.name},ensure_ascii=False))
