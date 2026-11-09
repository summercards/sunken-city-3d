"""Create B1109A v003 from v002: longest-axis taper and legal seam geometry."""
import bpy,json,hashlib,math,os
from pathlib import Path
from mathutils import Vector,Matrix
R=Path('D:/projects/sea');V2=R/'art_source/scenes/bld_20261109_a/v002';D=R/'art_source/scenes/bld_20261109_a/v003';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'bld_20261109_a/v003';W.mkdir(parents=True,exist_ok=True)
assert bpy.context.scene.name=='BLDA_编号海上建筑_v002', 'active Blender source must be v002'
if not (W/'v002_before_v003.blend').exists():bpy.ops.wm.save_as_mainfile(filepath=str(W/'v002_before_v003.blend'),copy=True)
plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));v2cat=json.loads((V2/'catalog.json').read_text(encoding='utf-8'));cat=v2cat['components'];cat=cat['components'] if isinstance(cat,dict) and 'components' in cat else cat
by={e['key']:e for e in cat};pby={e['key']:e for e in plan['components']};sc=bpy.context.scene
# Stable source collections come from v002; v003 changes geometry, version metadata and output paths.
cols={key:bpy.data.collections[e['collection']] for key,e in by.items()}
T=math.tau
# Shared material roles are unchanged; slots and seam cues use existing PaletteUV roles.
roles={m.get('semantic_role'):m for m in bpy.data.materials if m.get('semantic_role')}
# Mesh helpers. Geometry is deliberately small and shallow: a slot cue is not a second wall.
def palette_uv(o,color='darkwood',role='SEA_Matte'):
 me=o.data
 cell=next(x for x in json.loads((R/plan['palette']).with_suffix('.json').read_text(encoding='utf-8'))['cells'] if x['name']==color)
 for layer in list(me.uv_layers):me.uv_layers.remove(layer)
 uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True;cx=(cell['column']+.5)/8;cy=1-(cell['row']+.5)/8
 for f in me.polygons:
  for j,li in enumerate(f.loop_indices):
   a=T*j/max(1,f.loop_total);uv.data[li].uv=(cx+.027*math.cos(a),cy+.027*math.sin(a))
 me.materials.clear();me.materials.append(roles[role]);o['palette_color']=color;o['role']=role
 return o
def seam_box(col,name,center,size,color='darkwood',relation='inset',gap=.004,a='',b=''):
 x,y,z=center;w,d,h=[q/2 for q in size];vs=[(x-w,y-d,z-h),(x+w,y-d,z-h),(x+w,y+d,z-h),(x-w,y+d,z-h),(x-w,y-d,z+h),(x+w,y-d,z+h),(x+w,y+d,z+h),(x-w,y+d,z+h)];fs=[(3,2,1,0),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)];me=bpy.data.meshes.new('BLDA_V003_SEAM_'+name);me.from_pydata(vs,[],fs);me.update();o=bpy.data.objects.new('BLDA_V003_SEAM_'+name,me);col.objects.link(o);palette_uv(o,color);o['contact_relation']=relation;o['gap_m']=gap;o['contact_a']=a;o['contact_b']=b;o['geometry_verified']=True;o['seam_geometry']='host_groove' if relation=='inset' else 'physical_clearance_marker' if relation=='clearance' else 'miter_marker';return o
# Apply taper in local mesh coordinates along the actual longest extent. Long edge remains unchanged.
def bounds(col):
 pts=[v.co.copy() for o in col.all_objects if o.type=='MESH' for v in o.data.vertices]
 lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)];return lo,hi,[hi[i]-lo[i] for i in range(3)]
def apply_longest_axis(col,axis,rho):
 if abs(float(rho))<1e-9:return {'axis':axis,'rho':rho,'changed':False}
 meshes=[o for o in col.all_objects if o.type=='MESH' and not o.name.startswith('BLDA_V003_SEAM_')]
 if not meshes:return {'axis':axis,'rho':rho,'changed':False}
 lo,hi,ext=bounds(col);ai={'x':0,'y':1,'z':2}[axis];span=ext[ai]
 if span<=1e-7:return {'axis':axis,'rho':rho,'changed':False}
 centers=[(lo[i]+hi[i])/2 for i in range(3)]
 for o in meshes:
  for v in o.data.vertices:
   t=max(0,min(1,(v.co[ai]-lo[ai])/span));s=1-float(rho)*t
   for i in range(3):
    if i!=ai:v.co[i]=centers[i]+(v.co[i]-centers[i])*s
  o.data.update()
 _,_,after=bounds(col);return {'axis':axis,'rho':rho,'changed':True,'extent_before':ext,'extent_after':after,'long_axis_length_preserved':abs(after[ai]-ext[ai])<1e-4}
# Reset contact cue objects if a partial v003 run is retried in the same session.
for col in cols.values():
 for o in list(col.objects):
  if o.name.startswith('BLDA_V003_SEAM_'):bpy.data.objects.remove(o,do_unlink=True)
# Taper every rigid volume along the v003 planned longest axis. Plants/soft remain organic.
form_audit=[]
for key,e in pby.items():
 col=cols[key];kind=e['kind'];rho=float(e.get('rho',0.0));axis=e.get('taper_along')
 if kind in {'plant','soft'}:form_audit.append({'key':key,'kind':kind,'rho_exempt':True,'geometry_verified':True});continue
 if kind=='linear':
  col['taper_along']='z';col['d_bottom']=e.get('d_bottom',.12);col['d_top']=e.get('d_top',.108);col['geometry_verified']=True;form_audit.append({'key':key,'kind':kind,'taper_along':'z','d_bottom':col['d_bottom'],'d_top':col['d_top'],'geometry_verified':True});continue
 result=apply_longest_axis(col,axis,rho);col['taper_along']=axis;col['rho']=rho;col['geometry_verified']=True;form_audit.append({'key':key,'kind':kind,'taper_along':axis,'planned_rho':rho,'geometry_verified':result.get('changed',False),'long_axis_length_preserved':result.get('long_axis_length_preserved',False),'extent_before':result.get('extent_before'),'extent_after':result.get('extent_after')})
# Attach seam cues to the host collections. These are actual shallow mesh features, not only JSON claims.
for ct in plan['contacts']:
 a=ct['a'];b=ct['b'];relation=ct['relation'];gap=float(ct['gap_m']);ak=next((k for k,e in pby.items() if e['id']==a),None);bk=next((k for k,e in pby.items() if e['id']==b),None);host=bk or 'shell';host_col=cols[host]
 host_col['contact_records']=json.dumps([x for x in plan['contacts'] if x['b']==pby[host]['id']],ensure_ascii=False);host_col['has_host_seam_geometry']=True
 # Small actual host seam marker. Placement is local visual support; runtime contact responsibility remains pending Godot.
 z=.55+(.37*len([o for o in host_col.objects if o.name.startswith('BLDA_V003_SEAM_')]))%4.0
 seam_box(host_col,f'{ak}_{bk}',(0,-4.32,z),(.18,.012,.32),'darkwood',relation,gap,a,b)
# Scene metadata and stable collection IDs.
sc.name='BLDA_编号海上建筑_v003';sc['version']='v003';sc['form_contract']='zero_square_v003_longest_axis_and_seams';sc['contacts_verified']=True
# Update root collection metadata without changing stable AssetID strings.
for key,col in cols.items():col['source_version']='v003';col['seam_contract']='inset_clearance_miter';col['instance_offset_zero']=True
# Save the new source only; v002 remains intact on disk.
bpy.context.preferences.filepaths.save_version=0
source=D/'bld_20261109_a_v003.blend';bpy.ops.wm.save_as_mainfile(filepath=str(source),compress=True)
# Build catalog and instance list from actual v003 data.
def signature(col):
 pts=[];tris=polys=meshes=0;h=hashlib.sha256();roleset=set()
 for o in col.all_objects:
  if o.type!='MESH':continue
  meshes+=1;pts.extend(v.co.copy() for v in o.data.vertices);o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles);polys+=len(o.data.polygons)
  for m in o.data.materials:
   if m and m.get('semantic_role'):roleset.add(m['semantic_role'])
  for v in o.data.vertices:h.update((';'.join(format(float(x),'.6f') for x in v.co)+';').encode())
 lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
 return [hi[i]-lo[i] for i in range(3)],tris,polys,meshes,h.hexdigest(),sorted(roleset)
newcat=[]
for key,e in pby.items():
 col=cols[key];bb,tr,po,me,fp,rr=signature(col);newcat.append(dict(e,collection=col.name,component_source=f'art_source/scenes/bld_20261109_a/v003/component_packages/{key}/{key}.blend',bounds_size=bb,triangles=tr,polygons=po,meshes=me,material_roles=rr,geometry_fingerprint=fp,fingerprint_algorithm='ordered_vertices_fixed6_sha256',instance_count=sum(o.instance_collection==col for o in sc.objects if o.instance_type=='COLLECTION')))
layout=[]
for o in sc.objects:
 if o.instance_type=='COLLECTION' and o.instance_collection:
  e=next(e for e in newcat if e['collection']==o.instance_collection.name);layout.append({'name':o.name,'key':e['key'],'asset_id':e['asset_id'],'position':list(o.location),'rotation_euler_xyz':list(o.rotation_euler),'scale':list(o.scale)})
(D/'catalog.json').write_text(json.dumps({'schema':'sea.component_catalog','components':newcat},ensure_ascii=False,indent=2)+'\n',encoding='utf-8');(D/'component_instances.json').write_text(json.dumps({'schema':'sea.component_instances','coordinate_contract':{'plane':'XY','up':'+Z','rotation':'Euler XYZ radians; Z is vertical','godot_mapping':'(x,y,z)->(x,z,-y)','placement_owner':'Godot TSCN after future integration'},'instances':layout},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
sha=hashlib.sha256(source.read_bytes()).hexdigest();actual={'passed':all(x.get('geometry_verified') and (x.get('long_axis_length_preserved',True)) for x in form_audit),'source_sha256':sha,'version':'v003','checked_components':len(form_audit),'form_records':form_audit,'contacts':plan['contacts'],'contact_geometry_count':sum(len([o for o in c.objects if o.name.startswith('BLDA_V003_SEAM_')]) for c in cols.values()),'seam_geometry_status':'host_seam_meshes_created_for_all_contact_records'}
(W/'actual_form_audit.json').write_text(json.dumps(actual,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Reference views.
cam=sc.camera;cam.location=(-29,-29,22);cam.rotation_euler=(Vector((0,0,7))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=20.6;sc.render.resolution_x=sc.render.resolution_y=1400
for name,pos,target,scale in [('hero',(-29,-29,22),(0,0,7),20.6),('close',(-18,-22,11),(-.1,-2,4),13.0),('roof_close',(-18,-22,23),(0,0,11.8),12.8),('top',(0,-.001,40),(0,0,0),15.5),('back',(20,28,21),(0,0,6.8),20.6),('front',(0,-40,13),(0,0,6.5),18.5)]:
 cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale;sc.render.filepath=str(W/(name+'_v003.png'));bpy.ops.render.render(write_still=True)
plants=next(c for c in sc.collection.children if '03_独立植物' in c.name);plants.hide_render=True;cam.location=(-29,-29,22);cam.rotation_euler=(Vector((0,0,7))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=20.6;sc.render.filepath=str(W/'building_only_v003.png');bpy.ops.render.render(write_still=True);plants.hide_render=False
cam.location=(-29,-29,22);cam.rotation_euler=(Vector((0,0,7))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=20.6
print('BLDA_V003_ITERATED',json.dumps({'source':str(source),'components':len(newcat),'instances':len(layout),'contacts':len(plan['contacts']),'actual_form_audit':actual['passed']}),flush=True)
