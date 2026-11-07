# 2026-11-07 按海域切换独立潜水地图

[主文档中控](../../GDD_V1.0.md#sea-dive) · [潜水设计](../features/dive/spec.md) · [潜水账本](../features/dive/ledger.md) · [模块契约](../architecture/module_contracts.md)

## 1. 交付性质与范围

用户要求先更新机制，再更新设计文档与功能账本。本轮已完成按来源海域切换九份独立TSCN、稳定会话与旧档兼容。**最终九项隔离验收均通过，计数专项903/0；完整结果见第10节。** 下面第9节保留设计初填时的pending作为过程记录，不是当前签署状态；设备、完整地图美术与全工程检查不随本机制通过而升级。

本分支仅修改以下文档，不改代码、测试、场景、资产注册、运行/源哈希、派生索引或玩家存档，不执行sync/check及其它命令：

- `docs/features/dive/spec.md`、`ledger.md`。
- `docs/features/boot/spec.md`、`ledger.md`。
- `docs/features/world/spec.md`、`ledger.md`。
- `docs/features/save/spec.md`、`ledger.md`。
- `docs/architecture/module_contracts.md`、`GDD_V1.0.md`。
- 新增本记录 `docs/development/2026-11-07_dive_map_switch.md`。

四个功能保持 `partial`。账本标题、主文档/功能回链、JSON登记头及历史记录保持原样，只追加本轮章节。上方历史“UnderwaterWorld统一几何所有者”“Underwater常驻隐藏”口径由本轮章节覆盖，不删除历史证据，也不把历史通过当作本轮结果。

## 2. 条款与跨功能交接

读取现有spec/ledger确认最大值为DIVE R05、BOOT R06、WORLD R25、SAVE R18后，新增：

| 条款 | 承接范围 |
|---|---|
| SEA-DIVE-R06 | 稳定来源ID与实际泊位最近分区 |
| SEA-DIVE-R07 | 唯一map_id/TSCN、9图内容复用与碰撞归属 |
| SEA-DIVE-R08 | preflight、同Main挂起、唯一路由及失败回滚 |
| SEA-DIVE-R09 | 原实例上浮恢复与跨图共享恢复冷却 |
| SEA-DIVE-R10 | 原v4进度、稳定全局宝箱ID、全量覆盖及busy门禁 |
| SEA-DIVE-R11 | 默认范围、旧资源/生成器兼容及SunkenCity隔离 |
| SEA-BOOT-R07 | 装配、挂起退出、原实例恢复与最终清理边界 |
| SEA-WORLD-R26 | 世界来源查询、实际摆位权威及景观边界 |
| SEA-SAVE-R19 | 潜水快照唯一所有者、兼容及直接写盘拒绝 |

GDD的SEA-DIVE范围改为“按海域切换独立地图的潜水探索与宝箱”；前置保留SEA-WORLD、SEA-INVENTORY，并增加SEA-SAVE（进度/写盘门禁）与SEA-BOOT（同一Main挂起/返回）。不新增其它功能或反向前置，不修改并行NPC、商亭等章节。

## 3. 九图目录与配置快照

目录名称、来源、map_id、路径和基数逐项取自 [`dive_map_catalog.gd`](../../godot/src/diving/dive_map_catalog.gd)，不按地面区块名称猜海底名称。`res://`指正式Godot工程；每个来源有独立且唯一的map_id/TSCN。

| source_id | catalog label | map_id | scene_path | chest_id_base |
|---|---|---|---|---|
| zone1 | 家园礁盘 | dive_zone1 | res://scenes/underwater/maps/zone1.tscn | 0 |
| zone2 | 浅湾珊瑚园 | dive_zone2 | res://scenes/underwater/maps/zone2.tscn | 100 |
| zone3 | 环礁深庭 | dive_zone3 | res://scenes/underwater/maps/zone3.tscn | 200 |
| zone4 | 远海断街 | dive_zone4 | res://scenes/underwater/maps/zone4.tscn | 300 |
| zone5 | 北境裂谷 | dive_zone5 | res://scenes/underwater/maps/zone5.tscn | 400 |
| sea_supply | 补给站沉箱水域 | dive_sea_supply | res://scenes/underwater/maps/sea_supply.tscn | 500 |
| rooftop_ranch | 牧场岩阶 | dive_rooftop_ranch | res://scenes/underwater/maps/rooftop_ranch.tscn | 600 |
| neon_garden_quarter | 霓虹沉街花园 | dive_neon_garden_quarter | res://scenes/underwater/maps/neon_garden_quarter.tscn | 700 |
| resident_harbor | 居民港湾遗迹 | dive_resident_harbor | res://scenes/underwater/maps/resident_harbor.tscn | 800 |

以下为上述正式TSCN的当前配置快照，不是新增美术资产清单。B=basin、N=neighborhood、R=reef、T=trench；fish为旧swim数据的零基索引，出生点属于独立地图局部坐标，不是海面设施的参考位。

| source_id | region组合 | spawn_point (X,Y,Z) | 局部chest_ids | 固定全局宝箱ID | fish_indices | basin_closure |
|---|---|---|---|---|---|---|
| zone1 | B/N/R/T | (0,1.12,12) | 0,1,2,3,4 | 0,1,2,3,4 | 0,1,2,3,4,5,6 | false |
| zone2 | B/R | (-6,1.12,10) | 0,1 | 100,101 | 0,1,2 | true |
| zone3 | B/R/T | (6,1.12,4) | 0,3 | 200,203 | 2,3,6 | false |
| zone4 | B/N/T | (0,1.12,-24) | 2,4 | 302,304 | 0,4 | false |
| zone5 | B/T | (0,1.12,-12) | 4 | 404 | 4,5,6 | false |
| sea_supply | B/N | (-4,1.12,18) | 1,2 | 501,502 | 1,4 | true |
| rooftop_ranch | B | (0,1.12,6) | 0,2,3 | 600,602,603 | 2,5 | true |
| neon_garden_quarter | B/N/R/T | (4,1.12,-18) | 1,2,3 | 701,702,703 | 1,3,5 | false |
| resident_harbor | B/N/R | (4,1.12,10) | 0,1,2 | 800,801,802 | 0,2,4 | true |

霓虹图的reef单独绕Y旋转 `0.34906585` 弧度；它是无碰撞装饰。其它有碰撞归属的region与地图/Regions根保持原baked坐标。九图共享 `res://assets/baked/underwater/swim.json`，以显式子集配置筛选，不是9套新美术，也不表示全海面9来源均已安装。zone3/4保留为规划目录，本次不自动恢复它们的Main实例。

## 4. 生产来源解析

生产装配为 `Main._setup_dive()` → `DiveSession.configure(self)`，注入 `source_query = Main._dive_source_at` 以及既有奖励回调。来源用稳定ID，不用显示名称当map key。

1. 岸上：ActorController模式为ASHORE时返回 `GameState.current_zone`。
2. 船上：遍历Main已安装的 `_zone_nodes`；仅考虑 `Scope.zone_enabled(id)`为真且catalog有映射的区块。
3. 读取各区块当前 `landing_points()` 的真实 `global_position`，以XZ平方距离取最近泊位所属区块；近似等距按来源ID字典序仲裁。
4. 这是覆盖**整个海平面**的nearest partition，不是泊位有限半径探测，也不读 `zones.json.origin`。设施被用户手动移动或旋转后，其实际泊位自然带动来源分区；泊位Y不参与距离。
5. 若没有合格来源，返回空ID并拒绝进入，不静默回退家园。明确未知来源也不能凭空产生地图。

直接 `enter_map(id)` 是目录路由/内部验收入口，不替代生产Scope/已安装筛选。默认潜水入口仍被屏蔽，显式 `--full-world` 只用于开发回归，不会把未安装的zone3/4自动加回海面。

## 5. 会话切换事务与生命周期

### 5.1 海面稳定态

Main仅挂 `DiveSession` 轻节点，不挂任意海底地图几何。稳定会话拥有全局进度和同一个DiveAir；没有潜水runtime时继续推进海面换气与恢复冷却。catalog只持静态目录，不持实例或玩法进度。

### 5.2 preflight与提交

- 拒绝active/switching重入、无有效在树Main、恢复冷却未完以及未知目录项。
- 加载/实例化候选PackedScene，检查Regions/Deco/Chests/DiveCamera/WorldEnvironment、map_id及宝箱基数匹配；检查swim数据可读取且包含必要基础数据。此阶段失败释放候选，Main仍在海面。
- 提交时设置switching并记录来源/map_id；runtime使用会话同一个DiveAir和注入奖励端口。
- 缓存Main父节点/顺序、原current_scene、海面相机和Economy.ticking；设置 `dive_map_suspended`。稳定DiveSession临时reparent到树根，保存海面节点可见性及来自外部的脚本信号连接，然后把**同一Main**移出场景树缓存。
- 不free Main、不重新实例化、不重跑Main._ready、不读取存档。Main挂起退出不得清空save_registry、业务端口与稳定会话。
- 暂停Economy.ticking，挂入唯一runtime并设置 `SceneTree.current_scene = runtime`；使用地图自己的WorldEnvironment执行setup。

### 5.3 地图初始化与运行

`UnderwaterWorld.setup([], local_environment) -> bool`在地图ready且在树后执行；生产传空海面节点表，不引用已出树Main环境。进一步检查本地环境、几何实例、region/碰撞开关、数据字段、出生点及完整水面→ENTER_DEPTH路径、宝箱交互站位，失败返回false并回滚同一Main，不继续运行半初始化地图。

每图都有本地DiveCamera、WorldEnvironment、Deco、Chests；运行时组装潜水角色和独立DiveMapHUD，消费稳定会话事件。只存在一张活动runtime，不在海面常驻其它地图。海面Main出树停止海面时钟/天气/自动存档驱动，Economy停止经营tick；不是推进一份隐藏海面世界。

### 5.4 上浮与失败回滚

正常/缺氧上浮触发deferred返回，先合并当前地图进度，移除并释放海底runtime；同一Main回原父节点/顺序，恢复current_scene、外部信号原Callable及flags、可见性、原海面相机与环境，恢复原Economy.ticking。

Main `resume_after_dive_map()`只恢复出树时清理的派生投影/必要端口，包括GroundSpace、角色档案/开场回调、NPC世界投影和 `dive_resume_listener`；不重读存档或重建整局。原船/海面角色姿态与角色模式保持，不强制改成船上；最后会话回Main、清active/switching/source_id/map_id并发布exited。真正销毁会话仍走原最终清理，不能把挂起误当结束。

这些是本轮应验契约，**实际恢复完整性、外部信号无重复/失联及其它并行模块生命周期均待父线程运行验证**，不凭静态阅读签署通过。

## 6. 内容几何、碰撞与动作边界

- 四类旧region仍是内容复用单位，不代表所有地图都必须带齐四区。
- 街区碰撞对应旧solids索引0..32，海沟沉船对应33..42；分别由对应开关筛入，不可因共用swim.json把已移除region的碰撞留成空阻挡。
- 台地与盆地保留；无海沟地图开启basin_closure补北口可见边界/底面并撤海沟碰撞。有海沟图保持原通道，不加封口。
- reef是无碰撞装饰，可独立变换；其它碰撞region及地图/Regions根暂不支持未同步baked数据的变换。
- UnderwaterWorld继续拥有surface/enter/swim/exit及7个既有独立动作；出生点由本图配置，完整入水段须无遮挡。原氧气/发现/搜索/奖励规则不因切图另建业务副本。
- 鱼群是装饰表现，只选旧数据子集，不接捕鱼、背包或独立存档；奖励仍经注入的原库存入口。
- DiveAir恢复冷却属于稳定会话，卸载地图、切换来源或重建runtime均不能绕过；海面继续走恢复时间，氧气归零仍强制上浮但不扣已有资源。不会把冷却新增为必填存档字段。

## 7. 根v4兼容、进度与写盘门禁

保留原wire格式：

```json
{"version":4,"dive":{"found":[0,100],"opened":[0]}}
```

上例只展示根版本与dive片段，**不是完整可恢复快照**。

- `SnapshotRegistry`仍注册原键 `dive`，所有者由稳定DiveSession承担，不能注册瞬态runtime或改成按map_id嵌套的新key。
- `found`与`opened`仍是整数数组；无map_id必填扩展，无版本升级。zone1保留原0..4，其它百位100..800加固定局部子集，详见第3节；ID不因表顺序或删减内容重新编号。
- 返回合并当前图发现/开启结果并排序去重，保留其它未加载地图及未知ID；runtime只投影本图已知宝箱。未知ID保留优先于历史通用“未知内容按内容表过滤”描述，不改变其它模块策略。
- `from_dict`先清空全局进度再全量应用；读较旧档必须清掉现场各图新增进度，不能仅并集叠加。单图from_dict先复位开盖/发现表现再应用本图ID。
- 已开启宝箱重访不重复发奖励；氧气、中途动作与当前地图不存，读档仍回稳定海面。切图/上浮本身不是SaveGame.read/restore，不会用磁盘旧快照覆盖当前背包与内存进度。
- `Main._setup_save_registry` 的busy_query包含 `dive.active or dive.switching`，原结算/睡眠/建造/攀爬门禁保留。潜水或切换时registry拒绝capture/restore，**直接 `SaveGame.write(path, main)` 同样检查busy并拒绝**，不是仅拦F5或UI。
- 正常上浮后才允许稳定整档写盘；应验证拒绝期间不产生文件、不覆盖原有效档。禁止用玩家真实档做验证。

## 8. 默认范围、兼容与不做事项

- 默认PlayScope仍屏蔽dive/lamp；内部专项能进图不等于玩家默认开放。
- `godot/scenes/underwater/underwater_world.tscn`保留为旧资源，不在Main常驻，也不是新的正式九图入口；旧内部注释/历史记录不能反向推翻本轮生命周期契约。
- 旧 `build_underwater.py`只能在工程外候选副本运行，不能覆盖手工维护的正式maps或Main。
- `World/SunkenCity`、SunkenSeabed及其用户手摆位置/材质/几何保持，仍为海面纯观赏，不挪作九图玩法，不改全局海水参数。
- 不自动恢复zone3/4、不增加9套新美术、不新增海面设施、不新增map_id必填schema、不换 `dive` key、不重编号宝箱、不开放默认潜水。
- 本次文档分支不改资产注册/哈希/代码/测试/runner。runner登记由父线程实现，本分支只读取确认入口存在。

## 9. 验证登记与父线程回填

已只读确认 `scripts/run_verification.py` 登记 `dive-maps` 和 `visual-dive-maps`，均指向 `tests/test_dive_maps.gd`；非headless分支保存逐来源真实渲染图。入口存在、测试源码有断言或PNG写出成功，均不能单独当作玩法/美术验收通过。

待父线程使用统一runner的隔离数据目录执行并回填（下列为入口说明，本分支未执行）：

```text
python3 scripts/run_verification.py dive-maps visual-dive-maps
```

| 验证项 | 应记录的证据与边界 | 当前状态 |
|---|---|---|
| 目录与9地图 | 实际测试版本、9来源唯一map_id/路径、内容/碰撞/出生点断言，未知来源及重复进入拒绝 | pending，待父线程补充 |
| 来源选择 | 岸上current_zone、船上实际泊位全海平面nearest partition、等距仲裁、Scope/未安装筛选、手动移位跟随、不依赖JSON参考位；当前专项未覆盖部分单列 | pending，待父线程补充 |
| Main挂起/恢复 | 同实例与current_scene、唯一runtime、原船人姿态/模式/相机/环境、GroundSpace/端口/外部信号、setup失败回滚 | pending，待父线程补充 |
| 海面暂停 | 时钟/天气/经营/自动存档在潜水期间不推进，恢复原ticking，不仅比较某一帧船位 | pending，待父线程补充 |
| 恢复冷却 | 同一会话跨地图拒绝绕过、海面继续推进、正常及缺氧上浮 | pending，待父线程补充 |
| 存档兼容 | 原v4/旧0..4、百位全局唯一、未知ID保留、跨图不串、全量覆盖清旧进度、已开不重奖、磁盘往返 | pending，待父线程补充 |
| 写盘门禁 | active与switching阶段直接SaveGame.write拒绝，无文件/有效档不变，上浮后正常保存 | pending，待父线程补充 |
| 默认范围 | 默认入口拒绝、catalog不安装zone3/4，SunkenCity纯景观不变 | pending，待父线程补充 |
| 真实渲染 | visual-dive-maps的9张图、实际场景/机位/图形后端、逐图目视可读性与返回海面画面；图非空不等于美术通过 | pending，待父线程补充 |
| 相关回归 | 父线程实际选择的集成/存档/场景入口、命令、退出码、checks/failures、unexpected_errors；未执行明确列出 | pending，待父线程补充 |
| 设备与性能 | GPU/透明渲染/帧耗时/低端设备，不由逻辑专项推定 | pending，待父线程补充 |
| 静态工程门禁 | sync/check及索引/资产漂移由父线程按范围另记，本分支未运行、未刷新哈希 | pending，待父线程补充 |

### 父线程最终结果占位

- 隔离验证根 / report.json：pending。
- 源版本 / 工作树快照及隔离副本一致性：pending。
- `dive-maps`：退出码pending；checks/failures pending；runner状态pending；日志pending。
- `visual-dive-maps`：退出码pending；checks/failures pending；图形后端pending；图像路径与逐图审阅pending。
- 相关回归、失败项、预期故障、非预期脚本错误与未执行项：pending。
- 已知缺口、运行/视觉/设备分别签署与功能状态决定：pending；当前四功能保持partial。

以上pending是文档初填时的过程事实；最终由下节实测覆盖，不以历史通过冒充当前结果。

## 10. 最终实测与签署

### 机制与兼容结果

最终隔离报告：`D:/projects/sea-work/verification/20261107-190643-dive-map-switch-signed-451501/report.json`。runner在Autoload前隔离用户目录，无玩家真实存档读写。该批9项全部PASS、exit0、expected_errors与unexpected_errors均空。

| 专项 | checks / failures | 退出码 |
|---|---|---|
| dive-maps | 312 / 0 | 0 |
| visual-dive-maps | 322 / 0 | 0 |
| modules | 31 / 0 | 0 |
| framework-integration | 52 / 0 | 0 |
| click | 39 / 0 | 0 |
| minimum-loop | 147 / 0 | 0 |
| save-seed | ok=true（独立完成标记） | 0 |
| save-corrupt-seed | complete（独立完成标记） | 0 |
| save-protection | ok/protected/unchanged/separate=true | 0 |

六个计数专项合计903 checks/0 failures；三项种子/存档保护不混入检查数。覆盖九来源唯一场景/出生点/23宝箱ID、当前已安装泊位选源及岸上ID、显式未知来源拒绝、实际current_scene切换、同Main实例移出/回树、海面时钟与船位暂停、原角色模式与姿态/镜头/环境/地面投影/Terrain3D变换及top_level恢复、跨图旧档与未知ID保留/全量覆盖/磁盘往返、直接busy写盘拒绝、缺氧上浮/跨图冷却、异常地图销毁清理与本地HUD暂停/告警。

### 实现中补齐的生命周期问题

- 旧UI纸张在tree_exiting无条件queue_free，导致缓存Main回树后样式引用已释放；改为只在拥有面板确实排队销毁时释放，临时离树保留。
- 外部脚本信号挂起期间临时断开、恢复时保留原Callable/flags；原生Control/Label内部Viewport/Font连接交给引擎处理，不能重复断连。
- Terrain3D重进树会缓存退出中的潜水相机。保留同一地形实例，先独立缓存，再在Main海面相机已回树后重新挂载；运行时临时top_level调整后恢复。没有改正式场景海床坐标、几何、材质或用户手摆transform。
- 旧启动deferred排版/调色在Main临时离树时需要等待tree_entered；回归夹具也等待真实启动deferred完成，而不在同一初始化栈内瞬间切图。
- 地图异常销毁时释放缓存Main、Terrain3D、控制/注册表闭包和会话；恢复全局暂停/ticking，避免根节点孤儿会话。
- 新SEA-DIVE-R12：宝箱奖励生产改注入Inventory.add_all，整份加入成功才记opened。满包既不部分发放也不销毁奖励，并在独立HUD提示；重复已开请求不重奖。give_resource只作历史独立工具兼容。
- 独立HUD显示地图、水深、氧气、发现数和短消息；30%橙/15%红，Esc暂停菜单可继续或上浮，暂停不耗氧；不借离树海面菜单/日志。

### 真实渲染与目视

`visual-dive-maps`使用RTX4060Ti、Vulkan Forward+真实渲染，九张图位于该报告目录的`project/outputs/dive-map-<source_id>.png`；交付对照为`D:/projects/sea-work/outputs/dive-map-switch-20261107/nine-map-contact.png`。已目视九图拼图与浅湾原尺寸图：角色/海底/本地HUD正常，无全黑或缺图；街区图和纯礁盆图内容可区分，zone2/zone3、zone1/resident在同近景相似，属于旧素材组合，不能冒充九套全新视觉主题。未完成各图全路线人工探索、深沟全景/宝箱逐个手玩、低端GPU/性能/手柄触屏验收。

### 保留失败与过程证据

- 首轮`20261107-173151-dive-map-switch-first-75acb7`281/20失败；含并行shop_panel类型错误、原生断连、临时离树UI与地形错误，作为过程保留。
- `173614-dive-map-switch-refined-4c19f4`281/2，`175914-dive-map-switch-lifecycle-1908a3`281/1；修复JSON数字读回float比较夹具和原生地形生命周期后`180751-dive-map-switch-acceptance-74d594`281/0、真实291/0。
- 追踪`180144-dive-map-switch-trace-4cbffd`大量日志导致timeout124，不算通过；缩小追踪后定位Terrain3D在重新选相机时读退出对象。
- `185208-dive-map-switch-release-2d4c10`扩展专项302/1、真实312/1（岸上夹具用无效状态转换）；框架/点击虽断言0失败但存在deferred离树脚本错误，runner正确判FAIL；修正后`190002-dive-map-switch-final-63535f`地图302/0、真实312/0、框架52/0、click39/0。
- 同一190002批次综合selftest511通过/24失败，包含已撤zone4、home_cabin地面、旧菜箱/温室/种植、zone5区域、采集、泊位航路、旧相机边界/订单及读档镜头；且出现farm_plot_a旧夹具脚本错误，**没有把它计为通过，也未对全部24项逐项回退证明来源**。本轮潜水分段未报失败，整套selftest仍未绿。
- 功能契约已执行sync；初次43功能/930源/1255runtime，19项问题，涉及并行shop入口、源/内容ID/runtime哈希漂移。未批量更新未知哈希，不宣称全工程绿。最终静态结果随后追加。
- `check_placed_positions.py`4结构通过/0warning，`git diff --check`exit0。验证时引擎有导航体素精度与资源UID回退warning，不等于ERROR；最终runner非预期错误为空。

### 源一致性与交付

交付摘要`D:/projects/sea-work/outputs/dive-map-switch-20261107/verification-summary.json`记录已验副本及逐文件SHA256。签署后Main出现并行商店回调变量提取（inline ashore lambda改本地变量再注入），潜水相关块未变；另跑当前树机制/框架/最小循环确认，结果另附。所有潜水专属代码与九图均逐字节对应签署副本。其它未签署工具适配只通过静态语法，不外推运行通过。功能整体保持partial：机制已落地，不等于默认开放或美术/设备全验收。

### 19:18 当前树与最终静态追加

- 最新并行Main回调变化后，再跑`20261107-191444-dive-map-switch-current-tree-911183/report.json`：dive-maps312/0、framework-integration52/0、minimum-loop147/0与save-seed均PASS/exit0，无非预期错误。当前Main与此副本逐字节一致；签署九图/专属代码与190643副本一致。
- 最后`check_feature_contracts.py --sync`退出1：43功能/966源资产/1360 runtime，27项；随后普通check退出1：28项（多derived feature index stale）。工作区其他会话持续增改内容，摘要在两次调用间已变化。条款/路径没有新增潜水错误；清单含SEA-SHOP unknown shop-modules、10项源资产漂移、15项runtime漂移（含本轮涉及Main/主场景/HUD及并行材质/存档/居民场景等）、zones内容ID漂移；未把本轮runtime登记缺口全部推成任务外，也未用批量hash更新掩盖未知变更。静态全局门禁未绿。
- `check_placed_positions.py`4结构通过/0warning；`git diff --check`exit0。项目内既有用户/其他会话改动保留，没有提交或回退。
- 追加真实开发入口验收`20261107-192036-dive-map-switch-production-d0a693/report.json`：`visual-dive-maps --full-world`324/0、exit0、runner PASS、无非预期错误；在九图基础上检查生产`Main._on_dive()`确实按来源切图并正常返回，同时生成`dive-map-return-surface.png`。已目检返回海面图，家园/船人/HUD与水面正常，无残留海底镜头或黑屏。该追加不开放默认潜水，也不代表未安装海域被自动装回。最新测试脚本与此副本一致。最终源比较时HUD另有并行新增一行shop_query兼容注释，忽略纯注释后执行行与生产验收副本一致；摘要保留原字节SHA不相等，不伪称完全同哈希。交付前Main又有并行商店/职业档案更新，当前整文件不再等于签署副本，潜水7个装配/来源/进出/恢复/清理/存档方法单独比较保持一致；未回退他人功能，也不宣称这些最新任务外改动已经本轮回归。
