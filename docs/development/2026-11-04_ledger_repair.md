# 账本登记头修复与提交前契约核查（2026-11-04）

## 问题

提交前按 AGENTS.md 第 3 条跑 `scripts/check_feature_contracts.py`，直接崩在
`UnicodeDecodeError`：`docs/features/asset/ledger.md` 第 7 行是一个孤立的字节 `0xae`。

顺着查下去，发现两处账本被同一种坏编辑伤到：

| 账本 | 症状 |
|---|---|
| `docs/features/asset/ledger.md` | 标题、主文档回链、`## 登记头`（含 `feature_id` JSON）、`## 2026-10-28 黄白木船与双桨`、`## 设计承接与实施条目` 标题全部丢失；第 7 行残留坏字节 `0xae`；新段以 LF 写入、正文是 CRLF，行尾混用 |
| `docs/features/world/ledger.md` | 标题、主文档回链、`## 登记头`、`## 设计承接与实施条目` 标题丢失；条款行 R02／R03／R05 被删；新增的顶层牧场条款被误标成 `SEA-WORLD-R01`，而 spec 里已登记为 `SEA-WORLD-R17` |

两处的共同形态是「新章节被插进文件开头时，把原有的开头整体覆盖掉」，不是内容缺失，
而是头部结构被吃掉。

## 处理

| 动作 | 证据 |
|---|---|
| asset 账本：从 HEAD 取回标题／回链／登记头／2026-10-28 段，与新写的 `2026-11-03 顶层牧场接入（R41 · v004 运行侧）` 段并存，再接回 `## 设计承接与实施条目` 与其表格；删除坏字节行；全文统一为 CRLF | 章节数 HEAD 50 → 现 51（0 丢失、1 新增）；UTF-8 校验通过；433 行全 CRLF、0 孤立 LF |
| world 账本：取回标题／回链／登记头，补回 `## 设计承接与实施条目` 标题；从 HEAD 恢复 R01／R02／R03／R05 四行；把误标的顶层牧场行改为 `SEA-WORLD-R17` | spec 条款集与账本条款集双向差为空，17 == 17 |
| 运行 `check_feature_contracts.py --sync` 同步主文档摘要与 `docs/generated/feature_index.json` | 无 feature 状态类报错 |

材质契约 `check_material_params.py --quiet` 退出码 0。

## 尚未解决：资产登记哈希漂移（6 项）

本轮工作区的实现改动领先于资产登记，检查仍报：

```
FAIL: SEA-SCENE-ORF-ASSEMBLY: source hash drift
FAIL: source index differs from asset ledger
FAIL: runtime hash drift: godot/assets/data/zones.json
FAIL: runtime hash drift: godot/assets/materials/ocean_sky.tres
FAIL: runtime hash drift: godot/src/ui/hud.gd
FAIL: content ID drift/duplicate godot/assets/data/zones.json
```

**没有就地改哈希。** 按 AGENTS.md 第 9 条，未核验的变更必须保持 pending，不能靠刷新
`source_sha256` / `sha256` 把未知变更藏起来。各自的成因与应有的收口动作：

| 项 | 成因 | 应走的流程 |
|---|---|---|
| `SEA-SCENE-ORF-ASSEMBLY` | 该行仍指向 `art_source/scenes/ocean_rooftop_farm/v001/ocean_rooftop_farm.blend`，而 v001 源文件在本轮被就地改写；v002／v003／v004 尚未登记 | 跑 `tools/blender/ocean_rooftop_farm/register_v004.py`（账本行已记 pending），按 `source_verification.json` + `skill_verification.json` 双 passed 才升登记 |
| `source index differs` | `current_source_index.json` 是各分账本行的派生视图，账本行变了但索引没重建 | 登记脚本收尾时重建；账本定稿后一次性刷新 |
| `zones.json` 两项 | 默认世界范围压缩（只留横滨＋顶层牧场），区块与 id 集合变化，未跑对应专项 | 先跑 `scripts/run_verification.py` 相关专项，再把 id 表与哈希一并登记 |
| `ocean_sky.tres`、`hud.gd` | 天空材质与 HUD 本轮改动，未留验证记录 | 同上；补一次真实渲染抓图作证据 |

在这些跑完之前，上述 6 项应继续以失败状态暴露，不作为“已通过”记入账本。

## 复发（2026-11-04 傍晚）

同一个故障当天又发生一次，被 `0666ccd`（每日自动提交）固化进历史：
`docs/features/world/ledger.md` 的标题、主文档回链、`## 登记头`、
`## 设计承接与实施条目` 标题再次被顶层新章节覆盖，`check_feature_contracts.py`
报 `SEA-WORLD: ledger has no JSON registration header`。

已按同一路径从 `b4601d5` 取回登记头（41 行：标题 → 回链 → 登记头 JSON 围栏），
补回承接段标题，正文与新增的两个 11-04 章节原样保留，全文 CRLF。

因为这是两天内第二次同形损坏，已在 `AGENTS.md` 第 2 条补一句硬约束：
账本新章节只能追加在原有内容之后，禁止整文件重写或"取前 N 行替换"式保存。
这属于会重复发生的流程缺陷，光靠这一次修文件不够。
