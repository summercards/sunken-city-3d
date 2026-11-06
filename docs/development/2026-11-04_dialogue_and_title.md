# 2026-11-04 · 角色台词多段推进与开始画面补充（2026-11-06 补记）

## 为什么补记

这两件事与划船同批提交（`1f336a13 feat(rowing): 坐姿划船与握桨解算、多段对话、开始画面修订`），
但当时的交付记录只写了划船，commit message 里「多段对话、开始画面修订」六个字没有落到任何
设计条款或账本行；`SEA-UI` 的 spec／ledger 最后一条停在 2026-11-02 的 R49。

行为本身已经在跑，开场三句独白与「首击补全、次击换句」的语义记在
`SEA-ONBOARDING-R11`，但那是**新旅程流程**的条款，不是对话框组件的能力边界。
本次按 `AGENTS.md` 第 2、3 条补条款 **SEA-UI-R50 / R51**，并回填账本。

## 一、`CharacterDialogue` 从单行改成队列

改前：`show_line()` 只画一行，右下角一个「继续」，点一下整块收掉。

改后（`godot/src/ui/character_dialogue.gd`）：

| 行为 | 实现事实 |
|---|---|
| 单行兼容 | `show_line(speaker,text)` 内部转成 1 行队列调 `show_sequence()`，旧调用点不用改 |
| 多行入口 | `HUD.show_dialogue_sequence(lines)`；每行 `{speaker,text}`，空 speaker 或空 text 的行被丢弃 |
| 页码 | 队列 >1 时右上角显示 `当前 / 总数`；单行时留空 |
| 按钮文案 | 中间行「下一步 ▸」、末行「开始生活」、单行「继续」 |
| 打字机 | `visible_ratio` 从 0 到 1，时长 `clamp(字数 × 0.018, 0.22, 0.65)` 秒；**只在多段时启用**，`Cozy.motion_enabled` 关闭时直接全显 |
| 首击语义 | 当前行没显示完 → 只补全（`visible_ratio = 1.0`），不换句；显示完 → 才 `_index += 1` |
| 键盘 | 空格 / 回车 / 小键盘回车推进，并 `set_input_as_handled()`；叙事键不许漏给玩法或已聚焦的 HUD 按钮 |
| 输入阻断 | 多段时挂一层全屏 `Control`（`MOUSE_FILTER_STOP`）；`is_blocking()` 仅在「面板可见且队列 >1」时为真 —— 单句不锁世界，保持体力提示原有的非叙事行为 |
| 版式 | 面板 680×168、底部居中、距底 32 px（按 1600×1000 设计基准等比缩放）；正文 24 px、说话人 21 px、页码 18 px；入场 18 px / 0.24 s + 透明度 0.20 s |
| 外部收起 | `close_line()` 由调用方直接收（体力见底那句由 Main 定时收，不等玩家点） |

实际调用点两处：

- `godot/src/bootstrap/main.gd:3307` —— 开场三句（内容与时机归 `SEA-ONBOARDING-R11`）
- `godot/src/bootstrap/main.gd:2677` —— 体力见底「啊，太累了，今天需要休息了。」（内容归 `SEA-ENERGY`）

`SEA-UI-R20` 不变：系统到达／收获／错误仍是右上轻提示，**不因为角色对话框有了打字机就也加打字机**。

## 二、开始画面补充

改前：倾斜 SEA 三字 + 「开始游戏」，标题 1.2 s 淡入 / 1.5 s 轻移、按钮 0.85 s 延迟淡入。

改后（`godot/src/ui/start_screen.gd`）只加三件，原有构图与时长一字未动：

| 件 | 数值 |
|---|---|
| 副标题 | 「沉 没 街 区 上 的 屋 顶 生 活」，22 px，旋转 −2.5°，奶油白 86% 不透明，位置 (18, 258)（相对标题组） |
| 登岸提示 | 「—  点击或按 Enter 登岸  —」，18 px，挂在按钮内 (44, 62)；透明度 `0.62 + 0.28 × sin(2.2 t)` 呼吸，`_entering` 后停止 |
| 投影 | 标题字 4/6 px、按钮 3/4 px 海色 `(0.06,0.16,0.21,0.42)` |
| 悬停 | 按钮整枚转暖金 `#ffe29a`、提示右移 8 px，0.18 s |

`SEA-UI-R21 / R22 / R34` 的淡入时长、按钮锚点 0.755、输入与时间阻断、读档时刻取景一律不变；
没有新增按钮、第二入口或额外可点区域。

## 归属与验证

- 条款：**SEA-UI-R50**（对话队列）、**SEA-UI-R51**（开始画面补充）。
- 已执行证据（本轮未新增专项，沿用同批运行）：
  `D:/projects/sea-work/verification/20261104-151119-onboarding-r11-accepted-c93b3b`
  —— `onboarding` 38 项、`title-screen` 29 项、`visual-avatar` 49 项，含「打字机两次输入语义」
  「台词模态」「三分辨率真实渲染」。
  `D:/projects/sea-work/verification/20261104-151730-onboarding-r11-ui-regression-5b28ba`
  —— `visual-title-screen-day` 28 项。
- **未做**：单独针对 `character_dialogue` 的专项（页码、末行文案、输入盾的独立断言），
  当前只有开场流程覆盖它。归为 pending，不当作已完整验收。
