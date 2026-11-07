# SEA-RESIDENCE · 七人住所社区与生活锚点 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-residence) · [功能文档](spec.md) · [NPC账本](../resident/ledger.md) · [商店账本](../shop/ledger.md) · [施工记录](../../development/2026-11-07_npc_module_framework.md)

## 登记头

本页为状态唯一编辑源。静态资源/源码存在不等于运行或视觉通过；主线程实测签署前保持partial。

### 2026-11-07 19:40 用户暂停覆盖（当前）

本功能登记状态保持 `partial`，因为已有历史制作资源留存；本轮住房制作/接入/验收为 **deferred / 用户暂停**，不是通过签退，也不是已完成住房。下方R01–R07、七屋/50m²/家具/住商空间/35住所Marker与历史待办原样保留，不新增住房开发，不再作为本轮NPC/Shop硬前置。当前不接入住房现场；截至本轮收尾，Main现有resident_harbor实例及zones/scope绑定已移除，源资源保留；用户手摆root及其他旧transform未动。此为接入清理，不是住房验收通过。

七人当前无物理房屋，正式现场改为rooftop_ranch用户手摆root下NpcStations的35个局部Marker，随scene变换而非绝对世界坐标，UI仅写“暂驻天台”。当前站位归公开世界端口，后续可插住所；NPC功能依赖已移除SEA-RESIDENCE。历史参考 `(38,0,-32)` 不得作为当前前置或摆位指令。下表住房条目仍属历史partial，不因本轮暂停升级完成；旧“下一步接线/验收”已暂停，等待用户重新授权。

```json
{
  "feature_id": "SEA-RESIDENCE",
  "status": "partial",
  "owner": "ResidentHarbor / 静态TSCN / GroundSpace派生空间",
  "code_paths": [
    "godot/src/residence/resident_harbor.gd",
    "godot/scenes/residence",
    "godot/assets/data/npc/residences.json"
  ],
  "verification": []
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-RESIDENCE-R01 | 部分实现；独立目录/场景/API已见，GDD单向依赖已登记 | 不依赖NpcService；独立加载与正式结构检查待主线程 |
| SEA-RESIDENCE-R02 | 部分实现；7座独立TSCN共用shell与床/桌/灯，两座住商空间已见 | residence专项测50m²/家具/入口，真实渲染签署后才认定可用 |
| SEA-RESIDENCE-R03 | 历史部分实现；main曾新增resident_harbor参考实例，现按用户要求已撤下并暂停接入；源保留 | 旧参考(38,0,-32)不作为当前指令，正式天台无住所前置；住房手摆/接入验收deferred |
| SEA-RESIDENCE-R04 | 部分实现；7×5生活Marker映射及anchor_snapshot源码已见 | residences.json版本2是静态映射；35生活Marker有效性、坐标变换/旧锚点fallback待验 |
| SEA-RESIDENCE-R05 | 部分实现；Community可走面和GroundSpace派生路径已见 | 统一地面/家具阻挡/CharacterMotor物理路线/失支撑停止待npc-world+residence实测 |
| SEA-RESIDENCE-R06 | 设计已冻结；本轮无住所动态存档，不碰profile | 正式新zone位置、旧档迁移及跨进程save/integration待主线程接线验证 |
| SEA-RESIDENCE-R07 | 部分实现；独立测试/适配脚本已见，无本轮执行结论 | 本分支不跑sync/Godot/专项；结构/运行/视觉/设备各层待回填 |

## 资源与调用入口

- 资源：`godot/scenes/residence/resident_harbor.tscn`、`residence_shell.tscn`和7个独立residence场景；归属与节点映射：`godot/assets/data/npc/residences.json`。
- 空间服务：`godot/src/residence/resident_harbor.gd`；`anchor_snapshot()`与`refresh_space()`。GroundSpace按既有ZoneScene框架生成派生对象，不存第二份布局；NPC world只消费，不生成房屋。
- 测试源码：`godot/tests/test_residence.gd`；已有适配入口`godot/src/residence/verify_residence.py`只作路径线索，其内部residence/visual-residence映射不能当真实渲染已通过。本分支不执行、不改runner/registry。
- 静态TSCN为真；无residence存档副本，不复制npc状态或Inventory/Shop目录。资产生产登记与授权未在本分支核验。

## 验证记录与主线程回填占位

- 19:40历史证据限定：`D:/projects/sea-work/verification/20261107-192319-seven-npc-release-a6fb1b` 的release integration/save已PASS仅对应住所版历史，不代表住房全项签署，更不是当前天台版通过。下表住房专项待验因用户暂停转deferred，不在本轮补做或签退；主线程仅回填resident_harbor实例/zone binding移除与源资源保留结果，最新天台证据回填NPC-R13及施工记录第12节，现为pending。

| 证据层 | 待回填 | 当前结论 |
|---|---|---|
| 结构 | GDD依赖/链接/条款检查实际命令、版本、日志 | 仅只读候选依赖无环，不是正式结构专项 |
| 运行 | residence实际入口/命令/版本/退出码/断言与失败数/日志；7屋尺寸家具/35Marker/碰撞路径 | 未执行 |
| 集成存档 | Main新zone与泊位、NPC消费锚点、两商店、手摆变换、save/integration/跨进程 | 待主线程接线实测 |
| 视觉 | 真图形后端、截图路径与7屋/床桌灯/两商店/NPC路线审阅 | 待真实渲染，不用headless数量替代 |
| 设备与未验 | 设备/性能/输入与文件系统、未验条款和资产登记 | 未验 |

## 遗留与下一步

主线程负责正式Main接线、旧锚点兼容是否存在的核实、世界GroundSpace/CharacterMotor联测及全部实测证据回填。当前不宣称整套完成，不从并行隔离测试或旧日志推断当前工作树通过数，状态保持partial。

## 变更记录

- 2026-11-07 下午：在GDD先登记独立SEA-RESIDENCE后建立本spec/ledger，承接七正式50m²住所、家具、两商店、35生活Marker、静态TSCN真值与统一空间；仅文档更新，运行/视觉/设备未验。

## 2026-11-07 收尾：接入移除已完成，住房历史仍deferred

- Main中的resident_harbor实例及zones/scope绑定已移除，source（resident_harbor、shell、七屋TSCN、resident_harbor.gd及residences.json）保留，不删除R01–R07和原登记头JSON。历史R03“main已有实例”只描述暂停前制作，不是当前挂载事实。
- 七人全在既有rooftop_ranch的NpcStations35局部Marker，随用户手摆root变换，无物理住房，UI仅“暂驻天台”。不再把住房作为NPC/Shop前置，不移动用户root或其他旧transform。天台泊位调整只涉本轮局部Marker/boat，属于世界通行而非住房开发。
- 本轮天台通行772/0、rooftop655/0、water-layer1613/0三个专项均PASS；[对应报告](../../../../sea-work/verification/20261107-211124-rooftop-access-final-5ada04/report.json)中的landing-markers另有失败，不能签整批全绿，更不能计入住房完成。
- 最新性能及天台已验/未验分层见[性能修复记录](../../development/2026-11-07_npc_performance_fix.md)和[NPC账本](../resident/ledger.md)。全量天台integration/save/seed/restart/visual已按214439五项2277/0、exit0/PASS独立通过，14PNG已出、主线程三图目检、11图待审；本功能仍partial / deferred用户暂停，住房运行/视觉/设备不在本轮补做。

## 最终封存签署（非住房完成）

[天台最终报告](../../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/report.json)五项PASS、unexpected_errors空；[Shop输入](../../../../sea-work/verification/20261107-213213-shop-input-final-638cdf/report.json)259/0通过，仅支持当前NPC/Shop已实现，不支持SEA-RESIDENCE完成。七人初始位置均既有天台草地对应职业站点，非旧房屋/温室。历史source和R01–R07继续partial/deferred，Main无住房挂载，未恢复开发。原JSON与历史记录保留。
