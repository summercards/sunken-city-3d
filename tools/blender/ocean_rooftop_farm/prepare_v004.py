import bpy,json,hashlib
from pathlib import Path
from datetime import datetime
s=bpy.context.scene;W=Path('D:/projects/sea-work/ocean_rooftop_farm/v004');W.mkdir(parents=True,exist_ok=True)
p=W/('prechange_'+datetime.now().strftime('%Y%m%d_%H%M%S')+'.blend');bpy.ops.wm.save_as_mainfile(filepath=str(p),copy=True)
keys={'bed','field','cabbage','seedling','tomato','solar','greenhouse','tank'};locked=[];targets=[]
for o in s.objects:
 if o.instance_type!='COLLECTION':continue
 key=o.get('component_id','').replace('SEA-SCENE-ORF2-','').lower()
 row={'name':o.name,'key':key,'matrix':[list(v) for v in o.matrix_world],'collection':o.instance_collection.name,'geom':hashlib.sha256(repr([[tuple(v.co) for v in x.data.vertices] for x in o.instance_collection.objects if x.type=='MESH']).encode()).hexdigest()}
 (targets if key in keys else locked).append(row)
(W/'scope.json').write_text(json.dumps({'source':bpy.data.filepath,'locked':locked,'targets':targets,'old_source_sha256':hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest()},ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'file':bpy.data.filepath,'scene':s.name,'backup':str(p),'targets':{k:sum(x['key']==k for x in targets) for k in keys},'locked':len(locked)},ensure_ascii=False))
