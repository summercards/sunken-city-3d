# SEA-QUICKTOOLS 开发记录

日期：2026-11-12

## 1. 设计与职责

本轮负责文档与 UI 资产登记，并保留代码为独立功能路径。新增 `SEA-QUICKTOOLS`，依赖 `SEA-UI`、`SEA-MOVE`、`SEA-BUILDING`、`SEA-PICKUP`、`SEA-DIVE`。

快捷工具是角色头顶的瞬态菜单：按一次 Alt 切换；陆地显示建造/拆除，船上显示钓鱼/潜水。允许普通 walking/strolling 与 sailing 上下文打开；打开环不主动取消既有自动航线。手动键盘驾驶因菜单 modal 不再读取驾驶意图，沿既有 `release_drive` 自然减速，不能承诺 manual sailing 状态不变；本次只修正文档，不改 production 航行逻辑。modal、过场、潜水、攀爬、室内、睡眠、采集中不打开；上下文变化与窗口失焦收起。普通 world action 菜单使用独立 presentation，不被快捷模块误关。

视觉口径复用 `WorldActionBubbles`：两枚 76px 青绿色圆按钮、奶油边、白色剪影，角色头顶屏幕锚点跟随，左右上弧布局；hover/focus 暖金 1.09；0.24s BACK 展开、0.035s 错峰、0.16s 收起；减少动态偏好即时生效。

## 2. 实现与端口

- `godot/src/quick_tools/quick_tools.gd`：只管理临时上下文、打开/收起、会话 token 和选中后复验，不拥有玩法状态。旧回调先验 token 与菜单 active，不能关闭新菜单；取消退场中/后不执行。Main 读档入口立即 `close(true)` 并 invalidate，不等下一帧门禁。
- `godot/src/ui/quick_tool_glyph.gd`：`quick_build`、`quick_demolish`、`quick_fish`、`quick_dive` 四个图元均为本地原创 Godot `_draw()` 程序化绘制，不加载位图、不伪造图片生成。
- `godot/src/bootstrap/main.gd`：仅做 QuickTools 节点装配、公开上下文查询和命令转发。建造/拆除仍沿 SEA-BUILDING 原资格确认与退款；钓鱼只接既有最近 24m 鱼群和 1.6s 停船采集链，无鱼提示；潜水沿既有先停船提示与 DiveSession 入口。不改用户手摆 TSCN/场景资源，不新增存档字段；运行时通过代码创建并挂载的 `QuickTools` 节点真实存在。
- `docs/architecture/module_contracts.md`：追加快捷工具端口与所有权说明。
- `docs/features/ui/spec.md`、`docs/features/ui/ledger.md`：追加 SEA-UI-R60 关联条款，UI 只承接表现和菜单隔离。
- `assets/registry/ledgers/ui.json`：独立登记四个程序化图元源，授权为 `local_original_procedural_Godot_geometry`；没有更新既有他人资产 hash。

## 3. 验收状态

当前 `SEA-QUICKTOOLS` 为 `implemented`（已实现待完整验收）：加固后正式release的8入口均通过，最终结果见[第5节](#5-正式-release-最终验收回填)。用户最终美术确认、手柄、各体型仍pending，不升级为verified。第4节与下列清单保留为回填前过程快照，不作为当前仍待运行的结论；本次文档修订未运行 Godot、统一 runner、sync 或架构/资产派生同步，避免干扰主线程及其他并行登记。

### 加固后最终复验待回填（历史清单，结果已回填第5节）

- `quick-tools`：Alt 单次切换、首次 release 前 non-echo duplicate Alt 锁与 echo、松开后再按收起、普通 world 菜单隔离、walking/strolling/boat_idle/sailing 上下文、打开环不主动取消自动航线、手动驾驶沿既有 `release_drive` 自然减速、会话 token 防旧回调关新菜单、取消退场中/后不执行、读档立即关闭并 invalidate、有效选中先关 modal 再复验、无鱼提示、既有 1.6s 采集链、潜水先停船提示。
- `visual-quick-tools`：76px 尺寸、青绿/奶油边/白剪影、角色屏幕锚点跟随、左右上弧、0.24s BACK、0.035s 错峰、0.16s 收起、hover 1.09、动效关闭即时态、窗口边缘和分辨率审阅。
- 阻断矩阵：modal、过场、潜水、攀爬、室内、睡眠、采集、窗口失焦和上下文变化。
- 主线程应回填命令、工程/源码快照、计数、退出码、unexpected/leak、真实截图路径与人工目检结论；不得以依赖模块历史 PASS 代替本功能证据。

## 4. 本次验证过程与加固边界

以下批次均由主线程执行；本次只读日志并补文档，保留失败历史，不运行 sync 或测试。

1. **first：44/1，FAIL。** 批次 `D:/projects/sea-work/verification/20261112-120840-quick-tools-first-2dbb56`，`quick-tools.log` 末 marker 为 `44 checks, 1 failures`。失败在“已打开后出现外部 modal，子节点 process 自动关闭”：夹具直接 `set_external_modal`，该值被 `IslandMenu` 每帧刷新覆盖，未持续建立真实 modal；随后改用真实 `cam_panel.set_open(true/false)`，不是改 production 门禁来迎合夹具。
2. **validation：quick69/2、visual219/2，FAIL。** 批次 `D:/projects/sea-work/verification/20261112-121327-quick-tools-validation-ffa854`，两日志末 marker 分别为 `69 checks, 2 failures`、`219 checks, 2 failures`。真实抓到旧 `KEY_2` 的 release 被新建造 UI 消费，`WorldActionBubbles` 残留键锁跨菜单，导致随后潜水项未执行，连带“撤 modal 后仅一次 request_dive/即时 switching”和“转场立即阻塞新输入”两断言失败。修复在 `WorldActionBubbles.open` 清旧锁，并重新捕获当前 E/本次 quick Alt，避免旧锁污染新菜单，同时保留开菜单长按不能直接确认的约束。
3. **final-d51e92：六项 PASS，仅为后续会话/输入加固前证据。** 批次 `D:/projects/sea-work/verification/20261112-121946-quick-tools-final-d51e92`，报告 `report.json` 记录 head=`9a3a4a0e5d76644deefe1cae068640071ce056f1` + 当时 working_tree；每项实际 Godot 命令、工程副本、渲染器和独立用户目录均在报告内。计数逐项取对应日志末 marker，不推测：

   | 入口 / 日志 | 末 marker 计数 | 报告结果 |
   |---|---|---|
   | `quick-tools.log` | 70 checks, 0 failures | exit0 / PASS |
   | `visual-quick-tools.log` | 220 checks, 0 failures | exit0 / PASS，真实渲染 |
   | `keyboard-building.log` | 40 checks, 0 failures | exit0 / PASS |
   | `dive-transition.log` | 501 checks, 0 failures | exit0 / PASS |
   | `keyboard-panels.log` | 81 checks, 0 failures | exit0 / PASS |
   | `ocean-pickups.log` | 48 checks, 0 failures | exit0 / PASS |

   六项报告均 `completion_marker=true`、`unexpected_errors=[]`。该结论只对应当时快照与上述入口；不据此声称没有任何资源警告、截图已逐图人工审完，或加固后无泄漏/全部验收。
4. **后续加固已落代码，release 待主线程签署（回填前历史状态，现已完成，见第5节）。** 会话 token 在打开/关闭时更新；旧回调在关闭动作前拒绝，不得关新菜单；取消退场中/后不执行；读档立即 `close(true)` 并 invalidate。R01补首次 release 前 non-echo duplicate Alt 锁与 echo，以及关闭态 echo 不重开。`D:/projects/sea-work/verification/20261112-123340-quick-tools-release-913ecd` 当时正由主线程运行；该阶段不读取中间计数冒充最终报告，不预签通过。当时要求最终源码快照、结果/退出码、unexpected/leak、真实截图与人工审阅由主线程完成后回填，功能及 UI R60 记录为已代码+加固、待最终复验。

## 5. 正式 release 最终验收回填

### 5.1 正式证据、快照与隔离

本节据主线程已完成的正式统一runner报告、最终日志和主线程提供的ViewImage审阅结论回填；本次文档线程未运行测试或sync。代码及当前专项已完成；最终功能登记仍保守维持 `partial`，原因是全局契约校验拒绝写回派生索引，且用户美术/设备完整验收未签署，并非verified；SEA-UI整体仍partial。

- [正式报告 report.json](../../../sea-work/verification/20261112-123340-quick-tools-release-913ecd/report.json)：label=`quick-tools-release`，head=`9a3a4a0e5d76644deefe1cae068640071ce056f1` **+ 报告中的working_tree快照**，不是该head的纯净提交结果；`source_overlay=null`。本次回填发生在验证后，不宣称报告包含后续文档修改。
- [隔离运行工程](../../../sea-work/verification/20261112-123340-quick-tools-release-913ecd/project/)：`D:/projects/sea-work/verification/20261112-123340-quick-tools-release-913ecd/project`。
- Autoload前隔离 `user://`，根名 `sea-verification/20261112-123340-quick-tools-release-913ecd`；各入口独立子目录，坏档seed与保护入口共用 `/protection`。不改原用户save数据、不改 `godot/scenes/main.tscn`，根v4/模块存档字段不变；不能把隔离坏档夹具写成用户原档被破坏。
- 只有 `visual-quick-tools` 使用真实渲染（Godot 4.7.2、Vulkan/Forward+、RTX 4060 Ti），其余7入口headless；不据此声称全设备通过。

### 5.2 完整命令与最终结果

统一runner复现命令如下（按本批入口与label列出；本次不执行，不冒充报告未留存的原始shell文本；runner会在 `save-protection` 前保证seed入口存在）：

```bash
python scripts/run_verification.py quick-tools visual-quick-tools keyboard-building dive-transition keyboard-panels ocean-pickups save-corrupt-seed save-protection --label quick-tools-release
```

报告中8组实际Godot argv完整等价展开如下（Bash变量只用于消除重复路径；由runner在各入口启动前设置隔离用户目录，禁止脱离该隔离流程直接操作用户档）：

```bash
GODOT="I:/下载/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
PROJECT="D:/projects/sea-work/verification/20261112-123340-quick-tools-release-913ecd/project"
"$GODOT" --path "$PROJECT" --headless --script res://tests/test_quick_tools.gd -- --skip-title
"$GODOT" --path "$PROJECT" --resolution 1280x800 --fixed-fps 60 --script res://tests/test_quick_tools.gd -- --skip-title
"$GODOT" --path "$PROJECT" --headless --script res://tests/test_keyboard_building.gd -- --skip-title
"$GODOT" --path "$PROJECT" --headless --script res://tests/test_dive_transition.gd -- --skip-title
"$GODOT" --path "$PROJECT" --headless --script res://tests/test_keyboard_panels.gd -- --skip-title
"$GODOT" --path "$PROJECT" --headless --script res://tests/test_ocean_pickups.gd -- --skip-title
"$GODOT" --path "$PROJECT" --headless --script res://tests/test_save_corrupt_seed.gd -- --skip-title
"$GODOT" --path "$PROJECT" --headless --script res://tests/test_save_protection.gd -- --skip-title
```

| 入口 / 最终日志 | 末marker计数或完成标记 | 正式报告结果 |
|---|---|---|
| [quick-tools](../../../sea-work/verification/20261112-123340-quick-tools-release-913ecd/quick-tools.log) | 116 checks, 0 failures | exit0 / passed=true |
| [visual-quick-tools](../../../sea-work/verification/20261112-123340-quick-tools-release-913ecd/visual-quick-tools.log) | 266 checks, 0 failures | exit0 / passed=true，真实渲染 |
| [keyboard-building](../../../sea-work/verification/20261112-123340-quick-tools-release-913ecd/keyboard-building.log) | 40 checks, 0 failures | exit0 / passed=true |
| [dive-transition](../../../sea-work/verification/20261112-123340-quick-tools-release-913ecd/dive-transition.log) | 501 checks, 0 failures | exit0 / passed=true |
| [keyboard-panels](../../../sea-work/verification/20261112-123340-quick-tools-release-913ecd/keyboard-panels.log) | 81 checks, 0 failures | exit0 / passed=true |
| [ocean-pickups](../../../sea-work/verification/20261112-123340-quick-tools-release-913ecd/ocean-pickups.log) | 48 checks, 0 failures | exit0 / passed=true |
| [save-corrupt-seed](../../../sea-work/verification/20261112-123340-quick-tools-release-913ecd/save-corrupt-seed.log) | `[save-corrupt-seed] complete`，无数值计数 | exit0 / PASS |
| [save-protection](../../../sea-work/verification/20261112-123340-quick-tools-release-913ecd/save-protection.log) | `[save-protection] ok=true protected=true unchanged=true separate=true`，无数值计数 | exit0 / PASS |

8入口均 `completion_marker=true`、`unexpected_errors=[]`；两项存档不编checks/failures数值。**这不是零警告或零泄漏声明**：最终日志仍有invalid UID回退文本路径、导航agent_radius精度及采集坐标吸附等警告；`dive-transition.log` 保留 `9 ObjectDB instances were leaked at exit` 警告，report未将其列入unexpected_errors。未做独立全工程资源生命周期验收。

### 5.3 加固覆盖与依赖边界

- 当前116/0与266/0已包含会话token、防旧回调关闭新菜单、取消退场中/后旧命令不执行、同类land读档立即关闭并invalidate、恢复前旧命令不能影响恢复后新环、失焦通知与旧命令失效、首次release前non-echo duplicate Alt/echo、关闭态echo不重开及edge caption完整包围盒边缘断言。边缘夹具取正式上下文快照后注入视口角点，不能说成所有边缘机位均已人工目检。
- 真实键鼠入口、普通world菜单隔离、land/boat分流、modal/标题/室内/房间过场/潜水切换/拾取中/sleeping拒绝、land→boat失效、减少动效即时态均有当前专项；攀爬等完整状态组合未逐项穷举。
- 打开环不主动取消既有自动航线；手动键盘驾驶不再读驾驶意图后仅按既有 `release_drive` 自然减速，未新增减速规则或独立全设备驾驶验收，不承诺manual sailing状态不变。
- 建造/拆除覆盖正式book/remove入口、不提前扣费或退款，依赖 `keyboard-building`40/0；不将入口专项扩写成全部建造资格、退款、保护组合通过。
- 钓鱼覆盖24m外无鱼提示、近木头不抢鱼、原航行→范围校验→1.6s采集→结算与重复推进不重奖；`ocean-pickups`48/0是依赖回归。满包鱼、重复目标等未新增独立快捷专项，不编造新测试；仍非鱼竿咬钩小游戏。
- 潜水覆盖航行中先停船提示/不切图、停船后先撤modal再一次request_dive/即时switching；快捷专项在deferred加载前dispose，不冒充完整潜水往返。完整往返与失败回滚归 `dive-transition`501/0依赖回归，不重复签署所有依赖边界。

### 5.4 PNG产出与人工审阅范围

[最终截图目录](../../../sea-work/verification/20261112-123340-quick-tools-release-913ecd/project/outputs/)内30张 `quick-tools-*.png`：1280×800、1600×1000、1920×1080 × land/boat × opening/open/hover/closing/closed。展开/收起取真实tween中间帧，hover为真实鼠标命中，closed检查根控件隐藏；截图非空、尺寸匹配与保存成功均有当前断言，不是合成效果图。

按主线程提供的ViewImage记录，本轮最终图仅已目检：

- [1280×800 land-open](../../../sea-work/verification/20261112-123340-quick-tools-release-913ecd/project/outputs/quick-tools-1280x800-land-open.png)。
- [1920×1080 boat-hover](../../../sea-work/verification/20261112-123340-quick-tools-release-913ecd/project/outputs/quick-tools-1920x1080-boat-hover.png)。

另有前轮1600两图已由主线程目检，仅作前轮补充，不替代本轮1600最终图审阅。主线程确认已审图无挡脸/裁切，青绿底、奶油边、白色剪影与暖金hover符合本轮表现口径；**不声称30张全目检**，本次文档线程未追加ViewImage审阅。用户最终美术确认、手柄及各体型仍pending，不声称完整产品或全设备验收。

### 5.5 架构与全局门禁待独立补充

主线程已提供架构 **PASS 25/0**，与本批8入口结果分列，不虚构其为report中的第9入口。全局sync/check此前曾为 **84/85 issues**；`assets/registry/current_source_index.json`仅定向补4条已修source index差异，不代表接纳其他资产hash漂移或全局问题已清零，本次也未修改该索引。

**最终主线程门禁补记：** 已执行 `python scripts/check_feature_contracts.py --sync` 与无参数检查。首次最终回填时sync为83项，check85项（其中1项为刚把快捷工具升级implemented造成的主表摘要不同、1项为派生索引过期）。脚本仅在所有issue为零时写回，因此本轮同步被既有资产哈希漂移、SEA-ASSET条款承接不齐及并行plant_authoring引用缺资源等阻断；不批量刷新未知哈希绕过门禁。为保持主文档与账本一致并如实反映全局门禁，快捷工具登记回退partial，代码及专项PASS不受影响。恢复partial后再跑：sync为83项、无参数check为84项（多1项derived feature index stale），均exit1；不再出现SEA-QUICKTOOLS状态/条款问题或source index差异。本轮范围内git diff --check通过（末命令exit0不代表前两条门禁通过）。架构校验25个独立规则/存储服务、0问题、exit0。第4节历史失败及其修复过程完整保留。
