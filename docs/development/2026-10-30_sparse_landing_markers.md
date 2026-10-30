# 2026-10-30 自建平台上岸提示稀疏与闪烁修复

对应SEA-BUILDING-R13/R17、SEA-UI-R38；不改变实际平台、导航、上下船和存档规则。用户反馈：扩建后上岸图标过密，新图标周期闪烁。

## 原因与修改

原BuildingAccess.refresh_markers每0.75秒先删除全部dynamic_build字典，再创建visible=false、near=0、size=30的新字典。该Node在LandingMarkers之后处理，当帧画布因此拿到未投影的不可见图标；下一帧重新出现，悬停大小/颜色又从头插值。另有原4米间距、最多8个的策略，在中等平台周边仍然过密；每次按船距重排还会让候选跳动。

修改为：

- 普通动态提示最小水平间距12米，约5块木板；再加100px投影间距，每轮最多4个自建提示。视野内固定泊位提示也参与避让，避免原泊位周围再堆新图标。
- 优先保留有效当前返船ID，即使它不在最近24块板候选内；再保留仍可见/有效的旧提示，最后补充新候选。厘米级船位变化不洗牌。
- LandingMarkers新增sync_dynamic_markers，按zone+landing复用原Dictionary，只更新位置/名称；保留near/size/visible等展示状态，同步当帧完成投影，不再制造一帧空白。
- 上述限制只影响提示。landing_data、稳定登陆ID和直接点击实际板面的登陆能力不删减，也不修改玩家已有布局或存档。

代码：godot/src/building/building_access.gd、godot/src/ui/landing_markers.gd。12米、100px、最多4个集中为常量，后续可统一调整。有效当前返船入口优先，必要时允许在固定泊位附近保留；普通图标之间仍执行间距。

## 验证与证据

全部运行经scripts/run_verification.py，Autoload前隔离用户目录，不改玩家存档。新入口landing-markers / visual-landing-markers同用godot/tests/test_landing_markers.gd。

- 首次20261030-105806-sparse-landing-markers-ccc784：两轮各23项/2失败，退出1。失败出在测试夹具把虚拟图标放在初始相机外，还要求保留伪造屏幕坐标；同步当帧正确重投影后它自然不可见。修正夹具的机位、使用实际投影坐标，不修改正确的投影行为。该轮真实重复刷新可见性/对象身份/悬停连续性均已为true，但整轮不算通过。
- 修正轮20261030-110042-sparse-landing-markers-final-74675a：逻辑与真实Forward+渲染各25项、0失败、退出0。46块新板（6×6平台+10块长支路）只显示2个普通提示，间隔12.875米/201.826px；反复刷新5次，原悬停对象、可见性、50px大小和颜色进度均连续。船位变动1厘米不重排；固定泊位避让与超出最近24板的当前返船ID保护通过。
- building-ocean / board-click：20261030-105742-landing-marker-compile-e91c70均退出0，验证实际平台登陆/返船命令仍可用。

原始日志、report.json与截图位于工程外D:/projects/sea-work/verification/各对应目录。真实截图分别为project/outputs/landing-markers-before.png与landing-markers-after.png，JSON观测为landing-markers.json。首次修正轮的after截图只取到海面与图标，属于独立出图的背景取证限制，不将它当作完整场景视觉通过依据。增加固定机位等待及捕获后渲染帧的最终轮20261030-110442-sparse-landing-markers-render-482766仍有一张before背景缺失，但after实景完整，已目视确认46块板仅2个提示、悬停图标位置/尺寸正常；不宣称所有取样帧的完整3D背景一致。对象身份、每次刷新可见性与悬停插值连续性由独立断言验证，并非从两张背景图推断。

已有NavigationMesh烘焙WARNING（agent_radius按cell_size取整）单列保留，未修改角色导航参数；成功轮没有非预期SCRIPT ERROR或ERROR。未执行全地图/全部缩放/全部设备穷举，不声称所有图标在所有镜头下都同时可见。

## 文档与收尾

主文档增加最新规则；building spec/ledger新增R17，R13说明实际登陆边和提示显示分离；UI-R38同步稳定展示要求，nav账本登记行为不变。最终真实渲染轮20261030-110442-sparse-landing-markers-render-482766：25项/0失败、退出0，expected_errors和unexpected_errors均为空；相机与实际视口相机位置一致，world_visible=true、instances=46。最终完整截图为该轮project/outputs/landing-markers-after.png。

收尾静态检查：check_architecture.py退出0（15独立服务、0问题）；git diff --check退出0；check_feature_contracts.py --sync及无参检查均退出0（35功能、460源资产、393运行期哈希、0问题）。仅修改建造派生提示、UI展示同步、对应测试/文档，不重算未知资产哈希。工作区其他采集、收获表现改动由各自任务拥有，未代其作验收结论。
