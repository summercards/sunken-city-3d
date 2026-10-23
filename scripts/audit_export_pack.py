#!/usr/bin/env python3
"""Inspect the real PCK index, including Godot 4.7's format 4, without loading payloads."""
import argparse
from collections import Counter
import json
from pathlib import Path
import struct


def audit(pack):
    size = pack.stat().st_size
    with pack.open('rb') as stream:
        def read(n):
            data = stream.read(n)
            if len(data) != n: raise ValueError('truncated PCK index')
            return data
        header = read(40)
        if header[:4] != b'GDPC': raise ValueError('invalid PCK magic')
        version = struct.unpack_from('<I', header, 4)[0]
        if version not in (3, 4): raise ValueError('unsupported PCK format ' + str(version))
        flags = struct.unpack_from('<I', header, 20)[0]
        if flags & 1: raise ValueError('encrypted directory not supported')
        directory = struct.unpack_from('<Q', header, 32)[0]
        if not 40 <= directory < size: raise ValueError('invalid directory offset')
        stream.seek(directory)
        count = struct.unpack('<I', read(4))[0]
        entries = []
        for _ in range(count):
            length = struct.unpack('<I', read(4))[0]
            if length > size - stream.tell(): raise ValueError('invalid path length')
            path = read(length).rstrip(b'\0').decode('utf-8')
            offset, length = struct.unpack('<QQ', read(16))
            read(20)  # MD5 and file flags
            entries.append({'path': path.removeprefix('res://'), 'bytes': length})
        if stream.tell() != size: raise ValueError('index end does not match file size')
    names = {x['path'] for x in entries}
    forbidden = [p for p in names if p.startswith(('tests/', 'tools/', 'outputs/', 'build/', 'docs/', 'art_source/')) or p.endswith(('.blend', '.blend1', '.md'))]
    required = ['assets/data/items.json', 'assets/data/crops.json', 'assets/data/orders.json',
                'assets/data/zones.json', 'assets/baked/geoms.bin', 'scenes/main.tscn.remap',
                'src/bootstrap/main.gdc', 'src/farming/farm.gdc', 'src/orders/orders.gdc']
    missing = [p for p in required if p not in names]
    return {'format': version, 'file_count': count, 'pack_bytes': size,
            'payload_bytes': sum(x['bytes'] for x in entries), 'index_end_verified': True,
            'directory_counts': dict(Counter(x['path'].split('/')[0] for x in entries)),
            'forbidden_entries': sorted(forbidden), 'missing_required': missing,
            'passed': not forbidden and not missing, 'entries': entries}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pack', type=Path)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.pack)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k:v for k,v in result.items() if k != 'entries'}, ensure_ascii=False))
    raise SystemExit(0 if result['passed'] else 1)
