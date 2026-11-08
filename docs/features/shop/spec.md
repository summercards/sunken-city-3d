# SEA-SHOP · 花店与综合商店

[主文档中控](../../../GDD_V1.0.md#sea-shop) · [本功能账本](ledger.md) · [NPC 功能](../resident/spec.md) · [住所空间](../residence/spec.md) · [施工文档](../../development/2026-11-07_npc_module_framework.md)

设计修订：r4（2026-11-08，经营者先对话再开店）。所属系统：经营。本轮状态 **implemented（已实现，非完整产品verified）**；人物/场地按R10，点击经营者的入场流程按文末R11，当前验收见[开发记录](../../development/2026-11-08_npc_conversation.md)。前置仅 SEA-INVENTORY / SEA-CROP / SEA-INTERACT，不硬依赖SEA-RESIDENT、Farm或住所；本轮使用既有天台/浮店，不恢复住房开发。

### 2026-11-07 19:40 覆盖（历史：两经营者全天台，不等待住房）

七人正式现场改为 `rooftop_ranch` 天台草地，用户手摆root下NpcStations的35个局部Marker随scene变换；花序/货架仍经营 `shop_flower` / `shop_general`，通过vendor_requested交接独立ShopPanel，商品/价格/库存与NPC剧情、职业端口所有权不变。七人当前无物理房屋，UI仅写“暂驻天台”，不称已住屋。

SEA-RESIDENCE保持partial（历史资源留存），本轮deferred用户暂停；旧住商房屋空间仅保历史，不新增住房开发，不作为开店/交易或当前验收前置。Shop继续仅依赖INVENTORY/CROP/INTERACT，不硬依赖NPC、Farm或住所。Main的resident_harbor实例及zone binding已移除，源资源保留；天台当前接入与测试见末节最终签署。

住所版历史release integration/save已PASS证据为 `D:/projects/sea-work/verification/20261107-192319-seven-npc-release-a6fb1b`，不得转写为天台版通过。天台两入口→独立ShopPanel/模态/真实交易/save恢复与真实渲染已由当前天台专项通过，见施工记录第14节；完整产品验收边界仍单列。

## 1. 功能目的与独立边界

SEA-SHOP 负责商店目录、商品定义、价格、购买资格、库存/数量规则和购买事件。首批包含：

- `shop_flower`：小花花店，由`npc_hua_yi`「小花」在天台经营；出售花种、花材和花店主题礼物。
- `shop_general`：阿店海上商店，由`npc_bao_he`「阿店」在东南既有浮店经营；出售种子、土壤和日常补给。店名为本轮目标，内容表标题由主线程更新，本分支不改JSON。

商店是独立系统。它不拥有 NPC 的身份、好感、日程、剧情、住所或角色外观；NPC 仅通过 `vendor_requested(npc_id, shop_id)` 打开商店。商店也不直接读取 `NpcService` 私有状态。

商店拥有：

- 稳定 `shop_id`、`product_id` 和商品目录；
- 价格和购买上限；
- 通过 Inventory 端口扣款、加物品；
- 商品购买事件与商店开放条件；
- 花店/综合商店的分类和文案。

商店不拥有：

- NPC 好感、对白、剧情、关系网；
- Inventory 内部数量和容量；
- Farm 的种植结算；
- Order 的订单状态；
- NPC 的住所和角色形象。

## 2. 首批商店与商品

### 花店 `shop_flower`

经营 NPC：`npc_hua_yi`（小花，旧称花序）。当前场地为天台草地花摊，不依赖未接入的住所/温室。定位：把种植系统的“收成”转成可见的花色、关系礼物和生活装饰。

| product_id | 名称 | 类型 | 价格 | 购买限制 |
|---|---|---|---:|---|
| `flower_seed_blue` | 蓝星花种子 | seed | 8 | 每次最多20件，背包空间与瓶盖 |
| `flower_seed_sun` | 晨光花种子 | seed | 10 | 每次最多20件，背包空间与瓶盖 |
| `flower_seed_coral` | 珊瑚花种子 | seed | 12 | 每次最多20件，背包空间与瓶盖 |
| `flower_bundle` | 小束鲜花 | gift | 18 | 每次1件，背包空间与瓶盖 |
| `flower_ribbon` | 花序缎带 | gift | 26 | 每次1件，背包空间与瓶盖 |

### 综合商店 `shop_general`

经营 NPC：`npc_bao_he`（阿店，旧称货架）。当前场地为用户已摆好的`World/SeaStructures/floating_shop`、`sea_supply`；不再在天台经营。定位：补充核心循环的基础物资，不替代采集和订单。

| product_id | 名称 | 类型 | 价格 | 购买限制 |
|---|---|---|---:|---|
| `general_lettuce_seed` | 生菜种子 | seed | CropCatalog.seed_price | 每次最多20件，引用crop_id=lettuce |
| `general_tomato_seed` | 番茄种子 | seed | CropCatalog.seed_price | 每次最多20件，引用crop_id=tomato |
| `general_pumpkin_seed` | 南瓜种子 | seed | CropCatalog.seed_price | 每次最多20件，引用crop_id=pumpkin |
| `general_soil` | 土壤（item=soil） | material | 4 | 每次最多40件 |
| `general_rope` | 缆绳（item=rope） | material | 9 | 每次最多10件 |
| `general_glass` | 玻璃（item=glass） | material | 16 | 每次最多5件 |

以上对应 `shops.json` 的2目录11个product_id；product_id与Inventory item_id不能混用。三种作物种子仅登记crop_id，由CropCatalog解析seed/seed_price，禁止商店重复硬编码物品或价格；名称/描述取ItemDB。当前三花已登记为flower_blue/sun/coral品种，种子ID与价格通过CropCatalog解析，真实播种、生长、收获与送礼已专项验证；不复制第二套花卉数值。坏目录全表拒绝，不静默删坏商品凑可用目录。价格不是NPC好感副本，关系只影响对白/推荐语，不隐式改价。

## 3. 购买公式与边界

商品购买为原子操作：先验证数量、价格、背包空间和瓶盖，再一次性扣款并入包。任一条件不满足，都不改变任何状态。

```text
total_cost = unit_price × amount
max_buy = min(product.max_amount, floor(coins / unit_price), inventory.room_for(item_id), MAX_VALUE - owned)
MAX_VALUE = 9007199254740991
```

花店赠礼商品若是 `gift` 类型，仍然只是 Inventory 物品。是否送给 NPC、关系变化多少，由 SEA-RESIDENT 的 `give_gift` 端口决定，商店不自动送礼。

商店不得出现负价格、未知物品、超过配置上限、溢出或扣款成功但入包失败的半成功状态。`quote` 为纯查询，不发事件或缓存token；购买唯一写端口为 `Inventory.exchange(costs,gains)->{ok:bool,reason:String}`。Main已注入真实Inventory实现：失败数量/排列/信号全不变，成功完整提交后才发Inventory信号；ShopService不能用pay/add/remove分步或补偿退款冒充原子操作。当前原子交易已由正式天台integration/save验证，数值边界另有shop-rules专项；不把端口存在直接等同测试通过。

`buy(...,request_token)` 仅在同一服务实例内保留120秒、最多256条（含拒绝结果），不续期。相同token和相同参数重放独立副本且不再发购买事件；相同token不同参数拒绝；空token每次是独立请求。过期/淘汰/configure/重建实例后不保证去重，不持久化token，不承诺跨进程exactly-once。configure用于装配/换档，不在每次开店调用。

## 4. 对外接口

| 类别 | 端口 | 说明 |
|---|---|---|
| 查询 | `shops()` | 返回商店目录副本 |
| 查询 | `shop_snapshot(shop_id)` | 返回商品、价格、玩家余额和各商品 `max_buy` |
| 命令 | `open_shop(shop_id)` | 仅验证商店存在/开放；不修改库存 |
| 查询 | `quote(shop_id, product_id, amount)` / `max_buy` / `inventory_snapshot` | 只读价格、数量与容量，独立副本 |
| 命令 | `buy(shop_id, product_id, amount, request_token="")` | 仅通过注入的Inventory.exchange原子结算 |
| 事件 | `shop_opened(shop_id, vendor_npc_id)` | UI 和装配层消费 |
| 事件 | `purchase_completed(shop_id, product_id, amount, total_cost)` | NPC 可选消费公开结果，不拥有购买状态 |
| 事件 | `purchase_blocked(shop_id, product_id, reason)` | UI 展示原因 |

NPC 与商店唯一业务桥接：

```text
NpcInteractable(npc_id)
  -> vendor_requested(npc_id, shop_id)
  -> ShopService.open_shop(shop_id)
  -> 独立ShopPanel.open_shop(shop_id)，不打开旧HUD商店页
```

不得让 `ShopService` 调用 `NpcService` 的好感、剧情或日程接口；不得让 `NpcService` 读取商品价格数组。

## 5. 数据与存档

内容表实际位置：`godot/assets/data/shop/shops.json`。ShopCatalog/CropCatalog/ItemDB为静态内容源，不在玩家存档再存目录副本。首批无限目录，无动态库存或独立shop快照；UI页签/选中量/token也不存档。未来每日库存必须另行设计版本化动态契约，不能暗加到npc。

购买本身由 Inventory 的已有存档承担，商店服务不重复保存瓶盖或物品数量。

## 6. 验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-SHOP-R01 | 花店与综合商店具有独立 `ShopService`、目录、账本和内容表；不把商店规则写进 NPC/Main/HUD。 |
| SEA-SHOP-R02 | 商品、价格、数量上限和开放资格由商店数据驱动，查询返回副本。 |
| SEA-SHOP-R03 | 购买使用原子公式和 Inventory 唯一写入者；瓶盖不足/背包满/未知商品均不改变现场。 |
| SEA-SHOP-R04 | NPC 与商店通过 `vendor_requested` 和公开购买事件连接；好感、对白、住所和价格互不隐式依赖。 |
| SEA-SHOP-R05 | 首批花店和综合商店商品内容可验证，花店独立于已有种子/土壤商店路径。 |
| SEA-SHOP-R06 | 商店查询、购买、重复点击、坏数据和跨进程恢复有独立验证入口；不重复保存 Inventory。 |
| SEA-SHOP-R07 | 独立ShopPanel仅消费ShopService查询/命令与同一Inventory，支持选择数量、购买反馈、键鼠焦点及关闭清理，不转旧HUD页，不新增第二套价格规则。 |
| SEA-SHOP-R08 | 主线程注入真实原子Inventory.exchange；失败不变/成功后发信号；token去重仅120秒/256条/实例内，边界和重入可验证，不承诺跨进程去重。 |
| SEA-SHOP-R09 | 独立无NPC运行、两商店世界入口、NPC模态交接、真实购买、save/integration及真实渲染分别验收；静态目录与UI/token不另存副本，状态保持partial直至签署。 |

## 7. 当前实现边界

已见 `godot/src/shop/shop_service.gd`、`shop_catalog.gd`、`shop_panel.gd` 和两目录11商品源码。独立面板已存在，不能再写成“尚无UI”；但Main仍有旧HUD桥接，真实原子Inventory.exchange、NPC→独立ShopPanel、输入屏蔽及关闭生命周期由主线程接通并实测。原Farm种子/MaterialShop兼容入口不在本轮删除，但新两商店不得继续借其页面或复制价格。

### 主线程回填占位

待主线程回填 `shop-rules` 实际注册入口/命令/版本/退出码/断言失败数/日志；真实Inventory.exchange失败不改数量排列信号、重复/过期token、NPC→ShopPanel模态、两商店真实交易和save/integration跨进程结果；独立面板真实渲染截图、后端/设备/性能和未验项。本分支未执行sync、Godot或测试，不填写通过数，保持partial。

## 2026-11-07 22:39 当前覆盖：经营者场地与独立购买

上方“两经营者都在天台”的口径是历史；当前小花仍在天台，阿店在用户既有东南`World/SeaStructures/floating_shop`（`sea_supply`）。居民世界分配为6roof/1sea，不移动用户建筑root、不新造房屋。UI标“常在”：小花为天台草地暂驻，阿店为东南海上商店；`residence_id`及Home/Rest语义不等于已经建成住房。住所继续partial/deferred，不成为开店或购买前置。

目录显示标题目标为 **小花花店**（`shop_flower`，`npc_hua_yi`）和 **阿店海上商店**（`shop_general`，`npc_bao_he`），由主线程更新`shops.json`。文档核对时JSON仍为“花序花店/货架综合商店”，这是明确待办，不声称已改生产标题。仍是两目录11个product ID：小花5、阿店6，price/max_amount、crop_id/item、CropCatalog价格来源一律不变；`flower_ribbon`及现有商品标签“花序缎带”不能被经营者改名顺带全局替换。

NPC经`vendor_requested`关闭原会话并交给独立ShopPanel；Shop仍只认识可选`vendor_npc_id`元数据和稳定shop_id，无NPC实例也能配置、查询、报价、开店及经同一Inventory.exchange购买。场地/经营者用于入口与展示，不拿好感/剧情作为暗价、库存或购买资格，不在NpcService加入Shop规则。小花天台备花托船送、阿店浮店本地收花是叙事，不自动产生商品、扣物品、订单或库存副本，不要求双方跨海寻路。

`NpcAnchorHub`和site provider只负责世界站位，浮店heave/支撑归原世界owner，不参与ShopService结算。阿店每physics随支撑仍须在柜台稳定交互，0.5秒增量解析、模态/取消/关闭、重复token与失败原子性须用本轮迁址后场景实测，不借旧全天台PASS。

追加前最大编号R09，新增稳定条款如下；R01–R09历史证据不删，本轮整体 **partial / pending**。

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-SHOP-R10 | 小花天台花店/阿店东南海上商店按稳定经营者与shop_id展示、用户手摆场地不动；目录标题由主线程改，11商品ID/价格/上限不变。NPC仅提供可选vendor入口，Shop不硬依赖NPC/住所，独立无NPC购买与迁址后的两入口→独立ShopPanel→Inventory.exchange均验证；场地/剧情不复制交易状态或隐式改价。 |

主线程回填`npc-shop-site`/`npc-relocation`/`visual-npc-people`以及shop-rules、集成/save回归实际入口、工作树、退出码、计数、日志和逐图审阅至[账本本轮表](ledger.md#2026-11-07-2239-当前覆盖与-r10-承接)及[开发记录第6节](../../development/2026-11-07_npc_names_and_shop.md#6-主线程实测回填)。本分支只补文档，不改shops.json、代码、Main roots或runner，不执行global sync/hash/运行，不填本轮PASS。

## 2026-11-08 继续执行后本轮运行签署

SEA-SHOP本轮为 **implemented（已实现）**，不是 **verified**；`SEA-SHOP-R10`保持原稳定用途。正式`shops.json`现为小花花店/阿店海上商店，`residences`标签同步，仅改display label；11个商品及`flower_ribbon`/“花序缎带”未改。小花仍在天台，阿店仍在东南`sea_supply`浮店；六人天台30 Marker、阿店5 Marker、建筑手摆root未动，住所继续partial/deferred。Shop仅追加相关入口`npc-shop-site`、`npc-relocation`、`visual-npc-people`，不把`npc-profile-ui`计入Shop专项。

本轮与NPC联动的最终13专项报告中，Shop相关结果为`npc-shop`18/0、`npc-shop-site`335/0、`shop-rules`259/0；完整报告为`D:/projects/sea-work/verification/20261108-041703-npc-final-regression-799f0f/report.json`。正式交付报告`D:/projects/sea-work/verification/20261108-035812-npc-people-delivery-599f67/report.json`中，`npc-relocation`898/0、`npc-integration`695/0、`npc-save`615/0、`npc-save-seed`405/0、`npc-save-restart`197/0、`visual-npc-people`348/0，共28张PNG；19个独立入口合计13177/0，均exit0且`unexpected_errors=[]`。`npc-people`严格最终复跑为`D:/projects/sea-work/verification/20261108-042106-npc-people-strict-final-0d9095/report.json`的3054/0，仅为覆盖结果，不重复累加。

设备为Godot4.6.3/VulkanForward+/RTX4060Ti；1920为窗口记录，实际PNG像素以文件为准。21张人物图由独立代理逐图查看，7张业务场景图由主线程逐图打开；28张图均审阅不等于所有剧情、动作、滚动以下内容和完整商店体验均人工验收。长文底部是可滚动视口正常剪裁，未推断隐藏行。低端、发行包、完整剧情体验、资产权属和用户美术验收仍pending；本轮未测长期FPS，不继承59.943。

旧FAIL历史保留：float/literal int dict严格比较误报、旧名字断言、Panel常量遮蔽native、话题局部ID误判全局唯一、UI键盘同帧/未释放；仅测试与runner修复，未改变事件数值。runner补五入口、独立套件移除autoload、集成使用`--nosave`，并修复terrain重复copy/mount缺陷。全局sync32/check35问题可能随并行变化，不锁最终数字；hash/source drift未批量重签。architecture25服务0、placed3结构0警告、gitdiffcheck通过，但不宣称全工程门禁通过。验收页为`D:/projects/sea-work/outputs/npc_names_shop_acceptance.html`及同名JSON，开发记录由主线程追加第8节；历史assets为symlink同文件，不能作为冻结内容快照比对证据。


## 2026-11-08 经营者先对话再开店

| 条款 ID | 规则与验收 |
|---|---|
| SEA-SHOP-R11 | 点击小花/阿店先进入NPC底部对白，初见/满足条件剧情/偶发日常先于营业问候；营业问候右侧选“商店”才经vendor_requested打开原独立ShopPanel。退出不打开商店。NPC不读取价格或改商品；两目录、11商品、原子Inventory.exchange及无NPC独立购买能力保持。阿店初见为南边海域漂流来客、自我介绍和补给询问，之后用“今天的库存还有这些，看看吧。”承接功能选项。 |

## 2026-11-08 商店改为与背包同款图标网格

| 条款 ID | 规则与验收 |
|---|---|
| SEA-SHOP-R12 | 独立ShopPanel不再用列表行，而是复用背包同一套 `PocketService` 格子、分页、名签与操作气泡：商品以图标成格，单价画在格内左下角标，持有数不再冒充"库存×N"；开店只摆格并把焦点落在首件商品，确认后才打开气泡，气泡给单价/当前可购/合计/购后余额与不可购买原因，数量 `− N +` 与购买一次结算后才收起。Tab 与背包一致关闭面板，Esc 先收气泡再关店；方向键只在商品行内移动，不把焦点甩到背包。价格、上限与原子结算仍全部由 ShopService/Inventory.exchange 裁决，本层不复制任何数值。 |

实现与运行证据：[开发记录](../../development/2026-11-08_shop_icon_grid.md)、[本功能账本](ledger.md#2026-11-08-商店图标网格交付)。
