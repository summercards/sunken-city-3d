# 2026-11-07 阳光房独立水下美术 r2 与精确阻挡（已独立验收，产品未接入）

[主文档](../../GDD_V1.0.md) · [潜水规范](../features/dive/spec.md) · [潜水账本](../features/dive/ledger.md) · [环境规范](../features/ambient/spec.md) · [环境账本](../features/ambient/ledger.md) · [资产规范](../features/asset/spec.md) · [资产账本](../features/asset/ledger.md) · [上一轮交付](2026-11-07_sunroom_underwater_region.md)

## 1. 最终独立验收与回归签署

**最终报告**：`D:/projects/sea-work/verification/20261107-232826-sunroom-art-r2-signed-5f3e30/report.json`。225915 unified-fog批78/0、264/0、114/0保留为中间历史，以下signed结果为本轮最终运行证据，运行final不再pending；登记和静态门禁结果另列第8节。

| 入口 | 最终结果 | 证据范围 |
|---|---|---|
| sunroom-underwater | PASS，78 checks / 0 failures，exit0 | 独立区域结构；同目录sunroom-underwater.log |
| sunroom-collision | PASS，264 checks / 0 failures，exit0 | 真实物理与安全定位；同目录sunroom-collision.log |
| visual-sunroom-underwater | PASS，118 checks / 0 failures，exit0 | 真实18机位＋远雾像素＋射光开关差分；同目录visual-sunroom-underwater.log |
| dive-maps | PASS，302 checks / 0 failures，exit0 | 旧地图机制回归；同目录dive-maps.log |
| modules | PASS，31 checks / 0 failures，exit0 | 模块回归；同目录modules.log |

新区域三项460/0，回归333/0，总计 **793 checks / 0 failures**。五项`unexpected_errors`均空，`completion_marker=true`、`failure_labels`空。报告记录HEAD `aa12686907371f5e389e5923f259a2f886738235`及working_tree快照；HEAD不等于全部改动已提交。真实渲染为RTX4060Ti、Vulkan1.4.341 Forward+，1280×800、fixed-fps60；固定帧参数不代表性能达60FPS。

父线程已目检 **home-base / ray-street / coral / fish / far-edge / corner-close**，最终远角为pure gradient无边，近处建筑/地板等实体轮廓不等于远雾cut；不冒称18机位每张全细节人工签署，也不代替用户完整产品接受。

| 最终视觉证据 | 结果 / 范围 |
|---|---|
| far-fog-edge 像素最大差 | 0.0078431517 < 0.025 |
| corner 像素最大差 | 0.0039215982 < 0.025 |
| west 像素最大差 | 0.0039215982 < 0.025 |
| 射光实际可见 | shader射光on/off差分lit_samples5365 > 150，不仅是node计数 |
| 默认射光 | 默认环境画面与上述开关像素差分共同证明实际可见 |
| 气泡 | 独立列为泡尘表现与动态审阅，不拿射光节点数替代 |
| 珊瑚 | coral近景及色彩/接地审阅，不冒称新GLB |
| 鱼 | fish视角与默认环境中鱼体/色差审阅 |
| 低照灯 | 单独低照灯具/局部实灯视角，不拿低照效果冒充默认射光 |

最终local Environment、Sky和material均`resource_local_to_scene`，保护多实例环境/天空/材质，不把本区域状态写入共享资源。

初填历史：当时三个runner正在跑，全部pending，758proxy/约300万三角仅预计；初版环境depth fog6..100/curve1.65、8steps及焦散0.13为过程快照。以下当前实现和实测取代这些旧参数，不删除其初填时点。上一轮205426的67/0、89/0仍只属于旧交付，不作为r2证据。

## 2. 范围与生产边界

用户追加要求：新区域与旧海域水下美术一致，远景在雾中不能切边，建筑物体有阻挡，补气泡/海面射光并深化色彩层次。对应SEA-DIVE-R14、SEA-AMBIENT-R24、SEA-ASSET-R60；追加前最大ID分别R13/R23/R59，没有新增重复条款或AssetID。R13/R23“不新增碰撞”是上一轮历史，本轮仅对本独立scene追加阻挡，不改海面观赏建筑职责或原9图手工solid。

- 入口仍`godot/scenes/underwater/sunroom_region.tscn`，F6独立预览，右键＋WASD/QE、Shift加速。`production_route_integrated=false`，未接production player、DiveSession生产路由、catalog或存档；不称第10可潜水图或默认开放。
- toplevel、原位置、范围、深度不变，不重摆/整体下沉/扩域掩盖切边。city240×240、terrain1024×1024、water1280×1280米是不同职责域。
- 原海面Y=1.12、旧城根Y=43.487442及基座矩阵保持；这里只记现有摆位，不给未来用户手摆新增绝对坐标硬规则。沿用海床-62..-18.562597、最大深63.12米及旧城包络P(-120,-38.65286,-120)/S(240,37.00966,240)的尺度口径。
- 本任务不修改Main。**Main 可能被并行修改，不要求 Main 字节不变**。不能宣称主场景一直没有并行变化，也不能把Main字节相等作为本任务register guard的必要条件。
- 50城市源GLB不动。原9图、旧城、base、海床、原GLB共70保护项由父线程最终核对；未回填前不签全量哈希保护完成。不得批量刷新共享资源或未知漂移来消除差异。

## 3. 当前水色、统一雾与材质

### 3.1 单一屏幕混合，替代环境雾

runtime明确`environment.fog_enabled=false`；TSCN中的旧环境雾配置不代表运行时有效。真正水下吸收使用与旧地图相同的pass顺序：**一个opaque WaterFogPass，render_priority=-128**，采屏幕颜色/深度后统一混合。

`sunroom_underwater_color.gdshaderinc`提供共同水色/吸收函数：

- 距离6..110米，curve1.3；距离项为`pow(smoothstep(6,110,distance),1.3)`。
- 天空、水顶、地形经统一pass使用同一相机方向的上下渐变水色，随视点水深调整，不各自叠不同雾色。
- 有限海床边缘按`max(abs(world.x),abs(world.z))`在448..500米额外fade，与距离项取max；这是视觉吸收，不缩小可动范围、不改高度源。
- 透明泡尘自行应用同一水雾并衰减alpha；beam继承同距离fade。引擎环境雾停用，不再双雾叠加。

过程缺陷是Environment fog＋aerial1在角落产生三角块；改为单通道后，当前已审far-edge/corner-close实拍边角为纯渐变无边。旧黑水平线不能只靠surface的fog标志位解释：当前由统一水色、天空/水顶/地形合成和边缘吸收共同收敛。

### 3.2 局部PBR、光照与水顶

| 项目 | 当前参数 / 方向 |
|---|---|
| 旧海域参考 | 主光#edffe3、环境#b9e9e2、辅光#a1f7ef，近景保留米白/暖色，中景青绿吸收、远景水色渐变 |
| 光照能量 | ambient默认0.48→深水0.29，Sun0.60→0.30，Cool0.13；ambient过渡深度18..60米，Sun14..60米 |
| PBR palette | 本区域surface override保留色板/顶点色、roughness/metallic；不写共享Mesh surface/GLB材质缓存或制作源 |
| 焦散 | 仅朝上面低强度动态焦散，gain0.075，随深度衰减，不整栋自发光 |
| 地板与水顶 | 压下之前泛白地板；水顶纹理gain0.18，保持正常水色，经统一pass吸收，不另叠环境雾 |

## 4. 鱼、气泡、尘埃与软射光

保留8群138鱼、32簇珊瑚、24实灯（16Omni/8Spot，局部阴影0），不替换旧模型或重复整个礁群。

- 10条水面下1米起、长度21..29米的软体积代理光；不是新增10个真实灯，也不是引擎体积雾验收声明。
- beam采用加色、**16steps**体内积分，采scene depth截断不透明墙/楼板，软交界与软端边；density基值**0.085**，按束加0/0.008/0.016，输出soft cap **0.23**。使用共同距离fade，不双雾；透明几何遮挡不能由不透明深度自动保证。
- 192泡/200尘，2个MultiMesh、固定seed73191，`sample(time)`/`snapshot(time)`可定时采样；粒子自雾并衰减alpha，避免远景亮点露出水雾。
- 气泡列终点在水面下0.65米，光束/泡/尘仍是无碰撞纯表现；物体阻挡由独立区域碰撞系统拥有。

## 5. 精确物理代理与安全Viewer

### 5.1 真实规模与缓存

| 指标 | 当前实测 |
|---|---|
| proxy | 758 |
| uniqueMeshes | 85 |
| cache shapes | physicsrun99 / visual158，不要求一致 |
| instanceTriangles | 3115351 |

按Mesh/MultiMesh实例的实际变换建立exact concave/backface代理；非均匀缩放/剪切烘入形状，以mesh＋deformation缓存并immutable复用，不能逐实例修改共享形状。保留窗洞、桥下、凹形空隙，不以整包AABB代替。physicsrun缓存99、visual缓存158：两者使用同一精确Basis key，启动浮点差异会拆分缓存键；各角色数量、assemblies、triangles一致，不能冒写缓存数完全相同。85个uniqueMeshes与缓存数均不等于新增源GLB数量，50城市源GLB不动。

Terrain3D仅本区域实例collision_mode=3（FullGame），不改data/material/assets或高度源。碰撞scope只属于本独立scene，未来角色可复用，不代表生产player已接入。

### 5.2 分段扫掠、安全定位与出生

Viewer胶囊半径0.35米/总高1.6米，margin0.001米，正常8米/秒、Shift18米/秒。`move_and_collide`每段≤0.75米、每段最多8slide，总预算2048steps/4096tests，控制长请求接触精度并保留斜向滑动。旧100米cast保守停靠约0.09米，曾使精度断言不达标；这是保守停靠误差，不是穿透，也不能写成初版阻挡失效。≤0.75米substep后最终两轴thinwall末位接触误差<0.03米。

`try_set_viewer_position`拒绝重叠/越界；raw set仅用于测试fixture，不作安全传送保证。F6出生延迟至新增静态体和Terrain3D物理提交后校验。Viewer水面下中心上限为 **1.12−0.8−0.02=0.30米**，避免胶囊顶部穿出水面。

当前264/0覆盖：100米请求thinwall两轴精准接触误差<3厘米、全部8roles至少1抽样、海床、桥下路口、斜滑与安全定位。它是实际胶囊/物理验收，不是ray-only；抽样不代表所有758proxy每个面都走过，也不签全路线人工探索。

## 6. 性能与产品未验边界

初次建树collision报告 **setup1834.253ms、load256.285ms**，仅单次样本，不是持续帧时间、FPS或低端通过。3115351实例三角的精确物理、透明16步光束/粒子overdraw、24实灯与焦散均有开销；缓存和较少提交数不能替代实测。

低端设备、连续运行、稳定CPU物理/GPU帧时间及内存/显存仍pending。纸面budget不作为验收，也不允许降级成整包AABB伪造性能达标。来源/rights、完整02b复用签署、产品接入与完整用户验收继续pending。

## 7. 唯一资产v002与15文件待登记

唯一AssetID仍`SEA-SCENE-SUNROOM-UNDERWATER-REGION`。父线程正在执行v002白名单定向登记，**实际写成功及退出码待父线程回填**，不能先写成已升级。仅允许4个JSON目标：`assets/registry/ledgers/scenes.json`、`assets/registry/manifests/scene_components/sea-scene-sunroom-underwater-region.json`、`assets/registry/current_source_index.json`、`assets/registry/runtime_resource_inventory.json`；事务backup/回滚及old history保留，不执行旧GLB导出，不批量刷新未知hash。R59旧6文件登记不自动覆盖r2。

总源15文件如下；原6保留并扩展9文件，不新造Blend/优化源/GLB，不重复登记旧组件。

| 组别 | 文件 |
|---|---|
| 原6 | godot/scenes/underwater/sunroom_region.tscn |
| 原6 | godot/scenes/underwater/sunroom_region/ecology.tscn |
| 原6 | godot/src/diving/sunroom_region.gd |
| 原6 | godot/src/ambient/sunroom_underwater_ecology.gd |
| 原6 | godot/shaders/sunroom_underwater_surface.gdshader |
| 原6 | godot/shaders/sunroom_underwater_lamp.gdshader |
| atmosphere相关3 | godot/scenes/underwater/sunroom_region/atmosphere.tscn |
| atmosphere相关3 | godot/src/ambient/sunroom_underwater_atmosphere.gd |
| atmosphere相关3 | godot/src/diving/sunroom_region_collision.gd |
| 新增shader/include6 | godot/shaders/sunroom_underwater_palette.gdshader |
| 新增shader/include6 | godot/shaders/sunroom_underwater_beam.gdshader |
| 新增shader/include6 | godot/shaders/sunroom_underwater_particles.gdshader |
| 新增shader/include6 | godot/shaders/sunroom_underwater_sky.gdshader |
| 新增shader/include6 | godot/shaders/sunroom_underwater_fog.gdshader |
| 新增shader/include6 | godot/shaders/sunroom_underwater_color.gdshaderinc |

功能账本verification关联包含sunroom-underwater、sunroom-collision、visual-sunroom-underwater；登记头和历史保留。本次仅精准更新本轮docs/GDD节，不修改登记JSON，不运行命令、sync或登记工具。

runtime白名单共17文件：上表15源＋`godot/tests/test_sunroom_underwater_region.gd`＋`godot/tests/test_sunroom_underwater_collision.gd`，两份测试不计为新美术源。

### 当前命令与参数记录

最终五入口实际Godot命令取自signed报告。以下命令只记录，不在本次执行；每项日志、完整command数组、HEAD/working_tree均可从最终report追溯：

```bash
"C:/Users/zhuangmenghong/bin/godot.CMD" --path "D:/projects/sea-work/verification/20261107-232826-sunroom-art-r2-signed-5f3e30/project" --headless --script res://tests/test_sunroom_underwater_region.gd -- --skip-title
"C:/Users/zhuangmenghong/bin/godot.CMD" --path "D:/projects/sea-work/verification/20261107-232826-sunroom-art-r2-signed-5f3e30/project" --headless --script res://tests/test_sunroom_underwater_collision.gd -- --skip-title
"C:/Users/zhuangmenghong/bin/godot.CMD" --path "D:/projects/sea-work/verification/20261107-232826-sunroom-art-r2-signed-5f3e30/project" --resolution 1280x800 --fixed-fps 60 --script res://tests/test_sunroom_underwater_region.gd -- --skip-title
"C:/Users/zhuangmenghong/bin/godot.CMD" --path "D:/projects/sea-work/verification/20261107-232826-sunroom-art-r2-signed-5f3e30/project" --headless --script res://tests/test_dive_maps.gd -- --skip-title
"C:/Users/zhuangmenghong/bin/godot.CMD" --path "D:/projects/sea-work/verification/20261107-232826-sunroom-art-r2-signed-5f3e30/project" --headless --script res://tests/test_feature_modules.gd -- --skip-title
```

登记工具为`tools/register_sunroom_underwater_art_r2.py`。当前参数契约：必填`--baseline`（修改前真实baseline，不能以现盘补造）、`--evidence`（本次signed报告）；可选`--before-project`（旧工程副本）；写入需`--write`及已存在的工程外`--backup-dir`。以下为参数模板，baseline/backup/before-project实值未在本次交接中提供，须父线程以实际argv替换，**不冒称以下模板是已执行成功命令**：

```text
python tools/register_sunroom_underwater_art_r2.py --baseline "<父线程真实baseline.json>" --evidence "D:/projects/sea-work/verification/20261107-232826-sunroom-art-r2-signed-5f3e30/report.json" --backup-dir "<父线程真实工程外备份目录>" --write
可选追加：--before-project "<父线程真实旧Godot工程副本>"
```

## 8. 最终运行签署、登记及静态门禁

最终运行报告232826-signed：78/0、264/0、118/0、302/0、31/0，总793/0，五入口全PASS/exit0无unexpected；新区域460/0、回归333/0。远雾像素与射光可见差分已经纳入，不再将运行final写成pending。产品接入、性能和资产权属不随运行签署自动完成。

| 收尾项 | 当前真实状态 | 父线程回填要求 |
|---|---|---|
| v002定向登记 | 已写入成功；第二次dry-run为0项变更 | write exit0；4JSON、15源/17runtime已定向更新，事务目录为`D:/projects/sea-work/outputs/sunroom-underwater-art-r2-20261107/sunroom-underwater-v002-lrbgphni`，旧v001 history与回滚副本保留 |
| 原9图/旧城/base/海床/原GLB70保护项 | 70/70保持不变 | 最终摘要确认70项均未变化；Main 也与本次baseline一致，但未来并行修改不受本次保证限制 |
| check_feature_contracts.py --sync | exit1，25项问题；43功能/967源/1381运行哈希 | 登记后本轮总成漂移已消除；剩余为鱼群/土壤源漂移及NPC、海水、主场景、存档等并行/历史运行漂移，未批量刷未知哈希 |
| check_feature_contracts.py 普通check | exit1，28项问题 | 含SEA-SHOP/SEA-RESIDENT状态索引、鱼群/土壤源漂移及并行运行哈希漂移；不代表本轮运行验收失败 |
| 低端/连续performance | pending | 真实设备、CPU物理/GPU帧时间/内存及持续测量，初次建树单次记录不是FPS通过 |
| rights/user acceptance/完整02b | pending | 各自独立证据，技术目检不代替用户接受或权属/优化源签署 |
| production player/路由/存档 | 未接入，pending | 保持production_route_integrated=false，不称默认开放 |

### 父线程静态门禁真实输出回填位

- 定向登记：write exit0，第二次dry-run exit0且planned_changes=0；4JSON目标、15源/17runtime白名单已更新。事务备份：`D:/projects/sea-work/outputs/sunroom-underwater-art-r2-20261107/sunroom-underwater-v002-lrbgphni`，旧history与回滚副本保留。
- `check_feature_contracts.py --sync`：exit1，25项问题；43功能/967源/1381运行哈希。登记后本轮总成漂移已消除，剩余为其他并行/历史漂移。
- 普通`check_feature_contracts.py`：exit1，28项问题；含索引状态和其他运行/源漂移，不覆盖本轮793/0专项运行验收。
- 70保护项：70/70保持；`check_placed_positions.py`为3结构/0warning，`git diff --check`为exit0。

本轮最终已完成v002登记写入；普通静态检查保留真实未解决项，未批量刷新未知哈希。
