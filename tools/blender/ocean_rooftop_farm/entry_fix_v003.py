import bpy,json,math
from pathlib import Path
D=Path('D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v003');s=bpy.context.scene;cat=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];by={e['key']:e for e in cat};root=next(c for c in s.collection.children if c.name.startswith('ORF3_'));src=next(c for c in root.children if c.name.startswith('01_制作'));out=next(c for c in root.children if c.name.startswith('02_'))
# Top landing uses explicit open-edge variant, not invisible deletion from repeated standard.
k='stair_landing_open';e=dict(by['stair_landing']);e.update({'key':k,'asset_id':'SEA-SCENE-ORF2-STAIR_LANDING_OPEN','name':'消防梯开放入口平台','component_family':'fire_landing','variant_axis':'edge_opening','variant_value':'roof_entry','variant_reason':'roof bridge must pass through building-side edge','component_source':'art_source/scenes/ocean_rooftop_farm/v003/component_packages/'+k+'/'+k+'.blend'})
source=bpy.data.collections[by['stair_landing']['collection']];c=bpy.data.collections.new('ORF3_组件_'+k);src.children.link(c)
for ob in source.objects:
 cp=ob.copy();cp.data=ob.data.copy();c.objects.link(cp);me=cp.data
 # remove loose mesh components representing negative X edge guard, preserve base deck
 adj={i:set() for i in range(len(me.vertices))}
 for ed in me.edges:a,b=ed.vertices;adj[a].add(b);adj[b].add(a)
 rem=set(adj);kill=set()
 while rem:
  a=rem.pop();ids=[a];stack=[a]
  while stack:
   x=stack.pop()
   for y in adj[x]:
    if y in rem:rem.remove(y);ids.append(y);stack.append(y)
  if max(me.vertices[i].co.x for i in ids)<-1.7 and max(me.vertices[i].co.z for i in ids)>.4:kill.update(ids)
 if kill:
  import bmesh
  bm=bmesh.new();bm.from_mesh(me);bm.verts.ensure_lookup_table();bmesh.ops.delete(bm,geom=[bm.verts[i] for i in kill],context='VERTS');bm.to_mesh(me);bm.free();me.update()
 cp.name='ORF3_开放平台_金属主体'
e['collection']=c.name;cat.append(e)
for o in s.objects:
 if o.instance_type=='COLLECTION' and o.get('component_id')==by['stair_landing']['asset_id'] and o.location.z>59:
  o.instance_collection=c;o['component_id']=e['asset_id']
# Upper landing has open left side x=24.0; bridge overlaps 2.05m of landing.
route=json.loads((D/'stair_route.json').read_text(encoding='utf-8'));route['top_landing_guard_open_x']=24.0;route['roof_entry_free_width_m']=2.5;route['minimum_stair_clear_width_m']=1.30;route['continuous_route_nodes']=[[25,-3,0]]
for i in range(12):route['continuous_route_nodes'] += [[25,1.2,i*5+2.5],[27,1.2,i*5+2.5],[27,-3,i*5+5],[25,-3,i*5+5]]
route['continuous_route_nodes'] += [[24.4,-3.8,60],[23,-3.8,60],[22.5,-3.8,60]]
(D/'stair_route.json').write_text(json.dumps(route,ensure_ascii=False,indent=2),encoding='utf-8')
plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));plan['components'].append(e);plan['component_budget']={'limit':50,'planned':46,'remaining':4};plan['scope_amendment']='User 10:55:22 requested plumper all posts incl greenhouse frames; only frame thickness allowed beyond earlier locks.';(D/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf-8')
for e in cat:
 c=bpy.data.collections[e['collection']];e['instance_count']=sum(o.instance_type=='COLLECTION' and o.instance_collection==c for o in s.objects);pts=[v.co for ob in c.objects if ob.type=='MESH' for v in ob.data.vertices];e['bounds_size_m']=[max(v[i] for v in pts)-min(v[i] for v in pts) for i in range(3)]
(D/'component_catalog.json').write_text(json.dumps({'components':cat},ensure_ascii=False,indent=2),encoding='utf-8')
# Current view cameras include all height and entry closeup.
cam=next(o for o in s.objects if o.type=='CAMERA' and o.name.startswith('ORF3_右侧'));cam.data.ortho_scale=112
bpy.ops.wm.save_as_mainfile(filepath=str(D/'ocean_rooftop_farm_v003.blend'),compress=True)
print(json.dumps({'components':46,'roof_entry_platform':'open_left_side','clear_stair_width_m':1.30},ensure_ascii=False))
