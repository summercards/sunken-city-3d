---
name: sea-contract-ledgers
description: sea 的功能契约、功能账本与资产分账本的改动与校验流程。用于新增或修改功能条款、登记资产、排查 check_feature_contracts 失败、以及处理资产哈希漂移与位置台账。
---

# sea 契约与账本

## 先定位，再动手

1. 读 `GDD_V1.0.md`，从功能导航找到本次 FeatureID。
2. 读 `docs/features/<feature>/{spec,ledger}.md`。主文档管全局规则与关系，spec 管细则，ledger 管实施状态与证据。
3. 每个登记功能必须有独立文档和账本，计划中的功能也要有；**不能用模块目录或资产分账本代替功能账本**。

## 改完的固定动作

```bash
python scripts/check_feature_contracts.py --sync
python scripts/check_feature_contracts.py
```

`--sync` 只同步主文档状态摘要与派生的 `feature_index`；不带参数那次才是正式校验，必须 0 issues。

## 账本的写法约束

- 新增章节**只能追加在原有内容之后**。顺序固定：标题 → 主文档回链 → `## 登记头` JSON → 历次章节 → `## 设计承接与实施条目`。
- 禁止整文件重写、禁止「取前 N 行替换」。历史上出过两次事故，`asset`、`world` 两个账本的标题、回链、登记头被顶层新章节整段覆盖，检查脚本直接崩在解码上。

## 资产登记

- 从 `assets/registry/ledger_index.json` 解析资产属于哪本分账本（`scenes` / `characters` / `crops` / `items` / `music` / `sfx` / `ui` / `vfx`），不要猜。
- 每条必填 `domain` + `category` + `category_label`，类别只能取本域词表里的值，中文必须与词表一致。
- AssetID 全库唯一，一份资产一条主记录。AssetID 的历史前缀不要改，改了会断开 `asset_manifest.json` 的组件引用。
- **调参型 `.tres` 不发 AssetID**（`water.tres`、`water_absorption.tres`、`world_env.tres`）：只进 `runtime_resource_inventory.json`，否则每调一次水色就触发资产级哈希漂移。
- 烘焙产物、`data/*.json`、材质实例、第三方字体同样只进运行清单。
- 新建源不等于正式接入；授权未核验就写 pending。

## 校验失败怎么读

| 报错 | 处理 |
|---|---|
| `derived feature index stale` | 跑一次 `--sync` 即可，不需要改内容 |
| `source/runtime hash drift` | 先判断性质，别急着改数 |
| 缺类别 / 类别越界 / 账本 `domain` 头不符 | 按词表补正 |
| `ledgers/` 有未路由 json | 在 `ledger_index.json` 里登记这本账本 |

**哈希漂移的判定法**：把工作区字节的 `\r\n` 换成 `\n`，与 `git show HEAD:<path>` 比。

- 相同 → CRLF 幻影（本机 `core.autocrlf=true` 造成的）。还原行尾即可，**不要重算哈希**。
- 仍不同 → 真·内容漂移。再确认上游是不是漏登记（登记哈希既不等于 LF 内容，也不等于 CRLF 内容，就属于这一类）。这种情况按条款报 pending 或补登，**不许用批量重算哈希掩盖未知变更**。

## 位置

用户手动摆在 `godot/scenes/main.tscn` 里的 `transform` 是唯一真值。`zones.json` 的 `origin`、文档坐标都只是初期参考位。改了位置就要在 `docs/features/world/placed_positions.md` 留一行（参考位、实测位、偏差、时间），然后：

```bash
python scripts/check_placed_positions.py
```

文档里不得出现被钉死的绝对坐标断言，断言要写成「与 TSCN 一致」。
