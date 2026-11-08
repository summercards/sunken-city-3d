# 2026-11-08 统一潜水 3C：两域控制器与十图共用运行时

[主文档中控](../../GDD_V1.0.md#sea-dive) · [SEA-DIVE 设计](../features/dive/spec.md) · [独立账本](../features/dive/ledger.md) · [模块契约](../architecture/module_contracts.md)

## 1. 本批范围与稳定 ID

本批仅追加 GDD_V1.0.md、docs/features/dive/spec.md、docs/features/dive/ledger.md、docs/architecture/module_contracts.md，并新建本记录；不改代码、场景、资产、登记头、GDD 状态摘要或其它 feature 文档，不整文件重写。用户列举实际为上述 5 个文件路径，不凭“6类”另造文件。既有并行改动原样保留，不将工作区全量 diff 当成本批成果。

已先读 AGENTS.md、GDD 功能导航及 SEA-DIVE 前置 WORLD/INVENTORY/SAVE/BOOT、dive spec/ledger、模块契约和实际控制器。R27/R28 已被高楼布局/生态排除占用，历史不改，本次续增 **SEA-DIVE-R29–R38**，spec/ledger 逐条对应，功能仍 partial。

## 2. 最终所有权与生命周期

- **海面/陆地一套独立 ActorController；潜水一套独立 Shared DiveRuntimeController。** 家园 + 旧九图共用 surface/enter/swim/exit，不是海面/家园/旧图三套状态机，不为每图复制控制逻辑。实际控制器为 `godot/src/diving/dive_runtime_controller.gd`。
- Map 只提供内容、入口、位置、碰撞、route、camera_clip、env、explore；控制器解释潜水输入、推进阶段/运动意图/潜水耗氧、写第三人称相机和独立角色表现。Map 的物理执行回传实际位移，不另推进输入/氧气/镜头。
- Map 端口：`dive_begin/entry_tick/exit_begin/exit_tick/end`、`dive_position/set_position/move/water_level`、`dive_route/cancel_content/content_tick/camera_clip/zone_label`。地图的入出水执行只返回完成状态，不另建状态循环。
- `phase/phase_machine` 保持旧测试接口、转发控制器 machine；无控制器的兼容夹具不能成为生产第二状态机。旧 enter/surface/finish_exit/swim/camera/diver_pose actions 与旧状态驱动不得继续运行；search_action 可留作 explore 内容搜索，不能接管 3C。
- DiveSession 仍负责 preflight/setup 事务、失败回滚、同 Main 身份挂起/恢复及原船人姿态/模式/相机/环境，不能 free/rebuild/read-save 冒充恢复；active/switching 拒绝直接写盘。
- 根 v4 `dive:{found:int[],opened:int[]}` 保持，固定 ID 不重编、未知 ID 与未加载图进度保留、from_dict 全量替换；give_rewards 原子提交，满包不部分发奖/不标开启，重复不开第二份奖励。
- 同一 DiveAir 由稳定 Session 持有，潜水控制器只在潜水推进耗氧，Session 只在海面推进恢复/cooldown；Map 只引用同对象，切图/卸载不重置共享 cooldown，不复制 air 状态。

## 3. 统一操控、镜头、角色与 HUD

| 项目 | 最终口径 |
|---|---|
| InputMap | dive_left/right/forward/back = A/D/W/S + 对应 arrow；dive_down = Q/Ctrl，dive_up = E/Space，dive_sprint = Shift |
| 速度/响应 | 巡航4.2m/s、加速7m/s；ACCEL_TAU0.22s、BRAKE_TAU0.16s、反向tau0.13s，是指数时间常数，不把它们写成精确到速/停止时长 |
| 鼠标/自动游 | 右键仅环视，WASD无需右键；左键release位移≤8px且按住期间未超阈值才短点击自动游，拖拽不触发；手动输入取消路线，无路拒绝、受阻停止，不穿墙直游 |
| 距离/视野 | 滚轮4..13m，默认7.5m；FOV72°，加速渐变78°；pitch[-1.1,1.15]弧度、yaw平滑tau0.07s |
| 跟随/防墙 | 镜头直接继承主体位移，速度前视0.10s；camera_clip半径0.32m，收回立即、离墙缓出，插值后再次最终clip；Map只做空间裁剪，不持镜头状态 |
| Character | 模型/骨骼复用、潜水实例独立，不挪用海面实例；碰撞后实际速度驱动float/cruise/sprint，垂直速度驱动升降pitch、转向驱动turnbank，撞墙不按期望速度假游 |
| hat/mask | 入水保存hat可见性，隐藏hat/显示mask；退出还原帽子原可见性、收起mask；模型表现不写位移或奖励；海面idle/walk/rowing动画不改 |
| HUD | 十图统一dive_map_hud海底墨绿半透明板+奶油按钮；氧气bar/百分比、深度、地图/游动状态、键位hint、头灯/消息、30%/15%告警；无宝箱不展示虚假计数 |
| Esc | 暂停菜单支持继续或上浮，暂停不耗氧；HUD只读状态、经Session发命令，不直写phase/air/位置 |

## 4. 场景保护与源码核对边界

家园现行水面51.12m、可游85m、viewer_min_y=-33.88保持；用户手摆layout、Base2/SolarCabinBase2、当前40高楼均不动。历史388实例与历史758代理等只属于当时快照，不作为当前固定数量断言；当前数量/变换以TSCN实测为准，不回退用户摆位来迁就旧夹具。真正独立Terrain3D海床高度数据仍pending，不以本地包装或可游边界冒签新海床。

本分支已读并核对：

- `godot/src/diving/dive_runtime_controller.gd`：共用machine、dive_动作、实际位移回传、相机最终clip、Character独立实例与卸载清理。
- `godot/src/diving/underwater_world.gd`、`sunroom_region.gd`：控制器装配、phase转发及dive_*适配；旧states/swim.gd仍保留为历史代码文件，不因文件存在允许生产驱动。
- `godot/src/diving/dive_session.gd`：事务切图、air注入、同Main恢复、进度全量替换/合并及统一HUD装配。
- `godot/src/player/character.gd`、`animation/swimming_action.gd`：set_swim_motion、实际速度表现、升降pitch/turnbank及hat/mask切换。
- `godot/src/diving/dive_map_hud.gd`：状态只读、氧气bar、墨绿板/奶油按钮与Esc暂停。

上述为源码核对，不是本分支运行通过证明。旧搜索动作属于内容执行例外，不得据此复活旧移动/镜头/耗氧actions；真实双tick、生命周期泄漏和十图一致性由主线程专项验证。

<a id="unified-dive-3c-acceptance"></a>
## 5. 主线程最终验收结果（PENDING，唯一运行签署回填位）

### 5.1 过程结果与必须保留的失败历史

| 项目 | 本次收到的过程结果 | 当前结论 |
|---|---|---|
| behaviour | [403 或 396]/0；实际入口名、批次与精确数待主线程核对 | PENDING，不择一当最终数，不据此预签 |
| 初批 dive-maps | 326/0 | 断言零失败，但resource leak导致FAIL，修复中 |
| 初批 click | 39/0 | 同批resource leak导致FAIL，不能写通过 |
| 初批 framework-integration | 52/0 | 同批resource leak导致FAIL，不能借历史同数字PASS |
| curved collision | **3448/42** | **FAIL历史必须保留**；未有本次新复测不得宣称通过 |

### 5.2 最终精确结果回填（主线程填写）

不覆盖5.1旧FAIL；新结果须写实际已注册入口/命令及报告，不能编造测试名、计数、路径或把0断言失败等同整体PASS。

| 回填 ID | 验收内容 | 最终结果 / 证据 |
|---|---|---|
| UD3C-VERIFY-01 | behaviour实际入口、精确checks/failures、工作树版本与report | **PENDING（主线程精确回填403或396及最终结果）** |
| UD3C-VERIFY-02 | 资源泄漏修复后dive-maps/click/framework-integration重跑；分别列exit/unexpected/leak与批次 | **PENDING** |
| UD3C-VERIFY-03 | curved collision修复与新复测；保留3448/42旧报告并另列新报告 | **PENDING，不签通过** |
| UD3C-VERIFY-04 | 家园+旧九图同控制器/无旧actions双tick、共享air/cooldown、Esc暂停与同Main身份恢复 | **PENDING** |
| UD3C-VERIFY-05 | v4/未知ID/全量恢复、奖励原子、busy写盘拒绝与失败回滚回归 | **PENDING** |
| UD3C-VERIFY-06 | 真实输入/镜头防墙与角色float-cruise-sprint、pitch/turnbank、hat/mask、HUD；逐图截图审阅与海面动画隔离 | **PENDING** |
| UD3C-VERIFY-07 | 手摆layout/Base2/40高楼/水位深度保护实测；独立海床pending不冒签 | **PENDING** |
| UD3C-VERIFY-08 | 主线程最终结论、命令、HEAD+working_tree、报告/日志、exit/unexpected/leak、未执行项与签署人 | **PENDING，当前不签运行PASS** |

设备/低端GPU/连续性能、全路线人工体验及用户终审未签；本批未执行Godot/真实渲染，不从历史1270/0、1241/0或更早PASS外推当前统一3C已通过。

<a id="unified-dive-3c-doc-checks"></a>
## 6. 文档检查与全局门禁

- DOC-01：既有四文件末尾追加、原文前缀字节不变、GDD摘要不变、R29–R38逐条承接、链接和换行检查：**PENDING（本分支检查后追加结果）**。
- DOC-02：只读 `python scripts/check_feature_contracts.py`：**PENDING（本分支记录实际exit及问题，不修范围外漂移）**。
- DOC-03：`python scripts/check_feature_contracts.py --sync`：**本分支未执行**，因为脚本可重写GDD并写入范围外 `docs/generated/feature_index.json`，与用户本批只追加/限文件要求冲突；留主线程最终获准范围执行并回填，不能称已同步。
- 换行基线：GDD现有LF；dive/spec、dive/ledger及module_contracts均CRLF。既有文件保持各自格式、不全文件换行归一；本新记录使用CRLF。

### 6.1 本分支文档检查实录

- DOC-01：既有四文件追加前的字节长度分别为155081/24003/22845/48273；按此前缀长度重新计算SHA256，四份原文前缀均未变，包含GDD摘要/登记头/历史章节。R29–R38在spec/ledger各10条且集合一致，新增回链目标存在；既有CRLF文件无裸LF，GDD保持原LF。新记录写入工具最初归一为LF，Edit换行替换亦未持久保留CRLF，最终仅对这个新文件做字节级换行修正；收尾复核CRLF，不改既有前缀。
- DOC-02：已执行 `python scripts/check_feature_contracts.py`，**exit1 / FAIL，71 issues**；汇总为43 features、987 source assets、1422 runtime hashes。问题包含source hash drift、source index不一致、runtime hash drift和derived feature index stale；输出未报SEA-DIVE条款缺失/多余或新增回链缺失。未修范围外哈希/索引，不据此签全工程通过。完整工具输出留本会话检查记录，未另造报告文件。
- `git diff --check -- GDD_V1.0.md docs/features/dive/spec.md docs/features/dive/ledger.md docs/architecture/module_contracts.md docs/development/2026-11-08_unified_dive_3c.md`：exit0，无空白错误；Git提示GDD的LF未来可能由Git转换为CRLF，仅记录提示，本批未转换该文件。
- DOC-03仍未执行sync，5.2的UD3C-VERIFY-01–08仍由主线程填写，不能用文档检查替代Godot实测。上方DOC-01/02初填PENDING保留为过程历史，当前文档检查以本节及收尾复核为准。

## 7. 主线程最终验收回填

最终报告：`D:/projects/sea-work/verification/20261108-202515-dive-unified-final-edbd96/report.json`。

| 验收入口 | 结果 |
|---|---:|
| dive-control | 396/0 |
| dive-maps | 326/0 |
| visual-dive-maps | 338/0，real renderer |
| sunroom-underwater | 83/0 |
| sunroom-collision | 3313/0 |
| click | 39/0 |
| framework-integration | 52/0 |
| minimum-loop | 112/0 |
| modules | 31/0 |
| keyboard-control | 30/0 |
| control-feel | 31/0 |
| character-motor | 42/0 |

12 个入口全部 exit0/PASS、无 unexpected。`dive-control` 的 396 项覆盖 Shared DiveRuntimeController 的四阶段、九旧 source + 家园、InputMap/右键环视/短点击自动游、加速刹停反向、FOV/zoom/pitch/roll、防墙、氧气单实例、实际速度动画、装备生命周期、HUD 与返回；真实 `visual-dive-maps` 通过。`sunroom-collision` 已按连续实际碰撞轨迹复验 3313/0；旧 `20261108-195027...` 的 curved collision 3448/42 仍保留为历史失败，不覆盖、不抹除。

真实产物：同一 run_dir 下 `project/outputs/dive-control-report.json`、`sunroom-collision-report.json`、`sunroom-underwater-report.json`，以及 `dive-map-home-seabed.png`、九张旧图运行图和返回海面图。截图复核确认：角色/潜水装备可见，第三人称广角 FOV72，HUD 已统一为墨绿水下板与奶油按钮；家园初始指定的未进入街景的基座/空腔取景已在代码中改为拒绝空腔保底点，未把坏取景当成功。

最终边界：低端 GPU、连续运行性能、全路线人工探索、用户美术终审、独立 Terrain3D 海床高度图仍 pending；统一 3C 专项通过不等于全工程发布签署。

## 8. 最后修正后签署（当前有效结果，覆盖第5节待填和第7节中间批次）

第1–6节的“本分支”指文档委派阶段，第7节为中间回归；本节是完整代码重构与最后入水点修正后的主线程运行签署，不将前文PENDING或历史FAIL删除。当前最终报告：`D:/projects/sea-work/verification/20261108-205037-dive-unified-signed-2f2292/report.json`。HEAD为`842e2e07ed1ee78f2831a42c2ad29f0bc694e145`加该报告记录的working_tree，非干净提交快照。

| 验收入口 | checks / failures | 运行结果 |
|---|---:|---|
| dive-control | 396 / 0 | headless，exit0/PASS |
| visual-dive-control | 403 / 0 | Vulkan Forward+ / RTX 4060 Ti，exit0/PASS |
| dive-maps | 326 / 0 | exit0/PASS |
| visual-dive-maps | 338 / 0 | 真实渲染，exit0/PASS |
| sunroom-underwater | 83 / 0 | exit0/PASS |
| sunroom-collision | 3313 / 0 | exit0/PASS |
| click | 39 / 0 | exit0/PASS |
| framework-integration | 52 / 0 | exit0/PASS |
| minimum-loop | 112 / 0 | exit0/PASS |
| modules | 31 / 0 | exit0/PASS |
| keyboard-control | 30 / 0 | exit0/PASS |
| control-feel | 31 / 0 | exit0/PASS |
| character-motor | 42 / 0 | exit0/PASS |
| save-seed | 无checks计数 | 前置种档，exit0/PASS |

合计13个计数入口 **5196 checks / 0 failures**；连同save-seed共14个报告条目，全部exit0、expected_errors=[]、unexpected_errors=[]。396与403不是待定二选一：前者为无显示操控测试，后者增加了真实渲染检查。未借旧1270/1241等结果。

实际命令：`python scripts/run_verification.py dive-control dive-maps sunroom-underwater sunroom-collision click framework-integration minimum-loop modules keyboard-control control-feel character-motor visual-dive-maps visual-dive-control --label dive-unified-signed --timeout 300`。

| 回填ID | 本次签署 |
|---|---|
| UD3C-VERIFY-01 | dive-control396/0、visual-dive-control403/0；当前14份核心源码/测试/总场景逐字节与隔离快照一致 |
| UD3C-VERIFY-02 | dive-maps/click/framework-integration分别326/0、39/0、52/0；卸载循环引用已拆除，本批unexpected为空 |
| UD3C-VERIFY-03 | sunroom-collision3313/0；保留原CoralCluster11样本与3448/42历史FAIL，不通过筛掉样本“修复”；实际轨迹逐段独立cast，曲面合法切向滑移与平面3cm接触判据分离 |
| UD3C-VERIFY-04 | 十图同脚本、同四阶段；InputMap无需右键使能、单次耗氧、共享air/cooldown、Esc与同Main恢复已覆盖 |
| UD3C-VERIFY-05 | dive-maps/framework-integration/minimum-loop/save-seed通过；v4、未知ID、全量恢复、满包原子奖励及切换回滚覆盖仍以对应测试实际断言为限，不扩展成所有存档分支穷举 |
| UD3C-VERIFY-06 | 两个真实渲染入口通过；家园街区、旧图、角色装备与统一HUD已审阅；角色+Z对真实速度，悬浮/巡航/冲刺及升降/转向混合验证；全路线人工体验未签 |
| UD3C-VERIFY-07 | 家园水面51.12/85m/viewer_min-33.88及当前手摆场景保持；本次不改变Main/城市布局/Base2/40栋高楼；独立高度图仍pending |
| UD3C-VERIFY-08 | 主线程签署本次统一3C功能专项通过；日志/命令/工作树均见本报告，低端/连续性能与用户终审仍未签 |

### 8.1 真实手感、入口修正与已知边界

- 实测巡航4.1986m/s、冲刺6.9926m/s，冲刺松键刹停约1.0563m；默认广角72°、冲刺78°，转向/刹停无持续漂移，角色面向与速度方向偏差约0.26°。以上为固定步测试工况，不作为所有地形的固定距离保证。
- 家园实际入水点为`(7,-10.61256,-39)`，当前街面视野水深约61.73m；修正旧保底点落在基座封闭内腔的问题。搜索以玩家落水XZ为中心，从真实街面支撑与净空中选点，可能水平避让；不承诺落点XZ绝对不变，不通过搬动用户建筑求通过。
- 当前源码、HUD、Session、两类Map、碰撞/视觉适配、角色/动作、4份测试与总场景共14份文件，均与本批工程副本逐字节匹配。没有以测试启动后继续修改的工作树冒充本批证据。
- `sunroom_region.tscn`保留一条旧脚本UID失效警告，Godot按稳定文本路径回退并加载成功；本批无unexpected，不将非阻断警告写成完全无警告。
- 验证工具保留隔离用户目录，不再尝试删除AppData中的临时目录；不碰真实玩家存档。输出/预览统一放工程外sea-work。
- 低端GPU/连续性能、所有路线人工探索、用户美术终审及独立Terrain3D高度图仍pending。全局资源哈希门禁另记，不批量重签未知资产。

### 8.2 最后全局检查与交付状态

- 已按工程约定执行`python -X utf8 scripts/check_feature_contracts.py --sync`：exit1，72 issues；43 features / 987 source assets / 1422 runtime resource hashes。脚本仅在无issues时写入GDD/派生索引，本次被源/运行资源哈希漂移及source index不一致阻断，故不能说已成功同步。
- 随后不带参数复核：exit1，73 issues（上述72项加derived feature index stale）。未报SEA-DIVE条款遗漏、多余或登记测试入口未知。除既有全工程漂移外也包含本轮潜水文件的真实改动；不批量更新哈希隐藏其它会话或用户手改资产，不将全局FAIL混写成本次运行FAIL。
- 本轮代码/文档`git diff --check` exit0。字节校验：GDD保持LF，dive/spec、ledger、module_contracts及本记录保持CRLF，无CRCRLF；登记头仍在原位，R29–R38各自有当前签署行。
- 已审阅十张生产潜水图、返回海面图及两张操控取景，共13张；角色/背部装备可见、无明显镜头穿墙、空白、HUD重叠或截断，返回后切回海面UI。两张独立control夹具未装生产HUD属夹具范围，HUD验收取生产十图；静帧不当作完整动画/手感证明，动画由行为测试补充。
- 交付位于`D:/projects/sea-work/outputs/unified-dive-3c-20261108/`：`index.html`为完成摘要/键位/证据/边界；`verification-summary.json`为精确计数与限制；`report.json`为最终原报告副本；`implementation-notes.md`为本记录副本。实际运行代码已写入原工程，交付页不是替代实现。
- 最终结论：用户要求的两域独立状态机与十图统一第三人称潜水3C完成，已自主专项验收；设计文档和逐条账本已更新。全局资源登记门禁/派生索引、低端/连续性能/人工全路线/用户终审及独立海床不冒签。
