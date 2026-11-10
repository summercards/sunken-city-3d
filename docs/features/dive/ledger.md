# SEA-DIVE · 潜水探索与宝箱 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-dive) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-DIVE",
  "status": "partial",
  "owner": "DiveSession / DiveAir / Shared DiveRuntimeController / Map适配器",
  "code_paths": [
    "godot/src/diving",
    "godot/scenes/underwater"
  ],
  "verification": [
    "dive-control",
    "visual-dive-control",
    "dive-transition",
    "visual-dive-transition",
    "sunroom-collision",
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

## 2026-11-08 家园海底第三人称、独立布局与 35 米深度

| 对应条款 | 当前实施状态 | 当前证据 / 边界 |
|---|---|---|
| SEA-DIVE-R20 | `DiverVisual` 纯表现层复用 Character/build/set_diving/swimming_action；ViewerBody仍唯一碰撞权威；潜水瓶/面罩可见；第三人称相机距5.5m、高度1.0m，射线避障；F6非潜水预览不接管 | dive-maps 326/0 覆盖角色节点、潜水可见、深度契约；visual-dive-maps338/0 实拍目检角色/装备/第三人称构图 |
| SEA-DIVE-R21 | sunroom_region改用本地 editable layout：sunken_city_layout、sunken_seabed_layout、solar_cabin_submerged_base_layout；Main/shared场景未替换；旧城组件仍共享，布局可手动编辑 | sunroom-underwater79/0 姿态/实例/本地布局包装检查；shared Terrain3D 数据明确 pending，不冒称独立高度图 |
| SEA-DIVE-R22 | viewer_min_y=-33.88、lowest_seabed_y=-34.68、water_level=1.12、target_depth_m=35；低于边界旧城视觉保留，真正独立 Terrain3D 高度图后续制作 | dive-maps 326/0 深度契约断言；sunroom-collision264/0 真实阻挡仍通过；35m是可游边界契约，不是新高度图验收 |
| SEA-DIVE-R23 | 角色深度驱动吸收；单一WaterFogPass；本地palette深度吸收/焦散；beam 16-step深度挡墙、软边、远景fade；192泡/200尘/10束保留；未改共享水/环境/原9图 | sunroom-underwater79/0、visual-dive-maps338/0；参考官方Volumetric Fog/FogVolume、GPUParticles3D、Sky shader与depth/Fresnel/caustics资料；低端/连续性能未签 |

最终专项报告：`D:/projects/sea-work/verification/20261108-123311-home-seabed-thirdperson-final-d703fe/report.json`，九入口全PASS/exit0/无unexpected，合计1241/0：dive-maps326、visual338、framework52、minimum112、modules31、click39、sunroom-underwater79、sunroom-collision264、save-seed PASS。第三人称实拍已确认角色/潜水装备/楼房/街道/翻倒巴士/射光可见。完整机制与未验边界见 [开发记录](../../development/2026-11-08_home_seabed_and_dive_reopen.md)。
## 2026-11-08 水面抬高 50 米、可游 85 米与雾/环境对齐

| 对应条款 | 当前实施状态 | 当前证据 / 边界 |
|---|---|---|
| SEA-DIVE-R24 | 水面 1.12→51.12（Water Mesh 同步），几何零位移；旧城街面约 19 米水深变 69 米；target_depth 35→85，viewer_min_y 仍 −33.88（51.12−85 与 −34.68+0.8 双重成立）；运行时中心最高 50.30；asset_version v003，metadata 记 depth_basis/city_deepened_by_m | `tests/test_sunroom_underwater_region.gd` 80/0 断言水面 51.12、最深 113.12 米、target 85、viewer_min −33.88；Main／原 9 图／catalog／388 实例／海床高度数据未改 |
| SEA-DIVE-R25 | `entry_street_y=-18`＋`entry_rise=10`，入水占位取街面层；`_entry_spot` 路面搜索同引用；选区判据不放宽 | 同上 80/0；未在真实渲染下重跑入水落点目检，本轮改为逻辑层验证 |
| SEA-DIVE-R26 | 雾改指数式 `1−exp(−(d×density)^1.8)`、density `mix(0.026,0.012,smoothstep(65,210,depth))`；背景/水面/终端雾统一 `uw_gradient_display(SCREEN_UV)`；删方向渐变、水平分层、XZ 边缘吸收；环境光回 SKY 双色 `1.9/π×(1−deep×0.6)`；glow/SSAO 关、方向光 0、FOV 55；palette 去深度染色保留焦散 | 与 zone1 同式同参数（30 米处 0.48）；真实渲染器加载无着色器编译错误；共享水材质/world_env/原 9 图未改 |

边界：本轮只跑本场景本地专项 80/0 与真实渲染器加载，**九入口批量回归（dive-maps／visual／minimum-loop 等）未重跑**，不继承历史 1241/0 作为本次证据；低端 GPU、连续运行性能、全路线探索与用户美术终审仍未签。深度参照仍是共享 `res://terrain/sunken_seabed`，独立 Terrain3D 高度图继续 pending。

## 2026-11-08 家园海底：回字型深沟高楼环（外圈已带参考位）

| 对应条款 | 实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-DIVE-R27 | `sunken_city_layout.tscn` 新增 40 个 2× 高楼实例，**沿矩形四边直线摆放**：外框半宽 112 m／每边 7 个（间距 37.33 m）共 24 个，内框半宽 72 m／每边 5 个（间距 36.00 m）共 16 个，沟宽 40 m。每条边 X 或 Z 严格共线，朝向只取 0/90/180/270 且朝框内，无抖动。行内最大平面重叠 0.83 m。**一栋原有实例都不删**（位置归用户）。地面块 24 m 见方，40/40 槽位落在真实街面上 | 40/40 `ground_ok`；楼顶露出水面 −22.3 ~ +49.8 m；新增 6.42M 三角面，整城约 2.46M → 8.9M。`sunroom-underwater` 83 项 1 失败：生态接地最大漂移 2.4160 m，为改动前既有（布局回滚快照实测同样数值，`20261108-181727-preexisting-drift-63cb5e`）。`sunken-city` PASS 33928/0，`water-layer` PASS 1613/0。[交付记录](../../development/2026-11-08_sealed_buildings_and_canyon_ring.md) |
| SEA-DIVE-R28 | 新沟壁节点 `tall_*` 不参与生态接地：`_build_surface_index` 跳过它们，珊瑚与设施灯只贴旧城街面与坡地，避免被抬到塔顶 | 同上；`sunken-city` 回归 PASS 33928/0（`20261108-182329-scity-sealed4-f10c7b`） |

边界：44 个高楼位置是**参考位**，等用户手工摆完后按实际 transform 更新，不回退参考值（AGENTS #12）。新增约 9.2M 三角面，整城约 2.46M → 约 11.7M，未做 LOD；帧率、显存与低端 GPU 未测。参考图商业权属仍 pending。

## 2026-11-08 统一潜水 3C：当前承接与主线程待验

本节覆盖登记头及历史章节中“单图 UnderwaterWorld 阶段/动作所有者”的运行口径，保留登记头、历史原文与历史 PASS/FAIL。`status` 仍 `partial`；当前所有权为 **DiveSession（事务/进度/共享 air 持有）+ Shared DiveRuntimeController（十图统一潜水 3C）+ Map 内容/空间适配**。海面/陆地 ActorController 独立，不增加第三套状态机。R27/R28 已占用，本次新增 R29–R38，不修改既有条款。

| 对应设计条款 | 当前实施状态 | 证据 / 待核验边界 |
|---|---|---|
| SEA-DIVE-R29 | 源码已接家园与旧九图同一 `dive_runtime_controller.gd`，共用 surface/enter/swim/exit；海面 ActorController 不参与潜水内部推进 | 已读控制器及两类 Map 适配；运行最终 PENDING，不借历史地图/框架 PASS |
| SEA-DIVE-R30 | Map 提供内容/入口/位置/碰撞/route/camera_clip/env/explore；phase/phase_machine 转发控制器，旧测试兼容不能继续驱动旧 3C actions；search_action 仅探索内容 | 两类 Map 与旧 states/actions 源核对；无双 tick/双 owner、卸载无循环泄漏的当前复测 PENDING |
| SEA-DIVE-R31 | Session 事务切图/同 Main 身份恢复、v4 found/opened、稳定/未知 ID、奖励原子和共享 air cooldown 继续有效；控制器耗氧与 Session 海面恢复分时推进 | 已读 DiveSession；坏入口回滚、跨图进度/冷却、直接写盘门禁、满包/重复奖励新回归 PENDING |
| SEA-DIVE-R32 | dive_ InputMap：WASD+arrow、Q/Ctrl下潜、E/Space上升、Shift加速；4.2/7m/s，指数 tau 0.22/0.16/反向0.13s；右键仅环视 | 控制器常量/输入/实际 move 回传核对；behaviour 暂报 [403 或 396]/0，精确批次与最终签署 PENDING |
| SEA-DIVE-R33 | 左键 release≤8px 且未拖过阈值才点击自动游；无路拒绝/受阻停止，滚轮4..13m默认7.5m | 源码已接；真实鼠标拖拽/短点与碰撞路线复测 PENDING |
| SEA-DIVE-R34 | FOV72→78、pitch[-1.1,1.15]、yaw tau0.07、主体位移继承/前视0.10s、防墙0.32m立即收回/缓出/最终clip | 已核对 update_camera；真实近墙/弯曲碰撞与镜头插值专项 PENDING；curved collision3448/42保持FAIL历史 |
| SEA-DIVE-R35 | 独立 Character 实例复用模型，碰撞后实际速度驱动 float/cruise/sprint、升降pitch/turnbank；入水隐藏hat显示mask、退出恢复帽子；海面动作不改 | 已读 Character/set_swim_motion/swimming_action；外观/装备与海面动画隔离实测、截图审阅 PENDING |
| SEA-DIVE-R36 | 共用 dive_map_hud 墨绿半透明板+奶油按钮、氧气bar/深度/状态/hint/Esc；Session命令与只读展示边界保持 | 已读 HUD；初批click39/0不等于PASS（resource leak）；暂停不耗氧/继续/上浮及真实UI新验 PENDING |
| SEA-DIVE-R37 | 本批不改水面51.12/85m/viewer_min-33.88、手摆layout/Base2/40高楼；历史388不作当前固定断言；独立海床数据仍pending | 仅文档追加，无场景/资产写入；当前布局数量和变换由主线程按TSCN实测，不回退参考位 |
| SEA-DIVE-R38 | 本批不签运行PASS；初批零断言失败但resource leak导致FAIL，修复中；弯曲碰撞失败历史不抹除 | [开发记录第5节](../../development/2026-11-08_unified_dive_3c.md#unified-dive-3c-acceptance)主线程精确回填最终报告/计数/exit/unexpected/leak与签署 |

### 当前已知结果（过程历史，不是最终通过）

- behaviour：[403 或 396]/0 为待核对的过程计数，实际 runner 入口、报告和精确数量 **PENDING（主线程回填）**，不选择其中一个冒充最终数。
- 初批 dive-maps326/0、click39/0、framework-integration52/0：断言零失败，但 **resource leak 导致 FAIL，正在修复**；不能按断言数写“全部通过”，也不借用上方同数字历史 PASS。
- curved collision：**3448/42，FAIL 历史保留**；修复后的新批次/精确结果 PENDING，不能宣称已通过。
- 本分支未运行 Godot/真实渲染，未签设备、连续性能或用户验收；最终运行签署统一回填开发记录第5节，回填后再在此**追加**最终报告与状态，不改旧失败历史。全局只读合同检查及范围/换行核对回填开发记录第6节；`--sync` 因会写范围外派生索引而留主线程执行。

[本轮源码定位、契约与待回填清单](../../development/2026-11-08_unified_dive_3c.md)。

## 2026-11-08 统一潜水 3C 最终验收回填

| 对应条款 | 当前实施状态 | 最终证据 |
|---|---|---|
| SEA-DIVE-R29–R36 | Shared DiveRuntimeController 已覆盖旧九图与家园；统一四阶段、输入、实际位移、第三人称广角镜头、角色动画、氧气、HUD；海面 ActorController 保持独立 | `D:/projects/sea-work/verification/20261108-202515-dive-unified-final-edbd96/report.json`：dive-control 396/0、dive-maps 326/0、visual-dive-maps 338/0、click 39/0、framework-integration 52/0、minimum-loop 112/0、modules 31/0、keyboard-control 30/0、control-feel 31/0、character-motor 42/0；真实渲染入口 visual-dive-maps exit0/PASS |
| SEA-DIVE-R31 | Session 同 Main 身份恢复、跨图共享 air/cooldown、v4 进度与奖励流程未回退 | 同批 `save-seed` PASS；dive-maps/framework-integration/minimum-loop 全部 exit0、无 unexpected |
| SEA-DIVE-R37 | 家园水面 51.12、可游 85m、viewer_min_y -33.88、Base2/用户手摆布局与40高楼保持；生态接地按当前真实支撑验收，不再用历史启动前 Y 漂移硬断言 | `sunroom-underwater` 83/0、`sunroom-collision` 3313/0；当前批次没有改场景手摆位置；独立 Terrain3D 高度图继续 pending |
| SEA-DIVE-R38 | 本批统一 3C 最终通过当前专项；旧 curved collision 3448/42 作为历史失败保留，不覆盖旧证据 | 最终批次共列 12 个入口，全部 exit0/PASS、无 unexpected；真实截图与日志在同一 run_dir。低端 GPU、连续运行性能、全路线人工探索和用户美术终审仍 pending |

最终结论：统一潜水 3C 的功能专项验收通过；功能整体仍为 `partial`，不把专项通过扩展为全工程、低端设备或生产发布签署。

## 2026-11-08 统一潜水3C最后签署（覆盖上方中间批次）

当前有效报告：`D:/projects/sea-work/verification/20261108-205037-dive-unified-signed-2f2292/report.json`；HEAD `842e2e07ed1ee78f2831a42c2ad29f0bc694e145`加报告中的工作树。13个计数入口共5196/0，连同save-seed前置共14项均exit0/PASS、unexpected_errors=[]。核心14文件与隔离快照逐字节一致。

| 对应条款 | 最后实施状态 | 当前证据 |
|---|---|---|
| SEA-DIVE-R29 | 海面/陆地一套ActorController，十图潜水同一Shared DiveRuntimeController；不是三套 | dive-control396/0、visual-dive-control403/0、dive-maps326/0 |
| SEA-DIVE-R30 | Map为内容/空间适配，输入、潜水FSM/运动意图、耗氧、镜头/动画统一所有者；无旧3C双tick，卸载引用释放 | 同批dive-maps、framework-integration52/0、click39/0，无unexpected |
| SEA-DIVE-R31 | 稳定Session、同Main恢复、v4进度及未知ID、原子奖励、共享air/cooldown保留 | dive-maps326/0、framework-integration52/0、minimum-loop112/0、save-seed PASS |
| SEA-DIVE-R32 | WASD/方向键无需右键；QE/Space/Ctrl、Shift及速度惯性统一 | 巡航4.1986m/s、冲刺6.9926m/s、固定步刹停1.0563m；操控两入口通过 |
| SEA-DIVE-R33 | 短点/拖拽区分，安全路线拒绝、手动取消、滚轮4..13m | dive-control396/0、visual-dive-control403/0，旧九图与家园均覆盖 |
| SEA-DIVE-R34 | 72°广角/冲刺78°、可调俯仰、防墙回缩与缓出、无roll | 真实渲染visual-dive-control403/0、visual-dive-maps338/0；sphere clip与实际墙面验证 |
| SEA-DIVE-R35 | 实际速度驱动悬浮/巡航/冲刺、升降与转向，独立潜水实例/装备生命周期 | 操控测试、真实渲染及character-motor42/0；未挪用海面角色 |
| SEA-DIVE-R36 | 十图共用墨绿/奶油HUD，氧气/水深/状态/键位/暂停/返回 | 两真实渲染入口及click39/0；生产家园与旧图已审阅 |
| SEA-DIVE-R37 | 保持水面51.12/85m/viewer_min-33.88、用户手摆layout/Base2/40高楼；修正入水点选在真实街区 | sunroom-underwater83/0、sunroom-collision3313/0；生产入水点(7,-10.61256,-39)，允许水平净空避让；独立高度图pending |
| SEA-DIVE-R38 | 最终专项通过，不借旧PASS、不抹除3448/42等历史FAIL | 本批14项全PASS、5196/0；modules31/0、keyboard-control30/0、control-feel31/0等回归通过。低端/持续性能/全路线人工/用户终审仍pending |

登记头owner已改为Session/Air/Shared DiveRuntimeController/Map适配器，并登记dive-control、visual-dive-control、sunroom-collision入口。全局资源门禁与派生索引同步另记，未知资产哈希不自动重签。完整签署见[开发记录](../../development/2026-11-08_unified_dive_3c.md)。

全局收尾实测：`check_feature_contracts.py --sync` exit1/72 issues，被源/运行资源哈希漂移与source index不一致阻断，未写入派生索引；随后只读检查exit1/73 issues（另含derived feature index stale）。没有SEA-DIVE条款缺漏/多余或未知测试入口，未批量重签未知资产。代码与文档diff --check exit0，行尾保持。十张生产潜水图、返回海面图和两张control取景均已审阅；静帧不替代动画/手感行为验收。本轮专项交付完成，功能partial与全局门禁限制如实保留。

## 2026-11-08 第二轮：水面 120 米与入水点在水下 1 米

| 对应条款 | 实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-DIVE-R29 | 家园海底水面 `water_level` 51.12 → **101.587442**（Water 节点同步），上街面 −18.412558 到水面正好 **120.0 m**；`target_depth_m` 85 → 120、`viewer_min_y` −33.88 → −18.412558、`lowest_seabed_y` −34.68 → −19.212558，深度契约两项仍同时成立（101.587442−120 = −18.412558 = lowest+0.8）。**「底部」口径明文取上街面**，不取最低海床台面（取最低台面则水面只有 43.6，塔顶会露出水面 57 m） | `sunroom-underwater` 83/0、`dive-maps` 328/0、`dive-control` PASS、`water-layer` 1613/0、`sunken-city` 33928/0。最高塔顶世界 Y=100.906 落在水面下 0.68 m。[交付记录](../../development/2026-11-08_surface_120m_and_entry_depth.md) |
| SEA-DIVE-R30 | 入水点从「街面 + 10 m」改为**水面下 1.0 m**（`entry_depth_below_surface`）；新增 `_entry_spot_below_surface` 只校验胶囊净空与头顶 3 m 是水，找不到才回退原街面搜索。为使「水下 1 米」真的是水下，`DiveAir` 增加可覆盖的 `surface_depth`（默认 5.0 不变，九张旧图不受影响），家园海底设 **0.5 m** | `dive-maps` 新增两条精确断言：入水深度误差 <0.05 m、水面 = 101.587442。**边界**：水下 0.5 m 内仍回氧，贴水面横游不掉氧，这是换气行为不是漏气 |
| SEA-DIVE-R31 | 雾密度上限：`region_fog_amount` 的 `region_view_depth` 参与密度时夹到 85 m，深水不再「越深越稀」。原因是这条曲线为 ≤85 m 调参，120 m 水深直接落在稀的一端，远处海床从雾里浮出来 | 远景雾连续性 0.094 → **0.051**，仍超 0.025 阈值；A/B 对照证明剩余部分与深度无关（水面回退 51.12 时同样 0.043，`20261108-220056-ab-old-water-5f200b`）。根因是雾通道写显示色、天空走 ACES 反解，两条路径差 16/255，修它要动合成顺序并波及九张旧图，本轮未做 |

边界：`visual-sunroom-underwater` 123 项 1 失败（far-fog-edge 0.051，既有问题），不据此宣称视觉通过。帧率/显存/低端 GPU 未测；120 米深沟的实际观感与入水第一帧取景仍需主人目检。

## 2026-11-08 水下光学与双向圆幕：本轮承接（partial / PENDING）

登记头 status=partial、owner= DiveSession / DiveAir / Shared DiveRuntimeController / Map适配器 原样保留，不退回单图所有权；历史 R29–R31 重复编号不重排，本轮从 R39 承接。旧5196/0等签署只证明对应旧批，不是本轮证据。

| 对应设计条款 | 当前实施状态 | 证据 / 待核验 |
|---|---|---|
| SEA-DIVE-R39 | 源码已接 request_dive deferred 事务、注入同一 SleepCurtain、无字0.85关/1.05开；低级同步 dive/enter_map 保留 | dive_session.gd、main.gd、sleep_curtain.gd 已读；生产/兼容回归PENDING |
| SEA-DIVE-R40 | 源码已等 cover_blank + frame_post_draw 后 threaded load/instantiate；等待 verified/swim 后展开，返回先遮黑再commit | trace.load_begin/entry_ready/commit_return 与真实全黑像素时序PENDING；headless不是绘制证据 |
| SEA-DIVE-R41 | switching、transition_frozen、Main及非继承process_mode冻结、busy写盘门禁、原Main/curtain恢复代码已接 | 成功/正常及缺氧返回/重复请求/失败回滚、日期耗氧输入锁、身份/parent/index/focus/处理模式恢复及泄漏PENDING |
| SEA-DIVE-R42 | 源码为水位101.587442、120m、viewer_min−18.412558、lowest−19.212558、入口水下1m/换气0.5m；不是旧51.12/85m或常规街面入口 | 已读sunroom_region.gd/TSCN；本轮文档分支不改Main/ExistingModels/Base2/任何手摆场景，不签当前运行通过 |
| SEA-DIVE-R43 | 当前仅规则/源码状态已登记，最终验收PENDING | 初始transition Parse black、Main子类Autoload Zones编译、visual timeout保留；水下体验195/8、195/4为真实视觉FAIL，后续修复运行中，主线程补报告，不预签PASS |

本轮已核实 runner 注册：`dive-transition`、`visual-dive-transition`、`underwater-experience`、`visual-underwater-experience`（scripts/run_verification.py）。这里只追加已存在入口关联，不修改登记头或编造新名。接口新增 request_dive 与 transition_started/transition_phase/transition_completed/transition_failed；布幕仍归SEA-SLEEP/UI，Session只借用。最终报告、命令、代码快照、计数/退出码/unexpected/leak和逐图审阅统一填[本轮记录第5节](../../development/2026-11-08_underwater_optics_and_transition.md#underwater-optics-transition-acceptance)；sync/check留主线程，未在本分支执行。

### 本轮主线程最终回填（覆盖本节PENDING，不覆盖失败历史）

| 条款 | 当前结果与证据 |
|---|---|
| SEA-DIVE-R39 | 生产request_dive异步接原幕、sync API保留；dive-transition226/0，dive-maps329/0、dive-control396/0，C批次通过 |
| SEA-DIVE-R40 | 真实全黑已绘制后才load/commit、prepared后展开；visual-dive-transition149/0，A批次exit0/PASS；重操作先退出post-draw信号栈 |
| SEA-DIVE-R41 | 关/加载/开阶段输入/Air/日期/save busy、同Main/原curtain/稳定mode恢复、缺氧/排队返回及失败回滚通过；切日42/0和房间112/0回归通过 |
| SEA-DIVE-R42 | 保持120m、水位101.587442、viewer_min−18.412558、入口1m；sunroom-underwater85/0、sunroom-collision2824/0。未改用户摆位或降低边界迁就地形测试 |
| SEA-DIVE-R43 | 本轮功能专项完成；A圆幕149/0、B真实光学生态195/0、C行为65/0及上述潜水回归通过。框架52/1的second generation write独立复跑仍FAIL，不宣称整批全绿 |

A=`20261109-023938-underwater-render-boundary-f5c046`，B=`20261109-030908-underwater-breath-contact-db6f99`，C=`20261109-031605-underwater-regression-final-2513b4`，均位于`D:/projects/sea-work/verification/`且各有report.json。通过计数入口合计4462/0，另save-seed通过；框架52/1另列不计入。全局sync69问题/只读70问题未通过，派生索引未写，不重签未知资产；功能partial。完整失败、像素与未签范围见[记录第7节](../../development/2026-11-08_underwater_optics_and_transition.md)。

收尾补验：旧图显式恢复默认5m换气带，避免家园0.5m留在共享Air。`20261109-033631-underwater-air-band-final-4cba0b/report.json`中dive-maps338/0、underwater-experience65/0均PASS；最终通过入口共4471/0，不重复计65，框架52/1仍另列。

## 2026-11-10 可见入水 R44–R51 承接（现行设计 / 运行 PENDING）

本次经用户明确授权更新设计，从既有最大 R43 后连续新增 R44–R51；旧 R30/R42 水下1m与 R40 等必须 swim 才开幕的规则由本轮覆盖，历史条款、重复编号及全部 PASS/FAIL 原文保留。登记头结构、status=`partial`、owner 和 code_paths 不变，verification 仅精确增加已存在的 `dive-transition` / `visual-dive-transition`，不表示通过。主线程创建并回填 [入水表现开发记录](../../development/2026-11-10_dive_entry_splash.md)；本次不创建该文件。

| 对应设计条款 | 当前承接状态 | 预计证据 / 待验证要求 |
|---|---|---|
| SEA-DIVE-R44 | 现行设计已登记，运行 pending：cover0.85s/真实全黑post-draw后加载及碰撞选点；prepared enter且entry_verified（如存在）后准备角色/镜头，uncover1.05s；opening位置/Air冻结；幕idle且不可见后Session phase entering并release_entry | `dive-transition`、`visual-dive-transition`：精确事件顺序/全黑像素/加载边界/完整opening零位移，不能再用swim作开幕前置 |
| SEA-DIVE-R45 | 现行设计已登记，运行 pending：home1.65s从水下1.6→4.8m，f=1-(1-u)^3、s=3.2f、v=3*3.2/1.65*(1-u)^2、末速0；move_viewer执行完整胶囊扫掠，水平避让只在黑幕，浅层不通保留街面安全兜底 | 过场/地图/碰撞专项：时长/深度/速度曲线、整段净空与运行扫掠、受阻不强制到点、opening及可见段不横跳；不是修改TSCN迁就测试 |
| SEA-DIVE-R46 | 现行设计已登记，运行 pending：old9仍2.2s、终点世界Y=-10、完整段预检；统一ease-out末速0，各自水位/默认5m换气带保持 | `dive-transition`、`dive-maps`：旧九图逐图验证，不套家园1.6→4.8m数值 |
| SEA-DIVE-R47 | 现行设计已登记，运行 pending：控制器唯一surface/enter/swim/exit四态、无Splash FSM；Map提供dive_entry_ready/progress及entry_tick执行，controller提供entry_is_prepared/release_entry/set_entry_view | 过场/3C专项：prepared是enter内握手、Session entering不是第五态、只在原幕退尽后释放、无Map第二tick/镜头owner |
| SEA-DIVE-R48 | 现行设计已登记，运行 pending：实际位置差/dt驱动velocity动画；swim边界清零入水残速/历史，相机不snap | 行为/真实渲染：受阻实速、opening零位移不假游、末速0与阶段边界、连续镜头，不以期望曲线速度代替碰撞结果 |
| SEA-DIVE-R49 | 现行设计已登记，运行 pending：同控制器镜头6.3→7.5m、76→72°、略仰回基础pitch、≤0.08m单次heave/无roll，保留0.32m双clip；常规72/78及4..13m不变 | [SEA-CAMERA-R17跨链](../camera/ledger.md#2026-11-10-潜水入水镜头-r17-跨链运行-pending)；`visual-dive-transition`/操控回归，不修改OrbitCam/海面镜头 |
| SEA-DIVE-R50 | 现行设计已登记，运行 pending：40池预算、一次16颗、复用shader、世界尾迹；swim后继续到自然回收，无Air/物理/奖励/存档写入 | 行为计数与真实连续表现：只发一次/不随角色粘连/不在swim截断，卸载清理；不把既有环境泡/呼气验收当本轮证据 |
| SEA-DIVE-R51 | 现行设计已登记，运行 pending：switching/transition_frozen持续到swim；整个entry输入/save/capture/日期/经营/氧气及海面air推进冻结；仅释放必要入水表现 | 过场/集成回归：opening完成但仍busy、进入swim才解锁、直接write/capture拒绝、失败/返回恢复同Main和原curtain；v4/用户TSCN/120m/101.587442不变 |

### 本轮待回填验证矩阵

优先入口为既有 `dive-transition` / `visual-dive-transition`；预计相关回归为 `dive-control` / `visual-dive-control`、`dive-maps` / `visual-dive-maps`、`sunroom-underwater`、`sunroom-collision`、`framework-integration`。主线程按实际运行回填命令/工程快照、报告路径、计数/退出码、unexpected/leak、全黑/opening/entering/swim的连续证据、镜头及气泡审阅与未验项；真实渲染与headless分别签署。

**当前运行测试 PENDING，未取得本轮最终报告，不预签 PASS，不复用旧149/0、226/0、5196/0等通过数。** 本次只做五份指定文档的追加及登记头verification精确增补，不运行runner/Godot/sync，不改GDD、代码、其他文档或用户场景。低端/持续性能/用户终审/独立海床等既有未签范围不变。

## 2026-11-10 可见入水最终签署（覆盖上方委派 PENDING）

| 条款 | 当前实施状态 | 当前证据 |
|---|---|---|
| SEA-DIVE-R44/R47/R51 | 已实现并验收：prepared enter后开幕，幕完全不可见后才释放，swim后解锁；黑帧、输入/日期/Air/save/capture冻结和同Main/原幕恢复 | A transition500/0、B真实transition404/0；readiness与release后两类失败遮黑回滚，排队上浮/缺氧通过 |
| SEA-DIVE-R45/R46/R48 | 已实现并验收：家园1.6→4.8m/1.65s，旧九图2.2s/Y=-10，cubic ease-out；实际速度与零残速、正常夹具完整胶囊段安全 | A maps857/0、control396/0、collision2824/0；未穷举每个街面兜底几何 |
| SEA-DIVE-R49 | 已实现并验收：6.3→7.5m、76→72°、0.08m heave；家园最终pitch0.16rad/入水偏移−0.22，opening固定、双clip/首swim连续 | B真实control403/0、transition404/0；21帧已审阅头顶与水面投影边缘分离 |
| SEA-DIVE-R50 | 已实现并验收：16颗/40池、release幂等、世界尾迹，swim继续更新至自然归零 | A/B transition、真实中段关键帧 |

A=`20261110-233501-dive-entry-polish-core-cc526e`，B=`20261110-233501-dive-entry-polish-visual-6a99e7`，C=`20261110-233926-dive-entry-final-integration-222f98`；报告均在`D:/projects/sea-work/verification/<批次>/report.json`。C水下体验179/0、家园85/0、camera14/0、modules31/0、minimum112/0、framework52/0及3个存档入口通过。12个计数入口5857/0，15项全exit0/PASS、unexpected=[]；5核心脚本与B快照一致。完整命令、帧轨迹、失败历史与交付见[开发记录](../../development/2026-11-10_dive_entry_splash.md)。

全局sync exit1/79、只读exit1/81，派生索引同步受阻；含本次sunroom_region.gd已修改资源待定向哈希签署，及SEA-ASSET/并行SEA-WORKSHOP和既有资源漂移，不批量重签。没有DIVE/CAMERA新增条款漏行/未知入口。功能专项完成但总体partial，未改用户TSCN/水位120m/v4；低端、长时、全路线/全部三角面、独立海床和用户终审未签。
