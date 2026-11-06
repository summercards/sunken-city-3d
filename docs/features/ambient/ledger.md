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
    "visual-sea-fauna"
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
