# SEA-UI · HUD 与菜单反馈 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-ui) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-UI",
  "status": "partial",
  "owner": "HUD / UI presenters",
  "code_paths": [
    "godot/src/ui"
  ],
  "verification": [
    "visual-title-screen-day",
    "visual-title-screen-night",
    "visual-title-screen-dawn",
    "click",
    "management",
    "minimum-loop",
    "visual-title-screen",
    "visual-plot-shipping",
    "visual-sleep-cycle",
    "visual-pocket-bubbles",
    "visual-pocket-services",
    "visual-home-lighting"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-UI-R01 | 本轮单卡反馈、拒绝出售、背景点击隔离与详情返回通过；旧专项边界保留 | 2026-10-26 原生真实鼠标/键盘专项与 click/management；见单卡交付记录 |
| SEA-UI-R02 | 本轮仅 UI 显示状态与既有业务命令；旧直接读取字段待进一步接口治理 | 正式源修改限于 ui，未修改业务状态键/资产ID；原生出售与水下事件链实测 |
| SEA-UI-R03 | 部分实现；1600×1000、1280×800、1920×1080桌面布局覆盖 | 原生viewport截图及不越界断言；触控/手柄未验 |
| SEA-UI-R04 | 已实现；全界面扩展 | 海面渔具箱/水下日志420×620、3×3两页；680×680经营详情、卡外提示；全界面截图08—14 |
| SEA-UI-R05 | 已实现；缺数据明确「—」，不新增即时出售规则 | 只读Label、真实氧气/水深事件、库存角标零值隐藏、装备锁；截图01/03/06 |
| SEA-UI-R06 | 已实现并原生验证 | 开卡端点、背景强度、翻页中间态/结束态、连按不堆叠；截图02 |
| SEA-UI-R07 | 已实现并原生验证 | hover、数量中间态/上浮、飞入节点、到达高亮与衰减、选中恢复；`verify_ac_ui.gd` |
| SEA-UI-R08 | 已实现并原生验证 | 真实氧气25%橙/12%红、±2抖动、关闭反馈归零、卡外提示固定；截图03/06 |
| SEA-UI-R09 | 已实现，当前证据见交付记录 | `island_paper/island_presenters/island_atlas`；所有改动局限UI目录，外部presenter保留原控制与信号 |
| SEA-UI-R10 | 已实现，当前证据见交付记录 | `island_menu`；分层返回、详情历史、系统暂停、读档/退出取消优先 |
| SEA-UI-R11 | 已实现，当前证据见交付记录 | 独立 `user://island_ui.cfg`；动画/氧气反馈/音量偏好、全屏、帮助、原保存命令 |
| SEA-UI-R12 | 已实现桌面覆盖，设备项待验 | 原生截图、三分辨率、订单等待、打捞成功/失败、气泡淡出同步、收藏弹窗；触控/手柄未验 |
| SEA-UI-R13 | 已实现，最终证据见交付记录 | 统一字体工厂、UI层全树与动态节点字体绑定、字体资产授权/哈希登记；真实窗口逐页字体引用核对与字号排版检查 |
| SEA-UI-R17 | 已实现并真实渲染实测 | 遮罩开关收敛到 `HUD._sync_backdrop`，`island_menu._dim_wanted()` 按面板过滤。`tools/probe_panel_dim.gd` 同机位四块开阔水面：P 面板开 `0/105/152`（与关闭态一致），背包开 `13/90/124`（对照，遮罩照旧生效）；背板 `visible=false strength=0` 而 `external_modal=true`，模态语义未丢 |
| SEA-UI-R14 | 已实现，最终证据见交付记录 | 手机/口袋/选项/对话分形态；背包按stack_limit展示真实堆叠、24格含空位，真实点击打开详情及Esc返回 |
| SEA-UI-R15 | 已实现，`visual-paper-fit` 三分辨率通过 | 圆角由内容边距反推上限、纸外扩24px、面板控件与字号不动；11块纸背板逐字四角+四边中点内点判定0越界 |
| SEA-UI-R16 | 已实现，`visual-world-text` 通过（24 checks / 0 failures） | 字号下限26px、合成加粗 embolden=1.0、零勾边；回退倍率后闸门7项红，证明断言会失败 |
| SEA-UI-R18 | 已实现；详见本轮框架专项 | [交付记录](../../development/2026-10-27_modular_framework.md) |
| SEA-UI-R19 | 本轮实现；正式最小范围与独立专项验证 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |
| SEA-UI-R20 | 本轮实现；正式最小范围与独立专项验证 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |
| SEA-UI-R21 | 本轮实现；正式最小范围与独立专项验证 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |
| SEA-UI-R22 | 本轮实现；正式最小范围与独立专项验证 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |
| SEA-UI-R23 | 已实现，场景点击与存读专项验证 | [本轮证据](../../development/2026-10-27_plot_shipping_loop.md) |

## 资源与调用入口

- [godot/src/ui](../../../godot/src/ui)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

- `godot/src/ui/hud.gd`：命令/查询 `open_tab(tab: String), toast(text: String, seconds := 2.4), set_diving(on: bool), set_dive_air(ratio: float, lamp_on: bool, found: int, total: int), air_color(ratio: float), set_dive_zone(name: String), set_dive_depth(depth: float), note_zoom(ratio: float)`；事件 `destination_pressed(zone_id: String), dive_pressed, build_pressed, site_focus_requested(id: String), plot_focus_requested(id: String), command_requested(command: String), rest_requested, facility_build_requested(id: String), ship_upgrade_requested`。
- `godot/src/ui/landing_markers.gd`：命令/查询 `build(cam: Camera3D), pick(screen_pos: Vector2, radius: float = 26.0), set_highlight(zone_id: String)`；事件 `无`。
- `godot/src/ui/cozy_ui.gd`：命令/查询 `surface(color: Color, radius: int = 22), button_color(text: String), animate(control: Control, scale_to: float), reveal(control: Control), apply(control: Control), apply_tree(root: Node), apply_instance(instance_id: int)`；事件 `无`。
- `godot/src/ui/ui_font.gd`：命令/查询 `embedded(), make(font_names: PackedStringArray)`；事件 `无`。

- `hud.gd::presentation_snapshot()`：只读新字典，open/page/diving/depth/oxygen/clock/tide/turning；不暴露业务可变对象。
- `ac_card.gd`：UI内部 `flip/show_grid/show_detail/update_context/fly_in/flush_arrivals/move_selection`；事件 `activated/page_changed`，只操作表现。
- `ac_icon.gd`：UI内部 `set_amount/highlight`；数量与高亮不写回库存。
- 本轮未新增业务只读接口；状态来源详见下方交付记录。

## 验证记录

入口：`python3 scripts/run_verification.py click management`；纸背板装配见 `python3 scripts/run_verification.py visual-paper-fit`；世界浮层纯文字见 `python3 scripts/run_verification.py visual-world-text`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 click、management 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

- 2026-10-23 真实事件补充：visual-click 退出 1，第二地格点击目标断言失败；拆分前基线同样失败，完整根因待定位。不得以核心 click 通过覆盖此失败。详见[交付记录](../../development/2026-10-23_feature_split.md)。

### 2026-10-26 世界浮层大字

交付与档位对照见 [浮层字交付记录](../../development/2026-10-26_world_text_scale.md)。

- 问题：主界面左下「瓶盖 80 · 背包 1/24」笔画细、边缘发沟；上岸点名称用 `ThemeDB.fallback_font` + 11px + 4px `draw_string_outline`，既不是打包字体又被描边糊掉。
- 字号（基准1600×1000）：资源行 22→44、潜水状态 20→40、视野提示 17→33、上岸点 11→26、水下宝箱 12→29。下限 26px 由 `WORLD_TEXT_FLOOR` 独立锁定。
- 字重：霞鹜975圆体的拉丁数字在同一文件里偏细，44px 下与汉字两种粗细；用 `FontVariation.variation_embolden=1.0` 合成加粗补齐。档位实测 0.0 偏细、1.5 以上粘连，取 1.0。
- 去勾边：移除 `draw_string_outline` 与 Label 的 `font_shadow` 轮廓，只保留右下固定偏移的柔和投影（`shadow_outline_size=0`），保证白字在白色建筑上仍可辨。
- 修掉一处静默覆盖：`island_presenters._font_tree()` 把整树字体刷回 `hud._font`，会让加粗失效；世界浮层字打 `cozy_world_text` 标记后豁免。
- 闸门 `tools/check_world_text.gd`（注册名 `visual-world-text`）：24 项，查字号下限、字体家族（沿 `FontVariation.base_font` 回溯）、零勾边、`_font_tree` 后仍加粗、上岸点不再调用 `draw_string_outline`。**反向验证过**：把 `WORLD_TEXT_SCALE` 调回 1.0 时 7 项红。
- 回归：`click`、`management`、`camera`、`visual-paper-fit` 退出0；`verify_island_ui` 120项/0失败（字体断言改为沿 `base_font` 比较家族，不再要求同一对象）。

### 2026-10-26 纸背板装配

交付与截图见 [纸背板交付记录](../../development/2026-10-26_ui_paper_fit.md)。

- 根因：`island_paper` 的圆角按面板宽高百分比取（横向约0.10W、纵向约0.10H），而内容边距固定32px。面板越宽圆角越大，980px宽的订单板圆角横吃98px，「码头来信」直接落在被吃掉的区域。既有 `inside(panel)` 断言只比面板矩形、不比纸轮廓，所以全过。
- 实测越界（改前）：orders 22.5px、grade/water 13.5px、salvage 4.3px；camera/grade-filter/toast/menu 四页与 prompt 为0。改后全部0。
- 修法：圆角半径 = clamp(面板宽高×0.10, 内容边距+纸外扩−8px)，纸四边各外扩24px。面板、控件、字号一律未动。
- 附带修：世界提示气泡的背板原先「有弹窗就 hide()、无任何恢复路径」，开过一次背包后永久变成裸字；改为每帧按状态对齐。`hud._toast_tag` 骑纸边的装饰同步外扩24px。
- 新增闸门 `tools/check_paper_fit.gd`（注册为 `visual-paper-fit`）：11块纸背板、逐 Label 四角+四边中点做纸多边形内点判定，容差1.5px；并检查纸不越出视口、面板真的显示（防空跑）。1600×1000 / 1280×800 / 1920×1080 均 11 checks / 0 failures、退出0。
- `click`、`management`、`camera` 复跑退出0。`visual-management` 仍有2项失败（找不到按钮「材料一键入库」），已用临时还原基线对照：改前同样失败，与本次无关。

### 2026-10-26 单卡专项

交付与全部日志路径见 [单卡交付记录](../../development/2026-10-26_ui_ac_single_card.md)。真实截图：工程外 `sea-work/ui_shots_ac/01_card_open.png`、`02_page_flip.png`、`03_low_oxygen.png`，另有第二页、仓储与橙色警示三张。

- Godot 4.7.2 隔离导入退出0；SCRIPT ERROR / Parse Error / 非预期 ERROR 为0。
- `core` 已完整运行：8项通过；selftest 536 passed / 1 failed（退出1），失败是旧 `_tab_body` 必须直接包含 BackpackGrid 的结构断言。恢复 HEAD 的隔离基线同样失败，不能记为全绿；坏 JSON 注入另列为预期错误。
- 原生专项经现有 runner 注册执行，验证真正鼠标/键盘输入、模态隔离、同卡详情、数量/飞入/翻页中间态、真实出售与水下低氧。最终71项/0失败、退出0，`verification/20261026-100900-ui-ac-delivery-8b809e/report.json`；源码与实际运行副本逐字节一致。
- 第一次原生低氧场景准备的固定耗氧时间未到阈值，断言失败已保留；改用真实模型速率计算推进量后通过。未以合成HUD数值替代真实事件。
- 未执行：触控/手柄、其他分辨率、旧 visual-click/visual-management（旧布局假设）；历史地格失败保留。

## 遗留与下一步

部分 UI 仍直接读取业务字段；功能级面板分别由所属功能代码目录管理。时钟/潮汐缺查询显示「—」；非作物即时出售无既有命令，走码头交易。旧 BackpackGrid 结构断言需要在允许修改测试的任务中更新为新UI契约；本次不越过代码边界，也不挂隐藏旧容器凑通过。当前全界面补充证据以交付记录最新章节为准，早期截图及71项结果保留为历史。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

- 2026-10-26：完成单卡交互、程序化图标动画、真实低氧反馈与原生截图验收；新增R04—R08承接，整体仍partial，保留旧断言/设备覆盖缺口。

### 2026-10-26 全界面扩展

按用户补充参考图，完成当前所有正式UI入口与系统菜单；开发记录见[最新交付](../../development/2026-10-26_ui_ac_single_card.md)。新增UI内装饰器，不修改任何非UI业务源码。新只读接口仍只有 `presentation_snapshot()`；`bind_presenters()` 仅连接UI所有者，`back()/close_card()/set_external_modal()` 仅改变表现。

原生当前测试、运行失败及修复过程、核心结果和未执行项统一列于最新交付记录，不以早期通过替代最终代码实测。

### 接续交付：参考复核、抗锯齿与圆体字号

接续原对话最后补充的抗锯齿、整体参考风格和本对话的圆润饱满大字号要求。新增UI字体分账本（从总索引路由），`UI-FONT-LXGW975YUAN-SC-700` 使用上游完整未修改字体，OFL与版权随文件保存。只新增此资源哈希，不更改历史资产基线。

真实窗口中发现并修复早期hover发生在footer创建前的空引用、口袋图标局部变换未恢复导致的数量位置异常。输入测试将一次按下/释放作为同次Viewport事件序列提交，避免测试两个事件之间被原生鼠标更新插入；仍走真实GUI命中与按钮命令，不直接调用业务结果。最终日志与过程失败见开发记录。


接续最终实测：`20261026-161255-ui-rounded-native-capture-de770f` 原生120项/0失败，逐页字体引用一致、1280×800/1600×1000/1920×1080布局通过；最新隔离导入 `20261026-161339-ui-ac-import` 退出0。核心完整 `20261026-161546-ui-rounded-delivery-core-464e90` 八专项通过，selftest536/1保留旧BackpackGrid断言失败。截图等待自动绘制信号曾导致超时，改为主动绘制真实Viewport后取图；过程失败及取图方法见开发记录，未用历史通过覆盖最终代码。


最终单卡专项 `20261026-161646-ui-rounded-single-card-delivery-31a2d0` 71项/0失败、退出0；要求的六张1600×1000原生截图已刷新。两组共42张截图及源码副本一致性清单位于工程外 `ui_shots_ac/verification.json` 与 `ui_full_island/verification.json`。最终结构同步与无参数检查均0问题。

## 2026-10-27 模块边界

HUD 接收 economy / zones / game_state；presenter_sources 由 Main 装配，IslandPresenters.attach(hud,sources) 只拥有表现。日历显示读取 time/weather 查询，潜水或模态时隐藏。

[模块接口约定](../../architecture/module_contracts.md) · [本轮证据](../../development/2026-10-27_modular_framework.md)。

2026-10-27 接口收口：公开入口：is_panel_open / is_modal / toggle_panel / open_tab / refresh_view / toast_snapshot，Main 不再读面板和提示框私有字段。

## 2026-10-27 当前最小循环与开始画面

本节及本轮修改条款优先于下方保留的历史范围。默认发布配置只开放家园生活循环；旧全功能验证须显式 `--full-world`，不能代替最小版本验收。接口、迁移及实测见[交付记录](../../development/2026-10-27_minimum_loop_and_title.md)。

2026-10-27 场景点击循环：07:00收货、瓶盖、木土种植格及码头出货箱；[本轮记录](../../development/2026-10-27_plot_shipping_loop.md)。

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-UI-R24 | 已实现，圆形过场隐藏/恢复UI；实际点击与开始画面回归 | [本轮实测](../../development/2026-10-28_sleep_iris.md) |

## 2026-10-28 场景气泡与口袋界面

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-UI-R25 | 已实现；实际渲染与输入专项通过；设备/授权边界单列 | [交付记录](../../development/2026-10-28_pocket_action_bubbles.md) |
| SEA-UI-R26 | 已实现；实际渲染与输入专项通过；设备/授权边界单列 | [交付记录](../../development/2026-10-28_pocket_action_bubbles.md) |
| SEA-UI-R27 | 已实现；实际渲染与输入专项通过；设备/授权边界单列 | [交付记录](../../development/2026-10-28_pocket_action_bubbles.md) |

本轮运行结果、过程失败、退出码与未执行项集中记在交付记录。旧记录保留为历史，整体状态仍partial。

## 2026-10-28 服务界面补齐

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-UI-R28 | 已实现；真实GUI存取、商店购买与三分辨率专项 | [实测记录](../../development/2026-10-28_service_pockets.md) |

2026-10-28 恢复验收（request ID `21726f14-a5f7-438f-9db2-83ed622dd271`）：当前源码重新通过服务口袋、实体出货箱全流程、场景气泡三项真实渲染专项及最小循环/模块检查；完整世界3项可行走面失败单列，不签署全工程通过。见[本轮记录](../../development/2026-10-28_service_pockets.md)与[机器证据](../../development/2026-10-28_service_pockets.json)。

## 2026-10-28 家园箱子与夜灯修复

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-UI-R29 | 已实现；真实渲染和相关集成检查通过，设备边界单列 | [本轮实测](../../development/2026-10-28_home_lighting_recovery.md) |

SEA-UI-R19本轮按用户要求恢复P调试例外，其它范围限制保留。

[交付记录](../../development/2026-10-28_home_lighting_recovery.md)。

## 2026-10-28 P 面板分时段调参

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-UI-R30 | 已实现；4季×3天气×8段共96组合，侧栏挂在主面板左缘外侧（间距算上纸张外扩 24px）并每帧跟随，调过的时段按钮前显示· | `lighting-panel` 44项 |
| SEA-UI-R31 | 已实现；滑杆写入选中组合的差值，打开面板锁预览、关闭即放，复位只清当前组合 | 「切回上午还是1.23」「夕阳的偏移没被连坐」等断言 |
| SEA-UI-R32 | 已实现；天空盒7项本轮补齐（新增`sky`分段名），水面9项由`adopt`改走偏移 | 「天空盒地平线色真写进材质」「正午的海水没被夕阳的改动染上」 |
| SEA-UI-R33 | 已实现；对比度改走偏移，在19:00跑过一帧仍在1.42 | 「对比度改完跑过一帧仍在 1.42」 |

语义变更需注意：**P 面板不再修改 09:00 基准**。光照页、水面页里随时段走的 28 项、以及滤镜页的对比度，改的都是「当前选中时段」的偏移。原「改基准、夜里读基准」的断言已改为「改选中时段、别的时段不受影响」。

参数清单由 30 项增至 37 项（环境 19 + 太阳 11 + 天空 7），静态核对 217 项通过。

[本轮交付](../../development/2026-10-28_daypart_lighting_panel.md)。



## 2026-10-28 开始构图与存档时刻

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-UI-R34 | 已实现；保持角度的房屋上移、按钮右移、三分辨率原生布局，白天/夜间/清晨存档冷启动与实际点击入场光照连续核验 | [本轮交付](../../development/2026-10-28_title_composition_saved_time.md) |

开始机位只在TitleCamera临时接管，不改变玩家存档姿态；未修改光照时段参数、资产资源或存档格式。当前整体功能状态保持原状，目标设备等边界见交付记录。
