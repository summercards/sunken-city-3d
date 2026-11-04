"""Reference-led Blender source. Only writes the new NGQ suite, never runtime scenes."""
import bpy,bmesh,math,json,os,hashlib,random
from pathlib import Path
from mathutils import Vector,Matrix,Euler,Quaternion
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/neon_garden_quarter/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'neon_garden_quarter/v001'
P=json.loads((D/'component_plan.json').read_text(encoding='utf8'))
assert P['status']=='frozen_before_geometry'
assert hashlib.sha256((D/P['reference']).read_bytes()).hexdigest()==P['reference_sha256']
assert (D/'textures/poster_atlas.png').exists(),'image-2 print atlas must exist'
random.seed(144)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version=0
S=bpy.context.scene;S.name='霓虹花园街区_完整装配';S.unit_settings.system='METRIC'
M=bpy.data.scenes.new('组件母版_独立编辑');M.unit_settings.system='METRIC'
bpy.context.window.scene=M
LAY={}
for key,name in [('architecture','01_建筑结构'),('fixtures','02_固定设施'),('signage','03_招牌与广告画'),('plants','04_独立植物'),('support','90_展示支持_不导出')]:
 c=bpy.data.collections.new(name);S.collection.children.link(c);LAY[key]=c
ROOTS={}
for key in ['architecture','fixtures','signage','plants']:
 c=bpy.data.collections.new('母版_'+key);M.collection.children.link(c);ROOTS[key]=c
PAL=bpy.data.images.load(str(R/P['palette']));PAL.name='SEA_暖木公共色板'
ATLAS=bpy.data.images.load(str(D/'textures/poster_atlas.png'));ATLAS.name='NGQ_image2_广告画图集'
cells=json.loads((R/P['palette']).with_suffix('.json').read_text())['cells']
CELL={x['name']:((x['column']+.5)/8,1-(x['row']+.5)/8) for x in cells}
MATS={}
for role,metal,rough in [('Matte',0,.78),('Metal',.32,.46),('Gloss',.08,.25),('Emission',0,.38)]:
 mat=bpy.data.materials.new('SEA_'+role);mat.use_nodes=True;n=mat.node_tree.nodes;n.clear();l=mat.node_tree.links
 out=n.new('ShaderNodeOutputMaterial');bs=n.new('ShaderNodeBsdfPrincipled');bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough
 uv=n.new('ShaderNodeUVMap');uv.uv_map='PaletteUV';tx=n.new('ShaderNodeTexImage');tx.image=PAL;tx.interpolation='Closest';l.new(uv.outputs['UV'],tx.inputs['Vector'])
 if role=='Matte':
  puv=n.new('ShaderNodeUVMap');puv.uv_map='PosterUV';pt=n.new('ShaderNodeTexImage');pt.image=ATLAS;pt.interpolation='Linear';l.new(puv.outputs['UV'],pt.inputs['Vector'])
  attr=n.new('ShaderNodeAttribute');attr.attribute_name='PosterMask';mix=n.new('ShaderNodeMixRGB');l.new(attr.outputs['Fac'],mix.inputs[0]);l.new(tx.outputs['Color'],mix.inputs[1]);l.new(pt.outputs['Color'],mix.inputs[2]);l.new(mix.outputs[0],bs.inputs['Base Color'])
 else:l.new(tx.outputs['Color'],bs.inputs['Base Color'])
 if role=='Emission':l.new(tx.outputs['Color'],bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=.35
 l.new(bs.outputs[0],out.inputs[0]);MATS[role]=mat
FONT=bpy.data.fonts.load('C:/Windows/Fonts/msyhbd.ttc');LATIN=bpy.data.fonts.load('C:/Windows/Fonts/arialbd.ttf')
CUR=None;CAT=[];COLS={};INST=[]
def dump(path,data):path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
def shade(o,color,role='Matte'):
 me=o.data;me.materials.clear();me.materials.append(MATS[role])
 for u in list(me.uv_layers):me.uv_layers.remove(u)
 uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True;cx,cy=CELL[color]
 for f in me.polygons:
  for j,li in enumerate(f.loop_indices):
   a=math.tau*j/len(f.loop_indices);uv.data[li].uv=(cx+.022*math.cos(a),cy+.022*math.sin(a))
 o['palette_color']=color;o['material_role']=role
 return o
def mesh(name,vs,fs,color='cream',role='Matte',bevel=0,smooth=False):
 me=bpy.data.meshes.new(name);me.from_pydata(vs,[],fs);me.update();bm=bmesh.new();bm.from_mesh(me)
 bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
 if bevel:
  edges=[e for e in bm.edges if e.is_manifold and e.calc_face_angle()>.6]
  bmesh.ops.bevel(bm,geom=edges,offset=bevel,segments=3,affect='EDGES',profile=.5,clamp_overlap=True)
  for f in bm.faces:f.smooth=len(f.verts)==4 and f.calc_area()<bevel*bevel*12
 bm.to_mesh(me);bm.free();me.update();o=bpy.data.objects.new(name,me);CUR.objects.link(o)
 if smooth:
  for p in me.polygons:p.use_smooth=True
 o['bevel_segments']=3 if bevel else 0;o['bevel_width_m']=bevel
 return shade(o,color,role)
def box(name,c,s,color='cream',bev=.045,role='Matte',rot=(0,0,0)):
 a,b,d=[x/2 for x in s];vs=[(-a,-b,-d),(a,-b,-d),(a,b,-d),(-a,b,-d),(-a,-b,d),(a,-b,d),(a,b,d),(-a,b,d)]
 mat=Euler(rot).to_matrix();vs=[mat@Vector(v)+Vector(c) for v in vs]
 return mesh(name,vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],color,role,min(bev,min(s)*.43))
def prism(name,xy,z0,z1,color='cream',bev=.05):
 n=len(xy);vs=[(x,y,z) for z in [z0,z1] for x,y in xy];fs=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 return mesh(name,vs,fs,color,bevel=bev)
def tube(name,pts,r,color='teal',role='Matte',sides=8):
 pts=[Vector(v) for v in pts];vs=[];fs=[]
 for i,p in enumerate(pts):
  direction=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized();up=Vector((0,0,1)) if abs(direction.z)<.9 else Vector((0,1,0));u=direction.cross(up).normalized();v=direction.cross(u).normalized()
  vs.extend(p+r*(u*math.cos(j*math.tau/sides)+v*math.sin(j*math.tau/sides)) for j in range(sides))
  if i:
   st=i*sides;fs.extend((st-sides+j,st-sides+(j+1)%sides,st+(j+1)%sides,st+j) for j in range(sides))
 fs+=[tuple(range(sides-1,-1,-1)),tuple(range(len(vs)-sides,len(vs)))]
 return mesh(name,vs,fs,color,role,smooth=True)
def sphere(name,c,r,color,seg=12,rings=7):
 vs=[];fs=[]
 for j in range(rings+1):
  t=math.pi*j/rings
  for i in range(seg):
   a=math.tau*i/seg;vs.append((c[0]+r[0]*math.sin(t)*math.cos(a),c[1]+r[1]*math.sin(t)*math.sin(a),c[2]+r[2]*math.cos(t)))
 for j in range(rings):
  for i in range(seg):a=j*seg+i;b=j*seg+(i+1)%seg;fs.append((a,b,b+seg,a+seg))
 return mesh(name,vs,fs,color,smooth=True)
def leaf(name,root,direction,length,width,color):
 root=Vector(root);d=Vector(direction).normalized();cross=d.cross(Vector((0,0,1)))
 if cross.length<.01:cross=Vector((1,0,0))
 cross.normalize();up=cross.cross(d).normalized();vs=[];fs=[];steps=6;bands=4
 for side in [-1,1]:
  for j in range(steps+1):
   t=j/steps;w=width*(max(.025,math.sin(math.pi*t))**.7)
   for k in range(bands+1):
    q=k/bands*2-1;v=root+d*(length*t)+cross*(q*w)+up*(length*.22*math.sin(math.pi*t)+.09*w*(1-q*q)+side*.025);vs.append(v)
 n=(steps+1)*(bands+1)
 for s in range(2):
  for j in range(steps):
   for k in range(bands):a=s*n+j*(bands+1)+k;fs.append((a,a+1,a+bands+2,a+bands+1) if s else (a+bands+1,a+bands+2,a+1,a))
 rim=list(range(bands+1))+[j*(bands+1)+bands for j in range(1,steps+1)]+[steps*(bands+1)+k for k in range(bands-1,-1,-1)]+[j*(bands+1) for j in range(steps-1,0,-1)]
 for i,a in enumerate(rim):b=rim[(i+1)%len(rim)];fs.append((a,b,b+n,a+n))
 return mesh(name,vs,fs,color,smooth=True)
def text(body,c,height,maxwidth,color='cream',vertical=False,role='Emission'):
 parts=list(body) if vertical else [body]
 for i,t in enumerate(parts):
  cu=bpy.data.curves.new('饱满厚字_'+t,'FONT');cu.body=t;cu.font=FONT if any(ord(k)>127 for k in t) else LATIN;cu.align_x='CENTER';cu.size=1;cu.extrude=.055;cu.bevel_depth=.023;cu.bevel_resolution=2;cu.resolution_u=3;cu.offset=.008
  obj=bpy.data.objects.new('EM_厚字_'+t,cu);CUR.objects.link(obj);bpy.context.view_layer.update()
  deps=bpy.context.evaluated_depsgraph_get();me=bpy.data.meshes.new_from_object(obj.evaluated_get(deps));coords=[v.co for v in me.vertices]
  lo=Vector([min(v[k] for v in coords) for k in range(3)]);hi=Vector([max(v[k] for v in coords) for k in range(3)])
  sc=min(height/max(hi.y-lo.y,.01),maxwidth/max(hi.x-lo.x,.01));mid=(lo+hi)/2
  for v in me.vertices:
   q=(v.co-mid)*sc;v.co=(c[0]+q.x,c[1]-q.z,c[2]-i*height*1.24+q.y)
  bm=bmesh.new();bm.from_mesh(me);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001);bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.000001)
  bad=[f for f in bm.faces if f.calc_area()<1e-10]
  if bad:bmesh.ops.delete(bm,geom=bad,context='FACES_ONLY')
  bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update()
  bpy.data.objects.remove(obj,do_unlink=True);ob=bpy.data.objects.new('EM_自发光厚字_'+t,me);CUR.objects.link(ob);shade(ob,color,role);ob['bold_font']='Microsoft YaHei Bold / Arial Bold';ob['text']=t
def arc(name,center,r,thick,z0,z1,a0,a1,color='cream',n=20):
 xy=[(center[0]+r*math.cos(a0+(a1-a0)*i/n),center[1]+r*math.sin(a0+(a1-a0)*i/n)) for i in range(n+1)]
 xy +=[(center[0]+(r-thick)*math.cos(a0+(a1-a0)*i/n),center[1]+(r-thick)*math.sin(a0+(a1-a0)*i/n)) for i in range(n,-1,-1)]
 return prism(name,xy,z0,z1,color,.035)
def artwork(name,w,h,tile,y=-.16,z=0,curved=False):
 # Printer's surfaces are the only meshes carrying the documented PosterUV exception.
 vs=[];fs=[];n=16 if curved else 1
 for k in range(n+1):
  u=k/n;x=(u-.5)*w;yy=y+(.38*(2*u-1)**2 if curved else 0);vs.extend([(x,yy,z),(x,yy,z+h)])
 for k in range(n):fs.append((k*2,k*2+2,k*2+3,k*2+1))
 o=mesh(name,vs,fs,'cream');uv=o.data.uv_layers.new(name='PosterUV');mask=o.data.attributes.new('PosterMask','FLOAT','POINT')
 for d in mask.data:d.value=1
 col=tile%4;row=tile//4
 for poly in o.data.polygons:
  for li in poly.loop_indices:
   vi=o.data.loops[li].vertex_index;u=(vi//2)/n;v=vi%2
   # Wide portrait is a crop of the tall printed source, never a stretched face.
   if tile==1:v=.38+v*.55
   uv.data[li].uv=((col+.012+u*.976)/4,1-(row+.012+(1-v)*.976)/2)
 o.data.uv_layers.active_index=0;o.data.uv_layers[0].active_render=True;uv.active_render=False;o['poster_tile']=tile;o['poster_exception']='image-2 printed art only'
 return o
def poster(w,h,tile,name,curved=False):
 box('厚实广告底板',(0,.06,h/2),(w+.22,.3,h+.22),'cream',.09)
 artwork(name,w,h,tile,-.50 if curved else -.105,0,curved)
 for x in [-w/2-.075,w/2+.075]:box('厚边框',(x,-.10,h/2),(.15,.2,h+.3),'wood_dark',.04)
 for z in [-.075,h+.075]:box('厚边框',(0,-.10,z),(w+.3,.2,.15),'wood_dark',.04)
def make(key):
 global CUR
 meta=next(x for x in P['components'] if x['key']==key);CUR=bpy.data.collections.new(meta['collection']);ROOTS[meta['category']].children.link(CUR);COLS[key]=CUR;CUR['asset_id']=meta['asset_id'];CUR['category']=meta['category'];return CUR
def finish(key):
 c=COLS[key];objs=list(c.objects);vs=[v.co for o in objs for v in o.data.vertices];lo=Vector([min(v[i] for v in vs) for i in range(3)]);hi=Vector([max(v[i] for v in vs) for i in range(3)]);shift=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 for o in objs:
  for v in o.data.vertices:v.co-=shift
  # Text tessellation can create slivers that collapse after float32 recentering.
  # Inspect the actual final mesh areas, not only BMesh's pre-save calculations.
  for attempt in range(3):
   o.data.update();bad_ids=[f.index for f in o.data.polygons if f.area<1e-8]
   if not bad_ids:break
   bm=bmesh.new();bm.from_mesh(o.data);bm.faces.ensure_lookup_table();bmesh.ops.delete(bm,geom=[bm.faces[i] for i in bad_ids],context='FACES_ONLY');bm.to_mesh(o.data);bm.free()
  o['component_asset_id']=c['asset_id']
 c.instance_offset=(0,0,0);c['author_origin_shift']=list(shift)
 entry=dict(next(x for x in P['components'] if x['key']==key));entry.update(bounds_size_m=list(hi-lo),author_origin_shift=list(shift),mesh_objects=len(objs),material_roles=sorted({m.name for o in objs for m in o.data.materials}),source=f'art_source/scenes/neon_garden_quarter/v001/component_packages/{key}/{key}.blend',manifest=f'art_source/scenes/neon_garden_quarter/v001/component_packages/{key}/asset_manifest.json',palette=P['palette'],source_stage='authored_pending_reopen_verification',collision_responsibility='facility_projection_pending',loaded_branch=P['branch'] if entry['building_class'] else None)
 CAT.append(entry)
def inst(key,loc,rot=0,scale=(1,1,1),tag=''):
 c=COLS[key];o=bpy.data.objects.new((tag+'_' if tag else '')+key,None);o.instance_type='COLLECTION';o.instance_collection=c;o.location=loc;o.rotation_euler=(0,0,rot);o.scale=scale;LAY[c['category']].objects.link(o);o['asset_id']=c['asset_id']
 INST.append(dict(name=o.name,asset_id=c['asset_id'],key=key,location=list(loc),euler_xyz=[0,0,rot],scale=list(scale)));return o

# STRUCTURE: real recesses and rear/side elevations, broad round-edged slabs.
for key,w,depth in [('street_deck',30,29)]:
 make(key);box('薄实体承载平台',(0,0,.1),(w,depth,.2),'stone',.044)
 for y in [-12,-8,-4,0,4,8,12]:box('宽铺装横缝',(0,y,.205),(w-.4,.05,.015),'wood_mid',.006)
 finish(key)
for key,w,depth,color in [('left_storey',9,18,'seafoam'),('back_storey',9,8,'cream'),('round_storey',9,18,'plaster')]:
 make(key)
 box('层板_厚0.2',(0,0,.1),(w,depth,.2),'cream',.044)
 # All four elevations are complete. Front has a broad masonry pier rhythm.
 for side in [-1,1]:
  yy=side*(depth/2-.2)
  for z,h in [(.6,.8),(4.45,1.3)]:box('前后连续墙带',(0,yy,z),(w,.4,h),color,.065)
  for x in [-4.25,-1.5,1.5,4.25]:box('0.5米主柱',(x,yy,2.65),(.5,.5,4.9),'cream',.095)
  for xx in [-w/2+.2,w/2-.2]:
   for z,h in [(.6,.8),(4.45,1.3)]:
    if key=='left_storey' and xx<0 and z<1:
     box('门洞后墙带',(xx,-4.25,z),(.4,9.5,h),color,.065);box('门洞前墙带',(xx,5.75,z),(.4,6.5,h),color,.065)
    else:box('侧面连续墙带',(xx,0,z),(.4,depth,h),color,.065)
   for yy2 in ([ -8.75,-6,-3,0,3,6,8.75] if depth==18 else [-3.75,0,3.75]):box('侧面主柱',(xx,yy2,2.65),(.5,.5,4.9),'cream',.095)
 # broad floor cornices, not densely striped masonry
 for side in [-1,1]:box('前后宽檐',(0,side*(depth/2+.05),4.95),(w+.25,.35,.3),'mint_white',.08)
 finish(key)
make('roof_room');box('封闭楼梯间',(0,0,1.55),(3.8,3.4,3.1),'cream',.12);box('门深色内凹',(0,-1.715,1.45),(1.8,.12,2.9),'teal',.05);box('厚实低坡屋盖',(0,0,3.18),(4.1,3.7,.28),'sage_gray',.10);box('门把手',(.6,-1.85,1.4),(.12,.15,.4),'gold',.04);finish('roof_room')
make('parapet');box('女儿墙',(0,0,.55),(3,.42,1.1),'plaster',.121);box('圆润压顶',(0,0,1.13),(3.15,.5,.24),'cream',.105);finish('parapet')
make('broken_parapet')
prism('左侧概括断口',[(-1.5,-.22),(-.25,-.22),(-.1,.22),(-1.5,.22)],0,.98,'plaster',.08)
prism('右侧大残墙',[(.45,-.22),(1.5,-.22),(1.5,.22),(.15,.22)],0,.65,'stone',.07)
box('左残压顶',(-.95,0,1.04),(1.15,.5,.24),'cream',.09,rot=(0,-.08,0));finish('broken_parapet')
make('rubble');prism('大块残片',[(-.6,-.45),(.35,-.5),(.66,-.1),(.4,.4),(-.35,.5)],0,.38,'stone',.06);box('大裂分残块',(.8,.1,.2),(.65,.6,.4),'plaster',.065,rot=(0,.12,.24));finish('rubble')
make('wall_scar');pr=prism('大片剥落',[(-.8,0),(-.45,-.18),(.5,-.12),(.9,.22),(.4,.65),(-.55,.8)],0,.055,'stone',.015)
for v in pr.data.vertices:v.co=(v.co.x,-v.co.z,v.co.y)
tube('一条概括裂缝',[(-.12,-.07,.6),(.12,-.07,.35),(-.1,-.07,.1),(.05,-.07,-.35)],.045,'wood_dark',sides=5);finish('wall_scar')
make('stair_flight')
for i in range(15):box('宽厚踏步',(0,i*.26,.17*(i+1)/2),(1.8,.275,.17*(i+1)),'stone',.035)
for x in [-.94,.94]:
 tube('连续粗扶手',[(x,0,1.05),(x,3.7,3.45)],.075,'teal')
 for i in [0,5,10,14]:tube('扶手立柱',[(x,i*.26,.17*(i+1)),(x,i*.26,.17*(i+1)+1)],.065,'teal')
finish('stair_flight')
make('stair_landing');box('转角平台',(0,0,.1),(4.4,2,.2),'stone',.044);finish('stair_landing')
make('guardrail')
for x in [-1.4,0,1.4]:box('粗栏柱',(x,0,.6),(.12,.12,1.2),'teal',.035)
for z in [.45,1.17]:box('横栏',(0,0,z),(3,.14,.14),'teal',.04)
finish('guardrail')
make('double_door')
box('门体',(0,0,1.55),(1.8,.18,3.1),'teal',.05)
for x in [-.44,.44]:
 box('上玻璃',(x,-.11,2),( .7,.05,1.55),'ocean',.025,'Gloss');box('下木芯',(x,-.12,.55),(.7,.07,.75),'sage_gray',.03);box('门把手',(x*.3,-.24,1.25),(.07,.12,.4),'gold',.025)
finish('double_door')
for key,broken in [('window_pair',False),('window_broken',True)]:
 make(key)
 for x in [-1.25,0,1.25]:box('厚窗竖框',(x,0,1.35),(.16,.3,2.7),'sage_gray',.045)
 for z in [.08,2.62]:box('厚窗横框',(0,0,z),(2.65,.3,.16),'cream',.045)
 for x in [-.62,.62]:
  if broken and x>.0:
   mesh('缺失一大角的玻璃',[(.12,.05,.2),(1.12,.05,.2),(1.12,.05,1.6),(.75,.05,1.3),(.55,.05,2.5),(.12,.05,2.5)],[(0,1,2,3,4,5)],'ocean','Gloss')
  else:box('深凹完整窗玻璃',(x,.09,1.35),(1.05,.08,2.4),'ocean',.025,'Gloss')
 box('窗台',(0,-.1,0),(2.9,.65,.18),'cream',.06);finish(key)
make('arc_window');arc('弧形蓝窗',(0,0),2.6,.10,.15,2.65,math.pi,math.pi*1.5,'ocean',20)
for z in [0,2.65]:arc('弧形厚窗框',(0,0),2.73,.25,z,z+.18,math.pi,math.pi*1.5,'sage_gray',20)
for a in [math.pi+i*math.pi/8 for i in range(5)]:box('圆角窗立挺',(2.66*math.cos(a),2.66*math.sin(a),1.4),(.16,.16,2.7),'cream',.04)
finish('arc_window')
make('round_balcony');arc('圆弧阳台实体墙',(0,0),2.9,.35,.2,1.3,math.pi,math.pi*1.5,'cream');prism('四分之一圆板',[(0,0)]+[(3.05*math.cos(math.pi+i*math.pi/40),3.05*math.sin(math.pi+i*math.pi/40)) for i in range(21)],0,.2,'plaster',.04);finish('round_balcony')
make('shop_awning');box('暖色斜雨棚',(0,0,.7),(3.4,1.5,.18),'coral',.07,rot=(.12,0,0));box('厚前裙',(0,-.7,.55),(3.4,.15,.45),'cream',.06)
for x in [-1.5,1.5]:tube('雨棚支撑',[(x,.65,0),(x,-.6,.65)],.09,'sage_gray')
finish('shop_awning')
make('aircon');box('空调厚壳',(0,0,.65),(1.8,.75,1.3),'sage_gray',.10)
for i in range(5):box('宽格栅',(-.55,-.4,.3+i*.18),(.55,.08,.065),'cream',.018)
sphere('风扇圆罩',(.35,-.43,.68),(.45,.07,.45),'teal')
for a in [0,math.pi/2]:box('风扇粗叶',(.35,-.52,.68),(.65,.04,.12),'sage_gray',.03,rot=(0,a,0))
finish('aircon')
make('water_tank');tube('圆柱水箱',[(0,0,.5),(0,0,3.0)],1.15,'seafoam',sides=24)
for z in [.6,2.9]:tube('宽环带',[(1.17*math.cos(i*math.tau/32),1.17*math.sin(i*math.tau/32),z) for i in range(33)],.10,'cream')
for x in [-.7,.7]:box('水箱支脚',(x,0,.25),(.2,1.1,.5),'sage_gray',.06)
finish('water_tank')
make('drainpipe');tube('粗排水管',[(0,.25,0),(0,0,.3),(0,0,4.6),(0,.25,4.9)],.12,'sage_gray')
for z in [1,3.9]:box('管箍',(0,.1,z),(.36,.35,.13),'cream',.04)
finish('drainpipe')
make('street_lamp');tube('粗弯灯臂',[(0,0,0),(0,0,3.1),(.15,-.2,3.4),(.2,-.9,3.4)],.1,'teal');sphere('旧灯罩',(.2,-.9,3.25),(.4,.4,.2),'cream');em=sphere('EM_自发光灯芯',(.2,-.9,3.16),(.25,.25,.10),'butter');shade(em,'butter','Emission');finish('street_lamp')
make('lantern');em=sphere('EM_自发光灯笼',(0,0,.75),(.44,.44,.68),'coral',16,10);shade(em,'coral','Emission')
for z in [.1,1.4]:box('灯笼端帽',(0,0,z),(.55,.55,.16),'wood_dark',.055)
for a in [0,math.pi/2,math.pi,math.pi*1.5]:tube('灯笼概括骨线',[(.33*math.cos(a),.33*math.sin(a),.2),(.45*math.cos(a),.45*math.sin(a),.75),(.33*math.cos(a),.33*math.sin(a),1.3)],.026,'wood_dark',sides=6)
finish('lantern')
# Eight painted panels are atlas samples; giant signs are rounded extruded geometry.
for key,w,h,tile in [('bar_poster',2.35,5.0,0),('portrait_poster',4.6,4.2,1),('drink_poster',3.4,4.2,2),('route_board',2.0,3.1,4),('menu_board',3.3,3.3,5),('small_placard',1.25,2.4,7)]:
 make(key);poster(w,h,tile,key);finish(key)
make('charcoal_sign');poster(4.9,7.6,3,'弧面炭火印画',True);box('酒楼弧牌厚眉头',(0,0,8.6),(5.15,.52,1.7),'cream',.15);text('海道酒場',(0,-.39,8.6),.98,4.6,'jade');finish('charcoal_sign')
make('tavern_sign');box('奶油长竖招牌',(0,0,5.4),(2.5,.42,10.8),'cream',.14);text('海道酒場',(0,-.36,9.2),1.7,2.05,'jade',True);finish('tavern_sign')
make('restaurant_neon');box('旧店竖牌底',(0,0,5.8),(1.85,.38,11.6),'seafoam',.12);text('レストラン',(0,-.34,10.1),1.3,1.5,'cream',True);finish('restaurant_neon')
make('round_sign');tube('厚圆招牌',[(0,.12,1.25),(0,-.12,1.25)],1.25,'cream',sides=32)
vs=[(0,-.15,1.25)]+[(1.16*math.cos(i*math.tau/32),-.15,1.25+1.16*math.sin(i*math.tau/32)) for i in range(32)]
o=mesh('圆形裁切印画',vs,[(0,i+1,(i+1)%32+1) for i in range(32)],'cream');uv=o.data.uv_layers.new(name='PosterUV');mask=o.data.attributes.new('PosterMask','FLOAT','POINT')
for d in mask.data:d.value=1
for f in o.data.polygons:
 for li in f.loop_indices:
  v=o.data.vertices[o.data.loops[li].vertex_index].co;uv.data[li].uv=(.625+v.x/2.5*.25,.25+(v.z-1.25)/2.5*.25)
o.data.uv_layers.active_index=0;o.data.uv_layers[0].active_render=True;uv.active_render=False;o['poster_tile']=6;finish('round_sign')
make('trellis')
for x in [-1.2,0,1.2]:tube('粗竹架',[(x,0,0),(x+.08,.05,3.2)],.07,'wood_mid')
for z in [1.2,2.7]:tube('竹架横杆',[(-1.4,.02,z),(1.5,.02,z)],.065,'wood_light')
finish('trellis')
make('crop_bed');box('整块肥土',(0,0,.13),(2.5,5.2,.26),'bark',.10)
for x in [-1.32,1.32]:box('厚菜床边',(x,0,.18),(.15,5.45,.36),'wood',.05)
for y in [-2.66,2.66]:box('菜床端边',(0,y,.18),(2.8,.15,.36),'wood',.05)
finish('crop_bed')
make('planter');box('长花箱',(0,0,.45),(2.5,.9,.9),'wood_light',.09);box('整块土',(0,0,.91),(2.25,.68,.1),'bark',.04);finish('planter')
make('cabbage');sphere('圆润菜心',(0,0,.40),(.31,.31,.36),'leaf_light')
for i in range(8):a=i*math.tau/8;leaf('厚圆卷叶',(math.cos(a)*.12,math.sin(a)*.12,.13),(math.cos(a),math.sin(a),.55),.65,.35,'leaf_light' if i%2 else 'leaf')
finish('cabbage')
make('tomato');tube('主茎',[(0,0,0),(.05,0,1.2),(-.04,.06,2.6)],.055,'leaf_dark')
for i in range(8):
 a=i*2.4;z=.4+i*.25;tip=(math.cos(a)*.65,math.sin(a)*.55,z+.2);tube('粗分枝',[(0,0,z),tip],.035,'leaf');leaf('番茄大叶',tip,(math.cos(a),math.sin(a),.5),.5,.22,'leaf')
 if i%2==0:
  for j in range(2):sphere('红番茄',(tip[0]+j*.22,tip[1],tip[2]-.18-j*.1),(.17,.17,.19),'red' if j else 'coral')
finish('tomato')
make('herb')
for i in range(7):a=i*2.4;leaf('饱满圆菜叶',(0,0,.05),(math.cos(a),math.sin(a),.6+i*.12),.85,.23,'leaf' if i%2 else 'leaf_light')
finish('herb')
make('broadleaf')
for i in range(9):a=i*2.4;leaf('大宽叶',(0,0,.03),(math.cos(a),math.sin(a),.55+(i%3)*.5),1.5,.36,'leaf_dark' if i%3==0 else 'leaf')
finish('broadleaf')
make('vine');tube('粗藤主干',[(0,0,0),(.15,0,.8),(-.1,0,1.5),(.1,0,2.2),(0,0,3.2)],.05,'wood_mid')
for i in range(12):
 side=(-1)**i;leaf('藤蔓宽心叶',(0,-.025,.15+i*.24),(side,-.25,-.25),.52,.25,'leaf' if i%3 else 'leaf_light')
finish('vine')
make('hanging_bush')
for i in range(15):
 a=i*2.4;r=.4+random.random()*.4;leaf('密集垂叶',(math.cos(a)*r,math.sin(a)*r,.9+random.random()*.4),(math.cos(a)*.4,math.sin(a)*.4,-1),.8,.28,'leaf' if i%3 else 'sage')
finish('hanging_bush')
make('flowers')
for i in range(5):
 a=i*2.4;x=math.cos(a)*.35;y=math.sin(a)*.3;z=.45+(i%2)*.2;tube('粗花梗',[(x,y,0),(x,y,z)],.035,'leaf')
 for j in range(5):
  b=j*math.tau/5;leaf('饱满圆花瓣',(x,y,z),(math.cos(b),math.sin(b),.25),.34,.15,'pink_light' if i%2 else 'cream')
 sphere('花心',(x,y,z+.03),(.11,.11,.09),'butter',8,5)
finish('flowers')
make('grass')
for i in range(9):a=i*2.4;leaf('长厚草叶',(0,0,0),(math.cos(a)*.45,math.sin(a)*.45,1),1.1+(i%3)*.2,.12,'sage' if i%2 else 'leaf_light')
finish('grass')
make('roof_soil');box('花园屋顶实板',(0,0,.1),(9,8,.2),'cream',.044);box('大块菜园土坪',(0,0,.24),(8.3,7.3,.28),'wood_dark',.10);finish('roof_soil')
make('utility_cable');tube('概括粗缆',[(-3,0,.8),(-1.5,0,.3),(0,0,.15),(1.5,0,.3),(3,0,.8)],.065,'teal')
for x in [-3,3]:box('墙支架',(x,.1,.8),(.2,.5,.2),'sage_gray',.05)
finish('utility_cable')

# LAYOUT: the alley opens toward -Y. Five-storey garden closes the view, two tall wings frame it.
inst('street_deck',(-1,3,.1),scale=(1.1,1,1));floor_top=.3
buildings=[('left',-8,1,6,'left_storey'),('right',8,1,7,'round_storey'),('back',0,14,5,'back_storey')]
for tag,x,y,n,key in buildings:
 depth=8 if tag=='back' else 18
 for k in range(n):
  z=floor_top+k*5.1;inst(key,(x,y,z),tag=tag)
  for side in [-1,1]:
   for j in [-1,0,1]:
    xx=x+j*2.9;yy=y+side*(depth/2+.1);rot=0 if side==-1 else math.pi
    inst('window_broken' if (k+j+(tag=='right'))%7==0 else 'window_pair',(xx,yy,z+1),rot,tag=f'{tag}_frontrear')
   for yy2 in ([-7.4,-4.5,-1.5,1.5,4.5,7.4] if depth==18 else [-2,2]):
    if tag=='left' and side==-1 and yy2==1.5:inst('double_door',(x-4.65,y+yy2,z+.2),-math.pi/2,tag='楼梯侧门')
    else:inst('window_pair',(x+side*4.6,y+yy2,z+1),math.pi/2 if side==1 else -math.pi/2,tag=f'{tag}_side')
  if k in [1,3,5]:
   inst('wall_scar',(x-2.3,y-depth/2-.23,z+3.5));inst('aircon',(x+3,y-depth/2-.55,z+3.6))
  inst('drainpipe',(x+4.7,y+depth/2-.5,z),math.pi/2)
 # Complete the roof with a separate flat slab. No duplicated coincident floor faces.
 roofz=floor_top+n*5.1
 if tag=='back':inst('roof_soil',(x,y,roofz))
 else:inst('street_deck',(x,y,roofz),scale=(9/30,18/29,1))
 for xx in [-3,0,3]:
  inst('broken_parapet' if xx==0 and tag!='back' else 'parapet',(x+xx,y-depth/2,roofz+.2))
  inst('parapet',(x+xx,y+depth/2,roofz+.2))
 for side in [-1,1]:
  for dy in ([-7.5,-4.5,-1.5,1.5,4.5,7.5] if depth==18 else [-2.5,.5,2.5]):
   if not(tag=='left' and side==-1 and dy==1.5):inst('parapet',(x+side*4.5,y+dy,roofz+.2),math.pi/2)
 if tag!='back':
  inst('roof_room',(x,y+4,roofz+.2));inst('water_tank',(x-2,y+7,roofz+.2));inst('aircon',(x+2,y+2,roofz+.2));inst('rubble',(x-.5,y-7.6,roofz+.2))
 for xx in [-2.8,0,2.8]:
  inst('double_door',(x+xx,y-depth/2-.32,.3));inst('shop_awning',(x+xx,y-depth/2-.9,3.65));inst('lantern',(x+xx+.9,y-depth/2-1.3,2.1))
# Round upper corner is an additive bay attached to the right building, showing the reference's silhouette.
for z in [25.8,30.9]:
 inst('round_balcony',(4.1,-8.0,z));inst('arc_window',(4.25,-7.85,z+1.3))
inst('charcoal_sign',(6.8,-8.65,20.8),rot=-.07)
inst('tavern_sign',(3.6,-8.95,10.2),rot=-.06)
inst('restaurant_neon',(1.55,-8.7,9.9))
inst('route_board',(1.55,-8.75,22.0))
inst('menu_board',(7,-9.0,15.8),rot=-.07)
inst('bar_poster',(-4.0,-9.1,15.3),rot=.08)
inst('round_sign',(-4.4,-9.3,11.7),rot=.03)
inst('small_placard',(-5.4,-9.1,5.1))
inst('drink_poster',(-1.4,9.65,17.4))
inst('portrait_poster',(-1.2,9.62,11.5))
inst('small_placard',(1.9,9.6,7.4))
inst('menu_board',(-7.4,-9.1,21.5))
inst('route_board',(-9.5,-9.1,27))
inst('small_placard',(10.9,-9.12,6.3))
inst('bar_poster',(8,9.1,17),math.pi)
inst('menu_board',(-8,10.1,6.5),math.pi)
for x in [-3.0,3.0]:
 for yy in [-4,3,8]:inst('street_lamp',(x,yy,.3),0 if x<0 else math.pi)
for z in [8,16,23]:inst('utility_cable',(0,5,z))
for side in [-1,1]:
 for j,yy in enumerate([-2,3.5,7.5]):
  for k,z in enumerate([5.6,12,18.4]):
   key=['small_placard','route_board','menu_board'][(j+k+(side==1))%3]
   inst(key,(side*3.28,yy,z),math.pi/2 if side<0 else -math.pi/2,scale=(.72,.72,.72),tag='街内店招')
  inst('vine',(side*3.25,yy+1.1,21),math.pi/2 if side<0 else -math.pi/2)
# Back-roof farming: three readable beds and coarse vertical tomato supports.
garden_z=26.0
for x in [-2.8,0,2.8]:
 inst('crop_bed',(x,13.8,garden_z))
 for iy in range(5):
  for dx in [-.55,.55]:inst('cabbage' if x<0 else 'herb',(x+dx,11.9+iy*.95,garden_z+.35),rot=random.random()*6.28)
for x in [-2.8,0,2.8]:
 inst('trellis',(x,16.6,garden_z+.25))
 for dx in [-.65,.65]:inst('tomato',(x+dx,16.5,garden_z+.25),rot=random.random())
# Side fire stair is complete, with continuous six-level access and generous flat landings.
for floor in range(6):
 z=.3+floor*5.1
 inst('stair_flight',(-15.7,5.32,z));inst('stair_landing',(-14.7,8.2775,z+2.55-.2))
 inst('stair_flight',(-13.7,5.32,z+2.55),math.pi);inst('stair_landing',(-14.7,2.3625,z+5.1-.2))
# Vegetation uses only independent plant instances: rooftop, frame vines, pavement pockets.
for x,y,z in [(-8,-7,31.1),(7,-6,36.2),(-8,7,31.1),(8,7,36.2),(4,-7,31.2)]:
 inst('planter',(x,y,z));inst('grass',(x-.6,y,z+.94));inst('flowers',(x+.7,y,z+.94));inst('hanging_bush',(x,y-.3,z+.45))
for x,y,z in [(-4.8,-9.35,15),(-3,-9.35,15),(-5.6,-9.3,21),(2.25,-9.35,21),(8.5,-9.4,21),(9.4,-9.4,15),(-10,-9.3,26),(-3.8,9.3,20),(-4.4,8,24),(3.7,8,24)]:
 inst('vine',(x,y,z));inst('hanging_bush',(x,y,z+2.7),scale=(.65,.65,.65));inst('flowers',(x+.2,y-.1,z+2.7),scale=(.7,.7,.7))
for i in range(25):
 x=random.choice([-1,1])*random.uniform(3.7,12.4);y=random.uniform(-10.5,16);inst('broadleaf' if i%3==0 else 'grass',(x,y,.31),rot=random.random()*6.28)
 if i%4==0:inst('flowers',(x+.4,y,.31))
for x in [-4.0,4.0]:
 for yy in [0,5,9]:inst('hanging_bush',(x,yy,25.9));inst('vine',(x,yy,23.0),math.pi/2)
for pos in [(-11,-9,.3),(10,-8.7,.3),(-12,6,.3),(11,11,.3)]:inst('rubble',pos,rot=random.random())

# Facilities-only annotations: no collision or gameplay completion claimed.
S['asset_id']=P['assembly_asset_id'];S['building_class']='above_water';S['runtime_integration']='pending';S['reference_exclusions']='water / human meshes / animals';S['poster_generator']='gpt-image-2'
S.world=bpy.data.worlds.new('温暖晴空');S.world.use_nodes=True;S.world.node_tree.nodes['Background'].inputs[0].default_value=(.64,.78,.75,1);S.world.node_tree.nodes['Background'].inputs[1].default_value=.65
def camera(name,pos,target,ortho=None,lens=42):
 d=bpy.data.cameras.new(name);o=bpy.data.objects.new(name,d);LAY['support'].objects.link(o);o.location=pos;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();d.clip_end=500
 if ortho:d.type='ORTHO';d.ortho_scale=ortho
 else:d.lens=lens;d.sensor_fit='VERTICAL'
 return o
CAMS={
 'hero':camera('全景_完整建筑群',(-24,-65,50),(0,4,17),51),
 'reference':camera('参考镜头_街巷',(-.4,-53,36),(0,5,17.5),None,30),
 'garden':camera('近景_屋顶菜园',(0,2,44),(0,14,26),15),
 'top':camera('俯视_空间布局',(1,3,80),(0,3,0),37),
 'rear':camera('补全_背面屋顶',(-43,58,42),(0,4,17),51),
 'signs':camera('近景_招牌厚字',(-11,-34,25),(3,-8,21),27),
}
S.camera=CAMS['hero']
for name,pos,energy,size in [('主柔光',(-25,-35,60),4200,25),('右补光',(25,5,40),2500,20),('街巷柔光',(0,-5,21),700,7)]:
 d=bpy.data.lights.new(name,'AREA');d.energy=energy;d.shape='DISK';d.size=size;o=bpy.data.objects.new(name,d);LAY['support'].objects.link(o);o.location=pos;o.rotation_euler=(Vector((0,3,15))-o.location).to_track_quat('-Z','Y').to_euler()
d=bpy.data.lights.new('日光','SUN');d.energy=2.2;d.angle=.2;o=bpy.data.objects.new('日光',d);LAY['support'].objects.link(o);o.rotation_euler=(.42,-.5,-.45)
S.render.engine='CYCLES';S.cycles.samples=32;S.cycles.use_denoising=True
S.render.resolution_x=1600;S.render.resolution_y=1600;S.render.resolution_percentage=100;S.render.image_settings.file_format='PNG';S.render.film_transparent=False
S.view_settings.view_transform='AgX';S.view_settings.look='AgX - Medium High Contrast'
for scr in bpy.data.screens:
 for area in scr.areas:
  if area.type=='VIEW_3D':
   sp=area.spaces.active;sp.shading.type='MATERIAL';sp.region_3d.view_location=(0,4,17);sp.region_3d.view_distance=62;sp.region_3d.view_rotation=CAMS['hero'].rotation_euler.to_quaternion();sp.clip_end=500
bpy.context.window.scene=S;bpy.context.view_layer.update()
for curve in list(bpy.data.curves):
 if not curve.users:bpy.data.curves.remove(curve)
for font in list(bpy.data.fonts):
 if not font.users:bpy.data.fonts.remove(font)
for image in [PAL,ATLAS]:image.filepath=bpy.path.relpath(image.filepath,start=str(D))
bpy.ops.wm.save_as_mainfile(filepath=str(D/'neon_garden_quarter.blend'),compress=True)
dump(D/'component_catalog.json',dict(schema='sea.component_catalog',components=CAT))
dump(D/'component_instances.json',dict(schema='sea.component_instances',coordinate_system='Blender XY ground +Z up; Godot(x,z,-y)',instances=INST))
print('NGQ_BUILD_COMPLETE',len(CAT),'components',len(INST),'instances',flush=True)
