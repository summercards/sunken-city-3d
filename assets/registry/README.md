# sea 资产账本入口

[主文档中控](../../GDD_V1.0.md#feature-control) · [资产生产功能文档](../../docs/features/asset/spec.md) · [功能账本](../../docs/features/asset/ledger.md)

`ledger_index.json` 是域到分账本的路由表，总索引不含资产行。当前已登记场景域 43 个独立组件，分账本为 `ledgers/scenes.json`，每个 AssetID 只出现一次。

- `current_source_index.json` 从场景分账本提取源定位，不允许作为第二份可编辑资产主表。
- `runtime_resource_inventory.json` 登记已有运行文件路径、大小与哈希；这些路径尚未全部补齐生产级 AssetID，明确标注 pending。
- `content_index.json` 指向各功能唯一内容定义，记录 ID 集合和所有者，不复制物品价格或作物数值。
- 功能账本引用 AssetID 或明确 pending 的资源路径；资产分账本不能代替每个功能的独立账本。
- `source_registered_runtime_pending` 只表示源已登记，不能当作正式接入。授权来源未逐份审查，保留 pending，不自动填“自有”。
- 各域资产行维护后同步源索引，运行资源变更先核对来源再更新对应哈希，禁止批量接受漂移。

校验：`python3 scripts/check_feature_contracts.py`。运行资源仍在 `godot/assets`，制作源在根 `art_source`；所有登记路径以仓库根为基准。场景接入时在原 AssetID 行补稳定运行路径、Prefab 与证据。
