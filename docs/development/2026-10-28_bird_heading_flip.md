# 海鸥倒飞修正：烘焙朝向与 Godot 朝向约定相差 180°

- 日期：2026-10-28
- 功能：SEA-AMBIENT（场景装饰·动物）
- 依据：按图反馈 —— 截图圈出一只海鸥，"这个海鸥好像是反着飞的，把模型的头和屁股换一面"

## 根因

不是模型建反了，是**朝向公式的符号错了**。

鸟群资产由 `web/index.html` 的 Three.js 场景烘焙而来：

```js
createSoaringBird → const body = new THREE.Mesh(new THREE.ConeGeometry(0.08, 0.42, 5), birdMat);
                    body.rotation.x = Math.PI / 2;   // 锥尖从 +Y 转到 +Z
...
b.group.lookAt(nbx, by, nbz);   // Three 的 lookAt 让 +Z 指向目标
```

`Object3D.lookAt()` 在 Three 里（非相机/灯光）走的是 `_m1.lookAt(_target, _position, up)`，即让物体 **+Z 轴**朝向目标。所以在 Three 场景里，鸟的锥尖（鼻尖）朝 +Z，`lookAt` 之后鼻尖正好指向飞行方向 —— 网页版是对的。

烘焙导出后，`bird.gd` 自己算朝向，写的是：

```gdscript
rotation.y = atan2(-tangent.x, -tangent.z)   # ← 错
```

这个公式让物体的 **-Z** 对准切线。Godot 默认相机/模型的"前"是 -Z，写这行的人按 Godot 习惯来，但这份资产的前是 +Z。两个约定差 180°，于是整群鸥屁股朝前倒着飞。

## 同项目里的正确写法

同一个烘焙来源、同样需要"模型朝运动方向"的另外两处都对：

| 文件 | 行 | 公式 |
|---|---|---|
| `godot/src/ambient/decorative_whale.gd` | 119 | `atan2(-sin(angle)*radius.x, cos(angle)*radius.y)` ← 等价 `atan2(t.x, t.z)`，并带注释"模型鼻尖朝 +Z" |
| `godot/src/ambient/decorative_fish_school.gd` | 272 | `atan2(step.x, step.z)` |
| `godot/src/ambient/bird.gd` | 37 | ~~`atan2(-tangent.x, -tangent.z)`~~ → `atan2(tangent.x, tangent.z)` |

鲸鱼的注释已经把约定写明了，鸟这条是唯一漏掉的一处。

## 改了什么

`godot/src/ambient/bird.gd`：

```gdscript
var tangent := Vector3(-sin(angle)*radius.x, 0, cos(angle)*radius.y)
# 鸟身锥尖朝 +Z（Three 烘焙，网页版 lookAt 以 +Z 为前），与鲸鱼、鱼群同一约定。
# 原先写成 atan2(-tangent.x,-tangent.z)，等于让屁股朝前，整群鸥倒着飞。
rotation.y = atan2(tangent.x, tangent.z)
```

只改朝向，**没有动模型顶点、没有重新烘焙 `birds.json`**。理由：资产本身是对的（和网页版逐顶点一致），错在运行时朝向；改烘焙产物会让 Godot 与网页版不再同源，下次再烘焙又会被覆盖回去。

## 让它以后不会再错

### 1. `godot/tests/test_scene_decorations.gd` 新增断言

```gdscript
var body: MeshInstance3D = bird.get_child(0)
var nose := (body.global_transform.basis * Vector3(0, 1, 0)).normalized()
var tangent := Vector3(-sin(a)*bird.radius.x, 0, cos(a)*bird.radius.y).normalized()
check(nose.dot(tangent) > 0.9, "bird nose leads flight path")
```

`body` 是 `parts[0]`，锥尖在局部 +Y（烘焙时被 `rotation.x = PI/2` 从 +Y 转到 +Z，导出矩阵里 `basis.y` 落在世界 +Z，所以取局部 +Y 再乘全局基向量就是世界鼻尖方向）。

每 15 个采样点查一次，环绕一圈共 9 次。

**反证过这条断言真的能抓到这个 bug**：把公式临时改回 `atan2(-tangent.x, -tangent.z)` 重跑，`decorations` 从 `1659 checks, failures=0` 变成 `1659 checks, failures=63`（7 只鸟 × 9 个采样点），失败信息全是 `FAIL bird nose leads flight path`；还原后回到 0 failures。

### 2. 新增专项 `visual-birds`

`godot/tools/capture_birds.gd`，注册在 `scripts/run_verification.py`：

```
'visual-birds': ('tools/capture_birds.gd', r'\[birds\] \d+ checks, failures=0'),
```

跑法：`python scripts/run_verification.py visual-birds --full-world`

产出三张实拍：`birds-nose-side.png`（侧拍，看鼻尖与机位关系）、`birds-nose-front.png`（正对鼻尖）、`birds-flock-wide.png`（整群绕飞）。

**机位踩过的坑**：不能用 `cam.target` / `cam.distance` 摆位 —— `orbit_camera` 的 `distance` 被 `zoom_min = 9.0` 夹住，而海鸥在 `19 + 12 ≈ 31 m` 高空，9 m 外只剩米粒大（第一次抓图拍到的是一片屋顶和水面）。改成停掉相机 `set_process`、直接写 `global_position` + `look_at`，短距特写只在这个专项里用，不污染正式相机。

## 验证

| 检查 | 结果 |
|---|---|
| `decorations`（headless） | PASS，exit=0，`1659 checks, failures=0` |
| `visual-birds`（真实渲染，--full-world） | PASS，exit=0，`2 checks, failures=0` |
| 反向注入（公式改回 bug 版） | 63 failures，断言确实咬住 |

侧拍实拍确认：锥尖朝飞行方向、身体与展开的双翼在后；正对机位能看到鸟头正对镜头，不再是尾羽对着人。

证据目录：`D:\projects\sea-work\verification\20261028-173547-verification-610de0`

## 遗留

### 1. 既有 runtime hash drift

`check_feature_contracts.py` 的既有 runtime hash drift（`world_env.tres`、`salvage_station.glb`）与本轮无关，仍在未提交状态，本次未触碰。本轮 `--sync` 后检查干净：`PASS: 33 features, 432 source assets, 346 runtime resource hashes; 0 issues`。

### 2. selftest 的 29 项既有失败（非本轮引入）

跑集成时 `selftest` 报 `498 passed, 29 failed`，红项集中在两条：

- `FAIL 区块复原 zone1`
- `FAIL 船位复原 (3.066625, 1.12, 20.53675)`

**已用 stash 对照确认这不是本次改动引起的**：把 `bird.gd`、`test_scene_decorations.gd`、`capture_birds.gd`、`run_verification.py` 四处改动全部暂存后重跑，仍是 `498 passed, 29 failed`，数字与失败项完全一致；恢复改动后同样不增不减。

推测是存档复原相关的既有回归（船位与区块状态），与海鸥朝向无因果关系 —— 改的是一行 `atan2` 的符号。这项**没有修**，留给对应功能（`docs/features/world`、`docs/features/save`）单独排查，不在这里顺手改存档逻辑。

