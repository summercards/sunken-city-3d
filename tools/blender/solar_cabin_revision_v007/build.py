import bpy,json,math,hashlib,random,os
from pathlib import Path
from mathutils import Matrix,Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v007';OLD=D.parent/'v006';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'solar_cabin_revision_v007'
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
P=json.loads((D/'component_plan.json').read_text());spec={e['key']:e for e in P['components']};cat={e['key']:e for e in json.loads((OLD/'catalog.json').read_text())['components']}
pal=R/P['palette'];data=json.loads(pal.with_suffix('.json').read_text());cells={e['name']:e for e in data['cells']}
# Generate exact sRGB solid swatches without an external image editor.
import struct,zlib
rgb=[[(0,0,0)]*512 for _ in range(512)]
for c in cells.values():
 color=tuple(bytes.fromhex(c['hex'][1:]))
 for y in range(c['row']*64,(c['row']+1)*64):rgb[y][c['column']*64:(c['column']+1)*64]=[color]*64
def chunk(t,v):return struct.pack('>I',len(v))+t+v+struct.pack('>I',zlib.crc32(t+v)&0xffffffff)
pal.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',512,512,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(b'\0'+bytes(x for pixel in row for x in pixel) for row in rgb)))+chunk(b'IEND',b''))
bpy.ops.wm.open_mainfile(filepath=str(OLD/'sunny_bloom_retreat.blend'));bpy.context.preferences.filepaths.save_version=0;S=bpy.context.scene;LIB=next(s for s in bpy.data.scenes if s!=S)
S.name='太阳能木屋-海上区域-v007';LIB.render.engine='BLENDER_EEVEE_NEXT'
before={o.name:[list(row) for row in o.matrix_world] for o in S.objects if o.instance_type=='COLLECTION'}
def paint(me,color):
 uv=me.uv_layers['PaletteUV'];c=cells[color];u=(c['column']+.5)/8;v=1-(c['row']+.5)/8
 for f in me.polygons:
  for j,l in enumerate(f.loop_indices):uv.data[l].uv=(u+.025*math.cos(j*math.tau/len(f.loop_indices)),v+.025*math.sin(j*math.tau/len(f.loop_indices)))
# Recover the two user-realized boards without discarding their edited positions.
recovered=[]
for ob in list(S.objects):
 if ob.type!='MESH':continue
 key=next((k for k in ['platform_board','dock_board'] if ob.name.startswith(k+'_mesh')),None)
 if not key:raise RuntimeError('Unclassified user mesh '+ob.name)
 template=next(o for o in bpy.data.collections[cat[key]['collection']].objects if o.type=='MESH')
 assert len(ob.data.vertices)==len(template.data.vertices)
 assert max((a.co-b.co).length for a,b in zip(ob.data.vertices,template.data.vertices))<1e-5,'User changed board geometry; preserve explicitly'
 inst=bpy.data.objects.new('用户调整_'+key,None);ob.users_collection[0].objects.link(inst);inst.instance_type='COLLECTION';inst.instance_collection=bpy.data.collections[cat[key]['collection']];inst.matrix_world=ob.matrix_world.copy();inst['module']='front_platform' if key=='platform_board' else 'bridge';recovered.append({'name':ob.name,'matrix':[list(r) for r in ob.matrix_world]});bpy.data.objects.remove(ob,do_unlink=True)
# Preserve the user's red/bridge offsets; gently stagger only the regular yellow floors.
rng=random.Random(261026);stagger=[]
for key in ['concrete_slab','terrace']:
 col=bpy.data.collections[cat[key]['collection']]
 obs=sorted([o for o in col.objects if o.type=='MESH'],key=lambda o:sum(v.co.y for v in o.data.vertices)/len(o.data.vertices))
 pattern=['wood_light','honey','honey','wood_light','wood','wood_light','wood_light','honey','wood','honey','wood_light','honey']
 for j,o in enumerate(obs):
  dx=rng.uniform(-.095,.095);o.data=o.data.copy();o.data.transform(Matrix.Translation((dx,0,0)));paint(o.data,pattern[j]);stagger.append({'mesh':o.name,'local_offset_x':dx,'color':pattern[j]})
# Four UV-only variants retain the same geometry and are explicitly registered.
for key,e in spec.items():
 if 'variant_of' not in e:continue
 src=bpy.data.collections[cat[e['variant_of']]['collection']];col=bpy.data.collections.new(e['asset_id']);LIB.collection.children.link(col);root=bpy.data.objects.new('ROOT_'+key,None);col.objects.link(root)
 for o in src.objects:
  if o.type=='MESH':
   cp=o.copy();cp.data=o.data.copy();cp.parent=root;col.objects.link(cp);paint(cp.data,e['palette_color'])
 cat[key]=dict(cat[e['variant_of']],**e,collection=col.name,root=root.name)
for key,color in [('platform_board','red'),('dock_board','wood_light')]:
 for o in bpy.data.collections[cat[key]['collection']].objects:
  if o.type=='MESH':o.data=o.data.copy();paint(o.data,color)
patterns={'platform_board':['platform_board_coral','platform_board','platform_board','platform_board_ochre','platform_board_coral','platform_board_coral'],'dock_board':['dock_board_sand','dock_board','dock_board','dock_board_shade','dock_board','dock_board_sand','dock_board_sand','dock_board']}
assignments=[]
for key,pattern in patterns.items():
 obs=sorted([o for o in S.objects if o.instance_collection and o.instance_collection.name==cat[key]['collection']],key=lambda o:-o.location.y)
 assert len(obs)==len(pattern)
 for o,k in zip(obs,pattern):o.instance_collection=bpy.data.collections[cat[k]['collection']];assignments.append({'instance':o.name,'component':k})
# Extend the rope terminal inward to the actual rail, leaving every tire in place.
tirecol=bpy.data.collections[cat['hanging_tire']['collection']];rope=next(o for o in tirecol.objects if o.name=='轮胎悬挂绳');rope.data=rope.data.copy()
tires=[o for o in S.objects if o.instance_collection==tirecol]
rails=[o for o in S.objects if o.instance_collection and o.instance_collection.name==cat['bridge_rope']['collection']]
railpts=[rail.matrix_world@m.matrix_world@v.co for rail in rails for m in rail.instance_collection.objects if m.type=='MESH' for v in m.data.vertices]
# Terminal cap is the high, inward end of the existing hanging rope.
verts=list(rope.data.vertices);maxz=max(v.co.z for v in verts);cap=[v for v in verts if v.co.z>maxz-.065];end=sum((v.co for v in cap),Vector())/len(cap)
targets=[]
for tire in tires:
 world=tire.matrix_world@end;nearest=min(railpts,key=lambda p:(p-world).length);targets.append(tire.matrix_world.inverted()@nearest)
target=sum(targets,Vector())/len(targets);delta=target-end
for v in verts:
 t=max(0,min(1,(v.co.z-.98)/(end.z-.98)));v.co+=delta*t
ropecheck=[(tire.matrix_world@target-min(railpts,key=lambda p:(p-tire.matrix_world@target).length)).length for tire in tires]
assert max(ropecheck)<.06,ropecheck
for im in bpy.data.images:
 if im.source=='FILE':im.filepath=str(pal);im.reload()
for mat in bpy.data.materials:
 if mat.use_nodes:
  for node in mat.node_tree.nodes:
   if node.type=='TEX_IMAGE':node.interpolation='Closest'
entries=[];layout=[];idkey={v['collection']:k for k,v in cat.items()}
for o in S.objects:
 if o.instance_type!='COLLECTION':continue
 k=idkey[o.instance_collection.name];e=cat[k];layout.append(dict(name=o.name,asset_id=e['asset_id'],position=list(o.location),rotation_euler_xyz=list(o.rotation_euler),scale=list(o.scale),category=e['category'],module=o['module']))
for k,e in cat.items():
 count=sum(i['asset_id']==e['asset_id'] for i in layout)
 if not count:continue
 vs=[o.matrix_world@v.co for o in bpy.data.collections[e['collection']].objects if o.type=='MESH' for v in o.data.vertices];lo=[min(v[a] for v in vs) for a in range(3)];hi=[max(v[a] for v in vs) for a in range(3)];e.update(version='v007',bounds_min=lo,bounds_size=[hi[a]-lo[a] for a in range(3)],instance_count=count,component_source=(D/'components'/k/(k+'.blend')).relative_to(R).as_posix(),geometry_fingerprint=hashlib.sha256(str([tuple(v) for v in vs]).encode()).hexdigest());entries.append(e)
assert len(entries)==49
for name,m in before.items():assert max(abs(bpy.data.objects[name].matrix_world[i][j]-m[i][j]) for i in range(4) for j in range(4))<1e-6,name
write(D/'catalog.json',{'components':entries});write(D/'component_instances.json',{'coordinate_contract':{'plane':'XY','up':'+Z','godot':'(x,y,z) -> (x,z,-y)'},'instances':layout})
for im in bpy.data.images:
 if im.source=='FILE':im.filepath=bpy.path.relpath(str(pal),start=str(D))
S['revision']='v007';S.render.engine='CYCLES';S.cycles.samples=20;S.render.resolution_x=1000;S.render.resolution_y=1000;S.render.resolution_percentage=100
bpy.ops.wm.save_as_mainfile(filepath=str(D/'sunny_bloom_retreat.blend'),compress=True)
write(W/'edit_evidence.json',{'preserved_instance_transforms':len(before),'recovered_user_meshes':recovered,'stagger':stagger,'board_colors':assignments,'rope_terminal_surface_distances':ropecheck,'rope_delta':list(delta),'input_sha256':sha(OLD/'sunny_bloom_retreat.blend')})
S.render.filepath=str(W/'previews/beauty.png');bpy.ops.render.render(write_still=True)
print('BUILT',len(entries),len(layout),ropecheck,flush=True)
