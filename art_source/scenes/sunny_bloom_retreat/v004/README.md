# 太阳能木屋 v004 / 游戏装配 1.1

[完整制作源](sunny_bloom_retreat.blend) · [游戏比例装配](export/v001/placement/solar_cabin/solar_cabin_v1.1.blend) · [组件计划](component_plan.json)

## 独立分区

| 中文名称 | Blender文件 | Godot包装 |
|---|---|---|
| 太阳能木屋-后部方形建筑 | [rear_building.blend](modules/rear_building/rear_building.blend) | `godot/scenes/facilities/solar_cabin_rear_building.tscn` |
| 太阳能木屋-前部倾斜太阳能房 | [solar_room.blend](modules/solar_room/solar_room.blend) | `godot/scenes/facilities/solar_cabin_solar_room.tscn` |
| 太阳能木屋-前方可行动平台-酒红 | [front_platform.blend](modules/front_platform/front_platform.blend) | `godot/scenes/facilities/solar_cabin_front_platform.tscn` |
| 太阳能木屋-栈桥-暖木 | [bridge.blend](modules/bridge/bridge.blend) | `godot/scenes/facilities/solar_cabin_bridge.tscn` |

平台采用酒红色横向整板，桥采用暖木色整板。桥入口清空，右侧休闲区、盆栽及外缘绳柱保留。原v003与0.1快照不改。

制作源相对v003放大1.5倍；游戏继续应用1.15导入比例，总比例为原v003的1.725倍，正面Godot +Z，地板Y=2.15米。后部主墙宽8.625米；整体含花草、桥的运行范围约14.52×21.02米。海下基座保留；本轮移除的是海上模型底部灰色承台。
