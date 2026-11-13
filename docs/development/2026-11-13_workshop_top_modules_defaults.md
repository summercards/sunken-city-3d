# 2026-11-13 场景工坊顶部信息栏与默认模组

## 用户目标

用户要求把截图中的模块信息移到顶部，不挤占编辑区域，并提供几个可以直接使用的默认模组。

## 实施

- `editor_screen.gd`
  - 新增 `WorkshopTopInfo` 顶部独立信息栏。
  - `building_id` 和显示名称从左侧参数滚动区移到顶部身份行。
  - 模块导航从左侧移到顶部 `WorkshopTopModuleBar`；窄屏使用 `HFlowContainer` 自动换行，不再落到右侧形成竖列。
  - 左侧只保留当前模块参数，中央只保留预览与视图操作。
  - 顶部加入默认模组快捷按钮，载入前沿用未保存草稿确认保护。
- 新增4个可直接载入的 shell_v2 配方：
  - `workshop_default_sea_breeze.recipe.json`：海风公寓，矩形住宅。
  - `workshop_default_harbor_market.recipe.json`：码头商铺，矩形商业建筑。
  - `workshop_default_lighthouse_studio.recipe.json`：灯塔工作室，T形高层样式。
  - `workshop_default_courtyard.recipe.json`：回廊庭院，U形公共空间。
- 默认模组为样例源，载入后仍可编辑；需要保留自己的版本时使用“另存新ID”。

## 验证

- Godot 编辑器脚本 `--check-only`：exit 0。
- `git diff --check`：exit 0。
- 真实编辑器专项：
  - 报告：`/Users/zyq/work/sea-work/verification/20261113-111329-workshop-top-default-modules-final-r2-8e346a/report.json`
  - `editor-workshop-upgrade`：822 checks / 0 failures，exit 0。
  - 实际截图：`project/outputs/upgrade_10_palette_auto_ui.png`。
- 当前截图确认顶部已经形成身份、模块、默认模组三层信息栏；左侧只显示参数，中央预览不再被模块导航压缩。

## 边界

- 默认模组已通过配方规则和真实编辑器载入链验证，但尚未逐个做完整美术终验。
- 默认模组是工坊样例配方，不自动接入 `main.tscn`，不覆盖用户手动摆位或正式世界资产。
