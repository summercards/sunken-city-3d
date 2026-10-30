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
    "structure"
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
