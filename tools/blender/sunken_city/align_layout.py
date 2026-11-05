"""User feedback r2: aligned 24m ground tiles, common seam plane; no tilted floor joins.
Preserves live building geometry; fixes only duplicate coincident faces and authored layout.
"""
import ast
import bpy
import bmesh
import hashlib
import json
import math
import random
from pathlib import Path
from mathutils import Euler,Matrix,Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v001';W=R.parent/'sea-work/sunken_city/v001'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components']
S=bpy.data.scenes['沉没旧城_完整参考布局_v001'];MASTER=bpy.data.scenes['01_组件母版_独立编辑']
checkpoint=W/'before_aligned_floor.blend'
if not checkpoint.exists():bpy.ops.wm.save_as_mainfile(filepath=str(checkpoint),copy=True,compress=True)
# Stable meshes are not regenerated. Remove actual duplicate polygons only, retaining all UV/color/material data.
removed={}
for c in CAT:
    col=bpy.data.collections[c['collection']]
    for o in col.objects:
        if o.type!='MESH':continue
        bm=bmesh.new();bm.from_mesh(o.data);seen=set();bad=[]
        for f in bm.faces:
            sig=tuple(sorted(tuple(round(q,5) for q in v.co) for v in f.verts))
            if sig in seen:bad.append(f)
            else:seen.add(sig)
        if bad:
            bmesh.ops.delete(bm,geom=bad,context='FACES_ONLY');bm.to_mesh(o.data)
        removed[c['key']]=len(bad);bm.free()

# Reuse only the low-level geometry class definitions, never execute a build/reset.
module=ast.parse(Path(__file__).with_name('build.py').read_text(encoding='utf-8'))
keep=[n for n in module.body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in ('box_template','Builder')]
exec(compile(ast.Module(body=keep,type_ignores=[]),'geometry_primitives_only','exec'),globals())
CUBE_F=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)];CACHE={}
MATS=[bpy.data.materials[n] for n in ('SEA_Matte','SEA_Metal','SEA_Gloss')]
CELLS={c['name']:c for c in json.loads((R/P['palette']).with_suffix('.json').read_text(encoding='utf-8'))['cells']}
# Aligned module dimensions are frozen before replacement geometry is created.
for c in P['components']:
    if c['key'] in ('street_intact','street_split','junction','plaza_tile'):c['size_design_m']=[24,24,.8]
    elif c['key']=='canal_segment':c['size_design_m']=[24,24,2.2]
P['revision']='r2_aligned_floor_user_feedback_2026-11-05'
P['floor_contract']={'grid_m':24,'plane':'XY','base_z_m':-61.9,'paving_top_z_m':-61.3,'curb_top_z_m':-61.1,
    'seams':'exact shared 24m boundary, identity scale, yaw multiples of 90; cracks remain inside module',
    'ground_overlap_forbidden':True,'central_no_geometry':True}
old_plan_hash=hashlib.sha256((D/'component_plan.json').read_bytes()).hexdigest()
P['previous_plan_sha256']=old_plan_hash
arch_keys=[c['key'] for c in CAT if c['category']=='architecture']
ex=P['exclusions'];grid=[-108+24*i for i in range(10)]
def block(x,y,hx=12,hy=12):return any(x+hx>q['xy'][0]+1e-5 and x-hx<q['xy'][1]-1e-5 and y+hy>q['xy'][2]+1e-5 and y-hy<q['xy'][3]-1e-5 for q in ex)
# Every ground patch is one 24x24 component instance. Roads/canals occupy full tile domains, no overlays.
placements=[];tilemap={}
def put(key,x,y,z=-61.9,yaw=0):
    a=dict(instance_id=key+'_instance_'+str(sum(t['key']==key for t in placements)+1).zfill(3),key=key,position_m=[x,y,z],rotation_euler_deg=[0,0,yaw],scale=[1,1,1]);placements.append(a);return a
for x in grid:
    for y in grid:
        if block(x,y):continue
        horiz=y in (-84,84);vert=x in (-84,84)
        if horiz and vert:key='junction';yaw=0
        elif horiz or vert:key='street_split' if (int((x+108)/24)+int((y+108)/24))%5==0 else 'street_intact';yaw=90 if vert else 0
        else:key='plaza_tile';yaw=0
        if x==-60 and y in (-36,-12,12,36):key='canal_segment';yaw=90
        tilemap[(x,y)]=key;put(key,x,y,-63.3 if key=='canal_segment' else -61.9,yaw)
# Deterministic lots; each whole-building envelope fits one paving cell with a clear peripheral margin.
preferred=[
 ('coffee_steps',-108,-108,0),('slender_tower',-60,-108,0),('canal_shell',-12,-108,0),('roof_garden_shell',12,-108,0),('half_tower',60,-108,0),('terrace_residence',108,-108,0),
 ('cutaway_tenement',-108,108,180),('canal_housing',-60,108,180),('station_hall',-12,108,180),('balcony_tenement',12,108,180),('cinema_ruin',60,108,180),('terraced_tower',108,108,180),
 ('workshop_shell',-108,-60,90),('balcony_tenement',-108,-12,90),('tram_tenement',-108,12,90),('half_tower',-108,60,90),
 ('electronics_shop',108,12,270),('frame_construction',108,60,270),
 ('terraced_tower',-60,-60,0),('electronics_shop',-36,-60,0),('rounded_corner',-60,60,180),('frame_construction',-36,60,180),('canal_shell',-12,60,180),
 ('low_foundation',12,-60,0),('roof_garden_shell',36,-108,0),('workshop_shell',-36,108,180),('coffee_steps',-36,-108,0),('cutaway_tenement',-108,-36,90),
]
used=set()
for key,x,y,yaw in preferred:
    if tilemap.get((x,y))=='plaza_tile' and (x,y) not in used:
        put(key,x,y,-61.3,yaw);used.add((x,y))
# Ensure every architectural definition is present in the layout without forcing overlaps.
missing=[k for k in arch_keys if not any(a['key']==k for a in placements)]
for key in missing:
    candidates=[p for p,k in tilemap.items() if k=='plaza_tile' and p not in used]
    assert candidates,'No free lot for '+key
    x,y=candidates[0];put(key,x,y,-61.3);used.add((x,y))
# Elevated rail follows its own clear strip between the southern street and buildings.
for j,x in enumerate((-108,-88,-68)):put('viaduct_broken' if j==2 else 'viaduct_intact',x,-48,-61.3)
put('tram_wreck',-99,-48,-50.75);put('stair_link',-110,-38,-61.3,90)
# Vehicles and poles align to streets. No cable placed without a pair of matching pole sockets.
for i,(x,y) in enumerate([p for p,k in tilemap.items() if k in ('street_intact','street_split')]):
    horiz=y in (-84,84)
    if i%3==0:put('car_sedan' if i%2 else 'car_van',x,y,-61.3,90 if horiz else 0)
    if i%4==0:
        px,py=(x,y+8.6) if horiz else (x-8.6,y)
        put('street_lamp',px,py,-61.1,180 if horiz else 90)
    if i%5==0:
        px,py=(x-8,y-8.6) if horiz else (x+8.6,y-8)
        if not block(px,py,2,2):put('utility_pole' if i%2 else 'leaning_pole',px,py,-61.1)
for x,y in [(-84,-84),(-84,84),(84,84)]:
    if (x,y) in tilemap:put('traffic_light',x+8,y+8,-61.1,180)
for x,y,yaw in [(-105,-90,0),(-35,90,180),(-90,35,90)]:
    if not block(x,y,8,4):
        put('bus_shelter',x,y,-61.1,yaw);put('vending',x+4,y,-61.1,yaw);put('scooter',x-5,y,-61.1,yaw);put('sign_board',x+7,y,-61.1,yaw)
# Pole base height and cable end height agree; the 20m span is not stretched to fit.
for x,y in [(-54,-92),(-30,-92)]:
    if not block(x,y,11,2):
        for px in (x-10,x+10):put('utility_pole',px,y,-61.1)
        put('cable_span',x,y,-54.26)
# Independent, sparse ecological/structural remnants. Never scatter beyond the fence.
arch_instances=[a for a in placements if a['key'] in arch_keys]
for i,a in enumerate(arch_instances):
    x,y,_=a['position_m']
    if i%2==0:put('rubble_cluster',x+5,y+3,-61.3,(i*37)%360)
    put('moss_patch' if i%3 else 'kelp_clump',x-4,y+4,-61.28,(i*29)%360)
    if i%3==0:put('corrosion_patch',x,y-6.8,-56.2,a['rotation_euler_deg'][2])
P['instances']=placements
for c in P['components']:c['instance_count']=sum(a['key']==c['key'] for a in placements)
(D/'component_plan.json').write_text(json.dumps(P,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Rebuild ONLY the five floor definitions, already frozen above.
for key in ('street_intact','street_split','junction','plaza_tile','canal_segment'):
    c=next(c for c in CAT if c['key']==key);col=bpy.data.collections[c['collection']]
    old=[o for o in col.objects if o.type=='MESH']
    for o in old:bpy.data.objects.remove(o,do_unlink=True)
    B=Builder()
    if key=='plaza_tile':
        # Rectangular perimeter is unbroken. Joint grooves only subdivide the interior surface.
        B.box((0,0,.25),(24,24,.5),'stone')
        for ix in range(6):
            for iy in range(6):
                B.box((-10+4*ix,-10+4*iy,.55),(3.96,3.96,.1),'plaster' if (ix+iy)%5 else 'cloud',.02)
    elif key=='canal_segment':
        B.box((0,0,.15),(24,24,.3),'sage_gray')
        for yy in (-8.0,8.0):
            B.box((0,yy,1.0),(24,8,2),'plaster')
            for x in (-9,-3,3,9):B.box((x,yy,2.05),(5.96,7.96,.1),'stone',.02)
            # Exact shared wall end faces: no beyond-boundary rail/curb.
            B.box((0,yy+(-3.8 if yy>0 else 3.8),1.4),(24,.4,1.3),'plaster',.04)
    else:
        B.box((0,0,.3),(24,24,.6),'gray')
        if key!='junction':
            for yy in (-9,9):
                B.box((0,yy,.7),(24,6,.2),'stone')
                for x in (-9,-3,3,9):B.box((x,yy,.805),(5.97,5.97,.01),'plaster')
            for x in (-9,-3,3,9):B.box((x,0,.616),(3,.16,.03),'cream',.006)
        else:
            for xx in (-9,9):
                for yy in (-9,9):B.box((xx,yy,.7),(6,6,.2),'stone')
            for side in (-1,1):
                for t in (-4,-2,0,2,4):
                    B.box((side*7,t,.62),(2,.9,.035),'cream',.008)
                    B.box((t,side*7,.62),(.9,2,.035),'cream',.008)
        if key=='street_split':
            # Wide cracks only in asphalt centre; external tile boundary is untouched and aligned.
            B.tube([(-4,-5,.625),(-1,-2,.625),(-2,0,.625),(2,3,.625),(1,5,.625)],.045,'slate',0,4)
        for yy in (-8.7,8.7):B.box((7,yy,.83),(1.3,.8,.05),'steel',.015)
    obj=B.finish(c['name'],col);obj.parent=bpy.data.objects[c['root_object']]
    obj['asset_id']=c['component_id'];obj['building_class']='underwater';obj['collision']='none';obj['interactive']=False
    obj['source_only']=True;obj['emission']=False
# Replace layout instances, not geometry, with the revised orthogonal assembly.
for o in list(S.objects):
    if o.instance_type=='COLLECTION':bpy.data.objects.remove(o,do_unlink=True)
for a in placements:
    c=next(c for c in CAT if c['key']==a['key']);o=bpy.data.objects.new(a['instance_id'],None)
    o.instance_type='COLLECTION';o.instance_collection=bpy.data.collections[c['collection']]
    name='建筑_独立实例' if c['category']=='architecture' else '街道_逐段拼接实例' if c['category']=='ground' else '海藻青苔_独立可隐藏' if c['category']=='vegetation' else '设施车辆_独立实例'
    bpy.data.collections[name].objects.link(o);o.location=a['position_m'];o.rotation_euler=[math.radians(v) for v in a['rotation_euler_deg']]
    o['asset_id']=c['component_id'];o['building_class']='underwater';o['collision']='none';o['interactive']=False
for c in CAT:
    c.update(next(x for x in P['components'] if x['key']==c['key']))
    col=bpy.data.collections[c['collection']];mesh=next(o for o in col.objects if o.type=='MESH');mesh.data.calc_loop_triangles()
    pts=[v.co for v in mesh.data.vertices];lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
    # Keep bottom-center origin even for asymmetric canal details (these are symmetric by contract).
    shift=Vector(((lo[0]+hi[0])/2,(lo[1]+hi[1])/2,lo[2]))
    for v in mesh.data.vertices:v.co-=shift
    c.update(objects=[c['root_object'],mesh.name],bounds_size_m=[hi[i]-lo[i] for i in range(3)],triangles=len(mesh.data.loop_triangles),polygons=len(mesh.data.polygons))
(D/'component_catalog.json').write_text(json.dumps({'schema':'sea.component_catalog','components':CAT},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_instances.json').write_text(json.dumps({'schema':'sea.component_instances','coordinate_contract':P['coordinate_contract'],'floor_contract':P['floor_contract'],'instances':[dict(a,component_id=next(c['component_id'] for c in CAT if c['key']==a['key']),source_object=a['instance_id']) for a in placements]},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
S['plan_sha256']=hashlib.sha256((D/'component_plan.json').read_bytes()).hexdigest();S['floor_grid_m']=24
bpy.ops.wm.save_as_mainfile(filepath=str(W/'sunken_city_working.blend'),compress=True)
(W/'floor_revision.json').write_text(json.dumps({'removed_duplicate_faces':removed,'tiles':len(tilemap),'building_count':len(arch_instances),'instances':len(placements),'grid_m':24,'paving_top_m':-61.3},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('ALIGNED_FLOOR',len(tilemap),'tiles',len(arch_instances),'buildings',len(placements),'instances; duplicate faces removed',sum(removed.values()))
