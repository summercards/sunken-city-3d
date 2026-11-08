# 2026-11-08 水下光学与双向无文字圆幕

[主文档](../../GDD_V1.0.md) · [Dive 规则](../features/dive/spec.md) / [账本](../features/dive/ledger.md) · [Ambient 规则](../features/ambient/spec.md) / [账本](../features/ambient/ledger.md) · [Ocean 规则](../features/ocean/spec.md) / [账本](../features/ocean/ledger.md) · [模块契约](../architecture/module_contracts.md)

## 1. 原始要求、核对顺序与本分支边界

原始要求：先核对文档功能归属与复用，再做仰视海面/深度暗光/阳光、双向日切黑圈遮加载、呼气和环境泡增鱼。已先只读 AGENTS、GDD 导航与现行修订、dive/ambient/ocean/sleep/ui 的 spec 与 ledger，再读当前源码和 runner 注册；不是先造第二套系统再补归属。

本分支仅追加设计规则、源码实现状态和最终验收 PENDING 位。只在 GDD、三功能 spec/ledger、module_contracts 的末尾追加，并新建本记录；不修改生产代码、测试、场景、资产/哈希、派生索引或 sleep/ui 文件，不运行 Godot、测试、sync/check。工作树已有并行修改，本记录不把全部 git diff 算成本分支交付。

- SEA-DIVE 当前最大 R38，本轮新增 **R39–R43**。历史已有两组 R29–R31，本轮只说明歧义，不重编号、不改历史。
- SEA-AMBIENT 当前最大 R27，本轮新增 **R28–R31**。
- SEA-OCEAN 当前最大 R25，本轮新增 **R26–R29**。
- 三功能 status 均保持 `partial`；登记头完整保留，尤其 DiveSession / DiveAir / Shared DiveRuntimeController / Map适配器 不退回单图 owner。新 runner 只在末尾关联，不重写登记头。

## 2. 功能归属与复用决策

| 范围 | 唯一职责与复用 | 不做什么 |
|---|---|---|
| 双向潜水过场 | SEA-DIVE 的稳定 Session 拥有事务，Main 注入 SEA-SLEEP/UI 原 SleepCurtain | 不造第二套幕/睡眠流程，不调用跳日，不让UI拥有加载/碰撞 |
| 幕的画法 | 复用 sleep_curtain.gd 的 cover_blank/uncover_blank 与原圆形 shader，0.85关/1.05开、无文字 | 不改睡觉有字流程或其文字停留规则 |
| 仰视与暗光 | SEA-OCEAN 共享 shader/include，Map只投影水位/深度/太阳参数 | 不各图复制光学、不叠第二层雾、不造时钟 |
| 日照来源 | Session 在Main挂起前读取既有 World/Lights/Sun 快照 | 不反写 Main Sun/DaylightRig 或光照配置 |
| 环境泡/呼气/鱼 | SEA-AMBIENT 沿用 MultiMesh、粒子shader和fish_school；控制器注入表现输入 | 不改Air、物理、阶段真值、捕捞/库存/奖励/存档 |

### 当前家园口径及保护区

家园 `water_level=101.587442`、`target_depth_m=120.0`、`viewer_min_y=-18.412558`、`lowest_seabed_y=-19.212558`、clearance=0.8，同时满足 water−120=viewer_min=lowest+0.8。入水优先水面下1.0m，家园换气带0.5m；仅浅层无净空时沿现有安全搜索兜底，不把常规入口退回街景。旧51.12/85m/常规街面入口只留历史。原九图各自水位与默认换气带保持。

用户手摆 Main/ExistingModels/Base2 与原本地布局不动，历史“388实例”等不作当前硬断言；新增鱼参考位可由用户继续调整，不覆盖原8群变换。独立 Terrain3D 高度数据仍 pending，不把水面/移动边界变更写成新海床验收。

## 3. 当前源码核对（实现状态，不是实测通过）

| 源码入口 | 已读到的接入事实 | 尚须证明 |
|---|---|---|
| `godot/src/diving/dive_session.gd:81` | request_dive接受请求、switching立即置位，deferred进入生产事务；同步dive/enter_map仍留存 | 重入拒绝、异步结果与同步兼容真实回归 |
| `godot/src/diving/dive_session.gd:218` | 借原幕到root、冻结Main，cover_blank后等待绘制，再threaded load/instantiate；等待verified/swim及准备帧后展开 | 全黑绘制早于load/碰撞、无半初始化漏帧 |
| `godot/src/diving/dive_session.gd:292` | 非headless使用frame_post_draw，headless仅process_frame；trace保留幕身份与屏障信息 | 真实全帧黑像素与独立时序观测，不能只凭trace标记 |
| `godot/src/diving/dive_session.gd:332` | 保存/恢复curtain的parent/index/focus；冻结并恢复Main及非继承处理模式子节点 | 成功/失败原实例身份及全部稳定状态恢复 |
| `godot/src/diving/dive_session.gd:479` | 返回先关幕/绘制后commit_return，再展开/还幕/解锁；失败路径另见401行 | 正常/缺氧/失败回滚、日期/耗氧不推进、无残留或泄漏 |
| `godot/src/bootstrap/main.gd:3981` / `:4459` | active/switching进入保存busy；同一SleepCurtain同时装配sleep/room/dive | 直接SaveGame.write/capture拒绝，期间不生成中间保存文件 |
| `godot/src/ui/sleep_curtain.gd:94` | cover_blank/uncover_blank清文字，沿原0.85/1.05圆幕 | 真实关/黑/开及像素圆形与输入消费 |
| `godot/src/diving/dive_runtime_controller.gd:70` / `:313` / `:393` | transition_frozen门禁；必要entry仍可准备，游动/耗氧和呼气冻结；共用控制器创建呼气组件 | 关幕到展开末帧均锁输入/Air，只有准备能推进 |
| `godot/shaders/uw_water_color.gdshaderinc:70` | 共享uw_surface_optics处理水到空气Snell窗/内反射/太阳盘与碎光；两类表面shader消费 | 近法线/掠视、随波变化、深浅/白天/零日照真实可见 |
| `godot/shaders/uw_fog.gdshader:21` / `sunroom_underwater_fog.gdshader:14` | 单fogpass，水面命中方向弱吸收，显示色/HDR链合成 | 水窗不被抹平、实体雾仍有效、远雾接缝与深度暗光 |
| `godot/src/diving/sunroom_region.gd:144` / `uw_materials.gd:90` | Map注入绝对水位与实际米制深度；缓存记住深度/水位/太阳，晚创建材质继承 | 水位变化、跨图及全材质一致，不泄漏家园参数到旧图 |
| `godot/src/diving/dive_session.gd:386` | 日照读取Main现有Sun方向/颜色/强度，注入两类Map | 零日照盘/碎光/日照beam消退，局部灯仍可读 |
| `godot/src/ambient/sunroom_underwater_atmosphere.gd:45` | configure_water更新泡顶、材质、光柱入口/位置及AABB；192泡/200尘/10beam不膨胀 | 升降水位可恢复，实际池/轨迹/像素可见且无裁切 |
| `godot/src/diving/uw_deco.gd:79` / `:251` | 旧96环境泡先分配mesh/use_colors再instance_count，每帧写变换和实例色 | 实际回读与视觉，不以节点数当可见 |
| `godot/src/ambient/diver_breath_bubbles.gd:5` / `:113` | 固定48池、mask/head世界挂点、每簇4..7、基础间隔2..3秒；单泡寿命当前3.0..4.7秒；world余迹、动态AABB和alpha回收 | 发簇/脱离移动角色/上升回收/浅水显现、暂停和Air无副作用 |
| `godot/scenes/underwater/sunroom_region.tscn:124` / `:227` | 原8群138保持；新增ShallowShoal18、MidwaterShoal22至10群178，ID08/09 | 实际Body实例/动画/入场附近鱼、无新增碰撞或捕捞 |
| `godot/src/diving/uw_deco.gd:14` / `:60` | 旧鱼FISH_COUNT=24，仍按各图既有fish_specs子集装配 | 不冒称每图固定7群、旧内容子集与材质表现回归 |

上表是只读源码快照，主线程仍在修复/运行，行号及实现若继续变化，应按最终隔离代码快照复核，不据本表签PASS。

## 4. 必须保留的失败历史

以下为本轮任务交接给出的已知过程事实，本分支没有运行测试，也未据未提供的原始报告补造路径、退出码或失败标签。

| 阶段 | 已知结果 | 处理边界 |
|---|---|---|
| transition初始解析 | Parse black，失败 | 原始run_dir/日志/精确错误位置待主线程关联；不能静默删除 |
| transition夹具编译 | Main子类引用Autoload Zones编译阻断 | 当前已读test_dive_transition使用真实Main，FailedReadySession继承Session；源码调整不等于修复已验 |
| transition真实视觉 | visual timeout | 真实渲染时序/退出码/超时原因待主线程补；headless不能替代 |
| 水下体验真实视觉首批 | 195 checks / 8 failures，FAIL | 批次/日志/失败标签待主线程补，不标通过 |
| 水下体验真实视觉后批 | 195 checks / 4 failures，FAIL | 保留与首批的演进，仍非PASS |
| 后续修复 | 正在运行，最终PENDING | 不推测计数，不拿旧5196/0或其它历史批次冒签 |

历史far-fog-edge及更早3C失败/通过也保留各自文档，不把本轮“光学实现已接”当成它们已清零。

<a id="underwater-optics-transition-acceptance"></a>

## 5. 主线程最终验收回填（PENDING，唯一签署入口）

**当前结论：PENDING。本分支只写规则和实现状态，不预签PASS。** 四个名字已在 `scripts/run_verification.py:18–21` 实际注册；下表不新增runner，不代表本分支已执行。

| 已有runner入口 | 精确批次 / report.json / 命令 | checks / failures | exit / completion / unexpected / leak | 最终结论 |
|---|---|---|---|---|
| underwater-experience | PENDING（主线程填） | PENDING | PENDING | PENDING |
| visual-underwater-experience | PENDING（主线程填） | PENDING | PENDING | PENDING；195/8与195/4仍保留为历史FAIL |
| dive-transition | PENDING（主线程填） | PENDING | PENDING | PENDING |
| visual-dive-transition | PENDING（主线程填） | PENDING | PENDING | PENDING；初始编译/timeout历史不可抹除 |

### 5.1 运行证据与代码对应

- 最终 HEAD + working_tree / 隔离副本代码对应及关键文件差异：**PENDING**。
- 四入口报告路径、真实命令、硬件/后端/窗口与PNG实际尺寸：**PENDING**。
- 成功入水/正常及缺氧返回/重复/失败回滚、同Main/curtain及处理模式恢复：**PENDING**。
- 全黑绘制先于load_threaded/instantiate/collision，verified/swim先于展开；switching持续至开幕末帧，输入/Air/日期/保存全程门禁：**PENDING**。
- 呼气固定池/世界余迹、环境泡实际颜色/上升/动态水位、原鱼保留与新增鱼/动画、同dt Air无差别：**PENDING**。
- 必要旧同步API与基础/地图回归：**PENDING**；只填写实际执行且已注册的入口与精确结果。

### 5.2 真实图像与人工审阅

| 验收项 | PNG/日志/像素差分 | 审阅人与结论 |
|---|---|---|
| home + zone1 仰视近法线Snell窗 / 掠视内反射 / time0与time2太阳随波 | PENDING | PENDING |
| 深浅水背景/实体减光、白天与零日照、头灯与设施灯 | PENDING | PENDING |
| 单fogpass远雾接缝、水面弱吸收、无整屏白膜 | PENDING | PENDING |
| 呼气/环境泡独立开关差分及浅中层鱼可读性 | PENDING | PENDING |
| 双向关幕/全帧黑/展开、加载前黑帧、入口准备后首帧 | PENDING | PENDING |

静帧不能替代连续动画/手感；低端GPU、持续性能、全路线人工探索、发行包与用户美术终审未执行时保持pending。确认报告exit、completion、unexpected/leak和实际截图后，主线程在此**追加最终签署**并给GDD/三账本末尾补精确结论，不覆写失败历史。

## 6. 文档追加与全局门禁回填

- 文档分支改动范围：八份现有文档只追加末尾，另新建本记录；sleep/ui、源码、TSCN、资产/哈希与派生索引未在本分支修改。
- 追加前换行：GDD为LF；dive/ambient/ocean spec/ledger及module_contracts为CRLF。本记录为LF；不统一重写行尾。
- 编辑工具曾连续两次在修改前备份阶段超时，确认未改变文件后，对CRLF文件使用AppendAllText末尾追加；原字节前缀/换行核查见本分支交接，不把工具成功当运行验收。
- 本分支未执行测试、sync或全局合同检查。主线程最终 sync/check 的实际命令/exit/issues与资源漂移边界：**PENDING**，不得沿用旧72/73等问题数冒签本轮。
- 本轮最终状态：**partial / PENDING**，由第5节主线程真实结果决定专项结论，不自动晋升功能verified。

### 本文档分支只读核查结果

八份现有文档逐一按追加前字节长度截取前缀并对照SHA256，全部原文前缀不变；新增后缀均保持本地基线（GDD为LF，其余七份为CRLF）。三功能新增ID在spec/ledger各出现一次且集合配对：Dive R39–R43、Ambient R28–R31、Ocean R26–R29，未重排历史重复ID，登记头字节包含在未变前缀内。限定八文件 `git diff --check` exit0；Git提示GDD将来可能按配置转CRLF，但本次实测仍为LF，未执行转换。上述仅为文档完整性核查，不是测试、sync或全局合同门禁，也不改变第5节PENDING。

## 7. 主线程最后签署（覆盖第5节PENDING，保留全部失败历史）

本轮用户三项优化已经接入原工程并完成对应功能与真实渲染专项；不是新建独立演示代替生产实现。文档委派阶段的“不改代码/未执行”仅指其职责，本节为主线程实际执行结果。三功能仍partial，不签全工程发布。

### 7.1 当前有效报告与精确结果

| 报告代号 / run_dir | 入口 | checks / failures | 结果 |
|---|---|---:|---|
| A：`20261109-023938-underwater-render-boundary-f5c046` | visual-dive-transition | 149 / 0 | exit0/PASS，真实渲染 |
| B：`20261109-030908-underwater-breath-contact-db6f99` | visual-underwater-experience | 195 / 0 | exit0/PASS，真实渲染 |
| C：`20261109-031605-underwater-regression-final-2513b4` | underwater-experience | 65 / 0 | exit0/PASS |
| C | dive-transition | 226 / 0 | exit0/PASS |
| C | dive-control | 396 / 0 | exit0/PASS |
| C | dive-maps | 329 / 0 | exit0/PASS |
| C | sunroom-underwater | 85 / 0 | exit0/PASS |
| C | sunroom-collision | 2824 / 0 | exit0/PASS |
| C | click | 39 / 0 | exit0/PASS |
| C | sleep-cycle | 42 / 0 | exit0/PASS |
| C | room | 112 / 0 | exit0/PASS |
| C | save-seed | 无checks计数 | exit0/PASS，前置种档 |
| C | framework-integration | 52 / 1 | **FAIL，second generation write** |
| D：`20261109-032433-underwater-framework-recheck-7d457d` | framework-integration | 52 / 1 | **独立复跑仍FAIL，同一写盘断言** |

A/B/C/D均位于`D:/projects/sea-work/verification/`，原始`report.json`保存命令、HEAD、working_tree、exit、completion和unexpected。A的另一项visual-underwater-experience当时195/1仍为失败，不将A整批写成PASS；B才是该项有效通过。C的framework失败也不被其它通过项掩盖。

11个已通过计数入口合计 **4462 checks / 0 failures**；另save-seed前置通过。framework-integration52/1不计进4462/0，不称整批全绿。其失败发生在潜水之前的`test_framework_integration.gd:71`第二代存档写入，非潜水切换后写盘；主线程未修改SaveGame或减弱存档保护。尝试给该测试添加错误详情时文件备份服务超时，未落修改，不冒报已诊断具体根因。该存储回归仍需独立修复。

真实环境：Godot4.6.3、Vulkan Forward+、RTX4060Ti；1280×800窗口。随后直接指定现有console EXE运行统一runner，避免CMD包装器退出码/超时子进程归属歧义，不改用户全局启动器。A/B/C运行源码的相关路径与当前版本已逐字节核对：A的Session/控制器/Main/Map/圆幕/转场测试7文件一致；B的17份核心运行文件一致。C在最终呼气修正后运行，相关行为测试无源码旁路。文档后续追加不改变运行结论。

### 7.2 行为与视觉实证

- 双向转场复用同一个SleepCurtain：合拢0.85s、全黑、展开1.05s，无新增文字。149项真实渲染覆盖家园/zone1生产路径与失败回滚，独立frame_post_draw观测全黑早于load/commit，整帧RGB近零；226项headless另覆盖关/黑/开期间排队返回和缺氧退出，不以headless代替黑帧。
- Session通过`request_dive`接受请求后立即switching，收幕期不load/instantiate；黑帧确认后才线程加载并在黑幕实例化/重碰撞。entry_verified/swim及环境/镜头准备后展开；全程输入、导航、头灯、耗氧、日期/经营、直接写盘busy门禁有效。返回恢复同Main、curtain父级/index/focus、稳定处理模式和原船人姿态，不重建Main或读档恢复。
- 修复真实渲染信号边界：绘制屏障记录后先回到普通process_frame再执行切树/导航恢复；测试仅在post-draw抓取该帧Image与元数据，将PNG编码/统计移到deferred，避免采证I/O与生产重操作占用同一绘制信号栈。旧timeout/exit-1全部保留，未统一编造成同一种崩溃原因。
- 仰视水面已启用，复用共享水下表面光学：水到空气折射窗、掠视内反射、低频波面法线、暖白日光与碎光。修正首版过大波面斜率/密集高频重复，不把水面画成青色不透明平板；绝对水深吸收使远深水面仍可辨但更暗。单WaterFogPass和Environment fog关闭保持。
- 深度减光不仅改ambient_light_energy：在SKY环境光源下还缩放天空cubemap辐照。固定灰样板在5/30/70/115m的真实ROI亮度分别约 **0.09120 / 0.08082 / 0.04239 / 0.01040**；仰视海面ROI约 **0.30625 / 0.25882 / 0.21393 / 0.12002**，均单调变暗。不开额外全屏雾/黑幕或全局体积雾，不整体压曝光以免连头灯一起压黑。
- 日照从原Main Sun只读注入；真实day1/sun0及波纹time0/2均有实际像素差，局部灯独立保留。完整昼夜各时段/天气和历史远边far-fog-edge像素阈值本轮未重签，不把这次近中深仰视通过外推为旧远景问题清零。
- 呼气固定48池、2–3秒基础间隔、每簇4–7个，冲刺节奏加快；从真实面罩前下方生成并保留世界轨迹、上升/膨胀/消散，暂停/过场不推进表现或Air。池空槽改alpha0+非奇异矩阵。浅水1m处面罩接近水线，泡在水面下形成短小呼气而非飞到空气中；soft_contact由环境泡0.45m分离为呼气0.08m，防刚离脸被完全淡没。B家园呼气开关真实变化 **300像素、peak0.04706**；zone1为 **1090像素、peak0.18431**。
- 环境泡旧图96修复分配和实例色，现有首列避开珊瑚实体，实际on/off差分通过；家园192泡/200尘/10束保留，configure_water同步真实水位、泡顶、beam与AABB，反复调用不增节点。原鱼8群138与原摆位保留，只新增浅18/中22至10群178，旧各群18→24；真实泳动、fish-on/off与无碰撞/非捕捞均验。
- 当前家园120m、水面101.587442、入水1m不回退；不改用户Main/ExistingModels/Base2/高楼或原鱼群transform。Terrain碰撞回归因该合法viewer下界高于大部分外海床，底层独立sphere物理扫掠与玩家下界拦截分别验证：不降低viewer_min、不拿移动限位当Terrain真实碰撞，也不声称玩家可到边界下方地形。

### 7.3 新增与修改文件归属

新增必要组件：`godot/src/ambient/diver_breath_bubbles.gd`（纯表现）。新增正式测试：`godot/tests/test_dive_transition.gd`、`test_underwater_experience.gd`；runner注册四个已存在入口。其余均在原文件增量接入：Session/Main/共享控制器/HUD、两类Map、UwDeco/Atmosphere、现有水下shader链及总场景Water显隐和新增鱼节点。没有复制第二FSM、第二幕、第二水雾pass或新的鱼模型，没有修改海面水材质/原鱼模型/GLB。

### 7.4 最后全局门禁及未签范围

- `python -X utf8 scripts/check_feature_contracts.py --sync`：exit1，**69 issues**；只读复查exit1，**70 issues**（另含derived feature index stale）。43features、987source assets、1422runtime hashes；主要是源/运行资源哈希漂移，包含本轮真实修改及并行/用户变更。未出现新增条款缺失/多余、破损回链或未知runner。脚本有issues时不写派生索引，因此不能说全局同步成功，不批量重签未知资产。
- 非阻断UID文本路径回退与导航体素半径警告仍保留，不谎称日志完全无warning。A/B通过项无unexpected；C的framework失败按FAIL保留。
- 未签：低端GPU、持续运行性能/帧率、全路线人工探索、完整昼夜天气、历史far-fog-edge阈值、用户美术终审、独立Terrain3D高度图和发行包。另有独立框架第二代写盘失败，不在本轮视效代码内掩盖。
- 本轮最终：用户要求的三项水下表现与双向圆幕已完成并自主专项验收，设计/账本对应条款已回填；不是全工程全部测试通过。工程外交付目录为`D:/projects/sea-work/outputs/underwater-optics-transition-20261109/`。

收尾补验：旧图在dive_begin恢复默认5m换气带，避免家园0.5m留在共享Air。`D:/projects/sea-work/verification/20261109-033631-underwater-air-band-final-4cba0b/report.json`中dive-maps338/0、underwater-experience65/0均PASS。最终通过汇总4471/0，不重复计65；框架52/1另列。表面光学、圆幕与呼气代码未变。
