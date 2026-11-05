# 角色表现契约

## 2026-11-05 整体尺度 SCALE = 1.5（放大 50%）

`godot/src/avatar/avatar_dimensions.gd` 现在是唯一的尺寸开关：`const SCALE := 1.5`。骨骼关节（肩 `1.240` / 髋 `0.678` / 头心 `1.650`）、体型因子派生量、四肢蒙皮剖面、获物解算、划船坐姿间隙全部读取它；头部、礼帽、躯干球这些**自身已在局部缩放的子节点保留参考尺寸**，不得二次相乘。

实测外形：站立发顶 **1.869 m**、礼帽顶 **2.050 m**、最坏（礼帽 + 头大 1.12）**2.154 m**。房间门洞净高 2.06 m（SEA-ROOM-R03），默认外观余 1 cm，最坏组合会穿门楣 9.4 cm，已登记为已知限制（SEA-ROOM-R15）。

**胶囊与导航 agent 半径不跟着放大**：仍为 0.22 m / 1.30 m（`SEA-AVATAR-R27`）。把它们改成 0.33/1.95 的实测后果是导航网格把木桥与窄栈桥挖空 —— `surface`「木桥连接可达」失败、`landing-markers` 3 项失败。玩法可达性优先于「代理人恰好包住身体」；代价是极近距离贴墙时肩膀可能轻微压进墙里，在 77.8 m 俯视下不可见。

连带项（同一轮改完）：桨架与桨轴沿 +Z 前移到 z=0.73（`SEA-NAV-R16`，握点回到肩前 0.309 m）、相机跟随瞄准高度 0.7→1.05 m（`SEA-CAMERA-R13`）、头顶进度条抬升 1.35→2.025 m（`SEA-PICKUP-R20`）、到达与捏人肖像取景按 `SCALE` 缩放。

[完整推导、连带清单与实测数据](development/2026-11-05_character_scale_150.md)

## 2026-11-04 坐船与双桨接触

SEA-MOVE-R18 / SEA-NAV-R13：运行消费者仍为Character→rowing_action→LimbSkeleton，米制、根缩放1、+Z面向船尾、胶囊与21骨契约保持。Boat通过注入的`rowing_pose_query`提供`RowingSeat`世界变换及左右`Grip`世界位置；`rowing_query`保留原相位/出力。坐点在中排座板前半部（船局部0,0.6025,0.32），BodyPivot绕髋部微倾，腿朝前屈膝且避开板沿；纯表现跟随Model摇摆，不改玩法根。上船位置只由`Boat.boarding_position()`提供，停船仍坐着；岸上/潜水切回原动作并完整清除坐姿平移。双手使用当前体型的上/前臂长度解算，未借伸长补偿；未改角色网格、蒙皮、骨名或原始Blend/GLB。桨的长度/偏移由正式TSCN维护，角色不得反向拖桨轴。[实际网格接触与渲染证据](development/2026-11-04_rowing_seat_and_grips.md)。

## 当前正式Godot角色（2026-11-02）

**最新四肢契约：** 身体/头部仍使用既有表现容器，四肢已改原生Skeleton3D+Skin。BodyPivot下LimbSkeleton拥有21骨和4张连续闭合ArrayMesh；肩肘/髋膝节点只提供不可见姿势输入，旧分段胶囊、关节球、独立手脚实体已移除。每条手臂含手、每条腿含脚在同一连通网格内；袖口/裤脚/鞋底仅为同网格的着色分区。实际资产SEA-CHAR-RIG-001，节点、骨名和绑定见art_source/characters/avatar/v002/rig_contract.json。参见[本次骨骼交付](development/2026-11-02_avatar_limb_skinning.md)。


新增独立SEA-AVATAR：程序模型由`godot/src/avatar/avatar_visual.gd`与`avatar_catalog.json`制作，按用户指定图冻结宽头脸/窄肩腰/腿脚比例；18槽位/95选项，颜色和几何分开，服装条纹通过贴身材质生成。帽子遮盖高发髻，不删除所选发型ID；脱帽恢复。面部/服装/配饰均为原创程序几何，无动物之森现成资产。旧单一橙色角色外观已替换，原节点动作、工具、挎包和潜水装备仍由既有消费者拥有。

米制、根缩放1、+Y上/+Z前；胶囊0.22米/1.30米不变。头部中心1.015米，基础脸部含耳宽约0.73米、头脸高0.44米；无帽发顶约1.26米，礼帽顶约1.39米。肩半宽0.162米、髋高0.42米；静止尺寸表同时供腕部求解使用。制作源直接在Godot，可维护Blender母版不适用于本次程序角色；没有声称制作或审计Blend/GLB。新生产ID `SEA-CHAR-AVATAR-001`，旧动作`SEA-CHAR-RECEIVE-001`原样复用。功能根与碰撞资源前后相同，动作回归见[本轮交付](development/2026-11-02_avatar_and_arrival.md)。

以下保留2026-10-30动作基线，旧帽顶/整体登记pending描述仅针对当时单一外观；现时外观以本节和SEA-AVATAR文档为准。

运行消费者为`godot/src/player/character.gd`，继承CharacterMotor；`scenes/main.tscn`启动后由Main/ActorController接线。碰撞及人物根移动由CharacterMotor/ActorController拥有，动作保留BodyPivot、HeadLook、双肩→双肘、双髋→双膝作为姿势控制，四肢由新Skeleton3D/Skin真实蒙皮；本次为Godot程序骨骼，不是Blender导出骨架。

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

2026-11-02用户指定图修订：原图和人工标点位于art_source/characters/avatar/v001；六项实际网格投影与等高对照、正面、侧面自验由avatar-proportions/visual-avatar-proportions提供。以本次比例追加验收替代此前通用头身估计，详见SEA-AVATAR-R13和本轮交付。

## 2026-11-04 追加：自然握桨与连续肘轴

用户指出上一轮到点后手臂仍扭转。SEA-MOVE-R19 / SEA-NAV-R14覆盖旧参数：中排坐点不动，桨轴与桨架沿角色+Z方向前移19cm到z=0.55m，握点完整周期在肩前。`rowing_action.pose_arm`令上下臂共用由两骨弯曲面得到的肘轴，禁止按世界X正负强制翻轴；前臂仅绕共同肘轴屈伸，当前体型臂长保持。必须同时检查关节角、相邻采样轴连续性、实际手掌距离及正式近景，不能只以手掌对齐判自然。骨骼/网格/绑定和表现唯一写入者不变。[本轮修正与证据](development/2026-11-04_rowing_arm_direction.md)。
