# 场景组件细分、荷叶及动物恢复

日期：2026-10-27。功能：SEA-ASSET / SEA-AMBIENT / SEA-WORLD / SEA-DIVE。

[主文档](../../GDD_V1.0.md) · [场景分类目录](../../assets/registry/SCENE_COMPONENTS.md) · [机器验证记录](2026-10-27_scene_component_split.json)

## 本次改动

- 六设施维持独立建筑归属。横滨铁道、圆弧农场、远海街町、浅水养殖台共13个旧建筑单元新增可独立引用的 PackedScene 包装，保留原 GLB 子节点、材质覆盖路径及摆位。太阳房/打捞台总成提供组件身份接口。
- 太阳房25个可移动家具实例（13类模型）从共享批次拆出独立对象根；桌椅、沙发、花盆、花瓶、瓶子、箱子、地垫、太阳伞及灯笼分别维护。结构仍共享批次。花草按建筑升级附件拆分，原42种植物补齐AssetID；当前世界共276个植物实例（原植物场161、太阳房及基座115）。
- 太阳房160条、基座298条摆放记录添加持久实例ID；除新ID外与HEAD的JSON逐项相等。原模型/Blender源文件无改动，未改用户手工布局。
- 24片缺口荷叶恢复为独立组件：横滨15片逐顶点核对原烘焙并在运行时退役840个旧三角面；港湾9片已随旧建筑不可见，本轮按原位置恢复。没有修改原GLB，没有按包围盒删面。静态批次对照也排除相同几何ID，避免切换产生双层。
- 飞鸟改成独立组件，7只飞鸟保留原网格与颜色，增加振翅采样，将轨道高度统一上移12米。实测太阳房顶界Y=12.60833，覆盖30秒完整轨道的每只鸟网格最低点均高于屋顶1米以上。
- 海面场景缺失的水下装饰恢复为3群鱼（每群18条）和1头巡游鲸。鲸以原型的长须鲸体量和铰接摆尾意图重建原生运行组件，位于南侧水域；原有可采集鱼群继续归SeaProps。
- 潜水区7群鱼复用独立鱼群组件，由潜水层注入深度材质和动画时钟；不写库存、氧气、宝箱或存档。

## 接口与维护

`scene_component.gd`：`describe()` 返回资产/实例/设施/附件槽/分类/允许动作；`request_interaction()` 仅发意图事件；`set_upgrade_level()` 输入建筑等级并按`unlock_level`显隐。太阳房当前花叶默认0级可见，保留当前美术状态；原PlantField继续按建筑等级生长。

正式移动玩法尚未在此任务实现。后续摆放系统需消费relocate事件，检查可放范围及资源，原子更新位置，并按稳定实例ID存档。不能把“接口返回true”理解为已经落地移动。装饰动画相位不入存档。纯视觉组件显式`visual_only`，船只阻挡与岸线扫描跳过；不放采集命中面。

旧四区的建筑单元仍含固定附属细节，本次未凭不可靠的自动分割把这些网格全部认定为可移动家具；账本将未逐件识别的内部陈设保留为待语义拆分。已有明确家具组件已全部独立，源级重建/新美术造型与参考素材权属仍分别登记，不代签授权。

## 验证

所有运行检查均经`scripts/run_verification.py`，在Autoload之前隔离用户目录，输出位于工程外sea-work。当前检查实测：

| 专项 | 结果 | 证据 |
|---|---|---|
| decorations | 1585项通过（随后补单组件独立加载检查） | 150534-delivery |
| visual-decorations | 同一逻辑专项真实Vulkan渲染通过，3张实景已查看 | 150534-delivery |
| solar-components | 独立太阳房/基座组件加载与色板检查通过 | 150534-delivery |
| visual-solar-cabin | 695项几何、原位、基座与色板检查通过 | 150142-final |
| surface | 30条航线、503项检查通过 | 150534-delivery |
| selftest | 537通过0失败 | 150534-delivery |

首轮visual-solar-cabin的唯一失败是旧断言还使用打捞台历史位置(-12,0,13)。HEAD正式场景早已为(-5,0,4.15)，更新测试后通过；本任务没有移动打捞台。该轮失败原样保存在机器记录中。selftest的损坏JSON恢复用例允许一条预期Parse JSON错误，与退出码/真正错误分开登记。

真实画面目录：`D:/projects/sea-work/verification/20261027-150534-decorations-delivery-4c1de8/project/outputs/`，包含`decorations-home.png`、`decorations-animals.png`、`decorations-lilies.png`。鱼与鲸在当前水材质下可见，未调整水材质掩盖缺失问题。

## 最终独立组件与潜水实景补验

- `20261027-163537-decorations-independent-197e1e`：单独实例化鸟、鱼群、鲸及荷叶均产生实际几何；decorations 1589项通过。鸟可直接从PackedScene使用，无须依赖群管理器才出现。
- 旧`visual-underwater-capture`因缺少历史网页相机基准JSON退出2，未声称完成同机位对照。改为当前正式场景独立近景：`20261027-163954-decorations-dive-final-628b3a`，visual-decorations 1592项、退出0，无引擎错误。
- 补验覆盖潜水时隐藏海面动物、7群潜水鱼组件、真实水下可见性，以及公开`surface()`经exit状态返回海面并恢复Environment。`decorations-dive-fish.png`已查看。
- 中间探针163833错误地从swim调用私有完成入口跳到surface，被状态机合法转换表拒绝；修正探针为公开上浮命令后通过。保留失败证据，没有为了通过而放宽正式状态机。
- `check_feature_contracts.py --sync`及无参数检查：32功能、426源资产、317运行资源哈希，0问题。只更新本轮两份实例清单的哈希；验证原JSON除稳定ID之外完全一致。GLB/Blender源和水材质无改动。

最终画面：`D:/projects/sea-work/verification/20261027-163954-decorations-dive-final-628b3a/project/outputs/`。
