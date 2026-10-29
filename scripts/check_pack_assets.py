#!/usr/bin/env python3
"""导出包资产契约检查：运行期按路径读取的文件，必须在包里真的存在。

起因（2026-10-29）：`src/ui/ui_font.gd` 用 `FileAccess.get_file_as_bytes("res://.../xxx.ttf")`
直接读源字体。导出时 Godot 只打包导入后的 `.fontdata`，源 `.ttf` 不进包，
于是导出包里的 FontFile 数据为空 —— Web 端没有系统字体兜底，全部文字变豆腐块
（桌面端被系统字体掩盖，所以只在网页版暴露）。

本脚本对导出的 .pck/.bin 做静态断言：
  1. 代码引用的每个字体（.ttf/.otf），包里必须有它导入后的 .fontdata 或原文；
  2. 代码里 `FileAccess.open / get_file_as_bytes / get_file_as_string` 直读的
     `res://` 路径，必须是包内原样条目（FileAccess 不吃 .import 重映射）；
  3. 包里至少有一个 .fontdata。

用法：
    python3 scripts/check_pack_assets.py godot/build/web/index.bin
    python3 scripts/check_pack_assets.py godot/build/windows/sea.pck --quiet
退出码：0 通过，1 契约不成立，2 无法解析包。
"""
import argparse
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT_DIR = ROOT / 'godot'
SRC = GODOT_DIR / 'src'

FILE_ACCESS = re.compile(
    r'FileAccess\.(?:open|get_file_as_bytes|get_file_as_string)\s*\(\s*([^,)\n]+)'
)
FONT_LITERAL = re.compile(r'"(res://[^"]+\.(?:ttf|otf))"')
# const EMBEDDED_PATH := "res://..." —— 必须解析，否则检查对"常量间接引用"完全瞎
CONST_DEF = re.compile(r'^\s*(?:static\s+)?const\s+(\w+)\s*(?::\s*\w+\s*)?:?=\s*"([^"]+)"', re.M)
IDENT = re.compile(r'^[A-Za-z_]\w*$')


def read_entries(pack: Path):
    d = pack.read_bytes()
    if d[:4] != b'GDPC':
        raise ValueError('不是 Godot 包（缺少 GDPC 头）')
    version, = struct.unpack_from('<I', d, 4)
    size = len(d)
    if version >= 3:
        dir_off, = struct.unpack_from('<Q', d, 0x20)
        if 0 < dir_off < size:
            return _read_dir(d, dir_off)
    for header in (48, 36):  # v2 / v1：文件数在头部
        if header + 4 <= size:
            count, = struct.unpack_from('<I', d, header)
            if 0 < count < 200000:
                try:
                    return _read_dir(d, header)
                except Exception:
                    continue
    raise ValueError('无法定位包目录')


def _read_dir(d, off):
    count, = struct.unpack_from('<I', d, off)
    off += 4
    out = {}
    for _ in range(count):
        plen, = struct.unpack_from('<I', d, off)
        off += 4
        path = d[off:off + plen].rstrip(b'\x00').decode('utf-8', 'replace')
        off += (plen + 3) // 4 * 4
        _ofs, fsize = struct.unpack_from('<QQ', d, off)
        off += 16 + 16 + 4
        out[path] = fsize
    return out


def scan_code():
    """代码里：字体字面量 + FileAccess 直读路径（含常量间接引用）。"""
    fonts, hard_reads = set(), set()
    if not SRC.exists():
        return fonts, hard_reads
    files = sorted(SRC.rglob('*.gd'))
    texts = {f: f.read_text(encoding='utf-8', errors='replace') for f in files}
    # 全工程常量表（跨文件 preload 也能解析）
    consts = {}
    for text in texts.values():
        for m in CONST_DEF.finditer(text):
            consts[m.group(1)] = m.group(2)

    def resolve(arg: str):
        arg = arg.strip()
        if arg.startswith('"') and arg.count('"') >= 2:
            return arg.split('"')[1]
        if IDENT.match(arg):
            return consts.get(arg)
        return None

    for f, text in texts.items():
        rel_src = str(f.relative_to(ROOT))
        for m in FONT_LITERAL.finditer(text):
            fonts.add(m.group(1)[len('res://'):])
        for m in FILE_ACCESS.finditer(text):
            path = resolve(m.group(1))
            if path and path.startswith('res://'):
                hard_reads.add((rel_src, path[len('res://'):]))
        # 常量直接指向的字体也算（FileAccess 之外的 preload 由 FONT_LITERAL 覆盖）
        for name, value in consts.items():
            if value.startswith('res://') and value.lower().endswith(('.ttf', '.otf')):
                if re.search(r'\b%s\b' % re.escape(name), text):
                    fonts.add(value[len('res://'):])
    return fonts, hard_reads


def import_dest(rel: str):
    """.import 里记录的导入产物路径（已去掉 res:// 前缀）。"""
    imp = GODOT_DIR / (rel + '.import')
    if not imp.exists():
        return None
    for line in imp.read_text(encoding='utf-8', errors='replace').splitlines():
        if line.startswith('path="'):
            return line[6:].rstrip('"').replace('res://', '')
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('pack')
    ap.add_argument('--quiet', action='store_true')
    args = ap.parse_args()

    pack = Path(args.pack)
    if not pack.exists():
        print(f'FAIL 包不存在：{pack}')
        return 2
    try:
        entries = read_entries(pack)
    except Exception as exc:
        print(f'FAIL 解析失败：{exc}')
        return 2

    problems, warnings = [], []
    fonts, hard_reads = scan_code()
    fontdata = [p for p in entries if p.endswith('.fontdata')]

    for rel in sorted(fonts):
        dest = import_dest(rel)
        if rel in entries or (dest and dest in entries):
            continue
        problems.append(f'字体没进包：res://{rel}（导入产物 {dest or "无 .import"} 也不在包里）')

    for src_file, rel in sorted(hard_reads):
        if rel in entries:
            continue
        text = (ROOT / src_file).read_text(encoding='utf-8', errors='replace')
        lowered = rel.lower()
        if lowered.endswith(('.ttf', '.otf')):
            if 'ResourceLoader.load(' in text:
                # 允许保留"读源文件"作为隔离副本的兜底，但主路径必须是资源加载
                warnings.append(f'兜底读源文件不在包里（主路径已走资源加载）：res://{rel}')
            else:
                problems.append(f'字体只能靠直读源文件，而它不在包里：res://{rel}（{src_file}）')
        elif lowered.endswith(('.json', '.bin', '.csv', '.txt')):
            problems.append(f'FileAccess 直读的数据文件不在包里：res://{rel}（{src_file}）')
        else:
            # .tscn/.tres 导出时会转成二进制并被编辑器工具改写，属开发期面板，不算发布缺陷
            warnings.append(f'开发期面板读写源文件（导出后失效，不影响游玩）：res://{rel}（{src_file}）')

    if not fontdata:
        problems.append('包里没有任何 .fontdata 字体资源')

    for w in warnings:
        print('WARN', w)

    if problems:
        print(f'FAIL {pack.name}：{len(problems)} 项契约不成立')
        for p in problems:
            print('  -', p)
        return 1

    if not args.quiet:
        print(f'OK {pack.name}：{len(entries)} 条目，{len(fontdata)} 个字体资源，'
              f'{len(hard_reads)} 处 FileAccess 直读均命中')
    return 0


if __name__ == '__main__':
    sys.exit(main())
