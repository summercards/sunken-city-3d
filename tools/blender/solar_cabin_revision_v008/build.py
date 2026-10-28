import bpy,json,math,hashlib,struct,zlib,os
from pathlib import Path
from mathutils import Matrix,Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v008';OLD=D.parent/'v007';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'solar_cabin_revision_v008'
P=json.loads((D/'component_plan.json').read_text());pal=R/P['palette'];colors=json.loads(pal.with_suffix('.json').read_text());cells={e['name']:e for e in colors['cells']}
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
pixels=[[(0,0,0)]*512 for _ in range(512)]
for c in cells.values():
 for y in range(c['row']*64,(c['row']+1)*64):pixels[y][c['column']*64:(c['column']+1)*64]=[tuple(bytes.fromhex(c['hex'][1:]))]*64
def chunk(t,d):return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
pal.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',512,512,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(b'\0'+bytes(x for c in row for x in c) for row in pixels)))+chunk(b'IEND',b''))
bpy.ops.wm.open_mainfile(filepath=str(OLD/'sunny_bloom_retreat.blend'));bpy.context.preferences.filepaths.save_version=0;S=bpy.context.scene;S.name='太阳能木屋-海上区域-v008';cat=json.loads((OLD/'catalog.json').read_text());changes=[]
# Thinning a ceiling with its top pinned must also close the newly exposed wall gap.
roof_gap=.355-.22/(1.15*1.38)
house=next(e for e in cat['components'] if e['key']=='house')
for o in bpy.data.collections[house['collection']].objects:
 if o.type=='MESH':
  o.data=o.data.copy();hi=max(v.co.z for v in o.data.vertices)
  for v in o.data.vertices:
   if v.co.z>hi-.08:v.co.z+=roof_gap*max(0,min(1,(v.co.z-hi+.08)/.08))
for o in S.objects:
 if o.instance_collection and o.instance_collection.name=='SEA-SCENE-SBR-WALL-PIER' and o.location.z<1.0:o.scale.z*=1+roof_gap/2.85
def paint(me,color):
 uv=me.uv_layers['PaletteUV'];c=cells[color];u=(c['column']+.5)/8;v=1-(c['row']+.5)/8
 for f in me.polygons:
  for j,l in enumerate(f.loop_indices):uv.data[l].uv=(u+.025*math.cos(j*math.tau/len(f.loop_indices)),v+.025*math.sin(j*math.tau/len(f.loop_indices)))
for e in cat['components']:
 key=e['key'];col=bpy.data.collections[e['collection']]
 if key.startswith(('platform_board','dock_board')) or key in ['concrete_slab','terrace']:
  desired=.22/(1.15*(1.38 if key=='terrace' else 1.5))
  for j,o in enumerate(col.objects):
   if o.type!='MESH':continue
   me=o.data.copy();o.data=me;lo=min(v.co.z for v in me.vertices);hi=max(v.co.z for v in me.vertices);ratio=desired/(hi-lo)
   for v in me.vertices:v.co.z=hi+(v.co.z-hi)*ratio
   color='wood_light'
   if key.endswith(('coral','sand')):color='honey'
   elif key.endswith(('ochre','shade')):color='wood'
   elif key in ['concrete_slab','terrace']:color=['wood_light','honey','wood_light','wood','wood_light'][j%5]
   paint(me,color);changes.append(dict(component=key,mesh=o.name,old_thickness=hi-lo,new_thickness=desired,top_pinned=hi,color=color))
 vs=[o.matrix_world@v.co for o in col.objects if o.type=='MESH' for v in o.data.vertices];lo=[min(v[a] for v in vs) for a in range(3)];hi=[max(v[a] for v in vs) for a in range(3)]
 if key.startswith(('platform_board','dock_board')) or key in ['concrete_slab','terrace']:
  # Restore the bottom-center component pivot after thinning, preserving visible placement.
  offset=Vector(((lo[0]+hi[0])/2,(lo[1]+hi[1])/2,lo[2]))
  for o in col.objects:
   if o.type=='MESH':o.data.transform(Matrix.Translation(-offset))
  for o in S.objects:
   if o.instance_collection==col:o.location+=o.matrix_world.to_3x3()@offset
  vs=[o.matrix_world@v.co for o in col.objects if o.type=='MESH' for v in o.data.vertices];lo=[min(v[a] for v in vs) for a in range(3)];hi=[max(v[a] for v in vs) for a in range(3)]
 e.update(version='v008',bounds_min=lo,bounds_size=[hi[a]-lo[a] for a in range(3)],component_source=(D/'components'/key/(key+'.blend')).relative_to(R).as_posix(),geometry_fingerprint=hashlib.sha256(str([tuple(v) for v in vs]).encode()).hexdigest())
for im in bpy.data.images:
 if im.source=='FILE':im.filepath=str(pal);im.reload();im.filepath=bpy.path.relpath(str(pal),start=str(D))
for s in bpy.data.scenes:s.render.engine='CYCLES'
S['revision']='v008';S.cycles.samples=20;S.render.resolution_x=1000;S.render.resolution_y=1000;S.render.resolution_percentage=100
bpy.ops.wm.save_as_mainfile(filepath=str(D/'sunny_bloom_retreat.blend'),compress=True)
layout=json.loads((OLD/'component_instances.json').read_text())
for e in layout['instances']:
 o=S.objects[e['name']];e.update(position=list(o.location),rotation_euler_xyz=list(o.rotation_euler),scale=list(o.scale))
write(D/'catalog.json',cat);write(D/'component_instances.json',layout);write(W/'edit_evidence.json',dict(changes=changes,reference_thickness=.18,ground_thickness=.22,deck_world_top=1.38,deck_world_bottom=1.16,scene_y=-.77,visible_placement_unchanged=True,pivots_normalized_to_bottom_center=True,supports_extended_to_ceiling=True))
S.render.filepath=str(W/'previews/beauty.png');bpy.ops.render.render(write_still=True);print('BUILT v008',flush=True)
