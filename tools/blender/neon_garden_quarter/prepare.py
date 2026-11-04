"""Freeze the reference-led component plan before authoring any meshes."""
from pathlib import Path
import hashlib, json, os
R=Path(__file__).resolve().parents[3]
D=R/'art_source/scenes/neon_garden_quarter/v001'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def put(p,x):p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
rows=[
('street_deck','连续街巷平台','architecture','platform'),
('left_storey','左侧店屋标准层','architecture','storey'),
('back_storey','后街农园楼标准层','architecture','storey'),
('round_storey','右侧圆角酒楼标准层','architecture','storey'),
('roof_room','完整屋顶楼梯间','architecture','rooftop'),
('parapet','完整圆角女儿墙','architecture','parapet'),
('broken_parapet','大块断裂女儿墙','architecture','parapet'),
('rubble','大块混凝土残片','architecture','damage'),
('wall_scar','成片剥落与宽裂缝','architecture','damage'),
('stair_flight','实体折返楼梯梯段','architecture','stair'),
('stair_landing','楼梯转角平台','architecture','stair'),
('guardrail','厚实通道栏杆','fixtures','rail'),
('double_door','双扇店门','fixtures','door'),
('window_pair','凹窗双联窗','fixtures','window'),
('window_broken','破损缺角双联窗','fixtures','window'),
('arc_window','转角连续弧形窗','fixtures','window'),
('round_balcony','屋顶圆弧阳台','architecture','balcony'),
('shop_awning','暖色店铺雨棚','fixtures','awning'),
('aircon','厚边空调外机','fixtures','utility'),
('water_tank','屋顶圆柱水箱','fixtures','utility'),
('drainpipe','粗排水管','fixtures','utility'),
('street_lamp','弯臂街灯','fixtures','lighting'),
('lantern','饱满旧灯笼','fixtures','lighting'),
('bar_poster','BAR PSY艺术招贴','signage','art_advert'),
('portrait_poster','怀旧人像招贴','signage','art_advert'),
('drink_poster','复古饮料广告','signage','art_advert'),
('charcoal_sign','弧面炭火广告大牌','signage','shop_identity'),
('tavern_sign','海道酒场厚字招牌','signage','shop_identity'),
('restaurant_neon','餐厅饱满立体霓虹字','signage','shop_identity'),
('route_board','钏路方形路牌','signage','wayfinding'),
('menu_board','黑底粉笔菜单','signage','menu'),
('round_sign','69圆形吊牌','signage','wayfinding'),
('small_placard','小店招贴牌','signage','menu'),
('trellis','屋顶番茄粗竹支架','fixtures','garden_support'),
('crop_bed','带土菜畦','fixtures','garden_support'),
('planter','长条花箱','fixtures','garden_support'),
('cabbage','饱满卷叶甘蓝','plants','crop'),
('tomato','结果番茄植株','plants','crop'),
('herb','圆叶蔬菜簇','plants','crop'),
('broadleaf','宽叶观赏草','plants','foliage'),
('vine','成串宽叶藤蔓','plants','climbing'),
('hanging_bush','垂挂灌木团','plants','climbing'),
('flowers','粉白成簇花朵','plants','flower'),
('grass','饱满长叶草簇','plants','foliage'),
('roof_soil','农园屋顶土坪','architecture','garden_roof'),
('utility_cable','粗电缆及墙支架','fixtures','service'),
]
items=[]
for i,(key,name,category,family) in enumerate(rows,1):
 items.append(dict(key=key,name=name,asset_id=f'SEA-SCENE-NGQ-{i:03}',category=category,family=family,building_class=None if category=='plants' else 'above_water',origin='bottom_center',front_axis='-Y',triangle_budget=65000 if 'sign' in key or 'neon' in key else 18000,collection=f'NGQ_{i:02}_{name}',scope='scene_local'))
plan=dict(schema='sea.component_plan',suite='neon_garden_quarter',version='v001',feature_id='SEA-ASSET',requirement='SEA-ASSET-R44',status='frozen_before_geometry',building_class='above_water',branch='.agents/skills/sea-scene-component-authoring/references/above-water.md',reference='reference/user_reference.png',reference_sha256=sha(D/'reference/user_reference.png'),palette='art_source/shared/palettes/sea_cabin_timber_8x8_512.png',palette_sha256=sha(R/'art_source/shared/palettes/sea_cabin_timber_8x8_512.png'),dimensions=dict(storey_m=5.1,slab_m=.2,column_m=.5,door_outer_m=[1.8,3.1],street_clear_width_m=7.0,deck_top_m=.3),components=items,assembly_asset_id='SEA-SCENE-NGQ-ASSEMBLY',texture_asset_id='SEA-SCENE-NGQ-POSTER-ATLAS',exclusions=['water','human_meshes','animals','corals_as_animals'],invisible_completion=['rear_facades','side_facades','roof_parapets','rooftop_service_rooms','stairs','roof_services'],damage_rule='few broad missing sections and large rubble; no micro shards',material_exception=dict(reason='user explicitly requires image-2 recreation of poster paintings',roles=['SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission'],poster_uv='PosterUV used only by designated printed surfaces; PaletteUV remains active and valid',poster_mask='named mesh float attribute PosterMask',atlas='textures/poster_atlas.png'),runtime_status='pending_not_requested',reference_license='pending_user_supplied_reference')
assert len(items)<=50
from collections import Counter
assert max(Counter(x['family'] for x in items).values())<=3
put(D/'component_plan.json',plan)
prompt='''Use case: ads-marketing. Asset type: ONE flat print-texture atlas for a stylized 3D architectural reconstruction. Input image is the visual reference, not the output scene. Extract and lovingly reconstruct ONLY its retro Japanese alley advertising paintings, removing water tint, plants, frames, perspective, reflections, characters swimming or gardening, buildings and all scenery. Output exactly a 2048x2048 flat atlas divided into 4 equal columns and 2 equal rows, eight fully filled 512x1024 portrait rectangles. No gaps, no borders between tiles, no labels, each card fills its cell to all edges. Reading order left-to-right, top-to-bottom: 1 black forest-green BAR PSY art-nouveau poster with a cream surreal diving-mask botanical illustration and large BAR PSY letters, 2 vintage illustrated serious young Japanese man's face, dark teal hair, warm ivory face, old cream paper, Japanese typographic accents, 3 muted yellow-green retro soft drink ad with illustrated smiling short-haired woman and bottles, 4 rich burnt-orange charcoal-grill poster with bold creamy Japanese 炭火 lettering, 5 aged ivory route/restaurant placard with bold black 釧路 and red seal and geometric symbols, 6 charcoal-green handwritten menu with cream and mint Japanese writing and simple bowl illustration, 7 deep teal round 69 logo centered on an ivory background with tiny retro letters, 8 ivory and coral neighborhood shop placard with a little flower emblem and bold green Japanese text. Match the source illustration's hand-painted nostalgic charm and clear graphic layout. Restore readable large lettering and economical secondary shapes. Palette warm cream, sage green, deep teal, brick orange, faded coral. No blue underwater overlay, no glossy 3D look, no invented photos, no humans outside the printed portrait paintings. This is final print artwork, NOT a contact sheet with margins.'''
(D/'textures/image2_prompt.txt').write_text(prompt,encoding='utf-8')
print('FROZEN',len(items),plan['reference_sha256'])
