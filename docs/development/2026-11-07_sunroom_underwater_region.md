# 2026-11-07 阳光房下独立水下区域（独立场景已验）

[主文档](../../GDD_V1.0.md) · [潜水规范](../features/dive/spec.md) · [潜水账本](../features/dive/ledger.md) · [环境表现](../features/ambient/spec.md) · [资产登记](../features/asset/ledger.md)

## 1. 本轮范围与生产边界

按用户要求新增独立水下区域，复用当前阳光房下的 `SunkenCity + SunkenSeabed + SolarCabinBase`，补充鱼群、珊瑚和真实设施灯。入口为 `godot/scenes/underwater/sunroom_region.tscn`；生态子场景为 `godot/scenes/underwater/sunroom_region/ecology.tscn`。

**独立场景运行与真实渲染已验，未接生产潜水路由。** `production_route_integrated=false`；原 `dive_map_catalog.gd` 与 `maps/*.tscn` 保持9来源/9图，不能称为“第10张可潜水地图”或“默认已开放”。在Godot打开该TSCN后按F6运行，按住右键配合WASD/QE移动、Shift加速；自由预览镜头不是玩家潜水机制接入。不新增宝箱、奖励、采集、玩法状态、碰撞或存档字段。

本轮不写Main、旧场景、旧源/GLB、原9图及生产机制。父线程确认旧海床、旧城、base、9maps与catalog哈希不变，Main的水/旧城/基座仍为原值；期间并行NPC任务删除了Main中resident_harbor资源声明和实例，差异只有这两块，非本轮写入。**不据此声称整个Main字节未变。**

功能承接：SEA-DIVE-R13（独立区域与范围）、SEA-AMBIENT-R23（纯视觉生态）、SEA-ASSET-R59（原生总成登记与复用证据）。world 既有位置权威链及纯观赏规则保持，本轮无需新增 world 条款。

## 2. 尺度、海面与变换

| 口径 | 本轮记录 | 验收边界 |
|---|---|---|
| city 逻辑域 | X/Z 各 -120..120，240×240米 | 不是城市所有模型的实际包络 |
| terrain 持久海床域 | X/Z 各 -512..512，1024×1024米 | 复用现有四region Terrain3D，不伪造240米海床 |
| water 可视平面 | 1280×1280米 | 与原 Main 同尺寸 plane；局部水下预览材质不等于复制生产海水系统 |
| 海面 | 世界 Y=1.12 | 保留原基准 |
| 旧城根 | 世界 Y=43.487442 | 复用当前摆位，不改回历史0或45 |
| 海床最低 | 世界 Y=-62 | 相对海面最大海床深度为 1.12-(-62)=63.12米，不是62米 |
| 城市实际几何包络 | P(-120,-38.65286,-120)、S(240,37.00966,240) | 本轮真实几何实测；最高Y=-1.64320，海面余量2.7632米，不借逻辑域推断 |
| 海床实测高度范围 | Y=-62..-18.562597 | 最大海床深63.12米；不与城市最低点混写 |

基座原12项矩阵完整保留：

```text
Transform3D(1.4501, 0, 0, 0, 1, 0, 0, 0, 1.4308, -1.5113, -0.3, 1.5988)
```

长宽范围分别在上述三个域内一致，不将三种域混成同一个尺寸。这里记录本轮从现有场景复制的变换快照，不给主场景新增绝对坐标硬约束；未来仍以用户正式TSCN手摆为准。

## 3. 复用资源与生态数量

- 旧城沿用正式 `godot/scenes/world/sunken_city.tscn` 的50组件/388实例；海床沿用 `sunken_seabed.tscn` 及持久Terrain3D数据；基座沿用 `solar_cabin_submerged_base.tscn`。只做正式资源复用，本轮没有新Blender源、新GLB导出或新优化另存流程。
- 珊瑚由 `godot/src/ambient/sunroom_underwater_ecology.gd` 从原web baked reef `coral_00` 的原始几何/索引/实例数据提取12个小单体，在生态TSCN摆32簇；不是新Blender珊瑚模型，也不是把完整礁群重复32遍。来源为 `godot/assets/baked/underwater/{scene.json,geoms.bin,geoms_idx.bin,instances.bin}`；保留原始数据，不修改或重新烘焙。历史 `godot/assets/models/underwater/reef/units/coral_00.glb` 只作溯源，不把它误写成本轮直接加载模型。
- 24套灯具：8个旧城 `street_lamp.tscn`、8个gift_kiosk `deck_light.tscn`、8个gift_kiosk `spotlight.tscn`。真实局部光为16个 `OmniLight3D`＋8个 `SpotLight3D`，这24个局部光均无阴影；不把区域方向光也写成“全部无阴影”。新装配给本区域追加灯光，不修改旧城“熄灭路灯”源组件。新 `godot/shaders/sunroom_underwater_lamp.gdshader` 只让原镜片局部 y=6.774..6.826 且 x>=.674 发光1.6；街灯Point局部坐标(1.075,6.8,0)为实际镜片中心。只覆盖本区域实例，不写共享材质，不改全局水或旧源。
- 鱼群复用既有 `fish_school.tscn`，`dive/slim`，8群合计138条（14/18/16/20/18/14/18/20），纯观赏，不是捕捞点。预览自主动画不接库存、经济或存档。
- 珊瑚及灯的摆位由生态TSCN维护；接地由父区域读取既有网格表面/海床完成。56个生态根接地的最大误差为1.907e-6米，小于.001米；最终Y已精确固化到编辑器TSCN并增加断言，不仅在运行时补齐。几何射线查询不新增物理碰撞、导航或可行走面。最终数量、接地和独立实景专项通过；父线程已目检鱼/珊瑚/灯近景及全景，不外推任意路径和所有穿插组合。

## 4. 资产登记与复用证据（独立场景已验）

初填阶段仅准备默认只读登记脚本，资产行、manifest和运行清单曾待写；随后父线程已执行 `tools/register_sunroom_underwater_region.py --evidence D:/projects/sea-work/verification/20261107-205426-sunroom-underwater-signed-2fa2bb/report.json --write`，完成本轮定向登记。以下为当前交付，不把最初pending当最终结果，也不删除历史阶段事实。

- 通过 `assets/registry/ledger_index.json` 解析 scenes 分账本与 `asset_key`，仅新增总成 `SEA-SCENE-SUNROOM-UNDERWATER-REGION`，记录内挂ecology子装配及数量；不重复登记既有50城市组件、基座、鱼或灯具。
- 唯一manifest：`assets/registry/manifests/scene_components/sea-scene-sunroom-underwater-region.json`，回链唯一总成主记录。`source_paths`和新增runtime均为以下6文件，已逐项定向登记：
  - `godot/scenes/underwater/sunroom_region.tscn`
  - `godot/scenes/underwater/sunroom_region/ecology.tscn`
  - `godot/src/diving/sunroom_region.gd`
  - `godot/src/ambient/sunroom_underwater_ecology.gd`
  - `godot/shaders/sunroom_underwater_surface.gdshader`
  - `godot/shaders/sunroom_underwater_lamp.gdshader`
- source index只精确插新增行，并追加该新AssetID分类规则；既有源哈希/行与并行内容保留。独立水下预览不在海上建筑两类视图内，`building_class=null`；building_views未重建，runtime仅补六份新增资源，没有全量生成或刷新共享脚本、Main、水体、旧GLB及未知漂移。
- 阶段为 `standalone_runtime_verified_provenance_and_production_pending`，`runtime_verified=true`，`validation.runtime=passed_standalone_only`，`production_route_integrated=false`。本轮没有新blend、优化blend或GLB导出，相关字段为null；不伪造Blender源。
- 父线程已核对城市组件GLB哈希与旧v005导出50/50一致、source50/50一致，optimized文件50/50存在。此为正式资源复用的文件核对证据，不等于本轮重新打开优化源或完整02b验收；未重开，不假签新02b。
- 原始来源、源级完整审阅、完整优化复用/02b签署、性能、商业权属和用户美术验收继续 **pending**。技术性画面审阅不代替用户美术接受，单机实拍不签性能或低端设备。最终全局sync/check另列第7节，不用独立场景通过覆盖全局问题。

## 5. 最终独立场景验收与未验边界

最终隔离报告：`D:/projects/sea-work/verification/20261107-205426-sunroom-underwater-signed-2fa2bb/report.json`。报告HEAD为 `aa12686907371f5e389e5923f259a2f886738235`，含工作树快照，不将HEAD误作所有文件已提交。两个入口均执行隔离project中的 `res://tests/test_sunroom_underwater_region.gd -- --skip-title`；结构项带 `--headless`，真实渲染项不带headless，参数为 `--resolution 1280x800 --fixed-fps 60`。实际完整命令与日志路径见report；日志位于同目录 `sunroom-underwater.log` / `visual-sunroom-underwater.log`。

| 项目 | 最终结果 | 证据与签署边界 |
|---|---|---|
| sunroom-underwater | **PASS，67 checks/0 failures，exit0** | completion_marker=true，expected_errors/unexpected_errors/failure_labels均空 |
| visual-sunroom-underwater | **PASS，89 checks/0 failures，exit0** | 11真实视角；NVIDIA GeForce RTX4060Ti、Vulkan1.4.341 Forward+，Godot4.6.3；无非预期错误 |
| 城市实际包络/海面余量 | 已实测 | P(-120,-38.65286,-120)、S(240,37.00966,240)，最高-1.64320、余量2.7632米 |
| 海床范围/深度 | 已实测 | min=-62、max=-18.562597，最大深63.12米 |
| 珊瑚/灯具接地 | 已验 | 32珊瑚根＋24灯根共56根，maxdelta=1.907e-6米<.001；编辑器TSCN已精确固化并增加断言 |
| 生态与画面 | 本轮数量及独立实景已验 | 12原株/32簇、8群138鱼、24灯Omni16/Spot8且局部阴影0；父线程已目检鱼/珊瑚/灯近景与全景 |
| 正式资源复用 | 文件核对已完成，完整优化签署pending | 50/50城市GLB与旧v005导出哈希一致、50/50 source一致、50/50 optimized文件存在；未重开不签新02b |
| 新总成/manifest/source index/分类规则 | 已定向登记 | 唯一总成及唯一manifest，不重复登记复用组件，不刷新旧hash |
| 新runtime | 已补6文件 | 仅新增六份source/runtime，未全量生成，building_views未重建 |
| minimum-loop（204914集成批次） | **FAIL，147 checks/1 failure** | open shop失败，无脚本错误；新场景未挂Main，不能推为本轮造成；未做因果回退，也不签已排除关联 |
| 全局sync/check | FAIL：sync18项、普通check20项 | 43功能/967源/1367运行哈希；并行SEA-RESIDENCE状态变化、索引stale、SEA-SHOP未知入口与源/运行/内容漂移，未批量刷哈希 |
| 默认生产入口 | 未接入 | production_route_integrated=false，原9来源/默认屏蔽保持；仅F6独立查看，不签玩家潜水接入 |
| 来源/源级完整审阅/完整02b复用签署 | pending | 文件与哈希核对不代替完整来源和优化验收链 |
| 性能/低端设备/商业权属/用户美术 | pending | 11视角技术性目检不代替性能和用户接受 |

## 6. 过程记录与修正

- 初填阶段资产登记及两个专项结果均pending；当时仅登记脚本ast.parse、空数组/尾部/中间三个JSON内存样例及指定文档git diff --check退出0，未据此签运行通过。后续登记与最终结果以第4–5节为准。
- 首轮曾发生 `var reference` 解析错误，已修复；不能将该错误批次视为最终无错误通过。
- 最初画面出现黑阴影，定位为 `ambient_source=3` 使用错误，已改为2并柔化；两版图过程保留。最终使用本场景局部shader，不改全局水或旧源。
- 203158批次阶段结果为结构58/0、真实70/0；203458阶段计数未确认，不填推测值；203705真实项PASS。204914独立结构66/0、真实88/0，但同批minimum-loop147/1仍FAIL；后续固化编辑器Y并增加断言，最终205426结果为67/0、89/0。阶段绿项不覆盖过程错误或集成失败。
- 文档初次回填后执行最终全局sync/check，结果见第7节；不把先前文档分支未执行误写成最终没有验证。

## 7. 最终静态检查、源保护与交付

- `check_feature_contracts.py --sync`退出1，18项；随后普通check退出1，20项，43功能/967源/1367运行文件哈希。新增独立总成/六文件没有报漂移。剩余含SEA-SHOP unknown shop-modules、鱼群源漂移、共享水/海床/世界环境/Main/zone1/移动/NPC/存档等运行漂移、zones/dialogues内容ID漂移，以及并行住宅状态与派生索引变化。本轮未批量刷新这些旧哈希。
- `check_placed_positions.py`3结构通过/0warning；`git diff --check`exit0。居民港湾实例被并行NPC事务移除，故当前3结构，不把此前4结构照抄为本轮结果。
- 本轮保护比对：原九图、catalog、旧城PackedScene、海床PackedScene、阳光房及其基座PackedScene哈希保持；当前Main只有并行resident_harbor的资源和实例删除差异，本轮没有编辑Main，不回灌已停用的住房。旧城/水位/基座引用及变换与新场景一致。
- 最终六个新场景/脚本/shader与205426隔离副本逐字节一致；唯一总成、manifest和六运行指纹已登记，旧记录保持。`tools/register_sunroom_underwater_region.py --evidence <205426/report.json> --write`执行后再跑是幂等，证据路径/源哈希不匹配即拒绝覆盖。
- 工程外交付：`D:/projects/sea-work/outputs/sunroom-underwater-20261107/index.html`（实拍与范围预览）、`contact-sheet.png`、`verification-summary.json`及场景副本。正式入口仍为工程内`res://scenes/underwater/sunroom_region.tscn`，场景副本依赖既有工程资源，不能脱离工程直接运行。
- F6运行当前场景即可看；按住右键转视角，同时WASD平移、Q/E升降、Shift加速。相机只是区域查看工具，无物理碰撞和潜水背包/氧气玩法，本轮不接生产路由。
