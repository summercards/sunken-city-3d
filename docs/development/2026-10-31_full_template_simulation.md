# 2026-10-31 全模板模拟验收：12 框架拼装、真实通行、10 摆件、整档存读

关联 SEA-BUILDING-R23（新增）/ R06（顺序无关，本轮修复）/ R16 / R20。布局状态仍只由 BuildingService 写入；本轮修一处挂点判定缺陷，其余为模拟验收。

## 模拟做法

在正式 `main.tscn` 里按玩家路径装配：平台用 `origin=boat` 起在海面，构件通过 `BuildingController._furnishing_request` 或等价请求提交给 `BuildingService.begin`，`BuildingWorld` 负责投影、导航与 Farm 绑定。行走验证不用几何近似，而是真实 `ActorController` + 胶囊 + 导航面。

布局：8 块浮台成链（4×4 ×2 南北向承载楼梯与二层、2×4 门廊、2×4 横梁台、两处独立 4×4 屋顶台、两处 4×4 摆件台），12 种框架全部落地。

## 结果

框架（12/12 拼装成功）：

| 构件 | 拼装 | 通行实测 |
|---|---|---|
| 4×4 浮台 / 2×4 浮台 | ✅ | 旧板→4×4→2×4 三段接缝连通，胶囊走过 |
| 木板实墙 | ✅ | 中心不可走 |
| 开窗木墙 | ✅ | 中心不可走 |
| 通行门框 | ✅ | 门洞中心可走 |
| 木立柱 | ✅ | 中心不可走 |
| 承重横梁 | ✅ | `blocks_actor=false`，脚下甲板仍可走 |
| 交叉栏杆 | ✅ | 中心不可走 |
| 直跑楼梯 | ✅ | 真实胶囊爬升到 2.8 m 二层，落点误差 0.00 m |
| 二层木楼板 | ✅ | 二层可行走，整档恢复后角色仍在楼上 |
| 平顶遮棚 | ✅ | 不产生行走面，角色不可站立 |
| 斜面屋顶 | ✅ | 不产生行走面，2.8 m 与 3.2 m 处均不可站立 |

摆件（10/10 落位成功）：全部在新建浮台并集内按目录占地摆放，投影位置与瞄准点误差 < 0.02 m。阻挡与 `blocks_actor` 逐一吻合——`oil_lamp`/`lamp_post`/`flag`/`wind_chime` 不挡人，`windmill`/`flower_pot`/`storage_crate`/`water_barrel`/`table`/`stool` 挡人。油灯带真实暖光节点，木箱打开共享仓库，木桶经 Farm 端口把水壶补到 12；二层摆件不会在地面甲板开洞。

存档：`SaveGame.encode` → `restore` 后 31 个实例逐字段一致（id/kind/px/pz/py/turn/support/left），顺序反转后仍通过校验，角色从二层原位恢复，再存一次依然合法。施工计时、支撑关系、`origin` 瞬态字段均未被写入存档。

## 发现并修复的真实缺陷：挂点被第一个匹配遮蔽

`Assembly.bearing_ids` 原本对每个必需挂点只取**第一个**命中构件：

```gdscript
for socket in sockets(other):
    if socket.distance_to(point)<0.26: found=str(other.id);break
if found!="": break          # 拿到一个就不再找
```

柱角与墙端是同一个点。若墙先于柱进入列表，楼板的 `support`（指向柱）就不在 `bearings` 里，`reason()` 报“顶部挂点缺少完整的立柱或墙体支撑”。

两个后果：

1. **建造顺序敏感的误拒**：先建墙、后建柱、再建楼板，楼板会被拒——同样几何换个顺序就能建。
2. **存档自相矛盾**：R06 要求“不依赖创建顺序”。`validate_snapshot` 按记录顺序重放几何，一旦顺序不利，本已建成的布局会在读档时被判无效。

修复：每个必需挂点收集**全部**共有构件，只要有一个覆盖即算该点成立，不再短路。

```gdscript
for other in rows:
    ...
    for socket in sockets(other):
        if socket.distance_to(point)>=0.26: continue
        found=true
        if not ids.has(str(other.id)): ids.append(str(other.id))
        break          # 只跳出这个构件，继续找下一个共有者
if not found: return []
```

收紧性未变：仍需 4 个点各自有承载，不会让屋顶少支撑；只是把“谁先来”从判定里去掉。

**反向验证**：把旧实现临时放回，`kit-safety` 立即两条断言失败（`floor still finds its bearing post when the wall came first`、`every socket owner counts at a shared corner`）；恢复修复后 75 项 0 失败。这条断言确实能捕获该 bug，不是摆设。

## 模拟过程中修掉的测试自身问题

模拟第一轮 21 项失败，其中 18 项是我写错了夹具，不是产品问题，逐条记下以免误判：

| 现象 | 真实原因 |
|---|---|
| 角色原地不动、`start_walk` 返回 false | 我给 `restore_pose` 传了建造局部坐标，漏加世界原点 `Catalog.ORIGIN` |
| 摆件“不在瞄准点” | 断言拿世界坐标比局部坐标，且 `want` 里重复加了 `ORIGIN.y` |
| 回收报“背包空间不足” | 夹具把木料设成 4000，超过 40/格 × 24 格上限，`add_all` 自然失败；改 500 后正常 |
| 鼠标预览的墙被判重叠 | 探针点压在楼梯占地上，属真实拒绝，换点即可 |

第 3 条虽属夹具，但顺带确认了一个真实语义：**背包满时回收会整笔失败并保留物件**，与 R12 一致，不是 bug。

## 验收

| 专项 | 结果 | 证据目录 |
|---|---|---|
| `building-simulate`（新，191 项） | PASS 退出 0 | `20261031-005118-sim1-1e84ce` |
| `visual-building-simulate`（同模拟，真实渲染） | PASS 退出 0 | `20261031-005420-sim-visual-30d85f` |
| `kit-safety`（75 项，含新增 3 条顺序断言） | PASS 退出 0 | `20261031-005118-sim1-1e84ce` |
| `building` / `building-join` / `building-open-rules` / `building-space` | PASS 退出 0 | `20261031-005144-sim-regress-70a3c9` |
| `building-integration` / `building-kit` / `building-restart` / `building-approach` | PASS 退出 0 | 同上 |
| `ground-space` / `character-space-save` | PASS 退出 0 | 同上 |

实景核对（`kit-simulate-house.png` / `kit-simulate-props.png`）：合成后的主体读起来就是一间房子——实墙与窗墙成墙、门框留通行洞、四角立柱撑起二层楼板、直跑楼梯从甲板接到二层、角色站在楼上；平顶遮棚落在独立浮台的立柱上。摆件台上 10 件各自独立可见，油灯有暖光，风车与旗可辨认。渲染里留着的「水壶已补满」提示是木桶补水用例的 toast，不是异常。

## 未执行 / 边界

- 斜屋顶只验证“不产生行走面”，未验证从屋檐跳下的落点行为（本作无跳跃）。
- 手机触屏与实体手柄仍未执行。
- 模拟中的平台用 `origin=boat` 起造，岸上贴边路径由 `building-join` 独立覆盖。
