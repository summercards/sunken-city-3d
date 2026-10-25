"""Original Blender construction for the current image; does not import other kits."""
import bpy, math, random, json, hashlib, os, sys
from pathlib import Path
from mathutils import Matrix, Vector, Euler
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v003'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'sunny_bloom_retreat_v003';W.mkdir(parents=True,exist_ok=True);(W/'previews').mkdir(exist_ok=True)
P=json.loads((D/'component_plan.json').read_text());assert P['status']=='frozen_before_geometry'
if (D/'sunny_bloom_retreat.blend').exists() and '--replace-generated' not in sys.argv:raise RuntimeError('Existing source is protected; use a new version or --replace-generated only for this generated candidate')
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version=0
S=bpy.context.scene;S.name='Sunny Bloom Retreat | 参考图装配';S.unit_settings.system='METRIC'
LIB=bpy.data.scenes.new('组件母版 | 独立原点');LIB.unit_settings.system='METRIC'
def collection(name,parent):
 c=bpy.data.collections.new(name);parent.children.link(c);return c
B=collection('01 建筑',S.collection);STRUCT=collection('结构',B);FIX=collection('固定设施与陈设',B);F=collection('02 花朵与植物',S.collection);STUDIO=collection('90 展示支持_不导出',S.collection)
MB=collection('建筑组件母版',LIB.collection);MF=collection('花草组件母版',LIB.collection)
PAL=R/P['palette'];im=bpy.data.images.load(str(PAL));cells={c['name']:c for c in json.loads(PAL.with_suffix('.json').read_text())['cells']}
M={}
for role,rough,metal in [('Matte',.62,0),('Metal',.42,.18),('Gloss',.24,0),('Emission',.35,0)]:
 m=bpy.data.materials.new('SEA_'+role);m.use_nodes=True;n=m.node_tree.nodes;n.clear();uv=n.new('ShaderNodeUVMap');uv.uv_map='PaletteUV';tx=n.new('ShaderNodeTexImage');tx.image=im;tx.interpolation='Closest';bs=n.new('ShaderNodeBsdfPrincipled');bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal;bs.inputs['Specular IOR Level'].default_value=.25
 out=n.new('ShaderNodeOutputMaterial');lk=m.node_tree.links;lk.new(uv.outputs['UV'],tx.inputs['Vector']);sat=n.new('ShaderNodeHueSaturation');sat.inputs['Saturation'].default_value=1.12;lk.new(tx.outputs['Color'],sat.inputs['Color']);lk.new(sat.outputs['Color'],bs.inputs['Base Color']);lk.new(bs.outputs[0],out.inputs[0])
 # Keep one shared palette and four roles; only the solar swatch receives a small
 # hue correction for the reference's periwinkle blue under warm studio lighting.
 sep=n.new('ShaderNodeSeparateXYZ');lk.new(uv.outputs['UV'],sep.inputs[0]);tests=[]
 for axis,cell in [('X',5),('Y',5)]:
  mul=n.new('ShaderNodeMath');mul.operation='MULTIPLY';mul.inputs[1].default_value=8;lk.new(sep.outputs[axis],mul.inputs[0])
  fl=n.new('ShaderNodeMath');fl.operation='FLOOR';lk.new(mul.outputs[0],fl.inputs[0])
  eq=n.new('ShaderNodeMath');eq.operation='COMPARE';eq.inputs[1].default_value=cell;eq.inputs[2].default_value=.01;lk.new(fl.outputs[0],eq.inputs[0]);tests.append(eq)
 mask=n.new('ShaderNodeMath');mask.operation='MULTIPLY';lk.new(tests[0].outputs[0],mask.inputs[0]);lk.new(tests[1].outputs[0],mask.inputs[1])
 hue=n.new('ShaderNodeMath');hue.operation='MULTIPLY_ADD';hue.inputs[1].default_value=.020;hue.inputs[2].default_value=.5;lk.new(mask.outputs[0],hue.inputs[0]);lk.new(hue.outputs[0],sat.inputs['Hue'])
 solar_sat=n.new('ShaderNodeMath');solar_sat.operation='MULTIPLY_ADD';solar_sat.inputs[1].default_value=-.18;solar_sat.inputs[2].default_value=1.12;lk.new(mask.outputs[0],solar_sat.inputs[0]);lk.new(solar_sat.outputs[0],sat.inputs['Saturation'])
 if role=='Metal':
  grid_value=n.new('ShaderNodeMath');grid_value.operation='MULTIPLY_ADD';grid_value.inputs[1].default_value=.30;grid_value.inputs[2].default_value=1;lk.new(mask.outputs[0],grid_value.inputs[0]);lk.new(grid_value.outputs[0],sat.inputs['Value'])
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
 if key not in {'foundation','deck_tile','dock_board','pier','bollard'}:
  xyz=(xyz[0],xyz[1],.68+(xyz[2]-.68)*.92)
  if p['spec']['category']!='flora':
   ss=(scale,scale,scale) if isinstance(scale,(int,float)) else scale
   scale=(ss[0],ss[1],ss[2]*.92)
 o=bpy.data.objects.new(key,None);o.instance_type='COLLECTION';o.instance_collection=p['collection'];cat=p['spec']['category'];(F if cat=='flora' else STRUCT if cat=='structure' else FIX).objects.link(o);o.rotation_euler=rotation;o.scale=(scale,)*3 if isinstance(scale,(int,float)) else scale;o.location=Vector(xyz)+o.rotation_euler.to_matrix()@Vector([p['anchor'][i]*o.scale[i] for i in range(3)])
 instances.append(dict(name=o.name,asset_id=p['spec']['asset_id'],position=list(o.location),rotation_euler_xyz=list(o.rotation_euler),scale=list(o.scale),category=cat));return o

# All geometry below is original for this reference.
begin('foundation');cube('灰石承台',(0,0,.27),(.90,.80,.54),'gray',.045);end('foundation')
begin('deck_tile');cube('暖橙木铺板',(0,0,0),(.595,.395,.17),'wood_light',.045);end('deck_tile')
begin('dock_board');cube('栈桥厚木板',(0,0,0),(1.08,.44,.23),'wood_light',.065);end('dock_board')
begin('pier');cube('桥下石墩',(0,0,.26),(1.05,.86,.52),'gray',.045);end('pier')
begin('house')
# Wall surfaces are arranged around real openings, then joined with a boolean union.
body=cube('完整厚墙', (0,0,1.425),(5,3.5,2.85),'white',0)
for center,size in [((0,0,1.42),(4.58,3.08,2.62)),((-2.48,.30,1.33),(.65,1.60,1.64)),((-1.33,-1.73,1.44),(.35,.65,1.82)),((1.0,-1.73,1.25),(2.15,.65,2.45))]:
 bpy.ops.mesh.primitive_cube_add(size=1,location=center);cut=bpy.context.object;cut.scale=size;select(cut);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);select(body);m=body.modifiers.new('真实门窗洞','BOOLEAN');m.object=cut;m.operation='DIFFERENCE';bpy.ops.object.modifier_apply(modifier=m.name);bpy.data.objects.remove(cut,do_unlink=True)
finish(body,'圆角白灰墙壳','white',bevel=.055);end('house')
begin('terrace');cube('白色厚檐',(0,0,.14),(5.20,3.73,.28),'white',.09);cube('木露台坪',(0,0,.31),(4.98,3.48,.08),'wood_light',.025)
for x in [-2.0,-1.4,-.8,-.2,.4,1.,1.6,2.2]:cube('细砖接缝',(x,0,.353),(.009,3.4,.004),'wood_mid',0)
for y in [-1.3,-.7,-.1,.5,1.1]:cube('细砖接缝',(0,y,.353),(4.9,.009,.004),'wood_mid',0)
end('terrace')
begin('upper_room');body=cube('上层白墙',(0,0,.975),(2.25,1.95,1.95),'white',.08);end('upper_room')
begin('cap');cube('厚顶檐',(0,0,.16),(2.58,2.25,.32),'white',.095);end('cap')
begin('parapet');cube('柔白花台矮墙',(0,0,.24),(1.15,.30,.48),'white',.07);end('parapet')
begin('slope');cube('单坡白屋面',(0,0,0),(3.15,2.10,.20),'wood_light',.075,rot=(.44,0,0));cube('前檐橙木',(0,-.98,-.36),(3.30,.22,.20),'wood',.075)
for x in [-1.49,1.49]:cube('侧檐木梁',(x,0,.02),(.18,2.15,.20),'wood',.065,rot=(.44,0,0))
end('slope')
begin('bollard');cube('绳柱',(0,0,.41),(.34,.34,.82),'wood',.06);cube('柱脚',(0,0,.08),(.47,.45,.16),'wood_light',.055)
for z in [.18,.28]:torus('奶油绳环',(0,0,z),.233,.032)
end('bollard')
for key,w,h in [('tall_window',1.60,1.60),('narrow_window',.35,1.80),('small_window',.48,.58)]:
 begin(key);cube('窗内蓝玻璃',(0,.015,h/2),(w,.035,h),'teal',.012,role='Matte' if key!='small_window' else 'Gloss')
 frame='sand' if key=='small_window' else 'teal'
 for x in ([-w/2,0,w/2] if key=='tall_window' else [-w/2,w/2]):cube('窗竖框',(x,-.04,h/2),(.080,.14,h+.08),frame,.023)
 for z in [0,h]:cube('窗横框',(0,-.04,z),(w+.10,.14,.08),frame,.023)
 cube('柔蓝反光',(-w*.22,-.011,h*.53),(w*.12,.008,h*.9),'sky',.005,role='Gloss');cube('奶白窗台',(0,-.01,-.045),(w+.16,.20,.10),'cream',.03);end(key)
begin('door');cube('青蓝房门',(0,0,.87),(.83,.10,1.74),'teal',.025)
for x in [-.47,.47]:cube('米木色门套',(x,.02,.93),(.12,.23,1.86),'sand',.025)
cube('门顶',(0,.02,1.87),(1.06,.23,.13),'sand',.028);cube('金门牌',(.15,-.065,1.45),(.15,.03,.17),'gold',.01);cylinder('门柄',(-.29,-.09,.8),.035,.10,'ochre',rot=(pi/2,0,0));end('door')
begin('entry')
# Recessed interior visible through open central glass doorway; side glazing has reflected shapes.
for x in [-1.16,0,1.16]:cube('门廊青蓝立框',(x,0,1.05),(.10,.18,2.10),'teal',.028)
for z in [0,2.10]:cube('门廊青蓝横框',(0,0,z),(2.4,.18,.10),'teal',.028)
# Real interior behind transparent palette-tinted panes.
cube('室内木地板',(0,.53,.04),(2.25,1.2,.08),'wood',.025)
cube('室内后墙',(0,1.08,1.05),(2.27,.10,2.10),'cream',.025)
cube('室内木长椅',(.35,.69,.38),(1.30,.47,.15),'wood',.04)
cube('室内米白靠垫',(.35,.89,.67),(1.25,.14,.49),'sand',.055)
for x in [-.05,.62]:cube('室内软坐垫',(x,.65,.53),(.60,.43,.17),'honey',.045)
cube('室内矮木桌',(-.65,.50,.61),(.61,.43,.12),'wood',.035)
for x in [-.88,-.42]:cube('室内桌脚',(x,.5,.30),(.08,.30,.60),'wood_mid',.02)
for x in [-.60,.60]:
 cube('淡蓝透明玻璃',(x,.02,1.04),(1.05,.018,1.96),'ice',.004,role='Gloss')
 cube('长拉手',(x*.13,-.10,1.02),(.035,.055,.34),'wood_light',.01)
end('entry')
begin('solar');cube('饱满奶白圆角边框',(0,0,0),(1.38,1.85,.14),'white',.05);cube('蓝色光伏面',(0,0,.072),(1.24,1.71,.026),'solar',.018)
for x in [-.43,-.215,0,.215,.43]:cube('光伏淡蓝细栅',(x,0,.086),(.006,1.68,.002),'solar',0,role='Metal')
for y in [-.66,-.44,-.22,0,.22,.44,.66]:cube('光伏淡蓝细栅',(0,y,.086),(1.21,.006,.002),'solar',0,role='Metal')
for x in [-.43,.43]:cube('光伏背部支座',(x,0,-.102),(.08,.88,.064),'wood_dark',.009)
end('solar')
begin('awning')
for i in range(12):
 x=-1.43+i*.26;c='yellow' if i%2==0 else 'white';cube('条纹棚布',(x,0,0),(.261,.88,.055),c,.012,rot=(.3,0,0));ball('圆垂裙',(x,-.427,-.17),(.131,.055,.14),c)
end('awning')
begin('canopy_post');cube('棚架厚木柱',(0,0,1.08),(.32,.34,2.16),'wood',.075);cube('棚柱脚座',(0,0,.08),(.39,.41,.16),'wood_light',.045);cylinder('外露方梁销',(0,-.20,1.91),.10,.15,'wood_light',rot=(pi/2,0,0));end('canopy_post')
begin('canopy_beam');cube('遮阳厚木横梁',(0,0,0),(2.60,.26,.30),'wood',.07);end('canopy_beam')
begin('sail');vs=[]
for j in range(13):
 for i in range(21):
  u=i/20;v=j/12;vs.append(((u-.5)*2.55,(v-.5)*1.80+.16*u,-.48*math.sin(pi*u)*(.65+.35*math.sin(pi*v))))
fs=[(j*21+i,j*21+i+1,(j+1)*21+i+1,(j+1)*21+i) for j in range(12) for i in range(20)];o=raw('奶白柔软布面',vs,fs,'butter');select(o);sol=o.modifiers.new('布面厚度','SOLIDIFY');sol.thickness=.025;bpy.ops.object.modifier_apply(modifier=sol.name);paint(o,'butter','Matte');tube('前布边包边',[(-1.275,-.90,0),(-.6375,-.86,-.22),(0,-.82,-.312),(.6375,-.78,-.22),(1.275,-.74,0)],.018,'cream');end('sail')
begin('ladder')
for x in [-.31,.31]:
 cube('木梯圆柱',(x,0,1.28),(.13,.17,2.56),'wood',.05);tube('上端弯钩',[(x,0,2.45),(x,0,2.74),(x,.19,2.80),(x,.30,2.66)],.07,'wood')
for i in range(7):cube('圆梯踏步',(0,-.01,.24+i*.34),(.69,.17,.11),'wood',.04)
end('ladder')
for key,(w,d,h) in [('ac_tall',(.92,.54,1.30)),('ac_box',(.76,.53,.87)),('ac_roof',(1.0,.75,.60))]:
 begin(key);cube('圆角白设备箱',(0,0,h/2),(w,d,h),'snow',.065)
 if key!='ac_tall':
  cube('灰百叶凹槽',(-w*.10,-d/2-.012,h*.48),(w*.60,.03,h*.68),'steel',.02)
  for z in range(11):cube('散热横栅',(-w*.10,-d/2-.035,h*.20+z*h*.055),(w*.56,.018,.012),'silver',0)
  cube('青蓝设备侧盖',(w*.34,-d/2-.028,h*.52),(w*.18,.035,h*.71),'aqua',.018)
 else:
  for x in [-w*.37,w*.37]:cube('箱体铰链',(x,-d/2-.02,h*.67),(.07,.05,.13),'lightgray',.014)
 cube('上盖板',(0,0,h+.015),(w*.91,d*.88,.04),'white',.02)
 for x in [-.18,.03]:cube('顶盖浅灰条',(x,0,h+.038),(.12,d*.66,.008),'silver',.005)
 end(key)
begin('chimney');cube('浅橙通风柱',(0,0,.56),(.22,.26,1.12),'wood_light',.04);cube('灰竖风口',(.115,-.02,.52),(.018,.10,.58),'silver',.012);end('chimney')
begin('lantern');cube('灯背座',(0,.06,.25),(.15,.12,.36),'wood_mid',.025);cube('灯芯_emissive',(0,-.10,.24),(.17,.17,.28),'butter',.025,role='Emission')
for x in [-.105,.105]:cube('灯框',(x,-.10,.24),(.03,.21,.34),'ochre',.01)
for z in [.055,.425]:cube('灯框帽',(0,-.1,z),(.27,.25,.065),'ochre',.02)
tube('悬挂弯柄',[(0,.10,.40),(0,-.02,.59),(0,-.12,.47)],.025,'wood_dark');end('lantern')
begin('sofa')
for x in [-.62,.62]:
 for y in [-.22,.22]:cube('沙发脚',(x,y,.14),(.13,.13,.28),'wood',.025)
cube('沙发木座',(0,0,.30),(1.47,.67,.14),'wood',.04)
for x in [-.35,.35]:cube('饱满奶白坐垫',(x,-.045,.46),(.70,.59,.26),'white',.095)
cube('厚靠背',(0,.22,.75),(1.40,.23,.64),'cream',.075,rot=(.13,0,0))
for x in [-.73,.73]:cube('木扶手',(x,0,.62),(.12,.67,.18),'wood',.04)
cube('黄抱枕',(-.30,.08,.78),(.39,.17,.42),'yellow',.055,rot=(.1,-.15,-.15));cube('蓝抱枕',(.23,.08,.78),(.38,.17,.40),'aqua',.055,rot=(.12,.14,.1));end('sofa')
begin('roof_sofa')
for x in [-.62,.62]:
 for y in [-.22,.22]:cube('沙发脚',(x,y,.14),(.13,.13,.28),'wood',.025)
cube('沙发木座',(0,0,.30),(1.47,.67,.14),'wood',.04)
for x in [-.35,.35]:cube('饱满奶白坐垫',(x,-.045,.46),(.70,.59,.26),'white',.095)
cube('厚靠背',(0,.22,.75),(1.40,.23,.64),'cream',.075,rot=(.13,0,0))
for x in [-.73,.73]:cube('木扶手',(x,0,.62),(.12,.67,.18),'wood',.04)
cube('黄抱枕',(.10,.06,.78),(.39,.17,.42),'yellow',.055,rot=(.1,-.15,-.15));end('roof_sofa')
for key,w,d,h in [('coffee_table',1.20,.65,.40),('table',1.05,.82,.75)]:
 begin(key);cube('木桌厚面',(0,0,h-.07),(w,d,.18),'wood',.065)
 for x in [-w*.36,w*.36]:
  for y in [-d*.32,d*.32]:cube('木桌脚',(x,y,(h-.14)/2),(.12,.13,h-.14),'wood_mid',.025)
 end(key)
begin('stool');cube('厚木凳面',(0,0,.40),(.43,.43,.16),'wood',.055)
for x in [-.14,.14]:
 for y in [-.14,.14]:cube('方凳脚',(x,y,.18),(.09,.09,.36),'wood',.025)
end('stool')
begin('umbrella');cylinder('奶白伞座',(0,0,.06),.25,.12,'stone');cylinder('细木伞杆',(0,0,1.14),.035,2.28,'wood')
for k in range(8):
 vs=[]
 for ir in range(10):
  t=ir/9;r=.91*t
  for ia in range(9):
   a=(k+ia/8)*2*pi/8;z=2.36-.42*t**1.5-.04*math.sin(pi*ia/8)*t**3;vs.append((r*math.cos(a),r*math.sin(a),z))
 fs=[(ir*9+j,(ir+1)*9+j,(ir+1)*9+j+1,ir*9+j+1) for ir in range(9) for j in range(8)];o=raw('厚圆伞瓣',vs,fs,'yellow' if k%2==0 else 'white');select(o);m=o.modifiers.new('伞布厚度','SOLIDIFY');m.thickness=.045;bpy.ops.object.modifier_apply(modifier=m.name);paint(o,'yellow' if k%2==0 else 'white','Matte')
ball('小伞顶',(0,0,2.39),(.07,.07,.055),'wood');end('umbrella')
begin('cooler');cube('饱满青蓝箱体',(0,0,.28),(.85,.61,.56),'teal',.065);cube('奶白厚盖',(0,0,.60),(.91,.66,.16),'white',.06)
for x in [-.31,.31]:cube('箱盖扣',(x,-.34,.50),(.08,.035,.12),'aqua',.012)
end('cooler')
begin('pot');cylinder('陶盆',(0,0,.23),.21,.46,'peach',r2=.29);torus('厚盆沿',(0,0,.45),.275,.032,'sand');cylinder('盆土',(0,0,.447),.253,.018,'darkwood');end('pot')
begin('square_pot');cube('奶白方盆',(0,0,.24),(.48,.48,.48),'cream',.07);cube('盆口土',(0,0,.475),(.34,.34,.02),'darkwood',.035);end('square_pot')
begin('vase');ball('圆腹黄花瓶',(0,0,.16),(.12,.12,.15),'gold');cylinder('小瓶颈',(0,0,.30),.055,.14,'gold');torus('圆瓶口',(0,0,.37),.057,.013,'yellow');end('vase')
begin('canopy_hook');tube('墙侧短支杆',[(0,0,-.9),(0,0,-.12),(0,-.08,0)],.06,'wood');ball('布棚挂头',(0,-.08,0),(.085,.085,.085),'wood_light');end('canopy_hook')
begin('bottle');cylinder('红水壶',(0,0,.16),.09,.32,'red_dark');cylinder('瓶肩',(0,0,.33),.085,.05,'red',r2=.06);cylinder('瓶盖',(0,0,.38),.06,.05,'white');end('bottle')
begin('mat');cube('薄荷垫',(0,0,.014),(.92,.66,.028),'aqua',.02)
for x in [-.41,.41]:cube('金纹边',(x,0,.032),(.025,.56,.004),'yellow',0)
for y in [-.27,.27]:cube('金纹边',(0,y,.032),(.84,.025,.004),'yellow',0)
cylinder('太阳纹',(0,0,.033),.14,.004,'yellow')
for i in range(8):
 a=i*pi/4;cube('太阳光线',(.21*math.cos(a),.21*math.sin(a),.034),(.08,.025,.004),'yellow',0,rot=(0,0,a))
end('mat')
begin('porch_side')
for y in [-1.0,1.0]:cube('厚白窗间柱',(0,y,1.18),(.26,.22,2.36),'white',.06)
for z in [.12,2.24]:cube('白侧墙窗沿',(0,0,z),(.26,2.13,.28),'white',.06)
cube('侧窗淡蓝玻璃',(-.035,0,1.18),(.018,1.92,1.90),'ice',.004,role='Gloss')
for y in [-.95,.95]:cube('侧窗蓝竖框',(-.11,y,1.18),(.10,.065,1.98),'teal',.018)
for z in [.19,2.17]:cube('侧窗蓝横框',(-.11,0,z),(.10,1.96,.065),'teal',.018)
# Sloped plaster infill closes the space between window heads and the sloping roof.
vs=[]
for x in [-.105,.105]:
 for y,z in [(-1.08,2.33),(1.08,2.33),(1.08,3.05),(.55,3.05),(-1.08,2.45)]:vs.append((x,y,z))
o=raw('斜屋檐下白色封墙',vs,[(4,3,2,1,0),(5,6,7,8,9),(0,1,6,5),(1,2,7,6),(2,3,8,7),(3,4,9,8),(4,0,5,9)],'white',False)
select(o);be=o.modifiers.new('封墙软边','BEVEL');be.width=.018;be.segments=2;bpy.ops.object.modifier_apply(modifier=be.name);paint(o,'white','Matte')
end('porch_side')
begin('wall_pier');cube('圆角白墙柱',(0,0,1.425),(.30,.30,2.85),'white',.055);end('wall_pier')
begin('porch_return');cube('门廊后侧白墙',(0,0,1.18),(.66,.18,2.36),'white',.045);end('porch_return')
# Inflated, smoothly curved botanical meshes, distinct from all pots and walls.
begin('foliage')
for i in range(11):
 a=i*2.39996;r=.16+.15*(i%3)/2;z=.16+.13*(i%4)/3
 ball('肉质圆叶',(r*math.cos(a),r*math.sin(a),z),(.16,.25,.115),['leaf','leaf_mid','leaf_yellow'][i%3],rot=(.28+.2*(i%2),0,a-pi/2))
ball('顶端嫩叶',(0,0,.39),(.15,.16,.20),'leaf_yellow');end('foliage')
begin('vine');tube('自然弯藤',[(0,0,0),(.05,0,.40),(-.06,.01,.80),(.03,0,1.25)],.018,'leaf_dark')
for i in range(15):
 sign=(-1)**i;z=.06+i*.081;xx=sign*(.065+.06*math.sin(i*1.7)**2);ball('错落圆藤叶',(xx,-.025-.035*(i%3),z),(.10+.02*(i%2),.09,.14+.025*(i%3)),['leaf','leaf_yellow','leaf'][i%3],rot=(.3,sign*.55,sign*.26))
for sign,z in [(-1,.84),(1,1.01),(-1,.42)]:
 tube('藤侧支',[(0,0,z),(sign*.16,-.02,z-.10),(sign*.28,-.03,z-.23)],.014,'leaf_mid')
 for j in range(3):ball('侧枝肉叶',(sign*(.13+j*.065),-.05,z-.06-j*.075),(.095,.08,.13),'leaf_yellow' if j==0 else 'leaf',rot=(.2,sign*.6,0))
end('vine')
begin('palm')
# Distinct inflated lobed blades with blunt round tips and arched spines.
for k in range(7):
 a=k*2*pi/7;length=[.60,.70,1.12,1.05,1.1,.95,.58][k];vs=[];nr=29;ns=16
 for i in range(nr):
  t=i/(nr-1);side=Vector((-math.sin(a),math.cos(a),0));center=Vector((length*t*math.cos(a),length*t*math.sin(a),.14+(([1.25,1.1,0,0,0,0,1.35][k]*t+.20*math.sin(pi*t)) if k in [0,1,6] else (.60*math.sin(t*pi*.95)))))
  width=max(.009,(math.sin(pi*t)**.42)*(.23+.045*math.cos(t*8*pi)));thick=max(.006,.105*math.sin(pi*t)**.5)
  dz=([1.25,1.1,0,0,0,0,1.35][k]+.20*pi*math.cos(pi*t)) if k in [0,1,6] else (.60*pi*.95*math.cos(t*pi*.95))
  tangent=Vector((length*math.cos(a),length*math.sin(a),dz));normal=side.cross(tangent).normalized()
  for j in range(ns):
   q=2*pi*j/ns;vs.append(tuple(center+side*width*math.cos(q)+normal*(thick*math.sin(q))))
 fs=[(i*ns+j,i*ns+(j+1)%ns,(i+1)*ns+(j+1)%ns,(i+1)*ns+j) for i in range(nr-1) for j in range(ns)];fs+=[tuple(reversed(range(ns))),tuple(range((nr-1)*ns,nr*ns))];raw('圆润裂叶',vs,fs,['leaf','leaf_yellow','leaf'][k%3]);tube('叶柄',[(0,0,0),(.25*math.cos(a),.25*math.sin(a),.27),(.55*math.cos(a),.55*math.sin(a),.58)],.025,'leaf_mid')
end('palm')
for key,n,c in [('pink_flower',5,'pink'),('daisy',6,'white')]:
 begin(key)
 for k in range(n):
  a=k*2*pi/n;ball('饱满圆花瓣',(.245*math.cos(a),0,.43+.245*math.sin(a)),(.18,.145,.275),c,rot=(0,pi/2-a,0))
 ball('金色花心',(0,-.16,.43),(.13,.12,.13),'yellow');end(key)
begin('sprout')
for k in range(6):
 a=k*pi/3;ball('鲜嫩盆栽叶',(.17*math.cos(a),.17*math.sin(a),.22+.05*(k%2)),(.095,.23,.075),'leaf' if k%2 else 'leaf_yellow',rot=(.55,0,a-pi/2))
cylinder('小嫩茎',(0,0,.17),.025,.34,'leaf_mid',verts=12);end('sprout')

# Reference composition: continuous full-width forecourt with twin dock on the left.
for ix in range(8):
 for iy in range(9):place('foundation',(-3.15+.9*ix,-3.6+.8*iy,0))
# Narrow left equipment ledge is structural, not floating furniture.
for iy in range(9):place('foundation',(-3.75,-3.6+.8*iy,0),scale=(1/3,1,1))
for ix in range(8):place('foundation',(-3.15+.9*ix,-5.8,0),scale=(1,.5,1))
for ix in range(8):
 for iy in range(2):place('foundation',(-3.15+.9*ix,-5.2+.8*iy,0))
for ix in range(12):
 for iy in range(18):place('deck_tile',(-3.3+.6*ix,-3.8+.4*iy,.595))
for iy in range(18):place('deck_tile',(-3.75,-3.8+.4*iy,.595),scale=(.5,1,1))
for ix in range(12):
 for iy in range(5):place('deck_tile',(-3.3+.6*ix,-5.8+.4*iy,.595))
place('house',(-.72,.96,.68));place('terrace',(-.72,.96,3.53))
place('upper_room',(.75,1.20,3.89));place('cap',(.75,1.20,5.84));place('door',(.48,.215,3.91));place('small_window',(1.89,.97,4.39),rotation=(0,0,pi/2))
# One left double-pane window and one front narrow window, with matching real apertures.
place('tall_window',(-3.23,1.26,1.21),rotation=(0,0,-pi/2))
place('narrow_window',(-2.05,-.80,1.22))
place('porch_side',(-.21,-1.48,.70));place('porch_return',(2.02,-.40,.70));place('porch_side',(2.25,-1.48,.70));place('entry',(1.02,-2.55,.70))
place('slope',(1.09,-1.67,3.49));place('awning',(1.09,-3.02,3.06))
for x in [.34,1.84]:place('solar',(x,-1.68,3.64),rotation=(.44,0,0))
for x in [-2.64,-1.47]:place('parapet',(x,-.85,3.82))
for y in [-.05,1.12,2.28]:place('parapet',(-3.19,y,3.82),rotation=(0,0,pi/2))
place('ladder',(-.51,-.97,.74))
# Reference cloth attaches to wall on its right; no false crossbeam across the sagging front edge.
for x,y in [(-2.93,.02),(-2.93,1.9),(-.57,1.9)]:place('canopy_post',(x,y,3.9))
place('canopy_beam',(-1.75,1.90,5.83));place('canopy_beam',(-2.93,.96,5.83),rotation=(0,0,pi/2),scale=(.77,1,1))
place('canopy_hook',(-.38,.18,5.84));place('sail',(-1.655,.92,5.84))
place('roof_sofa',(-1.91,1.11,3.9),scale=.94);place('coffee_table',(-1.91,.23,3.9),scale=.86)
place('pot',(-1.91,.23,4.25),scale=.26);place('sprout',(-1.91,.23,4.37),scale=.38)
for x,y,z,s in [(-.39,.54,3.90,.67),(-.56,1.04,3.90,.68),(-2.86,.75,3.90,.65),(-.13,.95,6.16,.42),(-.31,1.50,6.16,.40)]:
 place('pot',(x,y,z),scale=s);place('sprout',(x,y,z+.46*s),scale=s*1.20)
place('square_pot',(-.08,.12,3.90),scale=.8);place('sprout',(-.08,.12,4.28),scale=.65)
# Equipment belongs on the left wall/ledge, not the visible front corner.
place('ac_tall',(-3.48,2.12,.68),rotation=(0,0,-pi/2),scale=1.06)
place('ac_box',(-3.49,.35,.68),rotation=(0,0,-pi/2),scale=1.0)
place('ac_box',(.94,-.03,3.90),scale=.80);place('ac_box',(-.1,-.48,3.90),scale=.40)
place('ac_roof',(.97,1.30,6.17));place('chimney',(-.12,1.55,6.15))
for x,y,z in [(-.18,.18,5.13),(-.10,-1.84,2.34),(2.38,-2.57,1.77)]:place('lantern',(x,y,z))
# Recessed seating along the building, then a separate open apron in front.
place('sofa',(1.45,-3.05,.69),scale=.90)
place('table',(2.67,-3.13,.69),scale=.66);place('vase',(2.72,-3.05,1.185),scale=.72);place('sprout',(2.72,-3.05,1.45),scale=.28)
place('table',(2.95,-4.18,.69),scale=1.10);place('umbrella',(2.95,-4.13,1.43),scale=.84)
place('stool',(2.86,-4.87,.69),scale=.92);place('stool',(3.45,-3.60,.69),scale=.86);place('bottle',(3.24,-4.38,1.52))
place('cooler',(1.85,-4.46,.69),scale=1.0);place('cooler',(-.75,-2.54,.69),scale=.86);place('mat',(.55,-3.55,.69))
for x,y,s in [(-.13,-2.97,.80),(.07,-3.77,.87)]:
 place('pot',(x,y,.69),scale=s);place('sprout',(x,y,.69+.46*s),scale=s*1.20)
for row in range(6):
 for x in [-2.05,-.82]:place('dock_board',(x,-6.23-row*.46,.575))
for x in [-2.05,-.82]:
 for y in [-6.45,-7.37,-8.29]:place('pier',(x,y,0))
for x,y in [(-3.23,-2.56),(-2.70,-5.93),(-.17,-5.93),(-2.70,-8.52),(-.17,-8.52),(-3.23,2.7),(-1.70,-5.20)]:place('bollard',(x,y,.67))
for x,y,a in [(-2.05,-3.52,0),(-3.24,-4.50,pi/2),(3.48,-2.53,pi/2),(3.48,-4.41,pi/2)]:place('parapet',(x,y,.69),rotation=(0,0,a))
random.seed(204)
def greens(x,y,z,s=1):place('foliage',(x,y,z),rotation=(0,0,random.uniform(0,2*pi)),scale=s)
for x,y in [(-3.17,-.74),(-3.17,2.66),(-.72,2.66),(1.73,2.66),(1.73,-.74)]:place('wall_pier',(x,y,.68))
for x in [-2.62,-1.43]:place('parapet',(x,2.77,3.82))
for x,y in [(-.335,2.13),(1.835,2.13)]:place('wall_pier',(x,y,3.89),scale=(.75,.75,1.95/2.85))
# Asymmetrical roof garden: large overhanging clumps at corners, open space around AC.
for x,y,s in [(-.33,.27,.55),(.28,.18,.58),(1.12,.18,.77),(1.74,.35,.83),(1.97,.90,.68),(1.96,1.60,.68),(1.45,2.03,.65),(.45,2.17,.67),(-.36,2.01,.74),(-.44,1.40,.59)]:greens(x,y,6.13,s)
for x,y,z,s in [(1.39,.12,5.05,.92),(1.88,.23,5.28,.76),(1.01,.12,5.70,.46)]:place('vine',(x,y,z),scale=s)
for x,z,ss in [(-3.15,4.07,.77),(-2.63,4.03,.66),(-2.05,4.11,.77),(-1.48,4.06,.65),(-.87,4.08,.72),(-.40,4.10,.66)]:greens(x,-.90,z,ss)
for y in [-.14,.55,1.31,2.10,2.65]:greens(-3.23,y,4.07,.80)
for x,y,z,s,a in [(-3.30,-.42,2.55,1.26,-.08),(-2.42,-.98,2.73,1.06,.18),(-1.1,-1.0,2.92,.92,-.15),(-3.31,1.75,2.78,1.04,.10),(-3.32,2.60,2.55,1.21,-.08)]:place('vine',(x,y,z),rotation=(0,0,a),scale=s)
for x,y,z,s in [(-2.68,2.05,5.02,.92),(-3.34,2.36,4.18,.91),(-3.39,.40,4.10,.64),(-2.00,-2.15,.89,1.18),(2.42,.24,3.25,.92),(3.47,-2.03,.91,1.10)]:place('palm',(x,y,z),rotation=(0,0,random.uniform(0,6.28)),scale=s)
for x,y,z,s in [(-.50,-.54,3.94,.78),(-.47,-1.10,3.72,.85),(-.76,-1.73,3.42,.82),(-.51,-2.12,3.15,.58),(2.53,-.33,3.92,.75),(2.63,-.90,3.72,.83),(2.65,-1.48,3.45,.76),(2.64,-2.07,3.18,.68),(2.37,.25,4.25,.77),(2.00,.49,4.34,.72)]:greens(x,y,z,s)
# Lower beds follow the left outer edge, leaving the dock approach and the wide right court open.
for x,y,z,s in [(-3.45,-1.65,.72,.75),(-2.71,-2.45,.74,.97),(-2.15,-2.95,.75,1),(-1.62,-3.52,.74,.95),(-1.01,-3.73,.72,.88),(-3.20,-4.13,.74,.76),(-3.20,-4.73,.74,.70),(-3.20,-5.34,.74,.56),(3.22,-5.39,.72,.54),(3.48,-.45,.73,.80),(3.49,-1.15,.73,.90),(3.53,-1.83,.74,.90),(3.51,-2.65,.74,.85),(3.51,-3.35,.73,.72),(3.51,-4.13,.74,.76),(3.51,-4.85,.73,.75),(-3.73,.04,.71,.55),(-3.72,1.10,.71,.53),(-3.71,2.60,.71,.60)]:greens(x,y,z,s)
for x,y,z,s in [(-1.8,-3.87,.15,.62),(-3.56,-4.65,.14,.60),(3.62,-4.42,.18,.65)]:place('vine',(x,y,z),scale=s)
# Independent seeded orientation variation: local flower face is -Y.
# Negative pitch tips its normal upward; yaw spreads lean directions, roll varies petals.
flower_rng=random.Random(814)
def flower(key,xyz,scale):
 pitch=flower_rng.uniform(-1.42,-.64)
 yaw=flower_rng.uniform(-1.1,1.1)
 roll=flower_rng.uniform(-.55,.55)
 rotation=(pitch,roll,yaw)
 center=Vector((0,0,.43*scale))
 pivot=Vector(xyz)+center-Euler(rotation).to_matrix()@center
 return place(key,tuple(pivot),rotation=rotation,scale=scale)
for x,y,z,s in [(-.40,-1.64,3.60,.95),(2.54,-.66,4.02,.88),(2.34,.24,4.68,.68),(-1.92,-2.73,1.18,.95),(-3.20,-4.38,1.01,.72),(3.48,-1.55,2.96,.68),(-1.20,-3.77,.97,.49)]:flower('pink_flower',(x,y,z),s)
for x,y,z,s in [(-3.40,.40,4.42,.53),(-2.50,-2.93,1.10,.60),(3.20,-5.36,.92,.45),(3.52,-4.63,1.13,.52),(3.44,-1.31,3.35,.46),(-.04,-1.78,3.49,.42),(3.32,-1.18,3.61,.40)]:flower('daisy',(x,y,z),s)
place('pot',(.40,-1.75,1.36),scale=.28);place('sprout',(.40,-1.75,1.49),scale=.38)
place('pot',(-2.83,.06,3.90),scale=.65);place('palm',(-2.83,.06,4.20),scale=.53)

# Studio has no geometry, no game component ownership.
world=bpy.data.worlds.new('蓝色摄影背景');world.use_nodes=True;S.world=world;n=world.node_tree.nodes;lk=world.node_tree.links;bg=n.get('Background');bg.inputs[0].default_value=(.78,.85,1,1);bg.inputs[1].default_value=.43;camera_bg=n.new('ShaderNodeBackground');camera_bg.inputs[0].default_value=(.035,.48,.90,1);camera_bg.inputs[1].default_value=.8;lp=n.new('ShaderNodeLightPath');mix=n.new('ShaderNodeMixShader');lk.new(lp.outputs['Is Camera Ray'],mix.inputs[0]);lk.new(bg.outputs[0],mix.inputs[1]);lk.new(camera_bg.outputs[0],mix.inputs[2]);lk.new(mix.outputs[0],n.get('World Output').inputs[0])
def aim(o,p):o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
for name,pos,power,size,col in [('柔暖主光',(-6,-9,12),1250,6,(1,.95,.86)),('柔蓝补光',(7,-3,9),750,7,(.9,.96,1)),('屋顶轮廓光',(-1,6,13),1300,5,(1,1,.9))]:
 data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=col;o=bpy.data.objects.new(name,data);STUDIO.objects.link(o);o.location=pos;aim(o,(0,0,2.8))
camdata=bpy.data.cameras.new('附件等距相机');cam=bpy.data.objects.new('附件等距相机',camdata);STUDIO.objects.link(cam);cam.location=(-11,-17,12.4);aim(cam,(0,-1.9,2.5));camdata.type='ORTHO';camdata.ortho_scale=13.4;S.camera=cam
S.render.engine='CYCLES';S.cycles.samples=48;S.cycles.use_denoising=True;S.render.resolution_x=1300;S.render.resolution_y=1300;S.render.resolution_percentage=100;S.view_settings.view_transform='Standard';S.view_settings.look='None';S.view_settings.exposure=-.12
S['reference_sha256']=P['reference_sha256'];S['source_policy']=P['source_policy'];S['feature_id']='SEA-ASSET'
for screen in bpy.data.screens:
 for a in screen.areas:
  if a.type=='VIEW_3D':a.spaces.active.region_3d.view_perspective='CAMERA';a.spaces.active.shading.type='MATERIAL'
for item in catalog:
 item['instance_count']=sum(i['asset_id']==item['asset_id'] for i in instances)
 meshes=[o for o in parts[item['key']]['collection'].objects if o.type=='MESH'];fingerprint=[{'vertices':[[round(t,6) for t in v.co] for v in o.data.vertices],'faces':[list(p.vertices) for p in o.data.polygons]} for o in meshes];item['geometry_fingerprint']=hashlib.sha256(json.dumps(fingerprint).encode()).hexdigest()
(D/'catalog.json').write_text(json.dumps({'components':catalog},ensure_ascii=False,indent=2)+'\n');(D/'component_instances.json').write_text(json.dumps({'coordinate_contract':{'plane':'XY','up':'+Z','rotation':'full Euler XYZ radians','godot':'(x,y,z) -> (x,z,-y)'},'instances':instances},ensure_ascii=False,indent=2)+'\n')
im.filepath=bpy.path.relpath(str(PAL),start=str(D));bpy.ops.wm.save_as_mainfile(filepath=str(D/'sunny_bloom_retreat.blend'),compress=True)
print('BUILT',len(catalog),'components',len(instances),'instances',flush=True)
S.render.filepath=str(W/'previews/beauty.png');bpy.ops.render.render(write_still=True)
