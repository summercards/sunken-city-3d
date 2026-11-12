# 老王场景工坊 · 正式场景公共色盘与四材质

按2026-11-12 14:00用户要求实施。FeatureID SEA-WORKSHOP，R50–R52。

## 变更

工坊原先通过StandardMaterial3D取公共色盘，虽有SEA_Matte/Gloss名字，质感不等于正式场景。现在直接引用 `godot/assets/materials/solar_cabin/sunny_matte.tres`、sunny_metal.tres、sunny_gloss.tres、sunny_emission.tres；这四份都是已有正式资源，不复制、不改参数。共同指向同一张512×512、8×8暖木色盘，PaletteUV内缩16px选色，未改几何或色格。

| 角色 | 正式资源参数 | 默认用途 |
|---|---|---|
| SEA_Matte | roughness .62 / metallic 0 / emission 0 | 墙、柱、腰线、木料 |
| SEA_Metal | roughness .42 / metallic .18 / emission 0 | railing_栏杆 |
| SEA_Gloss | roughness .24 / alpha shader默认 .81 | 玻璃 |
| SEA_Emission | roughness .35 / emission 2 | 显式指定发光构件；不强造发光窗 |

mesh_builder.shared_materials持有四个共享Resource身份，返回浅副本字典；material按角色取共享引用，不因色格/aging复制。catalog允许可选material_role且只允许四个SEA_*完整名；shell和旧内核均支持显式角色。无需额外四色都用满，默认建筑可只用其中2–3个。

新导出外链正式.tres（Godot在TSCN中可标注Material基类，不要求文本写ShaderMaterial）；manifest加shading_contract及四资源/shader/PNG hash。已有历史候选不重写，需要在编辑器重新生成另存版本。用户prefab不擅自重着色，仍为单独材料契约边界。

隔离editor工程复制四材质与两个shader依赖，不链接生产目录作为可写区域；不加载Main，不改世界光照全局。UI底部说明共用色盘与四角色。

## 验收设计与修正

- 四资源实例identity、路径、名字、单一512纹理、重复生成不新增材质。
- 各角色显式生成、默认栏杆Metal、玻璃Gloss，角色切换不改几何/法线/UV/碰撞。
- 原UV安全格/面积/实际图像采样检查保持，只从StandardMaterial读取改成ShaderMaterial.palette读取。
- 保存重载外链无内嵌ShaderMaterial或StandardMaterial副本，实际资源身份保持。
- 共享文件hash、shader源码与有效参数前后不变。Godot重载时把显式整数0变成默认null，以及把未设置uniform物化为默认值，并非调用方写材质。测试按源shader已核实的默认值归一数值表示，float精度1e-6；文件hash和非默认参数仍严格。
- 初批出现静态脚本call使用错误，随后外链基类误判和有效参数归一差异；历史失败不抹掉。最终结果补在功能账本。

## 影响范围

改动mesh_builder.gd、shell_geometry.gd、generator.gd、catalog.gd、editor_store.gd、editor_screen.gd、editor_verification.gd、test_workshop_shell.gd与统一runner的隔离依赖复制段。不修改公共四材质、PNG、着色器，不改Main与手摆布局，不恢复暂停植物任务。不提交推送并行工作。
