# 2026-10-29 初始六格种植区

按用户要求，原浅水平台六格作为新游戏自带种植区，与DIY种植区共用操作站位和种植流程。主条款SEA-FARM-R12；关联SEA-BUILDING-R05/R16和SEA-SAVE-R08。保留原场景、六格位置、模型及`platform_plot`、`platform_plot:1..5`稳定ID。

## 已确认的修复前差异

- FarmField已登记六个规格，但Farm.register_plot只登记规格，首次未操作的新局快照可能只有第一个基础ID的空状态。另五格依赖后续操作或恢复才补齐。
- DIY种植格有格内/侧边`approach_points`，固定六格没有。缺少操作点时接近流程回退到距中心1.35米的目标，边缘格可能选择平台最外边。
- 隔离探针覆盖六格×7起点，复现第一格从船上选种后角色停到平台最西边而未播种；另41例完成。该证据不能解读为原来六格在任何位置都完全不可操作。首轮探针的两个DIY造景断言因未按0.1米吸附而失败，属于测试夹具问题，保留原日志，不当成产品故障。

基线证据：`D:/projects/sea-work/verification/20261029-232350-fixed-six-access-baseline-rerun-4e29bc/project/outputs/fixed-planter-access.json`。

只读核查玩家档确认角色在初始平台中心且新增木板陆路连通；旧档六格作物状态存在。测试只使用隔离用户数据，未覆盖玩家存档。

## 正式修改

| 文件 | 改动 |
|---|---|
| `godot/src/farming/farm.gd` | 注册地格时只为缺失ID补空状态；已有状态不改，重复注册不重置作物。固定与动态地格都在登记时进入快照。 |
| `godot/src/building/building_space.gd` | 抽出以实际矩形与阻挡声明为参数的操作点计算，固定与DIY复用同一算法。 |
| `godot/src/building/building_world.gd` | 固定六格每次布局同步也更新格内/侧面操作点，以原位置和实际缩放计算占地；原有显式阻挡声明和外围保护保留。 |
| `godot/src/player/actions/approach_action.gd` | 有操作点的船上接近从当前泊位站立点预筛陆路，最后仍由start_walk检查同一地面、靠泊距离与航行状态；不把船座位当成陆地起点。 |

Farm仍是作物状态唯一写入者；位置与操作点由场景投影派生。初始六格不收费，初始种子仍为3包；现有作物、DIY布局、费用工期、出货和存档格式保持。旧档由Farm原恢复流程按当前规格补空并覆盖已保存作物，不新建另一份初始布局或更换ID。

## 验证

所有运行使用`scripts/run_verification.py`，在Autoload之前隔离用户数据。当前专项：

| 验证 | 当前结果 | 证据 |
|---|---|---|
| `initial-planters` | 247项、0失败、退出0，无预期故障及非预期脚本/引擎错误 | `D:/projects/sea-work/verification/20261029-232730-initial-six-real-mouse-fixed-19c00c/report.json` |
| `visual-initial-planters` | 原生渲染250项、0失败、退出0，无预期故障及非预期错误 | 同上；输出`initial-planters-six-ready.png`、`initial-planters-harvest-menu.png`、`initial-planters-restored-six-ready.png`已目视核查 |
| 玩家档只读副本探针 | 40项、0失败、退出0，无预期故障及非预期错误；六格从保存位置可达、逐格接近取消；旧番茄生长/水分/续茬及全部DIY作物记录保持 | `D:/projects/sea-work/verification/20261029-232738-original-six-player-slot-field-check-02e5c7/report.json` |
| `farming / modules / building-space / building-integration / building-open-rules / building-open-seed / building-open-restart / walk-on-planters / character-space-save` | 9组全部PASS、各退出0 | `D:/projects/sea-work/verification/20261029-232435-initial-planter-registration-regression-c81a37/report.json` |
| 最终接近修正后：`building-integration / building-open-seed / building-open-restart / farming / walk-on-planters / dock-seed / board-click / unreachable-menu / interact-focus / character-space-save / minimum-loop` | 11组全部PASS、各退出0，无预期故障及非预期错误 | `D:/projects/sea-work/verification/20261029-235452-initial-six-final-adjacent-a17beb/report.json` |
| `visual-building-diy / visual-plot-shipping` | 原生渲染与真实鼠标/按键，28项与61项全过、各退出0，无预期故障及非预期错误 | `D:/projects/sea-work/verification/20261029-235549-initial-six-final-visual-regression-1e952b/report.json` |

六格专项用真实鼠标点击模型、选择「种植」和二级「生菜」，接近后经Interactor完成；六格逐一浇水，18次浇水含一次正常「补水并浇水」，三晨后逐格显式收获。另覆盖新局原3包种子与六格空状态、旧档只含一格时补齐、重复FarmField.build/register不改作物、模型实例与ID不变、成熟保存恢复。测试补充种子只发生在隔离夹具，未改新局物资。

过程失败独立保留：`20261029-232606-initial-six-real-mouse-e2a512`暴露增加操作点后船上预筛仍使用船座位的缺口，同时测试首版只寻找「浇水」未识别水壶空后的「补水并浇水」，后续成熟/收获断言级联失败。修正正式接近起点与测试菜单选择后，上述两种模式均全过。玩家档探针首轮`20261029-232658-original-six-player-slot-d2cd7e`有13项比较失败，源于JSON浮点数与运行时整数做整字典比较；改为逐字段数值比较后40项全过，未为此修改产品状态。

本轮未改初始物资、配方价格、费用工期、作物天数/奖励、出货规则、资产内容或场景布局；未做设备/发行包验收。旧默认范围的历史失败不由本专项替代。

静态收尾：架构边界、功能摘要同步及无参契约检查、`git diff --check`分别登记退出码于工程外`final_checks.json`；当前正式脚本相对上轮交付仅为上表4个文件，逐文件差异与哈希在同一审计目录。继续使用原存档，无需创建新游戏。

修复前源码与哈希：`D:/projects/sea-work/audits/2026-10-29-initial-six-planters/`。
