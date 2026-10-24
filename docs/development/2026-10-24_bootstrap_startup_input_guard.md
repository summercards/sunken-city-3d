# 启动报错：HUD 未建好时的输入空指针

FeatureID：SEA-BOOT；日期：2026-10-24。

用户反馈「报错进不去」。最近一次运行日志（`user://logs/godot.log`，07:59）只有三段同样内容的脚本错误，没有 `[shore-atlas]` / `[render]` 行，说明启动在 `_ready()` 中段就中断了。

## 现象与定位

```
SCRIPT ERROR: Invalid access to property or key '_panel_open' on a base object of type 'Nil'.
   at: _unhandled_input (res://src/bootstrap/main.gd:1598)
   ...
   [4] _set_shore_uniforms (main.gd:778)
   [5] _setup_water (main.gd:764)
   [6] _ready (main.gd:130)
```

- `_ready()` 在 130 行调用 `_setup_water()`，其中 `_set_shore_uniforms()` 会遍历场景几何生成 1536² 岸线距离图，本机耗时 3.3–4.4 秒，是启动最长的一段。
- `hud` 要到 142 行 `_setup_hud()` 才创建；在此之前 `_unhandled_input()` 无条件读取 `hud._panel_open`，只要这段时间有输入事件到达就是空指针。
- 报错行是 1598 行（鼠标类事件走到的那句），而不是 ESC 分支的 1594 行，说明触发的是鼠标移动/点击而非按键。

复现方式：在 `_setup_water()` 之前用 `get_viewport().push_input()` 同步派发一个 `InputEventMouseMotion`，得到的错误文本、出错函数与该日志逐字一致（临时探针已移除）。

## 修复

`godot/src/bootstrap/main.gd`：

1. `_unhandled_input()` 开头早退：`hud` 为空或已释放时直接 return。启动阶段本来没有任何可交互界面，把点击/按键丢掉是正确行为。这条同时建立了「`hud` 存在 ⇒ 后续节点齐备」的门：`props`(140)、`markers`(135)、`dive`(141)、`player`(136)、`cam`(133) 都在 `_setup_hud()` 之前建好，之后才建的是 prompt/grade/salvage/trade/hover/ribbon，其中 `_unhandled_input` 用到的 `cam_panel`、`grade`、`salvage_panel`、`order_panel`、`hover` 原本就有空判断或在此补上。
2. 拆开 `if hud._panel_open or cam_panel.is_open() or grade.visible:`，`cam_panel`、`grade` 各自判空。
3. `_setup_boat()` 里 `navigation_blocked` 回调的 `hud.toast()` 加空判断：该信号若在 `boat.place_at()` 期间触发，`hud` 同样还不存在。

未改动的部分：岸线距离图的构建位置保留在 `_setup_water()` 内，因为它的结果只喂着色器 uniform，挪到 HUD 之后反而会把「输入已可用、但 props/markers 还没建」的窗口暴露出来，风险比现在大。

## 验证

| 项目 | 结果 |
|---|---|
| 早期输入探针（修复后） | `hud=<null>` 时派发鼠标移动，无 SCRIPT ERROR，`_ready` 继续跑完 |
| 早期输入探针（临时关闭守卫） | 复现原错误文本 `... '_panel_open' ... type 'Nil'` |
| `run_verification.py selftest ocean parity` | 三项均 exit=0、pass |
| 渲染截图 `--capture` | 岸线 8481 段、画面与此前基线一致 |

证据：`sea-work/verification/20261024-081722-bootstrap-input-guard-e16995/`（`report.json` 见同目录副本）。

## 遗留

- 日志里输入事件出现在 `_edt` 帧之下（`_unhandled_input` 被嵌在 `_ready` 的调用链中），与「事件只在帧边界派发」的常规路径不符；本次按「输入早于 HUD」处理并加守卫，未复现出该嵌套栈。若再次出现，用同一探针 + 完整栈定位。
- 启动 3–4 秒的岸线距离图构建期间窗口无响应，属已知代价；要缩短需改算法或降到 1024²，不在本次范围。
