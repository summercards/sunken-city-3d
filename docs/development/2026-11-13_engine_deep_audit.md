# 2026-11-13 sea 工程深度审计与整改计划

[主文档中控](../../GDD_V1.0.md#feature-control) · [质量账本](../features/quality/ledger.md) · [存档账本](../features/save/ledger.md) · [资产账本](../features/asset/ledger.md)

## 范围与基线

- 源码基线 `94ec42e09095ea0e31646b81b93e3027d489c6ad`；开始及所有引擎审计批次的工作区均干净。本轮随后仅追加审计记录和入口，不改生产代码、资产、shader、主场景/用户Transform，不读写玩家正式存档，不修复问题，不批量刷新哈希。
- 对46/46功能导航、spec、ledger建覆盖矩阵，重点调用链深审框架、内容数据、存档、经营、交互、移动、潜水、NPC及资产治理；不是46功能逐行为穷举。
- 工程外交付根 `/Users/zyq/work/sea-work/audit-2026-11-13/`。63项去重登记与逐项方案：`issues.json`；报告制作源 `output/sea-deep-audit-20261113/stage1/final_draft.md`；正式Word交付路径 `output/sea-deep-audit-20261113/stage3/sea工程深度审计与整改方案_2026-11-13.docx`。文档转换及打包结果以最终交付卡和证据清单为准，不将该路径声明当成功证明。

## 结论与优先级

现有模块化基础真实，但尚不能签署架构独立、存档安全、玩法与账本一致的完整健康结论。63项包含缺陷、结构债、治理风险和待裁决事项，不是63个已发生玩家事故：P1=14、P2=39、P3=10，未确认P0；动态复现15、静态确认29、风险待验14、规则待裁决3、测试治理2。

优先修：候选二楼状态校验(S01)、语义坏主档与备份(S02)、未来模块保护(S03/S06)、归档碰撞(S04)、畸形decode(S05)、过场/疲劳门禁(S08/S09)、动作目标锁定(G01)、潜水返树职业端口(G02)。菜园桥5个Marker比派生面高0.737953m导致0/5锚点、总聚合35/40、豆豆可见但回退天台(G04)，不同于已接受街口下沉，不抬用户根或放宽支撑门槛。

资产重点：二进制CRLF归一化错误放行32 GLB(R01)、水密passed漏核心谓词(R02)、模板残留当前身份字段矛盾、45正式牧场GLB漏运行清单、8源/123运行真实内容漂移、许可pending与可携证据缺口。469差异路径字节等HEAD，属于已提交治理基线，非本轮弄脏。不把820条license pending当已侵权。

已排除误报：固定建造/一级船费const真实拒写，不能据静态说可改真实价格；Goal设施仅展示容器污染，权威支付不变。用户接受的位置、暂停住所、规划任务/音乐/音效/植物工坊不列回归。

## 当前实测与退出码

| 批次/检查 | 结果 | 原始证据 |
|---|---|---|
| 架构边界 | exit0；25服务/0 issues，覆盖有限 | 工程外审计根 `evidence/check_architecture.py.log` |
| 功能契约 | exit1；499 issues，不能签整体通过 | `evidence/check_feature_contracts.py.log` |
| 摆放台账 | exit0；6结构/0警告 | `evidence/check_placed_positions.py.log` |
| Python治理 | exit0；10/10 | `evidence/engineering-guards.exit.json`及日志 |
| 当前逻辑专项 | 40项32通过8失败，其中2项exit124；整体exit1 | `/Users/zyq/work/sea-work/verification/20261113-123757-deep-audit-20261113-199237/report.json` |
| 自检 | exit1；499 passed/33 failed，另1 SCRIPT ERROR，不沿用旧536/1 | `/Users/zyq/work/sea-work/verification/20261113-131204-deep-audit-visual-20261113-444694/selftest.log` |
| 真实room/quick-tools/gift-kiosk | 3项exit0/PASS，68PNG | 同一444694目录report及project/outputs |
| 存档反例 | 2入口；wrapper exit1，畸形decode7错误原样保红 | `/Users/zyq/work/sea-work/verification/20261113-124339-save-data-readonly-audit-cffaaf/report.json` |
| 玩法反例/常量裁决 | 9入口；wrapper exit1，5常量拒写负例保红 | `/Users/zyq/work/sea-work/verification/20261113-124651-audit-gameplay-dynamic-b16e30/report.json` |
| 菜园桥定向诊断 | exit1；8条/3失败，完成marker=true、无脚本异常 | `/Users/zyq/work/sea-work/verification/20261113-131805-audit-garden-readonly-8d6b04/report.json` |

40专项35入口有数值终局小计11303 checks/16 failures，不是全轮断言总数；24条FAIL与1脚本错误并非24新bug。失败包含开放范围/7格2床/替代支撑/三维面/prefab/迁址/密度旧夹具，wood测试采8束测10次索引越界，NPC seed受boot失败阻断并级联restart；仍保留真实garden失败。NPC集成超时具体停点未定。详见工程外 `evidence/test-triage.md`。

**真实渲染**：仅room8、quick-tools30、gift-kiosk30共68PNG；主线程目检3张(room-inside、1280 land-open、gift-kiosk-hero-day)，未称全图审。三视觉88 WARNING含60条同名instance uniform不同索引，需后续正确性验收，不签零警告。退出实例泄漏与导航/采集点吸附警告单列未归因。

**预期故障**：主动复现畸形decode、只读常量拒写与garden红项；原runner的exit/错误过滤未放宽，诊断完成不等于功能健康。

**未执行**：全部功能组合、全部Blend重开/GLB逐件渲染、68图全目检、二楼真实攀梯双进程自动加载、默认家园/五职业全矩阵、房间23点竞态、全owner重入、全部模块版本/平台存储/断电/磁盘满、实际PCK、远端CI、低端长时、音频听验与许可审核。

## 修改计划（仅计划，尚未实施）

1. B0：冻结证据，修二进制哈希/水密门禁与过时/挂起测试，保留真实红项，补治理负例（5条）。
2. B1：存档保护与关键生命周期止血；decode/版本→完整备份→候选世界→唯一归档；统一事务busy、target/token、挂起恢复（11条）。
3. B2：业务原子收支与保存窗口、迁移/消费者/autosave/reset体验、模态睡眠关闭、床与菜园局部空间（11条）。
4. B3：owned/integration/dependency编辑权、窄端口与规则归域、内容schema、条款/索引、资产身份/hash/manifest/分类/闭包/证据逐项归因（30条）。
5. B4：instance uniform、资源释放、导出包/平台故障/长期性能及许可发布闭包（6条）。

Main/HUD/SaveSchema整合热点由单一整合者串行接线，不机械按行拆文件；修复按FeatureID回到spec与ledger，反例先红后绿、专项后集成、如适用再真实视觉设备；每批可回滚。不扩大存档格式/ContentID变更，确需迁移先订契约。

全局门禁sync及无参最终检查的结果追加在本记录后续章节；未清零前明确失败，不因文档或索引回填宣称生产修复完成。

## 最终静态收尾

仅追加审计入口/质量、存档、资产、启动、交互、世界六功能账本后，正式执行：`check_feature_contracts.py --sync` exit1/498 issues；无参数检查exit1/499 issues（多一条派生索引陈旧）。检查器仅无issues才写回，故本轮未修改派生索引、主表状态摘要或资产JSON。日志 `evidence/final-contract-sync.log`、`final-contract-check.log` 与 `final-contract-results.json` 保留全部原始问题。`git diff --check` exit0。生产源、配置、模型、材质、主场景和用户位置均无diff；所有已有受跟踪文档变更为末尾追加，无删改历史。

## B1 交互生命周期子批实际实施

基于共享工作区HEAD `40c939d80ac58acf308a1d0a9959af43f221502b`。开始已有SaveGame/schema、test_save_reset、工程守卫及未跟踪test_save_boundaries改动；本子批未编辑这些文件，不能将整份工作树diff归本子批。不改main.tscn、用户Transform、生产资产、根v4或模块快照字段。

### 实际改动

1. Interactor锁action_target/generation，完成只消费捕获目标；扫描换焦点、不可交互/失效/取消清动作及旧command，防旧代次与同步进度取消误提交。同目标自动接近重设锚点、松键继续完成保留。新增独立正式test_interactor_action_target.gd及runner一条登记。
2. Main统一Registry busy包含room.busy、疲劳台词事务；公开capture/write/restore/reset均门禁，不靠黑幕吃键。房间期间Main不推进SleepCycle时钟，房间请求查询睡眠/疲劳/潜水busy。RoomController generation/cancel_transition及SleepCurtain.cancel_blank防旧await覆盖恢复，室外重同步还原室内相机，重复室内恢复保留原室外备份。
3. EnergyModel新增不持久化generation，Main恢复完成才续接零体力强制休息；旧timer同时核对会话和体力代次，from_dict不重放exhausted。低层restore_world_state取消疲劳/房间旧事务，公共restore在busy时仍拒绝。
4. NpcCareerPanel.suspend/resume保留query/perform并失效按钮；出树只挂起，Main返树resume，最终dispose释放端口，不重复连信号。出树Button不调用release_focus。

### 正式 runner 与当前逻辑证据

所有引擎经原 `scripts/run_verification.py`，环境固定 `GODOT=/Applications/Godot.app/Contents/MacOS/Godot`、`SEA_WORK_ROOT=/Users/zyq/work/sea-work`，Godot4.7.2。外部wrapper `audit-2026-11-13/evidence/run_b1_lifecycle.py` 仅在内存登记组合探针并复制到隔离tests，不改生产runner错误过滤或超时判定。

- 首批 `20261113-155412-b1-interactor-cfb781`：总exit1，新测试38/1（夹具扫描后未复位朝向），query15/0、facing118/0、reach36/0、farm636/0通过。
- 首个生命周期批 `20261113-160135-b1-lifecycle-first-1014c4`：总exit1。room163/0、energy40/0、framework52/0、sleep42/0、dive-transition501/0及存档前置通过；careers87/0但release_focus引擎ERROR使runner FAIL/引擎exit0；组合109/1（opening取消后相机未还原）；npc-integration因旧天台/花园锚点断言失败并exit124。上述新缺陷已修，旧报告保留。
- 最终合批 `20261113-160949-b1-lifecycle-final-4bf571/report.json`：15入口全部runner PASS、exit0、completion_marker=true、unexpected_errors=[]。计数：interactor38/0、query15/0、facing118/0、reach36/0、farm636/0、room163/0、energy40/0、careers87/0、framework52/0、sleep42/0、dive-transition501/0、b1-lifecycle109/0；另save-corrupt-seed/save-protection/save-seed无计数PASS。总命令含上述入口，--label b1-lifecycle-final --timeout180。
- 最后同步回调保护加强：`20261113-161138-b1-final-guards-10b98b/report.json` interactor41/0、room163/0，均exit0；此批六个修改核心脚本与当前工作区逐字节一致，上一合批仅Interactor/RoomController少两条同步边界guard。

组合109/0具体覆盖：进出closing/closed/opening六边界直接API拒绝；自动保存到期但过场不替换文件；22:59进屋不触发共幕睡眠；cover/opening取消后旧等待不覆盖恢复现场；归零台词门禁、旧timer对满体力新现场失效、合法零体力快照经公共restore完成后续接强制睡眠并次日50/50；三轮真实zone1潜水往返后五职业入口都可打开/刷新真实query，保持Main/Panel/端口身份及连接数，每轮种植职业真实perform路由商店。五职业逐一扣费/奖励不在本次证明范围。

### 真实渲染、预期故障、未执行与遗留

- 真实渲染：本子批全部headless，无截图，不将process_frame当黑帧绘制；不复用历史截图签本轮。
- 预期/保留红项：npc-integration旧站位数量/归属与花园支撑问题仍FAIL/124，不修改用户摆位或资产迁就。首轮自新增测试/组合问题如上保留，不按零断言失败掩盖引擎错误。
- 警告：最终dive-transition有9个、b1-lifecycle有4个ObjectDB实例退出泄漏警告；另导航agent_radius量化/采集点吸附警告仍有。runner按原规则PASS不等于零泄漏，未归因。
- 未执行：真实渲染/黑帧像素、F5/F9真实按键、默认home_seabed往返、全图/全部职业支付奖励、跨进程零体力恢复、长时与全设备、泄漏归因。零体力只签同进程公开恢复；不宣称跨进程。
- 未修范围：存档核心问题由另一子批处理，NPC锚点/菜园桥支撑属后续；未批量更新任何资产哈希，未提交或推送。

静态全局sync/check、diff和保护边界最终结果在下方追加，不预签全工程通过。

### B1 子批静态收尾

- `python3 -B scripts/check_feature_contracts.py --sync`：exit1，531 issues；随后无参检查exit1，532 issues（含派生索引陈旧）。46功能/1073源资产/1510运行哈希。包含历史断链/资产条款/大量真实哈希差异，以及本次Main/RoomController/NpcCareerPanel/SleepCurtain的定向登记未更新；未批量重签或写资产JSON。无参完整日志 `/Users/zyq/work/sea-work/audit-2026-11-13/evidence/b1-contract-check.log`。
- `check_architecture.py`：exit0，25服务/0issues；`check_placed_positions.py`：exit0，6结构/0warning；`git diff --check`：exit0。
- 禁止范围核对：main.tscn、godot/assets、assets、art_source没有工作树diff；SaveGame/schema仍是开始时已有diff（79/45、39/3），本子批没有编辑。没有提交/推送。
- 职业面板实现与定向潜水五入口已验证，但npc-integration综合入口仍失败/124，任务保留集成阻塞，不以局部绿项签全量完成。全局静态及资源泄漏也未清零。

## B0/B1 第二轮实际实施与收尾（2026-11-13）

本节覆盖前文“仅审计、未修生产”的历史状态之后实际授权实施的B0/B1子批；前文历史结果不回写。

### B0 验收基础

- `scripts/check_feature_contracts.py` 的CRLF兼容现在只适用于明确文本后缀、UTF-8且无NUL资源；GLB/Blend/PNG等二进制只按原始字节SHA校验。新增GLB/PNG/Blend/NUL/非UTF8/文本CRLF负例。
- `tools/blender/sunken_city/audit_seal.py` 将boundary_after、nonmanifold_after、缺输入、空组件和记录不完整纳入失败；失败返回非零退出码。新增水密逐项失败的纯Python模拟门禁，不运行Blender替代真实几何验收。
- 过期夹具已同步当前契约：开放海域显式边界与无界海面分开断言；默认种植7格/2床；建造柱允许真实重绑定但唯一支撑仍保护；wood-bundles按当前家园3槽配额、每个yield独立restore，避免数组索引级联超时。
- B0治理测试由原10项扩为17项，**exit0**；`git diff --check` **exit0**。B0专项首轮framework-modules/farming **exit0**；building-simulate/wood-bundles在重启隔离工程、修正GDScript显式类型与当前密度夹具后 **exit0**（报告：`/Users/zyq/work/sea-work/verification/20261113-165534-b0-fixture-repair-20261113-r3-fdafe3`）。

### B1 存档保护

- SaveGame decode先做future/基础容器守卫，畸形economy不再SCRIPT ERROR；Schema加入模块future传播、weather/profile版本、NPC日期和farm水位线校验；旧v0/v1迁移以历史农田日次建立时间。
- 语义读档支持带完整SnapshotRegistry的可恢复择优，坏主档不会污染有效bak；archive固定stamp生成唯一后缀并校验回滚；Main.load_game改用`read_recoverable`。根v4与已有模块存档字段不变。
- 新增`save-boundaries`独立runner，覆盖畸形输入回退、模块未来版本、旧档迁移、weather版本、farm水位线、缺room一致性、语义坏档/bak、唯一归档。第一版挂在save-reset内曾exit124（夹具过宽）；拆分后**exit0**，报告：`/Users/zyq/work/sea-work/verification/20261113-163754-b01-save-boundaries-20261113-c5098f`。
- B1组合复测：`interactor-action-target`、`room`、`energy`、`npc-careers`、`save-corrupt-seed`、`save-protection`、`save-reset`、`save-seed`、`framework-integration`均**exit0**；初次组合中的save-boundaries exit124属于旧runner挂载方式，已由独立入口复验exit0。该轮全headless，无真实渲染，不签跨设备断电、全职业支付奖励和长时零泄漏。

### 当前剩余阻塞

- G04 菜园桥锚点空间归属已修复：`NpcStations/residence_garden_bridge` 本地 Y 对齐模型派生 WalkGardenDeck 实际代表层，未改用户摆位、资产或 `SUPPORT_TOLERANCE`；正式 `garden-npc` exit0，5/5 锚点有效、聚合40、豆豆不 fallback。`npc-integration` 仍受当前工作区既有天台站位/路径断言失败并超时 exit124；`npc-save-seed` 受既有天台/恢复前置失败 exit1，不能据此签全集成或存档通过，未运行 restart。
- `check_feature_contracts.py`在B0/B1代码及账本变更后仍需重新执行；既有资产/链接/条款/索引问题不能通过批量刷新哈希解决。
- 当前生产工作区未提交、未推送；未改main.tscn、godot/assets、assets、art_source或玩家正式存档。

## B2 G06 床位一致性子批

基于含 B0/B1 未提交修改的共享工作区实施，仅编辑 `godot/src/room/room_service.gd`、现有 `godot/tests/test_room.gd`、room spec/ledger 及本节；原 B1 room 测试与账本追加保持。未编辑 Main、RoomController、RoomBed、SaveGame/schema、runner、主场景、资产或用户 Transform；未提交/推送。

- 根因：clampf 接受上边界，Rect2.has_point 却排除上边界；朝向归一化晚于候选布局计算。现先归一化 yaw，再夹回/滑位；候选必须经同一 validate_snapshot 后才能提交并发 changed。滑位/校验共用有限闭区间、固定 `1e-6` 局部米边界容差；陈设重叠仍用实际位置，不通过临时夹回或向内 epsilon 掩盖。from_dict 不再夹改已接受的 X/Z，默认床与 room v1/root v4 保持。
- 正式命令：`GODOT=/Applications/Godot.app/Contents/MacOS/Godot SEA_WORK_ROOT=/Users/zyq/work/sea-work python3 -B scripts/run_verification.py room save-boundaries framework-integration --label b2-g06-final --timeout 180`。报告 `/Users/zyq/work/sea-work/verification/20261113-175647-b2-g06-final-6b72dd/report.json`：room763/0、save-boundaries168/0、自动前置save-seed PASS、framework-integration52/0，各项及总命令 exit0，completion_marker=true、unexpected_errors=[]；未修改 runner 判定。
- 测试覆盖默认床、0/±90/180/±45度/绕整圈/巨大有限 yaw 共8组，每组四边四角/超界夹回/陈设滑位；成功返回值与状态一致、changed 时即合法、同服务校验、恢复不挪位及正式磁盘 write/read。额外覆盖边界±0.5e-6接受、±4e-6拒绝、非有限命令不改现场。
- 反例证据：`20261113-174933-b2-g06-red-467531` room675/95 exit1；修复后首轮 `20261113-175218-b2-g06-room-84b7cd` room682/82 exit1，主要为新增测试对 JSON float 的 Dictionary 精确比较错误，修正为位置按 Vector3 精确比较、yaw仅容忍1e-12序列化末位后，`20261113-175446-b2-g06-room-final-427544` room763/0 exit0，再跑上述正式合批。红报告保留，不将测试误判称生产缺陷。
- 真实渲染：全部 headless，无截图，不复用旧图签本轮。预期负例为非有限输入/容差外快照拒绝；最终无预期引擎错误，导航半径量化及既有采集点吸附 WARNING 未修。
- G07 明确保留待验：bedside_point 的固定 +X 偏移再夹回仍有床内几何风险，例如 yaw=PI/2 的右后边界床位；本批未改站位、facing_yaw、碰撞或路线，未做真实胶囊及到门矩阵，不宣称已证必卡死或已修复。全角度穷举、真实渲染、跨平台/断电/磁盘满不在本批证明范围。
- 静态门禁：`check_feature_contracts.py --sync` exit1/531 issues，随后无参 exit1/532 issues（多派生索引陈旧），日志存最终验证目录 `contracts-sync.log` / `contracts-check.log`。包括历史断链/资产条款/哈希问题，以及本批 room_service.gd 的真实源码哈希漂移；未越界修改运行资源清单或批量重签，不宣称全工程契约通过。`git diff --check` 首次发现本节 EOF 多空行，修正后复验 exit0。最终工作区 room_service.gd/test_room.gd 与上述合批隔离副本 SHA256 一致；main.tscn、godot/assets、assets、art_source 无 diff。

## B2 业务事务与空间修复最终回填（2026-11-14）

### 范围、当前口径与证据身份

本节承接 B2 全部 11 项 S10/S11/S12/S14/S15/S16/G03/G04/G05/G06/G07；S10 已在 B1 实现，本批复用，不重复计为新增修复。这里的“最终回填”是已完成业务/空间实现及已确定报告的汇总，**不是全工程 verified 或父线程尚在执行项目的提前签署**。各功能登记头、主表状态和历史原文保持；相冲突的旧阶段描述以本节及对应 spec 文末覆盖声明为现行口径。

本次文档作业先读 AGENTS、GDD 功能导航、相关 spec/ledger，再逐项只读核对共享工作区代码、隔离报告与日志；只追加既有文档，不启动 Godot、runner、契约 checker 或 sync，不改代码、资产、派生索引，不提交/推送。运行证据来自父批已有产物，不算本次文档作业新跑。报告 HEAD 为 `40c939d80ac58acf308a1d0a9959af43f221502b` 且工作树有未提交修改；报告的隔离工程/当时字节才是证据对象，HEAD+working_tree 文本不能替代当前全文件哈希签署。

### 11 项实现逐项核对

| 审计项 | 当前实现与代码核对入口 | 承接与证据边界 |
|---|---|---|
| S10 缺 room 迁移一致性 | `godot/src/save/save_game.gd:159` 的 `_migrate_optional` 被 decode 与公开 restore 共用；restore 先深复制候选，缺 room 才补默认，已存在但截断/错误的 room 仍交 Schema/Registry 拒绝。Registry.validate 本身不松绑。 | 复用 B1；SEA-SAVE-R05/R06、SEA-ROOM-R12；本轮 save-boundaries168/0，不另造迁移入口或提升状态。 |
| S11 恢复后的纯消费者 | `godot/src/bootstrap/main.gd:4280` `_after_restore` 在 owner/世界投影恢复后调用 `:4307` `_sync_restored_consumers`，主动同步 Birds/GullFlock 小时、DaylightRig 天气上下文和小时、WeatherView、日历文案，不重发 clock.changed/weather.changed。 | SEA-SAVE-R04/R06、SEA-AMBIENT-R05/R21；b2-session 暂停雨夜/晴昼互读、即时消费者与 clock.changed 计数为0。既有 DailyShipping/Fishery 仍由各 owner 水位线负责，不将“纯消费者刷新”说成整条 after_restore 无业务调用。 |
| S12 失败保护与自动保存意愿 | `main.gd:348` 启动失败只置 `_save_protected`；`:3456` 保护期间冻结自动保存倒计时，未永久改 `_autosave_on`。`:606` 显式成功 load 撤临时保护、接管 target 为当前 `_save_path`、重置倒计时，避免随后自动覆盖原坏槽；reset 也仅成功后接管槽位，不开启用户/nosave/capture/测试明确禁用。 | SEA-BOOT-R04、SEA-SAVE-R01/R05/R14；b2-session 实际到期写入替代槽且原坏字节不变。005741 的旧 save-protection 断言失败仍保留 exit1；新断言已见源码，补跑待父最终追加。 |
| S14 重置存储事务 | `godot/src/save/reset_transaction.gd:11`：校验前态/defaults → prepare staging并读回 → intent → 复制并SHA校验主档/bak旧字节归档 → Registry apply → 按实际 restored 完成态再stage并更新intent → replace主槽、退出旧bak → commit → recover清理。`save_game.gd:13/76` 与 `main.gd:645` 为正式入口。 | 覆盖旧 R14“先改名归档再恢复再普通写盘”。失败按intent恢复磁盘，已apply时回前持久态及非持久runtime memento；明确 rollback_ok/recovery_required，失败不伪报成功。未提交intent启动回滚，已提交校验新槽/归档后收尾；仅intent空槽也能启动。单进程单写者、同文件系统rename；flush/读回不是目录fsync，不保证真实断电。b2-reset-atomic98/0；早批中断矩阵单列，不签修订后当前字节跨进程通过。 |
| S15 跨 owner 保存窗口及 apply 结果 | `main.gd:4212` busy_query 汇集 Economy/NPC/SeaProps及既有过场等；`economy.gd:52` 聚合各业务/库存busy。`snapshot_registry.gd:59` 全验后捕获前持久态与可选runtime，屏蔽原event_sources，识别bool false/字典ok=false；失败回滚且不发restored，成功恢复原屏蔽状态后发一次。void旧apply保持兼容。 | SEA-SAVE-R05/R06；NPC礼物/请求、Fishery收获、拾取的锁覆盖外部入账与自身状态提交/事件，Inventory.changed中capture为空、write/restore拒绝。若回滚自身失败明确返回，不承诺任意owner故障必能恢复。 |
| S16 旧经营同步重入 | `inventory.gd:225/251/273` pay/add_all/exchange整笔候选后发布，发布期busy；`inventory_transfer.gd:11` 双端预检/静默提交、失败回滚counts/order/原屏蔽状态，成功两端busy后按实际差发布。`warehouse_service.gd:32` 背包优先再仓库；Construction/Facility/Ship/Farm/Orders 各持owner锁跨支付→状态→事件。Farm与正式Orders使用exchange，不把遗留fake give分支说成已删除。 | SEA-INVENTORY-R02/R05/R11/R12、WAREHOUSE-R02–R04、BUILD-R01/R02/R04、FACILITY-R01/R04、SHIP-R01/R04、FARM-R03/R05/R13、ORDER-R02/R03/R05；b2-transactions103/0包含仓储异命令/失败回滚/订单补位与NPC memento。声明但未接线的 transaction_begin/end 不计已用端口。 |
| G03 合并奖励 | `salvage_rewards.gd:43` `commit_salvage_result` 校验整笔奖励，receive_all（或add_all）一次入账，成功才16秒冷却；`commit_salvage`仍只回实际added。`economy.gd:471`接Inventory.add_all；Main职业打捞消费详细结果，不按预期奖励虚报。`sea_props.gd:378/397/420`复合箱/鱼共用原子receive_all和collection busy，失败不移目标/推进冷却随机流。 | SEA-SALVAGE-R02/R04、PICKUP-R02/R03/R05/R16、INVENTORY-R11；旧salvage give不再被结算接受（configure能保存旧键不等于可结算），无原子端口明确拒绝。SeaProps单资源旧give兼容仍在，不能混写成所有旧端口均删除。b2-session真实NPC 0/1/2空格；b2-pickup-transactions191/0含复合箱和半堆等。 |
| G04 菜园桥锚点 | `godot/scenes/facilities/neon_garden_quarter.tscn:214` 只改 `NpcStations/residence_garden_bridge` 本地Y，对齐实际派生WalkGardenDeck代表层；原高度差0.737953m。不改根、五Marker相对关系、模型、派生参数或SUPPORT_TOLERANCE=0.05。 | SEA-WORLD-R12/R21/R29/R32、RESIDENT-R09/R18/R24；garden-npc26/0、5/5菜园锚点/聚合40/豆豆不fallback；当前集成853/0及seed527/0、restart280/0补上早批未签的NPC链，不据此恢复已退出主场景的zone3/旧街口。 |
| G05 自动睡眠结束模态 | `main.gd:4791/4802` `_close_owned_modals` 在Canvas隐藏前真实close商店/职业、cancel NPC session、close工坊/快捷环/建造、dismiss招呼并清external modal；菜单/卡片/订单等原入口同样关闭。 | SEA-SLEEP-R02/R03、RESIDENT-R11；b2-session三类Shop/职业/NPC在22:59自动睡后均逻辑closed、旧确认回调不购买/扣费、只换日一次。醒来只恢复基础可见性，不复活旧会话；真实视觉另待。 |
| G06 床位可保存一致性 | `room_service.gd:82/112/355` yaw先归一化，共用有限闭区间1e-6局部米容差和陈设规则；最终候选先validate再提交/changed，from_dict不再二次夹改已接受XZ。 | SEA-ROOM-R08/R09/R12；复用先前G06修复，当前room763/0覆盖边角/滑位/旋转/写读；历史675/95与682/82保留，不称全角度穷举。 |
| G07 床边净空与真实接近 | `room_service.gd:149/230/320` 四边候选按床局部OBB、实际胶囊半径/房间scale换算，筛墙/家具/三块walk中心域与到门路线；真实route_query先查询并复核净空，必要时0.1m局部网格求路。RoomController注入世界↔局部转换，RoomBed.approach_path提供可选世界路线；`approach_action.gd:41` 消费该路线，保留start_walk支撑/状态准备且不被普通求路覆盖。 | SEA-ROOM-R07–R10/R12、SLEEP-R01；新布置无安全候选拒绝，旧档不挪床/不增字段，醒在受保护前厅并提示重新布置。b2-bedside1800/0：130合法布局、133真实胶囊布局、133真实move_ground到门、26正式approach含13绕行，不以数学采样替代物理证据。 |

### 已确定正式逻辑结果（仅本报告快照）

- A：`/Users/zyq/work/sea-work/verification/20261114-005436-b2-production-closeout-e11fda/report.json`，5入口全部 PASS、exit0、completion_marker=true、unexpected_errors=[]，renderer均headless。

| A入口 | checks / failures |
|---|---:|
| b2-session | 51 / 0 |
| b2-transactions | 103 / 0 |
| b2-reset-atomic | 98 / 0 |
| b2-pickup-transactions | 191 / 0 |
| b2-bedside | 1800 / 0 |

- B：`/Users/zyq/work/sea-work/verification/20261114-005741-b2-integrated-final-dde4f5/report.json`，**19入口中18 PASS/exit0，save-protection FAIL/exit1**，不能写整批通过。全部unexpected_errors为空不抵消失败。

| B已通过入口 | checks / failures |
|---|---|
| modules / framework-modules / farming / farm-day-change | 101/0；52/0；35/0；23/0 |
| fishery-production / room / sleep-cycle | 33/0；763/0；42/0 |
| save-boundaries / save-reset / framework-integration | 168/0；195/0；52/0 |
| garden-npc / npc-rules / npc-careers / npc-integration | 26/0；655/0；87/0；853/0 |
| npc-save-seed / npc-save-restart | 527/0；280/0 |
| save-corrupt-seed / save-seed | 无数值终局计数，各PASS/exit0 |

B的save-protection失败精确来自旧断言 `_save_protected and not _autosave_on`；同一日志真实未来主档字节不变、原槽拒写、另槽写成功，不能解读为已覆坏档。父线程已把断言改为实际保护及121秒后倒计时冻结；**当前仅核到修订源码，补跑结果待父最终追加**，不把代码修改当已通过。

早批进程中断矩阵 `/Users/zyq/work/sea-work/b2-reset-atomic-results.json`：unit引擎0/runner0；intent/archive/replace/commit/future五seed均引擎 **-9 / runner1**，为精确预期SIGKILL；五recover均引擎0/runner0。accepted=true只说明命中中断/恢复预期，不把seed涂成普通PASS/exit0。该矩阵早于当前memento修订，**不能用早批hash签当前字节**；修订后的跨进程矩阵如另跑，待父按实际报告追加。进程kill也不等于真实设备断电。

已有父批静态实证为17项纯Python治理、架构25/0、摆位6/0与diff-check exit0；本次文档作业未复跑上述治理/架构/摆位。整体契约初次sync531/check532、并行后sync533/check534均为历史失败，父最终门禁另跑另记，不借历史数字签当前。

### 遗留、保护范围与待父最终追加

- 真实视觉本轮尚未回填：`visual-room` / `visual-garden-bubble` / `visual-sleep-cycle` 的实际报告、退出码、PNG清单与目检范围 **待父最终追加**；不沿用旧图、不把headless或process_frame当绘制证明。
- `legacy management --full-world` 为36/1，唯一“修复后开放第二种植床”失败：当前正式Farm无 `farm_plot_a` specs，zone3已退出main；记为旧完整范围夹具不可签，不为凑绿恢复旧内容或修改生产规则。
- 未执行整全selftest、真实设备断电/磁盘满、多进程并写及长时泄漏验收；导航agent_radius量化和zone2_glass吸附警告仍在，不签零警告/零泄漏或全部平台存储可靠。
- B2实施范围未动main.tscn、生产资产源/GLB、用户根Transform、正式user档；空间只改菜园NpcStations局部高度。共享工作区并行workshop/plant_authoring变化不是本批，不纳入B2修复/验证归属，也不回滚他人改动。
- 待父填：保护专项新断言补跑；memento修订后跨进程中断/恢复的报告与字节身份；本轮视觉与审图；最终契约sync/check真实退出码及本批精确文件快照。所有待项未补前，各功能status原样，不升级verified。

### 本次纯文档追加检查

本次25份既有文档（本主记录、模块契约、18本功能账本、5份spec）逐份以作业前长度切取现有前缀并比对SHA256：25/25原字节前缀保持，追加相对文件链接可定位；登记头/历史无删改。`git diff --check` exit0；这只是文档追加/格式检查，不是功能契约checker或运行验收。GDD、派生索引、代码/runner/资产未由本作业写入，未提交。

## B2 最后复测与签署范围（2026-11-14）

本节追加覆盖上一节待父回填项，不改早批FAIL记录。

- 生产专项：`20261114-005436-b2-production-closeout-e11fda` 的5项均exit0/PASS：transactions103/0、reset-atomic98/0、pickup191/0、bedside1800/0、session51/0。随后强化session夹具，先给足真实升级资源并断言捕获的商店/职业旧确认Callable有效，实际自动睡醒后调用不能扣费/购买/升级；`20261114-012421-b2-session-valid-confirm-d25e8b` **53/0，exit0**，不是空回调验收。
- 关联集成：`20261114-005741-b2-integrated-final-dde4f5` 19项18通过1旧断言失败保留；`20261114-010438-b2-last-safety-visual-a96032` 的10项全exit0/PASS，含修订后save-protection、坏档seed、Interactor41/0、energy40/0、building-simulate/wood-bundles、npc-clock303/0，以及3真实视觉。当前各入口采用最新结果后没有剩余B2失败；不是全量selftest或全工程绿。
- 旧management --full-world的36/1，定位为正式FarmField只注册实际场景地格，已退场zone3不存在farm_plot_a；测试现在分别验证“已退场不凭空建床”与“修缮后定义资格规则成立”，没有恢复旧建筑或放宽升级门槛。`20261114-012647-b2-legacy-management-current-profile-739d6f` **37/0，exit0**。
- 当前字节进程中断矩阵：重新运行工程外 `run_b2_reset_atomic.py`，正式runner单位批 `20261114-012203-b2-reset-atomic-unit-297b2c` exit0；intent/archive/replace/commit/future五个seed均引擎 **-9、runner1**（故意SIGKILL），各自独立新进程recover均引擎0/runner0，外层矩阵exit0。完整阶段report路径见 `/Users/zyq/work/sea-work/b2-reset-atomic-results.json`。只有同机进程中断恢复证据，不把SIGKILL当目录fsync、物理断电、磁盘满或跨平台保证。
- 真实渲染：010438批的visual-room、visual-garden-bubble、visual-sleep-cycle均exit0，**18张PNG（房间8/菜园4/睡眠6）**。本轮只目检room-inside、garden-bubble-single、sleep-wake三图：卧室家具/人物可见；菜园对白可读、尾巴指向人物，但下半身被作物遮住，不能从图确认脚底接触或签全站姿美术；醒来图玩家位于屋外太阳房门口、HUD可见且无残留黑幕，符合该次屋外睡眠。没有将其写成室内醒来截图。其余15图未人工逐图审阅。材质同名instance uniform索引冲突、agent_radius量化、玻璃点吸附等WARNING保留，归后续治理，不称零警告。
- 代码证据：005436后Main仅更新重置流程注释，不改变执行语句；最后session使用012421副本。涉及reset/registry/room/props/economy等核心文件已与对应隔离源码比对字节一致；并行工坊/植物工坊未纳入B2归属，不回滚他人改动。只改菜园NPC站台局部高度，main.tscn、资产源/GLB、用户根Transform和玩家正式档未改，未提交/推送。
- 静态：17项治理、架构25服务/0问题、摆放6/0、diff-check均exit0。全库契约最终值在下节独立回填；B3/B4、全部selftest、全设备、长期泄漏与完整职业支付/内容矩阵未签。

### B2 最终门禁与证据索引

按最新结果去重，**33个入口全部PASS/exit0（30逻辑、3真实渲染）**，不是一次批跑，也不是全库测试；过程批save-protection旧断言exit1、management旧前提36/1及其它早期失败保留。`b2-final-run-index.json` 已冻结33项各自report/log SHA、18PNG SHA及19个核心生产脚本与相关测试的SHA/匹配隔离批；抽取文件无未匹配源码。路径 `/Users/zyq/work/sea-work/audit-2026-11-13/evidence/b2-final-run-index.json`。当前b2-session强化版本53/0，management37/0，均exit0。

最终全工程契约复查：`check_feature_contracts.py --sync` **exit1 / 532 issues**，无参正式检查 **exit1 / 533 issues**（含派生索引陈旧）。日志与机器摘要位于同evidence目录的 `b2-final-contract-{sync,check}.log`、`b2-final-contract-results.json`。只如实登记，没有批量刷新源码/资产hash、放宽门禁或把索引同步当全工程通过。随后仅追加账本结果及本节，无生产变更；若共享工作区后续并行继续变更，数字以新批为准。

B2业务/空间实现与本批关联回归完成；18本功能账本、5份现行spec、模块契约与主入口已追加承接。总体状态不升级verified；B3资产/文档治理、B4视觉设备/发行可靠性，以及前述未执行/视觉遮挡限制继续保留。未自动提交或推送。

## B3 模块边界与验收治理修复（2026-11-14）

本节登记B3中已安全实施的子集，不把资产事实冻结、产品规则裁决或B4发行验收提前纳入。当前工作区保留B0/B1/B2及并行工坊/植物工坊未提交改动；本批未回退、未改用户手摆主场景根Transform、正式资产源或正式存档。

### 已实施

- **A04 / G11 查询边界**：`Zones.get_zone/landing/landings_of`、`ItemDB.get_item`、`GoalService.goal_info`均在公开查询边界返回递归副本；`Zones.bind_scene`仍直接写唯一内部注册表，权威支付服务和价格数值不变。
- **A06 建筑规则解环**：楼梯吸附纯规则下沉至`AssemblyRules.snap_stairs`；`BuildingCatalog`旧三参入口保留兼容转发，改为显式运行时装配，不再编译期/静态初始化依赖反向注册。现有吸附结果、排序、5m规则与旧布局格式保持。
- **A05 内容漂移守卫**：真实建造/搬移/回收/快照入口在支付、退款和布局提交前拒绝配方目录漂移；热路径改为逐字段检查，不再每次预览/施工tick做全目录JSON深复制序列化。`active`仍是运行开关，不被误判为源内容腐化；提交期间的外部回调不可变事务边界仍按测试覆盖范围解释，未宣称任意宿主回调故障均可自动回滚。
- **R15 高置信解析子集**：摆位检查器统一有限浮点词法，支持科学计数法、显式正号和`.25`，严格解析Transform3D 12个数并按序列化basis列计算缩放；用户位置真值、台账和非均匀缩放告警政策不变。
- **Q01/Q02 夹具与runner治理**：`run_verification.py`每项从完整配置独立派生，工坊/植物检查不再污染后续游戏检查的Autoload；management按默认minimal与显式`--full-world`分支断言当前范围，不恢复已退出zone3或用旧夹具凑绿。

### B3 实测结果

证据目录：`/Users/zyq/work/sea-work/verification/20261114-104347-b3-final-regression-20261114-6155e0`、`.../b3-management-minimal-final-20261114-517f33`、`.../b3-management-full-final-20261114-b52afa`。

- B3专项及关联回归全部exit0：`b3-goal-query-copy`、`b3-query-copy`、`b3-building-guards`、`building-decoupling`、`building-5m-rules`、`building-simulate`、`building-integration`、`framework-modules`、`save-seed`、`framework-integration`。
- `management`默认minimal与`--full-world`各自exit0；此前默认profile的37/4已裁决为旧范围夹具错配，保留原始失败证据，不归因于B3生产回归。
- 工程治理测试31/31通过；摆位检查6 structures / 0 warnings；架构检查25 services / 0 issues；`git diff --check` exit0。

### B3未完成与后续边界

- B3收尾契约门禁：`check_feature_contracts.py --sync` exit1 / 535 issues；无参正式检查 exit1 / 536 issues。主要仍为SEA-ASSET条款行不一致、历史/外部证据链接不可携和资产/运行资源治理问题；未批量刷新哈希或派生索引。R03/R04/R05/R07–R14/R17–R18继续按资产事实冻结和治理策略处理。
- G08满包采集、G09 scope矩阵、G10潜水HUD、S13迁移时刻、D01/D02/D03/D04以及A01–A03仍需产品或架构裁决，不在本批擅改。
- R15仅完成解析与负例子集，Interior/更完整闭包、文档硬坐标lint等范围仍待扩展；A05不签长期性能、任意回调故障回滚或发行设备可靠性。
- B4继续负责真实视觉警告、导航/采集告警、资源生命周期、导出包、许可、断电/磁盘满/跨平台与长期性能；本审计没有预设B5。

本节只登记B3实现和真实退出码，未提交或推送；B3不升级功能登记头为verified，不等同全工程健康。

## B4 视觉、发行与可靠性修复（2026-11-14）

本节登记B4当前可安全完成的验证与小范围修复，不把未生成的发行包、未授权的许可、未执行的设备故障和未完成的长期生命周期矩阵写成通过。保持用户主场景摆位、正式资产源/GLB、正式存档和产品规则不变。

### 已实施的安全子集

- **Q03 材质实例槽位**：`sunny_palette.gdshader`保留0–8原布局；`sunny_palette_gloss.gdshader`对共享的`sea_material_role`、`sea_gloss_controls`、`sea_gloss_emission_energy`显式使用0、3、7槽位。新增文本负例检查重复槽位、缺槽位、隐式声明和跨shader错位，不改变默认值和材质资源。
- **D05 发行闭包审计工具**：新增只读`scripts/audit_release_closure.py`，要求显式PCK、closure JSON和发行根目录；支持PCK v2/v3/v4及内嵌包、动态资源映射、资源清单、GDExtension、外置库、字体/插件许可证文件及pending/unknown阻断。没有输入包时返回`UNEXECUTED/exit2`，不调用导出或发布。
- **A08 生命周期证据协议**：新增离线证据解析与负例测试，要求隔离user目录、真实源退出码、完成标记、每个场景至少3轮预热+3轮测量、WeakRef/Callable探针、延迟释放检查和稳定窗口。合成样本只能标`SYNTHETIC_ONLY`，不能冒充Godot通过。

### B4 当前实测

- 纯Python tooling：**87/87，exit0**；包含B0–B3治理、Q03槽位、D05闭包审计和A08生命周期协议。`git diff --check` exit0。
- `check_material_params.py`：**10份登记材质、51份材质文件，exit0**。
- Q03视觉回归：`visual-room` exit0、`visual-gift-kiosk` exit0、`workshop-rules` exit0。三项日志不再出现此前的同名instance uniform冲突；仍有导航半径和zone2_glass数据警告。
- Q04导航/采集回归：`ground-space`、`character-motor`、`interaction-reach`、`probe-gather-reach`、`neon-roof-access`、`walk-deck-fit`均exit0。probe明确记录`zone2_glass`运行吸附到当前有效可走面约`(-26.000, 2.704, -19.800)`并可达；这只是当前场景诊断证据，不把该坐标写回台账或改用户摆位。
- 发行闭包工具无显式输入时返回`UNEXECUTED/exit2`，证明不会用`include_filter`或缺包状态误报发行通过。

### B4 仍未签署的边界

- `visual-quick-tools`本批exit1，261 checks中20项为历史1920×1080截图尺寸夹具不匹配；不归因于Q03材质槽位，保留原始报告，待独立修正视觉夹具后复测。
- 最新视觉日志仍保留Godot的`agent_radius is ceiled to cell_size`和`Spot_zone2_glass`吸附WARNING。当前逻辑/可达性专项均exit0，但没有改变导航体素、胶囊半径或采集数据来消警告；Q04仅完成诊断与等价性证据，不签零警告。
- A08只有证据协议和纯Python反例，未执行Godot长期潜水往返、重置、多次创建销毁、对象/WeakRef/Callable真实采样；不能签零泄漏。
- D05没有当前PCK/Windows/Web发行闭包输入，平台导出、启动、动态资源全量闭包、磁盘满/权限/断电/浏览器存储、多进程同槽均未执行。
- R06许可仍有pending，R18四份`.r2-*`事务文件未删除、未覆盖主表、未裁决归档政策；不批量晋升许可，不清理事务文件。

B4本批已完成“可执行的安全子集”，未完成发行验收或设备可靠性验收。B4后最终契约门禁仍为`--sync` exit1 / 535 issues、无参 exit1 / 536 issues，未刷hash/派生索引；审计不新增B5阶段。所有证据和退出码保持可追溯，未提交或推送。

### B4 visual-quick-tools 截图尺寸夹具修复（2026-11-14）

承接SEA-QUALITY-R01/R03/R04/R05。本轮只修改`godot/tests/test_quick_tools.gd`的`save_frame`及本记录/quality账本，不改runner、Main、玩法、场景资产、用户摆位或正式存档；改前工程外10955份文件SHA256基线见`/Users/zyq/work/sea-work/b4-quick-tools-fixture-before-20261114.json`。

- 原始`20261114-114407-b4-visual-q03-20261114-583bf6/visual-quick-tools.log`为261 checks/20 failures、exit1。准确范围是1600×1000与1920×1080两组各10张，而非只1920组；上节保留为历史表述，以本节明细为准。
- runner真实启动参数为`--resolution 1280x800 --fixed-fps 60`。macOS实际窗口高度受限到928，`canvas_items`保持比例时渲染区域与请求窗口尺寸不同；`ViewportTexture.get_size()`还会额外应用stretch，亦不能直接当作读取图像的像素尺寸。最终期望值独立从`root.get_visible_rect().size * root.get_stretch_transform().get_scale()`取整计算，逐张严格断言两个维度为正且`Image.get_size()`精确相等，不从待验Image反推、不删除或放宽到任意尺寸。
- 保留每张非空/PNG保存检查、请求尺寸+land/boat+opening/open/hover/closing/closed标签，以及真实Alt、hover命中、按钮在视口内、展开/收起中间帧、closed隐藏、世界时钟/自动保存不变和潜水接纳边界断言。
- 两次过程复测保留原始失败：`20261114-121721-b4-quick-tools-viewport-fixture-20261114-b6a077`与`20261114-121845-b4-quick-tools-current-viewport-20261114-3d2cd1`均261/20、exit1，证明仅改用纹理逻辑尺寸不足以修复，未掩盖错误。
- 最终命令：`GODOT=/Applications/Godot.app/Contents/MacOS/Godot python3 scripts/run_verification.py visual-quick-tools --visual --label b4-quick-tools-render-rect-20261114 --timeout 240`；引擎及runner均**exit0**，**266 checks/0 failures**，`passed=true`、`completion_marker=true`、`unexpected_errors=[]`。真实Godot4.7.2/Metal4/Forward+/Apple M6，不是headless或模拟截图。
- 最终证据根：`/Users/zyq/work/sea-work/verification/20261114-122154-b4-quick-tools-render-rect-20261114-bb6420`；`report.json`保留命令/隔离user，`visual-quick-tools.log`逐图记录window/viewport/image，`png-size-evidence.json`列全30张绝对路径、字节数与PNG IHDR尺寸。文件位于`project/outputs/quick-tools-{1280x800,1600x1000,1920x1080}-{land,boat}-{opening,open,hover,closing,closed}.png`。逐张IHDR/标签矩阵核验exit0。

| 文件名请求尺寸 | 本机实际窗口 | viewport/PNG实测 | 张数 |
|---|---|---|---|
| 1280×800 | 1280×800 | 1280×800 | 10 |
| 1600×1000 | 1600×928 | 1484×928 | 10 |
| 1920×1080 | 1920×928 | 1649×928 | 10 |

本轮仅目检`quick-tools-1280x800-land-open.png`、`quick-tools-1920x1080-boat-hover.png`两图：对应两枚图标/文字完整，船上潜水暖金hover可见，无空白渲染；其余28张未逐图人工审阅。请求尺寸标签不等于本机完成相同原生像素分辨率验收，未覆盖不受限的1600×1000/1920×1080原生输出、Windows/Web、其他DPI/设备、用户最终美术确认或完整潜水往返。仍有`agent_radius`/`zone2_glass`警告；无预期故障白名单，无Q03同名uniform槽位冲突。发行/许可/断电/磁盘满/生命周期长期项未执行，登记头partial不变。

本轮最终治理复测：`python3 -m unittest discover -s tests/tooling -v` **87/87、exit0**；`git diff --check` **exit0**。契约按约定重新执行`--sync` **exit1/535 issues**、无参 **exit1/536 issues**，与既有B4计数一致，仍为全局条款/证据链接/资源漂移等阻断，未刷hash或写回派生索引；不得把本次视觉通过写成全工程通过。四项完整日志分别在最终证据根`tooling.log`、`diff-check.log`、`contract-sync.log`、`contract-check.log`。改前SHA基线核验除本测试与两份追加记录外其余文件不变，已有B0–B4改动全部保留，未提交/推送。

## 2026-11-14 B3/B4 文档收尾与最新工程外证据

本节只追加当前已取得证据，不改以上历史原文；发生时点差异时按各批原报告分别解释，不把后轮通过回写成首轮通过。本次仅编辑本记录、GDD及quality/asset/ocean/nav四本账本；未启动Godot、测试或runner，未执行契约checker/`--sync`，不改生产代码、资产、登记头、派生索引、许可或哈希，不删除事务文件，也不提交/推送。功能登记头维持原状态，不升级verified；quality现行R01–R05已足以承接证据分层，本次不新增spec条款。

### B3 已有安全子集与门禁

- `20261114-104347-b3-final-regression-20261114-6155e0/report.json`的10个逻辑入口全部exit0/PASS：`b3-goal-query-copy`、`b3-query-copy`、`b3-building-guards`、`building-decoupling`、`building-5m-rules`、`building-simulate`、`building-integration`、`framework-modules`、`save-seed`、`framework-integration`。默认minimal与显式full-world的management另有各自exit0报告：同目录层级`20261114-104347-b3-management-minimal-final-20261114-517f33`与`20261114-104347-b3-management-full-final-20261114-b52afa`；不是把两个profile混成一次验收。
- 已有治理31/31、架构25服务/0问题、摆位6结构/0警告及diff-check exit0，均为原批实证，本次只读回填。契约最近已记录实跑仍为`--sync` **535 issues / exit1**、无参check **536 issues / exit1**；日志见`/Users/zyq/work/sea-work/b3-contract-{sync,check}-final-20261114.log`与后续B4同值记录。最新工程外收集器和本次文档作业均未重跑契约，不能称文档追加后的新门禁已通过。

### B4 已实现范围与最近收集结果

Q03只完成共享SunnyPalette instance uniform槽位治理：主shader保留0–8，Gloss共享槽为0/3/7；D05是显式输入下的只读发行闭包审计；A08是生命周期采样证据协议及离线正反例，均不是实际发行或长期采样完成。截图夹具修复已有`20261114-122154-b4-quick-tools-render-rect-20261114-bb6420`的**266/0、engine0/runner0**；`20261114-114407-b4-visual-q03-20261114-583bf6`内room/gift/workshop入口各自exit0，整批因quick失败仍非全绿。历史261/20包括1600与1920两组尺寸错配，不与下表新首轮的航行潜水断言失败混为同一原因。

最新工程外证据根为`/Users/zyq/work/sea-work/b4-validation-closeout-20261114/`，只读核对`b4-validation-summary.md`、JSON及所引原报告；以下是已有运行产物，非本次新跑。

| 检查 | 实际结果与限定 |
|---|---|
| tooling / material params | 87/87、exit0；10份登记材质/51份材质文件、exit0；静态/合成夹具不签真实生命周期。 |
| architecture / placed / diff | 25服务/0问题、6结构/0警告、diff-check均exit0；不抵消契约535/536失败。 |
| Q04六入口 | `ground-space`37/0、`character-motor`42/0、`interaction-reach`36/0、`probe-gather-reach`诊断完成、`neon-roof-access`41/0、`walk-deck-fit`16/0；engine/runner均0，headless。报告`verification/20261114-123746-b4-closeout-q04-5e801d/report.json`。 |
| 首轮visual合批 | `verification/20261114-123153-b4-closeout-visual-e5b769/report.json`，整批runner1。quick为102 checks/2 failures、engine1、marker=false、0PNG，失败是航行潜水入口消费与先停船提示；room为engine124、marker=false、仅outside/door两PNG；均保留FAIL，不降格expected。 |
| quick独立复测 | `verification/20261114-124023-b4-closeout-independent-visual-quick-tools-58b845/report.json`：266/0、engine0/runner0、marker=true、30PNG，真实渲染。 |
| room独立复测 | `verification/20261114-124128-b4-closeout-independent-visual-room-3576f7/report.json`：0 failures、engine0/runner0、marker=true、8PNG，真实渲染。 |
| gift首轮与后续口径 | 上述123153合批runner1，但gift入口本身engine0、53/0、passed=true、marker=true、30PNG；不可写成gift引擎失败，也不可写整批runner0。用户另补充“后续独立视觉通过”；本次所读摘要尚未收录对应独立report/退出码，按用户补充证据登记，不冒填批次路径、不冒充本次重跑，亦不以旧114407报告代替后续独立报告。 |
| workshop | `verification/20261114-123657-b4-closeout-workshop-7d180e/report.json`：879/0、engine0/runner0，headless而非视觉证明。 |
| D05无真实发行输入 | `release-closure-no-input.json`：**UNEXECUTED / exit2**；无真实PCK/closure/发行根，不能签发行包、许可闭包或平台启动。 |
| A08无真实采样输入 | `a08-lifecycle-no-input.json`：**UNEXECUTED / exit2**；协议单测/合成样本不签WeakRef/Callable真实释放、稳定测量窗口或长期零泄漏。 |

独立quick/room与首轮各核对2835文件、差异0；收集器记录仓库前后10955文件变化路径为空。故这里只能登记“无改动独立复测可通过”，不能宣称首轮根因已证实、又修复了生产缺陷或已完成稳定性验收。首轮102/2与room124仍保留。摘要已记目检room-door、gift-hero-day、quick两图、独立room-inside；其余PNG只核尺寸/字节/SHA，本次未重新审图。请求分辨率标签不等于原生大分辨率通过。Q03同名uniform槽位冲突在所引日志未检出，agent_radius、zone2_glass及2D MSAA警告仍保留，不签零警告。

### 重置矩阵当前重跑与不可扩张的结论

当前`/Users/zyq/work/sea-work/b2-reset-atomic-results.json`已指向**124724单位批及124828–124832中断/恢复批**，与收集器`b2-reset-historical-reference.json`所称“本轮未运行的历史引用”分开记时点。本次只读核对矩阵及11份原报告，没有自行注入kill：unit为engine0/runner0；intent/archive/replace/commit/future五seed均**engine-9/runner1、expected_sigkill=true**，五recover均engine0/runner0。seed的accepted=true表示命中预期SIGKILL，不是普通PASS或exit0；unit/recover通过也不抹去seed真实非零。只证明所列同机、隔离user、进程中断后的恢复，**不宣称真实设备断电、目录fsync、磁盘满、跨平台或并发同槽可靠性**。

### 收尾边界与承接

B3/B4只签已取得证据的安全子集；B4仍未完成真实发行包/平台启动、完整资源与许可闭包、设备/跨平台故障和长期生命周期/性能矩阵。daily_release/export及真实A08矩阵未启动命令的项仍是UNEXECUTED、exit=null，与无输入检查器exit2区分。许可pending、资产事实冻结与R18四份`.r2-*`事务文件继续保留，禁止批量刷hash或清理造绿；本审计**没有B5**。

本节由[质量账本](../features/quality/ledger.md)、[资产账本](../features/asset/ledger.md)、[光学账本](../features/ocean/ledger.md)、[航行账本](../features/nav/ledger.md)及[GDD入口](../../GDD_V1.0.md)承接；这里只追加事实与待验边界，不新增重复所有者或状态晋升。
