# sea 资产账本入口

[主文档中控](../../GDD_V1.0.md#feature-control) · [资产生产功能文档](../../docs/features/asset/spec.md) · [功能账本](../../docs/features/asset/ledger.md)

`ledger_index.json` 是域到分账本的路由表，总索引不含资产行。场景域分账本为 `ledgers/scenes.json`，每个 AssetID 只出现一次。

- `current_source_index.json` 从场景分账本提取源定位，不允许作为第二份可编辑资产主表。
- `runtime_resource_inventory.json` 登记已有运行文件路径、大小与哈希；这些路径尚未全部补齐生产级 AssetID，明确标注 pending。
- `content_index.json` 指向各功能唯一内容定义，记录 ID 集合和所有者，不复制物品价格或作物数值。
- 功能账本引用 AssetID 或明确 pending 的资源路径；资产分账本不能代替每个功能的独立账本。
- `source_registered_runtime_pending` 只表示源已登记，不能当作正式接入。授权来源未逐份审查，保留 pending，不自动填“自有”。
- 各域资产行维护后同步源索引，运行资源变更先核对来源再更新对应哈希，禁止批量接受漂移。

校验：`python3 scripts/check_feature_contracts.py`。运行资源仍在 `godot/assets`，制作源在根 `art_source`；所有登记路径以仓库根为基准。场景接入时在原 AssetID 行补稳定运行路径、Prefab 与证据。

2026-10-23 新增太阳能花屋源：36 个独立组件、1 份参考装配和 1 张公共方格色板。制作目录为 `art_source/scenes/solar_flower_house/v001/`，建筑与花草分离；源级验收通过后标记 `source_verified_runtime_pending`，不表示 Godot 已接入。场景制作入口见 [目录说明](../../art_source/scenes/README.md)。

2026-10-24：太阳能花屋低面数装配 v002，引用 28 个低面数组件，共 84 个实例；展开后 2999 三角面。组件沿用原 AssetID，旧源进入各行 previous_sources；未被 v002 使用的 8 个 v001 组件仍保留，资产主记录总数不变。

2026-10-24：按用户最新指示，当前风格源为从 v001 派生的 v003，36 组件、255 实例，调整色调与花叶样式，保留建筑几何。沿用 AssetID 并登记前两版历史；本版不满足 3000 三角面，v002 低面数版本仍保留。公共色板不变，Godot 接入 pending。

## 类型分账本（2026-10-27）

| 域 | 独立账本 | 登记边界 |
|---|---|---|
| scenes | [scenes](ledgers/scenes.json) | 已有源记录，逐行维护验证阶段 |
| ui | [ui](ledgers/ui.json) | 已有源记录，逐行维护验证阶段 |
| characters | [characters](ledgers/characters.json) | pending；分类空账本，不代表该类资产已制作/授权/接入 |
| items | [items](ledgers/items.json) | pending；分类空账本，不代表该类资产已制作/授权/接入 |
| vfx | [vfx](ledgers/vfx.json) | pending；分类空账本，不代表该类资产已制作/授权/接入 |
| music | [music](ledgers/music.json) | pending；分类空账本，不代表该类资产已制作/授权/接入 |
| sfx | [sfx](ledgers/sfx.json) | pending；分类空账本，不代表该类资产已制作/授权/接入 |
| crops | [crops](ledgers/crops.json) | 2026-10-29建立；生菜/番茄/南瓜各一行，四阶段模型列 stage_models |

总索引先定位域，再按 AssetID 查询唯一主记录。新增域须同步独立账本；新增记录须同步来源索引和授权/接入证据。未重新核验的运行资源不批量刷新哈希。

2026-10-27：[场景组件细分目录](SCENE_COMPONENTS.md)，建筑、升级植物、可移动摆件、装饰/水面植物、装饰/动物分别维护。新增42种植物与4类装饰资产登记，原AssetID和来源哈希保留。

2026-10-27：新增程序化开始画面 `UI-TITLE-SEA-001`，登记在UI分账本，复用已有OFL授权圆体。参考图不进入发行资源；标题排字源、镜头适配和真实渲染证据见[本轮记录](../../docs/development/2026-10-27_minimum_loop_and_title.md)。仅为新增资产计算哈希，既有资产基线不变。

## 2026-10-29 作物独立资产域

作物从 `scenes.json` 的种植格条目中独立出来，主记录迁入 `ledgers/crops.json`：

- `SEA-CROP-LETTUCE` / `SEA-CROP-TOMATO` / `SEA-CROP-PUMPKIN`，各含 `stage_models` 四条（seed/sprout/leaf/harvest）。
- 制作源 `art_source/crops/<id>/v001/<id>_v001.blend`，外链公共 8×8 色板，PaletteUV 逐面落格。
- 12 个阶段 GLB 已登记运行清单，单阶段整格三角面 336–780，均在 900 预算内。
- `godot/assets/data/crops.json` 的 ContentIndex 所有权由 `SEA-FARM` 转为 `SEA-CROP`；数值仍被种植规则查询，不复制第二份。

原 `SEA-FARM-SOIL-CELL` 保留，但描述改为「木框培养土」，不再声称承载作物模型。
