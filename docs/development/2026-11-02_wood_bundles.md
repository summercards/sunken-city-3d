# 2026-11-02 海面三档浮木

承接SEA-PICKUP-R16–R19 / SEA-SAVE-R12。用户要求海面浮木分少、中、多三档，模型与范围不同，阳光房附近多量级很少、外圈更常见；补充将固定3／8／15改为随机2–3／7–9／12–16，交付时更新设计与账本。

**后续外观修订：** 用户指定复用最小三根绑带小束，三档改为1／2／3个相同单元。本页逐根匹配奖励数量的模型方案、旧中大档尺寸和范围属于首轮记录，当前以[小束复制修订](2026-11-02_wood_bundle_copies.md)及功能spec为准；奖励、概率、密度及补货规则继续有效。

后续修订的文档摘要同步与普通检查已均退出0；本页末尾的8处哈希阻挡是首轮历史结果，当前结果见上述修订记录。

## 设计与正式实现

完整参数以[SEA-PICKUP功能文档](../features/pickup/spec.md)为准：45米内90%／9%／1%，45–150米线性过渡，150米外40%／40%／20%。参考点为阳光房主体占地中心XZ `(6.158,1.813)`；先抽档，再在档内均匀抽整数。平均单束收益由近处3.11增加到外圈7根。束数密度、鱼群和原补货日历保持。

- `wood_bundle.gd`集中三档数量、概率、模型尺度、水纹和范围；`sea_props.gd`以真实数量生成逐根程序网格并统一结算、点击及交互查询，外侧木头本体也能点中。
- `ocean_population.gd`持有槽位数量和补货代次，使用独立随机流，避免改变鱼群随机序列。先按原算法生成鱼群布局，再只迁走不满足大档包络的浮木；家园仍总计6束。
- `save_schema.gd`校验可选数量、代次与未加载槽位缓存。旧档已存在的浮木按原3根保留，跨分区回访也稳定；已采槽位和冷却不丢失。下一次真正补货／日更才换新分布。
- 主场景通过公开查询取范围，hover通过同一查询取实际收益；小／中／大停船打捞范围2.2／2.7／3.3米，计时仍1.2秒。成功一次仍按原规则扣打捞体力。

这是既有运行程序模型的深化，没有新Blender／GLB文件、未改手工TSCN或网页原型。资产索引路由至items分账本；该域既有运行资源补登仍pending，本轮未虚构AssetID或授权验收状态。

## 当前实测

由`scripts/run_verification.py`创建工程外副本及独立用户目录，在Autoload前隔离玩家存档。以下均为本轮实际执行，退出码和标记双重检查。

| 检查 | 实测 | 退出码 | 渲染 |
|---|---|---|---|
| wood-bundles | 33项0失败；近／外圈各20000次抽样、含端点范围、10种可能数量逐一结算、满包整束保留、磁盘往返、两代旧档、区块回访、补货代次、各档范围内外 | 0 | headless |
| wood-density | 16项0失败；家园6束、外海18/60、鱼群原布局、密集旧档及冷却保留 | 0 | headless |
| ocean-pickups | 48项0失败；远海日历、取消、冷却、存读及到站朝向 | 0 | headless |
| building-integration | 53项0失败；实际浮木数量入包、点击巡航后才捞、家园建造及存读 | 0 | headless |
| minimum-loop | 141项0失败 | 0 | headless |
| progress-bars | 45项0失败；停船／取消／失败结算与进度条 | 0 | headless |
| visual-ocean-pickups | 14项0失败；正式海面密度及真实收获浮层 | 0 | 真实渲染 |
| visual-wood-bundles | 35项0失败；同一运行网格三档对比、外侧木头投影超出旧26px仍可点击 | 0 | 真实渲染 |

证据目录（均在工程外）：

- `D:/projects/sea-work/verification/20261102-104635-wood-bundles-specialists-3a7c71/`：wood-density专项报告。
- `D:/projects/sea-work/verification/20261102-104823-wood-bundles-integration-7c6b10/`：建造／生活／进度条集成与原生海面收获渲染报告。
- `D:/projects/sea-work/verification/20261102-105003-wood-bundles-final-a09625/`：最终逻辑33项及ocean48项，含无ocean旧档兼容补强。
- `D:/projects/sea-work/verification/20261102-105139-wood-bundles-preview-7dcce7/`：最终35项真实渲染与`project/outputs/wood-bundles-comparison.png`。图中3／8／15是三档示例，不代表固定产出。

预期故障：无预期引擎错误；测试主动提交非法数量、字段类型、槽位等，均以返回失败验证恢复事务，不能报SCRIPT ERROR。最终专项和集成均无非预期脚本／引擎错误。保留导航体素精度等既有WARNING，不把它们混记为预期故障。

初轮曾有两条断言失败（退出1）：PlaneMesh单精度尺寸用精确浮点相等比较，已改近似；未加载槽位的JSON整数缓存恢复成float导致快照文本不一致，已在正式OceanPopulation恢复时转回int。后续对应专项通过，初轮证据保留于`20261102-104356-wood-bundles-a4d5d6`和`20261102-104516-wood-bundles-fix-3a3fbd`，未覆盖成历史成功。

未执行：人工长时航行手感、手柄与发行平台验证；未写入玩家存档、未运行整套core（相关专项后已做必要集成）。

## 文档门禁与范围外差异

本轮功能文档、独立账本及主文档内容已更新；功能整体状态仍为partial，不借一次专项把长期功能改为全部验收完成。仅定向更新了本轮已审查的`godot/src/bootstrap/main.gd`运行基线；未批量刷新资产哈希。

最终已顺序执行`python3 scripts/check_feature_contracts.py --sync`和不带参数的检查，均退出1。`--sync`被8处本轮以外的哈希差异阻挡：`godot/assets/materials/ocean_sky.tres`，以及`godot/src/building/`下的`building_catalog.gd`、`building_service.gd`、`building_space.gd`、`building_world.gd`、`building_access.gd`、`building_controller.gd`、`building_book.gd`。不带参数检查另报告派生feature_index陈旧（同步器在任何问题存在时不写索引），共9项；本轮新增条款承接、文档链接与资源路径没有报错。未用未知变更的新哈希掩盖这些差异。

两次结构检查的退出码与完整日志保存于最终预览证据目录的`feature-contract-report.json`、`feature-sync.log`和`feature-check.log`。`git diff --check`退出0，仅有工作区既有LF/CRLF转换提示。以上结构问题与本轮运行专项通过分别登记。
