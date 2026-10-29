#!/usr/bin/env python3
"""材质参数契约检查：ShaderMaterial 的 shader_parameter 不能被静默清空。

起因（2026-10-29，一天内复发两次）：
    `godot/assets/materials/water.tres` 与 `solar_cabin/sunny_*.tres` 被编辑器
    保存后，全部 `shader_parameter/*` 行消失，只剩 `shader = ExtResource("1")`。
    Godot 重写 ShaderMaterial 时，参数行是从「当前已编译着色器的 uniform 列表」
    重新生成的；该列表一旦为空（着色器正在重编译、或材质早于着色器就绪被保存），
    它会**逐条丢弃全部参数且不报任何错**。
    `sunny_palette.gdshader` 的 `palette` 没有默认值，丢掉后 `texture()` 返回纯白，
    于是整栋太阳能木屋变成白模 —— 现象是「移动节点导致变白」，实际与位置无关。
    更糟的是 09:38 的提交把损坏状态一起提交了，所以「从 HEAD 恢复」也拿不到好的。

本脚本只做静态断言，不改文件：
    1. `shader_param_contract.json` 里登记的材质，`required` 参数必须存在且非 null，
       且参数行数不得少于基线；
    2. `godot/assets/materials/**` 下任何 ShaderMaterial 不得「零 shader_parameter」
       （这是被清空的指纹），白名单见文件末尾 ALLOW_EMPTY。

用法：
    python3 scripts/check_material_params.py
    python3 scripts/check_material_params.py --quiet
退出码：0 通过，1 契约不成立，2 清单读不到。
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAT = ROOT / 'godot' / 'assets' / 'materials'
CONTRACT = MAT / 'shader_param_contract.json'

# 允许「零参数」的材质：确实是只挂 shader、全部吃 uniform 默认值的。
ALLOW_EMPTY = set()

PARAM = re.compile(r'^shader_parameter/([A-Za-z0-9_]+)\s*=\s*(.*)$')


def read_params(path: Path):
    """返回 {参数名: 原始右值文本}；null 视作未设置。"""
    out = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        m = PARAM.match(line.strip())
        if not m:
            continue
        name, raw = m.group(1), m.group(2).strip()
        out[name] = None if raw == 'null' else raw
    return out


def is_shader_material(path: Path) -> bool:
    head = path.read_text(encoding='utf-8')[:400]
    return head.startswith('[gd_resource type="ShaderMaterial"')


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--quiet', action='store_true')
    args = ap.parse_args()

    if not CONTRACT.exists():
        print(f'读不到契约清单：{CONTRACT}', file=sys.stderr)
        return 2
    contract = json.loads(CONTRACT.read_text(encoding='utf-8'))['materials']

    problems = []
    checked = 0

    # ---- 1. 契约材质 ----
    for rel, spec in contract.items():
        path = ROOT / rel
        if not path.exists():
            problems.append(f'{rel}：文件不存在')
            continue
        checked += 1
        params = read_params(path)
        for name in spec['required']:
            if name not in params or params[name] is None:
                problems.append(f'{rel}：缺少必需参数 {name}（丢了就会白模或整体失色）')
        if len(params) < int(spec['min_params']):
            problems.append(
                f'{rel}：参数只剩 {len(params)} 个，基线是 {spec["min_params"]} 个 —— 被清空了')

    # ---- 2. 全量零参数指纹 ----
    for path in sorted(MAT.rglob('*.tres')):
        rel = path.relative_to(ROOT).as_posix()
        if rel in contract or rel in ALLOW_EMPTY:
            continue
        try:
            if not is_shader_material(path):
                continue
        except (OSError, UnicodeDecodeError):
            continue
        if not read_params(path):
            problems.append(f'{rel}：ShaderMaterial 一个 shader_parameter 都没有（被清空）')

    if problems:
        print(f'材质参数契约不成立（检查了 {checked} 份登记材质）：', file=sys.stderr)
        for p in problems:
            print('  ✗', p, file=sys.stderr)
        print('\n修复：python3 scripts/repair_material_params.py', file=sys.stderr)
        return 1

    if not args.quiet:
        print(f'[material-params] OK — {checked} 份登记材质、{len(list(MAT.rglob("*.tres")))} 份材质文件')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
