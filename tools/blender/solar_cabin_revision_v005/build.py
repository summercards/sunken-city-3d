"""Derive v005 from saved v004; all edits are in the new source only."""
import bpy,bmesh,json,math,hashlib,os
from pathlib import Path
from mathutils import Matrix,Vector,Euler
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v005';OLD=D.parent/'v004';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'solar_cabin_revision_v005';P=json.loads((D/'component_plan.json').read_text());assert P['status']=='frozen_before_geometry'
PAL=R/P['palette'];cells={x['name']:x for x in json.loads(PAL.with_suffix('.json').read_text())['cells']}
oldcat=json.loads((OLD/'catalog.json').read_text())['components'];cat={x['key']:x.copy() for x in oldcat};spec={x['key']:x for x in P['components']}
bpy.ops.wm.open_mainfile(filepath=str(OLD/'sunny_bloom_retreat.blend'));bpy.context.preferences.filepaths.save_version=0;S=bpy.context.scene;S.name='太阳能木屋-海上区域-v005';LIB=next(s for s in bpy.data.scenes if s!=S)
M={key:bpy.data.materials['SEA_'+key] for key in ['Matte','Metal','Gloss','Emission']}
def paint(me,color,faces=None):
 uv=me.uv_layers.get('PaletteUV') or me.uv_layers.new(name='PaletteUV')
 for layer in list(me.uv_layers):
  if layer.name!='PaletteUV':me.uv_layers.remove(layer)
 me.uv_layers.active_index=0;uv=me.uv_layers['PaletteUV'];uv.active_render=True;c=cells[color];u=(c['column']+.5)/8;v=1-(c['row']+.5)/8
 for f in me.polygons if faces is None else faces:
  for k,l in enumerate(f.loop_indices):
   a=2*math.pi*k/len(f.loop_indices);uv.data[l].uv=(u+.025*math.cos(a),v+.025*math.sin(a))
def recolor(key,color,wood_only=False):
 for o in bpy.data.collections[cat[key]['collection']].objects:
  if o.type!='MESH':continue
  fs=list(o.data.polygons);uv=o.data.uv_layers['PaletteUV']
  if wood_only:fs=[f for f in fs if int(uv.data[f.loop_indices[0]].uv.y*8)==6]
  paint(o.data,color,fs)
def select(o):
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o

def box_mesh(key,dimensions,color,bevel=.045):
 col=bpy.data.collections.get(cat[key]['collection']) if key in cat else None
 if col:
  for o in list(col.objects):bpy.data.objects.remove(o,do_unlink=True)
 else:
  col=bpy.data.collections.new(spec[key]['asset_id']);LIB.collection.children.link(col)
 S.collection.children.link(col)
 bpy.ops.mesh.primitive_cube_add(size=1,location=(0,0,dimensions[2]/2));o=bpy.context.object;o.scale=dimensions
 for c in list(o.users_collection):c.objects.unlink(o)
 col.objects.link(o);select(o);bpy.ops.object.transform_apply(location=True,rotation=False,scale=True)
 b=o.modifiers.new('实体倒角','BEVEL');b.width=bevel;b.segments=3;bpy.ops.object.modifier_apply(modifier=b.name)
 for f in o.data.polygons:f.use_smooth=True
 n=o.modifiers.new('加权法线','WEIGHTED_NORMAL');n.keep_sharp=True;bpy.ops.object.modifier_apply(modifier=n.name)
 o.name=key+'_mesh';o.data.materials.clear();o.data.materials.append(M['Matte']);paint(o.data,color)
 root=bpy.data.objects.new('ROOT_'+key,None);col.objects.link(root);o.parent=root;S.collection.children.unlink(col)
 cat[key]=dict(spec[key],collection=col.name,root=root.name,source_anchor=[0,0,0]);return col
# Three structural concrete remnants replace decorative pergola posts/beams.
box_mesh('canopy_post',(.30,.30,2.20),'cloud',.032)
# Slightly uneven cut top, small enough to read as solid old floor columns.
post=next(o for o in bpy.data.collections[cat['canopy_post']['collection']].objects if o.type=='MESH')
for v in post.data.vertices:
 if v.co.z>2.10:v.co.z+=.024*(v.co.x/.15)+.009*(v.co.y/.15)
# Thick, softly rounded ground boards; top surfaces stay on the same datum.
box_mesh('platform_board',(7.5,.518,.40),'berry',.085)
box_mesh('dock_board',(2.48,.435,.40),'wood_light',.085)
box_mesh('concrete_slab',(7.5,6.2,.40),'cloud',.085)
# Create rope and tire modules with actual round geometry and shared palette UV.
def start(key):
 col=bpy.data.collections.new(spec[key]['asset_id']);LIB.collection.children.link(col);S.collection.children.link(col);return col

def finish_obj(o,col,color):
 for c in list(o.users_collection):c.objects.unlink(o)
 col.objects.link(o);select(o);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);o.data.materials.clear();o.data.materials.append(M['Matte']);paint(o.data,color)
 for f in o.data.polygons:f.use_smooth=True
 return o

def tube(col,name,pts,r=.045,color='cream'):
 cv=bpy.data.curves.new(name,'CURVE');cv.dimensions='3D';cv.resolution_u=12;cv.bevel_depth=r;cv.bevel_resolution=3;sp=cv.splines.new('BEZIER');sp.bezier_points.add(len(pts)-1)
 for q,p in zip(sp.bezier_points,pts):q.co=p;q.handle_left_type='AUTO';q.handle_right_type='AUTO'
 o=bpy.data.objects.new(name,cv);col.objects.link(o);select(o);bpy.ops.object.convert(target='MESH');return finish_obj(o,col,color)

def torus(col,name,p,major,minor,rotation=(0,0,0),color='rubber'):
 bpy.ops.mesh.primitive_torus_add(major_segments=40,minor_segments=12,major_radius=major,minor_radius=minor,location=p,rotation=rotation);o=bpy.context.object;o.name=name;return finish_obj(o,col,color)

def end(key,col):
 meshes=[o for o in col.objects if o.type=='MESH'];vs=[v.co for o in meshes for v in o.data.vertices];lo=Vector([min(v[i] for v in vs) for i in range(3)]);hi=Vector([max(v[i] for v in vs) for i in range(3)]);anchor=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 for o in meshes:o.data.transform(Matrix.Translation(-anchor))
 root=bpy.data.objects.new('ROOT_'+key,None);col.objects.link(root)
 for o in meshes:o.parent=root
 cat[key]=dict(spec[key],collection=col.name,root=root.name,source_anchor=list(anchor));S.collection.children.unlink(col);return anchor
col=start('bridge_rope');length=5.265
# End loops and smooth catenary-like sag; stays at the two edges only.
tube(col,'粗麻绳垂弧',[(-length/2,0,.42),(-length/4,0,.13),(0,0,0),(length/4,0,.13),(length/2,0,.42)])
for x in [-length/2,length/2]:torus(col,'绳结绕柱',(x,0,.42),.275,.045,color='cream')
rope_anchor=end('bridge_rope',col)
col=start('hanging_tire')
torus(col,'饱满橡胶轮胎',(0,0,.55),.40,.145,rotation=(math.pi/2,0,0))
for y in [-.115,.115]:torus(col,'胎侧环纹',(0,y,.55),.395,.027,rotation=(math.pi/2,0,0),color='slate')
tube(col,'轮胎悬挂绳',[(0,-.30,1.44),(0,-.13,1.15),(0,-.12,.94),(.08,-.02,.87),(0,.12,1.0),(0,-.13,1.15)],.035)
tire_anchor=end('hanging_tire',col)
# Restore explicit placement from the saved current source, then make narrow edits.
byid={e['asset_id']:e['key'] for e in oldcat};objects=[o for o in S.objects if o.instance_type=='COLLECTION']
for o in objects:
 key=byid[o.instance_collection.name]
 if key=='canopy_beam':bpy.data.objects.remove(o,do_unlink=True);continue
 if o.get('module')=='solar_room':o.location.x+=1.25
 if key in {'platform_board','dock_board'}:o.location.z=.68-.40*o.scale.z
 if key=='concrete_slab':
  # Preserve elevated side-roof thickness, enlarge only the ground slab.
  if o.location.z<1:o.location.z=.68-.40*o.scale.z
  else:o.scale.z*=.24/.40
 if key=='bollard' and o.get('module')=='bridge':o.location.y-=1.38
# Align the three columns with the exact lower bearing-column centerlines.
posts=[o for o in S.objects if o.instance_type=='COLLECTION' and byid.get(o.instance_collection.name)=='canopy_post']
for ob,(x,y,height) in zip(posts,[(-4.395,-1.59,2.70),(-4.395,3.51,3.30),(-.72,3.51,3.30)]):
 ob.location=(x,y,4.95);ob.scale=(1.5,1.5,height/2.2);ob.rotation_euler=(0,0,0)
# Recut stretched sail between the new columns and wall attachment. Supports
# end above the cloth so the remains of an old concrete storey read clearly.
col=bpy.data.collections[cat['sail']['collection']]
for o in list(col.objects):bpy.data.objects.remove(o,do_unlink=True)
S.collection.children.link(col);vs=[];fs=[]
corners=[Vector((-4.395,-1.59,7.42)),Vector((-.14,-.30,7.42)),Vector((-4.395,3.51,8.05)),Vector((-.72,3.51,8.05))]
for j in range(13):
 for i in range(21):
  u=i/20;v=j/12;p=(1-v)*((1-u)*corners[0]+u*corners[1])+v*((1-u)*corners[2]+u*corners[3]);p.z-=.48*math.sin(math.pi*u)*(.7+.3*math.sin(math.pi*v));vs.append(tuple(p))
for j in range(12):
 for i in range(20):a=j*21+i;fs.append((a,a+1,a+22,a+21))
me=bpy.data.meshes.new('新柱间柔软棚布');me.from_pydata(vs,[],fs);me.update();o=bpy.data.objects.new('sail_mesh',me);col.objects.link(o);select(o);mod=o.modifiers.new('布厚度','SOLIDIFY');mod.thickness=.035;bpy.ops.object.modifier_apply(modifier=mod.name);finish_obj(o,col,'butter')
# end helper normalizes the component and captures its placement anchor.
sail_anchor=end('sail',col)
for o in S.objects:
 if o.instance_type=='COLLECTION' and byid.get(o.instance_collection.name)=='sail':o.location=sail_anchor;o.scale=(1,1,1);o.rotation_euler=(0,0,0)
 if o.instance_type=='COLLECTION' and byid.get(o.instance_collection.name)=='canopy_hook':o.location.z=6.20
# Remove flora overlapping the new column feet, preserving unrelated greenery.
for o in list(S.objects):
 if o.instance_type!='COLLECTION' or o.get('module')!='rear_building':continue
 key=byid.get(o.instance_collection.name)
 if key in {'foliage','daisy'} and 4.6<o.location.z<6.1 and any(abs(o.location.x-x)<.55 and abs(o.location.y-y)<.55 for x,y in [(-4.395,-1.59),(-4.395,3.51),(-.72,3.51)]):bpy.data.objects.remove(o,do_unlink=True)
bridge=bpy.data.collections['04 栈桥-暖木']
def instance(key,name,pos,rot=0,scale=(1,1,1),anchor=None):
 o=bpy.data.objects.new(name,None);bridge.objects.link(o);o.instance_type='COLLECTION';o.instance_collection=bpy.data.collections[cat[key]['collection']];o.rotation_euler=(0,0,rot);o.scale=scale;o.location=Vector(pos)+(o.rotation_euler.to_matrix()@anchor if anchor is not None else Vector((0,0,0)));o['module']='bridge';o['asset_id']=spec[key]['asset_id'];return o
for row in [6,7]:instance('dock_board',f'桥横向长板_{row+1:02}',(-1.7925,-9.825-row*.69,.08),scale=(1.5,1.5,1.5))
for x in [-3.69,.105]:instance('bridge_rope','栈桥边缘粗绳',(x,(-9.375-14.64)/2,1.14),rot=math.pi/2,anchor=rope_anchor)
for side,x in [(-1,-3.99),(1,.405)]:
 for y in [-10.8075,-13.2075]:instance('hanging_tire','桥边悬挂轮胎',(x,y,-.20),rot=-side*math.pi/2,anchor=tire_anchor)
# Update normalized component bounds, per-instance manifests and semantic parts.
byid.update({e['asset_id']:key for key,e in spec.items()});instances=[];used=set()
for o in S.objects:
 if o.instance_type!='COLLECTION':continue
 key=byid[o.instance_collection.name];used.add(key);instances.append(dict(name=o.name,asset_id=spec[key]['asset_id'],position=list(o.location),rotation_euler_xyz=list(o.rotation_euler),scale=list(o.scale),category=spec[key]['category'],module=o['module']))
entries=[]
for key in sorted(used):
 item=dict(cat[key]);item.update(spec[key]);col=bpy.data.collections[item['collection']];vs=[v.co for o in col.objects if o.type=='MESH' for v in o.data.vertices];lo=[min(v[i] for v in vs) for i in range(3)];hi=[max(v[i] for v in vs) for i in range(3)];item.update(bounds_min=lo,bounds_size=[hi[i]-lo[i] for i in range(3)],instance_count=sum(e['asset_id']==item['asset_id'] for e in instances),component_source=str((D/'components'/key/(key+'.blend')).relative_to(R)),triangle_budget=10000)
 item['geometry_fingerprint']=hashlib.sha256(b''.join(repr(tuple(v.co)).encode() for o in col.objects if o.type=='MESH' for v in o.data.vertices)).hexdigest();entries.append(item)
for key,item in cat.items():
 if key not in used:
  col=bpy.data.collections.get(item['collection'])
  if col:bpy.data.collections.remove(col)
for im in bpy.data.images:
 if im.source=='FILE':im.filepath=bpy.path.relpath(str(PAL),start=str(D))
P['components']=[spec[e['key']] for e in entries];(D/'component_plan.json').write_text(json.dumps(P,ensure_ascii=False,indent=2)+'\n');(D/'catalog.json').write_text(json.dumps({'components':entries},ensure_ascii=False,indent=2)+'\n');(D/'component_instances.json').write_text(json.dumps({'coordinate_contract':{'plane':'XY','up':'+Z','godot':'(x,y,z) -> (x,z,-y)'},'instances':instances},ensure_ascii=False,indent=2)+'\n')
S['revision']='v005';S.render.resolution_x=1100;S.render.resolution_y=1100;S.cycles.samples=32;S.camera.data.ortho_scale=24
bpy.ops.wm.save_as_mainfile(filepath=str(D/'sunny_bloom_retreat.blend'),compress=True)
(W/'previews').mkdir(exist_ok=True);S.render.filepath=str(W/'previews/beauty.png');bpy.ops.render.render(write_still=True);print('BUILT',len(entries),len(instances),flush=True)
