---
name: sea-verification
description: 用 scripts/run_verification.py 在隔离用户数据下跑 sea 的 Godot 契约与渲染验证，并按规定记录真实渲染、预期故障、未执行项与退出码。用于改完代码要出证据、或要复现某个专项失败时。
---

# sea 运行验证

## 基本用法

```bash
python scripts/run_verification.py <check...> [--label 名字] [--timeout 180] [--visual] [--import-assets]
```

- 不带参数默认只跑 `core`；一次可以给多个 check 名。
- 可用的 check 名在脚本顶部 `TESTS` 字典里，例如 `modules`、`parity`、`farming`、`crops`、`surface`、`click`、`keyboard-control`、`sunken-city`、`sea-fauna`、`seabed-scene`。
- `--visual`：给真实渲染器（`visual-*` 开头的 check 自动需要）。headless 下截不了图，会挂住不退出，所以视觉检查必须带这个标志。
- `--import-assets`：新增美术在隔离工程里先导入再测。
- `--label`：给本次运行命名，产物与日志按它归档到工程外 `sea-work/`。
- 引擎优先读环境变量 `GODOT`；新开的 shell 可能读不到，此时用绝对路径 `F:\Godot\4.7.2-stable\` 下的控制台版 exe。

## 记录要求

一次验证要分别写清四件事，缺一项等于没跑：

1. **真实渲染**：哪些 check 真的出了图（截图路径），哪些只是逻辑断言；
2. **预期故障**：已知会红且已登记的问题，说明它属于哪个功能条款；
3. **未执行项**：因为环境（缺引擎、缺资源、需要人工摆位）没跑的，单独列出来；
4. **退出码**：原样贴上，不要用「通过」两个字掩盖非零退出。

专项通过之后再跑必要集成，**不要用历史结果代替当前实测**。

## 跑完必看

`run_verification.py` 会在隔离工程里跑，但 Godot 的编辑器上下文副作用会落到工作区：

- `water_surface.gd` 是 `@tool`，编辑器保存会把 `godot/scenes/main.tscn` 烘成 1.2 MB（ArrayMesh 写进 tscn）。跑完 `git status` 看一眼，`git checkout -- godot/scenes/main.tscn` 还原——**前提是它没有未提交改动**，有就先 `git diff` 手工处理。
- 导入器会给 `.glb.import` 补字段、给 `.tres` 加 uid，这些多是噪音，别提交。

## 隔离工程的老问题

Windows 上 `Path.symlink_to` 无权限时不抛异常，会留空目录/空文件，导致 `res://assets/...` 全线缺资源、测试假红（典型表现 `Cannot call method 'get_shader_parameter' on a null value` 跑几分钟不过）。现版本已改成 `mount_readonly()`：目录用 junction（`mklink /J`）并验内容，否则 `copytree` 兜底。如果又出现整片缺资源，先查这里。
