import bpy,json,hashlib
from pathlib import Path
R=Path('D:/projects/sea');D=R/'art_source/scenes/floating_shop/v001';sc=bpy.data.scenes['海上悬浮商铺_v001']
actual=[o for o in sc.objects if o.instance_type=='COLLECTION'];data={'filepath':bpy.data.filepath,'scene':sc.name,'saved_source_sha256':hashlib.sha256((D/'floating_shop.blend').read_bytes()).hexdigest(),'instances':len(actual),'plant_instances':len([o for o in actual if o.users_collection[0].name=='FSH_植物附件']),'component_collections':len({o.instance_collection.name for o in actual}),'source_dirty':bpy.data.is_dirty}
Path('D:/projects/sea-work/floating_shop/final_session_probe.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(data,ensure_ascii=False))
