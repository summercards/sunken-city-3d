"""Independent triangle/UV/normal comparison of saved bpy meshes and real GLBs."""
import bpy,json,struct,collections,os
from pathlib import Path
R=Path('D:/projects/sea');D=R/'art_source/scenes/gift_kiosk/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'gift_kiosk/v001';cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components'];errors=[];triangles=0
def q(values):return tuple(round(float(v),5) for v in values)
def triangle(points):return tuple(sorted(points))
for e in cat:
 path=R/f"godot/assets/models/facilities/gift_kiosk/{e['key']}/{e['key']}.glb";raw=path.read_bytes();length=struct.unpack_from('<I',raw,12)[0];g=json.loads(raw[20:20+length]);base=28+length
 def read(a):
  acc=g['accessors'][a];view=g['bufferViews'][acc['bufferView']];n={'SCALAR':1,'VEC2':2,'VEC3':3}[acc['type']];fmt={5126:'f',5125:'I'}[acc['componentType']];start=base+view.get('byteOffset',0)+acc.get('byteOffset',0);data=struct.unpack_from('<'+fmt*(acc['count']*n),raw,start)
  return [data[i:i+n] for i in range(0,len(data),n)]
 expected=collections.Counter();actual=collections.Counter()
 for obj in bpy.data.collections[e['collection']].objects:
  me=obj.data;me.calc_loop_triangles();uv=me.uv_layers['PaletteUV'];norm=me.corner_normals
  for tri in me.loop_triangles:
   points=[]
   for li in tri.loops:
    v=me.vertices[me.loops[li].vertex_index].co;n=norm[li].vector;t=uv.data[li].uv
    points.append(q((v.x,v.z,-v.y,n.x,n.z,-n.y,t.x,1-t.y)))
   expected[(obj['role'],triangle(points))]+=1
 for mesh in g['meshes']:
  for prim in mesh['primitives']:
   pos=read(prim['attributes']['POSITION']);norm=read(prim['attributes']['NORMAL']);uv=read(prim['attributes']['TEXCOORD_0']);indices=[v[0] for v in read(prim['indices'])];role=g['materials'][prim['material']]['name']
   for i in range(0,len(indices),3):
    actual[(role,triangle([q(pos[v]+norm[v]+uv[v]) for v in indices[i:i+3]]))]+=1
 missing=sum((expected-actual).values());extra=sum((actual-expected).values());triangles+=sum(actual.values())
 if missing or extra:errors.append({'component':e['key'],'missing_triangles':missing,'unexpected_triangles':extra})
report={'passed':not errors,'components':len(cat),'triangles_compared':triangles,'includes':['positions','corner normals','UV0','material role'],'errors':errors}
(W/'export_audit.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps(report),flush=True)
if errors:raise RuntimeError(str(errors))
