# 2026-11-16 建筑外挂32类型／96状态设计冻结

[主文档](../../GDD_V1.0.md) · [WORLD设计](../features/world/spec.md) / [账本](../features/world/ledger.md) · [WORKSHOP设计](../features/workshop/spec.md) / [账本](../features/workshop/ledger.md) · [ASSET设计](../features/asset/spec.md) / [账本](../features/asset/ledger.md)

## 本次范围与所有权

用户明确授权本记录及 `art_source/scenes/building_attachments/v001/component_plan.json` 新建；先检查 `art_source/scenes` 和 `docs/development` 父目录，再创建计划目录。其余只在GDD及三个现有功能spec/ledger末尾追加，不重写账本、登记头或历史章节，不创建新FeatureID。

本次是文档与sourceplan交接，不负责修复native代码、UI、静态库、正式资产登记或Blender导出。源码与UI由并行代理实施；本任务没有写code/tests/runner/runtime/registry/memory、正式场景、公共材质或用户transform，也没有运行Godot、Blender、runner、contracts、style checker、commit或push。文中的验证数字均为只读已有报告，不是本次执行。

## 规则编号与职责

全文核对ASSET已有条款最大为R68（另有R68a），不是R31或R50；保留旧重复R57，不占用历史条款。

| 本轮规则 | 职责 |
|---|---|
| SEA-WORLD-R37 | 现有场景装配内独立Templates/图库入口、四分类按钮、全局三condition按钮、搜索、真实缩略图和明确用途 |
| SEA-WORLD-R38 | 只读宿主真实可见三角面；surface point点击/拖放、wall/roof、米制锚点/法向与父变换补偿、失败/取消保护 |
| SEA-WORLD-R39 | Asset兄弟Attachments、独立实例、编辑器undo/redo、宿主换版保当前transform且不自动重投、显式重新贴合/手动场景保存 |
| SEA-WORLD-R40 | 静态无脚本运行、显式256层碰撞、水下无功能与世界派生排除、分域验收 |
| SEA-WORKSHOP-R92 | 独立外挂nativecore与房屋Recipe/shell/Generator/Session/Store/旧screen隔离，仅只读消费 |
| SEA-ASSET-R69 | 准确catalog的32type/96状态计划、四族八子族、候选身份不正式登记 |
| SEA-ASSET-R70 | 八类广告style与可编辑原创粗低面英文、保输入、正反面无镜像、编辑期烘焙 |
| SEA-ASSET-R71 | SF-B、单段实体倒角例外、公共PaletteUV/四solar角色、预算、逐part真实收分与三档损伤局部授权 |
| SEA-ASSET-R72 | 原生作者源/真实hash、旧mesh不复用、逐part native JSON与contacts、Blender衍生快照derive_pending |
| SEA-ASSET-R73 | 96静态交付与候选六件、独立重载/脚本安全/碰撞/分域状态与正式登记隔离 |

以上本轮实施条目统一 `implemented_pending_current_verification`；这不是登记头status新枚举，原功能全局 `partial` 不变。旧房屋R89–R91与旧装配R33–R36通过历史不撤销，但不签新外挂。

## 32种准确目录与计数

唯一目录 `godot/data/building_attachments/catalog_v1.json`，冻结SHA-256：`917a5a1dbf4bd6f23950eecd78af14ca8e6876cebc7a0019a713df9644082f39`。

| 族 | type_id与准确name（每族8项） |
|---|---|
| signage 招牌广告 | sign_fascia 横招；sign_vertical 竖招；sign_projecting 双面悬挑招牌；sign_rooftop 屋顶架招牌；sign_letters 独立粗字；sign_lightbox 灯箱；sign_arrow 箭头招牌；sign_hanging 拱顶吊牌 |
| hvac 机电通信 | ac_wall_single 单风扇壁挂机；ac_wall_twin 双风扇壁挂机；ac_roof_upflow 屋顶上排风机；fan_wall 墙面轴流风机；utility_junction 接线箱；utility_meter_pair 双计量表；satellite_dish 卫星碟；tv_antenna 电视天线 |
| water 水箱管线 | tank_round_short 矮圆水箱；tank_tower_cone 锥顶高脚水塔；tank_horizontal 卧式水箱；tank_rect 拼板矩形水箱；pipe_downspout 落水管；pipe_elbow 独立弯管；pipe_t_valve 三通阀管；pipe_bundle 成束管线 |
| shelter 风管棚盖 | duct_straight 直风管；duct_elbow 转角风管；vent_louver 百叶风口；vent_mushroom 蘑菇通气帽；chimney 烟囱；awning_slope 单坡雨篷；awning_barrel 圆拱雨篷；canopy_entry 入口柱式棚 |

每项有fresh全新/damaged破损/ruined残破三个准确catalog damage描述，共96状态项；32个unique type≤50，状态轴3≤5。四大族不是八种只改尺寸的同件：每族八个不同子族kind/接口/轮廓，常规子族各一个type；不通过把状态重命名type规避组件上限。广告frame/block/marquee、文字/色格/尺寸和实例姿态不另计type。

每type的 `asset_id=null`、`planned_key` 全部唯一，`formal_records_written=0`。后续登记脚本才经 `assets/registry/ledger_index.json` 的 `domains.scenes` 路由 `assets/registry/ledgers/scenes.json`、全库查重并分配正式身份；本计划不是资产账本，不新增96个正式主记录。独立候选 `ledger` / manifest同样不等于正式登记。

## 计划冻结内容

[component_plan.json](../../art_source/scenes/building_attachments/v001/component_plan.json)包含32行components及三态profiles、四族、完整公共契约与来源记录。

- name/raw_title逐字等于catalog，不自行换名；逐项kind/type/family/subfamily/mount_mode/anchor、米制默认尺寸、名义position_bounds、碰撞责任、预算与来源引用完整。
- Godot米制、Y-up、front=-Z、根/网格恒等与几何底心；墙锚 `mount_back`（anchorBack）在最终bounds背面中心，屋顶锚 `mount_roof`（anchorRoof）在底心。any类型按显式wall/roof选锚，不拿目录默认anchor当所有挂载已验。
- 名义bounds只由catalog默认宽高深推得，**不是实测AABB**。dimensions与scale各可取默认0.75..1.25，两者相乘名义范围0.5625..1.5625；真实字、支架、收分、style与破损均可能改变最终bounds，必须另测。正式场景transform始终是位置唯一真值。
- SF-B与三态condition严格分轴。用户授权本套件单段真实倒角与三档真实损伤，仅局部覆盖旧参考禁止损伤的风格，不改其他套件或房屋core。
- 每体量part真实1%..10%收分，最长轴变截面，线性d_top/d_bottom≤0.953；至少一件反锥。native部分当前只自报默认rho、功能尖锥rho=1或0段边处理，不等于合格，均待实测/修复，不追认例外。
- 保既有公共暖木8×8色板、Closest、PaletteUV非零面积单格小岛、安全边至少8px（native声明16px），只用四solar_cabin共享角色，不复制/改写共享材质或色板。
- 默认单状态总计≤1800 triangles；英文长度>8字符可≤3500；单glyph≤128。含双面字、背板、支架、style边饰全部最终可见几何。超限拒绝保原文，不截字凑预算。
- 粗英文原创笔画实体，仅编辑期生成/静态烘焙。A–Z/0–9/空格/.-!&最多24字符，未知或全空白招牌拒绝保输入；无运行TextMesh/字体重建。破损不删用户字；前面与双面外侧可读且不镜像。
- 内部接缝参考8mm、合法clearance 2..20mm；挂面世界净空参考12mm，不混为已验接触。禁止共面/穿插/flush。host不因本任务被开槽；boolean_cut若将来需要须有真实cut_verified。

## 原生作者源与Blender衍生边界

作者源为 `godot/src/building_attachments/` 的11份native脚本和catalog；source_records逐文件保留真实读取SHA-256。已有代码生成不是本任务新建的Blender作品，也不追称计划先于首次建模。

项目轮廓参考仅以下三份计划，实际文件SHA已计算并写入计划，不要求用户新图、不消费旧图/mesh、不移植旧字形或广告画：

| 参考计划 | SHA-256 |
|---|---|
| art_source/scenes/water_building_002/v003/component_plan.json | c3536c6203fb2846cbe2241e398cfdcdbd8ff7a17647953724b62f08e900c271 |
| art_source/scenes/gift_kiosk/v001/component_plan.json | 12c00931d7e8a3ad11f521ea7dee087a5a0a35c64d024c15981b0953fdc0b462 |
| art_source/scenes/neon_garden_quarter/v004/component_plan.json | 6a5b3e8d97bccdc303ab03954cfe653ef4fc20e60a193434d7794aa56e12263e |

旧mesh复用仍pending，本套件不复用；商业法务未签。Blender由另代理据native JSON做derived snapshot，状态 `derive_pending`，不得改写成原生Blender创作或完整02b。Godot→Blender `(x,y,z)->(x,-z,y)`，回Godot `(x,y,z)->(x,z,-y)`；衍生产物回链原生代码、配方与快照SHA。

native JSON应有meshes/source_parts/collision_proxies/bounds，逐part真实rho/taper、taper_along、bottom/top、线性d_bottom/d_top、missing_sectors、contacts等。非圆件显式0/不适用，附着必须有attached_to与接缝记录。当前contacts只部分声明、真实截面与自定义曲面未验，计划 `source_parts=null` 是有意待补，不生成假实测记录。

## 装配、用途与碰撞

场景装配拥有唯一场景写入；外挂core/Store独立，房屋只是只读消费者。Templates/图库用分类与三状态按钮/搜索/真实图预览；交接时仍观察到condition下拉，按钮化与拖放、上下文锁定由UI代理继续实施，不把目标写成已完成。

层级为 `Placement/{Asset,Attachments/<independent attachment>}`。只读宿主真实可见三角面点击/拖放，支持wall/roof，不是旧Y平面。宿主换版只换Asset，Attachments和所有子transform保持，挂点metadata仅追溯，不自动重投；提示检查并由用户显式重新贴合。编辑器新增/编辑/复制/删除/重新贴合走undo/redo，失败/过期上下文不改树或吞输入；场景Ctrl+S手动保存，Main不自动保存。

碰撞用简化逐part静态代理，显式layer=256/mask=0；五类重件ac_roof_upflow及四水箱默认true，其余false，但默认不代表人物mask或实际阻挡已验。管腔/缺口不得用总AABB/凸包封空，文字不生碰撞。所有外挂排除WalkArea/泊位/导航/船阻挡/岸线/泡沫/潜水/玩法派生，visual_only用于排除派生，不隐去已明确开启的物理碰撞。水下纯观赏requires_collision=false且collision_enabled必须false，true明确拒绝、不静默调整；全子树无空间/玩法功能，UI明确用途。

运行场景是静态scriptfree，无生成器/controller/TextMesh。每type/condition库计划三件 `.tscn/.native.json/.recipe.json` 及library_manifest；独立候选六件为attachment.tscn、attachment.recipe.json、geometry.native.json、catalog_snapshot.json、source_manifest.json、candidate_manifest.json，写新revision、不覆历史。数量/manifest存在不等于合格、正式登记或Main接入。

## 房屋core与旧screen锁定

读取时先 `git status --short`、再 `git diff --stat` 并计算当前文件SHA与完整diff SHA，保存在计划housing_core_locked。以下8件只读，不回退HEAD、不接管并行改动：

- godot/src/workshop/recipe.gd
- godot/src/workshop/shell_geometry.gd
- godot/src/workshop/shell_generator.gd
- godot/src/workshop/shell_union_geometry.gd
- godot/src/workshop/generator.gd
- godot/src/workshop/session.gd
- godot/src/workshop/store.gd
- godot/addons/building_workshop/editor_screen.gd

读取时recipe/shell_union/旧screen已分别有27/24/433行规模diff；本任务不把它们清零或重签为外挂修改。配方、shell算法/阈值、Session/Store、旧UI不增加外挂字段或分支；外挂保存不经过房屋Store。

## r6真实证据与未合格状态

只读外层报告：`/Users/zyq/work/sea-work/verification/20261116-032945-attachments-frozen-r6-1b18e2/report.json`。

| 域 | 结果 | 结论 |
|---|---|---|
| building-attachments core | 7712 checks / 10 failures；exit1；passed=false | 卫星碟、锥顶水塔、蘑菇帽各三态闭合共9项失败；另有-Z前轴F镜像。typed Array传proxy异常仍在，不是合格96件 |
| build-attachment-library | 96 records；inner passed=true；exit0；9条SCRIPT ERROR；outer passed=false | 输出数量/进程0不能覆盖脚本错误；不能签96静态库合格 |
| visual-building-attachments | 484 checks / 0 failures；exit0；13条unexpected；passed=false | 真实renderer已执行但整体blocked，不签视觉、美术或零错误；本任务未逐图目检 |
| editor | 用户交接时尚未hook、未执行 | 未读到当前完整editor成功报告，不填检查数或通过状态 |
| Blender衍生 | derive_pending | 另代理承接，未签源重开/导出/02b |
| 正式登记、世界、性能、商业权属、用户艺术终审 | pending | 不写AssetID/registry/runtime清单，不签导航/行走/岸线/潜水 |

本批并非“预期红项”或可忽略警告。旧工坊1453/0和旧装配78/0仅保历史，不挪作外挂验收。并行修复可能已改变源码，但本计划hash明确是冻结输入，后续须绑定实际新源码/报告，不能拿r6对后续字节签通过或回写r6失败成成功。

## 本次静态检查与主线程交接

仅用Python JSON解析/目录对照，已确认32行、四族各8、96个state_profiles、planned_key唯一、asset_id全null，name/raw_title、默认尺寸、mount_mode/anchor、collision_default和damage描述逐项等于catalog。此为设计计划一致性，不是引擎、风格、实测part或契约校验。文档保存用末尾精确追加，不整写旧md。

主线程后续承接：修typed Array proxy及三类闭合/尖锥真实收分、镜像文字；补全逐part native JSON截面/missing_sectors/contacts实测；完成三按钮/图库拖放/上下文锁定与hook；在统一runner中分别执行当前内核/96静态重载/视觉/editor并绑定当前源码；另代理完成Blender衍生。验证、正式登记与最终contracts同步另行按授权实施，本任务不执行。所有未验项继续 `implemented_pending_current_verification` 或专属pending，不因计划冻结晋升。

## 最终当前交付：v002／r10b（完成后更新设计文档）

本节为当前签署，覆盖前述“pending、未hook、未登记、Blender derive_pending”的时点状态；前述r6、计划与中间失败保持原文，不能回写成功。**SEA-WORLD-R37/R38/R39/R40、SEA-WORKSHOP-R92、SEA-ASSET-R69/R70/R71/R72/R73逐条 implemented_verified_in_scope**，三个功能登记头全局partial不变，不新建重复FeatureID。

v001计划SHA仍 `246a8a68b51dcd7bf2215475a3c19cf919a377d89391c017cc87742aa7f53fe7`，未改其冻结源hash/asset_id/null/旧pending；用户明确授权新建 [v002/delivery_validation.json](../../art_source/scenes/building_attachments/v002/delivery_validation.json)，在父目录check后仅追加当前测量、登记事实和正式scoped exceptions。本次只改设计文档与该补充，不改code、registry、source_blend/source目录、memory或正式场景，不跑引擎/runner/contracts；下面全部是实读既有报告。

### 最终证据矩阵（非r9j分批）

唯一最终串行外层：`/Users/zyq/work/sea-work/verification/20261116-064110-attachments-production-library-r10b-c8e894/report.json`，SHA-256 `1f2ff1e29dd975f7e83a8a04d2b2a4d282670f503702cbce1e35b191f21504f5`。五项同一minimal隔离工程串行，不拼接不同批次冒充一批。

| 同批入口 | checks / failures | 签署范围 |
|---|---:|---|
| verify-attachment-library | 12103 / 0 | 正式制作库96冷load+96次隔离user重存重载，生产322文件前后hash一致 |
| building-attachments | 11122 / 0 | 32type/96默认状态+2改字=98实际样本，真实几何/文字/拒绝/存储与12物理case |
| editor-building-attachments | 328 / 0 | 117安装矩阵=96默认+21any另一挂载面、actual profile/foot/collision及真实自动GUI链 |
| editor-scene-assembly | 78 / 0 | 旧装配当前回归，不借历史78/0 |
| editor-workshop-upgrade | 1453 / 0 | 原房屋当前回归，不借历史1453/0 |

import及各项exit0、completion=true、unexpected=[]、source_consistent=true、source_changed_during_run=false；核心仅NaN非法输入负例触发JSON.stringify警告，不能写“零warnings”。r9j分开editor/scene不是最终签署源。GUI为Input.parse_input_event+warp_mouse自动事件而非人工；117矩阵/部分数学负例/房屋回编保存为直接调用，不能全称GUI。只首视口、gizmo轴拖动未测，生产Main未运行。

内层同批：`project/outputs/attachment_library_report.json`、`building_attachments_report.json`、`building_attachments_editor_report.json`、`building_attachments_all_mounts.json`。生产322文件保护不是313 runtime登记目标，两者统计域不同。

### 实测模型、物理与视觉

96默认单项 **140..1204 triangles**，总 **45376 triangles、136128 vertices、221 surfaces**，逐件2..4mesh/surfaces；glyph≤128、默认≤1800、>8字符长文≤3500门禁保留。mesh/surface计数与实际draw分列，单件真实SubViewport draw在r9c visual_report的 `captures[].viewport_draw_calls`，不能作Main总draw、GPU耗时或FPS。

五重件 `ac_roof_upflow/tank_round_short/tank_tower_cone/tank_horizontal/tank_rect` 默认collision=true，共15状态，layer256/mask0；全部96默认合计441代理。残存实体part逐段代理不封脚间/管腔/破口。12真实physics case含人物胶囊半径0.22m、高1.3m撞实体及高脚间可通；细管仅小胶囊通腔，不称人物通管。水下观赏true明确拒绝，requires_collision=false；外挂无Walk/导航/泊位/岸线/泡沫/boat/dive或正式Main地图职责。

原生视觉独立证据：`/Users/zyq/work/sea-work/verification/20261116-052700-attachments-v2-support-r9c-a4e161/report.json`，**507/0、131PNG**，原图目录同批 `project/outputs/building_attachments_visual/`；v2几何与当前r10b相同，Store后续保存修复不反写几何来源。此前8张拼图和review-close找到的8个悬空bug由真实v2支撑修闭，但本任务没有重新逐图目检，不以旧八图或partial witness签全接缝美术终审。

### 有意义的失败与修复简史

| 迭代 | 实际失败 / 已闭合约定 | 后续证据与限制 |
|---|---|---|
| r6 `20261116-032945-attachments-frozen-r6-1b18e2` | typed Array proxy、九项曲面闭合和镜像字；core7712/10，库9脚本错误，视觉13unexpected | 原失败完全保留；不能因exit0/96文件制造全绿 |
| r7 `20261116-035500-attachments-r7-afd959` | 数组/封盖/前轴镜像修复后core7732/0、库和visual484/0，unexpected=[] | 只签当时内核与视觉，不覆盖后来支撑悬空发现 |
| r8 `20261116-043047-attachments-lifecycle-r8-721272` | 增补事务/生命周期，editor102/0；旧装配另批回归 | 不是最终117矩阵或生产库冷load证明 |
| r9支持迭代 `051618…r9` → `052700…r9c` → `053030…r9d` | 初r9有2unexpected；review发现8个悬空bug后加真实carrier/轴支撑；r9c core11122/0、visual507/0；r9d editor186/5暴露any支点/拖放，后续完整editor仍有拒绝失败 | 修真实支撑、2mm三角薄带profile、cull/支点与拖放输入链，不用AABB/force放行；r9j分批通过留历史，不作最终 |
| Store编辑器临时保存 → r10b | WRITE临时备份路径带.tscn-random，ResourceSaver报ERR_FILE_UNRECOGNIZED=15；改READ_WRITE、get_path取实际路径并close。base/id/rev/file真实symlink负例、防覆盖与manifest-last补齐 | r10b同minimal工程五项全过、库322文件hash不变；不是忽略15错误或删失败日志 |

完整迭代报告均在 `/Users/zyq/work/sea-work/verification/`，上表只保有意义根因，不复制长日志；r6→r7→r8→r9→r10b不被合并为一次验收。

### 当前交互与使用步骤

1. Godot编辑器“场景装配”→“建筑外挂”，不F5/Main。打开本地Node3D场景，选择建筑Placement/Asset或安全本地宿主，点锁host。
2. 中文四分类按钮：招牌广告、机电通信、水箱管线、风管棚盖；全新/破损/残破三按钮是真实几何损伤，非SF-A/B/C。名称/type_id搜索，图库单击只选择并保留drag源；双击或“编辑组件”才打开参数。32种准确4×8目录见本文原目录表与ASSET spec当前表，未改名。
3. 招牌style选框式/块式/灯泡边饰。只支持A–Z、0–9、空格和.-!&，最多24字符；中文、小写、未知/超限明确拒绝并保原输入，不uppercase或丢字。原创粗stroke与carrier背托，独立字近背板是候选美术取舍；三态保原字符串，不要求所有笔画都断掉。
4. 拖图库组件到宿主真实可见mesh face，或点“贴到宿主”后点3D真实wall/roof表面。按材质cull筛表面，双面normal朝观察者；绿色ghost合法，红色拒绝roofedge/窄支撑/脚洞/邻墙穿透，不force。多脚/背支点来自实际tri极值2mm薄带，不用AABB角点；外偏0.012m、支撑误差4mm。自动GUI真drag已覆盖damaged/offset0.03m/angle7°，以及墙牌与roof箱surfaceclick。
5. arm后text/state/size/collision/mount变化取消旧事务、保输入；selected/hostrev/geometry变化按stale拒。需要重新发起放置，any跨wall/roof不能直接apply，须显式reproject。
6. Attachments与Asset兄弟、独立sea_attachment metadata、静态无脚本；新增/编辑/复制/删除/重新贴合用undo/redo。房屋换版后刷新旧Assetfree引用，只换Asset、其余当前transform保持，新revision提示检查贴合不自动位置重投；undo/reference恢复旧节点，不再生成。
7. Ctrl+S手动保存场景，不自动保存Main。独立候选另存新revision需Python3，以目录相对O_NOFOLLOW/O_EXCL原子写、manifest最后提交；无Python清楚拒候选导出，但Ctrl+S无此依赖。只hash+JSON重生成外部候选，不执行其TSCN。

### sourceplan补充：不能隐瞒的局部风格/接缝例外

本轮明确允许在v002补充中记录这些**正式scoped exception**，不是仅改metadata把未合规件冒充已验；旧v001仍字节不动。R71/R72签的是有例外的当前交付范围，不是整套SF全通过。

- `BAT-V002-EMBEDDED-SUPPORT`：`geometry.require_connection` 的 `embedded_support` 在字背carrier及少量连接轴/杆有意实际嵌入/重叠、clearance=0，是低面实体连接例外，局部覆盖v001禁止overlap/interpenetrate。与宿主挂面12mm普通clearance分开，不扩散成任意穿插许可。native contacts/真实witness保留，约450part有partial标记；完整contacts/全场穿插与总成审计仍pending。
- `BAT-V002-FUNCTIONAL-CONE`：水塔锥顶和蘑菇锥帽真实rho=1为功能收尖例外，不虚填为1%..10%；保封闭/真实厚度。普通box约3.5%、rod约4.8%收分，不借锥形例外让普通方盒零收分。
- `BAT-V002-ROUND-GLYPH-BEVEL`：十段圆截面/功能曲面与原创glyph bevel=0，普通box单段真实倒角；自定义箭头/拱牌挤出的逐part边处理例外留证，不声称全体硬边已倒角。低面预算、PaletteUV和四solar材质角色不取消。

### Blender派生与当前正式登记

作者源始终为原创native代码/配方/native JSON，Blender是可编辑派生，GLB为视觉交换不是runtime权威；未复用旧mesh，不伪称原生Blender创作。32份 `art_source/scenes/building_attachments/v002/components/<type_id>.blend` 各含三态view layer、1577可编辑part；`source/overview.blend` 实际重开96 Collection Instance/0 localMesh；`export/<type_id>__<condition>.glb` 共96。Godot(x,y,z)→Blender(x,-z,y)，source前+Y/上+Z，回Godot(x,z,-y)；不擅自补yaw或重写源目录。

源重开 `/Users/zyq/work/sea-work/building_attachments_source/v002/reopen_validation_final.json`：exit0/passed=true，32包/96态、UV90752面，最小512px²、16px安全边、32px跨度；96GLB无image/texture，max normal component error=0.00019996786362241892≤原阈值0.0003，位置阈值2e-6未放宽。四图Cycles CPU已完成，无GPU；不签动态HSV/灯光shader逐像素等价或完整风格。原source/derived_manifest.json里的未登记pending是派生时点，不修改其历史；GLB导出成功不等于版权clear，来源/商业法务仍pending。

当前实读 `assets/registry/ledgers/scenes.json` 已32个 `SEA-SCENE-BAT-*` 主记录、source index32new，正式source_path为32派生blend并回链原始native权威；分类scenes/furnishing、building_class=null、water_layer/role=none/none。`tools/apply_water_layer.py:FAMILIES` 添加BAT前缀none/none，属于资产分类helper，不自动视作水上建筑；路径在ASSET职责中承接，不新增Feature。实际运行制作库 `godot/scenes/components/facilities/building_attachments/v002/` 有96静态native场景和对应native JSON/recipe；初登记审计313runtime目标，后续librarytest/runner/policy追加由主线程定点维护，313不是当前全库资源数。

阶段实际为 `authoring_library_integrated_art_review_pending_not_world_installed`：已入制作库/主登记，不代表正式Main或地图接入。registry是只读事实，本次未改任一登记文件。房屋core八件文件SHA及完整diff SHA当前仍等冻结基线；Main SHA仍 `f246ee6aa3bd474ec20979783e0f0c9e606f99de1dcfe899400ccb686e8b1291`。

### 交付与尚未签署

- [审阅HTML](../../outputs/building_attachments_review_20261116/index.html)：真实131PNG、分类三态/文字/编辑器证据与来源路径。
- [审阅ZIP](../../outputs/building_attachments_review_20261116.zip)：20352407 bytes，约20MB。
- [源资产ZIP](../../outputs/building_attachments_assets_v002.zip)：8992971 bytes，约9MB；可编辑派生源与交换文件不替代native运行权威。
- [v002当前测量／局部例外](../../art_source/scenes/building_attachments/v002/delivery_validation.json)：包含每state测量原始报告路径及SHA，保v001冻结hash。

完整contacts/style/布尔/穿插审计、用户美术终审、来源/商业权属、真实性能/GPU计时、人工GUI/其它视口/gizmo轴、生产Main/Walk/shore/boat/dive地图及全工程contracts仍未签。全局partial保持。主线程之后实际sync/check再追加真实全库数字，本任务不执行、不预填历史488/489为本轮值。

## 主线程收尾：资源、内核保护与最终全库检查

- 32个新资产主记录、96静态场景、315个定点运行目标逐项核验；运行总数1873，源索引总数1105。未批量重算其他漂移，也未将制作库登记当生产Main装配。
- 实际sync489/check490 issues，均exit1；46功能/1105源/1873运行，421运行漂移、14源漂移、51历史断链及资产条款集合/派生索引问题保留。新增候选输出根 `scenes/workshop_attachments` 仅首次另存创建，通用res静态扫描将其判成缺输入；未创建空目录或注入样例骗过。完整 `/Users/zyq/work/sea-work/building_attachments_release/contracts_results.json` 与原始sync/check日志可核对，不以汇总Python进程exit0替代内部exit1。
- 主线程已实际核对最终五项r10b都exit0/unexpected=[]、source_consistent，原八件房屋内核与旧screen的冻结SHA/diff零变，Main仍 `f246ee6aa3bd474ec20979783e0f0c9e606f99de1dcfe899400ccb686e8b1291`。此保护基于本轮开始时工作区，不把上一轮未提交默认值修改误当成本轮外挂侵入。
- 最终v2原生八张组件墙与关键支撑近景已审；原镜像字、悬空字/阀轮/天线/线盒/帽/风管框缺陷在可见范围修闭。最终Editor1280与房屋外挂示例亦已审；全部131张逐张美术、人工拖动/gizmo轴、完整内部接缝、性能/GPU、商业权属及生产Main空间接入仍未签。
- 输出页面及审阅ZIP/资源ZIP含32类×96状态、真实报告、32三态Blend及96交换GLB；原图、源hash和ZIP CRC校验，静态链接验证不冒称浏览器实测。未提交推送、不发布在线、不改用户摆位。
- 交付补全最终门禁说明后重新组包，审阅ZIP现为20352790 bytes／170文件、SHA256 `54b89002608efd7789ee55dc9e311bce1d6798c8d0b48a02c5873fcbc7086440`；资源ZIP保持8992971 bytes／464文件、SHA256 `c336c9b20efbb4d52d4620a54e54e092d4cc313a828b6e7f83853a73384cfee2`。140张PNG、206静态引用缺失0、图像副本hash差异0、JavaScript语法exit0；浏览器实际交互未执行。315个目标是本轮定点审计集合，不能用整个scene_assembly目录全量计数混算成新增条目数。

## 2026-11-18 用户纠正：外挂放建筑工坊里编辑，而非独立一块

本节是现行设计/实施回填，覆盖11/16 R92“不许screen/UI页”和独立dock为主要编辑器的旧限制，历史原文、冻结时点与失败不删。沿GDD导航读完WORKSHOP/WORLD最新11/17后确认R93–R95空闲，新增 **SEA-WORKSHOP-R93（内嵌入口）/R94（完整作品双域事务保存）/R95（场景context、历史及输入防串）**；WORLD只细化已有R35、R37–R39，不新建重复Feature。

### 统一操作，不改房屋core或重制资产

- 生产主路径：建筑工坊→「外挂」，在同栋模型上编辑。PAGES append外挂page9、文件保8，视觉nav第二项；参数栏复用四分类/三状态gallery及style/text/buttons，中央复用同一个嵌入SubViewport。
- 原生gallery drag，或arm后点击真实wall/roof，沿用已有cull/法向、绿红ghost与真实支点算法，无force、不拿Y平面代替。选本栋列表/actual mesh pick；XYZ按钮步距0.01..1m，沿面投影后射线重验支撑，垂直支撑面方向明确拒绝，不伪装native gizmo。非法组件参数保成功模型、历史与所有目标缓存。
- 切页保11/17相机/导航；离开外挂页cancelghost，screen隐藏停timer/导航临时状态但保输入。dock主按钮改「到建筑工坊编辑外挂」，公开show_attachment_page直达；旧controller/panel内部API保留兼容维护，不再推荐独立页编辑。
- `godot/src/workshop/` recipe/session/generator/store及shell/union全部不动，editor adapter拥有新增编排；shared Store不改。独立32类×三态96项v002资产/Generator不重制。native无Script静态交付、layer256/mask0简化碰撞、水下拒绝true及无Walk/shore/boat/dive派生全保持，不冒称生产Main已安装。

### 真实Editor尺寸根因与原生drop链

隐藏DockTab仍参与minimum；scene_assembly长note/status在约17px窄宽wrap，content最小高2864，反向撑大编辑器。scene_assembly局部ScrollContainer min-height160阻断传播后，1920×969原生窗口实测screen2779→836、preview2548→605；preview split/sidebar只rightExpand。不是缩字/缩gallery或放宽阈值，原52%宽/60%高、18px按钮/16px正文、图库160均保留。三档尺寸后缀是请求值，实际native/Control矩形另记，不冒称三种原生窗口已按请求缩放。

普通Control drag receiver承接SubViewportContainer的target-control原生 `_get_drag_data→_can_drop_data/_drop_data` 链，DRAG_END查询 `gui_is_drag_successful()`；不是用直接insert制造落位。新自动GUI用Window.push_input+warp_mouse同步motion ack并查询真实drag状态；旧Input.parse事件未ack曾失败，改定向WindowGUI后再验，不称OSfocus已验证。

### 八文件完整作品：双域事务、安全读取与兼容

`editor_store.export_work_revision`复用父Temp→manifest→rename，所有八件在同一.tmp写入/验证、失败清理，不先发布房屋，不修改sharedStore或旧revision：

| 文件 | 当前职责 |
|---|---|
| building.recipe.json | 原房屋配方，不嵌外挂字段 |
| building.tscn | 原静态房屋壳体，不把外挂焊入 |
| catalog_snapshot.json | 原房屋目录快照 |
| candidate_manifest.json | 八件清单/hash、外挂声明/指纹与完整作品路径 |
| ledger.json | 候选记录，不是正式资产账本 |
| building.attachments.json | 当前layer+instance各12数Transform3D、稳定ID、metadata/recipe |
| building.attachments.tscn | 静态无Script外挂层 |
| building.work.tscn | 完整Work，Asset外链building.tscn + Attachments外链静态层 |

schema/完整anchor/JSON-safe/uniqueID/有限正determinant>1e-9、≤256实例严格验证；JSON canonical hash与metadata按1e-9定点。nativeTSCN Transform3D单独按有限float32回读容差 `max(1,abs(expected))*9.5367431640625e-7`，不能把此相对容差扩到metadata或JSON。`JSON.new().parse`拒绝badJSON而非触发引擎error。新声明缺件/hash/schema/wrapper错误拒绝，不静默降为空；oldlegacy原五件、无新声明/旁车才empty。外部只读JSON+可信Generator重建，不执行外部附加TSCN；刚生成的可信.tmp静态资源重载用于验证。

保存需apply/discard当前及其他有效installed/candidate的未应用输入，不自动吞。打开/恢复双域prepare全部成功才commit，坏草稿插件锁写保original recovery，失败保原双层/历史/输入。dirty覆盖有效installed和图库candidate；已删A缓存保undo但不阻save，undo恢复后再选A回到原未应用input。house→attachment→house按时间顺序undo/redo，只有显式navigate移动marker；手动A→B→A是新commit，不凭相同值猜undo，新分支清redo。

### 场景context与当前实例保护

新work候选带兄弟外挂；回编request_document传当前scene Attachments layer ctx snapshot，不读disk旧状态替代现场；打开成功才token+plugin/screen双instance binding，保11/17失效回调隔离。保存前fp确认现场未并发变化，否则“新revision已保存，实例未更新”，保newrevision、不自动写Main。同snapshot只换Asset，保layer及全部子node身份/当前transform；实际changed（含metadata）才双层同一undo。保Placement当前transform及其他同款、不重复append、不auto-reproject；场景手动Ctrl+S。

### 当前最终真实证据表

唯一最终五项串行minimal外层：`/Users/zyq/work/sea-work/verification/20261118-024220-workshop-embedded-attachments-reviewed-b8df68/report.json`。本次只读，不执行引擎或runner。

| 入口 | checks / failures | 实测方式 / scope |
|---|---:|---|
| editor-workshop-attachments | 323 / 0 | 新Window GUI原生drag/arm点击；参数直接准备/read-only pick与context/历史事务直接调用分列 |
| workshop-attachments | 129 / 0 | 逻辑direct_call：严格snapshot、原生重建、八件事务与坏旁车/legacy负例 |
| editor-workshop-upgrade | 1506 / 0 | 当前房屋/阳光房真实UV/槽选择与导航回归 |
| editor-scene-assembly | 159 / 0 | 当前装配与11/17生命周期兼容，不等于全部scenecontext都走GUI |
| editor-building-attachments | 328 / 0 | 旧内部API兼容；只修identity引用，不改旧断言、不推荐独立入口 |

import/五项exit0、passed=true、completion_marker=true、unexpected_errors=[]、每项source_consistent=true。独立switch `/Users/zyq/work/sea-work/verification/20261118-025131-workshop-embedded-attachments-reviewed-switch-af2d96/report.json` 为336/0，import/editor exit0、completion_marker=true、unexpected_errors=[]。交接65项GDS字节一致，本次完整隔离副本81/80个GDS（含tools/tests）也均与当前字节一致，不混计65为全副本。预期坏草稿保护Warning仍有，不宣称零warnings。

实际Glob核对内层：`project/outputs/workshop_attachments_editor_report.json`、`workshop_attachments_logic_report.json`，不是猜名 `workshop_attachments_report.json`。其余同批inner为workshop_upgrade_report/scene_assembly_report/building_attachments_editor_report.json。真实七PNG在同outputs：

| 图像 | 证据性质 |
|---|---|
| workshop_attachments_embedded_live.png | 实际嵌入视口，不是独立重取景模型图 |
| workshop_attachments_layout_1280x800.png / workshop_attachments_gallery_1280x800.png | 请求1280×800，实际Control尺寸见inner |
| workshop_attachments_layout_1000x700.png / workshop_attachments_gallery_1000x700.png | 请求1000×700，实际Control尺寸见inner |
| workshop_attachments_layout_860x600.png / workshop_attachments_gallery_860x600.png | 请求860×600，实际Control尺寸见inner |

### 有意义的失败简史（保留失败，不扩成长日志）

| 阶段问题 | 修正与签署限制 |
|---|---|
| typed Panel/anchor、JSON数字直接equality | 修实际类型/完整anchor与canonical比较；不把旧失败改为绿 |
| preview split/sidebar/rightDock minimum撑高 | 查真实Control父链，局部滚动隔断；不降字号/gallery/面积门禁 |
| 原Input.parse焦点motion未ack | 定向Window.push_input+warp同步ack/native drag query后重跑；不宣称OSfocus唯一根因或人工通过 |
| 旧328 identity | 修释放后引用，旧业务断言不删/不放宽 |
| review两个P2 | 显式navigate marker防手调回原值误判undo；只对有效目标dirty gate，已删缓存留undo不锁save |
| 少量fixture invalidrefs/退出泄漏 | 清理测试夹具引用后重新完整运行，早失败不隐藏、不借中间计数签当前 |

### 本次文档权限、交接与未测

仅Edit追加GDD、workshop/world各spec/ledger与本既有开发记录的2026-11-18节，登记头只加必要helpers/newtest及workshop-attachments/editor-workshop-attachments验证名。原owner与partial保持；runner路径已SEA-QUALITY不更owner。本次不写code/registry/art_source/memory/currentruntime，不跑contracts/Godot，不提交/推送。currentruntime15目标由另一任务处理，主线程实际sync/check后再追加真实数字，绝不预写旧门禁当新结果。

生产src/workshop、外挂Generator、Main/project无本轮改动；生产用户PID4359未由本任务关闭/操作，进程在本环境无法额外读取确认，不冒称新做进程验收。人工全轴/物理鼠标、其它viewport、OSfocus、生产Main、真实热重载/跨进程原草稿恢复、性能、license/art均未签。矩阵logic/scenecontext的直接调用不伪称GUI；七图存在不等于逐张艺术终审。审阅页 `outputs/workshop_attachments_embedded_review_20261118/index.html` 由另一代理制作，本任务不创建新大文档或制作该页；写入时尚未见文件，不签页面/浏览器交互已验。

### 2026-11-18 主线程最终交付与门禁回填

当前15项明确目标SHA/bytes一致、8项更新7项新增，1868非目标entry及metadata原字节不变，无新AssetID或96件素材重制。主线程复核323/0内嵌、129/0逻辑、1506/0房屋、159/0装配、328/0旧外挂，以及独立336/0切换的退出/完成/错误与源一致性；当前报告源与工作区无差异。已目检同批1280图库与860编辑图，整栋及水塔/横招可见，左栏滚动操作不重叠，不签人工手感或全部接缝。

全库实跑sync **539 issues、exit1**，无参数check **540 issues、exit1**，46功能/1105源资产/1883运行资源。无本轮World/Workshop新增条款或验证入口错；已有候选输出根 `scenes/workshop_attachments` 在首次另存前不存在，被扫描为缺资源的问题与其余漂移/断链保留，不造空目录或批量重签。真实原始日志及结果在工程外 `sea-work/workshop_attachments_embedded_20261118/contracts_{sync,check}.log`、`contracts_results.json`，记录包装进程exit0不替代内部exit1。

交付 `outputs/workshop_attachments_embedded_review_20261118/index.html`、7原PNG/5原JSON及同名ZIP；页面注明自动窗口输入与直接调用/未测范围，复制hash、静态引用和ZIP CRC已核验，未做浏览器交互自动化。房屋src/workshop、Main/project和公共资源未改，未提交推送，不替用户保存正式场景。
