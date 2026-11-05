"""r3: fill actual missing ground, city blocks instead of equal lots, settlement and structural collapse.
Runs only on this suite's live source. A checkpoint precedes changes; no existing game files touched.
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
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'))
CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components']
S=bpy.data.scenes['沉没旧城_完整参考布局_v001'];MA=bpy.data.collections['01_制作组件_单栋与街段']
checkpoint=W/'before_urban_r3.blend'
if not checkpoint.exists():bpy.ops.wm.save_as_mainfile(filepath=str(checkpoint),copy=True,compress=True)
# A geometry-only import. No global build code, no scene reset.
mod=ast.parse(Path(__file__).with_name('build.py').read_text(encoding='utf-8'))
keep=[n for n in mod.body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in ('box_template','Builder','text_shape','rail')]
exec(compile(ast.Module(body=keep,type_ignores=[]),'sunken_city_geometry_only','exec'),globals())
CUBE_F=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)];CACHE={}
MATS=[bpy.data.materials[n] for n in ('SEA_Matte','SEA_Metal','SEA_Gloss')]
CELLS={c['name']:c for c in json.loads((R/P['palette']).with_suffix('.json').read_text(encoding='utf-8'))['cells']}
bykey={c['key']:c for c in CAT}
# Freeze all genuinely new definitions before geometry, retaining the 50 component gate.
newdefs=[
 dict(key='collapsed_residence',name='倒塌住宅_断腰折落',category='architecture',component_family='collapsed_building',size_design_m=[24,30,18],collapse_state='mid_storey_fracture',floors=5,color='seafoam',damage=.85,style='folded_residence'),
 dict(key='fallen_hall',name='侧倒厂馆_残墙与翻转楼板',category='architecture',component_family='collapsed_building',size_design_m=[25,30,15],collapse_state='lateral_wall_failure',floors=3,color='plaster',damage=.9,style='fallen_hall'),
 dict(key='t_junction',name='丁字路口_连续人行道',category='ground',component_family='junction',size_design_m=[24,24,.8]),
 dict(key='canal_end',name='运河收口_桥面步道',category='ground',component_family='canal',size_design_m=[24,24,2.2]),
]
for n in newdefs:
    if n['key'] in bykey:continue
    c=dict(n,slug=n['key'],component_id='SEA-SCENE-SCITY-'+n['key'].replace('_','-').upper(),building_class='underwater',scope='scene_local',origin='bottom_center',front_axis='-Y',allowed_rotations_y_deg=[0,90,180,270],collision=False,interactive=False,emission=False,variant_axis='collapse_state' if n['category']=='architecture' else None,variant_value=n.get('collapse_state'),variant_reason='physically different collapse topology, no world-location geometry')
    P['components'].append(c)
P['component_budget']=dict(limit=50,planned=len(P['components']),remaining=50-len(P['components']))
assert len(P['components'])<=50
P['revision']='r3_user_fill_missing_city_logic_tilt_collapse'
P['exclusion_policy']={'central':'no new buildings; ground must be continuous and complete under existing buildings, as clarified by user 2026-11-05 13:53','existing_outer_facilities':'new buildings avoid projected footprints; new street foundation is below existing facilities, never omit the ground'}
P['floor_contract']['outer_extent_m']=[-120,120,-120,120]
P['floor_contract']['central_buildings_exclusion_m']=[-36,38,-44,34]
P['floor_contract'].pop('central_hole_m',None)
P['floor_contract']['expected_ground_tiles']=100
(D/'component_plan.json').write_text(json.dumps(P,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

# Store entire source material/UVs when reshaping a fallen building, not recolored approximations.
def transfer(source, predicate=lambda f:True, transform=Matrix.Identity(4), target=None):
    target=target or Builder();me=source.data;uv=me.uv_layers['PaletteUV']
    names={(c['column'],7-c['row']):n for n,c in CELLS.items()}
    for f in me.polygons:
        if not predicate(f):continue
        coords=[transform@me.vertices[i].co for i in f.vertices]
        u=uv.data[f.loop_start].uv;color=names[(int(u.x*8),int(u.y*8))]
        target.geo(coords,[tuple(range(len(coords)))],color,f.material_index,[f.use_smooth])
    return target

def add_component(c,b):
    col=bpy.data.collections.new(c['component_id']+'_'+c['name']);MA.children.link(col)
    o=b.finish(c['name'],col)
    root=bpy.data.objects.new(c['component_id']+'_ROOT',None);col.objects.link(root);o.parent=root
    for ob in (o,root):
        ob['asset_id']=c['component_id'];ob['building_class']='underwater';ob['collision']='none';ob['interactive']=False;ob['emission']=False
    root['front_axis']='-Y';col.instance_offset=(0,0,0)
    row=dict(c,collection=col.name,root_object=root.name,objects=[root.name,o.name],local_origin=[0,0,0],version='v001',
        component_blend=f'art_source/scenes/sunken_city/v001/component_packages/{c["key"]}/{c["key"]}.blend',
        palette=P['palette'],source_stage='source_authored_verification_pending',collision_owner='none_pure_scenery',dependencies=[])
    CAT.append(row);bykey[c['key']]=row
    return o
for key,sourcekey,fracture,angle in [('collapsed_residence','cutaway_tenement',10.5,math.radians(71)),('fallen_hall','cinema_ruin',5.5,math.radians(-82))]:
    if key in bykey:continue
    c=next(q for q in P['components'] if q['key']==key)
    source=next(o for o in bpy.data.collections[bykey[sourcekey]['collection']].objects if o.type=='MESH')
    # Keep a low jagged stump; detached upper structure rotated about a fracture line then brought to ground contact.
    lower=transfer(source,lambda f:f.center.z<fracture-.2)
    upper=transfer(source,lambda f:f.center.z>fracture+.45,Matrix.Translation((0,0,-fracture)))
    rot=Matrix.Rotation(angle,4,'X');pts=[rot@Vector(v) for v in upper.v]
    low=min(v.z for v in pts)
    # Detached chunk behind the remaining stump. Their concrete fragments bridge the fracture, never float.
    offset=Vector((.6,11.5 if key=='collapsed_residence' else -9.5,-low+.15))
    lower.geo([v+offset for v in pts],upper.f,'plaster')
    # Restore every source face's original palette and role to the appended part.
    n=len(lower.f)-len(upper.f);lower.colors[n:]=upper.colors;lower.roles[n:]=upper.roles;lower.smooth[n:]=upper.smooth
    for j in range(6):
        x=-4+j*1.6;lower.box((x,2.8+(j%2),.5+j%3*.2),(2.6,2.1,.5),'stone',.08,rot=(j*.1,.14,j*.4))
        lower.tube([(x,1.5,fracture-.5),(x+.3,3.4,fracture-1.7)],.045,'bark')
    add_component(c,lower)
for key in ('t_junction','canal_end'):
    if key in bykey:continue
    c=next(q for q in P['components'] if q['key']==key);B=Builder()
    if key=='t_junction':
        B.box((0,0,.3),(24,24,.6),'gray')
        B.box((0,9,.7),(24,6,.2),'stone')
        for xx in (-9,9):B.box((xx,-9,.7),(6,6,.2),'stone')
        for t in (-4,-2,0,2,4):B.box((t,-7,.62),(.9,2,.035),'cream',.008)
        for xx in (-9,9):B.box((xx,0,.62),(3,.15,.03),'cream',.006)
    else:
        B.box((0,0,.15),(24,24,.3),'sage_gray')
        B.box((-5.5,0,1.0),(13,24,2),'plaster')
        B.box((6.5,0,1.0),(11,24,2),'plaster')
        for yy in (-9,9):B.box((1,yy,1.1),(2,6,2.2),'stone')
    add_component(c,B)
# Remove duplicate surfaces by the same 1e-4 geometric tolerance as the independent verifier.
removed={}
for c in CAT:
    for ob in bpy.data.collections[c['collection']].objects:
        if ob.type!='MESH':continue
        bm=bmesh.new();bm.from_mesh(ob.data);seen=set();bad=[]
        for f in bm.faces:
            sig=tuple(sorted(tuple(round(v,4) for v in q.co) for q in f.verts))
            if sig in seen:bad.append(f)
            else:seen.add(sig)
        if bad:bmesh.ops.delete(bm,geom=bad,context='FACES_ONLY')
        bm.to_mesh(ob.data);bm.free();removed[c['key']]=len(bad)
# Break the uniform high diagonal cut on selected shells: coarse slab chunks and uneven parapet bites.
# Existing mesh remains editable; missing sectors are retained, not filled by false black panels.
for key in ('canal_shell','half_tower','workshop_shell','frame_construction'):
    c=bykey[key];o=next(ob for ob in bpy.data.collections[c['collection']].objects if ob.type=='MESH')
    me=o.data
    # Exposed free ends receive broad stepped shear displacement, not vertex-noise roughness.
    if not o.get('r3_jagged_fracture'):
        for v in me.vertices:
            if v.co.z>5.2 and v.co.x>1.8:
                level=int(v.co.z/5.1);v.co.x+=(-.45,.25,-.2)[level%3]
        o['r3_jagged_fracture']=True
# Remove black z-fighting cross seams: adjacent wall piers share corner cubes, duplicate face deletion above
# handles exact duplicates. Existing structural geometry and all facade colors remain otherwise unchanged.
for c in CAT:
    o=next(ob for ob in bpy.data.collections[c['collection']].objects if ob.type=='MESH')
    pts=[v.co for v in o.data.vertices];lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
    shift=Vector(((lo[0]+hi[0])/2,(lo[1]+hi[1])/2,lo[2]))
    for v in o.data.vertices:v.co-=shift
    o.data.update();o.data.calc_loop_triangles()
    c.update(bounds_size_m=[hi[i]-lo[i] for i in range(3)],triangles=len(o.data.loop_triangles),polygons=len(o.data.polygons),material_roles=sorted({o.data.materials[f.material_index].name for f in o.data.polygons}))

placements=[];grid=[-108+24*i for i in range(10)];tilemap={}
def put(key,x,y,z=-61.9,yaw=0,rx=0,ry=0,role=None,settle=False):
    a=dict(instance_id=f'{key}_instance_{sum(p["key"]==key for p in placements)+1:03}',key=key,position_m=[x,y,z],rotation_euler_deg=[rx,ry,yaw],scale=[1,1,1])
    if role:a['urban_role']=role
    if settle:a['ground_contact_required']=True
    placements.append(a);return a
for x in grid:
    for y in grid:
        # User 13:53 clarification: the centre excludes BUILDINGS only. All 100 ground domains remain.
        h=y in (-84,84);v=x in (-84,84)
        if h and v:key='junction';yaw=0
        elif h or v:key='street_split' if (int((x+108)/24)+int((y+108)/24))%7==0 else 'street_intact';yaw=90 if v else 0
        else:key='plaza_tile';yaw=0
        if x==-60 and y in (-36,-12,12,36):key='canal_segment';yaw=90
        if x==-60 and y in (-60,60):key='canal_end';yaw=90 if y==-60 else 270
        tilemap[(x,y)]=key
        put(key,x,y,-63.4 if key in ('canal_segment','canal_end') else -61.9,yaw,role='aligned_ground_domain')
assert len(tilemap)==100
# Urban plan: commercial frontage on south boulevard, dense mixed blocks to west, broad civic courts to north.
# Every coordinate follows a street frontage/court/access purpose; no jittered checkerboard.
lots=[
 # Southern retail ribbon, interrupted by a collapsed block and access court.
 ('coffee_steps',-107,-103,0,0,0,'south_boulevard_coffee_corner'),
 ('electronics_shop',-89,-106,0,0,0,'attached_shopping_frontage'),
 ('roof_garden_shell',-28,-103,0,0,0,'shop_with_rooftop_greenhouse'),
 ('terrace_residence',-7,-106,0,0,0,'setback_stair_residence'),
 ('collapsed_residence',25,-104,180,0,0,'collapsed_lowrise_empty_plot'),
 ('canal_shell',64,-104,0,0,0,'half_building_after_collapse'),
 ('cinema_ruin',101,-104,0,0,0,'cinema_plaza_facing_boulevard'),
 # Southwest high-rise set back from smaller shops, not evenly alternating heights.
 ('slender_tower',-58,-100,0,0,-5,'rear_tower_settlement'),
 ('balcony_tenement',-108,-61,90,0,0,'west_residential_frontage'),
 ('tram_tenement',-110,-34,90,-3,0,'tram_station_housing'),
 ('cutaway_tenement',-107,-6,90,0,0,'collapsed_courtyard_edge'),
 ('workshop_shell',-106,52,90,0,0,'western_industrial_yard'),
 ('fallen_hall',-105,24,0,0,0,'fallen_factory_grounded'),
 # Western canal: towers at street nodes, low courts and half structures between.
 ('terraced_tower',-58,-59,180,0,0,'canal_south_anchor'),
 ('canal_housing',-53,55,180,0,0,'canal_north_housing'),
 ('canal_shell',-58,7,90,0,0,'canal_partial_shell'),
 # Northern civic row with forecourt gaps, backed by tall housing in one group.
 ('station_hall',-101,102,180,0,0,'station_court'),
 ('rounded_corner',-70,105,180,0,0,'corner_department_frontage'),
 ('terrace_residence',-47,102,180,0,0,'north_lane_residence'),
 ('frame_construction',-18,106,180,0,0,'unfinished_block'),
 ('half_tower',9,103,180,5,0,'leaning_fractured_block'),
 ('terraced_tower',45,105,180,0,0,'northern_tower_cluster'),
 ('slender_tower',66,105,180,0,0,'northern_tower_cluster'),
 ('low_foundation',101,105,180,0,0,'demolished_corner_lot'),
 # Eastern ribbon and old workshop courts, leaving existing ranch and floating shop undisturbed.
 ('roof_garden_shell',107,68,270,0,0,'east_lane_low_shop'),
 ('electronics_shop',108,8,270,0,0,'eastern_retail_node'),
 ('balcony_tenement',107,34,270,0,6,'tilted_residential_settlement'),
 ('workshop_shell',109,-17,270,0,0,'east_service_court'),
 ('half_tower',108,-65,270,0,-7,'leaning_tower_away_from_home'),
 ('low_foundation',11,-62,0,0,0,'southern_clearance_court'),
 ('cutaway_tenement',-18,-62,0,0,0,'south_lane_exposed_rooms'),
]
for key,x,y,yaw,rx,ry,role in lots:put(key,x,y,-61.3,yaw,rx,ry,role,True)
# Independent track components form one continuous run and a broken end in the industrial court.
for j,x in enumerate((-108,-88,-68)):put('viaduct_broken' if j==2 else 'viaduct_intact',x,-48,-61.3,role='tram_branch')
put('tram_wreck',-96,-48,-50.75,rx=-3,role='wreck_on_tracks')
put('stair_link',-109,-36,-61.3,90,role='station_stair_access')
# Street services inhabit curbs and transport nodes instead of a repeating lamp-car-pole pattern per tile.
for i,(x,y,yaw) in enumerate([(-100,-84,90),(-47,-84,86),(2,-84,90),(59,-84,94),(99,-84,90),(-84,-58,-3),(-84,9,8),(-84,67,0),(-28,84,90),(29,84,90),(94,84,80),(84,-35,3),(84,30,-5)]):
    put('car_van' if i in (1,7,10) else 'car_sedan',x,y,-61.3,yaw,role='abandoned_traffic')
for x,y,yaw in [(-107,-91,0),(-27,-92,0),(-92,46,90),(101,91,180)]:
    put('bus_shelter',x,y,-61.1,yaw,role='transit_node');put('vending',x+4,y,-61.1,yaw);put('scooter',x-5,y,-61.1,yaw)
for x,y,yaw in [(-76,-77,0),(-76,76,90),(76,76,180),(76,-76,270)]:
    put('traffic_light',x,y,-61.1,yaw);put('sign_board',x+4,y+2,-61.1,yaw)
for i,(x,y,yaw) in enumerate([(-112,-91,0),(-62,-91,0),(-12,-91,0),(38,-91,0),(103,-91,0),(-92,-42,90),(-92,14,90),(-92,73,90),(-55,92,180),(13,92,180),(69,92,180),(92,47,270),(92,-7,270),(92,-63,270)]):
    put('street_lamp',x,y,-61.1,yaw)
for i,(x,y) in enumerate([(-105,-77),(-85,-77),(-65,-77),(-13,-77),(7,-77),(27,-77),(-78,32),(-78,52),(-78,72)]):
    put('leaning_pole' if i in (2,6) else 'utility_pole',x,y,-61.1)
for x,y in [(-95,-77),(-3,-77),(17,-77)]:put('cable_span',x,y,-54.26)
# Broad chunks concentrate at collapse sites; sparse seaweed and corrosion is independent of buildings.
for i,a in enumerate([a for a in placements if a['key'] in {c['key'] for c in CAT if c['category']=='architecture'}]):
    x,y,_=a['position_m']
    dx=4 if x<100 else -4;dy=5 if y<100 else -5
    if i%3!=0:put('rubble_cluster',x+dx,y+dy,-61.3,(i*41)%360)
    put('kelp_clump' if i%4==0 else 'moss_patch',x-dx,y+dy,-61.27,(i*29)%360)
    if i%4==0:put('corrosion_patch',x,y-6.8,-55.6,a['rotation_euler_deg'][2])
# Delete only current layout instances. Component geometry remains independent and editable.
for o in list(S.objects):
    if o.instance_type=='COLLECTION':bpy.data.objects.remove(o,do_unlink=True)
instance_rows=[];contact=[]
for a in placements:
    c=bykey[a['key']];o=bpy.data.objects.new(a['instance_id'],None);o.instance_type='COLLECTION';o.instance_collection=bpy.data.collections[c['collection']]
    name='建筑_独立实例' if c['category']=='architecture' else '街道_逐段拼接实例' if c['category']=='ground' else '海藻青苔_独立可隐藏' if c['category']=='vegetation' else '设施车辆_独立实例'
    bpy.data.collections[name].objects.link(o);o.location=a['position_m'];o.rotation_euler=[math.radians(v) for v in a['rotation_euler_deg']]
    if a.get('ground_contact_required'):
        rot=o.rotation_euler.to_matrix();mesh=next(q for q in o.instance_collection.objects if q.type=='MESH')
        low=min((rot@v.co).z for v in mesh.data.vertices);o.location.z=-61.3-low
        a['position_m'][2]=o.location.z;contact.append(dict(instance=o.name,world_bottom_m=-61.3,tilt_deg=a['rotation_euler_deg'][:2]))
    o['asset_id']=c['component_id'];o['building_class']='underwater';o['collision']='none';o['interactive']=False
    if a.get('urban_role'):o['urban_role']=a['urban_role']
    instance_rows.append(dict(a,component_id=c['component_id'],source_object=o.name))
# Persist exact final transforms to the instance contract, not invented catalogue positions.
P['instances']=placements
for c in CAT:
    c['instance_count']=sum(a['key']==c['key'] for a in placements)
    pc=next(q for q in P['components'] if q['key']==c['key']);pc['instance_count']=c['instance_count']
P['urban_contract']={'blocks':['south commercial boulevard','west canal tenements and tram workshop','north civic courts and clustered highrises','east service street'],
 'spacing':'frontage strips, setbacks, pairs and collapse gaps; not one-building-per-floor-tile',
 'collapse':'two separate whole-building component definitions containing upright stump and ground-contact rotated upper chunk',
 'tilt':'five selected settlement instances, rigid geometry, full Euler saved, lowest world vertex set to paving top'}
(D/'component_plan.json').write_text(json.dumps(P,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_catalog.json').write_text(json.dumps({'schema':'sea.component_catalog','components':CAT},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_instances.json').write_text(json.dumps({'schema':'sea.component_instances','coordinate_contract':P['coordinate_contract'],'floor_contract':P['floor_contract'],'instances':instance_rows},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_tree.txt').write_text('\n'.join(c['component_id']+' '+c['name']+' -> component_packages/'+c['key'] for c in CAT)+'\n',encoding='utf-8')
S['plan_sha256']=hashlib.sha256((D/'component_plan.json').read_bytes()).hexdigest();S['floor_grid_m']=24
# Full scene used to crop at the sides. Increase fixed whole-scene framing once, then freeze for r3 comparison.
for n in ('相机_全景_固定','相机_建筑分离'):bpy.data.objects[n].data.ortho_scale=365
S.render.resolution_x=1800;S.render.resolution_y=1600
bpy.ops.wm.save_as_mainfile(filepath=str(W/'sunken_city_working.blend'),compress=True)
(W/'urban_revision.json').write_text(json.dumps({'components':len(CAT),'tiles':len(tilemap),'building_count':len(lots),'instances':len(placements),'ground_contacts':contact,'removed_duplicate_faces':removed},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('URBAN_R3',len(CAT),'components',len(tilemap),'ground tiles',len(lots),'buildings',len(placements),'instances')
