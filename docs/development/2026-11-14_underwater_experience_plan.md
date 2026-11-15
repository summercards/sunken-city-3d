# 2026-11-14 水下体验规划记录

[3–5分钟潜水主方案](../features/dive/underwater_experience_plan.md) · [SEA-DIVE spec](../features/dive/spec.md) · [SEA-DIVE ledger](../features/dive/ledger.md) · [SEA-CAMERA](../features/camera/spec.md#2026-11-14-水下体验镜头与轻潜水镜设计规划planned) · [SEA-MOVE](../features/move/spec.md#2026-11-14-潜水角色动画3c承接设计规划planned) · [SEA-SAVE](../features/save/spec.md#2026-11-14-潜水远征照片与采集存读设计规划planned)

## 1. 本轮交付范围

本记录开头对应本轮**初始设计阶段**：当时只做文档设计交付，更新GDD、主方案、四功能spec/ledger和本记录；不改代码、场景/TSCN、资产、root v4或用户存档。随后用户要求按复审结果优化，代码与测试变更已在第9、10节另行登记。初始阶段已读 GDD 导航、SEA-DIVE 最新 R51、SEA-CAMERA 最新 R17、SEA-MOVE 最新 R31、SEA-SAVE 最新 R19/B2 条款，并在文末追加：

- CAMERA：R18–R19，潜水候选镜头与轻潜水镜。
- MOVE：R32，独立潜水 Character 与实际碰撞速度驱动的动画3C。
- SAVE：R20–R21，潜水远征、照片、奖励/耗尽/日配额事务。
- DIVE：R52–R75，3–5分钟潜水、电影化进出水、打捞、拍照、抄网捕鱼和跨功能承接。

所有新增条款均为 `design/planned`，运行状态 `pending`。不将历史PASS作为新条款证据；本轮未运行Godot或玩法runner，不新增假测试入口。委派写作阶段未跑checker/sync，主线程复审阶段实际执行文档检查及全局sync/check，结果与限制统一见第8节，不能再沿用“本轮不跑checker”的旧过程描述。

## 2. 现有框架承接

- 潜水运行时继续使用 `DiveSession + Shared DiveRuntimeController + Map 适配器`。Map 可提供既有 `dive-control`/`dive-transition` 链路所需的内容、route、碰撞、`camera_clip`、环境与 explore 端口，但不拥有第二套输入、Air、镜头、动画或奖励状态机。
- 电影化进出水继续使用既有无文字圆幕、真实全黑 `frame_post_draw`、prepared enter、uncover、`release_entry`、switching/transition_frozen 与同一 Main 恢复事务。不能用新 Splash FSM 或读档重建来绕过既有链路。
- 相机候选集中登记在 SEA-CAMERA-R18/R19；海面 OrbitCam 与 R16 不改。潜水镜头、姿态和电影段由 Shared DiveRuntimeController 唯一拥有。
- 角色候选集中登记在 SEA-MOVE-R32；独立潜水 Character 只消费碰撞后的实际速度，脚蹼为待制作装备，不改变根位置、奖励、Air、陆地2.2步频或海面角色实例。
- 存档候选集中登记在 SEA-SAVE-R20/R21；root v4 与 `dive:{found:int[],opened:int[]}` 不改，`dive.expedition` 可选、唯一 owner 为 DiveSession，照片只存稳定记录和受控相对引用。

## 3. 体验闭环

参考完整体验窗口为 3–5 分钟，但不强制倒计时：

1. 进入水下：圆幕遮黑、加载与碰撞准备、展开后可见入水，直到swim才释放过场/input/Air门禁，active期间存档禁写仍保持。
2. 探索观察：第三人称水下移动，目标可打捞、拍照或捕鱼；手动观察不被目标抢镜。
3. 结算活动：打捞和捕鱼使用稳定 ID、一次性 token、Inventory 唯一写者和 busy 事务；拍照先记观察，异步图片成功后才补引用。
4. 电影出水：同一 Main、角色、船、相机、环境、HUD 和处理模式恢复；不重建、不重读存档、不遗留 runtime。
5. 持久化：返回并全 busy 解锁后最多请求一次既有 `SaveGame.write`；写失败不重发、不撤销已得内存资源，等待用户按既有保存意愿重试。

## 4. 设计条款索引

| 功能 | 新增条款 | 规划重点 |
|---|---|---|
| SEA-DIVE | R52–R75 | 短潜水节奏、电影进出水、打捞/拍照/捕鱼、所有权、事务、日配额、照片与验收矩阵 |
| SEA-CAMERA | R18–R19 | 9.5m/5..16m、vFOV74/80、KEEP_HEIGHT、0.32m双clip、轻潜水镜和共享投影逆映射 |
| SEA-MOVE | R32 | 独立潜水 Character、实际速度动画、上身/腿悬停、相位连续、5体型与30/60/120FPS |
| SEA-SAVE | R20–R21 | 可选 expedition、严格迁移/校验、07:00 epoch、照片记录、奖励/耗尽/日配额 busy 事务 |

## 5. 预计实施与验收（未执行）

当前只规划，不创建测试入口。未来应扩展既有 `dive-control`、`visual-dive-control`、`dive-transition`、`visual-dive-transition`、`underwater-experience`、`visual-underwater-experience`、`camera` 及相关存档/事务入口，并按真实运行结果回填报告。验收至少包含：

- 3–5分钟连续体验、提前出水、重入不刷新、跨 07:00 日配额。
- 打捞/捕鱼的满包、重复、取消、过期 token、事务失败和奖励唯一性。
- 拍照成功、异步失败、缺图、相对路径遍历、零强度投影点击等价。
- 入水/出水真实连续录像、近墙双clip、碰撞挡停无假踢蹼/无冲刺FOV。
- 5体型、30/60/120FPS，以及 16:9、16:10、21:9、Compatibility 的真实渲染。
- active/switching 禁止 capture/write/restore、坏档/未来版本保护、写盘失败不重复发奖。

headless 逻辑断言不能代替真实渲染、输入、图片异步和跨文件边界验收；任何最终 PASS 必须有本轮实际命令、报告、计数、退出码、unexpected/leak 与人工审阅记录。

## 6. 当前状态与限制

- 新增条款：SEA-DIVE-R52–R75、SEA-CAMERA-R18/R19、SEA-MOVE-R32、SEA-SAVE-R20/R21。
- 状态：全部 `planned` / `pending`；不升级任何 feature ledger 登记头的 `partial`。
- 本轮前期规划阶段未运行Godot/玩法runner；复审后按P0实施计划已改潜水代码与相关测试，未改场景/TSCN、资产或存档；已更新GDD。最终实现与验证结果见第9节，不将完整设计交付混写为全部游戏优化已经落地。
- 既有 `dive-control`、`dive-transition`、存档 B2 及历史视觉结果只作为框架背景，不替代本轮新增条款的证据。

## 7. 用户要求重新审视后的补齐与纠偏

前期委派任务完成不代表整体交付完成；原进度中过早标记的“更新设计文档并校验”已重新打开。复审补齐主方案第7–16节，明确以下首版决策：

1. 浅/中/深三路线分别240/225/210秒，swim主动返程计时且耗气，退出表演不计时。新候选A气量算例消耗85.276/82.744/81.835、剩14.724/17.256/18.165点；仅数学算例，非引擎路线实测。灯不耗气、首版无水下换气，救援保留6秒冷却。
2. 5个家园稳定打捞候选、2个捕鱼候选、6个摄影观察候选；新增全图日配额wood2/rope1/parts1/glass1/pearl1/fish2，以WorldClock07:00晨次刷新，旧23箱奖励不动。取消单潜“2箱/2鱼/3照片”硬上限，照片不发钱。
3. 补齐材料真实用途与售价、打捞距离和取消、抄网观察与惊扰、摄影可见度和构图指标、背包整份容量判断；新增资源全配额按当前售价52瓶盖，旧23箱含直接货币总价值665瓶盖，均为对照价值而非额外发币。
4. 分离save busy和content busy：active时禁止存读，不禁止稳定swim内存领奖。Inventory当前内部add_all事务不代表跨Session原子；实现需增加延后广播/回滚端口，不以文档假称已经实现。
5. 纠正exit冻结会阻止表现tick的问题：Session授权同Controller的exit白名单，输入/奖励/Air继续锁；浅层安全末段正常上浮，深处或救援短表现+遮黑压缩返程，不明场穿楼、不长时间锁操作。
6. 补齐现7.5m/72–78°与候选9.5m/vFOV74–80°区分、精细移动1.4m/s、动作层/IK/踢蹼滑行、5体型和多FPS验收、镜片投影/点击、舒适档和性能增量门槛。
7. 照片图像保留环境雾/光线，排除HUD/圆幕；构图记录不存渲染资源。图片迟到只挂有效Session记录，等待下次普通保存，不为每图强写；缺整个expedition迁移空与已有version1字段损坏拒绝严格分开。

本轮交付文件：`GDD_V1.0.md`；`docs/features/{dive,camera,move,save}/{spec,ledger}.md`共8份；新建 `docs/features/dive/underwater_experience_plan.md` 与本开发记录，共11份文档。新增29条对应关系（24+2+1+2），功能登记头和历史签署保持不变。并行工坊4份代码变动不属于本轮，没有覆盖。

## 8. 本轮静态检查与全局门禁

复审开始前在当前工作区执行只读 `python3 scripts/check_feature_contracts.py`，输出保存在工程外 `../sea-work/underwater-plan-before.log`：46 features、1073 source assets、1527 runtime resource hashes、**540 issues**。这不是干净HEAD基线，而是本轮重新审视开始时的工作区基线（含前期文档与并行变动）。四个相关FeatureID均无契约配对错误。

本轮定向检查先发现MOVE/SAVE账本两条本次新链接的标题锚点多一个连字符，已修正；29条新增spec/ledger均已配对。临时定向脚本曾因假定“登记头”后立即出现JSON而报错，按实际文件结构修正读取方式后重新完整执行；没有修改检查器或登记头来让检查通过。

### 最终实际结果

| 检查 | 实际结果 | 证据与含义 |
|---|---|---|
| 新增条款与账本 | **29/29逐条对应，0问题** | DIVE24、CAMERA2、MOVE1、SAVE2；新增实施状态全部planned |
| 历史与登记头 | **8/8历史前缀保留，4/4登记头未变** | 与HEAD按LF比较；未覆写历史、未升级feature状态 |
| 本轮本地链接及标题锚点 | **58项、0问题** | 覆盖新方案、开发记录及9份现有文档的新增部分，不代表历史全库链接无错 |
| 差异格式 | **定向与全工作区diff-check exit0** | 不等于并行工坊代码已通过运行测试 |
| `python3 scripts/check_feature_contracts.py --sync` | **exit1，539 issues** | 工程外日志 `../sea-work/underwater-plan-sync.log`；失败时脚本不写主文档摘要/派生索引 |
| `python3 scripts/check_feature_contracts.py` | **exit1，540 issues** | 工程外日志 `../sea-work/underwater-plan-check.log`；46功能、1073源资产、1527运行哈希 |
| 复审前后问题集合对照 | **新增0，减少0** | 正式check的全部输出行与 `underwater-plan-before.log` 一致，不是只比较计数 |

540项构成：运行资源哈希漂移472、源资产哈希漂移14、历史断链51；另3项为SEA-ASSET条款/账本配对、`godot/src/plant_authoring/store.gd`引用的`scenes/workshop_plants`缺失、派生feature index过期。四个本轮功能无FeatureID契约配对错误。没有创建空目录、伪造历史报告、批量重算hash或改资产许可来消红；因此**全局门禁仍阻塞，不能签全工程通过**。

设计与本轮定向文档核对已完成；P0首轮代码与专项验证已完成，P1活动事务/存档、P2脚蹼与工具动作/镜片视听、P3完整路线和宽高比矩阵仍未完成。未提交或推送。全局契约检查仍按第8节阻塞。

## 9. P0实现与真实验证收口

### 9.1 已落地的代码范围

本轮按审视结果修改了：

- `godot/src/diving/dive_air.gd`：候选A耗气模型 `100点 + 深度归一化 + 悬停/巡航/冲刺倍率`；灯不额外耗气；工具动作留显式可选成本参数；正式潜水关闭水下换气，回到surface状态再恢复兼容换气。
- `godot/src/diving/dive_runtime_controller.gd`：潜水相机默认9.5m、5–16m、竖直FOV74°/冲刺80°、显式`Camera3D.KEEP_HEIGHT`；保留4.2/7m实际游速基线；新增Session授权的exit表现tick白名单，未解除输入、奖励或Air门禁。
- `godot/src/diving/dive_session.gd`：冻结保存/奖励/输入时，允许同一Controller完成安全exit表现；再进入真实黑帧、卸载和同Main恢复。
- `godot/src/diving/underwater_world.gd`、`sunroom_region.gd`：浅层仅沿碰撞可达短段播放1.5秒上浮；深处、堵塞或不可达时播放0.45秒短表现后由圆幕压缩返程，取消明场直接Y插值穿过海底结构。
- 同步旧P0验证断言：`test_dive_control.gd`、`test_dive_transition.gd`、`test_dive_maps.gd`、`test_underwater_experience.gd`、`integration/selftest.gd`。selftest直接从正式工程启动仍受既有`Zones`前置编译错误阻塞，不能用外层exit0冒充通过。

### 9.2 本轮真实证据

| 入口 | 结果 | 证据 |
|---|---|---|
| `dive-control` | PASS，406 checks / 0 failures，headless | `sea-work/verification/20261114-165857-dive-p0-air-camera-exit-ef80b0` |
| `dive-transition` | PASS / exit0，headless | 同上 |
| `dive-maps` | PASS / exit0，headless | 同上 |
| `visual-dive-control` | PASS / exit0，Forward+ 1280×800 / 60FPS | `sea-work/verification/20261114-170124-dive-p0-visual-air-camera-exit-15ee28` |
| `visual-dive-transition` | PASS / exit0，Forward+ 1280×800 / 60FPS | 同上 |
| `underwater-experience` | PASS / exit0，headless | `sea-work/verification/20261114-170450-dive-p0-underwater-experience-f412f8` |
| `visual-underwater-experience` | PASS / exit0，修正旧72°断言后真实渲染 | `sea-work/verification/20261114-171701-dive-p0-visual-underwater-fixed-8ab139` |

真实渲染入口确实生成了Forward+画面，未把headless当截图证据。P0没有新增验证入口，也没有覆盖旧场景摆位、资产或存档。

### 9.3 仍未完成与既知阻塞

- 打捞、摄影、抄网捕鱼、稳定内容ID、日配额、`dive.expedition`和跨owner奖励事务尚未接入。
- 脚蹼、工具挂点、上身工具层、轻潜水镜shader、标签逆映射、声音交接、舒适性开关和5体型完整动画尚未接入。
- 3–5分钟完整路线、实际210/225/240秒气量实测、跨07:00配额、16:9/16:10/21:9、Compatibility、低端设备和人工舒适性验收尚未完成。
- 直接运行正式工程`tests/integration/selftest.gd`日志 `sea-work/dive-p0-selftest.log` 报 `Identifier not found: Zones`；这次没有得到有效核心自检结果。
- 隔离`core`长批次（`sea-work/verification/20261114-170616-dive-p0-core-isolated-54ed42`）曾观察到旧72°断言、阳光房组件/远景水面、旧城实例、鱼群GPU色彩、NPC超时及资源泄漏等失败；这些失败没有完成逐项基线归因。该批随后已安全停止，最终状态为`killed`，没有最终全局退出码；不能把它写成全局通过，也不能把未完成的失败笼统归因于P0。

因此本轮结论是：**P0潜水控制、耗气、镜头和出水过渡优化已实现并通过定向逻辑/真实渲染专项；完整海底玩法闭环和全局工程门禁仍未完成。**

## 10. P0退出时序收口补验（2026-11-14）

复审P0代码后发现，正式返回在 `dive_exit_tick()` 完成时直接切到 `surface`，可能在圆幕真实遮黑前触发 `dive_end()`，造成水下角色/环境提前隐藏。已按原有四态与同一 `DiveSession` 事务修正：

- `DiveRuntimeController`：正式Session地图保留 `exit`，由 `exit_presentation_finished` 标记表现完成；只有Session确认真实黑帧后调用 `complete_exit_presentation()` 才进入 `surface`。无Session的旧预览/低级夹具仍保留同步完成行为。
- `DiveSession`：等待同一Controller完成短出水表现，超时记录诊断事件但仍进入遮幕；`cover_blank()`及`_await_curtain_draw()`完成后才授权Controller清理地图；返回异常路径统一恢复共享Air的 `surface_refill_enabled`。
- `DiveAir`/Controller：工具动作参数真正接入 `update()`；冲刺倍率要求实际有运动，碰撞挡停后清除冲刺意图，避免挡墙时继续显示冲刺FOV或按冲刺倍率耗气；浅层出水首帧的小位移不再误判为阻塞。
- 集成断言新增“真实黑帧前仍处于exit且runtime/潜水角色可见”，并保留非零位移/遮挡路径检查。

本次补验结果：

| 入口 | 结果 | 证据 |
|---|---|---|
| `dive-control`、`dive-transition`、`dive-maps` | 全部 PASS / exit0 | `/Users/zyq/work/sea-work/verification/20261114-175029-dive-p0-exit-sequencing-fix-e76e34` |
| `visual-dive-transition`、`visual-dive-control` | 全部 PASS / exit0，Forward+真实渲染 | `/Users/zyq/work/sea-work/verification/20261114-175307-dive-p0-exit-sequencing-visual-fix-1fc609` |
| 带“黑帧前仍可见”新断言的 `dive-transition` | PASS / exit0 | `/Users/zyq/work/sea-work/verification/20261114-175537-dive-p0-exit-sequencing-regression-assertion-7cf265` |

前述隔离 `core` 长批已由主线程安全停止，最终事实为 `killed`，没有最终全局退出码，不能当作全局通过。其观察到的旧场景、NPC、资源泄漏等失败保持“未完成/未归因”口径，不再写成已证实与P0无关。当前仍未完成的是P1内容闭环、P2装备/镜片/音视听、P3完整路线与设备矩阵，以及全局契约539/540问题。

## 11. P1远征协议第一阶段实现与回归（2026-11-14）

### 11.1 已实施范围

本阶段先收稳协议与所有权，不直接铺真实目标节点，保持 `DiveSession + Shared DiveRuntimeController + Map适配器` 的唯一所有者架构：

- `dive_session.gd`：修正 `WorldClock.query()`/`to_dict()`边界；使用 `day/seconds` 计算07:00 epoch；`to_dict()`为纯读；新增可选 expedition 序列化、候选存档时钟校验、严格照片摘要与图片引用校验。
- `SaveSchema`/`Main`：`dive.expedition`为可选模块，旧档缺整个模块迁移为空；存在但缺字段/类型/未来版本/非法晨次/重复ID/构图分数不一致/路径引用非法均拒绝。候选快照校验不读取恢复前现场时钟。
- `Inventory`：增加静默 `begin_add_all`、`commit_add_all`、`rollback_add_all`。Session 预检固定目标奖励与日配额，再预留库存，提交 expedition 与库存，最后由 Inventory 广播；失败恢复两端现场。
- `DiveSession` token：必须 active、稳定 swim、非 switching/frozen；绑定 session generation、target/action/map/epoch；换图、返回、读档、dispose 会失效。目标注册接口要求固定 action、owner map 与 reward，完成时拒绝奖励篡改。
- 照片协议：先记录稳定 photo_id、分数/可见度/构图摘要与首次日期；图片只接受受控相对引用。真实图片异步生产者尚未接入。

### 11.2 当前证据

| 入口 | 结果 | 证据 |
|---|---|---|
| `dive-maps`（含P1目标、token、照片、配额和wire夹具） | **873/0，exit0** | `/Users/zyq/work/sea-work/verification/20261114-190910-dive-p1-target-ownership-6653a6` |
| `dive-control` | **406/0，exit0** | `/Users/zyq/work/sea-work/verification/20261114-191056-dive-p1-final-control-regression-b2f959` |
| `dive-transition` | **exit0** | `/Users/zyq/work/sea-work/verification/20261114-191206-dive-p1-final-transition-regression-6f86c2` |
| `b2-pickup-transactions` | **191/0，exit0** | `/Users/zyq/work/sea-work/verification/20261114-191428-dive-p1-final-inventory-regression-223e8d` |
| `save-seed` | **exit0** | `/Users/zyq/work/sea-work/verification/20261114-191710-dive-p1-save-schema-seed-5b4c3b` |
| `save-corrupt-seed` | **exit0** | `/Users/zyq/work/sea-work/verification/20261114-191827-dive-p1-save-schema-corrupt-seed-c90d60` |
| `save-protection` | **exit0** | `/Users/zyq/work/sea-work/verification/20261114-191946-dive-p1-save-schema-protection-6b4546` |
| `framework-integration` | **52/0，exit0** | `/Users/zyq/work/sea-work/verification/20261114-192115-dive-p1-framework-regression-bcfc34` |

### 11.3 未完成边界

本阶段不签完整玩法：正式地图仍没有5个打捞锚点、2个捕鱼代理、6个摄影观察点及对应HUD/UI；没有真实距离/LOS/动作中断/抄网接触判定；没有异步图片成功/失败/迟到回调与图片文件落盘；没有返回后尊重自动保存意愿的单次写盘请求；没有210/225/240秒路线日志、跨07:00多潜实测、P2脚蹼/工具/镜片/声音与P3设备矩阵。

正式工程直接运行 `tests/integration/selftest.gd` 仍受 `Identifier not found: Zones` 前置编译错误阻塞；全局契约sync/check仍为历史539/540 issues，未批量重签hash、未宣称全工程通过。
