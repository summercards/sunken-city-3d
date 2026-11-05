"""Original palette plants with rooted WindData; source -> independent optimized -> GLB."""
import bpy,bmesh,json,math,random,hashlib,sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
DEST=ROOT/'art_source/vegetation/v001'
WORK=ROOT.parent/'sea-work/vegetation_implementation_20261105'
PLAN=json.loads((DEST/'component_plan.json').read_text(encoding='utf-8'))
assert not (DEST/'REJECTED.md').exists(), 'v001 was rejected by the user. Use build_soft_cards.py and v002.'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(p,v):
 p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
cells={c['name']:c for c in json.loads((ROOT/PLAN['palette']).with_suffix('.json').read_text())['cells']}
vs=[];fs=[];cs=[];ws=[]
def vert(p,w):
 vs.append(tuple(p));ws.append(w);return len(vs)-1
def face(indices,col):fs.append(tuple(indices));cs.append(col)
def leaf(start,angle,length,width,rise,col,phase=0,grass=False):
 # Ridge + tapered edges, segmented along the stem; solid back for broad leaves.
 s=Vector(start);d=Vector((math.cos(angle),math.sin(angle),0));side=Vector((-d.y,d.x,0));rows=[]
 for t in [0,.34,.7,1]:
  p=s+d*(length*t)+Vector((0,0,rise*t+.08*length*math.sin(math.pi*t)))
  w=width*(math.sin(math.pi*t)**.7) if 0<t<1 else .002
  bend=max(0,min(1,p.z/HEIGHT))
  rows.append([vert(p+side*w,(bend,t,phase,.8+.2*t)),vert(p+Vector((0,0,width*.24*math.sin(math.pi*t))),(bend,t,phase,.8+.2*t)),vert(p-side*w,(bend,t,phase,.8+.2*t))])
 for j in range(3):
  a,b=rows[j],rows[j+1]
  face((a[1],b[1],b[0],a[0]),col);face((a[2],b[2],b[1],a[1]),col)
  if not grass:face((b[0],b[2],a[2],a[0]),col)
def ellipsoid(center,scale,col,n=12,rings=5,rooted=False):
 rows=[]
 for j in range(rings+1):
  a=math.pi*j/rings
  row=[]
  for i in range(n):
   b=math.tau*i/n;p=(center[0]+scale[0]*math.sin(a)*math.cos(b),center[1]+scale[1]*math.sin(a)*math.sin(b),center[2]+scale[2]*math.cos(a))
   row.append(vert(p,(0 if rooted else max(0,min(1,p[2]/HEIGHT))*.45,0,0,.88)))
  rows.append(row)
 for j in range(rings):
  for i in range(n):face((rows[j][i],rows[j+1][i],rows[j+1][(i+1)%n],rows[j][(i+1)%n]),col)
def stem(p,h):
 n=5;lo=[];hi=[]
 for i in range(n):
  a=i*math.tau/n
  lo.append(vert((p[0]+.009*math.cos(a),p[1]+.009*math.sin(a),0),(0,0,0,1)))
  hi.append(vert((p[0]+.006*math.cos(a),p[1]+.006*math.sin(a),h),(h/HEIGHT,0,0,1)))
 for i in range(n):face((lo[i],lo[(i+1)%n],hi[(i+1)%n],hi[i]),'leaf_dark')
def audit(o):
 me=o.data;me.calc_loop_triangles();uv=me.uv_layers.active;colors=me.color_attributes['WindData']
 bad=0
 for f in me.polygons:
  pts=[uv.data[i].uv for i in f.loop_indices]
  area=abs(sum(a.x*b.y-b.x*a.y for a,b in zip(pts,pts[1:]+pts[:1])))/2
  bad+=area<1e-8
 assert bad==0 and uv.name=='PaletteUV'
 assert all(0<=v<=1.0001 for c in colors.data for v in c.color)
 lo=[min(v.co[i] for v in me.vertices) for i in range(3)];hi=[max(v.co[i] for v in me.vertices) for i in range(3)]
 root=[colors.data[l.index].color[0] for l in me.loops if me.vertices[l.vertex_index].co.z<.00001]
 assert root and max(root)<.0001,(o.name,root)
 return dict(vertices=len(me.vertices),triangles=len(me.loop_triangles),surfaces=1,bounds_blender=[lo,hi],root_vertices=len(root),root_max_weight=max(root),uv_nonzero=True,color_range=[min(c.color[0] for c in colors.data),max(c.color[0] for c in colors.data)])
reports=[]
for ai,entry in enumerate(PLAN['components']):
 key=entry['key'];random.seed(931+ai);vs=[];fs=[];cs=[];ws=[]
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
 S=bpy.context.scene;S.unit_settings.system='METRIC'
 HEIGHT=.32 if entry['profile']=='grass' else .65
 if key.startswith('grass'):
  for i in range(5):
   a=random.random()*math.tau
   leaf((random.uniform(-.12,.12),random.uniform(-.12,.12),0),a,random.uniform(.08,.19),.028 if key=='grass_fine' else .05,random.uniform(.16,.3),['moss','leaf','leaf_mid'][i%3],random.random(),True)
 elif key.startswith('mound'):
  spread=key=='mound_spread';rx=.66 if spread else .49;ry=.44;height=.4 if spread else .57;HEIGHT=height+.08
  ellipsoid((0,0,height*.40),(rx*.87,ry*.87,height*.40),'leaf',12,5,True)
  for j in range(4):
   a=j*math.tau/4
   ellipsoid((rx*.46*math.cos(a),ry*.46*math.sin(a),height*.28),(rx*.47,ry*.48,height*.29),'moss',10,4,True)
  for i in range(54):
   a=i*2.39996;r=math.sqrt((i+.4)/54);x=rx*.83*r*math.cos(a);y=ry*.83*r*math.sin(a);z=height*(1-r*r)**.6*.82
   leaf((x,y,max(.025,z)),a+random.uniform(-.7,.7),random.uniform(.11,.19),random.uniform(.048,.072),random.uniform(.02,.055),['leaf','moss','leaf_mid'][i%3],random.random())
 elif key=='broadleaf':
  for i in range(18):
   a=i*2.39996;r=i/18
   leaf((0,0,0),a,.16+.2*r,.06+.035*r,.54-.24*r,['leaf','moss','leaf_mid'][i%3],random.random())
 elif entry['profile']=='flower':
  for i in range(12):leaf((0,0,0),i*2.39996,.15,.055,.1+random.random()*.08,'leaf_mid',random.random())
  for j in range(3):
   a=j*2.39996;x=.16*math.cos(a);y=.16*math.sin(a);h=.34+j*.10;stem((x,y),h)
   for k in range(7):leaf((x,y,h),k*math.tau/7,.095,.037,.014,'white' if key=='daisy' else 'pink_light',j*.23)
   ellipsoid((x,y,h+.022),(.033,.033,.025),'yellow',8,3)
 else:
  HEIGHT=1
  # Slightly rounded rectangular cover. Root-fixed, independent of wind.
  for z in [0,.035]:
   for x,y in [(-.46,-.5),(.46,-.5),(.5,-.46),(.5,.46),(.46,.5),(-.46,.5),(-.5,.46),(-.5,-.46)]:vert((x,y,z),(0,0,0,1))
  face(tuple(range(8,16)),'moss');face(tuple(reversed(range(8))),'leaf_dark')
  for i in range(8):face((i,(i+1)%8,(i+1)%8+8,i+8),'leaf_mid')
 me=bpy.data.meshes.new(key);me.from_pydata(vs,[],fs);me.update()
 o=bpy.data.objects.new(key,me);S.collection.objects.link(o);bpy.context.view_layer.objects.active=o;o.select_set(True)
 uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True
 color=me.color_attributes.new(name='WindData',type='FLOAT_COLOR',domain='CORNER');me.color_attributes.active_color=color
 for f,c in zip(me.polygons,cs):
  cell=cells[c];u=(cell['column']+.5)/8;v=1-(cell['row']+.5)/8;f.use_smooth=True
  for j,li in enumerate(f.loop_indices):
   ang=j*math.tau/len(f.loop_indices);uv.data[li].uv=(u+.025*math.cos(ang),v+.025*math.sin(ang));color.data[li].color=ws[me.loops[li].vertex_index]
 mat=bpy.data.materials.new('SEA_Matte');mat.use_nodes=True
 bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Roughness'].default_value=.9
 tx=mat.node_tree.nodes.new('ShaderNodeTexImage');tx.image=bpy.data.images.load(str(ROOT/PLAN['palette']));tx.interpolation='Closest';tx.image.filepath=str(ROOT/PLAN['palette'])
 mat.node_tree.links.new(tx.outputs['Color'],bs.inputs['Base Color']);me.materials.append(mat)
 o['asset_id']=entry['asset_id'];o['wind_contract_version']=1;o['visual_only']=True
 # Identical transforms and bottom-center pivot across all packages.
 lo=[min(v.co[i] for v in me.vertices) for i in range(3)];hi=[max(v.co[i] for v in me.vertices) for i in range(3)]
 for v in me.vertices:v.co-=Vector(((lo[0]+hi[0])/2,(lo[1]+hi[1])/2,lo[2]))
 folder=DEST/'components'/key;folder.mkdir(parents=True,exist_ok=True)
 source=folder/(key+'.blend');optimized=folder/(key+'_optimized.blend')
 bpy.ops.wm.save_as_mainfile(filepath=str(source));source_hash=sha(source)
 bpy.ops.wm.open_mainfile(filepath=str(source));o=bpy.data.objects[key];before=audit(o)
 bm=bmesh.new();bm.from_mesh(o.data)
 old=len(bm.verts);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001);bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.000001);bm.to_mesh(o.data);bm.free();o.data.update()
 bpy.ops.wm.save_as_mainfile(filepath=str(optimized));bpy.ops.wm.open_mainfile(filepath=str(optimized));o=bpy.data.objects[key];after=audit(o)
 assert after['triangles']<=entry['triangle_budget'],(key,after['triangles'])
 assert sha(source)==source_hash
 out=ROOT/'godot/assets/models/vegetation'/f'{key}.glb';out.parent.mkdir(parents=True,exist_ok=True)
 bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',export_yup=True,export_materials='EXPORT',export_image_format='NONE',export_vertex_color='NAME',export_vertex_color_name='WindData',export_all_vertex_colors=False,export_active_vertex_color_when_no_material=True)
 report=dict(**entry,source=source.relative_to(ROOT).as_posix(),source_sha256=source_hash,optimized_source=optimized.relative_to(ROOT).as_posix(),optimized_sha256=sha(optimized),glb=out.relative_to(ROOT).as_posix(),glb_sha256=sha(out),before=before,after=after,operations=['merge coincident vertices at 1e-6 m','remove degenerate edges','preserve PaletteUV and WindData seams','reopen both sources and verify'],removed_vertices=before['vertices']-after['vertices'])
 dump(folder/'production_report.json',report);reports.append(report)
dump(WORK/'source_report.json',dict(passed=True,assets=reports))
print('VEGETATION_SOURCE_OK',[(r['key'],r['after']['triangles']) for r in reports])
