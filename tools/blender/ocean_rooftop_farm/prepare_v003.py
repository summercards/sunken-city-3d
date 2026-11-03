import bpy,json,hashlib
from pathlib import Path
from datetime import datetime
s=bpy.context.scene;W=Path('D:/projects/sea-work/ocean_rooftop_farm/v003');W.mkdir(parents=True,exist_ok=True)
p=W/('prechange_'+datetime.now().strftime('%Y%m%d_%H%M%S')+'.blend');bpy.ops.wm.save_as_mainfile(filepath=str(p),copy=True)
def sig(o):
 d={'name':o.name,'matrix':[list(v) for v in o.matrix_world],'collection':o.instance_collection.name if o.instance_type=='COLLECTION' else None}
 if o.instance_type=='COLLECTION':d['geometry']=hashlib.sha256(repr([[tuple(v.co) for v in x.data.vertices] for x in o.instance_collection.objects if x.type=='MESH']).encode()).hexdigest()
 return d
locked=[sig(o) for o in s.objects if o.instance_type=='COLLECTION' and o.get('component_id','').split('-')[-1].lower() in ['bed','field','cabbage','seedling','tomato','greenhouse','tank','wind','solar','compost','table','chair','crate','barrel','lamp','pot','plant','stone','plank','grass','tuft']]
(W/'locked_scope.json').write_text(json.dumps(locked,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'file':bpy.data.filepath,'scene':s.name,'backup':str(p),'locked':len(locked),'collections':[(c.name,len(c.objects)) for c in bpy.data.collections if c.name.startswith('ORF2_组件_')],'camera':s.camera.name},ensure_ascii=False))
