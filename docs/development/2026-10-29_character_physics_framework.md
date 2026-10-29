# 正式角色碰撞、三维空间与表现框架交付

日期：2026-10-29。关联SEA-MOVE-R01/R02/R04/R08–R13、SEA-WORLD-R12、SEA-CAMERA-R09、SEA-INTERACT-R11、SEA-SAVE-R08。按用户要求直接改正式系统，不制作样板楼或正式楼梯；保留当前场景内容、操作、玩法数值和经营规则。

## 范围与实现

输入是包含自由建造未提交工作的工作区，不是单独HEAD。改造前代码快照位于 `D:/projects/sea-work/verification/20261029-184001-movement-pre-physics-baseline-077ded/project`，当时HEAD为cbffe47c64254818c192bd92f90f7d16e2ce5508。本次不提交/推送，不回退其它工作。相对输入的正式代码/场景变更清单及前后SHA在 `D:/projects/sea-work/audits/2026-10-29-character-physics/runtime_changed_from_input.json`。

- Character继承独立CharacterMotor/CharacterBody3D，单胶囊半径0.22m、高1.30m；人物层512，只碰人物地面层256。行走以move_and_collide扫掠执行，保留2.3m/s、+Z正面、指数12转向、点击取消和上下船父节点规则。生产只从Main物理帧推进控制器，渲染帧不重复tick。上船/潜水关闭陆地碰撞，岸上恢复启用；无直接写position的行走兜底。非有限输入不交给物理引擎。
- ZoneScene装配GroundSpace，读取现有WalkArea矩形/多边形作为稳定迁移输入，派生地板、外缘/洞口阻挡及NavigationServer3D私有导航。可选surface_triangles提供三维坡面/重叠楼层；area_at、surface_point、surface_normal按三维位置解析地面。现有正式场景不新增楼层内容，隔离内存夹具验证上下楼与坡道能力。
- 动态平台的矩形已按0.22m半宽计算角色中心域，导航不重复内收；物理支撑补回宽度后，从并集统一生成边界，接缝不加墙、洞口保留。原先逐墙移位会把端头伸进合法窄路，已由真实DIY搬移复现并修复，增加窄中心通路的实体胶囊专项防回归。
- 静态三维表面烘焙角色净空；动态平台用稀疏坐标分割生成精确导航，不烘焙平台之间整片海洋。私有map/region同步更新并清理RID，保留NavigationMesh引用，未变几何按签名跳过重建。建造通过原geometry_changed回调刷新，BuildingService/BuildingSpace/BuildingWorld、费用和通路规则未改。
- 点击/路径保留真实Y；接近按三维操作点判可达，Interactor通过注入reachable_query过滤，结算仍由原服务执行。世界存档适配按原XYZ选择0.5m内表面，不按XZ首层覆盖Y；version4、必填字段和恢复事务不变。follow镜头跟随真实高度，manual及全部原镜头数值保持。
- 角色表现增加register_action/play_action/cancel_action、进度快照和开始/完成/取消事件，token区分重复动作。原7份sampler、农作1.1秒曲线和play_farm_action兼容入口保留。未来收菜/工具/查看动作可注册sampler及时长；表现信号不支付、不发奖励、不写作物或推进模式。
- 按用户追加要求，碰撞按用途配置：蔬菜、花草、纯装饰与种植模型没有被自动加模型碰撞。新增独立ActorCollisionBody组件代理，blocks_actor可启停简单碰撞，专项验证实体由阻挡变为可穿过。地板/布局通路/承载与物体显示不是一份状态；当前培养土占地仍由原建造通路规则拥有，本轮不暗改该规则或把所有可见网格当实体。

Main仅接线；Farm、CropCatalog、Inventory、Orders、DailyShipping、BuildingService、BuildingSpace、BuildingWorld、Boat、WaterNavigation、BlockerSet、HUD、水面/光照与SaveGame/SnapshotRegistry规则都保持输入内容。main.tscn只改既有Explorer原生类型，路径、父节点、Transform、模型及其它实例不动。生产源码变更局限角色、陆地导航、ZoneScene及必要的镜头/交互/装配适配。

## 验证与证据

全部Godot执行经过 `scripts/run_verification.py`，Autoload前复制代码/场景并隔离用户目录；Godot4.7.2、Python3.14.2。headless只签逻辑/结构/物理数值；visual-*使用真实Forward+和RTX4060Ti。截图另行查看，不以headless作画面证据。真实玩家槽位未改。

机器摘要：`D:/projects/sea-work/audits/2026-10-29-character-physics/verification_summary.json`。各轮report.json保留逐项退出码、完成标记、引擎错误、渲染类型、命令和用户目录。

主要证据（以下目录位于 `D:/projects/sea-work/verification/`）：

| 轮次 | 证据目录与范围 |
|---|---|
| 广泛逻辑 | 20261029-224200-physics-final-logic-4d419c |
| 原输入对照 | 20261029-224220-physics-original-baseline-e16605；management另跑20261029-224601-physics-original-baseline-a30829 |
| 最终针对性专项 | 20261029-225355-physics-final-targeted-56e5b4，角色/表现/空间/登陆/建造/跨进程恢复全部退出0 |
| 选层与存档 | 20261029-224449-physics-height-save-9015f9，10项退出0；验证上层保存恢复、坏高度拒绝且经济不变、镜头高度及隔层交互 |
| 碰撞开关 | 20261029-225754-physics-optional-component-e4ff47，角色碰撞及空间专项退出0 |
| 真实渲染 | 20261029-224508-physics-final-render-c22a0d；修复后DIY通过20261029-225301-physics-boundary-union-2fac93；最终复测见机器摘要 |
| 视觉原输入对照 | 20261029-224634-physics-original-baseline-ce2828 |

最终补记：最新运行代码的角色/空间/高度存档/表现/建造/登陆/朝向8组专项在`20261029-225946-physics-delivery-logic-e5ed19`全部退出0；最终DIY真实鼠标/键盘28项在`20261029-225836-physics-final-diy-392d85`退出0。`20261029-225529-physics-final-visual-acceptance-f8a484`中的离岸建造、行走及最小循环退出0，DIY初次布局失败/超时保留为失败，后续明确单项复测通过。已目视查看最终DIY完成图。7组旧失败的逐条标签与输入基线完全一致，机器摘要记录same_failure_lines=true。

结构收尾：check_architecture.py退出0（15个独立规则/存储服务、0问题）；check_feature_contracts.py --sync及随后无参数检查均退出0（35功能、459源资产、392运行资源哈希、0问题），没有批量接受未知哈希。git diff --check退出0。最初文档检查曾缺相机/交互新增条款的账本表格行，已补齐后通过；最终检查输出及退出码见同目录final_checks.json。

已通过：胶囊真实挡墙/长步扫掠/贴坡/取消、生产单一物理驱动、角色状态切换、上下重叠选层、连通坡道的正式控制器实际行走、不连通拒绝、动态地板与洞口/窄路、移除清理、表现动作生命周期，以及walk-facing102项、walk-deck-fit16项、rope-bounds14项、dock-seed21项、board-click12项、building-integration39项、building-ocean30项、building-approach18项。modules、farming、camera、minimum-loop、sleep-cycle、save-protection及building-open跨进程恢复也通过。逐轮计数以摘要为准。

真实渲染已查看往返行走、最小生活场景和离岸平台图；visual-minimum-loop、visual-walk-facing、visual-building-ocean通过。visual-building-diy修复后28项通过，覆盖真实鼠标选配方、精细/旋转输入、到位施工、跨板搬移保留作物及空物件退款。

### 原有失败保留

默认最小范围的以下失败在输入快照可复现，未为放绿修改业务或删除断言：framework-modules1项旧海域边界；management4项旧解锁/仓库；click3项旧流程；surface8项（仍执行30条有向航路）；selftest25项；framework-integration1项将[999,1,999]远海当作非法位置。当前失败标签与基线逐项对照见机器摘要。

visual-plot-shipping是61项/42失败，输入快照同为61项/同42失败，首批为原六格可选性/入口，后续依赖链失败。本轮未改这份旧脚本，不能以最小循环通过覆盖它，也不宣称全部真实种植出货UI已验收。

### 过程失败与限制

施工中曾有依赖编译、add_faces绕序导致空导航、map/region同步、原地登陆绕点、物理安全余量追点、手动tick未等待物理更新等失败，均修复后复测，旧日志保留。DIY曾出现初次GUI布局未稳定导致选按钮失败及超时，测试增加可见布局等待和安全失败判断，未删业务判据。静态烘焙agent_radius按0.05m体素向上量化的引擎WARNING保留；物理胶囊仍0.22m，动态中心域不二次烘焙侵蚀。

唯一已有预期ERROR是selftest故意坏JSON的精确Parse JSON诊断，由runner单列。其它引擎错误即使exit0也判失败。没有以历史绿项代替本轮运行。

未执行：发行导出/目标设备、超大布局长时性能、正式多层房间内容、真实台阶抬阶、竖直梯子/电梯/跳跃及新动画内容。此基础不等于这些玩法已完成。

## 后续扩展

新增普通地面/楼层/坡道由稳定场景声明三维表面，GroundSpace统一派生；楼梯可用坡面代理，真实台阶另需抬阶策略。新增交互物优先声明同层approach_points，命令由所属业务执行；新增动作注册sampler及时长，取消后不能依赖旧完成信号继续业务。纯表现模型默认不需碰撞，实体代理按用途显式配置；新玩法仍须主文档条款与独立账本。
