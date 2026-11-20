# 2026-11-19 · 海上总平面图 V01 归档

[总设计文档 §3.4](../../GDD_V1.0.md#sea-surface-plan) · [SEA-WORLD-R41 与换版流程](../features/world/spec.md#surface-plan-maintenance) · [世界功能账本](../features/world/ledger.md)

根据用户要求，把已交付的海上规划图 **SEA–01 / V01** 纳入总设计，作为今后重新布局的起点，而不是一张无法修改的参考图。

- 归档：[可编辑 SVG](../features/world/sea-surface-plan/v01/sea-surface-plan.svg) · [3120 × 2080 PNG](../features/world/sea-surface-plan/v01/sea-surface-plan.png)。PNG 用于总文档预览，SVG 是后续设计源；本版文件与已交付图纸逐字节一致。
- 总设计第 3.4 节负责图纸的当前版入口和版本表，保留第 3.1–3.3 节的早期设计记录；SEA-WORLD 负责场景投影与修订规则。图纸的示意建筑、水下轮廓、靠泊点符号不替代正式场景或玩法契约。
- 仍未实施：A 家园扩建浮台、B 外海中途泊点、图中的建议航线。未改 `main.tscn`、手摆台账、运行逻辑或资产登记，也未运行 Godot 或做通航验收。

## 核验

- PNG 为 3120 × 2080；SVG 可解析，内部引用齐全；新增的 15 处图纸相关链接与锚点核验通过。`check_placed_positions.py` 检查 6 个结构，0 失败、0 警告。
- `check_feature_contracts.py --sync` 返回 541 项问题（退出码 1），未写入索引；正式检查改前与改后均为 542 项（退出码 1），逐项完全一致。保留既有资产条款缺口、历史断链、哈希漂移与索引问题，未扩大本次文档改动范围。
