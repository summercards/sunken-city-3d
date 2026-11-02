# 建筑两类账本入口

[主文档](../../GDD_V1.0.md#feature-control) · [分类与职责规范](../../docs/standards/水层分类与空间职责.md) · [唯一主记录](ledgers/scenes.json)

建筑正式按building_class分为**水上功能建筑**与**水下观赏建筑（含基座）**两类。下面的JSON是自动生成的AssetID视图，不是第二份资产主表。

| 类别 | 入口 | 当前资产行数 | 管理内容 |
|---|---|---:|---|
| 水上功能建筑 above_water | [水上登记视图](views/buildings_above_water.json) | 322 | 完整设施、可建结构及水上附属构件；在设施层级提供行走、泊位、阻挡和已定义功能 |
| 水下观赏建筑 underwater | [水下登记视图](views/buildings_underwater.json) | 129 | 海下基座、柱脚／底框、观赏楼、沉没远景及水下装饰舱；全部只作观赏 |

另116行不纳入两类视图（building_class=null）：73行船、独立植物／生活摆件／动物／色板及混合海面设施总览；43行ENV-TOWER-DISTRICT独立参考组件未确认属于海上主场景，保持范围外，另行处理。**资产行数不是建筑栋数**；上述数字包含源级候选、构件和历史记录。

本页只管理**海上主场景及其制作候选**，其中“水下”仅指在海面场景内透水可见的基座和观赏楼。独立海底／潜水场景 `godot/scenes/underwater/` 不在本次范围，不套用“水下只观赏”来关闭其既有功能。

## 水上设施清单

| 建筑／设施 | 稳定AssetID | 关系／状态 |
|---|---|---|
| 阳光房／太阳能木屋 | SEA-REF-FACILITY-SOLAR-CABIN | 水上设施总成；海下基座单独归水下 |
| 绞盘打捞台 | SEA-REF-FACILITY-SALVAGE-STATION | zone1原设施，与野外渔场同址前后阶段 |
| 野外渔场 | SEA-FISHERY-ASSEMBLY | 原打捞台升级后的装配，不增加独立地点 |
| 浅水养殖台 | SEA-REF-FACILITY-AQUACULTURE-PLATFORM | zone5；特殊养殖仍规划 |
| 海上悬浮商铺／补给站 | SEA-SCENE-FSH-ASSEMBLY | sea_supply；当前位置、水线和靠泊故障pending |
| 横滨沉没铁道 | SEA-REF-FACILITY-YOKOHAMA-STATION | 正式资源保留，默认隐藏 |
| 圆弧屋顶农场 | SEA-REF-FACILITY-ARC-ROOFTOP-FARM | 正式资源保留，默认隐藏 |
| 远海街町 | SEA-REF-FACILITY-FAR-SHORE-SETTLEMENT | 正式资源保留，默认隐藏 |
| 太阳能花屋 | SEA-SCENE-SOLAR-FLOWER-HOUSE | 制作源已验收，未接入Godot |
| 清新错层花屋码头 | SEA-SCENE-PFH-ASSEMBLY | 制作源已验收，未接入Godot |
| 饱满卡通热带花屋 | SEA-SCENE-TFH-ASSEMBLY | 制作源已验收，未接入Godot |
| 巨手托举纪念品灯塔 | SEA-SCENE-LHL-ASSEMBLY | 制作源已验收，未接入Godot；漂浮驳船基座归水下视觉件 |

正式8条总成对应7处设施地点；另4套源级候选。通用木板＋12件拼接结构另计13种构件。阳光房海上子总成不重复计为一栋。

## 水下观赏建筑与基座

| 内容 | 稳定AssetID／家族 | 职责与边界 |
|---|---|---|
| 阳光房七层海下基座与23件组件 | SEA-SCENE-BLB-* | underwater；任何视觉顶板不提供可走面或船阻挡 |
| 六种水下景观楼及参考装配 | SEA-SCENE-SUBMERGED-* | underwater；当前main摆放8实例，不是8种模型 |
| 旧沉没街区与远景组件 | SEA-REF-01-BG-*、BACKGROUND-BUILDING-LIBRARY | underwater观赏职责；历史远景的水线／实际无功能仍需接入复验 |
| 独立基础、底框、墩柱、驳船基座 | 工具UNDERWATER_VISUAL_COMPONENTS明确列举 | 按基座视觉职责登记；跨水线源的分段／标高待制作接入验收，不能靠名字盲目认定已全部沉水 |
| 浮店水下推进舱、浮舱、喷口及内芯 | SEA-SCENE-FSH-ENGINE / ENGINE-GLOW / FLOAT-POD / AUX-NOZZLE / AUX-GLOW | 外观组件；不提供真实推进、资源、交互、行走或阻挡 |

当同一视觉包有顶面和下部基础，站立高度、角色碰撞、船只占用都由水上设施投影管理；水下视觉包不承担这些功能。部件可以跨归属类，不能由父级递归扫描把水下观赏件重新算成阻挡。

本次登记的是职责分类；原资产stage／授权pending保持，模型与运行完整验收另记。[本轮整理与校验](../../docs/development/2026-11-02_building_two_class_contract.md)。
