"""SEA-RESIDENCE 原生 TSCN 制作源；只生成本目录拥有的住所场景。"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'scenes/residence'
assert OUT.is_dir()


def node(name, parent, instance=None, kind='Node3D', props=''):
    spec = f'instance=ExtResource("{instance}")' if instance else f'type="{kind}"'
    return f'\n[node name="{name}" {spec} parent="{parent}"]\n{props}\n'


def ext(kind, path, key):
    return f'[ext_resource type="{kind}" path="{path}" id="{key}"]\n'


# 复用正式套件，不复制 GLB、材质或伪造 Blender source。
header = '[gd_scene format=3]\n'
for key in ['platform_5x5', 'door_frame_5m', 'window_wall_5m', 'wall_5m', 'table', 'oil_lamp', 'stool']:
    header += ext('PackedScene', f'res://scenes/buildables/kit/{key}.tscn', key)
for key in ['wood', 'linen', 'teal']:
    header += ext('Material', f'res://scenes/residence/materials/{key}.tres', key)
header += '''
[sub_resource type="BoxMesh" id="bed_frame"]
size = Vector3(1.7, 0.38, 2.6)
[sub_resource type="BoxMesh" id="mattress"]
size = Vector3(1.6, 0.24, 2.45)
[sub_resource type="BoxMesh" id="pillow"]
size = Vector3(1.2, 0.14, 0.48)
[sub_resource type="BoxMesh" id="blanket"]
size = Vector3(1.62, 0.1, 1.5)
[sub_resource type="BoxMesh" id="headboard"]
size = Vector3(1.7, 0.9, 0.12)
[node name="ResidenceShell" type="Node3D"]
metadata/feature_id = "SEA-RESIDENCE"
metadata/building_class = "above_water"
metadata/source_kind = "godot_existing_kit_and_native_scene"
metadata/cutaway = "无屋顶；侧墙和前窗墙剖切到1.12m，门墙保留真实门楣"
metadata/door_clear_width = 1.85
metadata/door_clear_height = 3.1
metadata/interior_size = Vector2(10, 5)
'''
for i, x in enumerate([-2.5, 2.5]):
    header += node(f'Floor{i}', '.', 'platform_5x5', props=f'position = Vector3({x}, 0, 0)')
    header += node(f'Rear{i}', '.', 'window_wall_5m', props=f'position = Vector3({x}, 0, -2.5)\nscale = Vector3(1, 0.55, 1)\nmetadata/walk_obstacle = Rect2(-2.5, -0.1, 5, 0.2)')
for name, x in [('Left', -5), ('Right', 5)]:
    header += node(name, '.', 'wall_5m', props=f'position = Vector3({x}, 0, 0)\nrotation = Vector3(0, 1.5707963268, 0)\nscale = Vector3(1, 0.22, 1)\nmetadata/walk_obstacle = Rect2(-2.5, -0.1, 5, 0.2)')
header += node('FrontCutaway', '.', 'window_wall_5m', props='position = Vector3(-2.5, 0, 2.5)\nscale = Vector3(1, 0.22, 1)\nmetadata/walk_obstacle = Rect2(-2.5, -0.1, 5, 0.2)')
header += node('DoorFrame', '.', 'door_frame_5m', props='position = Vector3(2.5, 0, 2.5)')
for name, x in [('DoorLeft', 0), ('DoorRight', 3.425)]:
    header += node(name, '.', props=f'metadata/walk_obstacle = Rect2({x}, 2.4, 1.575, 0.2)')
header += node('Bed', '.', props='position = Vector3(-3.3, 0, -0.75)\nmetadata/walk_obstacle = Rect2(-0.85, -1.3, 1.7, 2.6)')
for name, mesh, mat, pos in [('Frame','bed_frame','wood','0, 0.19, 0'),('Mattress','mattress','linen','0, 0.5, 0'),('Pillow','pillow','linen','0, 0.69, -0.85'),('Blanket','blanket','teal','0, 0.67, 0.42'),('Headboard','headboard','wood','0, 0.45, -1.3')]:
    header += node(name, 'Bed', kind='MeshInstance3D', props=f'mesh = SubResource("{mesh}")\nmaterial_override = ExtResource("{mat}")\nposition = Vector3({pos})')
header += node('DailyTable', '.', 'table', props='position = Vector3(0, 0, -1.6)\nmetadata/walk_obstacle = Rect2(-0.7, -0.5, 1.4, 1)')
header += node('Lamp', '.', 'oil_lamp', props='position = Vector3(0.25, 0.78, -1.6)')
header += node('RestStool', '.', 'stool', props='position = Vector3(-1.7, 0, -1.8)\nmetadata/walk_obstacle = Rect2(-0.28, -0.28, 0.56, 0.56)')
header += node('Markers', '.')
for name, pos in [('Home','-1.3, 0, 0.5'), ('Rest','-1.85, 0, -0.6'), ('Work','2.5, 0, -0.9'), ('Door','2.5, 0, 2.5'), ('Social','-2, 0, 3.4')]:
    header += node(name, 'Markers', kind='Marker3D', props=f'position = Vector3({pos})')
(OUT / 'residence_shell.tscn').write_text(header, encoding='utf-8')

rows = [
('residence_dock_workshop','npc_luo_yan','牵线 · 修船间','船匠 / 航线图与绳具',-7,-10,'crates'),
('residence_sunroom_greenhouse','npc_mu_he','叶脉 · 晒种房','种子保管 / 育苗与水桶',7,-10,'plants'),
('residence_salvage_cabin','npc_ji_chen','回声 · 打捞舱','旧城记录 / 标本与打捞箱',-7,-2,'salvage'),
('residence_builder_loft','npc_nan_zhi','榫口 · 木作阁','木工 / 木料与测绘台',7,-2,'builder'),
('residence_lantern_archive','npc_bai_shi','灯芯 · 灯档','守灯档案 / 书架与阅读角',-7,6,'archive'),
('residence_flower_shop','npc_hua_yi','花序 · 花店','花材培育 / 花束柜台',7,6,'flower'),
('residence_general_store','npc_bao_he','货架 · 综合商店','日用补给 / 分类货架',0,14,'general')]
for rid, npc, label, profession, _, _, theme in rows:
    text = '[gd_scene format=3]\n' + ext('PackedScene','res://scenes/residence/residence_shell.tscn','shell')
    for key in ['storage_crate','flower_pot','water_barrel','table','wind_chime','oil_lamp']:
        text += ext('PackedScene',f'res://scenes/buildables/kit/{key}.tscn',key)
    text += ext('Material','res://scenes/residence/materials/wood.tres','wood')
    text += ext('Material','res://scenes/residence/materials/linen.tres','linen')
    text += '''[sub_resource type="BoxMesh" id="counter"]
size = Vector3(2.8, 1.05, 0.65)
[sub_resource type="BoxMesh" id="shelf"]
size = Vector3(2.8, 0.12, 0.55)
[sub_resource type="BoxMesh" id="upright"]
size = Vector3(0.12, 2, 0.55)
[sub_resource type="BoxMesh" id="book"]
size = Vector3(0.18, 0.46, 0.3)
'''
    text += f'[node name="{rid}" type="Node3D"]\nmetadata/residence_id = "{rid}"\nmetadata/npc_id = "{npc}"\nmetadata/feature_id = "SEA-RESIDENCE"\nmetadata/profession = "{profession}"\n'
    text += node('Shell','.','shell')
    text += node('Nameplate','.',kind='Label3D',props=f'position = Vector3(0.5, 2, 2.66)\ntext = "{label}"\nfont_size = 56\npixel_size = 0.009\nmodulate = Color(0.95, 0.88, 0.64, 1)\noutline_modulate = Color(0.18, 0.27, 0.26, 1)\ndouble_sided = true')
    if theme in ['flower','general']:
        text += node('Counter','.',kind='MeshInstance3D',props='position = Vector3(2.5, 0.525, 0.3)\nmesh = SubResource("counter")\nmaterial_override = ExtResource("wood")\nmetadata/walk_obstacle = Rect2(-1.4, -0.325, 2.8, 0.65)')
        text += node('ShopSign','.',kind='Label3D',props=f'position = Vector3(2.5, 3.7, 2.65)\ntext = "{label.split(" · ")[1]}"\nfont_size = 64\npixel_size = 0.012')
    # 后部三层陈列架有独立可避让的占地，不将货架中心当站位。
    text += node('Display','.',props='position = Vector3(3, 0, -1.85)\nmetadata/walk_obstacle = Rect2(-1.4, -0.3, 2.8, 0.6)')
    for side, x in [('Left',-1.35),('Right',1.35)]:
        text += node(f'{side}Upright','Display',kind='MeshInstance3D',props=f'position = Vector3({x}, 1, 0)\nmesh = SubResource("upright")\nmaterial_override = ExtResource("wood")')
    for i, y in enumerate([0.35,1.1,1.85]):
        text += node(f'Shelf{i}','Display',kind='MeshInstance3D',props=f'position = Vector3(0, {y}, 0)\nmesh = SubResource("shelf")\nmaterial_override = ExtResource("wood")')
    if theme in ['plants','flower']:
        for i in range(5):
            text += node(f'Flowers{i}','Display','flower_pot',props=f'position = Vector3({-1+i*.5}, {0.41+(i%3)*.75}, 0)')
        text += node('WateringBarrel','.','water_barrel',props='position = Vector3(-4.1, 0, 1.35)\nmetadata/walk_obstacle = Rect2(-0.35, -0.35, 0.7, 0.7)')
    elif theme in ['archive','general']:
        for i in range(12):
            text += node(f'Book{i}','Display',kind='MeshInstance3D',props=f'position = Vector3({-1.1+(i%6)*.4}, {0.64+(i//6)*.75}, 0)\nmesh = SubResource("book")\nmaterial_override = ExtResource("linen")')
        if theme == 'archive':
            for i in range(2): text += node(f'ArchiveLamp{i}','Display','oil_lamp',props=f'position = Vector3({-0.8+i*1.6}, 1.91, 0)')
    else:
        for i in range(3): text += node(f'ToolCrate{i}','Display','storage_crate',props=f'position = Vector3({-0.9+i*.9}, 0.41, 0)')
        text += node('RouteOrPlan','.',kind='Label3D',props=f'position = Vector3(0, 1.6, -2.34)\ntext = "{profession}"\nfont_size = 36\npixel_size = 0.008')
        if theme == 'salvage': text += node('RecoveredChime','.','wind_chime',props='position = Vector3(-1.7, 2.1, -2.3)')
        if theme == 'builder':
            for i in range(3): text += node(f'Timber{i}','Display',kind='MeshInstance3D',props=f'position = Vector3(0, {1.25+i*.15}, 0)\nmesh = SubResource("shelf")\nmaterial_override = ExtResource("wood")')
    # 家具只作静态陈列，不能因复用 storage/water prefab 而偷偷注册业务交互。
    for line in ['ToolCrate0','ToolCrate1','ToolCrate2','WateringBarrel']:
        marker = f'[node name="{line}" instance='
        if marker in text:
            start = text.index(marker); end = text.find('\n[node ',start+1)
            if end < 0: end = len(text)
            text = text[:end] + 'script = null\n' + text[end:]
    (OUT / f'{rid}.tscn').write_text(text,encoding='utf-8')

text = '[gd_scene format=3]\n'
for kind,path,key in [('Script','res://src/residence/resident_harbor.gd','zone'),('Script','res://src/navigation/walk_area.gd','walk'),('Script','res://src/navigation/landing_point.gd','landing'),('Script','res://src/world/blocker_set.gd','blockers'),('PackedScene','res://scenes/buildables/kit/platform_5x5.tscn','platform'),('PackedScene','res://scenes/buildables/kit/lamp_post.tscn','lamp'),('PackedScene','res://scenes/buildables/kit/railing_5m.tscn','rail')]: text += ext(kind,path,key)
for row in rows: text += ext('PackedScene',f'res://scenes/residence/{row[0]}.tscn',row[0])
text += '''[node name="resident_harbor" type="Node3D"]
script = ExtResource("zone")
zone_id = "resident_harbor"
zone_label = "七灯住所港"
water_layer = "amphibious"
metadata/feature_id = "SEA-RESIDENCE"
metadata/building_class = "above_water"
metadata/source_kind = "godot_existing_kit_and_native_scene"
[node name="Models" type="Node3D" parent="."]
[node name="Platform" type="Node3D" parent="Models"]
[node name="Blockers" type="Node3D" parent="Models/Platform"]
script = ExtResource("blockers")
mode = "manual"
manual_rects = Array[Rect2]([Rect2(-15, -15, 30, 33), Rect2(15, -1.5, 4, 3)])
'''
# 6×7块正式5m平台，最后一排收边到18米；没有微型盒子。
for ix in range(6):
    for iz in range(7):
        z = -12.5+5*iz
        scale = '\nscale = Vector3(1, 1, 0.6)' if iz == 6 else ''
        if iz == 6: z = 16.5
        text += node(f'Deck_{ix}_{iz}','Models/Platform','platform',props=f'position = Vector3({-12.5+5*ix}, 1.38, {z}){scale}')
text += node('Pier','Models/Platform','platform',props='position = Vector3(17, 1.38, 0)\nscale = Vector3(0.8, 1, 0.6)')
text += node('Homes','Models')
for rid,_,_,_,x,z,_ in rows: text += node(rid,'Models/Homes',rid,props=f'position = Vector3({x}, 1.38, {z})')
text += node('PublicLighting','Models')
for i, pos in enumerate(['0, 1.38, -12','0, 1.38, -5','0, 1.38, 3','12.8, 1.38, 12']): text += node(f'Lamp{i}','Models/PublicLighting','lamp',props=f'position = Vector3({pos})')
text += node('Blockers','Models/PublicLighting',props='script = ExtResource("blockers")\nmode = "none"')
text += node('Blockers','Models/Homes',props='script = ExtResource("blockers")\nmode = "none"')
# 外缘栏杆保留东面登岸缺口。
for i,x in enumerate([-12.5,-7.5,-2.5,2.5,7.5,12.5]):
    for side,z in [('North',-15),('South',18)]: text += node(f'Rail{side}{i}','Models/Platform','rail',props=f'position = Vector3({x}, 1.38, {z})')
text += '''
[node name="WalkAreas" type="Node3D" parent="."]
[node name="Community" type="Node3D" parent="WalkAreas"]
position = Vector3(0, 1.38, 0)
script = ExtResource("walk")
area_id = "resident_harbor_ground"
zone_id = "resident_harbor"
surface_y = 1.38
body_radius = 0.38
[node name="Landing" type="Marker3D" parent="WalkAreas/Community"]
position = Vector3(18.1, 0, 0)
script = ExtResource("landing")
landing_id = "main"
landing_label = "七灯住所港泊位"
[node name="BoatPark" type="Marker3D" parent="WalkAreas/Community/Landing"]
position = Vector3(3.5, -0.26, 0)
[node name="DockEdge" type="Marker3D" parent="WalkAreas/Community/Landing"]
position = Vector3(0.9, 0, 0)
'''
(OUT / 'resident_harbor.tscn').write_text(text,encoding='utf-8')
