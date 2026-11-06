# 2026-11-06 默认玩法全键盘实施总交付与实测

[主文档](../../GDD_V1.0.md) · [Farm](../features/farm/spec.md) / [账本](../features/farm/ledger.md) · [Interact](../features/interact/spec.md) / [账本](../features/interact/ledger.md) · [UI](../features/ui/spec.md) / [账本](../features/ui/ledger.md) · [Camera](../features/camera/spec.md) / [账本](../features/camera/ledger.md)

## 交付性质与当前状态

本记录汇总本轮默认玩法全键盘的实际实施、最终专项验收、过程失败与未完成边界。用户目标是**种植区及默认已开放玩法全键盘、不留鼠标专属入口；日常操作无提示/无键位教程，靠近可交互物显示原hover图标**。玩家主动打开的系统帮助允许，维护键位表不自动出现在日常玩法中。

最终键盘专项farm606/0、travel374/0、panels80/0、building40/0、entry39/0均通过；近距无教程真实渲染farm617/0、建筑visual43/0均exit0、passed=true。近距9张唯一截图已落盘，本轮画面目视审阅watered/full-bag/harvest-overhead/already-watered确认无底部条和键位教程。200446回归报告18项均已返回，14通过、4失败，**该历史批次不是全绿**。四项旧测试已在201957契约适配批次通过：interaction-reach35/0、dock-seed22/0、minimum-loop147/0、harvest-receive92/0，均exit0、passed=true，不再pending；203447最终keyboard-final-contracts七项均PASS、合计479/0，已收口。

实现、测试与有限范围登记分别完成；文档回填按实际report/log记录，不把文字登记代替运行验收。用户TSCN位置未改。建造键盘条款R33与专项证据已追加承接，不代签全部新套件组合。四功能登记头保持 **partial**，四项契约回归与口袋文案同步差异已收口；仍保留full-world/规划/设备与所有输入组合未全面验收的边界；最终合批已通过，但整体门禁仍受哈希/并发登记问题阻挡，不能混为一谈。

证据口径：计数以日志末行、通过与退出码以report为准；画面证据统一记为“本轮画面目视审阅”，不是用户亲自验收，也不伪称本次文档回填重新看图。历史失败保留，最新通过替代旧待跑状态；未提供的新回归报告不推测为通过。

## 条款编号与历史覆盖

追加前已检索当前 spec/ledger：Farm 最大 R14、Interact 最大 R18、Camera 最大 R14；UI spec 最大 R52，但 ledger 已占用集中建筑 UI 的 **R53**，因此从 R54 起，不撞号、不重编号历史重复条款。

| 功能 | 本轮已登记 ID（沿用，不新增编号） | 承接 |
|---|---|---|
| SEA-FARM | R15、R16 | 全阶段菜单入口、二级返回、原业务种植闭环与单次结算 |
| SEA-INTERACT | R19、R20、R21 | 近距循环/选中优先、松开防连发、完整世界菜单键盘路由 |
| SEA-UI | R54、R55、R56、R57 | 近距无教程式反馈、服务/背包、笔记地图、首创及系统安全返回 |
| SEA-CAMERA | R15 | 独立键盘取景/缩放/跟随入口 |

用户新增无提示要求正式覆盖而不删除历史：上午SEA-INTERACT-R18底部prompt常显、R17/SEA-UI-R52角标要求已被近距原hover图标/真实进度及无教程行取代；动作、状态、灰因保留。主动系统帮助是允许项。Camera-R12“只留鼠标”由独立取景键取代，WASD/方向/Q/E不驱动镜头仍有效。当前视觉通过引用194828最终证据，不借上午截图。

ledger登记头verification数组已精确插入正式映射：Farm登记keyboard-farm-loop、visual-keyboard-farm-loop、keyboard-travel、keyboard-panels；Interact登记farm-loop两入口与travel；UI登记panels、entry、farm-loop两入口、travel、building两入口；Camera登记travel与visual-keyboard-farm-loop。原数组其他项、status及上部历史保留。`scripts/run_verification.py:43`的keyboard-travel映射已核实存在，未改runner或生成索引。

UI集合门禁修复：按`check_feature_contracts.py:121`、`:122`的表格行正则只读比对，原spec为56个唯一ID、ledger57个，`spec-only={}`、`ledger-only={SEA-UI-R53}`。此前spec正文写“R53已占用”不被提取。现仅在UI spec末尾追加R53表格行，引用真实SEA-BUILDING-R32集中表现边界，不新增实现、不删除ledger R53；修后两边R01–R57共57个ID一致，R54–R57均各一行。主线程最新sync已不再报UI ID集合及unknown verification命名错误；旧building未知verification错误保留为已解决过程，不再列当前阻塞。其余哈希/并发登记问题与本次文档ID修复分开，当前sync仍13 issues，普通check加derived stale共14，详见末尾门禁补记；本次未重跑门禁或sync，不宣称全局已绿。

## 实现完成链条与所有权

### 1. 近距选目标、E 与船不抢同一目标

- `godot/src/interaction/interactor.gd:46` 的 `candidates()` 过滤不可见、不可交互、空间不可达、垂直差过大与超近距目标，按节点路径稳定排序；`:66` 的 `cycle_target()` 提供 Q/Shift+Q 正反循环。
- `godot/src/bootstrap/main.gd:2288` 路由 Q；`:2412` 的 `_boat_key_action()` 在 active 且 `keyboard_target == target` 时不给上船抢 E。未显式选中时保留物件与泊位距离取舍；船上拾取/上下船/近泊位靠岸仍走原链。
- `interactor.gd:60/101/187` 的 require_release / `_wait_release` 保证手动 E 成功（含 options）后先松开；`world_action_bubbles.gd:35/106/183` 的 held-key、echo 与同帧保护阻止持续 E 穿菜单或重复确认。

### 2. 一级/二级菜单与成熟地格

- `godot/src/farming/farm_plot.gd:86`：`use_action_menu=true` 时不论 empty/growing/ready 都发 `interaction_requested` 返回 options，**ready 也先选收获**，不直接发奖。
- `main.gd:3623/3651` 装配地格一级；`:3770` 选种二级只列持有种子，保留真实数量，并用 `back_action` 回同格一级；一级 Esc 关闭。
- `godot/src/ui/world_action_bubbles.gd:35/96` 打开默认选中首个可用项（全灰保留选择与原因），方向键/WASD/Tab 导航，Enter/KPEnter/E/Space 确认当前项，数字1…9直达；灰项反馈原因不执行、不关闭。
- `main.gd:3785/3795` 接近、计时后调用 `FarmPlot.perform`，水壶空走原补水并浇水组合。成功 Farm→FarmPlot/FarmField acted→角色表现仍只一次；取消/缺种/重复浇水/满包不生成假成功。

### 3. 种植与次日循环

默认六格稳定 ID 为 `platform_plot`、`platform_plot:1..5`，DIY 格沿已有登记/命令，不另存键盘作物状态。链条为近距选格→一级种植→二级选种→播种→浇水→房门/床→睡眠醒来换天→继续照料→成熟显式收获→再种。生长由既有 `Farm.advance_to_day` / grow_day 水位线拥有；07:00 出货仍归 DailyShipping；库存、奖励与存档归原所有者。

`godot/tests/test_keyboard_farm_loop.gd` 纳入六格循环、不误操作邻格、E不被船抢、持续E/echo、菜单焦点/布局、二级取消、过期种子执行重验、已浇拒绝、空壶补水、三次真实床铺睡眠、满包保留成熟、收获实物/动画一次与再种。**位置、库存、水壶、初始日历属于夹具**，首创由另一专项验证；不能据此声称一份新档从标题一路无夹具旅行、全部作物或所有 DIY 布局都通过。

### 4. 靠近出现原 hover 图标，不恢复底部说明条

- `main.gd:1484` 当前为 `prompt.enabled=false`，覆盖上午恢复底部 prompt 的临时方案；旧 InteractPrompt 节点/代码保留不代表可见。
- `main.gd:1064` / `hover_card.gd:63/76` 让 `_near_icon` 与 `_near_progress` 读取真实焦点/进度；不依赖鼠标位置，零进度收条，同位置不叠两颗图标。船边资源/泊位图标沿原查询。
- `main.gd:1814` 菜单opened即收近距图标；`input_blocked()`、指针UI与过场生命周期负责modal/叙事/标题/睡眠等接管。farm-loop606/0及真实渲染617/0已有该链证据，不再写全部视觉pending。
- `world_action_bubbles.gd:66/123` 保留当前动作、状态、数量、灰显原因，`hotkey=""`，不画数字角标、不加方向/确认教程行。数字键逻辑仍在。

**说明文字收口**：玩家主动打开system help及系统返回提示允许，不列缺口。重新核实当前生产源码，`godot/src/ui/pocket_service.gd:247`已仅“上限…余额…”，`:281`仅动词/数量/整叠，`pocket_inventory.gd:168`仅option.label；原“按1购买”句与动作数字前缀确已删除，口袋同步差异已解决，不再pending。库存、限额、余额、动作数量和灰因保留，数字键逻辑不因去前缀被删除。200446副本中的旧字符串仅为清理前历史，不能代表现生产。`hud.gd:511`无目的地拒绝反馈仍有Esc是独立点状事实，不据此将整个清理段重新标pending。203447最终keyboard-final-contracts已覆盖新契约、面板80与旧pocket回归，七项均PASS；不再待附，也不以旧panels80/0代替新合批证据。

### 5. HUD面板、笔记地图与单次确认

`godot/src/ui/hud.gd:557/597` 在 GUI 前收口按键与帧级激活，按下/松开、echo及多确认键同帧不重复业务。服务数量由真实 max_buy 封顶；存/取1或当前整叠、当前池分页、纯背包/服务上方背包 Shift排序复用原信号与 Inventory 命令，禁止跨到商品/仓库/出货托盘整理，刷新按物品ID恢复焦点。

`notebook.gd:114/180/185/192` 保持分类、卡片、详情动作和返回焦点；`hud.gd:498/513/524` 以稳定 zone ID 恢复地图目的地，跳过禁用项并滚动可见。笔记→地图/服务/地格仍发原 requested、destination_pressed、plot_focus_requested，不创建旅行或库存真值。`keyboard-panels` 是正式 HUD+真实模型、但目的地只验原信号，不等价于船已驶达。

### 6. 新档入口与系统边界

`start_screen.gd` 的默认焦点与Enter/KPEnter/Space入口、`avatar_editor.gd:543/603/615` 的姓名/外观/旅人证、稳定ID焦点/滚动、失败重试和取消、`island_menu.gd:161/190` 的设置/重置安全返回均已有实现。entry专项覆盖首创Esc不绕过、台词首击补全/次击推进、已有档案编辑取消和设置音量/重置默认取消。

**entry保存端口使用内存替身模拟失败/重试**，不实际写文件；39 checks不能替代磁盘保存、冷启动或真实断电验收，不能把“默认取消重置”写成“已执行整档重置”。

### 7. 镜头、室内退出与建造交接

`godot/src/camera/orbit_camera.gd:261` 的 `[`/`]`→既有orbit，`-`/`=`→set_distance；`main.gd:2294` F→restore_follow(player)，`:2280` X→正式room_exit命令。UI/过场与固定机位门禁、室内orbit-only约束仍须专项核验；本轮没有重设镜头参数或用户位置。

K入口、世界键盘游标0.1/Shift0.01米、搬移/拆除与默认否安全确认归SEA-BUILDING，keyboard-building40/0、visual43/0已由最终报告核实通过。详细设计承接仍引用[building设计](../features/building/spec.md)、[账本](../features/building/ledger.md)及[现有交付](2026-11-06_building_5m_and_ui.md)，不改其文档、不分配building新ID，UI-R53既有登记不挪号。

## 维护键位表（不作为游戏内教程）

| 场景 | 输入 | 正式语义/边界 |
|---|---|---|
| 岸上/船上 | WASD / 方向键 | 角色/船移动；菜单与建造接管时不穿透 |
| 岸上近距 | Q / Shift+Q；按住E | 顺/逆循环合法目标；对选中目标交互，成功后先松开 |
| 船上 | E | 原资源拾取、上下船或近泊位靠岸，受距离/航行/模态限制 |
| 世界菜单 | 方向/WASD/Tab；Shift+Tab | 切换当前项；默认选中不等于自动执行 |
| 世界菜单 | Enter / KPEnter / E / Space；1…9 | 确认当前项或数字直达，灰因保留；无上屏角标 |
| 世界种子二级 | Esc | 回同格一级；一级Esc关闭，不穿透暂停 |
| HUD | B / Tab；N | 背包；笔记及其服务/地图入口；地图Tab用于目的地导航 |
| 口袋/服务 | 方向；Shift+方向；PgUp/PgDn | 选格；背包排序；服务当前池/笔记分页（纯背包随容量加行，不冒称其有分页） |
| 购买/存取动作层 | 左右；方向/数字；四种确认 | 调数量；选1件/整叠；只结算一次，Esc先回物品 |
| 建造 | K；方向；Shift | 既有手册/世界游标0.1/0.01与安全确认专项40/0、visual43/0通过，详细契约归building |
| 取景 | [ / ]；- / =；F | 转镜头；缩放；恢复跟随，不占移动/Q/E |
| 室内 | X | 既有room_exit；不另写房间/存档状态 |
| 首创/编辑 | Tab / Shift+Tab、方向、Enter/KPEnter/Space、Esc | 保留输入框/滑杆原生语义；首次不跳建档，已有编辑可取消 |
| 系统 | Esc；F5；F9 | 分层返回/暂停；原保存；读取确认（安全取消优先） |

这是一份当前维护映射，不构成 `--full-world` 每个历史面板、调试面板、设备输入与所有按键组合均已通过的承诺。

## 默认、full-world、仅景观与规划边界

依据 `godot/src/core/play_scope.gd:11–20` 与 `main.gd:1707/3468`，本轮不修改范围开关或场景挂载。

| 类别 | 当前边界 |
|---|---|
| 默认范围 | zone1、zone2、zone5、sea_supply、rooftop_ranch、neon_garden_quarter、room为范围允许列表，仍须实际挂载、可达、解锁与当前位置合法；允许列表不是每处都可上岸的证明 |
| 默认已开放链 | 岸边采集、海面鱼/漂流物拾取、种植照料、服务口袋、每日出货、房间/床睡眠、首创/外观、存读/设置、笔记地图及独立DIY建造入口；本轮全键盘目标不自动等于这些全都最终验收通过 |
| 默认禁用 | `build/dive/lamp/hook/camera/orders/salvage/rise/descend`命令仍禁；build是旧建造计划页，不是craft/K DIY；camera是取景面板，不是镜头本体；海面拾取不等于绞盘小游戏 |
| 绞盘特别澄清 | 当前`_apply_play_scope`隐藏并停用salvage_winch，`_open_salvage`在minimal直接返回；不能沿GDD旧阶段描述写成默认绞盘可玩 |
| full-world | 仅显式开发回归配置；放开开关不自动补回主场景已移除的zone3/zone4，也不完成潜水/订单等未列入本轮默认闭环的验收 |
| 景观与手摆状态 | 水下建筑/海下基座/沉没旧城不承诺交互、行走、阻挡或产出；霓虹花园当前沿用户TSCN标高，旧街口不可上岸状态不被文档擅自修正；所有坐标以用户手摆为准，本次未动 |
| 仍为规划/另项 | 居民、任务、全部长期成长、开垦/工具升级/品质/季节、未来DIY绘图等不因键盘补入口晋升可玩；P调试工具不算正式玩法新增 |

## 最终报告、完成状态与验收矩阵

以下六份report及日志完成计数已核实；report共同记录head为`345fa178ad698bd704ba5e61c94fd5e7937be27b`且工作区存在未提交改动，不能将该head单独当作源码内容指纹。计数按日志末行，headless农场为606、visual为617。

| 证据代号 | 绝对路径 | 完成状态 |
|---|---|---|
| H | `D:/projects/sea-work/verification/20261106-200446-keyboard-release-regression-eae88a/report.json` | 18项均已返回exit_code；14通过、4失败，不是运行中，也不是整体PASS |
| V | `D:/projects/sea-work/verification/20261106-194828-keyboard-visual-travel-final-09cca9/report.json` | visual-keyboard-farm-loop与keyboard-travel均exit0、passed=true、completion_marker=true、unexpected_errors空 |
| B | `D:/projects/sea-work/verification/20261106-191403-visual-keyboard-final-no-instructions-5m-8295dd/report.json` | visual-keyboard-building已结束，exit0、passed=true、completion_marker=true、unexpected_errors空 |
| C | `D:/projects/sea-work/verification/20261106-201957-keyboard-contract-regression-888baa/report.json` | 四项契约适配全部完成：interaction-reach35/0、dock-seed22/0、minimum-loop147/0、harvest-receive92/0；均exit0、passed=true、completion_marker=true、unexpected_errors空 |
| F | `D:/projects/sea-work/verification/20261106-203447-keyboard-final-contracts-ff6d9f/report.json` | 最终合批7项全PASS：keyboard-panels80/0、interaction-reach35/0、dock-seed22/0、minimum-loop147/0、harvest-receive92/0、pocket-bubbles59/0、pocket-drag-buy44/0，合计479/0；全部exit0、passed=true、completion_marker=true、unexpected_errors空 |
| P | `D:/projects/sea-work/verification/20261106-204809-verification-52bb38/report.json` | keyboard-panels真实渲染93/0（80+layout/captures）、exit0、passed=true、completion_marker=true、unexpected_errors空；4张截图；此批次在ac_card footer教程删除之前，不能据此签署清理后最终无教程 |

H中已通过项的passed与completion_marker均true、unexpected_errors为空；这不等于日志零警告。每项原日志与report同目录，名称为`<入口>.log`。V/B真实渲染参数均1280×800、fixed-fps60；headless与visual独立登记。

| 入口 | checks / failures | exit / runner | 证据及覆盖 |
|---|---|---|---|
| keyboard-farm-loop | **606 / 0** | 0 / PASS | H；六格、同一选中E、菜单释放/拒绝、三次床睡、成熟收获再种 |
| visual-keyboard-farm-loop | **617 / 0** | 0 / PASS | V；真实近距图标/进度与菜单/灰因/实物、9张唯一截图，本轮画面目视审阅4张 |
| keyboard-travel | **374 / 0** | 0 / PASS | H、V两次；地图→原航行靠岸→WASD行走/采集→六格菜单/返回与室外相机键，初始定位夹具保留 |
| keyboard-panels（headless） | **80 / 0** | 0 / PASS | H、F；最终F已包含口袋清理后合批；数量、存取1/整叠、分页、Shift排序、笔记地图焦点/滚动、单次确认/不穿透 |
| keyboard-panels（真实渲染） | **93 / 0** | 0 / PASS | P；原80+layout/captures、4张图；footer清理前批次；最新keyboard-panels-clean-final路径/结果待主补，不用P旧图证明最终无教程 |
| keyboard-building | **40 / 0** | 0 / PASS | H；K/手册/世界游标0.1/0.01、搬移与拆除默认否；设计仍归building |
| visual-keyboard-building | **43 / 0** | 0 / PASS | B；真实建筑UI/游标/确认，日志列book/placement/demolition三张截图，未据此声称本轮已逐张目视审阅 |
| keyboard-entry | **39 / 0** | 0 / PASS | H；姓名外观首创、失败重试/编辑取消、台词/设置/重置默认取消；保存内存替身，不替代写盘/冷启 |
| keyboard-control | **30 / 0** | 0 / PASS | H |
| control-feel | **31 / 0** | 0 / PASS | H |
| camera | **12 / 0** | 0 / PASS | H；日志marker为camera-follow |
| click | **32 / 0** | 0 / PASS | H；日志marker为click-controls |
| initial-planters | **247 / 0** | 0 / PASS | H |
| walk-on-planters | **53 / 0** | 0 / PASS | H |
| farm-day-change | **23 / 0** | 0 / PASS | H |
| pocket-bubbles | **59 / 0** | 0 / PASS | H、F |
| pocket-drag-buy | **44 / 0** | 0 / PASS | H、F |
| interaction-reach | **35 / 0** | 0 / PASS | C、F；已承接无角标与当前菜单规则；H历史35/1为旧“第一项带键位角标1”断言 |
| dock-seed | **22 / 0** | 0 / PASS | C、F；已承接当前二级标题；H历史21/1为旧“二级有层级标题”断言 |
| minimum-loop | **147 / 0** | 0 / PASS | C、F；显式菜单选择收获后经营链通过；H历史141/10为scene harvest及库存/仓储/出货/迁移连锁断言 |
| harvest-receive | **92 / 0** | 0 / PASS | C、F；已承接E开菜单后显式收获与单次动作；H历史80/1为旧E直接收获断言 |

H的四项FAIL保留为本轮菜单显式收获、无角标/新标题契约变更的**测试承接过程失败**，不是范围外，也不追改旧report为通过。C已在适配后逐项PASS收口，计数按各日志末行35/0、22/0、147/0、92/0，不再pending；这是新证据替代待验状态，不是以farm视觉PASS抹去失败。F最终keyboard-final-contracts合批现已完成：面板80/0、四契约35/0/22/0/147/0/92/0、旧pocket59/0与44/0，七项均exit0、PASS，合计479/0；旧H四项失败仍按历史过程保留，不追改。

### 近距无教程真实截图与本轮画面目视审阅

V的截图目录为`D:/projects/sea-work/verification/20261106-194828-keyboard-visual-travel-final-09cca9/project/outputs/`，已核实9张唯一文件：`keyboard-farm-planted.png`、`keyboard-farm-watered.png`、`keyboard-farm-already-watered.png`、`keyboard-farm-wake-1.png`、`keyboard-farm-refill-watered.png`、`keyboard-farm-wake-2.png`、`keyboard-farm-wake-3.png`、`keyboard-farm-full-bag.png`、`keyboard-farm-harvest-overhead.png`。日志有11次成功截图记录，planted与watered路径重复写入，故617 checks不能减成“只截图9次”，也不能将11次写入冒称11张唯一图。

本轮画面目视审阅已检查**watered / full-bag / harvest-overhead / already-watered**，记录无底部条和键位教程；其余5张仅登记已生成，不伪造人工逐张审阅，不将审阅写成用户亲自验收。B的三张建筑截图在其`project/outputs/keyboard-building-{book,placement,demolition}.png`，与本轮9张农场图不混计。

P面板截图目录为`D:/projects/sea-work/verification/20261106-204809-verification-52bb38/project/outputs/`，4张文件已核实：`keyboard-panels-01-bag-actions.png`、`keyboard-panels-02-shop-buy-three.png`、`keyboard-panels-03-warehouse-whole-stack.png`、`keyboard-panels-04-map-zone5-focus.png`。本轮画面目视审阅shop/map发现`ac_card` footer仍有旧Esc/滚轮教程；主线程已删除，当前`godot/src/ui/ac_card.gd:168`为`footer.text = ""`。P的93/0只证明该次渲染、布局/捕获与原业务断言，不证明删footer后的最新最终无教程。清理后最终批次 `D:/projects/sea-work/verification/20261106-210922-keyboard-panels-clean-final-5186a7/report.json` 已完成：visual-keyboard-panels **93/0**、keyboard-travel **374/0**，均exit0、PASS且unexpected_errors为空。4张新图位于该批 `project/outputs/`；本轮重新目视最终map图，旧Esc/滚轮教程已消失，浅水养殖目的地焦点完整可见。

### travel失败到修后通过

历史travel曾374/0但`Zones.footprint`负Rect引发runner FAIL；该过程不删除。`godot/src/world/zones.gd:66`加入`.abs()`后，V与H的travel均374/0、exit0、passed=true、unexpected_errors空，已完成修后重跑，不再列待跑。旧失败report确切目录未在本轮提供，不能猜路径；保留会话失败事实与两份最终修后证据。

### 剩余收口

- 四项旧契约已由C批次全部通过，不再待填；旧失败原因与H证据保留。
- 口袋按1说明/数字前缀已在当前生产源码删除，原同步差异已解决；主动system help允许。最终keyboard-final-contracts的F报告、面板/旧pocket等七项计数与exit0均已核实并登记，不再pending；`hud.gd:511`点状拒绝文案事实独立保留，不将整段清理标pending。
- building键盘路径已由R33及其账本行承接40/0与visual43/0真实通过，不再写全部证据pending；R30/R31的新几何与任意多层组合不由本键盘专项代签。
- 面板P批次真实渲染93/0及4图已登记；删除ac_card footer教程后的210922最终批次93/0、travel374/0及新图审阅已收口，无待填最终批次。
- 室内全部取景边界、full-world未开放/未挂载内容、其他作物/DIY布局、触控/手柄/发行包/真实断电与所有按键组合不因本轮专项自动通过；四功能整体partial保留。

## 并发与修改范围

总交付实现已由既有键盘入口、业务所有者与上述隔离runner完成；本记录回填范围仍仅原八份spec/ledger、本开发记录与GDD既有尾节。使用Edit精确更新本轮段落与ledger verification数组，不整文件覆盖、不碰GDD上部历史、不改其他会话内容。没有新增文档、运行检查/sync、改生产/资产哈希/用户手摆TSCN或building文档；当前四功能partial保留，已通过专项、201957四项契约适配通过与200446历史过程失败明确分列；203447最终合批7项全PASS、479/0及204809面板真实渲染93/0已附；footer清理后210922最终批次也已通过93/0与travel374/0。这些结果不代表全局门禁全绿。

## 最终交付补记

- 删除详情页底部旧Esc/滚轮教程后，210922最终实景面板93/0、键盘旅行374/0均通过，4张面板新图已生成；最新地图截图已目视确认无教程footer。
- `visual-keyboard-panels`已正式登记runner与UI账本；全部正式运行均在隔离用户目录，没有修改玩家存档。
- 已追加建造R33及其键盘/无常驻教程验收，不覆盖并发套件的其余几何范围。

## 最后门禁与登记边界补记

以下门禁、位置与差异格式结果来自主线程最新回报，本次文档收尾没有再跑验证、sync、普通check、placed_positions或git diff --check，也没有触碰registry、哈希或用户场景位置。

- 当前登记规模：**40 features / 881 source assets / 1079 runtime resources**，不沿用旧数量。
- 最新sync已消除UI requirement IDs集合及unknown verification命名错误；当前仍 **13 issues**。普通check另加`derived feature index stale`，共 **14 issues**；同步未成功生成全局一致状态，不能称全绿。
- 13项为underwater派生视图过期、鱼asset漂移，以及11项运行hash：`water.tres`、`main.gd`、building的`assembly_rules`/`assembly_surfaces`/`building_catalog`/`building_controller`/`building_service`、`ground_space`及3个UI运行资源。3个UI运行资源具体为 `building/ui/building_book.gd`、`building/ui/demolition_tool.gd`、`building/ui/building_view.gd`；详细归属以主线程门禁输出为准。
- `main.gd`包含本轮键盘与并发改动，未强制刷哈希。不能简单把全部剩余漂移归为“范围外”，也不能因键盘专项通过就接纳全部并发内容。
- 本轮已完成定向review并更新 **4资产 / 4 runtime**，由registry代理办理；这是真实有限范围登记，不代表所有本轮资源hash均无漂移。本文档代理未自行刷新其他哈希、派生视图或索引。
- 主线程回报placed_positions **3项全PASS、0warnings**，`git diff --check`通过；这不替代仍红的全局feature/asset门禁。
- 用户景观TSCN手摆位置继续为位置真值，不因审计剩余hash、视图或参考坐标而修回初始参考位。已通过玩法/渲染与仍受阻全局登记分别记录，四功能保持partial。
