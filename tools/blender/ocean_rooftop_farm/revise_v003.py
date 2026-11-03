import bpy,math,json,random,ast,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/ocean_rooftop_farm/v003';W=R.parent/'sea-work/ocean_rooftop_farm/v003';D.mkdir(parents=True,exist_ok=True);W.mkdir(parents=True,exist_ok=True)
s=bpy.context.scene
assert 'v002' in s.name, 'Only run once on backed-up v002; use backup for clean repeat'
# Reuse only the verified primitive builder class, never execute the v002 generator.
source=(R/'tools/blender/ocean_rooftop_farm/author_v002.py').read_text(encoding='utf-8');tree=ast.parse(source);node=next(n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='Geo');exec(compile(ast.Module(body=[node],type_ignores=[]),'Geo','exec'))
root=next(c for c in s.collection.children if c.name.startswith('ORF2_屋顶'));src=next(c for c in root.children if c.name.startswith('01_制作'));out=next(c for c in root.children if c.name.startswith('02_'));qa=next(c for c in root.children if c.name.startswith('90_'))
oldcat=json.loads((D.parent/'v002/component_catalog.json').read_text(encoding='utf-8'))['components'];cols={e['key']:bpy.data.collections[e['collection']] for e in oldcat};spec={e['key']:dict(e) for e in oldcat}
roles=[next(m for c in src.children for o in c.objects for m in o.data.materials if m.name=='ORF2_FINAL_'+r) for r in ['SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission']]
cells={x['name']:x for x in json.loads((R/'art_source/shared/palettes/sea_cabin_timber_8x8_512.json').read_text(encoding='utf-8'))['cells']}
new=[('window_cracked','裂纹缺角玻璃窗','fixture','window'),('window_broken','缺片木板封窗','fixture','window'),('moss_cluster','成片不规则苔藓','flora','moss'),('stair_flight','消防梯标准半层梯段','structure','fire_stair'),('stair_landing','消防梯折返休息平台','structure','fire_landing'),('roof_entry','消防梯屋顶开放入口','structure','entry')]
plan=json.loads((D.parent/'v002/component_plan.json').read_text(encoding='utf-8'));plan.update({'version':'v003','status':'frozen_before_local_revision','revision_scope':['edge silhouette','pitched rooftop rooms','deep recessed damaged windows','irregular edge vegetation','right continuous fire escape and roof entry'],'parent_source':'v002/ocean_rooftop_farm_v002.blend','component_budget':{'limit':50,'planned':45,'remaining':5},'locked_signature':'D:/projects/sea-work/ocean_rooftop_farm/v003/locked_scope.json'})
for k,name,cat,fam in new:
 e={'key':k,'name':name,'category':cat,'component_family':fam,'asset_id':'SEA-SCENE-ORF2-'+k.upper(),'scope':'scene_local','origin':'bottom_center','front_axis':'-Y','allowed_rotations_y_deg':[0,90,180,270]};plan['components'].append(e);spec[k]=e
for e in plan['components']:
 if e['component_family']=='window':e.update({'variant_axis':'damage_state','variant_value':e['key'],'variant_reason':'intact/cracked/missing glass and boarded states from user reference'})
plan['stair_contract']={'base_z':0,'roof_z':60,'floor_height':5,'flights':24,'riser':2.5/14,'tread':.30,'steps_per_flight':14,'clear_width':1.5,'landing_depth':1.8,'handrail_height':1.1,'roof_gap_y':[-4.8,-1.2],'runtime_status':'pending_Godot_collision_navigation_capsule'}
(D/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf-8')
random.seed(110350)
def replace(k,g,bevel=.035):
 c=cols.get(k)
 if c is None:c=bpy.data.collections.new('ORF3_组件_'+k);src.children.link(c);cols[k]=c
 else:
  for o in list(c.objects):bpy.data.objects.remove(o,do_unlink=True)
 c.instance_offset=(0,0,0);lo=Vector([min(p[i] for p in g.v) for i in range(3)]);hi=Vector([max(p[i] for p in g.v) for i in range(3)]);offset=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z));g.v=[tuple(Vector(p)-offset) for p in g.v]
 for rr in sorted(set(g.r)):
  fi=[i for i,r in enumerate(g.r) if r==rr];used=sorted({j for i in fi for j in g.f[i]});remap={j:i for i,j in enumerate(used)};me=bpy.data.meshes.new('ORF3_'+k);me.from_pydata([g.v[i] for i in used],[],[[remap[j] for j in g.f[i]] for i in fi]);me.update();ob=bpy.data.objects.new('ORF3_'+spec[k]['name']+('_自发光' if rr==3 else '')+'_'+str(rr),me);c.objects.link(ob);me.materials.append(roles[rr]);uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True
  for p,i in zip(me.polygons,fi):
   ce=cells[g.c[i]];n=len(p.loop_indices)
   for j,li in enumerate(p.loop_indices):a=j*math.tau/n;uv.data[li].uv=((ce['column']+.5+.2*math.cos(a))/8,1-(ce['row']+.5-.2*math.sin(a))/8)
  if bevel:mod=ob.modifiers.new('项目实体柔边_三段','BEVEL');mod.width=bevel;mod.segments=3
  if spec[k]['category']=='flora':
   for p in me.polygons:p.use_smooth=True
 return offset
catgroups={'structure':out.children[0],'fixture':out.children[1],'flora':out.children[2]}
def inst(k,p,rz=0,scale=(1,1,1),tilt=(0,0)):
 o=bpy.data.objects.new('ORF3_实例_'+k,None);catgroups[spec[k]['category']].objects.link(o);o.instance_type='COLLECTION';o.instance_collection=cols[k];o['component_id']=spec[k]['asset_id'];o.location=p;o.rotation_euler=(tilt[0],tilt[1],rz);o.scale=scale;return o
def objs(k):return [o for o in s.objects if o.instance_type=='COLLECTION' and o.get('component_id')=='SEA-SCENE-ORF2-'+k.upper()]
# 1: perimeter ledges no longer extend past the reference primary facade plane.
g=Geo();g.box((0,0,.15),(46.6,30.5,.30),'cloud');replace('slab',g,.07)
# deep shadowed backing: columns remain forward, openings genuinely recessed.
g=Geo();g.box((0,0,29.8),(41.8,25.6,59.6),'gray');replace('shell',g,.1)
g=Geo();g.box((0,0,29.9),(3.1,1.55,59.8),'lightgray')
for z in [5.2,16.4,28.1,43.3,55.6]:g.patch((random.uniform(-.6,.6),-.783,z),random.uniform(.6,1.4),random.uniform(.6,1.8),'stone','XZ')
replace('pier',g,.095)
# balcony width fills bay; front edge behind column plane. Real returned sides and chipped lip.
g=Geo();g.box((0,0,.14),(12.0,2.4,.28),'cloud');g.box((0,-1.05,.57),(11.75,.17,.88),'lightgray')
for x in [-5.8,5.8]:g.box((x,0,.55),(.18,2.1,.85),'lightgray')
for x in [-5.6,-2.8,0,2.8,5.6]:g.rod((x,-1.08,.2),(x+.035,-1.1,1.25),.035,'wood_dark')
g.rod((-5.7,-1.1,1.25),(5.7,-1.1,1.23),.04,'steel');g.patch((2.3,-1.142,.7),1.3,.35,'gray','XZ');replace('balcony',g,.04)
for o in objs('balcony'):o.location.y=-14.6
# 2: window frame is open, not an opaque box with pretend breaks pasted over it.
for state in ['window','window_cracked','window_broken']:
 g=Geo();w=5.7;h=3.0
 for x in [-w/2,w/2]:g.box((x,0,h/2),(.16,.3,h),'silver',1)
 for z in [.08,h-.08]:g.box((0,0,z),(w,.3,.16),'gray')
 for x in [-.95,.95]:g.box((x,-.025,h/2),(.075,.18,h-.2),'steel',1)
 # pane segmentation, missing polygons expose inset dark recess, not surface stickers.
 for j in range(3):
  x=-2.75+j*1.83
  if state=='window_broken' and j==1:continue
  if state in ['window_broken','window_cracked'] and j==2:
   g.add([(x,-.04,.18),(x+1.7,-.04,.18),(x+1.7,-.04,2.0),(x+1.10,-.04,1.65),(x+.85,-.04,2.82),(x,-.04,2.82)],[(0,1,2,3,4,5)],'deepblue')
  else:g.box((x+.85,.025,1.5),(1.7,.035,2.65),'deepblue')
 if state!='window':
  for a,b in [((-.4,-.085,.55),(.12,-.085,1.4)),((.12,-.085,1.4),(-.22,-.085,2.5)),((.12,-.085,1.4),(.65,-.085,1.8))]:g.rod(a,b,.013,'ice',0)
 if state=='window_broken':
  g.box((-.9,-.19,1.2),(2.4,.12,.22),'wood_mid',rot=(0,.14,.1));g.box((-.7,-.2,1.9),(2.7,.12,.18),'wood_dark',rot=(0,-.12,-.10))
 g.box((0,.08,.08),(6.0,.5,.16),'cloud');replace(state,g,.02)
for i,o in enumerate(objs('window')):
 p=o.location.copy()
 if abs(p.y+14.85)<.3:o.location.y=-13.85
 elif abs(p.x)>22:o.location.x=math.copysign(21.75,p.x)
 pick='window_broken' if random.random()<.34 else 'window_cracked' if random.random()<.50 else 'window';o.instance_collection=cols[pick];o['component_id']=spec[pick]['asset_id']
# 3: roof rooms tilted roof plane and sloped wall crown. Keep footprints and lower facades.
for k,amount in [('platform',.075),('room',.09),('shed',.13)]:
 c=cols[k]
 for ob in c.objects:
  for v in ob.data.vertices:
   # topmost region only; floor and door bottoms remain level
   threshold=4.7 if k=='platform' else 2.45 if k=='room' else 2.65
   if v.co.z>threshold:v.co.z+=amount*v.co.y
  ob.data.update()
# 4: parapet no repeated dots; plain segments plus sparse independently varied moss clusters.
g=Geo();g.box((0,0,.55),(3.9,1.2,1.1),'cloud');g.box((0,0,1.10),(3.82,1.13,.035),'sage');g.patch((1.3,-.606,.5),.45,.3,'stone','XZ');replace('parapet',g,.10)
g=Geo()
for i in range(15):
 a=random.uniform(-1.3,1.3);z=random.uniform(.03,.45);g.patch((a,0,z),random.uniform(.2,.7),random.uniform(.08,.35),random.choice(['forest','sage','leaf_dark']),'XZ')
replace('moss_cluster',g,0)
# use broad leaf clusters with irregular lengths, remove all checkerboard corner vines
for o in list(objs('vine')):bpy.data.objects.remove(o,do_unlink=True)
for x,z,n in [(-23,49,8),(-8,36,3),(22.4,55,6),(7.5,12,3),(-22,26,4)]:
 for i in range(n):inst('vine',(x+random.uniform(-.6,.6),-16.4,z+random.uniform(-3,2)),random.uniform(-.14,.14),scale=(random.uniform(.6,1.3),1,random.uniform(.3,1.6)))
for side in [-1,1]:
 for x in [-19,-16,-7,11,19]:
  if random.random()<.62:inst('moss_cluster',(x+random.uniform(-1,1),side*16.015,60.05),math.pi if side>0 else 0,scale=(random.uniform(.7,1.6),1,random.uniform(.5,1.5)))
for y in [-10,-8,3,11]:inst('moss_cluster',(24.015,y,60.05),math.pi/2,scale=(random.uniform(.7,1.3),1,random.uniform(.7,1.6)))
# 5: open roof entry on right side, remove only authorized crossing parapet/rail segments.
removed=[]
for k in ['parapet','rail']:
 for o in list(objs(k)):
  if o.location.x>23 and abs(o.location.y+4)<.5:removed.append(o.name);bpy.data.objects.remove(o,do_unlink=True)
# standard half-floor stair runs +Y 4.2m / rises 2.5m, origin compensated for true bottom-center.
g=Geo();N=14;rise=2.5/N;run=.30;cw=1.5
for j in range(N):g.box((0,(j+.5)*run,(j+1)*rise-.045),(cw,run+.012,.09),'steel',1)
for x in [-cw/2,cw/2]:
 g.rod((x,0,.05),(x,4.2,2.5),.065,'wood_dark');g.rod((x,0,1.1),(x,4.2,3.6),.045,'wood_mid')
 for j in [0,3,7,10,14]:g.rod((x,j*run,j*rise),(x,j*run,j*rise+1.1),.035,'steel')
flight_offset=replace('stair_flight',g,.008)
g=Geo();g.box((0,0,.10),(4.0,1.8,.2),'steel',1)
# outward edge only, no cross rails over route exits
for x in [-2,2]:
 g.rod((x,-.9,.2),(x,.9,.2),.06,'wood_dark');g.rod((x,-.9,1.3),(x,.9,1.3),.04,'wood_mid')
 for y in [-.8,0,.8]:g.rod((x,y,.2),(x,y,1.3),.035,'steel')
landing_offset=replace('stair_landing',g,.01)
g=Geo();g.box((0,0,.1),(3.5,2.8,.2),'gray')
for y in [-1.4,1.4]:
 for z in [.75,1.2]:g.rod((-1.7,y,z),(1.7,y,z),.045,'wood_dark')
 for x in [-1.6,0,1.6]:g.rod((x,y,.2),(x,y,1.25),.04,'steel')
entry_offset=replace('roof_entry',g,.02)
route=[]
def place_comp(k,anchor,offset,rz=0):
 from mathutils import Euler
 a=Vector(anchor);rot=Euler((0,0,rz)).to_matrix();return inst(k,a+rot@offset,rz)
for floor in range(12):
 z=floor*5
 a=place_comp('stair_flight',(25,-3,z),flight_offset)
 b=place_comp('stair_flight',(27,1.2,z+2.5),flight_offset,math.pi)
 # landing lower edge y=1.2, joins both stair top/bottom exactly
 place_comp('stair_landing',(26,2.1,z+2.3),landing_offset)
 # whole-floor landing y=-4.8..-3 and surface top z
 place_comp('stair_landing',(26,-3.9,z-.2),landing_offset)
 route.append({'floor':floor,'flight_a':a.name,'flight_b':b.name,'a_start':[25,-3,z],'a_end':[25,1.2,z+2.5],'b_start':[27,1.2,z+2.5],'b_end':[27,-3,z+5]})
place_comp('stair_landing',(26,-3.9,59.8),landing_offset)
# roof entry bridge from landing into garden: x22..27, y -5.5..-2.7. Remain clear of farming beds.
place_comp('roof_entry',(24.3,-3.8,59.8),entry_offset)
# ground entry exterior approach, same package does not represent marine dock.
place_comp('roof_entry',(25.9,-6.2,-.2),entry_offset,math.pi/2)
# Last parapet gap adjacent -4 segment is 3.9m wide y=-5.95..-2.05.
# locks preserved: all original agriculture, greenhouse, solar, paths etc unchanged.
s.name='海上屋顶农场_轮廓破窗消防梯_v003';root.name='ORF3_屋顶农场_中文资产管理'
# camera angles retained, add actual side and facade detail inspection views.
def camera(name,pos,target,scale):
 ca=bpy.data.cameras.new(name);ob=bpy.data.objects.new(name,ca);qa.objects.link(ob);ob.location=pos;ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler();ca.type='ORTHO';ca.ortho_scale=scale;return ob
camera('ORF3_右侧消防梯全景',(100,-53,69),(22,-1,32),94)
camera('ORF3_消防梯屋顶入口',(47,-28,79),(24,-3,58),24)
camera('ORF3_凹窗破损近景',(21,-45,64),(7,-15,53),25)
# sample same-camera before/after source signature stored; output at new version only
(D/'stair_route.json').write_text(json.dumps({'contract':plan['stair_contract'],'floors':route,'removed_roof_barriers':removed,'entry_gap':{'x':[22.55,26.05],'y':[-5.2,-2.4],'floor_top_z':60}},ensure_ascii=False,indent=2),encoding='utf-8')
# All package geometry identity; preserve role/shared image references.
cat=[]
for k,c in cols.items():
 e=spec[k];pts=[v.co for ob in c.objects if ob.type=='MESH' for v in ob.data.vertices];e.update({'collection':c.name,'component_source':str((D/'component_packages'/k/(k+'.blend')).relative_to(R)).replace('\\','/'),'bounds_size_m':[max(v[i] for v in pts)-min(v[i] for v in pts) for i in range(3)],'instance_count':sum(o.instance_type=='COLLECTION' and o.instance_collection==c for o in s.objects),'source_version':'v003'});cat.append(e)
(D/'component_catalog.json').write_text(json.dumps({'components':cat},ensure_ascii=False,indent=2),encoding='utf-8')
instances=[{'name':o.name,'component_id':o.get('component_id'),'position_m':list(o.location),'rotation_euler_xyz':list(o.rotation_euler),'scale':list(o.scale)} for o in s.objects if o.instance_type=='COLLECTION'];(D/'component_instances.json').write_text(json.dumps({'instances':instances,'coordinate_mapping':'(x,y,z)->(x,z,-y)'},ensure_ascii=False,indent=2),encoding='utf-8')
s.render.resolution_percentage=85;s.cycles.samples=32
bpy.ops.wm.save_as_mainfile(filepath=str(D/'ocean_rooftop_farm_v003.blend'),compress=True)
print(json.dumps({'file':bpy.data.filepath,'components':len(cat),'instances':len(instances),'fire_flights':24,'entry_gap_removed':removed},ensure_ascii=False))
