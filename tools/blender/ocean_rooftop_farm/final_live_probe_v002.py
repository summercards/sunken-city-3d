import bpy,json,hashlib
from pathlib import Path
s=bpy.context.scene;p=Path(bpy.data.filepath);r=next(c for c in s.collection.children if c.name.startswith('ORF2_屋顶'));src=next(c for c in r.children if c.name.startswith('01_制作'))
report={'current_file':str(p),'scene':s.name,'current_camera':s.camera.name,'is_dirty':bpy.data.is_dirty,'component_collections':len(src.children),'instances':sum(o.instance_type=='COLLECTION' for o in s.objects),'materials':sorted({m.name for c in src.children for o in c.objects if o.type=='MESH' for m in o.data.materials}),'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'no_background_geometry':True,'runtime_imported':False}
Path('D:/projects/sea-work/ocean_rooftop_farm/v002/live_session_probe.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(report,ensure_ascii=False))
