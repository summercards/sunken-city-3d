import json, hashlib
from pathlib import Path
D = Path('D:/projects/sea/art_source/scenes/water_building_003/v001')
P = 'SEA-SCENE-WATER-BUILDING-003'
# key, group, kind, rho, family
SPECS = [
 ('deck','structure','shell',.015,'platform'),('wall_f1','structure','shell',.015,'wall'),('wall_f2','structure','shell',.015,'wall'),('wall_tower','structure','shell',.015,'wall'),
 ('slab_f2','structure','horizontal_cover',.02,'slab'),('slab_f3','structure','horizontal_cover',.02,'slab'),
 ('roof_low','structure','horizontal_cover',.03,'tile_roof'),('roof_mid','structure','horizontal_cover',.03,'tile_roof'),('roof_top','structure','horizontal_cover',.03,'flat_roof'),
 ('roof_rail','structure','vertical_structure',.03,'rail'),('step_stones','structure','shell',.02,'step'),
 ('door_main','furnishing','opening',.025,'door'),('window_f1','furnishing','opening',.025,'window'),('window_f2','furnishing','opening',.025,'window'),('window_tower','furnishing','opening',.025,'window'),('shutter_door','furnishing','opening',.025,'door'),
 ('balcony','furnishing','horizontal_cover',.025,'balcony'),('tower_ledge','furnishing','horizontal_cover',.025,'balcony'),('lean_to','furnishing','horizontal_cover',.03,'awning'),
 ('pipe','furnishing','linear',.06,'pipe'),('pole','furnishing','linear',.06,'pole'),
 ('wall_box','furnishing','flat_attached',.03,'cabinet'),('sign_plate','furnishing','flat_attached',.025,'sign'),
 ('rubble','furnishing','freestanding',-.06,'stone'),('clay_pot','furnishing','freestanding',-.06,'pot'),('crate','furnishing','freestanding',-.06,'crate'),
 ('trunk','plant','plant',0,'tree_trunk'),('crown_left','plant','plant',0,'canopy'),('crown_right','plant','plant',0,'canopy'),('moss_mound','plant','plant',0,'moss'),
 ('vine','plant','plant',0,'vine'),('flower','plant','plant',0,'flower'),('big_leaf','plant','plant',0,'leaf'),
]
plan = {'schema':'sea.component_plan','status':'frozen_before_geometry','asset_id':P,'display_number':'003','version':'v001',
 'building_class':'above_water','water_layer':'surface','water_layer_role':'entity','category':'通用海上建筑',
 'palette':'art_source/shared/palettes/sea_cabin_timber_8x8_512.png','reference_image':'reference.jpg',
 'reference_sha256':hashlib.sha256((D/'reference.jpg').read_bytes()).hexdigest(),
 'loaded_differences':['references/above-water.md'],
 'size_assumptions':{'method':'reference_pixel_measurement','ref_px_per_m':47.0,
   'calibration':'ground floor pitch 5.1 m == 240 px (floor y 840 -> floor-2 eave y 600); door 95x160 px -> 2.0x3.4 m, built 1.8x3.1 per skill',
   'ground_deck_top_m':0.3,'slab_thickness_m':0.2,'F1':{'footprint':[9.0,7.0],'center_x':0.25,'clear_m':4.9,'floor_z':0.3},
   'F2':{'footprint':[5.4,5.6],'center_xy':[-0.3,0.0],'clear_m':4.2,'floor_z':5.4},
   'F3_tower':{'footprint':[4.7,4.4],'center_xy':[0.4,0.0],'clear_m':3.6,'floor_z':9.8},
   'roof_top_z':13.7,'rail_top_z':14.7},
 'budget':{'target_triangles':16000,'max_triangles':20000,'bevel_segments':1,
   'preserve':['cream_cracked_plaster','blue_grey_trim','green_double_door','tile_skirt_roofs','tower_flat_roof_rail','gnarled_tree_trunk','left_canopy','right_canopy','utility_pole','stone_steps'],
   'omit':['photographic_weathering','ink_outlines','background_swoosh','3D_text']},
 'components':[{'key':k,'id':P+'-'+k.upper().replace('_','-'),'asset_id':P+'-'+k.upper().replace('_','-'),'group':g,'kind':kd,'rho':r,'family':f,
   'origin':'bottom_center','front_axis':'-Y','scope':'scene_local','source_version':'v001'} for k,g,kd,r,f in SPECS]}
(D/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(len(SPECS),'components', plan['reference_sha256'])
