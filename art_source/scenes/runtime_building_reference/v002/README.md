# 当前游戏建筑参照库 · 中文设施整理版 v0.2

> 当前版本：[v0.3 独立绞盘打捞台](../v003/README.md)。

## 打开入口

- [海面可玩设施总览](sea_playable_facilities_v0.2.blend)
- [远景建筑组件总览](background_building_components_v0.2.blend)
- [中文资产账本](资产账本.md)；[中文表头 CSV](asset_index.csv)

## 五个设施独立文件

| 设施 | 英文资产名 | Blender |
|---|---|---|
| 太阳能木屋 | `solar_cabin` | [太阳能木屋](facilities/solar_cabin/solar_cabin_v0.2.blend) |
| 横滨沉没铁道 | `yokohama_station` | [横滨沉没铁道](facilities/yokohama_station/yokohama_station_v0.2.blend) |
| 圆弧屋顶农场 | `arc_rooftop_farm` | [圆弧屋顶农场](facilities/arc_rooftop_farm/arc_rooftop_farm_v0.2.blend) |
| 远海街町 | `far_shore_settlement` | [远海街町](facilities/far_shore_settlement/far_shore_settlement_v0.2.blend) |
| 浅水养殖台 | `aquaculture_platform` | [浅水养殖台](facilities/aquaculture_platform/aquaculture_platform_v0.2.blend) |

## Blender 中的层级

```text
太阳能木屋
  太阳能木屋-海上区域
  太阳能木屋-海下基座
横滨沉没铁道
  横滨沉没铁道-海上区域
  横滨沉没铁道-海下基座
圆弧屋顶农场
  圆弧屋顶农场-海上区域
  圆弧屋顶农场-海下基座
远海街町
  远海街町-海上区域
  远海街町-海下基座
浅水养殖台
  浅水养殖台-海上区域
  浅水养殖台-海下基座
```

总览只在最外层显示五个设施；每个设施的两个区域可以单独隐藏。区域内的对象继续使用中文设施和部件名称。97 个独立部件、5 个设施总成、2 个总览均可独立打开；详细对应见中文资产账本。

## 命名和几何约定

- 账本 `name` 与 Blender 中文显示名一致；`asset_key` 与英文文件名一致，文件名后接 `_v0.2.blend`。
- Godot 现有 `unit_01` 等路径保留为原始来源，通过稳定 AssetID、asset_key 和清单关联；本次不改正式游戏资源路径。
- 海上/海下分界为实际游戏水面 Godot Y=1.12（Blender Z=1.12）。跨水面的网格切为两个区域，合并显示保持原形；切面不额外封盖。
- 原 v0.1 文件保留。本版只整理命名、集合、引用及水面分区，位置、尺度、颜色和有效表面保持一致。
- 远景公共构件使用组件母版归类；这类归一化零件的海上/海下归属由实际摆放决定，不在母版上固定。
- 海面部件保留旧自动拆分边界，未声称每个旧 GLB 都等于一栋完整设施；设施总成提供完整区块参照。
- 远景实例清单已同步为本版英文资产名；逻辑部件索引可通过原始 source_instance 追溯到拆分后的区域对象。

## 独立部件

| 中文名称 | 英文资产名 | Blender |
|---|---|---|
| 太阳能木屋-港湾周边 | `solar_cabin_harbor_surroundings` | [太阳能木屋-港湾周边](playable/solar_cabin/solar_cabin_harbor_surroundings/solar_cabin_harbor_surroundings_v0.2.blend) |
| 太阳能木屋-前侧平台 | `solar_cabin_front_deck` | [太阳能木屋-前侧平台](playable/solar_cabin/solar_cabin_front_deck/solar_cabin_front_deck_v0.2.blend) |
| 太阳能木屋-后侧楼体 | `solar_cabin_rear_tower` | [太阳能木屋-后侧楼体](playable/solar_cabin/solar_cabin_rear_tower/solar_cabin_rear_tower_v0.2.blend) |
| 太阳能木屋-木屋主体 | `solar_cabin_core` | [太阳能木屋-木屋主体](playable/solar_cabin/solar_cabin_core/solar_cabin_core_v0.2.blend) |
| 横滨沉没铁道-周边连接设施 | `yokohama_station_connections` | [横滨沉没铁道-周边连接设施](playable/yokohama_station/yokohama_station_connections/yokohama_station_connections_v0.2.blend) |
| 横滨沉没铁道-站台结构 | `yokohama_station_platform` | [横滨沉没铁道-站台结构](playable/yokohama_station/yokohama_station_platform/yokohama_station_platform_v0.2.blend) |
| 横滨沉没铁道-东侧设施 | `yokohama_station_east_facilities` | [横滨沉没铁道-东侧设施](playable/yokohama_station/yokohama_station_east_facilities/yokohama_station_east_facilities_v0.2.blend) |
| 横滨沉没铁道-西侧设施 | `yokohama_station_west_facilities` | [横滨沉没铁道-西侧设施](playable/yokohama_station/yokohama_station_west_facilities/yokohama_station_west_facilities_v0.2.blend) |
| 圆弧屋顶农场-外围结构 | `arc_rooftop_farm_outer_structure` | [圆弧屋顶农场-外围结构](playable/arc_rooftop_farm/arc_rooftop_farm_outer_structure/arc_rooftop_farm_outer_structure_v0.2.blend) |
| 圆弧屋顶农场-农场主体 | `arc_rooftop_farm_core` | [圆弧屋顶农场-农场主体](playable/arc_rooftop_farm/arc_rooftop_farm_core/arc_rooftop_farm_core_v0.2.blend) |
| 远海街町-水面标记 | `far_shore_settlement_water_marker` | [远海街町-水面标记](playable/far_shore_settlement/far_shore_settlement_water_marker/far_shore_settlement_water_marker_v0.2.blend) |
| 远海街町-主楼结构 | `far_shore_settlement_main_building` | [远海街町-主楼结构](playable/far_shore_settlement/far_shore_settlement_main_building/far_shore_settlement_main_building_v0.2.blend) |
| 远海街町-附属设施 | `far_shore_settlement_annex` | [远海街町-附属设施](playable/far_shore_settlement/far_shore_settlement_annex/far_shore_settlement_annex_v0.2.blend) |
| 远海街町-屋顶设施 | `far_shore_settlement_rooftop_facilities` | [远海街町-屋顶设施](playable/far_shore_settlement/far_shore_settlement_rooftop_facilities/far_shore_settlement_rooftop_facilities_v0.2.blend) |
| 远海街町-侧墙结构 | `far_shore_settlement_side_wall` | [远海街町-侧墙结构](playable/far_shore_settlement/far_shore_settlement_side_wall/far_shore_settlement_side_wall_v0.2.blend) |
| 浅水养殖台-外围支撑 | `aquaculture_platform_outer_supports` | [浅水养殖台-外围支撑](playable/aquaculture_platform/aquaculture_platform_outer_supports/aquaculture_platform_outer_supports_v0.2.blend) |
| 浅水养殖台-养殖台主体 | `aquaculture_platform_core` | [浅水养殖台-养殖台主体](playable/aquaculture_platform/aquaculture_platform_core/aquaculture_platform_core_v0.2.blend) |
| 远景-阳台住宅楼 | `background_balcony_residence` | [远景-阳台住宅楼](background_components/background_balcony_residence/background_balcony_residence/background_balcony_residence_v0.2.blend) |
| 远景-破顶围墙楼 | `background_broken_roof_frame` | [远景-破顶围墙楼](background_components/background_broken_roof_frame/background_broken_roof_frame/background_broken_roof_frame_v0.2.blend) |
| 远景-阳台框架楼甲型 | `background_balcony_frame_a` | [远景-阳台框架楼甲型](background_components/background_balcony_frame_a/background_balcony_frame_a/background_balcony_frame_a_v0.2.blend) |
| 远景-破损楼板楼 | `background_broken_slab_frame` | [远景-破损楼板楼](background_components/background_broken_slab_frame/background_broken_slab_frame/background_broken_slab_frame_v0.2.blend) |
| 远景-阶梯框架楼 | `background_stair_frame` | [远景-阶梯框架楼](background_components/background_stair_frame/background_stair_frame/background_stair_frame_v0.2.blend) |
| 远景-阳台框架楼乙型 | `background_balcony_frame_b` | [远景-阳台框架楼乙型](background_components/background_balcony_frame_b/background_balcony_frame_b/background_balcony_frame_b_v0.2.blend) |
