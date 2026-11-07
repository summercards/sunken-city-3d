# 项目技能安装（WorkBuddy + Codex）

日期：2026-11-07

## 目标

把 sea 的工程技能做成**项目级**技能，随仓库分发：Codex 读 `.agents/skills/`，WorkBuddy 读 `.workbuddy/skills/`。此前只有 `sea-scene-component-authoring` 一个，且两份内容不一致（`.workbuddy` 那份是没有「水上／水下分类」判断的旧版）。

## 目录约定

- **真源**：`.agents/skills/<名字>/`，入库。
- **镜像**：`.workbuddy/skills/<名字>/`，由 `scripts/sync_project_skills.py` 从真源整目录复制；`--check` 只比对，有漂移退出码 1。
- `.gitignore` 从整目录忽略 `.workbuddy/` 改为 `/.workbuddy/*` + `!/.workbuddy/skills/`：技能入库，`memory/`、日志继续忽略。

## 装了什么

| 技能 | 来源 | 作用 |
|---|---|---|
| `sea-scene-component-authoring` | 用户级最新版 | 场景组件制作，补回缺失的「先判水上／水下」章节与 `agents/openai.yaml` |
| `blender-game-prop-standard` | Codex 用户级 | 场景／关卡组件的 Blender 建模与色板 UV 规范 |
| `godot-model-asset-import-standard` | Codex 用户级 | 从 DCC 规范导入 Godot：GLB、坐标比例、PackedScene、碰撞、台账 |
| `game-prop-model-pipeline` | Codex 用户级 | 独立道具模型到 Godot（拾取、掉落、手持、物理碰撞） |
| `game-character-model-pipeline` | Codex 用户级 | 从代码／场景／测试反推角色契约，再制作与导出 |
| `sea-repo-sync` | 新写 | github.com 不通时的拉取与推送：缺对象补齐、大文件分块、API 重放推送 |
| `sea-verification` | 新写 | `run_verification.py` 用法与证据记录口径 |
| `sea-contract-ledgers` | 新写 | 功能契约、功能账本、资产分账本的改动流程与失败排查 |
| `sea-godot-traps` | 新写 | `@tool` 改写场景、`source_color` 存 Color、CozyUI 覆盖样式、水面双方案 |

新写的四个技能都从本轮实际踩过的记录里提炼，不含未验证的步骤。

## 校验

- `python scripts/sync_project_skills.py --check` → 9 个技能，0 处差异。
- frontmatter 逐条校验：`name` 与目录同名、`description` 非空，9/9 通过。
- `scripts/check_feature_contracts.py` 与本次改动无关，仍是拉取带入的 4 个 issue（见 `2026-11-07` 备忘录）。

## 后续

改技能只改 `.agents/skills/`，然后跑 `python scripts/sync_project_skills.py`，两处一起更新；提交前用 `--check` 确认没有漂移。
