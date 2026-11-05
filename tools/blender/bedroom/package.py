#!/usr/bin/env python3
"""为 bedroom/v001 的每个 GLB 生成 Godot 组件场景（PackedScene 包装）。

只写 `godot/scenes/components/room/*.tscn`：资产身份、材质角色绑定与可搬运意图。
房间的装配、行走面、灯光、碰撞归正式房间 TSCN，不在这里生成。

用法：python3 tools/blender/bedroom/package.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / 'art_source/rooms/bedroom/v001'
OUT = ROOT / 'godot/scenes/components/room'
CATALOG = json.loads((D / 'component_catalog.json').read_text(encoding='utf8'))['components']
EXPORT = json.loads((D / 'export/v001/export_index.json').read_text(encoding='utf8'))
GLB = {c['key']: c['glb'] for c in EXPORT['components']}
for key in GLB:
    # export_index 记的是仓库相对路径；Godot 的 res:// 根是 godot/。
    assert GLB[key].startswith('godot/'), GLB[key]
    GLB[key] = GLB[key][len('godot/'):]

# 节点名（Godot 里显示的中文名）、角色、子类、是否允许布置功能搬动。
PRESENT = {
    'floor_planks': ('室内木地板', 'building', 'interior_shell', False),
    'wall_window': ('后墙（带窗）', 'building', 'interior_shell', False),
    'wall_door': ('前墙（带门洞）', 'building', 'interior_shell', False),
    'wall_side_e': ('东侧白墙', 'building', 'interior_shell', False),
    'wall_side_w': ('西侧白墙', 'building', 'interior_shell', False),
    'ceiling': ('天花与木梁', 'building', 'interior_shell', False),
    'porch_glass': ('玻璃前厅', 'building', 'interior_shell', False),
    'door_leaf': ('门框与门扇', 'building', 'interior_shell', False),
    # 床是唯一声明 movable 的家具：布置功能将来要能搬动并旋转它。
    'bed': ('床铺', 'furnishing', 'furniture', True),
    'nightstand': ('床头柜', 'furnishing', 'furniture', False),
    'table_lamp': ('床头台灯', 'furnishing', 'furniture', False),
    'rug': ('地毯', 'furnishing', 'furniture', False),
    'shelf': ('靠墙矮柜', 'furnishing', 'furniture', False),
}

# 两个直接对着「外面」的件各用一种玻璃，因为它们的后面不一样：
#   · 后墙窗：后面是黑的（房间外面什么都没有）→ 深色玻璃 room_glass.tres；
#   · 玻璃前厅：玩家能走进去、也会绕着看 → 近透明的 room_porch_glass.tres。
#     用深色玻璃时，转到侧面就是一块斜插在画面里的黑板（实测截图里就是这样）。
# 其余件（门、墙、家具）一律走公共四角色。
GLASS_KEYS = {
    'wall_window': 'res://assets/materials/room/room_glass.tres',
    'porch_glass': 'res://assets/materials/room/room_porch_glass.tres',
}

OUT.mkdir(parents=True, exist_ok=True)
for item in CATALOG:
    key = item['key']
    name, kind, sub, movable = PRESENT[key]
    glb = GLB[key]
    glass = ""
    if key in GLASS_KEYS:
        glass = ('\n[ext_resource type="Material" path="' + GLASS_KEYS[key] + '" id="room_glass"]')
    steps = 4 if key in GLASS_KEYS else 3
    overrides = ('\nmaterial_overrides = {\n"Gloss": ExtResource("room_glass")\n}'
                 if key in GLASS_KEYS else "")
    text = f'''[gd_scene load_steps={steps} format=3]
[ext_resource type="Script" path="res://src/world/sunny_palette_binding.gd" id="bind"]
[ext_resource type="PackedScene" path="res://{glb}" id="visual"]{glass}
[node name="{name}" type="Node3D"]
script = ExtResource("bind")
asset_id = "{item['asset_id']}"
component_kind = "{kind}"
subcategory = "{sub}"
movable = {"true" if movable else "false"}{overrides}
metadata/asset_id = "{item['asset_id']}"
metadata/water_layer = "surface"
metadata/water_layer_role = "part"
[node name="Visual" parent="." instance=ExtResource("visual")]
'''
    (OUT / (key + '.tscn')).write_text(text, encoding='utf8')
print('[bedroom-package] %d component scenes -> %s' %
      (len(CATALOG), OUT.relative_to(ROOT).as_posix()))
