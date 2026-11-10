# SEA-CROP · 作物品种与四阶段形态 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-crop) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-CROP",
  "status": "implemented",
  "owner": "CropCatalog / CropView",
  "code_paths": [
    "godot/src/crops",
    "godot/assets/data/crops.json",
    "godot/scenes/crops",
    "godot/assets/models/crops",
    "art_source/crops",
    "assets/registry/ledgers/crops.json"
  ],
  "verification": [
    "crops",
    "visual-crops",
    "farming",
    "harvest-receive",
    "visual-harvest-receive",
    "modules",
    "structure",
    "flower-crops"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-CROP-R01 | 已实现：`crops.json` 为唯一品种源，含 produce / model / stage_labels；代码无写死品种名 | `crops` 目录断言 + [本轮交付](../../development/2026-10-29_crop_formalization.md) |
| SEA-CROP-R02 | 已实现：四阶段固定，映射公式在 `CropStage.stage_for_progress` | `crops` 阶段映射 4 组断言 |
| SEA-CROP-R03 | 已实现：12 个阶段节点独立，切换只改 visible | `crops` 节点名与唯一可见性断言 |
| SEA-CROP-R04 | 已实现：`farm_plot.gd` 不再构造作物网格，只挂 CropView | `farming` 回归 + 代码检索 |
| SEA-CROP-R05 | 已实现：CropCatalog 无节点/单例依赖；Farm 仅查询数值 | `modules` 隔离用例 |
| SEA-CROP-R06 | 源与导出已落地；12 阶段真实渲染已取得（正视图 + 俯视图）；Blender 源级「保存重开 + 四视图」仍**未执行** | `visual-crops` 两张渲染图：[正视图](../../development/evidence/2026-10-29_crop/crops_stage_grid.png) / [俯视图](../../development/evidence/2026-10-29_crop/crops_stage_ortho.png) |
| SEA-CROP-R07 | 已实现：缺模型保留上一阶段并只警告一次 | `crops` 降级用例 |
| SEA-CROP-R08 | 已实现：seed 类别、produce 存在、yield 键一致由 `validate()` 断言 | `crops` 一致性断言 |
| SEA-CROP-R09 | 已实现：三品种 leaf 轮廓不同（放射结球 / 直立分层 / 匍匐藤蔓） | 阶段几何差异断言 + 待补真实渲染 |
| SEA-CROP-R10 | 已实现：`ledgers/crops.json` 独立分账本 3 行，GLB 进运行清单 | `structure` 契约检查 |
| SEA-CROP-R11 | 已实现：seed 0.07 → sprout 0.45 → leaf 0.48 → harvest 0.80（生菜高度，米）；首次浇水当次可见 | `visual-crops` 四阶段对照图 + `visual-plot-shipping` 游戏内 day-1 截图 |
| SEA-CROP-R12 | 已实现：`FRAME_ENVELOPE` 构建期断言，12 阶段全部 ≤ 1.30 × 0.90 | 构建输出 `all stages within budget`，越界即 exit 2 |
| SEA-CROP-R13 | 已实现：`farm_plot.gd` 按 `1/scale.y` 补偿；`_pop` 基于基准缩放 | `visual-plot-shipping` 游戏内地格截图 |
| SEA-CROP-R14 | 已实现；三品种从成熟阶段复制一份可收物，只含视觉，无碰撞；真实渲染已核对，原四阶段资源未改 | `harvest-receive`、`visual-harvest-receive`；[本轮交付](../../development/2026-10-30_harvest_receive_animation.md) |

## 当前接口清单

CropCatalog：ids / has / get_crop / definitions / stage_labels / model_scene / produce_of / stage_for_progress / validate / reload。
CropView：show_crop / set_stage / set_dry / current_stage / current_crop。
CropStage：SEED / SPROUT / LEAF / HARVEST / KEYS / NODE_NAMES / count / key_of / label_of。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；本功能不持有存档字段，地格状态仍由 Farm 的 farm v2 快照保存。

## 验证记录

当前入口：`python3 scripts/run_verification.py crops visual-crops farming modules`。

- 2026-10-29 验证：见 [本轮交付记录](../../development/2026-10-29_crop_formalization.md)，逐项记录退出码、失败项与未执行项。

| 项 | 结果 |
|---|---|
| `crops` | exit 0，`[crops] 60 checks, 0 failed` |
| `visual-crops` | exit 0，12 阶段渲染 + 正/俯视图，`[crops-render] 0 failures` |
| `farming` | exit 0 |
| `modules` | exit 0 |
| `visual-plot-shipping` | exit 0，`[plot-shipping] 0 failures` |
| `check_feature_contracts.py` | PASS：35 features / 459 source assets / 380+ runtime hashes / 0 issues |

## 遗留与下一步

- SEA-CROP-R06 的「Blender 源级保存后重开 + 四视图」尚未执行，资产阶段保持 `runtime_component_verified`，不写成已验收。游戏内真实渲染已有正视图与俯视图两张证据，但它不等于源级四视图。
- 缺水叶色目前由 CropView 统一处理，尚未按品种给出枯萎形态；若要分品种枯萎，先加条款。
- 新增作物须同时补：`crops.json` 一行、`art_source/crops/<id>/v001` 制作源、`godot/scenes/crops/<id>.tscn`、`ledgers/crops.json` 一行、`runtime_resource_inventory.json` 四条 GLB、`content_index.json` 的 ID 列表。

## 变更记录

- 2026-10-29（第二轮）：按用户反馈调整体量。第 1 阶段从 0.2 米的芽放大到 0.45 米（三叶 + 嫩茎），解决「浇水后第二天才看得出变化」；第 3/4 阶段单株体积放大约 2.6x / 5x。暴露并修掉两个真问题：① 地格父级 `scale.y=0.65` 把作物压扁，容器补 `1/0.65`；② `_pop` 把补偿洗成 1，改成基于基准缩放。同时加入 `FRAME_ENVELOPE` 越界断言，防止放大后穿模。面数预算 900 → 1600，理由是造型目标变了而非数据超标。

- 2026-10-29：从 SEA-FARM 拆出品种与形态，建立独立功能文档、独立账本、独立代码模块 `godot/src/crops`、独立资产分账本 `ledgers/crops.json`；三作物升级为四阶段正式资产，原 `farm_plot.gd` 内联几何移除。

## 2026-11-07 三花与真实手持接口承接

本节追加承接 [SEA-CROP-R15](spec.md#2026-11-07-三花品种程序制作源与收获接口追加)，不改 R01–R14 原语义、登记头顺序、status 或历史 JSON/验证结论。上方三品种、12节点/3行资产及“新作物待做”的描述属于原阶段快照；当前品种集合为原生菜/番茄/南瓜 + 蓝星/晨光/珊瑚三花，共6品种，不能删除原三品种来满足旧数量断言。

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-CROP-R15 | 已实现三花独立 seed / produce、2/3/4浇水日、8/10/12瓶盖、基础yield各2、单次收成不再生；真实四阶段程序网格及成熟花手持/原Character动作接通。运行专项已通过；源级stage预算独立审计、美术source验收与未取得的权属/用户确认仍待验 | 最新221054中 `crops`96/0、`flower-crops`1233/0，均exit0/PASS；下方区分运行实例测量与source验收，不冒签R06 |

### 接口与资源增量

- [crops.json](../../../godot/assets/data/crops.json)：`flower_blue` / `flower_sun` / `flower_coral`；seed依次 `flower_seed_blue` / `flower_seed_sun` / `flower_seed_coral`，各produce为同名独立鲜花，不是 `flower_bundle`。
- 正式制作源为 [flower_view.gd](../../../godot/src/crops/flower_view.gd) + [flower_blue.tscn](../../../godot/scenes/crops/flower_blue.tscn) / [flower_sun.tscn](../../../godot/scenes/crops/flower_sun.tscn) / [flower_coral.tscn](../../../godot/scenes/crops/flower_coral.tscn)；四节点固定，`ensure_built()`离树幂等。它们是原生Godot程序源，不是新增.blend、GLB或 `art_source/crops` 下的伪源；上方旧新增作物的Blender/四GLB清单不作为这三花的已交付事实。
- [CropCatalog.reload](../../../godot/src/crops/crop_catalog.gd)规范JSON yield为整数，修复三花数量消费者基础产量1→2，不改播种扣1包种子；原三作物数值不变（产量2/2/3，原温室加成保留）。[test_flower_crops.gd](../../../godot/tests/test_flower_crops.gd)明确断言旧产量与加成未变。
- [HarvestVisual](../../../godot/src/crops/harvest_visual.gd)：`supports` / `create`增加三花成熟真实网格，复制花瓣/花心/茎叶、无土无碰撞，0.40米居中；保留R14原三作物选择及角色动作所有权，取消/结束清理不改库存或地格。
- 资产归原[crops分账本](../../../assets/registry/ledgers/crops.json)；[蓝星manifest](../../../assets/registry/manifests/sea-crop-flower-blue.json)、[晨光manifest](../../../assets/registry/manifests/sea-crop-flower-sun.json)、[珊瑚manifest](../../../assets/registry/manifests/sea-crop-flower-coral.json)只作已登记来源引用，不由本次文档补记改资产stage或把pending重签为通过。

### 已执行证据与剩余边界

[最新221054报告](../../../../sea-work/verification/20261107-221054-npc-final-regression-bc8a22/report.json)共11项全部PASS/exit0、completion_marker=true、unexpected_errors=[]；head/working_tree、完整命令、隔离user_data及project快照以报告为准。这是已存在报告的核对，不是本次文档修改后新跑。

| 专项 / 日志 | 实测结果 | 覆盖与不能替代的内容 |
|---|---|---|
| [crops](../../../../sea-work/verification/20261107-221054-npc-final-regression-bc8a22/crops.log) | 96 checks / 0 failed，exit0/PASS | `test_crops.gd`原3断言已扩6集合，保留原品种，六品种目录/阶段/表现回归；不是旧60项结果沿用 |
| [flower-crops](../../../../sea-work/verification/20261107-221054-npc-final-regression-bc8a22/flower-crops.log) | 1233 checks / 0 failures，exit0/PASS | 三花种收/缺水/换天/存档/满包/送礼，12运行阶段真实网格、每stage≤900面/框内、缺水还原，成熟手持与Character动作/取消；headless，不是source美术签署或真实四视图人工验收 |

保留原R06 Blender源级“保存重开+四视图”未执行；三花程序源stage预算/source美术验收未取得独立结论，不用运行实例预算断言代签。历史visual-crops等只证明原范围，不借给三花；整体 `implemented` 不等于完整产品verified。后续其他品种、品质、耐性及既有待验仍保留。本次不运行global sync/最终门禁，由主线程统一负责。

## 2026-11-10 种植专用集合归档（引用 SEA-ASSET-R63）

本节承接 `SEA-ASSET-R30`、`SEA-CROP-R06` 与 `SEA-CROP-R15`，不新增作物条款，不把 Blender 静态归档升级为三花程序源或作物运行验收。

| 对应设计条款 | 当前实施状态 | 证据 / 待核验 |
|---|---|---|
| SEA-ASSET-R63；SEA-ASSET-R30；SEA-CROP-R06；SEA-CROP-R15 | `planting_library.blend` 已完成 source-only 存放和源级验证：6品种×4阶段的24组件、2设施、6手持、2装配，共34 Collection、8原资产ID、459网格、13364 triangles / 11000 polygons，最终 SHA-256 `dbd4a94c125d775de639e5e14e76d87c1887c4815e6a2bd7fe975e5aee4e6249`。真实场景名为 `01_组件总览_只摆实例` 与 `02_组件母版_按AssetID追加`。三花的正式程序源仍为既有 `flower_view.gd` 与三份 Godot TSCN；本库中的静态快照不冒称原有原创 Blend。最终 `source_verification.json` 为9047 checks/0 failures、`passed=true`；`register.py --write` 成功，仅给原AssetID增加 `library_refs`，不改旧 `stage` / `source` / `hash` / `runtime`，也不重复登记库成员。原 R06 的用户美术终审、性能与运行接入不由本次归档签署；R15 已有的运行专项结论保持原样。三花/运行与 `farm_plot` 的既有 hash drift 保留。 | [最终归档记录](../../development/2026-11-10_botanical_collection_libraries.md)；[最终源验证](../../../../sea-work/botanical_libraries/v001/source_verification.json)；[登记结果](../../../../sea-work/botanical_libraries/v001/registration.json)；[最终提取报告](../../../../sea-work/verification/20261110-095851-botanical-final-8de438/report.json)实际292/0、exit0。8个Cycles PNG已生成，两个overview与植被top已审阅，不冒称8图所有细节全目视；全库sync/check因既有 manifest 缺 `asset_ledger` 的KeyError均exit1且无同步写入。 |

## 2026-11-10 v002 种植三形态模型（承接 SEA-ASSET-R64）

本节只记录作物 v002 的源模型交付，不把三形态源模型升级为运行四阶段覆盖或作物玩法验收。

| 对应设计条款 | 当前实施状态 | 证据 / 待核验 |
|---|---|---|
| SEA-ASSET-R64；SEA-ASSET-R30；SEA-CROP-R06；SEA-CROP-R15 | 种植域6个管理名、18个small/medium/large模型已完成最终源交付。生菜、番茄、南瓜及蓝星花、晨光花、珊瑚花各自通过叶、分枝、花蕾、果实拓扑与器官数量变化表达三档；花冠花蕾接枝、瓜果连藤与 XY 底心修正已纳入；无季节；纯植物模型不含盆、土、平台或手持。既有作物 v001 四阶段保留，v002 三形态不表示运行四阶段被替换或完全覆盖。 | 源 `art_source/crops/libraries/v002/planting_library.blend`；组件计划/manifest为 `art_source/crops/libraries/v002/component_plan.json`、`library_manifest.json`；最终报告 `D:/projects/sea-work/botanical_growth/v002/crops/verification_report.json`：1921/0、13276 triangles、7382 polygons（manifest meshes汇总）、SHA-256 `8831430d18cb7a8d92166b407cb926c360e22109f2f8a0601796450d5665d15d`。两个作者场景名为 `01_小中大对照`、`02_植物母版`。登记、交付审计和29图均已完成；运行接入、既有四阶段覆盖关系、性能和用户审美仍按边界保留。契约全库 sync/check 受旧 manifest `asset_ledger` KeyError/exit1 阻塞，未发生同步写入。 |

## 2026-11-11无损性能优化第一批

承接 SEA-CROP-R02/R03/R05/R07/R15 与 CropView 公开接口；登记 JSON、status、四阶段及原条款历史保持。

- CropView 对同阶段免重复遍历，但每次调用 `set_stage` 仍发 signal；空状态语义保留，不能为去重吞掉原有通知或改变空地表现。
- 阶段映射、独立阶段节点、生长与库存所有权、缺失模型降级规则不因本批优化改写。
- `farm_plot.gd` 已还原，不宣称本批修改地格实现、缩放补偿或种植规则。
- 主线程已提供 `performance-equivalence` 19/0、`crops` 与 `flower-crops` 通过。本次仅回填已提供结果，未新增测试或复跑；源级美术与历史待验不由这些结果升级。

[主记录](../../development/2026-11-11_performance_optimization.md)由主线程建立；最终视觉、存档及经营回归仍处理中，本节不预签完整验收。
