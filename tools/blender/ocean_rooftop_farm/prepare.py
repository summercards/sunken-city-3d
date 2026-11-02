import bpy, json, hashlib, shutil
from pathlib import Path

R = Path(r'D:/projects/sea')
D = R / 'art_source/scenes/ocean_rooftop_farm/v001'
W = R.parent / 'sea-work/ocean_rooftop_farm/v001'
D.mkdir(parents=True, exist_ok=True)
W.mkdir(parents=True, exist_ok=True)
backup = W / 'session_safety_before.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(backup), copy=True)
ref = Path(r'C:/Users/zhuangmenghong/.workbuddy/clipboard-images/clipboard-2026-11-02T10-32-37-228Z-c2c3c968.jpg')
shutil.copy2(ref, D / 'reference.jpg')

items = [
    ('building_shell', '混凝土楼体与水平层线', 'structure', 'building'),
    ('floor_slab', '厚圆角混凝土楼板', 'structure', 'building'),
    ('facade_column', '外挑混凝土结构柱', 'structure', 'building'),
    ('facade_window', '蓝玻璃混凝土窗框', 'fixture', 'facade'),
    ('balcony', '混凝土栏板阳台', 'structure', 'facade'),
    ('roof_deck', '屋顶矩形平台', 'structure', 'roof'),
    ('parapet', '低矮混凝土女儿墙', 'structure', 'roof'),
    ('railing_segment', '圆管金属防护栏杆', 'fixture', 'railing'),
    ('raised_platform', '左后抬高设备平台', 'structure', 'platform'),
    ('upper_room', '平台顶部居住小间', 'structure', 'room'),
    ('metal_ladder', '竖直金属爬梯', 'fixture', 'access'),
    ('clothesline', '晾衣绳与橙红衣片', 'fixture', 'domestic'),
    ('tool_shed', '中央工具房墙体与木门', 'structure', 'shed'),
    ('shed_roof', '红褐波纹双坡屋顶', 'structure', 'roof'),
    ('small_lean_to', '左侧蓝色斜顶棚屋', 'structure', 'shed'),
    ('greenhouse_frame', '温室金属框架与入口', 'structure', 'greenhouse'),
    ('greenhouse_panels', '温室浅青透明板材', 'fixture', 'greenhouse'),
    ('water_tank', '圆肚储水罐与锥形盖', 'fixture', 'water'),
    ('water_tower_frame', '水塔立柱与斜撑', 'structure', 'water'),
    ('wind_pump', '多叶风力装置', 'fixture', 'energy'),
    ('solar_panel', '低支架厚框太阳能板', 'fixture', 'energy'),
    ('equipment_box', '圆角设备箱', 'fixture', 'equipment'),
    ('raised_bed', '木框高架菜床', 'fixture', 'planting'),
    ('main_field', '主农田土垄与木分隔', 'fixture', 'planting'),
    ('small_field', '后方小型种植田', 'fixture', 'planting'),
    ('leaf_row', '饱满叶菜种植行', 'flora', 'crop_row'),
    ('seedling_row', '稀疏幼苗种植行', 'flora', 'crop_row'),
    ('vine_row', '高藤蔓与攀爬杆种植行', 'flora', 'crop_row'),
    ('grass_patch', '圆润低矮草地', 'flora', 'ground_cover'),
    ('stepping_stone', '不规则厚石板', 'fixture', 'path'),
    ('wood_walkway', '暖木步道板', 'fixture', 'path'),
    ('round_table', '圆形户外小桌', 'fixture', 'furniture'),
    ('chair', '圆角木座椅', 'fixture', 'furniture'),
    ('crate', '木储物箱', 'fixture', 'storage'),
    ('barrel', '圆肚储物桶', 'fixture', 'storage'),
    ('planter_pot', '厚边陶土花盆', 'fixture', 'pot'),
    ('potted_plant', '宽厚盆栽叶簇', 'flora', 'pot'),
    ('low_fence', '低矮金属围栏', 'fixture', 'fence'),
    ('pipe_run', '弯曲外露管道', 'fixture', 'utility'),
    ('lamp_post', '弯臂屋顶灯具', 'fixture', 'lighting'),
    ('chicken_coop', '空家禽木棚舍', 'fixture', 'shelter'),
    ('water_trough', '种植灌溉水槽', 'fixture', 'water'),
    ('trellis', '细杆攀爬架', 'fixture', 'planting'),
    ('roof_hatch', '屋顶检修入口', 'fixture', 'access'),
]
assert len(items) == 44 and len(items) <= 50
components = []
for key, name, category, family in items:
    components.append({
        'key': key,
        'asset_id': 'SEA-SCENE-ORF-' + key.upper().replace('_', '-'),
        'name': name,
        'category': category,
        'component_family': family,
        'origin': 'bottom_center',
        'front_axis': 'Blender -Y / Godot +Z',
        'allowed_rotation': 'full Euler XYZ on instances',
        'scope': 'scene_local',
        'collision': 'visual source only; future facility assembly owns projection',
        'budget_triangles': 40000,
        'budget_source': 'task-authored component ceiling, not a user-supplied cap'
    })
plan = {
    'schema': 'sea.scene.component_plan',
    'version': 'v001',
    'status': 'frozen_before_geometry',
    'scene_id': 'ocean_rooftop_farm',
    'feature_id': 'SEA-ASSET',
    'design_clause': 'SEA-ASSET-R41',
    'asset_ledger': 'assets/registry/ledgers/scenes.json',
    'assembly_asset_id': 'SEA-SCENE-ORF-ASSEMBLY',
    'building_class': 'above_water',
    'water_layer': 'surface',
    'reference': {
        'source': 'user supplied rooftop farm image and written dimensions',
        'archive': 'reference.jpg',
        'sha256': hashlib.sha256((D / 'reference.jpg').read_bytes()).hexdigest(),
        'license': 'pending_user_reference_rights_review'
    },
    'style': 'Plump cartoon style, rounded shapes, fuller forms, soft geometry, cute proportions, simplified forms, reduced tiny details, clean silhouettes, light volumetric modeling, playful toy-like look',
    'excluded': ['people', 'chickens and all other animals', 'ocean and distant buildings', 'seabirds', 'background scenery'],
    'palette': 'art_source/shared/palettes/sea_cabin_timber_8x8_512.png',
    'material_roles': ['SEA_Matte', 'SEA_Metal', 'SEA_Gloss', 'SEA_Emission'],
    'coordinate_mapping': 'Blender(x,y,z)->Godot(x,z,-y); front=-Y',
    'dimension_contract': {
        'roof_m': [36, 24], 'outer_envelope_m': [38, 26], 'visible_floors': 3,
        'floor_height_m': 3.2, 'roof_top_z_m': 9.6, 'slab_thickness_m': 0.22,
        'parapet_height_m': 0.55, 'railing_height_m': 1.1,
        'raised_platform_m': [8, 7, 3.4], 'upper_room_m': [3.5, 3, 2.5],
        'tool_shed_m': [4.5, 3.5, 3.2], 'small_lean_to_m': [3, 2.5, 2.4],
        'greenhouse_m': [5, 9, 3.8], 'water_tower_height_m': 9,
        'water_tank_diameter_m': 3.5, 'main_field_m': [11, 8],
        'raised_bed_m': [5.5, 4, 0.45], 'small_field_m': [4, 5],
        'main_path_width_m': [1.0, 1.5],
        'scale_exception': 'User-specified 3.2m floor height and 36x24m roof override the solar-cabin 5.086335m floor-height baseline; slab 0.22m and soft-edge language retained.'
    },
    'geometry_budget': {'maximum_expanded_triangles': 900000, 'source': 'task-authored target; user supplied no cap'},
    'components': components
}
(D / 'component_plan.json').write_text(json.dumps(plan, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'session_backup': str(backup), 'plan': str(D / 'component_plan.json'), 'components': len(components), 'previous_scene': bpy.context.scene.name}, ensure_ascii=False))
