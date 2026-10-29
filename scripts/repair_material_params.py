#!/usr/bin/env python3
"""按基线把被清空的 shader_parameter 补回材质文件（文本级，不走 ResourceSaver）。

为什么不用 ResourceSaver：
    · 它会把每帧改的运行时参数（u_time / u_ripples / ocean_waves …）一起写进资源；
    · 它会给「材质里没有」的参数写一行 `= null`，等于往文件里塞垃圾；
    · 它会重排整个文件（format / uid / 行序都变），diff 看不出改了什么。
    而这次事故本身，正是 ResourceSaver 那条「按已编译 uniform 列表重建参数行」
    的路径干的。

行为：
    · 只补缺失的行，已有的非 null 值一律不动（--force 才覆盖）；
    · 保留原文件的换行风格（仓库是 CRLF 检出）与头部（format / uid）；
    · 参数按基线顺序追加到 `shader = ...` 之后，不插进别的段。

用法：
    python3 scripts/repair_material_params.py            # 补缺失
    python3 scripts/repair_material_params.py --dry-run  # 只看要补什么
    python3 scripts/repair_material_params.py --force    # 基线值覆盖现有值
退出码：0 已修复或无缺失，1 有文件读不到，2 清单读不到。
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAT = ROOT / 'godot' / 'assets' / 'materials'
CONTRACT = MAT / 'shader_param_contract.json'

PARAM = re.compile(r'^shader_parameter/([A-Za-z0-9_]+)\s*=\s*(.*)$')


def render_value(value, ext_id_of: dict) -> str:
    """基线里的值 → .tres 原始右值。资源写成 ExtResource("id")。"""
    if isinstance(value, dict):
        res = value.get('res', '')
        if res not in ext_id_of:
            raise KeyError(f'缺少 ext_resource：{res}')
        return f'ExtResource("{ext_id_of[res]}")'
    return str(value)


def repair_one(path: Path, spec: dict, force: bool, dry: bool):
    # newline='' 才能在读的时候保留原始 CRLF；否则会被统一成 \n，
    # 写回去就是整文件 diff（仓库是 CRLF 检出）。
    raw = path.open(encoding='utf-8', newline='').read()
    eol = '\r\n' if '\r\n' in raw else '\n'
    lines = raw.replace('\r\n', '\n').split('\n')

    # 现有参数 → 行号
    existing = {}
    for i, line in enumerate(lines):
        m = PARAM.match(line.strip())
        if m:
            existing[m.group(1)] = (i, line, m.group(2).strip())

    # path → ext id 反查，用于把资源参数写成 ExtResource("…")
    ext_id_of = {}
    for line in lines:
        m = re.match(r'^\[ext_resource.*path="([^"]+)".*id="([^"]+)"\]', line.strip())
        if m:
            ext_id_of.setdefault(m.group(1), m.group(2))

    added, replaced = [], []
    for name, value in spec['params'].items():
        want = render_value(value, ext_id_of)
        line = f'shader_parameter/{name} = {want}'
        if name in existing:
            idx, cur_line, cur_val = existing[name]
            if force and cur_val != want:
                lines[idx] = line
                replaced.append(name)
            continue
        added.append(line)

    if not added and not replaced:
        return [], []

    if not dry:
        if added:
            # 追加到最后一个 shader_parameter 行之后；没有则整段接在 shader 行之后。
            anchor = max((i for i, *_ in existing.values()), default=None)
            if anchor is None:
                anchor = next(
                    (i for i, l in enumerate(lines) if l.strip().startswith('shader = ')), None)
            if anchor is None:
                raise ValueError('找不到 shader = 行，拒绝盲插')
            lines[anchor + 1:anchor + 1] = added
        path.write_text(eol.join(lines), encoding='utf-8', newline='')

    return added, replaced


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--force', action='store_true')
    args = ap.parse_args()

    if not CONTRACT.exists():
        print(f'读不到契约清单：{CONTRACT}', file=sys.stderr)
        return 2
    contract = json.loads(CONTRACT.read_text(encoding='utf-8'))['materials']

    touched = 0
    for rel, spec in contract.items():
        path = ROOT / rel
        if not path.exists():
            print(f'  ! 缺失：{rel}', file=sys.stderr)
            return 1
        try:
            added, replaced = repair_one(path, spec, args.force, args.dry_run)
        except (KeyError, ValueError) as exc:
            print(f'  ! {rel}：{exc}', file=sys.stderr)
            return 1
        if added or replaced:
            touched += 1
            verb = '将补' if args.dry_run else '已补'
            print(f'{verb} {rel}：{len(added)} 条缺失'
                  + (f'，{len(replaced)} 条覆盖' if replaced else ''))
            for line in added:
                print('    +', line)

    if touched == 0:
        print('[material-params] 无需修复，全部参数在位')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
