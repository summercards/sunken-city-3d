import bpy,json
from pathlib import Path
s=bpy.context.scene;w=Path('D:/projects/sea-work/ocean_rooftop_farm/v003');w.mkdir(parents=True,exist_ok=True)
s.cycles.samples=24;s.render.resolution_percentage=85
views=[('ORF2_参考图','01_reference_roof.png'),('ORF3_右侧','02_fire_escape_full.png'),('ORF3_消防梯','03_roof_entry.png'),('ORF3_凹窗','04_facade_detail.png'),('ORF2_垂直','05_top_plan.png')]
for prefix,file in views:
 s.camera=next(o for o in s.objects if o.type=='CAMERA' and o.name.startswith(prefix));s.render.filepath=str(w/file);bpy.ops.render.render(write_still=True)
s.camera=next(o for o in s.objects if o.type=='CAMERA' and o.name.startswith('ORF2_参考图'))
print(json.dumps({'views':[f for p,f in views],'scene':s.name},ensure_ascii=False))
