# 功能、架构、存档与 3C 审计（2026-10-26）

## 结论与范围

正式对象为 `godot/`；`web/` 为历史原型，不作为正式功能通过的证据。本次检查文档、代码与隔离运行，未修改玩法实现。工作区在审计前已有未提交修改，审计期间其他修改仍在发生；以下运行结果绑定各自 runner 的副本与 report.json，不代表之后的任意工作区版本。

- 有唯一主文档：[GDD_V1.0.md](../../GDD_V1.0.md)。31 项功能全部各有独立 spec.md 和 ledger.md，条款 ID 与账本承接、文件路径及状态投影未报告问题。
- 登记状态为 25 项 partial、6 项 planned、0 项 verified；这是实施状态，不是完成率。
- 有按职责组织的代码和接口，但未达到每个功能都能独立替换、独立运行、独立维护。Main、Economy 和 UnderwaterWorld 仍承载多个职责。
- 存档正常往返有测试保障，但有可复现的旧档覆盖及异常数据清空风险，不能判为健康。
- 3C（角色 Character、相机 Camera、控制 Control）具备基础行为和专项证据，整体尚未完善，真实交互和集成门禁仍有失败。

## 完整功能清单

以下每项都有独立文档及独立账本。代码路径来自账本登记，表示有入口，不代表全部规则已独立；细则与遗留应继续以对应文件为准。

| FeatureID | 功能 | 状态 | 独立文档 / 账本 | 代码入口 |
|---|---|---|---|---|
| SEA-BOOT | 启动与会话装配 | 部分实现 | [文档](../features/boot/spec.md) / [账本](../features/boot/ledger.md) | `src/bootstrap`、`godot/project.godot`、`godot/scenes/main.tscn` |
| SEA-WORLD | 区块与世界装配 | 部分实现 | [文档](../features/world/spec.md) / [账本](../features/world/ledger.md) | `src/world`、`godot/scenes/zones`、`godot/scenes/world`、`godot/assets/data/zones.json` |
| SEA-MOVE | 角色移动与上下船 | 部分实现 | [文档](../features/move/spec.md) / [账本](../features/move/ledger.md) | `src/player`、`src/navigation/walk_area.gd`、`src/navigation/ground_path.gd`、`src/navigation/landing_point.gd` |
| SEA-NAV | 航行与靠泊 | 部分实现 | [文档](../features/nav/spec.md) / [账本](../features/nav/ledger.md) | `src/navigation/boat.gd`、`src/navigation/route_ribbon.gd` |
| SEA-CAMERA | 相机跟随与手动控制 | 部分实现 | [文档](../features/camera/spec.md) / [账本](../features/camera/ledger.md) | `src/camera` |
| SEA-INTERACT | 点击与长按交互 | 部分实现 | [文档](../features/interact/spec.md) / [账本](../features/interact/ledger.md) | `src/interaction` |
| SEA-GATHER | 岸边采集 | 部分实现 | [文档](../features/gather/spec.md) / [账本](../features/gather/ledger.md) | `src/gathering`、`godot/assets/data/gather_spots.json` |
| SEA-INVENTORY | 资源与背包 | 部分实现 | [文档](../features/inventory/spec.md) / [账本](../features/inventory/ledger.md) | `src/inventory`、`godot/assets/data/items.json` |
| SEA-WAREHOUSE | 材料仓储 | 部分实现 | [文档](../features/warehouse/spec.md) / [账本](../features/warehouse/ledger.md) | `src/economy/economy.gd` |
| SEA-BUILD | 建筑修缮与升级 | 部分实现 | [文档](../features/build/spec.md) / [账本](../features/build/ledger.md) | `src/construction` |
| SEA-FACILITY | 设施解锁与生产 | 部分实现 | [文档](../features/facility/spec.md) / [账本](../features/facility/ledger.md) | `src/economy/economy.gd` |
| SEA-SHIP | 船只升级与区域解锁 | 部分实现 | [文档](../features/ship/spec.md) / [账本](../features/ship/ledger.md) | `src/economy/economy.gd`、`src/navigation/boat.gd` |
| SEA-FARM | 种植与日常照料 | 部分实现 | [文档](../features/farm/spec.md) / [账本](../features/farm/ledger.md) | `src/farming`、`godot/assets/data/crops.json`、`godot/scenes/props/farm_plot.tscn`、`godot/scenes/props/farm_cell.tscn` |
| SEA-SALVAGE | 绞盘打捞 | 部分实现 | [文档](../features/salvage/spec.md) / [账本](../features/salvage/ledger.md) | `src/salvage` |
| SEA-DIVE | 潜水探索与宝箱 | 部分实现 | [文档](../features/dive/spec.md) / [账本](../features/dive/ledger.md) | `src/diving`、`godot/scenes/underwater` |
| SEA-PICKUP | 海面漂流物与鱼群收取 | 部分实现 | [文档](../features/pickup/spec.md) / [账本](../features/pickup/ledger.md) | `src/pickups` |
| SEA-ORDER | 交易与订单 | 部分实现 | [文档](../features/order/spec.md) / [账本](../features/order/ledger.md) | `src/orders`、`godot/assets/data/orders.json`、`godot/assets/data/trade_board.json` |
| SEA-GOAL | 小目标追踪与引导 | 部分实现 | [文档](../features/goal/spec.md) / [账本](../features/goal/ledger.md) | `src/economy/economy.gd`、`src/ui/hud.gd` |
| SEA-RESIDENT | 居民与生活行为 | 规划中 | [文档](../features/resident/spec.md) / [账本](../features/resident/ledger.md) | 无正式实现 |
| SEA-TIME | 天气与世界时间 | 规划中 | [文档](../features/time/spec.md) / [账本](../features/time/ledger.md) | 无正式实现 |
| SEA-AQUA | 浅水养殖 | 规划中 | [文档](../features/aqua/spec.md) / [账本](../features/aqua/ledger.md) | 无正式实现 |
| SEA-QUEST | 任务成就与区域复兴 | 规划中 | [文档](../features/quest/spec.md) / [账本](../features/quest/ledger.md) | 无正式实现 |
| SEA-UI | HUD 与菜单反馈 | 部分实现 | [文档](../features/ui/spec.md) / [账本](../features/ui/ledger.md) | `src/ui` |
| SEA-OCEAN | 水面与光照渲染 | 部分实现 | [文档](../features/ocean/spec.md) / [账本](../features/ocean/ledger.md) | `src/rendering`、`godot/shaders`、`godot/assets/materials` |
| SEA-AMBIENT | 环境植物与生活表现 | 部分实现 | [文档](../features/ambient/spec.md) / [账本](../features/ambient/ledger.md) | `src/ambient`、`godot/scenes/plants` |
| SEA-SAVE | 存档与恢复 | 部分实现 | [文档](../features/save/spec.md) / [账本](../features/save/ledger.md) | `src/save` |
| SEA-SFX | 环境与交互音效 | 规划中 | [文档](../features/sfx/spec.md) / [账本](../features/sfx/ledger.md) | 无正式实现 |
| SEA-MUSIC | 场景音乐 | 规划中 | [文档](../features/music/spec.md) / [账本](../features/music/ledger.md) | 无正式实现 |
| SEA-ASSET | 美术组件生产与登记 | 部分实现 | [文档](../features/asset/spec.md) / [账本](../features/asset/ledger.md) | `art_source`、`assets/registry`、`tools/blender` |
| SEA-QUALITY | 验证与性能治理 | 部分实现 | [文档](../features/quality/spec.md) / [账本](../features/quality/ledger.md) | `scripts`、`godot/tests`、`tests` |
| SEA-RELEASE | 导出与发行 | 部分实现 | [文档](../features/release/spec.md) / [账本](../features/release/ledger.md) | `godot/export_presets.cfg`、`godot/tools/make_web_dist.py` |

## 代码维护边界与数据接口

1. 种植、订单是较好的边界样本：`farming/farm.gd`、`orders/orders.gd` 使用 `configure(ports)` 注入库存、支付、奖励、设施和进度查询；通过 planted/watered/harvested/changed/fulfilled 等信号通知外部。当前独立模块测试在没有 Main、Economy、GameState、Zones Autoload 的情况下运行 28 项通过，覆盖种植、订单及氧气/打捞的部分规则。
2. 库存数量由 `inventory/inventory.gd` 管理，提供 count/add/remove/pay/to_dict/from_dict 等接口；物品、作物、订单等静态配置有 JSON。游戏需要的是明确的数据所有权与契约，不要求另建数据库服务器。
3. `economy/economy.gd`（审计快照 555 行）仍合并仓储、建造进度、设施、船升级、小目标、打捞结算和经营模型装配。construction 有独立表现/交互文件，不表示建造状态已独立。warehouse、facility、goal 尤其缺独立业务服务。
4. `bootstrap/main.gd`（2048 行）仍处理输入、岸上行走、自动接近、航路、上下船、模式切换、UI反馈与存读档。`player/character.gd` 主要是程序化角色表现及动画，不是完整独立角色控制器。
5. `diving/underwater_world.gd`（974 行）合并游动、相机、宝箱、状态和表现；`ui/hud.gd`（672 行）及其他表现仍有业务内部字段读取。
6. `save/save_game.gd` 直接调用 Main 的 `_sync_zone_levels`，操作 `_walk_path/_after_walk/_walking`，刷新 HUD 私有方法，并写 GameState 字段；存档接口存在，但模块恢复契约未闭合。
7. 6 项 planned 的 code_paths 为空，独立功能实现尚不存在；环境小鸟/植物不是居民系统，鱼群收取不是养殖，种植天数不是统一世界时间，小目标不是完整任务成就。

## 存档问题与复现

### P1：默认重新启动可让自动存档覆盖旧进度

`main.gd:123` 的启动流程仅在显式 `--load` 参数时调用读档；默认 `_autosave_on=true`，120 秒定时保存仍开启（`main.gd:45`、`:111`、`:1925`）。UI 有手动读取入口，但没有启动时先恢复/选择继续、再允许覆盖当前槽的门禁。

通过同一个 runner 隔离用户目录的两个独立 Godot 进程复现：第一个进程保存 98,765 海贝到默认槽；第二个无 `--load` 启动，磁盘还是 98,765，内存为 80，自动存档开启；将计时器置零并调用真实 `_process(0.01)`，磁盘变成 80。此处加速了计时器，没有人工替换保存逻辑。风险是未先手动读档的普通重启覆盖既有进度。

### P1：合法 JSON 的空数据及异常嵌套数据缺少校验

`SaveGame.decode("{}")` 返回 ok=true、migrated=true；`restore` 返回 ok=true，并将预先设为 12,345 的海贝清为 0。原因是无版本对象全部按 v0 迁移，未要求旧格式必须含已知有效字段；迁移后空 economy 仍被接受。

附加复现：ship_level=-9、capacity=-4、unknown_site=99 被接受，from_dict 后仍保留这些值；inventory 为字符串也通过 decode（未继续恢复错误类型，避免用脚本异常混淆观测）。`Economy.from_dict` 对建筑/设施/施工键未统一过滤、船级未校验范围。应在任何状态写入前做完整类型、范围、ID 与一致性验证，并保障失败不修改当前局面。

### 已有保障与尚未验证

本轮 selftest 的 [save] 子段 24 项全部通过，包括临时文件读回后替换、正常恢复、相对冷却、旧版本迁移、未来版本拒绝、坏 JSON 拒绝、镜头恢复。潜水与打捞中禁止存档在 Main 有显式检查。库存未知物品 ID、种植和订单快照有各自容错/往返机制，但不能推导为所有内容 ID 都安全。

未发现轮换备份/上一份有效快照恢复机制；未进行断电、磁盘满/权限、Web 浏览器持久化、玩家真实槽位健康扫描。跨进程测试仅覆盖上述复现，不等于完整跨进程进度回归。对被破坏的数据缺少备份恢复保障，不能把“使用 rename”视为所有故障下安全。

## 3C 结论

| 部分 | 当前能力 | 缺口 / 证据限制 |
|---|---|---|
| 角色 | 岸上寻路、泊位上下船、待机/行走/划船/种植动作、潜水装备与游动 | 表现和控制分散；岸上状态在 Main，潜水控制在 UnderwaterWorld；未形成独立统一控制器 |
| 相机 | 自动跟随、手动接管、恢复跟随、平移/旋转/缩放边界、阻尼；水下有独立镜头 | camera 8 项通过，含 30/60/120 FPS 阻尼；覆盖有限，未做完整分辨率与设备手感验收、全场景遮挡检查 |
| 控制 | 点击地面/水面/目标、自动接近、长按、取消、模态 UI 隔离、潜水操作 | click 30 项通过，但真实鼠标脚本 5 项失败；主要键鼠硬编码，未发现完整可重绑输入配置及原生触控/手柄契约 |
| 航行 | 加减速、转向限速、靠泊、障碍检查、目标替换 | surface 正式运行 30 条有向航路、503 项通过；selftest 的几何判定另有冲突，须按当前场景核对，不得只选绿测试 |

本游戏是点击式休闲建造/航海玩法，不能因没有跳跃、冲刺或战斗就判定 3C 缺失。这里的不完善指现有目标的实现边界、真实事件与验收闭环仍不足。

## 本轮验证

工具：Godot 4.7.2，`I:/下载/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`；Python 设置 `PYTHONUTF8=1`。所有 Godot 执行均经过 `scripts/run_verification.py` 建立隔离工程及用户目录，不触及玩家槽位。

| 检查 | 结果 | 退出码 |
|---|---|---|
| modules | 28 项，0 失败 | 0 |
| surface | 30 条航路、503 项，0 失败 | 0 |
| click | 30 项，0 失败 | 0 |
| camera | 8 项，0 失败 | 0 |
| management | 36 项，0 失败 | 0 |
| selftest | 530 通过、7 失败；其中 save 子段 24 通过 | 1 |
| visual-click（真实 Forward+） | 5 失败 | 1 |
| visual-management（真实 Forward+） | 2 项、2 失败 | 1 |
| 存档三阶段观测 | 旧档覆盖与异常数据接受已复现；PASS 仅代表观测执行完成，不代表存档健康 | 三阶段均 0 |

selftest 失败：背包页格子容器、zone1 共享材质假设、岛心障碍、泊位两两路线（4 条异常）、绕行长度、岛心水面判定、订单板可行走区域。背包和材质断言带旧结构假设，路线断言与 surface 使用的几何判据不一致；本轮保留失败，不将其全部宣判为真实穿模，也不因专项通过自动豁免。订单板坐标为 (-9.5, 1.33, 14.1)，应按当前可行走面核对可达性。

visual-click 失败：工具栏直达种植、视角面板、鼠标保存、第二地格选中、退出打捞。visual-management 找不到“材料一键入库”按钮并导致操作失败。脚本含旧 UI 入口假设，需更新契约并通过真实事件重新验收，不可直接删断言放绿。

唯一允许的预期诊断为 selftest 故意坏 JSON 的 `ERROR: Parse JSON failed. Error at line 0: Expected key`；runner 单独计数。本轮运行不含 farming/ocean/parity 全集、独立 UI 120 项、手柄/触控/Web/移动实机、长期帧率性能或人工全流程手感验收。

证据（工程外）：

- `D:/projects/sea-work/verification/20261026-235150-feature-save-3c-audit-63e689/report.json`：首轮逻辑/集成副本、命令、日志、工作区快照。
- `D:/projects/sea-work/verification/20261026-235233-audit-real-input-6bbf98/report.json`：真实渲染与事件日志、截图保存在隔离工程 outputs。执行了真实渲染，但本次未将截图作人工画面验收结论。
- `D:/projects/sea-work/verification/20261026-235503-save-risk-reproduction-948811/report.json`：最终存档观测，复用首轮已复制的 src/scenes/tests/tools/shaders，避免并发编辑影响代码。assets 仍遵循 runner 共享输入机制，并非整个工程不可变快照。
- `D:/projects/sea-work/audit-20261026/run_save_audit.py`：通过导入统一 runner、注入临时测试到隔离工程执行，正式源未新增测试或变更。执行环境设定同上。观测脚本有意打印实际值，不以绿色退出表示产品健康。

过程失败也保留：首次探针在顶层 preload 依赖 Autoload 的 SaveGame 导致编译错误，运行被停止；第二次探针遇到工作区并发编辑中的 shader `cp` 未定义及 sunny_bloom_visual 类型推断错误，runner 即使进程退出 0 仍判失败。最终改为运行期 load 并复用首轮代码副本，三个观测均无非预期错误。中间日志位于 `20261026-235331-save-risk-reproduction-096306` 和 `20261026-235427-save-risk-reproduction-214d94`，不作最终通过证据。

## 推进优先级

1. 先修默认启动与自动存档覆盖保护、异常存档校验与失败不改状态；补充跨进程重启、空对象、坏类型/范围、备份恢复专项。
2. 对照当前场景和 UI 核对 selftest/真实输入失败，修正过时契约并修复真实可达性或输入问题；需要通过当前真实事件测试。
3. 拆出角色移动/交互协调器，以及仓储、建造、设施、船成长、目标服务；让 SaveGame 只消费快照/恢复接口，逐项扩大无主场景测试。
4. 最后补首个 20 分钟真人闭环、目标设备与 3C 手感验收；六个规划功能按产品优先级推进。

结构门禁初查发现 `godot/assets/data/zones.json` 登记哈希漂移（31 features、380 source assets、316 runtime hashes、1 issue）。未通过批量更新哈希掩盖来源。交付时按要求再次执行 `--sync` 与无参数检查，最终结果见下方补记。

交付补记：`--sync` 与随后无参数检查均报告 3 个哈希漂移：`godot/assets/data/trade_board.json`、`godot/assets/data/zones.json`、`godot/assets/materials/water.tres`；无参数检查退出 1。相比初查新增两项，发生在并发工作区修改期间。同步器仅在无问题时写投影，本轮因门禁失败未重写摘要；31 项原状态未更改，文档/账本结构未报告缺失或不一致。原始同步日志保存在工程外 `audit-20261026/structure-sync.log`。
