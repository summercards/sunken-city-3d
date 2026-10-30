# 场景组件分类与维护入口

[主文档](../../GDD_V1.0.md) · [场景资产分账本](ledgers/scenes.json) · [运行验证](../../docs/development/2026-10-27_scene_component_split.md)

资产主记录仍只在 scenes 分账本，本页用于导航。原 category 字段保留生产工具语义；classification 记录用户维护分类。

| 一级类 | 子类 | 所有权与入口 |
|---|---|---|
| 建筑 | 结构/设施总成 | 六设施保持独立；旧四区13个建筑单元新增独立包装，原GLB和材质覆盖路径保留 |
| 建筑升级附件 | 植物 | 原42种植物与太阳房/基座花叶分别登记，276个当前场景实例，读取建筑等级 |
| 摆件 | 可移动家具 | 太阳房13类、25实例；独立实例根，接口发交互请求 |
| 装饰 | 水面植物 | 24片荷叶，独立组件和摆放清单 |
| 装饰 | 水下纯景观建筑 | 阳光房周围六栋独立楼体，单栋导出三角面≤1000，无碰撞/互动/资源；正式布局 `godot/scenes/decorations/underwater/neighborhood.tscn` |
| 装饰 | 动物 | 7只飞鸟、海面下3群鱼、潜水7群鱼、1头巡游鲸；无资源产出 |
| 船只 | 基础船与附属件 | reference_skiff：12组件、44实例，基础黄白木船、双桨、船外机和行李；正式入口 [reference_skiff.tscn](../../godot/scenes/props/reference_skiff.tscn)，行为仍由Boat拥有 |
| 建筑 | 商店（海上结构物） | 海上悬浮商铺 `SEA-SCENE-FSH-ASSEMBLY`，39组件/248实例烘成4材质角色单一GLB；预制体 [floating_shop.tscn](../../godot/scenes/facilities/floating_shop.tscn)，正式摆放 `main.tscn` 的 `World/SeaStructures/floating_shop`（阳光房主体正南50米）；无WalkArea/泊位/交互 |

## 维护规则

- 修改组件模型：进入对应 prefab；修改单个太阳房/基座实例：进入该套件 instances.json，以已保存 instance_id 定位，不靠重排数组产生新ID。
- 升级植物使用 facility_id / attachment_slot / unlock_level；可移动家具只提供 inspect / relocate 请求，正式移动编辑器与存档事务后续由玩法实现。
- 叶片摆放源为 godot/assets/data/lily_components.json；旧zone2网格的840三角面仅运行时精确退役，原GLB不改。zone1旧叶片随旧房替换已不在可见模型中，本轮恢复9片。
- 旧设施GLB中的固定细节仍随建筑维护；尚未逐件识别的内部陈设标 pending，不将整栋楼标为可移动家具。
- 素材权属沿用 pending_provenance_review；本次代码/运行验证不代签授权。

## 独立组件索引

| AssetID | 名称 | 分类 | 独立入口 |
|---|---|---|
| SEA-SCENE-SBR-FOUNDATION | 石砌平台块 | building/structure | [组件](../../godot/scenes/components/solar_cabin/foundation.tscn) |
| SEA-SCENE-SBR-DECK-TILE | 橙木平台铺板 | building/structure | [组件](../../godot/scenes/components/solar_cabin/deck_tile.tscn) |
| SEA-SCENE-SBR-DOCK-BOARD | 栈桥-暖木横向整板 | building/structure | [组件](../../godot/scenes/components/solar_cabin/dock_board.tscn) |
| SEA-SCENE-SBR-PIER | 码头墩 | building/structure | [组件](../../godot/scenes/components/solar_cabin/pier.tscn) |
| SEA-SCENE-SBR-HOUSE | 开窗下层墙壳 | building/structure | [组件](../../godot/scenes/components/solar_cabin/house.tscn) |
| SEA-SCENE-SBR-TERRACE | 顶楼露台-暖木整板 | building/structure | [组件](../../godot/scenes/components/solar_cabin/terrace.tscn) |
| SEA-SCENE-SBR-UPPER-ROOM | 屋顶小屋墙壳 | building/structure | [组件](../../godot/scenes/components/solar_cabin/upper_room.tscn) |
| SEA-SCENE-SBR-CAP | 小屋厚帽檐 | building/structure | [组件](../../godot/scenes/components/solar_cabin/cap.tscn) |
| SEA-SCENE-SBR-PARAPET | 白花台矮墙 | building/structure | [组件](../../godot/scenes/components/solar_cabin/parapet.tscn) |
| SEA-SCENE-SBR-SLOPE | 单坡门廊屋面 | building/structure | [组件](../../godot/scenes/components/solar_cabin/slope.tscn) |
| SEA-SCENE-SBR-BOLLARD | 双绳圈木柱 | building/structure | [组件](../../godot/scenes/components/solar_cabin/bollard.tscn) |
| SEA-SCENE-SBR-TALL-WINDOW | 左侧双扇宽窗 | building/structure | [组件](../../godot/scenes/components/solar_cabin/tall_window.tscn) |
| SEA-SCENE-SBR-NARROW-WINDOW | 后部建筑-加宽前窗 | building/structure | [组件](../../godot/scenes/components/solar_cabin/narrow_window.tscn) |
| SEA-SCENE-SBR-SMALL-WINDOW | 上层小窗 | building/structure | [组件](../../godot/scenes/components/solar_cabin/small_window.tscn) |
| SEA-SCENE-SBR-DOOR | 青蓝门 | building/structure | [组件](../../godot/scenes/components/solar_cabin/door.tscn) |
| SEA-SCENE-SBR-ENTRY | 玻璃入口框扇 | building/structure | [组件](../../godot/scenes/components/solar_cabin/entry.tscn) |
| SEA-SCENE-SBR-SOLAR | 蓝色光伏板 | building/structure | [组件](../../godot/scenes/components/solar_cabin/solar.tscn) |
| SEA-SCENE-SBR-AWNING | 黄白条纹圆边遮阳篷 | building/structure | [组件](../../godot/scenes/components/solar_cabin/awning.tscn) |
| SEA-SCENE-SBR-CANOPY-POST | 遮阳棚橙木立柱 | building/structure | [组件](../../godot/scenes/components/solar_cabin/canopy_post.tscn) |
| SEA-SCENE-SBR-CANOPY-BEAM | 遮阳棚横梁 | building/structure | [组件](../../godot/scenes/components/solar_cabin/canopy_beam.tscn) |
| SEA-SCENE-SBR-SAIL | 下垂奶白布棚 | building/structure | [组件](../../godot/scenes/components/solar_cabin/sail.tscn) |
| SEA-SCENE-SBR-LADDER | 橙木圆角爬梯 | building/structure | [组件](../../godot/scenes/components/solar_cabin/ladder.tscn) |
| SEA-SCENE-SBR-AC-TALL | 侧墙高设备箱 | building/structure | [组件](../../godot/scenes/components/solar_cabin/ac_tall.tscn) |
| SEA-SCENE-SBR-AC-BOX | 小立式空调 | building/structure | [组件](../../godot/scenes/components/solar_cabin/ac_box.tscn) |
| SEA-SCENE-SBR-AC-ROOF | 屋顶卧式空调 | building/structure | [组件](../../godot/scenes/components/solar_cabin/ac_roof.tscn) |
| SEA-SCENE-SBR-CHIMNEY | 屋顶通风立柱 | building/structure | [组件](../../godot/scenes/components/solar_cabin/chimney.tscn) |
| SEA-SCENE-SBR-LANTERN | 暖光壁灯 | furnishing/movable | [组件](../../godot/scenes/components/solar_cabin/lantern.tscn) |
| SEA-SCENE-SBR-SOFA | 白垫双人木沙发 | furnishing/movable | [组件](../../godot/scenes/components/solar_cabin/sofa.tscn) |
| SEA-SCENE-SBR-ROOF-SOFA | 露台单黄抱枕沙发 | furnishing/movable | [组件](../../godot/scenes/components/solar_cabin/roof_sofa.tscn) |
| SEA-SCENE-SBR-COFFEE-TABLE | 低木茶几 | furnishing/movable | [组件](../../godot/scenes/components/solar_cabin/coffee_table.tscn) |
| SEA-SCENE-SBR-TABLE | 户外方桌 | furnishing/movable | [组件](../../godot/scenes/components/solar_cabin/table.tscn) |
| SEA-SCENE-SBR-STOOL | 方木凳 | furnishing/movable | [组件](../../godot/scenes/components/solar_cabin/stool.tscn) |
| SEA-SCENE-SBR-UMBRELLA | 黄白圆瓣遮阳伞 | furnishing/movable | [组件](../../godot/scenes/components/solar_cabin/umbrella.tscn) |
| SEA-SCENE-SBR-COOLER | 白盖蓝冷藏箱 | furnishing/movable | [组件](../../godot/scenes/components/solar_cabin/cooler.tscn) |
| SEA-SCENE-SBR-POT | 圆陶花盆 | furnishing/movable | [组件](../../godot/scenes/components/solar_cabin/pot.tscn) |
| SEA-SCENE-SBR-SQUARE-POT | 方白花盆 | furnishing/movable | [组件](../../godot/scenes/components/solar_cabin/square_pot.tscn) |
| SEA-SCENE-SBR-VASE | 黄陶圆腹小花瓶 | furnishing/movable | [组件](../../godot/scenes/components/solar_cabin/vase.tscn) |
| SEA-SCENE-SBR-CANOPY-HOOK | 墙侧布棚支撑挂杆 | building/structure | [组件](../../godot/scenes/components/solar_cabin/canopy_hook.tscn) |
| SEA-SCENE-SBR-BOTTLE | 红色水瓶 | furnishing/movable | [组件](../../godot/scenes/components/solar_cabin/bottle.tscn) |
| SEA-SCENE-SBR-MAT | 太阳纹薄荷地垫 | furnishing/movable | [组件](../../godot/scenes/components/solar_cabin/mat.tscn) |
| SEA-SCENE-SBR-PORCH-SIDE | 门廊厚侧墙与玻璃窗 | building/structure | [组件](../../godot/scenes/components/solar_cabin/porch_side.tscn) |
| SEA-SCENE-SBR-WALL-PIER | 白色墙角与后侧承重柱 | building/structure | [组件](../../godot/scenes/components/solar_cabin/wall_pier.tscn) |
| SEA-SCENE-SBR-PORCH-RETURN | 门廊后侧封墙 | building/structure | [组件](../../godot/scenes/components/solar_cabin/porch_return.tscn) |
| SEA-SCENE-SBR-FOLIAGE | 错落厚叶簇 | upgrade_attachment/plants | [组件](../../godot/scenes/components/solar_cabin/foliage.tscn) |
| SEA-SCENE-SBR-VINE | 自然交错垂藤 | upgrade_attachment/plants | [组件](../../godot/scenes/components/solar_cabin/vine.tscn) |
| SEA-SCENE-SBR-PALM | 厚裂叶热带棕榈 | upgrade_attachment/plants | [组件](../../godot/scenes/components/solar_cabin/palm.tscn) |
| SEA-SCENE-SBR-PINK-FLOWER | 五瓣饱满粉花 | upgrade_attachment/plants | [组件](../../godot/scenes/components/solar_cabin/pink_flower.tscn) |
| SEA-SCENE-SBR-DAISY | 六瓣白色小花 | upgrade_attachment/plants | [组件](../../godot/scenes/components/solar_cabin/daisy.tscn) |
| SEA-SCENE-SBR-SPROUT | 盆栽嫩叶 | upgrade_attachment/plants | [组件](../../godot/scenes/components/solar_cabin/sprout.tscn) |
| SEA-SCENE-BLB-FACADE-BAY | 长面厚白窗湾 | building/structure | [组件](../../godot/scenes/components/bloom_lower_building/facade_bay.tscn) |
| SEA-SCENE-BLB-END-BAY | 短面厚白窗湾 | building/structure | [组件](../../godot/scenes/components/bloom_lower_building/end_bay.tscn) |
| SEA-SCENE-BLB-RETURN-BAY | 转角窄窗墙 | building/structure | [组件](../../godot/scenes/components/bloom_lower_building/return_bay.tscn) |
| SEA-SCENE-BLB-FLOOR-SLAB | 内楼板 | building/structure | [组件](../../godot/scenes/components/bloom_lower_building/floor_slab.tscn) |
| SEA-SCENE-BLB-ROOF-SLAB | 厚顶板 | building/structure | [组件](../../godot/scenes/components/bloom_lower_building/roof_slab.tscn) |
| SEA-SCENE-BLB-ROOF-TILE | 浅杏屋顶砖 | building/structure | [组件](../../godot/scenes/components/bloom_lower_building/roof_tile.tscn) |
| SEA-SCENE-BLB-ROOF-RIM | 奶白屋顶边条 | building/structure | [组件](../../godot/scenes/components/bloom_lower_building/roof_rim.tscn) |
| SEA-SCENE-BLB-FOUNDATION | 落地厚柱脚 | building/structure | [组件](../../godot/scenes/components/bloom_lower_building/foundation.tscn) |
| SEA-SCENE-BLB-WALL-PIER | 厚白墙柱 | building/structure | [组件](../../godot/scenes/components/bloom_lower_building/wall_pier.tscn) |
| SEA-SCENE-BLB-BLUE-COLUMN | 蓝灰凹槽立柱 | building/structure | [组件](../../godot/scenes/components/bloom_lower_building/blue_column.tscn) |
| SEA-SCENE-BLB-BLUE-COLLAR | 天蓝柱箍 | building/structure | [组件](../../godot/scenes/components/bloom_lower_building/blue_collar.tscn) |
| SEA-SCENE-BLB-WIDE-WINDOW | 青蓝双扇窗 | building/structure | [组件](../../godot/scenes/components/bloom_lower_building/wide_window.tscn) |
| SEA-SCENE-BLB-END-WINDOW | 端面宽双扇窗 | building/structure | [组件](../../godot/scenes/components/bloom_lower_building/end_window.tscn) |
| SEA-SCENE-BLB-RETURN-WINDOW | 转角单扇小窗 | building/structure | [组件](../../godot/scenes/components/bloom_lower_building/return_window.tscn) |
| SEA-SCENE-BLB-AIR-CONDITIONER | 白色外挂机 | building/structure | [组件](../../godot/scenes/components/bloom_lower_building/air_conditioner.tscn) |
| SEA-SCENE-BLB-LEAF-CLUSTER | 饱满放射叶簇 | upgrade_attachment/plants | [组件](../../godot/scenes/components/bloom_lower_building/leaf_cluster.tscn) |
| SEA-SCENE-BLB-EDGE-CLUSTER | 横向花台叶簇 | upgrade_attachment/plants | [组件](../../godot/scenes/components/bloom_lower_building/edge_cluster.tscn) |
| SEA-SCENE-BLB-VINE-LONG | 长垂藤 | upgrade_attachment/plants | [组件](../../godot/scenes/components/bloom_lower_building/vine_long.tscn) |
| SEA-SCENE-BLB-VINE-SHORT | 短垂藤 | upgrade_attachment/plants | [组件](../../godot/scenes/components/bloom_lower_building/vine_short.tscn) |
| SEA-SCENE-BLB-PINK-FLOWER | 五瓣亮粉花 | upgrade_attachment/plants | [组件](../../godot/scenes/components/bloom_lower_building/pink_flower.tscn) |
| SEA-SCENE-BLB-WHITE-FLOWER | 五瓣白花 | upgrade_attachment/plants | [组件](../../godot/scenes/components/bloom_lower_building/white_flower.tscn) |
| SEA-SCENE-BLB-YELLOW-BUDS | 小黄花苞 | upgrade_attachment/plants | [组件](../../godot/scenes/components/bloom_lower_building/yellow_buds.tscn) |
| SEA-REF-01-ZONE1-HOME-HARBOR--UNIT-01 | 太阳能木屋-前侧平台 | building/structure | [组件](../../godot/scenes/components/solar_cabin/base_solar_cabin_front_deck.tscn) |
| SEA-REF-01-ZONE1-HOME-HARBOR--UNIT-02 | 太阳能木屋-后侧楼体 | building/structure | [组件](../../godot/scenes/components/solar_cabin/base_solar_cabin_rear_tower.tscn) |
| SEA-REF-01-ZONE1-HOME-HARBOR--UNIT-03 | 太阳能木屋-木屋主体 | building/structure | [组件](../../godot/scenes/components/solar_cabin/base_solar_cabin_core.tscn) |
| SEA-REF-01-ZONE2-YOKOHAMA-STATION--DETAIL | 横滨沉没铁道-周边连接设施 | building/legacy_structure | [组件](../../godot/scenes/components/facilities/zone2_yokohama_station/detail.tscn) |
| SEA-REF-01-ZONE2-YOKOHAMA-STATION--UNIT-01 | 横滨沉没铁道-站台结构 | building/legacy_structure | [组件](../../godot/scenes/components/facilities/zone2_yokohama_station/unit_01.tscn) |
| SEA-REF-01-ZONE2-YOKOHAMA-STATION--UNIT-02 | 横滨沉没铁道-东侧设施 | building/legacy_structure | [组件](../../godot/scenes/components/facilities/zone2_yokohama_station/unit_02.tscn) |
| SEA-REF-01-ZONE2-YOKOHAMA-STATION--UNIT-03 | 横滨沉没铁道-西侧设施 | building/legacy_structure | [组件](../../godot/scenes/components/facilities/zone2_yokohama_station/unit_03.tscn) |
| SEA-REF-01-ZONE3-ARC-FARM--DETAIL | 圆弧屋顶农场-外围结构 | building/legacy_structure | [组件](../../godot/scenes/components/facilities/zone3_arc_farm/detail.tscn) |
| SEA-REF-01-ZONE3-ARC-FARM--UNIT-01 | 圆弧屋顶农场-农场主体 | building/legacy_structure | [组件](../../godot/scenes/components/facilities/zone3_arc_farm/unit_01.tscn) |
| SEA-REF-01-ZONE4-FAR-SHORE--DETAIL | 远海街町-水面标记 | building/legacy_structure | [组件](../../godot/scenes/components/facilities/zone4_far_shore/detail.tscn) |
| SEA-REF-01-ZONE4-FAR-SHORE--UNIT-01 | 远海街町-主楼结构 | building/legacy_structure | [组件](../../godot/scenes/components/facilities/zone4_far_shore/unit_01.tscn) |
| SEA-REF-01-ZONE4-FAR-SHORE--UNIT-02 | 远海街町-附属设施 | building/legacy_structure | [组件](../../godot/scenes/components/facilities/zone4_far_shore/unit_02.tscn) |
| SEA-REF-01-ZONE4-FAR-SHORE--UNIT-03 | 远海街町-屋顶设施 | building/legacy_structure | [组件](../../godot/scenes/components/facilities/zone4_far_shore/unit_03.tscn) |
| SEA-REF-01-ZONE4-FAR-SHORE--UNIT-04 | 远海街町-侧墙结构 | building/legacy_structure | [组件](../../godot/scenes/components/facilities/zone4_far_shore/unit_04.tscn) |
| SEA-REF-01-ZONE5-AQUA-PLATFORM--DETAIL | 浅水养殖台-外围支撑 | building/legacy_structure | [组件](../../godot/scenes/components/facilities/zone5_aqua_platform/detail.tscn) |
| SEA-REF-01-ZONE5-AQUA-PLATFORM--UNIT-01 | 浅水养殖台-养殖台主体 | building/legacy_structure | [组件](../../godot/scenes/components/facilities/zone5_aqua_platform/unit_01.tscn) |
| SEA-REF-01-ZONE1-HOME-HARBOR--DETAIL | 太阳能木屋-港湾周边 | building/structure | [组件](../../godot/scenes/components/solar_cabin/base_solar_cabin_harbor_surroundings.tscn) |
| SEA-SCENE-SBR-CONCRETE-SLAB | 后部建筑-暖木整板地坪 | building/structure | [组件](../../godot/scenes/components/solar_cabin/concrete_slab.tscn) |
| SEA-SCENE-SBR-PLATFORM-BOARD | 前方平台-酒红横向整板 | building/structure | [组件](../../godot/scenes/components/solar_cabin/platform_board.tscn) |
| SEA-SCENE-SBR-BRIDGE-ROPE | 栈桥-两端系结垂绳 | building/structure | [组件](../../godot/scenes/components/solar_cabin/bridge_rope.tscn) |
| SEA-SCENE-SBR-HANGING-TIRE | 栈桥-悬挂轮胎与吊绳 | building/structure | [组件](../../godot/scenes/components/solar_cabin/hanging_tire.tscn) |
| SEA-SCENE-SBR-PLATFORM-BOARD-CORAL | 前方平台-酒红横向整板-coral | building/structure | [组件](../../godot/scenes/components/solar_cabin/platform_board_coral.tscn) |
| SEA-SCENE-SBR-PLATFORM-BOARD-OCHRE | 前方平台-酒红横向整板-ochre | building/structure | [组件](../../godot/scenes/components/solar_cabin/platform_board_ochre.tscn) |
| SEA-SCENE-SBR-DOCK-BOARD-SAND | 栈桥-暖木横向整板-sand | building/structure | [组件](../../godot/scenes/components/solar_cabin/dock_board_sand.tscn) |
| SEA-SCENE-SBR-DOCK-BOARD-SHADE | 栈桥-暖木横向整板-shade | building/structure | [组件](../../godot/scenes/components/solar_cabin/dock_board_shade.tscn) |
| SEA-PLANT-COMMON-PLANT_01_5L | 通用升级植物 plant_01_5l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/common/plant_01_5l.tscn) |
| SEA-PLANT-COMMON-PLANT_02_3L | 通用升级植物 plant_02_3l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/common/plant_02_3l.tscn) |
| SEA-PLANT-COMMON-PLANT_03_4L | 通用升级植物 plant_03_4l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/common/plant_03_4l.tscn) |
| SEA-PLANT-COMMON-PLANT_05_4L | 通用升级植物 plant_05_4l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/common/plant_05_4l.tscn) |
| SEA-PLANT-COMMON-PLANT_15_8L | 通用升级植物 plant_15_8l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/common/plant_15_8l.tscn) |
| SEA-PLANT-COMMON-PLANT_18_3L | 通用升级植物 plant_18_3l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/common/plant_18_3l.tscn) |
| SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_04_8L | zone1_home_harbor升级植物 plant_04_8l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone1_home_harbor/plant_04_8l.tscn) |
| SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_07_6L | zone1_home_harbor升级植物 plant_07_6l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone1_home_harbor/plant_07_6l.tscn) |
| SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_11_3L | zone1_home_harbor升级植物 plant_11_3l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone1_home_harbor/plant_11_3l.tscn) |
| SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_12_3L | zone1_home_harbor升级植物 plant_12_3l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone1_home_harbor/plant_12_3l.tscn) |
| SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_13_8L | zone1_home_harbor升级植物 plant_13_8l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone1_home_harbor/plant_13_8l.tscn) |
| SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_19_10L | zone1_home_harbor升级植物 plant_19_10l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone1_home_harbor/plant_19_10l.tscn) |
| SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_20_10L | zone1_home_harbor升级植物 plant_20_10l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone1_home_harbor/plant_20_10l.tscn) |
| SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_33_9L | zone1_home_harbor升级植物 plant_33_9l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone1_home_harbor/plant_33_9l.tscn) |
| SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_34_5L | zone1_home_harbor升级植物 plant_34_5l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone1_home_harbor/plant_34_5l.tscn) |
| SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_35_7L | zone1_home_harbor升级植物 plant_35_7l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone1_home_harbor/plant_35_7l.tscn) |
| SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_36_3L | zone1_home_harbor升级植物 plant_36_3l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone1_home_harbor/plant_36_3l.tscn) |
| SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_37_3L | zone1_home_harbor升级植物 plant_37_3l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone1_home_harbor/plant_37_3l.tscn) |
| SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_38_3L | zone1_home_harbor升级植物 plant_38_3l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone1_home_harbor/plant_38_3l.tscn) |
| SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_39_3L | zone1_home_harbor升级植物 plant_39_3l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone1_home_harbor/plant_39_3l.tscn) |
| SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_40_4L | zone1_home_harbor升级植物 plant_40_4l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone1_home_harbor/plant_40_4l.tscn) |
| SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_41_5L | zone1_home_harbor升级植物 plant_41_5l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone1_home_harbor/plant_41_5l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_00_4L | zone3_arc_farm升级植物 plant_00_4l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_00_4l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_06_6L | zone3_arc_farm升级植物 plant_06_6l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_06_6l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_08_4L | zone3_arc_farm升级植物 plant_08_4l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_08_4l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_09_12L | zone3_arc_farm升级植物 plant_09_12l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_09_12l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_10_5L | zone3_arc_farm升级植物 plant_10_5l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_10_5l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_14_3L | zone3_arc_farm升级植物 plant_14_3l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_14_3l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_16_6L | zone3_arc_farm升级植物 plant_16_6l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_16_6l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_17_14L | zone3_arc_farm升级植物 plant_17_14l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_17_14l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_21_4L | zone3_arc_farm升级植物 plant_21_4l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_21_4l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_22_11L | zone3_arc_farm升级植物 plant_22_11l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_22_11l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_23_3L | zone3_arc_farm升级植物 plant_23_3l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_23_3l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_24_6L | zone3_arc_farm升级植物 plant_24_6l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_24_6l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_25_7L | zone3_arc_farm升级植物 plant_25_7l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_25_7l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_26_6L | zone3_arc_farm升级植物 plant_26_6l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_26_6l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_27_13L | zone3_arc_farm升级植物 plant_27_13l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_27_13l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_28_7L | zone3_arc_farm升级植物 plant_28_7l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_28_7l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_29_6L | zone3_arc_farm升级植物 plant_29_6l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_29_6l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_30_3L | zone3_arc_farm升级植物 plant_30_3l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_30_3l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_31_8L | zone3_arc_farm升级植物 plant_31_8l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_31_8l.tscn) |
| SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_32_7L | zone3_arc_farm升级植物 plant_32_7l | upgrade_attachment/plants | [组件](../../godot/scenes/plants/zones/zone3_arc_farm/plant_32_7l.tscn) |
| SEA-DECO-ANIMAL-BIRD | 场景装饰·飞鸟 | decoration/animals | [组件](../../godot/scenes/decorations/animals/bird.tscn) |
| SEA-DECO-ANIMAL-FISH-SCHOOL | 场景装饰·鱼群（水面 / 水下共用；v002 移植网页版模型与游动） | decoration/animals | [组件](../../godot/scenes/decorations/animals/fish_school.tscn) |
| SEA-DECO-ANIMAL-WHALE | 场景装饰·巡游鲸 | decoration/animals | [组件](../../godot/scenes/decorations/animals/whale.tscn) |
| SEA-DECO-WATER-LILY | 场景装饰·缺口荷叶 | decoration/water_plants | [组件](../../godot/scenes/decorations/water/lily_leaf.tscn) |

## 2026-10-27 生活循环组件

| AssetID | 用途 | 独立入口 |
|---|---|---|
| SEA-FARM-CULTIVATION-DECK | 浅水平台木板面 | `godot/scenes/props/cultivation_deck.tscn` |
| SEA-FARM-SOIL-CELL | 木框培养土（作物模型已移至 crops 域，见下节） | `godot/scenes/props/farm_cell.tscn` |
| SEA-SCENE-SBR-COOLER | 复用原白盖蓝箱，码头出货入口 | `godot/scenes/components/solar_cabin/cooler.tscn`；`godot/src/orders/shipping_box.gd` |

## 2026-10-29 作物品种（独立资产域 crops）

| AssetID | 用途 | 独立入口 |
|---|---|---|
| SEA-CROP-LETTUCE | 生菜·四阶段（种子/发芽/二次发芽/收成） | `godot/scenes/crops/lettuce.tscn` |
| SEA-CROP-TOMATO | 番茄·四阶段 | `godot/scenes/crops/tomato.tscn` |
| SEA-CROP-PUMPKIN | 南瓜·四阶段 | `godot/scenes/crops/pumpkin.tscn` |

主记录在 [crops 分账本](ledgers/crops.json)，不在 `scenes.json`。每品种 4 个阶段 GLB，合计 12 个，单个阶段整格 ≤900 三角面（实测 336–780）。
