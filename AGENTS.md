# sea 工程协作约定

1. 开始工作先读 `GDD_V1.0.md`，从功能导航定位本次 FeatureID，再读该功能的 `spec.md` 和 `ledger.md`。主文档是唯一中控。
2. 每个登记功能必须有独立文档和账本，计划中功能也不例外。设计条款有稳定 ID，账本逐条承接；不能用模块目录或资产分账本代替功能账本。
3. 主文档拥有全局规则、功能范围与关系；功能文档拥有细则；功能账本拥有实施状态和证据。改完运行 `python3 scripts/check_feature_contracts.py --sync` 同步摘要，再运行不带参数的检查。
4. 正式 Godot 代码位于 `godot/src/<职责>/`。根网页仍是历史原型与烘焙来源；`godot/tests/parity` 仅为旧算法对照，不能作为正式实现通过的唯一证据。
5. 状态只有一个写入者，跨功能经命令/查询/事件。种植、订单规则必须保留注入端口，不得重新访问全局 Economy、Main 或 UI。
6. 正式场景与资产路径保持稳定。旧构建器只能在 `scripts/create_generation_candidate.py` 创建的工程外副本运行，审阅差异后逐文件接入；不覆盖手工 TSCN。
7. 所有运行验证使用 `scripts/run_verification.py`，在 Autoload 前隔离用户数据。真实渲染、预期故障、未执行项和退出码分别记录。相关专项通过后再跑必要集成，不以历史结果代替当前实测。
8. 资产从 `assets/registry/ledger_index.json` 解析所属分账本，AssetID 不重复。授权或正式接入未核验时明确 pending，不通过批量更新哈希隐藏未知变更。
9. 输出放工程外 `sea-work/`，可通过 `SEA_WORK_ROOT` 重定向；必要代码和文档留仓库。现有 outputs 含历史工具与源引用，不批量删除。
10. 交付更新本功能账本及 `docs/development/` 记录。用户已授权范围内持续完成，不增加重复审批。
