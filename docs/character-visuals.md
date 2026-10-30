# 角色表现契约

## 当前正式Godot角色（2026-10-30）

运行消费者为`godot/src/player/character.gd`，继承CharacterMotor；`scenes/main.tscn`启动后由Main/ActorController接线。碰撞及人物根移动由CharacterMotor/ActorController拥有，表现使用BodyPivot、HeadLook、双肩→双肘、双髋→双膝的现有程序节点，不是Blender骨骼角色。

创作/运行尺寸沿用现有米制、根缩放1、+Y上/+Z前，胶囊半径0.22m/高1.30m；帽顶约1.35m。没有本次角色Blend/GLB或骨架ID，原角色整体生产登记仍pending，不套用ShellStorm2双母版或1.5m契约。

获物动作源`godot/src/player/animation/item_receive.gd`以既有`harvesting`注册动作采样，2.4秒。`play_action(id,context={})`接独立上下文；`play_receive_item(crop_id)`或`play_farm_action(event,payload)`复用。正文动作条款为SEA-MOVE-R14：代表实物中心最高1.60m，双手扶住底部，右侧挎包中心(0.29,0.49,0.08)、包口约0.64m。肩抬高与袖长只在表现节点内调整，结束/中断恢复，碰撞和根变换不动。

实物来自`godot/src/crops/harvest_visual.gd`复制成熟阶段网格，角色拥有临时节点ReceivedItem。不附加碰撞，不转移原种植物，不改网格材质，不把代表实物份数当成产量。FarmPlot成功事件是当前接线入口；满包、未成熟或中止准备均不触发。物品数已由Farm唯一写入，动画信号不能发奖。角色/物品临时节点不序列化，读档取消动作。

新资产`SEA-CHAR-RECEIVE-001`由`assets/registry/ledger_index.json`路由到characters分账本，清单`assets/registry/manifests/sea-char-receive-001.json`。专项、真实渲染及回归见[本轮交付](development/2026-10-30_harvest_receive_animation.md)。

## 历史网页原型契约

主角为女性探险者：侧分刘海、固定侧辫、柔和五官与合身橙色服装；潜水时保留辨识发型，侧辫避开背部气瓶。

本项目为 Three.js 程序模型，制作源为 character-art.js，无 Blender / GLB 中转资产。

- gameplay.js 持有 explorerGroup（移动、朝向、场景归属）与 explorerBodyPivot（表现姿态）。本次保留已有肩、髋、工具节点和地面状态机。
- 原点、世界尺寸沿用已有角色，局部 +Y 向上、+Z 向前。潜水维持既有 1.25 根缩放。
- refineCharacter 添加头部、肘、膝、踝节点，细化几何和服装、面部、潜水装备。新增节点通过 swimParts.detail 提供给 diving.js。
- createSwimAnimation 只驱动表现节点，不改变移动速度、导航、碰撞或宝箱判定。前游按水平速度混合姿态；垂直速度调整俯仰；入水、出水、搜寻具有独立姿态目标。
- 入水缓存全部动画节点的局部位置和旋转，出水逐项恢复；面罩、呼吸器、气瓶和脚蹼仅潜水时显示。气泡发射点取呼吸器世界坐标。
- 保持现有海面走路、划船、工具动作的肩髋控制。高细分仅限主角，场景模型不变。

验证：tests/character-animation.cjs 检查速度倾角、左右膝相位差、出水关节和装备恢复，并输出前游、悬停、下潜、上浮近景。tests/diving-regression.cjs 验证完整潜水玩法和岸边/船上恢复。
