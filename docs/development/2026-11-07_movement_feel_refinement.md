# 2026-11-07 移动手感细修：顶岸脱困、Shift小步跑与正面交互

[主文档中控](../../GDD_V1.0.md) · [MOVE设计](../features/move/spec.md) / [账本](../features/move/ledger.md) · [NAV设计](../features/nav/spec.md) / [账本](../features/nav/ledger.md) · [INTERACT设计](../features/interact/spec.md) / [账本](../features/interact/ledger.md)

## 本轮范围与状态

用户11-07反馈：船头顶岸后无法转向/退开；Shift希望是轻快小步跑、只略提速；种植区靠岸处应面对操作区域才判定，不能靠近泊位就误触离岸；继续不显示操作教程。

本次移动手感实施与最终合批已完成：165822报告11项全PASS；170723最终渲染报告真实shore163769/0、视觉农场647/0双PASS，均exit0且unexpected_errors空；最新172123的facing102/0 PASS确认NPC/dive最新装配可启动。轻跑、原地转脸、正面交互、键盘生活与真实岸线画面已收口，主任务已目检最新boatsequence、facing plot及shift phases。171743兼容批只有actor-presentation PASS、其余五项runner FAIL如实保留，新版DiveSession装配后的172517五项兼容复验均PASS，不宣称整套潜水完成。三个功能保持`partial`，不外推为全工程或所有设备组合通过；主任务已执行全局sync与普通check但仍未绿，未强刷哈希。GDD已由主任务追加摘要，本次只回填原七文件，不改生产、registry/hash、TSCN或NPC摆位。

追加前最大条款已核对为MOVE-R25（移动浮台）、NAV-R18（浮动商亭）、INTERACT-R21（菜单键盘）；新增MOVE-R26/R27、NAV-R19、INTERACT-R22/R23，不占用或重编号已有条款。正文数值来自本轮实际源码，历史任务状态不当作当前实现证据。

## 实现契约与当前源码

### 1. 船头顶岸仍能摆头脱困（SEA-NAV-R19）

- `godot/src/navigation/boat.gd:305`：`_drive()`按`1/120s`子步调用`_advance_drive`，单帧消费`clamp(delta,0,0.25)`。不是提高渲染帧率，也不是放宽岸线。
- `boat.gd:314`、`:354`：子步先积分yaw/舵效/侧滑，再用`_clear(here,moved)`复核平移。受阻时`_vel`与`_speed_actual`归零，但保留`manual_drive`、`drive_dir`和`_yaw_rate`；继续按键可原地摆头，朝合法水面后划开。退开仍是朝期望世界方向转船后推进，不新增倒车档，不直接推船出岸。
- `boat.gd:356`、`:366`：`_manual_blocked`保证一轮贴岸只发一次`navigation_blocked`；只有合法推进累计至少0.1m才重新开放反馈。再次碰撞归零累计距离，方向明显变化（`set_drive`中角差>0.08rad）也归零累计距离，防止微进/再撞刷提示。
- **release的精确边界**：`boat.gd:270`的`release_drive()`当前只清方向，不立即清锁存；按原刹车与角速度收敛，直到`:373`确认停稳、退出手动才清锁存和累计距离。`stop_drive()`（`:289`）、`place_at()`（`:145`）、`sail_to()`（`:173`）则同步清理。不能把「松手最终结束驾驶会清理」写成「release当帧清理」。
- `godot/src/bootstrap/main.gd:1267`：手动阻挡回调只给一次结果反馈，不切回`boat_idle`；自动阻挡仍取消待处理并回船上待机。`:1073`仅在`not boat.driving()`时分派泊位朝岸方向键自动上岸，不吃掉脱困中的手动输入。
- `boat.gd:527`：自动路线遇碰撞仍停止并发阻挡，不套用手动继续摆头的逻辑。`boat.gd:584`与`godot/src/rendering/boat_wake.gd:27`让手动尾流取实际航迹方向；阻挡实际速度为0，不伪造移动尾迹。自动模式不消费旧手动侧滑方向。

### 2. Shift轻快短步跑（SEA-MOVE-R26）

- `godot/src/bootstrap/main.gd:1054`将岸上方向输入与物理Shift状态提交给控制器；`godot/src/player/actor_controller.gd:151`限制为输入未阻断、有方向、mode0且`strolling`，不是所有动作共享一个全局加速开关。
- `godot/src/player/actions/free_walk_action.gd:16`、`:62`：普通目标速度2.3m/s；Shift乘1.12，目标`2.576m/s`，继续共用0.085s起步/0.055s收速及原反向积分，不改点击走路。
- `free_walk_action.gd:115`：实际位移地速除以**2.3**写`walk_speed_ratio`，轻跑稳态1.12；不是除以2.576把表现误归一回走路。
- `godot/src/player/character.gd:95`、`:384`：0.12s指数姿势混合，走/跑共用连续相位。地速已带来12%相位提升，额外仅乘`1.15/1.12`；稳态`6.4×1.12×(1.15/1.12)=7.36rad/s`，不是再完整乘1.15。
- `godot/src/player/animation/walking_action.gd:8`：腿摆幅从0.54收至`0.54×1.12/1.15`，屈肘基线约-0.82rad、回收膝抬幅0.86rad、躯干轻前倾约0.12rad，以短步轻跑而非整段动画放大/快放表达。
- 松Shift回走速与姿态；松方向清轻跑意图、保留既有收速。模态、取消、睡觉、上下船、潜水、恢复及点击接管经原生命周期清临时标记，非走路表现归零混合。只按Shift不启动移动；不新增体力消耗、存档字段或玩法状态。

### 3. 被岸边挡住也能转脸（SEA-MOVE-R27）

`free_walk_action.gd:93`在合法地面判断完全挡停时清速度与实际速度比，仍按非零intent平滑转脸；`:110`在物理位移不足时同样使用intent，不强行挪根位置。正常移动沿既有速度方向转向。`character.gd:386`仅在实际速度比非零时推进步行相位：挡停位置0变化、步相位0增量，不原地空踩。该补丁用于解除「想朝船但边界不让走→不能转身→正面交互永远不成立」的死锁。最终165822合批已纳入补丁后的轻跑56/0、视觉57/0；`godot/tests/test_shift_jog.gd:245–248`新增3条断言分别守住根位置不挪、侧向输入确实转脸、实际速度比与相位保持0增量，不再列为待验。

### 4. 正面操作与泊位防误触（SEA-INTERACT-R22/R23）

- `godot/src/interaction/interactor.gd:45`、`:56`：手动候选取角色局部+Z的水平dot≥0.55，约±56.6°；水平距目标≤0.35m近中心豁免。可见、可交互、空间可达、半径及高度过滤仍保留。
- `interactor.gd:67`：仅`auto_hold && node == preferred_target`的明确自动目标豁免朝向，已选命令仍在正常hold边界消费一次；单独preferred或Q选择不能豁免。
- `interactor.gd:81`、`:215`：Q/Shift+Q只循环当前正面候选，转身离面/越距/不可达清旧`keyboard_target`，不能用历史选中操作身后种植格。
- `godot/src/bootstrap/main.gd:2526`：岸上上船仍须当前船靠泊、距stand≤2.4m、非冷却/过场/模态，另要求朝**实际boat位置**dot≥0.60；不以`stand-here`零向量当正面。有效spot默认优先，boat alignment至少高出spot alignment 0.15才能胜；有效显式Q spot受保护。
- `main.gd:1085`的near图标和E分派共用`_boat_key_action()`胜者；不得图标承诺种植、E却送上船。
- `main.gd:2700`：near dock仍为8m内、非航行的合法泊位；船头(-Z)朝park dot≥0.20，且`plan_route_to`非空。距park≤0.5m时方向无意义而豁免，其余条件不省略。继续调用`_select_landing`原靠妥→上岸链。
- `main.gd:1595`仍`prompt.enabled=false`；沿SEA-UI-R54保留原near图标/进度、状态/灰因，模态隐藏，不恢复底部键位条、教程或世界气泡键位角标；主动打开系统帮助仍允许。

## 验证入口登记

已只读核对`scripts/run_verification.py:54–59`，六项确实已注册，均使用原隔离runner：

| 已注册入口 | 正式脚本 | 本轮ledger登记 |
|---|---|---|
| `boat-unstick` / `visual-boat-unstick` | `godot/tests/test_boat_unstick.gd` | NAV |
| `shift-jog` / `visual-shift-jog` | `godot/tests/test_shift_jog.gd` | MOVE |
| `facing-interaction` / `visual-facing-interaction` | `godot/tests/test_facing_interaction.gd` | MOVE、NAV、INTERACT |

统一专项入口：`python scripts/run_verification.py boat-unstick visual-boat-unstick shift-jog visual-shift-jog facing-interaction visual-facing-interaction`。最终合批同时执行keyboard-control、control-feel、interaction-reach、keyboard-travel、keyboard-farm-loop，结果见下；始终按实际report与日志覆盖范围验收，入口名称不代替证据。

## 最终合批：11项全PASS

报告：`D:/projects/sea-work/verification/20261107-165822-movement-feel-final-9b7646/report.json`。以下11项均exit0、passed=true、completion_marker=true、unexpected_errors空，失败数均0；checks已与各自日志核对。

| 入口 | checks / failures | 覆盖与限制 |
|---|---|---|
| `shift-jog` | 56/0 | 正式输入与控制器、地速/步频/生命周期、含新增3条岸边原地转脸断言。 |
| `visual-shift-jog` | 57/0 | 同一轻跑契约及连续八相位真实图`project/outputs/shift-jog-phases.png`；主任务已用ViewImage目检，确认抬膝、屈肘、微前倾，不再只记生成。 |
| `boat-unstick` | 153459/0 | 脱困单体与帧率一致性。 |
| `visual-boat-unstick` | 153459/0 | **只执行单体**，未进入real_shore；不能计为该批正式岸线截图或岸线集成通过。 |
| `facing-interaction` | 102/0 | 当前真实Main正面候选、Q、菜单及上船仲裁。 |
| `visual-facing-interaction` | 105/0 | 同一朝向契约与真实渲染截图断言。 |
| `keyboard-control` | 30/0 | 原键盘移动/划船/上下船。 |
| `control-feel` | 31/0 | 既有加减速、转向、镜头/船手感回归。 |
| `interaction-reach` | 35/0 | 旧NPC抢焦点问题修复后的正式交互链，不再待签。 |
| `keyboard-travel` | 374/0 | 当前键盘旅行回归。 |
| `keyboard-farm-loop` | 636/0 | 0.55正面契约下逐格面对再Q锁定及完整农场链。 |

实测轻跑地速`2.57582712173462m/s`，符合目标2.576；相位速率`7.35999964149879rad/s`，符合7.36；30/60/120FPS同段位移`0.85319137573242 / 0.83400124311447 / 0.82388764619827m`，按`(max-min)/min`比较差异约3.56%<5%。实际速度比仍以2.3为基准，轻跑稳态约1.12；R27三条新增断言已在上述56/57项内，不另行重复计数。

165822的船visual运行时未设`SEA_BOAT_UNSTICK_SHORE`，当时脚本仅由该环境变量决定是否进入real_shore；日志只有单体153459/0、没有岸线截图输出。因此虽然report标renderer=real且PASS，其覆盖只能记单体。`godot/tests/test_boat_unstick.gd`入口已修为环境变量为1 **或nonheadless** 即调用real_shore；修正后的170723-movement-feel-render-final-950cd8已完成真实岸线与视觉农场双PASS，结果如下，不再pending，也不改写165822历史覆盖范围。

### 农场636项夹具适配，不放宽契约

`godot/tests/test_keyboard_farm_loop.gd:202`的lock先让角色面对目标、等待候选刷新，再发送真实Q；`:564–574`逐格独立lock并记录六格。旧夹具按32次Q循环却在轮转/面向刷新时采样前一帧焦点，导致两格漏记；新0.55正面锥下不能期望背面格无须转身也进入候选。修正的是输入夹具采样与面向前置，不是降低标准：仍逐格要求六格可选、焦点一致、角色位置未被偷移，且Q切目标不触发业务或成功动作；没有通过直接结算种植来凑通过。最终农场636/0，不再pending；170723视觉农场647/0已PASS，独立登记如下，不再待验。

## 已核实的历史报告（保留过程，不覆盖最终结果）

证据根：`D:/projects/sea-work/verification/`。以下均实际读取report，checks来自对应日志，不只看任务描述或exit码。

| 批次 / report | 入口及结果 | 准确结论 |
|---|---|---|
| `20261107-151338-boat-unstick-final-a24421/report.json` | `boat-unstick`：153459 checks/0 failures；exit0，passed=true，completion_marker=true，unexpected_errors空 | 船单体历史PASS，包含矩形两向、圆岸、内角、航区边缘脱困与帧率一致性，不等于主场景所有集成通过。 |
| `20261107-162541-boat-unstick-shore-visual-final-5f9f04/report.json` | 结果键为`boat-unstick`，renderer=real；163769/0，exit0，passed=true，completion_marker=true，unexpected_errors空 | 真实岸线历史PASS；163769包含单体153459，不把两批相加当独立覆盖量。日志有既有资源UID回退等WARNING，不能写成全日志零警告。 |
| `20261107-160834-facing-isolated-final-4b0148/report.json` | `facing-interaction`102/0、`visual-facing-interaction`105/0；两项均exit0、passed=true、完成标记真、unexpected_errors空 | 朝向专项及该批真实渲染PASS；仅限该副本与当时实现，不替代最新边界转脸补丁和当前NPC集成。 |
| 同一160834报告 | `interaction-reach`：exit1、passed=false、completion_marker=false；失败为「菜箱成为E焦点（实际NpcInteractable）」与「E弹出气泡菜单」 | 该批失败保留；NPC装配修复后已由165822的interaction-reach35/0收口，不再待修或待验。 |
| `20261107-155921-shift-jog-latest-5882ff/report.json` | `shift-jog`与`visual-shift-jog`均exit0但passed=false、unexpected_errors非空 | 当时NPC依赖编译/初始化失败，不将该旧批冒充通过；修复后165822轻跑56/0、视觉57/0已PASS，不再作为当前阻塞。 |

### 真实岸线截图核对

162541批日志记录13个PNG：12个时点图（blocked、030、060、turning、090、120、180、240、360、480、600、escaped）及`boat-unstick-sequence.png`拼图，位于该批`project/outputs/`。本轮打开核对的连续图为：

`D:/projects/sea-work/verification/20261107-162541-boat-unstick-shore-visual-final-5f9f04/project/outputs/boat-unstick-sequence.png`

图中可见小船由贴岸逐步改变船头方向，随后离开岸边驶向开阔水面；画面未见底部键位条或操作教程。静态拼图只能佐证可见状态变化，碰撞不穿岸、反馈只一次等由同批数值断言与PASS报告负责。日志`real_shore.escape_distance≈9.223m`，贴岸若干时点实际速度0、manual_drive=true且yaw变化，与本次脱困目标一致。

## 并发集成过程与已完成修复

1. 152158和155921旧报告的`available`/`birthday_slot`类型推断、依赖编译及new/configure/to_dict/changed连锁Nil错误，161514的`NpcActor.configure需要先add_child`，均保留为并发集成过程失败；不能因旧批exit0而掩盖错误，也不能在最终合批已通过后仍称当前阻塞。
2. 160834旧`interaction-reach`曾选到与菜箱重合的NpcInteractable，随之打不开预期菜单。NPC新世界端口已由独立装配修复，当前真实Main的facing102/0、visual105/0和interaction-reach35/0均在165822最终报告PASS，无该旧版本重合故障；没有为凑测试移动NPC/用户手摆，未放宽旧焦点或菜单断言。
3. `godot/src/bootstrap/main.gd:3496–3529`已向npc_service和presenter注入权威`world_clock.query`、正式residence和enabled query；`_on_npc_interaction_requested(npc_id="")`（`:3531`）兼无参enabled查询与有参输入清理，不再重复启动NPC业务。`:3509–3519`接入`owned_modal_query/close/input`，其中`owned_modal_input`在NPC模态时交给presenter，否则转发既有输入端口。旧的单参configure/缺端口记录已被当前装配取代，不再列待修；不据此宣称NPC所有独立功能完整验收。
4. 朝向专项用合法可走、无正面spot竞争的位置隔离0.60上船阈值，不隐藏/移除NPC、不放宽阈值或豁免正式世界竞争；自动接近、松E防连发、hold进度、菜单不穿透与业务只结算一次继续保留。

## 最终渲染与最新装配启动验证（已完成）

报告：`D:/projects/sea-work/verification/20261107-170723-movement-feel-render-final-950cd8/report.json`。两项均PASS、exit0、unexpected_errors空：

| 入口 | checks / failures | 实际覆盖 |
|---|---|---|
| `visual-boat-unstick` | 163769/0 | 真正进入real_shore，生成13PNG（12时点及连续拼图），不是165822的visual单体复写。 |
| `visual-keyboard-farm-loop` | 647/0 | 0.55正面契约下的正式键盘农场真实渲染闭环。 |

主任务已用ViewImage审阅最新170723的`project/outputs/boat-unstick-sequence.png`，可见船头由贴岸转向并划开；同时审阅最新facing plot，确认面向地格时原near图标正确、无操作教程。shift phases亦已目视确认抬膝、屈肘、微前倾。渲染生成与目检均已完成，不再保留render待补；静态图仍只负责可见状态，碰撞/一次性反馈等行为由断言与报告负责。163769包含单体153459，不重复累加成独立覆盖量。

最新启动smoke：`D:/projects/sea-work/verification/20261107-172123-movement-latest-smoke-ed1994/report.json`的`facing-interaction`102/0 PASS，确认NPC/dive最新装配下真实Main可启动并通过朝向专项；不外推为潜水完整玩法或五项兼容已通过。

## 兼容回归：断言结果与runner结论分开

报告：`D:/projects/sea-work/verification/20261107-171743-movement-compat-final-7104b0/report.json`。当时潜水正在并发重构，本地WorldEnvironment缺失；六项中**只有actor-presentation为runner PASS**：

| 兼容入口 | checks / failures | runner结论 |
|---|---|---|
| `actor-presentation` | 31/0 | PASS |
| `click` | 32/3 | FAIL，存在3条断言失败，不能只归为日志错误。 |
| `board-click` | 12/0 | FAIL；局部断言0失败不能覆盖集成错误。 |
| `dock-seed` | 22/0 | FAIL；局部断言0失败不能覆盖集成错误。 |
| `character-space-save` | 10/0 | FAIL；局部断言0失败不能覆盖集成错误。 |
| `boat-water-contact` | 41/0 | FAIL；局部断言0失败不能覆盖集成错误。 |

上述失败是该隔离批次的真实结论，不因165822全PASS、170723渲染双PASS或172123启动smoke通过而抹掉；也不拿board/dock/save/water的0失败断言冒充runner PASS。主任务不修整套潜水；新版Main接入DiveSession后的最终兼容批 `D:/projects/sea-work/verification/20261107-172517-movement-current-compatible-8e5f98/report.json` 已完成：`board-click`12/0、`dock-seed`22/0、`character-space-save`10/0、`boat-water-contact`41/0、`shift-jog`56/0，五项均runner PASS、exit0、完成标记真、unexpected_errors空。旧失败保留为过程；鼠标`click`中的三条潜水测试本轮未重新签署通过，不拿海面手感验收代签并发潜水重构。

## 全局门禁与交付边界

主任务17:16的全局检查为sync20 issues、普通check21 issues；17:35最终重查降为**sync19 issues、普通check20 issues**，统计为43 features / 930 assets / 1255 runtime。dive_map_hud缺路径已由并发任务补齐；仍有shop unknown verification、鱼source漂移、runtime的main/actor/character/场景/物品/作物等漂移，以及content ID drift。**全局未绿**，未强刷registry/hash掩盖并发差异。主任务报告placed positions四项PASS、0 warnings及本轮`git diff --check`通过。执行过sync不等于检查通过，定向手感报告也不覆盖这些全局问题。

GDD已由主任务追加手感摘要；本次最终回填只涉及原七文件，不改生产、registry/hash、NPC摆位或用户手摆TSCN，不动本轮外ID。触屏/手柄、低端性能、所有地图组合与整套潜水未在本轮完整验收，MOVE/NAV/INTERACT继续`partial`。

## 本轮文档只读自检

指定七文件的`git diff --check`及定向只读自检通过；三个ledger登记头JSON可解析，状态均仍为`partial`，verification无重复，本轮5个条款在各自spec中各出现一条并由ledger承接，六个入口均能在当前runner找到；开发记录无尾随空白。165822报告的11项exit0/PASS/完成标记及unexpected_errors空已经逐项复核，三份spec与ledger均指向该最终报告。初次扩大到所有历史ID的唯一性断言遇到nav已有两个R09（航线水纹与参考小船）的历史重复；既有ID未重编号，定向本轮ID检查通过。该定向检查不代表全局feature contracts通过；主任务最终17:35重查sync仍19 issues、普通check20，真实门禁状态如上，不再表述为「本轮未运行sync」。游戏验收分别以165822合批、170723渲染、172123最新启动smoke及171743兼容过程报告为准；172517的movement-current-compatible五项已逐项核对PASS，兼容结果按上文追加收口。本次末轮仅依据主任务已完成的报告和画面审阅回填，不新增运行验证。
