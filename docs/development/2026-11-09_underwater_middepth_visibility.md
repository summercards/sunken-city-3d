# 2026-11-09 水下中层可见性

## 1. 范围与当前状态

本记录只覆盖 **SEA-OCEAN 渲染**与 **SEA-AMBIENT 表现**。本轮不修改 Dive FSM、保存/读档、鱼群职责、用户手动布局或其他玩法规则；不新增状态所有者，不改变登记头 / 登记 JSON，不执行 sync。

当前状态：专项与整合回归已通过。最终8个入口共4834项、0失败，详见第8节。低端设备、长期/连续性能、用户终审均未签。

关联条款：

- SEA-OCEAN-R30–R35（OceanR30+）
- SEA-AMBIENT-R32–R36（AmbientR32+）
- 跨模块契约见 `docs/architecture/module_contracts.md` 文末 2026-11-09 章节

## 2. 用户目标与明确排除项

本轮目标是解决和记录以下表现边界：

- 用户在 10–20m 处感觉过暗；
- 照片中的 41m 海面建筑出现切边；
- 修复正常游动时周围缺少浮游气泡/细尘的问题；
- 远景水下实体、海面与背景要连续雾化，不因 sky 判别把远建筑误当作天空；
- 环境泡、尘与角色移动保持世界空间连续，不粘在观察者身上。

明确不做：

- 不改 Dive FSM、DiveSession、输入、氧气所有权或过场事务；
- 不改保存结构、存档恢复或鱼群数量/职责；
- 不改 Main / ExistingModels / Base2 / 用户手动布局；
- 不把环境泡尘问题改写成鱼群或玩法问题；
- 不用节点计数、静态 shader 字符串或历史报告替代真实渲染验收。

## 3. 当前源码核对

本节是对主线程当前源码的只读核对，不是实现变更记录。

### 3.1 OCEAN 光照与表面

- `godot/shaders/uw_water_color.gdshaderinc:28-36`：`uw_irradiance_gain(depth)` 为 `mix(1.8, .34, smoothstep(5..120, depth)) * mix(.32, 1, sun_strength)`。
- `godot/src/diving/underwater_world.gd:210-235`：CPU `ambient_light_energy = 2.6 / PI` 固定；天空 cubemap 已负责深度和日照衰减，CPU 不重复乘深度日照。
- `godot/src/diving/sunroom_region.gd:165-181`：同样保持 `2.6 / PI`，不改曝光；实际相机 Y 转成米制 view depth 后注入材质、天空、fog 与氛围表现。
- `godot/shaders/uw_water_color.gdshaderinc:79-137`：`uw_surface_optics` 函数名保留兼容，但本轮产品读法为统一屏幕水色底、低频波纹与柔和日光；不能继续把它描述成完整物理 Snell 折射窗或独立反射色块。该口径覆盖旧 R26 的强窗口读法。

### 3.2 远景 fog 与 sky 判别

- `godot/shaders/uw_fog.gdshader:26-51` 与 `godot/shaders/sunroom_underwater_fog.gdshader:19-40`：surface match 依据 `abs(world_point.y - water_level)` 的 0.22–0.32m 连续带；远景 surface fog 在 140–190m 连续收口。
- Forward Reverse-Z 的 sky epsilon 已为 `1e-7`；Compatibility 后端保留反判。水面下约 0.68m 的远建筑不能因此被误认作 sky。
- 普通建筑仍走指数雾。透明材质与屏幕水雾统一使用 85m 密度曲线封顶；85m 只限制密度曲线，不把实际 120m 深度截为 85m。
- 水面尺寸曾试增到 4096 以排查切边，验证无效，当前已恢复 1280。

### 3.3 AMBIENT 泡尘与呼气

- 家园 `godot/src/ambient/sunroom_underwater_atmosphere.gd:4-29,90-119`：192 泡由 96 固定列 + 96 邻域泡组成，200 尘为邻域尘；邻域范围围 observer XZ ±12m、Y ±8m。
- 旧图 `godot/src/diving/uw_deco.gd:1-20,85-164`：96 泡由 48 vent + 48 邻域泡组成，180 尘为邻域尘。
- 两者的邻域均采用 world-space 连续 `mod` wrap，边缘 fade 1.5m，观察者移动不应拖动粒子世界位置；泡顶至少保持在水面下 0.77m。
- `godot/src/diving/sunroom_region.gd:165-178` 的 `Sunroom.set_observer` 读取 Camera；旧图 `underwater_world.gd:598` 的 `deco.update` 亦以 Camera 更新 observer。
- 家园/旧图环境粒子均走 Quad 共享 particles，不改成小 sphere。环境 soft contact 为 0.18m；`godot/src/ambient/diver_breath_bubbles.gd:42-56` 的呼气池固定 48，soft contact 0.08m，不与本轮环境泡预算合并。

## 4. 验收矩阵与条款

每一项必须由真实渲染图、像素/位置数据和逐图目检共同支持；结构存在不等于可见性通过。

| 条款 ID | 验收内容 | 当前状态 |
|---|---|---|
| SEA-OCEAN-R30 | 10/20m 暗水可读；灰样板亮度 >0.1；5/10/20/30/41/70/115m 灰样板序列单调递减；头灯/设施灯不被全屏曝光一起压暗 | PENDING，新批运行中 |
| SEA-OCEAN-R31 | 41m 海面建筑切边；四 yaw；surface match 连续；普通建筑指数雾；water−0.68m 不误判 sky | PENDING，新批运行中 |
| SEA-OCEAN-R32 | 220m、400m 黑盒远 fog 连续，透明雾 85m 密度封顶但实际深度不截断 | PENDING，新批运行中 |
| SEA-OCEAN-R33 | `uw_surface_optics` 只按统一水色底、低频波纹、柔和日光审阅；不以强 Snell/反射色块宣称完整物理折射窗 | PENDING，需逐图目检 |
| SEA-OCEAN-R34 | 10/20/41/80m × 四 yaw；正常 72° FOV；0.5m 移动后 world position 与渲染位置一致 | PENDING，新批运行中 |
| SEA-OCEAN-R35 | 记录失败批次、修复范围和未签范围；不得由旧样板或框架修复自动晋升 | PENDING |
| SEA-AMBIENT-R32 | 家园 192 泡/200尘、旧图 96 泡/180尘的分配与实际可见性分别核对；呼气池 48 不变 | PENDING，新批运行中 |
| SEA-AMBIENT-R33 | world-space wrap、observer ±12/±8m、边缘 fade 1.5m、泡顶至少水面下0.77m；0.5m移动不粘泡 | PENDING，新批运行中 |
| SEA-AMBIENT-R34 | Sunroom 与旧 deco 均从 Camera 设置 observer；环境 Quad / soft contact 0.18m，呼气 soft contact 0.08m | PENDING，需真实图和位置数据 |
| SEA-AMBIENT-R35 | 10/20/41/80m × 四 yaw、72° FOV、泡开关、尘开关；正常视野周围必须有可读浮游泡/细尘，不以节点数代替像素 | PENDING，新批运行中 |
| SEA-AMBIENT-R36 | 仅登记环境表现边界；不扩展 FSM、保存、鱼、布局、低端、长期性能或用户终审 | PENDING |

## 5. 当前失败批次与修复边界

最新定向失败批次：

`D:/projects/sea-work/verification/20261109-145508-underwater-targeted-depth-5b715a`

记录结果为 **179/32** 与 **436/35** 失败。该批次不得被描述为新成功，也不得与旧 195/0 混合计算。

已确认并修复的夹具/基础问题：

1. 夹具量化 box 与目标实体错配；
2. 节点入树前进行 global 赋值；
3. 远 sky epsilon 仍沿用过宽判别。

当前新批仍在运行，最终计数、exit code、unexpected、leak、报告路径、像素差分和逐图审阅结果均未填写。全局已知框架写盘与资源哈希/登记问题继续单列，不能折算为本轮 OCEAN/AMBIENT 成功。

`run_verification.py:392-396` 的 `write_project_config` 已改为写入临时文件后 `os.replace`，用于规避 Windows 隔离副本原地覆盖的 `PermissionError`；safe-delete 拒绝保留无删除。本修复仅记录 runner 写盘边界，不等于专项验收通过。

## 6. 旧证据的使用边界

- 旧 195/0 只是旧样板结果，不证明本轮 10/20/41/80m 四 yaw、0.5m 移动、72° FOV、220/400m 远 fog 或 41m 切边目标。
- 旧 195/8、195/4、195/1、timeout/exit-1 失败历史保留，不覆盖、不抹除。
- 历史家园/旧图环境泡、呼气、鱼群与 3C 通过记录只能证明旧条款对应批次，不自动升级本轮 R30+ / R32+。
- 全局框架写盘失败、sync/只读哈希门禁失败不作为本轮新失败的渲染原因，也不作为本轮新成功；两者均在全局边界单列。

## 7. 不签署项

本轮明确未签：

- 低端设备表现与性能；
- 长期/连续运行性能；
- 全昼夜、全路线和所有设备组合；
- 用户最终美术审阅；
- 完整工程门禁、全局资源哈希与登记派生索引；
- 任何超出 OCEAN 渲染 / AMBIENT 表现的玩法、存档或潜水状态机结论。

## 8. 最终验收

最终报告：`D:/projects/sea-work/verification/20261109-151955-underwater-middepth-signed-e09520/report.json`。8入口均exit0/PASS、unexpected_errors为空；不借旧195/0签本轮。

| 入口 | checks | failures | 渲染 |
|---|---:|---:|---|
| underwater-experience | 179 | 0 | headless，仅行为 |
| visual-underwater-experience | 436 | 0 | Vulkan Forward+，81张PNG与像素检查 |
| dive-control | 396 | 0 | headless |
| dive-maps | 338 | 0 | headless |
| sunroom-underwater | 85 | 0 | headless |
| sunroom-collision | 2824 | 0 | 真实物理 |
| dive-transition | 226 | 0 | headless事务/冻结/回滚 |
| visual-dive-maps | 350 | 0 | 真实十图与返回海面 |
| 合计 | **4834** | **0** | 不含历史批次重复计算 |

### 8.1 浅层提亮与深层递减

同一不透明灰样板实际亮度（显示RGB加权luminance）：5/10/20/30/41/70/115m分别为0.157384/0.157101/0.153103/0.142799/0.128497/0.080820/0.018255。10/20m均大于0.1；115m约为10m的11.6%。旧图10/20/41/60m为0.157101/0.153103/0.128497/0.098493。未提高全屏曝光，头灯/设施灯规则与耗氧不改。5→10m浅层仅下降0.000283，新增夹具用0.0001的8bit容差保留严格递减，其余跨度仍用0.0005。

### 8.2 环境泡尘与世界稳定

家园10/20/41m的正常72°FOV泡on/off变化像素分别924/1069/1359，尘为179/183/208；旧图泡339/505/426，尘67/50/86，均不是把相机贴到单泡拍摄。10/20/41/80m四yaw的周围12m内有效泡>=6、尘>=20及前方投影通过。

同t、observer平移0.5m后，家园泡87/87、尘167/167符合比较条件的元素世界位置不变；旧图泡45/46、尘150/150稳定，1个泡发生合法边界回卷。动态AABB、非奇异尺度、预算不增加和水面下边界通过。修正首版量化锚点导致整群跳位以及Y起点偏高，使用连续observer中心和绝对世界坐标mod wrap；边缘淡出1.5m，不把粒子挂到角色上。

### 8.3 切边与水面实拍

Forward+中`sky depth<=0.0005`把220/400m几何误判为空背景，导致远处楼体漏雾；改1e-7后两类地图黑box开关peak分别为家园0.003922、旧图0.0，低于0.025，water−0.68m样板也未被水面豁免。水面弱雾在140..190m完整收口，不再把收口系数乘ray.y而导致掠视无法全雾。

目检覆盖家园10/20/41m正常机位、低角远景、5/30m仰视、旧图10m街景及生产入水/返回图。原大片深黑与亮蓝圆弧被取消，周围细泡与颗粒可见，远建筑逐层融雾。生产水面近层仍保留低对比浪纹分界，不宣称所有角度完全无色差。强Snell窗已被统一水色波纹表达替代；不是完整物理折射/反射。试增4096m水面无效，恢复1280m且未移动任何用户建筑/基座/鱼。14份核心文件与最终副本逐字节一致。

### 8.4 失败历史与工具边界

保留179/32、436/35定向首批，以及此前195/1泡顶、波纹不足和PermissionError批次。夹具修正了连续场中心错用量化坐标、入树前global_transform赋值；未删真实失败断言。Windows隔离配置原地覆盖失败，runner改同目录临时文件写完`os.replace`，实际最终8入口成功；不改主工程project.godot或玩家存档，不再删除隔离数据目录。

专项通过不等于全工程门禁通过。低端GPU、长时性能、全昼夜/全路线、用户美术终审、独立Terrain3D海床仍未签。历史框架第二代存档写入失败与资产哈希门禁单列；本轮不改保护逻辑或批量重签未知资产。交付位于`D:/projects/sea-work/outputs/underwater-middepth-20261109/`。

### 8.5 文档门禁与收尾

已执行`check_feature_contracts.py --sync`：exit1、70issues；只读复查exit1、71issues（增加派生索引过期）。当前43features、1037source assets、1422runtime hashes，错误为既有/并行/本次资源hash漂移，无本轮新增条款缺失。脚本在有问题时不写索引，因此未成功同步；不批量更新未知资产hash来凑全绿。GDD保持LF，其余既有六份规格/账本/模块契约保持CRLF，新开发记录LF；无CRCRLF，条款OceanR30–35、AmbientR32–36完整成对，限定范围git diff --check通过。上方PENDING为实施过程中历史，本轮最终以第8节为准。
