# 2026-11-20 · 白盒复用原版白天海面视觉

## 开工基线

沿原白盒任务串行。约 01:43–01:47 CST 重读 [GDD 功能导航](../../GDD_V1.0.md#feature-control) 与 [OCEAN](../features/ocean/spec.md)／[账本](../features/ocean/ledger.md) R47/R48、[WORLD](../features/world/spec.md)／[账本](../features/world/ledger.md) R44/R45、[DIVE](../features/dive/spec.md)／[账本](../features/dive/ledger.md) R56/R57/R65/R76。分支 `codex/feature-controlled-structure`，HEAD `ceae1b03cce77935bd674c9374429a183dc28569`；无未解合并。开工白盒场景、马达、装配、水面和旧潜水地图脚本与上一批 `013502` 副本一致，并发旧差异不回退；文件清单、哈希及契约基线在工程外 `sea-work/sea-3c-20261119/visual-before.*` 和 `visual-contracts-before.log`。

## 先看真实画面，再补输入

`20261120-015130-sea-optics-before-646295` 使用 Metal Forward+、1280×800 窗口，选择 31° FOV、17.2 m、相同俯角和朝向，相对于两场景各自旅人取景；旧完整入口固定 09:00、禁自动存档。原家园建筑与白盒平台不是同一内容，不能直接把整张画面的像素差解读成水色误差。随后白盒修前、修后则在同一场景、同镜头及同测试水面相位对照。

- 白盒修前已有同一原版水材质/天空效果，反射开关和波相变化均实际改变像素，并非缺水面着色器。原版有岸线距离图和可见船壳泡沫，白盒修前 `shore_enabled=false`，平台只有原有深度接触表现，没有对应的岸线泡沫带。两边浪尖强度均为 0，不把零强度设定说成浪尖泡沫。
- 原版主光能量 0.54 且有三盏低强度补光；白盒原为 1.15 单光，坡面与船体更亮，阴影方向也不一样。复用旧完整入口固定上午灯值和影子设置，不启动 DaylightRig 或旧时钟。两场景共享 `world_env.tres`／`water.tres`；不改共享材质、着色器或海面波幅。白盒仍用 0.55 波幅，旧完整场景 1.2，不把泡沫补齐等同于波幅统一。
- `godot/src/rendering/minimal_ocean.gd` 仅对原材质运行副本补水位、后端深度标志和发光增益，用原岸线图算法处理实际渲染的平台、坡脚和三个木块。512² 距离图仅在白盒启动生成，不写用户缓存。`shore_distance.gd` 增可选 CSG 可见网格采样，默认关闭，旧入口不变。原 `boat_water_contact.gd` 的船壳投影提为只读方法；白盒读取实际船壳可见网格及其姿态，不改船只控制、碰撞、桨叶入水或尾迹。灯与两个渲染节点引用挂在 `main_minimal.tscn`；不拉入旧 Main、玩法场景、鱼群或水下几何。
- 区分潜水规划和实装：DIVE-R56/R57/R65 的候选镜头/轻潜水镜/统一体验交接不因观看参考图转正。既有 R76 的十图共享控制器仍由原地图拥有。旧 `zone1.tscn` 由 `underwater_world.gd:150` 初始化本地环境、`uw_sky.gdshader` 和 `uw_fog.gdshader`，原 DiveSession 管海面切换；不把雾通道挂进正在航行的白盒。`visual-dive-control` 对既有控制器/地图 **494/0**、exit 0；目检 `dive-control-zone1.png` 的青蓝远雾、浅层水面、水下建筑与射光。这是独立参考，不是白盒停船下潜、返同一船或环境恢复的实窗验收。白盒未接 zone1，这三项留待集成回归；未改潜水地图、材质或控制。

## 实窗证据及边界

工程外 `sea-work/verification/<批次>/report.json`、`project/outputs/`。`015130` 白盒原面 **14/0**，旧版近似机位 **18/0**，zone1 所在专项 **494/0**，三个及 runner 均 exit 0。`20261120-015940-sea-optics-final-1c24c7` 白盒海面 **26/0**：保留反射、时间相位和关闭泡沫 A/B，独立检查旋转木块、坡脚 CSG、平台轮廓及船壳。以每 8 像素取样、RGB 总差 >0.09 为指标，白盒修前/后反射分别影响 494/463 样点、波相分别 860/1406；修后以关闭该通道对照，岸线泡沫影响 652 样点、船壳接触影响 140 样点。旧版的 659 岸沫样点来自不同几何，仅证明旧通道有效，不作为白盒像素目标。

目检同名 `surface-visual-minimal.png` 前后与 `surface-visual-legacy.png`（基线），白盒修后坡脚与平台周围出现原版白色水线，光比更接近上午参考。已目检修后与 `surface-visual-minimal-hull-off.png` 的船壳接触对照；船壳变化较细，单看全幅图不如 A/B 像素检查明显。静态截图不替代实际操作或性能测试。

同一最终批次海上无头 **123/0**、实际窗口 **157/0**，陆地无头 **35/0**、实际窗口 **42/0**，旧船接水 `boat-water-contact` **41/0**；连同视觉专项六项及 runner 均 exit 0。航行、靠泊和 E 是窗口脚本输入，未签真人键鼠。未测其他渲染后端、发行性能、白盒潜水交接或真档。

位置检查 16 项、0 警告、exit 0；`git diff --check` exit 0。全局契约 `--sync`／无参检查分别 586／587 项、exit 1／1；失败项及出现次数与本批开工前一致，派生索引未写回。只更新白盒场景对应运行清单摘要，不刷无关哈希。旧完整场景、项目配置、共享水材质及天空资源、白盒船控与装配、原潜水地图脚本逐字节未变。

对照图： [原版海面参考](../../../sea-work/verification/20261120-015130-sea-optics-before-646295/project/outputs/surface-visual-legacy.png) · [白盒修前](../../../sea-work/verification/20261120-015130-sea-optics-before-646295/project/outputs/surface-visual-minimal.png) · [白盒修后](../../../sea-work/verification/20261120-015940-sea-optics-final-1c24c7/project/outputs/surface-visual-minimal.png) · [旧 zone1 水下参考](../../../sea-work/verification/20261120-015130-sea-optics-before-646295/project/outputs/dive-control-zone1.png)。
