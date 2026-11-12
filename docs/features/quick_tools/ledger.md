# SEA-QUICKTOOLS · 快捷工具环 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-quicktools) · [功能文档](spec.md)

## 登记头

```json
{
  "feature_id": "SEA-QUICKTOOLS",
  "status": "partial",
  "owner": "QuickTools / Main薄适配",
  "code_paths": [
    "godot/src/quick_tools/quick_tools.gd",
    "godot/src/ui/quick_tool_glyph.gd",
    "godot/src/ui/world_action_bubbles.gd",
    "godot/src/bootstrap/main.gd"
  ],
  "verification": [
    "quick-tools",
    "visual-quick-tools"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 最新证据 / 未覆盖边界 |
|---|---|---|
| SEA-QUICKTOOLS-R01 | 已实现 Alt 切换且不抢普通 world action 菜单；首次 release 前 non-echo duplicate Alt 锁与 echo 隔离，松开后再次按下才收起 | release-913ecd `quick-tools`116/0、`visual-quick-tools`266/0：首次未release连按/echo、关闭态echo不重开与普通菜单隔离通过；手柄及全设备未验 |
| SEA-QUICKTOOLS-R02 | 已实现陆地/船上分流；打开环不主动取消既有自动航线；手动键盘驾驶因菜单 modal 不再读驾驶意图，按既有 `release_drive` 自然减速，不承诺 manual sailing 状态不变 | 当前116/0、266/0覆盖陆地/船上上下文及既有航线相关断言；手动驾驶自然减速仅沿既有行为，不另称新增减速专项或全设备通过，不改 production 航行逻辑 |
| SEA-QUICKTOOLS-R03 | 已实现门禁、上下文变化关闭和窗口失焦关闭；动效遵循 SEA-UI 偏好 | 当前116/0、266/0：真实modal、标题、室内、房间过场、潜水切换、拾取中、sleeping、land→boat关闭及失焦通知通过；攀爬等完整状态/设备组合未单独穷举 |
| SEA-QUICKTOOLS-R04 | 已实现 76px 青绿/奶油边圆按钮与程序化白色剪影；角色屏幕锚点跟随、暖金 hover | 当前visual266/0及edge caption包围盒断言通过；30张PNG覆盖三分辨率×两上下文×五状态。主线程目检仅最终1280 land-open/1920 boat-hover及前轮1600两图，已审图无挡脸/裁切；用户最终美术确认、各体型仍pending |
| SEA-QUICKTOOLS-R05 | 已复用现有 world action 的 0.24s BACK、0.035s 错峰、0.16s 收起与动效偏好 | 当前116/0、visual266/0覆盖动效关闭即时态，真实展开/收起中间帧、hover及closed隐藏；不称30张逐图人工审完，目标设备完整动效体验未验 |
| SEA-QUICKTOOLS-R06 | 已加会话 token，旧回调在关闭动作前拒绝，不得关闭新菜单；取消退场中/后不执行；有效选中立即撤 modal 后复验上下文；读档立即 `close(true)` 并 invalidate | 当前116/0、266/0：同类重开、跨菜单替换、取消退场中/后旧命令、同类land读档立即失效、失焦旧回调及重复确认通过；不外推所有读档时序/设备组合 |
| SEA-QUICKTOOLS-R07 | 已转发既有建造/拆除入口；建造资格确认、退款与保护仍归 SEA-BUILDING | 当前116/0覆盖真实craft开book、remove选物、不提前扣费/退款；`keyboard-building`40/0回归通过，不把入口通过扩写为所有建造资格/退款/保护组合重新验收 |
| SEA-QUICKTOOLS-R08 | 已接最近 24m 鱼群与既有 1.6s 采集链；无鱼提示；无鱼竿小游戏实现声明 | 当前116/0覆盖24m外无鱼、近木头不抢鱼、原航行→采集计时→结算与重复推进不重奖；`ocean-pickups`48/0回归通过。满包鱼、重复目标等依赖边界未新增专项，不据回归计数虚构覆盖 |
| SEA-QUICKTOOLS-R09 | 已转发既有潜水入口；沿既有先停船语义，不复制 Dive FSM | 当前116/0覆盖航行中先停船提示及不切图、停船后先撤modal再一次request_dive/即时switching；`dive-transition`501/0回归通过，完整往返/失败回滚归依赖回归，不称快捷专项独立全验 |
| SEA-QUICKTOOLS-R10 | 不改用户手摆 TSCN/场景资源或存档字段；Main 通过代码真实创建并挂载运行时 `QuickTools` 节点，只做薄装配 | 当前116/0；`save-corrupt-seed`/`save-protection`均PASS（无数值计数），架构25/0另据主线程结果；隔离user://不改原save数据或main.tscn，不以“未新增节点”描述运行时事实，不外推所有坏档/存档边界 |

## 当前验收状态

状态保守维持 `partial`：代码与当前专项已完成，但全局登记门禁受范围外问题阻断，不能成功写回派生索引；用户美术及设备完整验收未签署，不等同于 `verified`。加固后正式 `20261112-123340-quick-tools-release-913ecd` 已完成：`quick-tools`116/0、`visual-quick-tools`266/0、`keyboard-building`40/0、`dive-transition`501/0、`keyboard-panels`81/0、`ocean-pickups`48/0，`save-corrupt-seed` / `save-protection`均PASS（无数值计数）；8入口均exit0、passed=true、completion_marker=true、unexpected_errors=[]。当前新增token、取消旧命令/退场、读档立即invalidate、失焦、non-echo Alt/echo与edge caption已通过当前专项，不再写待主测。

30张PNG覆盖3分辨率×land/boat×opening/open/hover/closing/closed。主线程ViewImage仅目检最终1280 land-open、1920 boat-hover及前轮1600两图，确认已审图无挡脸/裁切及青绿奶油边白剪影、暖金hover；不声称30张全目检。用户最终美术确认、手柄、各体型及表内未覆盖依赖边界继续pending。架构已PASS 25/0；全局sync/check曾84/85 issues，current_source_index仅定向补4条已修source index差异，最终sync为83项、check为84项，均exit1（check多派生索引过期）；脚本拒绝写回派生索引，不再有本功能状态/条款或source index差异。详见开发记录5.5。

首次44/1、validation的69/2与visual219/2，以及加固前final-d51e92的70/0、220/0及四项回归PASS均保留为[历史过程](../../development/2026-11-12_quick_tools.md#4-本次验证过程与加固边界)，不代替当前证据。正式报告对应head+working_tree快照、完整命令/日志/截图链接与警告边界见[最终验收](../../development/2026-11-12_quick_tools.md#5-正式-release-最终验收回填)：报告unexpected_errors为空不等于零警告或零泄漏，dive-transition保留9个ObjectDB实例退出泄漏警告。隔离user://不改原save数据，不改main.tscn；此次仅回填文档，不运行Godot、sync或统一runner，不改源码或资产hash。

## 变更记录

- 2026-11-12：创建独立规格与账本；登记 R01–R10，状态 `partial`，verification 使用 `quick-tools`、`visual-quick-tools`，等待主线程测试回填。
- 2026-11-12 加固回填前修订：纠正自动航线与手动驾驶减速、手摆场景资源与运行时节点的口径；R01/R06承接 duplicate Alt/echo、会话 token、取消退场及读档立即失效加固，补记失败过程与 final-d51e92 加固前证据；当时release待主线程最终复验，未运行sync/测试。
- 2026-11-12 最终验收回填：据release-913ecd正式报告登记8入口PASS、116/0与266/0等实际结果及30张PNG产出，逐R行替换已覆盖项的待主测，保留未覆盖依赖边界；状态更新为implemented（已实现待完整验收），用户最终美术确认/手柄/各体型仍pending。人工目检限主线程已审图片；全局sync/check最终结果待主线程独立补充，本次不运行sync/测试。
