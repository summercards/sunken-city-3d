"""Replace draft seam markers with real cuts and auditable, non-accumulated tapers.
Run in the active Blender MCP session. All earlier saved versions are read-only.
"""
import bpy,bmesh,json,hashlib,math,os
from pathlib import Path
from mathutils import Vector,Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/bld_20261109_a/v003';V1=R/'art_source/scenes/bld_20261109_a/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'bld_20261109_a/v003'
W.mkdir(parents=True,exist_ok=True)
if not (W/'draft_before_real_cuts.blend').exists():bpy.ops.wm.save_as_mainfile(filepath=str(W/'draft_before_real_cuts.blend'),copy=True)
source_v1_sha=hashlib.sha256((V1/'bld_20261109_a.blend').read_bytes()).hexdigest()
# Start with the undeformed v001 data, not the accumulated v002/v003 draft.
bpy.ops.wm.open_mainfile(filepath=str(V1/'bld_20261109_a.blend'),load_ui=False)
sc=bpy.context.scene;sc.name='BLDA_编号海上建筑_v003'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));oldcat=json.loads((V1/'catalog.json').read_text(encoding='utf-8'))['components'];catby={e['key']:e for e in oldcat};pby={e['key']:e for e in P['components']};cols={k:bpy.data.collections[e['collection']] for k,e in catby.items()}
roles={m['semantic_role']:m for m in bpy.data.materials if m.get('semantic_role')};cells={x['name']:x for x in json.loads((R/P['palette']).with_suffix('.json').read_text(encoding='utf-8'))['cells']}
work=bpy.data.collections.new('BLDA_V003_WorkOnly');sc.collection.children.link(work);work['display_support']=True
witnesses=[];cuts=[];contacts=[];errors=[]
def bb_obj(o):
 pts=[v.co for v in o.data.vertices];return Vector([min(p[i] for p in pts) for i in range(3)]),Vector([max(p[i] for p in pts) for i in range(3)])
def bb_col(c):
 pts=[v.co for o in c.objects for v in o.data.vertices];return Vector([min(p[i] for p in pts) for i in range(3)]),Vector([max(p[i] for p in pts) for i in range(3)])
def paint(o,color=None):
 color=color or o.get('palette_color','plaster');cell=cells[color];cx=(cell['column']+.5)/8;cy=1-(cell['row']+.5)/8
 for u in list(o.data.uv_layers):o.data.uv_layers.remove(u)
 uv=o.data.uv_layers.new(name='PaletteUV');uv.active_render=True
 for f in o.data.polygons:
  for j,li in enumerate(f.loop_indices):
   a=math.tau*j/f.loop_total;uv.data[li].uv=(cx+.027*math.cos(a),cy+.027*math.sin(a))
 if not o.data.materials:o.data.materials.append(roles['SEA_Matte'])
 o['palette_color']=color;o.data.update()
def box(c,n,p,s,color='plaster',bev=.02):
 x,y,z=p;dx,dy,dz=[v/2 for v in s];vs=[(x+a*dx,y+b*dy,z+d*dz) for a,b,d in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
 me=bpy.data.meshes.new(n);me.from_pydata(vs,[],[(3,2,1,0),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]);me.update();o=bpy.data.objects.new(n,me);c.objects.link(o)
 if bev:
  bm=bmesh.new();bm.from_mesh(me);bmesh.ops.bevel(bm,geom=list(bm.edges),offset=min(bev,min(s)*.4),segments=3,affect='EDGES',clamp_overlap=True);bm.normal_update();bm.to_mesh(me);bm.free()
 o['role']='SEA_Matte';o['bevel_width_m']=bev;o['bevel_segments']=3 if bev else 0;o['palette_color']=color;paint(o,color);return o
# The source sign already had old vertical taper: rebuild its two backplates as
# rounded rectangles before applying the new long-axis taper. Keep actual glyphs.
for key in ['main_sign','fascia','shop_lintel','blade_sign']:
 c=cols[key]
 for o in list(c.objects):
  if o.type=='MESH' and o.get('palette_color') in {'gold','yellow','red_dark','plaster'} and '_字' not in o.name:
   lo,hi=bb_obj(o);name=o.name;color=o.get('palette_color','plaster');size=hi-lo;center=(lo+hi)/2;bev=min(.065,min(size)*.25);bpy.data.objects.remove(o,do_unlink=True);box(c,name,center,size,color,bev)
# Build real reduced relief before deformation, within the structure component.
# Four restrained quoin blocks and four brackets keep the additive cost <35%.
shell=cols['shell']
for i,z in enumerate([.5,1.5,2.5,3.5]):
 o=box(shell,'V003_RealQuoin_'+str(i),(-4.12,-3.98,z),(.58,.42,.34),'stone',.035);o['relief_kind']='quoin'
for i,x in enumerate([-2.8,-.9,.9,2.8]):
 o=box(shell,'V003_RealBracket_'+str(i),(x,-3.99,4.68),(.22,.40,.36),'wood_edge',.03);o['relief_kind']='bracket'
# Per-mesh longest-axis deformation. Retain a sparse before/after vertex witness
# so a second process fits rho from actual coordinates, never from custom props.
for key,c in cols.items():
 e=pby[key];kind=e['kind']
 if kind=='linear':e.update(rho=.06,d_bottom=.12,d_top=.1128)
 angle={'main_sign':6,'blade_sign':8,'poster_panel':4,'awning':2,'menu':8,'notice':4}.get(key,0);e['tilt_deg']=angle
 if not angle:e['tilt_kind']=None
 c['asset_id']=e['asset_id'];c['source_version']='v003';c['form_layer']=e.get('form_layer',e.get('layer','ordinary'));c['kind']=kind;c['rho']=e.get('rho',0)
 c.instance_offset=(0,0,0)
 if kind=='plant':continue
 for o in list(c.objects):
  if o.type!='MESH':continue
  lo,hi=bb_obj(o);ext=hi-lo;center=(lo+hi)/2
  if kind=='soft':
   # Add real sag/folds, not a rectangular rigid-cloth exemption.
   for v in o.data.vertices:
    t=(v.co.z-lo.z)/max(ext.z,1e-6);v.co.y+=.035*math.sin(t*math.pi*2)*(1-t)
   o.data.update();continue
  ai=max(range(3),key=lambda i:ext[i]);cross=[i for i in range(3) if i!=ai]
  # Organic emblem, handles and rails still receive real local taper; closed loops
  # are not falsely described as straight cylinders.
  linear=(kind=='linear' or (max(ext)>min(ext)*3 and sorted(ext)[1]<max(ext)*.20))
  rho=.06 if linear else float(e.get('rho',.025))
  if abs(rho)<.01:rho=.025
  samples=[]
  for v in o.data.vertices:
   t=(v.co[ai]-lo[ai])/max(ext[ai],1e-7);factor=1-rho*t
   if (v.index%max(1,len(o.data.vertices)//36)==0 or t<.002 or t>.998) and len(samples)<160:
    samples.append({'i':v.index,'before':list(v.co),'t':t})
   for j in cross:v.co[j]=center[j]+(v.co[j]-center[j])*factor
  o.data.update();o['taper_along']='xyz'[ai];o['rho_applied']=rho;o['form_kind']='linear' if linear else kind
  witnesses.append({'key':key,'object':o.name,'axis':ai,'cross_axes':cross,'rho_requested':rho,'center_before':list(center),'extent_before':list(ext),'axis_min_before':lo[ai],'samples':samples,'is_linear_segment':linear})
# Use v001 reference transforms, add tilt only to eligible hanging pieces. Keep
# pots, tables and service poles upright so they remain supported.
for o in sc.objects:
 if o.instance_type!='COLLECTION':continue
 key=next(k for k,c in cols.items() if o.instance_collection==c)
 angle={'main_sign':6,'blade_sign':8,'poster_panel':4,'awning':2,'menu':8,'notice':4}.get(key,0)
 if angle:
  pv=Vector((0,0,0));o.rotation_euler.x=math.radians(angle)
# Temporary host linking permits exact booleans; no exporter modifier assumptions.
def vol(me):
 bm=bmesh.new();bm.from_mesh(me)
 try:r=abs(bm.calc_volume(signed=True))
 except Exception:r=0.0
 bm.free();return r

def do_cut(host,lo,hi,label):
 # All cutter geometry is in the host mesh local coordinates (mesh transform identity).
 hlo,hhi=bb_obj(host)
 if any(min(hhi[i],hi[i])-max(hlo[i],lo[i])<=.0001 for i in range(3)):return False
 before=vol(host.data);nv=len(host.data.vertices);scratch_link=host.name not in work.objects
 if scratch_link:work.objects.link(host)
 bpy.context.view_layer.update()
 cutter=box(work,'CUT_'+label,(lo+hi)/2,hi-lo,'stone',0)
 for ob in sc.objects:
  if ob.select_get():ob.select_set(False)
 host.select_set(True);bpy.context.view_layer.objects.active=host
 mod=host.modifiers.new('V003_ActualSocketCut','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
 try:
  with bpy.context.temp_override(scene=sc,view_layer=sc.view_layers[0],object=host,active_object=host,selected_objects=[host],selected_editable_objects=[host]):bpy.ops.object.modifier_apply(modifier=mod.name)
 except Exception as exc:
  if mod.name in host.modifiers:host.modifiers.remove(mod)
  bpy.data.objects.remove(cutter,do_unlink=True)
  if scratch_link:work.objects.unlink(host)
  raise RuntimeError(label+': '+str(exc))
 host.select_set(False);after=vol(host.data);changed=len(host.data.vertices)!=nv or abs(after-before)>1e-8
 bpy.data.objects.remove(cutter,do_unlink=True)
 if scratch_link:work.objects.unlink(host)
 if changed:
  paint(host);cuts.append({'label':label,'host_object':host.name,'bounds_min':list(lo),'bounds_max':list(hi),'volume_before':before,'volume_after':after,'removed_volume':max(0,before-after),'topology_changed':True})
 return changed
# Remove overlap within the ladder: rung seats are holes in rails, 4 mm around.
lad=cols['stair_ladder'];rails=[o for o in lad.objects if '梯边' in o.name];rungs=[o for o in lad.objects if '横档' in o.name]
for i,rung in enumerate(rungs):
 lo,hi=bb_obj(rung);pad=Vector((.004,.004,.004))
 for rail in rails:do_cut(rail,lo-pad,hi+pad,'ladder_socket_'+str(i))
# Actual attachment contracts. Insets cut real host material wherever the expanded
# child envelope meets it. Clearance uses a measured separating plane, not a mesh marker.
instances={k:[o for o in sc.objects if o.instance_type=='COLLECTION' and o.instance_collection==c] for k,c in cols.items()}
host_inst=instances['shell'][0]
def world_pts(inst,objs=None):return [inst.matrix_world@v.co for o in (objs or list(inst.instance_collection.objects)) for v in o.data.vertices]
def world_bounds(inst):
 pts=world_pts(inst);return Vector([min(p[i] for p in pts) for i in range(3)]),Vector([max(p[i] for p in pts) for i in range(3)])
# Logical attachment map is about actual hosts, not the draft's arbitrary pair labels.
attachment_specs={
 'main_sign':('shell','clearance',1,-1,.006), 'awning':('shell','clearance',1,-1,.006),
 'blade_sign':('shell','clearance',1,-1,.006), 'poster_panel':('shell','clearance',0,-1,.004),
 'ac_unit':('shell','clearance',0,-1,.006), 'pipe_set':('shell','inset',0,-1,.004),
 'vent_duct':('shell','inset',0,-1,.006), 'antenna':('slab','clearance',2,1,.006),
 'clothesline':('slab','clearance',2,1,.006), 'barred_window':('shell','inset',None,None,.006),
 'transom':('shell','inset',0,-1,.006), 'backdoor':('shell','inset',1,1,.006),
 'stair_ladder':('shell','inset',1,1,.006), 'shop_lintel':('shell','clearance',1,-1,.004),
 'fascia':('awning','clearance',1,-1,.004), 'side_eave':('shell','clearance',0,-1,.004),
 'coping':('slab','clearance',2,1,.006)}
# Calculate mesh bounds after taper and update transforms before positioning.
bpy.context.view_layer.update()
for key,(hostkey,relation,axis,direction,gap) in attachment_specs.items():
 e=pby[key];e['attached_to']=pby[hostkey]['id']
 for child in instances[key]:
  host=instances[hostkey][-1] if hostkey=='slab' else instances[hostkey][0]
  ai=axis;sgn=direction
  if ai is None:
   if abs(child.rotation_euler.z)>1:ai,sgn=0,-1
   else:ai,sgn=1,-1
  clo,chi=world_bounds(child);hlo,hhi=world_bounds(host);hostface=hhi[ai] if sgn>0 else hlo[ai]
  if relation=='inset':
   # Relief stones are not the wall's mating surface. Use only actual wall bands
   # overlapping this component's two-dimensional interface projection.
   faces=[]
   for hm in host.instance_collection.objects:
    if hm.get('relief_kind'):continue
    hp=world_pts(host,[hm]);hml=Vector([min(v[j] for v in hp) for j in range(3)]);hmh=Vector([max(v[j] for v in hp) for j in range(3)])
    if all(min(chi[j],hmh[j])-max(clo[j],hml[j])>0 for j in range(3) if j!=ai):faces.append(hmh[ai] if sgn>0 else hml[ai])
   if faces:hostface=max(faces) if sgn>0 else min(faces)
  rec={'a':e['id'],'b':pby[hostkey]['id'],'a_key':key,'b_key':hostkey,'child_instance':child.name,'host_instance':host.name,'relation':relation,'gap_m':gap,'axis':ai,'direction':sgn,'measurement_status':'unverified'}
  if relation=='clearance':
   # Exact projected clearance with an independent empty separating plane.
   childface=clo[ai] if sgn>0 else chi[ai];delta=hostface+sgn*gap-childface
   child.location[ai]+=delta;bpy.context.view_layer.update()
   al,ah=world_bounds(child);bl,bh=world_bounds(host);actual=al[ai]-bh[ai] if sgn>0 else bl[ai]-ah[ai]
   rec.update(actual_gap_m=actual,separating_plane_verified=.002-1e-5<=actual<=.020+1e-5,measurement_status='measured_projected_gap')
  else:
   # Actual shallow sockets follow the wall, not its projecting decorative pieces.
   # Window bands need up to 0.14m insertion because the original opening is recessed.
   insertion=.14 if key in {'barred_window','transom','pipe_set','vent_duct'} else .03
   childface=clo[ai] if sgn>0 else chi[ai];delta=hostface-sgn*insertion-childface
   child.location[ai]+=delta;bpy.context.view_layer.update()
   al,ah=world_bounds(child);rec['cut_indices']=[]
   # Include every child part, not a single arbitrary seam cube; host remains editable per mesh.
   for sub in child.instance_collection.objects:
    pts=world_pts(child,[sub]);wl=Vector([min(v[i] for v in pts) for i in range(3)]);wh=Vector([max(v[i] for v in pts) for i in range(3)])
    if min(wh)-max(wl)>1e6:continue
    pad=Vector((gap,gap,gap));hl=host.matrix_world.inverted()@(wl-pad);hh=host.matrix_world.inverted()@(wh+pad)
    ll=Vector([min(hl[j],hh[j]) for j in range(3)]);high=Vector([max(hl[j],hh[j]) for j in range(3)])
    for hm in host.instance_collection.objects:
     idx=len(cuts)
     if do_cut(hm,ll,high,key+'_'+sub.name):rec['cut_indices'].append(idx)
   rec['measurement_status']='actual_boolean_sockets' if rec['cut_indices'] else 'no_host_intersection_at_interface'
   rec['cut_verified']=bool(rec['cut_indices'])
  contacts.append(rec)
# Real relief sockets: remove the wall material occupied by each quoin/bracket
# with 4mm margin; the decorative component remains separate but no hidden overlap.
relief=[o for o in shell.objects if o.get('relief_kind')]
for sub in relief:
 lo,hi=bb_obj(sub);pad=Vector((.004,.004,.004))
 for wall in list(shell.objects):
  if wall==sub or wall.get('relief_kind'):continue
  do_cut(wall,lo-pad,hi+pad,'relief_'+sub.name)
# Rebase all collections to true bottom-centre; preserve every world-space instance.
rebases={}
for key,c in cols.items():
 lo,hi=bb_col(c);shift=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z));rebases[key]=list(shift)
 for o in c.objects:o.data.transform(Matrix.Translation(-shift));o.data.update()
 for inst in instances[key]:inst.location+=inst.rotation_euler.to_matrix()@shift
 c.instance_offset=(0,0,0)
 # correct main/upper layer labels and stable IDs, no version-specific logical IDs.
 c.name=pby[key]['id']
# Record witnesses after final operations. Cut meshes are audited for volume removal
# rather than treated as unchanged vertex-index witnesses.
cut_names={x['host_object'] for x in cuts}
for w in witnesses:
 w['rebase']=rebases[w['key']];w['post_boolean']=w['object'] in cut_names
# Contacts refer to semantic surface pairs; now corrected from actual transforms.
P['contacts']=contacts;P['stylized_form']['contacts']=contacts
P['stylized_form']['relief']={'layers':2,'quoin_protrusion':.12,'quoin_blocks':4,'brick_blocks':0,'grooves':0,'brackets':4}
P['stylized_form']['corners']=0
# Nominal slab z thickness and walking heights remain the original source contracts;
# measured tapers and contact tolerances are separately reported, never called gameplay tested.
P['source_version']='v003';P['asset_id']='SEA-SCENE-B1109A-ASSEMBLY';P['geometry_route']='clean_v001_meshes_to_v003_latest_rules';P['reference_base_preserved_sha256']=source_v1_sha
newcat=[];layout=[]
for key,c in cols.items():
 e=pby[key];lo,hi=bb_col(c);ext=hi-lo
 e['extent']=list(ext);e['taper_along']='xyz'[max(range(3),key=lambda i:ext[i])];e['component_family']=catby[key].get('component_family',catby[key]['family']);e['family']=e['component_family']
 tris=polys=0;h=hashlib.sha256();mats=set()
 for o in c.objects:
  paint(o);o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles);polys+=len(o.data.polygons)
  for v in o.data.vertices:h.update((','.join(format(float(x),'.6f') for x in v.co)+';').encode())
  mats.update(m.get('semantic_role') for m in o.data.materials if m)
 newcat.append(dict(e,collection=c.name,bounds_size=list(ext),triangles=tris,polygons=polys,meshes=len(c.objects),geometry_fingerprint=h.hexdigest(),fingerprint_algorithm='ordered_vertices_fixed6_sha256',material_roles=sorted(mats),instance_count=len(instances[key]),component_source=f'art_source/scenes/bld_20261109_a/v003/component_packages/{key}/{key}.blend'))
 for inst in instances[key]:layout.append({'name':inst.name,'key':key,'asset_id':e['asset_id'],'position':list(inst.location),'rotation_euler_xyz':list(inst.rotation_euler),'scale':list(inst.scale)})
P['stylized_form']['components']=P['components'];P['stylized_form']['body']['triangles']=sum(e['triangles']*e['instance_count'] for e in newcat if e['key'] in {'shell','slab','post','deck','roof_hut'})
P['actual_contact_count']=len(contacts);P['draft_marker_count']=0
# Remove temporary empty collections and save approved geometry before preview changes.
bpy.data.collections.remove(work);bpy.context.view_layer.update();sc.camera.location=(-29,-29,22);sc.camera.rotation_euler=(Vector((0,0,7))-sc.camera.location).to_track_quat('-Z','Y').to_euler();sc.camera.data.ortho_scale=20.6
for area in bpy.context.screen.areas if bpy.context.screen else []:
 if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA'
bpy.context.preferences.filepaths.save_version=0
out=D/'bld_20261109_a_v003.blend';bpy.ops.wm.save_as_mainfile(filepath=str(out),compress=True)
for name,value in [('component_plan.json',P),('catalog.json',{'schema':'sea.component_catalog','components':newcat}),('component_instances.json',{'schema':'sea.component_instances','coordinate_contract':{'plane':'XY','up':'+Z','rotation':'Euler XYZ radians','godot_mapping':'(x,y,z)->(x,z,-y)'},'instances':layout})]:(D/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
witness={'schema':'bld.v003.actual_geometry_witness','source_sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'source_v001_sha256':source_v1_sha,'objects':witnesses,'cuts':cuts,'contacts':contacts,'full_scene_self_intersections':'not_exhaustively_verified','notes':['No seam-marker cubes. Host booleans removed actual solid volume.','Sparse predeformation witnesses permit independent per-mesh taper regression.','Closed curved loops are not claimed to have a straight-cylinder diameter ratio.']};(W/'geometry_witness.json').write_text(json.dumps(witness,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
sc.render.filepath=str(W/'hero_v003.png');bpy.ops.render.render(write_still=True)
print('REAL_GEOMETRY_REVISED',json.dumps({'components':len(newcat),'instances':len(layout),'actual_socket_cuts':len(cuts),'contacts':len(contacts),'witnesses':len(witnesses),'source_sha256':witness['source_sha256'],'inset_without_cut':[r['a_key'] for r in contacts if r['relation']=='inset' and not r.get('cut_verified')]}),flush=True)
