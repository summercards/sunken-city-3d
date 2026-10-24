# 太阳能花屋 v003 · 第一版色调和花叶风格修订

所属功能：SEA-ASSET；设计条款 R03–R07、R09。用户最新要求是在第一版上先改色彩和花朵，参考新提供的游戏截图。

## 制作范围

直接读取已保存的 v001 母版另存 v003。保留 30 项建筑组件与棕榈的几何、摆位、倒角以及原始平台尺度；重做叶簇、藤蔓、白花、粉花、黄花共 5 项。没有使用 v002 的精简几何，也没有重跑第一版全屋构建器。

墙面改用浅薄荷白/米白，木料偏暖橙，蓝色设施保留海洋色调。花朵使用较大的圆润五瓣轮廓、黄花心和粉白浅黄色；叶片更宽圆、减少细碎层次。材质降低高光，改用中性柔光。公共 64 色 PNG 不修改，通过 PaletteUV 平移到已有色格完成配色。

v003 为风格制作源，36 个组件、255 个实例。保存后真实依赖图实测 **704880 多边形 / 1383200 三角面**，不是 3000 面游戏优化版。先完成此次风格修订，低面数优化暂缓；历史 v002 仍为 1947 多边形 / 2999 三角面，扩大平台也在该版保留，不能将其指标套用到 v003。

## 文件和登记

- [v003 母版](../../art_source/scenes/solar_flower_house/v003/solar_flower_house.blend)
- [冻结组件计划](../../art_source/scenes/solar_flower_house/v003/component_plan.json)
- [建筑几何及摆位锁定](../../art_source/scenes/solar_flower_house/v003/scope_lock.json)
- [配色映射与范围](../../art_source/scenes/solar_flower_house/v003/style_mapping.json)
- [结构化验证记录](2026-10-24_solar_flower_house_style_verification.json)

36 组件和装配沿用原 AssetID 更新为 v003，前两版记录保留在 previous_sources；共享色板仍为 v001。场景分账本共 81 行，未新增重复资产 ID，派生源索引同步。历史源哈希逐条核对，未覆盖原版文件。

## 验证边界

源文件重开、36 个独立包重开、139486 个母版面的 PaletteUV 安全区和面积验证通过。31 项锁定组件逐顶点/拓扑指纹及实例变换检查通过；v001 母版和公共 PNG 哈希不变。真实渲染及工程契约检查的最终结果见结构化记录。

输出位于工程外 `../sea-work/solar_flower_house_v003/`，包含四张真实 Cycles 渲染、日志、源级 QA 和 Blender 自动备份。未做 Godot 导入、碰撞、导航、运行性能或商业授权验证；保持 pending，无预期故障注入。

工程契约同步及无参数检查均退出 1：任务外 `godot/assets/materials/water.tres` 哈希漂移，以及 `README.md` 链接 `docs/development/2026-10-24_web_directory_split.md` 当时不存在。未通过接受其他任务哈希漂移使检查变绿，SEA-ASSET 继续为 partial。
