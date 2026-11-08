# 2026-11-08 商店改为与背包同款图标网格

[主文档](../../GDD_V1.0.md#sea-shop) · [商店设计](../features/shop/spec.md) · [商店账本](../features/shop/ledger.md) · [UI 设计](../features/ui/spec.md) · [UI 账本](../features/ui/ledger.md)

用户要求「商店的 UI 现在是列表式的，需要改成和背包一样，是图标样式的，对应的功能和体验也要一起修改」。这一轮只改 Godot 正式实现里的商店面板与它依赖的格子控件，不改商品、价格、库存与原子交易。

## 1. 接手时的状态

Codex 那一轮在 `2026-11-08T03:01` 被用量上限打断，工作树留下了半成品：`shop_panel.gd` 已被整文件替换为「复用 PocketService」的适配层，`pocket_service.gd` 加了 `detailed_shop` / `purchase_quote` / 三个报价 Label，`test_shop_rules.gd` 的面板段仍是旧列表契约。最后一次运行 `20261108-110457-shop-grid-compile-152038` 是 219/10，`_panel_tests` 崩在 `:384` 对 `_details.text` 的空引用上。

续跑先做的第一件事不是改代码，而是把面板段按新交互重写、确认剩下的是真问题——结果就是 29 项失败基本来自「旧断言在测不存在的列表控件」，而不是新面板算错了钱。

## 2. 实现

### 2.1 面板（`godot/src/shop/shop_panel.gd`，整文件重写）

职责收窄成「适配层」：不画格子、不算价格，只把 ShopService 的快照与命令接到 PocketService 上。

- **开店**：`open_shop` 只摆格、把 `selected_pool` 设到商品区、焦点落在首件商品，**不替玩家打开气泡**。与背包一致，选中之后才确认进入操作。
- **输入**：`handle_input` 沿用既有的同帧去重（HUD 委托 + 自身 `_input` 会收到同一枚事件）与「开店帧不吃确认键」；`Tab` 改成关面板（与背包 `/` HUD 一致，不再用它遍历控件）；`Esc` 先 `back()` 收气泡，收不了才 `close()`；方向键只走商品行。
- **结算**：仍在 `_operate` 里，保留 `_opened_frame/_actions_frame/_purchase_frame` 三重同帧防护与 `panel:<id>:<seq>` token，成功后才 `cancel_actions()` + 刷新。
- **反馈**：`_feedback` 从「压在第 702 行、和气泡打架」挪到底部纸面区右侧独立一行（360,629），字号 21。

### 2.2 共用格子（`godot/src/ui/pocket_service.gd`）

新增三处，都只在 `detailed_shop` 分支生效，背包/出货箱/仓库行为不变（`pocket-services`、`pocket-bubbles`、`pocket-drag-buy` 全绿）：

| 新增 | 作用 |
|---|---|
| `lock_pool` | 方向键在指定池内环绕；商店只有一行商品，上下键不该把焦点甩到背包 |
| `cancel_actions()` | 立即收气泡并作废闭包，供宿主关面板时用（`back()` 带 0.12s 回退动画，关店时不能等） |
| `_update_shop_quote()` | 单价 / 当前可购 / 合计 / 购后余额，不可购时合计与余额写「—」而不是把单价当总价 |

名签：商店分支挂在商品行**下方**空白处（`grids[1].y + 92`）。先前试过右上角与右侧空位，都被购买气泡或说明带压住，图上一眼可见。

### 2.3 图标（`godot/src/ui/ac_icon.gd`）

- 新增 `price` 字段，价格画成**格内左下角标**。旧实现挂一个 `position=(-8,72)`、`size=(100,28)` 的子 Label，宽 100 超出 84 见方的格子、往下溢出，正好压住名签——第一版截图里「8 瓶盖」和名签叠成一团就是这个原因。
- 补三种花种（封条取 `ItemDB.color`）、三种花材 + 小束鲜花（五瓣 + 花心）、缎带的手绘图形。花色全部来自 `ItemDB.color`，不另存一套配色。
- 商品格的 `amount` 置 0：一个格子里同时出现「×3」和「8」会被读成「这堆有 3 个」，和背包行话撞车。持有数只由名签（`· 持有 ×0`）与气泡说明。

### 2.4 关闭键归属（`hud.gd` / `main.gd`）

图上真实主场景那张一眼看出右下角并排两枚圆键。查下去是两个独立问题：

1. `hud.gd` 那枚圆键 `pressed` 直接落 `back()`，而 `back()` 在 `_external_modal` 下第一句就 `return` —— 商店/职业/建造打开时按钮可见却按不动。改为先走 `owned_modal_query` → `owned_modal_close`。
2. 商店自带一枚圆键，两者位置几乎重合。改为 `main.gd` 在 `shop_panel.opened/closed` 时隐藏/恢复 HUD 那枚（`_set_hud_close_visible`），同一角落始终只有一枚可见关闭入口。

## 3. 验收

所有运行均经 `scripts/run_verification.py`，Autoload 前隔离用户目录，`--skip-title --nosave`，不读写默认用户槽位；真实渲染用 Vulkan Forward+ / RTX 4060 Ti。

| 专项 | 检查数 / 失败 | 退出码 | 报告目录 |
|---|---|---|---|
| shop-rules | 252 / 0 | 0 | `20261108-120301-sg-rules-3-87979f` |
| **visual-shop-grid**（新增入口） | 51 / 0 | 0 | `20261108-120703-sg-visual-6-54a036` |
| pocket-services | 32 / 0 | 0 | `20261108-120714-sg-pocket-svc-3-860739` |
| pocket-drag-buy | 44 / 0 | 0 | `20261108-115553-sg-pocket-drag-b46e50` |
| visual-pocket-services | 29 / 0 | 0 | `20261108-115754-sg-pocket-visual-d66221` |
| visual-pocket-drag-buy | 9 / 0 | 0 | `20261108-120021-sg-pocket-drag-visual2-39b6ce` |
| npc-shop | 18 / 0 | 0 | `20261108-115544-sg-npc-shop-cdad1b` |
| npc-shop-site | 335 / 0 | 0 | `20261108-115547-sg-npc-shop-site-c29d64` |
| npc-integration | 780 / 0 | 0 | `20261108-120956-sg-int-3-aebfcd` |
| npc-save | 702 / 0 | 0 | `20261108-121433-sg-save-3-8607bb` |
| minimum-loop | 112 / 0 | 0 | `20261108-121527-sg-min-3-985416` |
| close-hint | 16 / 0 | 0 | `20261108-120919-sg-close-hint-72baab` |
| click | 39 / 0 | 0 | `20261108-120749-sg-click-e1df25` |
| keyboard-entry | 39 / 0 | 0 | `20261108-120830-sg-keyboard-51c4a4` |

14 个独立入口合计 **2458 / 0**，全部 `exit0`、`completion_marker=true`、`unexpected_errors=[]`。报告父目录 `D:/projects/sea-work/verification/`。

### 3.1 画面

`visual-shop-grid` 出 8 张，逐图打开审阅过：

- `shop-grid-grid-1280x800.png`（1280×800）、`-1600x1000.png`（1600×1000）、`-1920x1080.png`（**1728×1080**，1920 窗口在原 KEEP 画布下的实际像素，日志已逐个打印，不拿窗口名冒充图像尺寸）
- `shop-grid-bubble-1.png` / `bubble-3.png`：气泡数量 1 与 3，合计 8 / 24 瓶盖随动
- `shop-grid-purchase.png`：真实购买后的反馈行，独占底部一行
- `shop-grid-general.png`：阿店六格同页
- `shop-grid-blocked.png`：余额 0 时合计/余额写「—」并给「瓶盖不足」

另加一张正式主场景实拍 `scene-shop-grid.png`（来自 `visual-pocket-drag-buy` 的 `pocket-buy-grid.png`，海店柜前，含世界画面），用来确认右下角只剩一枚关闭键、气泡不压商品格。工程外副本：`D:/projects/sea-work/outputs/shop_icon_grid/final/`。

### 3.2 过程失败（保留）

| 报告 | 现象 | 处理 |
|---|---|---|
| `104457-shop-grid-compile-152038` | 继承的 codex 半成品，列表契约 219/10 | 重写面板段 |
| `111211-shop-grid-panel-fix-2185f9` | 238/29，Tab 遍历/`_details` 空引用 | 新交互不开气泡，改断言 |
| `111417` / `11457` / `111537` / `111611` / `111714` | 气泡焦点、回退动画等待、按键同帧去重 | 逐条修测试节奏，未改生产规则 |
| `112452` / `112752` 两次渲染 | 1280 下全画面采样过稀（判成空白）、气泡压反馈行 | 采样改到面板矩形内、气泡挪到右上 |
| `114153-shop-grid-npc-release-587a67` | 170/2：天台取景 `fits=false` | 见下 |
| `114505-shop-grid-npc-people-38b9d3` | 385/13：`npc_bao_he` 被 `glass_bay__SEA_Gloss` 遮挡、七人姓名断言失败 | 见下 |

最后两项用 `20261108-115045-baseline-head-people-8bcdc9` 做了对照：把 `shop_panel.gd`/`pocket_service.gd`/`ac_icon.gd` 临时回退到 `git show HEAD`，跑同一条 `visual-npc-people`，得到**同样 13 项失败、同一个 `visual_blocker` 路径**。结论是既有取景/身份断言问题，不由本次商店改动引入；本次未修、未重签，`visual-npc-release`/`visual-npc-people` 保持既有失败，不冒充通过。回退后已恢复本次实现并复跑 `shop-rules` 252/0、`minimum-loop` 112/0 确认无损。

### 3.3 未执行项

低端设备、发行包、手柄/触屏、长期 FPS、完整商店购物体验（逐商品逐数量人工游玩）均未执行；`npc-save-seed`/`npc-save-restart` 跨进程两相本轮未重跑，沿用 `20261108-104628-npc-conversation-release-149113` 的 476/0、202/0，不当作本轮实测。

## 4. 门禁

- `python scripts/check_architecture.py` → exit0，25 独立规则/存储服务 0 issues。
- `python scripts/check_placed_positions.py` → exit0，3 结构 0 警告。
- `git diff --check` → exit0；`godot/scenes/main.tscn` 无本次 diff，用户手摆 transform 未动。
- `python scripts/check_feature_contracts.py --sync` → **exit1，52 issues**；不带参数 → **exit1，53 issues**（另加 derived index stale）。
  - 48 项 runtime hash drift：含本次真实改动的 `shop_panel.gd`、`pocket_service.gd`、`hud.gd`、`main.gd`，用「工作区去 CRLF 后与 `git show HEAD` 比」逐一确认是**真内容漂移**（登记哈希等于 HEAD，不等于当前字节）；其余为并行任务与历史漂移（如 `items.json` 来自上一轮花种说明）。
  - 4 项 source hash drift：SEA-DECO-ANIMAL-FISH-SCHOOL、SEA-FARM-SOIL-CELL、SEA-SCENE-SUNROOM-UNDERWATER-REGION、UI-HUD-CORNERS-001。最后一项源文件是 `corner_hud.gd`，登记哈希既不等于当前字节也不等于 HEAD（HEAD 侧为空），属上游漏登记；四项均与本次改动无关。
  - 按既有口径不批量重签、不冒签；`--sync` 在有 issues 时按脚本设计不写派生索引。故全局门禁未通过。

## 5. 条款

新增稳定条款：

- `SEA-SHOP-R12`（[商店设计](../features/shop/spec.md)）
- `SEA-UI-R59`（[UI 设计](../features/ui/spec.md)）

两功能状态保持 **implemented（已实现）**，不升 **verified**。
