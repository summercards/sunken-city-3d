# sea 游戏设计文档

**版本：** V1.0  
**文档状态：** 项目主文档 / 功能管理中控
**记录日期：** 2026-10-17；管理结构修订：2026-10-23
**项目类型：** 治愈系水上家园建造 × 轻度资源经营 × 航海探索

---

## 0. 主文档中控规则

本文是 sea 的唯一项目管理中枢。先在本页确定目标、全局规则和功能关系，再进入每个功能的独立文档与独立账本。Godot 为当前正式运行工程；根目录 Three.js 保留为原型、烘焙来源和对照，不作为第二份当前玩法主设计。

- 每个功能一个稳定 FeatureID、一份独立功能文档、一份独立功能账本；规划中的功能同样登记。
- 本文拥有全局目标、功能范围、依赖和阶段安排；功能文档拥有该功能细则；功能账本拥有实施状态与证据。
- 功能之间通过公开命令/查询/事件和稳定 ID 交接，资源与状态只有一个最终写入者。
- 新增功能先登记本页再建独立文件；修改功能先读其文档和账本，验证后回填账本并同步本页摘要。
- 本页状态摘要由 `python3 scripts/check_feature_contracts.py --sync` 从功能账本更新；禁止在两处手工维护不同进度。
- 第一版按完整行为闭环划分功能。例如种植含播种、浇水、生长、收获，各步骤有独立设计条款；后续若升级为独立功能，先在本页拆 FeatureID，再拆文件。
- 目标设计与当前实现分别保留；已有代码不能自动取代用户目标，旧完成度百分比不代表当前状态。

[功能导航](#feature-control) · [工程约定](docs/standards/工程管理规范.md) · [本次拆分记录](docs/development/2026-10-23_feature_split.md) · [拆分前完整主文档](docs/archive/pre_split_20261023/GDD_V1.0.md)

---

## 1. 核心幻想与产品定位

### 1.1 核心幻想

整个文明沉入水下，玩家却在废弃建筑的屋顶上，重新创造一个温暖、有生命力的小家园。

游戏最吸引人的并不是末日灾难本身，而是：

> 在被海水覆盖的旧世界上，逐步修复屋顶、种下植物、迎来居民，让破败的建筑重新变成有灯光、有收成、有来往船只的水上村落。

### 1.2 产品定位

- 节奏缓慢、没有强制战斗的休闲建造游戏。
- 以建造成就感、场景变化和探索发现为主要驱动力。
- 航海是解锁新景色、新材料和新建筑遗址的奖励，不应成为重复跑图负担。
- 玩家最终追求的不是单纯更高的数值，而是一个越来越繁荣、越来越有生活气息的水上世界。

### 1.3 三条长期成长线

1. **家园越来越繁荣：** 屋顶从废墟变成住宅、农场、工坊和聚落。
2. **船只越来越先进：** 从初始木船成长为可以前往远海、打捞材料和运输物资的船只。
3. **世界越来越广阔：** 从第一个屋顶群落出发，逐步发现更多沉没街区、建筑遗址和水下景观。

---

## 2. 核心玩法闭环

### 2.1 第一版核心循环

```text
发现废墟
  ↓
收集物资
  ↓
修建家园
  ↓
种植与生产
  ↓
收获资源
  ↓
扩大家园
  ↓
升级船只
  ↓
探索新的废墟
```

### 2.2 初始循环的调整原因

原始循环是：

```text
建房 → 收获 → 升级房屋 → 更多收获 → 升级船
```

这个循环能够推动数值增长，但缺少玩家主动探索、改变环境和持续建设的理由。第一版应把资源增长嵌入场景变化与区域解锁中，让每一次建造都带来“世界真的变了”的反馈。

### 2.3 三个设计原则

#### 原则一：每次建造都改变场景

建造不能只是房屋从 Lv.1 变成 Lv.2。升级后应至少发生一项可见变化：

- 屋顶出现植物、花盆或种植箱。
- 居民搬入，窗户亮起灯光。
- 邻近屋顶之间出现木桥、晾衣绳或小型码头。
- 破败建筑逐步扶正、补全或变成新的功能设施。
- 夜晚或阴影区域出现温暖灯光与生活细节。

#### 原则二：房屋、农场、船只互相依赖

- 房屋提供居民、仓储和工作能力。
- 农场生产食物、植物和交易物资。
- 船只带回木料、旧零件和特殊材料，并负责抵达新的废墟。
- 不能只依靠挂机收钱完成全部升级。

#### 原则三：航海是奖励，不是负担

- 新船只应解锁新景色、新资源、新建筑遗址。
- 常用区域之间应减少无意义的重复跑远路。
- 航海过程需要有风景、漂流物资和发现感，而不是纯粹等待进度条。
- 船只升级应自然地扩大玩家的生活范围。

---

## 3. 首个区域规划

### 3.1 区域尺度与整体构图

- 建议核心可玩区域约为 **45 × 40 米**。
- 保留现有工程中的太阳能木屋、水道、沉没铁道、远海沉没街町和周边水下建筑景观。
- 画面重点为：前景温暖家园、中景水道与航线、远景沉没建筑和水下巨鲸。
- 当前地图可继续扩展，但第一版应优先确保核心区域内的功能层次清晰。

### 3.2 五个建筑功能区

| 区域 | 功能 | 玩家获得 | 第一版状态 |
| --- | --- | --- | --- |
| A 太阳能木屋 | 住宅升级、居民、仓储 | 解锁更多种植位和工作能力 | 首局起点，优先实现 |
| B 圆弧屋顶农场 | 种植、浇水、收获蔬菜 | 持续获得农产品 | 首局核心功能 |
| C 绞盘打捞站 | 打捞漂流物和废料 | 木料、旧零件、修缮材料 | 首局核心功能 |
| D 水上码头 | 交易与改造小船 | 海贝、船只升级、远航许可 | 首局核心功能 |
| E 浅水养殖台 | 鱼类养殖和新材料 | 鱼类、特殊材料、后续建筑资源 | 第一版预留，后续扩展 |

### 3.3 第一版区域功能取舍

第一次游玩只需要 A、B、C、D 四个功能真正可用。E 只保留视觉预留或锁定入口，避免新玩家一开始面对过多系统。

当前工程中的横滨沉没铁道、天台种植园和太阳能木屋可继续作为第一版三个主要可玩点，但需要把它们与 A-D 的功能身份重新对齐，避免“场景名称”和“玩法功能”脱节。

---

## 4. 建筑与场景成长表现

详细设计已归入 [SEA-BUILD 功能文档](docs/features/build/spec.md)，实施状态见 [独立账本](docs/features/build/ledger.md)。原始设计全文已保留，历史网页数值不作为当前 Godot 数值。

---

## 5. 资源与数值

详细设计已归入 [SEA-INVENTORY 功能文档](docs/features/inventory/spec.md)，实施状态见 [独立账本](docs/features/inventory/ledger.md)。原始设计全文已保留，历史网页数值不作为当前 Godot 数值。

---

## 6. 前 20 分钟体验目标

这些时间是体验节奏目标，不是强制倒计时。

### 0–3 分钟：修复第一块屋顶

- 玩家乘船抵达圆弧楼或在太阳能木屋醒来。
- 使用初始木料修好两格农田。
- 看到第一批种子和建筑部件在场景中出现。
- 通过一次明确的视觉变化理解“建造会改变世界”。

### 3–7 分钟：第一次种植与收获

- 作物逐渐生长。
- 玩家去旁边绞盘站打捞旧零件。
- 第一次收获获得农产品或海贝。
- 玩家知道资源需要主动收取和分配，而非只等待数字自动增长。

### 7–12 分钟：升级自己的木屋

- 出售作物获取海贝。
- 修缮住宅，增加居民或屋顶种植位。
- 屋顶出现植物、窗灯和生活道具。
- 玩家第一次感受到“家园开始有人住”。

### 12–20 分钟：升级船只并准备远航

- 完成第二轮收获和材料收集。
- 在水上码头改造木船。
- 木船变成可驶往远海的帆船或改良船。
- 航行至远海沉没街町，看到下一座屋顶等待建设。
- 首局在“下一座屋顶可以建成什么样”的期待中结束。

---

## 7. 航海成长与探索

详细设计已归入 [SEA-SHIP 功能文档](docs/features/ship/spec.md)，实施状态见 [独立账本](docs/features/ship/ledger.md)。原始设计全文已保留，历史网页数值不作为当前 Godot 数值。

---

## 8. 交互与用户体验

### 8.1 交互原则

- 主要操作应保持简单，优先使用场景中的建筑、船只和角色作为入口。
- 建筑悬停只在鼠标指向模型时出现，避免常驻 UI 遮挡画面。
- 资源收取和升级使用统一的建筑操作点，但收取优先于升级。
- 航行入口可以来自角色行动环、船只或码头。
- 右键或手动镜头操作应明确接管自动跟随，避免镜头和玩家意图冲突。

### 8.2 反馈要求

- 资源收取：显示短暂浮动数值，并让顶部海贝数字产生轻微反馈。
- 升级中：显示简短进度，不打断观察场景。
- 升级完成：建筑模型、植物、灯光或居民立即发生变化。
- 不可用状态：说明缺少什么，而不是只显示无响应的按钮。
- 满级状态：给出后续解锁或“等待新区域”的方向。

---

## 9. 开发优先级

### P0：完成首个 20 分钟垂直切片

1. 统一 A-D 四个功能区的命名、入口和玩法职责。
2. 保留现有 Three.js 场景和三处可玩建筑，补齐木屋、农场、打捞站、码头之间的依赖关系。
3. 将船只升级做成可见、可操作、能解锁远海区域的系统。
4. 完成从第一次种植到驶向远海街町的首局流程。
5. 为首局流程增加明确的新手引导、目标提示或轻量任务。

### P1：补齐资源经营基础

1. 增加木料、旧零件、农产品等基础物资。
2. 增加仓储和简单交易。
3. 让打捞站成为资源来源，而不是仅有视觉装饰。
4. 让码头消耗基础材料完成船只升级。

### P2：扩展世界与生活感

1. 开放第五功能区浅水养殖台。
2. 增加居民、生活动画和聚落关系。
3. 增加更多屋顶之间的桥、船、灯和生活设施。
4. 增加存档、读档和跨刷新状态恢复。

### P3：产品化与长期内容

1. 增加任务、成就和区域复兴目标。
2. 增加更多沉没街区和深海探索内容。
3. 完善性能、兼容性和视觉回归测试。
4. 根据玩家节奏调整产出、建造成本和船只成长曲线。

---


<a id="feature-control"></a>
## 10. 功能管理与导航

下表逐行定义功能范围与前置关系；依赖是契约/数据交接，不代表允许读取对方内部字段。模块可承载多个功能，所有功能都必须独立有文档、有账本。状态摘要来源为各功能账本；`部分实现` 包括已具备行为但目标、解耦或验收尚未全部闭环。

<!-- FEATURE_CONTROL_BEGIN -->
| FeatureID | 功能 | 所属系统 | 前置功能 | 独立文档 | 独立账本 | 状态摘要 |
|---|---|---|---|---|---|---|
| <a id="sea-boot"></a>SEA-BOOT | 启动与会话装配 | 基础 | — | [文档](docs/features/boot/spec.md) | [账本](docs/features/boot/ledger.md) | 部分实现 |
| <a id="sea-world"></a>SEA-WORLD | 区块与世界装配 | 世界 | SEA-BOOT | [文档](docs/features/world/spec.md) | [账本](docs/features/world/ledger.md) | 部分实现 |
| <a id="sea-move"></a>SEA-MOVE | 角色移动与上下船 | 3C | SEA-WORLD | [文档](docs/features/move/spec.md) | [账本](docs/features/move/ledger.md) | 部分实现 |
| <a id="sea-nav"></a>SEA-NAV | 航行与靠泊 | 3C | SEA-WORLD, SEA-MOVE | [文档](docs/features/nav/spec.md) | [账本](docs/features/nav/ledger.md) | 部分实现 |
| <a id="sea-camera"></a>SEA-CAMERA | 相机跟随与手动控制 | 3C | SEA-MOVE | [文档](docs/features/camera/spec.md) | [账本](docs/features/camera/ledger.md) | 部分实现 |
| <a id="sea-interact"></a>SEA-INTERACT | 点击与长按交互 | 交互 | SEA-MOVE | [文档](docs/features/interact/spec.md) | [账本](docs/features/interact/ledger.md) | 部分实现 |
| <a id="sea-gather"></a>SEA-GATHER | 岸边采集 | 资源 | SEA-INTERACT, SEA-INVENTORY | [文档](docs/features/gather/spec.md) | [账本](docs/features/gather/ledger.md) | 部分实现 |
| <a id="sea-inventory"></a>SEA-INVENTORY | 资源与背包 | 经营 | — | [文档](docs/features/inventory/spec.md) | [账本](docs/features/inventory/ledger.md) | 部分实现 |
| <a id="sea-warehouse"></a>SEA-WAREHOUSE | 材料仓储 | 经营 | SEA-INVENTORY, SEA-FACILITY | [文档](docs/features/warehouse/spec.md) | [账本](docs/features/warehouse/ledger.md) | 部分实现 |
| <a id="sea-build"></a>SEA-BUILD | 建筑修缮与升级 | 经营 | SEA-INVENTORY, SEA-INTERACT | [文档](docs/features/build/spec.md) | [账本](docs/features/build/ledger.md) | 部分实现 |
| <a id="sea-facility"></a>SEA-FACILITY | 设施解锁与生产 | 经营 | SEA-BUILD, SEA-INVENTORY | [文档](docs/features/facility/spec.md) | [账本](docs/features/facility/ledger.md) | 部分实现 |
| <a id="sea-ship"></a>SEA-SHIP | 船只升级与区域解锁 | 成长 | SEA-INVENTORY, SEA-BUILD | [文档](docs/features/ship/spec.md) | [账本](docs/features/ship/ledger.md) | 部分实现 |
| <a id="sea-farm"></a>SEA-FARM | 种植与日常照料 | 经营 | SEA-INVENTORY, SEA-FACILITY, SEA-WORLD | [文档](docs/features/farm/spec.md) | [账本](docs/features/farm/ledger.md) | 部分实现 |
| <a id="sea-salvage"></a>SEA-SALVAGE | 绞盘打捞 | 探索 | SEA-INTERACT, SEA-INVENTORY | [文档](docs/features/salvage/spec.md) | [账本](docs/features/salvage/ledger.md) | 部分实现 |
| <a id="sea-dive"></a>SEA-DIVE | 潜水探索与宝箱 | 探索 | SEA-WORLD, SEA-INVENTORY | [文档](docs/features/dive/spec.md) | [账本](docs/features/dive/ledger.md) | 部分实现 |
| <a id="sea-pickup"></a>SEA-PICKUP | 海面漂流物与鱼群收取 | 探索 | SEA-NAV, SEA-INVENTORY | [文档](docs/features/pickup/spec.md) | [账本](docs/features/pickup/ledger.md) | 部分实现 |
| <a id="sea-order"></a>SEA-ORDER | 交易与订单 | 经营 | SEA-INVENTORY, SEA-BUILD, SEA-SHIP | [文档](docs/features/order/spec.md) | [账本](docs/features/order/ledger.md) | 部分实现 |
| <a id="sea-goal"></a>SEA-GOAL | 小目标追踪与引导 | 成长 | SEA-BUILD, SEA-SHIP | [文档](docs/features/goal/spec.md) | [账本](docs/features/goal/ledger.md) | 部分实现 |
| <a id="sea-resident"></a>SEA-RESIDENT | 居民与生活行为 | 生活 | SEA-WORLD, SEA-BUILD | [文档](docs/features/resident/spec.md) | [账本](docs/features/resident/ledger.md) | 规划中 |
| <a id="sea-time"></a>SEA-TIME | 天气与世界时间 | 生活 | SEA-WORLD | [文档](docs/features/time/spec.md) | [账本](docs/features/time/ledger.md) | 规划中 |
| <a id="sea-aqua"></a>SEA-AQUA | 浅水养殖 | 经营 | SEA-WORLD, SEA-INVENTORY | [文档](docs/features/aqua/spec.md) | [账本](docs/features/aqua/ledger.md) | 规划中 |
| <a id="sea-quest"></a>SEA-QUEST | 任务成就与区域复兴 | 成长 | SEA-GOAL, SEA-WORLD | [文档](docs/features/quest/spec.md) | [账本](docs/features/quest/ledger.md) | 规划中 |
| <a id="sea-ui"></a>SEA-UI | HUD 与菜单反馈 | 表现 | SEA-INTERACT, SEA-INVENTORY | [文档](docs/features/ui/spec.md) | [账本](docs/features/ui/ledger.md) | 部分实现 |
| <a id="sea-ocean"></a>SEA-OCEAN | 水面与光照渲染 | 表现 | SEA-WORLD | [文档](docs/features/ocean/spec.md) | [账本](docs/features/ocean/ledger.md) | 部分实现 |
| <a id="sea-ambient"></a>SEA-AMBIENT | 环境植物与生活表现 | 表现 | SEA-WORLD | [文档](docs/features/ambient/spec.md) | [账本](docs/features/ambient/ledger.md) | 部分实现 |
| <a id="sea-save"></a>SEA-SAVE | 存档与恢复 | 基础 | SEA-BOOT, SEA-INVENTORY | [文档](docs/features/save/spec.md) | [账本](docs/features/save/ledger.md) | 部分实现 |
| <a id="sea-sfx"></a>SEA-SFX | 环境与交互音效 | 表现 | SEA-INTERACT | [文档](docs/features/sfx/spec.md) | [账本](docs/features/sfx/ledger.md) | 规划中 |
| <a id="sea-music"></a>SEA-MUSIC | 场景音乐 | 表现 | SEA-BOOT, SEA-WORLD | [文档](docs/features/music/spec.md) | [账本](docs/features/music/ledger.md) | 规划中 |
| <a id="sea-asset"></a>SEA-ASSET | 美术组件生产与登记 | 生产 | — | [文档](docs/features/asset/spec.md) | [账本](docs/features/asset/ledger.md) | 部分实现 |
| <a id="sea-quality"></a>SEA-QUALITY | 验证与性能治理 | 工程 | SEA-BOOT | [文档](docs/features/quality/spec.md) | [账本](docs/features/quality/ledger.md) | 部分实现 |
| <a id="sea-release"></a>SEA-RELEASE | 导出与发行 | 工程 | SEA-QUALITY | [文档](docs/features/release/spec.md) | [账本](docs/features/release/ledger.md) | 部分实现 |
<!-- FEATURE_CONTROL_END -->

## 11. 跨功能交接与推进顺序

经营主链：采集/打捞/种植 → 背包 → 订单或出售 → 仓储与建造 → 设施和船升级 → 更多种植空间与探索。UI 发送命令、显示结果；存档收集各所有者快照。资源写入由库存所有者执行，业务模块负责本功能状态。

工程推进顺序：文档与账本闭环 → 功能目录和接口 → 独立专项 → 正式游戏集成 → 真实表现 → 发行验证。每个阶段的事实与缺口在对应功能账本登记，不用总完成度百分比代替证据。

- [资产总索引与分账本](assets/registry/README.md)支撑各功能，不取代独立功能账本。
- [结构门禁与运行验收](docs/standards/工程管理规范.md)是持续维护入口。
- [历史开发计划](docs/archive/pre_split_20261023/开发计划_V1.0.md)和[历史功能计划](docs/archive/pre_split_20261023/功能重做计划.md)保留未完成设计与原始依据，当前调度以本页及独立功能文件为准。
