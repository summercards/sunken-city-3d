# 太阳能木屋 v005 / 游戏装配 1.2

[完整制作源](sunny_bloom_retreat.blend) · [游戏比例装配](export/v001/placement/solar_cabin/solar_cabin_v1.2.blend) · [组件计划](component_plan.json)

| 中文名称 | Blender文件 | Godot包装 |
|---|---|---|
| 太阳能木屋-后部方形建筑 | [rear_building.blend](modules/rear_building/rear_building.blend) | `godot/scenes/facilities/solar_cabin_rear_building.tscn` |
| 太阳能木屋-前部倾斜太阳能房 | [solar_room.blend](modules/solar_room/solar_room.blend) | `godot/scenes/facilities/solar_cabin_solar_room.tscn` |
| 太阳能木屋-前方可行动平台-酒红 | [front_platform.blend](modules/front_platform/front_platform.blend) | `godot/scenes/facilities/solar_cabin_front_platform.tscn` |
| 太阳能木屋-栈桥-暖木 | [bridge.blend](modules/bridge/bridge.blend) | `godot/scenes/facilities/solar_cabin_bridge.tscn` |

顶楼三根柱沿下层承重轴向上延续，前低后高；阳光房向右平移，梯子净空；水泥地坪、酒红平台和暖木桥加厚圆角，顶面保持不变。桥增加两排横向整板，两侧垂绳共挂四个轮胎。太阳伞休闲区保留。

47组件、163实例；建筑与花草独立集合。旧v004和原0.1备份保留。游戏比例装配包括海上四分区、原海下基座及独立打捞台；制作源只有本次海上建筑。

Godot导入系数1.15，相对v003总1.725倍，正面+Z、地板Y=2.15米。主墙宽8.625米；阳光房较v004右移1.4375米，桥延长1.587米。含植物/绳胎包围盒约15.953×22.606米，高11.465米。
