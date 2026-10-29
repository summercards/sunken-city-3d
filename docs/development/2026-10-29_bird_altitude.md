# 鸥群高度下压：从「贴画面上沿」降到「绕屋檐飞」

- 日期：2026-10-29
- 功能：SEA-AMBIENT（场景装饰·动物）
- 依据：按图反馈 —— 截图红框圈出海鸥所在空域，"海鸥的高度可以低一点"

## 数值

鸟群高度不是直接写的数，是烘焙值加偏移：

```gdscript
# godot/src/ambient/birds.gd
bird.altitude = float(b.baseY) + altitude_offset
```

`assets/baked/birds.json` 里 7 只的 `baseY` 是 5.8 / 6.8 / 7.2 / 7.6 / 8.0 / 8.4 / 9.2（来自 Three 原型坐标，不能直接搬进 Godot 世界）。

| `altitude_offset` | 高度带 | 与屋脊（11.84 m）净空 |
|---|---|---|
| 12.0（原） | 17.8 – 21.2 m | +5.96 ~ +9.36 m —— 高过屋顶近两层，实机看着悬在画面上沿 |
| **8.5（现）** | **14.3 – 17.7 m** | **+2.46 ~ +5.86 m** |
| 7.0（试算） | 12.8 – 16.2 m | 触发「屋顶 +1 m」断言，不可用 |

单只自身还有 `sin(t*1.4+phase)*0.65` 的上下浮动，所以最低点要再减 0.65 m：

- `8.5` → 最低 13.65 m，高于断言线（11.84 + 1.0 = 12.84）1.81 m；
- `7.5` → 最低 12.65 m，已跌破断言线。

**8.5 是净空断言下的可取低值，不是随手挑的中间数。** 再要往下压，必须同时放宽 `test_scene_decorations.gd` 的「屋顶 +1 m」并重新论证穿模，否则会先报 FAIL 而不是先变好看。

## 验收

- `visual-decorations`：1713 checks，鸟轨迹净空与鼻尖朝向两条断言全通过；报告的 2 项失败（`home_submerged/flat_annex` 重复实例 ID、`decorations follow dive lifecycle`）已在 `altitude_offset=12.0` 下复跑对照确认为**改动前就存在的基线失败**，与鸥群无关。
- `visual-birds`：PASS exit=0，出 `birds-flock-wide.png` 全景与 `nose-side` / `nose-front` 侧拍；全景里鸥群已改为绕屋顶与楼体游弋。
- 高度对比用临时探针跑过 12.0 / 8.5 / 7.0 三档同机位渲染，探针与对比图用完即删，未留仓库。

## 边界

只改 Godot 正式实现。`web/index.html` 的 Three 原型 `baseY` 是另一套坐标系（它没有 `altitude_offset`，高度直接读 `baseY`），本次未动；若网页原型也要压低，应在 Three 侧单独调 `createSoaringBird` 的 `baseY`，不能照搬 8.5。
