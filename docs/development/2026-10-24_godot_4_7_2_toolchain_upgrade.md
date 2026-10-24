# Godot 工具链升级至 4.7.2-stable

2026-10-24，工具链变更，不涉及功能条款。

本地引擎由 4.6.3-stable 升级到 4.7.2-stable。`godot/project.godot` 自首个提交 aea20a0 起即声明 `config/features=PackedStringArray("4.7", "Forward Plus")`，此前安装的 4.6.3 与该声明错配，本次对齐。

## 安装位置

安装于 F 盘，未落入 C 盘（C 盘当时仅剩 2.3 GB）。

- 主程序：`F:\Godot\4.7.2-stable\Godot_v4.7.2-stable_win64.exe`
- 控制台版：`F:\Godot\4.7.2-stable\Godot_v4.7.2-stable_win64_console.exe`
- 安装包留存：`F:\Godot\_download\Godot_v4.7.2-stable_win64.exe.zip`

来源为官方 GitHub Release 4.7.2-stable 的 win64 资产，经加速通道取得；SHA512 `83decd58fdf67b9d657958a1ae6bf1929c20785315a81effe245874cdc57acb709bf868e00778a96984338c1b29dafdb453c6847747694621c6ecf5da2259993`，与官方 `SHA512-SUMS.txt` 逐字节一致。引擎自报 `4.7.2.stable.official.ed1daf0bf`。

选用标准版而非 .NET 版：工程无 C# 文件，92 个脚本均为 GDScript。

用户级环境变量 `GODOT` 已指向控制台版 exe，`scripts/run_verification.py` 优先读取该变量。

## 导入与运行证据

- `--headless --path godot --import` 退出 0，全部资产导入完成。
- headless 运行主场景 240 帧：0 error，shore atlas 与 shoreline 几何正常构建。
- 真实渲染器运行主场景 180 帧：0 error，Vulkan 1.4.325 / RTX 3060 / Forward+，水面与地形自定义 shader 编译通过。

## 行尾与运行哈希冲突

导入后 66 个 `.import` 文件被判为改动，实际仅时间戳差异，`git diff` 无内容。清理时触发了一个既有的仓库级问题：本机 `core.autocrlf=true` 且无 `.gitattributes`，任何一次 `git checkout` 都会把文本资源写成 CRLF，而 `assets/registry/runtime_resource_inventory.json` 里登记的 sha256 是按 LF 内容算的。

实测对照：`godot/assets/plants/zones/zone3_arc_farm/plant_32_7l/meta.json` 的库内 blob 哈希为 `ffd6a81c…`，与登记值一致；工作区 CRLF 版本的哈希为 `356e1abb…`，故被判漂移。本次把 85 个受影响文件还原为 LF，逐个哈希核对回登记值，并重新登记索引（`git diff --cached` 为空，未产生实质变更）。契约检查由 86 项回落到 1 项。

该冲突不是本次升级引入，但未根治：建议后续在仓库加 `.gitattributes`（`* text=auto eol=lf`）或将本机 `core.autocrlf` 置为 `false`，否则以后再 checkout 会重现。本次未改动这两处配置。

## 全量核心回归

`scripts/run_verification.py` 的隔离机制在本机不可用：脚本以符号链接组装隔离副本，而本机无法创建符号链接，`assets`、`.godot`、`icon.svg` 落成空目录与 0 字节文件（`assets` 内 0 个文件），任何涉及资源加载的用例都会拿到 `null`，例如 `boat_wake.gd:47` 的 `set_shader_parameter` 空引用、`sea_props.gd:177` 的 `Rect2 size is negative`，日志刷屏后撞 180 s 超时（exit 124）。这类失败与被测引擎版本无关。

改用真实拷贝（`cp -r godot` 到 `F:\wxgame\sea-work\verif-manual\project472`，312 个资产文件齐全、无链接）在同一份工程上跑全部 9 项核心用例，结果 9/9 通过：

| 用例 | 结果 |
|---|---|
| modules | PASS，28 checks / 0 failures |
| parity | PASS，422 checks / 0 failures |
| farming | PASS，31 checks / 0 failed |
| surface | PASS，routes=30 checks=375 failures=0 |
| click | PASS，30 checks / 0 failures |
| management | PASS，36 checks / 0 failed |
| camera | PASS，8 checks / failures=0 |
| ocean | PASS，141 checks / failures=0 |
| selftest | PASS，537 passed / 0 failed |

selftest 日志内唯一一条 `ERROR: Parse JSON failed. Error at line 0: Expected key` 属脚本 `EXPECTED_JSON_ERROR` 白名单内的故意用例，非缺陷。

`run_verification.py` 的软链接隔离建议改为真实拷贝（或在脚本内对复制失败做回退），否则任何在此类环境下的回归都会产出假阴性。

## 未执行项

- 未执行 visual-* 渲染基线对照，未实测 Web 导出产物。
- 旧版 4.6.3 仍保留在 `F:\安装包`，未删除。

## 副作用已回滚

真实渲染冒烟测试期间，`godot/src/rendering/color_grade_panel.gd` 把调色参数写回了 `godot/assets/materials/world_env.tres`（`tonemap_exposure` 1.10→1.19、`glow_hdr_threshold` 1.50→1.5），并非升级需要。已按索引字节还原，两处数值恢复原状，工作区仅余本次新增记录文件。

## 遗留

契约检查余 1 项既有问题：`godot\src\bootstrap\main.gd: missing resource outputs`，属账本登记范畴，与引擎版本无关，本次未处理。
