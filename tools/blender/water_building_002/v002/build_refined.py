"""Number 002: bounded low-poly architecture, tree and facilities, MCP authoring."""
import bpy, bmesh, json, math, random, hashlib, os, shutil
from pathlib import Path
from mathutils import Vector, Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/water_building_002/v002';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'water_building_002/v002'
REF=Path('C:/Users/zhuangmenghong/.workbuddy/clipboard-images/clipboard-2026-11-10T02-51-58-980Z-73413825.jpg')
assert D.is_dir() and W.is_dir()
PAL=R/'art_source/shared/palettes/sea_cabin_timber_8x8_512.png'
REF_SHA=hashlib.sha256(REF.read_bytes()).hexdigest();shutil.copy2(REF,D/'reference.jpg')
PREFIX='SEA-SCENE-WATER-BUILDING-002';H=5.1;N=7;FW=14.8;FD=10.8;GROUND=.3;ROOF=GROUND+N*H
# Freeze the budget BEFORE making geometry; no unapproved texture or 3D lettering.
SPECS=[
 ('deck','structure','shell',.015,'platform'),('story_wall','structure','shell',.015,'wall'),('ground_wall','structure','shell',.015,'wall'),('floor_slab','structure','horizontal_cover',.015,'slab'),('parapet','structure','horizontal_cover',.018,'parapet'),
 ('front_window','furnishing','opening',.025,'window'),('side_window','furnishing','opening',.025,'window'),('entry','furnishing','opening',.025,'door'),('balcony','furnishing','horizontal_cover',.025,'balcony'),('ac_unit','furnishing','flat_attached',.035,'hvac'),('pipe','furnishing','linear',.06,'pipe'),('switchbox','furnishing','flat_attached',.03,'cabinet'),('solar_panel','furnishing','horizontal_cover',.02,'solar'),('solar_frame','furnishing','horizontal_cover',.02,'solar_support'),('roof_utilities','furnishing','freestanding',-.06,'roof_utility'),('antenna','furnishing','linear',.06,'aerial'),
 ('trunk_a','plant','plant',0,'tree_trunk'),('trunk_b','plant','plant',0,'tree_trunk'),('crown_a','plant','plant',0,'canopy'),('crown_b','plant','plant',0,'canopy'),('vine','plant','plant',0,'vine'),('planter','furnishing','freestanding',-.06,'planter'),('flower','plant','plant',0,'flower'),('wall_patch','furnishing','no_volume',0,'patch'),('brace','structure','vertical_structure',.02,'brace'),('orange_tank','furnishing','freestanding',-.06,'tank'),('small_sign','furnishing','flat_attached',.025,'sign'),('entry_step','structure','shell',.02,'step')]
plan={'schema':'sea.component_plan','status':'frozen_before_geometry','asset_id':PREFIX,'display_number':'002','version':'v002','building_class':'above_water','water_layer':'surface','water_layer_role':'entity','palette':PAL.relative_to(R).as_posix(),'reference_sha256':REF_SHA,'reference_image':'reference.jpg','size_assumptions':{'method':'single_image_ratio_not_measured','footprint':[FW,FD],'floors':N,'floor_pitch_m':H,'clear_height_m':4.9,'slab_thickness_m':.2,'roof_elevation_m':ROOF,'ground_deck_top_m':.3},'budget':{'basis':'all_visible_depsgraph_instances_after_modifiers','target_triangles':10000,'max_triangles':11000,'bevel_segments_exception':1,'preserve':['cream_old_building','green_windows','roof_solar_grid','solar_side_canopy','large_wrapping_tree_trunks','layered_leaf_crowns','square_hvac','balcony_rail'],'omit':['3D_text','tiny_screws','photographic_weathering','background_city','cars','people']},'components':[{'key':k,'id':PREFIX+'-'+k.upper().replace('_','-'),'asset_id':PREFIX+'-'+k.upper().replace('_','-'),'group':g,'kind':kind,'rho':rho,'family':fam,'origin':'bottom_center','front_axis':'-Y','scope':'scene_local','source_version':'v002'} for k,g,kind,rho,fam in SPECS]}
(D/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Safety copy of the live session. Only this new output scene is authored.
if not (W/'session_before_refine.blend').exists():bpy.ops.wm.save_as_mainfile(filepath=str(W/'session_before_refine.blend'),copy=True)
# Separate data scope: previous 001 and failed 002 v001 files are never saved.
old=bpy.context.scene
sc=bpy.data.scenes.new('WB002_Refined_v002');win=bpy.context.window or next(iter(bpy.context.window_manager.windows));win.scene=sc
for s in list(bpy.data.scenes):
 if s!=sc:bpy.data.scenes.remove(s)
# Drop unused old data in memory only to prevent .001 role copies and large source files.
for o in list(bpy.data.objects):
 if o.users==0:bpy.data.objects.remove(o)
sc.unit_settings.system='METRIC';sc.unit_settings.scale_length=1
cells={c['name']:c for c in json.loads(PAL.with_suffix('.json').read_text(encoding='utf-8'))['cells']}
image=bpy.data.images.load(str(PAL),check_existing=True);image.filepath=str(PAL)
roles={}
for role,rough,metal in [('SEA_Matte',.78,0),('SEA_Metal',.55,.25),('SEA_Gloss',.3,0)]:
 m=bpy.data.materials.new('WB002V2_'+role);m['semantic_role']=role;m.use_nodes=True
 bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal
 uv=m.node_tree.nodes.new('ShaderNodeUVMap');uv.uv_map='PaletteUV';tx=m.node_tree.nodes.new('ShaderNodeTexImage');tx.image=image;tx.interpolation='Closest';tx.extension='EXTEND';m.node_tree.links.new(uv.outputs['UV'],tx.inputs['Vector']);m.node_tree.links.new(tx.outputs['Color'],bs.inputs['Base Color']);roles[role]=m
random.seed(1002);current=None;cols={};catalog=[];instances=[];witness=[];by={c['key']:c for c in plan['components']}
top={}
for key,name in [('structure','01_Architecture'),('furnishing','02_Fixtures'),('plant','03_SeparateVegetation'),('display','90_DisplaySupport')]:
 c=bpy.data.collections.new('WB002V2_'+name);sc.collection.children.link(c);top[key]=c

def uvpaint(o,color,role,smooth=False):
 me=o.data;assert color in cells,color;cell=cells[color];cx=(cell['column']+.5)/8;cy=1-(cell['row']+.5)/8
 for u in list(me.uv_layers):me.uv_layers.remove(u)
 u=me.uv_layers.new(name='PaletteUV');u.active_render=True
 for f in me.polygons:
  f.use_smooth=smooth
  for j,li in enumerate(f.loop_indices):
   a=2*math.pi*j/f.loop_total;u.data[li].uv=(cx+.028*math.cos(a),cy+.028*math.sin(a))
 me.materials.clear();me.materials.append(roles[role]);o['palette_color']=color;o['semantic_role']=role;return o

def make(name,vs,fs,color='plaster',role='SEA_Matte',bevel=0,rho=None,smooth=False,organic=False):
 me=bpy.data.meshes.new('WB002V2_'+name);me.from_pydata(vs,[],fs);me.update();o=bpy.data.objects.new('WB002V2_'+name,me);current.objects.link(o)
 if bevel:
  bm=bmesh.new();bm.from_mesh(me);bmesh.ops.bevel(bm,geom=list(bm.edges),offset=bevel,segments=1,affect='EDGES',clamp_overlap=True);bm.to_mesh(me);bm.free();me.update()
 if not organic and rho is not None and rho!=0:
  lo=Vector(tuple(min(v.co[a] for v in me.vertices) for a in range(3)));hi=Vector(tuple(max(v.co[a] for v in me.vertices) for a in range(3)));ext=hi-lo;axis=max(range(3),key=lambda a:ext[a]);cen=(lo+hi)*.5;pre=[tuple(v.co) for v in me.vertices]
  for v in me.vertices:
   t=(v.co[axis]-lo[axis])/ext[axis]
   for j in range(3):
    if j!=axis:v.co[j]=cen[j]+(v.co[j]-cen[j])*(1-rho*t)
  o['actual_taper_axis']='xyz'[axis];o['actual_rho']=rho
  witness.append({'object':o.name,'axis':axis,'rho':rho,'extent_before':list(ext),'center':list(cen),'axis_min':lo[axis],'sample_before':pre,'bevel':bevel})
 o['bevel_width_m']=bevel;o['bevel_segments']=int(bool(bevel));me.update();return uvpaint(o,color,role,smooth)

def box(n,p,s,c='plaster',role='SEA_Matte',b=0,r=.02):
 v=[tuple(p[j]+q[j]*s[j]/2 for j in range(3)) for q in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
 return make(n,v,[(3,2,1,0),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)],c,role,b,r)

def tube(n,pts,rad,c='bark',sides=6,organic=True):
 pts=[Vector(p) for p in pts];vs=[]
 for i,p in enumerate(pts):
  t=(pts[min(i+1,len(pts)-1)]-pts[max(i-1,0)]).normalized();up=Vector((0,0,1)) if abs(t.z)<.9 else Vector((0,1,0));u=t.cross(up).normalized();v=t.cross(u).normalized();rr=rad*(1-(.65 if organic else .06)*i/(len(pts)-1))
  vs.extend(tuple(p+rr*(u*math.cos(2*math.pi*j/sides)+v*math.sin(2*math.pi*j/sides))) for j in range(sides))
 fs=[tuple(reversed(range(sides))),tuple((len(pts)-1)*sides+j for j in range(sides))]+[(i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j) for i in range(len(pts)-1) for j in range(sides)]
 o=make(n,vs,fs,c,'SEA_Matte',smooth=True,organic=True);o['diameter_ratio']=.35 if organic else .94;return o

def crown(n,p,s,color='leaf_mid',detail=1):
 bm=bmesh.new();bmesh.ops.create_icosphere(bm,subdivisions=detail,radius=1);bm.verts.ensure_lookup_table();vs=[]
 for v in bm.verts:
  a=v.co;f=1+random.uniform(-.13,.13);vs.append(tuple(p[j]+a[j]*s[j]*f for j in range(3)))
 fs=[tuple(v.index for v in f.verts) for f in bm.faces];bm.free();return make(n,vs,fs,color,smooth=True,organic=True)

def frame(n,w,h,depth=.18):
 # Direct annular frame, not a solid panel pasted over the opening.
 outer=[(-w/2,0,0),(w/2,0,0),(w/2,0,h),(-w/2,0,h)]
 inner=[(-w/2+.13,0,.13),(w/2-.13,0,.13),(w/2-.13,0,h-.13),(-w/2+.13,0,h-.13)]
 vs=outer+inner+[(x,depth,z) for x,y,z in outer]+[(x,depth,z) for x,y,z in inner];fs=[]
 for i in range(4):
  j=(i+1)%4;fs.extend([(i,j,4+j,4+i),(8+j,8+i,12+i,12+j),(j,i,8+i,8+j),(4+i,4+j,12+j,12+i)])
 return make(n,vs,fs,'wood_edge',rho=.025)

def part(key,fn):
 global current
 e=by[key];current=bpy.data.collections.new(e['asset_id']);sc.collection.children.link(current);current['asset_id']=e['asset_id'];current['kind']=e['kind'];fn();obs=[o for o in current.objects if o.type=='MESH'];pts=[v.co for o in obs for v in o.data.vertices]
 lo=Vector(tuple(min(v[a] for v in pts) for a in range(3)));hi=Vector(tuple(max(v[a] for v in pts) for a in range(3)));pivot=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 for o in obs:
  o.data.transform(Matrix.Translation(-pivot));o['component_key']=key;o['asset_id']=e['asset_id']
 for rec in witness:
  if any(o.name==rec['object'] for o in obs):rec['pivot']=list(pivot);rec['component_key']=key
 current.instance_offset=(0,0,0);sc.collection.children.unlink(current);cols[key]=current
 for o in obs:o.data.calc_loop_triangles()
 row=dict(e,collection=current.name,design_pivot=list(pivot),bounds_size=list(hi-lo),triangles=sum(len(o.data.loop_triangles) for o in obs),polygons=sum(len(o.data.polygons) for o in obs),meshes=len(obs),material_roles=sorted({o['semantic_role'] for o in obs}),component_source=f'art_source/scenes/water_building_002/v002/component_packages/{key}/{key}.blend')
 h=hashlib.sha256()
 for o in obs:
  for v in o.data.vertices:h.update((','.join(format(float(x),'.6f') for x in v.co)+';').encode())
 row['geometry_fingerprint']=h.hexdigest();catalog.append(row);print('COMPONENT',key,row['triangles'],flush=True)

def put(k,p=(0,0,0),rot=(0,0,0)):
 e=next(x for x in catalog if x['key']==k);o=bpy.data.objects.new('WB002V2_I_'+k+'_'+str(sum(x['key']==k for x in instances)+1).zfill(3),None);o.instance_type='COLLECTION';o.instance_collection=cols[k];o.rotation_euler=rot;o.location=Vector(p)+o.rotation_euler.to_matrix()@Vector(e['design_pivot']);top[e['group']].objects.link(o);instances.append({'name':o.name,'key':k,'asset_id':e['asset_id'],'position':list(o.location),'rotation_euler_xyz':list(o.rotation_euler),'scale':[1,1,1]});return o

def wall():
 # Hollow facade bays, clear glazing apertures; no whole-building solid cube.
 for y in [-5.4,5.4]:
  for z,h in [(.65,.9),(4.575,1.05)]:box('FacadeBand',(0,y,z),(14.8,.3,h),r=.015)
  for x in [-6.55,6.55]:box('FacadePier',(x,y,2.575),(1.7,.3,3.85),r=.015)
 for x in [-7.4,7.4]:
  for z,h in [(.65,.9),(4.575,1.05)]:box('SideBand',(x,0,z),(.3,10.4,h),r=.015)
  for y in [-4.4,0,4.4]:box('SidePier',(x,y,2.575),(.3,1.6,3.85),r=.015)
part('story_wall',wall)
def groundwall():
 for x in [-7.4,7.4]:box('GroundSide',(x,0,2.65),(.3,10.8,4.9),b=.035,r=.015)
 box('GroundBack',(0,5.4,2.65),(14.5,.3,4.9),b=.035,r=.015)
 for x in [-5.3,5.3]:box('EntrySidePier',(x,-5.4,2.65),(4.0,.3,4.9),r=.015)
 box('EntryLintel',(0,-5.4,4.55),(6.3,.3,1.1),r=.015)
part('ground_wall',groundwall)
part('deck',lambda:box('Foundation',(0,0,.2),(18.4,14.4,.2),'stone',b=.075,r=.015))
part('floor_slab',lambda:box('FloorSlab',(0,0,.1),(15.3,11.3,.2),'plaster',b=.045,r=.015))
def para():
 for y in [-5.6,5.6]:box('Parapet',(0,y,.45),(15.5,.28,.9),'plaster',r=.018)
 for x in [-7.6,7.6]:box('ParapetReturn',(x,0,.45),(.28,10.85,.9),'plaster',r=.018)
part('parapet',para)
def fw():
 frame('WindowFrame',10.8,2.8)
 # Individual panes inside frame with 6mm perimeter clearance.
 box('GreenPane',(0,.095,1.4),(10.50,.035,2.49),'jade','SEA_Gloss',r=.025)
 for x in [-2.645,0,2.645]:box('WindowMullion',(x,.02,1.4),(.085,.08,2.51),'wood_dark',r=.025)
part('front_window',fw)
def sw():
 frame('SideWindowFrame',2.7,2.8)
 box('SideGlass',(0,.095,1.4),(2.40,.035,2.49),'petrol','SEA_Gloss',r=.025)
 # Side panes stay broad: omit the tiny central mullion in the 10k variant.
part('side_window',sw)
def entry():
 frame('EntryDoorFrame',3.5,3.7,.24)
 for x in [-.85,.85]:
  box('EntryDoor',(x,.08,1.85),(1.55,.12,3.42),'wood_mid',r=.025)
  box('EntryDoorGlass',(x,-.012,2.15),(1.22,.012,2.18),'jade','SEA_Gloss',r=.025)
part('entry',entry)
def balcony():
 box('BalconyDeck',(0,-.60,.1),(11.5,1.35,.2),'plaster',b=.045,r=.025)
 for x in [-5.58,5.58]:box('BalconyRailSide',(x,-.62,1.0),(.07,1.18,.07),'steel','SEA_Metal',r=.06)
 box('BalconyHandrail',(0,-1.27,1.1),(11.45,.07,.08),'steel','SEA_Metal',r=.06)
 for i in range(7):box('BalconySpindle',(-5.4+i*1.8,-1.27,.64),(.06,.06,.85),'steel','SEA_Metal',r=.06)
part('balcony',balcony)
def ac():
 box('SquareACBody',(0,.25,.48),(1.4,.55,.96),'mint_white',r=.035)
 box('SquareVent',(0,-.04,.50),(.94,.016,.61),'slate',r=.035)
 # Chunky slat hint, not a circular fan/mesh.
 for z in [.48]:box('SquareVentSlat',(0,-.055,z),(.90,.012,.035),'stone',r=.035)
part('ac_unit',ac)
part('pipe',lambda:tube('ExposedPipe',[(0,0,0),(.0,0,3.5),(.3,0,4.4),(.3,0,5.0)],.065,'sage_gray',6,False))
part('switchbox',lambda:[box('WallCabinet',(0,.18,.55),(.8,.38,1.1),'sage_gray',r=.03),box('CabinetInset',(0,-.018,.55),(.61,.012,.76),'mint_white',r=.03)])
def solar():
 box('PanelFrame',(0,0,.055),(2.9,2.0,.11),'stone','SEA_Metal',r=.02)
 box('SolarFace',(0,0,.121),(2.78,1.88,.012),'deepblue','SEA_Gloss',r=.02)
 # Geometry grid, no extra texture, sits 5mm above cells.
 for x in [0]:box('SolarGridX',(x,0,.135),(.014,1.83,.006),'sky',r=.02)
 for y in [0]:box('SolarGridY',(0,y,.136),(2.74,.014,.006),'sage_gray',r=.02)
part('solar_panel',solar)
def sf():
 for x in [-4.5,4.5]:box('CanopyBeam',(x,0,0),(.16,5.6,.2),'stone','SEA_Metal',r=.02)
 for y in [-2.7,2.7]:box('CanopyCrossbar',(0,y,0),(9.15,.16,.2),'stone','SEA_Metal',r=.02)
part('solar_frame',sf)
def utility():
 box('RoofEquipment',(0,0,.65),(1.4,1.2,1.3),'sage_gray',b=.04,r=-.06)
 box('RoofEquipmentCap',(0,0,1.36),(1.6,1.4,.12),'stone',r=-.06)
 tube('RoofVent',[(.40,0,1.45),(.40,0,2.7)],.18,'silver',6,False)
part('roof_utilities',utility)
part('antenna',lambda:[tube('AerialMast',[(0,0,0),(0,0,4.0)],.045,'steel',6,False),tube('AerialHorizontal',[(-.9,0,3.7),(.9,0,3.7)],.03,'steel',6,False)])

def trunk_a():
 tube('OrganicTrunk',[(0,0,0),(.4,-.2,5),(-.35,-.15,10),(.2,0,15),(-.5,.2,20),(.1,-.2,25),(.5,0,30),(0,0,39)],.80,'bark',8)
 for pts in [[(.0,0,1),(-1.8,-1.2,.25),(-3.2,-1.5,.15)],[(.3,0,8),(1.8,-.4,12),(3.8,-.4,15)],[(-.4,0,19),(-2.5,-.8,23),(-4.2,-.6,24.8)],[(.4,0,29),(2.0,-.4,32),(3.7,-.2,34)],[(0,0,35),(-2.2,-.5,38),(-4,-.4,40)]]:tube('Branch',pts,.34,'wood_dark',6)
part('trunk_a',trunk_a)
def trunk_b():
 tube('SecondTrunk',[(0,0,0),(-.25,0,7),(.25,-.15,14),(-.35,0,21),(.25,0,29),(0,0,38)],.62,'bark',7)
 for pts in [[(0,0,5),(-2,-.6,9),(-3.4,-.5,11)],[(0,0,18),(-2,-.5,22),(-3.5,-.5,24)],[(0,0,28),(2,-.5,33),(3.8,-.3,34)]]:tube('SideBranch',pts,.25,'wood_dark',6)
part('trunk_b',trunk_b)
def ca():
 crown('CanopyCore',(0,0,0),(2.25,1.85,1.35),'leaf_mid',1)
 for i in range(3):
  a=i*2.4;crown('CanopyLobe',(1.65*math.cos(a),1.2*math.sin(a),.35*math.sin(i)),(.95,.85,.75),['leaf','leaf_light','leaf_yellow'][i%3],1)
part('crown_a',ca)
def cb():
 for i in range(3):
  a=i*2.4;crown('SunnyFoliage',(1.3*math.cos(a),.9*math.sin(a),.25*math.sin(i)),(1.2,1.,.80),['leaf','leaf_yellow','leaf_light'][i%3],1)
part('crown_b',cb)
def vine():
 pts=[(math.sin(i)*.12,0,2.6-i*.65) for i in range(5)];tube('HangingVine',pts,.025,'forest',4,True)
 for i in range(8):
  x=(-1 if i%2 else 1)*.22;z=2.45-i*.31;v=[(0,0,z+.15),(x,-.06,z+.10),(x*1.8,0,z-.11),(x,.08,z-.23),(x*.8,-.12,z-.08)];make('VineLeaf',v,[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],['leaf','forest','leaf_light'][i%3],organic=True,smooth=True)
part('vine',vine)
part('planter',lambda:[box('BoxPlanter',(0,0,.3),(1.8,.75,.6),'wood_mid',b=.035,r=-.06),box('PlanterSoil',(0,0,.615),(1.60,.55,.03),'darkwood',r=-.06)])
def flowers():
 for i in range(3):
  p=(-.58+i*.58,0,.3+(.12 if i%2 else 0));crown('Foliage',p,(.41,.30,.28),'leaf_mid',1)
  # Eight-triangle flower buds rather than individual icosphere petals.
  x,y,z=p[0],-.09,p[2]+.24
  make('FlowerBud',[(x-.12,y,z),(x,y-.12,z),(x+.12,y,z),(x,y+.12,z),(x,y,z+.12),(x,y,z-.08)],[(0,1,4),(1,2,4),(2,3,4),(3,0,4),(1,0,5),(2,1,5),(3,2,5),(0,3,5)],['red','gold','ochre'][i%3],organic=True,smooth=True)
part('flower',flowers)
def patch():
 make('PlasterWear',[(-.55,0,0),(.5,0,.10),(.6,0,.50),(.1,0,.80),(-.6,0,.43)],[(0,1,2,3,4)],'stone',organic=True)
part('wall_patch',patch)
part('brace',lambda:box('ConcreteQuoin',(0,0,.24),(.68,.42,.48),'stone',b=.035,r=.02))
part('orange_tank',lambda:[box('OrangeRoofTank',(0,0,.9),(1.9,1.7,1.8),'ochre',b=.045,r=-.06),box('TankLid',(0,0,1.86),(2.,1.8,.12),'red_dark',r=-.06)])
part('small_sign',lambda:[box('BlankOrangePlaque',(0,0,.4),(.8,.10,.8),'ochre',b=.02,r=.025),box('PlaqueSymbol',(0,-.064,.4),(.28,.012,.36),'cream',r=.025)])
part('entry_step',lambda:box('EntranceStep',(0,0,.10),(4.4,1.35,.20),'stone',b=.04,r=.02))
# Assembly design origins remain distinct from bottom-center component pivots.
put('deck')
put('ground_wall',(0,0,GROUND))
for i in range(1,N):put('story_wall',(0,0,GROUND+i*H))
for i in range(N+1):put('floor_slab',(0,0,GROUND+i*H))
put('parapet',(0,0,ROOF+.21));put('entry',(0,-5.57,GROUND+.02));put('entry_step',(0,-6.2,GROUND))
for i in range(1,N):
 z=GROUND+i*H+1.13;put('front_window',(0,-5.61,z));put('front_window',(0,5.61,z),rot=(0,0,math.pi))
 for yy in [-2.3,2.3]:
  put('side_window',(7.61,yy,z),rot=(0,0,math.pi/2));put('side_window',(-7.61,yy,z),rot=(0,0,-math.pi/2))
 if i in [1,3]:put('balcony',(0,-5.58,GROUND+i*H+.015))
for i in range(1,N):
 z=GROUND+i*H+1.4
 put('ac_unit',(7.7,(-3.9 if i%2 else .2),z),rot=(0,0,math.pi/2))
 put('ac_unit',(-7.7,2.8,z+.4),rot=(0,0,-math.pi/2))
 put('switchbox',(7.7,3.8,z-.8),rot=(0,0,math.pi/2))
for z in [1,7,13,19,25,31]:put('pipe',(7.9,1.0,z));put('pipe',(-7.9,4.7,z))
for x in [-4.55,-1.52,1.52,4.55]:
 for y in [-2.05,.05,2.15]:put('solar_panel',(x,y,ROOF+.23))
# Right-hand solar lean-to is a key reference silhouette.
canopy=(11.,1.0,GROUND+3*H+.55);put('solar_frame',canopy,rot=(0,-.08,0))
for x in [8.,11.,14.]:
 for y in [-.9,1.2]:put('solar_panel',(x,y,canopy[2]+.20+(x-11)*.08),rot=(0,-.08,0))
put('roof_utilities',(4.7,3.7,ROOF+.21));put('roof_utilities',(-4.7,3.7,ROOF+.21));put('orange_tank',(-4.6,2.7,ROOF+.21));put('antenna',(6.5,4.2,ROOF+.21))
# Independent large trunks wrap outside the two visible corners, not through building rooms.
put('trunk_a',(8.25,-5.85,GROUND));put('trunk_b',(-8.25,-5.8,GROUND))
# Crown coordinates follow the actual branch endpoints and form separated organic tiers.
for p in [(10.7,-6.2,14.6),(10.4,-5.2,15.6),(5.0,-6.0,24.6),(2.2,-6.1,25.8),(9.8,-5.7,33.8),(11.2,-5.2,34.8),(6.0,-5.5,39.1),(3.5,-5.7,40.0),(-8.0,-6.0,24.1),(-10.,-5.5,11.0),(-7.,-5.8,35.0),(-5.,-5.,38.2)]:put('crown_a',p)
for p in [(11.5,-5.5,15.),(2.0,-5.8,24.8),(12.,-4.8,34.),(1.9,-5.,40.),(-10.8,-5.5,11.2),(-5.,-5.8,35.5)]:put('crown_b',p)
for i in [1,3,5,6]:
 for x in [-6.0,6.2]:put('vine',(x,-5.85,GROUND+i*H-.6))
for p in [(-4.3,-6.0,GROUND),(4.3,-6.0,GROUND),(-7.8,-4.,GROUND),(-3.6,-6.45,GROUND+H+.22),(3.6,-6.45,GROUND+3*H+.22),(-3.6,-6.45,GROUND+5*H+.22)]:put('planter',p);put('flower',(p[0],p[1],p[2]+.65))
for i in [0,1,3,5]:
 for x in [-6.6,6.6]:put('brace',(x,-5.65,GROUND+i*H+.5))
for i in range(6):put('wall_patch',(-5.0 if i%2 else 5.0,-5.565,GROUND+i*H+4.15))
for p in [(2.5,-5.62,GROUND+2.5),(-3.,-5.62,GROUND+1.5),(7.7,3.,GROUND+2.5)]:put('small_sign',p,rot=(0,math.radians(5),0))
# display support: no geometry counted or exported with game components.
current=top['display'];ground=box('StudioGround',(0,0,-.12),(140,140,.10),'sage_gray',r=0);ground['display_support']=True
world=bpy.data.worlds.new('WB002V2_World');world.use_nodes=True;bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.25,.34,.36,1);bg.inputs[1].default_value=.55;sc.world=world
for n,p,e,size in [('Key',(-30,-40,65),8000,23),('Fill',(36,-14,42),5000,25),('Rim',(0,30,55),6500,20)]:
 ld=bpy.data.lights.new('WB002V2_'+n,'AREA');ld.energy=e;ld.shape='DISK';ld.size=size;o=bpy.data.objects.new(ld.name,ld);current.objects.link(o);o.location=p;o.rotation_euler=(Vector((0,0,18))-o.location).to_track_quat('-Z','Y').to_euler()
cd=bpy.data.cameras.new('WB002V2_Camera');cam=bpy.data.objects.new(cd.name,cd);current.objects.link(cam);cam.location=(52,-70,55);cam.rotation_euler=(Vector((1.,0,20))-cam.location).to_track_quat('-Z','Y').to_euler();cd.type='ORTHO';cd.ortho_scale=53;sc.camera=cam
sc.render.engine='CYCLES';sc.cycles.samples=24;sc.cycles.use_denoising=True;sc.render.resolution_x=1050;sc.render.resolution_y=1400;sc.render.resolution_percentage=100;sc.render.image_settings.file_format='PNG';sc.view_settings.view_transform='Standard'
sc['asset_id']=PREFIX;sc['building_class']='above_water';sc['source_version']='v002';sc['reference_sha256']=REF_SHA
# Resolve plan extents from REAL masters. All pieces are single-pivot zero-transform meshes.
for e in catalog:
 p=by[e['key']];p['extent']=e['bounds_size'];axis=max(range(3),key=lambda a:e['bounds_size'][a]);p['taper_along']='xyz'[axis];p['bottom']=1.;p['top']=1-p['rho'];p['bevel']=.008
 if p['kind']=='linear':p['d_bottom']=.10;p['d_top']=.094
 if p['kind']=='no_volume':p.update(no_volume=True,thickness=0.,bevel=.008)
 if p['key']=='small_sign':p['tilt_deg']=5.
plan['stylized_form']={'form_style':'SF-A','body':{'width_base':14.8,'width_top':14.8*.985,'height':35.7},'components':plan['components'],'relief':{'quoin_blocks':8,'brackets':0,'grooves':0,'brick_blocks':0},'contacts':[{'a':PREFIX+'-FRONT-WINDOW','b':PREFIX+'-STORY-WALL','relation':'clearance','gap_m':.006,'scope':'designed_aperture_perimeter_pending_measured'}]};plan['status']='geometry_candidate_pending_source_audit'
(D/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'catalog.json').write_text(json.dumps({'schema':'sea.component_catalog','components':catalog},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_instances.json').write_text(json.dumps({'schema':'sea.component_instances','coordinate_contract':{'plane':'XY','up':'+Z','godot_mapping':'(x,y,z)->(x,z,-y)','rotation':'Euler XYZ radians'},'instances':instances},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(W/'taper_witness.json').write_text(json.dumps({'records':witness},indent=2)+'\n',encoding='utf-8')
bpy.context.preferences.filepaths.save_version=0;S=D/'water_building_002_v002.blend';bpy.ops.wm.save_as_mainfile(filepath=str(S),compress=True)
T=sum(e['triangles']*sum(i['key']==e['key'] for i in instances) for e in catalog)
(W/'draft_counts.json').write_text(json.dumps({'triangles':T,'components':len(catalog),'instances':len(instances),'source_sha256':hashlib.sha256(S.read_bytes()).hexdigest()},indent=2)+'\n',encoding='utf-8')
sc.render.filepath=str(W/'hero.png');bpy.ops.render.render(write_still=True)
print('REFINED002',json.dumps({'triangles':T,'components':len(catalog),'instances':len(instances),'source':str(S)},ensure_ascii=False),flush=True)
