# SEA-QUICKTOOLS · 快捷工具环

[主文档中控](../../../GDD_V1.0.md#sea-quicktools) · [独立账本](ledger.md)

设计日期：2026-11-12。状态：`partial`（代码与专项已完成；全局登记同步受既有问题阻断，完整验收未签署）。加固后正式 release 的8个入口已通过，逻辑116/0、真实渲染266/0；用户最终美术确认、手柄及各体型仍 pending，不升级为 `verified`，也不声称全设备通过。

## 功能目的与边界

Alt 一次切换角色头顶的快捷工具环：陆地提供建造/拆除，船上提供钓鱼/潜水。快捷工具只编排临时 UI、读取公开上下文并转发既有命令，不拥有建造、拆除、鱼群、潜水、航行、库存或存档状态。

依赖：`SEA-UI`、`SEA-MOVE`、`SEA-BUILDING`、`SEA-PICKUP`、`SEA-DIVE`。

## 设计条款与验收标准

| 条款 ID | 规则 / 验收 |
|---|---|
| SEA-QUICKTOOLS-R01 | 在普通世界输入未被阻断时，按一次 Alt 打开快捷工具；首次 release 前锁住重复的 non-echo duplicate Alt press，并消费 echo，不关闭或重建菜单；松开后再次按 Alt 才收起。关闭时 echo 不得重新打开。普通 world action 菜单打开时，快捷模块不关闭、不接管，也不误触发。 |
| SEA-QUICKTOOLS-R02 | `ashore_idle`、普通 walking、strolling 显示建造/拆除；`boat_idle`、sailing 显示钓鱼/潜水。打开快捷环不主动取消既有自动航线；手动键盘驾驶因菜单 modal 不再读取驾驶意图，按既有 `release_drive` 自然减速，不承诺 manual sailing 状态不变，不改 production 航行逻辑。 |
| SEA-QUICKTOOLS-R03 | modal、过场、潜水、攀爬、室内、睡眠、采集中不打开；上下文变化或窗口失焦立即收起。减少动态偏好即时生效，关闭动效时直接稳定显示。 |
| SEA-QUICKTOOLS-R04 | 两枚 76px 青绿色圆按钮，奶油色圆边，白色程序化剪影；以角色头顶屏幕锚点跟随，相对左右上弧展开；hover/focus 暖金并放大到 1.09。 |
| SEA-QUICKTOOLS-R05 | 打开动画 0.24s BACK，左右按钮错峰 0.035s；收起 0.16s；普通 UI 的动画偏好由 SEA-UI 统一控制，不建立第二份偏好。 |
| SEA-QUICKTOOLS-R06 | 每次打开/关闭以会话 token 隔离按钮回调；执行前先校验 token 与本会话菜单 active，旧回调不得关闭新菜单，取消退场中及退场后均不执行。有效选中先立即关闭快捷 modal，再复验上下文和资格，通过才调用公开命令；过期、阻断或上下文变化不执行。读档入口立即 `close(true)` 并 invalidate 会话，不等下一帧上下文门禁。 |
| SEA-QUICKTOOLS-R07 | 建造/拆除继续使用 SEA-BUILDING 原资格、空间确认、扣费/退款、保护与返回链；船上不显示建造快捷项，但不禁用既有船上手册。 |
| SEA-QUICKTOOLS-R08 | 钓鱼只连接既有最近 24m 鱼群查询与 SEA-PICKUP 的 1.6s 停船采集链；无鱼群时给出明确提示。不实现、不声称鱼竿咬钩小游戏。 |
| SEA-QUICKTOOLS-R09 | 潜水转发既有入口；船上沿现有先停船提示，不复制潜水状态机、过场、氧气、奖励或存档字段。 |
| SEA-QUICKTOOLS-R10 | 不改用户手摆 TSCN/场景资源，不新增存档字段；运行时 `QuickTools` 节点由 Main 通过代码真实创建并挂载。Main 只做节点装配、公开查询注入和命令转发，功能规则保持在各依赖所有者。 |

## 公开接口与装配

- `godot/src/quick_tools/quick_tools.gd`：`query()`、`toggle()`、`is_open()`、`close(immediate)`；依赖注入 `context_query`、`execute`、`notify` 与现有 `world_action_bubbles`。
- `godot/src/ui/world_action_bubbles.gd`：复用 `presentation="quick"`，保持普通 world presentation 独立；快捷环只使用公开 `open/close/is_open/activate` 路径。
- `godot/src/ui/quick_tool_glyph.gd`：四种图标均由 Godot `_draw()` 程序化绘制，不加载位图或生成图片。
- Main 仅注入角色/镜头/依赖查询，执行 `craft`、拆除、既有鱼群采集和 `_on_dive`；不写入任何依赖模块私有状态。

## 状态与持久化

快捷环的打开状态、上下文、会话 token 和按钮动画都是瞬态，不进入 `SnapshotRegistry`，不新增根 v4 或任何模块存档字段；读档入口立即 `close(true)` 并 invalidate 会话，潜水事务、室内和过场仍由依赖上下文门禁使快捷环收起。

## 验收入口

本功能登记 `quick-tools`（逻辑）与 `visual-quick-tools`（真实视觉）两个统一 runner 入口。加固后正式 `20261112-123340-quick-tools-release-913ecd` 已完成：两专项116/0、266/0，建造40/0、潜水501/0、面板81/0、海上拾取48/0与 `save-corrupt-seed` / `save-protection` PASS；8入口均exit0、passed=true、completion_marker=true、unexpected_errors=[]。新增会话token、取消旧命令/退场、读档、失焦、non-echo Alt/echo和edge caption均在当前专项通过范围内。

真实渲染产出30张PNG：1280×800、1600×1000、1920×1080 × land/boat × opening/open/hover/closing/closed。主线程ViewImage目检仅含最终1280 land-open、1920 boat-hover及前轮1600两图；已审图确认无挡脸/裁切及青绿、奶油边、白剪影、暖金hover，不等于30张全目检。用户最终美术确认、手柄、各体型与未覆盖的依赖业务边界继续pending；手动驾驶仅沿既有自然减速语义，不外推全设备。

完整命令、head+working_tree快照、报告/截图链接、资源与退出泄漏警告及全局门禁边界见[最终验收记录](../../development/2026-11-12_quick_tools.md#5-正式-release-最终验收回填)。架构已PASS 25/0；全局sync/check最终结果以主线程最新运行独立补充为准。本次仅回填文档，不运行sync或测试，不改源码、资产hash、原save数据或 `main.tscn`；[历史失败与加固前证据](../../development/2026-11-12_quick_tools.md#4-本次验证过程与加固边界)保留。
