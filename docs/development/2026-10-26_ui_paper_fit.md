# 2026-10-26 纸背板装配：圆角不许吃字

[功能账本](../features/ui/ledger.md) · [功能文档](../features/ui/spec.md) · 条款 SEA-UI-R15

## 问题

截图里多处 UI 的字「探出背板」：字在线外，背板的弧线从字中间切过去。

按要求不调字体、不调排版，只把纸背板放大。

## 根因

`godot/src/ui/island_paper.gd` 的轮廓是按面板**宽高百分比**画的圆角：

| 方向 | 旧系数 | 980×606 的订单板实际圆角 |
|---|---|---|
| 横向 | 0.10 W | 98 px |
| 纵向 | 0.10 H | 61 px |

而 `cozy_ui.paper()` 给面板的内容边距是固定 32 px。于是：

```
字到纸边的距离  =  32 px（内容边距）
圆角横向吃进    =  98 px（面板越宽越大）
→ 字必然落在被圆角吃掉的那块里
```

面板越宽，坏得越明显。这也解释了为什么只有部分面板出问题：暂停菜单（580 宽）圆角 58 px、边距却是 52 px，刚好没出事。

既有断言 `check(inside(panel), "orders fit")` 只比「控件在不在面板矩形里」，而面板矩形比纸的轮廓大一圈 —— 所以 71 项断言全绿，但人眼一看就是破的。

## 改法（三个文件，不改任何排版）

### 1. `island_paper.gd`：圆角由内容边距反推上限

```gdscript
func _corner_radius() -> Vector2:
    var room := _content_margin() + Vector2(outset, outset) - Vector2(CORNER_GAP, CORNER_GAP)
    var rx := clampf(size.x * 0.10, 0.0, maxf(room.x, 0.0))   # 上限封死
    var ry := clampf(size.y * 0.10, 0.0, maxf(room.y, 0.0))
    rx = maxf(rx, minf(CORNER_MIN, maxf(room.x, 0.0)))         # 下限保住纸的圆润
    ...
```

`CORNER_GAP = 8.0`、`CORNER_MIN = 14.0`。半径上限 = 内容边距 + 纸外扩 − 8 px，**与面板被拉多宽多高无关**，这条约束写在文件头。

### 2. `cozy_ui.gd`：纸四边各外扩 24 px

```gdscript
const PAPER_OUTSET := 24.0
```

纸比面板大一圈，面板里的控件一个都没动 —— 这就是「把 UI 调整大，不动字」的实现方式。要更宽松只改这一个常数。

### 3. 骑纸边的装饰跟着纸走

- `hud.gd::_layout_notice()`：「海上的消息」标签原先按面板角点定位，纸一外扩它就整个漂到纸外。减去同样的 `PAPER_OUTSET`。
- `island_presenters.gd::_process()`：顺手修掉一个真 bug —— 世界提示气泡的背板「有弹窗就 `hide()`」却没有任何恢复路径，玩家开过一次背包之后，采集提示就永久变成一行没有底的裸字。

## 实测

新增闸门 `godot/tools/check_paper_fit.gd`（runner 注册名 `visual-paper-fit`）：

- 逐 Label 取**四角 + 四边中点**共 8 点，做纸多边形内点判定（射线法），容差 1.5 px。
- 额外两条防「假通过」：纸不得越出视口；面板必须真的有可测文字（防空跑）。
- 覆盖 11 块纸背板：camera、grade/filter、grade/water、orders、salvage、prompt、toast、menu 四页。

| 面板 | 尺寸 | 改前越界 | 改后 |
|---|---|---|---|
| 码头来信 | 980×606 | **22.5 px**（「ESC 关闭」） | 0 |
| 风景调色室·水面 | 700×663 | **13.5 px**（底部状态行） | 0 |
| 海底的小惊喜 | 700×468 | **4.3 px**（标题） | 0 |
| camera / filter / prompt / toast / menu×4 | — | 0 | 0 |

- 1600×1000、1280×800、1920×1080 三个分辨率均 `11 checks, 0 failures`，退出 0。
- 回归：`click`、`management`、`camera` 退出 0；`visual-paper-fit` 退出 0。

## 未解决 / 未执行

- `selftest` 536 passed / 1 failed：`tests/integration/selftest.gd:209` 仍要求 `_tab_body` 直接包含旧 `BackpackGrid`，当前九格主卡不再使用该容器。HEAD 隔离基线同样失败，本次不越过边界改测试。
- `visual-management` 2 项失败（找不到按钮「材料一键入库」）：已临时还原本次改动做基线对照，**改前同样失败**，与本次无关，根因待单独定位。
- 触控/手柄仍未验证。
- 36 处正文说明（`note` 行）在滚动区内，由 `ScrollContainer` 自己裁切，不在闸门判定范围内。

## 截图

工程外 `sea-work/tmp_ui/`：`paper-fit-{camera,grade-filter,grade-water,orders,salvage,prompt,toast,menu-*}.png`。
