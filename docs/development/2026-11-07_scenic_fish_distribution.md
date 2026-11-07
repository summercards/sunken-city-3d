# 2026-11-07 纯观赏小鱼扩布到其他海域

## 用户意图与范围

用户指出上轮鱼群仍集中在阳光房周边，要求把同款纯观赏小鱼布置到其他海域，明确不是可捕鱼的鱼点。归 SEA-AMBIENT-R22，资产复用与来源按 SEA-ASSET-R50 的既有链路登记。

本轮不修改捕鱼点、鱼ery业务、资源产出、船只阻挡、存档字段、建筑摆位或海水美术参数。新增源为可编辑摆位场景，不新增几何，不伪造 Blender、GLB 或优化记录。

## 已实装

稳定场景：`godot/scenes/decorations/animals/scenic_sea_fish_schools.tscn`。
正式树：`World/Environment/Animals/ScenicSeaFishSchools`。
通过既有 `fish_flock_group.gd` 和 Main 的 Animals 注入链读取真实主水。
全部复用阳光房 `fish_school.tscn` / `decorative_fish_school.gd` 的 surface/flat 小鱼、三色材质、身体与尾鳍动画；体型0.46–0.5，不扩大捕鱼鱼模型冒充观赏鱼。

| 节点 | 海域 | 条数 | 散布半径m |
|---|---|---:|---:|
| StationOuter | 铁道站外海 | 6 | 1.8 |
| AquaOuter | 浅水台东侧外海 | 10 | 2.8 |
| HomeSouth | 家园南侧 | 8 | 2.2 |
| RanchOuter | 屋顶牧场外海 | 12 | 3.4 |
| CityCanal | 旧城水道上方 | 14 | 4.2 |
| CityWest | 旧城西侧 | 10 | 2.8 |
| CityEast | 旧城东侧 | 14 | 4.2 |
| RestStopOuter | 旧驿站外侧 | 8 | 2.2 |
| NeonOuter | 霓虹街外围 | 10 | 2.8 |
| KioskOuter | 新补给站外侧 | 6 | 1.8 |

共98条，原阳光房6/10/14三群与旧Home/East/West各10条均保留，相关Animals可见观赏鱼合计16群158条，不含捕鱼鱼群或潜水地图。
巡游半径与散布分开：轨迹平面约为 `个体散布 + 旋转椭圆巡游(orbit_radius × squash × size_scale) + 侧摆`，不是把所有鱼固定到一条圆周。鱼最高点相对实际浪面保持0.5–1.5m沉深。

## 实测证据与限制

主要报告：`D:/projects/sea-work/verification/20261107-144832-scenic-fish-release-24e68f/report.json`。

| 项目 | 断言结果 | 统一runner最终状态 |
|---|---:|---|
| 正式import | exit0、无导入错误 | PASS |
| visual-scenic-fish-structure | 4750 checks / 0 failures | FAIL：退出lambda/资源错误 |
| visual-scenic-fish-distribution | 416 checks / 0 failures | FAIL：退出资源错误 |
| sea-fauna | 2195 checks / 0 failures | FAIL：退出资源错误 |
| water-layer | 1595 checks / 0 failures | FAIL：退出资源错误 |
| minimum-loop | 147 checks / 0 failures | FAIL：退出资源错误 |

不得将上述断言0失败、进程exit0误写成完整runner通过。主要退出错误为 `4 resources still in use at exit`，结构脚本另有两条 `Lambda capture ... was freed`。后续并行NPC/shop/save脚本继续改动，verbose诊断轮 `20261107-150808-scenic-fish-lifetime-diagnostic-a1fe5d`出现新编译错误并超时exit124，不作为当前集成通过证据。本轮没有屏蔽日志、修改runner错误判定或替换存档规则。

本轮为解除初始编译阻塞，仅在Main的forward3、NPC graph的copy、Shop的row/added补明确类型，未改变靠岸、NPC、购买业务；这些脚本属于并行工作区，后续文件变化不由本轮签署。

### 已获得的限定证据

- 10群98条实际加载；独立PackedScene重开身份、数量、唯一ID、与阳光房同款网格/材质、无捕捞属性、无交互组等断言成立。
- 每群33时刻采样；鱼最高点实际沉深0.555909–1.491927m；身体与相对尾鳍都变化。
- 1245近水位真实几何实例、22638鱼心/头尾等短段探针，相交0。属于离散时刻表面交叉检测，不冒充连续扫掠或完整体积碰撞证明。
- 20张真实水面12m/18m近景，逐群固定相位fish-on/off差分，鱼相关像素509–2488；未隐藏水面、未放大小鱼。
- 3张77.8m环境图有53–91个鱼相关像素；远景仍很小，不承诺每条都可辨。
- 主任务目检十处至少一张近景，确认同款小鱼可见；AquaOuter和CityEast画面边缘还存在原有大体型带环捕鱼目标，那不是本轮新增鱼。新增鱼为分散的小型无环彩色鱼。旧捕鱼目标未被隐藏或删掉来美化验收。
- 摆位台账检查：3 structures / 0 warnings。

## 登记与回退

AssetID：`SEA-DECO-SCENIC-SEA-FISH`，版本v001；分账本由 `ledger_index.json` 路由到scenes。
已按真实状态登记 `source_scene_registered_runtime_final_pending`、`runtime_integrated=false`、`runtime_verified=false`，同时标记正式场景已挂载；依赖、源/运行SHA、失败日志和后续并行SHA差异保留。不是否认场景已实装，而是禁止把未完成完整验收升级为verified。

登记脚本：`tools/register_scenic_fish_distribution.py`。严格晋升仍要求当前snapshot一致、全部目标与import通过。pending模式不会绕过严格模式门禁，不刷新共享鱼源旧hash；原鱼源已有source hash漂移单列warning。

回退仅移除 `surface_animals.tscn` 本轮一个ext_resource和一个ScenicSeaFishSchools实例，不覆盖原鱼群、鲸或建筑。原文件历史与本轮增量patch记录于工程外 `scenic_fish_distribution/runtime_registration.json`。

## 待完成

- 并行NPC/shop/save稳定后重新跑import及全部相关运行目标，通过后再晋升登记。
- 当前完整主场景与最终退出生命周期尚未通过，不以限定图像/断言结果替代。
- 商业素材溯源、用户美术终审与跨设备性能仍pending。
- 已执行全工程契约同步与无参复核，均exit1。最终41功能/930源资产/1250运行哈希：sync11问题，无参check另含派生索引过期共12问题。分别为SHOP未知shop-modules验证键、旧共享鱼源哈希、items/water/Main/walk_area/actor_controller/character/save_game/save_schema运行哈希、NPC dialogues内容ID漂移。本轮新增鱼资产的building_class=null及来源索引已修复；未刷新上述旧源或并行哈希。
