# 2026-11-02 八层海上屋顶农场 Blender 源

关联条款：SEA-ASSET-R41。按用户参考图及后续修订，在 Blender 中制作独立水上功能建筑候选。本轮交付制作源、组件包、预览和账本，不自动接入正式游戏场景。

## 范围与最终内容

- 套件：`art_source/scenes/ocean_rooftop_farm/v001/`；母版 `ocean_rooftop_farm.blend`，场景 `海上屋顶农场_制作与装配_v001`。
- 八层可见楼体，3.2 米层高，主屋顶 36×24 米；屋顶含前压顶的实测包络为 36.10×24.05 米，行走面 Z=25.60 米。
- 左后 8×7 米抬高平台底面与主屋顶相接，平台顶 Z=29.00 米；上层小间坐落 Z=29.00 米。水塔罐顶实测 Z=34.49 米，符合约 9 米名义总高。
- 保留红褐屋顶工具房、温室、风力装置、储物、步道、休息区、空田垄与空菜床。按用户最新要求删除全部农作物与太阳能板，不含人物、动物、海洋或远景建筑；普通草地和盆栽保留。
- 大块地砖有真实厚度、缺角、裂缝、磨损和局部裸露基层；房屋及立面有剥落、裂口、露筋、破窗、封窗木板、外露管道和锈蚀。采用饱满、圆润、简化的玩具感卡通几何。

## 组件、材质与尺寸验收

- 44 个唯一组件 Collection，302 个 Collection Instance；80 扇唯一正侧面窗、32 个阳台、8 块楼板。44 个独立 `.blend` 包和对应 `asset_manifest.json` 全部生成并重开。
- 公共色板 `art_source/shared/palettes/sea_cabin_timber_8x8_512.png` 保持外链；仅使用 `SEA_Matte`、`SEA_Metal`、`SEA_Gloss`、`SEA_Emission` 四角色，Closest 采样，每网格只有活动及渲染启用的 PaletteUV。
- `sea-work/ocean_rooftop_farm/v001/verification.json` 最终 `passed=true`、`errors=[]`，共 47320 项检查；6130 个母版面逐面 UV 检查，实例展开为 115208 多边形 / 233672 三角面。没有用户指定的低面数上限。
- 通用验证器 `tools/blender/ocean_rooftop_farm/validate_skill.py` 仅将格网检查适配到 sea 8×8 色板，其余材质、输出、外链图片、活动 UV、自发光与归属规则不变。44 个组件全部通过，见 `skill_prop_verification.json`。
- 五视图 `beauty.png`、`roof_detail.png`、`top.png`、`facade_detail.png`、`building_only.png` 均由最终保存源渲染并目视查看；平台、屋顶设施、水塔支架及温室连接正常，地砖与破损细节可辨。

## 修订及纠错记录

1. 初版三层屋顶农场完成后，按用户反馈改为八层、删除作物和太阳能板、加入旧地砖及建筑破损细节。
2. 修复公共色板路径丢失造成的紫红渲染；修复重复执行造成的屋顶设施二次抬升，使屋顶、平台、小间及水塔恢复连接。
3. 严格验收按含压顶屋顶包络、实际行走面及约 9 米水塔名义尺寸分别核对；修正 `facade_weathering` 微小原点偏差。
4. 失败重跑遗留 6 个重合实例：一份整屋地砖、一份立面破损及四扇破窗。已去重至 302 实例，并在验收中加入五位小数变换签名的重复检查，防止重合闪面。
5. 通用验证器发现发光灯泡名称不含明确灯光标识，将 `暖灯` 改为 `暖灯_UI灯光`，几何不变；重跑两级验收后通过。
6. 活跃 Blender 的 MCP 在反复 `read_factory_settings/open_mainfile` 后停止监听，但 Blender 进程仍在。后续清理、重开、验收与渲染改用独立后台 Blender，没有继续操作该会话。若需继续 MCP 操作，在 Blender 的 BlenderMCP 面板重新连接。

## 登记、边界与复现

- `register_sources.py` 仅在主源 QA 通过且哈希一致时执行。已将 44 个组件和 `SEA-SCENE-ORF-ASSEMBLY` 共 45 条记录经索引写入场景分账本，装配清单为 `v001/asset_manifest.json`。
- `tools/apply_water_layer.py` 新增 `SEA-SCENE-ORF-` surface/assembly 家族规则；装配为 `above_water` 实体，组件为其零件。同步后场景账本共 612 条，其中 above_water 367 条。
- 源索引由分账本派生；登记工具断言无关资产旧索引记录不变，没有刷新其他任务哈希。
- 打开说明：`art_source/scenes/ocean_rooftop_farm/README.md`；功能账本：`docs/features/asset/ledger.md`。
- 最终实际执行 `scripts/check_feature_contracts.py --sync` 及两次无参数复核，均退出码 0：`PASS: 39 features, 625 source assets, 515 runtime resource hashes; 0 issues`。日志位于工程外本套件 `feature_contracts_sync.log`、`feature_contracts_check.log`。
- 正式源验收顺序为 `verify.py → validate_skill.py → register_sources.py`，使用 `blender --background --python-exit-code 1 --python <script>`。历史生成/修订脚本不应在已手改母版上随意重跑。

明确未执行：Godot GLB/PackedScene/TSCN 接入、角色及船碰撞、导航、实际生产或交互玩法、运行性能、参考图商业授权和用户最终美术验收。本记录中的“通过”仅指 Blender 源级与通用材质/UV检查。
