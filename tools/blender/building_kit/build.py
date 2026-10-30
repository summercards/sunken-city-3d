"""New modular kit only; never regenerate existing scene assets."""
import bpy,json,math,hashlib,os,sys
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from export_component import export_component, normalize_palette_uv
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/ocean_building_kit/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'building_kit_v001';W.mkdir(parents=True,exist_ok=True)
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));assert P['status']=='frozen_before_geometry'
assert not (D/'building_kit.blend').exists(),'Do not overwrite authored sources'
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
S=bpy.context.scene;S.name='建筑与生活摆件_展示';LIB=bpy.data.scenes.new('组件母版_独立维护')
structures=bpy.data.collections.new('建筑结构');decor=bpy.data.collections.new('生活摆件');LIB.collection.children.link(structures);LIB.collection.children.link(decor)
img=bpy.data.images.load(str(R/P['palette']));cells={x['name']:x for x in json.loads((R/P['palette']).with_suffix('.json').read_text())['cells']}
M={}
for role in ['Matte','Metal','Gloss','Emission']:
 m=bpy.data.materials.new('SEA_'+role);m.use_nodes=True;nt=m.node_tree;bs=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED');tex=nt.nodes.new('ShaderNodeTexImage');tex.image=img;tex.interpolation='Closest';uv=nt.nodes.new('ShaderNodeUVMap');uv.uv_map='PaletteUV';nt.links.new(uv.outputs['UV'],tex.inputs['Vector']);nt.links.new(tex.outputs['Color'],bs.inputs['Base Color']);bs.inputs['Roughness'].default_value=.8 if role=='Matte' else .28
 if role=='Metal':bs.inputs['Metallic'].default_value=.6
 if role=='Emission':nt.links.new(tex.outputs['Color'],bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=2
 M[role]=m
col=None
def finish(o,name,color='wood_light',role='Matte',bevel=0):
 o.name=name
 for c in list(o.users_collection):c.objects.unlink(o)
 col.objects.link(o);bpy.context.view_layer.objects.active=o
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 if bevel:
  mod=o.modifiers.new('实体倒角','BEVEL');mod.width=bevel;mod.segments=2;bpy.ops.object.modifier_apply(modifier=mod.name)
 o.data.materials.append(M[role]);uv=o.data.uv_layers.get('PaletteUV') or o.data.uv_layers.new(name='PaletteUV')
 for layer in list(o.data.uv_layers):
  if layer.name!='PaletteUV':o.data.uv_layers.remove(layer)
 o.data.uv_layers.active_index=0;uv.active_render=True;c=cells[color];u=(c['column']+.5)/8;v=1-(c['row']+.5)/8
 for f in o.data.polygons:
  for j,l in enumerate(f.loop_indices):a=math.tau*j/len(f.loop_indices);uv.data[l].uv=(u+.025*math.cos(a),v+.025*math.sin(a))
 return o
def box(name,p,d,c='wood_light',b=.025,rot=0):
 bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.scale=d;o.rotation_euler.z=rot;return finish(o,name,c,bevel=b)
def cyl(name,p,r,h,c='wood_mid',role='Matte',rot=None):
 bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=r,depth=h,location=p);o=bpy.context.object
 if rot:o.rotation_euler=rot
 return finish(o,name,c,role,.012)
def sphere(name,p,scale,c='moss_light',role='Matte'):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=6,location=p);o=bpy.context.object;o.scale=scale
 for f in o.data.polygons:f.use_smooth=True
 return finish(o,name,c,role)
def bar(name,a,b,r=.045,c='wood_mid'):
 mid=(Vector(a)+Vector(b))/2;diff=Vector(b)-Vector(a)
 bpy.ops.mesh.primitive_cylinder_add(vertices=8,radius=r,depth=diff.length,location=mid);o=bpy.context.object;o.rotation_euler=diff.to_track_quat('Z','Y').to_euler();return finish(o,name,c,bevel=.008)
def planks(w,d,z=0,h=.16):
 count=round(w/.25)
 for j in range(count):box('plank_%02d'%j,(-w/2+(j+.5)*w/count,0,z-h/2),(w/count-.012,d,h),'wood_light' if j%3 else 'wood_mid',.016)
def lamp(z=0):
 cyl('lamp_base',(0,0,z+.055),.17,.11,'steel','Metal');cyl('glass',(0,0,z+.28),.12,.32,'sand','Gloss');sphere('emission_flame',(0,0,z+.29),(.06,.06,.12),'honey','Emission');cyl('lamp_cap',(0,0,z+.49),.16,.08,'steel','Metal')
 for x,y in [(-.12,0),(.12,0)]:bar('cage',(x,y,z+.1),(x,y,z+.49),.016,'steel')
 bar('handle',(-.12,0,z+.51),(0,0,z+.65),.018,'steel');bar('handle',(0,0,z+.65),(.12,0,z+.51),.018,'steel')
records=[]
for index,e in enumerate(P['components']):
 key=e['id'];col=bpy.data.collections.new(e['asset_id']);(structures if index<12 else decor).children.link(col);S.collection.children.link(col);col.instance_offset=(0,0,0)
 if key.startswith('raft_'):
  w,d=e['footprint'];planks(w,d,0,.5)
  for y in [-d/2+.18,d/2-.18]:box('cross_brace',(0,y,-.34),(w,.16,.20),'wood_edge')
 elif key=='wall':
  for i in range(7):box('wall_board',(0,0,(i+.5)*.4),(2,.14,.39),'wood_light' if i%2 else 'wood_mid')
 elif key in ['window_wall','door_frame']:
  opening=1.08 if key=='window_wall' else 1.1
  for x in [-.79,.79]:box('wall_side',(x,0,1.4),(.42,.16,2.8),'wood_mid')
  box('lintel',(0,0,2.6),(1.2,.18,.4),'wood_edge')
  if key=='window_wall':
   box('window_sill',(0,0,.7),(1.2,.28,.18),'wood_edge');box('lower_wall',(0,0,.3),(1.2,.14,.6),'wood_light');box('window_mullion',(0,0,1.65),(.065,.12,1.7),'cream')
 elif key=='post':box('post',(0,0,1.4),(.2,.2,2.8),'wood_mid',.025)
 elif key=='beam':box('beam',(0,0,.1),(2,.2,.2),'wood_mid');box('peg',(-.8,0,.08),(.08,.28,.08),'wood_edge')
 elif key=='railing':
  for x in [-.9,.9]:box('upright',(x,0,.5),(.12,.14,1),'wood_edge')
  box('handrail',(0,0,1),(2,.18,.12),'wood_light');bar('diagonal',(-.85,0,.18),(.85,0,.90));bar('diagonal',(-.85,0,.90),(.85,0,.18))
 elif key=='stairs':
  for j in range(14):box('step_%02d'%j,(0,2-(j+.5)*4/14,(j+1)*.2-.075),(1.2,4/14+.015,.15),'wood_light',.012)
  for x in [-.51,.51]:bar('stringer',(x,1.90,.05),(x,-1.95,2.68),.075)
 elif key=='upper_floor':planks(2,2,.0,.18)
 elif key=='roof_flat':
  planks(4,4,.16,.16)
  for x in [-1.92,1.92]:box('roof_trim',(x,0,.10),(.15,4.12,.23),'seafoam')
 elif key=='roof_slope':
  # Shed roof: rises from local Y=-2 to +2; root remains a bottom-centre socket.
  for j in range(10):
   y=-2+(j+.5)*.4;o=box('roof_tile',(0,y,.2+(y+2)*.25),(2,.42,.12),'seafoam' if j%2 else 'mint_white',.02);o.data.transform(__import__('mathutils').Matrix.Rotation(math.atan(.25),4,'X')) if False else None
  for x in [-.94,.94]:bar('roof_rib',(x,-2,.12),(x,2,1.12),.065)
 elif key in ['oil_lamp','lamp_post']:
  if key=='lamp_post':cyl('post',(0,0,.77),.065,1.54,'wood_mid');cyl('foot',(0,0,.05),.19,.1,'steel','Metal')
  lamp(1.54 if key=='lamp_post' else 0)
 elif key=='windmill':
  cyl('mast',(0,0,.65),.09,1.3,'wood_mid');cyl('hub',(0,-.08,1.28),.13,.16,'honey',rot=(math.pi/2,0,0))
  for j in range(4):
   a=j*math.pi/2;x=.24*math.cos(a);z=1.28+.24*math.sin(a);box('rotor_%d'%j,(x,-.18,z),(.48,.06,.15),'cream',.025)
 elif key=='flower_pot':
  cyl('pot',(0,0,.18),.23,.36,'ochre');cyl('rim',(0,0,.37),.27,.06,'honey')
  for j in range(3):
   a=j*math.tau/3;x=.12*math.cos(a);y=.12*math.sin(a);bar('stem',(x,y,.36),(x,y,.68),.025,'forest')
   for k in range(5):a=k*math.tau/5;sphere('petal',(x+.08*math.cos(a),y+.08*math.sin(a),.69),(.085,.055,.035),'cream' if j%2 else 'coral')
   sphere('flower_center',(x,y,.72),(.045,.045,.035),'honey')
 elif key=='storage_crate':
  for j in range(4):box('crate_board',(0,0,(j+.5)*.16),(1,.65,.15),'wood_light' if j%2 else 'wood_mid')
  for x in [-.4,.4]:box('crate_strap',(x,0,.34),(.08,.68,.68),'wood_edge')
  box('lid',(0,0,.68),(1.04,.69,.07),'wood_mid')
 elif key=='water_barrel':
  cyl('barrel',(0,0,.45),.33,.9,'wood_mid')
  for z in [.15,.75]:cyl('hoop',(0,0,z),.35,.06,'steel','Metal')
  cyl('lid',(0,0,.91),.34,.05,'wood_edge');bar('tap',(0,-.3,.32),(0,-.45,.32),.045,'gold')
 elif key=='flag':
  cyl('mast',(0,0,1),.045,2,'wood_mid');box('flag',(0.30,0,1.7),(.56,.04,.42),'coral',.01);cyl('base',(0,0,.05),.16,.1,'wood_edge')
 elif key=='table':
  box('table_top',(0,0,.79),(1.2,.8,.12),'wood_light',.05)
  for x in [-.47,.47]:
   for y in [-.27,.27]:box('leg',(x,y,.38),(.09,.09,.76),'wood_mid')
 elif key=='stool':
  cyl('seat',(0,0,.4),.23,.1,'wood_light')
  for a in [0,math.tau/3,math.tau*2/3]:bar('leg',(.16*math.cos(a),.16*math.sin(a),.03),(.13*math.cos(a),.13*math.sin(a),.38),.04)
 elif key=='wind_chime':
  for x in [-.17,.17]:box('frame',(x,0,.65),(.055,.06,1.3),'wood_mid')
  box('top',(0,0,1.32),(.45,.12,.07),'wood_edge')
  for j in range(3):bar('string',((j-1)*.11,0,1.3),((j-1)*.11,0,.75+j*.07),.009,'sand');cyl('chime_%d'%j,((j-1)*.11,0,.64+j*.07),.025,.28,'gold','Metal')
 # Export placeholders keep role names; Godot wrappers bind shared runtime materials.
 bpy.ops.object.select_all(action='DESELECT')
 for o in col.objects:o.select_set(True)
 target=R/'godot/assets/models/building_kit'/key;target.mkdir(parents=True,exist_ok=True)
 export_component(col,target/(key+'.glb'))
 pkg=D/'component_packages'/key;pkg.mkdir(parents=True,exist_ok=True)
 bpy.data.libraries.write(str(pkg/(key+'.blend')),{col},fake_user=True,compress=True)
 verts=[o.matrix_world@v.co for o in col.objects for v in o.data.vertices];tris=sum(len(f.vertices)-2 for o in col.objects for f in o.data.polygons)
 records.append(dict(e,collection=col.name,triangles=tris,bounds={'min':[min(v[k] for v in verts) for k in range(3)],'max':[max(v[k] for v in verts) for k in range(3)]}))
 S.collection.children.unlink(col)
 inst=bpy.data.objects.new(key,None);inst.instance_type='COLLECTION';inst.instance_collection=col;S.collection.objects.link(inst);inst.location=((index%6)*5,(index//6)*5,0)
world=bpy.data.worlds.new('Gallery');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.15,.25,.28,1);world.node_tree.nodes['Background'].inputs[1].default_value=.7;S.world=world
bpy.ops.object.light_add(type='AREA',location=(8,-8,22));light=bpy.context.object;light.data.energy=4500;light.data.shape='DISK';light.data.size=20
bpy.ops.object.camera_add();cam=bpy.context.object;cam.data.type='ORTHO';cam.data.ortho_scale=36;S.camera=cam
S.render.engine='CYCLES';S.cycles.samples=12;S.cycles.use_denoising=True;S.render.resolution_x=1500;S.render.resolution_y=1000;S.render.resolution_percentage=100;S.view_settings.view_transform='AgX'
img.filepath=str(R/P['palette'])
bpy.ops.wm.save_as_mainfile(filepath=str(D/'building_kit.blend'),compress=True)
(D/'catalog.json').write_text(json.dumps({'components':records},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_instances.json').write_text(json.dumps({'plane':'Blender XY','up':'+Z','godot_mapping':'(x,y,z)->(x,z,-y)','instances':[{'id':r['id'],'collection':r['collection'],'position':[(i%6)*5,(i//6)*5,0]} for i,r in enumerate(records)]},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Reopen the saved mother and every standalone package before accepting them.
bpy.ops.wm.open_mainfile(filepath=str(D/'building_kit.blend'))
for e in records:
 with bpy.data.libraries.load(str(D/'component_packages'/e['id']/(e['id']+'.blend'))) as (data,_):assert e['collection'] in data.collections
 for o in bpy.data.collections[e['collection']].objects:
  assert o.location.length<1e-5 and all(abs(x-1)<1e-5 for x in o.scale)
  assert o.data.uv_layers.get('PaletteUV') and len(o.data.vertices)>0
S=bpy.context.scene;cam=S.camera
for label,loc in [('front',(35,-35,32)),('back',(-12,35,30)),('top',(12,7,55)),('side',(47,7,14))]:
 cam.location=loc;cam.rotation_euler=(Vector((12,7,1))-cam.location).to_track_quat('-Z','Y').to_euler();S.render.filepath=str(W/(label+'.png'));bpy.ops.render.render(write_still=True)
print('BUILDING_KIT_SOURCE_PASS',len(records),sum(r['triangles'] for r in records),flush=True)
