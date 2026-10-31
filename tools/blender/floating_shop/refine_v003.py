import bpy,json
from pathlib import Path
R=Path('D:/projects/sea');D=R/'art_source/scenes/floating_shop/v003';sc=bpy.data.scenes['海上悬浮商铺_v003']
o=sc.objects['sign_panel_001'];o.location=(0,-5.25,5.55)
p=D/'component_instances.json';j=json.loads(p.read_text(encoding='utf-8'))
next(i for i in j['instances'] if i['name']==o.name)['position']=list(o.location)
p.write_text(json.dumps(j,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(D/'floating_shop.blend'),compress=True);print('SIGN_MOVED_CLEAR_OF_ROOF')
