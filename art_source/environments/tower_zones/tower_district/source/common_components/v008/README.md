# TOWER DISTRICT 组件库 v008

打开 `tower_district_components_v008.blend`，默认场景为 **TD_组件实例街区_v008**。

本版按 `02-battle-room-component-decomposer` 对既有 v007 街区进行明确授权的结构迁移，保留原有几何、材质表现、位置和动画。43 个组件定义、2,883 个集合实例，建筑结构 9 类，预算剩余 7 类。v007 的 SHA-256 首尾一致。

## Blender 结构

- **01_制作组件_按组件拆分**：唯一母版，按结构／设施／装饰／环境支持归类；默认在主视图中排除直接绘制。组件内为 `ROOT_<slug>`、`<slug>_主体` 和必要的 `<slug>_自发光`。
- **02_游戏输出_独立资产包_v008**：只包含 Collection Instance，不含直接网格。按组件分组浏览重复摆放。
- **03_动画控制与坐标契约**：ROOM_FRAME、车辆控制根、无人机悬浮根及旋翼控制。保留历史统一展示缩放；母版 ROOT、网格局部变换和集合 instance_offset 均为恒等／零。
- **90_展示环境_灯光相机与动态**：原灯光、相机、雨丝、飘纸与体积雾。它们属于场景展示／动态支持，不冒充静态组件定义。

另有 **TD_组件母版画廊_v008**（分离式组件实例画廊）和 **TD_JSON重放验收_v008**（由清单独立重放的验收场景）。组件总表见 `component_tree.txt`。

编辑时展开 01 中所需母版，临时取消该制作集合的视图排除并单独隔离组件；02 中所有引用会同步更新。主参考镜头仍为 `TD_Reference_Camera`，时间轴 1–240 帧／24 fps。

## 实际归并

- 9 辆轿车 → 1 份轿车几何母版。
- 14 块招牌框 → 1 份框体母版；文字图案合为独立的完整字图资产，保留原文字内容。
- 2,640 块人行道砖 → 1 份砖母版。
- 144 块路缘石 → 1 份路缘母版。
- 12 段护栏、6 个排水格栅、5 个箱体、4 个路桩分别复用各自母版。
- 冷却机组按真实风扇／百叶结构分成 2 类；警示灯、桥墩、壁灯、旋翼护圈和叶片按几何指纹归并。

配色变化通过共享 PaletteUV、面属性 `PaletteVariantMask` 与实例属性 `palette_shift` 实现，不复制轿车／路砖几何，也不增加表面材质角色。仍共用 `TD_Metal`、`TD_Matte`、`TD_WetPaint`、`TD_Emission` 四种表面角色；主体与自发光网格分离。色盘外链至 `assets/art/shared/palette/tower_district_palette.png`。

## 坐标与追溯

ROOM_FRAME 的平面中心来自既有沥青基础面的边界，走行面来自基础面顶面的实测值。此工作区是独立参考场景，没有 ShellStorm2 的 battle／expedition 白模、关卡编号或 Godot 工程，因此使用 `block_id=tower_district`、`level_id=null`，不虚构关卡或第二个房型消费者。

`component_instances.json` 保存房间局部矩阵、世界位置追溯、绕 Blender Z 的旋转、完整 XYZ 姿态扩展、历史统一缩放、动画父级及色盘偏移。`rotation_y_deg` 延续规范的历史命名，其语义为绕 Blender Z。动态车辆／无人机由额外父级控制记录重放。

旧源把多种物件批量合在 66 个静态网格中，故“源网格数”与“实例数”不同。检查逐个覆盖全部 **31,213 个静态源方块**，没有重复或丢失；`source_object_count` 在新清单中明确表示拆分后的语义片段数。其余 48 个环境动态网格保留在 90 下。

## 文件与唯一维护来源

- `tower_district_components_v008.blend`：本版唯一权威母版库及参考实例布局。
- `component_plan.json`：创建输出几何前冻结的 43 项组件计划，含归并键、几何指纹和变体理由。
- `component_catalog.json`：一组件一行的目录。
- `component_instances.json`：2,883 个实例、坐标契约、动画父级与色盘偏移。
- `component_packages/<component_id>/asset_manifest.json`：组件 ID、原点、包络、材质、来源和接口契约。
- `component_packages/<component_id>/<slug>.blend`：43 份独立可开、可预览、可验证的版本快照。由权威母版导出，不作为第二套独立维护的库；修改母版后应同步重新生成这些快照。
- 验收图与报告：`outputs/tower_district/component_migration_v008/qa/`。
- 制作和验证脚本：`tools/blender/tower_district_components/`。

## 验收范围

已执行 Blender 结构检查、43 文件逐个重开、逐面 PaletteUV 检查、ROOT／Mesh／instance_offset 三层锚点检查、源几何覆盖、5 个动画时刻的位置核对，以及清单独立重放。原源未被覆盖。

本次未执行 Godot 导入、Prefab、碰撞、GLB 转换或跨房型互用率验收。所有组件均诚实登记为单个参考类型使用；未凭空增加 `serves_room_types`。原造型尺寸也未强行重制为其他项目的 5m 网格。未来 Godot 导入需按 02b 阶段转换并验证实例色盘偏移等 Blender 材质接口。

渲染复核对整理前后采用一致设置。为处理原场景的阴影缓存报满，v008 使用 1024 MiB 阴影缓存和 0.5 阴影分辨率缩放；灯光颜色、能量、位置、光雾与动画参数保留。
