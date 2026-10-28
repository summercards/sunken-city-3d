# SEA-BUILDING · 家园拼接建造

[主文档](../../../GDD_V1.0.md#sea-building) · [独立账本](ledger.md)

本功能独立于SEA-BUILD固定建筑升级。规则与布局由BuildingService唯一拥有，场景适配BuildingWorld、输入BuildingController、手册BuildingBook分别维护；正式代码在godot/src/building。库存只由Inventory写入，作物只由Farm写入，世界导航由场景适配提供派生数据。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-BUILDING-R01 | 右上展开菜单设置右侧新增建造按钮，打开双页书本式建造手册；显示成本、工期和现有材料。 |
| SEA-BUILDING-R02 | 初阶施工者须在浅水种植平台陆地上。木板只在原六格木面周围有限网格边相接扩建，不支持角点连接、悬空、其他岛或船上施工。通过注入资格策略保留未来海上施工能力，不直接读全局状态。 |
| SEA-BUILDING-R03 | 拼接木板消耗6木板、施工3秒；单格种植区消耗3木板+2土壤、施工4秒。参数集中目录配置。选择配方显示可施工虚影，点击合法虚影一次扣费并锁定占地，小进度条结束后转为实体。关闭手册/离开不撤销已付款施工，暂停冻结计时。 |
| SEA-BUILDING-R04 | 新种植区外观与原六格一致，每次建一格；在已完工新木板上按0.1米吸附自由摆位、R旋转，不允许重叠或越界，保留通行与操作位置。完工后沿用Farm播种、浇水、三日生长、收获与满包规则。 |
| SEA-BUILDING-R05 | 新木板立即更新连续行走面与船只阻挡，保护泊位与停船位置；新地格增量注册并接入操作气泡与笔记。不能只生成模型而未接玩法。 |
| SEA-BUILDING-R06 | 布局、稳定实例ID与剩余施工秒数独立存档。整份候选快照验证后再恢复布局/地格登记、Farm、角色与船；旧档迁移为空布局，坏档不改变现场。 |
| SEA-BUILDING-R07 | 规则无Autoload、Main、UI或场景树依赖；注入支付、资格、空间检查端口，查询返回副本。重叠、缺料、重复点击、取消预览均不重复扣费。 |

当前不提供拆除、搬移已建成物或海上独立基地；未来海上资格只更换策略，仍须经过空间、库存与存档契约。允许在施工中保存，恢复不得再次扣料或自动完成未完工物。

空间基准为zone5原木面，顶面1.48米；新木板2.15×2.575米，网格基础3×2格，新区域限两圈且保留泊位通道。摆件记录support_id与局部位置，plot_id由实例ID派生，不能用坐标或列表序号作身份。

接口：configure / catalog / candidates / can_place / begin / tick / query / to_dict / from_dict；changed / completed。快照验证由validate_snapshot执行。接口实现与本轮验证见[交付记录](../../development/2026-10-28_building_delivery.md)。

## 维护方式

- `building_catalog.gd`：配方、几何尺寸与扩建范围。修改后同步手册与验收；手册直接读取配方成本工期。
- `building_service.gd`：唯一布局状态、支付前检查、施工倒计时、纯数据校验；无Autoload可执行。
- `building_boundary.gd`：当前陆地资格与场景空间策略。未来海上施工可替换eligibility端口；不放宽现有存档结构与费用原子性。
- `building_world.gd`：由布局投影模型、WalkArea、水面阻挡和FarmField登记，不另存状态。
- `building_controller.gd` / `building_book.gd`：输入、虚影、进度条与书本展示，只发送命令/读取副本。
- `material_shop.gd`：无状态土壤购买命令，经注入Inventory检查、扣款、入包；UI不实现价格规则。

首版每块新板可承载一格培养土；位置按0.1米吸附，可R旋转，底面必须完全在该板内。不限制一次只能施工一项，可同时施工多个不同位置。西侧为泊位通道，不生成扩建虚影。角色进入睡眠时退出预览，暂停冻结施工；退出建造界面仍继续施工，离线不计时。
