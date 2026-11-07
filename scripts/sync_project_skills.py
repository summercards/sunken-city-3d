#!/usr/bin/env python3
"""把 .agents/skills 的项目技能镜像到 .workbuddy/skills。

两个工具读不同目录：Codex 读 `.agents/skills`，WorkBuddy 读 `.workbuddy/skills`。
`.agents/skills` 是唯一真源（也入库），改完技能跑一次本脚本同步，避免两份漂移。

用法：python scripts/sync_project_skills.py [--check]
  --check  只比对不写入，有差异时退出码 1
"""
import argparse
import filecmp
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / '.agents' / 'skills'
DST = ROOT / '.workbuddy' / 'skills'


def tree_diff(left: Path, right: Path):
    """返回 (缺失或不同的文件, 只在镜像侧多出的文件)。"""
    missing, extra = [], []
    left_files = {p.relative_to(left) for p in left.rglob('*') if p.is_file()}
    right_files = {p.relative_to(right) for p in right.rglob('*') if p.is_file()}
    for rel in sorted(left_files):
        target = right / rel
        if not target.is_file() or not filecmp.cmp(left / rel, target, shallow=False):
            missing.append(rel.as_posix())
    for rel in sorted(right_files - left_files):
        extra.append(rel.as_posix())
    return missing, extra


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true', help='只比对，不写入')
    args = parser.parse_args()

    if not SRC.is_dir():
        print(f'源目录不存在：{SRC}')
        return 2

    skills = sorted(p for p in SRC.iterdir() if p.is_dir())
    if args.check:
        problems = 0
        for skill in skills:
            mirror = DST / skill.name
            if not mirror.is_dir():
                print(f'MISSING  {skill.name}')
                problems += 1
                continue
            missing, extra = tree_diff(skill, mirror)
            if missing or extra:
                problems += 1
                print(f'DRIFT    {skill.name}: 缺/异 {len(missing)}，多 {len(extra)}')
                for rel in missing[:5]:
                    print(f'          - {rel}')
                for rel in extra[:5]:
                    print(f'          + {rel}')
        stale = sorted(p.name for p in DST.iterdir() if p.is_dir()) if DST.is_dir() else []
        for name in stale:
            if name not in {s.name for s in skills}:
                print(f'STALE    {name}（镜像里多出的技能目录）')
                problems += 1
        print(f'{len(skills)} 个技能，{problems} 处差异')
        return 1 if problems else 0

    DST.mkdir(parents=True, exist_ok=True)
    for skill in skills:
        target = DST / skill.name
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(skill, target)
        count = sum(1 for _ in target.rglob('*') if _.is_file())
        print(f'{skill.name}: {count} 个文件')
    for leftover in DST.iterdir():
        if leftover.is_dir() and leftover.name not in {s.name for s in skills}:
            shutil.rmtree(leftover)
            print(f'移除镜像侧多余目录：{leftover.name}')
    print(f'已同步 {len(skills)} 个技能 → {DST.relative_to(ROOT)}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
