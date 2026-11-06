# 2026-11-06 建筑5m套件与集中UI最终交付

## 范围

本记录覆盖整个任务：独立10件5m建筑套件、旧定义与存档兼容、实际高度/承载与楼梯拼接、集中建筑UI与键盘链、Service高空支撑安全、GroundSpace坡脚通行适配，以及隔离测试与真实渲染验收。最终222059 release-signed共13项全PASS/exit0；其中12专项合计2965 checks/0 failures，另`building-scale-reference`按62 rows/0 failures独立记录、不并入checks总数。机器汇总已生成于[本轮验证记录](2026-11-06_building_5m_verification.json)，十件资产已精确晋升运行集成验收状态；未知并行哈希不接纳。全局同步与无参检查已执行，具体未通过项见末尾，不以本功能专项通过代替全工程门禁。

## 当前规则口径

- 横向平台唯一为 5×5m。
- 墙与横梁跨度为 5m。
- 竖向构件与阳光小屋采用实测 5.086335m；不是 5m，也不是 5.1m。
- 楼梯为宽1.5m×水平进深5m，不是整件5×5m宽；共27级，每级爬升H/27。H为recipe总爬升，只应用一次，不重复scale；实际顶高=承载面底高+H。小家具/培养土保持各自recipe尺寸，不放大到5m。
- 楼梯要求同层无间隙并排，段与段首尾连续；不得产生空缝、重叠或悬空。
- 门洞为 1.85×3.1m。
- 允许 2.8m 旧结构与 5.086335m 实际平面混合；阳光小屋的位置与尺寸均不动，`main` 场景手动摆放不改。

## 实际文件与目录登记

- 新目录文件：`godot/assets/data/building_kit_5m.json`。
- 相关目录：现有定义 `godot/assets/data/building_kit.json`；本轮登记口径为总计 35 definitions、菜单可见 22 项：10 新结构、10 家具、2 培养土。
- 旧内容取舍：旧 deck、12 个旧结构定义、原稳定定义 ID、尺寸、坐标和旧 py2.8 数据保留；旧定义 `menu_visible=false`，仍可用于旧存档/API 展示与恢复。
- 根 v4 `building` 不增加新的必填 schema 字段；旧存档原数据无需迁移。
- UI 实际目录：`godot/src/building/ui`。
- 归位并保持 UID 的四个 UI 文件：`building_book.gd`、`recipe_card.gd`、`recipe_thumbnail.gd`、`demolition_tool.gd`。
- 集中表现入口：`building_view.gd`、`building_progress_presenter.gd`；承接手册、搬移、拆除、高度、自动、吸附、旋转、退出和返回链。
- 锤子只属于建筑模块表现，不在模式外常驻；集中Toolbar按钮沿现代码无键名，无常驻按键教程，遵循并行UI spec已登记的SEA-UI-R54–R57；保留失败灰因、选择轮廓、确认材料、安全细节和原返回链，不新增业务写入者。
- 适配依赖：`godot/src/navigation/ground_space.gd`，仅关联建筑坡面通行；导航所有权不转移给building，GroundSpace不拥有建造布局。坡脚sharedpoint及胶囊接触法线修复沿既有SEA-MOVE-R12/R15登记，不新增需求ID。

## 兼容取舍

保留旧 API、旧实例 ID、旧坐标、旧 deck/结构定义和根 v4 存档形状；新 5m 目录项通过现有目录识别，不把旧 2.8m 数据重写为 5.086335m。旧定义隐藏菜单但不删除，避免旧存档无法展示、验证或回收。存档校验失败必须在恢复/写盘前拒绝，保持现场、不覆盖有效备份、不重复收费。

## 最终签署状态

building spec/ledger 的 SEA-BUILDING-R30–R33 已完成最终回填；verification 精确名称为：`building-5m-rules`、`building-5m-experience`、`visual-building-5m-experience`、`building-ui-unified`、`visual-building-ui-unified`、`keyboard-building`。不得使用简写作为注册名称。UI ledger 的 SEA-UI-R53 已补最终证据，UI spec/ledger 的 R54–R57保持既有内容；save ledger/spec 的 SEA-SAVE-R18已补正式兼容证据；move ledger/spec已补既有R12/R15适配记录。

## 首轮失败与当前工作状态

- `20261106-160245-building-5m-first-2a11bd`：import 0，但 `newtestsparsefail`；保留为首轮失败记录，不能作为通过证据。
- `20261106-165720-building-5m-integration-741225`：`building-5m-rules`262/9、`building-ui-unified`65/3、`building-5m-experience`190/1；`building`、`building-join`、`building-decoupling`通过。该轮失败作为历史过程保留，已由最终签署报告覆盖，不作为最终状态。

以上首轮报告保留为过程证据；最终状态以签署报告与补充报告章节为准。

## 本次文档纠错时的中间进展（已被最终签署结果覆盖）

以下为最终签署前的中间状态，仅保留历史轨迹；最终结果见下一节。计数均按日志明确结果记录：

- `building-5m-rules`最新446 checks、0失败。
- `building-5m-experience`headless最新589 checks、0失败。
- 视觉验收批次曾为10项中8项PASS、2项旧fixture失败；fixture已适配，最终签署报告中的`visual-building-5m-experience`为597/0、`visual-building-ui-unified`为66/0。这里的历史批次描述不是verification注册名。
- `keyboard-building`40/0已通过；已有报告为`D:/projects/sea-work/verification/20261106-200446-keyboard-release-regression-eae88a/report.json`，来源见[UI账本](../features/ui/ledger.md)。该结果不代表`building-ui-unified`或`visual-building-ui-unified`已最终验收。
- `ground-space`坡脚sharedpoint与胶囊接触法线修复已由补充报告确认37/0；仅补充既有SEA-MOVE-R12/R15实施记录。

## 最终签署报告与范围

最终release签署报告：`D:/projects/sea-work/verification/20261106-222059-building-5m-release-signed-2a186b/report.json`。213331先签报告`D:/projects/sea-work/verification/20261106-213331-building-5m-signed-e9ca1f/report.json`保留为历史12专项2962/0；最新新增boat/shore预览3条，使integration53→56，并合批几何高度守卫。

| 检查 | 结果 |
|---|---:|
| `building-5m-rules` | 446/0，exit0 |
| `building-5m-experience` | 589/0，exit0 |
| `visual-building-5m-experience` | 597/0，exit0，real renderer |
| `building-ui-unified` | 66/0，exit0 |
| `visual-building-ui-unified` | 66/0，exit0，real renderer |
| `keyboard-building` | 40/0，exit0 |
| `kit-safety` | 94/0，exit0 |
| `building-kit` | 221/0，exit0 |
| `building-save-compat` | 37/0，exit0 |
| `building-integration` | 56/0，exit0；新增boat/shore预览3条 |
| `keyboard-farm-loop` | 606/0，exit0 |
| `minimum-loop` | 147/0，exit0 |
| `building-scale-reference` | 62 rows、0 failures，exit0；不是62 checks，不计入2965 checks合计 |

最新报告13个检查均`passed=true`、`exit_code=0`、`completion_marker=true`、`unexpected_errors=[]`；计数已逐项从同目录日志读取，非转述汇总。`visual-building-5m-experience`与`visual-building-ui-unified`的renderer为real，日志为Vulkan/Forward+、NVIDIA GeForce RTX4060Ti。最新机器汇总`visual_review`已记录`reviewed_by=main_agent`并将`source_directory`绑定222059新副本；四张真实渲染图的主线程目检记录及完整路径为：

- `D:/projects/sea-work/verification/20261106-222059-building-5m-release-signed-2a186b/project/outputs/building-5m-ui.png`
- `D:/projects/sea-work/verification/20261106-222059-building-5m-release-signed-2a186b/project/outputs/building-5m-parallel-preview.png`
- `D:/projects/sea-work/verification/20261106-222059-building-5m-release-signed-2a186b/project/outputs/building-5m-confirm.png`
- `D:/projects/sea-work/verification/20261106-222059-building-5m-release-signed-2a186b/project/outputs/building-5m-overview.png`

213331先签的44项src/test一致性保留为历史；222059新副本20个code完全一致，最新机器汇总`signed_source_comparison`现列44项且全部`matches_signed=true`。这是主线程对新release副本的独立核对结果，本轮只读证据、不运行比较脚本。本任务没有修改主场景手摆、阳光屋位置/尺寸或玩家真实存档。

Controller修复新平台preview漏传`origin=boat/shore`，与旧deck路径统一；new5m船上独立起点确认不再误拒，岸上隔空起板仍拒绝，预览取消不收费。新增3条集成断言，`building-integration`56/0。

高度守卫先于`20261106-221546-building-5m-live-height-contract-912216`独立执行，现已纳入222059 release。最新实际日志`[building-scale-reference] 62 rows, 0 failures`；同副本`project/outputs/building-scale-reference.json`记录actual=`5.08633422851563`、target=`5.086335`、tolerance=`0.002`、failures=0。`probe_building_scale.gd`从现场house底部与terrace顶部计算实际层高并和Catalog断言比对；这是真实跨资源守卫，不是只打印常量，后续几何与目录不一致会失败。

补充报告：`D:/projects/sea-work/verification/20261106-211435-building-5m-final-816d34/report.json`及对应日志，确认`ground-space`37/0、`character-space-save`10/0、`building-surfaces`80/0、`building-open-rules`122/0、`building-perf`239/0、`building-decoupling`62/0、`building-seed`5/0+`building-restart`11/0、`building-open-seed`70/0+`building-open-restart`8/0，均exit0、passed=true。`save-protection`exit0、passed=true，实际末行`ok=true protected=true unchanged=true separate=true`，不虚构checks数。`building-perf`9/25/45/100板单次求解实测0.247/0.512/0.963/2.289ms，仅表示该隔离样例性能，不外推低端GPU或任意规模。`ground_space.gd`坡脚sharedpoint/胶囊接触法线修复解决4.7cm stuck，不放宽WalkAction。P1高空孤台/循环支撑save绕过已修service rooted；无支持新旧high全拒，地面历史孤立合法。

### 范围与遗留

- `farming`35 checks中的2项仍为过时13地格/3床圆弧农场fixture失败；属于范围外历史夹具，不在本任务修业务。`keyboard-farm-loop`606/0不掩盖该历史失败。
- 211435旧报告`kit-safety`94 checks/7 failures、`building-kit`141 checks/8 failures、两项均exit1，保留为旧fixture未适配的过程失败；213331 signed已分别94/0、221/0、passed=true/exit0。不能把旧失败挪到signed报告，也不能抹去旧报告。
- 功能登记头仍为implemented（已实现待完整验收），因为触摸/手柄、低端GPU、任意规模与层数尚未覆盖；不影响R30–R33本范围专项通过。
- 全局featurecontracts已执行：`--sync`退出1、4问题；无参退出1、5问题。四个根问题为水下建筑派生视图过期、`SEA-DECO-ANIMAL-FISH-SCHOOL`源哈希漂移、`water.tres`运行哈希漂移、`main.gd`并行运行哈希漂移；无参检查另报派生功能索引未同步。脚本约定有根问题不写索引，故未手工强行同步，也未批量重算未知哈希。本功能无残留路径/条款/哈希错误。
- 架构检查通过：17个独立规则/存储服务、0问题；`git diff --check`退出0，仅存在Git正常行尾提示。
- 10件资产已使用带本批全部运行哈希的机器签署清单，经专属工具晋升`runtime_integrated_verified`；旧源资产不晋升或重算。资产账本R54已回填。
- 机器汇总`docs/development/2026-11-06_building_5m_verification.json`已创建，主报告已指向222059 release，记录13项全PASS、前12专项2965 checks/0 failures及另列62 rows高度守卫，保留补充通过项、源/运行哈希、未执行项、原始失败和全局门禁结果；新release副本20代码文件一致及44项src/test全部匹配均已记录，旧批次证据独立保留。工程外交付总览位于`D:/projects/sea-work/building_kit_v002/outputs/index.html`。