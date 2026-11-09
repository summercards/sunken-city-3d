# SEA-AMBIENT · 环境植物与生活表现 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-ambient) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-AMBIENT",
  "status": "partial",
  "owner": "PlantField / Birds / VegetationWindController / VegetationPatch / ProtonScatter authoring",
  "code_paths": [
    "godot/src/ambient",
    "godot/scenes/plants",
    "godot/addons/proton_scatter",
    "godot/scenes/vegetation_authoring"
  ],
  "verification": [
    "selftest",
    "decorations",
    "visual-decorations",
    "visual-birds",
    "visual-fish-schools",
    "vegetation-contract",
    "visual-vegetation",
    "visual-vegetation-performance",
    "visual-proton-scatter",
    "visual-proton-preview",
    "sea-fauna",
    "visual-sea-fauna",
    "scenic-fish-distribution",
    "visual-scenic-fish-structure",
    "visual-scenic-fish-distribution",
    "sunroom-underwater",
    "visual-sunroom-underwater"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-AMBIENT-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-AMBIENT-R02 | 本批实现并专项验证 | zone1 花瓣粒子按主人截图反馈停用（数据层 `effect=None`，代码路径保留）；`visual-decorations` 断言 zone1 运行时不建任何 `GPUParticles3D`、植物场无 `effect_node`、摆动参数仍在。见[本轮记录](../../development/2026-10-28_zone1_petals_removed.md) |
| SEA-AMBIENT-R03 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-AMBIENT-R04 | 本批实现并专项验证 | 稳定实例ID、describe/request_interaction/set_upgrade_level接口、完整鸟轨迹净空、装饰鱼与捕捞解耦；飞鸟鼻尖朝飞行切线（`bird.gd` 用 `atan2(tangent.x, tangent.z)`，与鲸鱼/鱼群同一烘焙约定），`visual-decorations` 断言鼻尖与切线 `dot > 0.9`、`visual-birds` 出侧拍实拍；鸥群高度带 14.3–17.7 m（`altitude_offset` 12 → 8.5，屋脊实测 11.84 m），按截图反馈压低后仍由「屋顶 +1 m」净空断言守住；水面装饰群沉在浪面下 0.5–1.5 m（最高点口径）、每群 3 色、铺开跨度 ≥3 m、单条鱼游程 ≥1 m。见[本轮记录](../../development/2026-10-28_fish_school_spread_palette.md)、[海鸥朝向修正](../../development/2026-10-28_bird_heading_flip.md)、[鸥群高度下压](../../development/2026-10-29_bird_altitude.md) |
| SEA-AMBIENT-R05 | 已实现；06:00–18:00 出现，18:00 后整群收起，05:30/18:30 两侧断言通过 | `decorations` 新增四条时段断言（11:00 可见 / 18:30 不可见 / 05:30 不可见 / 06:06 恢复）；小时由 `Main` 从 `WorldClock.changed` 下发，鸟群不持有第二份时间；[本轮交付](../../development/2026-10-30_detail_fixes.md) |

## 2026-11-06 阳光房鱼群与露水建筑海鸥

| 对应设计条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-AMBIENT-R20 | 已实现并验证。阳光房周边鱼群6/10/14三档，真实水面采样、基座避让、身体/尾鳍动画通过。 | `sea-fauna`通过；纯视觉，无捕捞/库存/经济/存档职责。 |
| SEA-AMBIENT-R21 | 已实现并验证。阳光房和屋顶牧场海鸥接入唯一WorldClock，白天可见、夜间隐藏，真实水面画面通过。 | `sea-fauna`、`visual-sea-fauna`通过；纯视觉，无建筑玩法/交互/资源职责。 |

## 资源与调用入口

- [godot/src/ambient](../../../godot/src/ambient)
- [godot/scenes/plants](../../../godot/scenes/plants)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

- `godot/src/ambient/birds.gd`：命令/查询 `build(), set_hour(hour: float), is_flying_hour()`；事件 `无`。
- `godot/src/ambient/plant.gd`：命令/查询 `set_growth(value: float), grow_to(value: float)`；事件 `无`。
- `godot/src/ambient/plant_field.gd`：命令/查询 `spawn_from_placements(), spawn(arch: String, scope: String, position: Vector3), set_zone_level(level: int, instant := false)`；事件 `无`。
- `godot/src/ambient/mesh_io.gd`：命令/查询 `load_mesh(path: String)`；事件 `无`。

## 验证记录

入口：`python3 scripts/run_verification.py selftest`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 selftest 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

美术登记需按源/运行资产分别维护，不把装饰动画计作生活玩法完成。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。
- 2026-10-28：**zone1 停用区块级花瓣粒子**（主人截图："阳光房的中间有一些飘起的粒子，帮我去掉"）。花瓣是区块中心单发射器（`plant_effect.gd` 的 `petals`，14×14 m 盒子、半径 7 m），不跟植株走，所以固定飘在上层平台与栈道交界。撤的是数据（`naming.ZONE_PLANT_EFFECTS["zone1"].effect = None` + 16 个 zone1 植物场景的 `effect` 行），`plant_effect.gd` 代码路径保留可复启用；摆动 `0.028/0.9` 原样保留。`visual-decorations` 1599 checks / failures=1，唯一失败为既有 `decorations follow dive lifecycle`（2026-10-27 起即存在）。见[本轮记录](../../development/2026-10-28_zone1_petals_removed.md)。
- 2026-10-28：水面景观鱼群按两轮截图反馈修订（《散开 / 3 色 / 游得开》《浮在水面，要沉到 0.5–1.5 m》），见[本轮交付与验证记录](../../development/2026-10-28_fish_school_spread_palette.md)。资产 `SEA-DECO-ANIMAL-FISH-SCHOOL` 升 v007，`visual-fish-schools` 119 checks / 0 failures。水面色板按"透水后上屏"实拍标定重算。

## 2026-10-27 场景组件细分与动物恢复

见[本轮交付与验证记录](../../development/2026-10-27_scene_component_split.md)及[组件分类目录](../../../assets/registry/SCENE_COMPONENTS.md)。运行验证与素材授权分别登记；交互请求端口不代表玩家摆放编辑器已实现。

最终补验：decorations 1589项通过；visual-decorations 1592项通过（包含独立实例、真实鱼群近景和正常上浮环境恢复）。surface 503项/30航线、自检537项通过；静态契约32功能/426源资产/317运行哈希0问题。旧水下网页同机位测试缺基准未执行，单列在本轮记录。

## 2026-10-27 鱼群组件移植网页版

`decorative_fish_school.gd` 的鱼体与巡游动画改为移植网页版：水面群用 `web/fish-schools.js` 的扁胖型 + 薄荷青系，水下群用 `web/underwater-art.js` 的细长型 + 四色轮换。零件由 `animal_mesh.gd` 分段烘网格（身体 / 背脊 / 双眼 / 尾鳍），4 个 MultiMesh 绘制。单群个体按抖过的黄金角螺旋 + 两两互斥铺开（18 条，最近间距 ≥ 1.0 m），水面群抬到浪峰之上避免被半透明水膜洗白。

新增专项 `visual-fish-schools`，水面三条群 + 水下七群全部纳入断言与近景渲染证据。

同日第三轮修订（2026-10-28，按图反馈）：巨鲸改走 `toon.gdshader` 并开启网页版那个 `depth_tint`（`makePainterlyMat` 的第三个参数），此前它是 StandardMaterial3D，整条深度染色链路不存在，所以水下仍是一块死蓝；`toon_common` 补两个默认值等于原行为的 uniform（`depth_tint_strength`、`uw_glow_amount`），鲸取 2.0 / 0.60 / ambient 0.55，由四组实拍扫描定档。水面装饰群 18 → 10 条，巡游半径与最小间距改为随 `size_scale` 缩放（此前写死，鱼缩小后群被拉散成散点）。可捕捞群恢复网页版原尺寸，装饰群与交互目标就此分化。

同日第四轮修订（2026-10-28，按图反馈）：巨鲸材质退回普通 `StandardMaterial3D`，深灰 `#59606a`（鳍 `#4c525b`），`roughness 0.88`、`metallic 0`，默认 shading。**摘掉**上一轮加的三层演出：`toon.gdshader`、`depth_tint`（含 2.0 力度）、`ambient_boost` / `uw_glow_amount` 补偿，以及"背面 + 顶点外扩"的青色描边壳（7 个构件原本各多渲一遍）。此后鲸与场景里其它物体走同一条光照/阴影/后处理链路，不再单独作弊。

同日第五轮修订（2026-10-28，按图反馈）：鲸位置**锚定到阳光房海下基座倒数第三层楼板** `y=-11.86`（基座 7 层、间距 2.58，从底往上 `-17.02 / -14.44 / -11.86`），距水面 12.98 m，起伏幅度 0.65 → 1.3。定档依据是同机位实测的深度序列：`-3.6`（清晰）→ `-6.0`（清晰）→ `-9.0`（可读出鲸形）→ `-12.0`（只剩淡影，能辨尾鳍）→ `-15.0`（基本消失）→ `-18.6`（纯水面，完全不可见）。主人要的是"隐约剪影"，因此取 `-12` 这一档而非区间更深处。

**必须记住的约束**：海面世界与水下世界是两张独立地图，潜水时 `world_root` 整个隐藏。鲸挂在海面世界的 `environment.tscn` 下，所以它只能被水面俯视看到 —— 沉过 `-15` 就等于从游戏里消失，不是"藏起来了"。

`visual-fish-schools` 的材质断言整段反转：原先是"必须是 ShaderMaterial 且 depth_tint 开着"，现在是"必须是普通材质、不许自发光、不许 UNSHADED、不许有 Rim 壳、色相接近中性、亮度落在深灰区间、`y` 必须等于 `-11.86`、深度落在 12–14 m、起伏 ≥ 1.0 m"，共 12 条。把 `y` 写成等值断言是为了让"基座层高一旦改动"立刻红，避免锚定关系悄悄失效。

同日第二轮修订（按图反馈）：水面群与可捕捞群体型减半（0.5×），抬升量改为按体型自动计算，避免小鱼悬空；尾鳍从"轴向朝后的圆锥"改为显式三角网格横扇（俯视才读得出鱼尾），薄片材质双面渲。巨鲸按网页版 `web/gameplay.js` 构件表重建：头球 + 躯干球 + 两块 Box 胸鳍 + 圆锥尾段 + 一块 Box 尾鳍，皮肤 `#062356`、鳍 `#16589e`、青色 grow 描边；去掉网页版没有的椭球腹块、椭球尾鳍与球状眼。专项扩到 70 条断言，把体型倍率、贴水高度、鲸构件表都变成会失败的检查。

见[本轮交付与验证记录](../../development/2026-10-27_fish_school_port.md)。

### 同日第三轮修订

巨鲸改为走 `toon.gdshader` 并开启 `depth_tint`（对应网页版 `makePainterlyMat` 的第三个参数），鲸不再是水下的一块死蓝。`toon_common.gdshaderinc` 新增 `depth_tint_strength` 与 `uw_glow_amount` 两个 uniform，默认值等于原行为，既有沉没城市材质零影响；鲸取 2.0 / 0.60 / `ambient_boost` 0.55（实拍四组扫描定的）。水面装饰群条数 18 → 10，地盘半径按体型收紧到 1.5–1.65 m；个体最小间距改为随 `size_scale` 缩放（`0.60 m × size_scale × 1.70`），否则鱼缩小后相对间距翻倍、群读成散点。


## 2026-11-05 植被视效评估与制作设计

用户授权本阶段先评估、确定实现方案并落制作文档，已确认桌面 PC 优先。本批完成参考视频抽帧分析、当前代码与三个代表 GLB 的静态审计、官方文档研究和 ProtonScatter 固定提交的源码评估。**本批没有新增运行视效、安装插件或验收帧率。**

| 对应设计条款 | 当前实施状态 | 证据 / 下一阶段要求 |
|---|---|---|
| SEA-AMBIENT-R06 | 设计完成；实际美术 pending | [方案 §2](vegetation_visual_plan.md#2-视频参考哪些值得迁移)记录视频哈希与观察边界；需真实样板近/中/远录屏 |
| SEA-AMBIENT-R07 | planned；风函数与控制器未实现 | [方案 §5–6](vegetation_visual_plan.md)；需根固定、相干阵风、相位与暂停测试 |
| SEA-AMBIENT-R08 | 生产协议完成；源通道/导入/材质未实现 | [制作规范](../../standards/植被视效制作规范.md)；三代表 GLB 均无 COLOR/UV2，不能直接宣称可风动 |
| SEA-AMBIENT-R09 | 分层草苔方案确定；模型/真实渲染 pending | 现有青苔 POSITION 的 Z 包络为零；需苔垫/短绒小样与原生录屏 |
| SEA-AMBIENT-R10 | planned；分块/LOD/预算已设计 | 源码确认当前阳光房 flora 多为单实例 MultiMesh；新分组、动态包围盒、投影分级待实现 |
| SEA-AMBIENT-R11 | 所有权与迁移契约确定；接入 pending | [方案 §3/6/9](vegetation_visual_plan.md)；保留原生长/升级接口，迁移单株时关闭旧旋转 |
| SEA-AMBIENT-R12 | 源码评估完成；插件接入与中立导出 pending | 审计 HEAD `7198cc00078ebde61307578137c3f35223c6e438`，插件 v4.2.0；未安装/执行；缓存不是脱插件烘焙 |
| SEA-AMBIENT-R13 | 水面/水下策略确定；实际组合验证 pending | [方案 §10](vegetation_visual_plan.md)；水面浮动输入、两种海面实景和空间职责需验证 |
| SEA-AMBIENT-R14 | 性能目标与采样协议完成；所有性能数字未实测 | [方案 §8](vegetation_visual_plan.md)；目标机、GPU/CPU/显存/提交、60 FPS 整帧结果待 P0 采集 |
| SEA-AMBIENT-R15 | 阶段计划完成；正式场景迁移未执行 | [方案 §9](vegetation_visual_plan.md)；先小样，再渔场/阳光房，逐消费者推进 |
| SEA-AMBIENT-R16 | 文档与逐条账本建立；运行专项未注册/未执行 | [制作规范 §9](../../standards/植被视效制作规范.md)；后续统一 runner 增入口，不复用历史绿项 |

登记头、历史章节和原条款完整保留，未改 partial 状态；本轮只追加。相关资产制作管理归 SEA-ASSET-R49。完整证据、检查退出码及未执行项见[本轮交付记录](../../development/2026-11-05_vegetation_visual_plan.md)。


## 2026-11-05 阳光房草皮 v002 返工交付

| 对应设计条款 | 当前实施 | 证据与边界 |
|---|---|---|
| SEA-AMBIENT-R17 | 已改为贴图面片草皮：1301草簇、122苔藓贴片，原56株花草保留；屋顶牧场试铺撤回。原生近景/默认/宏观叶片和风动帧已制作；用户审美验收待反馈。 | [本轮交付与当前检查](../../development/2026-11-05_vegetation_soft_cards.md)；[复用手册](vegetation_soft_cards.md) |
| SEA-AMBIENT-R07/R08/R10/R11/R16 | 本轮阳光房采用单一GPU风时钟、根权重、RGBA图集例外、共享材质、空间分块、屏幕分级与显隐/暂停契约；原物件职责保持。 | vegetation-contract / visual-vegetation / visual-vegetation-performance 经统一runner；结果与失败历史见交付记录。 |
| SEA-AMBIENT-R09/R12/R13/R15 | 本轮完成阳光房草皮与低矮苔藓，不安装Scatter。草堆/花朵贴片重制、屋顶牧场新铺设、青苔短绒与水生植物尚未实施。 | 先完成用户指定的阳光房草皮；不以本轮小范围替代全植被系统完成。 |


## 2026-11-05 v002 当前实测结论

SEA-AMBIENT-R17及本轮R07/R08/R10/R11/R16覆盖项：六项统一runner实测全通过，退出码均0；2658项植被契约、56株原植物保留、16绘制批次、近景GPU p95增量0.273ms。完整镜头、动态、性能范围与全库文档门禁的无关阻塞见[当前验收附录](../../development/2026-11-05_vegetation_soft_cards.md#当前验收附录2026-11-05-1550-快照)。本轮仅阳光房贴图草皮与低苔，草堆花朵重制及屋顶牧场仍planned；用户审美验收pending。


## 2026-11-05 v003 宽叶与天台草堆当前交付

| 对应设计条款 | 当前实施 | 证据 |
|---|---|---|
| SEA-AMBIENT-R18 | v003两处宽叶草地及天台14处面片草堆已接入；风位移参数0.20/0.30米，阵风沿世界方向传播；远景保留草轮廓。原56株阳光房花草保持。六项统一runner均退出0，515336项植被契约无失败。用户审美验收pending。 | [实景、动态、性能与边界](../../development/2026-11-05_vegetation_meadow.md)；[当前复用手册](vegetation_meadow.md) |
| SEA-AMBIENT-R07/R10/R14/R16 | 同一风系统供草地/草堆两类资产、两个区域复用。52作者绘制批次，测得GPU p95增量阳光房0.053ms/天台0.501ms；CPU专项在初始预算内。未签署整帧锁60FPS或其他设备。 | 当前最终报告20261105-165018-meadow-final-7648b4；不复用v002结果。 |


## 2026-11-05 ProtonScatter原版试刷当前结论

| 对应条款 | 当前实施 | 证据与边界 |
|---|---|---|
| SEA-AMBIENT-R12/R18 | 已实际安装插件4.2.0/7198cc0，调用真实ProtonScatter＋Create Inside Random＋Randomize Transforms＋正负Shape。原版草11500、灌木42，共60批；可编辑预设重开仍生成11542实例。visual-proton-scatter及visual-proton-preview当前均退出0。 | [当前交付](../../development/2026-11-05_proton_scatter_trial.md)；[用法](proton_scatter_trial.md)。首次正式Main实拍与最终独立台验证分列，未冒充全世界集成通过。 |
| SEA-AMBIENT-R07/R11/R14 | 插件原版TIME风动、示例材质和模型在独立预览展示，未替换正式共用时钟。单一视效台测得根Viewport GPU p95 1.000ms，不签署全游戏锁60FPS；正式暂停/显隐接入及跨设备仍pending。 | 绿色版只改Gradient与wind_strength=.45；原模型、贴图、shader不改。 |


## 2026-11-06 植被跟随设施与场景内编辑

| 条款 ID | 实施状态 | 证据 |
|---|---|---|
| SEA-AMBIENT-R19 | 两处草皮分区、天台 14 个草堆、阳光房 56 个原花草均有保存到设施场景的调整节点。实际位置与朝向从当前主场景读取。正式草皮和草堆继续使用共享阵风。ProtonScatter 的真实生成批次及预览相机跟随预览设施。 | 契约 515315 项通过，两处正式场景实拍、ProtonScatter 11542 实例重开和移位通过。操作见[手动编辑入口](vegetation_meadow.md#在-godot-里手动摆放)，完整出口与集成失败见[开发记录](../../development/2026-11-06_vegetation_facility_editing.md)。 |

## 2026-11-07 纯观赏小鱼多海域扩布

| 对应条款 | 实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-AMBIENT-R22 | 已实装独立 `ScenicSeaFishSchools`，10群98条覆盖其他海域，阳光房同款surface/flat小鱼，原群保留。4750逻辑/几何断言、416真实图像断言无失败；20近景、3环境图已生成。 | [本轮记录与明确失败边界](../../development/2026-11-07_scenic_fish_distribution.md)。正式import通过，但运行退出资源错误导致runner仍FAIL，后续并行NPC编译阻塞；完整集成和verified晋升pending。 |

## 2026-11-07 阳光房独立水下预览生态（独立场景已验）

| 对应条款 | 实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-AMBIENT-R23 | ecology装配reef12原株/32簇、24灯具（Omni16/Spot8、局部阴影0），总成复用8群138鱼；56根接地最大误差1.907e-6米<.001，编辑器TSCN已固化。局部灯shader仅原镜片y6.774..6.826、x>=.674发光1.6，Point(1.075,6.8,0)，不写共享材质。ambient_source由错误3修为2并柔化，保留两版图过程，不改全局水或旧源 | 最终205426-signed报告sunroom-underwater67/0、visual89/0均exit0/PASS、无非预期错误；RTX4060Ti Vulkan Forward+、11真实视角，鱼/珊瑚/灯近景与全景已由父线程目检。[最终交付与失败过程](../../development/2026-11-07_sunroom_underwater_region.md)。仅独立预览，不新增碰撞/玩法，不接生产路由；来源、完整02b复用签署、性能、商业权属及用户美术验收仍pending，不冒称新Blender模型或默认开放。 |

## 2026-11-07 阳光房水下美术 r2（已独立验收，产品未接入）

初填时三项均pending，旧参数为环境depth fog6..100/curve1.65与8steps；仅保留该初填时点，不再代表当前方案。R23历史/登记头保留，物体阻挡归SEA-DIVE-R14，泡尘光束自身无碰撞。

| 对应条款 | 当前实施 | 当前证据 / 边界 |
|---|---|---|
| SEA-AMBIENT-R24 | runtime禁用环境fog，按旧图同序one opaque WaterFogPass、render_priority=-128；sunroom_underwater_color include统一6..110/curve1.3，天空/水顶/地形同一相机方向上下渐变，worldXZ448..500额外fade。透明粒子自雾＋alpha衰减；beam加色16steps/density基值0.085（每束增0/0.008/0.016）/soft cap0.23，采深度挡墙并继承同距离fade，不叠双雾。ambient0.48→深0.29、Sun0.60→0.30、Cool0.13、palette caustic0.075；压下泛白地板，水顶纹理gain0.18、正常水色。保留138鱼/32珊瑚/24实灯与10光束/192泡/200尘及sample/snapshot | 最终232826-signed：结构78/0、碰撞264/0、视觉118/0，新区域460/0；dive-maps302/0与modules31/0回归333/0，五入口总793/0全PASS/exit0、无unexpected。local env/sky/material均resource_local_to_scene保护多实例；far-fog-edge max0.0078431517、corner/west各0.0039215982均<0.025；射光shader开关lit_samples5365>150，已证实际可见，不止node计数。RTX4060Ti/Vulkan Forward+、18机位；父线程已目检home-base/ray-street/coral/fish/far-edge/corner-close，旧环境fog＋aerial1角落三角块改单通道后已审边角纯渐变无边，不冒称18图全细节人工签署。原9图/旧源/高度源、toplevel/位置范围深度保持，70保护项最终核对待父回填。本任务不改Main；Main 可能被并行修改，不要求 Main 字节不变。低端/连续性能、rights/完整02b及产品验收仍pending，未接生产路由/存档。[r2记录](../../development/2026-11-07_sunroom_underwater_art_r2.md)。 |

最终报告：`D:/projects/sea-work/verification/20261107-232826-sunroom-art-r2-signed-5f3e30/report.json`；verification关联三项新区域及dive-maps/modules回归，总793/0全PASS。默认射光、气泡、珊瑚、鱼与低照灯分列审阅，最终远角pure gradient已目检，近处实体边缘不等于远雾cut。225915为中间历史，不再称latest final待验；登记实际写入及sync/check真实输出由父线程补到开发记录静态门禁节。本次不改登记头/登记JSON，不运行命令。

## 2026-11-08 家园海底技术深化（SEA-AMBIENT-R25）

| 对应条款 | 当前实施 | 当前证据 / 边界 |
|---|---|---|
| SEA-AMBIENT-R25 | 本地 `WaterFogPass` 单通道；Environment fog关闭；palette本地深度吸收/饱和度/轻焦散；beam 16-step深度挡墙、上下软边、远景fade；角色深度驱动雾色；既有192泡/200尘/10束保留。参考官方Volumetric Fog/FogVolume、GPUParticles3D、Sky shader及水体depth/Fresnel/caustics资料，但未无条件开启体积雾、不改共享水/世界环境/原9图 | `D:/projects/sea-work/verification/20261108-123311-home-seabed-thirdperson-final-d703fe/report.json`：visual338/0、sunroom-underwater79/0、collision264/0，完整1241/0；第三人称实拍确认角色/潜水装备/旧城/街道/射光可见。低端GPU/连续性能/完整美术终审pending，不以资料或节点计数替代性能验收 |

家园海底 third-person/depth/layout 规则归 SEA-DIVE-R20–R23；技术链只拥有独立场景的本地材质与氛围，不得回写 `water.tres`、`world_env.tres`、shared city/seabed/base 或原9图。
## 2026-11-08 家园海底雾/环境对齐旧九图（SEA-AMBIENT-R26／R27）

| 对应条款 | 当前实施 | 当前证据 / 边界 |
|---|---|---|
| SEA-AMBIENT-R26 | 单通道 `WaterFogPass` 改用 zone1 同式指数雾与屏幕渐变；天空补 `AT_CUBEMAP_PASS` 双色；环境光 SKY 双色 + 深度衰减；glow/SSAO 关、方向光 0、FOV 55；palette 去逐材质深度染色只留焦散。删除方向渐变、`smoothstep(14,92)` 分层与 448..500 米 XZ 边缘吸收三处叠加 | 30 米处雾浓度 0.08→0.48，10/20/40/60/110 米分别为 0.085/0.264/0.658/0.892/1.0，与 zone1 同式同参数；`tests/test_sunroom_underwater_region.gd` 80/0；真实渲染器无着色器编译错误 |
| SEA-AMBIENT-R27 | 10 光柱顶到 50.12、长度 60~70 米、density 按 `22/长度` 反比；192 气泡升至 50.47；200 悬尘限 17 米带；粒子 `custom_aabb` 纵向 27→76 米。数量、种子、16 步深度挡墙积分不变 | 同上 80/0 覆盖气泡不越水面与光柱 on/off 实照亮像素；未开启全局体积雾 |

边界：本轮为参数与公式对齐，未新增粒子数、未改共享水材质/`world_env.tres`/原 9 图；低端 GPU 与连续运行性能、整段下潜观感、用户美术终审仍 pending。

## 2026-11-08 环境泡/呼气/增鱼承接（partial / PENDING）

登记头与原owner原样保留；本节补充 SunroomUnderwaterAtmosphere / UwDeco / DiverBreathBubbles / FishSchool 的纯表现职责，不取代已有植被/飞鸟所有者。

| 对应设计条款 | 当前实施状态 | 证据 / 待核验 |
|---|---|---|
| SEA-AMBIENT-R28 | 已读家园192泡/200尘/10beam、configure_water动态泡顶/材质/光柱/AABB，旧图96泡mesh/use_colors先于count与颜色写入 | sunroom_underwater_atmosphere.gd / uw_deco.gd；真实实例回读、time0/2上升、升降水位恢复与像素可见性PENDING，不据数量签视觉 |
| SEA-AMBIENT-R29 | 已有diver_breath_bubbles.gd固定48池、mask/head世界挂点、每簇4..7、基础间隔2..3秒、世界轨迹/动态AABB/alpha隐藏 | 当前寿命3.0..4.7秒，与发簇间隔区分；真实发出/脱离角色/回收/浅水可见PENDING |
| SEA-AMBIENT-R30 | Shared DiveRuntimeController创建并注入呼气，sample_effects消费实际速度比/水位深度，transition_frozen跳过 | 不持有或写Air，不写物理/输入/存档；暂停/切图卸载/同dt氧气无差别实测PENDING |
| SEA-AMBIENT-R31 | 家园TSCN保留原8群138，新增浅18+中22=10群178，新增ID08/09；旧UwDeco每群18→24、内容子集不改 | 复用fish_school，原群手摆变换不动；真实泳动、入水近浅层与纯装饰/无碰撞/非捕捞验收PENDING |

已核实本轮 runner `underwater-experience` / `visual-underwater-experience` 存在，仅在末尾关联，不重写登记头。真实视觉195/8、195/4均FAIL历史，后续修复正在跑，最终PENDING；不借旧793/0、1241/0或5196/0。主线程在[开发记录第5节](../../development/2026-11-08_underwater_optics_and_transition.md#underwater-optics-transition-acceptance)回填报告、像素对照与目检；本分支未跑测试/sync/check，低端/连续性能与用户终审未签。

### 本轮主线程最终验收

SEA-AMBIENT-R28–R31当前专项通过：`D:/projects/sea-work/verification/20261109-030908-underwater-breath-contact-db6f99/report.json`的visual-underwater-experience195/0、exit0/PASS；`20261109-031605-underwater-regression-final-2513b4`的underwater-experience65/0通过。旧96泡分配/颜色和实际像素可见已修，家园192泡/200尘/10束水位/AABB动态复验通过；呼气池48非奇异矩阵、真实mask前方出生、上升/膨胀/世界轨迹/退出清空/暂停过场冻结均通过。浅水呼气soft-contact0.08m，家园on/off差分300像素/peak0.04706，zone1为1090像素/0.18431，不仅计节点。家园原8群138保留，浅18中22总178、旧图每群24均实际实例/动画与像素差分通过，无捕捞或碰撞职责。旧195/8、195/4和195/1过程失败保留。

总体partial；低端/持续性能、完整昼夜/全路线/用户美术终审未签。全局sync69/只读70资源哈希门禁失败与框架52/1 second generation write另外记录，不写全工程通过。[完整签署](../../development/2026-11-08_underwater_optics_and_transition.md)。

## 2026-11-09 AmbientR32+ 环境泡尘承接（partial / PENDING）

登记头与原 owner 原样保留；本节仅登记环境表现，不改登记 JSON、不运行 sync。

| 对应设计条款 | 当前实施状态 | 证据 / 待核验 |
|---|---|---|
| SEA-AMBIENT-R32 | 家园192泡=96固定列+96邻域泡、200邻域尘；旧图96泡=48 vent+48邻域泡、180邻域尘；呼气48池不变 | `sunroom_underwater_atmosphere.gd:4-29,90-119`、`uw_deco.gd:1-20,85-164`；数量源码已核对，实际可见性待新批 |
| SEA-AMBIENT-R33 | world-space 连续mod wrap：observer XZ±12m/Y±8m，移动不粘泡，边缘fade1.5m，水面下至少0.77m | `sunroom_underwater_atmosphere.gd:187-194,290-324`、`uw_deco.gd:265-324`；0.5m移动 world position与边缘像素待签 |
| SEA-AMBIENT-R34 | Sunroom 由 Camera 设置 observer，旧 deco.update 由 Camera 更新；环境 Quad共享particles，环境soft contact0.18m，呼气0.08m | `sunroom_region.gd:165-178`、`underwater_world.gd:598`、`sunroom_underwater_atmosphere.gd:213-238`、`uw_deco.gd:85-164`、`diver_breath_bubbles.gd:42-56`；待真实画面对照 |
| SEA-AMBIENT-R35 | 验收矩阵含10/20/41/80m四 yaw、72°FOV、泡尘开关、正常视野周围应有可读浮游泡/尘 | 最新 `D:/projects/sea-work/verification/20261109-145508-underwater-targeted-depth-5b715a` 为179/32与436/35失败；当前新批仍运行，不借旧195/0 |
| SEA-AMBIENT-R36 | 保持 `partial` / PENDING；不扩展至 FSM/保存/鱼/布局/低端/长期性能/用户终审 | 4096水面尺寸试验无效并恢复1280；夹具box错配、节点入树前global赋值、远sky epsilon已修；全局框架写盘/哈希问题独立保留 |

最终签署见 [开发记录第8节](../../development/2026-11-09_underwater_middepth_visibility.md)。

### 本轮最终回填

SEA-AMBIENT-R32–R36专项通过，功能总体partial。最终报告`D:/projects/sea-work/verification/20261109-151955-underwater-middepth-signed-e09520/report.json`：underwater-experience179/0、visual-underwater-experience436/0；整合8入口4834/0、exit0/PASS、unexpected=[]。家园正常10/20/41m泡变化像素924/1069/1359、尘179/183/208，旧图泡339/505/426、尘67/50/86；四yaw及80m周围覆盖通过。移动0.5m家园87/87泡与167/167尘稳定，旧45/46泡与150/150尘稳定；边缘回卷不粘角色。192/200/10与96/180预算、48呼气池、用户摆位不变。动态AABB/真实回读/水面下边界通过。低端、持续性能、用户终审与全局门禁未签，首批179/32、436/35保留，不借旧样板签本轮。最新sync70/只读71登记问题阻断派生索引，同专项通过分列。
