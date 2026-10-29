# 2026-10-29 背包拖拽整理与购买数量 +/−

关联功能：SEA-UI（R43 / R44）、SEA-INVENTORY（R09 / R10）。

## 现象

主人两条需求，各配一张截图：

1. **背包界面，使用拖拽的方式进行移动。**（截图：背包 3 行 8 列格子，鱼/生菜/番茄/土壤各占一格，红框圈住生菜格）
2. **购买界面需要有卖多少个的 + 和 − 的功能。**（截图：光标停在南瓜种子上，右侧只有一颗「购买 1」按钮，红框圈出）

第 2 条的痛点很直接：种子和土壤是**消耗品**。玩家一次要种好几格、或者囤一叠土，只能一个一个点「购买 1」，等于逼人重复点十几次。

## 根因

### 一、背包根本没有"位置"这个概念

两个口袋界面的格子都是**每次打开时重新排**的：

```gdscript
# 改之前：pocket_service._stacks()
for id in Items.all_ids():          # 按物品表顺序
    while remaining > 0: ...        # 拆堆
```

`Inventory` 只记 `{物品id: 数量}`，没有顺序。所以就算把格子拖来拖去，`refresh()` 一跑就按物品表顺序重排回去 —— 拖了等于没拖。

**要让拖拽成立，先得让"排列"成为背包的状态**，而不是界面的临时产物。这也意味着它必须进存档，否则关掉游戏再进来顺序又变了。

### 二、购买固定 1 件

`pocket_service.show_actions()` 里写死了：

```gdscript
for amount in ([1,int(selected_data.count)] if int(selected_data.count)>1 and action!="buy" else [1]):
```

`action=="buy"` 时永远只出 `[1]`，即「购买 1」。底层 `buy_seed(crop_id)` / `buy_soil()` 也没有数量参数，各自固定 1 件。

放开数量不能只改按钮：**扣款与入包必须原子**。否则会出现"加到 5 包、扣了 5 份钱、结果背包只塞得下 2 包"这种最难向玩家解释的状态。

## 修法

### 一、排列成为 Inventory 的状态

`godot/src/inventory/inventory.gd` 新增：

| 方法 | 作用 |
|---|---|
| `ordered_ids()` | 当前持有的非货币物品次序 |
| `move_item(a, b)` | 互换两者位置 |
| `move_to_end(a)` | 挪到末尾（拖到空槽） |
| `_register(id)` | 新物品进来自动登记到末尾（幂等） |

几个刻意的选择：

- **拖到 B 上是"A 到 B 那格、B 到 A 那格"（互换），不是"插入后整体后移"**。这既符合直觉，也保证整理可逆 —— 再拖回来就还原。
- **`ordered_ids()` 留了两条兜底**：旧存档没有 `order` 就退回物品表顺序；新捡到、还没登记的物品补在末尾。少任何一条，要么旧档打不开，要么新捡的东西"消失"。
- **同种物品拆出的几堆必须相邻**。`_stacks()` 按物品 id 分组再拆堆，排序只排"物品种类"，不排"堆"。
- `to_dict()` 只写**当前还持有**的物品，已用光的不占顺序位。

存档：`save_schema.inventory()` 加了 `order: list_of(string)`，**故意不进 `required`** —— 旧存档没有这个字段必须照样能读。但只要它出现，就必须是字符串数组，脏数据不能把界面搞崩。

`from_dict()` 对脏 order 全部过滤：不存在的 id、数量已为 0 的、货币、重复项。

### 二、格子支持拖拽

`godot/src/ui/ac_icon.gd`（格子控件）加 `_get_drag_data` / `_can_drop_data` / `_drop_data`：

- 用 `drag_sortable` 开关控制，默认关 —— 卡片、图标等其它用途不会被拖走。
- 预览就是该物品的图标本身（同脚本再实例化一个影子格），不另做贴图。
- `drag_pool` 决定能落在哪：只接受同一池。商店目录/出货托盘**不接受**背包物品落下 —— 那不是"我的格子"，拖过去没有可解释的后果。
- 空槽也能接住（表示"挪到末尾"），玩家拖到空位时不该被无视。

> 中途踩到一个坑：最初把"造载荷"和"造预览"写在一起。测试里只想问一句"这格能不能拖"，也会顺手 `set_drag_preview()`，而 viewport 不在拖拽状态时调用它直接报
> `Condition "!get_viewport()->gui_is_dragging()" is true`，还留下 8 个 RID 泄漏。
> 已拆成纯数据的 `drag_payload()` 与真实拖拽用的 `_get_drag_data()`。

界面侧：`pocket_service` 新增 `sort_requested(from, to)` 信号 —— **界面不算账，只把意图转给宿主**；`hud._service_sort()` 落到 `Inventory`，改完立即 `refresh()`，玩家不用关掉面板再开。B 键纯背包 `pocket_inventory.gd` 同样接上，两处行为一致。

### 三、购买数量 +/−

`pocket_service` 新增 `_buy_picker()`，气泡结构变成：

```
[−]   3   [+]
   购买 3
```

- 默认 1；`+`/`−` 每次 1。
- 上限 `max_buy` 由快照给：`min(瓶盖够买几份, 背包 room_for)`。
- **到顶就置灰**，而不是让玩家点到"瓶盖不足"再被弹回来 —— 让按钮看起来能点却失败，是最容易让人误会的交互。
- 上限 0 时不给按钮，直接显示原因（瓶盖不足 / 背包已满）。
- 切换商品时数量重置为 1：上一件选到 7、换一件还是 7 会误买。
- 点 `+`/`−` 只改 `counter.text`、`buy.text` 与两个按钮的 `disabled`，**不重建气泡** —— 否则每点一次都闪一下动画。

底层放开数量并保证原子：

```gdscript
# material_shop.gd
func buy_soil(amount := 1) -> Dictionary:
    amount = maxi(1, amount)
    var total: int = PRICE * amount
    if not inventory.can_add("soil",amount): return {"blocked":"背包已满"}
    if not inventory.has_all({"coins":total}): return {"blocked":"瓶盖不足"}
    # 两项都过了才扣

# farm.gd
func buy_seed(crop_id: String, amount := 1) -> Dictionary:
    ... 同样先算总价、一起检查，够才扣
```

单价 × 份数即总价，不引入折扣或批量优惠。

## 验证

新增两个闸门：

| 闸门 | 内容 | 结果 |
|---|---|---|
| `pocket-drag-buy`（44 项，无渲染） | 排列层：互换、可逆还原、挪末尾、多堆相邻、存档往返、**旧档无 order 可读**、脏 order 过滤。界面层：按排列摆格、拖拽载荷、空槽可接、落下后立即重排、拖拽不改数量、商店目录不接落物。购买层：默认 1、点两次 + 变 3、减号回退、买 2 扣 2 倍价并到手 2 包、只够 1 个时 ± 都置灰、切商品重置 | **PASS，0 失败** |
| `visual-pocket-drag-buy`（8 项 + 4 张图） | 走**真实鼠标事件**：按下 → 8 步移动 → 松开，确认 `root.gui_is_dragging()` 真的为 true（Godot 已接管预览），落下后顺序实测由 `fish,vegetable,tomato` 变 `tomato,vegetable,fish` | **PASS，0 失败** |

> 真实拖拽踩到的第二个坑：模拟 `InputEventMouseMotion` 时**必须给 `relative`**。
> Godot 靠它累计 `drag_accum` 判断"这是拖还是点"，只改 `position` 时累计位移恒为 0，
> 永远进不了拖拽状态 —— 第一次跑就是"拖不动"，顺序一点没变。

回归：`pocket-bubbles` / `pocket-services` / `farming` 全部 PASS。

契约与架构：`check_feature_contracts.py --sync` 与无参检查 PASS（35 功能 / 459 源资产 / 392 运行期哈希 / 0 问题）；`check_architecture.py` 15 服务 0 问题。

证据目录（工程外 `sea-work/`）：

- `20261029-152247-pockui2-15461a`：最终渲染证据（`pocket-buy-1.png` / `pocket-buy-3.png` / `pocket-drag-hover.png` / `pocket-dropped.png`）

## 未改变的行为

- 物品数量、价格、堆叠上限、补货计时：一律未动。`buy_soil(1)` / `buy_seed(id, 1)` 与原来的单件购买完全等价。
- 出货箱 / 仓库的存入取出规则：未动。它们的"1 件 / 整叠"气泡照旧，只有 `buy` 分支换成了数量选择器。
- 存档 schema 只增字段、不改既有字段，且新字段不进 `required`。
- 格子尺寸、配色、空位圆点、绿色名称胶囊等视觉规格：未动。
