# SEA-SHOP · 花店与综合商店 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-shop) · [功能文档](spec.md) · [NPC 功能](../resident/spec.md)

## 2026-11-07 19:40 覆盖与验收边界（七人全天台历史；本轮以文末22:39覆盖）

两商店和经营者保留、NPC与Shop独立；本轮入口随七人迁到rooftop_ranch天台草地，用户手摆root下NpcStations的35个局部Marker随scene变换，不固定世界坐标。七人当前无物理房屋，UI仅写“暂驻天台”。旧两住商房屋空间仅历史资源，SEA-RESIDENCE保持partial且deferred用户暂停，不新增住房开发、不作为Shop硬前置；下方旧住房接线待办不再要求本轮完成。截至本轮收尾，Main的resident_harbor实例及zones/scope绑定已移除，源资源保留；用户手摆root和其他旧transform未动。当前天台运行链已由214439五项2277/0实际通过，不由移除事实或住所版旧PASS代签；剩余产品验收见末节。

历史 `D:/projects/sea-work/verification/20261107-192319-seven-npc-release-a6fb1b` 中release integration/save已PASS仅为住所版证据，不等于当前天台版通过。当前天台入口、vendor→独立ShopPanel、模态/输入盾、真实交易及save/integration/真实渲染运行证据已收齐，shop259/0、天台五项2277/0通过；登记implemented，非verified，14图仅三图已目检。

## 登记头

```json
{
  "feature_id": "SEA-SHOP",
  "status": "implemented",
  "owner": "ShopService / ShopCatalog / ShopPanel",
  "code_paths": [
    "godot/src/shop/shop_catalog.gd",
    "godot/src/shop/shop_service.gd",
    "godot/src/shop/shop_panel.gd",
    "godot/assets/data/shop/shops.json"
  ],
  "verification": ["shop-rules", "npc-integration", "npc-save", "visual-npc-release", "pocket-drag-buy", "npc-shop-site", "npc-relocation", "visual-npc-people"]
}
```

## 设计承接与实施条目

下表保留接线前的阶段状态；R01–R09旧shop及七人全天台联合主验保留为历史，不重写其通过记录。本轮经营者迁址、目录标题与独立购买按文末22:39及R10承接，登记partial、新实测pending。

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-SHOP-R01 | 已实现纯规则独立服务、目录和内容表；正式 HUD/场景切换待完成 | `godot/src/shop/`、`shops.json`；架构门禁不得出现 NPC/Main/HUD 业务规则 |
| SEA-SHOP-R02 | 部分实现；目录/quote/查询副本源码已见，作物种子引用CropCatalog | `shop_catalog.gd`、`shop_service.gd`；shop-rules待主线程实测，历史shop-modules名称不代表当前已注册/通过 |
| SEA-SHOP-R03 | 部分实现；唯一exchange注入与拒绝路径已见，真实原子Inventory.exchange由主线程补齐 | fake测试不能代替生产库存原子性；余额/容量/未知物品/溢出/失败数量排列信号待验 |
| SEA-SHOP-R04 | 已冻结 `vendor_requested` / `purchase_completed` 桥接；真实 NPC 交互接入待完成 | NPC 与商店互不读取私有状态；后续集成专项覆盖 |
| SEA-SHOP-R05 | 已实现花店与综合商店首批商品目录；花店物品资产/视觉仍 pending | `shops.json` 内容检查；资产登记另走 SEA-ASSET |
| SEA-SHOP-R06 | 静态目录无另副本存档，购买沿用Inventory持久化，跨进程尚未验 | save/integration由主线程选实际入口；历史shop-save只是计划，不认定已注册 |
| SEA-SHOP-R07 | 部分实现；独立ShopPanel源码已见，不通过旧HUD开店 | `shop_panel.gd`；Main桥接切换、键鼠焦点/数量/反馈/关闭待实测 |
| SEA-SHOP-R08 | 部分实现；exchange唯一写口与实例内120秒/256条token逻辑已见 | `shop_service.gd`；真实库存、同token重入/异参/过期/淘汰/configure边界待主线程 |
| SEA-SHOP-R09 | 部分实现；独立目录/服务/面板均存在，整局集成未签署 | 无NPC独立运行、两商店/模态/购买/save/integration/真实渲染与设备分开回填 |

## 当前接口清单

- `ShopCatalog.data()` / `ShopCatalog.resolve(source=null,crops=null)`：静态两目录11商品；三作物种子item/price由CropCatalog解析，名称/描述由ItemDB解析。
- `ShopService.configure(bag,exchange=Callable(),content=null,crops=null)`：可注入真实Inventory.exchange，不每次开店重配。
- `ShopService.shops()` / `shop_snapshot(shop_id)` / `quote(shop_id,product_id,amount=1)` / `max_buy` / `inventory_snapshot`：只读独立副本。
- `ShopService.open_shop(shop_id,vendor_npc_id="")`：经营者是可选元数据，不查询NPC，不硬依赖RESIDENT。
- `ShopService.buy(shop_id,product_id,amount,request_token="")`：唯一写端口exchange，不用pay/add/remove补偿。
- `ShopPanel.configure(service,inventory)` / `open_shop` / `close` / `is_open` / `handle_input`：同一Inventory，独立面板；端口非存档。
- 事件：`shop_opened`、`purchase_completed`、`purchase_blocked`

## 验证记录

- 2026-11-07 早期计划（历史）：建立独立商店目录和服务，计划运行 `shop-modules`；该旧名称仅保留历史；主线程现已将登记头verification改为shop-rules/npc-integration/npc-save/visual-npc-release，不再保留无效shop-modules入口。
- 早期本功能为 `partial`：当时纯规则已实现、UI/场景待接；以下原遗留/占位表均保留历史。最终运行已收齐通过，当前implemented，按文末签署覆盖旧待接线口径。

## 遗留与下一步

1. 主线程补齐真实原子Inventory.exchange并注入；Main的vendor桥接切换独立ShopPanel，关闭NPC模态后再开店，接通输入盾和关闭清理，不再借旧HUD页。
2. 两商店空间归[SEA-RESIDENCE](../residence/spec.md)，经营者角色归NPC；世界入口/vendor源码不等于交互全链路通过。
3. 核实商品图标、花材可用性与两名经营者真实渲染；花种作为物品不自动代表Crop已可种植。
4. 验证无NPC独立运行、真实库存交易、存档联合恢复、真实渲染及设备，保留partial。

### 主线程回填占位

| 证据层 | 待回填 | 当前结论 |
|---|---|---|
| 结构 | 依赖/条款/目录检查命令与日志；前置INVENTORY/CROP/INTERACT | 仅静态数量核对2目录11商品，未跑正式结构专项 |
| 运行 | shop-rules实际入口/命令/版本/退出码/断言失败数/日志；exchange和token边界 | 本分支未执行，测试文件test_shop_rules.gd存在不等于通过 |
| 集成存档 | 两入口→ShopPanel、模态/重复点击、真实Inventory、save/integration跨进程 | 待主线程真实接线实测 |
| 视觉 | 独立商店面板/11商品/两经营者截图、图形后端与审阅 | 待真实渲染 |
| 设备与未验 | 设备/分辨率/性能/文件系统/资产登记和未验条款 | 未验 |

本分支不执行sync、Godot或专项，不编造通过数。主线程计划shop-rules，是否已注册由其核实；不将历史shop-modules/shop-save写成当前运行结论。

## 变更记录

- 2026-11-07：新增 SEA-SHOP 独立功能设计与账本；冻结花店/综合商店、商品目录、原子购买公式和 NPC vendor 桥接边界。
- 2026-11-07 下午：追加R07–R09及承接，核对独立Panel、2目录11商品/Crop价格来源、exchange主线程责任与token有限去重；不重写登记头/历史，不宣称整套完成。

## 2026-11-07 天台收尾与当时失败（历史：七人全天台，阶段partial）

NPC独立、Shop独立；两商店11商品、三花各四stage已实现，flower-crops专项1233/0 PASS不等于ShopPanel输入验收。正式经营者随七人暂驻既有rooftop_ranch，NpcStations35局部Marker随用户root变换，无物理房屋、UI“暂驻天台”；Main已移除resident_harbor实例及zones/scope绑定并保留source，住房partial/deferred不是Shop前置。

[当前合批报告](../../../../sea-work/verification/20261107-211435-npc-performance-rooftop-7e1d96/report.json)内shop-rules为 **218 checks / 7 failures，exit1 / FAIL**：键盘增量、鼠标增量、鼠标减量、Enter购买后保持开启、向下选商品、E确认购买、购买失败保持开启且原因可读。该七项UI失败已由213213最终shop-rules259/0解决，保留原报告；不得用同批NPC性能/rules/world/appearance/careers/flowers/sleep七项PASS覆盖此失败，也不把旧shop-modules或住所版历史PASS当作当前天台结论。

最终输入、天台交易/模态及联合存档/重启/真实渲染运行证据已收齐并按下节签署，原218/7失败历史与本节历史标题保留。剩余产品审阅见[性能记录最终表](../../development/2026-11-07_npc_performance_fix.md#6-主线程最终待填位置)。

## 最终签署：Shop运行实现通过（22:39前七人全天台历史）

状态 **implemented（已实现待完整产品验收）**，不标verified。主线程已将verification改为shop-rules、npc-integration、npc-save、visual-npc-release，本线程保留其新值，只定点改status，未改代码/registry/runner。

- [213213最终输入报告](../../../../sea-work/verification/20261107-213213-shop-input-final-638cdf/report.json)：shop-rules259 checks / 0 failures，exit0/PASS、unexpected_errors空，原七项UI失败已解决。
- [214439当前天台报告](../../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/report.json)：integration668/0、save618/0、seed408/0、restart202/0、visual381/0，总2277/0，五项exit0/PASS、unexpected_errors空。实际命令、head/working_tree和隔离快照见report；真实vendor→独立ShopPanel、交易/模态/恢复与玩家profile隔离已验，不是fake库存或历史住所版结果替代。
- R01–R04独立域/目录/原子交易/vendor桥接，R05两目录11商品，R06持久化联合恢复，R07独立面板输入，R08exchange/token边界，R09整局当前运行集成，均按规则专项及最终交付通过；三花各四stage专项保留，不将flowers代作Shop输入通过。
- 14PNG已产出；主线程只确认seven-residents、flower-purchase、story-choice三图已目检，其中花店正确5商品/价格和购买成功。其余11图（含general-shop）仍待人工审阅，不称两店所有视觉均人工签署。[完整逐图链接](../../development/2026-11-07_npc_performance_fix.md#8-最终天台运行签署与14图清单)。
- 当前运行范围无已知未覆盖条款；R05/R07/R09的全细节/全组合图像审阅、资产权属、设备发行及长期体验仍属产品待验，不升级verified。七人全部原天台草地，无物理住房、UI天台暂驻；住所仍partial/deferred，不签完成。

## 主线程最终回归补签（22:39前七人全天台历史）

[221054最终回归](../../../../sea-work/verification/20261107-221054-npc-final-regression-bc8a22/report.json)shop-rules259/0、全部11专项5324/0；[222551当前工作树](../../../../sea-work/verification/20261107-222551-npc-final-live-worktree-6eb68a/report.json)旧拖拽/批量购买兼容适配器44/0，正式集成668/0、存档618/0、seed408/0、restart202/0，均PASS/exit0且无unexpected_errors。生产商店命令仍打开独立ShopPanel，旧兼容专项直接打开HUD适配器，不把两种入口混为一体。原编译失败/完成标记失配另保历史，后续复跑已通过。

主线程已原图/联系图补审14张正式场景图（含general-shop、关系及职业面板），并审七人正面设计；不签全部241张外观/动作细节人工检查。最终合同sync17/check18问题由混合工作树source/runtime及派生索引引起，未批量覆盖，详[最终性能与门禁记录](../../development/2026-11-07_npc_performance_fix.md#9-主线程最终回归视觉审阅与门禁)。

## 2026-11-07 22:39 当前覆盖与 R10 承接

登记头定点改为 **partial**；本轮新实测 **pending**。上文implemented/PASS、两经营者全天台及14图审阅仅属旧快照历史，不能代签阿店迁址后的交互/交易/视觉。标题→回链→原登记头JSON与全部历史顺序保留，不重写账本；verification仍保留原值，新专项是否已注册由主线程核实，不冒填通过数。

| 对应设计条款 | 当前实施状态 | 证据 / 本轮验证要求 |
|---|---|---|
| SEA-SHOP-R10 | partial；小花/阿店稳定经营者映射及天台/sea_supply站位源码已见，目录标题更新仍待主线程；运行pending | [spec本轮覆盖](spec.md#2026-11-07-2239-当前覆盖经营者场地与独立购买)。当前`shops.json`读到旧标题“花序花店/货架综合商店”，目标“小花花店/阿店海上商店”；保留11商品ID、price/max_amount及CropCatalog来源。实测无NPC独立购买、两世界入口/vendor→独立ShopPanel、浮店升沉中交互、Inventory.exchange失败原子/成功单次、save恢复；不将NPC背景送花当库存结算。 |

### 本轮主线程实测回填

| 范围 | 应填写证据 | 当前结论 |
|---|---|---|
| 目录 | 更新后的两个display_name、原11商品ID/价格/上限前后对照、实际工作树快照 | pending；本分支未改JSON |
| 独立规则 / shop-rules | 实际命令、注册入口、exit、checks/failures、无NPC实例的查询/购买、失败不变与token边界 | pending；旧259/0不算本轮通过 |
| 场地 / npc-shop-site、npc-relocation | 经营者6roof/1sea、两本地入口、全条件日程不跨海、用户root未动及海浪中可交互 | pending |
| 集成/save | 迁址后真实vendor→独立ShopPanel、模态取消/重复购买/库存持久化、玩家profile隔离；实际入口由主线程确认 | pending；旧668/0、618/0等仅历史 |
| visual-npc-people | 天台小花与浮店阿店/新店标题/实际购买反馈截图、后端/设备/分辨率、逐图已审/未审 | pending，未捕获、未目检 |

与[Resident R15–R18](../resident/ledger.md#2026-11-07-2239-当前覆盖与新增条款承接)及[本轮开发记录第6节](../../development/2026-11-07_npc_names_and_shop.md#6-主线程实测回填)共同回填实际head+working_tree、隔离输出、命令/退出码/计数/日志/截图和未验项。住所partial/deferred、用户Main roots不动；NPC与Shop独立，商品“花序缎带”不顺带改名。本分支未执行global sync、hash、Godot、runner或测试，未改旧报告或生产JSON，无本轮PASS。

## 2026-11-08 继续执行后本轮运行签署

| 对应设计条款 | 当前实施状态 | 本轮证据 |
|---|---|---|
| SEA-SHOP-R10 | implemented；两完整新店名、独立无NPC购买、迁址后真实两店交易与存读 | shop-rules259/0、relocation898/0、integration695/0、save615/0、visual348/0；28图已审 |

登记头状态已定点更新为`implemented`，非`verified`；verification原数组保留并仅追加Shop相关已注册入口`npc-shop-site`、`npc-relocation`、`visual-npc-people`。`shops.json`现为小花花店/阿店海上商店，`residences`标签同步，仅改display label；11商品和`flower_ribbon`未改。Shop R10保持原稳定用途，小花天台、阿店东南`sea_supply`，30+5 Marker、建筑手摆root不动，住所继续partial/deferred。

最终13专项报告中的Shop相关项为`npc-shop`18/0、`npc-shop-site`335/0、`shop-rules`259/0；报告：`D:/projects/sea-work/verification/20261108-041703-npc-final-regression-799f0f/report.json`。正式交付报告：`D:/projects/sea-work/verification/20261108-035812-npc-people-delivery-599f67/report.json`，`npc-relocation`898/0、`npc-integration`695/0、`npc-save`615/0、`npc-save-seed`405/0、`npc-save-restart`197/0、`visual-npc-people`348/0，28张PNG。`npc-people`严格最终报告`D:/projects/sea-work/verification/20261108-042106-npc-people-strict-final-0d9095/report.json`的3054/0覆盖同项，不重复累加；19个独立入口合计13177/0，均exit0且`unexpected_errors=[]`。

设备为Godot4.6.3/VulkanForward+/RTX4060Ti；1920为窗口记录，PNG实际像素以文件为准。21张人物front/identity/background由独立代理逐图查看，7张业务场景图由主线程逐图打开；28图审阅不代表所有剧情、动作、滚动以下内容或完整商店体验均人工验收。长文底部为可滚动视口正常剪裁，未推断隐藏行。低端、发行包、完整剧情体验、资产权属和用户美术验收仍pending；未测长期FPS，不继承59.943。

旧FAIL历史保留并追加解释：float/literal int dict严格比较误报改为逐字段数值相等并保留精确字段数，另修旧名字断言、Panel常量遮蔽native、话题局部ID误判全局唯一、UI键盘同帧/未释放；仅测试与runner修复，无事件数值变动。runner补五入口、独立套件移除autoload、集成使用`--nosave`、修复terrain重复copy/mount缺陷。全局门禁当前sync32/check35问题可能并行变化，不锁最终数字；hash/source drift未批量重签。architecture25服务0、placed3结构0警告、gitdiffcheck通过，但不宣称全工程门禁通过。验收页为`D:/projects/sea-work/outputs/npc_names_shop_acceptance.html`及同名JSON，开发记录由主线程追加第8节；历史assets为symlink同文件，不能作为冻结内容快照比对证据。

### 2026-11-08 最后校对覆盖

`items.json`两花种desc使用“小花”，固定“花序缎带”商品名不动。最新shop-rules**260/0**（新增说明断言）、people3054/0、flower1233/0，报告`20261108-043507-npc-label-polish-final-21bea3`；该合批visual航程278/1不签绿。仅追加超时只读诊断后`20261108-044915-npc-visual-route-diagnosis-03bb1f`visual**348/0**、28图重拍且全部逐图审阅，两店标题/小花说明正确。最终19入口合计**13178/0**覆盖上方13177；无生产导航阈值/建筑位置修改。一次120秒航程超时根因未稳定复现，保留任务149持续跟踪，implemented不升verified。
