"""Freeze source-only sunken_city plan before any Blender geometry exists."""
from pathlib import Path
import hashlib
import json
import os

R = Path(__file__).resolve().parents[3]
D = R / 'art_source/scenes/sunken_city/v001'
W = Path(os.environ.get('SEA_WORK_ROOT', R.parent / 'sea-work')) / 'sunken_city/v001'
PAL = R / 'art_source/shared/palettes/sea_cabin_timber_8x8_512.png'
assert D.is_dir() and W.is_dir()
assert not (D / 'sunken_city_v001.blend').exists(), 'Plan cannot be retroactively frozen'
refs = [
 ('clipboard-2026-11-05T03-48-23-836Z-f3a8d931.jpg', 'warm layered tram street, balconies, rooftop tanks, arch and stairs'),
 ('clipboard-2026-11-05T03-48-23-837Z-a503716e.jpg', 'varied district silhouettes and streets, not active neon'),
 ('clipboard-2026-11-05T03-48-23-839Z-576a8cdc.jpg', 'coffee/electronics shops, exterior stair, rooftop greenhouse, vending and scooter'),
 ('clipboard-2026-11-05T03-48-23-840Z-36af0fc0.jpg', 'light concrete canal canyon, inset windows, roof services and articulated pavement'),
 ('clipboard-2026-11-05T03-48-23-840Z-be2c322c.jpg', '240 m fenced area'),
 ('clipboard-2026-11-05T03-48-23-841Z-86ebbb38.jpg', 'depth estimate using existing 60 m rooftop ranch'),
 ('clipboard-2026-11-05T03-48-23-842Z-80832552.jpg', 'central no-build zone'),
]
components = []
def add(key, name, kind, family, size, **kw):
    components.append(dict(key=key, slug=key, name=name, category=kind, component_family=family,
        component_id='SEA-SCENE-SCITY-' + key.replace('_', '-').upper(),
        building_class='underwater', scope='scene_local', origin='bottom_center', front_axis='-Y',
        allowed_rotations_y_deg=[0, 90, 180, 270], size_design_m=size,
        collision=False, interactive=False, emission=False, **kw))

# Every building is one independent semantic component, including its fixed facade/roof attachments.
buildings = [
 ('coffee_steps', '梯巷咖啡楼_断顶', 'stepped_shop', [18,16,25], 4, 'red', .26, 'coffee'),
 ('electronics_shop', '旧电器商店_半边楼', 'stepped_shop', [15,14,19], 3, 'seafoam', .50, 'electronics'),
 ('terrace_residence', '错层露台公寓_侵蚀', 'stepped_shop', [18,16,34], 6, 'plaster', .22, 'terrace'),
 ('tram_tenement', '电车街连廊公寓_残缺', 'tenement', [18,14,43], 8, 'mint_white', .30, 'tram'),
 ('balcony_tenement', '阳台住宅_斜向塌顶', 'tenement', [16,14,38], 7, 'seafoam', .43, 'balcony'),
 ('cutaway_tenement', '半栋住宅_楼层剖露', 'tenement', [17,14,30], 6, 'plaster', .63, 'cutaway'),
 ('slender_tower', '竖窗高楼_局部崩角', 'tower', [14,14,59], 11, 'white', .18, 'slender'),
 ('terraced_tower', '退台高楼_破顶机房', 'tower', [18,16,54], 10, 'plaster', .34, 'tower_terrace'),
 ('half_tower', '高楼半骸_外露柱架', 'tower', [16,15,43], 8, 'mint_white', .65, 'half_tower'),
 ('canal_housing', '运河侧白楼_阶梯屋顶', 'canal_housing', [18,16,39], 7, 'cloud', .23, 'canal'),
 ('canal_shell', '运河街断墙_半栋遗址', 'canal_housing', [17,16,23], 5, 'white', .72, 'canal_shell'),
 ('rounded_corner', '弧角百货楼_掉角', 'retail_corner', [18,16,34], 6, 'seafoam', .33, 'corner'),
 ('cinema_ruin', '旧影院_残破招牌', 'civic', [20,16,19], 3, 'plaster', .55, 'cinema'),
 ('station_hall', '电车候车馆_坍塌拱厅', 'civic', [20,17,21], 4, 'stone', .62, 'station'),
 ('workshop_shell', '旧维修厂_锯齿断顶', 'workshop', [20,17,14], 2, 'sage_gray', .68, 'workshop'),
 ('frame_construction', '停工楼架_缺层', 'construction', [18,16,35], 6, 'cloud', .73, 'frame'),
 ('roof_garden_shell', '屋顶温室楼_破碎玻璃架', 'greenhouse_building', [17,16,24], 4, 'red', .38, 'greenhouse'),
 ('low_foundation', '半层残楼_基础遗址', 'foundation', [17,16,8], 1, 'stone', .84, 'foundation'),
]
for key,name,family,size,floors,color,damage,style in buildings:
    add(key,name,'architecture',family,size,floors=floors,color=color,damage=damage,style=style,
        variant_axis='structure_damage',variant_value=style,
        variant_reason='distinct height, cut silhouette and original building function; not location')
for key,name,size,fam in [
 ('street_intact','车行街段_带两侧路沿',[20,12,.6],'street'),
 ('street_split','开裂街段_错位断板',[20,12,.6],'street'),
 ('junction','十字路口_斑马线',[12,12,.6],'junction'),
 ('canal_segment','下沉运河_两岸步道',[20,16,2.0],'canal'),
 ('plaza_tile','旧铺砖广场_局部缺角',[20,20,.5],'plaza'),
 ('viaduct_intact','高架轨道_完整跨段',[20,9,11.1],'viaduct'),
 ('viaduct_broken','高架轨道_断裂跨段',[20,9,11.1],'viaduct'),
 ('stair_link','高架长梯_断侧扶栏',[4,14,10.8],'stair'),
]: add(key,name,'ground',fam,size)
for key,name,fam,size in [
 ('car_sedan','废弃轿车_压瘪车顶','vehicle',[4.8,2.2,1.7]),
 ('car_van','旧厢车_车门脱落','vehicle',[5.7,2.5,2.7]),
 ('tram_wreck','旧电车_断窗侧倾','tram',[12,3.8,5.4]),
 ('scooter','旧踏板车_沉没','scooter',[2.2,1,1.7]),
 ('utility_pole','电线杆_锈蚀横担','power',[1.8,1.0,10]),
 ('leaning_pole','断杆_折落横担','power',[3.1,1.2,6.8]),
 ('cable_span','三根下垂电线_20米','cable',[20,.9,2.6]),
 ('street_lamp','旧路灯_熄灭','lamp',[3.4,1,7.3]),
 ('traffic_light','红绿灯_熄灭掉罩','signal',[2.6,1,5.8]),
 ('vending','旧饮料售货机','vending',[1.4,1.1,2.7]),
 ('bus_shelter','候车亭_缺顶板','shelter',[6,2.5,3.4]),
 ('sign_board','旧街道导向牌','sign',[4.4,1,4.5]),
 ('rubble_cluster','大块楼板残骸_露筋','rubble',[6.5,5,2.5]),
 ('corrosion_patch','侵蚀剥落块_硬表面','corrosion',[3.4,.1,2.0]),
 ('moss_patch','攀附海藻苔片_独立','vegetation',[3.2,2.4,.45]),
 ('kelp_clump','宽叶海藻簇_独立','vegetation',[2.8,2.8,3.4]),
]: add(key,name,'vegetation' if fam=='vegetation' else 'facilities',fam,size)
assert len(components) <= 50
# Layout footprints are planned at authored size, never nonuniform-scaled.
placements=[]
def place(key,x,y,z=-61.9,yaw=0,**kw):
    placements.append(dict(instance_id=f'{key}_instance_{sum(a["key"]==key for a in placements)+1:03}',
        key=key,position_m=[x,y,z],rotation_euler_deg=[0,0,yaw],scale=[1,1,1],**kw))
# Protected existing installations, in Blender world XY (= Godot X,-Z).
exclusions=[
 dict(id='central_user_red_box',xy=[-36,38,-44,34],reason='conservative screenshot-derived no-build area, entire geometry excluded'),
 dict(id='existing_rooftop_ranch',xy=[18,76,30,76],reason='current main.tscn 46,-55.92,-52 with measured 49.6x33.6 footprint plus clearance'),
 dict(id='existing_floating_shop',xy=[44,99,-73,-22],reason='current main.tscn edited transform, conservative XY footprint'),
 dict(id='existing_station',xy=[-53,-8,3,36],reason='existing Zone2 station footprint, conservative clearance'),
]
def blocked(x,y,hx=12,hy=12):
    return any(x+hx>q['xy'][0] and x-hx<q['xy'][1] and y+hy>q['xy'][2] and y-hy<q['xy'][3] for q in exclusions)
# Four neighbourhood ribbons, not a uniform filled grid.
row_keys=[
 ['coffee_steps','slender_tower','canal_shell','roof_garden_shell','half_tower','low_foundation','terrace_residence'],
 ['cutaway_tenement','canal_housing','station_hall','balcony_tenement','cinema_ruin','terraced_tower','workshop_shell'],
]
for row,y in enumerate((-95,95)):
    for j,x in enumerate((-96,-65,-34,0,34,65,96)):
        if not blocked(x,y): place(row_keys[row][j],x,y,yaw=0 if row==0 else 180)
for side,x in enumerate((-96,96)):
    keys=['workshop_shell','balcony_tenement','tram_tenement','half_tower','electronics_shop','frame_construction']
    for j,y in enumerate((-62,-31,0,31,62)):
        if not blocked(x,y,11,12):place(keys[(j+side)%len(keys)],x,y,yaw=90 if side==0 else 270)
for key,x,y,yaw in [
 ('terraced_tower',-65,-62,0),('electronics_shop',-34,-65,10),('canal_housing',1,-78,0),
 ('low_foundation',34,-95,0),('coffee_steps',-65,-30,90),('cutaway_tenement',-65,1,90),
 ('rounded_corner',-62,55,180),('frame_construction',-28,65,0),('cinema_ruin',2,91,180),
 ('canal_shell',4,62,180),('slender_tower',96,62,180),('roof_garden_shell',70,-95,0),
 ('workshop_shell',-96,-96,0)]:
    if not blocked(x,y):
        # Avoid colliding deliberately sparse ribbons, checked again against true mesh envelopes later.
        if not any(abs(a['position_m'][0]-x)<22 and abs(a['position_m'][1]-y)<23 for a in placements):place(key,x,y,yaw=yaw)
# Continuous outer streets: 20 m blocks plus 12 m intersection domains.
for y in (-76,76):
    for x in (-90,-70,-50,-30,-10,10,30,50,70,90):
        if not blocked(x,y,10,6):place('street_split' if (int(x)+int(y))%3==0 else 'street_intact',x,y)
for x in (-76,76):
    for y in (-66,-46,-26,-6,14,34,54,74):
        if not blocked(x,y,6,10):place('street_intact' if y%3 else 'street_split',x,y,yaw=90)
# Independent canal modules and civic plaza, all outside the protected centre.
for y in (-52,-32,-12,8,28,48):
    if not blocked(-48,y,8,10):place('canal_segment',-48,y,-63.5,90)
for x,y in ((-18,50),(-18,72),(94,-12),(-94,18)):
    if not blocked(x,y,10,10):place('plaza_tile',x,y)
# A broken elevated tram line, and one offset stair access. Tracks are support components, never fused to buildings.
for j,x in enumerate((-90,-70,-50)):
    place('viaduct_broken' if j==2 else 'viaduct_intact',x,-49)
place('tram_wreck',-78,-49,-51.35)
place('stair_link',-99,-43,-61.9,90)
# Street dress with different directions, rusted vehicles and broken power infrastructure.
for i,x in enumerate((-88,-64,-40,-16,16,40,64,88)):
    y=-76 if i%2==0 else 76
    if not blocked(x,y,5,5):
        place('car_sedan' if i%3 else 'car_van',x,y,-61.28,yaw=90+(7 if i%2 else -4))
        if not blocked(x,y+7.5,2,2):place('utility_pole' if i%3 else 'leaning_pole',x,y+7.5,-61.3)
        if not blocked(x+6,y-7,2,2):place('street_lamp',x+6,y-7,-61.3,yaw=180)
for y in (-58,-18,22,62):
    if not blocked(-76,y,5,4):
        place('car_sedan',-76,y,-61.3,yaw=13)
        place('utility_pole',-83,y,-61.3)
        place('traffic_light',-69,y,-61.3,90)
for x,y,rot in ((-62,-83,0),(-42,83,180),(-104,-22,90),(-23,83,180)):
    if not blocked(x,y,4,4):
        place('bus_shelter',x,y,-61.3,rot)
        place('vending',x-4,y,-61.3,rot)
        place('scooter',x+4,y-1,-61.3,rot)
        place('sign_board',x+5,y+2,-61.3,rot)
for x,y in ((-78,-68),(-54,83),(22,83)):
    if not blocked(x,y,10,1):place('cable_span',x,y,-53.4)
# Separate natural encrustation and structural debris, never part of an unrelated host mesh.
building_placements=list(placements[:sum(a['category']=='architecture' for a in components)*4])
arch_keys={a['key'] for a in components if a['category']=='architecture'}
for i,a in enumerate([q for q in placements if q['key'] in arch_keys]):
    x,y,z=a['position_m']
    if not blocked(x+6,y+5,4,3):place('rubble_cluster',x+6,y+5,-61.65,yaw=(i*37)%360)
    if not blocked(x-5,y+4,3,3):place('kelp_clump' if i%3==0 else 'moss_patch',x-5,y+4,-61.35,yaw=i*23%360)
    # Vertical patches form independently removable biofouling, on selected surviving walls.
    if i%2==0:
        place('corrosion_patch',x,y-7.15,-55.7,yaw=a['rotation_euler_deg'][2])
for c in components:
    c['instance_count']=sum(a['key']==c['key'] for a in placements)
# All planned geometry must be discoverable even when not used in the layout.
P=dict(schema='sea.sunken_city.component_plan',version='v001',status='frozen_before_geometry',
    suite='sunken_city',feature_id='SEA-ASSET',design_clause='SEA-ASSET-R50',
    references=[dict(local_path=str(Path.home()/'.workbuddy/clipboard-images'/f),sha256=hashlib.sha256((Path.home()/'.workbuddy/clipboard-images'/f).read_bytes()).hexdigest(),role=role) for f,role in refs],
    palette=str(PAL.relative_to(R)).replace('\\','/'),palette_sha256=hashlib.sha256(PAL.read_bytes()).hexdigest(),
    component_budget=dict(limit=50,planned=len(components),remaining=50-len(components)),
    coordinate_contract=dict(blender_plane='XY',blender_up='+Z',godot_mapping='(x,y,z)->(x,z,-y)',
        world_frame_translation_m=[0,0,0],water_level_m=1.12,street_base_z_m=-61.9,
        depth_from_water_m=63.02,depth_source='screenshot #6 calibrated with current rooftop_ranch 60m building; estimate +/-5m, not exact screenshot metadata',
        boundary_xy_m=[-120,120,-120,120]),
    scale_contract=dict(storey_m=5.1,clear_height_m=4.9,column_m=.5,slab_m=.2,bevel_segments=3,
        source='.agents/skills/sea-scene-component-authoring/SKILL.md',exception=None),
    exclusions=exclusions,
    scope=dict(source_only=True,modify_godot=False,animals=False,background=False,
        collision=False,navigation=False,walk_surface=False,interaction=False,emission=False),
    visual_contract=dict(primary='warm ivory, pale mint/blue, coral terracotta and restrained honey yellow',
        damage='large missing floor sectors, exposed interiors/rebar, irregular roof profiles and separate rubble; no uniform noise holes',
        references_policy='retain architecture/style/features, switch inhabited lights/green planting to abandoned underwater material; no animals/background'),
    components=components,instances=placements)
(D/'component_plan.json').write_text(json.dumps(P,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('FROZEN',len(components),'components',len(placements),'instances',sum(a['key'] in arch_keys for a in placements),'buildings')
