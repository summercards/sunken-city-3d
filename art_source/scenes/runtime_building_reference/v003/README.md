# 游戏建筑替换参照 · v0.3

## 打开入口

- [六设施总览](sea_playable_facilities_v0.3.blend)
- [太阳能木屋](facilities/solar_cabin/solar_cabin_v0.3.blend)
- [绞盘打捞台](facilities/salvage_station/salvage_station_v0.3.blend)
- [中文资产账本](资产账本.md)；[资产索引 CSV](asset_index.csv)

## 独立设施

绞盘打捞台与太阳能木屋是两个顶层设施，各自都有“设施名字-海上区域”和“设施名字-海下基座”。总览内任一设施均可独立隐藏，不会连带隐藏另一设施。

| 设施 | 英文资产名 | 当前源 |
|---|---|---|
| 太阳能木屋 | `solar_cabin` | [太阳能木屋](facilities/solar_cabin/solar_cabin_v0.3.blend) |
| 横滨沉没铁道 | `yokohama_station` | [横滨沉没铁道](../v002/facilities/yokohama_station/yokohama_station_v0.2.blend) |
| 圆弧屋顶农场 | `arc_rooftop_farm` | [圆弧屋顶农场](../v002/facilities/arc_rooftop_farm/arc_rooftop_farm_v0.2.blend) |
| 远海街町 | `far_shore_settlement` | [远海街町](../v002/facilities/far_shore_settlement/far_shore_settlement_v0.2.blend) |
| 浅水养殖台 | `aquaculture_platform` | [浅水养殖台](../v002/facilities/aquaculture_platform/aquaculture_platform_v0.2.blend) |
| 绞盘打捞台 | `salvage_station` | [绞盘打捞台](facilities/salvage_station/salvage_station_v0.3.blend) |

## 拆分与定位

- 原分组把整个家园港湾归到太阳能木屋，现按游戏中独立的 salvage 登岸点拆出绞盘打捞台，包括甲板、绞盘、立柱、下方支撑及附近装饰。
- 原运行单元 detail.glb 仍作为共同来源；Blender 与资产账本分别拥有独立设施 AssetID，不把旧 GLB 当作设施边界。
- 打捞台局部原点位于 Godot 世界坐标 (-12,0,13)，文件保留水面 Y=1.12 对应的海上/海下分类；总览按原世界位置摆放。
- 更新木屋港湾部件、木屋总成和总览；其余 v0.2 部件直接复用。v0.1/v0.2 保存不变。
- 原游戏 GLB/TSCN、碰撞、登岸点与玩法未改动。本版是制作替换参照。

## 验证

4 个新增/变更源均重开；集合与链接有效；拆分后的三角形总数、有效表面积和合并包围盒保持；两种结构预览已目视核对。
