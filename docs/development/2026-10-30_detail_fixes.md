# 2026-10-30 三个细节修订：海鸥时段、打捞转向、右下关闭键

本轮按主人截图与三点口头反馈修订，只动表现与到站朝向，不改经济、存档与玩法数值。

## 1. 海鸥过了 18:00 不再出现（SEA-AMBIENT-R05）

- 时段：`06:00 ≤ hour < 18:00`。18:00 是傍晚六点（日落前后），06:00 之前同样不出现。
- 时间只有一个来源：`Main` 在 `_setup_birds` 里把 `world_clock.changed` 转发给
  `Birds.set_hour(hour)`，并用当前时刻初始化一次。鸟群不存第二份日程、不写存档。
- 收起不是只关 `visible`：`set_hour` 同时把每只鸟的 `set_process(false)`，
  否则十二只鸟整夜还在算 `sample()`（三角 + 矩阵）。重新出现时从冻结相位接着飞。
- `build()` 之后若已有小时数，立刻按它定位，读档停在 19:00 不会先闪一群鸟。

实测：`decorations` 新增四条断言 —— 11:00 可见、18:30 不可见、05:30 不可见、06:06 恢复。

## 2. 打捞时船不再自动转向（SEA-PICKUP-R15）

根因是 `boat.sail_to()` 只有一种到站语义：`_yaw_to` 取出发朝向，停稳后
`_dock_left = |角度差|` 非零，`_process` 里那一段「靠妥后把船头拧正」就开始转 ——
那是为泊位写的，打捞时被一起继承了。玩家看到的就是"捞完自己转了一下"。

改法：`sail_to(..., align_at_arrival := true)`。打捞的两处调用（浮木 / 鱼群）
传 `false`，到站时 `_yaw_to` 就地改成当前朝向、`_dock_left` 归零，船头保持航行方向；
真实靠泊不传，行为不变。

只改到站朝向：航路、航速、停稳判定（`ARRIVE_DIST` / `ARRIVE_SPEED`）、
打捞范围（浮木 2.2 m / 鱼群 3.2 m）、结算时机全部未动。

实测 `ocean-pickups` 四条：
- 出发朝北、目标正东，到站朝向与出发朝向差 > 0.5 rad（证明没被拉回去）；
- 停稳后 40 帧角度变化 < 0.01（证明不再自转）；
- `_dock_left` 为 0（不再排队拧正）；
- 反向对照：靠泊仍保留 > 0.5 rad 拧正量（证明泊位语义没被顺手废掉）。

## 3. 右下角只留一枚关闭键（SEA-UI-R47）

原状：`hud._hints` 是 `HBoxContainer`，里面两枚奶油胶囊
「Ⓑ 返回 Esc」「Ⓐ 选择 Enter」，只要开面板/模态就出现在屏幕右下。

现为：一枚 `godot/src/ui/close_button.gd` 圆片。
- 奶白 `#fff9e8`、深棕 `#625744` 描边 3.2 px、手绘粗叉 5.6 px、底部 4 px 实心落影；
- 直径 62 px，贴右下角（右边距 34 / 下边距 30）；
- 整枚逆时针歪 `-0.105 rad`（约 6°），`pivot_offset` 取圆心，歪了也不跑位；
- **没有文字**。Esc / Enter 的键盘路径完整保留（`hud._input`、`_activate_selection`），
  只是不再把键盘提示画到屏幕上；说明放 `tooltip_text`；
- 关闭语义沿用原胶囊：`menu.back()`，所以内层面板仍是一层层退；
- **面板内部不再各挂一个右下角关闭件**：服务口袋（出货箱 / 保管仓库 / 家园补给）
  原有的「完成」按钮一并移除，关闭入口只剩这一枚。`close_requested` 信号、
  Esc、点卡片外空白三条回退路径一行没改，只是少一个可见按钮。

笔记（海岛笔记）**右上角**那个「×」保留：它不在右下角，是纸质笔记封面的角标，
与本条不是同一个东西。若主人觉得它也该去掉，再单独提一句即可改。

### 踩到的坑：Container 会把 rotation 归零

第一版把按钮放进 `HBoxContainer`，断言直接红了：`rotation=0.000`。
Godot 的 `Container.fit_child_in_rect()` 在布置子节点时会重写 position/size，
并把旋转归零 —— 放进任何 Container 的手绘歪按钮都摆不出那 6°。
所以 `_hints` 改成普通 `Control`（只有一枚按钮，不需要容器排版），
`size` 在 `_layout()` 里显式给。`_hints.position/visible` 的三个既有调用点
（`set_external_modal`、`_toggle_panel`、`island_menu`）一行没改。

### 为什么按钮不吃主题

`Cozy.apply()` 会把 `Button` 的 stylebox 换成 `surface()` 并强制
`custom_minimum_size.y >= 44`，圆片尺寸与描边会被刷回去。
控件在 `_init()` 里就打 `cozy_skip`，并自己把五态 stylebox 覆盖成 `StyleBoxEmpty`，
圆片与叉全部走 `_draw()`。

## 验证

| 项 | 自身断言 | 说明 |
|---|---|---|
| `close-hint` | 16 / 0 失败 | 新增；退出码 0 |
| `visual-close-hint` | 5 / 0 失败 | 新增；出三张实拍 |
| `ocean-pickups` | 47 / 0 失败 | 新增 4 条到站朝向断言 |
| `decorations` | 1716 / 1 失败 | 唯一失败为既有 `flat_annex` 重复实例 ID |
| `progress-bars` | 45 / 0 失败 | 通过 |
| `visual-birds` | 0 失败 | 通过 |
| `pocket-services` / `visual-pocket-services` | 0 失败 | 移除「完成」按钮后回归 |
| `visual-corner-notebook` / `island-atlas` | 0 失败 | 通过 |

注意：`run_verification.py` 把日志里任何 `ERROR:` 行都算失败，所以上表中
`minimum-loop` / `landing-markers` / `pocket-bubbles` / `close-hint` / `ocean-pickups`
可能被判 FAIL —— 触发条件是下面第 2 条那条退出期泄漏，不是各自断言失败。

### 两条既有欠账（不是本轮引入，未修）

**1. `decorations` 的 `unique component instance home_submerged/flat_annex`。**
`godot/scenes/main.tscn` 里 `flat_annex2`（26.7, -16.4, -2.2 附近）与 `flat_annex`
（-5.8, -16.7, 18.8 附近）两个节点写了同一个 `instance_id = "home_submerged/flat_annex"`，
而 `assets/registry/ledgers/scenes.json` 的 `runtime_instances` 只登记了后者。
该行在 HEAD 里就存在，本轮没改场景文件。修法是给 `flat_annex2` 另起一个稳定 ID
（例如 `home_submerged/flat_annex_east`）并补登记 `runtime_instances`——会动资产账本，
需要主人点头再改。

**2. 多个 main.tscn 专项在退出时 `10 RID allocations of type Environment were leaked at exit`。**
`minimum-loop` / `landing-markers` / `pocket-bubbles` / `close-hint` / `ocean-pickups`
本轮的「FAIL」全部由这一条触发（各自的自有断言是 0 失败、退出码 0）。
三次反证，都指向「不是本轮引入」：

1. **HEAD 快照不泄漏。** 用 `git worktree` 检出 `02a5d46`，在同样的探针
   （只 instantiate main.tscn → 10 帧 → free → quit）下退出干净；说明泄漏来自
   工作区里**未提交**的那批改动。
2. **本轮独立新增文件不泄漏。** 把 `birds.gd`、`boat.gd`、`pocket_service.gd`、
   `close_button.gd` 拷进 HEAD 快照后探针仍然干净。
3. **关掉本轮接线仍泄漏。** 在当前工作区把鸟群的 `world_clock.changed` 接线断开、
   把 `_hints` 临时改回原来的两枚胶囊按钮，泄漏照旧复现。

结论：泄漏来自工作区里另一批并行未提交改动（`hud.gd` 已引入 `ItemDB` 等新依赖，
与本轮改动耦合在同一文件里，无法单独回退比对）。本轮三项修订与其无关，未改动那批代码。
该项按原样留给对应负责人。

未执行：手柄/触控专项（无设备）；`verify_ac_ui.gd` 的旧 AC 单卡专项
（它由外部 run_ac 适配器驱动，本机没有该适配器，未执行）。
