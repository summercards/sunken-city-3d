# 2026-11-20 · 正式世界总集成：保留玩法基线与切换阻断

[主文档](../../GDD_V1.0.md#feature-control) · [模块接口](../architecture/module_contracts.md)

**未切换正式 F5，也未退役运行代码。** 旧完整入口目前以原 profile 可启动并游玩；实验船壳迁移会回归正式航线、泊位与海上拾取，未引入共享树。F5 仍为 `scenes/main_minimal.tscn`，原完整场景仍为 `scenes/main.tscn`。正式潜图选择、经营、存读档协议、用户手摆均未修改。

## 1. 隔离与上游交接

- 初始 `codex/feature-controlled-structure`，HEAD `ceae1b03cce77935bd674c9374429a183dc28569`，240 未暂存、61 未跟踪。外置测试根：`/Users/zyq/work/sea-work/formal-integration-rKdBCR`（下表批次均在其 `verification/` 下）。`evidence/before.sha256` 的 114 路径与初始独立副本一致；上游工作进行中发现公共文件变化，未覆盖。确认上游 turn 完成后重采 `handoff/live-before.sha256`，包括钻入发现的视觉改动，原型结束时逐项复核一致。
- 上游交付白盒水色/波纹/反射复查及接触泡沫、固定上午光照，见 [视觉复用交付](2026-11-20_minimal_surface_visual_reuse.md)。白盒仍不含 zone1 下潜接线；旧完整场景的潜图控制器和环境无需复制。原完整入口依次由原版家园优先判定和已安装泊位选择来源，本次在正常 zone1 水域验证，不强制改成 zone1。
- 所有 Godot 运行经 `scripts/run_verification.py` 在外置副本执行；先设独立 `user://` 再导入及启动 Autoload。只用自动生成的旧存档夹具、测试世界和 `user://trip-busy.json` 拒写探针；不读写真玩家档。

## 2. 未迁移产品代码的基线

| 批次 | 结果 |
|---|---|
| `20261120-014525-old-entry-0625a5` | 隔离重导入 exit 0；旧 profile 原 Main、Zones/Economy/GameState 及节点检查 9/0，exit 0。 |
| `20261120-014722-old-headless-2acbb8` / `20261120-014603-old-retained-6ba5b0` | 两批均 runner exit 1；原 `surface` 540/2、`landing-markers` 24/3、`building-surfaces` 80/3 均 exit 1。其余 11 项各 exit 0：`click` 39/0、`keyboard-control` 30/0、`keyboard-travel` 374/0、`ground-space` 37/0、`building-integration` 46/0、`management` 40/0、`minimum-loop` 112/0（实窗 113/0）、`save-seed` 生成成功、`framework-integration` 52/0、`save-boundaries` 168/0、`dive-maps` 882/0（实窗 894/0）。 |
| `20261120-020836-entry-recheck-7f198e` | 外置入口候选仅修测试夹具：泊位检查读取实际支撑，保留单格菜箱包装断言；标记密度夹具补体力；门洞夹具经正式 `can_place` 查空水，保留真实建造和选取。实窗 `surface` 540/0（56 条航路）、`landing-markers` 25/0、`building-surfaces` 81/0，均 exit 0；没有放宽经营或世界规则。 |
| `20261120-020112-old-trip-r3-bcd02a` | 原完整入口单链：WASD 走近 → 同源 E 提示与上船 → 点击水面、沿原航线停船 → 点击正式潜水 HUD → 正常选定 zone1 → 真实 HUD 上浮 → 返回同一 Main/船/人、原海面镜头与环境 → 点击原泊位并上岸。无头 31/0、Metal Forward+ 36/0，均 exit 0。只放置起步夹具和测试取景机位，途中不写人物/船姿态。下潜期间直接保存拒绝；姿态在冻结与恢复信号边界相同。第一轮未找到视野可点目标、第二轮在冻结前采样把海面正常升沉误计为位置变化，原失败证据保留。 |

真实渲染：最后往返 `project/outputs/formal-trip-01-shore.png` 至 `formal-trip-05-landed.png` 共 5 张（目检 `03-underwater` 与 `04-return-same-boat`，不是人工操作）。原实窗批还生成 11 张潜图及返回画面、2 张泊位、4 张建造、2 张经营截图；没逐张签审。Runner 报告 `unexpected_errors` 里的 `FAIL` 行和实际引擎错误分开查，不把基线红项列成允许通过的预期引擎故障。

## 3. 发行入口实测（只在外置入口候选）

- `20261120-015035-old-pack-27b438`：Windows Desktop 导出两种 profile，两个引擎 exit 0 但 runner exit 1。直接发行默认白盒的真实 `project.binary` 指向 `main_minimal.tscn`，三个 Autoload 均不在；旧脚本缺 Autoload 编译错误与 Terrain3D 无选中节点错误共 291 条匹配。旧完整 profile 的 `project.binary` 指向 `main.tscn` 并含三 Autoload，仅剩 Terrain3D 的空引用错误。不能用文件存在或原始退出码签署发行。
- `20261120-020258-entry-candidate-e8081c` 与 `20261120-021134-entry-all-presets-7ca38f`：外置 `entry-candidate` 恢复真实 `project.godot` 的 Full Main 与三 Autoload；Terrain3D 导出插件对无选中地形时的版本查询作防护，不改资源数据。无 override 的正式启动 9/0，默认入口真窗口 120 帧，Windows Desktop、Windows 单文件及 Web 三个 preset 均真实 `--export-pack` 成功，exit 0。索引校验三包各 4353 项、必要项无缺、禁入项 0（336,359,028 / 336,359,060 / 336,359,044 字节）。这是包数据与 macOS 编辑器引擎启动证据；本机发行模板目录为空，目标 Windows / Web 的实际运行、渲染和发包未验。

## 4. 原生船壳候选与切换阻断

外置 `physics-candidate` 试接原白盒凸船壳，在平均水线做平移扫掠和分段旋转净空；船根仍是原 `Boat` 唯一写。候选把 zone1 栈桥接触体放在组件 TSCN，在建造投影为完工底层平台建实体；旧导航/场地查询全部保留，对其他碰撞及新泊位安全不作完成声明。

| 批次 | 守门结果 |
|---|---|
| `20261120-022016-hull-candidate-b13a30` 无头 | 原入口 9/0、静态航路对照 `surface` 540/0，exit 0；原生主场景 `keyboard-travel` 38/2（zone1 离泊去 zone5 未到达）、`building-integration` 46/2（到站未触发收取，奖励未结算）、正式往返 30/2（潜水同船恢复通过，回泊上岸失败），exit 1。 |
| `20261120-022332-hull-candidate-r2-3c8533` Metal Forward+ | 加入「转角不净空时按原航段低速尝试，平移仍经完整扫掠」，`building-integration` 46/0、exit 0，但离泊 `keyboard-travel` 38/2 和回泊实窗往返 34/2 均 exit 1；同船恢复通过。未通过门禁，不接入共享。 |

**下一步先改航线接口再退役旧阻挡**：原中心线可航不是完整船体可航；起离泊、入泊及漂流物/建造收取接近点要按实际船壳与局部泊位朝向验证。先重放失败航段记录碰撞体、相对姿态及计划转角，再验不穿实体的低速进出泊与远岸接近；不是改手摆、移动现有 Marker 或删除障碍来过测试。

- `WaterNavigation` 保留航线、开阔/几何水、泊位和存档查询；`BlockerSet` 还供水线轮廓和世界/建造占用，不因名字删除。`GroundSpace` 仍提供 `area_at/surface_point/route` 及旧物理投影；实体支撑、外缘和楼层接缝逐区域覆盖后，才能逐项停用已替代的地板/边界生成。`geometry_changed` 保留同一布局所有者，完工/移动/拆除/恢复依原生命周期刷新；施工预留与已完工物理阻挡分开，纯视觉不生成碰撞。
- **已退役、已清引用：无。** 尚未将白盒船控、正式泊位安全提示和实体阻挡签署进正式入口，也未将白盒下潜标为完成。旧档夹具、视觉及预期故障必须在下一版候选重跑；未验人工手感、所有静动态碰撞、目标平台、性能和素材终审。
- 摆位台账未更新：没有新增、移动或替换正式建筑实例。`check_placed_positions.py` 检查 16 个、0 警告、exit 0；共用 `main.tscn` 和 `project.godot` 指纹在实验前后相同。功能规格没有替换或加新条款，因为候选未改变现行契约；各功能账本只追加本轮实测与阻断。
- 共享树 `check_feature_contracts.py --sync` exit 1（586 项）、只读检查 exit 1（587 项）。相对交接前共享树的只读检查（588 项）无新增失败；白盒场景哈希差异已由上游消除。余下含旧报告链接、登记与资源哈希、派生索引，未批量更新哈希。具体为 `evidence/shared-feature-sync-after.log` 和 `evidence/shared-feature-check-after.log`。

## 5. 后续已实测：完整 F5 与可拆试坡

以上部署阻断及路线结果是旧候选的历史记录。共享项目现已默认启动完整 `main.tscn`，保留三 Autoload，不装 `override.cfg`。[正式 F5 临时试坡](2026-11-20_formal_home_ramp.md)记录原开场落点到坡脚、无跳上下坡、回原甲板的实窗结果。原自动航线不再作为下一阶段验收目标；旧候选未合入，独立查询、原存档和用户手摆保留。正式手动船壳和上下船安全尚未在此批次验收。
