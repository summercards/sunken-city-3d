# SEA-CAMERA · 相机跟随与手动控制

[主文档中控](../../../GDD_V1.0.md#sea-camera) · [本功能账本](ledger.md)

设计修订：r1（2026-10-23 工程拆分，未更改玩法数值）。所属系统：3C。
范围来源：主文档保留的全局设计、拆分前文档与当前代码核对；下面明确区分目标与实现边界。

## 功能目的与边界

正式或规划入口：跟随玩家，右键拖拽、滚轮、C 面板。

本功能以这一玩家行为或工程交付闭环为管理粒度，内部操作作为设计条款逐项承接；不按脚本数量拆功能。跨功能前置和关系由主文档本行统一维护。

## 设计条款与验收标准

| 条款 ID | 目标规则 / 应验证的行为 |
|---|---|
| SEA-CAMERA-R01 | 自动跟随角色，手动观察时尊重玩家控制意图，允许恢复跟随。 |
| SEA-CAMERA-R02 | 缩放和距离预设有边界，交互 UI 不应误触世界导航。 |
| SEA-CAMERA-R03 | 海面与潜水切换后只由对应相机控制视口。 |
| SEA-CAMERA-R04 | 镜头状态和动作分别维护，通过输入端口判断模态；读档、上下船及潜水结束不得遗留拖拽状态。 |
| SEA-CAMERA-R05 | TitleCamera独立保存并接管临时开始机位；游戏镜头处理暂停，点击进入后1.1秒插值到原姿态/FOV再交还OrbitCam，不能将开始机位存为角色位置。 |

## 所有者、接口与数据

状态/交付所有者：**OrbitCam / follow、manual 状态**。正式代码和资源入口：

- [godot/src/camera](../../../godot/src/camera)

读取上述所有者的公开查询，修改通过其命令或交互入口；事件由拥有该状态的对象发出。具体公开方法、信号和持久化字段见本账本的接口清单。原有稳定 ContentID、场景 ID 和存档键保持不变，重命名须另做迁移。

共享资源的所有权以被依赖功能为准。本功能引用它们，不复制背包数值、资产记录或其他功能规则。规划中的接口尚无实现时必须先补契约再编码。

## 当前实现与待完成边界

镜头拆为 follow/manual 状态和 pan/orbit/zoom 动作，UI 阻断经 input_blocked 回调注入，读档恢复跟随。跨分辨率与目标设备手感仍需验收。

2026-10-27 接口：resume_follow / suspend_follow / restore_follow / setup / set_distance；状态见 camera/states，动作见 camera/actions。

详细所有权、状态转换与扩展方法见 [模块接口约定](../../architecture/module_contracts.md)；实测范围见 [框架交付记录](../../development/2026-10-27_modular_framework.md)。原目标中尚未实现的内容保持登记，不因架构拆分自动升级完成度。

## 验收入口

通过主文档定位本功能后执行账本列出的检查。正常、拒绝、取消/重复、存档恢复均按适用范围记录；真实渲染、听验和设备项单列。本次使用统一 runner 的隔离存档项目，不能直接拿玩家存档做测试。

## 来源与交付记录

- [拆分前完整主文档](../../archive/pre_split_20261023/GDD_V1.0.md)
- [拆分前功能计划](../../archive/pre_split_20261023/功能重做计划.md)
- [本次工程拆分记录](../../development/2026-10-23_feature_split.md)
- [godot/CAMERA_FOLLOW.md](../../../godot/CAMERA_FOLLOW.md)

2026-10-27 接口收口：公开姿态入口：apply_pose / orbit；Main 不再调用镜头私有姿态方法。

## 2026-10-28 开始构图调整

| 条款 ID | 规则 |
|---|---|
| SEA-CAMERA-R06 | 开始镜头保持原视线方向、31°FOV、64m距离和水平构图，只沿自身视平面向下平移3.4m，使房屋主体上移约画面高度的10%；不得改动房屋位置或把开始机位写入正式玩家镜头。入场仍按R05恢复原游戏姿态。 |

[本轮实景](../../development/2026-10-28_title_composition_saved_time.md)。


## 2026-10-28 右下锁定角色图标

| 条款 ID | 规则 |
|---|---|
| SEA-CAMERA-R07 | 右下人物定位圆形图标点击恢复resume_follow，跟随真实player全球坐标；Main将follow_enabled经HUD.set_follow_locked同步为图标颜色。手动拖动保持原接管规则，图标同步为自由观察态，再点恢复。点击图标不向世界发送移动目标，不改变原角度、缩放和距离规则。 |

[本轮交付](../../development/2026-10-28_hud_date_camera_lock.md)。

## 2026-10-29 自由海域镜头

| 条款 ID | 规则 |
|---|---|
| SEA-CAMERA-R08 | 正式自由海域pan_bounds为空，跟随和手动平移不被旧154m矩形夹住；显式有面积的场景边界仍可生效。缩放、俯角和UI模态规则保留，合法远处读档恢复跟随。 |

[本轮交付](../../development/2026-10-29_open_ocean_building.md)。

## 2026-10-29 角色真实高度跟随

| 条款 ID | 规则 |
|---|---|
| SEA-CAMERA-R09 | follow模式按真实角色高度加0.7m跟随，不再被旧target.y≤10夹住；manual仍保留0–10m观察高度。原角度、FOV、距离、阻尼、缩放、手动接管、UI阻断及开始镜头不变。 |

[本轮交付](../../development/2026-10-29_character_physics_framework.md)。

## 2026-11-02 新旅程与角色档案

| 条款 ID | 规则 |
|---|---|
| SEA-CAMERA-R10 | 未完成新档由独立ArrivalCamera在1.8秒内从标题拉近码头人物，向海取景避开栏杆，保留右侧编辑区；创建/编辑完成或取消后1秒恢复此前Transform/FOV/near/处理模式。日常OrbitCam参数不重写，外观旋转仅作用表现根。 |

## 2026-11-05 缩放上限 77.8 米

| 条款 ID | 规则 |
|---|---|
| SEA-CAMERA-R11 | 玩家可拉远的最远距离固定为 **77.8 米**（`zoom_max`），即旧区间 9~190 米从最近端算起的 **38%**（`9 + 0.38 × 181 = 77.8`）；滚轮、捏合、C 面板滑杆与「最远/远景」预设一律不得越过 77.8 米，下限 9 米不变。开局机位仍是 54.25 米，不随上限改变。验证与宣传工具需要更宽机位时，只能在自己脚本里临时抬高 `zoom_max`，不得改玩家上限，也不得把工具机位当作可达范围。FOV、俯角、阻尼、跟随/手动接管、UI 阻断与存档字段不变。 |

定值依据：主人指认截图那一档就是最远。把该截图与同构图渲染做连通块量尺（同一算法跑两边，系统偏差抵消）：
参考图里小屋宽占画面 **28.3%**，78 米渲染 **29.1%**、90 米 **25.1%**、54.25 米 **42.0%**，
77.8 米即落在实测最贴近的一档，与「38%」这一读数互相印证。

[本轮交付](../../development/2026-11-05_camera_zoom_max_38.md)（文件名沿用首次落地时的路径，内含 38→77.8 的修订过程）。

## 2026-11-05 键盘不再驱动镜头

| 条款 ID | 规则 |
|---|---|
| SEA-CAMERA-R12 | `W A S D`、方向键与 `Q`/`E` 不再平移或旋转镜头；键盘全部归角色与交互（SEA-MOVE-R20、SEA-NAV-R15、SEA-INTERACT-R13）。镜头保留鼠标左键拖拽平移、右键/中键旋转、滚轮与触控板捏合缩放；跟随/手动接管、俯角、FOV、阻尼、77.8 米缩放上限与 UI 阻断均不变。需要键盘取景的抓图/探针工具改为直接写 `apply_pose()`，不得依赖玩家键位。 |

[交付与实测](../../development/2026-11-05_keyboard_control.md)。

## 2026-11-05 尺度联动（追加）

| 条款 ID | 规则 |
|---|---|
| SEA-CAMERA-R13 | 跟随瞄准高度由写死的 0.7 m 改为 `0.7 × SCALE`（默认 1.05 m），统一引用 `avatar_dimensions.gd` 的 `CAMERA_FOCUS`，覆盖 `follow.gd`、`orbit_camera.gd`、`main.gd`（跟随目标、睡眠过场投影点）、`room_controller.gd`。到达与捏人的肖像机位，其中心点、距离与横向偏移同样乘 `SCALE`，否则放大后的头部会被裁掉。缩放上限 77.8 m、FOV、阻尼与鼠标交接规则不变。 |

[交付与实测](../../development/2026-11-05_character_scale_150.md)


## 2026-11-05 跟随手感：位移继承与前视

| 条款 ID | 规则 |
|---|---|
| SEA-CAMERA-R14 | 跟随模式分两层：①**位移继承** —— 主体每帧移动多少，视点先平移同样的量，阻尼只收敛残差，匀速段不得残留滞后（旧实现恒定滞后 `v·τ`，实测约 0.62 m，现应 ≤ 0.02 m）；②**速度前视** —— `lead = clamp(v × 0.52, 0…1.4 m)`，按 0.32 s 时间常数缓入缓出，站定后自动回零。主体速度由位置差分估计并经 0.12 s 平滑，单帧位移 ≥ 8 m 视为传送、不参与估计。前视只在跟随且室外生效，手动接管、`pose_lock`、房间环视一律为零；跟随目标切换时清空速度与前视历史，不得把旧主体的坐标差继承进新构图。俯角、FOV、缩放上限、阻尼帧率一致性与 UI 阻断保持不变。 |

[交付与实测](../../development/2026-11-05_control_feel.md)。

## 2026-11-06 独立键盘取景入口

本节取代 R12 中「镜头只留鼠标/键盘全部归角色」的绝对表述；WASD、方向键及Q/E仍不驱动相机，它们继续归角色、选目标与交互。鼠标路径、既有镜头状态及上限规则不因新增入口自动完成验收。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-CAMERA-R15 | `[` / `]` 通过既有 orbit 动作旋转，`-` / `=` 通过 `set_distance` 缩放；F 由 Main 恢复角色跟随，与正式跟随命令同源。不得抢用WASD/方向/Q/E、绕过模态/过场/固定机位输入限制或新增一份相机状态。室内仍沿 orbit-only 取景和原距离/俯角约束；范围、跟随/手动交接与室内实际手感需专项核验，不因按键分支存在就认定通过。 |

源码定位：`godot/src/camera/orbit_camera.gd:261` 的输入门禁与独立取景键，`godot/src/bootstrap/main.gd:2294` 的F跟随。X退出复用正式room_exit，不新增相机状态。`.abs()`修复后194828与200446最终报告keyboard-travel均374/0、exit0、passed=true；`test_keyboard_travel.gd:201`在家泊位与六格菜单退出后用真键复验室外旋转/缩放/F跟随；200446同批camera12/0、keyboard-control30/0、control-feel31/0通过。旧负Rect runner FAIL保留为过程，不再写修后待跑；室内全部缩放边界/设备与所有组合仍未据此验收，整体partial。报告完整路径与矩阵见[总交付](../../development/2026-11-06_keyboard_complete.md)。
## 2026-11-09 缩放区间收窄到 7%–38%

主人给两张截图：「最远视角调整到 image2 这个位置，最近调整到 image3」。两张都是当前版本拍的，读数是 **视野 38%** 与 **视野 7%**，因此百分比按现行刻度反解：`d = 9 + pct × (77.8 − 9)` → 最远 35.14 m、最近 13.82 m。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-CAMERA-R16 | 玩家可达区间从 9–77.8 m 收窄为 **13.82–35.14 m**（显示刻度 7%–38%）。`zoom_ratio()` 的刻度锚定新增字段 `zoom_ref_min = 9` / `zoom_ref_max = 77.8`，**不跟着 `zoom_min / zoom_max` 走**：主人用这个百分比指认机位，刻度一动，同一句话就换个画面。开局 54.25 m 已越界，改为 **27.9 m**（新区间 66%，与旧值在 9–77.8 里的 65.8% 同档；显示读 27.5%），两端都留余量、不钉在最远。滚轮/捏合、C 面板滑杆与四个预设全读同一对字段；需要更宽机位的证据脚本仍在自己文件里临时抬高 `zoom_max`，玩家上限不跟着放开。 |

真实渲染证据：`camera-zoom-far.png`（拉到顶=35.14 m，读数 38%）、`camera-zoom-near.png`（拉到最近=13.82 m，读数 7%）。断言见 `tests/test_camera_follow.gd` 与 `tools/capture_camera_zoom.gd`；交付记录见[本轮交付](../../development/2026-11-09_dock_hotspot_and_zoom_range.md)。

## 2026-11-10 潜水入水镜头跨链（现行设计，运行验收 PENDING）

本轮用户明确要求更新设计，从既有最大 R16 后追加 R17，全部历史保留；本条是 SEA-CAMERA-R03 的跨域交接说明，**潜水镜头所有者仍为 SEA-DIVE 的 Shared DiveRuntimeController，不是修改 OrbitCam**。不新增相机状态机，不修改 R16 海面缩放区间、既有跟随/手动规则或登记头 owner。

| 条款 ID | 现行规则 / 应验证的行为 |
|---|---|
| SEA-CAMERA-R17 | 潜水可见入水镜头与角色入水由同一 Shared DiveRuntimeController、同一 entry 进度推进，见 [SEA-DIVE-R44–R51](../dive/spec.md#2026-11-10-圆幕展开后可见入水现行设计运行验收-pending)。cover0.85s并经真实全黑post-draw后加载/碰撞选点，prepared enter且entry_verified（如存在）后通过 `set_entry_view` 准备初始角色/镜头，再uncover1.05s，不等swim。opening全程位置/Air及初始镜头保持，圆幕彻底idle且不可见后Session phase entering、`release_entry` 才启动可见下沉：家园1.65s/水下1.6→4.8m，旧九图2.2s/终点Y=-10，统一 `f=1-(1-u)^3` ease-out且末速0。镜头距离6.3→7.5m、FOV76→72°、初始略仰回基础pitch，单次heave≤0.08m、无roll；保留半径0.32m的候选clip与插值后最终clip、立即回缩/离墙缓出。实际位置差驱动velocity动画，swim边界清零入水残速但不snap相机。switching/transition_frozen及输入/save/日期/氧气冻结持续到swim；普通游泳72°/冲刺78°/滚轮距离4..13m不改，Map只提供camera_clip空间裁剪，不能另持镜头状态。 |

预计验证入口为既有 `dive-transition` / `visual-dive-transition`，并由 `dive-control` / `visual-dive-control` 检查普通潜水参数不回退；真实连续帧需核对opening固定构图、全幕退场后才下沉、ease-out/无roll/≤0.08m单次heave、近墙双clip与swim不snap。**当前运行 PENDING，不借旧 camera 或潜水 PASS 预签。** 报告、计数/退出码、unexpected/leak及逐图/时序审阅由主线程回填 [入水表现开发记录](../../development/2026-11-10_dive_entry_splash.md)（主线程创建）；本次不运行Godot/sync，不改代码/GDD/用户TSCN，家园120m与水位101.587442不动。

### 2026-11-10 当前运行签署

上方为委派阶段待验，现以本轮实测覆盖：`20261110-233501-dive-entry-polish-core-cc526e`的transition500/0、control396/0；`20261110-233501-dive-entry-polish-visual-6a99e7`的真实transition404/0、control403/0；`20261110-233926-dive-entry-final-integration-222f98`的海面camera14/0，均exit0/PASS、unexpected=[]。R17的opening固定相机、全展开后可见下沉、首swim连续、原普通游泳参数及碰撞裁剪通过；最终家园pitch0.16rad、入水偏移−0.22rad，使水面边缘在终点高于头顶。真实21帧/动态预览已审阅，海面OrbitCam与用户TSCN未改。完整报告及全局sync79/只读81未过、低端/长时/用户终审边界见[开发记录第5节](../../development/2026-11-10_dive_entry_splash.md#5-最终运行验收)，不据此宣称全工程绿。

## 2026-11-14 水下体验镜头与轻潜水镜（设计规划，planned）

核对既有最大 R17 后追加 R18/R19。承接 [3–5分钟潜水主方案](../dive/underwater_experience_plan.md) 与 [SEA-DIVE-R52–R75](../dive/underwater_experience_plan.md#4-r52r75-设计条款)（主方案追加），服务打捞、拍照、抄网捕鱼及电影化进出水。以下全部数值均为候选，待实现及运行验收；不表示当前镜头参数已变，不覆盖历史实现签署。主方案及[本轮开发记录](../../development/2026-11-14_underwater_experience_plan.md)由主线程建立。

| 条款 ID | 规划规则 / 应验证的行为 |
|---|---|
| SEA-CAMERA-R18 | **planned**：未来潜水第三人称候选默认距离 **9.5m**、滚轮范围 **5..16m**、垂直视场角 **vFOV74°**、冲刺 **vFOV80°**；实现时必须显式设置 `Camera3D.KEEP_HEIGHT`，不得把水平FOV误记为垂直FOV。潜水参数、姿态及电影段仍只归 **Shared DiveRuntimeController**，Map只提供空间 `camera_clip`，Session只交接，不新增镜头owner；海面 OrbitCam、SEA-CAMERA-R16 的距离/刻度/输入规则不动。保持半径 **0.32m** 候选clip与插值后最终clip、遇障立即缩回及离墙缓出；防墙时最终距离允许短于玩家最小距离；无roll。手动输入期间不自动抢镜，打捞/拍照/抄网不因目标出现强制转向。入水、普通游泳、返程镜头由同一控制器连续交接，保留既有圆幕/冻结门禁，不能在游泳边界snap；本候选若实施需联动主方案电影段终点，不把旧R17的6.3→7.5m/76→72°曲线与新默认距离硬拼。碰撞后实际速度为零时停止冲刺镜头效果，不因持续按Shift维持冲刺FOV。 |
| SEA-CAMERA-R19 | **planned**：轻潜水镜仅作可关闭的画面表现；画面中心 **55%** 区域不扭曲，边缘位移候选默认 **≤画面短边1.5%**、可调上限 **3%**，强度可归零且零强度等价于无该效果。呈现顺序为完成世界雾与透明合成后、HUD及圆幕前，不能再次叠加世界雾或扭曲HUD/圆幕。世界目标投影标签使用同一畸变模型的正向映射、点击拾取使用共享参数的逆映射，不允许视觉标签与命中空间错位；零强度下投影/点击必须与原路径等价。需在 **16:9、16:10、21:9** 与 **Compatibility** 真实渲染验证合成顺序、边缘位移、标签/拾取对齐及零强度等价，不能以静态shader或无渲染断言替代。 |

待验仅扩展既有 `dive-control` / `visual-dive-control`、`dive-transition` / `visual-dive-transition`、`underwater-experience` / `visual-underwater-experience`、`camera` 等入口；不向 verification 登记未来测试名。P0已接入9.5m/5–16m/vFOV74/80/KEEP_HEIGHT，专项headless与Forward+ 1280x800/60FPS真实渲染均通过；轻潜水镜、标签逆映射、三宽高比/Compatibility和完整3–5分钟体验仍待实现验收，登记头不变。

### 2026-11-14 规划复审补充

R18电影段候选入水起点为7.8m/vFOV78°，终点为用户距离/74°（默认9.5m），不可把旧6.3→7.5m曲线硬拼。现行实际为7.5m、4–13m、FOV72/78，尚未切换；74°竖直在16:9约为106.52°水平，不混用。R19中心55%按半短边归一化径向定义，标签仅锚点随世界正向映射、字形不扭；照片保留雾/光线/可选镜片、不含HUD/圆幕。出水受Session令牌授权的Controller表现tick在冻结白名单内推进，但玩家输入/奖励/Air仍锁；深处采用短表现+遮黑压缩返程，不明场穿墙。详细验收见[主方案第14、16节](../dive/underwater_experience_plan.md)，仍planned/pending。
