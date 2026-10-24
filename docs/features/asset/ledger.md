# SEA-ASSET · 美术组件生产与登记 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-asset) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-ASSET",
  "status": "partial",
  "owner": "制作源负责人 / 各域资产账本",
  "code_paths": [
    "art_source",
    "assets/registry",
    "tools/blender"
  ],
  "verification": [
    "structure"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-ASSET-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-ASSET-R02 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-ASSET-R03 | 部分实现；太阳能花屋按源级验收和运行接入分别登记 | 本套源验证通过；Godot 接入和参考图授权仍 pending，见本次制作记录 |
| SEA-ASSET-R04 | 本批完成，存量不追溯改写 | 当前风格源 v003：36 种组件、255 个 Collection Instance；建筑和花草分别归类，36 个独立包重开验证；v001/v002 保留 |
| SEA-ASSET-R05 | 本批完成 | 64 色公共 PNG、JSON 色名表；共享四材质角色，逐面 UV 非零面积、同格安全区验证 |
| SEA-ASSET-R06 | 本批完成源级验证，运行期 pending | 当前 v003 保留 v001 建筑真实倒角，重做圆润花叶；保存重开及四视图验证，见 v003 制作记录 |
| SEA-ASSET-R07 | 本批完成 | 工程内 .agents/skills/sea-scene-component-authoring/SKILL.md；路由场景分账本、登记 38 个新 AssetID |
| SEA-ASSET-R08 | 历史 v002 源级完成；当前 v003 不满足该预算 | 保存文件依赖图实测：整场景 1947 多边形 / 2999 三角面；平台 8.6×8.2 米，前方 6.85×1.20 米净空无陈设侵入 |
| SEA-ASSET-R09 | v003 风格源已制作，验证证据见修订记录 | 基于 v001 实际文件派生；31 项几何与摆位锁定，重做 5 项花叶组件；公共 PNG 与原版源哈希不变 |
| SEA-ASSET-R10 | 本批源级验证通过；Godot pending | 30 组件、142 Collection Instance；30 独立包重开，17690 母版面 UV 核验；见本轮制作记录 |

## 资源与调用入口

- [art_source](../../../art_source)
- [assets/registry](../../../assets/registry)
- [tools/blender](../../../tools/blender)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

规划功能尚无正式接口实现。

## 验证记录

入口：`python3 scripts/check_feature_contracts.py`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 尚无本功能独立运行验收，不将结构通过视为玩法完成。

## 遗留与下一步

首批登记现有 43 个独立组件；其他运行资源建立路径归属，生产级 AssetID 补登作为明确债务。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 太阳能花屋源级交付（2026-10-23）

- [场景目录与打开方法](../../../art_source/scenes/README.md)；[组件计划](../../../art_source/scenes/solar_flower_house/v001/component_plan.json)；[公共色板](../../../art_source/shared/palettes/sea_cozy_8x8_512.png)。
- AssetID 前缀 `SEA-SCENE-SOLAR-`，装配 `SEA-SCENE-SOLAR-FLOWER-HOUSE`，色板 `SEA-PALETTE-COZY-64`。38 条新记录通过总索引路由到场景分账本；旧 43 条源行不改。
- [本次制作记录](../../development/2026-10-23_solar_flower_house.md)与[结构化源级验证证据](../../development/2026-10-23_solar_flower_house_verification.json)。
- 当前未接入 Godot，没有替换游戏建筑、碰撞、导航或正式 TSCN。参考图商业授权待核验。

- 2026-10-24：本批 Blender 源验证与 Skill 校验通过（退出码 0）；工程契约同步及检查退出码 1，唯一错误为任务外 `godot/assets/materials/water.tres` 的既有运行哈希漂移。未修改该哈希；SEA-ASSET 主文档状态仍为“部分实现”。

## 太阳能花屋 v002 简约低面数修订（2026-10-24）

- 用户追加要求：花叶更饱满，风格更简约，所有面数 <=3000，木平台更大。按更严格的全场景三角面口径执行。
- v002 低面数源：[v002 母版](../../../art_source/scenes/solar_flower_house/v002/solar_flower_house.blend)，[实测预算](../../../art_source/scenes/solar_flower_house/v002/geometry_budget.json)。总实例展开后 1947 多边形、2999 三角面；母版单算为 822 多边形，不用该较小数字宣称整场景预算。
- 平台由约 7.4×6.6 米扩大到 8.6×8.2 米（名义面积增加约 44%），保持房屋尺度；前方连续净空检查通过。仅视觉源净空，尚未制作 Godot 碰撞或导航。
- v002 套件引用的 28 组件和装配沿用原 AssetID 更新到 v002，previous_sources 保留 v001 路径和哈希；8 个未复用旧组件仍保留登记。公共色板不改。
- [修订记录](../../development/2026-10-24_solar_flower_house_lowpoly.md)与[验证证据](../../development/2026-10-24_solar_flower_house_lowpoly_verification.json)。

- v002 本轮验证：Blender 源、实例展开预算、平台净空、独立包、UV 与真实渲染通过（退出码 0）；工程契约同步/检查仍仅因既有 water.tres 哈希漂移退出 1，未覆盖任务外记录。

## 太阳能花屋 v003 第一版风格修订（2026-10-24）

- 最新要求是先在第一版上调整色彩和花朵，参照用户新提供的游戏截图。直接打开 v001 派生 v003，未从 v002 回拼，也未运行 v001 全屋构建器。
- [当前风格母版](../../../art_source/scenes/solar_flower_house/v003/solar_flower_house.blend)，[范围锁定](../../../art_source/scenes/solar_flower_house/v003/scope_lock.json)，[配色映射](../../../art_source/scenes/solar_flower_house/v003/style_mapping.json)。
- 保留 30 项建筑组件及棕榈的几何和原始摆位；重做叶簇、藤叶、粉花、白花、黄花 5 项组件。米白/浅薄荷墙面、暖橙木色、粉白五瓣花与宽圆叶片，材质改为偏哑光。
- 当前为 36 组件、255 实例的风格源。3000 三角面优化暂缓，v002 的 2999 三角面结果仅属于 v002，不转用作本版验收结论；加大平台也仍保留在 v002。
- [本次修订记录](../../development/2026-10-24_solar_flower_house_style.md)与[验证证据](../../development/2026-10-24_solar_flower_house_style_verification.json)。Godot 接入仍 pending。

- v003 工程契约同步/检查退出 1：任务外 water.tres 哈希漂移，以及 README.md 指向尚缺失的网页目录迁移文档。未更新这些资源哈希或修改其他任务的文档；详细输出见本次验证记录。

## WorkBuddy 技能安装（2026-10-24）

- SEA-ASSET-R07：技能已安装至用户级 ~/.workbuddy/skills/sea-scene-component-authoring，工程镜像位于 .workbuddy/skills/sea-scene-component-authoring。
- 附带原始 8×8 公共色板 PNG、颜色 JSON 和 asset_manifest.json；PNG 哈希与原登记一致，不修改工作色板或资产哈希。
- 同步入口 .workbuddy/tools/sync_sea_scene_skill.py 连跑两次退出 0；逐文件 SHA-256 校验及漂移负向断言通过。详见 docs/development/2026-10-24_workbuddy_scene_skill.md。

## 参考图错层花屋码头（2026-10-24）

- 用户要求按附件完整还原，不接受自行简化和布局偏差；船不制作。首个简化候选已撤出交付，按附件重新制作 `pastel_flower_harbor/v001`。
- [完整 Blender 源](../../../art_source/scenes/pastel_flower_harbor/v001/pastel_flower_harbor.blend)；[本轮制作记录](../../development/2026-10-24_pastel_flower_harbor.md)；[结构化验证记录](../../development/2026-10-24_pastel_flower_harbor_verification.json)。
- 30 组件、142 实例，其中花草实例 67；建筑与花草分离。完整实例求值合计 146514 多边形 / 269760 三角面；当前请求未指定低面数上限。
- `SEA-SCENE-PFH-` 前缀，共 31 条新记录通过总索引路由到场景分账本；公共色板及已有太阳能花屋源不覆盖。源索引从分账本派生。
- 仅 Blender 源级交付；未接入 Godot，碰撞、导航、运行性能与参考图商业使用权 pending。

- 本批最终结果：源级验证及四视图渲染退出 0；工程契约同步/检查退出 1，仅有既有 water.tres 哈希漂移，未修改任务外哈希。参考图还原已目视核对，未声明像素级零偏差或用户美术验收通过。
