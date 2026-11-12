# SEA-PLANT-EDITOR · 独立植物工坊

[主文档中控](../../../GDD_V1.0.md#sea-plant-editor) · [本功能账本](ledger.md)

## 功能目的与边界

按 2026-11-12 用户两张森林参考制作独立 Godot 编辑器主屏。树干、分枝、叶簇和叶片可以编辑；真实树种定义树形，不以任意球团改名充当树种。苔藓、藤蔓与既有草对象组合。不改建筑工坊及玩家手摆场景，不改变 Farm 生长、游戏存档或全局风唯一写入者。

## 设计条款与验收标准

| 条款 ID | 规则 / 验收 |
|---|---|
| SEA-PLANT-EDITOR-R01 | 独立插件 `addons/plant_editor`，主屏“植物工坊”；独立 Session、预览 World3D、撤销历史、草稿与 `scenes/workshop_plants` 保存根。与建筑插件同时启用、切换前后配方/预览/草稿不串写；不修改原建筑脚本、不打开或保存当前编辑场景。 |
| SEA-PLANT-EDITOR-R02 | 首批香樟 Cinnamomum camphora、鸡爪槭 Acer palmatum、垂枝桦 Betula pendula；记录来源。分别保留宽圆冠/互生全缘椭圆叶、层状舒展冠/对生掌裂叶、直立主干与下垂小枝/互生三角锯齿叶。幼树景观尺度与夸张叶片尺度明确是游戏参数，不冒称完整植物生理模拟。 |
| SEA-PLANT-EDITOR-R03 | 可编辑主干高度/半径/弯曲、冠幅、首分枝高度、主枝数/伸展/上扬/下垂；每枝稳定 ID，可单独隐藏、改长度/角度/粗度并保存，叶簇随所属枝走。seed 确定性，不同枝/叶/附生流独立，改树叶密度不得重抽树干。 |
| SEA-PLANT-EDITOR-R04 | 叶片与叶簇分层编辑：叶片形状由树种约束、尺寸/密度/叶簇大小/松散度/色差/球形法线混合可调。柔软树冠依赖层叠叶片与统一叶簇法线、上亮下暗和清楚轮廓，不用不透明球体替代所有叶片、不从用户图剪切素材。树干和叶片可独立显隐检查。 |
| SEA-PLANT-EDITOR-R05 | 苔藓为固定树皮附生覆盖、藤蔓为独立路径和叶片；各自开关与密度/长度可调，宿主变化后跟随，不整面苔垫摆动。可组合现有 `grass_soft`/`mound_soft` 资源，复制实例与材质，仅预览局部调整，不改原 GLB/TRES/catalog 或设施 TSCN。 |
| SEA-PLANT-EDITOR-R06 | 配方 JSON 与静态 PackedScene 共同版本化保存；验证输入、路径、有限数/区间/未知字段，生成通过后原子提交历史。连续保存只新增 revision，旧版哈希不变，坏配方/失败/取消保留原文档；导出不含编辑器脚本/相机/灯光/碰撞/游戏业务节点。候选不是正式登记，不自动插 Main。 |
| SEA-PLANT-EDITOR-R07 | 预览风使用本地材质 uniform 时间，不写 `vegetation_*` 全局参数；隐藏主屏暂停预览渲染和时钟，重新打开继续。植物作者层不得依赖 building_workshop、Main、Economy 或 Farm。公共资源只读。 |
| SEA-PLANT-EDITOR-R08 | 制作前阅读文章/工具官方说明并记录采用与不采用原因及授权。Sapling 的分枝层级与 seed、Mtree 分层生成、球形法线等仅作算法/工作流参考；不伪称已安装或拷贝第三方代码。若后续确有复用必须记录具体版本与许可，不随意导入不兼容二进制。 |
| SEA-PLANT-EDITOR-R09 | 通过统一 runner 分列内核、实际编辑器双插件隔离、保存重载、旧建筑回归与真实渲染；至少整树/裸枝/叶片近景/附生近景及多树种对照。测试数字不替代图像目检，性能目标与设备实测分开，用户美术终审保持 pending。 |

## 内核接口（冻结 v1）

- `src/plant_authoring/recipe.gd`：`defaults(species="camphor") -> Dictionary`、`validate(data) -> String`；JSON 扁平参数＋`branch_overrides` 字典。
- `src/plant_authoring/species.gd`：`definitions() -> Dictionary`（深副本），键 camphor/maple/birch，值 name/latin/description/sources。
- `src/plant_authoring/generator.gd`：`build(recipe) -> Dictionary`，返回 ok/reason/root/branches/stats；root 是独立 Node3D，枝干分支 `Trunk`、叶片 `Leaves`、苔藓 `Moss`、藤蔓 `Vines`、草 `Grass`。branches 数组每项 id/name；stats 为 triangles/leaf_count/branch_count。
- `src/plant_authoring/session.gd`：唯一拥有配方。`snapshot()`、`apply_patch(patch)`、`load_recipe(data)`、`new_document(species)`、`undo()`、`redo()`、`is_dirty()`、`mark_saved()`；信号 changed。
- `src/plant_authoring/store.gd`：`save(recipe, root_dir="res://scenes/workshop_plants") -> Dictionary`、`load_recipe(path)`、`list_recipes(root_dir)`；result 含 ok/reason/directory/recipe_path/scene_path。
- 参数：species/seed/name/height/trunk_radius/trunk_curve/crown_radius/branch_start/branch_count/branch_spread/branch_rise/branch_droop/leaf_size/leaf_density/cluster_size/cluster_jitter/normal_blend/color_variation/trunk_visible/leaves_visible/moss_enabled/moss_amount/vine_enabled/vine_count/vine_length/grass_enabled/grass_count/grass_asset/branch_overrides。
- branch_overrides[id]：enabled/length_scale/radius_scale/angle_offset；ID 为 branch_00 等。无自定义脚本输入。

## 参考与取舍

- [Sapling 官方手册（4.1 固定版本）](https://docs.blender.org/manual/en/4.1/addons/add_curve/sapling.html)：树形、分枝层级、seed、半径收分与叶片参数；Blender GPL 工具，只参考工作流，不拷贝插件。
- [Mtree](https://github.com/MaximeHerpin/modular_tree)：TrunkFunction→BranchFunction→二级枝，核心 MIT / Blender 插件 GPLv3；当前不增加编译型运行依赖。
- [Zylann Tree Generator](https://github.com/Zylann/godot_tree_generator_plugin)：官方说明 Godot 4.x 不支持，拒绝直接安装旧 GDNative。
- [TreeIt 官方](https://www.evolved-software.com/treeit/treeit)：独立树木工具可编辑关节、叶片与 LOD，导出 DBO/FBX/OBJ/X；免费不等于开源，不拷贝源或预设素材。
- [Forest Waypoint 制作文章](https://80.lv/articles/forest-waypoint-in-ue4-creating-stylized-landscape-and-materials/)：TreeIt 作树、从包络面转移法线，叶片统一受光；借鉴算法，不把 UE 材质直接当 Godot 插件。
- [香樟资料](https://plants.ces.ncsu.edu/plants/cinnamomum-camphora/)、[鸡爪槭资料](https://plants.ces.ncsu.edu/plants/acer-palmatum/)、[垂枝桦资料](https://plants.ces.ncsu.edu/plants/betula-pendula/)：只提取文字形态事实，不下载第三方 CC-BY-NC 图片作游戏素材。

研究日期 2026-11-12。参考图仅作用户提供的视觉方向，不作为可再分发纹理授权。
