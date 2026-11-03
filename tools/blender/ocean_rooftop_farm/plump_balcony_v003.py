import bpy,json
from pathlib import Path
import numpy as np
D=Path('D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v003');s=bpy.context.scene;cat=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];keys=['balcony'];count=0
for e in cat:
 if e['key'] not in keys:continue
 for o in bpy.data.collections[e['collection']].objects:
  if not any('Metal' in m.name for m in o.data.materials):continue
  me=o.data;adj={i:set() for i in range(len(me.vertices))}
  for ed in me.edges:a,b=ed.vertices;adj[a].add(b);adj[b].add(a)
  rem=set(adj)
  while rem:
   a=rem.pop();ids=[a];stack=[a]
   while stack:
    a=stack.pop()
    for b in adj[a]:
     if b in rem:rem.remove(b);ids.append(b);stack.append(b)
   if len(ids)<12:continue
   p=np.array([me.vertices[i].co[:] for i in ids]);ctr=p.mean(0);ev,ax=np.linalg.eigh(np.cov((p-ctr).T));lc=(p-ctr)@ax;ext=np.ptp(lc,axis=0)
   if ev[0]>1e-8 and ev[1]/ev[0]<1.8 and ext[1]<.18 and ext[2]>ext[1]*2:
    lc[:,:2]*=.18/ext[1]
    for i,co in zip(ids,lc@ax.T+ctr):me.vertices[i].co=co
    count+=1
print('BALCONY_RODS_THICKENED',count)
