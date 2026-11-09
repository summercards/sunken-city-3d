import bpy,json
from pathlib import Path
R=Path('D:/projects/sea'); D=R/'art_source/scenes/bld_20261109_a/v003'; S=D/'bld_20261109_a_v003.blend'
bpy.ops.wm.open_mainfile(filepath=str(S),load_ui=False)
cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components']
inst=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))['instances']
from collections import Counter
cnt=Counter(x['key'] for x in inst)
rows=[];total=0
for e in cat:
 c=bpy.data.collections.get(e['collection']); obs=[o for o in c.all_objects if o.type=='MESH']
 texts=[o for o in obs if '字' in o.name]
 n=len(obs)-len(texts); weighted=n*cnt[e['key']]; total+=weighted
 rows.append((e['key'],cnt[e['key']],len(obs),len(texts),n,weighted))
print(json.dumps({'weighted_nontext_objects':total,'proxy12':total*12,'rows':rows},ensure_ascii=False,indent=2))
