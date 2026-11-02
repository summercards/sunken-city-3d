# 2026-11-02 建造旧档续建、搬移与拆回反馈

关联SEA-BUILDING-R02/R06/R11/R12/R22/R26、SEA-SAVE-R10/R13。

用户反馈更新后旧建筑仍在，但不能续接、搬移或拆回；手册的「拆回 Delete」按钮缺少有效反馈与操作指引。

## 核查结论

玩家默认槽位及备份已只读复制到工程外`D:/projects/sea-work/investigations/2026-11-02-building-save/`。主档副本25个建造物通过正式SaveGame.decode/restore，布局与作物保留。本轮没有写入玩家槽位、没有重置进度。不是本次主档损坏或建筑丢失。

三个实际缺口：

1. 平台归一只覆盖「浮台接旧木板」，木板仍按全局整数网格选位、只认网格邻居。玩家旧浮台中心局部坐标`(2,10)`，边界与旧木板网格不齐；新木板可能重叠或隔缝，无法按统一平台规则续建。旧档没错，后续操作使用的几何规则不完整。
2. `select_recipe`在进入管理模式前检查当前地点。玩家在阳光房时，按拆回会被资格拒绝，停留在书本；模式未打开。既有提示又位于画面底部，文案仅提木板/培养土，缺少明显模式标题和返回入口。
3. 管理选取把鼠标射线投到当前楼层平面，只查底面矩形；点击灯杆、墙体等的可见主体不等于点中它的底面，也就无法选中。没有目标的点击原先无解释。

存档目前确实会用当前规则校验历史布局；本轮已用真实副本排除它是本次现象的直接原因。没有通过放宽损坏数据校验来解决操作问题。目录定义发生破坏性变更时仍须单独设计明确迁移，不在本轮声称已具备任意未来版本兼容。

## 实现

木板优先保留能合法拼接的原网格位置；附近网格不能贴合时调用平台共用的边对齐求解。新非网格木板保存可选布尔`positioned=true`及有限`px/pz`；缺省/false继续按旧`x/z`解释。根v4、building v1、旧ID及原记录位置保持。渲染、承载、行走、船阻挡、登陆和回收均使用Catalog.footprint_rect；显式坐标木板不进入旧网格占用索引。接缝至少0.6米，只有完工平台提供连接；远处岸上点击仍显示该处无效预览，不把光标目标拉回岸边。

搬移/拆回按钮允许进入可见模式，资格拒绝在模式里说明「前往自建平台或乘船靠近」。上方纸色提示卡显示模式名、左键步骤、目标名称、拒绝原因、返回手册按钮及Esc；三维射线按目录矩形/高度选择最近目标并画轮廓。不可搬移的平台、原有固定设施、有作物、依附承载、当前角色和通路保护继续生效。点击空处提示选择自建物件。所有状态修改仍经BuildingService，退款仍经注入Inventory端口。

## 本轮验证

运行均经`scripts/run_verification.py`，Autoload之前隔离用户数据，测试产物位于工程外`sea-work/verification/`。

最终24项检查均通过、各退出0、非预期引擎错误0；最终结果按测试名选用最近一轮，过程失败保留在下方及原始报告，不计作通过。机器记录见[验证摘要](2026-11-02_building_save_compatibility_verification.json)。

| 验证 | 当前结果 | 证据目录（`D:/projects/sea-work/verification/`下） |
|---|---|---|
| building-save-compat / visual-building-save-compat | 各39检查/0失败；含玩家副本25实例和作物恢复、旧浮台接新木板、混合坐标磁盘往返、三维点选灯杆并拆回/退款、阳光房管理模式指路；后者真实Vulkan渲染 | `20261102-105322-building-save-final-c0767a` |
| building-open-seed / building-open-restart | 70+8检查/0失败；65实例含搬移作物，跨进程冷启动 | 同上 |
| energy | 37检查/0失败；没有为测试改变体力规则 | 同上 |
| visual-building-diy / visual-recipe-cards | 29+108检查/0失败；真实鼠标页签/卡片、搬移保留作物、拒绝有作物回收、空种植区回收退款 | `20261102-105045-building-ui-regression-6f02fe` |
| building / building-join / building-open-rules / building-space | 30/37/122/18检查，均0失败 | `20261102-104952-building-save-regression-15ae13` |
| building-integration / building-seed / building-restart / building-approach | 53/5/11/18检查，均0失败 | 同上 |
| building-kit / building-simulate / building-perf / building-decoupling | 121/191/7/62检查，均0失败 | 同上 |
| save-corrupt-seed / save-protection / save-seed / framework-integration / character-space-save | 全部退出0；集成44、三维恢复10检查/0失败；损坏/未来档为预期业务拒绝，非预期引擎错误0 | 同上 |

已目视检查`20261102-105322-building-save-final-c0767a/project/outputs/building-remove-guide.png`，模式卡、左键指引、选中轮廓和退款提示均可见。设备触控、手柄、断电与发行平台文件系统本轮未执行；任意未来目录几何变更迁移不在本轮承诺范围。

`check_feature_contracts.py --sync`与无参检查均通过（36功能、565源资产、465运行资源哈希，0问题）；架构17独立服务、0问题。运行资源登记只刷新经本轮代码审查/运行验证的7个建造脚本；另修正一条已证实的历史基线错误：`ocean_sky.tres`工作区内容与HEAD逐字一致，原登记SHA错误；仅更新该条元数据，未改材质。逐条前后哈希及依据在`sea-work/investigations/2026-11-02-building-save/runtime-hash-review.json`，未批量刷新未知变更。

## 过程失败与修正

- 首次runner受本机GBK默认编码影响，读取UTF-8工程配置失败；后续以`PYTHONUTF8=1`运行，不改项目编码。
- 新专项首轮存在GDScript类型推断错误，已补明确Dictionary类型。
- 专项夹具最初直接调用BuildingService.from_dict复用与玩家档相同的ID，绕过正式恢复的清投影步骤，造成旧地格残留和孤儿作物；改为正式组合层恢复入口。生产SaveGame.restore已有此步骤，本次没有把测试错误当作产品修复。
- JSON数字会从int转float，并对长小数舍入；往返断言改为逐字段结构/数值比较，明确保留所有字段及位置，未放宽生产校验。
- 既有visual-building-diy试图点击「全部」第一页不可见的种植卡片；改为先真实点击种植页签，并在按下前发送鼠标移动事件以更新GUI悬停命中。后续真实鼠标/按键、作物搬移与回收流程通过。
- 既有65实例冷启动夹具未声明`origin=boat`，与当前独立海面起板要求不符，首轮建造全拒绝，随后访问空结果并超时退出124；同轮重启因无种子档退出1。修正夹具显式船上来源、每次建造前经公开体力接口补满，并在前置失败时及时退出。复跑70+8检查均退出0；未改实际资格或体力数值。
