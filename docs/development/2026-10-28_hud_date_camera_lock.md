# 2026-10-28 月日显示与右下角色视角锁定

本次只承接SEA-UI-R39/R40、SEA-TIME-R11、SEA-CAMERA-R07。继续保留上一轮已确认的原白色加粗圆体、左下纯文字、右上图标菜单、笔记和手绘泊位。

## 本次变化

- 左下日期从“第41天”换为“2月10日”，时分与天气保留；瓶盖由36px缩到28px，与背包一致。去掉原左下两颗操作按钮。
- 右下72px圆形人物定位图标恢复原follow命令。青绿为锁定跟随、暖金为自由观察；拖动仍可接管，点击重新跟随。按钮无常驻文字，有悬停说明，颜色由OrbitCam真实状态回填。
- 停止行动按钮不再创建/注册，业务取消命令保留用于控制器；历史抓图工具的取消阶段改为明确调用命令，不再声称点击已移除的按钮。

## 日期与镜头所有权

在未指定初始月份的情况下，采用第1天=1月1日、固定365日显示循环。WorldClock.calendar_date纯查询使用常规月份长度（2月28日），query新增month/day_of_month并修改text；day/seconds/day_length快照完全保留。第366天显示1月1日但累计day继续366，晨次、休息、离线冻结和经济不受影响，不取电脑日期，不引入年份或闰年状态。笔记中读取query.text的今日信息同步更新。

图标只发出已有follow命令，Main继续调用cam.resume_follow。Main查询follow_enabled，经HUD.set_follow_locked更新表现；没有UI直接写镜头状态。镜头角度/FOV/缩放规则保持原值。暂停、笔记、其它模态、开始画面和睡觉继续隐藏镜头入口。

## 验证

所有运行经scripts/run_verification.py，在Autoload前隔离user://。完整路径、退出码和错误分类见同名JSON。

| 检查 | 结果 | 说明 |
|---|---|---|
| visual-corner-notebook | 87项 / 0失败，退出0 | Forward+ / RTX4060Ti，原生1280×800、1600×1000、1920×1080；日期/字号/右下布局、实际锁定点击、真实player目标、无世界移动穿透、手动观察状态、原菜单和笔记分页 |
| framework-modules | 50项 / 0失败，退出0 | 含1/31/32/59/60/365/366/730/731日、查询无写入、午夜跨月、原快照恢复 |
| camera | 8项 / 0失败，退出0 | 原手动拖动接管、恢复跟随及帧率阻尼 |
| click --full-world | 32项 / 0失败，退出0 | 原远区/建造开发检查需完整范围；更新HUD入口断言为follow且无cancel |
| minimum-loop | 77项 / 0失败，退出0 | 最小经营、种植、出货、旧档迁移/恢复 |
| sleep-cycle | 33项 / 0失败，退出0 | 06:00醒来、07:00结算和界面恢复 |

原生测试曾缺少鼠标移动事件，在手动观察后合成第一次点击时漏点；测试helper现按移动→按下→松开顺序并等待界面布局稳定，最终实际GUI点击通过。新增图标的一处Vector2类型推断编译错误已显式声明并重新验证。开发范围click在默认最小范围出现的3条失败由--full-world匹配测试范围后通过，未开放正式玩法范围。

以上通过项unexpected_errors为空；本次没有预期故障用例。触控/手柄设备未执行。

## 资产与文档

先从资产总索引定位UI分账本，修改前核对UI-HUD-CORNERS-001源及依赖的原登记哈希。只将该资产更新为v002，保留v001哈希与交付记录；只刷新已审阅的corner_hud.gd源及launcher_icon.gd依赖。旧图片、字体、灯光与其它资产哈希不变，已有图标授权pending不变。

主文档与UI/Time/Camera独立文档、账本已承接。结构检查sync/只读结果见同名JSON的contract_checks。

预览位于工程外：D:/projects/sea-work/hud-date-follow-20261028/main-interface.png、camera-locked.png、night-interface.png。
