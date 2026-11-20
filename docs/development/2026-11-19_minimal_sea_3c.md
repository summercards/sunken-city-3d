# 2026-11-19 · 最小海面入口：步行、登离船与手动划行

[主文档](../../GDD_V1.0.md) · [前置只读盘点](2026-11-19_sea_0.1_3c_inventory.md) · [白盒初版](2026-11-19_minimal_main.md)

## 入口和玩法

默认 F5 仍为 `godot/scenes/main_minimal.tscn`。开局在坡脚，向「E · 泊位」走近后按 **E** 上船。岸上和船上均用 **WASD／方向键** 按当前画面的上下左右移动。船先朝所指方向转头再推进，松手滑行后停下；撞到码头可按远离障碍的画面方向离开。手动驶回坡脚同一侧，船身大致与泊位平行且停稳，再按 **E** 下船。不自动航行或吸附；岸上移动、快跑、坡脚落水复位仍走原先的陆地控制。拖拽、滚轮和 **F** 重跟随继续使用同一台 OrbitCam。

工作树为 `codex/feature-controlled-structure` / `ceae1b03cce77935bd674c9374429a183dc28569`，开始时与盘点的三项入口文件哈希一致，保有并行未提交改动，无暂存、合并冲突或 `override.cfg`。只在现行白盒挂载，没换分支、拉取、提交或推送；`project.godot`、旧 `main.tscn`、船外观资源、共享角色和 OrbitCam 源码保持字节不变。旧 `Boat` 初版未改，补充阶段仅把既有划桨采样和挂点查询提为共用代码，见下文。没有读取或修改玩家真档。潜水、经济、旧界面及存读档不进入白盒。

## 实现和编辑

- `godot/scenes/main_minimal.tscn`：使用原坡脚作码头；`Ramp/Berth/Shore` 与 `BoatPark` 是局部可编辑锚点，可随 `Ramp` 移动。`Boat` 的初始 XZ 和朝向独立可编辑（运行时 Y 初次对齐 `Ocean`，不会在航行时重新吸附泊位）。移动坡脚时应核对与 Deck 的接缝，并摆回实际有净空的船初始位置；编辑器只保存参考配置，不承诺任意旋转、缩放仍可靠泊。各初摆及实测见[位置台账](../features/world/placed_positions.md)。
- `godot/src/bootstrap/minimal_main.gd`：一个即时登离船交接，在物理帧先查距离、船停稳、船向、船壳净空、座点高差/水平距、坡脚支撑及角色胶囊净空；失败只显示原因，角色、船和镜头不切换。默认岸上接近 0.85 m／停船半径 0.95 m／允许沿泊位轴两个方向 ±24°；都可在场景中调整。成功才切换同一角色父节点、碰撞和运动权限；按住方向跨态要先松开，无双重操控；F 总是接回当前主体。座点与划桨握点来自现有黄白木船的实例。
- `godot/src/navigation/minimal_skiff.gd`：复用老船手感常量和正式外观，不实例化旧 `Boat` 控制器。新白盒用 `CharacterBody3D.move_and_collide()` 扫掠；可在编辑器里检查船壳凸形代理，转向前查候选姿态净空，与既有平台/斜坡真实碰撞共层。没有刚体漂移补偿或绕过碰撞的持续位置写入。松手用原有减速/低速收尾参数；船身不能立即转过障碍时，才以限速脱困步向目标方向移动，且仍须通过扫掠；渲染模型（含船座）使用同一海面波场的四点采样，物理船壳保持平均水线。船桨和附件是表现，不单独参与扫掠；未做尾流。
- 复用 `SEA-SCENE-SKIFF-ASSEMBLY`，不发第二个 AssetID。白盒的泊位、标识和碰撞是场景内接线，不是新美术源包：更新场景运行清单和已有木船消费者。木船底图商业权属保持 pending，未以此次接线作为授权签署。

## 初版验证（补充复验见下文）

证据根 `/Users/zyq/work/sea-work/verification/`，各批有 `report.json` 和逐项日志。全程通过 `scripts/run_verification.py` 派生独立工程和用户目录。以下 exit 是引擎子进程退出码；runner 非零另列。

| 批次 | 实测与结果 |
|---|---|
| `20261119-221706-sea-3c-skiff-final-e433b3` | `minimal-skiff` **43/0**（headless），`visual-minimal-skiff` **57/0**（真实 Metal Forward+ / Apple M6，1280×800）；两项及 runner 均 exit 0，无预期或非预期引擎错误。通过 `Input.parse_input_event` 从配置的实际场景走通：陆地 → E 上船 → 倒划/前划、转弯、松手停 → 船头触发真实 Ramp 碰撞并挡住 → 倒划脱离 → 驶回泊位停稳 → E 下船 → 再走路。回泊未写船位置。 |
| `20261119-221907-sea-3c-entry-and-land-1dd1b5` | `minimal-main` 和 `visual-minimal-main` 均真实渲染 **42/0**，`minimal-main-launch` 直接启动正式 F5 入口、120 帧；三项及 runner 均 exit 0。上下坡贴地、快跑、刹停、侧面阻挡、开放边落水复位和陆地镜头回归通过。另 `20261119-222501-sea-3c-land-headless-final-d1ff30` 无头陆地 **35/0**、exit 0。 |
| `20261119-221930-sea-3c-legacy-entry-df5726` | `legacy-main-restore` 9/0、引擎 exit 0，但屋顶街机铺 GLB 的导入缓存缺失；runner exit **1**，不记作通过。 |
| `20261119-222023-sea-3c-legacy-reimport-917f2c` | `legacy-main-restore` 用隔离 `--import-assets` 重跑（本进程内把 `terrain` 挂载也换为复制），导入 exit 0，旧入口/三个旧 Autoload/节点布局 **9/0**、引擎和 runner 均 exit 0。只复验旧入口，不签经营或旧档兼容。 |

`visual-minimal-skiff` 输出 `project/outputs/minimal-skiff-{01-land,02-boarded,03-open-water,04-contact,05-detached,06-moored,07-ashore}.png`，7 张均已目检。各最终验证副本的场景、本轮 gameplay 脚本与两项测试源码已与当前树逐字节比对一致。预期业务拒绝：岸上过远、泊位内仍在移动、泊位外、船头斜顶、落点被占、缺支撑；拒绝时仍处原输入主体及镜头。Echo E、高差、真实船壳接触和停住后的稳定也受专项覆盖。

**结构核对：** 位置台账 13 项、0 警告，exit 0；`git diff --check` exit 0。全局 `check_feature_contracts.py --sync` exit 1（543 项），随后无参 check exit 1（544 项，与开工前失败列表完全相同），派生索引未写回。已知基线包含历史证据链接、资产/脚本哈希、`SEA-ASSET-R67` 缺双向登记及并行区块内容漂移。未批量刷哈希或改动无关资产；木船运行清单原 CRLF 哈希可由 Git 内容复现，现有工具不支持 LF 去匹配已登记的 CRLF，未为了消红改旧资源字节。完整日志在 `/Users/zyq/work/sea-work/sea-3c-20261119/`。

**未验项：** 系统键鼠或真人操作没有执行：本机 Computer Use 未开启。上述真实窗口全程由 Godot 脚本注入输入，不等同于系统键盘、手柄、触屏或人工手感。未签编辑器实拖重开、任意海况和角度的所有船体附件间隙、连续性能、发行包、其他设备、旧世界全量或潜水。初版船桨在泊位可能伸至坡脚板上方；本轮只保证凸形船壳阻挡，不把桨当作实体船宽。

## 补充复验：现成划桨与海面木块

- 船模 `reference_skiff.tscn` 和角色动作 `rowing_action.gd` 没有改动。把旧 `Boat` 中的原划桨采样及挂点查询提到 `godot/src/player/animation/rowing_rig.gd`，两个运行入口共用。白盒明确给旅人的现成动作注入船的相位、幅度、`RowingSeat` 与左右 `Grip`；不再靠缺少查询时的通用手臂摆动。停划恢复原有坐姿持桨，只有下船才切回站姿。
- 在 `main_minimal.tscn` 的 `TimberObstacles` 下摆三个 `timber_obstacle.tscn` 实例，单件可拖动、旋转或增删。木色网格和静态碰撞的局部尺寸与变换一致，使用船实际检测的码头层（256）。A/B 净宽约 5.8 米，C 在另一侧，未改坡脚泊位和原陆路。原生白盒木块为一个组件、一个新 AssetID `SEA-SCENE-MIN3C-TIMBER`，已有船模仍沿原 AssetID，未替换模型或清除权属 pending。
- 新增斜碰专项曾抓到常规直接位移在凸角接触时缓慢爬移。现先测 Godot 原生扫掠及末点净空，只提交安全步，接触后阻断同向继续推进；松键、反向、或有净空的转向可恢复。没有用位置重设脱困。前几轮测试路线调试及斜碰失败保留在 `sea-3c-timber-first`、`sea-3c-timber-route`、`sea-3c-timber-final` 和 `sea-3c-timber-sweep` 各批报告，不计当前通过。

| 当前批次 | 结果 |
|---|---|
| `20261119-224719-sea-3c-timber-signed-937619` | `minimal-skiff` **78/0**、`visual-minimal-skiff` **104/0**，引擎及 runner 均 exit 0，无预期或非预期引擎错误。通过全程预约键位的 `Input.parse_input_event` 而不是改船坐标：保留原上下船往返，再连续实测正撞 A、斜撞 B、各自倒划脱离及驶过 A/B 通道。正撞与斜撞期间每物理帧核验船壳不重叠，持续推进也不再爬移。 |
| `20261119-224515-sea-3c-rowing-regression-135c1c` | 隔离导入 exit 0；已有 `rowing-fit` **76631/0**、`reference-skiff` **94/0**，陆地无头 **35/0**、真实渲染 **42/0** 及 F5 启动均 exit 0，无非预期错误。该回归与最终专项的共享采样、旧 Boat、模型和木块场景一致；白盒最终的同向阻断以 224719 为准。 |

最终 Metal Forward+ 窗口有 13 张 PNG，目检其中本次新增 6 张：`08-rowing-15`、`08-rowing-48`、`09-rowing-stopped`、`10-timber-head-on`、`11-timber-oblique`、`12-beyond-channel`（文件前缀 `minimal-skiff-`，见批次 `project/outputs/`）。活画面按物理帧采样，断言桨叶和双手确有位移、掌心距实际握点低于 8 mm、骨盆与座板高差低于 25 mm；松手后核对两桨回到原停桨角度且手未离开握点。物理日志报告两块木块接触对象与撞前/撞后位置；第三块验了可见/实际碰撞配置与入水线，未逐块测所有角度。系统键鼠/人工操作和编辑器实拖重开仍未执行，真实窗口证据不替代它们。

最终位置检查 **16 项、0 警告、exit 0**，`git diff --check` exit 0；契约 `--sync` / 普通 check **exit 1 / 1（543 / 544）**，失败项及出现次数与原基线相同，未重写派生功能索引。旧 `main.tscn`、项目入口、船模、角色动作不变；没有切分支、提交、推送、接入潜水/经营或碰真档。


## 补读与契约复核

### 阅读时点（北京时间，按本实施任务的工具记录，不以此前盘点代替）

- **初次写代码前（晚间首轮，开工基线快照 22:07）**：实际读取 `AGENTS.md`、两份 README、[GDD §0／当前可玩版本与阶段记录](../../GDD_V1.0.md) 以及 [§10 功能导航和 §11 交接](../../GDD_V1.0.md#feature-control)，并读[前置盘点](2026-11-19_sea_0.1_3c_inventory.md)。GDD 先定位 BOOT / WORLD / MOVE / NAV / CAMERA / OCEAN / ASSET / SAVE，也见 INTERACT / QUALITY 导航。确认 F5 白盒与旧完整入口不能混签，位置、状态所有权和证据按对应功能管理。首轮对功能文件做的是**定向搜索和摘录阅读**，部分只看到标题或被截断；不记作全文通读。前置盘点只是资料来源，不把它列的文件追记为本轮开工时直接阅读。
- **木块补充前（约 22:30–22:37）**：再定位 GDD 当前入口及 MOVE / NAV / WORLD / ASSET 白盒增量章节，复查旧船、船座/桨、`rowing-fit` 与资产分类；没有在这个时点补齐下表缺项。
- **本次补读（约 22:53–22:56，镜头修复前）**：按下表重新核对各 spec/ledger 相关条款和现行白盒章节。此前没逐条读到的标为「补读」，不回填成开工前已读。

| FeatureID / 实际读取文件 | 初次开工前看到的内容；本轮补读 | 约束和对照结果 |
|---|---|---|
| SEA-BOOT · [spec](../features/boot/spec.md) / [ledger](../features/boot/ledger.md) | 开工前：R08 白盒入口与旧入口隔离摘录、账本头及 R07/R08 局部；本轮补读 R02/R03 与现行 R09。 | `_physics_process` / `_try_transfer` 只允许一个移动主体；成功按当前主体恢复唯一镜头，失败保持；不引入旧 Autoload、潜水或持久化。 |
| SEA-MOVE · [spec](../features/move/spec.md) / [ledger](../features/move/ledger.md) | 开工前：R02 泊位交接部分、R19 握桨及 R37 陆地摘录，账本 R18/R37 摘录；R02 完整条件及 R18 整行本轮补齐，复核 R02/R18/R19/R37–R39。 | 相同旅人在白盒泊位站点和原 `RowingSeat` 之间交接父节点、朝向、碰撞与动作；查站立、停稳、真实支撑和净空。不移植自动接近、潜水和读档路径。默认旅人真窗口测动态握点与座板；极端体型/多帧率几何用旧 `rowing-fit` 分列。 |
| SEA-NAV · [spec](../features/nav/spec.md) / [ledger](../features/nav/ledger.md) | 开工前：R01/R04/R09/R15/R17/R19/R21–R24 摘录及账本对应证据摘录；第二轮补看原划桨和 `rowing-fit`；本轮补全 R09 双用途、R14/R15/R19/R22 及 R25/R26。 | R09 采用既有模型、桨与平滑收桨，不引入点击航点水纹、夜灯；R15/R19 保留手动控船、松手停、撞岸不穿及继续脱离的结果，不套用旧 `_clear`、120Hz 私有子步、旧侧滑/状态或尾迹。R22 的旧规划器距离、胶囊余量与自动到达容差不移植；白盒查原生船壳净空、实际胶囊及场景泊位。 |
| SEA-CAMERA · [spec](../features/camera/spec.md) / [ledger](../features/camera/ledger.md) | 开工前：独立文件导航、账本头及 R20 白盒摘要，另读 OrbitCam 源码，但未读到 R04 正文；本轮补读 R04 与 R20/R21。 | 成功上船/下船清平移、右键/中键旋转和跟随历史；拒绝不清玩家正在使用的镜头。只修白盒交接，不变更共享 OrbitCam、读档或潜水镜头。 |
| SEA-INTERACT · [spec](../features/interact/spec.md) / [ledger](../features/interact/ledger.md) | 开工前：文件导航、账本头/章节定位及盘点摘要；没有直接读 R07 条文和承接行。本轮补读 R07/R29，核对 R13/R14/R22/R23 的历史键盘口径，附记白盒 R30。 | R07 点击船体、图标换宿主和叫船是旧完整入口；白盒是固定位置标识 + E。复核拒绝给原因、不改输入模式、不启动自动航线，新增专项断言不安全落点的短句和不清当前旋转。 |
| SEA-WORLD · [spec](../features/world/spec.md) / [ledger](../features/world/ledger.md) · [摆位台账](../features/world/placed_positions.md) | 开工前：R42/R43 白盒边界、旧位置规则及台账两入口；首轮实施期间细查台账行和校验脚本，非开工前；本轮补核 R01–R03/R43–R45 与 7 条新增初摆行。 | 白盒只认 TSCN/局部锚点；原坡脚和 Deck 实体、独立木块装配和真实位置保持单一来源。参考位不是运行断言。不增旧 Zones 条目、不覆写旧 Main 手摆。 |
| SEA-OCEAN · [spec](../features/ocean/spec.md) / [ledger](../features/ocean/ledger.md) | 开工前：R47 最小海面条款与承接摘录；本轮核对 R47/R48。 | 船表现读同源海浪，实船壳留在平均水位；不接旧时钟、尾迹、材质写盘或潜水。 |
| SEA-ASSET · [spec](../features/asset/spec.md) / [ledger](../features/asset/ledger.md) | 开工前：R75/R76 摘录、现有船资产行和参考小船制作记录；并未直接读完 R28 条款。本轮补核 R28/R76–R78；木块制作前读既有组件计划、分账路由和原生白盒例外。 | 复用船模原 AssetID 及权属 pending；一份木块资产三实例，记录原生 TSCN、manifest、哈希和消费者，不刷新无关哈希。 |
| SEA-SAVE · [spec](../features/save/spec.md) / [ledger](../features/save/ledger.md) | 开工前：R22 的独立用户目录、不读写旧档及承接摘录；本轮复核 R22。 | 只验证白盒不会创建旧槽或水面设置；未测真档、旧档迁移或旧经营。 |
| SEA-QUALITY · [spec](../features/quality/spec.md) / [ledger](../features/quality/ledger.md) | 开工前：GDD/工程约定以及实际 runner 的隔离检查；未直接逐条看这两份文件。本轮补读 R01–R05。 | 专项使用正式场景，Autoload 前隔离，渲染与逻辑分列；保留失败、退出码和未验项，不以真实窗口脚本输入冒充人工。 |

### 差异与更新位置

- [GDD 当前可玩版本](../../GDD_V1.0.md)：默认入口新范围及条款编号。BOOT spec/ledger R09、MOVE R38/R39、NAV R25/R26、WORLD R44/R45、CAMERA R21、OCEAN R48、ASSET R77/R78 均是本任务追加；SAVE 只在 ledger 续记 R22（spec 不改）。本次补读另追加 INTERACT spec/ledger R30、CAMERA ledger R04/R21 回归和 QUALITY ledger R01–R05 验证分层；不重写历史条款或抬升功能状态。NAV 登记头只补当前代码和两项专项入口。
- 场景实例在 `godot/scenes/main_minimal.tscn` 的 `Ramp/Berth`、`Boat`、`TimberObstacles`。`godot/src/bootstrap/minimal_main.gd` 的 `_try_transfer` / `_at_berth` / `_safe_landing` 是交接、船位和岸上净空差异；`godot/src/player/minimal_walker.gd` 只接输入门；`godot/src/navigation/minimal_skiff.gd` 的 `advance` / `_physics_process` 实现碰撞与原波场，`godot/src/player/animation/rowing_rig.gd` 与旧 `boat.gd` 的 `_animate_oars` / `rowing_pose` 共用原采样。旧 Main、project、模型、角色动作及共享相机未改。
- 资产更新：`assets/registry/ledgers/scenes.json`（SKIFF-ASSEMBLY 增白盒复用证据、MIN3C-TIMBER 新行）、`current_source_index.json`、`views/buildings_above_water.json`、`runtime_resource_inventory.json` 定点增量；`art_source/scenes/minimal_main/v001/{component_plan.json,timber_obstacle.manifest.json}` 追溯木块。`docs/features/world/placed_positions.md` 增船、泊位根、两个局部标记和三个木块；`scripts/check_placed_positions.py` 只补白盒条目核对。`scripts/run_verification.py` 增两项白盒选择，`godot/tests/test_minimal_skiff.gd` 驱动整条海上流程，`test_minimal_main.gd` 保留陆地基线并更新装配清单。
- 并发与本次差异分开：开工前已有默认 F5 白盒与旧场景本地改动、屋顶街机铺、潜水/工坊及其资料/导入、GDD、若干账本/清单及 runner 的其他差异。未借 `git diff HEAD` 把这些归本任务；开工状态与关键字节在 `/Users/zyq/work/sea-work/sea-3c-20261119/` 的 `worktree-before.txt`、`protected-before.sha256`、`contracts-before.log`。旧 GLB 缓存缺失见初版失败批，已隔离重导验证，未改现场缓存或替并发更改签收。

### 复核实测与仍未验证的范围

- **发现并修正**：OrbitCam 的跟随复位原先只清平移、不清右键/中键旋转。负向 `20261119-225605-sea-3c-camera-negative-3ebdff` 为 **83 项、3 失败，exit 1**：按住右键上船、按住中键和左键下船仍残留旋转，以及后者改变镜头相对陆地方向的连带断言。白盒成功交接现在先清旋转，再复用原平移和跟随复位；拒绝保留正在使用的镜头并提示原因。旧 OrbitCam 源码未改。
- **过程失败保留**：修复后第一批 `20261119-225654-sea-3c-handoff-audit-8b8efc` 无头及陆地通过，但真窗口航线偏离、下游用例连带失败（109 项 27 失败，exit 1）；`20261119-230107-sea-3c-handoff-window-repeat-5dc89b` 仅通道末段失败（109 项 1 失败，exit 1）。此后仅对专项关闭脚本事件聚合、保存更细失败诊断；不改产品输入缓冲或降低断言。`20261119-230402-sea-3c-handoff-unbuffered-ebd311` 真窗口 **109/0**、exit 0，随后再跑当前快照。
- **最终批次 `20261119-230546-sea-3c-contract-signed-1b3f6f`**：无头 `minimal-skiff` **83/0**、Metal Forward+ 1280×800 `visual-minimal-skiff` **109/0**、陆地无头 **35/0**、实际窗口 **42/0**；四项及 runner 均 exit 0，无预期或意外引擎错误。键鼠由 `Input.parse_input_event` 驱动，涵盖右键上船、中键/左键下船、拒绝保留旋转并给原因，以及同次航行、现成划桨、正斜碰与绕行。最终批次 `02-boarded`、`07-ashore`、`12-beyond-channel` 三图已目检；全图存在不等于全部复审。场景、运行补丁与相关测试源码已和最终隔离副本逐字节对比一致。旧船回归继续取上节 `224515` 批，不把它当这次新跑。
- **静态与边界**：位置 **16 项、0 警告、exit 0**；`git diff --check` exit 0。全局 `--sync` 与无参均 exit 1（543/544），失败集合及出现次数与开工前一致，未更新派生索引。日志 `handoff-contracts-{sync,check}.log`、`handoff-positions.log` 同在上述工程外 `sea-3c-20261119`。系统键鼠、真人手感、真实编辑器拖动重开、所有船桨/第三木块角度、性能/发行包、旧世界全量与真档均未验。


## sea 0.1 方向更正

### 本批开工前重读与基线

2026-11-19 23:12 CST 写入 `directions-before.txt` 与 `directions-before.sha256` 前，重新核对 GDD §10 的 [MOVE/NAV/CAMERA](../../GDD_V1.0.md#sea-move) 和 [DIVE](../../GDD_V1.0.md#sea-dive) 导航、各 [MOVE spec](../features/move/spec.md)/[ledger](../features/move/ledger.md) 的 R20/R38/R39、[NAV spec](../features/nav/spec.md)/[ledger](../features/nav/ledger.md) 的 R15/R25/R26、[CAMERA spec](../features/camera/spec.md)/[ledger](../features/camera/ledger.md) 的 R04/R21，以及 [DIVE spec](../features/dive/spec.md)/[ledger](../features/dive/ledger.md) 的 R32/R34/R78 相关段。继续沿原任务，不另开或转派。分支 `codex/feature-controlled-structure`、HEAD `ceae1b03cce77935bd674c9374429a183dc28569`，没有未解合并。两个输入脚本、walker、白盒场景与之前 `230546` 已验副本字节相同。旧完整入口、潜水和其他在途差异已存在，未发现与本批共享输入改动冲突；未写这些文件。

代码基线：`minimal_walker.gd:22–26` 已从相机取水平前向；旧 `minimal_main.gd:62–63` 把前后键变成船的油门、左右键变成舵，旧 `minimal_skiff.gd:57` 沿船头推进。实施：`minimal_main.gd:62–67` 取与 walker 同口径的当前镜头水平基，将按键转换为世界目标方向；`minimal_skiff.gd:27` 以该方向定目标航向、保留转向/加减速，正常对准后推进，180° 反向不能用不限期倒划替代转头。近障碍转角被拒时，允许朝已按方向做限速扫掠脱离，空出转向空间；同一目标方向撞住后不会持续擦入。姿态、原划桨、上/下船条件、镜头接管及陆地实现不改；屏幕操作提示改成画面方向。白盒场景、资产、旧完整入口 NAV-R15、共享相机与潜水控制器均字节不变。

潜水只读核对：当前 `godot/src/diving/dive_runtime_controller.gd:294–325` 的 X/Z 输入取完整 `camera.global_basis`；因此水平投影随镜头偏航，前/后在有俯仰时也带竖直分量，**不是**白盒船的纯水平投影。Q/Ctrl、E/Space 分别独立沿世界竖轴叠加，不改这条。`main_minimal.tscn` 和白盒装配无 DiveSession／潜水入口；本批没有实际跑停船下潜→返船，未接入潜水，也未把旧专项当成本批实测。

### 最终证据

| 批次（工程外 `sea-work/verification/<批次>/report.json`） | 结果 |
|---|---|
| `20261119-232351-sea-3c-direction-physics-320fd3` | `minimal-skiff` **104/0**，headless；Godot / runner exit 0，无意外引擎错误。 |
| `20261119-232459-sea-3c-direction-window-01d020` | Metal Forward+ 真窗口 `visual-minimal-skiff` **132/0**，陆地 `minimal-main` **35/0**、`visual-minimal-main` **42/0**；各项及 runner exit 0，无意外引擎错误。 |

海上和陆地各在三个实际镜头方位测四向，两次使用注入的鼠标拖转事件改变相机，既测 WASD 也测箭头；陆地每个样本以相反面向布置，船包括 90°/180° 输入和目标方向的实际位移。陆地矩阵只重置夹具起点；船在方向矩阵、泊位往返和木块动线中没有被改位置。为重复碰撞路线，测试会设定若干已知取景方向，和用鼠标旋转的矩阵分开。完整流程仍覆盖起步、滑停、真实桨动画与停桨、相反方向脱困、正斜碰及不重叠、绕行、拒绝不安全落点、靠泊和陆地跟随恢复。真实窗已目检 `minimal-skiff-13-camera-relative.png` 与 `minimal-skiff-11-timber-oblique.png`；生产和测试相关文件与两份最终副本逐字节一致。历史首批 `232019-sea-3c-direction-first-74f2df` **102/1，exit 1**：划桨采样窗临近木块，采到了碰撞后的收桨；最终把动作采样移到独立开水面，未放宽阈值。

真人键鼠/手感、编辑器实拖、手柄/触屏、白盒停船下潜返船、旧世界全量、存档和发行性能未验。真窗口是 Godot 脚本键鼠事件，不是系统键鼠或人工操作。


## 白盒泊位提示补充

### 起点与适用范围

2026-11-19 23:32 CST，实施前沿 [GDD §10](../../GDD_V1.0.md#feature-control) 重读 [NAV spec](../features/nav/spec.md)/[ledger](../features/nav/ledger.md) R25/R26、[MOVE spec](../features/move/spec.md)/[ledger](../features/move/ledger.md) R38、[INTERACT spec](../features/interact/spec.md)/[ledger](../features/interact/ledger.md) R07/R30、[CAMERA spec](../features/camera/spec.md)/[ledger](../features/camera/ledger.md) R04/R21。本次仍在 `codex/feature-controlled-structure` / `ceae1b03cce77935bd674c9374429a183dc28569`；无未解合并。本次触及场景、装配和海上测试与方向更正已验证快照相同，未见冲突；旧完整入口、潜水/工坊等改动仍是已有差异。现场清单、关键字节见工程外 `sea-3c-20261119/berth-before.txt` / `berth-before.sha256`。白盒仍无潜水入口，返船后的提示刷新待潜水接入后回归。

### 改动定位

- `godot/scenes/main_minimal.tscn:61`：原贴地 `BerthSign` 改为坡脚上方、朝向镜头的有描边标记，抬高并排在透明水面之后绘制，转镜头也可阅读；不动两个交互锚点、木块或物理资源。定点更新 `assets/registry/runtime_resource_inventory.json` 的白盒场景摘要，不新增 AssetID。
- `godot/src/bootstrap/minimal_main.gd:82,113,173`：`_check_berth()` 返回安全状态及通过查验的落脚点。E 请求及物理帧的两处提示共用这个查询，不再用泛指操作提示或两秒过期文案。没有加大热区；接近、坡脚支撑、泊位半径、停稳、对齐、船壳净空和落点支撑/胶囊重叠判据不变。就绪时标记和底部同示 E 上船或 E 上岸，否则底部说明当前缺的条件。拒绝不切角色、拖拽状态或镜头。标记不是按钮，不接入旧点击、叫船或自动寻路。
- `godot/tests/test_minimal_skiff.gd` 把岸侧和水侧边界的 ±0.04 m 夹具，与键位实走的靠泊往返分开记录；同时核普通行船、碰撞和镜头相对四向。边界探针只摆测试起点，不把夹具摆位算手动航行。走完边界夹具返回航线时等待胶囊真正重新接地，而不是下船后一帧强求能上船。

### 最终证据与边界

工程外 `sea-work/verification/20261119-234816-sea-3c-berth-serial-58af4a/report.json`：`minimal-skiff` **123/0**，Metal Forward+ 1280×800 真窗口 `visual-minimal-skiff` **157/0**，陆地无头 **35/0**、真窗 **42/0**。四项及 runner 均 exit 0，无非预期引擎错误。窗口注入 Godot 键鼠，实走陆地找标记上船、划回泊位、停妥按 E 上岸；检查岸侧/水侧边界、未停稳、未对齐、拒绝以及状态刷新、鼠标转镜头，兼验三机位四向、真实船壳正斜碰、脱离、绕行和停划。目检 `project/outputs/minimal-skiff-{01-land,07-ashore,14-berth-stop,15-berth-angled,16-berth-unsafe}.png` 五图，斜视时文字完整。最终隔离副本的场景、装配及测试与工作树逐字节一致。

过程失败保留：`233640` 类型推断导致测试脚本未加载；`233721`/`233820` 水侧夹具未等恢复后的胶囊重新接地，后续检查跑错主体。修复夹具，未放宽产品安全条件。`233916`/`234450` 实窗有方向矩阵或碰后脱离输入失败，期间有重叠窗口，不单凭日志断定焦点是根因；串行终版完整通过。初版标识在斜镜头曾被透明水面盖住，终版修正绘制顺序并按截图复核。正常拒绝是预期玩法，不是引擎错误。

位置 **16 项、0 警告、exit 0**，`git diff --check` exit 0；全局契约 sync/无参 **543/544、exit 1/1**，失败项和次数与开工前一致，派生索引未写回。旧完整场景、潜水、航行马达、陆地马达及共享相机未改；未新增资产、热区、点击交互，未提交或推送。真人／系统键鼠、编辑器拖摆、潜水返船后刷新仍未验。
