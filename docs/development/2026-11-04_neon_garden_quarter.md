# 2026-11-04 霓虹花园街区 Blender 源级交付

[主文档](../../GDD_V1.0.md#sea-asset) · [功能设计](../features/asset/spec.md) · [功能账本](../features/asset/ledger.md)

对应 SEA-ASSET-R44。用户要求整张参考图中的建筑、招牌与植物，省略水、角色与生物，补完看不见的结构，并指定广告画使用 image-2。按 `sea-scene-component-authoring` 的 `above_water` 分支完成，未自动接入 Godot。

## 制作结果

- 母版：[neon_garden_quarter.blend](../../art_source/scenes/neon_garden_quarter/v001/neon_garden_quarter.blend)。另有46个可直接打开的独立组件包。
- 三栋主建筑：左侧六层店楼、右侧七层圆弧窗湾酒楼、后方五层屋顶农园；补全前后侧立面、层板、楼梯间、水箱、空调、排水管、外部折返梯。大尺寸按5.1米层高、0.5米主柱、0.2米楼板；临水底平台顶0.3米／底0.1米。
- 46组件／639 Collection实例；建筑、设施、招牌、植物及展示支持分组。场景总包络约33.0×29.9×39.4米；521764多边形／1011102三角形，为展开所有可见实例的真实统计。本轮无低面数上限，尚未作运行优化。
- 植物包含甘蓝、番茄、蔬菜叶簇、宽叶草、藤蔓、垂挂灌木、花簇和长叶草；花箱、土床、竹架与植物独立。
- 破损为少量大块窗角缺失、断裂女儿墙、大片墙面剥落／宽裂纹与大块残片。保留概括轮廓，不铺碎屑。
- 生成贴图用 `gpt-image-2`、2048×2048、high、参考图编辑调用。8幅广告共用一张4×2图集；[提示词](../../art_source/scenes/neon_garden_quarter/v001/textures/image2_prompt.txt)与[调用记录](../../art_source/scenes/neon_garden_quarter/v001/textures/generation_record.json)存档。肖像只印在广告上，没有人物模型。
- 大号日文／中文招牌使用粗体、实体挤出与圆角，发光网格独立。广告印刷与厚字分开，避免重复字叠在同一画面。

## 材质与例外

全部几何有活动／渲染 `PaletteUV`，面岛位于8×8公共暖木色板的单格安全区；色板外链唯一、Closest、未打包。四个共享角色 `SEA_Matte`／`SEA_Metal`／`SEA_Gloss`／`SEA_Emission`。

用户明确要求还原广告画，因此仅印刷表面额外使用 `PosterUV` 与 `PosterMask`，在同一 `SEA_Matte` 内采样本套件唯一图集（Linear）。此例外已在建模前的组件计划登记，不能将海报图集误判为公共色板副本。独立包仍外链项目公共色板与套件图集；图片缺失检查全部通过。

## 当前验收

| 项目 | 本轮结果 |
|---|---|
| Blender4.5母版重开＋46独立包重开 | 8896检查，0失败 |
| 每面UV面积、单格安全区、活动／渲染层 | 44439母版面全部通过；独立包再次检查 |
| 变换／底心原点／零集合偏移／非空／归属／图片／面几何 | 通过；清除中文字体转换产生的零面积小面后重新执行 |
| Skill验证器 | 母版＋46包共47份通过；明确适配sea的8×8，允许登记的广告图输入，未修改安装的Skill |
| 真实渲染与目视 | 7视图：全景、街巷参考机位、屋顶菜园、俯视、背面、厚字招牌、隐藏植物的建筑视图 |
| 分账登记 | 48条：46组件＋总成＋图集；ID前缀SEA-SCENE-NGQ；非本任务资产源哈希原样保留 |
| Godot运行 | 未执行；本轮为Blender制作任务，无GLB／PackedScene／运行功能通过声明 |

机器报告和渲染位于工程外 `D:/projects/sea-work/neon_garden_quarter/v001`：`source_verification.json`、`skill_verification.json`、`visual_review.json`、`registration_report.json`、`renders/`。独立验证不仅检查制作脚本的参数，还重新打开磁盘文件逐面量测。

首轮目视发现圆形吊牌四角、重复大字覆盖广告、外梯平台间距、侧窗柱位与广告肖像拉伸，已逐项修复；街巷补光使后方广告可读。参考图为一个混合上下水观察的二维构图，交付为完整三维、项目风格的结构还原，不声明像素级复刻。

## 边界与维护

源主哈希：`80740cab18db996054c32abe7c54c3c3c4415bfda882190bad1086b7281f0507`。计划、组件目录与实例清单都在同一版本目录；维护脚本位于 `tools/blender/neon_garden_quarter/`。主源通过Collection Instance复用，修改网格请编辑第二个“组件母版_独立编辑”场景。

Godot导出／接入、真实胶囊通行、泊位、角色与船阻挡、导航、岸线、功能交互、运行性能仍pending。源清单里的通路／泊位只是设计预留，不是运行验证。参考图商业授权与用户最终美术验收pending。已有Blender未保存会话、正式Godot场景及并行工作的资产均保留。


## 全局契约同步结果（本轮实测）

`python3 scripts/check_feature_contracts.py --sync` 已执行，退出1：39功能／739源资产／544运行哈希，5个任务外问题。无参复核退出1，另报派生功能索引过期，共6项。本套件48条登记没有独立错误。

阻断来自 `SEA-SCENE-ORF-ASSEMBLY` 源哈希、`godot/assets/data/zones.json`、`godot/assets/materials/ocean_sky.tres`、`godot/scenes/zones/zone1_home_harbor.tscn` 的运行哈希，以及 zones 内容ID差异。检查器仅在全工程零问题时写派生索引，因此同步没有落盘。没有重算或接受这些任务外文件的哈希；源码／场景／基线保持。源索引从各账本已有登记值派生，不重算他人源文件。完整结果见工程外 `feature_contract_results.json`。

本套件Blender源级和Skill专项仍为通过；全工程文档契约不能标记通过。最终母版已在新的Blender4.5窗口打开，原未保存窗口仍保留。
