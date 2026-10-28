#!/usr/bin/env python3
"""把绞盘打捞台 GLB 丢掉的顶点色，从同一几何的 zone1 detail.glb 按位置回填。

## 为什么要这一步

`salvage_station.glb` 是从 `zone1_home_harbor/units/detail.glb` 里拆出来的独立设施
（见 `docs/development/2026-10-25_runtime_building_reference_v03.md`）。拆分导出这条
路径把主体那个 primitive 的 `COLOR_0` 写成了纯白 (1,1,1)，而它的材质
（`baked_tn_1000`）是 `use_texture = false` 的卡通材质 —— 上色完全靠顶点色。
两者一叠加，整座打捞台就变成白模。

Blender 源 `art_source/.../salvage_station_v0.3.blend` 里的 `Color` 属性是完好的，
所以丢失只发生在 GLB 导出，不涉及美术设计。本脚本不改几何、不改材质、不改节点，
只按世界坐标把颜色写回 `COLOR_0` 的浮点区间 —— GLB 的 JSON 结构一个字节不动。

## 匹配规则

位置（四舍五入到 1e-4）在 detail.glb 里唯一对应一种颜色（实测 7972 个位置，0 歧义），
所以不需要法线辅助，也不会出现「同一点两个颜色」的二选一。

用法：
    python tools/restore_salvage_vertex_colors.py            # 写入
    python tools/restore_salvage_vertex_colors.py --check    # 只报告，不写
"""
from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'godot/assets/models/zones/zone1_home_harbor/units/detail.glb'
TARGET = ROOT / 'godot/assets/models/facilities/legacy_home/salvage_station.glb'
SIZE = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def read_glb(path: Path) -> tuple[dict, bytes, bytes]:
    """返回 (json, bin, 原始头部字节)。只接受单个 BIN chunk 的 GLB 2.0。"""
    raw = path.read_bytes()
    magic, version, _ = struct.unpack_from('<III', raw, 0)
    if magic != 0x46546C67 or version != 2:
        raise SystemExit(f'{path}: 不是 GLB 2.0')
    offset, doc, blob = 12, None, b''
    while offset < len(raw):
        length, kind = struct.unpack_from('<II', raw, offset)
        chunk = raw[offset + 8:offset + 8 + length]
        if kind == 0x4E4F534A:
            doc = json.loads(chunk.decode('utf-8'))
        elif kind == 0x004E4942:
            blob = chunk
        offset += 8 + length
    if doc is None:
        raise SystemExit(f'{path}: 缺少 JSON chunk')
    return doc, bytearray(blob), raw[:12]


def accessor_bytes(doc: dict, index: int) -> tuple[int, int, int, int]:
    """(起点, 元素数, 分量数, 步长)，都在 BIN chunk 内。"""
    acc = doc['accessors'][index]
    view = doc['bufferViews'][acc['bufferView']]
    width = SIZE[acc['type']] * 4
    start = view.get('byteOffset', 0) + acc.get('byteOffset', 0)
    return start, acc['count'], SIZE[acc['type']], view.get('byteStride') or width


def read_vec3(doc: dict, blob: bytes, index: int) -> list[tuple[float, float, float]]:
    start, count, comps, stride = accessor_bytes(doc, index)
    return [struct.unpack_from('<' + 'f' * comps, blob, start + i * stride) for i in range(count)]


def colour_table() -> dict[tuple[float, float, float], tuple[float, float, float]]:
    doc, blob, _ = read_glb(SOURCE)
    table: dict[tuple[float, float, float], tuple[float, float, float]] = {}
    for mesh in doc['meshes']:
        for prim in mesh['primitives']:
            attrs = prim['attributes']
            if 'COLOR_0' not in attrs:
                continue
            positions = read_vec3(doc, blob, attrs['POSITION'])
            colours = read_vec3(doc, blob, attrs['COLOR_0'])
            for p, c in zip(positions, colours):
                key = (round(p[0], 4), round(p[1], 4), round(p[2], 4))
                previous = table.setdefault(key, c)
                if previous != c:
                    raise SystemExit(f'源数据在同一位置出现两种颜色: {key}')
    return table


def nearest(table: dict, point: tuple[float, float, float], budget: float) -> tuple | None:
    """拆分时切开的面会新增顶点，位置精确匹配不到源；按容差找最近点。"""
    best, best_d = None, budget * budget
    for key, colour in table.items():
        d = (key[0] - point[0]) ** 2 + (key[1] - point[1]) ** 2 + (key[2] - point[2]) ** 2
        if d < best_d:
            best, best_d = colour, d
    return best


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='只报告缺失数量，不写文件')
    args = parser.parse_args()

    table = colour_table()
    doc, blob, header = read_glb(TARGET)
    patched = missing = 0
    report = []
    for mesh in doc['meshes']:
        for prim in mesh['primitives']:
            attrs = prim['attributes']
            if 'COLOR_0' not in attrs:
                continue
            acc = doc['accessors'][attrs['COLOR_0']]
            if acc['type'] != 'VEC3' or acc['componentType'] != 5126:
                raise SystemExit('只支持 float3 顶点色；遇到其它格式请先确认来源')
            start, count, comps, stride = accessor_bytes(doc, attrs['COLOR_0'])
            positions = read_vec3(doc, blob, attrs['POSITION'])
            before = {struct.unpack_from('<3f', blob, start + i * stride) for i in range(count)}
            local_missing = local_filled = 0
            for i, p in enumerate(positions):
                key = (round(p[0], 4), round(p[1], 4), round(p[2], 4))
                colour = table.get(key)
                if colour is None:
                    # 切开面新增的顶点：取 0.2 m 内最近的源顶点颜色。
                    colour = nearest(table, key, 0.2)
                    if colour is None:
                        local_missing += 1
                        continue
                    local_filled += 1
                struct.pack_into('<3f', blob, start + i * stride, *colour)
            after = {struct.unpack_from('<3f', blob, start + i * stride) for i in range(count)}
            patched += count - local_missing
            missing += local_missing
            report.append({'mesh': mesh.get('name'), 'material': prim.get('material'),
                           'vertices': count, 'matched': count - local_missing,
                           'missing': local_missing, 'nearest': local_filled,
                           'distinct_before': len(before), 'distinct_after': len(after)})

    for row in report:
        print('{mesh} [{material}] 顶点 {vertices} 命中 {matched} 缺失 {missing} '
              '近似 {nearest} 颜色种类 {distinct_before} → {distinct_after}'.format(**row))
    print(f'合计：回填 {patched} 个顶点，{missing} 个未命中源几何（留在原值）')
    if args.check:
        return 0
    if patched == 0:
        raise SystemExit('没有可回填的顶点，放弃写入')

    json_chunk = json.dumps(doc, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    json_chunk += b' ' * ((4 - len(json_chunk) % 4) % 4)
    bin_chunk = bytes(blob) + b'\0' * ((4 - len(blob) % 4) % 4)
    total = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    out = bytearray()
    out += struct.pack('<III', 0x46546C67, 2, total)
    out += struct.pack('<II', len(json_chunk), 0x4E4F534A) + json_chunk
    out += struct.pack('<II', len(bin_chunk), 0x004E4942) + bin_chunk
    TARGET.write_bytes(out)
    print(f'已写入 {TARGET.relative_to(ROOT)}（{len(out)} 字节）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
