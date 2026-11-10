# 2026-11-10 楼房工坊 V1 收尾记录

## 1. 本轮范围

本轮完成 SEA-WORKSHOP V1 的工程文档收尾与候选资产登记说明。文档范围严格限定为：

- `docs/features/workshop/spec.md`
- `docs/features/workshop/ledger.md`
- `docs/features/tool/ledger.md`
- `docs/features/asset/spec.md`
- `docs/features/asset/ledger.md`
- 本开发记录

本轮不修改 GDD、JSON、Godot 代码、主场景或其他文档；不运行 Godot、runner 或脚本。工作区已有的并行修改和新增文件不作清理、不作覆盖。

## 2. 已实现的 V1 结构

当前实现入口为：

```text
godot/src/workshop/
├─ recipe.gd
├─ catalog.gd
├─ generator.gd
├─ mesh_builder.gd
├─ session.gd
├─ store.gd
├─ preview.gd
├─ panel.gd
└─ host.gd

godot/data/workshop/
├─ standards_v1.json
├─ catalog_v1.json
└─ palette_cells_v1.json

godot/scenes/tools/building_workshop.tscn
```

暂停菜单到工坊是 Main/menu 薄接线：暂停菜单发出 `building_workshop` 命令，Main 调用 `WorkshopHost`，Host 管理 `WorkshopPanel` 生命周期。正式世界、玩家建造布局、库存、世界时间、主存档和主场景手摆 transform 不归工坊所有。

工坊预览自建独立 SubViewport、相机、灯光、选择高亮、线框和碰撞覆盖。打开时保存原暂停值并冻结世界，关闭时恢复原暂停值；编辑器输入由模态端口拦截，不把预览输入继续传给世界。

## 3. 配方、目录和生成范围

### 3.1 配方和编辑

V1 配方使用 `sea.workshop.building_recipe` schema version 1，按 `building_id` 独立管理一栋楼。当前能力包括：

- rectangle 与组合 L 形；
- 默认 3-floor 样例；校验上限为 1–8 floor；
- 宽、进深、层高、板厚、墙厚、主柱、窗洞、门洞和开间参数；
- 逐层覆盖与逐立面覆盖；
- 稳定 `slot_id`，不以数组位置作为唯一身份；
- 单槽组件替换与局部偏移；不兼容槽族明确拒绝；
- 反复打开、新建、加载、另存楼房 ID、导出、撤销、重做、取消和未保存退出提示；
- structure、damage、vegetation 三个独立 seed，同一配方与 catalog 输出确定，不消耗玩法随机流。

8-floor 是参数校验的上限，不是所有尺寸组合都可用。宽深、开间、门窗净洞、节点预算和三角面预算会共同限制实际可用组合；不能把 8-floor 描述成任意尺寸均可生成。

### 3.2 standards 和风格边界

`standards_v1.json` 记录机器表来源、默认层高 5.1m、板厚 0.2m、净高关系、主柱 0.5m、门框外尺寸与净洞分离、默认三段倒角以及局部厚度约束。

V1 默认 `bevel_width=0.06` 是原生自动档，不是完整美术 Skill 的最终实现。当前标准状态按 `partial_source_style` 记录：分件 rho、最长轴等 Skill 风格语法尚未完整实现，不能把参数生成器专项通过写成美术终验通过。

共享色板使用真实 UV，`palette_cells_v1.json` 记录 8×8 格、8px safe inset 以及来源色板哈希。工坊没有把共享材质或 Mesh 改写为编辑态副本。

### 3.3 老化、破损和植物

aging 与 damage 分开保存，并分别使用 seed。damage 可受控产生破窗、断墙、屋顶片段缺失等结果；缺失几何同步影响同源局部碰撞，断口保留封边。V1 不做实时刚体倒塌。

catalog 当前提供四类程序植物：`shrub`、`moss`、`vine`、`tree`。植物支持 small、medium、large 三种体量、密度、独立 seed、语义区域和局部锁定/排除。语义区域包括屋顶、外檐、墙角等最终结构区域；植物、花盆和建筑保持独立。

复杂根系贴墙、墙面刷苔、四季和作物玩法不在当前实现中。当前植物系统不是全能植物生成器。

## 4. 空间职责和导出边界

V1 使用三个明确 profile：

- `above_water`：水上功能候选，可声明局部人物碰撞、站立面和水面阻挡来源；
- `scenic_underwater`：水下观赏，整个子树不声明碰撞、导航、可走面、交互、产出、玩法状态或岸线来源；
- `dive_static`：独立潜水静态候选，使用独立碰撞层和局部空间声明。

生成器以分件静态结构输出碰撞和空间声明，门洞、院落、破口不是整栋 AABB 或单凸包封死。`walk_surfaces` 与 `water_blockers` 只是候选产物的局部声明，不代表正式世界或导航自动接入。没有 stairs 的楼不签署整楼可达；视觉楼板存在也不能自动推导完整楼层通行。

导出结果是无工坊重建脚本的静态 TSCN，按构件/材质分块，植物保留独立实例，节点 owner 和 slot/component metadata 完整保存。候选导出先写临时目录、重载比对 JSON 和场景，再提交：

```text
user://building_workshop/<building_id>/revision_NNNN/
├─ building.recipe.json
├─ building.tscn
├─ catalog_snapshot.json
├─ candidate_manifest.json
└─ ledger.json
```

revision 版本化且不覆盖历史；路径段、脚本/资源引用和路径穿越由 Store 拒绝。候选 ledger 明确 `candidate_only` 和 `exported_pending_project_registration`，不会自动写仓库正式账本。

## 5. 正式样例和资产登记

本轮正式样例只有两个主 AssetID：

- `SEA-SCENE-WORKSHOP-SAMPLE-001`：海风公寓；
- `SEA-SCENE-WORKSHOP-SAMPLE-002`：潮痕旧楼。

源目录分别为：

```text
art_source/scenes/building_workshop/v001/workshop_sample_001/
art_source/scenes/building_workshop/v001/workshop_sample_002/
```

每楼登记的候选文件为 recipe、静态 TSCN、catalog snapshot、candidate manifest 和 ledger 五件。正式源的 `static_scene` 字段是真实源路径，`runtime_path` 保持 `null`；这两个样例没有放入主场景，也没有冒称已成为正式运行资源。

当前登记还保留：

- `building_class=above_water`；
- `water_layer=surface`；
- `water_layer_role=entity`；
- `source_type=project_authored_native_Godot_source_no_Blender_or_GLB`；
- 正式主记录与 `current_source_index` 仅新增这两个样例，above-water 视图只增加这两个主记录；
- 工坊 catalog 内 10 个组件 ID 是当前 scope 的内部稳定 key，不拆为 10 个独立正式 Asset 主记录，未来若有独立制作或正式资源需求再另行引用和登记。

回滚/登记备份位置：

```text
D:/projects/sea-work/verification/20261110-221503-workshop-palette-ui-final-3030ca/project/outputs/registration_backup
```

## 6. 已有专项证据

已读取并按报告实际值记录：

### 6.1 核心 roundtrip

报告：

```text
D:/projects/sea-work/verification/20261110-212901-workshop-core-roundtrip-9e6e3c/report.json
```

- `workshop-rules`：`exit_code=0`、`passed=true`、0 unexpected errors；
- `workshop-deep`：`exit_code=0`、`passed=true`、0 unexpected errors。

### 6.2 最终视觉和样例

报告：

```text
D:/projects/sea-work/verification/20261110-221503-workshop-palette-ui-final-3030ca/report.json
```

- `visual-workshop`：`exit_code=0`、`passed=true`；日志实际为 **104 checks / 0 failures**；
- `workshop-samples`：`exit_code=0`、`passed=true`；日志实际为 **45 checks / 0 failures**；
- 视觉请求档位包含 1280×800、1600×1000、1920×1080；截图覆盖正面、背面、L 形俯视、破损选中、碰撞覆盖和透视。

视觉明细报告：

```text
D:/projects/sea-work/verification/20261110-221503-workshop-palette-ui-final-3030ca/project/outputs/workshop_report.json
```

其中记录 104 项、无 failures、`status=passed`，但同时标注 `not_run_in_authoring_session=true`；因此这里仅签该隔离 runner 的真实渲染证据，不扩展为用户美术终验。

## 7. 主集成未签全通过

正式 Main 集成当前刚完成 25 checks、3 failures。失败原因已定位为测试错误地假定 `LineEdit Ctrl+Z` 不会改变文本，不应把该批次改写成工坊功能失败，也不能在测试未修正、未重跑前签署全通过。

主线程应修正测试假设后重跑，并将最终证据回填到：

```text
D:/projects/sea-work/building_workshop/v001/delivery_report.json
```

在该回填完成前，本轮工程状态使用 `implemented_pending_acceptance`；R12 的最终集成、最终 delivery_report 数值、性能、正式世界/导航接入和用户美术终验均保持待验。没有为这些项目编造 status、计数或通过结论。

## 8. 当前结论

SEA-WORKSHOP V1 已具备可打开的独立楼房编辑体系、版本化 recipe、稳定 catalog/slot、局部覆盖、撤销历史、确定性生成、破旧与植物参数、三空间 profile、静态候选导出和两个正式候选样例登记。

它仍不是任意旧楼反推器、不是全能建筑雕塑器、不是完整 Blender/02b 美术生产链，也不是正式世界/导航自动接入器。`planned` 只保留给尚未实现的设计目标；本轮已落地但尚未完成主线程/产品验收的部分按 `implemented_pending_acceptance` 记录。
