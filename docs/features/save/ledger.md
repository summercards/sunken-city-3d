# SEA-SAVE · 存档与恢复 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-save) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-SAVE",
  "status": "partial",
  "owner": "SaveGame / SnapshotRegistry / 各模块快照",
  "code_paths": [
    "godot/src/save"
  ],
  "verification": [
    "selftest",
    "management",
    "framework-modules",
    "framework-integration",
    "save-protection",
    "building-save-compat",
    "visual-building-save-compat",
    "minimum-loop",
    "visual-plot-shipping",
    "sleep-cycle",
    "wood-bundles",
    "save-reset",
    "visual-save-reset",
    "fishery-environment",
    "visual-fishery-environment"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-SAVE-R01 | tmp读回、有效备份、旧版迁移/未来版保护；跨进程专项通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-SAVE-R02 | 全量模块恢复/相对冷却，旧内容按所属模块过滤；selftest与拾取恢复通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-SAVE-R03 | 潜水/收线拒绝中途档；Autoload前隔离，selftest/runner通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-SAVE-R04 | SaveGame只访问注册表；恢复与UI刷新经公开适配接口 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-SAVE-R05 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |
| SEA-SAVE-R06 | 已实现并专项核验 | [边界补强记录](../../development/2026-10-27_framework_boundary_hardening.md) |
| SEA-SAVE-R07 | 本轮实现；正式最小范围与独立专项验证 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |
| SEA-SAVE-R08 | 已实现，场景点击与存读专项验证 | [本轮证据](../../development/2026-10-27_plot_shipping_loop.md) |

## 2026-10-30 海域日历与冷却存读

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-SAVE-R11 | 已实现；v4可选ocean扩展，远处资源/截止时间磁盘往返、旧缺失数量迁移、负冷却和坏槽位恢复前拒绝 | `ocean-pickups`43项通过；[本轮交付](../../development/2026-10-30_ocean_pickups.md) |

## 2026-11-02 浮木数量存读

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-SAVE-R12 | 已实现并本轮专项通过：v4／ocean版本1可选wood_amount、harvested、wood_yields；旧束按3并保留回访，含无ocean旧档；校验范围空档/类型/槽位/缓存冲突且恢复前拒绝，磁盘恢复规范化未加载槽位的整数缓存 | `wood-bundles`33项、`wood-density`16项、`ocean-pickups`48项0失败；[交付](../../development/2026-11-02_wood_bundles.md) |

## 资源与调用入口

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-SAVE-R13 | 已实现；旧档布局坐标和作物保留，新贴边木板显式坐标经正式SaveGame磁盘往返；布尔标记与有限数值严格校验 | [兼容修复与实测](../../development/2026-11-02_building_save_compatibility.md) |

- [godot/src/save](../../../godot/src/save)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

encode / write / read / decode / restore；SnapshotRegistry.register / capture / validate / restore / clear；restored；ok/reason/recovered/future 结果。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

当前入口：`python3 scripts/run_verification.py selftest management framework-modules framework-integration save-protection`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 selftest、management 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

SaveGame 仅依赖 host.save_registry；版本2全模块先验证后恢复，启动读默认档，损坏回退上个有效备份，未来版本保护不覆盖。真实断电、磁盘故障及发行平台文件系统尚未实测。

## 变更记录

SEA-SAVE-R08初始六格修订：首次快照显式包含六格，旧单格档补齐空格且保留作物字段；玩家档只读副本通过正式decode/restore后逐格可达、接近并取消，固定及DIY作物记录不变。schema/version/恢复顺序不改，未写入玩家档。[实测](../../development/2026-10-29_initial_six_planters.md)。

2026-10-29 SEA-SAVE-R08：只在世界姿态适配层改为按XYZ选层吸附，SaveGame/SnapshotRegistry及存档格式未改。动态建造恢复、坏档/跨进程专项见[本轮交付](../../development/2026-10-29_character_physics_framework.md)。

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 2026-10-26 功能与健康审计

SEA-SAVE-R01/R02/R03/R04：selftest 存档子段24项通过，但隔离跨进程复现默认重启未读档、自动存档将98765瓶盖覆盖为80；空JSON被迁移接受，恢复将12345瓶盖清零；负船级/负容量/未知建筑键被接受。恢复仍访问Main/HUD私有字段。列为P1修复项，不能判健康；最终观测退出0仅表示复现完成。

[本轮审计与证据](../../development/2026-10-26_feature_architecture_save_3c_audit.md)。本轮只审计和登记，未修改玩法实现。

## 2026-10-27 模块框架落地

SaveGame 仅依赖 host.save_registry；版本2全模块先验证后恢复，启动读默认档，损坏回退上个有效备份，未来版本保护不覆盖。真实断电、磁盘故障及发行平台文件系统尚未实测。

新增条款 SEA-SAVE-R05 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。

## 2026-10-27 查询与恢复边界补强

SnapshotRegistry.event_sources、is_restoring 与 restored；结构/语义坏档、未来备份、事件观察一致性与重入存盘专项通过。

[本轮实测记录](../../development/2026-10-27_framework_boundary_hardening.md)。

## 2026-10-27 当前最小循环与开始画面

本节及本轮修改条款优先于下方保留的历史范围。默认发布配置只开放家园生活循环；旧全功能验证须显式 `--full-world`，不能代替最小版本验收。接口、迁移及实测见[交付记录](../../development/2026-10-27_minimum_loop_and_title.md)。

2026-10-27 场景点击循环：07:00收货、瓶盖、木土种植格及码头出货箱；[本轮记录](../../development/2026-10-27_plot_shipping_loop.md)。

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-SAVE-R09 | 已实现，写盘与往返验证 | [本轮实测](../../development/2026-10-28_sleep_cycle_delivery.md) |

## 2026-10-28 开始界面时间连续性

开始背景改为读取已恢复的同一WorldClock时刻，不修改存档格式、时间字段或07:00晨次。开始期间继续冻结时钟，入场后恢复计时；白天/夜间/清晨真实存档冷启动验证见[本轮记录](../../development/2026-10-28_title_composition_saved_time.md)。

## 2026-10-29 家园建造接入

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-SAVE-R10 | 已实现；65实例含带作物搬移的独立海上平台70+8项跨进程恢复，旧档边缘迁移5+11项通过 | [本轮交付](../../development/2026-10-29_open_ocean_building.md) |

## 2026-11-02 渔场空间与存读

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-SAVE-R15 | 已接入候选升级状态、岸坪支持与围网水域投影；39项逻辑/43项真实渲染通过，真实胶囊/原泊位/坏档拒绝及新旧档往返已实测 | [本轮交付](../../development/2026-11-02_wild_fishery.md)；fishery-environment |

## 2026-11-02 重置存档

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-SAVE-R14 | 已实现；暂停菜单独立确认页 → 归档 → 注册表回开局 → 立即写新档；旧档归档为 `_pre_reset-<时间戳>.json` | `save-reset` 27项、`visual-save-reset` 5项0失败；[交付](../../development/2026-11-02_save_reset.md) |

新增接口：`SaveGame.archive(path, stamp)`（改名归档，返回 `files`/`mark`，失败整体回滚）；
`Main.reset_save(path := "")`（归档 → `save_registry.defaults()` + `restore()` → `save_game()`）。
命令 `reset` 走既有的 `_on_click_command` 路由，暂停菜单确认页负责防误触。
存档格式、版本号与迁移链**未改**：重置产出的就是一份普通 v4 开局档，仍然走 `SaveGame.read()`。

| SEA-SAVE-R16 | 已接入周期储量与下次产鱼时刻，v1兼容、v2坏档拒绝与重复钟点由fishery-production专项核验 | [本轮交付](../../development/2026-11-02_fishery_production.md) |

## 2026-11-02 新旅程与角色档案

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-SAVE-R17 | 已接入，专项与回归以本轮记录为准 | `avatar / avatar-restart / onboarding / save-reset / save-protection`；[交付](../../development/2026-11-02_avatar_and_arrival.md) |
| SEA-SAVE-R18 | 已实现并实测通过；根v4/building版本1和必填schema不变，旧档原数据保留且无需迁移，支持2.8m旧结构与5.086335m实际平面混合；校验失败不改现场、不覆盖有效备份、不重复收费 | `building-save-compat`37/0来自`D:/projects/sea-work/verification/20261106-222059-building-5m-release-signed-2a186b/report.json`；`save-protection`来自`D:/projects/sea-work/verification/20261106-211435-building-5m-final-816d34/report.json`，exit0且日志`ok=true protected=true unchanged=true separate=true`；[建筑5m与UI开发记录](../../development/2026-11-06_building_5m_and_ui.md) |

2026-11-06 R18最终安全补记：Service以rooted支撑修复高空孤台/循环支撑save绕过；无支持的新旧高空布局均拒绝，地面历史孤立合法。根v4/building版本1、旧ID/尺寸/坐标/py原数据及失败不改现场原则保持，未修改玩家真实存档。`building-5m-rules`446/0、`building-5m-experience`589/0及`building-save-compat`37/0在222059 release-signed报告中均通过；211435中`character-space-save`10/0和`save-protection`通过补充恢复与保护证据。不因此宣称断电/所有平台文件系统已验收。

## 2026-11-07 多潜水地图进度兼容与写盘门禁

| 对应设计条款 | 当前实施状态 | 证据 / 待核验 |
|---|---|---|
| SEA-SAVE-R19 | 源码注册稳定DiveSession为原 `dive` 所有者；根v4与 `{found:int[],opened:int[]}`不变，不增map_id必填字段。固定全局宝箱ID、未知ID保留与from_dict全量覆盖已接入；registry.busy_query包含active/switching，直接SaveGame.write同样拒绝中间快照 | `DiveSession.to_dict / from_dict`、`Main._setup_save_registry`、`SnapshotRegistry.is_busy`、`SaveGame.write`；`dive-maps`运行 **pending，待父线程补充** |

本条覆盖潜水数据的旧“未知内容过滤”概述；其他模块规则不变。初填pending为过程，最终R19由`20261107-190643-dive-map-switch-signed-451501`签署：dive-maps312/0、framework52/0、save-seed/save-corrupt-seed/save-protection均exit0且无非预期错误，覆盖旧ID/未知ID、跨图隔离、全量恢复、磁盘往返和潜水直接写盘拒绝；满包奖励原子结算亦通过。未升级根v4、未改dive wire字段、未触玩家真实档。断电/低端设备与所有文件系统未测，状态保持partial。[完整机制与最终结果](../../development/2026-11-07_dive_map_switch.md#10-最终实测与签署)。

## 2026-11-13 存档深度审计（未修复）

补充现行存档校验/保护/恢复/归档/忙门禁条款的反例，不覆写旧验收。基线94ec42e0；动态确认S01候选二楼依当前sunroom现场误收/误拒、S02语义坏主档不回退且可污染bak、S03同root未来NPC模块可覆盖、S04macOS同stamp归档覆盖、S05畸形economy七例脚本异常、S06weather未来版降存、S07未来grow_day冻结、S08房间过场存读允许、S09疲劳窗口可存且新进程不续接强制睡眠。二楼真实攀梯双进程等扩展未执行，不夸大为全平台已复现。

S10–S16为迁移/投影/autosave/reset失败/跨owner事务等静态或待验条目。现有save-protection/reset/framework-integration通过不反驳新增反例；诊断wrapper exit1保留错误，未改生产/根v4/玩家正式档/哈希。优先B1候选上下文、完整可恢复备份择优、模块future、唯一归档及统一稳定态busy，B2再收口事务。逐项位置、方案、验收和真实report见[深度审计记录](../../development/2026-11-13_engine_deep_audit.md)及工程外issues.json。登记头保持partial，不预签修复。
