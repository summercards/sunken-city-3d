# 2026-10-26 世界浮层大字：饱满、圆润、不勾边

[功能账本](../features/ui/ledger.md) · [功能文档](../features/ui/spec.md) · 条款 SEA-UI-R16

## 问题

主界面左下「海贝 80 · 背包 1/24」笔画偏细、字边缘发"沟"。对比同屏的胶囊按钮
（「跟随中」「停止行动」），字数一样大，字形却明显单薄。

## 三个独立的原因

### 1. 字号本来就小

`hud._res_label` 建的时候传 15，但 `_label()` 里有 `maxi(22, pixels)` 兜底，
所以实际 22px —— 恰是"正文最小字号"。它不是在背板上，是在 3D 画面上裸着，
22px 不够。

### 2. 上岸点名称既不是打包字体、又被描边

```gdscript
_font = ThemeDB.fallback_font          # ← 系统字体，不是霞鹜975圆体
font_size = 11                          # ← 小
_canvas.draw_string_outline(..., 4, ...) # ← 4px 描边，贴着笔画勾
```

`draw_string_outline` 沿字形外侧均匀外扩。圆体的笔画之间有很小的负空间
（比如「贝」的两点之间、「背」的上半），4px 描边一糊，这些空隙就填掉了 ——
远看是"字变细了"，实际是"字被描边吃掉了透气感"。

### 3. 拉丁数字和汉字不是一个字重

霞鹜 975 圆体的 cmap 里数字齐全（30912 字形），但**同一文件里拉丁/数字是
另一套偏细的笔画**。44px 下「海贝」厚、`80` 和 `4 / 24` 薄，一行字两种粗细。

这是花体/圆体常见的现象：汉字按 W（weight）设计，拉丁按另一套比例设计。

## 改法

### 统一入口 `Cozy.world_text()`

```gdscript
const WORLD_TEXT_BASE := 22
const WORLD_TEXT_SCALE := 2.0
const WORLD_TEXT_FLOOR := 26      # 绝对下限，与倍数解耦
```

| 元素 | 原字号 | 现字号 | 倍数 |
|---|---|---|---|
| 资源常驻行 | 22 | **44** | 2.0× |
| 潜水状态 | 20 | **40** | 2.0× |
| 视野提示 | 17 | **33** | 1.9× |
| 上岸点名称 | **11** | **26** | 2.4× |
| 水下宝箱名牌 | **12** | **29** | 2.4× |

### 合成加粗补字重

目录里只有 700W 一份授权字体，没有 800/900W。用 `FontVariation`：

```gdscript
var fv := FontVariation.new()
fv.base_font = ui_font()
fv.variation_embolden = WORLD_TEXT_EMBOLDEN   # = 1.0
```

档位实测（1600×1000，44px）：

| embolden | 观感 |
|---|---|
| 0.0 | 数字明显比汉字细，就是截图里那个样子 |
| 0.5 | 好一些，仍偏细 |
| **1.0** | **与汉字同重，笔画间隙还清楚 —— 取这档** |
| 1.5 | 笔画开始粘连，"圆"变成"糊" |
| 2.0 | 明显糊，反字重 |

### 去勾边，换偏移投影

```gdscript
label.add_theme_constant_override("outline_size", 0)
label.add_theme_constant_override("shadow_outline_size", 0)
label.add_theme_constant_override("shadow_offset_x", 3)
label.add_theme_constant_override("shadow_offset_y", 3)
```

关键在 `shadow_outline_size = 0`：投影只是一个**偏移的副本**，不沿笔画外扩，
所以字周围不出现"沟"。`outline_size = 0` 同理。

这层投影是必要的：白色字压在同一帧里的白色灯塔上就看不见了（截图里
「海贝」两个字正压在塔尖上）。

### 修掉一处静默覆盖

`island_presenters._font_tree()` 会在 attach 时把整棵界面树的字体刷成
`hud._font`。它把字号的改动留下了，却把字体对象换回没有加粗的那一份 ——
症状是"字号对了，数字还是细的"，而且不报任何错。

```gdscript
func _font_tree(node: Node) -> void:
	if node.has_meta("cozy_world_text"):
		return      # 世界浮层字自带加粗字体，不许刷回去
```

## 闸门：`visual-world-text`

`godot/tools/check_world_text.gd`，24 项检查：

- 五处浮层字逐个查：字号 ≥ 26px、字体家族是打包圆体（沿 `FontVariation.base_font` 回溯）、`outline_size == 0` 且 `shadow_outline_size == 0`
- 显式重跑一遍 `_font_tree()`，确认加粗没被覆盖
- 上岸点源码里不得出现 `draw_string_outline(`
- 水下宝箱名牌至少存在 3 个且逐个合格

**反向验证**（这一步不能省）：把 `WORLD_TEXT_SCALE` 从 2.0 改回 1.0，闸门报
**7 项失败**；改回来 0 失败。说明断言真的会失败，不是因为写成了恒真。

> 第一版断言写的是 `fs >= Cozy.world_text_size(Cozy.WORLD_TEXT_LANDING)` ——
> 拿配置和配置自己比。倍率一调小，两边一起缩，只有上岸点那条硬编码的会红。
> 改成独立常数 `WORLD_TEXT_FLOOR` 之后才 7 项全红。

## 实测

| 项 | 结果 |
|---|---|
| `visual-world-text` | 24 checks / 0 failures，退出 0 |
| `visual-paper-fit` | 11 checks / 0 failures（三分辨率） |
| `click` / `management` / `camera` | 退出 0 |
| `verify_island_ui` | 120 checks / 0 failures |

## 一处需要说明的测试改动

`verify_island_ui.inspect_fonts()` 原本要求 `节点字体 == hud._font`（同一个对象）。
世界浮层字现在是 `FontVariation`，基字体仍是同一份打包圆体，对象自然不同。
断言已改为沿 `base_font` 回溯比较 —— 它的本意是"同一套字体家族"，不是
"同一个引用"。这是放宽判据而非放宽标准，前提是闸门里已单独锁了"必须能回溯
到打包字体"。

## 未执行

- 触控/手柄下的浮层字未验证。
- 水下宝箱名牌只在探针里读到了字号/字体，未出图（`capture_underwater_suite.gd`
  需要 web 相机基线，本机未配）。
- 其它分辨率（1280×800、1920×1080）下浮层字未逐张目视；字号是按 1600×1000
  基准定的，`canvas_items` 拉伸模式下比例保持一致。

## 截图

工程外 `sea-work/tmp_ui/`：`world-text-surface.png`、`world-text-surface-clear.png`、
`world-text-markers.png`、`embolden-ladder.png`（加粗档位对照）。
