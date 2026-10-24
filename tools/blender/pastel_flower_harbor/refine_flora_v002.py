"""Revise only flora in the saved source; preserve architecture and scene composition."""
import bpy,math,json,hashlib,os,sys
from pathlib import Path
from mathutils import Vector,Matrix
R=Path(__file__).resolve().parents[3];BASE=R/'art_source/scenes/pastel_flower_harbor/v001';D=BASE.parent/'v002'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'pastel_flower_harbor_v002'
assert R not in W.parents
(W/'previews').mkdir(parents=True,exist_ok=True)
plan=json.loads((D/'component_plan.json').read_text());OUT=D/'pastel_flower_harbor.blend'
if OUT.exists() and '--replace-generated' not in sys.argv:raise RuntimeError('Existing revision; explicit candidate replacement required')
assert hashlib.sha256((BASE/'pastel_flower_harbor.blend').read_bytes()).hexdigest()==plan['base_source_sha256']
bpy.ops.wm.open_mainfile(filepath=str(BASE/'pastel_flower_harbor.blend'))
scene=bpy.data.scenes['太阳能花屋_参考装配'];bpy.context.window.scene=scene
palette_path=R/'art_source/shared/palettes/sea_cozy_8x8_512.png'
palette_hash=hashlib.sha256(palette_path.read_bytes()).hexdigest()
cells={c['name']:c for c in json.loads(palette_path.with_suffix('.json').read_text())['cells']}
materials={role:bpy.data.materials['SEA_'+role] for role in ['Matte','Metal','Gloss','Emission']}
old=json.loads((BASE/'component_catalog.json').read_text())['components'];components={};current=None;pi=math.pi
for item in old:
 col=bpy.data.collections[item['collection']]
 components[item['slug']]={'collection':col,'anchor':Vector(item['source_anchor_shift_m']),'bounds':item['bounds_size_m'],'meshes':[o for o in col.objects if o.type=='MESH']}
def signature(col):
 data=[{'v':[list(v.co) for v in o.data.vertices],'p':[list(p.vertices) for p in o.data.polygons],'uv':[[round(u.uv.x,7),round(u.uv.y,7)] for u in o.data.uv_layers['PaletteUV'].data],'materials':[m.name for m in o.data.materials]} for o in col.objects if o.type=='MESH']
 return hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()
locked={c['slug']:signature(components[c['slug']]['collection']) for c in old if c['category']!='flora'}
placements={o.name:[list(row) for row in o.matrix_world] for o in scene.objects if o.instance_type=='COLLECTION' and o.users_collection[0].name=='建筑_实例'}
anchors={}
for o in scene.objects:
 if o.instance_type!='COLLECTION':continue
 c=next(c for c in old if c['component_id']==o['component_id']);a=components[c['slug']]['anchor']
 anchors[o.name]=o.location-o.rotation_euler.to_matrix()@Vector(tuple(a[i]*o.scale[i] for i in range(3)))
def start(slug):
 global current
 current=components[slug]['collection']
 for o in list(current.objects):
  data=o.data if o.type=='MESH' else None
  bpy.data.objects.remove(o,do_unlink=True)
  if data is not None and not data.users:bpy.data.meshes.remove(data)
 scene.collection.children.link(current)

def activate(o):
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o

def finish(o,name,color='cream',role='Matte',bevel=0,smooth=False):
 o.name=name
 for c in list(o.users_collection):c.objects.unlink(o)
 current.objects.link(o)
 # The working collection is temporarily linked to the active scene.
 activate(o)
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  mod=o.modifiers.new('柔和倒角_三段','BEVEL');mod.width=bevel;mod.segments=2
  bpy.ops.object.modifier_apply(modifier=mod.name)
 for p in o.data.polygons:p.use_smooth=smooth
 if bevel:
  mod=o.modifiers.new('平面加权法线','WEIGHTED_NORMAL');mod.keep_sharp=True;mod.weight=50
  try:bpy.ops.object.modifier_apply(modifier=mod.name)
  except RuntimeError:o.modifiers.remove(mod)
 o.data.transform(o.matrix_world);o.matrix_world=Matrix.Identity(4)
 o.data.materials.clear();o.data.materials.append(materials[role])
 for old_uv in list(o.data.uv_layers):o.data.uv_layers.remove(old_uv)
 uv=o.data.uv_layers.new(name='PaletteUV');uv.active_render=True
 cell=cells[color];cx=(cell['column']+.5)/8;cy=1-(cell['row']+.5)/8
 for p in o.data.polygons:
  count=len(p.loop_indices)
  for k,li in enumerate(p.loop_indices):
   a=2*math.pi*k/count;uv.data[li].uv=(cx+.022*math.cos(a),cy+.022*math.sin(a))
 o['palette_color']=color;o['soft_edge']='beveled_3_segments' if bevel else 'curved_surface'
 return o

def uvball(n,loc,scale,col='leaf',role='Matte',rot=None):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=10,location=loc);o=bpy.context.object;o.scale=scale
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role,smooth=True)

def line(n,pts,r=.025,col='wood',role='Matte'):
 curve=bpy.data.curves.new(n,'CURVE');curve.dimensions='3D';curve.resolution_u=6;curve.bevel_depth=r;curve.bevel_resolution=2
 sp=curve.splines.new('BEZIER');sp.bezier_points.add(len(pts)-1)
 for p,co in zip(sp.bezier_points,pts):p.co=co;p.handle_left_type='AUTO';p.handle_right_type='AUTO'
 o=bpy.data.objects.new(n,curve);scene.collection.objects.link(o);activate(o);bpy.ops.object.convert(target='MESH');return finish(bpy.context.object,n,col,role,smooth=True)

def end(slug):
 global current
 objs=list(current.objects)
 assert objs
 # Normalize each finished package to bottom center; bake every object transform.
 verts=[o.matrix_world@v.co for o in objs for v in o.data.vertices]
 lo=Vector(tuple(min(v[i] for v in verts) for i in range(3)));hi=Vector(tuple(max(v[i] for v in verts) for i in range(3)))
 anchor=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 for o in objs:o.data.transform(Matrix.Translation(-anchor))
 # Consolidate nonemissive surfaces, keep the luminous mesh separate.
 final=[]
 groups={e:[o for o in objs if any(m.name=='SEA_Emission' for m in o.data.materials)==e] for e in [False,True]}
 for emissive,group in groups.items():
  if not group:continue
  bpy.ops.object.select_all(action='DESELECT')
  for o in group:o.select_set(True)
  bpy.context.view_layer.objects.active=group[0];
  if len(group)>1:bpy.ops.object.join()
  o=bpy.context.object
  o.name=slug+('_emissive' if emissive else '_body');o.data.name=o.name+'_mesh';o['soft_edges']='bevel_3_segments_and_smooth_curves';final.append(o)
 root=bpy.data.objects.new('ROOT_'+slug,None);current.objects.link(root)
 for o in final:o.parent=root
 components[slug]={'collection':current,'anchor':anchor,'bounds':list(hi-lo),'meshes':final}
 scene.collection.children.unlink(current)
