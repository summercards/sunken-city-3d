# 网页版目录归位（2026-10-24）

## 动因

根目录同时散落着 Godot 正式工程之外的两类东西：22 个网页原型 `.js`、`index.html`、`ui.css`、`vendor/`、5 张参考图、22 个网页测试、2 个 CDP 调试脚本，以及 3 个其实只服务 Godot 的 Python 工具。看到 `tools/make_web_dist.py` 会误以为它与网页原型有关，实际处理的是 Godot 的 Web 平台导出包。

## 结果

两套实现各占一个顶层目录，互不引用；根目录只留共享层与产物。

| 原位置 | 新位置 |
|---|---|
| `index.html`、`ui.css`、22 个 `*.js` | `web/` |
| `vendor/` | `web/vendor/` |
| `reference.png`、`reference2.png`、`ref_yokohama.png`、`ref_overpass.png`、`ref_underwater.png` | `web/refs/` |
| `tests/*.cjs`（22 个） | `web/tests/` |
| `tools/cdp_play.mjs`、`tools/cdp_shot.mjs` | `web/tools/` |
| `tools/make_web_dist.py`、`tools/fetch_web_template.py`、`tools/web_font_refactor.py` | `godot/tools/` |
| `tests/tooling/test_engineering_guards.py` | 保留原地（跨端工程门禁，`parents[2]` 依赖仓库根） |

全部使用 `git mv`，保留文件历史。

## 随之修改的引用

- `web/gameplay.js` 参考图列表：`./reference.png` → `./refs/reference.png`（其余三张同理）
- `web/index.html` 参考图卡片 `<img src>`：同样加 `refs/`
- `docs/features/release/{spec,ledger}.md` 与 `docs/generated/feature_index.json`：`tools/make_web_dist.py` → `godot/tools/make_web_dist.py`；账本 `code_paths` 同步
- `README.md`、`AGENTS.md`（新增第 4、5 条目录与端口约定，原 5–10 顺延为 6–11）、`GDD_V1.0.md` 第 0 章、`docs/standards/工程管理规范.md` 目录职责

未改动的引用是刻意保留的：`web/tests/economy-unit.cjs` 里的 `import('../economy.js')` 在整体下移一层后依然指向 `web/economy.js`；网页测试里的 `outputs/...` 相对当前工作目录，从仓库根执行即写回原产物目录。

## 新的使用约定

- 起原型服务：`cd web && python3 -m http.server 8765`，页面仍是 `http://127.0.0.1:8765/index.html`，因此 `godot/tools/*.cjs` 里写死的 URL 一行都不用改。
- 网页测试：从仓库根 `node web/tests/<name>.cjs`。
- 禁止在根目录新增网页文件；禁止 `godot/` 相对引用 `web/`。

## 验证

- `node --check` 通过全部 22 个 `web/*.js`（ES module 语法层面）
- 静态服务指向 `web/` 后，`index.html` 与全部 `import` 目标返回 200
- `python3 scripts/check_feature_contracts.py`：迁移本身未新增问题；当前残留的 3 条与本次改动无关，见下

## 未完成 / 需另行处理

1. ~~`runtime hash drift: godot/assets/materials/water.tres`~~ —— **已结清（2026-10-24 09:41）**：调参定稿后先跑 `run_verification.py visual-sea-style ocean selftest --label pre-push-20261024`（三项 exit 0，证据 `sea-work/verification/20261024-094127-pre-push-20261024-c538d4/`），再只改 `water.tres` 一行的 `bytes/sha256`，未批量接受其他漂移；`check_feature_contracts.py` 现为 0 issues。
2. `docs/features/asset/ledger.md` 在 08:14 被并行改动引用了两份尚未落盘的太阳花文档，导致 2 条 broken link。**已随本批文档落盘消解**（`2026-10-24_solar_flower_house_lowpoly.md`、`_style.md` 已入库）。
3. `godot/src/bootstrap/main.gd` 仍通过 `class_name SailNavLib` 使用 `godot/tests/parity/sail_nav.gd`，正式运行逻辑依赖测试对照目录；`parity/economy.gd` 的 `EconomyModel` 无引用者。建议把寻路实现移入 `godot/src/navigation/`，另行处理。
4. 网页测试用隐式 `cwd` 写 `outputs/`，对调用位置敏感。彻底修法是基于 `__dirname` 解析绝对路径，涉及 22 个文件，留作独立任务。
