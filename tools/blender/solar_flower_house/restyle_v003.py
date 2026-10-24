"""Restyle the saved v001 source into v003, without rebuilding locked architecture.
Blender --background --factory-startup --python-exit-code 1 --python this_file -- --render
"""
import bpy,math,json,hashlib,os,sys,random
from pathlib import Path
from mathutils import Vector,Matrix
R=Path(__file__).resolve().parents[3];BASE=R/'art_source/scenes/solar_flower_house/v001';D=BASE.parent/'v003'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'solar_flower_house_v003'
if R==W or R in W.parents:raise RuntimeError('Output must be outside repo')
(W/'previews').mkdir(parents=True,exist_ok=True)
plan=json.loads((D/'component_plan.json').read_text());assert plan['status']=='frozen_before_geometry'
OUT=D/'solar_flower_house.blend'
if OUT.exists() and '--replace-generated' not in sys.argv:raise RuntimeError('Existing v003; explicit --replace-generated required')
base_hash=hashlib.sha256((BASE/'solar_flower_house.blend').read_bytes()).hexdigest();assert base_hash==plan['base_source_sha256']
bpy.ops.wm.open_mainfile(filepath=str(BASE/'solar_flower_house.blend'))
scene=bpy.data.scenes['太阳能花屋_参考装配'];bpy.context.window.scene=scene
lib=bpy.data.scenes['组件母版_建筑与花草'];mb=bpy.data.collections['建筑_母版'];mf=bpy.data.collections['花草_母版']
building=bpy.data.collections['建筑_实例'];flora=bpy.data.collections['花草_实例'];support=bpy.data.collections['90_展示环境_不导出']
palette_path=R/'art_source/shared/palettes/sea_cozy_8x8_512.png';palette_hash=hashlib.sha256(palette_path.read_bytes()).hexdigest()
cells={x['name']:x for x in json.loads(palette_path.with_suffix('.json').read_text())['cells']}
materials={r:bpy.data.materials['SEA_'+r] for r in ['Matte','Metal','Gloss','Emission']}
img=next(n.image for n in materials['Matte'].node_tree.nodes if n.type=='TEX_IMAGE')
old_catalog=json.loads((BASE/'component_catalog.json').read_text())['components'];components={};records=[];current=None
for c in old_catalog:
 col=bpy.data.collections[c['collection']];components[c['slug']]={'collection':col,'anchor':Vector(c['source_anchor_shift_m']),'bounds':c['bounds_size_m'],'meshes':[o for o in col.objects if o.type=='MESH']}
# Capture geometry and exact world transforms before touching any color or plant.
def fingerprint(c):
 g=[{'vertices':[[round(float(v),5) for v in p.co] for p in o.data.vertices],'polygons':[list(p.vertices) for p in o.data.polygons]} for o in c['meshes']]
 return hashlib.sha256(json.dumps(g,sort_keys=True).encode()).hexdigest()
locked={c['slug']:fingerprint(components[c['slug']]) for c in old_catalog if c['slug'] not in plan['style_scope']['editable_geometry']}
placements={o.name: {'component_id':o['component_id'],'matrix':[list(row) for row in o.matrix_world]} for o in scene.objects if o.instance_type=='COLLECTION'}
design_anchors={}
for o in scene.objects:
 if o.instance_type!='COLLECTION':continue
 c=next(c for c in old_catalog if c['component_id']==o['component_id']);a=Vector(c['source_anchor_shift_m']);design_anchors[o.name]=o.location-o.rotation_euler.to_matrix()@Vector(tuple(a[i]*o.scale[i] for i in range(3)))
# PaletteUV-only recolor of v001 geometry; shared PNG stays untouched.
remap={'cream':'mint_white','plaster':'mint_white','sand':'plaster','wood_light':'wood_mid','wood':'wood_mid','wood_mid':'wood_dark','wood_dark':'bark','wood_edge':'wood_light','aqua':'seafoam','teal':'ocean','deepblue':'ocean','yellow':'butter','gold':'yellow','coral':'red','leaf_light':'spring','lime':'moss_light','leaf_yellow':'moss','leaf':'fern','leaf_mid':'leaf_dark','forest':'jade','pink':'pink_light','rose':'pink','magenta':'rose'}
by_cell={(c['column'],7-c['row']):name for name,c in cells.items()}
for c in components.values():
 for o in c['meshes']:
  uv=o.data.uv_layers['PaletteUV']
  for p in o.data.polygons:
   u=uv.data[p.loop_indices[0]].uv;name=by_cell[(int(u.x*8),int(u.y*8))]
   if name not in remap:continue
   src=cells[name];dst=cells[remap[name]];dx=(dst['column']-src['column'])/8;dy=(src['row']-dst['row'])/8
   for li in p.loop_indices:uv.data[li].uv.x+=dx;uv.data[li].uv.y+=dy
# Matte, softly lit game colors instead of shiny gold/plastic highlights.
for role,m in materials.items():
 p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
 p.inputs['Roughness'].default_value={'Matte':.94,'Metal':.65,'Gloss':.68,'Emission':.8}[role]
 p.inputs['Metallic'].default_value=.12 if role=='Metal' else 0
 p.inputs['Specular IOR Level'].default_value=.12;p.inputs['Coat Weight'].default_value=0
 if role=='Emission':p.inputs['Emission Strength'].default_value=.3

def activate(o):
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o

def finish(o,name,color='cream',role='Matte',bevel=0,smooth=True):
 o.name=name
 for c in list(o.users_collection):c.objects.unlink(o)
 current.objects.link(o)
 # The working collection is temporarily linked to the active scene.
 activate(o)
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  mod=o.modifiers.new('柔和倒角_三段','BEVEL');mod.width=bevel;mod.segments=3
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

def box(n,loc,size,col='cream',bev=.04,role='Matte',rot=None):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.scale=size
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role,bev)
def uvball(n,loc,scale,col='leaf',role='Matte',rot=None):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=10,location=loc);o=bpy.context.object;o.scale=scale
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role)
def cyl(n,loc,radius,depth,col='wood',role='Matte',rot=None,vertices=32,r2=None):
 bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=radius,radius2=radius if r2 is None else r2,depth=depth,location=loc)
 o=bpy.context.object
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role,min(.025,radius*.13))
def torus(n,loc,major,minor,col='wood',rot=None,role='Matte'):
 bpy.ops.mesh.primitive_torus_add(major_segments=48,minor_segments=12,location=loc,major_radius=major,minor_radius=minor)
 o=bpy.context.object
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role)
def line(n,pts,r=.025,col='wood',role='Matte'):
 curve=bpy.data.curves.new(n,'CURVE');curve.dimensions='3D';curve.resolution_u=16;curve.bevel_depth=r;curve.bevel_resolution=3
 sp=curve.splines.new('BEZIER');sp.bezier_points.add(len(pts)-1)
 for p,co in zip(sp.bezier_points,pts):p.co=co;p.handle_left_type='AUTO';p.handle_right_type='AUTO'
 o=bpy.data.objects.new(n,curve);scene.collection.objects.link(o);activate(o);bpy.ops.object.convert(target='MESH');return finish(bpy.context.object,n,col,role)
def mesh(n,verts,faces,col,bev=0):
 me=bpy.data.meshes.new(n);me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(n,me);scene.collection.objects.link(o);return finish(o,n,col,bevel=bev)
def leaf(n,base,tip,width,col):
 base=Vector(base);tip=Vector(tip);d=tip-base;side=d.cross(Vector((0,0,1))).normalized()
 if side.length<.1:side=Vector((1,0,0))
 v=[]
 for i in range(9):
  t=i/8;c=base+d*t+Vector((0,0,math.sin(t*math.pi)*d.length*.16));w=max(.006,math.sin(math.pi*t)**.85*width)
  v.extend([tuple(c-side*w),tuple(c+Vector((0,0,w*.22))),tuple(c+side*w)])
 faces=[]
 for i in range(8):
  for j in range(2):a=i*3+j;faces.append((a,a+3,a+4,a+1))
 o=mesh(n,v,faces,col);activate(o)
 mod=o.modifiers.new('叶片厚度','SOLIDIFY');mod.thickness=.012;bpy.ops.object.modifier_apply(modifier=mod.name)
 # Remap UV after solidify so rim faces also have nonzero islands.
 return finish(o,n,col)
def start(slug):
 global current
 current=components[slug]['collection']
 for o in list(current.objects):
  data=o.data if o.type=='MESH' else None
  bpy.data.objects.remove(o,do_unlink=True)
  if data is not None and data.users==0:bpy.data.meshes.remove(data)
 scene.collection.children.link(current)
 return current

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

def inst(slug,loc=(0,0,0),rot=(0,0,0),scale=1):
 c=components[slug];o=bpy.data.objects.new(slug+'_instance',None);o.instance_type='COLLECTION';o.instance_collection=c['collection']
 (flora if c['collection']['category']=='flora' else building).objects.link(o)
 o.rotation_euler=rot;o.scale=(scale,)*3;o.location=Vector(loc)+o.rotation_euler.to_matrix()@(c['anchor']*scale)
 item=next(x for x in plan['components'] if x['slug']==slug)
 o['component_id']=item['component_id']
 records.append({'component_id':item['component_id'],'instance_id':o.name,'position_m':list(o.location),'rotation_euler_xyz_rad':list(o.rotation_euler),'scale':list(o.scale),'source_object':o.name})
 return o
pi=math.pi
random.seed(309)
def oval_leaf(n,base,tip,width,col):
 base=Vector(base);tip=Vector(tip);mid=(base+tip)*.5;length=(tip-base).length
 rot=(tip-base).to_track_quat('Y','Z').to_euler()
 # Rounded oval silhouette with a little thickness, no narrow jagged strips.
 return uvball(n,mid,(width,length*.53,width*.24),col,rot=rot)
start('leaf_cluster')
for i in range(5):
 a=i*2*pi/5;oval_leaf('宽圆叶',(0,0,.02),(.55*math.cos(a),.55*math.sin(a),.38+(i%2)*.18),.17,['fern','moss','moss_light','leaf_dark','spring'][i])
end('leaf_cluster')
start('vine')
for j in range(2):
 x=(j-.5)*.17;length=1.35+j*.2
 line('简约藤茎',[(x,0,.05),(x+.04,0,-length)],.012,'fern')
 for i in range(6):
  z=-length*i/6;side=(-1)**i;oval_leaf('圆形藤叶',(x,0,z),(x+side*.23,-.03,z-.18),.115,'moss' if i%2 else 'fern')
end('vine')
for slug,colors in [('daisy',['cream','cream']),('cosmos',['pink_light','pink']),('goldflower',['cream','butter'])]:
 start(slug)
 for k in range(2):
  x=-.19 if k==0 else .19;y=-.09 if k==0 else .13;z=.53 if k==0 else .73
  line('直立花茎',[(x*.6,y*.6,.02),(x,y,z)],.018,'fern')
  for side,c in [(-1,'moss_light'),(1,'fern')]:
   oval_leaf('花朵宽圆对叶',(x,y,.18),(x+side*.30,y-.06,.40+(side+1)*.025),.14,c)
  for j in range(5):
   a=2*pi*j/5+.22
   uvball('圆润五瓣花瓣',(x+.125*math.cos(a),y+.125*math.sin(a),z),(.146,.125,.050),colors[k],rot=(0,0,a))
  uvball('圆形黄色花心',(x,y,z+.05),(.075,.075,.035),'yellow')
 end(slug)
# Keep each v001 instance's design anchor. Adjust only normalized root offset for new flora bounds.
for o in list(scene.objects):
 if o.instance_type!='COLLECTION':continue
 item=next(c for c in old_catalog if c['component_id']==o['component_id']);c=components[item['slug']]
 if item['slug'] in plan['style_scope']['editable_geometry']:
  o.location=design_anchors[o.name]+o.rotation_euler.to_matrix()@Vector(tuple(c['anchor'][i]*o.scale[i] for i in range(3)))
 records.append({'component_id':o['component_id'],'instance_id':o.name,'position_m':list(o.location),'rotation_euler_xyz_rad':list(o.rotation_euler),'scale':list(o.scale),'source_object':o.name})
# Preserve reference v001 framing, use neutral fill and reduce photographic specular contrast.
for o in support.objects:
 if o.type=='LIGHT':
  o.data.energy*=.52;o.data.color=(1,.98,.94) if '暖阳' in o.name else (.91,.98,1);o.data.size*=1.25
world=scene.world
for n in world.node_tree.nodes:
 if n.type=='BACKGROUND':
  if n.name=='Background':n.inputs[0].default_value=(.82,.94,.93,1);n.inputs[1].default_value=.65
  else:n.inputs[0].default_value=(.006,.22,.34,1);n.inputs[1].default_value=1.15
scene.view_settings.exposure=-.55;scene.cycles.samples=48
route=json.loads((R/'assets/registry/ledger_index.json').read_text())['domains']['scenes']['ledger'];catalog=[]
for old in old_catalog:
 slug=old['slug'];c=components[slug];dest=D/'component_packages'/slug;dest.mkdir(parents=True,exist_ok=True)
 e={**old,'component_blend':str((dest/(slug+'.blend')).relative_to(R)),'version':'v003','bounds_size_m':c['bounds'],'source_anchor_shift_m':list(c['anchor']),'geometry_fingerprint':fingerprint(c),'source_sha256':None,'source_package_meshes':[o.name for o in c['meshes']],'style_base_version':'v001','instance_count':sum(x['component_id']==old['component_id'] for x in records)}
 (dest/'asset_manifest.json').write_text(json.dumps(e,ensure_ascii=False,indent=2)+'\n');catalog.append(e)
# Scope lock: all 30 architecture components and palm have unchanged topology/vertex positions.
locked_errors=[s for s,h in locked.items() if fingerprint(components[s])!=h]
placement_errors=[]
for o in scene.objects:
 if o.name not in placements:continue
 slug=next(c['slug'] for c in old_catalog if c['component_id']==o['component_id'])
 if slug not in plan['style_scope']['editable_geometry'] and [list(row) for row in o.matrix_world]!=placements[o.name]['matrix']:placement_errors.append(o.name)
assert not locked_errors and not placement_errors
assert len(records)==255 and len(catalog)==36
assert hashlib.sha256((BASE/'solar_flower_house.blend').read_bytes()).hexdigest()==base_hash
assert hashlib.sha256(palette_path.read_bytes()).hexdigest()==palette_hash
lock={'base_version':'v001','base_sha256':base_hash,'palette_sha256':palette_hash,'locked_geometry_count':len(locked),'locked_fingerprints':locked,'locked_geometry_errors':locked_errors,'locked_placement_errors':placement_errors,'passed':True,'editable_geometry':plan['style_scope']['editable_geometry']}
(D/'scope_lock.json').write_text(json.dumps(lock,ensure_ascii=False,indent=2)+'\n')
(D/'component_catalog.json').write_text(json.dumps({'schema':'sea.scene.component_catalog','components':catalog},ensure_ascii=False,indent=2)+'\n')
previous=json.loads((BASE/'component_instances.json').read_text());previous['instances']=records
(D/'component_instances.json').write_text(json.dumps(previous,ensure_ascii=False,indent=2)+'\n')
(D/'component_tree.txt').write_text('\n'.join(x['category']+' / '+x['slug']+' / '+str(x['instance_count'])+' instances' for x in catalog)+'\n')
(D/'style_mapping.json').write_text(json.dumps({'base_version':'v001','palette_uv_remap':remap,'reference':'style_reference.png','geometry_scope':plan['style_scope'],'material_finish':'matte_neutral_fill'},ensure_ascii=False,indent=2)+'\n')
img.filepath=bpy.path.relpath(str(palette_path),start=str(D));scene['source_stage']='style_iteration_runtime_pending';scene['base_version']='v001';scene['reference_sha256']=plan['reference_sha256']
bpy.ops.wm.save_as_mainfile(filepath=str(OUT),compress=True);print('SEA_V003_RESTYLE_BUILT',len(catalog),len(records),'LOCKED',len(locked),flush=True)
if '--render' in sys.argv:scene.render.filepath=str(W/'previews/solar_flower_house_beauty.png');bpy.ops.render.render(write_still=True)
print('SEA_BUILD_COMPLETE',flush=True)
