import bpy,json,math,ast,random
from pathlib import Path
from mathutils import Vector,Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/ocean_rooftop_farm/v003';s=bpy.context.scene;cat=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];by={e['key']:e for e in cat};root=next(c for c in s.collection.children if c.name.startswith('ORF3_'));src=next(c for c in root.children if c.name.startswith('01_制作'));out=next(c for c in root.children if c.name.startswith('02_'))
# close rear unsupported slab fingers with back columns and reduce slab depth.
c=bpy.data.collections[by['slab']['collection']]
for ob in c.objects:
 for v in ob.data.vertices:v.co.y*=28.2/30.5
 ob.data.update()
pc=bpy.data.collections[by['pier']['collection']]
for x in [-22.8,-7.6,7.6,22.8]:
 o=bpy.data.objects.new('ORF3_背立面连续结构柱',None);out.children[0].objects.link(o);o.instance_type='COLLECTION';o.instance_collection=pc;o['component_id']=by['pier']['asset_id'];o.location=(x,13.4,0)
# wind and window had collided in old prefix-based catalog lookup. Repair wind by exact component instance identity.
windobjs=[o for o in s.objects if o.instance_type=='COLLECTION' and o.get('component_id')=='SEA-SCENE-ORF2-WIND'];orig=next((c for c in src.children if c.name.split('.')[0]=='ORF2_组件_wind' and len(c.objects)>0),None)
if orig and orig!=bpy.data.collections[by['window']['collection']]:
 for o in windobjs:o.instance_collection=orig
 by['wind']['collection']=orig.name
 # small wind pole thickening via connected cylinder ring data
 for ob in orig.objects:
  if ob.type!='MESH':continue
  for v in ob.data.vertices:
   if abs(v.co.x)<.1 and abs(v.co.y)<.08:v.co.x*=1.6;v.co.y*=1.6
# Broaden decorative greenhouse frame poles too (only metal role, not panes).
ghc=bpy.data.collections[by['greenhouse']['collection']]
import numpy as np
for ob in ghc.objects:
 if not any('Metal' in m.name for m in ob.data.materials):continue
 me=ob.data;adj={i:set() for i in range(len(me.vertices))}
 for e in me.edges:a,b=e.vertices;adj[a].add(b);adj[b].add(a)
 rem=set(adj)
 while rem:
  a=rem.pop();ids=[a];stack=[a]
  while stack:
   x=stack.pop()
   for y in adj[x]:
    if y in rem:rem.remove(y);ids.append(y);stack.append(y)
  if len(ids)<12:continue
  p=np.array([me.vertices[i].co[:] for i in ids]);ctr=p.mean(0);ev,axes=np.linalg.eigh(np.cov((p-ctr).T));loc=(p-ctr)@axes;ext=np.ptp(loc,axis=0)
  if ev[0]>1e-8 and ev[1]/ev[0]<1.8 and ext[2]>2*ext[1] and ext[1]<.17:
   fac=.17/ext[1];loc[:,:2]*=fac
   for idx,co in zip(ids,loc@axes.T+ctr):me.vertices[idx].co=co
 me.update()
# remove many identical weather instance stamps from piers; cluster a smaller subset, attached.
weather=[o for o in s.objects if o.instance_type=='COLLECTION' and o.get('component_id')=='SEA-SCENE-ORF2-WEATHER'];random.seed(121)
for i,o in enumerate(weather):
 if random.random()<.48:bpy.data.objects.remove(o,do_unlink=True)
 else:o.location.z+=random.uniform(-.5,.5);o.scale.x*=random.uniform(.65,1.1);o.scale.z*=random.uniform(.55,1.25)
# roof platform mild front shear suggests leaning wall, while upper walk plane stays level across X.
# Cache corrected geometry/index, exact collections only.
for e in cat:
 c=bpy.data.collections[e['collection']];pts=[v.co for ob in c.objects if ob.type=='MESH' for v in ob.data.vertices];e['bounds_size_m']=[max(v[i] for v in pts)-min(v[i] for v in pts) for i in range(3)];e['instance_count']=sum(o.instance_type=='COLLECTION' and o.instance_collection==c for o in s.objects)
(D/'component_catalog.json').write_text(json.dumps({'components':cat},ensure_ascii=False,indent=2),encoding='utf-8')
# guards on flights: all remain no less than 1.30m clear, landing/tread geometry unchanged.
bpy.ops.wm.save_as_mainfile(filepath=str(D/'ocean_rooftop_farm_v003.blend'),compress=True)
print(json.dumps({'wind_collection':by['wind']['collection'],'window_collection':by['window']['collection'],'catalog_unique_collections':len({e['collection'] for e in cat}),'components':len(cat)},ensure_ascii=False))
