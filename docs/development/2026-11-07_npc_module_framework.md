# 2026-11-07 NPC 与商店独立模块框架施工文档

[主文档功能入口](../../GDD_V1.0.md#sea-resident) · [NPC 设计文档](../features/resident/spec.md) · [NPC 账本](../features/resident/ledger.md) · [模块接口约定](../architecture/module_contracts.md)

## 阅读口径：上午历史与下午当前承接

第1–9节保留上午规划及早期七人增补的历史混合稿，包含五人/15+2/60、planned、零路径等阶段表述；**不再作为当前完成状态**，也不删除以保留施工轨迹。第10节记录下午七人/住所制作及接线方案，第11节保留当时主线程回填占位。**19:40范围以第12节为准，性能修复及本轮最新已验/失败/待验以末尾第13节为准**：七人暂驻天台草地，住房deferred用户暂停；第10–11节七屋/住所路线/验收待办仅历史，不是本轮硬前置。旧勾选/预期入口不代表当前天台工作树通过。

## 1. 本轮施工目标（上午/早期历史）

本轮先确立并落地 NPC 与商店两个独立模块的产品边界、数据边界、施工顺序和验收门禁，不把 NPC 规则塞进 `Main`、`HUD`、`Farm`、`Building`、`Economy` 或现有开场对白脚本，也不把商品价格/购买规则塞进 NPC。

目标是建立一个可以独立运行、独立测试、独立维护的 NPC 规则域：

- 首批固定 7 名 NPC，其中花序经营花店、货架经营综合商店；
- 有日常对话、剧情对话和分支选择；
- 有 21 个个人剧情事件和 4 个跨 NPC 关系事件的内容预算；
- 有玩家-NPC 好感与 NPC-NPC 关系网；
- 七名 NPC 各有独立住所 ID 和参考住所表现；
- 有时间、天气、关系、剧情条件驱动的日程；
- 有版本化 `npc` 存档快照；
- 所有关联通过端口、查询、事件和稳定 ID 完成；
- 商店独立为 `SEA-SHOP`，NPC 只发 `vendor_requested`，不拥有商品和价格。

**本轮不以空脚本冒充完成；本轮已建立纯规则运行服务和最小真实装配入口。** 设计文档和账本建立完成不等于 NPC 已经在游戏中出现。

## 2. 参考结论与本项目取舍

本轮参考了牧场类 NPC 的常见结构：

- Stardew Valley 的好感/心级、每日交谈、每周送礼次数、生日倍率、关系事件和日程条件；
- Stardew Valley 的按季节/星期/好感阈值选择日程；
- Story of Seasons / Harvest Moon 系列的花朵等级、事件解锁、请求与村民群体关系。

参考只用于抽象模块能力，不复制角色、台词、地图、数值或美术。链接已记录在 [NPC 设计文档](../features/resident/spec.md#2-牧场类-npc-参考与本项目取舍)。

本项目采用的取舍：

| 参考能力 | sea 的落地方式 | 不采用的部分 |
|---|---|---|
| 好感心级 | `affinity 0..1000`，每100点显示1心 | 不做每日衰减，不做强制打卡 |
| 送礼 | 每周2次，生日额外1次，按喜好和品质结算 | 不让送错礼物阻断种植/建造 |
| 日程 | 06:00/10:00/17:00/21:30 时间段 + 条件优先级 | 不把真实导航写进 NPC 规则 |
| 心级事件 | 200/500/800 阈值的个人事件 | 首轮不做永久错过 |
| 村民关系 | 7条静态关系边 + 可追溯 delta | 不做强制恋爱、婚姻和儿童 |
| 请求/任务 | NPC 只提出请求、接收结果 | 不复制 SEA-QUEST 或 SEA-INVENTORY 状态 |

## 3. 目标目录与职责冻结

正式代码接入时，目录只允许放在 `godot/src/npc/`；内容表只放在 NPC 自己的内容目录；测试夹具放在统一测试入口允许的测试目录，不让正式代码反向依赖测试目录。

目标结构（NPC）：

```text
godot/src/npc/
├─ npc_service.gd              # 七名 NPC 的运行状态唯一所有者
├─ npc_catalog.gd              # 静态身份、关系基础、对白、事件、日程内容表
├─ npc_relationship_graph.gd   # 玩家关系与 NPC-NPC 边的命令/查询
├─ schedule_resolver.gd        # 只读世界快照 -> MoveIntent
├─ dialogue_runner.gd          # 多页对白、选择、提交、回看状态机
├─ npc_save_codec.gd           # npc.version=1 的校验、编码、迁移
├─ ports/
│  ├─ npc_world_port.gd        # 世界锚点/天气/时间只读适配
│  ├─ npc_move_port.gd         # 移动意图输出端口
│  ├─ npc_gift_port.gd         # 背包预检/扣除结果端口
│  └─ npc_dialogue_port.gd     # UI 展示与输入意图端口
└─ data/
   ├─ npcs.json                # 七名 NPC 的稳定身份、住所和角色组装配置
   ├─ residences.json          # 七个住所参考位与显示
   └─ dialogues.json            # 七名 NPC 的首批对白内容

godot/src/shop/
├─ shop_catalog.gd             # 花店/综合商店静态目录
└─ shop_service.gd             # 独立购买规则与 Inventory 端口

godot/assets/data/shop/shops.json

```

本目录冻结为“纯规则 + 数据 + 端口”。NPC 场景表现、肖像、动画和锚点实例后续由装配层接入，不能把场景节点路径硬编码进 `NpcService`。

## 4. 五人首批内容施工表

| NPC | 稳定 ID | 主要内容 | 关联结果事件 |
|---|---|---|---|
| 洛言 | `npc_luo_yan` | 船匠/领航员；旧航线故事；3个个人事件 | SEA-SHIP、SEA-NAV、SEA-BUILD |
| 沐禾 | `npc_mu_he` | 种植者/种子保管人；种子记忆故事；3个个人事件 | SEA-FARM、SEA-CROP、SEA-INVENTORY |
| 纪沉 | `npc_ji_chen` | 打捞者/旧城记录员；旧城航行记录；3个个人事件 | SEA-SALVAGE、SEA-DIVE、SEA-WORLD |
| 南栀 | `npc_nan_zhi` | 木工/屋顶修缮师；家园归属故事；3个个人事件 | SEA-BUILD、SEA-BUILDING、SEA-WORLD |
| 白拾 | `npc_bai_shi` | 灯火守望者/档案管理员；公共记忆故事；3个个人事件 | SEA-QUEST、SEA-TIME、SEA-WORLD |

关系边首批 7 条，内容在设计文档冻结。实现时每条边必须有稳定 `edge_id`，不得用排序下标作为存档 ID。

## 5. 数据契约草案

### 5.1 NPC 身份内容

```json
{
  "id": "npc_luo_yan",
  "display_name": "洛言",
  "role": "boatwright_navigator",
  "home_anchor": "anchor_dock_luo_yan",
  "portrait_id": "portrait_npc_luo_yan",
  "dialogue_tags": ["boat", "route", "repair"],
  "event_ids": ["npc_luo_yan_intro", "npc_luo_yan_turn", "npc_luo_yan_close"]
}
```

### 5.2 日程内容

```json
{
  "npc_id": "npc_luo_yan",
  "rules": [
    {
      "when": {"hour_from": 6, "hour_to": 10},
      "anchor_id": "anchor_home_luo_yan",
      "action": "prepare"
    },
    {
      "when": {"hour_from": 10, "hour_to": 17},
      "anchor_id": "anchor_dock",
      "action": "repair_boat"
    }
  ],
  "fallback_anchor_id": "anchor_home_luo_yan"
}
```

条件优先级固定为：

```text
特殊剧情 > 节日/天气 > 关系阈值 > 星期/季节 > 默认日程
```

解析结果必须是 `MoveIntent`，包含 `npc_id`、`anchor_id`、朝向和动作，不包含路径点、碰撞体或 SceneTree 引用。

### 5.3 对话内容

对白必须有稳定 `dialogue_id`，每页有 `page_id`，选项有 `choice_id`。缺失条件时选择 fallback；不可因为内容表缺一条就生成空对话框。

```json
{
  "dialogue_id": "npc_luo_yan_daily_dock",
  "npc_id": "npc_luo_yan",
  "kind": "daily",
  "conditions": {"met": true, "affinity_min": 0},
  "pages": [
    {
      "page_id": "p1",
      "speaker": "npc_luo_yan",
      "text_key": "npc.luo_yan.daily.dock.001",
      "choices": []
    }
  ],
  "fallback_dialogue_id": "npc_luo_yan_fallback"
}
```

## 6. 施工阶段

### S0：文档与目录契约（本轮）

- [x] 主文档保留 `SEA-RESIDENT` 唯一 FeatureID，并改名为 NPC 居民、对话与关系网。
- [x] 功能设计文档冻结五人 roster、关系网、对话状态机、日程和存档边界。
- [x] 功能账本逐条承接 R01–R07，状态仍为 `planned`。
- [x] 模块接口约定补充 NPC 的所有者、端口和恢复规则。
- [x] 施工文档建立，明确不创建空运行模块。

### S1：纯规则骨架

目标：不加载 `main.tscn`、不依赖 Autoload、不创建 NPC 场景节点。

- 建立 `NpcCatalog` 的内容表解析和稳定 ID 校验；
- 建立 `NpcRelationshipGraph`，实现 affinity/edge delta、clamp、只读副本和幂等命令；
- 建立 `DialogueRunner`，实现多页、打字完成、选择、重复提交、取消和回看；
- 建立 `ScheduleResolver`，实现条件优先级和 home anchor 降级；
- 建立 `NpcSaveCodec`，实现 `npc.version=1` 校验、编码和旧档明确迁移；
- 先以纯规则专项通过，再进入场景接入。

### S2：内容接入

- 填充五名 NPC 的稳定内容表；
- 填充 15 个个人事件、2 个关系事件；
- 填充至少 60 个对白槽位和 fallback；
- 对内容 ID、条件引用、事件前置、关系边引用做完整性检查；
- 不接真实 NPC 模型前，不把 `implemented` 写入账本。

### S3：装配层接入

- 由 Main/Bootstrap 只负责注入服务和连接端口；
- SEA-INTERACT 把交互目标转给 NPC；
- SEA-TIME/SEA-WEATHER 只提供快照；
- SEA-MOVE/SEA-WORLD 消费 `MoveIntent` 并回传到达/不可达结果；
- SEA-UI 展示对话和关系，只发送输入意图；
- Inventory 预检/扣除成功后，NPC 才结算礼物关系；
- SnapshotRegistry 注册 `npc`，恢复完成后才刷新表现。

### S4：正式表现与验收

- NPC 角色模型、肖像、动画和锚点资产另走 SEA-ASSET 登记；
- 验证日程切换、真实行走、不可达 fallback、对话 UI、关系网展示；
- 验证读档、坏档保护、跨进程恢复和重复交互；
- 设备、性能、内容审阅和美术授权分别记录，不用纯规则通过替代真实表现验收。

## 7. 必须写成会失败的断言

以下契约不能只靠注释：

1. **五人固定性**：`npcs.json` 必须恰好包含 5 个唯一 `npc_id`，关系边两端必须存在。
2. **关系边有界**：`edge_effective = clamp(edge_base + edge_delta, -100, 100)`；异常值拒绝，不静默截断存档数据。
3. **好感有界**：`affinity` 必须是整数 `0..1000`；心级必须等于 `floor(affinity / 100)`。
4. **对白完整**：每个事件页至少一个可显示文本键；缺条件走 fallback，不得返回空页。
5. **对话幂等**：同一 `choice_id` 重复提交不得重复改变关系或事件奖励。
6. **日程可降级**：目标锚点不可达时必须发出 `npc_schedule_fallback` 并返回 home anchor。
7. **存档边界**：`npc` 快照不得包含路径、SceneTree 对象、临时打字进度或其他模块私有库存。
8. **查询隔离**：关系图、NPC 快照和对话状态返回深副本，修改副本不能改变服务内部状态。
9. **跨模块写入**：NPC 不得直接调用 `Economy`、`Main`、`HUD`，不得写 Farm/Building/Inventory 的内部字段。

## 8. 预期验证入口

正式实现后新增并登记以下专项名称；在代码落地前不把它们写入账本 `verification`，避免把未存在的 runner 入口当作已通过：

| 专项 | 验证范围 |
|---|---|
| `npc-modules` | 五人目录、关系图、好感公式、幂等和纯规则状态机 |
| `npc-dialogue` | 日常/剧情对白、多页、选择、取消、回看、fallback |
| `npc-schedule` | 时间/天气/关系/剧情优先级、目标切换、不可达降级 |
| `npc-content` | 5人、15+2事件、60槽位、稳定引用和缺内容保护 |
| `npc-save` | v1快照、坏数据不改现场、旧档迁移、跨进程恢复 |
| `npc-integration` | 交互、UI、移动意图、送礼端口、公开结果事件 |
| `visual-npc` | 五人真实表现、对话面板、日程移动和关系网可读性 |

## 9. 当前状态与下一步

当前状态：**规划完成，施工未开始，正式代码 0 条路径。**

下一步应从 S1 开始，先建立纯规则服务与最小内容表，再申请正式场景接入。不要先做五个 NPC 场景节点；没有服务、快照和失败断言，先做模型只会把规则重新散落回场景脚本。

本轮没有修改 `godot/` 正式运行代码、玩家存档、场景摆位、资产登记或 `web/` 原型。

## 10. 下午制作：七人全套任务当前承接

### 10.1 主文档先登记设计分支

下午以[本轮GDD章节](../../GDD_V1.0.md#2026-11-07-七-npc-全套任务设计分支与下午制作承接)和三条独立功能行承接，不以本记录反改其他功能文档：

| 分支 | 唯一职责与前置 | 新条款与状态 |
|---|---|---|
| [SEA-RESIDENT](../features/resident/spec.md) | 七人规则/会话/world投影；在原WORLD/BUILD/MOVE/TIME/WEATHER/INTERACT/INVENTORY上接RESIDENCE/AVATAR输入，UI/SAVE仅装配协议 | 保留R01–R07原语义，追加R08角色组装、R09住所消费、R10职业挂载、R11集成、R12实际规则口径；partial |
| [SEA-SHOP](../features/shop/spec.md) | 独立Service/Catalog/Panel；前置INVENTORY/CROP/INTERACT，不硬依赖NPC或Farm | 保留R01–R06，追加R07面板、R08原子交易与有限去重、R09集成；partial |
| [SEA-RESIDENCE](../features/residence/spec.md) | 正式房屋/社区空间/Marker；只依赖WORLD/ASSET/INTERACT，无反向NPC边 | 新R01–R07逐条承接独立域、七屋、静态布局、35Marker、统一空间、存档边界及验收；partial |

修改前只读解析GDD候选依赖图，候选三条行未发现环；只是静态设计检查，不替代正式结构专项。没有运行sync、Godot、作者脚本或测试，没有修改其他功能依赖、代码、registry或runner。ledger标题/回链/JSON与历史保留，小范围Edit追加，不整体重写。

### 10.2 下午已见的源码与静态内容（不是运行通过）

| 层 | 当前实际路径/内容 | 仍需区分的边界 |
|---|---|---|
| NPC规则 | godot/src/npc/npc_service.gd、npc_catalog.gd、npc_relationship_graph.gd、npc_schedule_resolver.gd、npc_dialogue_runner.gd、npc_save_codec.gd | 不是上午草案中的src/npc/data或ports空目录；无Autoload规则测试与整局集成分开 |
| NPC内容 | godot/assets/data/npc/npcs.json、dialogues.json、events.json、requests.json | 只读数量核对7人、21个人+4关系事件、84日常对白、9边；不是剧情可玩/回看/缺内容保护验收 |
| UI与world | npc_panel.gd、npc_session.gd、npc_interactable.gd、npc_world_presenter.gd、npc_world_ports.gd | 独立面板/会话源码已存在，不能仍说“无UI”；Main旧桥接和输入盾尚需收口 |
| 角色 | npc_actor.gd、npc_accessories.gd复用Avatar/Character/骨骼原动作 | 七件配件存在不等于外观参数齐全、动作穿插和真渲染通过；不触碰玩家profile |
| 商店 | godot/src/shop/shop_service.gd、shop_catalog.gd、shop_panel.gd；assets/data/shop/shops.json | 2目录11商品；三作物种子取CropCatalog的seed/seed_price，ItemDB供名称描述，不能仍沿用旧商品ID/硬编码价格 |
| 住所 | godot/scenes/residence/的resident_harbor、shell与7独立房屋TSCN；src/residence/resident_harbor.gd | 七屋每座50m²(10×5)，床/桌/灯和两商店空间；正式TSCN是布局真值，不再是NPC临时拼屋 |
| 生活空间 | assets/data/npc/residences.json版本2、7×5生活Marker、WalkAreas/Community、GroundSpace | 35只计Home/Work/Social/Rest/Door，不含泊位；JSON存ID/路径，不存第二份坐标/存档布局 |

### 10.3 七人身份、组装与职业承接

| 当前名 / 稳定npc_id | 独特配件accessory_id | 外部功能意图 | 住所 |
|---|---|---|---|
| 牵线 / npc_luo_yan | signal_spool | ship | residence_dock_workshop |
| 叶脉 / npc_mu_he | seed_pouch | cultivation | residence_sunroom_greenhouse |
| 回声 / npc_ji_chen | diving_goggle | salvage | residence_salvage_cabin |
| 榫口 / npc_nan_zhi | joint_pencil | building | residence_builder_loft |
| 灯芯 / npc_bai_shi | lantern_badge | archive | residence_lantern_archive |
| 花序 / npc_hua_yi | petal_visor | vendor_requested→shop_flower | residence_flower_shop |
| 货架 / npc_bao_he | stock_clip | vendor_requested→shop_general | residence_general_store |

旧显示名仅是上午历史，稳定ID不重命名。程序化NpcActor复用AvatarCatalog/AvatarVisual/Character、既有骨骼与动作采样；NPC局部外观快照不提交玩家AvatarProfile，不覆盖玩家角色。主线程核实七套skin/morphs等参数是否齐全，再签npc-appearance及真实渲染；未核实不能用默认外观冒充七套正式差异。

五职业由NpcSession发action_requested，主线程路由外部功能口；NPC不拥有船只升级、种植、打捞、建造或档案业务状态。两经营者仅发vendor_requested，先撤销NPC模态再开独立ShopPanel；不能因按钮存在就勾选外部功能完成。

### 10.4 正式住所、锚点与物理路线

main中新增 `World/SeaStructures/resident_harbor` 实例，正式资源 `res://scenes/residence/resident_harbor.tscn`，zone_id=`resident_harbor`，当前参考位置(38,0,-32)；坐标仅供参考，可手摆，不覆盖其他场景摆位。住所布局只认静态TSCN，residences.json版本2仅映射稳定ID与Marker路径，不是npc.version。

NpcWorldPresenter仅消费住所anchor_snapshot和统一GroundSpace；world_ports通过surface_point/path_between取路线，CharacterMotor/Character.move_ground执行实际位移，不自行生成房屋/地面，不按插值穿墙。夜间消费自家Rest站位，不站床心；无路尝试home，home也失败就停止，出生或支撑失效可停止并隐藏，必须可观察fallback。读档清临时路径重求路，不恢复NPC世界坐标副本。挪动社区/房屋后的空间刷新及旧锚点alias是否真实存在，主线程核实后实测，不先宣称任意布局都支持。

### 10.5 日历、严格存档与库存原子性

- 实际规则：day从1开始，week=str(int((day-1)/7))，weekday=(day-1)%7+1，生日年内日=(day-1)%112+1。优先生日独立1次额度，再用当周普通2次；生日当天成功礼物均乘3。礼物按品质normal/silver/gold=1/1.1/1.2，roundi后clamp[-80,120]再clamp affinity[0,1000]，记录last_gift_day拒绝倒退。该112日周年不是HUD365日显示日历，不改玩家时间/profile。
- durable只归npc.version=1：根version/graph/seen_events/choice_flags/request_states；graph含七人met/affinity/last_talk_day/gift_week/gift_count/birthday_gift_day/last_gift_day及九边edge_deltas。seen_events是event_id→{day,choices}字典，不是旧数组；choice_flags与边delta必须由合法剧情路径/日期重建，请求来源/状态/完成标签匹配。精确字段/ID、有限整数及全部交叉约束以NpcSaveCodec.validate为准，from_dict先验后换，坏档不改现场。
- 旧无npc仅在明确migration补empty_snapshot，已有坏npc/未来版本拒绝，不以空默认覆盖。保存取消未提交对白，不存打字/待确认/路径/临时目标。主线程对齐SaveSchema/SaveGame/Registry并在全恢复后刷新world；shop静态目录和住所静态TSCN无另副本存档，Inventory保存物品与瓶盖，game仍保存玩家稳定位置。
- 主线程负责新增真实原子Inventory.exchange(costs,gains)，NPC/Shop只接注入端口。失败数量/排列/信号全不变，成功完整提交后才发信号；禁止pay/add/remove加补偿退款模拟。NpcService命名方法端口不能传捕获闭包；请求result只通知，acknowledge_request校验result_tag后仍需库存交付。
- Shop buy的token去重仅单实例120秒、最多256条（含拒绝结果）、不续期；同token同参重放副本不再发事件，异参拒绝，空token独立请求。过期/淘汰/configure/实例重建不保证去重，不存token，不承诺跨进程exactly-once。

### 10.6 主线程接线清单（待做/待核，不勾完成）

- [ ] 注入NpcService/world需要的有效对象命名查询、时钟/天气/屏蔽状态与库存count/exchange/remove/result端口，清理旧闭包契约冲突。
- [ ] 实现并注入真实Inventory.exchange，验证生产库存拒绝/成功信号及重入，而非仅fake通过。
- [ ] vendor切换独立ShopPanel，不再hud.open_tab(shop)；移除重复打开/旧HUD对白路径，统一NPC/Shop模态与Esc/暂停/标题/睡眠/室内/距离失效清理。
- [ ] 分别接通ship/cultivation/salvage/building/archive外部公开功能口，回填每个接收方、实际反馈和未实现项，禁止NPC私写业务状态。
- [ ] 核实七人完整外观输入、配件生命周期/动画及玩家profile隔离；npc-appearance和真实渲染分开。
- [ ] 对齐35Marker/旧日程alias、主场景zone/泊位/GroundSpace、物理路线及社区变换，不重跑作者脚本覆盖手摆。
- [ ] 对齐严格codec与SaveSchema/迁移/Registry全量恢复/world刷新，跑旧无npc、已有坏npc不改现场、取消/重放和跨进程集成。
- [ ] 核实统一runner实际注册，执行下表专项及真实渲染；把实测结果回填三账本和GDD，未验保持partial。

## 11. 主线程实测回填占位

本分支没有执行sync、Godot、专项或真实渲染，不填写通过/失败计数。隔离测试、源码存在、预期入口和历史日志都不是当前工作树整局验收。每项记录实际入口/完整命令、提交或工作树版本、退出码、断言/失败数、日志/截图及未验项；正式runner注册由主线程负责，文档不猜入口已经存在。

| 证据层 / 计划专项 | 已见路径线索 | 主线程待回填 |
|---|---|---|
| 结构 | GDD、三spec/ledger、module_contracts | 实际依赖/条款/链接检查命令、版本、结果；只读候选图无环不能替代正式结构专项 |
| 运行：npc-rules | godot/tests/test_npc_rules.gd | 真实命名端口、礼物周/生日/倒退、剧情/请求/幂等/严格codec；实际runner名/命令/退出码/计数/日志待填 |
| 运行：shop-rules | godot/tests/test_shop_rules.gd | 目录/报价/副本/坏数据/真实exchange及token边界；实际入口/结果待填 |
| 运行：npc-world | godot/tests/test_npc_world.gd | 35锚点消费、日程/物理路线/fallback、独立Panel/Session、暂停/取消/恢复；实际入口/结果待填 |
| 运行：npc-appearance | godot/tests/test_npc_appearance.gd | 七外观/七配件/骨骼动作/profile隔离/生命周期；实际入口/结果待填 |
| 运行：residence | godot/tests/test_residence.gd；src/residence/verify_residence.py适配线索 | 7×50m²/床桌灯/两商店/35Marker/统一GroundSpace/变换/真实胶囊穿门；入口与结果待填，不把visual-residence名称当视觉通过 |
| 集成：save/integration | SaveSchema/SaveGame/Registry、Main生产装配与已有save/integration路径 | 旧无npc明确migration、坏档不改现场、玩家profile不变、库存结果、world刷新、跨进程；实际专项名称/命令/日志待填 |
| 视觉：真实渲染 | godot/tools/capture_npc_appearance.gd、capture_npc_world.gd及住所/面板场景 | 七人/配件/动作/七屋/家具/两商店/NPC路线/独立面板真实截图、图形后端、审阅结论待填；headless不替代 |
| 设备/性能 | 待主线程选择实际设备 | 设备/分辨率/后端/输入/性能/文件系统验证与日志待填 |
| 未验与资产 | 三功能账本遗留项 | 未覆盖条款、生产资产登记/授权、缺失职业接收方和复验范围待填，不虚构AssetID或设备通过 |

### 当前结论

上午“规划完成/零路径”仅历史；下午已有规则、内容、角色/UI/world/住所/商店源码和正式场景，仍是 **partial / 接线与全套实测待主线程签署**。没有本轮通过数，不宣称所有任务完成。文档更新不代替主线程实际施工与验收。

## 12. 19:40覆盖：天台草地暂驻与住房暂停

### 12.1 最新范围与历史覆盖

用户19:40要求：“先不用做他们的住所，先全部放到那个天台草地上去”。本节是当前优先口径。第1–11节以及GDD/三功能spec与ledger中的七屋/7house、50m²、床桌灯、两住商房屋、35住所Marker、(38,0,-32)参考位与住所接线/验收待办均保留历史，不删除、不作为本轮硬前置，不冒称住房完成。

SEA-RESIDENCE登记保持partial，因为已有历史制作资源留存；本轮住房制作、接入与验收deferred（用户暂停），不新增住房开发，不把暂停签退成通过。截至本轮收尾，Main现有resident_harbor实例及zones/scope绑定已移除，源资源保留；用户手摆root及其他旧transform未动。本次仅更新文档记录该执行结果，不修改生产代码。恢复住房开发须等用户后续明确要求。

### 12.2 当前正式现场与稳定条款

- 七人正式现场改为rooftop_ranch天台草地，尊重用户手摆root，使用其下NpcStations的35个局部Marker（7×Home/Work/Social/Rest/Door）。Marker随scene/root变换，不写绝对世界坐标、不使用历史住所参考位、不重跑作者工具覆盖手摆。
- 七人当前无物理房屋；Home/Rest等ID只表示草地站位语义，UI统一写“暂驻天台”，不得写“已经住屋”。保留七人稳定npc_id、七件配件、21个人+4关系事件/84日常对白/9边、五职业和花序/货架两商店，不回退内容。
- GDD功能依赖移除SEA-RESIDENT→SEA-RESIDENCE，其余不变。R09保持NpcWorldPresenter / NpcWorldPorts与CharacterMotor/GroundSpace owner，改为“通过公开世界站位端口，当前草地，后续可插住所”；无住所资源加载硬前置。NPC只读站位/空间、发移动意图，不生成房屋/地面、不另存坐标。
- 新增稳定SEA-RESIDENT-R13，resident ledger仅新增一行pending主验，承接天台暂驻/35局部Marker/无房屋UI、旧实例及binding移除与源保留、当前独立验收。
- NPC独立、Shop独立；vendor_requested→独立ShopPanel及真实Inventory端口不变，五职业走外部公开意图。住所暂停不暂停角色配件/剧情/商店/职业，也不为两店新增住商房屋。

### 12.3 历史PASS与当前pending隔离

历史证据路径：`D:/projects/sea-work/verification/20261107-192319-seven-npc-release-a6fb1b`。其中release integration/save已PASS，但这是**住所版历史**，不是天台版；不据此声称当前天台通过或住房全项完成，不猜断言/通过数。当前最新天台验收尚待主线程稍后回填，以下均为pending；文档更新不运行Godot、sync、作者工具或专项。

### 12.4 主线程待回填：当前天台版

| 回填段落 / 对应条款 | 主线程应填实际证据 | 当前结论 |
|---|---|---|
| Main接入清理 / R13 | resident_harbor实例及zones/scope绑定已移除、source保留，用户root及其他旧transform未动；最终快照版本随第13.4节统一签署 | 清理已完成；不是住房完成或天台全量主验通过 |
| 天台站位与路线 / R09、R13 | rooftop_ranch用户手摆root/NpcStations35局部Marker、稳定ID映射、scene/root平移旋转后的实际站位与GroundSpace路线/fallback/支撑失效 | pending主验 |
| 七人内容与UI / R07、R08、R10、R13 | 七人/七配件/剧情保留，五职业实际接收方及反馈；七人无物理房屋，UI“暂驻天台”截图 | pending主验 |
| 两店与模态 / SHOP-R04、R07–R09 | 草地花序/货架→vendor_requested→独立ShopPanel，关闭NPC模态/输入盾/真实Inventory交易与重复请求边界 | pending主验，无住房前置 |
| 存档与集成 / RESIDENT-R06、R11–R13 | 天台版release integration/save实际入口、命令、版本、退出码、断言/失败数/日志；旧档迁移、坏档不改现场、跨进程、恢复后重求路线，不借用住所版PASS | pending主验 |
| 真实渲染与设备 / R08、R11、R13 | 天台七人同框/配件动作/路线/两店独立面板及暂驻UI截图、图形后端/设备/性能/审阅结论与未验项 | pending，不以headless或历史图替代 |
| 住房历史封存 / RESIDENCE-R01–R07 | 仅记录源资源留存、用户暂停与未来恢复条件；旧住房专项不在本轮补做，不签退通过 | partial，deferred用户暂停 |

回填同步位置：GDD“19:40主线程待回填”、resident spec“主线程回填占位”及ledger R13/验证记录、residence spec/ledger“19:40覆盖/历史封存”、shop ledger“19:40覆盖/主线程回填占位”、module_contracts“19:40NPC世界站位覆盖”和本节。本节为19:40阶段记录；最新已验/失败和仍待签署以追加第13节为准。

## 13. 性能优先收尾与当前证据

### 13.1 当前施工完成事实

Main已移除resident_harbor实例及zones/scope绑定，source留存；七人全部接到既有rooftop_ranch用户手摆root下NpcStations35局部Marker，无物理住房、UI“暂驻天台”。root和其他用户旧transform未动，住房source与R01–R07仍partial/deferred，不在本轮恢复制作或验收。NPC与Shop独立，7人/7配件、21个人+4关系剧情/84对白/9边、五职业、两店11商品与三花各四stage已实现，有专项；上方旧“仅见源码/待装配”不能继续当当前完成事实。

本轮天台泊位仅改局部Marker `(26.4,57.3,-2.1)` 与boat `(26.4,57.04,-5.1)`、yaw=PI/2，避开shore_environment旧圆弧楼shape。此为当前局部测量值，不钉死世界坐标、不移动用户root，不新造住房或改旧圆弧楼来掩盖碰撞。

### 13.2 稳定条款与性能修复

新增SEA-TIME-R12、SEA-RESIDENT-R14并在各自spec/ledger逐条承接，R13天台条款保留：Main删第二clock.tick，仅sleep_cycle.advance内部至多tick一次并cap23:00，06:00醒/07:00晨次不变；clock.changed经Main._on_npc_clock_changed→notify_world只小dict，不同步解析。Presenter0.5s检测日/分钟、任意日程from/to+conditions hour+21:30边界、天气/关系剧情/手摆Marker/root/support变化，一batch仅1snapshot，support cache带active/surface/revision失效，idle免逐physics支撑投影，force恢复保持。

[完整性能记录](2026-11-07_npc_performance_fix.md)承接报告、命令、快照版本、统计口径和未验；[原帧诊断](2026-11-07_frame_diagnosis.md)只在末尾追加修复后结果，旧诊断不删不改。保持泛光、画质及七人，没有通过减质/删NPC换帧率。

### 13.3 已验、失败与独立pending

| 层 / 报告 | 当前结果 | 不得扩大解释 |
|---|---|---|
| [204747小fixture](../../../sea-work/verification/20261107-204747-npc-performance-final-8687e2/report.json) | npc-performance61/0、exit0；120notify+sync共558μs | 不是正式Main每120帧成本 |
| [211435性能合批](../../../sea-work/verification/20261107-211435-npc-performance-rooftop-7e1d96/report.json) | npc性能61/0、rules655/0、world119/0、appearance2469/0、careers71/0、flowers1233/0、sleep42/0均exit0/PASS | shop-rules218/7、exit1/FAIL为历史，213213最终259/0已解决；不反写旧合批全绿 |
| [212152真实Main时钟](../../../sea-work/verification/20261107-212152-npc-clock-once-cc6ca7/report.json) | npc-clock301/0、sleep-cycle42/0均exit0/PASS | 不替代天台全量存档/集成 |
| [211124天台通行](../../../sea-work/verification/20261107-211124-rooftop-access-final-5ada04/report.json) | access772/0、rooftop655/0、water-layer1613/0均exit0/PASS | 同报告landing-markers另有失败，不能签整份报告通过；非住房验收 |
| [211435真实帧/函数](../../../sea-work/verification/20261107-211435-npc-fps-after-fix-6e7a56/report.json) | visual-frame-functions/diagnosis均exit0；Forward+/4060Ti实际1600×1000，泛光开59.943FPS、帧p5016.681ms/p9518.097ms，关59.956、再开59.956；Main._process median0.752ms，旧153.23 | 重复npc_sync median0.008ms五样本含首轮2.458ms，不是全量sync每次0.008；sleep0.017/clock0.012ms。旧~5.7FPS场景住所已撤、draw3186对旧3654–3955，不把全部约10倍归纯算法；函数直接证明同步阻塞消除 |
| 全量天台integration/save/restart | 已收齐214439五项2277/0、均exit0/PASS、unexpected_errors空；详见第14节 | 当前天台独立证据，不挪用192319住所版PASS |
| 14真实截图与目检 | 14PNG已产出，主线程已目检seven-residents/flower-purchase/story-choice三图 | 其余11图待人工审阅，不称全14图目检 |

### 13.4 主线程最终统一回填（仍待签署）

原待签表已收齐运行证据，标题保留作历史锚点；正式签署见第14节。

1. **Shop UI复验已通过**：213213 shop-rules259/0、exit0/PASS，保留211435的218/7失败历史并标已解决；实际命令和快照见报告。
2. **天台全量运行已通过**：214439 integration668/0、save618/0、seed408/0、restart202/0、visual381/0，总2277/0，五项exit0/PASS、unexpected_errors空；已覆盖坏档原子与重启profile隔离等当前链路，不再pending执行。
3. **14截图已产出，部分目检**：主线程实际审阅seven-residents、flower-purchase、story-choice三图；其余11图待人工审阅，不提前签全图目检。
4. **范围与全局门禁**：NPC当前R01–R14运行实现通过，NPC/Shop状态implemented（非verified）；产品设备/发行包/持续性能/全剧情人工体验及剩余图审另待。历史landing-markers额外失败不自动升级原专项PASS；global check由主线程另跑。本轮住所仍partial/deferred，不要求补做。
5. **最终同步位置**：GDD最新“NPC性能修复与天台收尾（当前）”、resident spec末节/ledger最终回填、time spec R12/ledger最新证据、shop ledger末节、module_contracts末节、本节及[性能记录第6节](2026-11-07_npc_performance_fix.md#6-主线程最终待填位置)。residence spec/ledger只维持已撤挂载/source封存/deferred，不写住房完成。

### 13.5 文档线程检查交接

定向检查exit0：4份ledger JSON原样、条款14/12/7/9承接一致、386相对链接无缺失、原诊断正文保留且仅追加、指定范围diff --check通过。全局契约实际执行sync后check，仍分别exit1 / 20 issues与exit1 / 22 issues，不是全局通过；历史shop-modules登记入口、鱼群source与16份runtime哈希、zones/dialogues内容索引、住所摘要及derived index问题由主线程统一收口。sync因问题未写生成索引，本线程未越界刷哈希或改JSON。详见[性能记录第7节](2026-11-07_npc_performance_fix.md#7-文档线程定向检查与全局门禁交接)。这是上一轮历史门禁，不是本次重跑结果；shop verification现已由主线程改正，住所摘要由主线程随后规范化，其余全局问题不推定已解决。

## 14. 最终天台交付范围签署

### 14.1 已收齐的最终运行证据

- [213213最终Shop输入报告](../../../sea-work/verification/20261107-213213-shop-input-final-638cdf/report.json)：shop-rules259 checks / 0 failures，exit0/PASS、unexpected_errors=[]。原211435中218/7 UI失败已解决，保留原日志/报告，不反写旧批全绿。Shop登记verification已由主线程改为shop-rules/npc-integration/npc-save/visual-npc-release。
- [214439当前天台最终报告](../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/report.json)：npc-integration668/0、npc-save618/0、npc-save-seed408/0、npc-save-restart202/0、visual-npc-release381/0，**总2277/0**；五项全部exit0/PASS、completion_marker=true、unexpected_errors=[]。实际完整命令、隔离user_data、head aa12686907371f5e389e5923f259a2f886738235、working_tree及工程外project快照见报告。
- 真实HUD航行/上下船/消防梯/七点实际走路/鼠标点击与E、各职业端口、七人请求礼物、坏档原子性与重启profile不变均已在当前天台通过；不是只验节点，也不挪用历史住所版PASS。当前草地站位provider为[npc_rooftop_anchors.gd](../../godot/src/npc/npc_rooftop_anchors.gd)，七人全部原rooftop_ranch草地对应职业站点，无新住房，root与其他旧用户transform未动。

### 14.2 14张PNG与真实人工审阅边界

14PNG均位于214439目录 `project/outputs/npc-release-*.png`；Forward+/RTX4060Ti，日志实际viewport1600×1000（启动1280×800另记）。[全部14图逐图相对链接](2026-11-07_npc_performance_fix.md#8-最终天台运行签署与14图清单)。

主线程**实际目检三张**：seven-residents确认7人站原天台草地、无新住房、形象与配件可辨；flower-purchase确认花店5商品/价格正确及购买成功；story-choice确认剧情文字可读、2choices，三图中天台暂驻UI已确认。其余overview、七张单人、general-shop、relationships、ship-career共11张尚待人工审阅/联系图，不称14全目检；visual381/0是渲染自动验证而非全部人工审阅签署。

### 14.3 状态与未覆盖的产品验收

- NPC R01–R14当前运行实现已通过；Shop当前R01–R09运行实现已通过。两账本status定点改为 **implemented（已实现待完整产品验收）**，不改为verified；GDD机器摘要与索引由主线程最终同步。
- 完整产品验收仍未覆盖：NPC R02/R07全剧情人工体验；R08/R11/R13剩余11图人工审阅；R11/R14其他设备/发行包/持续性能。Shop R05/R07/R09剩余视觉/资产权属/设备与长期体验另待。不是当前功能接线未完成。
- 既有59.943FPS及函数统计完整保留，0.008ms是含首2.458ms的重复sync统计，不是每次全量成本；旧住所撤除/draw变化与算法收益分开，保留泛光/画质/七人。
- SEA-RESIDENCE仍partial，历史R01–R07及source资源deferred用户暂停；不签住房完成、不恢复开发。历史landing-markers原专项额外失败单列，不因本轮天台通行集成通过就称它已重跑。
- 上述为文档分支当时不执行global check的记录；后续主线程已定点同步状态并执行，最终结果见下一节。

## 15. 主线程最终回归与交付收口

- [221054最终11项回归](../../../sea-work/verification/20261107-221054-npc-final-regression-bc8a22/report.json)共 **5324 checks / 0 failures**，全部PASS/exit0；包括原三品种+三花六品种96/0、真实花种1233/0、独立商店259/0、NPC外观2469/0、性能61/0、Main单时钟301/0与睡觉42/0。
- [222551最新工作树复验](../../../sea-work/verification/20261107-222551-npc-final-live-worktree-6eb68a/report.json)：角色真实渲染 **241 PNG / 0 failures**、旧购买适配器44/0、正式集成668/0、存档618/0、seed408/0、restart202/0，全部PASS/exit0、unexpected_errors空。补验曾捕获并行交互迁移中未声明字段导致编译失败，以及外观完成标记失配；已修复并重跑，不以exit0而忽略脚本错误。
- 14张天台场景图已通过原图/联系图补审，七人正面捏人设计另审；241图不冒签全部人工审阅。七人原草地落位、无新住所，店铺与剧情清晰，草较高在远镜头遮腿/小配件的表现限制已记录。
- 交付预览与真实截图包位于工程外 `sea-work/outputs/npc-rooftop-delivery/`；未建立网页玩法或修改用户主场景建筑transform。NPC/Shop分别implemented待完整产品验收；住所partial/deferred。
- 最终架构门禁25服务/0问题、3手摆结构/0警告、diff检查exit0；全局合同 **sync17/check18 issues** 仍未通过：3source、14runtime与派生索引stale，未批量签混合/未知变更。[精确列表、性能归因与证据](2026-11-07_npc_performance_fix.md#9-主线程最终回归视觉审阅与门禁)。保留原失败历史，不宣称全工程或发行包验收。
