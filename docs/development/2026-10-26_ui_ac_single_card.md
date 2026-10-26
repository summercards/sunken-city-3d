# SEA-UI · 动森风格全界面交付 · 2026-10-26

任务依据：工程外 `sea-work/ui_task_ac.md`，以及用户随后补充的全界面制作、Esc菜单、比例位置与交互动画要求。已读取 AGENTS、GDD、SEA-UI spec/ledger，实际查看 `web/refs/ac_ui/` 的16张参考图及用户补充的日历、对话、极简世界HUD图。复用视觉语言，不复制游戏商标、角色或贴图；全部皮肤、图标、地图均为程序化Control绘制。

## 交付范围与代码边界

覆盖当前正式游戏已实现的每类界面：世界HUD、海面渔具箱、水下日志、生活手册、种植、建造、背包仓储、物品、航海图、相机、滤镜、水面两套方案、收藏列表/命名/删除确认、颜色选择器、订单及补单等待、打捞下钩/收线/成功/失败、悬停、操作提示、完成反馈、消息气泡；新增暂停、偏好设置、操作帮助、读档确认和退出确认。

正式实现改动全部位于 `godot/src/ui/`。`src/bootstrap/camera/interaction/orders/rendering/salvage` 等非UI目录源码最终均与HEAD一致；`main.tscn`结构、ContentID、AssetID、游戏存档键和业务数值未变。实现过程中对这些presenter的样式调整已迁入UI装饰器，工程外保存迁移前diff供追溯。没有隐藏旧背包容器来迁就测试。

| 文件 | 职责 |
|---|---|
| `hud.gd` | 原公开方法与信号保留；极简世界入口、单卡/详情历史、真实状态订阅、原命令路由、模态遮罩、独立缩放提示、带名字标签的消息气泡。延迟装配UI装饰器。 |
| `ac_card.gd` | 420×620两页九格、只读状态、海面接缝/水下装订、裁剪翻页、收成飞入、低氧边框和抖动。经营详情展开为680×680，返回时还原主卡。 |
| `ac_icon.gd` | 96×96圆角22矢量图标、装备锁、零值隐藏的数量角标、hover/呼吸/数量/到达高亮；新增材料与等待时钟图标。 |
| `cozy_ui.gd` | 保留原全部公开方法；共享奶油/薄荷/海蓝/珊瑚/金黄/淡紫token、按钮焦点、滚动内容、滑杆、程序化纸张挂接和定位。 |
| `island_paper.gd` | 非规则圆润纸张轮廓、柔和投影、虚线与花瓣印记；持续同步所属面板的位置、缩放、可见性和透明度，避免气泡淡出后残底。 |
| `island_menu.gd` | UI模态协调；Esc按弹窗→详情历史→当前面板→系统菜单返回。系统菜单真正暂停SceneTree并恢复此前状态；保存/读取发送原命令，退出二次确认，独立UI偏好。 |
| `island_presenters.gd` | 发现同场景现有命名presenter，仅重排/装饰其Control与弹窗。订单保留原标签/按钮/信号并排成三封信；不替换业务模型，不新增业务字段写入。 |
| `island_atlas.gd` | 从现有Zones footprint、名称、解锁状态绘制海图；当前位置环，不编造路线或解锁。 |
| `verify_ac_ui.gd` | 原任务71项动画/状态/真实出售/输入/低氧专项，适配新的Esc返回层级，输出指定六张截图。 |
| `verify_island_ui.gd` | 全界面真实窗口专项：菜单层级、暂停、偏好、原订单命令、模型结果、弹窗、气泡同步和三分辨率截图。 |
| `docs/features/ui/spec.md`、`ledger.md` | R04—R12设计承接、接口和证据；本交付记录详述范围与限制。 |

测试注册适配器留在工程外：`sea-work/ui_shots_ac/run_ac.py`、`sea-work/ui_full_island/run_full.py`，均导入并调用原 `scripts/run_verification.py`。仓库统一runner没有修改。开始时已有未跟踪的 `ac_card.gd.uid` 原样保留。

## 版式与颜色

- 主卡420×620，图标3×3、96×96、间隔18；工具首行带锁，下两行收成数量为0时不画角标。状态区域高52，底部两页码。卡外右下角固定返回/选择胶囊。
- 按用户后续要求重新分配面积：经营/仓储/地图详情680×680居中；暂停580宽居中；订单980宽三列；打捞700宽居中；相机480宽靠右48；滤镜/水面700宽靠右48。详情/水面内容滚动，遮罩下世界不接收点击。打开新主面板时关闭前一张。
- 共享Cozy颜色家族：奶油 `#fff9e8`、正文 `#625744`、次要 `#9a8e76`、薄荷 `#b3dca7`、海蓝 `#acd5de`、珊瑚 `#edb39d`、金黄 `#f7d879`、淡紫 `#cfbfdc`、焦点绿 `#5baa96`。主卡强调蓝仍为 `#4e9fc4`，警示橙/红 `#e08b4a/#d4573f`。无真实状态的字段保持「—」。
- 主卡绕过Cozy旧面板版式，采用不透明程序化纸张、40px投影范围/y+12/黑18%的分层近似柔影。外部面板通过相同纸张纹理统一，保留原功能。没有新增位图皮肤或修改业务资产台账哈希。
- 中文统一走 `ui_font.gd.make()`；最终字体为下述霞鹜975圆体SC 700W，全部界面和动态控件同一资源，不按平台选不同系统字体。独立窗口/下拉菜单也指定相同字体与奶油主题。

## 数据来源与所有权

| 状态栏字段 | 真实来源 | 缺失显示 |
|---|---|---|
| 时间 | SEA-TIME仍规划中；无世界时钟查询接入，不拿系统时间或农场天数冒充 | 「—」 |
| 潮汐 | 没有潮汐阶段查询，不从渲染波纹时间推断 | 「—」 |
| 水深 | `diving/underwater_world.gd::_process()` → `depth_changed` → `bootstrap/main.gd::_on_depth_changed()` → `HUD.set_dive_depth()` → `ac_card.update_context()` | 海面/未收到事件「—」 |
| 氧气 | `diving/dive_air.gd::update()/ratio()` → `underwater_world._update_air()/_emit_air()` → `air_changed` → `main._on_dive_air()` → `HUD.set_dive_air()` | 海面/未收到事件「—」 |

状态是Label且忽略鼠标。库存读 `Economy.count()`，通过 `resources_changed` 更新；地图读 `Zones.footprint()/is_unlocked()/label()`。种植、仓储、建设沿用原命令，订单沿用原按钮绑定的fulfill/reroll信号，打捞沿用原model与操作按钮。首行工具表达现有常驻能力，不新造装备资源。

新增业务只读接口：**无**。新增UI诊断 `HUD.presentation_snapshot()` 每次返回新字典：open/page/diving/depth/oxygen/clock/tide/turning，不暴露可写业务对象。`bind_presenters()/back()/close_card()/set_external_modal()` 仅为UI协调；Card/Icons/Paper/Atlas只写表现状态。

游戏存档键未变。UI偏好单独保存在 `user://island_ui.cfg`，含动画开关、低氧反馈开关和主音量；全屏切换即时应用。未新增音效素材。

## 交互和动画参数

| 表现 | 实现参数 |
|---|---|
| 开卡 | y+64、scale0.92→原位/1，0.22s BACK/OUT；重入取消旧Tween。 |
| 背景 | 同步0.22s，去饱和18%、黑12%；主面板互斥，系统暂停另有柔和遮罩。 |
| 翻页 | 旧页x0→−366，新页366→0，0.18s CUBIC/IN_OUT，366宽裁剪，turning锁不堆叠。 |
| 图标hover/选中 | 0.12s到1.06；3px描边，1.2s正弦呼吸。 |
| 数量 | 0.4s插值取整，y上浮8px；0值立即去掉角标。 |
| 入包 | 卡内下方飞入目标格，0.48s CUBIC/OUT，scale0.38→1；到达高亮0.55s衰减。隐藏/翻页时合并待表现物品，回九格播放。 |
| 低氧 | ≤30%橙、≤15%红；x=2×sin(TAU×10×t)，±2px/10Hz。总开关/偏好均可关闭，不影响卡外提示。 |
| 共用按钮/面板 | 0.14s SINE/OUT，按钮hover1.025（原apply入口1.035）、按下0.98；面板0.94→1。 |
| 消息 | 55字/秒逐字显现，末0.9s淡出；纸底/标签与正文同步，暂停菜单内消息显示在副标题。缩放反馈使用独立小胶囊。 |
| 减少动画 | 主卡开关/翻页直接就位，图标不放大、数量直接更新、呼吸停止；低氧抖动有独立开关。 |

Esc：先关闭当前子弹窗，再返回详情历史，再关闭当前主面板；世界中才打开系统暂停。水下Esc不直接上浮；暂停中真实耗氧停止，关闭后继续。读档与退出确认默认焦点为取消。退出只有点击确认才调用SceneTree.quit；保存/读取仍由原会话所有者处理。

经营即时出售仍仅对真实作物yield提供「出售全部农产品」，明确包括订单用料；鱼/贝壳/珍珠走现有码头订单，没有在UI中拼接扣物品/加海贝来创建新经济规则。

## 验证方式与证据

全部Godot启动通过统一runner隔离工程，在Autoload之前使用独立 `sea-verification/<run>` 用户目录，不读取/覆盖玩家存档。`check_import.py` 复用runner的 `isolated_project()` 执行任务要求的 `--headless --path <隔离工程> --quit`，保留退出码和完整日志。原生截图由Metal Forward+窗口Viewport直接保存，无离线重绘、拼贴或后处理。

标准复跑命令：

```sh
python3 /Users/summercards/WorkBuddy/sea-work/ui_shots_ac/check_import.py
python3 scripts/run_verification.py core --label ui-full-core --timeout 240
python3 /Users/summercards/WorkBuddy/sea-work/ui_shots_ac/run_ac.py visual-ui-ac --label ui-ac-current-native --timeout 300
python3 /Users/summercards/WorkBuddy/sea-work/ui_full_island/run_full.py visual-ui-full --label ui-full-delivery --timeout 360
python3 scripts/check_feature_contracts.py --sync
python3 scripts/check_feature_contracts.py
```

`verify_ac_ui`覆盖真实Viewport鼠标/键盘、动画中间态和结束态、卡外点击隔离、数量/飞入、岸上/船上出售差异、真实潜水耗氧事件。`verify_island_ui`覆盖实际菜单点击和键盘；收藏保存/删除取消使用原对话框按钮信号，打捞结果通过真实模型 `update()` 推进，未伪造表现数值。它们是测试夹具，正式场景不引用验证脚本。

核心全集最近运行：`verification/20261026-161546-ui-rounded-delivery-core-464e90/report.json`。modules/parity/farming/surface/click/management/camera/ocean八项均通过、退出0。selftest **536 passed / 1 failed，退出1**；整组core退出1。唯一失败是 `tests/integration/selftest.gd:209` 仍要求 `_tab_body` 直接包含旧BackpackGrid；当前九格主卡不使用该容器。此前HEAD隔离基线 `20261026-100435-ui-ac-baseline-df3091` 同样失败，本轮不修改边界外测试或隐藏旧控件凑通过。坏JSON故障注入产生的一次 `ERROR: Parse JSON failed...` 被runner单列为预期错误。

过程中的失败如实保留：`20261026-133334-ui-full-boundary-00237d` 装饰器Array推断解析错误，明确标注Array后修复；`20261026-133412-ui-full-adapter-25fd28` headless49项全过。`20261026-133731-ui-full-final-design-dc73b2` 原生108断言全过但runner判失败：测试枚举元数据时对缺失键传null导致Godot报ERROR；改为先has_meta，不过滤错误。目视发现颜色弹窗越界、确认框默认灰色，也已在UI层修复。早期截图/71项结果只作历史，不替代以下最终实测。

## 截图交付

工程外 `sea-work/ui_shots_ac/` 保留并重新生成任务指定六张：

| 文件 | 内容 |
|---|---|
| `01_card_open.png` | 1600×1000海面渔具箱、装备锁、真实库存、零值不画角标 |
| `02_page_flip.png` | 真实翻页中间帧与裁剪 |
| `03_low_oxygen.png` | 真实水下低氧、红边和日志装订 |
| `04_page_ready.png` | 第二页完成态 |
| `05_storage.png` | 背包与仓储详情 |
| `06_oxygen_warning.png` | 真实25%橙色警示 |

`sea-work/ui_full_island/` 的01—34序号截图覆盖所有上述已实现界面和状态；25/26另有1280与1920宽版本。最终 `verification.json` 保存所有截图尺寸/哈希、运行证据及正式源码与实际运行副本的一致性核对。

## 明确限制

1. core保留1个旧内部结构断言失败；并非全绿。任务边界内的原生专项另列，不覆盖或隐藏失败。
2. 世界时钟/潮汐没有真实来源，保持「—」。不新增规划中的居民、养殖、天气、任务等玩法与虚构页面。
3. 触控、手柄和移动平台尚未实机验证；全屏按钮已接DisplayServer，但不为截图任务改动用户显示模式。音量已接AudioServer，不新增音效或宣称听验通过。
4. 旧visual-click/visual-management工具依赖旧布局，本轮未运行；当前布局由新原生专项覆盖。历史第二地格visual-click失败未在本任务修复。
5. 外部presenter装饰器依赖现有命名节点及UI控件字段，未来其UI结构变化需要同步适配；业务单写入者仍保持。收藏及颜色选择器保留完整原功能，退出确认的实际退出调用未自动点击，以免中止后续验证。

## 最终实测

以下接续章节记录最新实现；早期截图/结果不替代新代码验证。

## 2026-10-26 接续：原始参考、抗锯齿与字体比例

原对话因远程上下文压缩断线。接续时保留已完成的全界面交互，并执行最后追加的风格与锯齿要求；本对话追加「字体一致」「字形更圆润饱满、不要太小、画面占比还原」。本节参数覆盖前文对应旧值。

### 参考与落实

本轮再次实际打开项目内NookPhone、配方、地图与inventory图，并检视用户提供的世界HUD/中文对话图。项目中名为inventory的图实际为服装轮盘，因此补查了真正的口袋画面。

- [Interface In Game原始游戏截图集](https://interfaceingame.com/games/animal-crossing-new-horizons/)：查看NookPhone、对话与商店选择气泡。主卡按420×620、40px圆角恢复规则轮廓，标题居中，保留项目工具锁、只读状态与真实收成；不再套用通用不规则纸页。去掉各界面重复的花瓣印记和缝线。
- [New Horizons口袋参考](https://animalcrossingwiki.de/acnh/inventar)：物品格移除彩色App底板，改为8列、64px物品格、10px间隔、空位圆点、名称胶囊与选中圆底。按真实stack_limit拆显示格；格数和空位来自inventory.capacity()/slots_free()；不修改任何背包规则。
- 原始对话/选项参考：奶油色平面胶囊、暖黄选中、轻投影，菜单移除每行厚重阴影；增加程序绘制的手形选择标记。对话使用采样贝塞尔轮廓、姓名标签与逐字反馈。
- 世界HUD缩短左上入口，资源移到左下、增加文字投影；屏幕边角保留操作提示，中间留给场景。海面/水下、背包/经营/暂停仍是本项目实际功能，不增加参考游戏的虚假功能。

### 抗锯齿

`HUD._ready()`为Canvas启用4×MSAA，不改3D渲染参数或project.godot；全部自绘圆形显式开启抗锯齿，多边形加闭合抗锯齿轮廓；StyleBox圆角细分16–20、1.5px覆盖边；气泡轮廓每段48个采样点。字体采用灰度抗锯齿和2×oversampling。截图是原生Viewport，不做离线平滑。

### 圆体与字号

新字体：[霞鹜975圆体SC](https://github.com/lxgw/975Yuan)，上游提交 `37b753f408b25d3ab3d25cbddb5dd9dacca0289a`，使用完整未修改的700W字重；[SIL OFL 1.1](https://github.com/lxgw/975Yuan/blob/master/OFL.txt)与版权已随文件放入 `godot/src/ui/fonts/`。其圆角笔画与饱满字重更贴近参考的阅读观感。它是明确授权的替代字体，未使用任天堂专有字库。

1600×1000基准：主卡标题40px（原32），通用正文22px（原16/17），按钮24px、暂停选项26px（原17/20），对话正文30px（原21），主卡图标文字18px（原13）；只读状态14px、工具注释16px，细密滤镜控件18px。口袋数量使用22px逻辑字，随64/96格内缩放；按键提示24px并按实际宽度贴右定位。字体工厂保留原make签名，始终返回同一份圆体；UI装饰器覆盖现有、动态、弹窗及世界标记文字，业务目录不改。字体资产登记在独立UI分账本，既有AssetID/ContentID/游戏存档键未改。

本轮额外文件职责：`island_pointer.gd`绘制选择手形；`ui_font.gd`统一字体与抗锯齿；`src/ui/fonts/`保存字体、许可证和上游溯源。新增UI资产索引只登记这一个字体，不批量更新旧哈希。

### 接续过程验证（保留失败）

- `20261026-152200-ui-reference-smoke-4a566f`：headless75项通过。
- `20261026-152242-ui-reference-native-ad14a3`：原生117项、2项输入断言失败，另有footer初始化时序SCRIPT ERROR；已修复空引用与口袋绘制变换，未把本轮写为通过。
- `20261026-152701-ui-font-reference-check-46811f`：统一字体后headless82项通过。
- `20261026-152746-ui-reference-font-final-d2654c`：原生118项、低氧偏好点击1项失败；脚本/字体错误为0，之后修正测试按下/释放的帧间插入问题。
- `20261026-153214-ui-rounded-type-layout-1d6dc1`：圆体和放大字号后headless82项通过。
- `20261026-152811-ui-reference-font-core-42dae6`：8个核心专项通过；selftest536通过/1个旧BackpackGrid结构断言失败。属于圆体放大前阶段记录，最终版本结果另列。

- `20261026-153257-ui-rounded-native-2c1f99`：原生流程在相机阶段超时（退出124）；日志未见脚本错误，未将其写为通过。
- `20261026-154927-ui-camera-hang-probe-163604`：相机独立原生探针3项通过、退出0；不据此推断超时根因。
- `20261026-155036-ui-rounded-delivery-2e11b3`：完整原生118项通过、退出0、非预期错误0。目视后缩短种子购买按钮文案，避免放大字号撑宽经营详情。
- `20261026-155436-ui-rounded-margin-check-5e21f1`：追加种植/建设详情留白边界断言，headless84项通过、退出0。

原生最终截图和最终代码一致性哈希在最终结果章节登记。触控/手柄、实际退出调用、全屏显示模式切换及发行导出仍未验，不声称通过。


### 最终抓图等待问题排查

完整原生复跑 `20261026-160121-ui-rounded-final-delivery-77a6d5` 在14_map后停止推进，采样保存在工程外 `ui_reference_review/camera_full_hang.sample.txt`；采样后主动结束该验收进程（退出-15），未影响编辑器。带分段日志的 `20261026-160557-ui-camera-callback-trace-446f09` 与 `20261026-160924-ui-camera-layout-trace-96964b` 均超时退出124，全部保留。第二个日志显示相机布局已完成，后续_process持续执行数万次，故不是布局函数锁死；停点是截图等待自动frame_post_draw。macOS窗口遮挡停止自动绘制是工作假设，而非已单独证实的系统根因。

最终两个截图脚本在读取Viewport前调用RenderingServer.force_draw(false)，主动绘制真实原生视口，避免依赖自动绘制信号；仍使用Metal Forward+与实际场景节点，不离线合成画面。临时追踪代码全部恢复，未据此修改业务或正式布局逻辑。


### 最终代码实测与交付（接续完成）

- 隔离导入：`verification/20261026-161339-ui-ac-import/report.json`，退出0，SCRIPT ERROR / Parse Error / 非预期ERROR均0。
- 全界面原生：`verification/20261026-161255-ui-rounded-native-capture-de770f/report.json`，**120项通过、0失败、退出0、非预期错误0**。覆盖真实菜单/背包点击、字体逐页一致性、动态弹窗、种植与建设留白、三分辨率、真实低氧暂停、订单交付、打捞成功/失败。最终36张截图保存于 `sea-work/ui_full_island/`。
- 核心完整重跑：`verification/20261026-161546-ui-rounded-delivery-core-464e90/report.json`，modules/parity/farming/surface/click/management/camera/ocean八项通过；selftest536通过/1个旧BackpackGrid直接子节点断言失败，退出1。坏JSON注入的Parse JSON错误另列为预期故障，未算作新增UI错误。
- 统一字体资产授权与原生接入已核验，UI分账本和运行资源索引仅将此新字体转为runtime_integrated_verified；无旧资产基线重写。
- 正式源码变更限 `godot/src/ui/`，未修改main.tscn、project.godot、非UI业务模块或旧资源ID/存档键；未提交Git。

- 单卡原生最终重跑：`verification/20261026-161646-ui-rounded-single-card-delivery-31a2d0/report.json`，**71项通过、0失败、退出0、非预期错误0**。六张1600×1000图已全部重新生成，包括开卡、翻页中间帧、真实红色低氧和橙色警示。
- 两个截图目录各自的 `verification.json` 已更新：记录最终原生报告、源码及字体哈希、隔离副本逐文件一致性、PNG尺寸和哈希。共36+6张截图；每组16个源码/字体附带文件与实际运行副本一致。
- `python3 scripts/check_feature_contracts.py --sync` 和无参数检查均通过：31功能、375源资产、311运行资源哈希、0问题。最终git diff --check无错误。
