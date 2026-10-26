# 太阳能木屋 v006 / 游戏装配 1.3

[海上制作源](sunny_bloom_retreat.blend) · [完整游戏比例装配](export/v001/placement/solar_cabin/solar_cabin_v1.3.blend) · [组件计划](component_plan.json)

完整装配按“太阳能木屋-海上区域 / 太阳能木屋-海下基座”分组；海下采用七层新版楼体，独立绞盘台保留。

| 中文分区 | Blender文件 |
|---|---|
| 太阳能木屋-后部方形建筑 | [rear_building.blend](modules/rear_building/rear_building.blend) |
| 太阳能木屋-前部倾斜太阳能房 | [solar_room.blend](modules/solar_room/solar_room.blend) |
| 太阳能木屋-前方可行动平台-酒红 | [front_platform.blend](modules/front_platform/front_platform.blend) |
| 太阳能木屋-栈桥-暖木 | [bridge.blend](modules/bridge/bridge.blend) |

新增木铺板覆盖后区地坪和顶楼露台；前平台仍酒红色、桥仍暖木色。顶楼帆布和挂钩移除，承重柱保留。太阳伞移至右前角，与遮阳板无交叠；粉/白花缩至原75%，花叶独立。

海上45组件、161实例；海下[独立原源](../../bloom_lower_building/v001/bloom_lower_building.blend)不改，22组件独立导出，当前实例化19组件共298次；原屋顶砖、顶边及会穿入上部木地板的顶层花草不实例化。旧v005和0.1备份保留。

海上Godot系数1.15，地板Y=2.15米。海下源Blender XYZ适配系数(2.5,1.5,1.5)，前向映射+Z，顶板Y=1.46贴木地板底面；七层保持。GLB和Godot包装路径稳定，按独立组件管理。
