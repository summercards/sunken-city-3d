# 2026-11-10 潜水可见入水与镜头过渡

[主文档](../../GDD_V1.0.md) · [SEA-DIVE 设计](../features/dive/spec.md) · [潜水账本](../features/dive/ledger.md) · [相机跨链](../features/camera/spec.md)

## 1. 需求、原因与职责

用户要求先看设计与框架，在对应功能内制作简单但有「刚扑通跳进水里」感觉的下沉，稳定点更深，镜头更细腻，完成后同步设计。

原实现有两个原因叠加：家园入口直接定位水下1米，放大后的头顶接近水面；生产事务又等到swim才展开圆幕，旧九图已有的下潜也完全被黑幕遮住。只改深度无法解决「没有入水过程」。

本次归SEA-DIVE-R44–R51、SEA-CAMERA-R17。继续只有海面ActorController与十图共用DiveRuntimeController两域。Session管理事务，Map管理入口/碰撞，控制器管理唯一四态、实际速度、角色与镜头，不新增Splash状态机。未修改任何TSCN、用户摆位、海床或资产哈希；开始工作时存在的其它并行改动不属于本次。

## 2. 现行流程与参数

1. 接受请求立即switching，海面、输入与保存冻结。
2. 原无文字圆幕0.85秒合拢，等真实post-draw全黑，才线程加载、实例化、碰撞建树。
3. 等prepared enter与entry_verified；完成选点、实际碰撞校验和初始相机构图，不预播放下沉。
4. 原圆幕1.05秒展开；人物位置、相机、Air保持不变。
5. 幕idle且不可见后，事务阶段entering，release_entry一次，玩家可见下沉。
6. 家园中心水深1.6→4.8米、1.65秒；u=clamp(t/1.65,0,1)，f=1-(1-u)^3，位移s=3.2f，向下速率v=(9.6/1.65)(1-u)^2。先快后慢、末速零、无回弹。正常浅层整段胶囊扫描无阻挡；水平避让只发生在黑幕内；街面兜底也逐候选验证完整通道。
7. 控制器由真实位移差/dt给角色动画，下沉结束清零速度、swim镜头不snap。直到swim才结束switching/transition_frozen并交还操作。

家园最终基础俯角0.16rad，入水初始偏移-0.22rad，由略仰柔和下压，避免水面边缘再次切过头部。距离6.3→7.5米、FOV76→72°，单次heave≤0.08米，无roll；目标与臂端均限制水下，候选与插值后两次0.32米球形clip保持。普通游泳/冲刺72/78°、距离4..13米不改。

一次性入水泡使用独立纯表现MultiMesh池，预算40、本轮发16颗，世界空间尾迹；swim继续更新至自然回收。不写Air、物理、奖励或存档。旧九图仍2.2秒、Y=-10终点，仅换ease-out与可见释放；家园120米、水位101.587442及v4 dive键保持。

## 3. 改动文件与接口

- `godot/src/diving/dive_session.gd`：准备与播放分离，幕完全打开后释放，swim后才解锁；可见段失败重新遮黑回滚；转场上浮请求排队。
- `godot/src/diving/dive_runtime_controller.gd`：entry_is_prepared/release_entry/set_entry_view；实际速度与入水镜头、一次性效果；snapshot增加准备/进度/释放与效果诊断。
- `godot/src/diving/dive_entry_effect.gd`：新轻量世界空间入水气泡，不自主推进。
- `godot/src/diving/sunroom_region.gd`：1.6→4.8米连续碰撞下沉、完整段预检、选点后一次初始视图提交。
- `godot/src/diving/underwater_world.gd`：旧九图准备/进度查询与ease-out，不改原内容或终点。
- `godot/tests/test_dive_transition.gd`：opening冻结、可见入水、真实关键帧、实际速度、相机连续、尾迹回收、排队返回及readiness/释放后双失败回滚。
- `godot/tests/test_dive_maps.gd`：家园完整胶囊扫掠、固定步曲线、零残速与4.8米目标。
- `godot/tests/test_dive_control.gd`、`test_underwater_experience.gd`：把旧「单tick立刻swim」夹具改为完整入水，不放宽实际氧气或3C断言。
- GDD、dive/camera spec与ledger、`docs/architecture/module_contracts.md`追加现行规则和跨功能契约，保留全部历史/登记头。

## 4. 过程与失败历史

- 首次验证发现本机当前环境不解析引擎命令，使用已有安装的4.6.3绝对路径通过GODOT环境变量给原runner，不改runner路径或全局设置。
- `20261110-231336-dive-entry-core-0f0350`失败：controller `entry_view` 无法从Variant状态推断bool，连带地图装配失败、超时；已明确类型，不隐藏失败历史。
- `20261110-232015-dive-entry-core-r2-8d1a4a`：dive-maps、dive-transition、underwater-experience通过，dive-control396/1为旧单tick假设；改为完整1.65秒固定步后复验。
- `20261110-232408-dive-entry-regression-3f55f8`：13项含前置均PASS/exit0/unexpected=[]，潜水、碰撞、相机、框架与存档通过；这是精修前结果，不代替后续镜头/兜底修正的专项实测。
- `20261110-232408-dive-entry-visual-a13961`：两个真实入口通过，21张入水帧已目检。进一步发现正前水面边缘仍穿过角色投影，遂将最终俯角调为0.16rad；并修复entry_verified设置晚于set_entry_view导致opening可能残留相机阻尼、街面候选缺完整段过滤两项边界。

## 5. 最终运行验收

所有运行经`scripts/run_verification.py`工程外副本，在Autoload前隔离user://，不使用真实玩家存档。最终三批报告均位于`D:/projects/sea-work/verification/`：

- A：`20261110-233501-dive-entry-polish-core-cc526e/report.json`
- B：`20261110-233501-dive-entry-polish-visual-6a99e7/report.json`
- C：`20261110-233926-dive-entry-final-integration-222f98/report.json`

| 批次 | 入口 | 实测 | 退出码 / 状态 |
|---|---|---:|---|
| A | dive-transition | 500/0 | 0 / PASS |
| A | dive-maps | 857/0 | 0 / PASS |
| A | dive-control | 396/0 | 0 / PASS |
| A | sunroom-collision | 2824/0 | 0 / PASS |
| B | visual-dive-transition | 404/0，真实渲染 | 0 / PASS |
| B | visual-dive-control | 403/0，真实渲染 | 0 / PASS |
| C | underwater-experience | 179/0 | 0 / PASS |
| C | sunroom-underwater | 85/0 | 0 / PASS |
| C | camera | 14/0 | 0 / PASS |
| C | modules | 31/0 | 0 / PASS |
| C | minimum-loop | 112/0 | 0 / PASS |
| C | framework-integration | 52/0 | 0 / PASS |
| C | save-seed / save-corrupt-seed / save-protection | 种子、坏档种子与保护均通过 | 各0 / PASS |

12个计数入口共5857项、0失败，另3个存档入口通过；15项均exit0/PASS、unexpected_errors=[]，无非预期脚本错误或资源泄漏报告。导航体素精度WARNING仍属框架既有提示，不计作实测故障。

核心验证包括真实黑帧先于load/core、opening位置/Air/相机Transform和FOV固定、幕完全不可见才释放、完整下沉与实际速度、持续按前进/冲刺不能偷跑、写盘与capture拒绝、进入swim零残速、首个实际swim相机帧连续、已有入水尾迹在swim自然归零、重复请求/排队上浮/缺氧返回、readiness失败和可见段释放后失败均恢复同Main/原幕，且Air全字段回滚。家园正常夹具完整胶囊扫掠与逐段净空实测；街面兜底已按候选完整段过滤，但未故意封死整座浅层并遍历所有兜底几何，不冒称全分支空间穷举。

设计承接补验：DIVE/CAMERA设计条款集合与账本条款集合逐项相等，`git diff --check`通过，原登记头/历史完整保留。

真实入水21张PNG覆盖物理时间0.00→1.6667秒；记录中心从`[3.066625,99.987442,20.536751]`到`[3.066625,96.787537,20.536751]`，水平零偏移、终点实际水深4.799905米，约等于4.8米（运行采样点，不是布局位置硬规则）。首帧/中段/末帧及四格图已目检：水面投影边缘逐渐上移，最终位于头顶上方；角色俯身后舒展，入水泡留在身后上浮，无相机遮挡或可见穿模。动态WebP按真实物理时间重放，末帧额外停0.95秒；HTML可播放/暂停与逐帧查看，不是离线模型生成视频。

运行结束时5个核心脚本与B批隔离副本逐字节一致；收尾仅将部分LF文件恢复仓库CRLF行尾，统一行尾后内容仍完全一致，无逻辑改动。复现命令（GODOT环境变量指向现有4.6.3安装）：

```text
python scripts/run_verification.py dive-transition dive-maps dive-control sunroom-collision --label dive-entry-polish-core --timeout 300
python scripts/run_verification.py visual-dive-transition visual-dive-control --label dive-entry-polish-visual --timeout 300
python scripts/run_verification.py underwater-experience sunroom-underwater camera modules minimum-loop framework-integration save-protection --label dive-entry-final-integration --timeout 240
```

交付位于`D:/projects/sea-work/outputs/2026-11-10_dive_entry/`：`dive_entry_review.html`、`dive_entry_preview.webp`、`dive_entry_contact_sheet.jpg`、`dive_entry_final.png`、`preview_manifest.json`。

全局门禁实际执行：`check_feature_contracts.py --sync` exit1/79问题；紧接只读check exit1/81问题，摘要/派生索引同步受阻。包括SEA-ASSET条款承接、并行SEA-WORKSHOP状态/入口/缺资源，以及源/运行资源哈希漂移；`sunroom_region.gd`也是本轮实际改过的已登记脚本，哈希待定向重签，不能把全部漂移都归为既有。没有SEA-DIVE/SEA-CAMERA新增条款缺行或未知验证入口。没有批量刷新未知哈希，原始输出保存在交付目录的`feature_contract_sync.log`及`feature_contract_check.log`。功能专项完成，但不称全工程资源门禁通过。

## 6. 未签范围

低端GPU、持续性能、全路线人工探索、全部碰撞三角面、独立Terrain3D海床高度图、用户美术终审未签。旧资源哈希/资产来源门禁不批量重签；本功能专项通过不代表全工程资源门禁通过。动态预览只来自本轮真实生产入水帧，不是离线生成动画或玩家手动操作录像。
