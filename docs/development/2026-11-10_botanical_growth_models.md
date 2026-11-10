# 2026-11-10 植物 v002 三形态模型开发记录

## 1. 本轮结论

本轮在 R63（v001 原始归档）之后新增 R64，范围冻结为 **104 种植物命名，每种 small / medium / large 三形态**，暂不做季节，不接入游戏，只交付 Blender 模型源与源级验证证据。

- 植被域：98 种 × 3 = 294 个模型。
- 种植域：6 种 × 3 = 18 个模型。
- 总计：104 种、312 个 v002 模型。
- 中文名称是项目管理名，不是物种鉴定名。
- 三形态必须有叶、分枝、花蕾、果实等适用器官的拓扑、数量、展开或冠幅变化；不能用整体缩放冒充生长。
- 藤蔓使用 `top_center_attachment` 顶心吊挂原点，是明确例外；其他植物使用 `bottom_center` 底心原点。
- 纯植物模型不含盆、土、平台、手持物或玩法节点。
- 既有作物 v001 四阶段保留；v002 三形态不表示运行四阶段覆盖已完成。

关联条款：`SEA-ASSET-R64`，并承接 `SEA-ASSET-R49`、`SEA-ASSET-R30`、`SEA-CROP-R06`、`SEA-CROP-R15`。

## 2. 源文件与当前验证结果

### 2.1 植被域

- Blender 源：`art_source/vegetation/libraries/v002/vegetation_library.blend`
- 组件计划：`art_source/vegetation/libraries/v002/component_plan.json`
- 清单：`art_source/vegetation/libraries/v002/library_manifest.json`
- 库 ID：`SEA-LIB-VEGETATION-GROWTH-V002`
- 数量：98 种 / 294 模型
- 外部验证：`D:/projects/sea-work/botanical_growth/v002/vegetation/verification_report.json`
- 最终验证：7093 checks / 0 failures / `passed=true`
- 几何统计：325114 triangles / 164044 polygons
- SHA-256：`eb3341d9b3c380701231e5dcfea5073f36fc320429d3e3cf918ce491a7531199`
- 最终修正：补棕榈羽叶密度与柑橘/番茄果梗；真实反例谓词捕获 temporary mesh 改 UV、vertex 根位移、同小档 scale 1/2/3 复制和缺一档。
- 两个 Blender 场景（场景名以 `tools/blender/botanical_libraries/vegetation_growth_v002.py` 代码为准）：`01_小中大对照`、`02_植物母版`

### 2.2 种植域

- Blender 源：`art_source/crops/libraries/v002/planting_library.blend`
- 组件计划：`art_source/crops/libraries/v002/component_plan.json`
- 清单：`art_source/crops/libraries/v002/library_manifest.json`
- 库 ID：`SEA-LIB-PLANTING-GROWTH-V002`
- 数量：6 种 / 18 模型
- 外部验证：`D:/projects/sea-work/botanical_growth/v002/crops/verification_report.json`
- 最终验证：1921 checks / 0 failures / `passed=true`
- 几何统计：13276 triangles / 7382 polygons（由 manifest meshes 汇总）
- SHA-256：`8831430d18cb7a8d92166b407cb926c360e22109f2f8a0601796450d5665d15d`
- 最终修正：花冠花蕾接枝、瓜果连藤与 XY 底心；真实反例谓词捕获 temporary mesh 改 UV、vertex 根位移、同小档 scale 1/2/3 复制和缺一档。
- 两个 Blender 场景（代码/计划）：`01_小中大对照`、`02_植物母版`

### 2.3 共用约束

- 无季节：两个 v002 计划与清单均为 `season_variants=false`。
- 共享色板外链：`art_source/shared/palettes/sea_cozy_8x8_512.png`。
- `PaletteUV` 逐面有面积、单格保留 8px 安全边，nearest 采样。
- 材质角色：`SEA_Matte`、`SEA_Gloss`。
- 原 v001 与原主 source 不迁移、不覆盖；v001 只作为历史/参考边界。
- 新增代码只在 `tools/blender/botanical_libraries/` 的 v002 生长模型生成、验证、渲染和登记审核入口；本轮不改任何 Godot 运行代码。

## 3. 104 种命名表

编号按“植被 001–098、作物 099–104”固定。`family` 是模型管理族，不是物种鉴定。

| 编号 | 域 | AssetID | 管理名 | family |
|---:|---|---|---|---|
| 001 | 植被 | SEA-SCENE-SOLAR-PALM | 暖岛棕榈 | palm |
| 002 | 植被 | SEA-SCENE-PFH-LEAF-CLUSTER | 花港阔叶簇 | broadleaf |
| 003 | 植被 | SEA-SCENE-PFH-VINE | 花港圆叶藤 | vine |
| 004 | 植被 | SEA-SCENE-PFH-FLOWER-CLUSTER | 花港粉白花簇 | flower |
| 005 | 植被 | SEA-SCENE-PFH-GOLD-BLOOM | 花港顶柱黄花 | flower |
| 006 | 植被 | SEA-SCENE-SOLAR-LEAF-CLUSTER | 日光阔叶簇 | broadleaf |
| 007 | 植被 | SEA-SCENE-SOLAR-VINE | 日光垂藤 | vine |
| 008 | 植被 | SEA-SCENE-SOLAR-COSMOS | 日光粉瓣花 | flower |
| 009 | 植被 | SEA-SCENE-SOLAR-DAISY | 日光白瓣花 | flower |
| 010 | 植被 | SEA-SCENE-SOLAR-GOLDFLOWER | 日光黄苞花 | flower |
| 011 | 植被 | SEA-SCENE-TFH-LEAF-CLUSTER | 热屋厚圆叶簇 | broadleaf |
| 012 | 植被 | SEA-SCENE-TFH-VINE | 热屋短茎垂叶藤 | vine |
| 013 | 植被 | SEA-SCENE-TFH-PALM | 热屋裂叶棕榈 | palm |
| 014 | 植被 | SEA-SCENE-TFH-FLOWER | 热屋粉瓣花 | flower |
| 015 | 植被 | SEA-SCENE-TFH-DAISY | 热屋六瓣白花 | flower |
| 016 | 植被 | SEA-SCENE-TFH-SPROUT | 热屋盆栽宽叶芽 | broadleaf |
| 017 | 植被 | SEA-SCENE-SBR-FOLIAGE | 繁花小屋错落叶簇 | broadleaf |
| 018 | 植被 | SEA-SCENE-SBR-PINK-FLOWER | 繁花小屋粉瓣花 | flower |
| 019 | 植被 | SEA-SCENE-SBR-DAISY | 繁花小屋白瓣小花 | flower |
| 020 | 植被 | SEA-SCENE-SBR-SPROUT | 繁花小屋盆栽嫩叶 | broadleaf |
| 021 | 植被 | SEA-SCENE-BLB-LEAF-CLUSTER | 花湾放射叶簇 | broadleaf |
| 022 | 植被 | SEA-SCENE-BLB-EDGE-CLUSTER | 花湾横向叶簇 | broadleaf |
| 023 | 植被 | SEA-SCENE-BLB-VINE-LONG | 花湾长垂藤 | vine |
| 024 | 植被 | SEA-SCENE-BLB-VINE-SHORT | 花湾短垂藤 | vine |
| 025 | 植被 | SEA-SCENE-BLB-PINK-FLOWER | 花湾亮粉花 | flower |
| 026 | 植被 | SEA-SCENE-BLB-WHITE-FLOWER | 花湾五瓣白花 | flower |
| 027 | 植被 | SEA-SCENE-BLB-YELLOW-BUDS | 花湾小黄苞 | flower |
| 028 | 植被 | SEA-PLANT-COMMON-PLANT_01_5L | 通用细叶竖簇 | grass |
| 029 | 植被 | SEA-PLANT-COMMON-PLANT_02_3L | 通用短直叶 | grass |
| 030 | 植被 | SEA-PLANT-COMMON-PLANT_03_4L | 通用中直叶 | grass |
| 031 | 植被 | SEA-PLANT-COMMON-PLANT_05_4L | 通用暖色直叶 | grass |
| 032 | 植被 | SEA-PLANT-COMMON-PLANT_15_8L | 通用扇面阔叶 | broadleaf |
| 033 | 植被 | SEA-PLANT-COMMON-PLANT_18_3L | 通用低矮圆叶 | broadleaf |
| 034 | 植被 | SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_04_8L | 暖港高位阔叶一 | broadleaf |
| 035 | 植被 | SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_07_6L | 暖港高位阔叶二 | broadleaf |
| 036 | 植被 | SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_11_3L | 暖港横展宽叶一 | broadleaf |
| 037 | 植被 | SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_12_3L | 暖港横展宽叶二 | broadleaf |
| 038 | 植被 | SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_13_8L | 暖港高位阔叶三 | broadleaf |
| 039 | 植被 | SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_19_10L | 暖港高位密叶 | broadleaf |
| 040 | 植被 | SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_20_10L | 暖港窄杆高叶 | reed |
| 041 | 植被 | SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_33_9L | 暖港深展阔叶 | broadleaf |
| 042 | 植被 | SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_34_5L | 暖港中低圆叶 | broadleaf |
| 043 | 植被 | SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_35_7L | 暖港高柱叶穗 | palm |
| 044 | 植被 | SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_36_3L | 暖港短杆细叶 | grass |
| 045 | 植被 | SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_37_3L | 暖港小幅圆叶 | broadleaf |
| 046 | 植被 | SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_38_3L | 暖港侧向长叶 | broadleaf |
| 047 | 植被 | SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_39_3L | 暖港低矮叶团 | moss |
| 048 | 植被 | SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_40_4L | 暖港平台横叶毯 | broadleaf |
| 049 | 植被 | SEA-PLANT-ZONES-ZONE1_HOME_HARBOR-PLANT_41_5L | 暖港平台宽叶毯 | broadleaf |
| 050 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_00_4L | 弧农高位叶簇一 | broadleaf |
| 051 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_06_6L | 弧农厚叶簇一 | broadleaf |
| 052 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_08_4L | 弧农窄穗高叶 | reed |
| 053 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_09_12L | 弧农高位叶簇二 | broadleaf |
| 054 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_10_5L | 弧农高位阔叶四 | broadleaf |
| 055 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_14_3L | 弧农垂线细叶 | vine |
| 056 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_16_6L | 弧农厚叶簇二 | broadleaf |
| 057 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_17_14L | 弧农高穗叶簇 | grass |
| 058 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_21_4L | 弧农小幅叶簇 | broadleaf |
| 059 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_22_11L | 弧农高位长叶 | broadleaf |
| 060 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_23_3L | 弧农中高叶簇 | broadleaf |
| 061 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_24_6L | 弧农高位圆叶 | broadleaf |
| 062 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_25_7L | 弧农宽面叶簇 | broadleaf |
| 063 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_26_6L | 弧农深幅叶簇 | broadleaf |
| 064 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_27_13L | 弧农窄柱高叶 | reed |
| 065 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_28_7L | 弧农细柱长叶 | reed |
| 066 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_29_6L | 弧农窄叶高束 | grass |
| 067 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_30_3L | 弧农短窄叶束 | grass |
| 068 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_31_8L | 弧农细长叶束 | grass |
| 069 | 植被 | SEA-PLANT-ZONES-ZONE3_ARC_FARM-PLANT_32_7L | 弧农横展宽叶 | broadleaf |
| 070 | 植被 | SEA-SCENE-B1109A-LEAF-CLUSTER | B1109A宽叶簇 | broadleaf |
| 071 | 植被 | SEA-SCENE-B1109A-SUCCULENT | B1109A莲座叶 | broadleaf |
| 072 | 植被 | SEA-SCENE-B1109A-VINE | B1109A垂藤 | vine |
| 073 | 植被 | SEA-SCENE-B1109A-CITRUS | B1109A柑橘枝 | broadleaf |
| 074 | 植被 | SEA-VEG-GRASS-SOFT | 柔叶草簇 | grass |
| 075 | 植被 | SEA-VEG-MOUND-SOFT | 柔叶层叠草堆 | grass |
| 076 | 植被 | SEA-VEG-MOSS-SOFT | 柔片细苔 | moss |
| 077 | 植被 | SEA-FISHERY-TURF | 渔场软草苔 | moss |
| 078 | 植被 | SEA-FISHERY-REEDS | 渔场饱满芦苇 | reed |
| 079 | 植被 | SEA-SCENE-GKS-FOLIAGE | 商亭球簇绿植 | broadleaf |
| 080 | 植被 | SEA-SCENE-ORF2-GRASS | 屋顶半野草皮 | grass |
| 081 | 植被 | SEA-SCENE-ORF2-TUFT | 屋顶丛生野草 | grass |
| 082 | 植被 | SEA-SCENE-ORF2-VINE | 屋顶墙角垂藤 | vine |
| 083 | 植被 | SEA-SCENE-ORF2-PLANT | 屋顶厚叶盆栽 | broadleaf |
| 084 | 植被 | SEA-SCENE-ORF2-MOSS_CLUSTER | 屋顶不规则苔片 | moss |
| 085 | 植被 | SEA-SCENE-ORF2-TURF_CORE | 屋顶中央草芯 | grass |
| 086 | 植被 | SEA-SCENE-NGQ-037 | 霓虹卷叶菜簇 | broadleaf |
| 087 | 植被 | SEA-SCENE-NGQ-038 | 霓虹结果藤株 | tomato |
| 088 | 植被 | SEA-SCENE-NGQ-039 | 霓虹圆叶菜簇 | broadleaf |
| 089 | 植被 | SEA-SCENE-NGQ-040 | 霓虹宽叶观赏草 | grass |
| 090 | 植被 | SEA-SCENE-NGQ-041 | 霓虹成串藤蔓 | vine |
| 091 | 植被 | SEA-SCENE-NGQ-042 | 霓虹垂挂灌木 | broadleaf |
| 092 | 植被 | SEA-SCENE-NGQ-043 | 霓虹粉白花簇 | flower |
| 093 | 植被 | SEA-SCENE-NGQ-044 | 霓虹长叶草簇 | grass |
| 094 | 植被 | SEA-SCENE-SCITY-MOSS-PATCH | 沉城攀附海藻苔 | moss |
| 095 | 植被 | SEA-SCENE-SCITY-KELP-CLUMP | 沉城宽叶海藻 | kelp |
| 096 | 植被 | SEA-SCENE-FSH-FOLIAGE | 浮店宽叶盆栽 | broadleaf |
| 097 | 植被 | SEA-SCENE-FSH-FLOWERS | 浮店暖黄花簇 | flower |
| 098 | 植被 | SEA-DECO-WATER-LILY | 缺口荷叶 | water_leaf |
| 099 | 作物 | SEA-CROP-LETTUCE | 生菜 | lettuce |
| 100 | 作物 | SEA-CROP-TOMATO | 番茄 | tomato |
| 101 | 作物 | SEA-CROP-PUMPKIN | 南瓜 | pumpkin |
| 102 | 作物 | SEA-CROP-FLOWER-BLUE | 蓝星花 | flower |
| 103 | 作物 | SEA-CROP-FLOWER-SUN | 晨光花 | flower |
| 104 | 作物 | SEA-CROP-FLOWER-CORAL | 珊瑚花 | flower |

## 4. 三档形态定义与使用方法

### 4.1 植被

按 `component_plan.json` / `library_manifest.json` 的 `growth_axis` 使用：

- `small`（小）：保留识别轮廓的少量叶/枝/花器官，冠幅和高度最小。
- `medium`（中）：增加叶片、分枝或展开程度，形成独立的中档拓扑。
- `large`（大）：达到该管理名的完整冠幅；需要时加入更多分枝、花蕾或果实，不能只把小档等比放大。

具体植物的器官数量、目标高度/冠幅、Collection 名称和锚点以 v002 `component_plan.json` 为准。藤蔓挂点在顶部，使用时把顶心挂到墙、栏杆或悬挂槽；地生件把底心落到场景表面。

### 4.2 作物

v002 作物模型通过三档拓扑表达静态模型阶段：

- 生菜：少叶幼菜 → 舒展菜叶 → 多层放射结球。
- 番茄：单主茎三叶芽 → 二分枝与小果/花序 → 多层叶与果串。
- 南瓜：短藤双叶芽 → 一条匍匐藤与五片叶 → 粗主藤、多侧枝与瓜果。
- 蓝星花：低矮双叶芽 → 分叉花茎与小花蕾 → 三茎双花。
- 晨光花：直立双叶芽 → 直立茎与花蕾 → 高直主茎双花。
- 珊瑚花：三叉嫩叶芽 → 三叉茎与小花 → 多叉茎与杯状花簇。

这组 v002 模型不是对 v001 `seed` / `sprout` / `leaf` / `harvest` 四阶段运行资源的重命名；本次已完成源级登记，运行侧仍沿用既有四阶段契约，后续接入映射与运行验收需另行处理。

## 5. 生产与验证入口

1. 读取 GDD 导航、`docs/features/asset/spec.md`、三本功能账本和本规范，确认 AssetID 与所有权。
2. 读取 `plant_names_v002.json`、对应 v002 `component_plan.json` 与 `library_manifest.json`；不得新建重复主记录。
3. 运行 v002 模型生成/审核入口：`tools/blender/botanical_libraries/` 下的 `vegetation_growth_v002.py`、`crop_growth_v002.py` 及对应 `verify_*_growth_v002.py`；渲染入口为对应 `render_*_growth_v002.py`。
4. 以最终 Blender 源报告为当前模型证据：植被 `7093/0`，作物 `1921/0`，合计 `9014/0`；不要用 R63 的 v001 或 v002 中间批统计冒充最终结果。
5. 检查三档是否齐全、Collection/AssetID/管理名一致、根锚点正确、拓扑确实变化、PaletteUV 面积与 8px 安全边成立、材质角色正确、没有盆土平台手持或季节分支。
6. 模型源验证通过不等于 Godot 接入、风系统、LOD、性能或用户审美全量通过；当前模型交付已完成，运行 GLB/PackedScene、运行路径、运行四阶段覆盖、风/LOD/Scatter、低端设备性能、显存/帧率仍按各自边界验收。29图已完整生成，总览与部分近景由主线程审阅，不签312个模型全细节用户审美。

## 6. 当前未验收边界

- v002 模型交付、源验证、登记和交付审计已完成；不把模型交付冒充 Godot 运行接入或完整用户审美签署。
- 原 v001 与原主 source 未迁移；不以 v002 源模型存在宣称历史运行资产已替换。作物 v001 四阶段继续保留，v002 三形态不代表运行四阶段覆盖。
- 全库契约已由 `audit_growth_v002.py --run-contracts` 实跑；`D:/projects/sea-work/botanical_growth/v002/contract_status.json` 记录 sync/check 均 exit1，日志在 `contracts_sync.log` 与 `contracts_check.log`，根因是既有 `SEA-SCENE-WATER-BUILDING-001` manifest 在 `scripts/check_feature_contracts.py:232` 缺 `asset_ledger` 的 KeyError。未发生同步写入，不代表全库通过。
- R63 `v001` 原始归档保持原样，本轮只回填 R64 最终证据。

## 7. 最终登记与验证

### 7.1 最终登记

- 登记文件：`D:/projects/sea-work/botanical_growth/v002/registration.json`。
- `register_growth_v002.py --write` 已完成登记：104 个原 AssetID 增加 v002 refs，分域为 `scenes=95`、`crops=6`、`vegetation=3`；主记录新增0，`current_source_index` 不变，旧字段与既有 v001 `library_refs` 全部不变。
- `changed_asset_ids=6` 仅表示最终作物重建后的 6 条 hash 刷新；首轮 104 个 AssetID 已完成登记，不是缺少98个。
- 备份目录：`D:/projects/sea-work/botanical_growth/v002/registration_backup`。如需回滚，只撤销本轮新增 v002 refs，不主动执行回滚；不得删除或改写旧字段、旧 v001 refs 或主记录。

### 7.2 最终验证与审计

- 植被报告：`D:/projects/sea-work/botanical_growth/v002/vegetation/verification_report.json`，7093/0，325114 triangles、164044 polygons，hash `eb3341d9b3c380701231e5dcfea5073f36fc320429d3e3cf918ce491a7531199`。
- 作物报告：`D:/projects/sea-work/botanical_growth/v002/crops/verification_report.json`，1921/0，13276 triangles、7382 polygons（manifest meshes 汇总），hash `8831430d18cb7a8d92166b407cb926c360e22109f2f8a0601796450d5665d15d`。
- 两库源验证合计9014/0；`D:/projects/sea-work/botanical_growth/v002/delivery_audit.json` 为2077/0，检查104个计划成员、登记前旧字段/v001 refs、两个 v001 与230项旧计划保护、R64账本追加及29图完整性。
- 预览来源：`D:/projects/sea-work/botanical_growth/v002/outputs/三档植物模型_总览.jpg`、`D:/projects/sea-work/botanical_growth/v002/outputs/植物三档_分类对照.jpg`。29图由植被17图（4总览、3分页、10类近景）和作物12图（6对照、6近景）组成；总览与部分近景已主线程审阅，不签312个模型全细节用户审美。
- 代码范围：`tools/blender/botanical_libraries/vegetation_growth_v002.py`、`crop_growth_v002.py`、对应 build/verify/render 入口、`register_growth_v002.py`、`audit_growth_v002.py`；原 Godot 运行代码未改。
- 契约状态：`D:/projects/sea-work/botanical_growth/v002/contract_status.json`；sync/check 均 exit1，`contracts_sync.log` 与 `contracts_check.log` 均记录 `scripts/check_feature_contracts.py:232` 的 `KeyError: 'asset_ledger'`，未写同步；R64 模型交付和登记不受该既有全库阻塞否定。
