from pathlib import Path
p=Path('D:/projects/sea/tools/blender/ocean_rooftop_farm/verify_v002.py')
code=p.read_text(encoding='utf-8').replace('/v002','/v003').replace('farm_v002.blend','farm_v003.blend').replace("startswith('ORF2_屋顶')","startswith('ORF3_屋顶')").replace('len(cat)==39 and len(src.children)==39','len(cat)==46 and len(src.children)==46').replace("'component_count':39","'component_count':46").replace('ORF2_VERIFY','ORF3_VERIFY')
extra='''
# Verify actual route support surfaces by vertical ray against evaluated step/landing meshes.
route=json.loads((D/'stair_route.json').read_text(encoding='utf-8'))
from mathutils.bvhtree import BVHTree
bvhs=[]
for instance in inst:
 if instance.get('component_id','') not in ['SEA-SCENE-ORF2-STAIR_FLIGHT','SEA-SCENE-ORF2-STAIR_LANDING','SEA-SCENE-ORF2-STAIR_LANDING_OPEN','SEA-SCENE-ORF2-ROOF_ENTRY']:continue
 for ob in instance.instance_collection.objects:
  if ob.type!='MESH':continue
  pts=[instance.matrix_world@ob.matrix_world@v.co for v in ob.data.vertices]
  bvhs.append(BVHTree.FromPolygons(pts,[list(p.vertices) for p in ob.data.polygons]))
def supported(x,y,z):
 for bvh in bvhs:
  hit,n,idx,dist=bvh.ray_cast(Vector((x,y,z+.28)),Vector((0,0,-1)),.5)
  if hit is not None:return True
 return False
fails=[]
for f in range(12):
 for j in range(14):
  z=f*5+(j+1)*2.5/14;y=-3+(j+.5)*.3
  if not supported(25,y,z):fails.append(['a',f,j])
  z=f*5+2.5+(j+1)*2.5/14;y=1.2-(j+.5)*.3
  if not supported(27,y,z):fails.append(['b',f,j])
check('all_336_stair_treads_supported',not fails,fails[:10])
# Horizontal links on landing centers and rooftop bridge.
landing_fail=[]
for f in range(12):
 for x in [25,25.5,26,26.5,27]:
  if not supported(x,1.5,f*5+2.5):landing_fail.append([f,x,'half'])
for x in [22.8,23.3,23.8,24.3,24.8,25.3,25.8,26.3,26.8]:
 if not supported(x,-3.8,60):landing_fail.append(['roof',x])
check('landing_and_roof_bridge_support',not landing_fail,landing_fail)
check('46_unique_component_collections',len({e['collection'] for e in cat})==46)
# unchanged protected agriculture and furniture is measured from previous locked signature.
lock=json.loads((W/'locked_scope.json').read_text(encoding='utf-8')) if (W/'locked_scope.json').is_file() else []
lockbad=[];checked=0
for row in lock:
 o=s.objects.get(row['name'])
 if o is None:lockbad.append(row['name']);continue
 key=o.get('component_id','').split('-')[-1].lower()
 if key in ['greenhouse','tank','wind','solar']:continue # user 10:55 expands frame thickness scope
 current=hashlib.sha256(repr([[tuple(v.co) for v in x.data.vertices] for x in o.instance_collection.objects if x.type=='MESH']).encode()).hexdigest()
 matrix=[list(v) for v in o.matrix_world]
 if current!=row['geometry'] or max(abs(matrix[i][j]-row['matrix'][i][j]) for i in range(4) for j in range(4))>.0001:lockbad.append(row['name'])
 checked+=1
check('locked_agriculture_furniture_paths_unchanged',not lockbad,{'checked':checked,'failures':lockbad[:8]})
'''
code=code.replace('# independent component files actually reopened.',extra+'\n# independent component files actually reopened.')
exec(compile(code,'verify_v003_generated','exec'))
