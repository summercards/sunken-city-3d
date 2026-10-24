# sea

项目主文档：[GDD_V1.0.md](GDD_V1.0.md)。它统一管理功能范围、依赖和每个功能的独立文档、账本。

## 两个实现，各占一个目录

仓库只有两套可运行实现，各自独占一个顶层目录，互不引用：

| 目录 | 身份 | 说明 |
|---|---|---|
| `godot/` | **正式工程**（Godot 4.7.2） | 入口 `godot/project.godot`；代码 `godot/src/<职责>/`；场景与资产路径保持稳定 |
| `web/` | 历史 Three.js 原型 | 冻结的玩法设计来源；只作几何烘焙源与视觉对照，仍是事实上的数值基准 |

`web/` 的完整内容（源码、样式、依赖、参考图、网页测试、调试工具）都在该目录内，内部引用闭合，不依赖仓库其他位置。Godot 侧的烘焙工具通过 `http://localhost:8765/index.html` 读取原型，属构建期单向只读通路，不回写。

其余顶层目录为两端共享或产物：

- `docs/` 功能文档与账本；`assets/` 资产登记总账；`scripts/` 工程门禁；`tests/` 工程级契约测试
- `art_source/`、`tools/blender/` 美术源与管线；`outputs/`、`exports/`、`promo/` 产物（含历史记录，不批量清理）

## 常用命令

- 结构检查：`python3 scripts/check_feature_contracts.py`
- 功能验证：`python3 scripts/run_verification.py core`；如只查种植，使用 `farming modules`
- 起网页原型（服务根必须是 `web/`）：`cd web && python3 -m http.server 8765`
- 网页回归测试（从仓库根执行，产物写入根 `outputs/`）：`node web/tests/water-regression.cjs`
- 重新烘焙原型几何：先在 `web/` 起服务，再跑 `godot/tools/export_from_web.cjs`

测试 runner 复制小体积代码/场景，复用只读资产缓存，并在 Autoload 前设置独立用户目录；证据落在仓库同级 `sea-work/verification`，可用 `SEA_WORK_ROOT` 重定向。首次克隆先用 Godot 导入工程，再运行测试。

工作记录：[功能拆分](docs/development/2026-10-23_feature_split.md)、[网页目录归位](docs/development/2026-10-24_web_directory_split.md)。
