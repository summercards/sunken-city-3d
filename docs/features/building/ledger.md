# SEA-BUILDING · 家园拼接建造 · 独立账本

同日最新修订：用户明确要求种植模型不挡人、可直接踩上去。R05按阻挡角色分类，R16登记可踩种植区；只改碰撞声明、行走/操作点/恢复资格投影，不改Farm、费用工期、承载重叠或奖励。[种植区通行交付](../../development/2026-10-29_walk_on_planters.md)。

后续初始六格修复（R05/R16，关联SEA-FARM-R12）：固定六格每次布局同步也生成统一操作点，保留模型位置、ID与可踩踏；Farm独立负责初始状态补齐。[本轮交付](../../development/2026-10-29_initial_six_planters.md)。

2026-10-29角色碰撞接入：本功能运行代码及规则保持输入内容；仅Main原geometry_changed回调通知ZoneScene刷新人物空间。动态中心域不二次内收；返船、跨板搬移、作物保留和退款见[角色框架交付](../../development/2026-10-29_character_physics_framework.md)。

[主文档](../../../GDD_V1.0.md#sea-building) · [设计](spec.md)

**2026-11-06当前口径：状态implemented（已实现待完整验收）。** r5统一横向平台5×5m，墙/梁跨度5m，竖向与阳光小屋实测层高5.086335m；楼梯宽1.5m×水平进深5m，共27级、每级爬升H/27，H为recipe总爬升且不重复scale，支持同层无间隙并排与首尾连续。`building_kit_5m.json`使定义总数为35、菜单可见22项；旧deck/12旧结构定义ID尺寸坐标与旧py2.8数据保留，根v4不加必填schema。四个建筑UI文件归`godot/src/building/ui`且UID保持，新增view/progress_presenter集中表现，锤子不在模式外常驻。本范围R30–R33最终专项已签署通过；触摸/手柄、低端GPU、任意规模与层数仍未覆盖，登记头保持implemented（已实现待完整验收）。[本轮开发记录](../../development/2026-11-06_building_5m_and_ui.md)。

```json
{
  "feature_id": "SEA-BUILDING",
  "status": "implemented",
  "owner": "BuildingService / BuildingWorld / BuildingController",
  "code_paths": [
    "godot/src/building",
    "godot/src/building/ui",
    "godot/src/navigation/ground_space.gd",
    "godot/assets/data/building_kit.json",
    "godot/assets/data/building_kit_5m.json",
    "godot/scenes/buildables/kit",
    "godot/assets/models/building_kit",
    "godot/assets/materials/building_kit"
  ],
  "verification": [
    "building",
    "building-open-rules",
    "building-space",
    "building-ocean",
    "building-integration",
    "building-restart",
    "building-open-restart",
    "visual-building",
    "visual-building-diy",
    "visual-building-ocean",
    "building-boundary-audit",
    "visual-building-boundary-audit",
    "walk-on-planters",
    "visual-walk-on-planters",
    "building-kit",
    "visual-building-kit",
    "ground-space",
    "kit-safety",
    "building-join",
    "building-save-compat",
    "visual-building-save-compat",
    "building-simulate",
    "visual-building-simulate",
    "visual-kit-uv",
    "visual-recipe-cards",
    "character-space-save",
    "building-decoupling",
    "building-perf",
    "building-surfaces",
    "visual-building-surfaces",
    "building-demolition",
    "building-5m-rules",
    "building-5m-experience",
    "visual-building-5m-experience",
    "building-ui-unified",
    "visual-building-ui-unified",
    "keyboard-building",
    "visual-keyboard-building",
    "building-scale-reference"
  ]
}
```

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-BUILDING-R01 | 已实现；手册分类卡片保留，建造/搬移均有目标虚影和拒绝原因；拆除独立锤子与确认 | [本轮交付](../../development/2026-11-02_building_surface_and_demolition.md) |
| SEA-BUILDING-R02 | 已实现；稀疏无圈数网格、船上独立基础、实际建筑与泊位保护 | [本轮实测](../../development/2026-10-29_open_ocean_building.md) |
| SEA-BUILDING-R03 | 已实现；保持原费用/工期，新增小型配方，拒绝/重复/取消不收费 | [本轮实测](../../development/2026-10-29_open_ocean_building.md) |
| SEA-BUILDING-R04 | 已修复；新旧摆件共用同高间距/承载，0.1/0.01米自由摆位，混合搬移在提交前拒绝不合法间距 | [本轮交付](../../development/2026-11-02_building_surface_and_demolition.md) |
| SEA-BUILDING-R05 | 已修复；同源三维通路检查，家具切口共享顶点，阻止拆桥/唯一返程梯及封路；水线仅水面平台 | [本轮交付](../../development/2026-11-02_building_surface_and_demolition.md) |
| SEA-BUILDING-R06 | 已修复；全部记录同时参与几何校验、顺序无关；平台与培养土py进JSON，旧坐标不重排 | [本轮交付](../../development/2026-11-02_building_surface_and_demolition.md) |
| SEA-BUILDING-R07 | 已实现；无全局纯规则、提交锁、容量/支付/退款注入及回调重入拒绝 | [本轮实测](../../development/2026-10-29_open_ocean_building.md) |
| SEA-BUILDING-R08 | 已实现；木板顶面/吃水厚度不变，小型培养土按目录尺寸投影 | [本轮实测](../../development/2026-10-29_open_ocean_building.md) |
| SEA-BUILDING-R09 | 已实现；细条保留，全部木板参与状态，近景泡沫预算不再限制布局 | [本轮实测](../../development/2026-10-29_open_ocean_building.md) |
| SEA-BUILDING-R10 | 已实现；岸上接近与船上航行到位、停稳才扣费、取消清意图 | [本轮实测](../../development/2026-10-29_open_ocean_building.md) |
| SEA-BUILDING-R11 | 已修复；搬移继承高度并显示目标虚影，二层种植状态/ID保留；取消不改变原物 | [本轮交付](../../development/2026-11-02_building_surface_and_demolition.md) |
| SEA-BUILDING-R12 | 已实现；独立锤子→悬停轮廓→是/否确认→接近重验与全额原子退款；角色/作物/依附/三维通路保护 | [本轮交付](../../development/2026-11-02_building_surface_and_demolition.md) |
| SEA-BUILDING-R13 | 已实现；派生`built:实例ID:方向`登陆ID，独立平台可航行登陆、由当前登陆点返船 | 同上 |
| SEA-BUILDING-R14 | 已实现；目录声明category/role/support/footprint/visual，服务按平台-框架-装饰三类识别 | [平台归一交付](../../development/2026-10-31_platform_join_classes.md) |
| SEA-BUILDING-R15 | 已实现；4MiB布局/8MiB整档预算在扣费前拒绝，虚影与水线为表现预算非上限 | [海上自由建造交付](../../development/2026-10-29_open_ocean_building.md) |
| SEA-BUILDING-R16 | 已实现；固定六格与DIY双尺寸可踩踏，成熟蔬菜穿越状态不变；站格保存恢复和外缘阻挡通过 | [种植区通行实测](../../development/2026-10-29_walk_on_planters.md) |
| SEA-BUILDING-R17 | 已实现；上岸提示12米/最多4个、100px投影间距，稳定ID复用对象与悬停状态 | [稀疏提示交付](../../development/2026-10-30_sparse_landing_markers.md) |
| SEA-BUILDING-R18 | 已实现；目录集中声明22件内容与尺寸/成本/工期/挂点，停用退出菜单但保留旧实例 | [模块化套件交付](../../development/2026-10-30_modular_building_kit.md) |
| SEA-BUILDING-R19 | 已实现新口径；结构在实际平台平面自由摆位，上层墙/栏杆/新楼梯可用；平台不再要求四角柱齐 | [本轮交付](../../development/2026-11-02_building_surface_and_demolition.md) |
| SEA-BUILDING-R20 | 已修复；梯顶直接续普通木板/浮台，真实胶囊上二层、家具跨缝导航、上层种植与JSON恢复通过 | [本轮交付](../../development/2026-11-02_building_surface_and_demolition.md) |
| SEA-BUILDING-R21 | 已实现；10摆件独立成件，两灯真实暖光、箱子共享仓库、水桶补水，风车风铃仅动画 | 同上 |
| SEA-BUILDING-R22 | 已扩展；普通木板/两种浮台/旧二层板统一按高度接边，梯顶提供新平面起点，独立海面仍须乘船 | [本轮交付](../../development/2026-11-02_building_surface_and_demolition.md) |
| SEA-BUILDING-R23 | 已修复并补验；原模板与新增二层家具切口、自由组合和实际胶囊通行均有本轮证据 | [本轮交付](../../development/2026-11-02_building_surface_and_demolition.md) |
| SEA-BUILDING-R24 | 已修正门禁；夹具逐块验证成功并实测9/25/45/100块，纯吸附近线性；不外推完整GPU帧率 | [本轮交付](../../development/2026-11-02_building_surface_and_demolition.md) |
| SEA-BUILDING-R25 | 已实现；固定浮台的水下底座不再算「既有建筑」，浅水养殖台四面均可接板（28 项 0 失败） | [底座阻挡修复](../../development/2026-11-01_energy_fishery_and_join.md) |
| SEA-BUILDING-R26 | 已修复；实际网格点选保留门洞，管理选取独立于水平投射，目标轮廓/名称/原因及确认明确 | [本轮交付](../../development/2026-11-02_building_surface_and_demolition.md) |
| SEA-BUILDING-R27 | 已实现；四种平台梯顶续建，同高度承载/上层墙栏杆种植家具；5.6米继续衍生有纯规则证据 | [本轮交付](../../development/2026-11-02_building_surface_and_demolition.md) |
| SEA-BUILDING-R28 | 已实现；自由0.1/0.01米、G辅助吸附、U/H选层、搬移虚影、实际镜头滚轮与确认锁定通过 | [本轮交付](../../development/2026-11-02_building_surface_and_demolition.md) |
| SEA-BUILDING-R29 | 已实现；专用锤子按钮/指针、悬停轮廓、默认否、是/否鼠标与Esc层级，取消无修改、确认仅退款一次 | [本轮交付](../../development/2026-11-02_building_surface_and_demolition.md) |
| SEA-BUILDING-R30 | 已实现并最终专项通过；新增10件后35 definitions、菜单22项；平台5×5m、墙梁5m、门洞1.85×3.1m；楼梯1.5m宽×5m水平进深，不是5×5m宽；小家具/培养土保持各自recipe尺寸，旧定义兼容保留 | `building-5m-rules`446/0、`building-5m-experience`589/0；签署报告`D:/projects/sea-work/verification/20261106-222059-building-5m-release-signed-2a186b/report.json` |
| SEA-BUILDING-R31 | 已实现并最终专项通过；recipe总爬升H只应用一次，实际底/顶高支持2.8m+5.086335m混合平面；楼梯同层无间隙并排、首尾连续及安全校验通过 | `building-5m-rules`446/0、`building-5m-experience`589/0、`visual-building-5m-experience`597/0；同签署报告 |
| SEA-BUILDING-R32 | 已实现并最终专项通过；集中Toolbar按钮无键名、无常驻按键教程，保留失败灰因/选择轮廓、材料确认与安全细节、返回链；锤子仅模块内显示 | `building-ui-unified`66/0、`visual-building-ui-unified`66/0、`keyboard-building`40/0；同签署报告及[UI账本](../ui/ledger.md) |

`code_paths`中的`godot/src/navigation/ground_space.gd`仅登记建筑坡面通行的适配依赖，不转移导航所有权；GroundSpace仍只拥有派生碰撞/导航，不拥有建造布局。签署报告确认`ground-space`37/0、`character-space-save`10/0、`building-surfaces`80/0、`building-open-rules`122/0、`building-perf`239/0、`building-decoupling`62/0、`building-restart`11/0、`building-open-restart`8/0、`save-protection`通过，均来自`D:/projects/sea-work/verification/20261106-211435-building-5m-final-816d34/report.json`及日志。坡脚sharedpoint与胶囊接触法线修复已确认，不放宽WalkAction。

2026-11-02 R02/R06/R22补验：玩家副本25实例及作物恢复，旧自由浮台可继续接木板；新显式坐标木板与旧网格混合存读、三维点选拆回各39项/0失败。R11/R12真实鼠标29项、卡片108项、65实例跨进程70+8项及原有拼装/通行回归全部退出0，非预期引擎错误0。[本轮交付与过程失败](../../development/2026-11-02_building_save_compatibility.md)。

实施与验证记录：[本轮交付](../../development/2026-10-28_building_delivery.md)。

2026-10-29收尾：当前集成38检查通过；独立两进程冷启动5+8检查通过，坏档保护通过；15服务架构边界检查通过。

2026-10-29 00:32–00:40 复验（并行作物接入后的当前工作区）：`building` 20项、`building-integration` 38项、`building-seed` 5项、`building-restart` 8项、`visual-building` 19项全部PASS；同轮`farming` 35项、`minimum-loop` 77项、`framework-modules` 50项、`pocket-services` 28项、`save-corrupt-seed`、`save-protection`全部PASS。`check_architecture.py` 15服务0问题。`check_feature_contracts.py --sync`在00:35:16的窗口内为0问题，但随后并发的作物资产重写使crop源/运行期哈希漂移与`crops`高度断言失败，全局门禁当前为红，均由并行SEA-CROP任务承担，本功能未代其重算。`visual-building`首次在未导入的隔离工程中因新作物纹理缺失报20项资源错误，属并行作物的导入前置条件，`--import-assets`后复跑通过；该次失败不计作建造回归。证据目录`D:/projects/sea-work/verification/`下`20261029-003237-building-resume-7f7eed`、`20261029-003346-building-resume-visual-975be0`、`20261029-003551-building-resume-integration-8b4e07`。

2026-10-29最终收尾：上述并行临时红项已清除。`--sync`及无参功能检查均PASS（35功能、459源资产、387运行期哈希、0问题）；架构检查15服务0问题。`20261029-080045-building-visual-layout-d983d2`导入及真实渲染再次PASS，鼠标/按键19检查0失败；已查看书本、虚影与种植完成截图。测试补齐初次点击前的延迟布局等待，002616超时轮保留为失败记录。

2026-10-29 11:40–11:55 种植区摆位修正（R04）：旧判定把单块板内缩12厘米当边界，x容差仅±5.8厘米，比0.1米吸附步长还窄，因此光标离开板中心两三个像素就红，玩家实际上建不出种植区；同时`support`板只允许一格，跨板摆放不可能。改为以已完工木板的**并集**为边界（4厘米外缘边距）、只禁止与已有种植区重叠，`walk_rects` 对每块板减去每一个种植区footprint，接近点被拉回最近走道；越出木面不足0.4米时由`snap_planter`吸到最近合法格点，重叠与压角色不吸。`support` 降为主支撑板，旧档仍全部合法。`building` 29项、`building-integration` 38项、`building-restart` 8项、`building-seed` 5项、`visual-building` 21项全部0失败（新增接缝覆盖/单侧越界/缺口越界/偏离中心可建/贴边吸回/远处仍拒6条断言）。首轮`visual-building`有`rotate key`冷启动抖动，连续两轮复跑PASS并保留该失败记录。

## 2026-10-29 建造要先走到工地

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-BUILDING-R10 | 已实现；点击虚影只排队，角色走到格子旁站定才扣材料开工 | [交付记录](../../development/2026-10-29_build_requires_approach.md) |

旧实现 `handle_input` 里点击虚影直接 `service.begin(preview)`：五米外点一下，
木板上就自己长出了进度条 —— 建造读起来像在 map 上点按钮，而不是在自己家里动手。

新增 `building-approach` 专项：18 项断言，实测 `18 checks, 0 failures`，退出 0。
覆盖：人还在远处时不开工也不扣料、等待期间虚影锁在目标格、走到位自动开工且只扣一次、
开工后人确实站在工地边、退出建造模式清排队且不再自己开工、站在旁边点一下当场开工。

控制器新增三个注入端口（`stand_point` / `approach` / `actor_state`），不读全局。
`_construction_stand_point` 沿「角色这一侧」由近到远探 1.15/1.5/1.9/2.4 米，
取第一个落在可走矩形且有通路的位置 —— 新木板格本身还没进可行走面，不能直接拿格心当目标。

同轮复跑：`building` / `building-integration` / `building-restart` / `visual-building`（24 项）
/ `unreachable-menu` / `interact-focus` / `board-click` / `farming` / `modules` / `pocket-bubbles`
全部退出 0。整体状态仍 partial（拆除与海上施工未做）。

## 2026-10-29 外围木板不可建与机制完整性审计

本节为当前状态；此前通过记录只说明其覆盖样例，不能覆盖本轮新反例。登记头改为`partial`，原因是R04/R06已有目标未闭环，而非把明确不开放的拆除/海上施工算作失败。

最终`building-boundary-audit`与真实渲染`visual-building-boundary-audit`各31项、退出0：成功复现固定两圈边界、泛化提示、实际0.1米吸附布局缺角色通行宽度检查，以及24新板+36箱共60实例被存档54上限拒绝。另单独复现服务/快照端接受非吸附坐标的封路布局，以及此布局下不可达格仍提示点击施工，明确不把该服务层反例当成鼠标吸附直接复现。**审计探针通过表示反例复现成功，不代表建造机制验收通过。** 其中R06为P1保存风险；R04/R05通行宽度、服务层完整性及边界显示/提示列P2。

同轮原有专项：`building`29项、`building-approach`18项、`building-integration`38项、`building-seed`5项、`building-restart`8项均退出0；真实输入`visual-building`结果及完整证据见[审计记录](../../development/2026-10-29_building_boundary_audit.md)。本次未修改玩法限制、费用、布局状态或玩家存档。

## 2026-10-29 海上自由建造与DIY交付（当前口径）

本节按用户最新范围替代上方“两圈/不支持搬移拆除”的历史阶段；旧审计结果保留，不再把已修缺口作为当前结论。登记头为implemented（已实现待完整验收），不代表任意数量/任意远坐标性能或所有设备已验收。

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-BUILDING-R11 | 已实现；带作物搬移保留稳定ID、浇水/生长与原节点，取消不改现场 | [本轮交付](../../development/2026-10-29_open_ocean_building.md) |
| SEA-BUILDING-R12 | 已实现；空摆件/安全板拆回，全额原子退款；有作物、桥板、当前泊位等拒绝 | 同上 |
| SEA-BUILDING-R13 | 已实现；派生稳定登陆ID，独立平台航行→登陆→返船，冷热恢复 | 同上 |
| SEA-BUILDING-R14 | 已实现；目录role/support/footprint/visual元数据与注入策略，未来内容有明确适配入口 | 同上；尚未制作墙/门/家具/多层等未来内容 |
| SEA-BUILDING-R15 | 已实现；技术字节容量在扣费前拒绝，虚影96/水线24局部预算，稀疏坐标与局部航路 | 同上；不宣称任意无限实例帧率 |

当前专项、真实渲染、过程失败、退出码与未执行项集中记录在[交付记录](../../development/2026-10-29_open_ocean_building.md)。玩家存档未被用作测试槽，也未因本次规则更新强制重置。

2026-10-29最终收尾：建造纯规则120、空间15、集成39、海上真实渲染30、DIY真实输入28、边界回归51、大布局跨进程70+8、旧档迁移5+11全部0失败/退出0；最小循环77、种植35、上下船12、睡觉33及坏档保护通过。架构15服务0问题；功能同步与无参检查35功能/459源资产/392运行期哈希0问题。详见[机器证据](../../development/2026-10-29_open_ocean_building_verification.json)。

## 2026-10-30 上岸提示稀疏与闪烁修复

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-BUILDING-R17 | 已实现；4米/8个提示改为12米/最多4个，100px投影间距；稳定ID复用对象和悬停状态，当前返船入口优先 | [本轮交付](../../development/2026-10-30_sparse_landing_markers.md) |

R13的实际登陆边、航行/登岸/返船和存档格式保留，改动仅是派生提示选择与展示状态。闪烁根因：BuildingAccess每0.75秒删除再创建visible=false、near=0的字典，刚好发生在LandingMarkers当帧处理之后，导致下一次绘制缺图标且反复从小尺寸开始。现为按zone/landing同步，留存有效提示并保留插值进度。完整退出码、实景与过程失败见本轮交付。

本轮收尾：landing-markers与visual-landing-markers各25项/0失败，海上登陆/返船与board-click回归均退出0；功能同步及无参检查35功能/460源资产/393运行期哈希0问题，架构15服务0问题。见[机器证据](../../development/2026-10-30_sparse_landing_markers_verification.json)。

## 2026-10-30 模块化建筑与生活摆件

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-BUILDING-R18 | 已实现；25配方分类卡片、真实鼠标78检查通过；停用拒新建且保留历史存档 | [本轮记录](../../development/2026-10-30_modular_building_kit.md) |
| SEA-BUILDING-R19 | 已实现；12结构全部经正式Service/World建成，完整承载、依附拆除、门洞通行/实墙阻挡通过；旧板承载及4×4精确贴边/通路回归通过 | 同上；规则72项、完整游戏121项0失败 |
| SEA-BUILDING-R20 | 已实现；真实胶囊爬升、二层根快照恢复、上下层站位保护及楼梯/楼板拆除保护通过；实际渲染核对楼梯同向 | 同上；ground-space及character-space-save回归通过 |
| SEA-BUILDING-R21 | 已实现；10摆件全部在正式世界建成，真实暖灯、共享仓库、补水、摆动通过；22组件UV/材质563项及真实卡片渲染通过 | 同上；不提供电网和风铃声音 |

2026-10-30最终收尾：R01改为每卡仅图片+名字+消耗，R04承载包含固定木面和新旧板并集；原六箱占地保留。完整游戏121项、真实渲染120项、卡片真实鼠标78项、UV/材质563项、纯规则72项全部0失败/退出0；旧建造、集成、开放规则、三维空间与位置恢复专项通过。资产状态仅晋升本套件22件，不覆盖其他pending资产。全部结果和未执行设备项见[机器证据](../../development/2026-10-30_modular_building_verification.json)。

## 2026-10-31 平台归为一类

用户实测指出拼接木板能接、能走，4×4／2×4 浮台却拼不上并隔出一条缝；要求按「两类」收敛，且不能隔空造。本轮把平台类（旧板＋两种浮台）合成一套贴边拼接与连接体规则，框架件维持挂点要求。

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-BUILDING-R22 | 已实现；三种平台共用边对齐吸附（齐平优先、按光标到矩形距离取舍）、0.6米接缝门槛、跨缝行走；岸上隔空起板被拒，船上可另起独立起点；旧档孤立平台照常读档与拆除 | [本轮交付](../../development/2026-10-31_platform_join_classes.md) |
| SEA-BUILDING-R02 | 已实现（口径修订）；不再允许岸上“不相连的独立基础”，独立起点仅船上 | 同上 |
| SEA-BUILDING-R14 | 已实现（口径修订）；目录识别 platform/structure/decoration，行为两类 | 同上 |

改造前实测反例：4×4 在旧板边 0–2.5 米范围内全部落回世界 2 米网格，与旧板重叠 0.775–2.775 米；2×4 在 0.5 米处给出 0.225 米真空缝；900 米空旷海面可直接起板。根因是贴边候选被 1.45 米光标半径挡死、沿边吸附到 1 米节拍、以及 foundation 分支没有连接检查。

本轮收尾：`building-join` 37项、`building-open-rules` 122项、`building` 30项、`building-space` 18项、`building-integration` 53项、`kit-safety` 72项、`building-kit` 121项、`building-approach` 18项、`building-restart` 11+5项、`ground-space` 33项、`character-space-save` 10项、`visual-recipe-cards` 108项（真实鼠标）、`visual-building`与`visual-building-kit`（真实渲染）全部0失败/退出0。三条旧断言按新口径反转；另修了`visual-building`直接点隐藏卡片的测试缺陷（应先切种植页签），记录见交付文档。手机触屏与手柄专项本轮未执行。

## 2026-10-31 全模板模拟验收与挂点遮蔽修复

用户要求模拟一遍全部框架拼装、角色通行（斜面除外）、摆件落到新平台、存档与其它问题。模拟在正式场景按鼠标路径装配，用真实胶囊行走，再走整档存读。

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-BUILDING-R23 | 已实现；12 框架全部拼装成功，10 摆件全部落到新建浮台并集内，真实胶囊跨缝通行与爬楼梯到二层，两种屋顶均不产生行走面，整档存读 31 实例逐字段一致 | [本轮交付](../../development/2026-10-31_full_template_simulation.md) |
| SEA-BUILDING-R06 | 已修复；挂点判定不再只取第一个匹配，柱角与墙端共点时全部共有者计入承载，构建顺序不再影响合法性与读档 | `building-simulate` 191项、`kit-safety` 75项（新增3条顺序断言） |

真实缺陷：`Assembly.bearing_ids` 对每个必需挂点只认第一个命中构件。柱角与墙端同点时，若墙先入列，楼板的 `support`（指向柱）就不在承载依据里，报“顶部挂点缺少完整的立柱或墙体支撑”——先建墙后建柱再建楼板会被误拒；同样几何换个顺序却能建。这同时违反 R06「不依赖创建顺序」：布局可能建成后被自己的存档校验判无效。修复为收集该点全部共有者。反向验证：临时放回旧实现，`kit-safety` 立即两条断言失败，恢复后 75 项 0 失败。

模拟首轮 21 项失败中 18 项是夹具写错（漏加世界原点、世界/局部坐标混比、木料设 4000 超出 40×24 上限），已逐条记录以免误判为产品问题。其中“背包满时回收整笔失败并保留物件”是 R12 既定语义，非缺陷。

本轮收尾：`building-simulate` 191项、`kit-safety` 75项、`building` 30项、`building-join` 37项、`building-open-rules` 122项、`building-space` 18项、`building-integration` 53项、`building-kit` 121项、`building-restart` 11+5项、`building-approach` 18项、`ground-space` 33项、`character-space-save` 10项全部0失败/退出0。

## 2026-10-31 解耦与可独立维护审计

用户询问本功能文档账本与程序模块是否解耦、能否独立维护。结构层合格（依赖单向、装配集中15端口、查询回副本、条款与账本行由`requirements==covered`强制对齐）；修掉两处登记缺陷与一处无守卫契约。

| 项目 | 结论 | 处理 |
|---|---|---|
| 内容目录共享可变对象 | `Catalog.RECIPES`是`static var Dictionary`，卡片价格/扣费/投影共读同一对象，外部改价删条目无人察觉 | 新增`Catalog.verify_content()`内容指纹，改定义/删条目/加条目均报差项，`active`开关不算腐化；`building-decoupling`守 |
| `code_paths`漏登记 | 只写`godot/src/building`，漏`building_kit.json`、22预制体、44 GLB、4材质 | 已补齐四项 |
| 账本总表覆盖 | 原只到R16，R11–R15与R17–R23散在日期段落 | 已收全R01–R23共23条 |
| `validate_snapshot`字符串自引用 | `load("res://src/building/building_service.gd")`，改文件名编译期查不到 | 新增扫描6个文件的`load`路径存在性断言；第一版守卫失效（只查文件存在），已加强并反向注入验证 |
| `hud.gd`取`material_shop.PRICE` | UI反向依赖功能实现，但仅一个`const`，定价职责本属本模块 | 判定可接受，登记为已知依赖 |
| 目录硬读`FileAccess` | 无法注入替身，缺失只能`assert`崩 | 设计取舍，代价已记录 |

`building-decoupling` 62项0失败：内容指纹可检测、查询返回副本、不依赖`Economy`/`GameState`/`Zones`/`res://tests/`、每条配方经公开API可解析、全部字符串式`load`路径有效。

完整评估见[解耦审计](../../development/2026-10-31_building_decoupling_audit.md)。

## 2026-11-06 键盘建造与无教程表现

| 对应设计条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-BUILDING-R33 | 已实现并验收该键盘链：K入口、可见卡首焦点、方向与分页、相机相对游标0.1/0.01米、原通道单次提交扣料、鼠标/键盘切换、搬移保留作物、拆除默认否/安全拒绝与仅退款一次。操作无常驻教程，保留轮廓、业务状态、受阻原因及安全确认。 | `keyboard-building`最终222059 release-signed报告40/0、exit0；既有`visual-keyboard-building`43/0、exit0真实渲染证据保留，见[全键盘交付](../../development/2026-11-06_keyboard_complete.md)。R30/R31几何及多层专项另由本任务signed报告验收，不以键盘检查代签任意组合或发行包。 |

## 2026-11-06 五米建筑最终签署

最终报告：`D:/projects/sea-work/verification/20261106-222059-building-5m-release-signed-2a186b/report.json`。13项均`passed=true`、`exit_code=0`、`completion_marker=true`、`unexpected_errors=[]`；前12专项合计2965 checks/0 failures，另1项几何守卫按rows独立记录：`building-5m-rules`446/0、`building-5m-experience`589/0、`visual-building-5m-experience`597/0、`building-ui-unified`66/0、`visual-building-ui-unified`66/0、`keyboard-building`40/0、`kit-safety`94/0、`building-kit`221/0、`building-save-compat`37/0、`building-integration`56/0、`keyboard-farm-loop`606/0、`minimum-loop`147/0；`building-scale-reference`62 rows/0 failures，实测5.08633422851563m对目录5.086335m、容差0.002m，PASS且exit0，不并入checks合计。真实渲染在RTX4060Ti/Forward+执行；最新机器汇总`visual_review.source_directory`已指向222059副本`project/outputs`，主线程目检四图为`building-5m-ui.png`、`building-5m-parallel-preview.png`、`building-5m-confirm.png`、`building-5m-overview.png`。20个代码文件与新副本完全一致；最新机器汇总44项`signed_source_comparison`均`matches_signed=true`，本段记录该主线程核对结果，非本轮重新运行比较脚本。

release新增修复：Controller生成新5m平台preview时与旧deck同样传递`origin=boat/shore`，避免船上独立起点确认误拒；岸上隔空起板仍拒绝，取消预览不收费。`building-integration`从53增为56，覆盖新增3条船上/岸上预览路径。213331先签报告`D:/projects/sea-work/verification/20261106-213331-building-5m-signed-e9ca1f/report.json`的12项2962/0保留为历史，本次最终签署已由222059替代。

补充报告`D:/projects/sea-work/verification/20261106-211435-building-5m-final-816d34/report.json`的通过项：`ground-space`37/0、`character-space-save`10/0、`building-surfaces`80/0、`building-open-rules`122/0、`building-perf`239/0、`building-decoupling`62/0、`building-seed`5/0+`building-restart`11/0、`building-open-seed`70/0+`building-open-restart`8/0；`save-protection`exit0，实际日志`ok=true protected=true unchanged=true separate=true`，不虚构checks数。

P1高空孤台/循环支撑存档绕过已在Service按rooted支撑修复：无支持的新旧高空布局均拒绝，地面历史孤立布局合法；GroundSpace坡脚sharedpoint及胶囊法线修复4.7cm stuck，不放宽WalkAction。未修改main场景手摆、阳光小屋位置尺寸或玩家真实存档。

过程失败保留：211435中`kit-safety`94/7、`building-kit`141/8已由signed94/0、221/0收口；同旧报告`farming`35/2仍是13地格/3床（含已移除圆弧农场）的历史fixture残留，不修改业务凑通过，也不由键盘农场606/0掩盖。最终已执行全局sync与无参检查，分别4/5问题：水下派生视图、动物源、水材质、并行Main哈希及派生索引；本功能条款/路径/哈希无残留，不批量接纳其他改动。架构17服务0问题、diff检查0。触摸/手柄、低端GPU、任意规模层数未验，因此feature仍implemented（已实现待完整验收），R30–R33本范围已通过。[任务交付](../../development/2026-11-06_building_5m_and_ui.md)；[机器汇总](../../development/2026-11-06_building_5m_verification.json)已绑定最新release-signed，13项全PASS，其中12专项2965 checks/0 failures，另几何守卫62 rows/0 failures。
