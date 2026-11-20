# 2026-11-19 · 潜水游感与障碍缓冲

[SEA-DIVE-R76–R81 规范](../features/dive/spec.md#dive-swim-feel-design) · [潜水账本](../features/dive/ledger.md#dive-swim-feel-ledger) · [SEA-MOVE-R33–R36 规范](../features/move/spec.md#move-dive-swim-feel-design) · [移动账本](../features/move/ledger.md#move-dive-swim-feel-ledger)

## 实施边界

本轮已接入正式 Godot 工程。家园海底与旧九图共享 Controller 和同一套潜水动作，各图使用独立潜水 `Character` 实例，复用现有 21 骨蒙皮。Controller 解释原有输入、结合只读净空和实际位移驱动表现；Map 仍执行原碰撞及滑移；Character 只采样姿态和装备，不写根位移。家园用玩家现有胶囊查询实际物理代理和地形；旧九图用现有实体/地形判阻和路径子步估算可走距离，不输出精确法线，两者的净空精度不能等同。

这批只做游动、收势和脚蹼，不重绑输入，不改变场景布局、保存结构与门禁、Air 或出入水事务；不增加强制弹开、震屏或伤害。脚蹼为原创低模程序网格，随现有 `Foot` 关节走，不另加碰撞。开阔水域保留巡航 4.2 m/s、冲刺 7.0 m/s；对齐时倒游上限 2.7 m/s。水平方向净空探测 1.65 m、向下 1.32 m，线性时间常数平滑防护混合，刹停和推进仍消费碰撞实际位移。入水采样 Map 既有进度产生折身和抬腿，稳定水中 Q 则以实际下行速度混合到头先姿态，不重播折身段。

## 动作参考与游戏化转化

| 参考 | 本项目采纳的视觉线索 |
|---|---|
| [FreeDive International：Duck-Dive Like a Pro](https://freediveinternational.com/freediving-training-tips-6-duck-dive-like-a-pro/) | 以页面首个 slow-mo 和后两段作对照，看上身先转、腿后到的先后关系，以及过早踢动会破坏轮廓。转成清楚的游戏剪影：静态预备与头先动作分开，躯干先给方向，腿后抬，实际下行时才有小幅蹼动。 |
| [Romblon Freediving：How to Duck Dive in Freediving](https://www.romblonfreediving.com/blog/duck-dive-in-freediving) | 取由折身到流线的轮廓对比；转成入水和水中 Q 共用的姿态顺序，之后回到水平巡游，不照搬现实动作角度、时长或操作步骤。 |
| [DAN：Mastering Neutral Buoyancy and Trim](https://dan.org/?p=23198) | 以 trim 区分贴底水平收腿抬脚与头上脚下姿态；以 back kick 区分保朝向后退与翻身前游；以 helicopter turn 借鉴保持水平的转身剪影，不新增独立按键或专用旋转状态。 |

以上仅作虚构游戏的动作观察与对照，不导入或复用外部素材，不是现实潜水训练指南。

## 可复查验收矩阵（待实施）

后续统一用 `scripts/run_verification.py` 在 Autoload 前隔离用户数据。表中入口是计划复用的现有入口；新断言或样例是否已加入、是否执行，均以最终报告为准。复查记录应能定位地图 ID、入口/夹具、起始朝向、输入序列和时间轴，并把物理轨迹与真实画面按帧对齐。固定帧率和体型采样用于对照，不替代手感目检。

| 用例 | 操作与判据 | 预计入口 / 证据 |
|---|---|---|
| 十图共享与动作隔离 | 按正式目录逐图走到 `swim`，核对 Controller 脚本相同、每个 runtime 只有一个控制器推进、潜水 Character 与海面角色不是同一实例。验证脚蹼随脚、无新增骨或碰撞形状，退回陆地或船上后无脚蹼/水中姿态残留。 | `dive-maps`、`visual-dive-maps`、`avatar-skinning`、`actor-presentation`；逐图矩阵、骨骼/装备检查及近景。 |
| 开幕与头先顺序 | 走正式入水并逐帧对齐 prepared、opening、幕完全退场、`release_entry`、`swim`：opening 首尾及中间帧根位不变、无踢蹼、Air 冻结；释放后侧视能分辨上身下转、抬腿、流线/小幅踢蹼、回水平的顺序。另在稳定 `swim` 按 Q、松 Q，并在下行受阻处复验：有头先轮廓、不重进过场，受阻不持续假踢。 | `dive-transition`、`visual-dive-transition`、`dive-control`；时序日志加连续侧视，静帧不代签。 |
| 前游、滑行与倒游 | 开阔处固定操控参考前向，按 W 后松键，记录实际位移与髋、膝、踝相位先后，以及推进和收势滑行；角色与前向对齐时按 S，核对仍朝原前方而实际速度向后，近景可辨倒蹼。改侧向和其他反向输入，确认能自由平滑转身。回归原键位、点击路线/拖拽区分与手动取消。 | `dive-control`、`visual-dive-control`；输入、朝向、实际位移和骨姿/蹼姿帧序列。 |
| 来墙与擦墙 | 在家园和旧图分别选既有实体，保持同档推进，对比开阔、正对墙逼近和斜擦。记录查询方向、净空和碰撞后位移；查询前后位置相同，逼近净空缩小时可看到撞墙方向减速和收臂，斜擦仍按原地图滑移，不产生强制推离。跨图对照不把旧九图的近似子步写成精确法线。 | `sunroom-collision`、`dive-maps`、`dive-control`；胶囊/旧判阻、距离与位移日志，连续近景。 |
| 海床、挡停与离障 | 取家园和旧图现有海床点位，比较离底巡游、向底逼近、贴底游、完全挡停和撤离。贴底躯干保持近水平且踝/蹼相对抬起，挡停时记录实际位移与停止推进循环，持续按键也不空踢；掉头离障可移动且防护姿态淡出，不弹开、不震屏、不伤害。以五组体型和 30/60/120 FPS 抽查真实连续画面，分别记录网格穿插、踢蹼和恢复，不代签全网格。 | `dive-control`、`visual-dive-control`、`sunroom-collision`；地形样点、位移与混合轨迹、侧面/背面录像。 |
| 生命周期与保存回归 | 核对正常上浮、缺氧返回及既有失败回滚仍走原事务，恢复同一 Main 和原圆幕；冻结与解锁边界、保存门禁及存档结构不变，场景与用户手摆未改。 | `dive-transition`、`framework-integration` 及适用的既有存档入口；报告和范围差异。 |

<a id="dive-swim-feel-signoff"></a>
## 当前验收和范围

在 macOS 用 `GODOT=/Applications/Godot.app/Contents/MacOS/Godot python3 scripts/run_verification.py <入口> --label <批次>` 隔离执行；报告根为工程外 `/Users/zyq/work/sea-work/verification/`。下列有效入口均 exit 0，无预期故障、非预期错误或资源泄漏记录。

| 批次目录 | 有效证据 |
|---|---|
| `20261119-160522-swim-control-delivery-817b2e` | 头部/骨盆/双脚世界位置、前后输入、蹼关节相位、近障与撤离：`dive-control` 466/0；Metal Forward+ `visual-dive-control` 494/0，五个动作侧拍＋两幅地图实拍。 |
| `20261119-160145-swim-final-behavior-0e0eee` | `dive-transition` 504/0、`dive-maps` 873/0、`sunroom-collision` 2824/0、`avatar-skinning` 80/0、`framework-integration` 52/0、`save-seed` exit 0。此批 `dive-control` 因不规则墙面法向夹具假设失败，exit 1，不算有效入口。 |
| `20261119-160145-swim-final-visual-d06d9d` | Metal Forward+ `visual-dive-transition` 408/0；家园 21 张连续入水帧＋过场截图，`dive-entry-head-first.mp4` 从实际帧合成。该批 `visual-dive-control` 的同一中间断言失败，exit 1，由最终操控批覆盖。 |
| `20261119-160815-swim-surface-regression-b6b091` | `actor-presentation` 31/0。 |

家园和 zone1 的近障测试均为真实塔墙/街面及既有楼体/地台，未使用备用夹具。家园靠墙从 3.96 降至 0.79 m/s，接触后保留约 0.22 m/s 的低速擦移，蹼相位冻结；家园贴底从 4.05 降至 0.62 m/s 后实速归零。中间轮次把不规则面擦移误作轴对齐完全挡停；现以独立的慢擦和完全挡停两组判据验证，不删除失败历史。对齐倒游实测 2.67 m/s、方向保持点积 1.0；前游膝和踝分别约滞后 0.61 rad。抽看了家园入水、Q 下潜、倒蹼、靠墙收臂、贴底收腿；建筑边角附近仍不能由抽样图证明全网格零穿插。

未验：五体型、30/60/120 FPS 完整矩阵、全地图人工路线、低端硬件、Compatibility、持续性能及用户手感终审；本轮没有新增打捞、摄影或捕鱼。`check_placed_positions.py` 检查 6 处均通过。全库 `check_feature_contracts.py --sync` 和只读检查均 exit 1，历史断链、资产登记/哈希漂移和派生索引仍阻塞。`character.gd` 与家园碰撞脚本的登记哈希在本轮前已不匹配 HEAD，不靠批量重签掩盖；未写派生摘要。
