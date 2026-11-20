# 2026-11-20 · 正式阳光房实体阻挡首处预检

[总集成](2026-11-20_formal_world_integration.md) · [阳光房规格](../features/sunroom/spec.md#2026-11-20-阳光房实体阻挡迁移门禁)

**未迁移：当前正式 Main 的阳光房没有可接管的内置碰撞盒。** 此任务只允许接现有组件盒，验收通过才撤同职责旧判定。没有在生产场景增加新盒、改层、改摆位、改 F5 或撤旧阻挡。整图迁移暂停。

## 已核对的装配与所有者

- 正式 Main 的 `World/Zones/Zone1HomeHarbor/Models/太阳能木屋` 来自 `solar_cabin.tscn`。海上模块与下沉基座是独立子树。海上组件现经 `sunny_bloom_visual.gd` 装配：加载独立包装件，复制网格到 `MultiMeshInstance3D`，随后释放原包装实例，而不是把碰撞节点随包装挂入世界。
- 隔离重新导入后，直接实例化 `scenes/components/solar_cabin/` 下全部 **61** 个包装件（含各自导入场景子树），递归得到 **0 个 CollisionObject3D、0 个 CollisionShape3D、0 个 BoxShape3D**。正式 Main 里的整座阳光房也都是 **0/0/0**，同时确有 **230 个 MultiMesh**（海上 158、水下 72），因此不是场景没有装配。探针打印正式实例的实际局部和世界变换；此快照不锁定绝对摆位。
- zone1 的 `GroundSpace` 实例实际拥有 **2 个地板体和 1 个边界体**，各为非禁用的 `ConcavePolygonShape3D`、层 256 / 掩码 512；角色站岸时消费掩码 256。启动时人物在船上，探针实际读取层/掩码为 0/0，不误当陆地值。梯脚向下的碰撞射线命中 `GroundSpace/GroundFloor`；正式泊位至梯脚求出 22 个航点。上下梯、修缮和二楼启停继续归原模块。
- 阳光房 `Blockers` 按海上子树派生 **14** 个矩形；样点 `(5.2, -2.8)` 由现行几何水域查询拒绝。实际 `BoatPark` 可航，从泊位沿离岸方向 2 米段通过旧 `segment_clear`。水下基座保持 `mode="none"`。正式 `Boat` 实例仍为 `Node3D`，这些属于旧水域/航线结果，**不等于原生船壳物理通过**。

## 验证与限制

证据根 `/Users/zyq/work/sea-work/sunroom-collision-qAz9V2`。所有 Godot 运行经外置的 `scripts/run_verification.py`，在 Autoload 前隔离 `user://`；未用真档。原海上 3C 任务确认已结束；运行前后按 `evidence/live.sha256` 校验公共场景、脚本和资产一致。

| 批次 | 结果 |
|---|---|
| `20261120-023433-sunroom-boxes-r2-704d78` | 重新导入 exit 0；无头库存探针 69/0、修缮 14/0、正式 `sunroom-runtime` 21/0、Metal Forward+ 实窗库存探针 70/0，均 exit 0，无非预期引擎错误。当前 `sunroom-runtime` 是 21 项（历史账本为 20），包含实际攀爬、二楼走动及返回下层。 |
| `20261120-023557-sunroom-old-access-06bd09` | 实窗 `dock-hotspot` 33/0、`click` 39/0、`interaction-reach` 36/0，均 exit 0，无非预期引擎错误；只给原泊位、输入与交互基线签署。 |

真实窗口截图 `20261120-023433-sunroom-boxes-r2-704d78/project/outputs/sunroom-formal-scene.png` 已目检，画面包含正式木屋、码头、船和邻近水域。这是装配现况截图，不是人工按键或新物理效果证据。初次探针因两处变量类型推断编译失败（引擎 exit 0，runner exit 1），修复只在外置夹具；不与最终运行混记。

功能契约同步 exit 1（586 项）；只读检查 exit 1（587 项），对照此前共享树逐条无增减。摆位检查 16 处、0 警告、exit 0；正式运行输入指纹全部一致。

**未执行且未签署：** 新墙盒挡人、胶囊穿过门洞、船壳接触与新旧判定 A/B。没有碰撞盒可作为测试主体，不能把外观、旧路由或通行回归冒充为新物理验收。若有另一套已制作盒，需给出其正式 Godot 资源与使用位置；若没有，需另授权仅在阳光房内编写清楚归属和层的实体（门框分段、门洞留空、临水几何按职责验证）。只有该处通过验收才撤该处重复实际判定，保留支撑、路径、泊位、占用和岸线等仍有独立消费者的查询。
