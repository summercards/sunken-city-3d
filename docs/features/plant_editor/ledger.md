# SEA-PLANT-EDITOR · 独立植物工坊 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-plant-editor) · [功能文档](spec.md)

## 登记头

```json
{
  "feature_id": "SEA-PLANT-EDITOR",
  "status": "planned",
  "owner": "未来 PlantAuthoringSession；运行风与草地仍归 SEA-AMBIENT，正式资产归 SEA-ASSET",
  "code_paths": [
    "godot/src/plant_authoring/recipe.gd",
    "godot/src/plant_authoring/species.gd",
    "godot/src/plant_authoring/geometry.gd",
    "godot/src/plant_authoring/generator.gd",
    "godot/src/plant_authoring/session.gd",
    "godot/src/plant_authoring/store.gd"
  ],
  "verification": []
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 未签边界 |
|---|---|---|
| SEA-PLANT-EDITOR-R01 | planned / 暂停 | 尚无 EditorPlugin、主屏或隔离性验收；不得视为可用编辑器。 |
| SEA-PLANT-EDITOR-R02 | draft | species.gd 记录香樟/鸡爪槭/垂枝桦；植物形态事实来源见 spec。未做实际几何检查。 |
| SEA-PLANT-EDITOR-R03 | draft | recipe/generator 代码草稿；无 Godot 验收。 |
| SEA-PLANT-EDITOR-R04 | draft | 几何 helper 草稿；未渲染，无美术签署。 |
| SEA-PLANT-EDITOR-R05 | draft | 草库资源消费与苔藤代码草稿；未做集成或共享资源不变验证。 |
| SEA-PLANT-EDITOR-R06 | draft | session/store 草稿；未实际保存重载验证。 |
| SEA-PLANT-EDITOR-R07 | planned | 尚无预览风或生命周期验证。 |
| SEA-PLANT-EDITOR-R08 | research | 已读 Sapling/Mtree/Zylann TreeGen/TreeIt 官方说明与风格化叶簇法线文章。无第三方代码导入、无插件安装；网址、许可与取舍见 spec。 |
| SEA-PLANT-EDITOR-R09 | pending | 尚无注册 runner 入口，未启动 Godot 验收，不以子代理静态检查冒充通过。 |

## 2026-11-12 用户暂停

11:28 用户明确要求“植物编辑器先把记录放在一边”，优先修复楼房编辑器。不继续制作植物 UI、导出或验证。上述六个源草稿与调研保留，不删除、不接入 project.godot 或正式世界。恢复时先审查代码并补真实验收。
