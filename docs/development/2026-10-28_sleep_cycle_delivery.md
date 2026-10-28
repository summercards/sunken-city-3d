# 2026-10-28 · 点击睡觉、自动入睡与昼夜接入

[主文档](../../GDD_V1.0.md#sea-sleep) · [睡觉功能](../features/sleep/spec.md) · [独立账本](../features/sleep/ledger.md) · [光照记录](2026-10-28_daylight_sleep.md)

## 已交付行为

- 太阳房入口地毯增加月亮检查点。点击后可从停靠的小船自动上岸、按合法路径走近并入睡；岸上菜单“睡到06:00”使用同一流程。
- 23:00自动睡觉，取消行走、航行、交互和待领取目标，关闭面板、清除航线预览；淡出后回到太阳房入口，次日06:00淡入醒来。凌晨旧档回到当天06:00，不多跳一天。
- ActorController新增独立sleeping状态文件；SleepCycle只编排会话，WorldClock唯一写入时间，UI只做过渡。重复点击不重复跳日，超长帧在23:00截断，Esc无法卡住睡觉过渡。
- 06:00醒来不提前结算。作物生长与出货箱仍在07:00共用既有晨次水位线；仓库不自动出售。醒后日历在淡入前更新，时间、位置、待出货物均可存读，醒来正常自动保存，过渡中拒绝中间快照。
- 当前全部光影色彩保留为09:00基准；清晨06、中午12、下午15、傍晚18、夜晚21、深夜00为独立预设，平滑循环。太阳、环境、天空、雾、水体和反射统一读取时钟；开始画面保持09:00。基准写回、材质切回和午夜连续性有专项断言。

## 文件与资产

`src/time/sleep_cycle.gd`是睡觉流程；`sleep_checkpoint.gd`是点击适配；`src/player/states/sleeping.gd`是角色状态；`src/ui/sleep_curtain.gd`是过渡表现。`daylight_presets.gd`独立维护时段数值，`daylight_rig.gd`统一输出。Main只装配接口、停止现有动作和恢复家门位置。

门口标记复用现有建筑与打包字体，未新增模型源或冒充已验收床资产；没有批量重算资产哈希。保持稳定场景路径与既有存档v3字段。新登记SEA-SLEEP，相关TIME/OCEAN/MOVE/UI/SAVE/WEATHER账本已同步。

## 本轮实际验证

全部通过统一runner，Autoload前隔离用户数据；真实玩家存档未用于验证。完整路径、退出码、预期故障和实际错误见[机器记录](2026-10-28_sleep_cycle_delivery.json)。

| 验证 | 当前结果 | 证据目录末段 |
|---|---|---|
| daylight | 123项，0失败；最新真实渲染快照与当前三份光照代码一致 | 041422-sleep-wake-polish-5545e6；041648-verification-ec6906 |
| visual-sleep-cycle | 22项，0失败；实际鼠标点击、独立睡眠态、Esc拦截、超长帧、自动返家、存读、自动存档、航线清理、醒来日历 | 041422-sleep-wake-polish-5545e6 |
| minimum-loop | 77项，0失败；06醒来后07结算，三日种植/出货闭环 | 041216-sleep-current-final-778585 |
| framework-modules | 30项，0失败 | 041216-sleep-current-final-778585 |
| save-seed + framework-integration | 跨进程存档，44项，0失败；显式full-world | 041236-sleep-integration-4e5f2f |
| surface | 30条路线，503项，0失败 | 041236-sleep-integration-4e5f2f |
| farming | 31项，0失败 | 041236-sleep-integration-4e5f2f |
| visual-title-screen | 24项，0失败；开始画面不推进睡觉/时间 | 040837-sleep-light-render-2e6c8e |
| visual-weather | 七时段真实Forward+截图；已查看09、06、18、00及睡觉点/醒来画面 | 041648-verification-ec6906 |

最初一轮发生SleepCycle变量类型推断错误，已加显式类型；当时测试超时/失败记录保留。09:00新增断言曾因面板0.8写入32位属性与64位字典精度差失败，测试恢复原捕获基准且保留适当浮点容差。最终专项无预期故障，无脚本或着色器错误。

## 范围与未执行项

本轮验收为Windows、RTX 4060 Ti、Forward+。移动端/Web、触控/手柄、GL后端未专项重跑；没有制作室内、床模型、睡姿动画、NPC收货动画、季节或体力惩罚。23:00后正常玩法进入睡觉，因此深夜预设通过冻结时钟的渲染专项验证。

## 最后结构检查

此前33功能、429源资产、317运行资源检查通过。收尾再次运行--sync时发现两份场景动物脚本与资产分账本哈希不一致：SEA-DECO-ANIMAL-FISH-SCHOOL、SEA-DECO-ANIMAL-WHALE。这两份代码在本轮睡觉交付之外发生变化；暂不覆盖它们或批量重算哈希，最终检查结果继续记录。睡觉及光照专项已通过。

最终复跑：`20261028-085413-sleep-delivery-current-6616e1` 的visual-sleep-cycle真实渲染22项/0失败、退出0，当前整场景无脚本/着色器错误。两次最终结构命令（--sync及无参数）均退出1，只报告上述两个动物资产源哈希差异。差异已逐文件查看（鱼群注释与鲸鱼水下材质变化）；没有签署其动物资产专项验收，也未改写未知哈希。
