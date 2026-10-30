# SEA-BUILDING · 家园拼接建造 · 独立账本

同日最新修订：用户明确要求种植模型不挡人、可直接踩上去。R05按阻挡角色分类，R16登记可踩种植区；只改碰撞声明、行走/操作点/恢复资格投影，不改Farm、费用工期、承载重叠或奖励。[种植区通行交付](../../development/2026-10-29_walk_on_planters.md)。

后续初始六格修复（R05/R16，关联SEA-FARM-R12）：固定六格每次布局同步也生成统一操作点，保留模型位置、ID与可踩踏；Farm独立负责初始状态补齐。[本轮交付](../../development/2026-10-29_initial_six_planters.md)。

2026-10-29角色碰撞接入：本功能运行代码及规则保持输入内容；仅Main原geometry_changed回调通知ZoneScene刷新人物空间。动态中心域不二次内收；返船、跨板搬移、作物保留和退款见[角色框架交付](../../development/2026-10-29_character_physics_framework.md)。

[主文档](../../../GDD_V1.0.md#sea-building) · [设计](spec.md)

```json
{
  "feature_id": "SEA-BUILDING",
  "status": "implemented",
  "owner": "BuildingService / BuildingWorld / BuildingController",
  "code_paths": [
    "godot/src/building"
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
    "visual-kit-uv",
    "visual-recipe-cards",
    "character-space-save"
  ]
}
```

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-BUILDING-R01 | 已实现；25配方分类/分页卡片，每卡图片+名字+消耗；搬移/拆回与虚影理由保留，鼠标78项通过 | [本轮实测](../../development/2026-10-29_open_ocean_building.md) |
| SEA-BUILDING-R02 | 已实现；稀疏无圈数网格、船上独立基础、实际建筑与泊位保护 | [本轮实测](../../development/2026-10-29_open_ocean_building.md) |
| SEA-BUILDING-R03 | 已实现；保持原费用/工期，新增小型配方，拒绝/重复/取消不收费 | [本轮实测](../../development/2026-10-29_open_ocean_building.md) |
| SEA-BUILDING-R04 | 已实现；承载并集、跨缝、双尺寸、旋转、0.1/0.01米摆位 | [本轮实测](../../development/2026-10-29_open_ocean_building.md) |
| SEA-BUILDING-R05 | 已实现；0.22米角色宽度、连接/操作点保护、船阻挡和水线增量 | [本轮实测](../../development/2026-10-29_open_ocean_building.md) |
| SEA-BUILDING-R06 | 已实现；移除54上限、支撑顺序无关校验、65实例跨进程恢复及旧边缘迁移 | [本轮实测](../../development/2026-10-29_open_ocean_building.md) |
| SEA-BUILDING-R07 | 已实现；无全局纯规则、提交锁、容量/支付/退款注入及回调重入拒绝 | [本轮实测](../../development/2026-10-29_open_ocean_building.md) |
| SEA-BUILDING-R08 | 已实现；木板顶面/吃水厚度不变，小型培养土按目录尺寸投影 | [本轮实测](../../development/2026-10-29_open_ocean_building.md) |
| SEA-BUILDING-R09 | 已实现；细条保留，全部木板参与状态，近景泡沫预算不再限制布局 | [本轮实测](../../development/2026-10-29_open_ocean_building.md) |
| SEA-BUILDING-R10 | 已实现；岸上接近与船上航行到位、停稳才扣费、取消清意图 | [本轮实测](../../development/2026-10-29_open_ocean_building.md) |
| SEA-BUILDING-R16 | 固定六格与DIY双尺寸可踩踏，成熟蔬菜穿越状态不变；站格保存恢复和外缘阻挡通过 | [种植区通行实测](../../development/2026-10-29_walk_on_planters.md) |

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
