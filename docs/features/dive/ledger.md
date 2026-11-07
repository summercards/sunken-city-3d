# SEA-DIVE · 潜水探索与宝箱 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-dive) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-DIVE",
  "status": "partial",
  "owner": "DiveSession / DiveAir / 单图UnderwaterWorld阶段状态机",
  "code_paths": [
    "godot/src/diving",
    "godot/scenes/underwater"
  ],
  "verification": [
    "dive-maps",
    "visual-dive-maps",
    "sunroom-underwater",
    "visual-sunroom-underwater",
    "selftest",
    "modules",
    "framework-integration",
    "decorations",
    "visual-decorations"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-DIVE-R01 | DiveAir纯模块与自检通过；真实深度画面另计 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-DIVE-R02 | 搜索独立动作，奖励通过give_resource；selftest通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-DIVE-R03 | 快照由模块全量恢复，读档稳定海面；存档与自检通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-DIVE-R04 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |
| SEA-DIVE-R05 | 已接入；逻辑与组件检查通过 | 7群各18条鱼独立组件；自主更新关闭，潜水时钟sample驱动；见本轮记录 |

## 资源与调用入口

- [godot/src/diving](../../../godot/src/diving)
- [godot/scenes/underwater](../../../godot/scenes/underwater)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

dive / surface / swim_to / cancel_navigation / to_dict / from_dict；phase_machine；exited、air_changed；give_resource 注入。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

当前入口：`python3 scripts/run_verification.py selftest modules framework-integration`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 selftest、modules 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

潜水已拆为 surface/enter/swim/exit 状态及7个独立动作；UnderwaterWorld 保留几何与内容装配，奖励回调注入。真实深度、透明渲染和设备性能仍需专项 GPU 验收。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 2026-10-27 模块框架落地

潜水已拆为 surface/enter/swim/exit 状态及7个独立动作；UnderwaterWorld 保留几何与内容装配，奖励回调注入。真实深度、透明渲染和设备性能仍需专项 GPU 验收。

新增条款 SEA-DIVE-R04 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。

2026-10-27 接口收口：公开头灯与诊断入口：toggle_lamp / uses_underwater_environment。

## 2026-10-27 场景组件细分与动物恢复

见[本轮交付与验证记录](../../development/2026-10-27_scene_component_split.md)及[组件分类目录](../../../assets/registry/SCENE_COMPONENTS.md)。运行验证与素材授权分别登记；交互请求端口不代表玩家摆放编辑器已实现。

最终补验：decorations 1589项通过；visual-decorations 1592项通过（包含独立实例、真实鱼群近景和正常上浮环境恢复）。surface 503项/30航线、自检537项通过；静态契约32功能/426源资产/317运行哈希0问题。旧水下网页同机位测试缺基准未执行，单列在本轮记录。

## 2026-11-07 按海域切换独立潜水地图

本节为当前契约，覆盖上方“UnderwaterWorld 常驻/统一几何所有者”的历史口径；旧记录与登记头完整保留，功能状态仍为 `partial`。稳定进度与共享 DiveAir 所有者改为 `DiveSession`，`UnderwaterWorld` 仅承担当前地图运行时；目录为 `godot/src/diving/dive_map_catalog.gd`，正式地图为 `godot/scenes/underwater/maps/*.tscn`。

| 对应设计条款 | 当前实施状态 | 证据 / 待核验 |
|---|---|---|
| SEA-DIVE-R06 | 源码已接入：岸上取 current_zone，船上取已安装且 Scope 启用区块的实际泊位 XZ 最近来源，全海平面分区；不是有限半径或 JSON 参考位 | `Main._dive_source_at` / `DiveSession.source_query`；运行 pending |
| SEA-DIVE-R07 | catalog 登记9个唯一 map_id/TSCN；按图组合旧 region、出生点、宝箱与鱼群，非9套新美术；zone3/4仅保留目录，不自动安装海面区块 | [九图目录与配置表](../../development/2026-11-07_dive_map_switch.md#3-九图目录与配置快照)；运行/视觉 pending |
| SEA-DIVE-R08 | preflight 后同一 Main 移出树缓存，稳定会话留树；current_scene 切到唯一 runtime，本地环境/相机/HUD接管，海面时间/天气/经营/自动存档暂停 | `DiveSession.enter_map`；失败回滚与正式生命周期 pending |
| SEA-DIVE-R09 | 上浮卸载 runtime、恢复同一 Main及原船人姿态/模式/相机/环境；共享 DiveAir 的恢复冷却跨图保留 | `DiveSession._commit_return` / `Main.resume_after_dive_map`；恢复/冷却专项 pending |
| SEA-DIVE-R10 | 根v4 `dive.found/opened`整数数组保持；zone1 0..4，其余百位基数100..800加固定局部子集；未知ID保留，读档全量覆盖 | 注册表仍注册稳定会话为 `dive`；旧档/跨图隔离/磁盘往返/直接写盘拒绝 pending |
| SEA-DIVE-R11 | 默认入口仍屏蔽；旧 underwater_world.tscn仅兼容资源，旧构建器限候选，不覆盖正式地图/Main；SunkenCity景观不动 | 范围与兼容边界已登记；不以内部enter_map可调宣称默认可玩 |

本轮接口：`configure(host)`、注入 `source_query(position)` / `give_resource`；命令 `dive / enter_map / surface / abort_to_surface / swim_to / cancel_navigation / toggle_lamp`；快照 `to_dict / from_dict`；事件 `depth_changed / zone_changed / air_changed / message / exited`；只读诊断 `runtime / active / switching / source_id / map_id`。生产不直接修改 runtime 私有状态。

上表pending保留为文档初填时的过程状态，最终结果以下节为准。

## 2026-11-07 独立地图机制最终实测

| 对应设计条款 | 最终实施状态 | 当前证据 |
|---|---|---|
| SEA-DIVE-R06 | 当前已安装启用泊位来源与岸上稳定ID测试通过；未知ID拒绝 | dive-maps312/0；手摆实际泊位查询，不写参考坐标 |
| SEA-DIVE-R07 | 9独立PackedScene/唯一map_id、23全局宝箱ID、安全入水及对应region碰撞专项通过；9张近景已目检 | visual-dive-maps322/0；旧资产组合，不宣称9套新美术 |
| SEA-DIVE-R08 | current_scene真实切换、同Main离树、海面时钟/船位暂停、重复/中间写盘拒绝通过 | dive-maps；异常退出清理亦覆盖；破损资源setup回滚仅实现，未故意注入损坏文件运行 |
| SEA-DIVE-R09 | 同实例/船人模式与姿态/相机/环境/地面投影/Terrain3D变换与top_level恢复、缺氧上浮、跨图冷却通过 | dive-maps312/0；framework-integration52/0 |
| SEA-DIVE-R10 | 原v4键/数组、旧0..4、未知ID、全量恢复、跨图进度与磁盘往返、直接busy写盘拒绝通过 | dive-maps；save-seed、save-corrupt-seed、save-protection全exit0 |
| SEA-DIVE-R11 | 默认入口仍屏蔽，未恢复zone3/4海面实例；SunkenCity位置不改 | minimum-loop147/0；placed_positions4结构/0warning |
| SEA-DIVE-R12 | 整份奖励原子入包、满包不吞奖励、本地消息/橙红告警/Esc暂停、缺氧与异常清理通过 | dive-maps312/0及visual322/0 |

最终报告：`D:/projects/sea-work/verification/20261107-190643-dive-map-switch-signed-451501/report.json`。该批9项全PASS/exit0/无非预期错误；另modules31/0、click39/0。旧综合selftest本轮511/24失败含farm_plot_a旧夹具脚本错误，未算通过；全局sync/check的资产/内容/哈希漂移不批量刷新。设备/全路线/美术差异深化仍未签，功能保持partial。[最终交付与范围](../../development/2026-11-07_dive_map_switch.md#10-最终实测与签署)。

## 2026-11-07 阳光房下独立水下区域（独立场景已验）

| 对应设计条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-DIVE-R13 | 独立总成复用旧城50组件/388实例、海床及原基座。city240×240、terrain1024×1024、water1280×1280；海面1.12、旧城根43.487442与基座原矩阵保持。城市实测P(-120,-38.65286,-120)、S(240,37.00966,240)，最高-1.64320、余量2.7632米；海床-62..-18.562597、最大深63.12米。56生态根接地最大误差1.907e-6米，TSCN已固化 | 最终`D:/projects/sea-work/verification/20261107-205426-sunroom-underwater-signed-2fa2bb/report.json`：sunroom-underwater67/0、visual89/0，均exit0/PASS、无非预期错误；11真实视角已由父线程目检。[交付及过程](../../development/2026-11-07_sunroom_underwater_region.md)。仅F6独立预览，未接玩家潜水，原9来源/默认屏蔽保持；无新增玩法/存档/碰撞。204914 minimum-loop147/1 open shop仍FAIL，无脚本错误且未做因果回退，不归因本场景也不签全工程通过；全局sync/check及性能等未验项pending。 |

## 2026-11-07 阳光房水下 r2：独立区域阻挡（已独立验收，产品未接入）

初填历史：当时三个runner运行中，结果均pending，758代理/约300万三角为预计值。当前已有独立验收证据，以下取代初填状态；R13历史与登记头保留，功能仍partial。

| 对应设计条款 | 当前实施状态 | 当前证据 / 未验边界 |
|---|---|---|
| SEA-DIVE-R14 | 逐Mesh/MultiMesh exact concave/backface、mesh＋deformation immutable缓存；最终实测758proxy/85uniqueMeshes/3115351instanceTriangles，physicsrun缓存99、visual缓存158；同精确Basis key因启动浮点拆分而缓存数不同，各角色数量/assemblies/triangles一致，50源GLB不动。Terrain3D本实例collision_mode3；胶囊0.35/1.6、每段≤0.75米/8slide、总预算2048steps/4096tests，move_and_collide sweep并支持Shift。try_set拒绝重叠越界，raw set仅fixture，F6出生延迟物理校验，水面下中心上限1.12−0.8−0.02=0.30米 | 最终232826-signed：sunroom-collision264/0，exit0，无unexpected；旧100米cast保守停靠约0.09米属精度断言不满足，非穿透/阻挡失败，≤0.75米substep修至末位<0.03米；100米请求thinwall两轴精准接触<3厘米，全部8roles至少1抽样、海床/桥下路口/斜滑/安全定位已覆盖，不外推全部表面。setup1834.253ms/load256.285ms仅单次，不签FPS/低端/连续运行。scope仍本独立scene，可供未来角色复用但未接production player/路由/存档。原9图手工solid/toplevel/位置/范围/深度保持；原9图/旧城/base/海床/原GLB70保护项最终核对由父线程回填。本任务不改Main；Main 可能被并行修改，不要求 Main 字节不变。[r2记录](../../development/2026-11-07_sunroom_underwater_art_r2.md)。 |

### 本轮 verification 与最终运行签署

```json
{
  "verification": [
    "sunroom-underwater",
    "sunroom-collision",
    "visual-sunroom-underwater",
    "dive-maps",
    "modules"
  ],
  "status": "passed_standalone_only",
  "latest_final_status": "passed",
  "final_batch": "20261107-232826-sunroom-art-r2-signed-5f3e30",
  "final_owner": "父线程"
}
```

最终报告：`D:/projects/sea-work/verification/20261107-232826-sunroom-art-r2-signed-5f3e30/report.json`：78/0、264/0、118/0，新区域460/0；dive-maps302/0、modules31/0回归333/0；总793/0，五入口全PASS/exit0、无unexpected。225915为中间历史，运行final已签署；local env/sky/material均resource_local_to_scene保护多实例。v002定向登记已成功写入4个JSON、15源/17runtime，write exit0；事务备份与旧history保留，第二次dry-run为0项变更。`check_feature_contracts.py --sync` exit1/25项，普通check exit1/28项，均为其他并行/历史漂移，不签全工程、低端/连续performance/rights/user acceptance/02b/production通过；production_route_integrated=false。

## 2026-11-08 潜水重新开放与“家园海底”（现行）

本节取代 R11 的“默认屏蔽潜水入口”；R11 历史保留。潜水在默认范围重新开放，家园海底接管阳光房附近的入水，原 9 图与目录不变。

| 对应设计条款 | 当前实施状态 | 当前证据 / 边界 |
|---|---|---|
| SEA-DIVE-R15 | `home_map()` 提供唯一 `dive_home_seabed`（`scenes/underwater/sunroom_region.tscn`，label 家园海底，`world_aligned=true`，`entry_radius=60`，`domain=Rect2(-120,-120,240,240)`，chest_id_base=900 保留但无宝箱）；锚点取 `zone1 → 太阳能木屋` 实际 `global_position`；`source_ids()` 仍 9 条 | dive-maps：家园身份/标签/场景、九图目录仍 9、近处归家园、远处仍归各自海区；原 9 图 map_id/场景/宝箱基数逐条复核 |
| SEA-DIVE-R16 | 入水同 XZ、仅避让；环 16..30 米×12 角度×路面 +6/8/10/12 米；须 12 米球形净空、头顶 16 米无楼板、某向 18~38 米楼体（目标 26 米定朝向）；先 `enter` 占点、等垂直射线打到海床才选点；不满足逐级放宽并保底可下水 | dive-maps：`entry_verified` 后断言胶囊真实净空、阶段为 swim、水深与半径在声明范围内；真实渲染入水画面已目检（旧城楼房/街道/车辆可见，不贴墙、不落广场、不入基座内腔） |
| SEA-DIVE-R17 | 复用 sunroom_region 全部内容与尺度（240×240 城、1024 海床、最深 63.12 米、388 实例、138 鱼、32 珊瑚、24 灯、192 气泡、200 悬尘、10 射光）；新增 `begin_dive` 与 enter/swim/exit 三阶段、0.55 秒可见上浮、灯/游动/上浮命令与 5 个信号；阻挡沿用 758 精确代理与 ≤0.75 米分段扫掠；氧气共享 DiveAir（入水水面下 6 米越换气带）；本地 HUD 显示家园海底·氧气·水深 | dive-maps 家园段（入水、耗氧、HUD 名称、上浮返回同实例、相机与角色姿态不变）；visual-dive-maps 335/0 真实渲染；sunroom-underwater 78/0、sunroom-collision 264/0 保证场景与阻挡未回退 |
| SEA-DIVE-R18 | 无宝箱，`to_dict()` 仍为 v4 `{found:[],opened:[]}`；不变存档键/版本；返回走同一 `_commit_return`，恢复原 Main/船人姿态/相机/环境；长潜水后只重连存活且未连接的脚本信号，Terrain3D 原生信号不重复连接 | dive-maps 存档结构断言与返回后相机/角色姿态断言；framework-integration 52/0 覆盖真实进出；此前 `Parameter "obj" is null` 与 `already connected` 两处原生报错已修 |
| SEA-DIVE-R19 | 默认范围开放 `dive/lamp/rise/descend`，HUD 潜水按钮不再置灰，角落菜单在最小循环保留潜水；`build/hook/camera/orders/salvage` 仍锁 | minimum-loop 148/0（改为断言入口可用 + 其余入口锁定，不再断言潜水锁死）；click 39/0、modules 31/0 |

最终报告：`D:/projects/sea-work/verification/20261108-055128-dive-home-seabed-signed2-00d74f/report.json`。九入口全部 exit0/PASS、无 unexpected，合计 1270 项 0 失败：dive-maps 323/0、visual-dive-maps 335/0、framework-integration 52/0、minimum-loop 148/0、modules 31/0、click 39/0、sunroom-underwater 78/0、sunroom-collision 264/0、save-seed PASS。功能仍 `partial`：低端设备、连续运行性能、全路线人工探索、用户美术终审未签；家园海底不新增宝箱或收藏内容，不把“能下水”写成完整探索玩法。[机制与踩坑记录](../../development/2026-11-08_home_seabed_and_dive_reopen.md)。

```json
{
  "verification": ["dive-maps", "visual-dive-maps", "framework-integration", "minimum-loop", "modules", "click", "sunroom-underwater", "sunroom-collision", "save-seed"],
  "status": "passed_default_scope",
  "latest_final_status": "passed",
  "final_batch": "20261108-055128-dive-home-seabed-signed2-00d74f",
  "checks": 1270,
  "failures": 0
}
```
