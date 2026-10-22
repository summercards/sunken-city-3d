# 地面、泊位、种植与航行

正式布局在 `scenes/zones/zone*.tscn` 中管理；保持现有海面、岸线数据与航行网格结构。

```text
Zone
├─ Models                  建筑与平台模型
├─ WalkAreas
│  └─ Walk_*               统一行走地面：rects / polygons / surface_y
│     └─ Landing_main      上岸点；脚下高度直接取父地面
│        ├─ BoatPark       停船位置和船头朝向
│        └─ DockEdge       屏幕泊位标记的位置
├─ Objects
│  └─ FarmBed              独立 farm_plot.tscn 实例 + farm_bed.gd
│     └─ Cell1…Cell6        farm_cell.tscn + farm_plot.gd
└─ Plants                  装饰植物
```

## 编辑约定

- 地面范围只编辑 WalkArea。矩形与多边形是同一地面的并集；没有连接的平台不能直线跨过去。高度继续沿用当前平台的站立面配置。
- 泊位挂在对应 WalkArea 下；Landing 节点的 XZ 是上岸位置，Y 取地面高度。BoatPark 和 DockEdge 是其子锚点。运行时 Zones 从场景登记泊位与行走范围，标记和导航不再另读一套泊位坐标。
- 菜箱引用 `scenes/props/farm_plot.tscn`，在区块 Objects 下独立摆放；床脚本管理六格 ID，地格脚本负责外观及交互，FarmModel 负责作物状态。每张床必须有唯一 plot_id，并填写 zone_id、名称与解锁前置。
- FarmField 仅做登记和信号转发，不再根据 plots.json 重新生成/覆盖位置。现有 plot_id 未改，保留存档中的作物。
- zones.json / plots.json 保留原型与无场景测试基线，正式运行以场景节点为准。不要通过旧的整区生成流程覆盖手工场景；build_zone_scenes.gd 只替换标记包围的模型段，保留其余节点。
- 此次没有重建建筑碰撞或台阶物理。地面仍是显式定义的导航面；模型改动后须同步检查可走范围。

## 行走与上下船

角色从当前泊位的上岸点落地，然后沿同一地面上的可见图路径行走。路径的每一段必须全部位于地面并集内，凹角绕行，不连通则拒绝。船必须实际停在泊位附近；不能在远处直接点地面上岸。

离岸时先沿地面走回同一上岸点，到位后上船再执行航行。点击当前泊位可上岸/回船；直接点击水面或其它目的地也使用这个流程。重新点击地面或按 Esc 可以取消待执行的出航。

主码头至菜箱的旧行走范围缺少已有木桥，这次按 harbor-layout.js 中木桥的实际 XZ 轮廓补入 polygon。打捞台停船点向外挪 0.65m，消除其与既有岸线安全间距的冲突。其它区块造型不变。

## 航行

- 沿用原岸线 A* 网格；首尾段不满足水域间距时，按同一岸线规则建立更细的可航网格重规划。无路明确失败，不回退穿岸直线。
- 校验可通行后才把折线角做成相切曲线；窄处保留折线并提前降速。
- 按航路弧长推进，避免船头转不过来而漂进岸线；每步仍检查水域。
- 转向限速、加减速连续、靠岸按剩余距离收速。终点误差小于 1.5cm 才完成，不进行末段位置吸附。
- 中途改道保持当前速度。手动停船保持结束航向，不掉头恢复起航朝向。
- 桨频约 0.65–1.1 次/秒，收桨连续混合；人物、双桨、船体摇摆共用划桨相位。

## 验证与演示

一键验收：在 godot 目录运行 `bash verify_surface.sh`。最新结果：345 项专项断言、523 项场景自检通过。

也可在仓库根目录分别运行：

```sh
GODOT="$HOME/Applications/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path godot --script res://tests/test_surface_movement.gd
"$GODOT" --headless --path godot -- --selftest
```

运行时验证：6 个泊位之间 30 条有向航路全部抵达；全程水域、速度/角速度上限、到达事件只触发一次、途中改道、受阻停船、木桥连通、断开地面拒绝及上下船顺序均有断言。

30/60/120 FPS 同一转弯用例耗时分别为 8.433 / 8.417 / 8.417 秒。真实渲染录像在 `outputs/surface-movement.mp4`，包含出航、绕岸、靠泊和上岸走向菜箱。录像由真实渲染器生成，不是 headless 画面。

## 日制种植更新（2026-10-22）

每张独立种植床包含六个独立地格，共 18 格，床脚本分配稳定 ID；模型和交互由地格脚本负责。原床 ID 保留给第一格，以迁移旧存档。种植规则及回归详见 [FARMING_DESIGN.md](FARMING_DESIGN.md)。
