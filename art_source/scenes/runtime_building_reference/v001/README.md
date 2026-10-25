# 游戏现状建筑参照库 v0.1

> 当前归类版本：[v0.2 中文设施整理版](../v002/README.md)。本页保留 v0.1 历史导出索引。

本库由当前游戏引用的模型和实际环境批次转存，供替换时核对尺寸、位置、原点和构件关系。不是遗失的历史参数化 Blender 原稿。目录 `v001` 对应用户版本 **0.1**。

## 打开入口

- [海面五区总览](playable_overview_v0.1.blend)：按当前 Godot 世界坐标装配 17 个现有静态单元。
- [六类远景楼体组件库](background_building_library_v0.1.blend)：六类不同楼体各一个母版。
- [CSV 资产索引](asset_index.csv)：按“海面可玩区 / 远景背景”筛选，含每个独立 Blender 路径。
- [机器目录](catalog.json)；[远景实例清单（无损 gzip）](background_instances.json.gz)。

## 文件与用途

17 个海面静态模型单元、6 类远景楼体母版、74 类去重附属构件，共 97 个独立文件；另有 2 个链接总览。远景相同造型只存一个组件，颜色、缩放、旋转、位置单独记在实例清单。附属构件包含墙/基座/窗/叶片等旧网格及背景杂项，并非 74 栋不同楼体。

海面单元沿用已有 GLB 边界，可能包含多栋结构或邻近陈设；`zone4_far_shore/detail` 是零三角面的线条上下文，不能当作独立建筑。水下独立区域未导出，但海面建筑原本延伸到水下的楼体保留。角色、船只动作、玩法生成物和独立植物系统不属于本次静态建筑快照。

## 替换约定

- 单位为米。Godot `(x,y,z)` 到 Blender 为 `(x,-z,y)`；组件保持原运行枢轴，不能一键归零网格或改底部原点。
- 可玩区文件里的根在局部原点；清单同时记录区块内坐标、区块原点和世界坐标。总览已经应用世界坐标。
- v0.1 作为只读参照。制作替换件另存 v0.2 或新组件，不覆盖基线。正式 TSCN 仍拥有游戏装配位置。
- 远景楼体保存 789 处来源摆放，783 处完整匹配；6 处原始楼体因旧区块拆分等原因不完整，实例清单保留实际成员，不能无条件补成整栋。
- 远景全部 249052 个当前启用网格实例都有唯一去向。成员校正矩阵保留原始精度；没有把重复摆放当成新资产。
- 纹理、顶点颜色、法线、尺寸保留；不把旧材质强行换成新色板。Godot 卡通光照、水下染色、风动、后处理不在 Blender 中复刻，预览仅作结构参照。
- Blender 导入器会丢弃旧 GLB 中重复顶点索引的退化三角形，数量逐文件登记；有效三角形与包围盒已核对。

## 可玩区独立文件

| 单元 | Blender |
|---|---|
| zone1_home_harbor / D · 交易码头·6m | [zone1_home_harbor__detail](playable/zone1_home_harbor/detail/zone1_home_harbor__detail_v0.1.blend) |
| zone1_home_harbor / sea·2m | [zone1_home_harbor__unit_01](playable/zone1_home_harbor/unit_01/zone1_home_harbor__unit_01_v0.1.blend) |
| zone1_home_harbor / 岛心·6m | [zone1_home_harbor__unit_02](playable/zone1_home_harbor/unit_02/zone1_home_harbor__unit_02_v0.1.blend) |
| zone1_home_harbor / 岛心·0m | [zone1_home_harbor__unit_03](playable/zone1_home_harbor/unit_03/zone1_home_harbor__unit_03_v0.1.blend) |
| zone2_yokohama_station / 岛心·6m | [zone2_yokohama_station__detail](playable/zone2_yokohama_station/detail/zone2_yokohama_station__detail_v0.1.blend) |
| zone2_yokohama_station / 岛心·0m | [zone2_yokohama_station__unit_01](playable/zone2_yokohama_station/unit_01/zone2_yokohama_station__unit_01_v0.1.blend) |
| zone2_yokohama_station / 岛心·4m | [zone2_yokohama_station__unit_02](playable/zone2_yokohama_station/unit_02/zone2_yokohama_station__unit_02_v0.1.blend) |
| zone2_yokohama_station / 横滨铁道·4m | [zone2_yokohama_station__unit_03](playable/zone2_yokohama_station/unit_03/zone2_yokohama_station__unit_03_v0.1.blend) |
| zone3_arc_farm / 岛心·2m | [zone3_arc_farm__detail](playable/zone3_arc_farm/detail/zone3_arc_farm__detail_v0.1.blend) |
| zone3_arc_farm / 岛心·0m | [zone3_arc_farm__unit_01](playable/zone3_arc_farm/unit_01/zone3_arc_farm__unit_01_v0.1.blend) |
| zone4_far_shore / 远海街町·10m | [zone4_far_shore__detail](playable/zone4_far_shore/detail/zone4_far_shore__detail_v0.1.blend) |
| zone4_far_shore / 远海街町·5m | [zone4_far_shore__unit_01](playable/zone4_far_shore/unit_01/zone4_far_shore__unit_01_v0.1.blend) |
| zone4_far_shore / 远海街町·6m | [zone4_far_shore__unit_02](playable/zone4_far_shore/unit_02/zone4_far_shore__unit_02_v0.1.blend) |
| zone4_far_shore / 远海街町·2m | [zone4_far_shore__unit_03](playable/zone4_far_shore/unit_03/zone4_far_shore__unit_03_v0.1.blend) |
| zone4_far_shore / 远海街町·6m | [zone4_far_shore__unit_04](playable/zone4_far_shore/unit_04/zone4_far_shore__unit_04_v0.1.blend) |
| zone5_aqua_platform / 岛心·3m | [zone5_aqua_platform__detail](playable/zone5_aqua_platform/detail/zone5_aqua_platform__detail_v0.1.blend) |
| zone5_aqua_platform / 岛心·2m | [zone5_aqua_platform__unit_01](playable/zone5_aqua_platform/unit_01/zone5_aqua_platform__unit_01_v0.1.blend) |

## 远景楼体独立组件

| 类型 | Blender |
|---|---|
| 阳台住宅楼 | [background_building_type_00](background_components/background_building_type_00/background_building_type_00_v0.1.blend) |
| 破顶围墙楼 | [background_building_type_01](background_components/background_building_type_01/background_building_type_01_v0.1.blend) |
| 阳台框架楼A | [background_building_type_02](background_components/background_building_type_02/background_building_type_02_v0.1.blend) |
| 破损楼板楼 | [background_building_type_03](background_components/background_building_type_03/background_building_type_03_v0.1.blend) |
| 阶梯框架楼 | [background_building_type_04](background_components/background_building_type_04/background_building_type_04_v0.1.blend) |
| 阳台框架楼B | [background_building_type_05](background_components/background_building_type_05/background_building_type_05_v0.1.blend) |
