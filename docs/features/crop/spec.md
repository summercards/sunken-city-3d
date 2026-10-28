# SEA-CROP · 作物品种与四阶段形态

[主文档中控](../../../GDD_V1.0.md#sea-crop) · [本功能账本](ledger.md)

设计修订：r1（2026-10-29 从 SEA-FARM 拆出品种与形态，建立独立生产域）。所属系统：经营。
范围来源：原有三作物（生菜 / 番茄 / 南瓜）的数值散落在 `crops.json`，形态写死在 `farm_plot.gd` 的 `_build_plant()` 里。本功能把「作物是什么、长什么样」独立成可单独开发、单独验收、单独替换的域。

## 功能目的与边界

正式入口：种植品种目录、笔记中的作物资料、地格上的四阶段表现。

**本功能拥有**：品种定义（数值 + 阶段 + 模型引用）、阶段判定、品种目录查询、作物表现装配、作物美术资产。
**本功能不拥有**：地格状态与生长推进（SEA-FARM）、产物价格与背包（SEA-INVENTORY）、美术生产规范（SEA-ASSET）。

依赖方向单向：`SEA-FARM → SEA-CROP → SEA-ASSET`。SEA-CROP 不得引用 SEA-FARM，也不得读取地格状态。

## 设计条款与验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-CROP-R01 | 品种定义的唯一可编辑源是 `godot/assets/data/crops.json`。每个品种含稳定 `id`、`name`、`icon`、`seed`、`produce`、`grow_days`、`regrow_days`、`harvests`、`seed_price`、`yield`、`color`、`model`、`stage_labels`、`desc`。代码中不得写死品种名、品种数量或阶段名；增删品种只改本文件。 |
| SEA-CROP-R02 | 每个品种有且只有四个可见阶段：`seed`（种子）、`sprout`（发芽）、`leaf`（二次发芽·抽叶）、`harvest`（收成）。阶段由生长进度唯一决定，公式固定：`phase=="ready" → 3`；`p ≤ 0.001 → 0`；`p < 0.5 → 1`；否则 `2`。以 `grow_days=3` 为例，剩余 3/2/1/0 天分别对应 0/1/2/3，不得跳阶段，不得用同一套几何冒充两个阶段。 |
| SEA-CROP-R03 | 每个品种 × 每阶段都有独立美术资产与独立节点。场景内节点名固定为 `Stage0Seed` / `Stage1Sprout` / `Stage2Leaf` / `Stage3Harvest`；切换只改 `visible`。禁止运行时用 `scale=0`、`queue_free()` 或材质替换来"假装"切阶段。 |
| SEA-CROP-R04 | 作物几何只从 `godot/scenes/crops/<crop_id>.tscn` 装配。地格视图（SEA-FARM 的 `farm_plot.gd`）不得内联构造任何作物网格；替换作物外观只改 json 的 `model` 与场景，不碰规则代码。 |
| SEA-CROP-R05 | 规则层只查询品种数值，不持有几何、不引用场景资源；表现层只读品种定义，不回写生长状态。`CropCatalog` 无节点、无 Autoload、无场景依赖，可在隔离测试中直接 `new()` 并加载。 |
| SEA-CROP-R06 | 正式资产遵循 SEA-ASSET-R01/R05/R06：制作源在 `art_source/crops/<crop_id>/v001/`，外链唯一公共 8×8 色板，逐面 PaletteUV 落格且位于单格安全区，有机花叶用平滑曲面、可见硬边有真实倒角。每个品种每阶段的整格几何三角面不超过 900。 |
| SEA-CROP-R07 | 缺失模型或阶段节点时降级：保留上一个可见阶段，并只警告一次，不得崩溃、不得留下空箱。未知品种查询返回空定义且不创建任何状态。 |
| SEA-CROP-R08 | 品种的 `seed` 必须在 `items.json` 中属于 `seed` 类别，`produce` 必须存在于 `items.json`，`yield` 的键必须等于 `produce`。价格与出售价仍归 SEA-INVENTORY，本功能只引用 ID。 |
| SEA-CROP-R09 | 三品种在 `leaf` 阶段即可凭轮廓分辨：生菜为贴地放射结球，番茄为直立主茎分层叶，南瓜为沿土面匍匐藤蔓。`harvest` 阶段凭果实形态与颜色分辨，不依赖单一颜色差异。 |
| SEA-CROP-R10 | 资产账本独立：作物资产写入 `assets/registry/ledgers/crops.json`，每个品种一行主记录，`domain` 为 `crops`，不得记入 `scenes.json`。运行 GLB 同时登记 `runtime_resource_inventory.json`。 |

## 所有者、接口与数据

状态/交付所有者：**CropCatalog / CropView**。正式代码和资源入口：

- [godot/src/crops](../../../godot/src/crops)
- [godot/assets/data/crops.json](../../../godot/assets/data/crops.json)
- [godot/scenes/crops](../../../godot/scenes/crops)
- [godot/assets/models/crops](../../../godot/assets/models/crops)
- [art_source/crops](../../../art_source/crops)
- [assets/registry/ledgers/crops.json](../../../assets/registry/ledgers/crops.json)

公开接口（`CropCatalog`，可隔离 `new()` 后 `reload()`）：

- `ids() -> Array[String]`、`has(id) -> bool`、`get_crop(id) -> Dictionary`（深副本）
- `definitions() -> Dictionary`
- `stage_labels(id) -> Array[String]`
- `model_scene(id) -> String`
- `stage_for_progress(id, progress, ready) -> int`
- `validate() -> Array[String]`（品种与物品表、模型路径一致性）

公开接口（`CropView`，节点）：

- `show_crop(id)`、`set_stage(index)`、`set_dry(bool)`、`current_stage() -> int`、`current_crop() -> String`

公开接口（`CropStage`，静态常量与转换）：

- `SEED/SPROUT/LEAF/HARVEST = 0..3`、`KEYS`、`NODE_NAMES`、`count()`、`key_of(index)`

读取上述所有者的公开查询，修改通过其命令或交互入口；事件由拥有该状态的对象发出。原有稳定 ContentID、场景 ID 和存档键保持不变，重命名须另做迁移。

## 数据与阶段映射

`grow_days=3` 时，`progress = 1 - remaining/total`：

| 剩余天 | progress | phase | 阶段 | 节点 | 可读形态 |
|---|---|---|---|---|---|
| 3 | 0.000 | growing | 0 seed | `Stage0Seed` | 土面浅痕与三撮翻土，看不到绿 |
| 2 | 0.333 | growing | 1 sprout | `Stage1Sprout` | 破土小芽，一到两片子叶 |
| 1 | 0.667 | growing | 2 leaf | `Stage2Leaf` | 本叶展开，品种轮廓成形 |
| 0 | 1.000 | ready | 3 harvest | `Stage3Harvest` | 可收形态，果实高光 |

缺少浇水的 `growing` 格不改阶段，只把叶色向枯黄偏移并降亮度——「缺水只停长」，与 SEA-FARM-R02 一致。

## 当前实现与待完成边界

已实现：三品种 × 四阶段正式资产与场景、品种目录解耦、阶段公式、地格视图转交。
未实现（保持登记）：品种扩展（新作物）、季节性耐性、品质分级、工具对形态的影响；这些需要先在本文件新增条款再编码。

## 验收入口

`python3 scripts/run_verification.py crops farming`。`crops` 校验品种目录、四阶段节点齐全、阶段映射公式、未知品种降级；`farming` 回归确保拆出后地格循环不变。真实渲染与美术四视图另记，不以结构断言代替渲染证据。

## 来源与交付记录

- [本轮交付](../../development/2026-10-29_crop_formalization.md)
- [拆出前的种植设计](../../../godot/FARMING_DESIGN.md)
- [资产生产规范](../asset/spec.md)
