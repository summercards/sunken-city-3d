> 技术参考与历史记录。项目管理入口为 [主文档](../GDD_V1.0.md#feature-control)，本主题从 [独立功能文档](../docs/features/dive/spec.md) 和 [账本](../docs/features/dive/ledger.md) 进入。下文历史验收只对原记录时点成立。

# 海底材质规范与验收

2026-10-21，实测 Godot 4.7.2 stable，macOS / Apple M1 / Metal Forward+。
视觉基准为仓库中的网页版 underwater-art.js、north-trench.js 和 diving.js。

## 材质入口

- 所有海底模型、程序鱼、宝箱和潜水员通过 `src/diving/uw_materials.gd` 创建材质。
- manifest 的 Three.js 颜色已经是线性值，不再次做 sRGB 转换；代码中的美术色走 `from_color`，仅转换一次。
- 实体 shader 禁止写 ALPHA，使用不透明深度写入。透明变体只给真正透明的物体，测试深度但不写深度。
- 单双面遵循 manifest.double_side。Godot 自动处理 PBR 背面法线，自定义世界法线只在焦散/头灯计算中翻转一次。
- glTF 保留源逆时针索引，Godot 导入时转换为原生顺时针；导出阶段不重复翻转。
- 共用表面默认 roughness=0.58、metallic=0.06；特殊材质显式覆盖。缓存键包括透明度、粗糙度和金属度。
- 新建材质立即继承当前深度、焦散时间和头灯状态，避免区块切换出现亮度跳变。

## 光照和水雾

海面和海底使用不同 Environment。海底按网页版设置方向光、半球环境光、随身补光和三盏深沟点光；按照 Godot 的光能单位换算，随潜水员深度衰减。退出水下恢复原海面 Environment。

实体共用 PBR、焦散及自发光计算，ACES 参数对齐 Three.js exposure=1.1。`uw_fog.gdshader` 在实体渲染后、透明物体前读取颜色与深度，在显示颜色空间叠加网页版上下渐变水雾，再转换回 HDR 供最终色调映射。全屏合成的 ALPHA=1 是特例，不适用于模型实体。透明物体在自身材质中衰减，混合顺序与网页版仍存在近似。

头灯作为项目扩展保留；对照截图关闭头灯，另存开灯截图。

## 已执行验证

- 核心逻辑：422 checks，0 failures。
- 场景自检：522 passed，0 failed，包含导入模型绕序检查。
- GPU：两个实体变体在三个横向相机位置均正确遮挡；两个透明变体位于实体后方时被遮挡；缓存和晚创建状态通过。
- 双面受光：相同光照从两侧观察亮度一致。重复翻转 NORMAL 的故障版本实测为 [1,0]，修复后为 [1,1]。
- 入口、街区、珊瑚礁、海沟：冻结时间并隐藏动态实体后，两帧静态抽样变化均为 0；该检查不代表所有移动路径均已穷举。
- 上浮恢复原环境通过。GPU 验证日志没有脚本、shader 或资源泄漏错误。场景自检的坏 JSON 负例会输出一条预期解析诊断，验收脚本仅对白名单中的这条诊断放行。

## 复现

在 godot 目录执行 `bash verify_underwater.sh`。需要图形会话；可通过 GODOT 环境变量指定可执行文件。失败退出码保留，日志写入 outputs/uw-*.log。

首次或重新生成网页版基线：先在仓库根目录启动 HTTP 服务（默认端口 8765），安装 Playwright 后运行 `node tools/capture_underwater_ref.cjs uw-standard-web`（在 godot 目录）。可用 APP_URL 和 CHROME_BIN 覆盖地址与 Chrome 路径。

对照页：`outputs/underwater-comparison.html`。街区、珊瑚礁、海沟使用记录的相机变换；入口使用默认机位。Godot 焦散固定 3 秒，网页版动画未冻结。

## 视觉差异边界

场景模型和材质规则已经按网页版校准；不是像素级复刻。角色造型、HUD、鱼群动画、阴影滤波、环境半球光近似和透明混合仍存在差异。验收范围为当前 Forward+ 渲染器，不外推到 Compatibility 或移动设备。
