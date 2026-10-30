import bpy,json,hashlib
from pathlib import Path
R=Path('D:/projects/sea');D=R/'art_source/scenes/floating_shop/v002'
col=bpy.data.collections['SEA-SCENE-FSH-ENTRY']
for o in col.objects:
 if o.type=='MESH' and o.name.startswith('入口木色门槛'):
  for v in o.data.vertices:v.co.z*=.2
  o.data.update()
p=D/'catalog.json';cat=json.loads(p.read_text(encoding='utf-8'));e=next(x for x in cat['components'] if x['key']=='entry');geom=b''.join(str(tuple(round(x,5) for x in v.co)).encode() for o in col.objects if o.type=='MESH' for v in o.data.vertices);e['geometry_fingerprint']=hashlib.sha256(geom).hexdigest();p.write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(D/'floating_shop.blend'),compress=True);print('THRESHOLD_FLUSH_WITH_DECK')
