# 2026-11-10 两份专用 Blender 模型组件集合存放

## 1. 目的与范围

本记录对应 `SEA-ASSET-R63`，承接 `SEA-ASSET-R49` 的植被生产协议、`SEA-ASSET-R30` 的作物资产域边界，以及 `SEA-CROP-R06` / `SEA-CROP-R15`、`SEA-FARM-R11/R13/R17` 的既有所有权。最终结果是两份专用 Blender 成品完成可追溯源归档、源级验证和库引用登记；本轮未修改 GDD、正式玩法或运行资源。三域既有资产 JSON 仅为原 AssetID 增加 `library_refs`，同时新增生产提取脚本与 runner 入口。

| 集合 | 源文件 | 内容与规模 | 当前性质 |
|---|---|---|---|
| 植被库 | `art_source/vegetation/libraries/v001/vegetation_library.blend` | `SEA-LIB-VEGETATION-V001`；98 AssetID、98 组件 Collection、332 网格、149036 triangles / 80328 polygons | source-only 归档；不等于 Godot 接入或风系统完成 |
| 种植库 | `art_source/crops/libraries/v001/planting_library.blend` | `SEA-LIB-PLANTING-V001`；6 品种×4 阶段=24 组件＋2 设施＋6 手持＋2 装配，共34 Collection；8 原资产ID、459 网格、13364 triangles / 11000 polygons | source-only 归档；不取代三花 Godot 程序源 |

两个文件的真实场景名为 `01_组件总览_只摆实例`（展示实例）和 `02_组件母版_按AssetID追加`（组件母版），不是字面 `Scene01` / `Scene02`；组件 Collection 已 `AssetMark`。展览统一缩放只作用于展示，不改变母版；植物按 6 个语义族分组，每组不超过 50 个组件。未接入源单独标注，不与正式运行资产混记。

## 2. 来源与真实性边界

- 三花、42 个原版植物、荷叶、框、平台和手持来自真实 Godot 的静态编辑快照；原程序源保持权威，不把快照冒称原有原创 Blender Blend。
- 旧 `PaletteUV` / `BotanicalUV` / 顶点色 / `WindData` 保留。图片只保留外链，不复制进集合；不迁移 Godot 风 shader、运行绑定或玩法逻辑。旧深色细件保持 `mesh.bin` 原有形态，不重制；档案用途不等于新审美通过。
- `art_source/vegetation/libraries/v001/component_plan.json`、两份 `library_manifest.json`、`tools/blender/botanical_libraries/{prepare,build,verify,render,register}.py` 与 `godot/tools/extract_botanical_libraries.gd` 负责计划、构建、验证、渲染、登记和提取追溯。`register.py --write` 已实际成功，结果见 `D:/projects/sea-work/botanical_libraries/v001/registration.json`。
- 本轮保护 109 项原生来源输入与 230 项计划输入。三域既有资产 JSON 仅增加 `library_refs`：106 个原 AssetID，分布为 `scenes=97`、`crops=6`、`vegetation=3`；旧 `source` / `hash` / `stage` / `runtime` 字段、主记录数量和 `current_source_index` 均保持不变，不重复登记库成员。三花与 `farm_plot` 实际 hash 相对登记 hash 的既有差异，以及 ORF runtime v004 / ledger v003 差异，按已有 `preserved_drift` 保留。
- Godot 侧代码变化仅为生产提取脚本与 runner 入口；Blender 建库、验证、渲染与登记脚本保存在 tools/blender/botanical_libraries；未修改正式玩法或运行资源。

## 3. 使用与维护

1. 打开集合时以 `02_组件母版_按AssetID追加` 组件母版为编辑对象，以 `01_组件总览_只摆实例` 做展示和四视图渲染；不得把展示缩放回写到母版。
2. 新增或替换组件前先更新对应 `component_plan.json` / `library_manifest.json`，确认 AssetID、Collection、来源、语义族和未接入状态，再使用配套工具；不手工批量重命名或跨域复制资产记录。
3. 源修订必须另存版本或保留 `previous_sources` 关系，先保护源与色板 hash，再做独立重开、网格/UV/顶点属性复核。正式运行路径、Godot 程序源和玩法状态由各自所有者维护。
4. 植被表现后续仍遵循[植被视效制作规范](../standards/植被视效制作规范.md)的 `PaletteUV`、`WindData`、LOD、包络、材质角色和共享风函数协议；集合存放本身不启用风、不生成碰撞、不生成导航、不写存档。
5. 种植库不接管 Farm 或 Crop 的状态。四阶段形态、种植规则、收获物和手持动作继续以既有 Godot/Crop/Farm 所有者为准。

## 4. 差异边界与不纳入本轮的事项

| 事项 | 本轮处理 | 明确不做 |
|---|---|---|
| 组件集合存放 | 两份 Blend、真实场景名、AssetMark、组件规模和语义分组入文档 | 不写 GDD 或正式玩法/运行资源 |
| Godot 静态快照 | 保留来源说明与原程序源权威关系 | 不宣称快照为原创 Blend，不替换程序源 |
| UV/顶点属性/图片 | 保留旧属性和外链关系 | 不迁移风 shader，不复制图片，不重写旧通道 |
| 资产登记 | `register.py --write` 已成功，为106个原AssetID增加 `library_refs` | 不重复登记库成员，不改旧 source/hash/stage/runtime、主记录数量或 current_source_index |
| 历史 hash 漂移 | 记录并保持 `preserved_drift` | 不改三花、`farm_plot`、ORF 原字段，不批量接受无关漂移 |
| 全库基线问题 | 记录为本轮边界 | 不修 `SEA-SCENE-WATER-BUILDING-001` 登记为 manifest 的 `component_plan.json` 缺少顶层 `asset_ledger`、`source_index` 1037 对账本 1038 缺同一项，也不批量接受无关 hash |
| 视觉验收 | 8个Cycles PNG已生成，两个overview与植被top已实际审阅；材质提取与矩阵/色彩口径已修正 | 不外推为8图所有细节全目视通过；用户美术终审仍不签 |

## 5. 验证分列

### 5.1 最终提取结果

最终报告：`D:/projects/sea-work/verification/20261110-095851-botanical-final-8de438/report.json`。

- 专项：`botanical-library-extract`
- 实际结果：292 checks / 0 failures，exit 0，`passed=true`，`completion_marker=true`
- 运行属性：headless；只证明本次 Godot 提取入口成功，不证明 Blend 源级验收、运行接入、性能、权属或用户美术验收。

### 5.2 最终源验证结果

最终报告：`D:/projects/sea-work/botanical_libraries/v001/source_verification.json`。

- 9047 checks / 0 failures，`passed=true`
- 保护输入：109 项原生来源输入 + 230 项计划输入
- 两份 Blend 最终哈希：植被库 `8703643aaae74e092401d97660621f9f9c70929e14cb11321055247657f4f407`；种植库 `dbd4a94c125d775de639e5e14e76d87c1887c4815e6a2bd7fe975e5aee4e6249`
- 首轮 8631 checks 的 `selftest needs actual color attribute` 仅作为历史过程保留；修正临时颜色反例后已由最终 9047/0 覆盖当前状态，不据首轮失败签署当前失败。

### 5.3 登记结果

登记报告：`D:/projects/sea-work/botanical_libraries/v001/registration.json`。

- `register.py --write` 实际成功，`write=true`、`passed=true`
- 引用 106 个原 AssetID：`scenes=97`、`crops=6`、`vegetation=3`
- 仅新增 `library_refs`；`primary_record_count_unchanged=true`、`original_source_runtime_stage_unchanged=true`、`no_current_source_index_mutation=true`
- 不重复登记库成员；三域既有 JSON 变化限于上述 `library_refs`

### 5.4 渲染与目视

8 个最终四视图 PNG 位于：

`D:/projects/sea-work/botanical_libraries/v001/outputs/{vegetation,planting}_{overview,top,back,side}.png`

已使用 Cycles 完成生成。两个 overview 与植被 top 已实际审阅；不把该审阅范围外推为 8 图所有细节均完成目视签署。土框与平台白模缺材质问题已修正，Godot `material_override` 与 MultiMesh 总覆盖已纳入提取口径；矩阵口径、sRGB→linear 与共用色板引用已统一。旧深色细件保持 `mesh.bin` 原有形态，不重制；档案用途不等于新审美通过。用户美术终审、性能与运行接入不签。

### 5.5 全库命令与阻塞

已实际执行全库 sync/check，日志如下：

- `D:/projects/sea-work/botanical_libraries/v001/contracts_sync.log`
- `D:/projects/sea-work/botanical_libraries/v001/contracts_check.log`

两者均在 `check_feature_contracts.py:232` 因既有 `SEA-SCENE-WATER-BUILDING-001` manifest 缺 `asset_ledger` 触发 `KeyError: 'asset_ledger'`，exit 1，未发生同步写入。不能以 shell 最后 `printf` 的 exit 0 冒称 check 通过。本轮不修该全库基线问题、不批量接受无关 hash 漂移。

## 6. 文档与账本最终回填

本轮仅编辑以下允许文件，并采用账本末尾追加；以下内容已按最终报告、登记结果和全库日志回填：

- `docs/standards/植被视效制作规范.md`：新增“2026-11-10 两份专用 Blender 模型组件集合归档协议”。
- `docs/features/asset/spec.md`：新增 `SEA-ASSET-R63` 设计条款。
- `docs/features/asset/ledger.md`：新增 `SEA-ASSET-R63` 实施与证据条款。
- `docs/features/ambient/ledger.md`：引用 `SEA-ASSET-R63`，保留 `SEA-AMBIENT-R06–R16` 未验边界。
- `docs/features/crop/ledger.md`：引用 `SEA-ASSET-R63`，保留 `SEA-CROP-R06` 与三花 R15 的源/运行边界。
- `docs/features/farm/ledger.md`：引用 `SEA-ASSET-R63`，保留 Farm 规则所有权和 `farm_plot` 的既有 drift。

未修改登记头、原有标题/登记头、GDD、正式玩法或运行资源；三域既有资产 JSON 仅发生 `library_refs` 增量，Godot 代码仅新增生产提取脚本与 runner 入口；配套 Blender 脚本在 tools/blender/botanical_libraries。其他文件不在本轮文档编辑范围内。

## 7. 追加取景与交付复核

八视图按实际相机投影重新适配包络，修正侧视裁切；接触表只用于总览检查，不替代逐件近景美术终审。最终范围审计由 `tools/blender/botanical_libraries/audit_delivery.py` 执行，报告写入 `D:/projects/sea-work/botanical_libraries/v001/scope_audit.json`：比较登记前快照，核对三域旧主字段、原账本历史前缀、源保护和八张渲染。最终范围审计实际 **1392 checks / 0 failures，passed=true，exit 0**；三域主字段与四份账本历史前缀保持。重新适配后的八视图接触表已核对，无侧视裁切或缺图；仍不作为逐件近景美术终审。两份 Blender 的有效 Collection 可在空白文件通过“文件 → 追加 → Collection”单独使用；默认打开的是总览，切到母版场景后按 AssetID 编辑。图片仍依赖工程原有外链文件，单拷 Blend 到工程之外需要同时保持依赖路径，不以本次外链归档冒称可脱离工程的打包资产。
