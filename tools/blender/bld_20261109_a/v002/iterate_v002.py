"""Iterate the B1109A source in the live Blender MCP session under zero-square v002."""
import bpy,json,hashlib,math,os,copy
from pathlib import Path
from mathutils import Vector,Matrix
R=Path('D:/projects/sea');V1=R/'art_source/scenes/bld_20261109_a/v001';D=R/'art_source/scenes/bld_20261109_a/v002';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'bld_20261109_a/v002';W.mkdir(parents=True,exist_ok=True)
sc=bpy.context.scene
if sc.get('bld_v002_applied'):raise RuntimeError('v002 iteration already applied in this Blender session; reload v001 before retry')
if not (W/'v001_before_iteration.blend').exists():bpy.ops.wm.save_as_mainfile(filepath=str(W/'v001_before_iteration.blend'),copy=True)
plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));oldcat=json.loads((V1/'catalog.json').read_text(encoding='utf-8'))['components'];oldby={e['key']:e for e in oldcat};newby={e['key']:e for e in plan['components']}
# Discover the 49 existing master collections from the v001 catalog, then rename in place.
cols={}
for key,e in oldby.items():
 col=bpy.data.collections.get(e['collection']) or bpy.data.collections.get(newby[key]['asset_id'])
 if col is None:raise RuntimeError('missing master collection '+key)
 cols[key]=col
# Shared materials and palette UV contract are reused, never duplicated.
roles={m.get('semantic_role'):m for m in bpy.data.materials if m.get('semantic_role')}
if 'SEA_Matte' not in roles: raise RuntimeError('SEA_Matte missing')
pal=R/plan['palette'];cells={c['name']:c for c in json.loads(pal.with_suffix('.json').read_text())['cells']}
def ensure_uv(o,color='plaster',role='SEA_Matte'):
 me=o.data
 for uv in list(me.uv_layers):me.uv_layers.remove(uv)
 uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True;cell=cells[color];cx=(cell['column']+.5)/8;cy=1-(cell['row']+.5)/8
 for p in me.polygons:
  for j,li in enumerate(p.loop_indices):
   a=math.tau*j/max(1,p.loop_total);uv.data[li].uv=(cx+.027*math.cos(a),cy+.027*math.sin(a))
 me.materials.clear();me.materials.append(roles[role]);o['palette_color']=color;o['role']=role
 return o
def taper_component(col,rho,axis='z'):
 meshes=[o for o in col.all_objects if o.type=='MESH']
 pts=[v.co.copy() for o in meshes for v in o.data.vertices]
 if not pts:return
 axis_index={'x':0,'y':1,'z':2}[axis]
 lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)];span=hi[axis_index]-lo[axis_index]
 if span<1e-6:return
 cx=(lo[0]+hi[0])/2;cy=(lo[1]+hi[1])/2;cz=(lo[2]+hi[2])/2
 for o in meshes:
  for v in o.data.vertices:
   t=max(0,min(1,(v.co[axis_index]-lo[axis_index])/span));s=1-rho*t
   if axis=='z':v.co.x=cx+(v.co.x-cx)*s;v.co.y=cy+(v.co.y-cy)*s
   elif axis=='y':v.co.x=cx+(v.co.x-cx)*s
   else:v.co.y=cy+(v.co.y-cy)*s
  o.data.update()
def create_box(col,name,center,size,color='plaster',role='SEA_Matte',taper=.02):
 x,y,z=center;w,d,h=[s/2 for s in size];top_s=1-taper
 vs=[(x-w,y-d,z-h/2),(x+w,y-d,z-h/2),(x+w,y+d,z-h/2),(x-w,y+d,z-h/2),
     (x-w*top_s,y-d*top_s,z+h/2),(x+w*top_s,y-d*top_s,z+h/2),(x+w*top_s,y+d*top_s,z+h/2),(x-w*top_s,y+d*top_s,z+h/2)]
 fs=[(3,2,1,0),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]
 me=bpy.data.meshes.new('BLDA_V002_'+name);me.from_pydata(vs,[],fs);me.update();o=bpy.data.objects.new('BLDA_V002_'+name,me);col.objects.link(o);ensure_uv(o,color,role)
 bm=None
 try:
  bpy.context.view_layer.objects.active=o;o.select_set(True);mo=o.modifiers.new('v002真实三段倒角','BEVEL');mo.width=min(.025,min(size)*.25);mo.segments=3;mo.affect='EDGES';bpy.ops.object.modifier_apply(modifier=mo.name);o.select_set(False)
 except Exception:
  o.select_set(False)
 return o
def rotate_hanger(key,deg,limit=99):
 n=0
 for o in sc.objects:
  if o.instance_type=='COLLECTION' and o.instance_collection==cols[key] and n<limit:
   o.rotation_mode='XYZ';o.rotation_euler.x=math.radians(deg);n+=1
 return n
# Rename master collections and stamp the new form contract.
for key,col in cols.items():
 e=newby[key];col.name=e['asset_id'];col['asset_id']=e['asset_id'];col['version']='v002';col['form_layer']=e['form_layer'];col['kind']=e['kind'];col['rho']=e.get('rho',0.0);col['form_contract']='zero_square_v002';col['building_class']=e['building_class'] or 'not_applicable';col['collection_instance_offset']=[0,0,0]
# Apply actual nonzero asymmetry to every rigid volume component. Plants and cloth keep organic/soft geometry.
for key,e in newby.items():
 kind=e['kind'];rho=float(e.get('rho',0.0))
 if kind in {'plant','soft'}:continue
 if kind=='linear':taper_component(cols[key],rho,'z')
 elif kind=='horizontal_cover':taper_component(cols[key],rho,'y')
 else:taper_component(cols[key],rho,'z')
# Add true relief geometry to the wall shell, with 8 quoins, 12 brick blocks, 3 grooves and 6 brackets.
shell=cols['shell'];
for idx,z in enumerate((.42,1.62,2.82,4.02)):
 for side in (-1,1):create_box(shell,f'隅石_{idx}_{side}',(side*4.35,-4.30,z),(.22,.14,.82),'stone','SEA_Matte',.025)
for row,z in enumerate((.46,.96)):
 for i in range(6):
  x=-3.0+i*1.2+(0.3 if row else 0);create_box(shell,f'前立面砖嵌_{row}_{i}',(x,-4.31,z),(.52,.10,.28),'wood_edge','SEA_Matte',.025)
for i,z in enumerate((5.0,7.0,9.0)):create_box(shell,f'浅凹槽提示_{i}',(0,-4.31,z),(6.4,.06,.035),'deepgreen','SEA_Matte',.01)
for i,x in enumerate((-3.4,-2.0,-.6,.8,2.2,3.6)):create_box(shell,f'檐口托架_{i}',(x,-4.27,4.70),(.18,.24,.62),'wood_mid','SEA_Matte',.025)
shell['relief_layers']=2;shell['quoin_blocks']=8;shell['brick_blocks']=12;shell['grooves']=3;shell['brackets']=6
# Three-layer eave stack and tapered top cap make the top outline read as a constructed building.
cop=cols['coping']
for i,(z,w,d,h) in enumerate(((.76,8.85,8.45,.12),(.90,8.70,8.30,.10),(1.01,8.55,8.16,.08))):create_box(cop,f'三层叠涩檐口_{i}',(0,0,z),(w,d,h),'wood_edge','SEA_Matte',.025)
# The required hanging/leaning coverage is made visible at the instance layer.
for key,deg in [('main_sign',7),('awning',4),('blade_sign',8),('poster_panel',6),('carton',7),('stool_stack',5),('bin',5),('planter_round',7),('planter_trough',6),('menu',7),('notice',4)]:rotate_hanger(key,deg)
# Small linear parts receive explicit diameter metadata and visible tapered vertex scaling.
for key in ('pipe_set','vent_duct','antenna','clothesline','stair_ladder'):cols[key]['d_bottom']=.12;cols[key]['d_top']=.108;cols[key]['diameter_ratio']=.9
# Rename the scene and top-level collections, preserving the instance graph.
sc.name='BLDA_编号海上建筑_v002';sc['bld_v002_applied']=True;sc['version']='v002';sc['form_contract']='zero_square_v002'
for c in list(sc.collection.children):
 if c.name.startswith('BLDA_') and c.name[5:7].isdigit():c.name=c.name.replace('BLDA_','BLDA_V002_',1)
# Hero camera and render.
cam=sc.camera;cam.location=(-29,-29,22);cam.rotation_euler=(Vector((0,0,7.0))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=20.6
sc.render.resolution_x=sc.render.resolution_y=1400;sc.render.filepath=str(W/'hero_v002.png');bpy.ops.wm.save_as_mainfile(filepath=str(D/'bld_20261109_a_v002.blend'),compress=True);bpy.ops.render.render(write_still=True)
# Build exact v002 catalog and instance list from current data.
def local_stats(col):
 pts=[];tris=polys=0;h=hashlib.sha256();roleset=set()
 for o in col.all_objects:
  if o.type!='MESH':continue
  pts.extend(v.co.copy() for v in o.data.vertices);o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles);polys+=len(o.data.polygons)
  for m in o.data.materials:
   if m and m.get('semantic_role'):roleset.add(m['semantic_role'])
  for v in o.data.vertices:h.update((';'.join(format(float(x),'.6f') for x in v.co)+';').encode())
 lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
 return list(hi[j]-lo[j] for j in range(3)),tris,polys,len([o for o in col.all_objects if o.type=='MESH']),h.hexdigest(),sorted(roleset)
cat=[]
for key,e in newby.items():
 col=cols[key];bounds,tris,polys,meshes,fingerprint,roleset=local_stats(col);cat.append(dict(e,collection=col.name,component_source=f'art_source/scenes/bld_20261109_a/v002/component_packages/{key}/{key}.blend',bounds_size=bounds,triangles=tris,polygons=polys,meshes=meshes,material_roles=roleset,geometry_fingerprint=fingerprint,fingerprint_algorithm='ordered_vertices_fixed6_sha256',instance_count=sum(o.instance_collection==col for o in sc.objects if o.instance_type=='COLLECTION')))
layout=[]
for o in sc.objects:
 if o.instance_type=='COLLECTION' and o.instance_collection:
  e=next(e for e in cat if e['collection']==o.instance_collection.name);layout.append({'name':o.name,'key':e['key'],'asset_id':e['asset_id'],'position':list(o.location),'rotation_euler_xyz':list(o.rotation_euler),'scale':list(o.scale)})
(D/'catalog.json').write_text(json.dumps({'schema':'sea.component_catalog','components':cat},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_instances.json').write_text(json.dumps({'schema':'sea.component_instances','coordinate_contract':{'plane':'XY','up':'+Z','rotation':'Euler XYZ radians; Z is vertical','godot_mapping':'(x,y,z)->(x,z,-y)','placement_owner':'Godot TSCN after future integration'},'instances':layout},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('BLDA_V002_ITERATED',json.dumps({'components':len(cat),'instances':len(layout),'scene':sc.name,'hero':str(W/'hero_v002.png'),'relief':{'quoin':8,'brick':12,'grooves':3,'brackets':6}}),flush=True)
