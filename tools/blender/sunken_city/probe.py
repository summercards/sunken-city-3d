"""Independent Blender data probe: no geometry authoring helpers imported, no source save."""
import bpy
import hashlib
import json
import math
import os
from pathlib import Path
from collections import Counter
from mathutils import Vector
R=Path(__file__).resolve().parents[3]
VERSION=globals().get('VERSION',os.environ.get('SEA_SUNKEN_VERSION','v001'))
D=R/'art_source/scenes/sunken_city'/VERSION;W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'sunken_city'/VERSION
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'))
CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components']
S=bpy.data.scenes['沉没旧城_完整参考布局_'+VERSION]
bpy.context.view_layer.update()
errors=[];checks=0

def ck(ok,msg):
    global checks
    checks+=1
    if not ok:errors.append(msg)

def bounds(obj):
    pts=[obj.matrix_world@v.co for v in obj.data.vertices]
    return [[min(v[i] for v in pts) for i in range(3)],[max(v[i] for v in pts) for i in range(3)]]

ck(len(CAT)<=50,'component budget')
ck(len(bpy.data.materials)<=4,'material count')
for mat in bpy.data.materials:
    ck(mat.name in ('SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission'),'unexpected material '+mat.name)
    tex=[n for n in mat.node_tree.nodes if n.type=='TEX_IMAGE']
    ck(len(tex)==1,'palette image node '+mat.name)
    if tex:
        t=tex[0];ck(t.interpolation=='Closest','interpolation '+mat.name)
        ck(t.image.packed_file is None,'packed palette '+mat.name)
        ck(Path(bpy.path.abspath(t.image.filepath)).resolve()==(R/P['palette']).resolve(),'palette path '+mat.name)
    bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    ck(bs.inputs['Emission Strength'].default_value==0,'emission '+mat.name)
rows=[];fingerprints={};package_meshes=[]
for c in CAT:
    col=bpy.data.collections.get(c['collection']);ck(col is not None,'missing '+c['key'])
    if col is None:continue
    ck(tuple(col.instance_offset)==(0,0,0),'instance offset '+c['key'])
    mesh=[o for o in col.all_objects if o.type=='MESH'];root=bpy.data.objects.get(c['root_object'])
    ck(bool(mesh),'empty '+c['key']);ck(root is not None and root.type=='EMPTY','root '+c['key'])
    allpts=[];tris=0;faces=0;bad=0;dupes=[]
    for o in col.all_objects:
        ck(max(abs(o.matrix_basis[i][j]-(1 if i==j else 0)) for i in range(4) for j in range(4))<1e-6,'nonidentity transform '+o.name)
        ck(o.get('collision')=='none' and o.get('interactive') is False,'nonvisual '+o.name)
    for o in mesh:
        package_meshes.append(o.name);me=o.data;me.calc_loop_triangles();tris+=len(me.loop_triangles);faces+=len(me.polygons)
        allpts.extend([v.co for v in me.vertices]);uv=me.uv_layers.active
        ck(len(me.uv_layers)==1 and uv.name=='PaletteUV' and uv.active_render,'uv layers '+o.name)
        signatures=Counter()
        for poly in me.polygons:
            pts=[tuple(uv.data[i].uv) for i in poly.loop_indices]
            cells={(int(u*8),int(v*8)) for u,v in pts}
            area=abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(pts,pts[1:]+pts[:1])))/2
            safe=all(.015625<(u%0.125)<.109375 and .015625<(v%0.125)<.109375 for u,v in pts)
            ck(len(cells)==1 and area>1e-7 and safe,'bad UV '+o.name+' '+str(poly.index))
            bad+=int(not(len(cells)==1 and area>1e-7 and safe))
            signature=tuple(sorted(tuple(round(v,4) for v in me.vertices[i].co) for i in poly.vertices))
            signatures[signature]+=1
        dupes=[n for n in signatures.values() if n>1]
        ck(not dupes,'duplicate coincident polygons '+c['key'])
        ck(len(o.users_collection)==1,'multiple package ownership '+o.name)
        raw=';'.join(','.join(f'{v:.4f}' for v in p.co) for p in me.vertices)
        fp=hashlib.sha256(raw.encode()).hexdigest();fingerprints[c['key']]=fp
    lo=[min(v[i] for v in allpts) for i in range(3)];hi=[max(v[i] for v in allpts) for i in range(3)]
    ck(abs(lo[2])<1e-4 and abs(lo[0]+hi[0])<1e-4 and abs(lo[1]+hi[1])<1e-4,'bottom center '+c['key'])
    ck(tris==c['triangles'],'triangle count '+c['key'])
    rows.append(dict(key=c['key'],bounds=[lo,hi],triangles=tris,faces=faces,uv_failures=bad,fingerprint=fingerprints[c['key']]))
ck(len(set(fingerprints.values()))==len(fingerprints),'duplicate component geometry')
instances=[];violations=[];archboxes=[]
boundary=P.get('coordinate_contract',{}).get('boundary_xy_m',[-120,120,-120,120])
if VERSION=='v005': boundary=[-132,132,-132,132]
for o in S.objects:
    if o.instance_type!='COLLECTION' or o.instance_collection is None:continue
    c=next(c for c in CAT if c['collection']==o.instance_collection.name)
    pts=[o.matrix_world@v.co for ob in o.instance_collection.all_objects if ob.type=='MESH' for v in ob.data.vertices]
    lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
    ck(lo[0]>=boundary[0]-.001 and hi[0]<=boundary[1]+.001 and lo[1]>=boundary[2]-.001 and hi[1]<=boundary[3]+.001,'outside fence '+o.name)
    ck(hi[2]<1.12,'above water '+o.name)
    for q in P['exclusions']:
        # User clarified central exclusion is BUILDINGS ONLY; deep ground is deliberately continuous.
        if c['category']!='architecture':continue
        x0,x1,y0,y1=q['xy'];over=hi[0]>x0 and lo[0]<x1 and hi[1]>y0 and lo[1]<y1
        ck(not over,'protected building overlap '+o.name+' '+q['id'])
        if over:violations.append(dict(object=o.name,region=q['id'],bounds=[lo,hi]))
    rec=dict(name=o.name,key=c['key'],category=c['category'],bounds=[lo,hi],position=list(o.location),rotation=list(o.rotation_euler))
    instances.append(rec)
    if c['category']=='architecture':archboxes.append(rec)
overlaps=[]
for i,a in enumerate(archboxes):
    for b in archboxes[i+1:]:
        al,ah=a['bounds'];bl,bh=b['bounds']
        dx=min(ah[0],bh[0])-max(al[0],bl[0]);dy=min(ah[1],bh[1])-max(al[1],bl[1])
        if dx>1 and dy>1:overlaps.append([a['name'],b['name'],round(dx,2),round(dy,2)])
ck(not overlaps,'building envelopes overlap '+str(overlaps[:8]))
ck(len(instances)==len(P['instances']),'instance count drift')
report=dict(passed=not errors,checks=checks,errors=errors,file=bpy.data.filepath,components=len(CAT),instances=len(instances),
    buildings=len(archboxes),material_count=len(bpy.data.materials),materials=[m.name for m in bpy.data.materials],
    component_rows=rows,instance_rows=instances,protected_violations=violations,building_overlaps=overlaps,
    master_triangles=sum(r['triangles'] for r in rows),layout_triangles=sum(next(c['triangles'] for c in CAT if c['key']==i['key']) for i in instances),
    actual_height_range_m=[round(min(i['bounds'][0][2] for i in instances),3),round(max(i['bounds'][1][2] for i in instances),3)])
(W/'probe_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:report[k] for k in ('passed','checks','components','instances','buildings','master_triangles','layout_triangles','actual_height_range_m','errors')},ensure_ascii=False))
