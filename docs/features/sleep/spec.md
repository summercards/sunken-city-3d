# SEA-SLEEP · 睡觉与次日醒来

[主文档中控](../../../GDD_V1.0.md#sea-sleep) · [独立账本](ledger.md)

## 设计条款与验收标准

| 条款 ID | 规则 |
|---|---|
| SEA-SLEEP-R01 | 点击太阳房入口地毯的月亮检查点，角色按现有寻路接近后睡觉；岸上菜单的睡觉按钮使用同一命令。 |
| SEA-SLEEP-R02 | 23:00自动入睡，结束航行/行走/交互、关闭面板，次日06:00在太阳房入口醒来；午夜后旧档回到当天06:00。大delta不得跨过阈值跳多天。 |
| SEA-SLEEP-R03 | 睡觉使用黑色圆形向角色合拢、全黑显示次日早晨、圆形向外打开，不占角色对话框；睡眠态独立文件，过渡期间输入和日历暂停，重复点击只执行一次。 |
| SEA-SLEEP-R04 | 醒来06:00不提前卖货；07:00继续由DailyShipping唯一结算。过渡期间拒绝存档，醒后正常自动存档；读档不重复结算。（作物生长已于2026-11-01改为「醒来即换天」，见SEA-FARM-R14；本条只约束**卖货**仍在07:00，不约束生长时刻。） |
| SEA-SLEEP-R05 | 圆幕按屏幕像素距离计算，宽高比不使圆变椭圆；收拢0.85秒，完全遮黑后切换时间/位置，早晨文字在黑幕上显示，随后1.05秒向外打开。收拢和打开分别取角色屏幕位置；过场隐藏玩法UI，全开后恢复。 |

## 所有者与接口

SleepCycle拥有会话过渡，不拥有世界时间或经营状态。advance(delta)截断到23:00；request(automatic)开始一次睡眠；is_busy()给存档和输入查询；woke(snapshot)在淡入完成后发出。注入WorldClock、SleepCurtain、prepare和return_home命令。WorldClock.wake_to_morning是时间唯一写入口。

SleepCheckpoint只发sleep_requested；Main装配命令。ActorController.begin_sleep进入独立sleeping状态；restore_pose退出并恢复合法岸上位置与泊位。SleepCurtain只负责圆形遮罩、黑幕文字与输入消费；通过注入focus_query获取角色屏幕位置，不读取角色或时钟状态。

不保存动画进度；存档仍用time/game/economy原字段。暂停菜单停时；开始画面不会自动睡觉。开发全世界配置可结束潜水后回家，默认潜水仍锁定。暂不制作室内、床模型、睡姿动画、NPC收货动画。体力惩罚（见SEA-ENERGY）由Main在完全遮黑的这一段调用Energy.after_sleep(forced)，本功能不持有体力数值。

## 资产边界

复用太阳房入口与已有中文字体，月亮是临时检查点标记，不冒充正式床资产，不改建筑源和资产哈希。

## 验证

统一runner：sleep-cycle、visual-sleep-cycle、minimum-loop、framework-integration。视觉与退出码见[交付记录](../../development/2026-10-28_sleep_cycle_delivery.md).

2026-10-28：圆形睡觉/起床过场与逐阶段渲染验证见[本轮记录](../../development/2026-10-28_sleep_iris.md)。

## 2026-11-01 黑幕文字停留时间

用户反馈过场里那两句话「一闪就没了」。原来入睡文字淡入0.18秒、停0.3秒、淡出0.18秒，起床文字停0.65秒，读不完。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-SLEEP-R06 | 黑幕上的两段文字必须停留到「读得完」：淡入不少于0.4秒、完整可见的停留不少于2秒、淡出不少于0.4秒；起床文字的停留不短于入睡文字。圆幕的合拢（0.85秒）与打开（1.05秒）节奏不变，遮黑与切换时机的语义不变（时间与位置的切换仍在全黑、文字消失之后）。验收需实测而非只查常量：全黑后1.6秒两段文字仍处于完整可见状态。 |

验收证据：`sleep-cycle` / `visual-sleep-cycle` 额外断言 `COVER_HOLD`/`MORNING_HOLD` 与实测停留；见[本轮交付](../../development/2026-11-01_energy_fishery_and_join.md)。
