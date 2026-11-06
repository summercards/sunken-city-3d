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
    "godot/src/ui",
    "godot/src/building/ui"
  ],
  "verification": [
    "keyboard-panels",
    "visual-keyboard-panels",
    "keyboard-entry",
    "keyboard-farm-loop",
    "visual-keyboard-farm-loop",
    "keyboard-travel",
    "keyboard-building",
    "visual-keyboard-building",
    "interaction-reach",
    "visual-corner-notebook",
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
    "visual-home-lighting",
    "progress-bars",
    "pocket-drag-buy",
    "visual-pocket-drag-buy",
    "landing-markers",
    "visual-landing-markers",
    "close-hint",
    "visual-close-hint",
    "visual-recipe-cards"
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

## 2026-10-30 海上收获浮层

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-UI-R45 | 已实现；复用背包图标，在6px拾取条上方显示实际+数量，独立上飘/渐隐；不截获鼠标、失败不播 | `ocean-pickups`43项、`visual-ocean-pickups`13项通过；[原生画面与交付](../../development/2026-10-30_ocean_pickups.md) |

## 2026-10-30 海上地图：你在哪、太阳房在哪

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-UI-R46 | 已实现：`island_atlas` 新增太阳房房子徽标（钉 `zone1`，名字固定「太阳房 · 家园」）与按真实世界坐标投影的橙点；`HUD.player_query` 由 `Main._setup_hud` 注入 `player.global_position`，UI 不读业务状态 | `island-atlas` 10 项 0 失败（含"玩家标记用真实坐标""两块航间不贴回任一区块中心""无坐标时退回当前区块且仍画"）；`visual-island-atlas` 家园/浅水/两处之间的海面三张原生截图；[本轮交付](../../development/2026-10-30_island_atlas_you_and_home.md) |

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

2026-11-02建造输入适配：HUD新增注入的`owned_modal_camera_query`与`camera_modal()`，只在建造书本收起、拆除确认未打开时放行镜头；角色/世界业务输入仍保持原模态阻断。独立锤子按钮、指针、悬停轮廓及默认否确认由SEA-BUILDING表现层拥有，不复制退款规则。实际滚轮放置时可用、确认时锁定，鼠标是/否与跨分辨率控件专项通过。[建造交付与实测](../../development/2026-11-02_building_surface_and_demolition.md)。

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


## 2026-10-28 左下文字与海岛笔记

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-UI-R35 | 已实现；零背板、原白色加粗圆体、真实时间/余额/容量集中左下，三分辨率检查 | [本轮交付](../../development/2026-10-28_corner_hud_notebook.md) |
| SEA-UI-R36 | 已实现；右上单图标展开彩色图标菜单，真实服务路由、Esc/外点收起和模态隔离 | [本轮交付](../../development/2026-10-28_corner_hud_notebook.md) |
| SEA-UI-R37 | 已实现；四类目录、六卡分页、真实资料与状态、详情和原服务返回链 | [本轮交付](../../development/2026-10-28_corner_hud_notebook.md) |
| SEA-UI-R38 | 已实现；手绘船锚、无名称、平滑悬停及命中ID保留；动态提示稳定对象复用，周期刷新不再闪烁 | [原交付](../../development/2026-10-28_corner_hud_notebook.md)；[本轮修复](../../development/2026-10-30_sparse_landing_markers.md) |

公开表现入口增加corner（收拢/展开状态）与notebook（分类/页/选中资料），均为临时UI状态；calendar_query/weather_query在装配层注入。主场景保留唯一时钟Label引用，Label归入HUD左下区域。笔记query返回新字典，命令仍经HUD原分发器或plot_focus_requested信号。硬件设备触控/手柄专项未执行。


## 2026-10-28 月日与右下镜头入口

| 对应条款 | 实施状态 | 证据 |
|---|---|---|
| SEA-UI-R39 | 已实现；真实存档日数换算月日，瓶盖28px，原白色圆体与零背板保留 | [本轮交付](../../development/2026-10-28_hud_date_camera_lock.md) |
| SEA-UI-R40 | 已实现；右下圆形定位图标恢复角色视角锁定并同步状态，停止行动按钮移除 | [本轮交付](../../development/2026-10-28_hud_date_camera_lock.md) |

HUD增加公开表现入口set_follow_locked(bool)，Main查询OrbitCam.follow_enabled后同步；UI不写镜头内部状态。旧取消命令仍供控制器及验证使用，已从HUD按钮注册移除。R35的最新状态以R39/R40为准。

## 2026-10-29 家园建造接入

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-UI-R41 | 已实现；25配方以5列×2行奶油色图片/名字/消耗卡片展示，真实鼠标分类/翻页/整卡选择/退出78项通过；旋转精细/搬移拆回保留 | [本轮交付](../../development/2026-10-29_open_ocean_building.md) |
| SEA-UI-R42 | 已实现：世界浮层进度条统一为自绘细条（建造 8 px / 拾取 6 px），带 `cozy_skip`；浮层挂点选"永远在画面里"的对象（拾取条挂角色头顶） | `progress-bars` 37 项 0 失败（含"过一遍 cozy 主题仍是 6 px""目标在相机背后时条仍可见"）；[本轮交付](../../development/2026-10-29_pickup_progress_bar.md) |

## 2026-10-29 背包拖拽整理与购买数量

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-UI-R43 | 已实现：服务口袋与 B 键纯背包的背包格都可拖拽互换/挪到末尾；商店目录不可拖、也不接背包物品 | `pocket-drag-buy` 44 项 0 失败（含"界面按排列摆格""落下后立即重排""拖拽不改数量""商店目录不接受落下"）；`visual-pocket-drag-buy` 真实鼠标按下→移动→松开后顺序实测由 `fish,vegetable,tomato` 变 `tomato,vegetable,fish`；[本轮交付](../../development/2026-10-29_pocket_drag_buy.md) |
| SEA-UI-R44 | 已实现：`[−] N [+]` + 「购买 N」，上限取瓶盖与背包余量的较小值并置灰封顶 | `pocket-drag-buy` 覆盖"默认 1""点两次 + 变 3""减号回退""买 2 扣 2 倍价并到手 2 包""只够 1 个时 ± 都置灰"；真实截图见 `pocket-buy-1.png` / `pocket-buy-3.png` |

两处都改了对接层：`pocket_service` 新增 `sort_requested` 信号（界面不算账，只把意图转给宿主），`hud._service_sort` 落到 `Inventory`。快照额外带上 `bag_order` / `other_order` / 每件商品的 `max_buy`。

## 2026-10-30 右下角只留一枚关闭键

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-UI-R47 | 已实现：面板/模态打开时右下角只有一枚奶白圆片关闭键（62px、深棕描边、粗叉、落影、逆时针歪 6°），原「返回 Esc / 选择 Enter」两枚胶囊移除；服务口袋的「完成」按钮同步移除，关闭入口只剩这一枚；Esc/Enter 键盘路径保留，关闭语义仍走 `menu.back()` | `close-hint` 16 项 0 失败（只剩一枚、控件类型、无文字、贴角 34/30、62px、rotation≠0、绕圆心、`cozy_skip`、点击真关闭）；`visual-close-hint` 出全画面与 320×240 近景；`pocket-services` / `visual-pocket-services` 回归通过；[本轮交付](../../development/2026-10-30_detail_fixes.md) |
| SEA-UI-R47 实现注记 | 外层 `_hints` 从 `HBoxContainer` 改为普通 `Control`：Godot `Container.fit_child_in_rect` 会把子节点旋转归零，放进 HBox 的按钮永远摆不出那 6°。改动后 `_hints` 的 position/visible 调用点（`set_external_modal`、`_toggle_panel`、`island_menu`）全部保持原样 | `close-hint` 第一条「只剩一枚按钮」与 rotation 断言同时覆盖这一点；[坑位记录](../../development/2026-10-30_detail_fixes.md) |

2026-10-30建造手册卡片修订（R41）：BuildingBook/RecipeCard只展示目录与发送选择；RecipeThumbnail从实际组件渲染并缓存图片，最新PaletteUV修复后重新实测。卡片不显示描述、工期或独立“选择建造”按钮。见[交付](../../development/2026-10-30_modular_building_kit.md)及[机器证据](../../development/2026-10-30_modular_building_verification.json)。

## 渔场圆按钮（2026-11-02）

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-UI-R48 | FisheryMarker屏幕绘制复用原圆按钮和白色鱼剪影，移除3D图片/文字与重复悬浮图标；点击转发接近/收获 | fishery-production / visual-fishery-production；[交付](../../development/2026-11-02_fishery_round_button.md) |

R48本轮真实渲染36项、headless33项、操作气泡回归59项全部通过，鼠标按下/抬起确实触发按钮与实际收获；原生近景已检查。文档同步受并行水层资产登记阻挡，未批量接纳其他哈希。

## 2026-11-02 新旅程与角色档案

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-UI-R49 | 已接入，专项与回归以本轮记录为准 | `avatar / visual-avatar`；[交付](../../development/2026-11-02_avatar_and_arrival.md) |

## 2026-11-04 角色台词多段推进与开始画面补充（2026-11-06 补记）

本节补记 `1f336a13` 同批提交里除划船外的两件工作。当时只在 commit message 写了「多段对话、开始画面修订」，
未落设计条款，`SEA-UI` 停更在 11-02；行为已在线，但缺独立验收。

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-UI-R50 | 已实现：队列 + 页码 + 首击补全/次击换句 + 末行「开始生活」+ 打字机 0.018 s/字（夹 0.22–0.65 s）+ 多段全屏输入盾 + 空格/回车 consume。调用点为开场三句（`main.gd:3307`）与体力见底单句（`main.gd:2677`） | 源码 `godot/src/ui/character_dialogue.gd`、`godot/src/ui/hud.gd:906-921`；开场路径由 `onboarding` 38 项、`title-screen` 29 项覆盖（`20261104-151119-onboarding-r11-accepted-c93b3b`）。**pending**：对话组件自身的页码/末行文案/输入盾独立断言 |
| SEA-UI-R51 | 已实现：副标题「沉 没 街 区 上 的 屋 顶 生 活」、登岸提示呼吸、标题/按钮投影、悬停暖金与提示右移；R21/R22/R34 的时长与锚点未改 | 源码 `godot/src/ui/start_screen.gd`；`title-screen` 29 项与 `visual-title-screen-day` 28 项（`20261104-151730-onboarding-r11-ui-regression-5b28ba`）；[本轮补记](../../development/2026-11-04_dialogue_and_title.md) |

补记说明：本轮**没有新增运行**，证据全部来自 11-04 同批已接受目录；`character_dialogue` 缺独立专项这一项
按 pending 保留，不折算成已完整验收。

## 2026-11-06 世界菜单键位角标

| 对应设计条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-UI-R52 | 已实现；`ActionBubble.hotkey` + `_draw_hotkey()`，由 `WorldActionBubbles.open()` 按序号写入 | `interaction-reach`（第一项角标为 `1`）；真实渲染截图未单独出，菜单本体已在 `visual-plot-shipping` 覆盖 |
| SEA-UI-R53 | 已实现并最终专项通过；集中建筑UI仅承接表现与返回链，不新增业务写入者；Toolbar按钮无键名、无常驻按键教程，锤子仅建筑模块内显示，失败灰因/选择轮廓/材料确认/安全细节保留 | `building-ui-unified`66/0、`visual-building-ui-unified`66/0、`keyboard-building`40/0；签署报告`D:/projects/sea-work/verification/20261106-222059-building-5m-release-signed-2a186b/report.json`；[建筑5m与UI](../../development/2026-11-06_building_5m_and_ui.md) |

## 2026-11-06 默认玩法键盘闭环与近距图标

登记头 `status: partial` 不变，不执行 sync。R53 已占用并保留原样；本节只追加 R54–R57。上午 R52 的数字角标已被当前无教程式反馈目标覆盖，旧实测保留为历史。

| 对应设计条款 | 当前实施状态 | 证据 / 待验 |
|---|---|---|
| SEA-UI-R54 | 近距hover图标/细进度、modal收起、无底部prompt与世界角标/教程行的真实渲染专项通过；口袋按1说明/数字前缀同步差异已解决 | 194828报告visual-farm617/0、exit0；9张唯一截图，本轮画面目视审阅4张确认；主动系统help允许，不再列缺口 |
| SEA-UI-R55 | 购买数量、1件/整叠存取、分页、Shift排序、稳定物品ID焦点与单次确认通过 | 200446报告keyboard-panels80/0、exit0、passed=true；不外推未断言的可见文案 |
| SEA-UI-R56 | 笔记/地图稳定zone焦点、滚动、禁用跳过与原目的地信号通过；真实往返另有旅行专项 | 同报告panels80/0、travel374/0；194828报告travel374/0亦通过 |
| SEA-UI-R57 | 首创姓名外观、失败重试/取消、台词、设置及重置安全返回专项通过 | 同报告keyboard-entry39/0；保存为内存替身，不等于磁盘/冷启动/真实断电验收 |

证据根`D:/projects/sea-work/verification/`：

| 本轮验收 | checks/失败 | runner结果与报告 |
|---|---|---|
| keyboard-farm-loop / travel / panels / building / entry | 606/0、374/0、80/0、40/0、39/0 | `20261106-200446-keyboard-release-regression-eae88a/report.json`，五项均exit0、passed=true |
| visual-keyboard-farm-loop | 617/0，1280×800真实渲染；9张唯一截图 | `20261106-194828-keyboard-visual-travel-final-09cca9/report.json`，exit0、passed=true，无unexpected_errors；本轮画面目视审阅watered/full-bag/harvest-overhead/already-watered |
| visual-keyboard-building | 43/0，真实渲染，日志列3张截图 | `20261106-191403-visual-keyboard-final-no-instructions-5m-8295dd/report.json`，exit0、passed=true；仅引用[building设计](../building/spec.md)/[账本](../building/ledger.md)，未改building文档 |
| 关联通过回归 | keyboard-control30/0、control-feel31/0、camera12/0、click32/0、initial-planters247/0、walk-on-planters53/0、farm-day-change23/0、pocket-bubbles59/0、pocket-drag-buy44/0 | 200446报告均exit0、passed=true；整份报告18项均已有返回，14通过/4失败，不能称全绿 |
| 本轮承接历史过程失败 | interaction-reach35/1、dock-seed21/1、minimum-loop141/10、harvest-receive80/1 | 200446均exit1；旧角标、标题、直接harvest及下游断言契约，保留解释、不标范围外；已由下一行适配结果收口 |
| 四项契约适配回归 | interaction-reach35/0、dock-seed22/0、minimum-loop147/0、harvest-receive92/0 | `20261106-201957-keyboard-contract-regression-888baa/report.json`，四项均exit0、passed=true、completion_marker=true、unexpected_errors空；不再pending |
| 最终契约与口袋合批 | panels80/0、interaction-reach35/0、dock-seed22/0、minimum-loop147/0、harvest-receive92/0、pocket-bubbles59/0、pocket-drag-buy44/0；合计479/0 | `20261106-203447-keyboard-final-contracts-ff6d9f/report.json`，7项全PASS、exit0、completion_marker=true、unexpected_errors空；最终合批已完成 |
| 面板真实渲染（footer清理前批次） | keyboard-panels93/0（原80+layout/captures），1280×800真实渲染；4张截图 | `20261106-204809-verification-52bb38/report.json`，exit0、passed=true、completion_marker=true、unexpected_errors空；本轮画面目视审阅shop/map发现ac_card旧footer教程，当前源已删；清理后keyboard-panels-clean-final报告路径/结果待主补，不能以本批旧图声称最终无教程 |

用户无提示要求正式覆盖SEA-INTERACT-R18与SEA-UI-R52，主动系统帮助允许。当前生产源码已复核：`pocket_service.gd:247/281`分别仅显示上限/余额与动词数量，`pocket_inventory.gd:168`仅option.label；按1说明和动作数字前缀已删，原同步差异已解决，不再pending。200446隔离副本是清理前历史。`hud.gd:511`的无目的地拒绝反馈仍带Esc，单独保留源码事实，不以此把整个口袋清理写回pending。主线程keyboard-final-contracts已由203447报告确认7项全PASS、479/0，不再待附。旅行旧负Rect FAIL保留，`.abs()`修后194828/200446均通过，不再写修后待跑。

完整路径、截图清单、夹具与full-world/规划/设备边界见[总交付](../../development/2026-11-06_keyboard_complete.md)。四功能整体partial；本次只精确回填UI文档及总交付/GDD，不改其他账本、生产、资源哈希、用户TSCN或building文档，不运行sync。

UI条款集合差异已定位：门禁按`\| (SEA-UI-R\d+) \|`提取集合，原spec56项、ledger57项，唯一ledger-only为R53，正文“R53已占用”不构成条款行。spec末尾现补R53承接SEA-BUILDING-R32，ledger保留本行；R54–R57两边均各一行。verification数组既有keyboard/visual登记保留，未添加building未知入口。主线程最新sync已消除UI集合与unknown verification命名错误，不再将building未知命名列为当前阻塞。全局仍sync13 issues、普通check加derived stale共14；40功能/881资产/1079 runtime的当前登记与定向更新4资产/4runtime事实见总交付门禁补记。本次未刷新哈希/索引、未运行sync，不宣称全绿。
