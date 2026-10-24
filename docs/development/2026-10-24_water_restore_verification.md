# 工具箱整体丢失后的恢复与收尾验证

日期：2026-10-24
范围：`godot/src/rendering/`、`godot/shaders/water.gdshader`、`godot/assets/materials/`、`godot/tools/`、`scripts/run_verification.py`、`docs/`

## 起因

水面调参那一整套（60 参数面板、收藏预设、光点组、着色器改写）做完之后，工作区被整体还原成 HEAD：`color_grade_panel.gd` 退回 417 行的单页滤镜版，`water.tres` 从 3746 字节缩到 1790，`water.gdshader` 里没有 `glints` 组。用户的原话是「刚才做的工具不小心搞没了，帮我重新搞回来」。

## 恢复清单

按「内容特征」而不是按时间找备份——还原前的版本在文件历史快照里能按字节数和关键字符串认出：

| 文件 | 辨认依据 | 做法 |
|---|---|---|
| `shaders/water.gdshader` | 26851 字节、含 `group_uniforms glints` | 取历史快照里最大且含该组的版本 |
| `src/rendering/color_grade_panel.gd` | 49927 字节、同时含 `_water_body` 与 `_preset_items` | 取历史快照，再手工补回内置预设相关代码 |
| `assets/materials/water.tres` | 68 项 `shader_parameter`、`body_shallow` 为 (0.5175, 0.9961, 0.9961) | 从临时备份 `sea-work/tmp/water.tres.bak` 还原后补 10 项 glint |
| `src/rendering/water_params.gd` | 60 项 + `BUILTIN_PRESETS` | 整份重写 |
| `src/ui/cozy_ui.gd` | `apply()` 沿祖先链查 `cozy_skip` | 重写该方法与 `apply_tree()` |
| `src/bootstrap/main.gd` | `--water` 启动参数 | 补回 |
| `src/rendering/water_surface.gd` | `wave_scale := 1.2` 写在导出默认值上 | 补回 |
| `OCEAN_RENDERING.md` / `ledger.md` | 调参面板、定版、收藏、光点四节 | 重写 |

面板里最容易漏的是收藏下拉的三项结构（`_preset_items` 与 `OptionButton` 的 item index 一一同步、分隔项要 `set_item_disabled`、`_apply_values(values, fill_from_factory)` 的第二个参数决定未列项是否从资源复归）。这部分只能靠探针逐条断言，肉眼看截图看不出来。

## 恢复后的验证

| 检查 | 结果 |
|---|---|
| `tools/check_water_params.gd` | PASS 60 项 + 20 项豁免 |
| 面板探针（18 项断言） | fails=0：控件数 60、下拉 3 项、分隔项不可选、出厂 `depth_half_distance` 12.25 / `wave_scale` 1.2 / `glint_density` 0.24、内置预设 `body_shallow` 0.128 / `depth_half_distance` 7.0 / `sun_lobe_gain` 60 / `wave_scale` 1.0 |
| `run_verification.py core` | modules / parity / farming / surface / click / management / camera / ocean / selftest 全部 PASS |
| Forward+ 真实渲染 | 无 SHADER ERROR，面板深色底未被 CozyUI 染色 |
| `gl_compatibility` 真实渲染 | 无 SHADER ERROR、不变黑（本机整体过曝是老现象，不能做颜色参考） |
| 预设套用 / 复原 | 复原后与开机快照差异为空 |

## 顺手修的两个工具问题

### 1. 隔离验证工程读不到资源（会全线假红）

`scripts/run_verification.py` 用 `Path.symlink_to()` 把 `assets` / `icon.svg` / `.godot/imported` 挂进隔离工程。**Windows 上没有 symlink 权限时它不抛异常**，而是留下一个空目录 / 空文件。结果所有 `res://assets/...` 都读不到，测试因为缺资源全线报错，看着像代码回归——实际表现是 `ocean` 测试挂在 `Cannot call method 'get_shader_parameter' on a null value`（`water.tres` 根本没加载），跑了 4 分钟也没跑完。

改成 `mount_readonly()`：目录优先用 junction（`mklink /J`，不需要管理员权限），挂完必须验一下里面有东西，否则退回 `copytree`；单文件直接复制。修完 `ocean` 从「4 分钟仍失败」变成 5 秒 PASS。

### 2. 两个 `.tres` 的「哈希漂移」其实是行尾幻影

`check_feature_contracts.py` 报 `ocean_sky.tres`（435 vs 423 字节）与 `world_env.tres`（912 vs 879）哈希漂移，但 `git diff` 是空的。本机 `core.autocrlf=true` 且仓库没有 `.gitattributes`，检出会写成 CRLF，而登记的哈希按 LF 算。

判定方法：读工作区字节，把 `\r\n` 换成 `\n`，与 `git show HEAD:<path>` 逐字节比——相同就是幻影，不是内容变更。是幻影就还原行尾，**不要重算哈希**，否则等于把 CRLF 固化进登记表。

同类幻影还会让 `git status` 一直显示 `M`（index 的 stat 缓存没刷新），`git update-index --refresh` 或 `git add` 一次即可消掉。

## 复现

```bash
export GODOT="F:/Godot/4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe"
python scripts/run_verification.py core --label water-restore
python scripts/check_feature_contracts.py   # 只剩 main.gd:1928 引用 res://outputs 这一条历史遗留

export SEA_SHOT_DIR=F:/wxgame/sea-work/manual-water-check/panel
"$GODOT" --path godot --resolution 1280x800 --fixed-fps 60 --script res://tools/capture_water_panel.gd
"$GODOT" --path godot --resolution 1280x800 --fixed-fps 60 --script res://tools/capture_water_compare.gd
"$GODOT" --path godot --rendering-method gl_compatibility --resolution 1280x800 --fixed-fps 60 \
  --script res://tools/capture_water_panel.gd
```

跑完务必看一眼 `git status godot/scenes/main.tscn`：`@tool` 的 `water_surface.gd` 在编辑器上下文里会把 257² 网格烘进场景，文件从 6 KB 涨到 1.2 MB。
