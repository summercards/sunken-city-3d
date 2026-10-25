"""Original Blender construction for the current image; does not import other kits."""
import bpy, math, random, json, hashlib, os, sys
from pathlib import Path
from mathutils import Matrix, Vector, Euler
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/bloom_lower_building/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'bloom_lower_building_v001';W.mkdir(parents=True,exist_ok=True);(W/'previews').mkdir(exist_ok=True)
P=json.loads((D/'component_plan.json').read_text());assert P['status']=='frozen_before_geometry'
if (D/'bloom_lower_building.blend').exists() and '--replace-generated' not in sys.argv:raise RuntimeError('Existing source is protected; use a new version or --replace-generated only for this generated candidate')
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version=0
S=bpy.context.scene;S.name='Bloom Lower Building | 独立下层建筑';S.unit_settings.system='METRIC'
LIB=bpy.data.scenes.new('组件母版 | 独立原点');LIB.unit_settings.system='METRIC'
def collection(name,parent):
 c=bpy.data.collections.new(name);parent.children.link(c);return c
B=collection('01 建筑',S.collection);STRUCT=collection('结构',B);FIX=collection('固定设施与陈设',B);F=collection('02 花朵与植物',S.collection);STUDIO=collection('90 展示支持_不导出',S.collection)
MB=collection('建筑组件母版',LIB.collection);MF=collection('花草组件母版',LIB.collection)
PAL=R/P['palette'];im=bpy.data.images.load(str(PAL));cells={c['name']:c for c in json.loads(PAL.with_suffix('.json').read_text())['cells']}
M={}
for role,rough,metal in [('Matte',.62,0),('Metal',.42,.18),('Gloss',.24,0),('Emission',.35,0)]:
 m=bpy.data.materials.new('SEA_'+role);m.use_nodes=True;n=m.node_tree.nodes;n.clear();uv=n.new('ShaderNodeUVMap');uv.uv_map='PaletteUV';tx=n.new('ShaderNodeTexImage');tx.image=im;tx.interpolation='Closest';bs=n.new('ShaderNodeBsdfPrincipled');bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal;bs.inputs['Specular IOR Level'].default_value=.25
 out=n.new('ShaderNodeOutputMaterial');lk=m.node_tree.links;lk.new(uv.outputs['UV'],tx.inputs['Vector']);sat=n.new('ShaderNodeHueSaturation');sat.inputs['Saturation'].default_value=1.04;lk.new(tx.outputs['Color'],sat.inputs['Color']);lk.new(sat.outputs['Color'],bs.inputs['Base Color']);lk.new(bs.outputs[0],out.inputs[0])
 # Per-UV swatch tuning keeps the one public PNG unchanged.
 sep=n.new('ShaderNodeSeparateXYZ');lk.new(uv.outputs['UV'],sep.inputs[0])
 def cell_mask(col,row_from_bottom):
  eqs=[]
  for axis,value in [('X',col),('Y',row_from_bottom)]:
   mult=n.new('ShaderNodeMath');mult.operation='MULTIPLY';mult.inputs[1].default_value=8;lk.new(sep.outputs[axis],mult.inputs[0])
   fl=n.new('ShaderNodeMath');fl.operation='FLOOR';lk.new(mult.outputs[0],fl.inputs[0])
   eq=n.new('ShaderNodeMath');eq.operation='COMPARE';eq.inputs[1].default_value=value;eq.inputs[2].default_value=.01;lk.new(fl.outputs[0],eq.inputs[0]);eqs.append(eq)
  mm=n.new('ShaderNodeMath');mm.operation='MULTIPLY';lk.new(eqs[0].outputs[0],mm.inputs[0]);lk.new(eqs[1].outputs[0],mm.inputs[1]);return mm.outputs[0]
 blue=cell_mask(5,5);peach=cell_mask(4,1)
 for socket,mask,mult,base in [('Hue',blue,-.016,.5),('Value',blue,.26,1),('Saturation',peach,-.24,1.04)]:
  tune=n.new('ShaderNodeMath');tune.operation='MULTIPLY_ADD';tune.inputs[1].default_value=mult;tune.inputs[2].default_value=base;lk.new(mask,tune.inputs[0]);lk.new(tune.outputs[0],sat.inputs[socket])
 if role=='Gloss':
  tr=n.new('ShaderNodeBsdfTransparent');mixglass=n.new('ShaderNodeMixShader');mixglass.inputs[0].default_value=.19;lk.new(tr.outputs[0],mixglass.inputs[1]);lk.new(bs.outputs[0],mixglass.inputs[2]);lk.new(mixglass.outputs[0],out.inputs[0])
 if role=='Emission':lk.new(tx.outputs['Color'],bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=2.0
 M[role]=m
cur=None;parts={};catalog=[];instances=[];pi=math.pi

def select(o):
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o

def paint(o,color,role):
 o.data.materials.clear();o.data.materials.append(M[role])
 while o.data.uv_layers:o.data.uv_layers.remove(o.data.uv_layers[0])
 layer=o.data.uv_layers.new(name='PaletteUV');layer.active_render=True
 c=cells[color];u=(c['column']+.5)/8;v=1-(c['row']+.5)/8
 for face in o.data.polygons:
  for j,loop in enumerate(face.loop_indices):
   a=2*pi*j/len(face.loop_indices);layer.data[loop].uv=(u+.025*math.cos(a),v+.025*math.sin(a))

def finish(o,label,color='white',role='Matte',bevel=0,smooth=False):
 o.name=label
 for c in list(o.users_collection):c.objects.unlink(o)
 cur.objects.link(o);select(o);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  b=o.modifiers.new('实体圆角','BEVEL');b.width=bevel;b.segments=3;bpy.ops.object.modifier_apply(modifier=b.name)
 for face in o.data.polygons:face.use_smooth=smooth or bool(bevel)
 if bevel:
  # Weighted face normals retain flat large planes and smoothly rounded edge strips.
  w=o.modifiers.new('平面加权法线','WEIGHTED_NORMAL');w.keep_sharp=True;w.weight=40;bpy.ops.object.modifier_apply(modifier=w.name)
 o.data.transform(o.matrix_world);o.matrix_world=Matrix.Identity(4);paint(o,color,role);return o

def cube(n,p,d,c='white',b=.04,role='Matte',rot=None):
 bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.scale=d
 if rot:o.rotation_euler=rot
 return finish(o,n,c,role,b)

def ball(n,p,d,c='leaf',rot=None):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,location=p);o=bpy.context.object;o.scale=d
 if rot:o.rotation_euler=rot
 return finish(o,n,c,smooth=True)

def cylinder(n,p,r,h,c='wood',r2=None,rot=None,role='Matte',verts=24):
 bpy.ops.mesh.primitive_cone_add(vertices=verts,radius1=r,radius2=r if r2 is None else r2,depth=h,location=p);o=bpy.context.object
 if rot:o.rotation_euler=rot
 return finish(o,n,c,role,min(.02,r*.15),True)

def torus(n,p,r,t,c='cream'):
 bpy.ops.mesh.primitive_torus_add(major_segments=32,minor_segments=8,major_radius=r,minor_radius=t,location=p);return finish(bpy.context.object,n,c,smooth=True)

def raw(n,vs,fs,c='white',smooth=True,role='Matte'):
 mesh=bpy.data.meshes.new(n);mesh.from_pydata(vs,[],fs);mesh.update();o=bpy.data.objects.new(n,mesh);cur.objects.link(o);return finish(o,n,c,role,smooth=smooth)

def tube(n,pts,r,c='wood'):
 cv=bpy.data.curves.new(n,'CURVE');cv.dimensions='3D';cv.resolution_u=10;cv.bevel_depth=r;cv.bevel_resolution=3;sp=cv.splines.new('BEZIER');sp.bezier_points.add(len(pts)-1)
 for q,p in zip(sp.bezier_points,pts):q.co=p;q.handle_left_type='AUTO';q.handle_right_type='AUTO'
 o=bpy.data.objects.new(n,cv);cur.objects.link(o);select(o);bpy.ops.object.convert(target='MESH');return finish(bpy.context.object,n,c,smooth=True)

def begin(key):
 global cur
 spec=next(x for x in P['components'] if x['key']==key);cur=collection(spec['asset_id'],MF if spec['category']=='flora' else MB);S.collection.children.link(cur);cur.instance_offset=(0,0,0)

def end(key):
 objects=list(cur.objects);coords=[v.co for o in objects for v in o.data.vertices];lo=Vector([min(v[i] for v in coords) for i in range(3)]);hi=Vector([max(v[i] for v in coords) for i in range(3)]);anchor=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 for o in objects:o.data.transform(Matrix.Translation(-anchor))
 root=bpy.data.objects.new('ROOT_'+key,None);cur.objects.link(root)
 groups={em:[o for o in objects if ('SEA_Emission' in [m.name for m in o.data.materials])==em] for em in [False,True]}
 for emissive,group in groups.items():
  if not group:continue
  bpy.ops.object.select_all(action='DESELECT')
  for o in group:o.select_set(True)
  bpy.context.view_layer.objects.active=group[0]
  if len(group)>1:bpy.ops.object.join()
  o=bpy.context.object;o.name=key+('_emissive' if emissive else '_mesh');o.parent=root
 spec=next(x for x in P['components'] if x['key']==key)
 parts[key]={'collection':cur,'anchor':anchor,'spec':spec}
 item=dict(spec,collection=cur.name,root=root.name,bounds_size=list(hi-lo),bounds_min=[-float((hi-lo).x)/2,-float((hi-lo).y)/2,0],source_anchor=list(anchor),instance_count=0,material_roles=sorted({m.name for o in cur.objects if o.type=='MESH' for m in o.data.materials}),collision_owner='Godot wrapper pending',component_source=str((D/'components'/key/(key+'.blend')).relative_to(R)))
 catalog.append(item);S.collection.children.unlink(cur)

def place(key,xyz=(0,0,0),rotation=(0,0,0),scale=1):
 p=parts[key]
 xyz=(xyz[0],xyz[1],xyz[2]+5.16)
 o=bpy.data.objects.new(key,None);o.instance_type='COLLECTION';o.instance_collection=p['collection'];cat=p['spec']['category'];(F if cat=='flora' else STRUCT if cat=='structure' else FIX).objects.link(o);o.rotation_euler=rotation;o.scale=(scale,)*3 if isinstance(scale,(int,float)) else scale;o.location=Vector(xyz)+o.rotation_euler.to_matrix()@Vector([p['anchor'][i]*o.scale[i] for i in range(3)])
 instances.append(dict(name=o.name,asset_id=p['spec']['asset_id'],position=list(o.location),rotation_euler_xyz=list(o.rotation_euler),scale=list(o.scale),category=cat));return o

# Independently authored building components for this reference.
for key,w,opening,depth in [('facade_bay',2.12,1.18,.44),('end_bay',3.80,2.18,.48),('return_bay',.52,.28,.18)]:
 begin(key);jamb=(w-opening)/2
 for x in [-(w-jamb)/2,(w-jamb)/2]:cube('厚圆白窗间墙',(x,0,.86),(jamb,depth,1.72),'white',min(.055,jamb*.23))
 cube('厚白层间檐',(0,-.035,1.56),(w+.08,depth+.15,.32),'white',.05)
 cube('厚窗台',(0,-.035,.15),(w+.08,depth+.15,.30),'cream',.05)
 end(key)
begin('floor_slab');cube('内层楼板',(0,0,.08),(3.70,7.70,.16),'plaster',.035);end('floor_slab')
begin('roof_slab');cube('饱满屋顶厚板',(0,0,.14),(4.48,8.28,.28),'white',.085);end('roof_slab')
begin('roof_tile');cube('浅杏屋顶方砖',(0,0,.035),(1.014,.994,.07),'peach',.018);end('roof_tile')
begin('roof_rim');cube('厚奶白顶边',(0,0,.11),(1.58,.23,.22),'white',.055);end('roof_rim')
begin('foundation');cube('落地饱满柱基',(0,0,.38),(.57,.55,.76),'cream',.075);end('foundation')
begin('wall_pier');cube('白色厚立柱',(0,0,.86),(.34,.36,1.72),'white',.055);end('wall_pier')
begin('blue_column');cube('深蓝灰方柱',(0,0,.78),(.30,.34,1.56),'steel',.035);cube('蓝灰侧高光',(-.13,-.178,.78),(.038,.025,1.43),'silver',.012);end('blue_column')
begin('blue_collar');cube('天蓝厚柱箍',(0,0,.095),(.40,.44,.19),'aqua',.04);cube('下缘深色线',(0,0,.018),(.38,.42,.035),'ocean',.012);end('blue_collar')
for key,w in [('wide_window',1.18),('end_window',2.18),('return_window',.28)]:
 begin(key);h=1.10
 cube('饱满蓝玻璃',(0,0,h/2),(w,.065,h),'solar',.025)
 # All windows use opaque palette color, with restrained colored reflection strips.
 for x in ([-w/2,0,w/2] if key!='return_window' else [-w/2,w/2]):cube('圆角天蓝竖框',(x,-.06,h/2),(.075,.13,h+.03),'aqua',.018)
 for z in [0,h]:cube('圆角天蓝横框',(0,-.06,z),(w+.075,.13,.075),'aqua',.018)
 if key!='return_window':
  for x in [-w*.40,w*.10]:cube('柔蓝边缘反光',(x,-.038,h*.52),(.07,.012,h*.88),'ocean',.008)
 end(key)
begin('air_conditioner');cube('厚白室外机',(0,0,.33),(.76,.44,.66),'snow',.07);cube('顶盖',(0,0,.675),(.71,.41,.05),'white',.02)
for x in [-.22,.20]:cylinder('灰圆固定盖',(x,-.235,.31),.057,.025,'lightgray',rot=(pi/2,0,0),verts=20)
for y in [-.1,.02,.14]:cube('顶盖细槽',(0,y,.706),(.44,.018,.008),'sand',.003)
for z in [.14,.22,.30,.38,.46,.54]:cube('侧散热片',(.385,0,z),(.018,.28,.018),'silver',.004)
end('air_conditioner')
for key,number in [('leaf_cluster',8),('edge_cluster',13)]:
 begin(key)
 for i in range(number):
  a=i*2.39996;r=.14+.10*(i%3);stretch=1.5 if key=='edge_cluster' else 1
  ball('饱满嫩绿叶',(r*math.cos(a)*stretch,r*math.sin(a),.14+.035*(i%3)),(.14,.235,.115),['leaf_yellow','leaf','leaf_yellow'][i%3],rot=(.25+(.13*(i%2)),.1,a-pi/2))
 for i in range(3):
  a=i*2*pi/3;ball('向上圆嫩叶',(.095*math.cos(a),.095*math.sin(a),.32),(.10,.12,.18),'leaf_yellow',rot=(.2,0,a))
 end(key)
for key,length in [('vine_long',2.00),('vine_short',1.03)]:
 begin(key);tube('轻弯绿藤',[(0,0,0),(.06,.015,length*.30),(-.04,0,length*.65),(0,0,length)],.018,'leaf_mid')
 for i in range(17 if key=='vine_long' else 10):
  t=i/(16 if key=='vine_long' else 9);z=.06+t*(length-.1);a=(-1)**i
  ball('圆润垂藤叶',(a*(.07+.03*math.sin(i)), -.04-.025*(i%2),z),(.105,.105,.165),['leaf_yellow','leaf','leaf_yellow'][i%3],rot=(.15,a*.35,0))
 for a,z in [(-1,length*.75),(1,length*.57)]:
  tube('分叉藤',[(0,0,z),(a*.14,-.015,z-.15),(a*.21,-.03,z-.36)],.012,'leaf_mid')
  for j in range(3):ball('分叉圆叶',(a*(.10+.055*j),-.045,z-.08-.12*j),(.095,.09,.14),'leaf_yellow',rot=(.1,a*.38,0))
 end(key)
for key,c in [('pink_flower','pink'),('white_flower','white')]:
 begin(key)
 for i in range(5):
  a=i*2*pi/5;ball('饱满五瓣花',(.22*math.cos(a),.22*math.sin(a),.14),(.24,.14,.13),c,rot=(0,.10,a))
 ball('圆金黄花心',(0,0,.24),(.12,.12,.115),'yellow');end(key)
begin('yellow_buds')
for x,y,z,r in [(-.09,0,.15,.065),(.07,.07,.18,.07),(.04,-.07,.12,.055)]:ball('小金黄花苞',(x,y,z),(r,r,r*1.25),'gold')
end('yellow_buds')

# Four storeys. Long facade is on -X; short front is -Y. Projections remain explicit.
H=1.72
for level in range(7):
 z=(level-3)*H
 place('floor_slab',(0,0,z))
 for y,bay in [(2.60,0),(0,1),(-2.60,2)]:
  # Outer bays project; central bay is set back, exposing blue structural channels.
  fx=-2.07 if bay!=1 else -1.70
  if level==1 and bay==1:fx-=.05
  place('facade_bay',(fx,y,z),rotation=(0,0,-pi/2))
  place('wide_window',(fx-.255,y,z+.30),rotation=(0,0,-pi/2))
  place('facade_bay',(1.88,y,z),rotation=(0,0,pi/2))
  place('wide_window',(2.135,y,z+.30),rotation=(0,0,pi/2))
 for y,a in [(-3.88,0),(3.88,pi)]:
  place('end_bay',(0,y,z),rotation=(0,0,a))
  place('end_window',(0,y+(-.275 if y<0 else .275),z+.30),rotation=(0,0,a))
 # Small return windows on the cheeks of the projecting long-face bays.
 for y,a in [(1.39,0),(-1.39,pi)]:
  place('return_bay',(-1.72,y,z),rotation=(0,0,a))
  place('return_window',(-1.72,y+(-.115 if a==0 else .115),z+.24),rotation=(0,0,a))
 for x,y in [(-2.18,1.30),(-2.18,-1.30),(1.95,3.89),(1.95,-3.89)]:
  place('blue_column',(x,y,z+.08));place('blue_collar',(x,y,z+.02))
# White piers at four corners, backing the large structural masses.
for x,y in [(-1.90,3.83),(-1.90,-3.83),(1.90,3.83),(1.90,-3.83)]:
 for level in range(7):place('wall_pier',(x,y,(level-3)*H))
 place('foundation',(x,y,-5.16))
for y in [1.30,-1.30]:place('foundation',(-1.87,y,-5.16))
place('roof_slab',(-.10,0,4*H))
for ix in range(4):
 for iy in range(8):place('roof_tile',(-1.53+ix*1.02,-3.5+iy,7.16))
# Low perimeter strips broken into the same visible short segments as the reference.
for x in [-2.22,2.02]:
 for y in [-3.12,-1.55,.02,1.59,3.16]:place('roof_rim',(x,y,7.20),rotation=(0,0,pi/2))
for y in [-4.0,4.0]:
 for x in [-1.2,.39]:place('roof_rim',(x,y,7.20))
place('air_conditioner',(-2.32,-.65,3.98),rotation=(0,0,-pi/2))

random.seed(625)
def plant_position(p):
 x,y,z=p
 if z<6.8:
  if x<-1.6:x-=.28
  if y<-3.75:y-=.28
 return (x,y,z)
def green(key,p,scale=1,a=None):return place(key,plant_position(p),rotation=(0,0,random.uniform(0,2*pi) if a is None else a),scale=scale*1.10)
def flower(key,p,s=1):return place(key,plant_position(p),rotation=(random.uniform(.25,.55),random.uniform(-.55,-.1),random.uniform(-.8,.8)),scale=s)
def trail(x,y,top,length=2,a=-pi/2,scale=1):
 key='vine_long' if length>1.3 else 'vine_short';nominal=2 if key=='vine_long' else 1.03
 return place(key,(x,y,top-length*scale),rotation=(0,0,a),scale=(scale,scale,length*scale/nominal))
# Roof corner gardens; central tiles stay entirely clear.
roof_groups=[(-1.90,3.70,1.00),(.95,3.84,.78),(-2.00,1.55,.86),(-1.98,-.10,.62),(-1.98,-1.70,.94),(-1.68,-3.82,.85),(1.55,-3.82,1.0),(1.94,-2.10,.80),(1.94,.10,.64),(1.94,2.1,.81)]
for x,y,s in roof_groups:
 green('edge_cluster',(x,y,7.20),s)
 for dx,dy,ss in [(-.22,.27,.62),(.22,-.24,.66)]:green('leaf_cluster',(x+dx,y+dy,7.20),s*ss)
 green('yellow_buds',(x+.06,y-.04,7.40),s*.72)
for key,x,y,s in [('pink_flower',-.95,3.65,.72),('white_flower',-.40,3.88,.62),('white_flower',-1.94,3.39,.60),('pink_flower',-1.98,1.70,.78),('pink_flower',-1.99,-1.79,.73),('white_flower',-2.03,-1.16,.55),('pink_flower',1.63,-3.60,.73),('white_flower',1.83,-2.62,.55),('pink_flower',1.91,1.72,.70)]:green('leaf_cluster',(x,y,7.22),s*.82);flower(key,(x,y,7.70),s)
for x,y,top,le,ss,a in [(-2.26,3.72,7.55,2.65,.85,-pi/2),(-2.27,3.27,7.48,2.12,.82,-pi/2),(-2.24,1.65,7.45,2.2,.87,-pi/2),(-2.13,-.05,7.49,1.3,.82,-pi/2),(-2.25,-1.68,7.49,1.75,.88,-pi/2),(-1.54,-4.18,7.50,1.20,.85,0),(1.55,-4.17,7.46,2.0,.83,0)]:trail(x-.13 if x<0 else x,y,top,le,a,ss)
for x,y,top,le,ss,a in [(-2.34,3.54,7.45,3.10,.73,-pi/2),(-2.34,3.03,7.42,1.92,.70,-pi/2),(-2.34,1.82,7.42,1.43,.69,-pi/2),(-2.34,-1.47,7.42,2.34,.68,-pi/2),(1.35,-4.22,7.42,1.46,.70,0)]:trail(x-.13 if x<0 else x,y,top,le,a,ss)
# Intermediate window ledges: compact localized clusters, clear areas still expose the blue panes.
ledge_groups=[(-2.20,2.95,5.18,.68),(-2.18,1.70,3.46,.83),(-2.15,2.96,3.47,.61),(-2.06,-.05,5.17,.65),(-2.07,-.48,3.45,.70),(-2.10,1.12,1.73,.80),(-2.16,-1.90,1.73,.59),(-2.17,-2.94,.40,.64),(-1.45,-4.11,5.18,.55),(1.50,-4.12,5.18,.68),(1.49,-4.12,3.46,.70),(1.53,-4.11,1.73,.52)]
for x,y,z,s in ledge_groups:
 green('leaf_cluster',(x,y,z),s);green('edge_cluster',(x+.06,y+.22,z+.02),s*.78)
for x,y,z,le,s,a in [(-2.29,3.05,5.45,1.75,.72,-pi/2),(-2.27,1.65,3.70,1.82,.73,-pi/2),(-2.12,.04,5.4,2.12,.78,-pi/2),(-2.20,-.48,3.7,2.4,.83,-pi/2),(-2.20,1.1,1.94,1.1,.75,-pi/2),(-2.24,-2.94,.65,.65,.7,-pi/2),(1.6,-4.19,5.44,1.8,.80,0),(1.62,-4.19,3.70,1.45,.79,0),(1.65,-4.19,1.94,1.10,.72,0)]:trail(x-.12 if x<0 else x,y,z,le,a,s)
for key,x,y,z,s in [('pink_flower',-2.20,1.82,3.82,.60),('pink_flower',-2.20,3.01,5.50,.43),('white_flower',-2.12,-.45,3.80,.45)]:green('leaf_cluster',(x,y,z-.24),s*.85);flower(key,(x,y,z-.06),s)
# A few base sprouts; no ground plane or upper-building content.
for x,y,s in [(-2.15,2.74,.64),(-2.13,.83,.65),(-2.15,-2.83,.77),(1.89,-3.82,.65)]:green('leaf_cluster',(x,y,.12),s)

# Three new lower floors extend downwards; original roof gardens retain their relative placement.
for x,y,z,s in [(-2.18,2.6,-1.68,.80),(-2.18,-1.65,-1.68,.63),(-2.13,.28,-3.40,.74),(-2.18,-2.90,-3.40,.70),(1.50,-4.12,-1.68,.70),(1.50,-4.12,-3.40,.55),(-2.20,1.15,-5.08,.72),(-2.17,-2.8,-5.08,.74)]:
 green('edge_cluster',(x,y,z),s)
for x,y,z,le,s,a in [(-2.30,2.65,-1.43,2.0,.76,-pi/2),(-2.29,-1.70,-1.43,1.35,.69,-pi/2),(-2.30,.30,-3.15,1.8,.72,-pi/2),(-2.30,-2.85,-3.15,1.3,.72,-pi/2),(1.65,-4.25,-1.43,1.7,.72,0),(1.65,-4.25,-3.15,1.5,.70,0)]:trail(x-.27 if x<0 else x,y,z,le,a,s)
flower('pink_flower',(-2.20,2.6,-1.34),.55)
flower('white_flower',(-2.13,.28,-3.06),.52)

world=bpy.data.worlds.new('明蓝摄影背景');world.use_nodes=True;S.world=world;n=world.node_tree.nodes;lk=world.node_tree.links;bg=n.get('Background');bg.inputs[0].default_value=(.80,.89,1,1);bg.inputs[1].default_value=.42;cb=n.new('ShaderNodeBackground');cb.inputs[0].default_value=(.035,.48,.90,1);cb.inputs[1].default_value=1.0;lp=n.new('ShaderNodeLightPath');mix=n.new('ShaderNodeMixShader');lk.new(lp.outputs['Is Camera Ray'],mix.inputs[0]);lk.new(bg.outputs[0],mix.inputs[1]);lk.new(cb.outputs[0],mix.inputs[2]);lk.new(mix.outputs[0],n.get('World Output').inputs[0])
def aim(o,p):o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
for name,pos,power,size,col in [('柔暖主光',(-8,-10,21),1300,9,(1,.95,.85)),('正面补光',(7,-9,17),1000,9,(.92,.97,1)),('屋顶轮廓光',(1,6,22),1100,8,(1,1,.92))]:
 data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=col;o=bpy.data.objects.new(name,data);STUDIO.objects.link(o);o.location=pos;aim(o,(0,0,6.3))
camdata=bpy.data.cameras.new('参考等距镜头');cam=bpy.data.objects.new('参考等距镜头',camdata);STUDIO.objects.link(cam);cam.location=(-15,-21,19);aim(cam,(0,0,6.3));camdata.type='ORTHO';camdata.ortho_scale=16.1;S.camera=cam
S.render.engine='CYCLES';S.cycles.samples=40;S.cycles.use_denoising=True;S.render.resolution_x=1300;S.render.resolution_y=1300;S.render.resolution_percentage=100;S.view_settings.view_transform='Standard';S.view_settings.look='None';S.view_settings.exposure=-.13
S['reference_sha256']=P['reference_sha256'];S['source_policy']=P['source_policy'];S['feature_id']='SEA-ASSET';S['building_part']='independent lower building';S['roof_interface_z']=12.32;S['floor_count']=7
for screen in bpy.data.screens:
 for a in screen.areas:
  if a.type=='VIEW_3D':a.spaces.active.region_3d.view_perspective='CAMERA';a.spaces.active.shading.type='MATERIAL'
for item in catalog:
 item['instance_count']=sum(i['asset_id']==item['asset_id'] for i in instances)
 meshes=[o for o in parts[item['key']]['collection'].objects if o.type=='MESH'];fp=[{'vertices':[[round(t,6) for t in v.co] for v in o.data.vertices],'faces':[list(p.vertices) for p in o.data.polygons]} for o in meshes];item['geometry_fingerprint']=hashlib.sha256(json.dumps(fp).encode()).hexdigest()
(D/'catalog.json').write_text(json.dumps({'components':catalog},ensure_ascii=False,indent=2)+'\n');(D/'component_instances.json').write_text(json.dumps({'coordinate_contract':{'plane':'XY','up':'+Z','rotation':'full Euler XYZ radians','godot':'(x,y,z) -> (x,z,-y)'},'instances':instances},ensure_ascii=False,indent=2)+'\n')
im.filepath=bpy.path.relpath(str(PAL),start=str(D));bpy.ops.wm.save_as_mainfile(filepath=str(D/'bloom_lower_building.blend'),compress=True)
print('BUILT',len(catalog),'components',len(instances),'instances',flush=True)
S.render.filepath=str(W/'previews/beauty.png');bpy.ops.render.render(write_still=True)
