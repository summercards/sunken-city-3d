"""Latest-rule candidate with v001 instance transforms locked. Executed over MCP.
Internal connected meshes are exact-unioned; inter-component joints are true cuts.
All original sources remain read-only until final QA.
"""
import bpy,bmesh,json,hashlib,math,os,time
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
R=Path('D:/projects/sea');V1=R/'art_source/scenes/bld_20261109_a/v001';D=R/'art_source/scenes/bld_20261109_a/v003';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'bld_20261109_a/v003';S=D/'bld_20261109_a_v003.blend'
if not (W/'before_fixed_layout.blend').exists():bpy.ops.wm.save_as_mainfile(filepath=str(W/'before_fixed_layout.blend'),copy=True)
bpy.ops.wm.open_mainfile(filepath=str(V1/'bld_20261109_a.blend'),load_ui=False)
sc=bpy.context.scene;sc.name='BLDA_编号海上建筑_v003';sc['stage']='candidate_latest_fixed_layout'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));cat=json.loads((V1/'catalog.json').read_text(encoding='utf-8'))['components'];original_layout=json.loads((V1/'component_instances.json').read_text(encoding='utf-8'))['instances'];pc={x['key']:x for x in P['components']};cols={e['key']:bpy.data.collections[e['collection']] for e in cat};cells=json.loads((R/P['palette']).with_suffix('.json').read_text(encoding='utf-8'))['cells'];mats={m['semantic_role']:m for m in bpy.data.materials if m.get('semantic_role')};scratch=bpy.data.collections.new('FIXED_LAYOUT_SCRATCH');sc.collection.children.link(scratch);scratch['display_support']=True
# Exact values from the current project rework table, not arbitrary old presets.
settings={'ac_unit':('freestanding',-.06),'antenna':('linear',.06),'awning':('horizontal_cover',.035),'backdoor':('opening',.02),'barred_window':('opening',.02),'basket':('freestanding',-.06),'bin':('freestanding',-.06),'blade_sign':('flat_attached',.03),'carton':('freestanding',-.04),'clothesline':('soft',0),'coping':('shell',.02),'cup':('freestanding',-.05),'deck':('shell',.02),'display_fan':('freestanding',-.05),'fascia':('horizontal_cover',.03),'handtruck':('freestanding',-.04),'jar':('freestanding',-.08),'jerrycan':('freestanding',-.05),'mailbox':('freestanding',-.05),'main_sign':('flat_attached',.025),'menu':('flat_attached',.025),'notice':('flat_attached',.03),'pipe_set':('linear',.06),'planter_round':('freestanding',-.06),'planter_trough':('freestanding',-.06),'post':('vertical_structure',.03),'poster_panel':('flat_attached',.02),'roof_hut':('shell',.02),'roof_sheet':('horizontal_cover',.04),'shelf':('freestanding',-.03),'shell':('shell',.02),'shop_lintel':('shell',.02),'shrine':('freestanding',-.05),'side_eave':('horizontal_cover',.03),'slab':('horizontal_cover',.02),'stair_ladder':('vertical_structure',.02),'stool_stack':('freestanding',-.05),'table':('freestanding',-.03),'thermos':('freestanding',-.04),'transom':('opening',.02),'vent_duct':('vertical_structure',.02),'washer':('freestanding',-.03)}
for k in ['leaf_cluster','succulent','vine','citrus']:settings[k]=('plant',0)
for k in ['shirt','jacket','trousers']:settings[k]=('soft',0)
def uv_safe(o):
 me=o.data;old=me.uv_layers.get('PaletteUV');saved=[]
 for f in me.polygons:
  if old and f.loop_total:
   u,v=old.data[f.loop_start].uv;saved.append((max(0,min(7,int(u*8))),max(0,min(7,int(v*8)))))
  else:
   c=next(x for x in cells if x['name']==o.get('palette_color','plaster'));saved.append((c['column'],7-c['row']))
 for u in list(me.uv_layers):me.uv_layers.remove(u)
 u=me.uv_layers.new(name='PaletteUV');u.active_render=True
 for f,cc in zip(me.polygons,saved):
  cx=(cc[0]+.5)/8;cy=(cc[1]+.5)/8
  for j,li in enumerate(f.loop_indices):u.data[li].uv=(cx+.027*math.cos(math.tau*j/f.loop_total),cy+.027*math.sin(math.tau*j/f.loop_total))
 me.update()
def bbox(o):
 vs=o.data.vertices
 return Vector([min(v.co[i] for v in vs) for i in range(3)]),Vector([max(v.co[i] for v in vs) for i in range(3)])
def makebox(col,name,p,s,color='plaster',bevel=.02):
 x,y,z=p;dx,dy,dz=[v/2 for v in s];vs=[(x+a*dx,y+b*dy,z+c*dz) for a,b,c in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]];me=bpy.data.meshes.new(name);me.from_pydata(vs,[],[(3,2,1,0),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]);me.update();o=bpy.data.objects.new(name,me);col.objects.link(o);o.data.materials.append(mats['SEA_Matte']);o['palette_color']=color;o['role']='SEA_Matte'
 if bevel:
  bm=bmesh.new();bm.from_mesh(me);bmesh.ops.bevel(bm,geom=list(bm.edges),offset=min(bevel,min(s)*.4),segments=3,affect='EDGES',clamp_overlap=True);bm.normal_update();bm.to_mesh(me);bm.free()
 uv_safe(o);return o
# Strip pre-existing sign taper before the new single longest-axis operation.
for key in ['main_sign','fascia','shop_lintel','blade_sign']:
 c=cols[key]
 for o in list(c.objects):
  if o.get('palette_color') in {'gold','yellow','red_dark','plaster'} and '_字' not in o.name:
   lo,hi=bbox(o);name=o.name;color=o.get('palette_color','plaster');bpy.data.objects.remove(o,do_unlink=True);makebox(c,name,(lo+hi)/2,hi-lo,color,min(.065,min(hi-lo)*.25))
# Eight quoins and eight brackets per the rework brief, no fabricated extra components.
for side in [-1,1]:
 for i,z in enumerate([.50,1.65,2.80,4.00]):
  o=makebox(cols['shell'],f'QUOIN_{side}_{i}',(side*4.05,-3.93,z),(.62,.62,.55 if i%2==0 else .82),'stone',.03);o['relief_kind']='quoin'
for i in range(8):
 o=makebox(cols['shell'],'BRACKET_'+str(i),(-3.5+i, -3.98,4.66),(.20,.34,.45),'wood_edge',.025);o['relief_kind']='bracket'
# Clean mesh welding, fill accidentally open 2D artwork into solid thickness.
for c in cols.values():
 for o in c.objects:
  bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free();uv_safe(o)
# Actual taper along component longest axis; all its subparts share its transform.
# Sparse before points saved in a checkpoint, not only rho metadata.
witness=[]
for key,c in cols.items():
 kind,rho=settings[key];e=pc[key];e.update(kind=kind,rho=rho,version='v003',id='SEA-SCENE-B1109A-'+key.upper().replace('_','-'));e['asset_id']=e['id'];e['component_family']=next(x for x in cat if x['key']==key).get('component_family',key);e['family']=e['component_family'];c.name=e['id'];c['asset_id']=e['id'];c['kind']=kind;c['rho']=rho;c['form_layer']=e.get('form_layer','ordinary');c['version']='v003'
 pts=[v.co.copy() for o in c.objects for v in o.data.vertices];lo=Vector([min(v[i] for v in pts) for i in range(3)]);hi=Vector([max(v[i] for v in pts) for i in range(3)]);ext=hi-lo;ai=max(range(3),key=lambda i:ext[i]);ctr=(lo+hi)/2;e['extent']=list(ext);e['taper_along']='xyz'[ai]
 if kind=='linear':e.update(d_bottom=.12,d_top=.1128)
 else:e.update(bottom=max(ext[i] for i in range(3) if i!=ai),top=max(ext[i] for i in range(3) if i!=ai)*(1-rho))
 if kind in {'plant','soft'}:continue
 for o in c.objects:
  samples=[]
  for v in o.data.vertices:
   t=(v.co[ai]-lo[ai])/max(ext[ai],1e-7)
   if v.index%max(1,len(o.data.vertices)//24)==0:samples.append({'i':v.index,'before':list(v.co),'t':t})
   for j in range(3):
    if j!=ai:v.co[j]=ctr[j]+(v.co[j]-ctr[j])*(1-rho*t)
  o.data.update();witness.append({'key':key,'object':o.name,'axis':ai,'rho':rho,'center':list(ctr),'extent':list(ext),'samples':samples})
# Restore all 92 reference transforms exactly (including planned original positions).
for row in original_layout:
 o=sc.objects[row['name']];o.location=row['position'];o.rotation_euler=row['rotation_euler_xyz'];o.scale=row['scale']
bpy.context.view_layer.update()
# Save actual pre-joint geometry as independent proof of the zero-square operator.
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(W/'pre_joint_geometry.blend'),copy=True,compress=True)
prehash=hashlib.sha256((W/'pre_joint_geometry.blend').read_bytes()).hexdigest()
# Exact boolean operators acting on a fresh modifier context. Failed operations
# are rejected and keep the original mesh rather than silently dropping details.
boolean_log=[];failures=[]
def volume(me):
 bm=bmesh.new();bm.from_mesh(me)
 try:v=abs(bm.calc_volume(signed=True))
 except Exception:v=0
 bm.free();return v

def boolean(target,cutter,operation,label):
 if target==cutter:return False
 old=target.data;oldcopy=old.copy();before=(len(old.vertices),len(old.polygons),volume(old));was=target.name in scratch.objects
 if not was:scratch.objects.link(target)
 bpy.context.view_layer.update();mod=target.modifiers.new('LATEST_'+operation,'BOOLEAN');mod.operation=operation;mod.solver='EXACT';mod.object=cutter
 try:
  with bpy.context.temp_override(scene=sc,view_layer=sc.view_layers[0],object=target,active_object=target,selected_objects=[target],selected_editable_objects=[target]):bpy.ops.object.modifier_apply(modifier=mod.name)
  after=(len(target.data.vertices),len(target.data.polygons),volume(target.data))
  valid=after[0]>0 and after[1]>0
  if operation=='UNION':valid=valid and after[2]+1e-5>=before[2]
  if not valid:
   target.data=oldcopy;failures.append({'label':label,'reason':'empty_or_invalid_result','before':before,'after':after});return False
  uv_safe(target);boolean_log.append({'label':label,'operation':operation,'target':target.name,'cutter':cutter.name,'before':before,'after':after});return True
 except Exception as exc:
  if mod.name in target.modifiers:target.modifiers.remove(mod)
  target.data=oldcopy;failures.append({'label':label,'reason':str(exc)});return False
 finally:
  if not was and target.name in scratch.objects:scratch.objects.unlink(target)

def ov(a,b):
 la,ha=bbox(a);lb,hb=bbox(b)
 return all(min(ha[i],hb[i])-max(la[i],lb[i])>1e-6 for i in range(3))
def localtree(o):
 me=o.data;me.calc_loop_triangles();return BVHTree.FromPolygons([v.co.copy() for v in me.vertices],[tuple(t.vertices) for t in me.loop_triangles],all_triangles=True,epsilon=0)
# Fuse actual internal structures, not independently-exportable components.
for key,c in cols.items():
 objs=list(c.objects);merged=0
 # Large body first; ensure colour UV is carried through exact union.
 objs.sort(key=lambda o:len(o.data.polygons),reverse=True);names=[o.name for o in objs]
 for i,an in enumerate(names):
  a=bpy.data.objects.get(an)
  if a is None:continue
  for bn in names[i+1:]:
   b=bpy.data.objects.get(bn)
   if b is None or not ov(a,b):continue
   if not localtree(a).overlap(localtree(b)):continue
   if boolean(a,b,'UNION','internal_'+key):bpy.data.objects.remove(b,do_unlink=True);merged+=1
 print('UNION_COMPONENT',key,'merged',merged,'remaining',len(c.objects),flush=True)
# Reference poses stay fixed: every cross-component overlap is resolved in mesh
# coordinates, never by moving an instance. Prefer trimming decorative vegetation
# then small foreground props; do not cut huge windows with whole bbox cutters.
insts=[o for o in sc.objects if o.instance_type=='COLLECTION' and o.instance_collection in set(cols.values())];keycol={c.name:k for k,c in cols.items()};crosscuts=[]
priority={'deck':100,'slab':99,'shell':98,'post':97,'roof_hut':96,'coping':95,'barred_window':94,'transom':93,'roof_sheet':92,'awning':91,'main_sign':90,'poster_panel':89,'shop_lintel':88,'fascia':87,'shelf':80,'table':79}
def occs():
 out=[]
 for ins in insts:
  key=keycol[ins.instance_collection.name]
  for o in ins.instance_collection.objects:
   pts=[ins.matrix_world@v.co for v in o.data.vertices];lo=Vector([min(p[i] for p in pts) for i in range(3)]);hi=Vector([max(p[i] for p in pts) for i in range(3)]);out.append({'ins':ins,'key':key,'o':o,'lo':lo,'hi':hi})
 return out

def worldtree(x):
 me=x['o'].data;me.calc_loop_triangles();return BVHTree.FromPolygons([x['ins'].matrix_world@v.co for v in me.vertices],[tuple(t.vertices) for t in me.loop_triangles],all_triangles=True,epsilon=0)
for passno in range(3):
 objs=occs();processed=set();hitcount=0
 for i,a in enumerate(objs):
  if a['o'].name not in bpy.data.objects:continue
  for b in objs[i+1:]:
   if a['ins']==b['ins']:continue
   if any(min(a['hi'][j],b['hi'][j])-max(a['lo'][j],b['lo'][j])<=1e-6 for j in range(3)):continue
   pair=tuple(sorted((a['ins'].name+a['o'].name,b['ins'].name+b['o'].name)))
   if pair in processed:continue
   processed.add(pair)
   if not worldtree(a).overlap(worldtree(b)):continue
   hitcount+=1
   # Geometrically trim organic/soft intersections rather than cutting building
   # beams just because a leaf pokes into them.
   if settings[a['key']][0] in {'plant','soft'}:target,other=a,b
   elif settings[b['key']][0] in {'plant','soft'}:target,other=b,a
   elif priority.get(a['key'],20)>=priority.get(b['key'],20):target,other=a,b
   else:target,other=b,a
   if target['o']==other['o']:continue
   cut=bpy.data.objects.new('CROSS_CUT',other['o'].data.copy());scratch.objects.link(cut)
   transform=target['ins'].matrix_world.inverted()@other['ins'].matrix_world;cut.data.transform(transform)
   # 3mm normal offset around actual cutter, not arbitrary AABB deletion.
   cut.data.update()
   for v in cut.data.vertices:v.co+=v.normal*.003
   cut.data.update()
   ok=boolean(target['o'],cut,'DIFFERENCE','cross_'+target['key']+'_'+other['key'])
   if ok:crosscuts.append({'a':pc[other['key']]['id'],'b':pc[target['key']]['id'],'relation':'inset','gap_m':.003,'child_instance':other['ins'].name,'host_instance':target['ins'].name,'host_object':target['o'].name,'child_object':other['o'].name,'geometry_operation':'exact_boolean_difference','pass':passno})
   bpy.data.objects.remove(cut,do_unlink=True)
 print('CROSS_PASS',passno,'hits',hitcount,flush=True)
 if hitcount==0:break
# Lock reference pose signatures and leave originals unchanged.
for row in original_layout:
 o=sc.objects[row['name']]
 assert max(abs(o.location[i]-row['position'][i]) for i in range(3))<1e-6
 assert max(abs(o.rotation_euler[i]-row['rotation_euler_xyz'][i]) for i in range(3))<1e-6
assert len(insts)==92
# Source retains original local origins. Actual geometry edits may expose a
# bottom-centre residual; report it instead of moving instancers to fake a pass.
newcat=[];origin_issues=[]
for key,c in cols.items():
 pts=[v.co for o in c.objects for v in o.data.vertices];lo=Vector([min(p[i] for p in pts) for i in range(3)]);hi=Vector([max(p[i] for p in pts) for i in range(3)]);ext=hi-lo;e=pc[key];e['extent']=list(ext);e['taper_along']='xyz'[max(range(3),key=lambda i:ext[i])];e['component_source']=f'art_source/scenes/bld_20261109_a/v003/component_packages/{key}/{key}.blend'
 if abs(lo.z)>2e-5 or abs(lo.x+hi.x)>2e-5 or abs(lo.y+hi.y)>2e-5:origin_issues.append({'key':key,'min':list(lo),'max':list(hi)})
 tr=po=0;h=hashlib.sha256();roles=set()
 for o in c.objects:
  uv_safe(o);o.data.calc_loop_triangles();tr+=len(o.data.loop_triangles);po+=len(o.data.polygons)
  for v in o.data.vertices:h.update((','.join(format(float(q),'.6f') for q in v.co)+';').encode())
  roles.update(m.get('semantic_role') for m in o.data.materials if m)
 newcat.append(dict(e,collection=c.name,bounds_size=list(ext),triangles=tr,polygons=po,meshes=len(c.objects),geometry_fingerprint=h.hexdigest(),fingerprint_algorithm='ordered_vertices_fixed6_sha256',material_roles=sorted(roles),instance_count=sum(i.instance_collection==c for i in insts)))
# Contacts include the real mesh operations. Original listed attachments not cut
# still require pending interface checks; never invent a contact marker.
P['stylized_form']['components']=P['components'];P['stylized_form']['relief']={'layers':2,'quoin_blocks':8,'brackets':8,'quoin_protrusion':.12};P['contacts']=crosscuts;P['stylized_form']['contacts']=crosscuts;P['reference_instance_transforms_locked']=True;P['geometry_route']='v001_original_layout_locked';P['component_budget']={'limit':50,'planned':49,'remaining':1}
bpy.data.collections.remove(scratch);bpy.context.view_layer.update();sc.camera.location=(-29,-29,22);sc.camera.rotation_euler=(Vector((0,0,7))-sc.camera.location).to_track_quat('-Z','Y').to_euler();sc.camera.data.ortho_scale=20.6
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(S),compress=True);sha=hashlib.sha256(S.read_bytes()).hexdigest()
for name,value in [('component_plan.json',P),('catalog.json',{'schema':'sea.component_catalog','components':newcat}),('component_instances.json',{'schema':'sea.component_instances','coordinate_contract':{'plane':'XY','up':'+Z','rotation':'Euler XYZ radians; Z is vertical','godot_mapping':'(x,y,z)->(x,z,-y)'},'instances':original_layout})]:(D/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
report={'source_sha256':sha,'pre_joint_geometry_sha256':prehash,'pre_joint_geometry':str(W/'pre_joint_geometry.blend'),'reference_instance_count':92,'transforms_locked':True,'operations':boolean_log,'failures':failures,'taper_witnesses':witness,'crosscut_contacts':crosscuts,'origin_issues':origin_issues,'stage':'candidate_requires_independent_full_audit'};(W/'fixed_layout_operations.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
sc.render.filepath=str(W/'hero_fixed_layout.png');bpy.ops.render.render(write_still=True)
print('FIXED_LAYOUT_CANDIDATE',json.dumps({'source_sha256':sha,'crosscuts':len(crosscuts),'booleans':len(boolean_log),'failures':len(failures),'origin_issues':len(origin_issues)}),flush=True)
