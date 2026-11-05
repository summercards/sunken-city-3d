# 操控手感修订：加减速、阻尼与前视（2026-11-05）

[主文档](../../GDD_V1.0.md#feature-control) · 承接 SEA-MOVE-R23 / SEA-CAMERA-R14 / SEA-NAV-R17 / SEA-INTERACT-R14

## 起因

上一轮把方向键从「移镜头」改成「走人」，能用，但**手感是硬切的**：速度一帧到位、
松手一帧归零、船头按角速度限幅直接甩。用户要求把这一层补上：

> 细腻手感和阻尼这些一并帮我调整了，让操作更加丝滑，进阶感更好。

## 一条原则

所有平滑都用**时间常数**，不写「每帧乘 0.9」：

```
v ← v + (v_target − v) · (1 − e^(−Δt/τ))
```

这样 30 / 60 / 120 FPS 走出同一条曲线（实测 0.4 秒位移 0.762 / 0.745 / 0.736 米，
差 3.4%，来自指数积分离散化，不随时间累积）。

## 参数与推导

### 角色（SEA-MOVE-R23）

| 参数 | 值 | 依据 |
|---|---|---|
| `ACCEL_TAU` | 0.085 s | 63% 在 0.085 s、95% 在 0.25 s 到速。低于 0.06 像被弹出去，高于 0.12 按一下没反应 |
| `DECEL_TAU` | 0.055 s | 滑行距离 `s = v·τ = 2.3 × 0.055 ≈ 0.13 m`；停要果断，起要柔和，反过来像冰面 |
| `STOP_SPEED` | 0.05 m/s | 指数收敛到不了 0，低于此判站定，避免永远 0.001 m/s 地爬 |
| `REVERSE_FLOOR` | 0.35 | `scale = 0.35 + 0.65·(cosθ+1)/2`：180° 只剩 35% 推进，先转身再走 |
| `FACING_TAU` | 0.075 s | 朝向追速度方向；比位置略慢，转弯时肩膀有领先感 |
| `MAX_STEP` | 0.05 s | 单帧最多消费 50 ms，卡顿后不会一步跨出半米 |

**弧线转身**：目标速度按输入方向与当前速度方向的夹角折减，速度向量再指数追过去。
180° 反向时第一帧仍在原方向减速（实测 `dot = 0.55+`），0.5 秒后才真正反向 ——
这就是「人转身」和「贴纸翻转」的区别。

**步频耦合**（`Character.walk_speed_ratio`）：走路相位原来吃 `_t*6.4`，不管走多快腿都一个频率；
现在由地速驱动：`rate = 6.4 × clamp(v/2.3, 0.35, 1.35)`。满速仍是 6.4 rad/s（观感不变），
半速 3.2 rad/s（实测 3.20）。停下相位归零，重新起步从脚下开始 —— 脚不再打滑。

### 镜头（SEA-CAMERA-R14）

| 参数 | 值 | 依据 |
|---|---|---|
| 位移继承 | — | 主体走多少，视点先跟多少，阻尼只收敛残差。旧实现匀速段恒定滞后 `v·τ = 2.3 × 0.27 ≈ 0.62 m`，现在实测 0.016 m |
| `LEAD_PER_SPEED` | 0.52 s/m | 前视 = 速度 × 0.52；走路满速 1.19 m，让画面提前看到「要去的地方」 |
| `LEAD_MAX` | 1.4 m | 上限：38 m 机位下约占画面高度 6.6%，再多会让人觉得人不在中心 |
| `LEAD_TAU` | 0.32 s | 缓入缓出；反向时自然回零，不甩镜头 |
| `SUBJECT_VEL_TAU` | 0.12 s | 位置采样有 1–2 cm 抖动，不滤会放大成镜头晃动 |
| `TELEPORT_STEP` | 8 m/帧 | 读档/上下船/调试传送不参与速度估计，否则会得到一个假的巨大前视 |

前视只在「跟随 + 室外」加；手动接管、固定机位、房间环视一律不加 —— 玩家自己拖好的构图
不该被角色移动重新拽走。

### 船（SEA-NAV-R17）

| 参数 | 值 | 依据 |
|---|---|---|
| `TURN_ACCEL` | 4.6 rad/s² | `1.8 / 4.6 ≈ 0.39 s` 从静止到满舵：桨先入水、船头再跟上来（实测第一帧 0.077、0.2 秒 0.92 rad/s） |
| `TURN_AT_REST` | 0.55 | 舵效随船速：停船 `1.8 × 0.55 = 0.99 rad/s ≈ 57°/s`，满速 100%。划桨船停着也能小角度摆头，但不是原地打方向 |
| `DRIFT_TAU` | 0.16 s | 航迹方向滞后船头；稳态偏角 `min(ω·τ, DRIFT_MAX)` |
| `DRIFT_MAX` | 0.14 rad ≈ 8° | 上限：满舵实测 6.9°，转弯有一点「甩」，但不会像冰面 |
| `BRAKE_TAIL` | 0.35 | `decel = 3.0 × (0.35 + 0.65·v/v_cruise)`：最后半米用 35% 减速度收，贴上去停稳而不是最后一帧顿住 |

松手实测滑行 1.48 米（2.6 m/s 起），停稳后退出手动、由 SEA-MOVE 切回 `boat_idle`，不回弹。

### 上下船去抖（SEA-INTERACT-R14）

`BOAT_KEY_COOLDOWN = 0.35 s`：切换是一次性动作，走位到一半再按一下会立刻反向
（刚上船又上岸）。0.35 秒够过场起势，又不会让有意连按失效。

## 实测

`python3 scripts/run_verification.py control-feel` —— 新增专项，**31 项 0 失败**，退出 0。
同一次运行的指标（脚本自己打印，不靠回忆）：

```
v_first 0.41 m/s      v_at_0.25s 2.18 m/s    glide 0.105 m
travel@0.4s 0.762 / 0.745 / 0.736 m  (30/60/120 FPS)
walk_rate_full 6.17 rad/s            walk_rate_half 3.20 rad/s
lead 1.19 m           residual 0.016 m      (旧实现约 0.62)
yaw_rate 第一帧 0.077 → 0.2 s 0.92 rad/s     drift 6.9°
boat_glide 1.48 m
```

覆盖条目：起步曲线、滑行距离、反向弧线、`ashore_idle` 收尾、停稳不自走、
30/60/120 FPS 位移一致、步频满速/半速/归零、镜头前视与回落、匀速段零滞后、
船转向惯性、侧滑上限、软收尾不回弹、E 键去抖。

回归（同一工作区实测，非历史结果）：

| 套件 | 结果 |
|---|---|
| control-feel | 31 项 0 失败 |
| keyboard-control | 退出 0（停住断言改为「0.35 秒内停稳且不再滑」） |
| camera / click / walk-facing / walk-deck-fit / board-click / dock-seed | 退出 0 |
| character-motor / ground-space / actor-presentation / harvest-receive | 退出 0 |
| framework-integration / character-space-save / rowing-fit | 退出 0 |
| boat-water-contact / ocean / walk-on-planters | 退出 0 |
| visual-walk-facing / visual-camera-zoom | 退出 0（真实渲染） |

### 未通过项：`surface` 与 `selftest`

- `surface`：511 项 2 失败（`上岸高度与地面一致`、`种植物件是独立场景 home_plot`）。
  读的是场景与种植数据，与运动手感无关；上一轮同样是这两条（另有一条木桥连通已由别处修复）。
- `selftest`：491 通过 / 26 失败。**为了判断是不是本轮引入的，做了对照实测**：
  把本轮 11 个文件临时回退到 HEAD（上一轮键盘版本），重跑得到**完全相同**的
  491 / 26 与逐条相同的失败清单（`diff` 为空），随后原样恢复。
  失败集中在菜箱数量、zone 配置、泊位两两可达、种植链与采集冷却等场景/玩法数据上。
  
  注：另建 `git worktree` 跑 HEAD 做基线不可行 —— 工作树缺少被 gitignore 的生成资产
  （`rooftop_ranch` 的 balcony/weather 组件），场景加载即报错。所以改用「回退文件 + 重跑 + 恢复」。

## 边界与未完成

- 键盘只有满速档：没有模拟量输入，也没有「走/跑」切换。手柄摇杆与触屏方向盘未做。
- 前视按主体位移估计速度，斜坡上高度变化会被 `y=0` 滤掉 —— 这是有意的（前视只服务水平构图）。
- 点击走路的起步没有加缓入（只有键盘自由行走有），避免影响既有「按航点匀速推进」的
  到达判定与 42 条路线的回归基线。要加的话，需要连 `walk_action` 的到站判据一起重算。
- 室内房间（SEA-ROOM）的键位行走仍未单独实测；相机在 `orbit_only` 下也刻意不加前视。

### 条款 ID 撞号与更正

追加时发现同一天另一轮改动已经占用了三个号：`SEA-CAMERA-R13`（瞄准高度随 `SCALE`）、
`SEA-MOVE-R22`（放大后的玩法契约）、`SEA-NAV-R16`（重解双桨装配）。本轮三条已改为
**`SEA-CAMERA-R14` / `SEA-MOVE-R23` / `SEA-NAV-R17`**，代码注释、spec、账本、主文档与本文一并更名。
教训：新条款落笔前先 `grep -rhoE "SEA-<功能>-R[0-9]+"` 取当前最大号，不要按自己记忆加一。

### 文档门禁

`python3 scripts/check_feature_contracts.py --sync` 退出非零，剩 5 项，**都不是本轮的**：

- `SEA-SCENE-ORF-ASSEMBLY: source hash drift`
- `runtime hash drift: godot/assets/materials/ocean_sky.tres`
- `runtime hash drift: .../neon_garden_quarter/poster_atlas.png.import`
- `runtime hash drift: godot/tests/test_sunken_city.gd` / `godot/tools/capture_sunken_city.gd`

本轮动到的 4 个已登记运行资源（`main.gd`、`orbit_camera.gd`、`character.gd`、`walk_action.gd`）
已经按审阅流程更新 `sha256` / `bytes` / `previous_sha256`，并在 `hash_history` 里留了
"reviewed in 2026-11-05_control_feel.md" 的记录 —— 不是静默刷哈希。
`boat.gd`、`follow.gd`、`actor_controller.gd`、`walking_action.gd` 不在运行资源清单里，无需登记。

由于脚本只在 `issues` 为空时才写派生索引，`docs/generated/feature_index.json` 保持上一版并报 stale，
这是哈希漂移的连带结果，不是本轮漏跑同步。
