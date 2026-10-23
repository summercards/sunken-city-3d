# sea

项目主文档：[GDD_V1.0.md](GDD_V1.0.md)。它统一管理功能范围、依赖和每个功能的独立文档、账本。

- 正式运行：`godot/project.godot`，使用 Godot 4.7.2。操作说明见 [Godot README](godot/README.md)。
- 功能代码：`godot/src/<职责>/`；场景和正式资产路径保持稳定。
- 根目录网页是历史原型、烘焙来源和对照，暂保留路径，不另立当前玩法设计。
- 结构检查：`python3 scripts/check_feature_contracts.py`。
- 功能验证：`python3 scripts/run_verification.py core`；如只查种植，使用 `farming modules`。
- 工作记录：[本次拆分](docs/development/2026-10-23_feature_split.md)。

测试 runner 复制小体积代码/场景，复用只读资产缓存，并在 Autoload 前设置独立用户目录；证据落在仓库同级 `sea-work/verification`，可用 `SEA_WORK_ROOT` 重定向。首次克隆先用 Godot 导入工程，再运行测试。
