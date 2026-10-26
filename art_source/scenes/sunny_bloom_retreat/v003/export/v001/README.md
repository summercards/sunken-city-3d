# 太阳能木屋 · 当前游戏装配

[打开当前 Blender 装配](placement/solar_cabin/solar_cabin_v1.0.blend)；[独立优化源](solar_cabin_optimized_v001.blend)；[导出清单](export_manifest.json)。

- 海上区域来自 sunny_bloom_retreat/v003，原母版未改。
- 下方为原海下基座；绞盘打捞台保持独立。
- 源比例 1.15，正面 Godot +Z，yaw=0°，平台 Y=2.15 米。
- 含花草与桥的范围约 10.59×13.82 米，水面以上最大高约 8.00 米。

## 组件账本

| 中文组件名 | AssetID | Godot PackedScene |
|---|---|---|
| 石砌平台块 | SEA-SCENE-SBR-FOUNDATION | `godot/scenes/components/solar_cabin/foundation.tscn` |
| 橙木平台铺板 | SEA-SCENE-SBR-DECK-TILE | `godot/scenes/components/solar_cabin/deck_tile.tscn` |
| 双列码头木板 | SEA-SCENE-SBR-DOCK-BOARD | `godot/scenes/components/solar_cabin/dock_board.tscn` |
| 码头墩 | SEA-SCENE-SBR-PIER | `godot/scenes/components/solar_cabin/pier.tscn` |
| 开窗下层墙壳 | SEA-SCENE-SBR-HOUSE | `godot/scenes/components/solar_cabin/house.tscn` |
| 厚露台楼板 | SEA-SCENE-SBR-TERRACE | `godot/scenes/components/solar_cabin/terrace.tscn` |
| 屋顶小屋墙壳 | SEA-SCENE-SBR-UPPER-ROOM | `godot/scenes/components/solar_cabin/upper_room.tscn` |
| 小屋厚帽檐 | SEA-SCENE-SBR-CAP | `godot/scenes/components/solar_cabin/cap.tscn` |
| 白花台矮墙 | SEA-SCENE-SBR-PARAPET | `godot/scenes/components/solar_cabin/parapet.tscn` |
| 单坡门廊屋面 | SEA-SCENE-SBR-SLOPE | `godot/scenes/components/solar_cabin/slope.tscn` |
| 双绳圈木柱 | SEA-SCENE-SBR-BOLLARD | `godot/scenes/components/solar_cabin/bollard.tscn` |
| 左侧双扇宽窗 | SEA-SCENE-SBR-TALL-WINDOW | `godot/scenes/components/solar_cabin/tall_window.tscn` |
| 正面单扇窄高窗 | SEA-SCENE-SBR-NARROW-WINDOW | `godot/scenes/components/solar_cabin/narrow_window.tscn` |
| 上层小窗 | SEA-SCENE-SBR-SMALL-WINDOW | `godot/scenes/components/solar_cabin/small_window.tscn` |
| 青蓝门 | SEA-SCENE-SBR-DOOR | `godot/scenes/components/solar_cabin/door.tscn` |
| 玻璃入口框扇 | SEA-SCENE-SBR-ENTRY | `godot/scenes/components/solar_cabin/entry.tscn` |
| 蓝色光伏板 | SEA-SCENE-SBR-SOLAR | `godot/scenes/components/solar_cabin/solar.tscn` |
| 黄白条纹圆边遮阳篷 | SEA-SCENE-SBR-AWNING | `godot/scenes/components/solar_cabin/awning.tscn` |
| 遮阳棚橙木立柱 | SEA-SCENE-SBR-CANOPY-POST | `godot/scenes/components/solar_cabin/canopy_post.tscn` |
| 遮阳棚横梁 | SEA-SCENE-SBR-CANOPY-BEAM | `godot/scenes/components/solar_cabin/canopy_beam.tscn` |
| 下垂奶白布棚 | SEA-SCENE-SBR-SAIL | `godot/scenes/components/solar_cabin/sail.tscn` |
| 橙木圆角爬梯 | SEA-SCENE-SBR-LADDER | `godot/scenes/components/solar_cabin/ladder.tscn` |
| 侧墙高设备箱 | SEA-SCENE-SBR-AC-TALL | `godot/scenes/components/solar_cabin/ac_tall.tscn` |
| 小立式空调 | SEA-SCENE-SBR-AC-BOX | `godot/scenes/components/solar_cabin/ac_box.tscn` |
| 屋顶卧式空调 | SEA-SCENE-SBR-AC-ROOF | `godot/scenes/components/solar_cabin/ac_roof.tscn` |
| 屋顶通风立柱 | SEA-SCENE-SBR-CHIMNEY | `godot/scenes/components/solar_cabin/chimney.tscn` |
| 暖光壁灯 | SEA-SCENE-SBR-LANTERN | `godot/scenes/components/solar_cabin/lantern.tscn` |
| 白垫双人木沙发 | SEA-SCENE-SBR-SOFA | `godot/scenes/components/solar_cabin/sofa.tscn` |
| 露台单黄抱枕沙发 | SEA-SCENE-SBR-ROOF-SOFA | `godot/scenes/components/solar_cabin/roof_sofa.tscn` |
| 低木茶几 | SEA-SCENE-SBR-COFFEE-TABLE | `godot/scenes/components/solar_cabin/coffee_table.tscn` |
| 户外方桌 | SEA-SCENE-SBR-TABLE | `godot/scenes/components/solar_cabin/table.tscn` |
| 方木凳 | SEA-SCENE-SBR-STOOL | `godot/scenes/components/solar_cabin/stool.tscn` |
| 黄白圆瓣遮阳伞 | SEA-SCENE-SBR-UMBRELLA | `godot/scenes/components/solar_cabin/umbrella.tscn` |
| 白盖蓝冷藏箱 | SEA-SCENE-SBR-COOLER | `godot/scenes/components/solar_cabin/cooler.tscn` |
| 圆陶花盆 | SEA-SCENE-SBR-POT | `godot/scenes/components/solar_cabin/pot.tscn` |
| 方白花盆 | SEA-SCENE-SBR-SQUARE-POT | `godot/scenes/components/solar_cabin/square_pot.tscn` |
| 黄陶圆腹小花瓶 | SEA-SCENE-SBR-VASE | `godot/scenes/components/solar_cabin/vase.tscn` |
| 墙侧布棚支撑挂杆 | SEA-SCENE-SBR-CANOPY-HOOK | `godot/scenes/components/solar_cabin/canopy_hook.tscn` |
| 红色水瓶 | SEA-SCENE-SBR-BOTTLE | `godot/scenes/components/solar_cabin/bottle.tscn` |
| 太阳纹薄荷地垫 | SEA-SCENE-SBR-MAT | `godot/scenes/components/solar_cabin/mat.tscn` |
| 门廊厚侧墙与玻璃窗 | SEA-SCENE-SBR-PORCH-SIDE | `godot/scenes/components/solar_cabin/porch_side.tscn` |
| 白色墙角与后侧承重柱 | SEA-SCENE-SBR-WALL-PIER | `godot/scenes/components/solar_cabin/wall_pier.tscn` |
| 门廊后侧封墙 | SEA-SCENE-SBR-PORCH-RETURN | `godot/scenes/components/solar_cabin/porch_return.tscn` |
| 错落厚叶簇 | SEA-SCENE-SBR-FOLIAGE | `godot/scenes/components/solar_cabin/foliage.tscn` |
| 自然交错垂藤 | SEA-SCENE-SBR-VINE | `godot/scenes/components/solar_cabin/vine.tscn` |
| 厚裂叶热带棕榈 | SEA-SCENE-SBR-PALM | `godot/scenes/components/solar_cabin/palm.tscn` |
| 五瓣饱满粉花 | SEA-SCENE-SBR-PINK-FLOWER | `godot/scenes/components/solar_cabin/pink_flower.tscn` |
| 六瓣白色小花 | SEA-SCENE-SBR-DAISY | `godot/scenes/components/solar_cabin/daisy.tscn` |
| 盆栽嫩叶 | SEA-SCENE-SBR-SPROUT | `godot/scenes/components/solar_cabin/sprout.tscn` |
