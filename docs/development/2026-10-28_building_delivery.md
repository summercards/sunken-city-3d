# 家园拼接建造、浮木与种植区交付

实施跨2026-10-28至2026-10-29。[主文档](../../GDD_V1.0.md#sea-building) / [独立设计](../features/building/spec.md) / [独立账本](../features/building/ledger.md)。本功能为SEA-BUILDING，不复用SEA-BUILD固定建筑升级状态。

## 玩家操作

1. 家园水域随机分布6束漂流浮木，点击后小船接近收取；停船靠近也可拾取。每束3木板，入包后4–9秒补充；满包保留原浮木。
2. 商店的家园补给页出售土壤，4瓶盖/份，材料直接进入包裹。
3. 登上现有六格种植平台，展开右上菜单，点设置右侧的建造手册。双页书本列出配方、库存、成本和施工时间。
4. 木板：6木板，3秒。点击平台外围合法虚影付款施工，小进度条结束后成为连续可行走木面；西侧泊位留空，初阶只在当前平台周围两圈内拼接。
5. 种植区：3木板+2土壤，4秒。在已完工的新木板上移动鼠标摆位，0.1米吸附、R旋转，点击合法位置施工。每块新板最多一格，边缘保留通行空间；完工后使用现有操作气泡播种、浇水与收获。
6. Esc退出预览；取消预览不扣费。已付款施工继续，可以存档、退出、恢复剩余工时；暂停冻结，离线不推进。

当前未开放海上施工、拆除和搬移。未来海上施工替换资格策略接口，仍使用同一支付、占地和存档规则。

## 模块与稳定预制体

`godot/src/building/building_service.gd`是布局唯一写入者；Catalog维护尺寸/配方；Boundary通过注入查询判断陆地资格、停船位置与其他地面；World把布局投影为模型、行走面、船只阻挡、FarmField节点；Controller与Book只负责操作和展示。无Autoload规则专项可直接运行，支付和世界检查均注入。

通用木板：`godot/scenes/buildables/wood_deck.tscn`，AssetID `SEA-BUILDING-WOOD-DECK`，场景分账本登记。参数化薄木板沿用现有种植平台的厚度与配色，正式稳定路径供预览和实体共用。种植摆件复用现有`farm_cell.tscn`，不复制种植规则。动态地格身份为`dynamic/built_N`；作物状态仍由Farm维护。

新木板施工开始即预留水面占地，完工开放行走；培养土施工开始就扣除其通行占地，避免角色停在将完成的土壤内部。操作锚点位于土壤外围，选择最近可达点。完工后重新检查附近漂流物与鱼群，避免落在新增障碍内。

存档版本4新增独立building段。快照整体验证通过后，先恢复布局与地格注册，再恢复Farm与角色；检查候选地形而非旧现场地形。v3及更早档迁移为空布局，坏档保持现场。边界点与动态地格施工均有冷启动回归。

## 当前实测与证据

全部Godot运行通过`scripts/run_verification.py`，在Autoload之前隔离user目录；无真实用户存档改写。产物位于工程外`D:/projects/sea-work/verification/`。

| 运行目录后缀 | 检查 | 结果 |
|---|---|---|
| `20261029-001140-building-loop-a2167a` | building、building-integration、visual-building、minimum-loop、pocket-services | 全部PASS、退出0；视觉19检查，集成36检查 |
| `20261029-001326-building-save-6fa57d` | building、building-integration、framework-modules、farming | 全部PASS、退出0 |
| `20261029-001455-building-cold-02be23` | building-seed、building-restart | 分别5/8检查，全部PASS、退出0 |
| `20261029-002425-building-current-c7a0d5` | asset-import、building-integration、building-seed、building-restart、save-corrupt-seed、save-protection | 当前并行作物接入后再次验证，全部PASS、退出0；集成38检查，包含实际航行到浮木后入包且未远程领取 |

真实渲染截图位于首行运行目录的`project/outputs/building-{menu,book,ghosts,progress,completed,planted,soil-shop,driftwood}.png`。实测鼠标打开菜单/书本、选配方、点击虚影施工、种植气泡与按键退出；已查看书本、虚影与完工图。

调试失败也保留：首次集成暴露WalkArea类型赋值与资格适配器被释放，已修复；首次截图发现虚影被水面覆盖，已提升透明排序并重新真实渲染；首次冷启动存档在地板边界被Rect2判出界，已统一多边形边界判定并通过独立两进程复验。旧失败目录保留，不计作通过证据。

收尾期间其他任务接入作物Catalog/View，`building-final`与`building-final-fixed`两次运行分别捕获类型推断编译失败；Catalog两处显式类型在本轮补齐，View声明随后由并行工作补齐。以`building-current`导入后复验结果为准。未回退其他任务的作物、美术、水面与灯光改动。

架构检查通过：15个独立规则/存储服务、0问题，新BuildingService和MaterialShop纳入持续边界检查。实施期间全局`check_feature_contracts.py --sync`曾受并行作物交付链接缺失、旧地格源哈希及水面/环境材质哈希漂移阻断；这些由并行任务各自收尾后在复验轮清除，未批量重算未知资产掩盖问题。

未执行：海上建造、拆除/搬移（当前未开放）；不宣称全工程完整回归。各相关功能独立条款与账本已补充对本功能的依赖。

## 2026-10-29 复验（并行作物接入后）

| 运行目录后缀 | 检查 | 结果 |
|---|---|---|
| `20261029-003237-building-resume-7f7eed` | building、building-integration、building-seed、building-restart | 20/38/5/8检查，全部PASS、退出0 |
| 同上 | visual-building（未导入的隔离工程） | FAIL：新作物纹理缺20项资源，属并行作物导入前置条件，非建造回归 |
| `20261029-003346-building-resume-visual-975be0` | asset-import、visual-building | 全部PASS、退出0；产出8张实景截图 |
| `20261029-003551-building-resume-integration-8b4e07` | building、building-integration、farming、minimum-loop、framework-modules、pocket-services、save-corrupt-seed、save-protection | 全部PASS、退出0；29/38/35/77/50/28检查 |

`check_feature_contracts.py --sync`于00:35:16执行后与无参检查均为0问题（35功能、459源资产、381运行期哈希）；`check_architecture.py` 15服务、0问题。此后工作区仍有并发任务（00:37–00:38重写作物GLB、00:39起运行boat-water-contact验证），crop源与运行期哈希再次漂移14–15项并使`crops`的「番茄高于生菜」高度断言失败，均属并行作物/水面任务的在途改动，本轮未代其重算哈希或修资产。当前工作区同时含并行作物、水面与气泡改动，本次仅复验不动其实现。

截图复核：手册双页列出配方/成本/工期与口袋余量；虚影沿木面外侧铺开、水面已不遮挡；进度条完工后木面开放行走；新板上可摆放并完成一格培养土并接种植气泡；浮木6束分布在水域，拾取后补生，满包时保留原浮木。

## 2026-10-29 最终收尾

`20261029-080045-building-visual-layout-d983d2`：asset-import、visual-building全部PASS、退出0，真实鼠标/按键19检查、0失败。已逐张查看本轮`building-book.png`、`building-ghosts.png`、`building-planted.png`，新作物接入后仍能从菜单打开手册、点击虚影完成木板与培养土、沿用操作气泡播种浇水。

此前`20261029-002616-building-current-visual-87db01`未通过：测试在HUD延迟布局前就取坐标点击，后续空数组访问导致超时124；本轮测试先等待8帧布局稳定，并在入口失败时立即退出，随后复验通过。未以超时轮作为交付证据。

最终再次执行`python3 -X utf8 scripts/check_feature_contracts.py --sync`与无参检查，均PASS：35功能、459源资产、387运行期资源哈希、0问题。`check_architecture.py`PASS：15服务、0问题。前述并行任务的临时全局门禁红项已清除，主文档摘要与派生索引成功同步。
