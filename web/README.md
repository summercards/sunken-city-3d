# web · Three.js 原型

本目录是 sea 的网页版全集：**冻结的历史原型**，用作 Godot 侧的几何烘焙来源与视觉数值对照。当前玩法设计以 [GDD_V1.0.md](../GDD_V1.0.md) 和 `godot/` 为准，不在此新增玩法规则。

## 自洽边界

目录内引用闭合，不读写仓库其他位置：

| 路径 | 内容 |
|---|---|
| `index.html` | 入口；`importmap` 把 `three` 指到 `vendor/` |
| `*.js` | 22 个模块，`gameplay.js` 是主编排 |
| `ui.css` | 全部界面样式 |
| `vendor/` | `three.module.js`、`OrbitControls.js` |
| `refs/` | 原画参考图，运行时由参考图卡片的切换按钮读取 |
| `tests/` | 22 个浏览器/单元回归测试 |
| `tools/` | CDP 截图与交互冒烟脚本 |

## 运行

静态服务根必须是本目录，页面 URL 才是 `/index.html` —— Godot 侧的烘焙与抓图工具按这个约定取页面：

```bash
cd web && python3 -m http.server 8765
# 浏览器打开 http://127.0.0.1:8765/index.html
```

服务换成别的根目录会让 `godot/tools/export_from_web.cjs`、`capture_*.cjs` 全部 404。

## 测试

从**仓库根**执行，脚本里的 `outputs/...` 相对当前工作目录写盘：

```bash
node web/tests/water-regression.cjs
node web/tests/zone-travel.cjs
```

`economy-unit.cjs` 用 `import('../economy.js')` 相对自身定位模块，位置变更时不需要改。

## 与 Godot 的关系

单向：`godot/tools/export_from_web.cjs` 通过 CDP 打开本目录页面，把静态几何烘焙成 `godot/assets/baked/*.bin`。Godot 不引用本目录任何文件，本目录也不读取 Godot 产物。

八个 Godot 模块的注释写着「对齐网页版 xxx.js」，说明数值仍以原型为基准；改动这些数值时应同时评估两侧，避免只改一边。
