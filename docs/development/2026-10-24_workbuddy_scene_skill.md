# WorkBuddy 场景组件技能安装

2026-10-24，承接 SEA-ASSET-R07。

从 .agents/skills/sea-scene-component-authoring/SKILL.md 安装至用户级 ~/.workbuddy/skills/sea-scene-component-authoring，并保留工程 .workbuddy/skills 下镜像。附加安装资源说明，明确项目路径相对 sea 根；附带 resources/palettes 中的 PNG、颜色 JSON 和来源 manifest。工程原始公共色板不改，安装资源只供携带与恢复。

同步脚本：.workbuddy/tools/sync_sea_scene_skill.py。连续执行两次退出 0；四文件逐字节哈希一致，主动模拟漂移的负向断言生效。技能 Markdown 使用 CRLF。公共色板 PNG SHA-256 为 6906f7284161e58b5c1733fa00591d309ce8d5b5aac7e458e9679513bd4e50a1，与来源 manifest 相符。

本次仅安装文件，未通过 WorkBuddy UI 实测技能发现；未执行 Blender 或 Godot 运行验证，不涉及运行资源接入。

工程契约 --sync 与无参数检查均退出 1，唯一问题为既有 godot/assets/materials/water.tres 运行哈希漂移；未重算或覆盖该哈希。
