# 2026-10-31 建造系统解耦与可独立维护审计

关联 SEA-BUILDING。回答「这个功能是不是解耦、能不能独立维护运维护开发」。结论分两部分：结构层合格；有 3 个真实泄漏点，其中 2 个本轮已修，1 个判定为可接受并有记录。

## 一、结构层：依赖单向，接入点单一

模块 15 个文件、合计约 2100 行，最大 440 行（`building_controller.gd`），平均 150 行。依赖方向单向，没有环：

```
building_catalog  （唯一内容来源，无内部依赖）
      ↑
assembly_rules / assembly_surfaces / building_space    纯几何
      ↑
building_service  （唯一布局写入者）
      ↑
building_boundary / building_world / building_access   派生与投影
      ↑
building_controller / building_book / recipe_card      展示与输入
```

反向依赖：只有 4 处，方向合理——`bootstrap/main.gd`（装配）、`save/save_game.gd` + `save/save_schema.gd`（存档契约必须能重放建造规则）、`ui/hud.gd`（见第三节）。

模块对外部只依赖 3 类：`ui`（进度条、登陆提示）、`navigation`（走面、地面路径）、`inventory`（物品名）。没有依赖 `Economy`、`GameState`、测试或原型——`check_architecture.py` 每次门禁都会查，本轮仍是 17 服务 0 问题。

装配集中在 `main.gd` 一处，注入 15 个端口（`eligibility` / `space_reason` / `pay` / `refund` / `capacity_reason` / `layout_reason` / `stand_point` / `approach` / `actor_state` …）。规则层不读场景树。这是这套代码最扎实的一点。

只改拼接规则时，只需要动 `building_catalog.snap_foundation` + `assembly_rules`，`service`/`world`/`controller` 不用碰，且 `building-join` 37 项盯着。

## 二、修掉的泄漏点

### 1. 内容目录是共享可变对象，改写无人察觉（已修）

`Catalog.RECIPES` 是 `static var Dictionary`，GDScript 没有只读容器，任何持有引用的人都能改，而且是**同一份对象**被三个消费方共用：卡片显示的价格、开工扣除的数量、世界投影的占地。实证：

| 操作 | 后果 |
|---|---|
| `RECIPES.oil_lamp.cost.wood = 999` | 卡片显示 999，扣费 999，投影仍按旧占地 |
| `RECIPES.erase("post")` | 立柱整体消失，已有存档的支撑引用失效 |
| 追加一条伪造配方 | 立刻成为可建内容 |

71 处引用里，生产代码 0 处写，测试 4 处写（`active` 开关）。风险不在今天，在于「以后谁顺手改一下」没有任何东西会红。

修法：载入时留一份内容指纹，新增 `Catalog.verify_content()`。它覆盖定义字段（成本、占地、工期、profile、挂点），改价/删条目/加条目都会返回具体差项；`active` 是运行期开关，刻意排除，停用内容不算腐化。数字做了 int/float 归一，`2` 与 `2.0` 不误报。

新专项 `building-decoupling` 54 项守这条，并顺带断言：查询返回副本（改 `query()` 结果不会移动真实实例）、模块不碰 `Economy`/`GameState`/`Zones`、不依赖 `res://tests/`、每条配方都能通过公开 API 解析。

**边界说明**：`verify_content()` 防的是**运行期改写**。源文件本身被人改，由 `content_index`（22 个 id 归属 SEA-BUILDING）+ 运行期资源哈希 + 资产账本守，这是正确分工，不重复。

### 2. `code_paths` 漏登记数据与资产（已修）

账本只写 `godot/src/building`，但这个功能实际拥有：

| 路径 | 内容 | 原登记 |
|---|---|---|
| `godot/assets/data/building_kit.json` | 22 件内容唯一声明 | ❌ 漏 |
| `godot/scenes/buildables/kit` | 22 个独立预制体 | ❌ 漏 |
| `godot/assets/models/building_kit` | 44 个 GLB | ❌ 漏 |
| `godot/assets/materials/building_kit` | 4 套共享材质 | ❌ 漏 |

对照其他功能：`SEA-WORLD` 登记了 `ground_space.gd` 等具体文件，`SEA-GATHER` 登记了 `gather_spots.json`。只写目录会让「改了这个文件影响哪些功能」查不到。已补齐，门禁会校验路径存在。

### 3. 账本总表只覆盖到 R16（已修）

条款共 23 条，总表原来只有 R01–R10 + R16。R11–R15 埋在 10-29 的段落，R17–R23 散在 5 个日期段里。想看「R20 现在什么状态」要翻到第 127 行往后。

已把 R01–R23 全部收进总表，每行写当前状态 + 指向具体证据文档。23/23 覆盖，逐个核对过。

## 三、未修，但已记录判断

### `hud.gd` 反向取定价常量（判定可接受）

`ui/hud.gd:911` 直接 `preload("res://src/building/material_shop.gd").PRICE` 来显示土壤单价。方向是 UI → 功能实现，不理想。但它只取一个 `const`，且土壤定价本来就属于建造模块的交易职责，UI 是消费方。真要解耦应把定价上移到物品/经济层，那属于跨功能改动，收益不抵风险。登记为已知依赖。

### `validate_snapshot` 字符串自引用（已补守卫）

```gdscript
var validator=load("res://src/building/building_service.gd").new()
```

改文件名会让存档校验静默失效，编译期查不到。不能改 `preload` 自身（可能触发循环依赖），所以改为用断言守。

第一版守卫是错的：只检查 `building_service.gd` 这个文件能 `load`，而文件并没有被删、只是内部的路径指向了不存在的目标——注入坏路径后 59 项依然全绿。真正要守的是**文件内部的字符串路径本身有效**。改为用 `RegEx` 扫描 6 个含字符串式 `load` 的文件，提取每条 `res://…` 并要求 `FileAccess.file_exists`，外加断言重放校验仍按路径加载自己。注入坏路径后立刻 2 条红，且直接指出 `building_service.gd -> res://src/building/building_service_renamed.gd`；恢复后 0 失败。

这条过程记在这里，是因为「断言存在」和「断言有效」是两件事：如果没做反向注入，这条守卫会一直绿着什么也没守住。

### 目录硬读文件，无法注入（设计取舍）

`building_catalog._load_recipes` 用 `FileAccess` + `assert` 读 JSON。好处是 22 件内容不用每件写代码；代价是目录缺失或格式错误只能崩，没有降级路径，也无法在测试里注入替身。判定为合理取舍，代价明确。

### 单图标定

`kit_visual.gd`（50 行）按表面角色绑定 4 套共享材质，缺角色报错不回退——这是对的，避免「静默变 Matte」。

## 四、独立维护能力评估

| 任务 | 要动几处 | 是否有断言守 | 判断 |
|---|---|---|---|
| 改某件摆件成本 | 1（`building_kit.json`）+ 哈希同步 | 内容索引 id、解耦专项 | 好 |
| 新增一件内容 | 4（JSON、预制体、content_index id、资产账本） | 索引 id 列表、契约检查 | 尚可，步骤多但有守卫 |
| 停用一件内容 | 1（`active=false`） | 不触发腐化报告，停用后拒新建、旧档仍可读 | 好 |
| 改拼接/承载规则 | 2（catalog 吸附 + assembly_rules） | `building-join` 37 项 | 好 |
| 改投影/行走 | 1–2（world / space） | `ground-space` 33 项、`character-space-save` 10 项 | 好 |
| 改存档格式 | `save_schema` + service 快照 | `building-restart` 两进程、`validate_snapshot` | 好，但要同步 `save_schema` 的 object 结构 |
| 改 UI 卡片 | 2（book / card） | `visual-recipe-cards` 108 项真实鼠标 | 好 |

## 五、验收

`building-decoupling` 62 项 0 失败、退出 0（`20261031-011036-decouple-*`）。功能契约 `--sync` 与无参检查 PASS（35 功能、553 源资产、465 哈希、0 问题），架构检查 17 服务 0 问题。

回归：`building` 30、`building-join` 37、`building-simulate` 191、`kit-safety` 75、`building-kit` 121、`building-integration` 53、`building-restart` 11+5 全部 PASS。

## 六、结论

**解耦程度：合格偏优。** 分层清楚、依赖单向、装配集中、查询回副本、条款与账本行由 `requirements == covered` 强制对齐、内容表有 id 归属。可以按功能独立维护。

**真正的软肋只有一处：** 内容目录是共享可变对象，靠约定而非类型系统保证只读。本轮补上的 `verify_content()` 把「靠人记性」变成「会失败的断言」，但它是检测而非预防——GDScript 没有只读容器，这是语言层面的限制。

**本轮已把最后一处无守卫契约补上**：`validate_snapshot` 的字符串自引用现在由 7 条断言盯着（6 个文件内所有字符串式 `load` 路径存在、重放校验仍加载自己、脚本可解析可实例化、入口与重放能力齐全）。注入坏路径实测会红，不是纸面断言。
