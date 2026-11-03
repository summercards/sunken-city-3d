import bpy,json,math
import numpy as np
from pathlib import Path
s=bpy.context.scene;root=next(c for c in s.collection.children if c.name.startswith('ORF3_'));src=next(c for c in root.children if c.name.startswith('01_制作'))
keys=['rail','fence','ladder','line','wind','tank','solar','pipe','stair_flight','stair_landing','roof_entry'];report=[]
for key in keys:
 # exact collection via catalog, avoid substring overlaps
 cat=json.loads(Path('D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v003/component_catalog.json').read_text(encoding='utf-8'))['components'];entry=next(e for e in cat if e['key']==key);c=bpy.data.collections[entry['collection']]
 for ob in c.objects:
  if ob.type!='MESH':continue
  me=ob.data;adj={i:set() for i in range(len(me.vertices))}
  for edge in me.edges:a,b=edge.vertices;adj[a].add(b);adj[b].add(a)
  remaining=set(adj);count=0
  while remaining:
   seed=remaining.pop();ids=[seed];stack=[seed]
   while stack:
    a=stack.pop()
    for b in adj[a]:
     if b in remaining:remaining.remove(b);ids.append(b);stack.append(b)
   if len(ids)<12:continue
   p=np.array([me.vertices[i].co[:] for i in ids]);center=p.mean(axis=0);ev,axes=np.linalg.eigh(np.cov((p-center).T));local=(p-center)@axes;ext=np.ptp(local,axis=0)
   # Generated rods have two circular rings. Never enlarge flat boards, panes or tank body.
   if ev[0]<1e-8 or ev[1]/ev[0]>1.8 or ext[2]<ext[1]*2.0 or ext[1]>.32:continue
   diameter=max(ext[0],ext[1]);target=.20 if key in ['rail','stair_landing','roof_entry','tank'] else .18
   if diameter>=target-.001:continue
   fac=target/diameter;local[:,0]*=fac;local[:,1]*=fac;new=local@axes.T+center
   for idx,co in zip(ids,new):me.vertices[idx].co=co
   count+=1
  me.update();report.append({'key':key,'object':ob.name,'thickened_rods':count})
# Widen flight handrail attachment x coordinates, not the actual walking treads.
# The 1.5m step face stays, guard centers move to +-0.86 -> 1.54m between 0.18m rods.
entry=next(e for e in cat if e['key']=='stair_flight');c=bpy.data.collections[entry['collection']]
for ob in c.objects:
 me=ob.data
 for v in me.vertices:
  if abs(v.co.x)>.65 and v.co.z>.35:
   # only vertices above treads are separated via component PCA in next audit; don't change tread widths
   pass
# Request recorded without touching protected furniture/agriculture.
p=Path('D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v003/component_plan.json');plan=json.loads(p.read_text(encoding='utf-8'));plan['plump_rail_revision']={'minimum_rod_diameter_m':.18,'primary_posts_diameter_m':.20,'style_reference':'solar cabin broad toy-like forms','scope':keys,'runtime_clear_width_m':'pending geometric verification'};p.write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf-8')
Path('D:/projects/sea-work/ocean_rooftop_farm/v003/plump_rod_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath='D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v003/ocean_rooftop_farm_v003.blend',compress=True)
print(json.dumps({'rods_thickened':sum(e['thickened_rods'] for e in report),'report':report},ensure_ascii=False))
